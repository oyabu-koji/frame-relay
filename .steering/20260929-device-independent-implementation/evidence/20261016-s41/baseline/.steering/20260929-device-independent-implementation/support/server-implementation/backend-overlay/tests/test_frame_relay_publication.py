"""Real SQLite/files and fault/reopen boundaries; fixture authority is not quality proof."""
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from copy import deepcopy
from dataclasses import replace
import hashlib
import json
import os
import sqlite3
from threading import Barrier
from types import SimpleNamespace
from uuid import uuid4

from fastapi import FastAPI
from fastapi.testclient import TestClient
import pytest

from app.api.frame_relay_publication import create_router, PinnedResponse
from app.db.connection import connect
from app.db.migrations import run_migrations
from app.db import frame_relay_migrations as migrations
from app.repositories import frame_relay_publication as repository
from app.repositories import registrations
from app.repositories.frame_relay_publication import PublicationError
from app.repositories.frame_relay_storage import StorageError
from app.schemas import frame_relay_publication as wire
from app.services import frame_relay_files as files
from app.services.frame_relay_distribution import open_stream, header_id, parse_header_id
from app.services.frame_relay_publication import PublicationService, container_type, json_bytes
from frame_relay_publication_fixture import fixture_service, seed_candidate
from test_frame_relay_storage import _setup, _database, SECRET, Crash


PREFIX = "/frame-relay/v1/publication"
# Container-only unit fixture, deliberately not a playable/Rec.709 movie. The
# separately reviewed HTTP suite uses the actual QuickTime/PCM movie.
PAYLOAD = bytes(range(256)) * 1024
MOV = b"\0\0\0\x14ftypqt  \0\0\0\0qt  " + (len(PAYLOAD)+8).to_bytes(4,"big") + b"mdat" + PAYLOAD


def world(tmp_path, monkeypatch):
    settings, binding, _value = _setup(tmp_path, monkeypatch)
    settings = replace(settings, upload_session_chunk_size_bytes=65_536, upload_session_max_size_bytes=16*1024*1024)
    reg = {"destination_id": binding["destination_id"], "registration_id": binding["registration_id"],
           "generation": binding["registration_generation"]}
    seed = seed_candidate(settings, reg, SECRET, MOV, "opaque/capture:日本語", str(uuid4()))
    return SimpleNamespace(settings=settings, reg=reg, seed=seed, service=fixture_service(settings))


def publish(w):
    return w.service.publish_initial(operation_id=str(uuid4()), candidate_id=w.seed["candidate_id"], expected_revision=0)["rendition"]


def manifest(w, reg=None):
    return w.service.manifest({"schema_version": wire.VERSION, "registration": reg or w.reg,
        "original": w.seed["original"]}, SECRET)["result"]


def second(w):
    return seed_candidate(w.settings, w.reg, SECRET, MOV, w.seed["original"]["capture_id"], str(uuid4()))


def begin(w, *, invalidation_id=None):
    candidate = second(w)
    return w.service.begin_replacement(operation_id=str(uuid4()), candidate_id=candidate["candidate_id"],
        invalidation_id=invalidation_id or str(uuid4()), expected_revision=int(manifest(w)["revision"]))


def source_request(w, rendition, *, reg=None, operation=None):
    return {"schema_version": wire.VERSION, "operation_id": operation or str(uuid4()), "registration": reg or w.reg,
        "rendition": rendition, "gate": {"operation_id": "opaque/transport:日本語", "attempt_id": "attempt-1", "access_generation": "1"},
        "purpose": "source", "kind": "full", "range": None, "source_operation_id": None}


def read_request(source, *, operation=None, range_value=None):
    return {**source, "operation_id": operation or str(uuid4()), "purpose": "read", "kind": "range",
        "source_operation_id": source["operation_id"], "range": range_value or {"lower_bound": "0", "upper_bound": "32"}}


def accepted_read(w, rendition, *, reg=None, source_id=None, read_id=None):
    source = source_request(w, rendition, reg=reg, operation=source_id)
    source_response = w.service.accept_distribution(source, SECRET)
    request = read_request(source, operation=read_id)
    w.service.accept_distribution(request, SECRET)
    return source, source_response, request


def open_request(w, request, *, fault=None):
    value = request["range"]
    range_header = None if value is None else f"bytes={value['lower_bound']}-{int(value['upper_bound'])-1}"
    return open_stream(w.service, rendition_id=request["rendition"]["rendition_id"], registration=request["registration"],
        secret=SECRET, operation_id=request["operation_id"], gate=request["gate"], range_header=range_header, fault=fault)


def invalidations(w, reg=None, after=None, limit="8"):
    encoded = w.service.invalidations({"schema_version": wire.VERSION, "registration": reg or w.reg,
        "after_invalidation_id": after, "limit": limit}, SECRET)
    assert isinstance(encoded, bytes) and len(encoded) <= 196_608
    return json.loads(encoded)["result"]


def ack_request(w, record, *, reg=None):
    return {"schema_version": wire.VERSION, "registration": reg or w.reg,
        "acknowledgement": {"invalidation": record, "local_commit": {"previous_revision": "10", "committed_revision": "11"}}}


def confirm_request(w, receipt):
    return {"schema_version": wire.VERSION, "registration": w.reg, "confirmation": {
        "operation_id": str(uuid4()), "playback_session_id": "explicit-fixture-user-action",
        "distribution": receipt, "invalidation_generation": "0", "observation": "played",
        "local_commit": {"previous_revision": "8", "committed_revision": "9"}}}


def finish(w, replacement):
    return w.service.publish_replacement(operation_id=str(uuid4()), replacement_id=replacement["replacement_id"],
        expected_revision=int(manifest(w)["revision"]))


def new_registration(w):
    with _database(w.settings) as conn:
        value = registrations.register(conn, destination_id=w.reg["destination_id"], operation_id=str(uuid4()), secret=SECRET)
    return {key: value[key] for key in ("destination_id", "registration_id", "generation")}


def headers():
    return {"Authorization": "Bearer storage-test-bootstrap", "X-FrameRelay-Registration-Secret": SECRET}


def client(w, *, production=False):
    app = FastAPI()
    app.include_router(create_router(lambda: PublicationService(w.settings) if production else fixture_service(w.settings)))
    return TestClient(app)


def get_kwargs(request):
    reg = request["registration"]
    values = {**headers(), "Accept-Encoding": "identity",
        "X-FrameRelay-Distribution-ID": header_id(request["operation_id"]),
        "X-FrameRelay-Transport-ID": header_id(request["gate"]["operation_id"]),
        "X-FrameRelay-Attempt-ID": header_id(request["gate"]["attempt_id"]),
        "X-FrameRelay-Access-Generation": request["gate"]["access_generation"]}
    if request["range"] is not None:
        values["Range"] = f"bytes={request['range']['lower_bound']}-{int(request['range']['upper_bound'])-1}"
    return {"headers": values, "params": {"destination_id": reg["destination_id"], "registration_id": reg["registration_id"],
                                         "registration_generation": reg["generation"]}}


def test_unpublished_initial_commit_does_not_fabricate_previous_or_ack(tmp_path, monkeypatch):
    w = world(tmp_path, monkeypatch)
    assert manifest(w) == {"current": None, "media_type": None, "revision": "0", "invalidation_generation": "0", "replacement_pending": False}
    original = w.settings.media_root / ("originals/frame-relay/" + w.seed["session_id"] + ".bin")
    with _database(w.settings) as conn:
        original = w.settings.media_root / conn.execute("SELECT final_path FROM fr_upload_bindings WHERE session_id=?", (w.seed["session_id"],)).fetchone()[0]
    before = original.read_bytes()
    rendition = publish(w)
    w.service = fixture_service(w.settings)
    assert manifest(w)["current"] == rendition and manifest(w)["media_type"] == "video/quicktime"
    with _database(w.settings) as conn:
        assert conn.execute("SELECT COUNT(*) FROM fr_invalidation_acks").fetchone()[0] == 0
        assert conn.execute("SELECT COUNT(*) FROM fr_publication_replacements").fetchone()[0] == 0
        artifact = repository.artifact(conn, rendition["rendition_id"], w.service.authority)
        candidate = conn.execute("SELECT candidate_path FROM fr_conversion_candidates WHERE candidate_id=?", (w.seed["candidate_id"],)).fetchone()[0]
    assert (w.settings.media_root / artifact["path"]).stat().st_ino != (w.settings.media_root / candidate).stat().st_ino
    assert original.read_bytes() == before and artifact["proof_kind"] == "technical_fixture"


@pytest.mark.parametrize("stage", ["before_commit", "after_commit"])
def test_initial_publication_fault_reopen_and_exact_replay(tmp_path, monkeypatch, stage):
    w = world(tmp_path, monkeypatch)
    request = {"operation_id": str(uuid4()), "candidate_id": w.seed["candidate_id"], "expected_revision": 0}
    def fault(step):
        if step == stage:
            raise Crash()
    with pytest.raises(Crash):
        w.service.publish_initial(**request, fault=fault)
    w.service = fixture_service(w.settings)
    assert (manifest(w)["current"] is not None) == (stage == "after_commit")
    result = w.service.publish_initial(**request)
    assert w.service.publish_initial(**request) == result
    with pytest.raises(PublicationError, match="operation_conflict"):
        w.service.publish_initial(**{**request, "expected_revision": 9})
    with _database(w.settings) as conn:
        assert conn.execute("SELECT COUNT(*) FROM fr_publication_artifacts").fetchone()[0] == 1


def test_dynamic_required_recipients_preserve_old_registration_and_reject_old_ack_substitution(tmp_path, monkeypatch):
    w = world(tmp_path, monkeypatch)
    v1 = publish(w)
    first = source_request(w, v1)
    w.service.accept_distribution(first, SECRET)
    replacement = begin(w)
    old_record = invalidations(w)["invalidations"][0]
    reg2 = new_registration(w)
    w.service.accept_distribution(source_request(w, v1, reg=reg2), SECRET)
    second_record = invalidations(w, reg2)["invalidations"][0]
    with pytest.raises(PublicationError, match="ack_mismatch"):
        w.service.acknowledge(ack_request(w, old_record, reg=reg2), SECRET)
    w.service.acknowledge(ack_request(w, second_record, reg=reg2), SECRET)
    with pytest.raises(PublicationError, match="awaiting_acknowledgements"):
        finish(w, replacement)
    with pytest.raises(PublicationError, match="invalidated"):
        w.service.accept_distribution(source_request(w, v1, reg=reg2), SECRET)
    assert manifest(w)["current"] == v1
    w.service.acknowledge(ack_request(w, old_record), SECRET)
    v2 = finish(w, replacement)["rendition"]
    assert v2 == replacement["rendition"] and v2 != v1
    with _database(w.settings) as conn:
        assert conn.execute("SELECT COUNT(*) FROM fr_publication_recipients WHERE rendition_id=?", (v1["rendition_id"],)).fetchone()[0] == 2


@pytest.mark.parametrize("mutation", ["range", "kind", "gate", "source", "rendition"])
def test_same_distribution_operation_requires_entire_payload(tmp_path, monkeypatch, mutation):
    w = world(tmp_path, monkeypatch)
    _source, _receipt, request = accepted_read(w, publish(w))
    changed = deepcopy(request)
    if mutation == "range": changed["range"]["upper_bound"] = "31"
    elif mutation == "kind": changed["kind"] = "resume"
    elif mutation == "gate": changed["gate"]["attempt_id"] = "other"
    elif mutation == "source": changed["source_operation_id"] = str(uuid4())
    else: changed["rendition"]["conversion_version"] = "other"
    with pytest.raises(PublicationError, match="operation_conflict"):
        w.service.accept_distribution(changed, SECRET)


def test_identical_operation_ids_in_two_registrations_have_independent_concurrent_admissions(tmp_path, monkeypatch):
    w = world(tmp_path, monkeypatch)
    rendition = publish(w)
    reg2 = new_registration(w)
    first = accepted_read(w, rendition, source_id="same-source", read_id="same-read")[2]
    second_request = accepted_read(w, rendition, reg=reg2, source_id="same-source", read_id="same-read")[2]
    barrier = Barrier(2)
    def read(request):
        result = open_request(w, request, fault=lambda step: barrier.wait(timeout=10) if step == "after_hash" else None)
        return b"".join(result), result.closed
    with ThreadPoolExecutor(max_workers=2) as executor:
        futures = [executor.submit(read, value) for value in (first, second_request)]
        assert [future.result(timeout=20) for future in futures] == [(MOV[:32], True), (MOV[:32], True)]
    with _database(w.settings) as conn:
        assert conn.execute("SELECT COUNT(*) FROM fr_get_admissions WHERE distribution_operation_id='same-read'").fetchone()[0] == 2


def test_same_registration_concurrent_ticket_consumption_has_one_winner(tmp_path, monkeypatch):
    w = world(tmp_path, monkeypatch)
    request = accepted_read(w, publish(w))[2]
    barrier = Barrier(2)
    def read():
        try:
            result = open_request(w, request, fault=lambda step: barrier.wait(timeout=10) if step == "after_hash" else None)
            return b"".join(result)
        except PublicationError as error:
            return error.code
    with ThreadPoolExecutor(max_workers=2) as executor:
        futures = [executor.submit(read) for _ in range(2)]
        results = [future.result(timeout=20) for future in futures]
    assert results.count(MOV[:32]) == 1 and results.count("publication_get_consumed") == 1


@pytest.mark.parametrize("stage", ["before_commit", "after_commit"])
def test_distribution_response_loss_reopen_returns_exact_request_and_receipt(tmp_path, monkeypatch, stage):
    w = world(tmp_path, monkeypatch)
    request = source_request(w, publish(w))
    def fault(step):
        if step == stage: raise Crash()
    with pytest.raises(Crash): w.service.accept_distribution(request, SECRET, fault=fault)
    w.service = fixture_service(w.settings)
    query = {"schema_version": wire.VERSION, "registration": w.reg, "kind": "distribution", "operation_id": request["operation_id"]}
    if stage == "before_commit":
        with pytest.raises(PublicationError, match="not_executed"): w.service.lookup(query, SECRET)
    result = w.service.accept_distribution(request, SECRET)
    lookup = w.service.lookup(query, SECRET)
    assert lookup["request"] == query
    assert lookup["result"] == {"original_request": request, "original_result": result["result"]}


@pytest.mark.parametrize("stage", ["before_commit", "after_commit"])
def test_get_commit_loss_and_interrupted_body_require_new_acceptance(tmp_path, monkeypatch, stage):
    w = world(tmp_path, monkeypatch)
    source, _receipt, request = accepted_read(w, publish(w))
    def fault(step):
        if step == stage: raise Crash()
    with pytest.raises(Crash): open_request(w, request, fault=fault)
    if stage == "after_commit":
        with pytest.raises(PublicationError, match="get_consumed"): open_request(w, request)
    else:
        result = open_request(w, request)
        result.close()  # Body never starts; admission is nevertheless consumed.
        assert result.closed and result.delivered_bytes == 0
    next_request = read_request(source)
    w.service.accept_distribution(next_request, SECRET)
    result = open_request(w, next_request)
    iterator = iter(result)
    assert next(iterator) == MOV[:32]
    iterator.close()
    assert result.closed
    with pytest.raises(PublicationError, match="get_consumed"): open_request(w, next_request)


def test_get_whole_hash_is_outside_writer_and_rechecks_publication_before_bytes(tmp_path, monkeypatch):
    w = world(tmp_path, monkeypatch)
    v1 = publish(w)
    request = accepted_read(w, v1)[2]
    replacement = begin(w)
    observed = []
    def fault(step):
        if step == "artifact_read_block" and not observed:
            with _database(w.settings) as conn:
                conn.execute("CREATE TABLE publication_other_writer(value INTEGER)")
                conn.commit()
            observed.append(step)
        if step == "after_hash":
            w.service.acknowledge(ack_request(w, invalidations(w)["invalidations"][0]), SECRET)
            finish(w, replacement)
    with pytest.raises(PublicationError, match="stale_rendition"):
        open_request(w, request, fault=fault)
    assert observed
    with _database(w.settings) as conn:
        assert conn.execute("SELECT COUNT(*) FROM fr_get_admissions").fetchone()[0] == 0


def test_accepted_old_response_keeps_its_inode_after_ack_and_publication(tmp_path, monkeypatch):
    w = world(tmp_path, monkeypatch)
    v1 = publish(w)
    source, _receipt, request = accepted_read(w, v1)
    accepted = open_request(w, request)
    inode = os.fstat(accepted.source.fileno()).st_ino
    replacement = begin(w)
    w.service.acknowledge(ack_request(w, invalidations(w)["invalidations"][0]), SECRET)
    finish(w, replacement)
    assert os.fstat(accepted.source.fileno()).st_ino == inode
    assert b"".join(accepted) == MOV[:32] and accepted.closed
    with pytest.raises(PublicationError, match="stale_rendition"):
        w.service.accept_distribution(read_request(source), SECRET)


@pytest.mark.parametrize("change", ["same_size", "truncate", "replace", "symlink", "hardlink"])
def test_changed_artifact_after_hash_is_rejected_without_admission(tmp_path, monkeypatch, change):
    w = world(tmp_path, monkeypatch)
    request = accepted_read(w, publish(w))[2]
    with _database(w.settings) as conn:
        item = repository.artifact(conn, request["rendition"]["rendition_id"], w.service.authority)
    path = w.settings.media_root / item["path"]
    def fault(step):
        if step != "after_hash": return
        if change in ("same_size", "truncate"):
            path.chmod(0o600)
            path.write_bytes(b"x"*len(MOV) if change == "same_size" else MOV[:20])
        elif change == "replace":
            other = path.with_suffix(".external"); other.write_bytes(MOV); other.replace(path)
        elif change == "symlink":
            other = path.with_suffix(".external"); other.write_bytes(MOV); path.unlink(); path.symlink_to(other)
        else:
            os.link(path, path.with_suffix(".external-link"))
    with pytest.raises((PublicationError, StorageError)):
        open_request(w, request, fault=fault)
    with _database(w.settings) as conn:
        assert conn.execute("SELECT COUNT(*) FROM fr_get_admissions").fetchone()[0] == 0


def test_candidate_alias_write_after_hash_does_not_mutate_sealed_inode(tmp_path, monkeypatch):
    w = world(tmp_path, monkeypatch)
    request = accepted_read(w, publish(w))[2]
    with _database(w.settings) as conn:
        path = w.settings.media_root / conn.execute("SELECT candidate_path FROM fr_conversion_candidates WHERE candidate_id=?", (w.seed["candidate_id"],)).fetchone()[0]
    alias = path.with_suffix(".alias"); os.link(path, alias)
    def fault(step):
        if step == "after_hash": alias.write_bytes(b"x"*len(MOV))
    result = open_request(w, request, fault=fault)
    assert b"".join(result) == MOV[:32] and result.closed


def test_external_inplace_write_after_admission_is_detected_without_claiming_retraction(tmp_path, monkeypatch):
    w = world(tmp_path, monkeypatch)
    request = accepted_read(w, publish(w))[2]
    result = open_request(w, request)
    path = w.settings.media_root / result.item["path"]
    path.chmod(0o600); path.write_bytes(b"x"*len(MOV))
    with pytest.raises(PublicationError, match="artifact_changed"): next(iter(result))
    assert result.closed and result.delivered_bytes == 0
    # This observes detection before the first block, not prevention of arbitrary
    # external writes between a subsequent check and a network send.


def test_sealed_artifact_cannot_be_written_aliased_or_removed_by_app_helpers(tmp_path, monkeypatch):
    w = world(tmp_path, monkeypatch)
    rendition = publish(w)
    with _database(w.settings) as conn: item = repository.artifact(conn, rendition["rendition_id"], w.service.authority)
    with pytest.raises(StorageError, match="sealed"):
        with files.exclusive_writer(w.settings.media_root, item["path"]): pass
    with pytest.raises(StorageError, match="sealed"): files.publish(w.settings.media_root, item["path"], "tmp/alias")
    with pytest.raises(StorageError, match="sealed"): files.remove_owned(w.settings.media_root, item["path"])
    assert (w.settings.media_root/item["path"]).read_bytes() == MOV


@pytest.mark.parametrize("stage", ["before_commit", "after_commit"])
def test_confirmation_and_ack_fault_reopen_never_restore_invalidated_confirmation(tmp_path, monkeypatch, stage):
    w = world(tmp_path, monkeypatch)
    v1 = publish(w)
    source = source_request(w, v1)
    receipt = w.service.accept_distribution(source, SECRET)["result"]["receipt"]
    confirmation = confirm_request(w, receipt)
    def fault(step):
        if step == stage: raise Crash()
    with pytest.raises(Crash): w.service.confirm(confirmation, SECRET, fault=fault)
    w.service = fixture_service(w.settings)
    accepted = w.service.confirm(confirmation, SECRET)
    replacement = begin(w)
    ack = ack_request(w, invalidations(w)["invalidations"][0])
    with pytest.raises(Crash): w.service.acknowledge(ack, SECRET, fault=fault)
    w.service = fixture_service(w.settings)
    assert w.service.acknowledge(ack, SECRET)["result"]["accepted"]
    assert w.service.confirm(confirmation, SECRET) == accepted  # Historical acceptance only.
    changed = deepcopy(confirmation); changed["confirmation"]["operation_id"] = str(uuid4())
    with pytest.raises(PublicationError, match="invalidated"): w.service.confirm(changed, SECRET)
    lookup = {"schema_version": wire.VERSION, "registration": w.reg, "kind": "acknowledgement",
              "operation_id": ack["acknowledgement"]["invalidation"]["invalidation_id"]}
    assert w.service.lookup(lookup, SECRET)["result"]["original_request"] == ack
    finish(w, replacement)


def test_candidate_failure_after_invalidation_keeps_tombstone_and_old_pointer(tmp_path, monkeypatch):
    w = world(tmp_path, monkeypatch)
    v1 = publish(w)
    _source, _response, request = accepted_read(w, v1)
    replacement = begin(w)
    w.service.acknowledge(ack_request(w, invalidations(w)["invalidations"][0]), SECRET)
    with _database(w.settings) as conn:
        item = repository.artifact(conn, replacement["rendition"]["rendition_id"], w.service.authority)
    (w.settings.media_root/item["path"]).unlink()  # External fault, never app cleanup.
    with pytest.raises(OSError): finish(w, replacement)
    assert manifest(w)["current"] == v1
    with pytest.raises(PublicationError, match="invalidated"): open_request(w, request)


@pytest.mark.parametrize("entry", ["manifest", "distribution", "get", "lookup", "publish"])
def test_normal_production_authority_rejects_fixture_database_after_reopen(tmp_path, monkeypatch, entry):
    w = world(tmp_path, monkeypatch)
    rendition = publish(w)
    source, _response, request = accepted_read(w, rendition)
    w.service = PublicationService(w.settings)
    with pytest.raises(PublicationError, match="proof_not_implemented"):
        if entry == "manifest": manifest(w)
        elif entry == "distribution": w.service.accept_distribution(source, SECRET)
        elif entry == "get": open_request(w, request)
        elif entry == "lookup": w.service.lookup({"schema_version": wire.VERSION, "registration": w.reg, "kind": "distribution", "operation_id": source["operation_id"]}, SECRET)
        else: w.service.publish_initial(operation_id=str(uuid4()), candidate_id=w.seed["candidate_id"], expected_revision=0)


def test_boolean_rec709_forgery_does_not_enable_production_authority(tmp_path, monkeypatch):
    w = world(tmp_path, monkeypatch)
    with _database(w.settings) as conn:
        row = conn.execute("SELECT output_json FROM fr_conversion_candidates WHERE candidate_id=?", (w.seed["candidate_id"],)).fetchone()
        value = json.loads(row[0]); value["published"] = True; value["rec709_verified"] = True
        conn.execute("UPDATE fr_conversion_candidates SET output_json=? WHERE candidate_id=?", (json.dumps(value), w.seed["candidate_id"])); conn.commit()
    with pytest.raises(PublicationError, match="proof_not_implemented"):
        PublicationService(w.settings).publish_initial(operation_id=str(uuid4()), candidate_id=w.seed["candidate_id"], expected_revision=0)
    with _database(w.settings) as conn:
        assert conn.execute("SELECT COUNT(*) FROM fr_publication_artifacts").fetchone()[0] == 0


@pytest.mark.parametrize("operation", ["distribution", "confirmation", "acknowledgement", "publication"])
def test_sqlite_failure_rolls_back_entire_publication_mutation(tmp_path, monkeypatch, operation):
    w = world(tmp_path, monkeypatch)
    v1 = publish(w)
    source = source_request(w, v1)
    receipt = w.service.accept_distribution(source, SECRET)["result"]["receipt"]
    replacement = begin(w)
    acknowledgement = ack_request(w, invalidations(w)["invalidations"][0])
    if operation == "publication": w.service.acknowledge(acknowledgement, SECRET)
    other_reg = new_registration(w) if operation == "distribution" else None
    before = manifest(w)
    with _database(w.settings) as conn:
        conn.execute("CREATE TRIGGER publication_fault BEFORE INSERT ON fr_publication_operations BEGIN SELECT RAISE(ABORT,'injected disk failure'); END;")
        conn.commit()
    with pytest.raises(sqlite3.DatabaseError):
        if operation == "distribution": w.service.accept_distribution(source_request(w, v1, reg=other_reg), SECRET)
        elif operation == "confirmation": w.service.confirm(confirm_request(w, receipt), SECRET)
        elif operation == "acknowledgement": w.service.acknowledge(acknowledgement, SECRET)
        else: finish(w, replacement)
    w.service = fixture_service(w.settings)
    assert manifest(w) == before
    with _database(w.settings) as conn:
        assert conn.execute("SELECT COUNT(*) FROM fr_invalidation_acks").fetchone()[0] == int(operation == "publication")
        assert conn.execute("SELECT COUNT(*) FROM fr_publication_recipients").fetchone()[0] == 1


def test_new_004_migration_preserves_predecessor_and_rolls_back_all_new_tables(tmp_path, monkeypatch):
    sources = migrations.migration_sources
    path = tmp_path/"predecessor.sqlite3"
    monkeypatch.setattr(migrations, "migration_sources", lambda: sources()[:3])
    with closing(connect(path, 5000)) as conn:
        run_migrations(conn); migrations.run_frame_relay_migrations(conn)
        old = [tuple(row) for row in conn.execute("SELECT * FROM fr_schema_migrations ORDER BY version")]
        destination = conn.execute("SELECT destination_id FROM fr_destination").fetchone()[0]
    monkeypatch.setattr(migrations, "migration_sources", sources)
    official = migrations.PUBLICATION_SCHEMA
    broken = tmp_path/"broken004.sql"; broken.write_text(official.read_text()+"\nSELECT * FROM nonexistent;\n")
    monkeypatch.setattr(migrations, "PUBLICATION_SCHEMA", broken)
    with closing(connect(path, 5000)) as conn:
        with pytest.raises(sqlite3.DatabaseError): migrations.run_frame_relay_migrations(conn)
        assert conn.execute("SELECT name FROM sqlite_master WHERE name='fr_publication_heads'").fetchone() is None
        assert [tuple(row) for row in conn.execute("SELECT * FROM fr_schema_migrations ORDER BY version")] == old
    monkeypatch.setattr(migrations, "PUBLICATION_SCHEMA", official)
    with closing(connect(path, 5000)) as conn:
        migrations.run_frame_relay_migrations(conn)
        assert [tuple(row) for row in conn.execute("SELECT * FROM fr_schema_migrations ORDER BY version")][:3] == old
        assert conn.execute("SELECT destination_id FROM fr_destination").fetchone()[0] == destination


@pytest.mark.parametrize("path", ["/preview", "/results/unknown", "/preview-confirmation"])
def test_old_http_entries_without_version_header_never_deliver_or_confirm_fr_asset(tmp_path, monkeypatch, path):
    w = world(tmp_path, monkeypatch)
    publish(w)
    from app.main import app
    with TestClient(app) as legacy:
        call = legacy.post if path.endswith("confirmation") else legacy.get
        result = call(f"/assets/{w.seed['asset_id']}"+path, headers={"Authorization": "Bearer storage-test-bootstrap"})
    assert result.status_code in (409, 503)
    assert MOV[:20] not in result.content
    with _database(w.settings) as conn:
        asset = conn.execute("SELECT * FROM assets WHERE id=?", (w.seed["asset_id"],)).fetchone()
        assert asset["active_processed_result_id"] is None and asset["review_status"] != "preview_confirmed"


def test_direct_legacy_read_confirmation_and_pointer_helpers_reject_managed_asset(tmp_path, monkeypatch):
    w = world(tmp_path, monkeypatch)
    from app.services.preview_stream import open_preview_stream
    from app.services.processed_result_stream import open_processed_result_stream
    from app.services.asset_read import confirm_preview
    from app.services.phase2b_migration import _execute_phase2b_sql, Phase2BMigrationError
    for method, kwargs in ((open_preview_stream, {"range_header": None}),
            (open_processed_result_stream, {"range_header": None, "result_id": "unknown"}), (confirm_preview, {})):
        with pytest.raises(StorageError): method(settings=w.settings, asset_id=w.seed["asset_id"], **kwargs)
    with _database(w.settings) as conn:
        with pytest.raises(Phase2BMigrationError, match="legacy_migration_forbidden"):
            _execute_phase2b_sql(conn, fault_injector=None)
        with pytest.raises(sqlite3.DatabaseError, match="publication ledger"):
            conn.execute("UPDATE assets SET active_processed_result_id='legacy' WHERE id=?", (w.seed["asset_id"],))
        conn.rollback()
        with pytest.raises(sqlite3.DatabaseError, match="confirmation ledger"):
            conn.execute("UPDATE assets SET review_status='preview_confirmed' WHERE id=?", (w.seed["asset_id"],))
        conn.rollback()


@pytest.mark.parametrize("body", [b'{"schema_version":"fr-publication-v1","schema_version":"fr-publication-v1"}', b'\xff', b'{"x":NaN}', b'[]'])
def test_wire_rejects_duplicate_non_utf8_nonfinite_and_nonobject_json(tmp_path, monkeypatch, body):
    w = world(tmp_path, monkeypatch)
    with client(w) as http: result = http.post(PREFIX+"/manifest", content=body, headers=headers())
    assert result.status_code == 422


@pytest.mark.parametrize("change", ["unknown_json", "duplicate_query", "unknown_query", "padded_header", "changed_gate", "changed_range"])
def test_wire_exact_requests_reject_normalization_and_substitution(tmp_path, monkeypatch, change):
    w = world(tmp_path, monkeypatch)
    request = accepted_read(w, publish(w))[2]
    kwargs = get_kwargs(request)
    with client(w) as http:
        if change == "unknown_json":
            result = http.post(PREFIX+"/distributions", json={**request, "unknown": True}, headers=headers())
        else:
            if change == "duplicate_query": kwargs["params"] = list(kwargs["params"].items()) + [("registration_id", w.reg["registration_id"])]
            elif change == "unknown_query": kwargs["params"]["ignored"] = "no"
            elif change == "padded_header": kwargs["headers"]["X-FrameRelay-Distribution-ID"] += "="
            elif change == "changed_gate": kwargs["headers"]["X-FrameRelay-Attempt-ID"] = header_id("other-attempt")
            else: kwargs["headers"]["Range"] = "bytes=0-30"
            result = http.get(PREFIX+"/media/"+request["rendition"]["rendition_id"], **kwargs)
    assert result.status_code in (409, 422) and MOV[:20] not in result.content
    with _database(w.settings) as conn: assert conn.execute("SELECT COUNT(*) FROM fr_get_admissions").fetchone()[0] == 0


def test_canonical_http_get_single_consumption_and_matching_quicktime_identity(tmp_path, monkeypatch):
    w = world(tmp_path, monkeypatch)
    request = accepted_read(w, publish(w))[2]
    with client(w) as http:
        url = PREFIX+"/media/"+request["rendition"]["rendition_id"]
        result = http.get(url, **get_kwargs(request))
        assert result.status_code == 206 and result.content == MOV[:32]
        assert result.headers["Content-Type"] == "video/quicktime"
        assert result.headers["X-FrameRelay-Distribution-ID"] == header_id(request["operation_id"])
        again = http.get(url, **get_kwargs(request))
        assert again.status_code == 409 and again.json()["code"] == "publication_get_consumed"
        assert MOV[:20] not in again.content and manifest(w)["current"] == request["rendition"]


def test_pinned_response_closes_fd_even_when_asgi_send_fails_before_body(tmp_path, monkeypatch):
    import asyncio
    from starlette.requests import ClientDisconnect
    w = world(tmp_path, monkeypatch)
    accepted = open_request(w, accepted_read(w, publish(w))[2])
    response = PinnedResponse(accepted)
    async def receive(): return {"type": "http.disconnect"}
    async def send(_message): raise OSError("disconnected before body")
    with pytest.raises((OSError, ClientDisconnect)):
        asyncio.run(response({"type": "http", "asgi": {"spec_version": "2.4"}}, receive, send))
    assert accepted.closed and accepted.source.closed and accepted.delivered_bytes == 0


@pytest.mark.parametrize("data", [b"", b"\0\0\0\x14ftypqt  ", b"\0\1\0\x04ftypqt  \0\0\0\0", b"\0\0\0\x13ftypqt  \0\0\0\0xxx", b"\0\0\0\x10ftypnope\0\0\0\0"])
def test_container_identification_rejects_truncation_length_and_unknown_brand(data):
    with pytest.raises(PublicationError): container_type(data, len(data))


def test_opaque_ids_are_losslessly_encoded_and_noncanonical_headers_rejected():
    value = " opaque/日本語:\x01 "
    assert parse_header_id(header_id(value)) == value
    for changed in (header_id(value)+"=", "a", "***", "YQ==", "YR"):
        with pytest.raises(PublicationError): parse_header_id(changed)


def test_invalidation_pagination_is_bounded_progresses_and_repolls_lower_ids(tmp_path, monkeypatch):
    w = world(tmp_path, monkeypatch)
    v1 = publish(w); w.service.accept_distribution(source_request(w, v1), SECRET)
    begin(w, invalidation_id="z-first")
    first = invalidations(w, limit="1")
    assert len(first["invalidations"]) == 1 and first["next_after"] is None
    # Independent original gets its own publication/replacement; old unfinished
    # registrations do not stop another original's work.
    seed = seed_candidate(w.settings, w.reg, SECRET, MOV, "another-original", str(uuid4()))
    other = SimpleNamespace(settings=w.settings, reg=w.reg, seed=seed, service=w.service)
    v_other = publish(other); other.service.accept_distribution(source_request(other, v_other), SECRET)
    begin(other, invalidation_id="a-later")
    assert invalidations(w, after="z-first")["invalidations"] == []
    page = invalidations(w, limit="1")
    assert page["invalidations"][0]["invalidation_id"] == "a-later" and page["next_after"] == "a-later"
    next_page = invalidations(w, after=page["next_after"], limit="1")
    assert next_page["invalidations"][0]["invalidation_id"] == "z-first" and next_page["next_after"] is None
    assert invalidations(w, after="z-first")["next_after"] is None


def test_maximum_escaped_invalidation_fits_single_page_and_exact_bytes_are_retained(tmp_path, monkeypatch):
    w = world(tmp_path, monkeypatch)
    rendition = publish(w)
    maximum = "\x01"*1024
    rendition["original"]["capture_id"] = maximum
    for key in ("input_log_identity", "transform_asset_identity", "transform_asset_version", "output_configuration_identity", "conversion_version"):
        rendition[key] = maximum
    record = {"invalidation_id": maximum, "rendition": rendition,
        "registration": {"destination_id": maximum, "registration_id": maximum, "generation": str((1<<64)-1)},
        "invalidation_generation": str((1<<64)-1)}
    wire.Invalidation.model_validate(record)
    values = [{**deepcopy(record), "invalidation_id": maximum[:-1]+chr(index+2)} for index in range(9)]
    monkeypatch.setattr(repository, "pending_invalidations", lambda *_args: values)
    request = {"schema_version": wire.VERSION, "registration": w.reg, "after_invalidation_id": maximum, "limit": "8"}
    encoded = w.service.invalidations(request, SECRET)
    assert len(json_bytes({"schema_version": wire.VERSION, "request": request,
        "result": {"invalidations": [record], "next_after": maximum}})) < 196_608
    result = json.loads(encoded)["result"]
    assert 0 < len(result["invalidations"]) < 8 and result["next_after"] == result["invalidations"][-1]["invalidation_id"]
    from app.api.frame_relay_publication import response
    assert response(encoded).body is encoded and len(encoded) <= 196_608


@pytest.mark.parametrize("stage", ["before_commit", "after_commit"])
def test_replacement_publication_fault_reopen_and_historical_ack_replay(tmp_path, monkeypatch, stage):
    w = world(tmp_path, monkeypatch)
    v1 = publish(w)
    w.service.accept_distribution(source_request(w, v1), SECRET)
    replacement = begin(w)
    ack = ack_request(w, invalidations(w)["invalidations"][0])
    acknowledged = w.service.acknowledge(ack, SECRET)
    request = {"operation_id": str(uuid4()), "replacement_id": replacement["replacement_id"],
               "expected_revision": int(manifest(w)["revision"])}
    def fault(step):
        if step == stage: raise Crash()
    with pytest.raises(Crash): w.service.publish_replacement(**request, fault=fault)
    w.service = fixture_service(w.settings)
    expected = v1 if stage == "before_commit" else replacement["rendition"]
    assert manifest(w)["current"] == expected
    result = w.service.publish_replacement(**request)
    assert w.service.publish_replacement(**request) == result
    assert w.service.acknowledge(ack, SECRET) == acknowledged
    assert manifest(w)["current"] == replacement["rendition"]


@pytest.mark.parametrize("field", ["invalidation_id", "invalidation_generation", "rendition", "local_commit"])
def test_wrong_or_reused_ack_payload_never_satisfies_required_registration(tmp_path, monkeypatch, field):
    w = world(tmp_path, monkeypatch)
    v1 = publish(w); w.service.accept_distribution(source_request(w, v1), SECRET)
    replacement = begin(w)
    original = ack_request(w, invalidations(w)["invalidations"][0])
    changed = deepcopy(original)
    if field == "local_commit":
        w.service.acknowledge(original, SECRET)
        changed["acknowledgement"]["local_commit"] = {"previous_revision": "20", "committed_revision": "21"}
    elif field == "rendition": changed["acknowledgement"]["invalidation"]["rendition"]["conversion_version"] = "other"
    else: changed["acknowledgement"]["invalidation"][field] = "999" if field.endswith("generation") else str(uuid4())
    with pytest.raises(PublicationError): w.service.acknowledge(changed, SECRET)
    if field != "local_commit":
        with pytest.raises(PublicationError, match="awaiting_acknowledgements"): finish(w, replacement)


def test_sqlite_get_admission_failure_closes_pinned_fd_and_leaves_ticket_unused(tmp_path, monkeypatch):
    from contextlib import contextmanager
    w = world(tmp_path, monkeypatch)
    request = accepted_read(w, publish(w))[2]
    observed = []
    real = files.verified_reader
    @contextmanager
    def tracked(*args, **kwargs):
        with real(*args, **kwargs) as value:
            observed.append(value[0])
            yield value
    monkeypatch.setattr(files, "verified_reader", tracked)
    with _database(w.settings) as conn:
        conn.execute("CREATE TRIGGER admission_fault BEFORE INSERT ON fr_get_admissions BEGIN SELECT RAISE(ABORT,'injected admission failure'); END;")
        conn.commit()
    with pytest.raises(sqlite3.DatabaseError): open_request(w, request)
    assert len(observed) == 1 and observed[0].closed
    with _database(w.settings) as conn:
        assert conn.execute("SELECT COUNT(*) FROM fr_get_admissions").fetchone()[0] == 0
        conn.execute("DROP TRIGGER admission_fault"); conn.commit()
    assert b"".join(open_request(w, request)) == MOV[:32]
