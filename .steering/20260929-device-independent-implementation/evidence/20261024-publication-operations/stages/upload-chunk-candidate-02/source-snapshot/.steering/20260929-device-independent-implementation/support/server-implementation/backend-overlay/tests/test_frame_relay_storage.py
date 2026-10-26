"""Disposable bytes and real SQLite/files/thread barriers; no conversion claims."""
import asyncio
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from dataclasses import replace
from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
import sqlite3
from threading import Barrier, Event
from uuid import uuid4

from fastapi.testclient import TestClient
from pydantic import ValidationError
import pytest

from app.core.settings import load_settings
from app.db.connection import connect
from app.db.migrations import run_migrations
from app.db import frame_relay_migrations as migrations
from app.main import app
from app.repositories import frame_relay_storage as repository
from app.repositories import registrations
from app.repositories.frame_relay_storage import StorageError
from app.repositories.jobs import claim_next_job, recover_expired_jobs, insert_or_return_job, SUPPORTED_JOB_TYPES
from app.schemas.frame_relay_storage import StorageBindingRequest
from app.services import frame_relay_storage as service
from app.services import frame_relay_finalize as finalize
from app.services import frame_relay_files as files


SECRET = "a" * 64
DATA = b"abcdefgh12345678"
PREFIX = "/frame-relay/v1/uploads"


class Crash(BaseException):
    pass


def _database(settings):
    return closing(connect(settings.database_path, settings.sqlite_busy_timeout_ms))


def _setup(tmp_path, monkeypatch, data=DATA):
    tmp_path.mkdir(parents=True, exist_ok=True)
    monkeypatch.setenv("MEDIA_ROOT", str(tmp_path / "media"))
    monkeypatch.setenv("DATABASE_PATH", str(tmp_path / "db.sqlite3"))
    monkeypatch.setenv("API_TOKEN", "storage-test-bootstrap")
    settings = replace(load_settings(), upload_session_chunk_size_bytes=4,
                       upload_session_max_size_bytes=4 * 131_072)
    settings.media_root.mkdir()
    with _database(settings) as conn:
        run_migrations(conn)
        migrations.run_frame_relay_migrations(conn)
        destination = registrations.destination_identity(conn)
        receipt = registrations.register(conn, destination_id=destination, operation_id=str(uuid4()), secret=SECRET)
    request = {"destination_id":destination,"registration_id":receipt["registration_id"],
        "registration_generation":receipt["generation"],"operation_id":str(uuid4()),"capture_id":str(uuid4()),
        "content_generation":"1","sha256":hashlib.sha256(data).hexdigest(),"byte_count":str(len(data))}
    value = service.create(settings, request, SECRET)
    return settings,request,value


async def _body(data):
    yield data


def _receive(settings, request, value, data=DATA):
    for index,start in enumerate(range(0,len(data),value["chunk_size"])):
        chunk = data[start:start+value["chunk_size"]]
        asyncio.run(service.receive_chunk(settings,value["session_id"],request,SECRET,index,
            (start,start+len(chunk)-1,len(data)),hashlib.sha256(chunk).hexdigest(),_body(chunk)))


def _claim(settings, request, value):
    service.finalize(settings,value["session_id"],request,SECRET)
    with _database(settings) as conn:
        job = claim_next_job(conn,settings.job_lease_seconds,SUPPORTED_JOB_TYPES)
    assert job is not None and job["job_type"] == "fr_upload_finalize"
    return job


def _reclaim(settings, job):
    with _database(settings) as conn:
        with conn:
            conn.execute("UPDATE jobs SET lease_expires_at=? WHERE id=?",
                ((datetime.now(timezone.utc)-timedelta(seconds=1)).isoformat(),job["id"]))
        assert recover_expired_jobs(conn) == 1
        next_job = claim_next_job(conn,settings.job_lease_seconds,SUPPORTED_JOB_TYPES)
    assert next_job["fr_claim_generation"] == job["fr_claim_generation"]+1
    assert next_job["fr_claim_token"] != job["fr_claim_token"]
    return next_job


def _lookup(settings, request, value):
    return service.lookup(settings,value["session_id"],request,SECRET)


def _counts(settings):
    with _database(settings) as conn:
        return tuple(conn.execute("SELECT COUNT(*) FROM " + name).fetchone()[0]
            for name in ("fr_storage_evidence","assets")) + (conn.execute("SELECT COUNT(*) FROM jobs WHERE job_type='fr_conversion'").fetchone()[0],)


def _headers(secret=SECRET):
    return {"Authorization":"Bearer storage-test-bootstrap","X-FrameRelay-Registration-Secret":secret}


def test_first_finalization_independently_reads_final_destination_and_atomic_evidence(monkeypatch,tmp_path):
    settings,request,value = _setup(tmp_path,monkeypatch)
    _receive(settings,request,value)
    job = _claim(settings,request,value)
    calls=[]
    original=files.read_all
    def observe(root,path,**kwargs):
        result=original(root,path,**kwargs)
        calls.append((path,result["byte_count"],result["sha256"]))
        return result
    monkeypatch.setattr(files,"read_all",observe)
    assert finalize.process_finalize(settings=settings,job=job)
    assert (value["final_path"],len(DATA),request["sha256"]) in calls
    result=_lookup(settings,request,value)
    assert result["status"] == "completed" and result["evidence"]["method"] == "final_destination_read_back"
    assert result["evidence"]["committed"] and result["evidence"]["byte_count"] == str(len(DATA))
    assert _counts(settings) == (1,1,1)
    with _database(settings) as conn:
        assert conn.execute("SELECT status FROM jobs WHERE id=?",(job["id"],)).fetchone()[0] == "done"
        assert conn.execute("SELECT status FROM jobs WHERE job_type='fr_conversion'").fetchone()[0] == "queued"
        assert conn.execute("SELECT preview_status FROM assets").fetchone()[0] == "not_started"
        conversion=claim_next_job(conn,300,SUPPORTED_JOB_TYPES)
        assert conversion["job_type"] == "fr_conversion" and conversion["status"] == "running"
    assert _lookup(settings,request,value)["evidence"] == result["evidence"]


def test_existing_final_still_requires_full_read_and_does_not_use_assembly_hash(monkeypatch,tmp_path):
    settings,request,value=_setup(tmp_path,monkeypatch)
    _receive(settings,request,value)
    with files.exclusive_writer(settings.media_root,value["final_path"]) as output:output.write(DATA)
    before=files.current_fingerprint(settings.media_root,value["final_path"])
    job=_claim(settings,request,value)
    blocks=[]
    finalize.process_finalize(settings=settings,job=job,fault=lambda step:blocks.append(step))
    assert "read_block" in blocks and "assembly_block" not in blocks
    assert files.current_fingerprint(settings.media_root,value["final_path"]) == before
    assert _counts(settings) == (1,1,1)


def test_create_replay_is_bound_to_exact_context_and_never_serializes_secret(monkeypatch,tmp_path):
    settings,request,value=_setup(tmp_path,monkeypatch)
    assert service.create(settings,request,SECRET) == value
    for field,replacement in (("capture_id",str(uuid4())),("content_generation","2"),("sha256","f"*64),("byte_count","8")):
        with pytest.raises(StorageError,match="binding_mismatch"):
            service.create(settings,{**request,field:replacement},SECRET)
    with _database(settings) as conn:
        assert SECRET not in json.dumps([dict(row) for row in conn.execute("SELECT * FROM fr_upload_bindings")])
    _receive(settings,request,value)
    job=_claim(settings,request,value)
    assert SECRET not in job["payload_json"]


def test_wrong_destination_registration_generation_or_secret_cannot_receive_or_lookup(monkeypatch,tmp_path):
    settings,request,value=_setup(tmp_path,monkeypatch)
    for field,new_value in (("destination_id",str(uuid4())),("registration_id",str(uuid4())),("registration_generation","2")):
        incorrect={**request,field:new_value}
        with pytest.raises(registrations.RegistrationError):
            service.lookup(settings,value["session_id"],incorrect,SECRET)
        with pytest.raises(registrations.RegistrationError):
            asyncio.run(service.receive_chunk(settings,value["session_id"],incorrect,SECRET,0,
                (0,3,16),hashlib.sha256(DATA[:4]).hexdigest(),_body(DATA[:4])))
    with pytest.raises(registrations.RegistrationError):
        service.lookup(settings,value["session_id"],request,"b"*64)
    with pytest.raises(registrations.RegistrationError):
        asyncio.run(service.receive_chunk(settings,value["session_id"],request,"b"*64,0,
            (0,3,16),hashlib.sha256(DATA[:4]).hexdigest(),_body(DATA[:4])))
    assert _lookup(settings,request,value)["chunk_indexes"] == []
    assert not list(settings.media_root.glob("tmp/frame-relay/receiving/*.part"))
    assert _counts(settings) == (0,0,0)


def test_uint64_generation_is_exact_and_oversize_bytes_rejected_without_truncation(monkeypatch,tmp_path):
    settings,request,_value=_setup(tmp_path,monkeypatch)
    large={**request,"operation_id":str(uuid4()),"content_generation":str((1<<64)-1)}
    value=service.create(settings,large,SECRET)
    assert value["content_generation"] == str((1<<64)-1)
    with pytest.raises(StorageError,match="size_limit"):
        service.create(settings,{**request,"operation_id":str(uuid4()),"byte_count":str((1<<64)-1)},SECRET)
    for field in ("registration_generation","content_generation","byte_count"):
        for invalid in (True,1,"01","-1",str(1<<64)):
            with pytest.raises(ValidationError):StorageBindingRequest.model_validate({**request,field:invalid})


def test_capture_id_is_not_used_as_a_file_path(monkeypatch,tmp_path):
    settings,request,value=_setup(tmp_path,monkeypatch)
    assert request["capture_id"] not in value["final_path"]
    assert value["session_id"] in value["final_path"] and value["session_id"] != request["capture_id"]
    # The opaque identity can look like a path. It stays exact data, never a
    # path component, and even surrounding whitespace is not silently removed.
    opaque={**request,"operation_id":str(uuid4()),"capture_id":"  ../試験/capture?x=1#原本  "}
    accepted=service.create(settings,opaque,SECRET)
    assert accepted["capture_id"] == opaque["capture_id"]
    assert accepted["final_path"] == "originals/frame-relay/"+accepted["session_id"]+".mov"
    assert _lookup(settings,opaque,accepted)["binding"]["capture_id"] == opaque["capture_id"]
    with pytest.raises(StorageError,match="binding_mismatch"):
        service.create(settings,{**opaque,"capture_id":opaque["capture_id"].strip()},SECRET)
    for invalid in ("", " \t\n", 1, True, "\ud800"):
        with pytest.raises(ValidationError):StorageBindingRequest.model_validate({**request,"capture_id":invalid})


def test_chunk_wrong_digest_size_and_range_never_commit(monkeypatch,tmp_path):
    settings,request,value=_setup(tmp_path,monkeypatch)
    for data,content_range,digest in ((b"abc",(0,3,16),hashlib.sha256(b"abc").hexdigest()),(b"abcd",(0,3,16),"f"*64),(b"abcd",(1,4,16),hashlib.sha256(b"abcd").hexdigest())):
        with pytest.raises(StorageError):
            asyncio.run(service.receive_chunk(settings,value["session_id"],request,SECRET,0,content_range,digest,_body(data)))
    assert _lookup(settings,request,value)["chunk_indexes"] == []
    assert not list(settings.media_root.glob("tmp/frame-relay/receiving/*.part"))


def test_duplicate_chunk_same_payload_is_idempotent_and_other_payload_preserved(monkeypatch,tmp_path):
    settings,request,value=_setup(tmp_path,monkeypatch)
    _receive(settings,request,value)
    _receive(settings,request,value)
    path=settings.media_root/f"tmp/frame-relay/chunks/{value['session_id']}/0.part"
    before=path.read_bytes()
    with pytest.raises(StorageError,match="chunk_conflict"):
        asyncio.run(service.receive_chunk(settings,value["session_id"],request,SECRET,0,(0,3,16),hashlib.sha256(b"xxxx").hexdigest(),_body(b"xxxx")))
    assert path.read_bytes() == before


def test_missing_committed_chunk_does_not_acknowledge_a_successful_retry(monkeypatch,tmp_path):
    settings,request,value=_setup(tmp_path,monkeypatch)
    _receive(settings,request,value)
    path=settings.media_root/f"tmp/frame-relay/chunks/{value['session_id']}/0.part"
    path.unlink()
    with pytest.raises(StorageError,match="committed_chunk_missing"):
        asyncio.run(service.receive_chunk(settings,value["session_id"],request,SECRET,0,
            (0,3,16),hashlib.sha256(DATA[:4]).hexdigest(),_body(DATA[:4])))
    assert not path.exists()
    assert _counts(settings) == (0,0,0)


def test_receive_stream_interruption_closes_own_file_without_committing_chunk(monkeypatch,tmp_path):
    settings,request,value=_setup(tmp_path,monkeypatch)
    closed=[]
    async def interrupted():
        try:
            yield DATA[:2]
            raise asyncio.CancelledError()
        finally:closed.append(True)
    with pytest.raises(asyncio.CancelledError):
        asyncio.run(service.receive_chunk(settings,value["session_id"],request,SECRET,0,
            (0,3,16),hashlib.sha256(DATA[:4]).hexdigest(),interrupted()))
    assert closed == [True]
    assert _lookup(settings,request,value)["chunk_indexes"] == []
    assert not list(settings.media_root.glob("tmp/frame-relay/receiving/*.part"))
    _receive(settings,request,value)
    assert _lookup(settings,request,value)["chunk_indexes"] == [0,1,2,3]


def test_chunk_publish_interrupt_reopens_orphan_and_independently_reconciles(monkeypatch,tmp_path):
    settings,request,value=_setup(tmp_path,monkeypatch)
    def crash(step):
        if step == "after_chunk_publish":raise Crash()
    with pytest.raises(Crash):
        asyncio.run(service.receive_chunk(settings,value["session_id"],request,SECRET,0,(0,3,16),hashlib.sha256(DATA[:4]).hexdigest(),_body(DATA[:4]),fault=crash))
    assert _lookup(settings,request,value)["chunk_indexes"] == []
    _receive(settings,request,value)
    assert _lookup(settings,request,value)["chunk_indexes"] == [0,1,2,3]


def test_cancel_during_real_stream_preserves_receiver_until_terminal_then_refuses_callback(monkeypatch,tmp_path):
    settings,request,value=_setup(tmp_path,monkeypatch)
    reached,release=Barrier(2),Event()
    async def delayed():
        yield DATA[:2]
        reached.wait(timeout=10)
        assert release.wait(10)
        yield DATA[2:4]
    with ThreadPoolExecutor(max_workers=1) as pool:
        future=pool.submit(asyncio.run,service.receive_chunk(settings,value["session_id"],request,SECRET,0,(0,3,16),hashlib.sha256(DATA[:4]).hexdigest(),delayed()))
        try:
            reached.wait(timeout=10)
            assert list(settings.media_root.glob("tmp/frame-relay/receiving/*.part"))
            assert service.cancel(settings,value["session_id"],request,SECRET)["status"] == "cancelled"
            assert list(settings.media_root.glob("tmp/frame-relay/receiving/*.part"))
        finally:release.set()
        with pytest.raises(StorageError,match="not_receiving"):future.result(timeout=10)
    assert _lookup(settings,request,value)["chunk_indexes"] == []
    assert not list(settings.media_root.glob("tmp/frame-relay/receiving/*.part"))


def test_missing_chunks_cannot_start_finalize(monkeypatch,tmp_path):
    settings,request,value=_setup(tmp_path,monkeypatch)
    with pytest.raises(StorageError,match="chunks_missing"):service.finalize(settings,value["session_id"],request,SECRET)
    assert _counts(settings) == (0,0,0)


def test_final_mismatch_short_file_and_symlink_never_replace_existing_bytes(monkeypatch,tmp_path):
    for name,data in (("different",b"x"*len(DATA)),("short",DATA[:2]),("symlink",DATA)):
        settings,request,value=_setup(tmp_path/name,monkeypatch)
        _receive(settings,request,value)
        target=settings.media_root/value["final_path"];target.parent.mkdir(parents=True)
        if name == "symlink":
            elsewhere=settings.media_root/"held.mov";elsewhere.write_bytes(data);target.symlink_to(elsewhere)
        else:target.write_bytes(data)
        before=target.read_bytes()
        finalize.process_finalize(settings=settings,job=_claim(settings,request,value))
        assert _counts(settings) == (0,0,0)
        assert target.read_bytes() == before
        assert _lookup(settings,request,value)["status"] == "failed"


def test_missing_or_changed_chunk_never_publishes_final(monkeypatch,tmp_path):
    for mode in ("missing","short","digest","symlink"):
        settings,request,value=_setup(tmp_path/mode,monkeypatch);_receive(settings,request,value)
        path=settings.media_root/f"tmp/frame-relay/chunks/{value['session_id']}/0.part"
        if mode == "missing":path.unlink()
        elif mode == "short":path.write_bytes(b"a")
        elif mode == "digest":path.write_bytes(b"zzzz")
        else:
            other=settings.media_root/"other";other.write_bytes(DATA[:4]);path.unlink();path.symlink_to(other)
        finalize.process_finalize(settings=settings,job=_claim(settings,request,value))
        assert not (settings.media_root/value["final_path"]).exists()
        assert _counts(settings) == (0,0,0)


def test_crash_boundaries_reopen_reclaim_and_commit_exactly_one_evidence_job(monkeypatch,tmp_path):
    for step in ("before_publish","after_publish","read_block","after_read","after_evidence_insert","after_job_insert","before_commit"):
        settings,request,value=_setup(tmp_path/step,monkeypatch);_receive(settings,request,value);job=_claim(settings,request,value)
        def crash(observed):
            if observed == step:raise Crash()
        with pytest.raises(Crash):finalize.process_finalize(settings=settings,job=job,fault=crash)
        assert _counts(settings) == (0,0,0)
        new_job=_reclaim(settings,job)
        finalize.process_finalize(settings=settings,job=new_job)
        assert _counts(settings) == (1,1,1)
        assert _lookup(settings,request,value)["evidence"]["committed"]


def test_commit_response_loss_is_recovered_by_exact_query_without_second_job(monkeypatch,tmp_path):
    settings,request,value=_setup(tmp_path,monkeypatch);_receive(settings,request,value);job=_claim(settings,request,value)
    def crash(step):
        if step == "after_commit":raise Crash()
    with pytest.raises(Crash):finalize.process_finalize(settings=settings,job=job,fault=crash)
    first=_lookup(settings,request,value)
    assert first["status"] == "completed"
    assert service.finalize(settings,value["session_id"],request,SECRET) == first
    assert _counts(settings) == (1,1,1)
    finalize.process_finalize(settings=settings,job=job)
    assert _lookup(settings,request,value) == first


def test_actual_evidence_or_job_insert_failure_rolls_back_all_database_results(monkeypatch,tmp_path):
    for table in ("fr_storage_evidence","jobs"):
        settings,request,value=_setup(tmp_path/table,monkeypatch);_receive(settings,request,value);job=_claim(settings,request,value)
        with _database(settings) as conn:
            predicate=" WHEN NEW.job_type='fr_conversion'" if table == "jobs" else ""
            conn.execute("CREATE TRIGGER fr_test_reject BEFORE INSERT ON "+table+predicate+" BEGIN SELECT RAISE(ABORT,'injected'); END")
            conn.commit()
        finalize.process_finalize(settings=settings,job=job)
        assert _counts(settings) == (0,0,0)
        assert (settings.media_root/value["final_path"]).read_bytes() == DATA
        with _database(settings) as conn:conn.execute("DROP TRIGGER fr_test_reject");conn.commit()
        next_job=_claim(settings,request,value)
        finalize.process_finalize(settings=settings,job=next_job)
        assert _counts(settings) == (1,1,1)


def test_final_file_replacement_after_read_or_during_read_cannot_commit(monkeypatch,tmp_path):
    for step in ("read_block","after_read"):
        settings,request,value=_setup(tmp_path/step,monkeypatch);_receive(settings,request,value);job=_claim(settings,request,value)
        changed=False
        def change(observed):
            nonlocal changed
            if observed == step and not changed:
                changed=True
                target=settings.media_root/value["final_path"]
                replacement=target.with_suffix(".replacement");replacement.write_bytes(DATA);replacement.replace(target)
        finalize.process_finalize(settings=settings,job=job,fault=change)
        assert changed and _counts(settings) == (0,0,0)


def test_final_file_truncation_during_read_cannot_commit(monkeypatch,tmp_path):
    settings,request,value=_setup(tmp_path,monkeypatch);_receive(settings,request,value);job=_claim(settings,request,value)
    def change(step):
        if step == "read_block":(settings.media_root/value["final_path"]).write_bytes(DATA[:1])
    finalize.process_finalize(settings=settings,job=job,fault=change)
    assert _counts(settings) == (0,0,0)


def test_independent_hash_releases_writer_and_old_read_claim_cannot_commit(monkeypatch,tmp_path):
    settings,request,value=_setup(tmp_path,monkeypatch);_receive(settings,request,value);old=_claim(settings,request,value)
    reached,release=Barrier(2),Event()
    def pause(step):
        if step == "read_block":
            reached.wait(timeout=10)
            assert release.wait(10)
    with ThreadPoolExecutor(max_workers=1) as pool:
        future=pool.submit(finalize.process_finalize,settings=settings,job=old,fault=pause)
        try:
            reached.wait(timeout=10)
            with closing(connect(settings.database_path,100)) as conn:
                # This real independent writer must commit while final read is held.
                registrations.register(conn,destination_id=request["destination_id"],operation_id=str(uuid4()),secret=SECRET)
            new=_reclaim(settings,old)
            finalize.process_finalize(settings=settings,job=new)
        finally:release.set()
        assert future.result(timeout=10)
    assert _counts(settings) == (1,1,1)
    with _database(settings) as conn:
        assert conn.execute("SELECT claim_token FROM fr_storage_evidence").fetchone()[0] == new["fr_claim_token"]


def test_expired_attempt_cannot_publish_fail_renew_or_cleanup_new_attempt(monkeypatch,tmp_path):
    settings,request,value=_setup(tmp_path,monkeypatch);_receive(settings,request,value);old=_claim(settings,request,value)
    reached,release=Barrier(2),Event()
    def pause(step):
        if step == "before_publish":reached.wait(timeout=10);assert release.wait(10)
    with ThreadPoolExecutor(max_workers=1) as pool:
        future=pool.submit(finalize.process_finalize,settings=settings,job=old,fault=pause)
        try:
            reached.wait(timeout=10)
            old_path=settings.media_root/finalize.assembly_name(value,old)
            assert old_path.exists()
            new=_reclaim(settings,old)
            with pytest.raises(StorageError,match="stale_claim"):finalize.cleanup_attempt(settings,old)
            with pytest.raises(StorageError,match="stale_claim"):finalize.mark_failed(settings,old,"old")
            with _database(settings) as conn:
                conn.execute("BEGIN IMMEDIATE")
                with pytest.raises(StorageError,match="stale_claim"):repository.renew_claim(conn,old,300)
                conn.rollback()
            finalize.process_finalize(settings=settings,job=new)
        finally:release.set()
        assert future.result(timeout=10)
    assert old_path.exists() and _counts(settings) == (1,1,1)
    assert (settings.media_root/value["final_path"]).read_bytes() == DATA


def test_unproven_completed_or_legacy_verified_asset_never_becomes_evidence(monkeypatch,tmp_path):
    settings,request,value=_setup(tmp_path,monkeypatch)
    with _database(settings) as conn:
        conn.execute("UPDATE fr_upload_states SET status='completed' WHERE session_id=?",(value["session_id"],));conn.commit()
    with pytest.raises(StorageError,match="evidence_missing"):_lookup(settings,request,value)
    with pytest.raises(StorageError,match="evidence_missing"):service.finalize(settings,value["session_id"],request,SECRET)
    with _database(settings) as conn:
        conn.execute("UPDATE fr_upload_states SET status='receiving' WHERE session_id=?",(value["session_id"],))
        conn.execute("INSERT INTO assets(type,filename,original_path,verification_status) VALUES('video','old',?,'file_verified')",(value["final_path"],));conn.commit()
    _receive(settings,request,value)
    finalize.process_finalize(settings=settings,job=_claim(settings,request,value))
    assert _counts(settings) == (0,1,0)


def test_dedup_key_with_changed_fr_payload_is_rejected(monkeypatch,tmp_path):
    settings,request,value=_setup(tmp_path,monkeypatch);_receive(settings,request,value);job=_claim(settings,request,value)
    with _database(settings) as conn:
        with pytest.raises(ValueError):
            insert_or_return_job(conn,job_type=job["job_type"],asset_id=None,payload_json='{}',dedup_key=job["dedup_key"])
    assert _counts(settings) == (0,0,0)


def test_api_bound_upload_query_and_finalization_use_exact_authentication(monkeypatch,tmp_path):
    settings,request,value=_setup(tmp_path,monkeypatch)
    # HTTP settings have the production chunk size; this accepted binding keeps
    # the explicit test chunk size already committed in the same DB.
    with TestClient(app) as client:
        created=client.post(PREFIX,json=request,headers=_headers())
        assert created.status_code == 200 and created.json()["binding"]["session_id"] == value["session_id"]
        url=PREFIX+"/"+value["session_id"]
        assert client.get(url,params=request,headers=_headers("b"*64)).status_code == 403
        assert client.get(url,params=request).status_code == 401
        for index,start in enumerate(range(0,len(DATA),4)):
            chunk=DATA[start:start+4]
            result=client.put(url+f"/chunks/{index}",params=request,content=chunk,
                headers={**_headers(),"Content-Range":f"bytes {start}-{start+3}/{len(DATA)}","X-Chunk-SHA256":hashlib.sha256(chunk).hexdigest()})
            assert result.status_code == 200
        assert client.post(url+"/finalize",params=request,headers=_headers()).status_code == 200
        with _database(settings) as conn:job=claim_next_job(conn,300,SUPPORTED_JOB_TYPES)
        finalize.process_finalize(settings=settings,job=job)
        result=client.get(url,params=request,headers=_headers())
        assert result.status_code == 200 and result.json()["evidence"]["committed"]
        assert SECRET not in result.text


def test_legacy_session_get_put_finalize_cancel_cannot_touch_fr_session(monkeypatch,tmp_path):
    settings,request,value=_setup(tmp_path,monkeypatch)
    with TestClient(app) as client:
        url="/upload-sessions/"+value["session_id"]
        calls=[client.get(url,headers=_headers()),client.delete(url,headers=_headers()),client.post(url+"/finalize",headers=_headers()),
            client.put(url+"/chunks/0",content=DATA[:4],headers={**_headers(),"Content-Range":"bytes 0-3/16","X-Chunk-SHA256":hashlib.sha256(DATA[:4]).hexdigest()})]
        assert all(result.status_code == 409 for result in calls)
    assert _lookup(settings,request,value)["status"] == "receiving"


def test_legacy_processors_early_returns_and_publication_reject_managed_asset(monkeypatch,tmp_path):
    settings,request,value=_setup(tmp_path,monkeypatch);_receive(settings,request,value);job=_claim(settings,request,value)
    finalize.process_finalize(settings=settings,job=job)
    with _database(settings) as conn:asset_id=conn.execute("SELECT id FROM assets").fetchone()[0]
    from app.services.preview import process_preview_job
    from app.services.formal_preview_processing import process_formal_preview_job
    from app.services.rendition_processing import process_rendition_job
    from app.services.rendition_creation import create_rendition
    from app.services.processed_result_backfill import backfill_processed_result_for_asset
    from app.services.processed_result_finalizer import finalize_ready_processed_result
    from app.services.formal_preview_finalizer import resolve_verified_original,finalize_formal_preview_output
    from app.services.rendition_finalizer import finalize_rendition_output
    from app.repositories.processed_results import insert_ready_processed_result,insert_superseded_processed_result,set_active_processed_result
    from app.repositories.jobs import mark_job_done,mark_job_failed,fail_job_and_asset_preview
    with _database(settings) as conn:
        fake,_=insert_or_return_job(conn,job_type="preview",asset_id=asset_id,payload_json="{}",dedup_key="legacy-fr-bypass")
        conn.commit()
    for processor in (process_preview_job,process_formal_preview_job,process_rendition_job):
        with pytest.raises(StorageError,match="conversion_not_implemented"):processor(settings=settings,job=fake)
    with pytest.raises(StorageError):create_rendition(settings=settings,asset_id=asset_id,client_request_id=str(uuid4()),preset_id=None)
    with pytest.raises(StorageError):backfill_processed_result_for_asset(settings=settings,asset_id=asset_id)
    with pytest.raises(StorageError):finalize_ready_processed_result(settings=settings,job_id=fake["id"],asset_id=asset_id,preview_relative_path="previews/fake",mime_type="video/mp4",size_bytes=1)
    candidate=settings.media_root/"retained-candidate.mov";candidate.write_bytes(DATA)
    with pytest.raises(StorageError):finalize_formal_preview_output(settings=settings,job_id=fake["id"],attempt_id="unrelated",candidate_path=candidate,candidate_identity=None)
    with pytest.raises(StorageError):finalize_rendition_output(settings=settings,job_id=fake["id"],rendition_id="unrelated",candidate_path=candidate,evidence=None)
    assert candidate.read_bytes() == DATA
    with _database(settings) as conn:
        with pytest.raises(StorageError):resolve_verified_original(settings=settings,conn=conn,asset_id=asset_id)
        with pytest.raises(StorageError):insert_ready_processed_result(conn,asset_id=asset_id,derived_file_id=1,mime_type="video/mp4",size_bytes=1,sha256="a"*64)
        with pytest.raises(StorageError):insert_superseded_processed_result(conn,asset_id=asset_id,derived_file_id=1,mime_type="video/mp4",size_bytes=1,sha256="a"*64)
        with pytest.raises(StorageError):set_active_processed_result(conn,asset_id=asset_id,result_id="a"*32)
        with pytest.raises(StorageError):mark_job_done(conn,fake["id"])
        with pytest.raises(StorageError):mark_job_failed(conn,fake["id"],"forged")
        with pytest.raises(StorageError):fail_job_and_asset_preview(conn,job_id=fake["id"],asset_id=asset_id,error_message="forged")
        assert conn.execute("SELECT status FROM jobs WHERE id=?",(fake["id"],)).fetchone()[0] == "queued"
        assert conn.execute("SELECT preview_status FROM assets WHERE id=?",(asset_id,)).fetchone()[0] == "not_started"
        assert conn.execute("SELECT COUNT(*) FROM processed_results").fetchone()[0] == 0


def test_legacy_upload_worker_rejects_bound_session_before_failure_or_cleanup(monkeypatch,tmp_path):
    settings,request,value=_setup(tmp_path,monkeypatch);_receive(settings,request,value)
    from app.services.upload_finalize import process_upload_finalize_job
    with _database(settings) as conn:
        legacy,_=insert_or_return_job(conn,job_type="upload_finalize",asset_id=None,
            payload_json=json.dumps({"session_id":value["session_id"]}),dedup_key="legacy-session-bypass")
        conn.commit()
    with pytest.raises(StorageError,match="requires_bound_api"):
        process_upload_finalize_job(settings=settings,job=legacy)
    assert _lookup(settings,request,value)["status"] == "receiving"
    assert len(list(settings.media_root.glob("tmp/frame-relay/chunks/*/*.part"))) == 4
    with _database(settings) as conn:
        assert conn.execute("SELECT status FROM jobs WHERE id=?",(legacy["id"],)).fetchone()[0] == "queued"
    assert _counts(settings) == (0,0,0)


def test_broken_schema_and_missing_binding_never_fall_back_to_legacy(monkeypatch,tmp_path):
    settings,request,value=_setup(tmp_path,monkeypatch)
    from app.services.upload_sessions import get_upload_session
    with _database(settings) as conn:
        conn.execute("UPDATE fr_schema_migrations SET sha256='corrupt' WHERE version='002_storage'");conn.commit()
    with pytest.raises(migrations.FrameRelaySchemaError):get_upload_session(settings=settings,session_id=value["session_id"])
    with pytest.raises(migrations.FrameRelaySchemaError):_lookup(settings,request,value)


def test_missing_persistent_binding_refuses_legacy_session_and_asset_paths(monkeypatch,tmp_path):
    settings,request,value=_setup(tmp_path,monkeypatch)
    from app.services.upload_sessions import get_upload_session
    with _database(settings) as conn:
        conn.execute("PRAGMA foreign_keys=OFF")
        conn.execute("DROP TRIGGER fr_binding_no_delete")
        conn.execute("DELETE FROM fr_upload_bindings WHERE session_id=?",(value["session_id"],))
        conn.execute("INSERT INTO assets(type,filename,original_path) VALUES('video','retained',?)",(value["final_path"],))
        conn.commit()
    with pytest.raises(StorageError,match="binding_missing"):get_upload_session(settings=settings,session_id=value["session_id"])
    with pytest.raises(StorageError,match="binding_missing"):_lookup(settings,request,value)
    with _database(settings) as conn:
        asset_id=conn.execute("SELECT id FROM assets").fetchone()[0]
        with pytest.raises(StorageError,match="binding_missing"):repository.deny_legacy_asset(conn,asset_id)


def test_missing_conversion_job_does_not_return_completed_evidence(monkeypatch,tmp_path):
    settings,request,value=_setup(tmp_path,monkeypatch);_receive(settings,request,value)
    finalize.process_finalize(settings=settings,job=_claim(settings,request,value))
    with _database(settings) as conn:
        conn.execute("DELETE FROM jobs WHERE job_type='fr_conversion'");conn.commit()
    with pytest.raises(StorageError,match="evidence_inconsistent"):_lookup(settings,request,value)


def test_changed_finalization_job_or_claim_does_not_return_completed_evidence(monkeypatch,tmp_path):
    settings,request,value=_setup(tmp_path,monkeypatch);_receive(settings,request,value)
    job=_claim(settings,request,value)
    finalize.process_finalize(settings=settings,job=job)
    with _database(settings) as conn:
        conn.execute("UPDATE jobs SET job_type='upload_finalize' WHERE id=?",(job["id"],));conn.commit()
    with pytest.raises(StorageError,match="evidence_inconsistent"):_lookup(settings,request,value)
    with _database(settings) as conn:
        conn.execute("UPDATE jobs SET job_type='fr_upload_finalize' WHERE id=?",(job["id"],))
        conn.execute("UPDATE fr_job_claims SET token=? WHERE job_id=?",(str(uuid4()),job["id"]))
        conn.commit()
    with pytest.raises(StorageError,match="evidence_inconsistent"):_lookup(settings,request,value)
    assert _counts(settings) == (1,1,1)


def test_same_binding_job_with_forged_claim_or_payload_cannot_write_failure(monkeypatch,tmp_path):
    settings,request,value=_setup(tmp_path,monkeypatch);_receive(settings,request,value);job=_claim(settings,request,value)
    for field,wrong in (("fr_claim_generation",job["fr_claim_generation"]+1),("fr_claim_token",str(uuid4())),("payload_json","{}")):
        finalize.process_finalize(settings=settings,job={**job,field:wrong})
        assert _lookup(settings,request,value)["status"] == "finalizing"
        assert _counts(settings) == (0,0,0)
    finalize.process_finalize(settings=settings,job=job)
    assert _counts(settings) == (1,1,1)


def test_current_claim_renewal_and_cleanup_preserve_chunks_and_final(monkeypatch,tmp_path):
    settings,request,value=_setup(tmp_path,monkeypatch);_receive(settings,request,value);job=_claim(settings,request,value)
    with files.exclusive_writer(settings.media_root,finalize.assembly_name(value,job)) as output:output.write(b"partial")
    with _database(settings) as conn:
        conn.execute("BEGIN IMMEDIATE");repository.renew_claim(conn,job,300);conn.commit()
    finalize.cleanup_attempt(settings,job)
    assert not (settings.media_root/finalize.assembly_name(value,job)).exists()
    assert len(list(settings.media_root.glob("tmp/frame-relay/chunks/*/*.part"))) == 4
    finalize.process_finalize(settings=settings,job=job)
    with pytest.raises(StorageError,match="stale_claim"):finalize.cleanup_attempt(settings,job)
    assert (settings.media_root/value["final_path"]).read_bytes() == DATA


def test_claim_allocates_unique_token_and_generation_in_same_transaction(monkeypatch,tmp_path):
    settings,request,value=_setup(tmp_path,monkeypatch);_receive(settings,request,value);old=_claim(settings,request,value)
    new=_reclaim(settings,old)
    with _database(settings) as conn:
        claim=dict(conn.execute("SELECT * FROM fr_job_claims").fetchone())
        row=dict(conn.execute("SELECT * FROM jobs WHERE id=?",(old["id"],)).fetchone())
    assert claim["token"] == new["fr_claim_token"] and claim["generation"] == 2 and row["status"] == "running"


def test_invalid_job_binding_rolls_back_running_status_and_claim_allocation(monkeypatch,tmp_path):
    settings,request,value=_setup(tmp_path,monkeypatch);_receive(settings,request,value)
    service.finalize(settings,value["session_id"],request,SECRET)
    with _database(settings) as conn:
        conn.execute("UPDATE jobs SET payload_json='{}' WHERE job_type='fr_upload_finalize'");conn.commit()
        with pytest.raises(StorageError,match="payload_invalid"):
            claim_next_job(conn,300,SUPPORTED_JOB_TYPES)
        assert conn.execute("SELECT status FROM jobs WHERE job_type='fr_upload_finalize'").fetchone()[0] == "queued"
        assert conn.execute("SELECT COUNT(*) FROM fr_job_claims").fetchone()[0] == 0
    assert _lookup(settings,request,value)["status"] == "finalizing"


def test_ordered_002_migration_keeps_001_digest_destination_and_rolls_back(monkeypatch,tmp_path):
    path=tmp_path/"migration.sqlite3"
    original_sources=migrations.migration_sources
    monkeypatch.setattr(migrations,"migration_sources",lambda:[(migrations.VERSION,migrations.SCHEMA)])
    with closing(connect(path,5000)) as conn:
        run_migrations(conn);migrations.run_frame_relay_migrations(conn)
        destination=conn.execute("SELECT destination_id FROM fr_destination").fetchone()[0]
        original=tuple(conn.execute("SELECT version,sha256 FROM fr_schema_migrations").fetchone())
    monkeypatch.setattr(migrations,"migration_sources",original_sources)
    old_path=migrations.STORAGE_SCHEMA
    broken=tmp_path/"broken.sql";broken.write_text(old_path.read_text()+"\nSELECT * FROM does_not_exist;\n")
    monkeypatch.setattr(migrations,"STORAGE_SCHEMA",broken)
    with closing(connect(path,5000)) as conn:
        with pytest.raises(sqlite3.DatabaseError):migrations.run_frame_relay_migrations(conn)
        assert conn.execute("SELECT name FROM sqlite_master WHERE name='fr_upload_bindings'").fetchone() is None
        assert [tuple(row) for row in conn.execute("SELECT version,sha256 FROM fr_schema_migrations")] == [original]
    monkeypatch.setattr(migrations,"STORAGE_SCHEMA",old_path)
    with closing(connect(path,5000)) as conn:
        migrations.run_frame_relay_migrations(conn)
        assert tuple(conn.execute("SELECT version,sha256 FROM fr_schema_migrations WHERE version=?",(original[0],)).fetchone()) == original
        assert conn.execute("SELECT destination_id FROM fr_destination").fetchone()[0] == destination
        assert conn.execute("SELECT COUNT(*) FROM fr_schema_migrations").fetchone()[0] == 4


def test_worker_standalone_checks_fr_schema_before_recovery_or_claim(monkeypatch,tmp_path):
    settings,request,value=_setup(tmp_path,monkeypatch)
    from app.workers import worker
    called=[]
    monkeypatch.setattr(worker,"recover_expired_jobs",lambda *_:called.append("recovery"))
    monkeypatch.setattr(worker,"claim_next_job",lambda *_:called.append("claim"))
    with _database(settings) as conn:conn.execute("UPDATE fr_schema_migrations SET sha256='bad' WHERE version='002_storage'");conn.commit()
    with pytest.raises(migrations.FrameRelaySchemaError):worker.run_once()
    assert called == []


def test_worker_routes_fr_finalize_then_marks_unimplemented_conversion_failed(monkeypatch,tmp_path):
    settings,request,value=_setup(tmp_path,monkeypatch);_receive(settings,request,value)
    service.finalize(settings,value["session_id"],request,SECRET)
    from app.workers import worker
    assert worker.run_once()
    assert _lookup(settings,request,value)["evidence"]["committed"]
    assert worker.run_once() is True
    assert worker.run_once() is False
    assert _lookup(settings,request,value)["evidence"]["committed"]
    with _database(settings) as conn:
        row=conn.execute("SELECT status,error_message FROM jobs WHERE job_type='fr_conversion'").fetchone()
        assert tuple(row) == ("failed","conversion_adapter_not_implemented")
