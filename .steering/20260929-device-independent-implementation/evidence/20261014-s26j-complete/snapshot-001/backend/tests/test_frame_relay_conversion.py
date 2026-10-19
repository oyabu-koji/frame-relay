"""Real disk/job/candidate lifecycle, using explicitly non-Rec.709 fixture bytes."""
from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
from datetime import datetime, timedelta, timezone
import hashlib
import json
import sqlite3
from threading import Barrier, Event
from uuid import uuid4

import pytest

from app.db import frame_relay_migrations as migrations
from app.repositories import frame_relay_conversion as repository
from app.repositories import frame_relay_storage as storage_repository
from app.repositories.frame_relay_storage import StorageError
from app.repositories.jobs import claim_next_job, recover_expired_jobs, SUPPORTED_JOB_TYPES
from app.services import frame_relay_conversion as conversion
from app.services import frame_relay_storage as storage
from app.services import frame_relay_files as files
from app.workers import worker
from test_frame_relay_storage import _setup, _receive, _lookup, _database, SECRET, DATA, Crash


class FixtureAdapter:
    contract_version="fr-conversion-adapter-v1"
    result_kind="unpublished_technical_fixture"
    identity="fr-test-bytes-v1"

    def __init__(self):
        self.calls=[];self.handles=[]

    def accepts_source(self,context):
        return True

    def convert(self,*,context,source,destination,progress):
        self.calls.append(context);self.handles.extend((source,destination))
        data=source.read()
        assert len(data)==context.source_byte_count and hashlib.sha256(data).hexdigest()==context.source_sha256
        generated=b"unpublished-test-bytes:"+data
        destination.write(generated)
        progress("adapter_block")
        return conversion.CandidateReceipt(context,self.identity,hashlib.sha256(generated).hexdigest(),len(generated))


def prepared(tmp_path,monkeypatch):
    settings,request,value=_setup(tmp_path,monkeypatch)
    _receive(settings,request,value)
    storage.finalize(settings,value["session_id"],request,SECRET)
    assert worker.run_once()  # Actual S24 finalize dispatch, with real files/DB.
    assert _lookup(settings,request,value)["evidence"]["committed"]
    return settings,request,value


def claim(settings):
    with _database(settings) as conn:job=claim_next_job(conn,300,SUPPORTED_JOB_TYPES)
    assert job is not None and job["job_type"]=="fr_conversion"
    return job


def reclaim(settings,job):
    with _database(settings) as conn:
        conn.execute("UPDATE jobs SET lease_expires_at=? WHERE id=?",
            ((datetime.now(timezone.utc)-timedelta(seconds=1)).isoformat(),job["id"]));conn.commit()
        assert recover_expired_jobs(conn)==1
    result=claim(settings)
    assert result["fr_conversion_generation"]==job["fr_conversion_generation"]+1
    assert result["fr_conversion_token"]!=job["fr_conversion_token"]
    assert result["fr_conversion_candidate"]==job["fr_conversion_candidate"]
    return result


def candidates(settings):
    with _database(settings) as conn:
        return [dict(row) for row in conn.execute("SELECT * FROM fr_conversion_candidates ORDER BY generation")]


def jobs(settings):
    with _database(settings) as conn:
        return [dict(row) for row in conn.execute("SELECT * FROM jobs WHERE job_type='fr_conversion'")]


def retry(settings,value,previous,*,intent=None,payload=None,fault=None):
    with _database(settings) as conn:
        return repository.retry(conn,session_id=value["session_id"],expected_candidate_id=previous["candidate_id"],
            intent_id=intent or str(uuid4()),payload_json=payload or jobs(settings)[0]["payload_json"],fault=fault)


def test_real_worker_missing_adapter_is_terminal_and_preserves_storage_evidence(monkeypatch,tmp_path):
    settings,request,value=prepared(tmp_path,monkeypatch)
    proof=_lookup(settings,request,value)["evidence"]
    before=files.current_fingerprint(settings.media_root,value["final_path"])
    assert worker.run_once() and worker.run_once() is False
    item=candidates(settings)[0]
    assert item["status"]=="failed" and item["failure_code"]=="conversion_adapter_not_implemented"
    assert item["generation"]==1 and item["output_json"] is None
    assert len(jobs(settings))==1 and jobs(settings)[0]["status"]=="failed"
    assert _lookup(settings,request,value)["evidence"]==proof
    assert files.current_fingerprint(settings.media_root,value["final_path"])==before
    assert not list(settings.media_root.glob("candidates/frame-relay/*"))


def test_fixture_worker_creates_one_unpublished_candidate_without_rec709_or_pointer(monkeypatch,tmp_path):
    settings,request,value=prepared(tmp_path,monkeypatch)
    adapter=FixtureAdapter();assert worker.run_once(conversion_adapter=adapter)
    assert worker.run_once(conversion_adapter=adapter) is False
    item=candidates(settings)[0];output=json.loads(item["output_json"])
    assert item["status"]=="candidate_ready" and len(adapter.calls)==1
    assert output["published"] is False and output["rec709_verified"] is False
    assert output["receipt"]["result_kind"]=="unpublished_technical_fixture"
    assert (settings.media_root/item["candidate_path"]).read_bytes()==b"unpublished-test-bytes:"+DATA
    assert all(handle.closed for handle in adapter.handles)
    assert (settings.media_root/value["final_path"]).read_bytes()==DATA
    assert _lookup(settings,request,value)["evidence"]["committed"]
    with _database(settings) as conn:
        asset=conn.execute("SELECT * FROM assets").fetchone()
        assert asset["active_processed_result_id"] is None and asset["review_status"]=="not_reviewed"
        assert conn.execute("SELECT COUNT(*) FROM processed_results").fetchone()[0]==0


@pytest.mark.parametrize("field,bad",[("evidence_id","00000000-0000-0000-0000-000000000000"),
    ("session_id","00000000-0000-0000-0000-000000000000"),("asset_id",99999),
    ("binding_sha256","f"*64),("schema_version","unsupported")])
def test_forged_source_payload_is_terminal_before_candidate_or_adapter(monkeypatch,tmp_path,field,bad):
    settings,_request,_value=prepared(tmp_path,monkeypatch)
    row=jobs(settings)[0];payload=json.loads(row["payload_json"]);payload[field]=bad
    with _database(settings) as conn:
        conn.execute("UPDATE jobs SET payload_json=? WHERE id=?",(storage_repository.canonical(payload),row["id"]));conn.commit()
    adapter=FixtureAdapter();assert worker.run_once(conversion_adapter=adapter)
    assert worker.run_once(conversion_adapter=adapter) is False
    assert not adapter.calls and not candidates(settings)
    assert jobs(settings)[0]["error_message"]=="conversion_source_evidence_invalid"


def test_missing_storage_evidence_is_not_replaced_by_completed_or_is_log_flag(monkeypatch,tmp_path):
    settings,_request,_value=prepared(tmp_path,monkeypatch)
    with _database(settings) as conn:
        conn.execute("PRAGMA foreign_keys=OFF");conn.execute("DROP TRIGGER fr_evidence_no_delete")
        conn.execute("DELETE FROM fr_storage_evidence");conn.commit()
    adapter=FixtureAdapter();assert worker.run_once(conversion_adapter=adapter)
    assert not adapter.calls and not candidates(settings)
    assert jobs(settings)[0]["status"]=="failed"


def test_other_real_session_evidence_cannot_be_substituted(monkeypatch,tmp_path):
    settings,request,value=prepared(tmp_path,monkeypatch)
    second_request={**request,"operation_id":str(uuid4()),"capture_id":"other-original"}
    second=storage.create(settings,second_request,SECRET);_receive(settings,second_request,second)
    storage.finalize(settings,second["session_id"],second_request,SECRET)
    # Select only finalization so the first conversion remains untouched.
    from app.services.frame_relay_finalize import process_finalize
    with _database(settings) as conn:job=claim_next_job(conn,300,{"fr_upload_finalize"})
    process_finalize(settings=settings,job=job)
    second_proof=_lookup(settings,second_request,second)["evidence"]
    original=jobs(settings)[0];payload=json.loads(original["payload_json"]);payload["evidence_id"]=second_proof["evidence_id"]
    with _database(settings) as conn:
        conn.execute("UPDATE jobs SET payload_json=? WHERE id=?",(storage_repository.canonical(payload),original["id"]));conn.commit()
    adapter=FixtureAdapter();assert worker.run_once(conversion_adapter=adapter)
    assert not adapter.calls and not candidates(settings)


@pytest.mark.parametrize("mode",["missing","replacement","short","symlink"])
def test_changed_original_is_rejected_before_adapter(monkeypatch,tmp_path,mode):
    settings,_request,value=prepared(tmp_path,monkeypatch)
    path=settings.media_root/value["final_path"]
    if mode=="missing":path.unlink()
    elif mode=="short":path.write_bytes(DATA[:2])
    elif mode=="replacement":
        other=path.with_suffix(".replacement");other.write_bytes(DATA);other.replace(path)
    else:
        other=settings.media_root/"other.mov";other.write_bytes(DATA);path.unlink();path.symlink_to(other)
    adapter=FixtureAdapter();assert worker.run_once(conversion_adapter=adapter)
    assert not adapter.calls and candidates(settings)[0]["status"]=="failed"
    assert not list(settings.media_root.glob("candidates/frame-relay/*"))


def test_unfit_adapter_cannot_use_is_log_zero_as_input_classification(monkeypatch,tmp_path):
    settings,_request,_value=prepared(tmp_path,monkeypatch)
    adapter=FixtureAdapter();adapter.accepts_source=lambda context:False
    assert worker.run_once(conversion_adapter=adapter)
    assert not adapter.calls and candidates(settings)[0]["failure_code"]=="conversion_adapter_incompatible"


@pytest.mark.parametrize("mode",["wrong_context","wrong_digest","wrong_size","rec709_claim"])
def test_adapter_receipt_requires_exact_context_and_real_output(monkeypatch,tmp_path,mode):
    settings,_request,_value=prepared(tmp_path,monkeypatch)
    adapter=FixtureAdapter();original=adapter.convert
    def forged(**kwargs):
        result=original(**kwargs)
        if mode=="wrong_context":return replace(result,context=replace(result.context,claim_token=str(uuid4())))
        if mode=="wrong_digest":return replace(result,sha256="f"*64)
        if mode=="wrong_size":return replace(result,byte_count=result.byte_count+1)
        return replace(result,result_kind="validated_rec709")
    adapter.convert=forged
    assert worker.run_once(conversion_adapter=adapter)
    assert candidates(settings)[0]["status"]=="failed"
    assert not list(settings.media_root.glob("candidates/frame-relay/*"))
    assert all(handle.closed for handle in adapter.handles)


def test_explicit_retry_replays_acceptance_after_claim_and_failure_without_new_job(monkeypatch,tmp_path):
    settings,request,value=prepared(tmp_path,monkeypatch)
    original=files.current_fingerprint(settings.media_root,value["final_path"])
    assert worker.run_once();previous=candidates(settings)[0];intent=str(uuid4())
    accepted=retry(settings,value,previous,intent=intent)
    assert accepted["generation"]==2 and accepted["status"]=="queued"
    assert retry(settings,value,previous,intent=intent)==accepted
    current=claim(settings)
    running=retry(settings,value,previous,intent=intent)
    assert running["candidate_id"]==accepted["candidate_id"] and running["status"]=="running"
    conversion.process_conversion(settings=settings,job=current)
    failed=retry(settings,value,previous,intent=intent)
    assert failed["candidate_id"]==accepted["candidate_id"] and failed["generation"]==2 and failed["status"]=="failed"
    assert len(candidates(settings))==2 and len(jobs(settings))==1
    with pytest.raises(StorageError,match="retry_conflict"):
        retry(settings,value,previous,intent=intent,payload="{}")
    with pytest.raises(StorageError,match="stale_candidate"):
        retry(settings,value,previous)
    assert files.current_fingerprint(settings.media_root,value["final_path"])==original
    assert _lookup(settings,request,value)["evidence"]["committed"]


def test_retry_success_reuses_original_bytes_without_receiving_chunks_again(monkeypatch,tmp_path):
    settings,request,value=prepared(tmp_path,monkeypatch)
    before=files.current_fingerprint(settings.media_root,value["final_path"])
    assert worker.run_once();retry(settings,value,candidates(settings)[0])
    monkeypatch.setattr(storage,"receive_chunk",lambda *_args,**_kwargs:pytest.fail("No new upload allowed"))
    adapter=FixtureAdapter();assert worker.run_once(conversion_adapter=adapter)
    assert [row["status"] for row in candidates(settings)]==["failed","candidate_ready"]
    assert files.current_fingerprint(settings.media_root,value["final_path"])==before
    assert _lookup(settings,request,value)["chunk_indexes"]==[0,1,2,3]


@pytest.mark.parametrize("step",["before_retry_commit","after_retry_commit"])
def test_retry_commit_boundary_reopens_and_replays_one_accepted_candidate(monkeypatch,tmp_path,step):
    settings,_request,value=prepared(tmp_path,monkeypatch);assert worker.run_once()
    previous=candidates(settings)[0];intent=str(uuid4())
    def crash(observed):
        if observed==step:raise Crash()
    with pytest.raises(Crash):retry(settings,value,previous,intent=intent,fault=crash)
    assert len(candidates(settings))==(1 if step=="before_retry_commit" else 2)
    accepted=retry(settings,value,previous,intent=intent)
    assert len(candidates(settings))==2 and retry(settings,value,previous,intent=intent)["candidate_id"]==accepted["candidate_id"]


@pytest.mark.parametrize("step",["before_candidate_publish","after_candidate_publish","before_candidate_commit","after_candidate_update","after_candidate_commit"])
def test_candidate_crash_boundaries_reopen_without_duplicate_version_or_publication(monkeypatch,tmp_path,step):
    settings,_request,value=prepared(tmp_path,monkeypatch);old=claim(settings)
    def crash(observed):
        if observed==step:raise Crash()
    with pytest.raises(Crash):conversion.process_conversion(settings=settings,job=old,adapter=FixtureAdapter(),fault=crash)
    if step=="after_candidate_commit":
        assert candidates(settings)[0]["status"]=="candidate_ready"
        conversion.process_conversion(settings=settings,job=old,adapter=FixtureAdapter())
    else:
        assert candidates(settings)[0]["status"]=="running" and jobs(settings)[0]["status"]=="running"
        new=reclaim(settings,old)
        conversion.process_conversion(settings=settings,job=new,adapter=FixtureAdapter())
    assert len(candidates(settings))==1 and candidates(settings)[0]["status"]=="candidate_ready"
    assert jobs(settings)[0]["status"]=="done"
    assert (settings.media_root/value["final_path"]).read_bytes()==DATA


def test_sqlite_candidate_commit_failure_rolls_back_and_requires_explicit_retry(monkeypatch,tmp_path):
    settings,_request,value=prepared(tmp_path,monkeypatch)
    with _database(settings) as conn:
        conn.execute("""CREATE TRIGGER fr_test_reject_candidate BEFORE UPDATE OF status ON fr_conversion_candidates
            WHEN NEW.status='candidate_ready' BEGIN SELECT RAISE(ABORT,'injected'); END""");conn.commit()
    assert worker.run_once(conversion_adapter=FixtureAdapter())
    previous=candidates(settings)[0]
    assert previous["status"]=="failed" and previous["output_json"] is None
    assert jobs(settings)[0]["status"]=="failed" and worker.run_once() is False
    assert (settings.media_root/previous["candidate_path"]).exists()
    with _database(settings) as conn:conn.execute("DROP TRIGGER fr_test_reject_candidate");conn.commit()
    retry(settings,value,previous);assert worker.run_once(conversion_adapter=FixtureAdapter())
    assert [row["status"] for row in candidates(settings)]==["failed","candidate_ready"]


def test_old_claim_delayed_success_failure_renew_and_cleanup_cannot_touch_current_candidate(monkeypatch,tmp_path):
    settings,_request,value=prepared(tmp_path,monkeypatch);old=claim(settings)
    reached,release=Barrier(2),Event()
    def pause(step):
        if step=="before_candidate_publish":reached.wait(timeout=10);assert release.wait(10)
    with ThreadPoolExecutor(max_workers=1) as pool:
        future=pool.submit(conversion.process_conversion,settings=settings,job=old,adapter=FixtureAdapter(),fault=pause)
        try:
            reached.wait(timeout=10)
            previous=candidates(settings)[0];old_file=settings.media_root/conversion.attempt_path(previous,old)
            assert old_file.exists()
            new=reclaim(settings,old)
            with pytest.raises(StorageError,match="stale_claim"):conversion.cleanup_attempt(settings,old)
            with pytest.raises(StorageError,match="stale_claim"):conversion.mark_failed(settings,old,"late_failure")
            with _database(settings) as conn:
                conn.execute("BEGIN IMMEDIATE")
                with pytest.raises(StorageError,match="stale_claim"):repository.renew_claim(conn,old,300)
                conn.rollback()
            conversion.process_conversion(settings=settings,job=new,adapter=FixtureAdapter())
        finally:release.set()
        assert future.result(timeout=10)
    item=candidates(settings)[0];receipt=json.loads(item["output_json"])["receipt"]
    assert item["generation"]==1 and receipt["context"]["claim_generation"]==2
    assert receipt["context"]["claim_token"]==new["fr_conversion_token"] and old_file.exists()
    assert jobs(settings)[0]["status"]=="done" and (settings.media_root/value["final_path"]).read_bytes()==DATA


def test_input_read_holds_no_sqlite_writer_and_old_read_claim_never_reaches_adapter(monkeypatch,tmp_path):
    settings,_request,_value=prepared(tmp_path,monkeypatch);old=claim(settings)
    reached,release=Barrier(2),Event();adapter=FixtureAdapter()
    def pause(step):
        if step=="input_read_block":reached.wait(timeout=10);assert release.wait(10)
    with ThreadPoolExecutor(max_workers=1) as pool:
        future=pool.submit(conversion.process_conversion,settings=settings,job=old,adapter=adapter,fault=pause)
        try:
            reached.wait(timeout=10)
            new=reclaim(settings,old)  # Real independent writer commits while read is paused.
            conversion.process_conversion(settings=settings,job=new,adapter=FixtureAdapter())
        finally:release.set()
        assert future.result(timeout=10)
    assert not adapter.calls and candidates(settings)[0]["status"]=="candidate_ready"


def test_current_claim_renewal_and_terminal_attempt_cleanup_keep_original_and_other_files(monkeypatch,tmp_path):
    settings,_request,value=prepared(tmp_path,monkeypatch);job=claim(settings)
    item=candidates(settings)[0];owned=conversion.attempt_path(item,job)
    with files.exclusive_writer(settings.media_root,owned) as output:output.write(b"ended-attempt")
    other=settings.media_root/"unrelated-retained";other.write_bytes(b"retained")
    with _database(settings) as conn:
        conn.execute("BEGIN IMMEDIATE");repository.renew_claim(conn,job,300);conn.commit()
        row=conn.execute("SELECT lease_expires_at FROM jobs WHERE id=?",(job["id"],)).fetchone()
        assert row[0]>storage_repository.now_text()
    conversion.cleanup_attempt(settings,job)
    assert not (settings.media_root/owned).exists()
    assert other.read_bytes()==b"retained" and (settings.media_root/value["final_path"]).read_bytes()==DATA
    conversion.process_conversion(settings=settings,job=job,adapter=FixtureAdapter())
    with pytest.raises(StorageError,match="stale_claim"):conversion.cleanup_attempt(settings,job)
    assert candidates(settings)[0]["status"]=="candidate_ready"


def test_original_change_during_adapter_is_not_a_ready_candidate(monkeypatch,tmp_path):
    settings,_request,value=prepared(tmp_path,monkeypatch);job=claim(settings)
    def mutate(step):
        if step=="adapter_block":(settings.media_root/value["final_path"]).write_bytes(DATA[:1])
    conversion.process_conversion(settings=settings,job=job,adapter=FixtureAdapter(),fault=mutate)
    assert candidates(settings)[0]["status"]=="failed"
    assert not list(settings.media_root.glob("candidates/frame-relay/*"))


def test_v1_fixture_pointer_bytes_and_confirmation_survive_candidate_failure_and_success(monkeypatch,tmp_path):
    settings,_request,value=prepared(tmp_path,monkeypatch)
    # Seed a legacy-shaped V1 directly as a retention fixture, not as G3 proof
    # or through a forbidden publication API. S26J must never alter this row.
    v1=b"published-v1-fixture";relative="previews/"+uuid4().hex+".mp4"
    path=settings.media_root/relative;path.write_bytes(v1);result_id=uuid4().hex
    with _database(settings) as conn:
        asset_id=conn.execute("SELECT id FROM assets").fetchone()[0]
        derived=conn.execute("INSERT INTO derived_files(asset_id,kind,path,mime_type,size_bytes) VALUES(?,'preview',?,'video/mp4',?)",
                             (asset_id,relative,len(v1))).lastrowid
        conn.execute("INSERT INTO processed_results(id,asset_id,derived_file_id,status,mime_type,size_bytes,sha256) VALUES(?,?,?,'ready','video/mp4',?,?)",
                     (result_id,asset_id,derived,len(v1),hashlib.sha256(v1).hexdigest()))
        conn.execute("UPDATE assets SET active_processed_result_id=?,preview_status='preview_ready',review_status='reviewed' WHERE id=?",(result_id,asset_id));conn.commit()
        before=dict(conn.execute("SELECT * FROM assets WHERE id=?",(asset_id,)).fetchone())
        before_result=dict(conn.execute("SELECT * FROM processed_results WHERE id=?",(result_id,)).fetchone())
    assert worker.run_once();retry(settings,value,candidates(settings)[0])
    assert worker.run_once(conversion_adapter=FixtureAdapter())
    with _database(settings) as conn:
        assert dict(conn.execute("SELECT * FROM assets WHERE id=?",(asset_id,)).fetchone())==before
        assert dict(conn.execute("SELECT * FROM processed_results WHERE id=?",(result_id,)).fetchone())==before_result
        assert conn.execute("SELECT COUNT(*) FROM processed_results").fetchone()[0]==1
    assert path.read_bytes()==v1 and (settings.media_root/value["final_path"]).read_bytes()==DATA


def test_003_migration_preserves_001_002_and_rolls_back_candidate_schema(monkeypatch,tmp_path):
    settings,_request,_value=prepared(tmp_path,monkeypatch)
    with _database(settings) as conn:
        original=[tuple(row) for row in conn.execute("SELECT * FROM fr_schema_migrations WHERE version!='003_conversion_candidates' ORDER BY version")]
        # Construct a fresh predecessor with the same official 001/002 files.
    from app.db.connection import connect
    from app.db.migrations import run_migrations
    from contextlib import closing
    predecessor=tmp_path/"predecessor.sqlite3";sources=migrations.migration_sources
    monkeypatch.setattr(migrations,"migration_sources",lambda:sources()[:2])
    with closing(connect(predecessor,5000)) as conn:
        run_migrations(conn);migrations.run_frame_relay_migrations(conn)
        destination=conn.execute("SELECT destination_id FROM fr_destination").fetchone()[0]
    monkeypatch.setattr(migrations,"migration_sources",sources)
    real=migrations.CONVERSION_SCHEMA;broken=tmp_path/"broken003.sql"
    broken.write_text(real.read_text()+"\nSELECT * FROM nonexistent;\n");monkeypatch.setattr(migrations,"CONVERSION_SCHEMA",broken)
    with closing(connect(predecessor,5000)) as conn:
        with pytest.raises(sqlite3.DatabaseError):migrations.run_frame_relay_migrations(conn)
        assert conn.execute("SELECT name FROM sqlite_master WHERE name='fr_conversion_candidates'").fetchone() is None
        assert [tuple(row) for row in conn.execute("SELECT * FROM fr_schema_migrations ORDER BY version")]==original
    monkeypatch.setattr(migrations,"CONVERSION_SCHEMA",real)
    with closing(connect(predecessor,5000)) as conn:
        migrations.run_frame_relay_migrations(conn)
        assert conn.execute("SELECT destination_id FROM fr_destination").fetchone()[0]==destination
        assert [tuple(row) for row in conn.execute("SELECT * FROM fr_schema_migrations WHERE version!='003_conversion_candidates' ORDER BY version")]==original
