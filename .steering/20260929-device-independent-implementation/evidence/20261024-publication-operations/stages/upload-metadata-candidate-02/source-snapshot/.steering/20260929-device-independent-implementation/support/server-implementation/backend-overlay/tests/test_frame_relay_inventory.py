"""Saved identity discovery across registrations; real SQLite/files, metadata only."""
import base64
import hashlib
import json
from uuid import uuid4

from fastapi.testclient import TestClient
from pydantic import ValidationError
import pytest

from app.main import app
from app.repositories import frame_relay_storage as repository
from app.repositories import registrations
from app.repositories.frame_relay_storage import StorageError
from app.repositories.jobs import claim_next_job
from app.schemas.frame_relay_storage import OriginalInventoryRequest, StorageBindingRequest
from app.services import frame_relay_finalize as finalize
from app.services import frame_relay_storage as service
from app.services import frame_relay_files as files
from test_frame_relay_storage import _setup, _database, _receive, SECRET


PREFIX = "/frame-relay/v1/uploads/inventory"
NEW_SECRET = "b" * 64


def complete(settings, request, value):
    _receive(settings, request, value)
    service.finalize(settings, value["session_id"], request, SECRET)
    with _database(settings) as conn:
        job = claim_next_job(conn, settings.job_lease_seconds, ("fr_upload_finalize",))
    assert job is not None and job["job_type"] == "fr_upload_finalize"
    assert finalize.process_finalize(settings=settings, job=job)


def query(settings, *, secret=NEW_SECRET, limit="32"):
    with _database(settings) as conn:
        destination = registrations.destination_identity(conn)
        receipt = registrations.register(conn, destination_id=destination, operation_id=str(uuid4()), secret=secret)
    return {"destination_id": destination, "registration_id": receipt["registration_id"],
        "registration_generation": receipt["generation"], "limit": limit}


def saved(settings, original_request, *, capture=None, generation="1"):
    request = {**original_request, "operation_id": str(uuid4()),
        "capture_id": capture if capture is not None else str(uuid4()), "content_generation": generation}
    value = service.create(settings, request, SECRET)
    complete(settings, request, value)
    return request, value


def original(request):
    return {key: request[key] for key in ("capture_id", "content_generation", "sha256", "byte_count")}


def headers(secret=NEW_SECRET):
    return {"Authorization": "Bearer storage-test-bootstrap", "X-FrameRelay-Registration-Secret": secret}


def tables(settings):
    with _database(settings) as conn:
        names = [row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")]
        return {name: sorted(json.dumps(dict(row), sort_keys=True) for row in conn.execute('SELECT * FROM "' + name + '"'))
            for name in names}


def media(settings):
    return {str(path.relative_to(settings.media_root)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in sorted(settings.media_root.rglob("*")) if path.is_file()}


def tamper_immutable(conn, trigger, statement, parameters):
    # A fresh test DB simulates corruption then restores the exact schema SQL;
    # no product API exposes this seam or changes the immutable ledger rules.
    sql = conn.execute("SELECT sql FROM sqlite_master WHERE type='trigger' AND name=?", (trigger,)).fetchone()[0]
    conn.execute("DROP TRIGGER " + trigger)
    conn.execute(statement, parameters)
    conn.execute(sql)


def test_new_registration_discovers_old_saved_identity_without_old_secret_or_adoption(monkeypatch, tmp_path):
    settings, request, value = _setup(tmp_path, monkeypatch)
    complete(settings, request, value)
    current = query(settings)
    before = tables(settings)
    response = service.original_inventory(settings, current, NEW_SECRET)
    assert response == {**{key: current[key] for key in ("destination_id", "registration_id", "registration_generation")},
        "request_cursor": None, "items": [original(request)], "next_cursor": None}
    assert current["registration_id"] != request["registration_id"]
    with _database(settings) as conn:
        assert registrations.authenticate_registration(conn, destination_id=request["destination_id"],
            registration_id=request["registration_id"], generation=int(request["registration_generation"]), secret=SECRET)
    assert tables(settings) == before
    assert all(not before[name] for name in before if name.startswith(("fr_publication", "fr_distribution", "fr_confirmation", "fr_invalidation")))


@pytest.mark.parametrize("field,value", [
    ("destination_id", "00000000-0000-0000-0000-000000000001"),
    ("registration_id", "00000000-0000-0000-0000-000000000002"),
    ("registration_generation", "2"),
])
def test_inventory_authenticates_current_exact_destination_registration_and_generation(monkeypatch, tmp_path, field, value):
    settings, request, binding = _setup(tmp_path, monkeypatch)
    complete(settings, request, binding)
    current = query(settings)
    changed = {**current, field: value}
    if changed == current:
        changed[field] = "3"
    before = tables(settings)
    with pytest.raises(registrations.RegistrationError):
        service.original_inventory(settings, changed, NEW_SECRET)
    assert tables(settings) == before


@pytest.mark.parametrize("secret", ["a" * 64, "c" * 64, "", "short"])
def test_old_or_invalid_secret_cannot_authorize_new_registration_inventory(monkeypatch, tmp_path, secret):
    settings, request, value = _setup(tmp_path, monkeypatch)
    complete(settings, request, value)
    current = query(settings)
    with pytest.raises(registrations.RegistrationError):
        service.original_inventory(settings, current, secret)


def test_metadata_endpoint_precedes_session_route_and_returns_no_media_or_paths(monkeypatch, tmp_path):
    settings, request, value = _setup(tmp_path, monkeypatch)
    complete(settings, request, value)
    current = query(settings)
    sentinel = settings.media_root / "unrelated-sentinel.bin"
    sentinel.write_bytes(b"retained external fixture")
    before, before_media = tables(settings), media(settings)

    def deny_media(*args, **kwargs):
        raise AssertionError("Metadata discovery attempted media access")

    monkeypatch.setattr(files, "read_all", deny_media)
    monkeypatch.setattr(files, "current_fingerprint", deny_media)
    client = TestClient(app)
    response = client.get(PREFIX, params=current, headers=headers())
    assert response.status_code == 200
    assert response.headers["cache-control"] == "no-store"
    assert response.headers["content-type"] == "application/json"
    assert response.json()["items"] == [original(request)]
    assert len(response.content) <= 256 * 1024
    for forbidden in (SECRET, NEW_SECRET, "storage-test-bootstrap", "originals/", "final_path", "evidence_id",
                      request["registration_id"], request["operation_id"]):
        assert forbidden not in response.text
    assert tables(settings) == before and media(settings) == before_media
    assert client.get(PREFIX, params=current).status_code == 401
    assert client.get(PREFIX, params=current, headers=headers(SECRET)).status_code in (401, 403)


def test_only_completed_evidence_backed_rows_are_listed_without_conversion_or_publication(monkeypatch, tmp_path):
    settings, request, value = _setup(tmp_path, monkeypatch)
    complete(settings, request, value)
    incomplete_request = {**request, "operation_id": str(uuid4()), "capture_id": "receiving"}
    service.create(settings, incomplete_request, SECRET)
    cancelled = {**request, "operation_id": str(uuid4()), "capture_id": "cancelled"}
    cancelled_value = service.create(settings, cancelled, SECRET)
    service.cancel(settings, cancelled_value["session_id"], cancelled, SECRET)
    failed = {**request, "operation_id": str(uuid4()), "capture_id": "failed"}
    failed_value = service.create(settings, failed, SECRET)
    with _database(settings) as conn:
        with conn:
            conn.execute("UPDATE fr_upload_states SET status='failed' WHERE session_id=?", (failed_value["session_id"],))
    current = query(settings)
    before = tables(settings)
    assert service.original_inventory(settings, current, NEW_SECRET)["items"] == [original(request)]
    assert tables(settings) == before
    with _database(settings) as conn:
        assert conn.execute("SELECT status FROM jobs WHERE job_type='fr_conversion'").fetchall()[0][0] == "queued"


def test_pages_are_bounded_keysets_with_replay_empty_tail_and_no_record_deletion(monkeypatch, tmp_path):
    settings, request, value = _setup(tmp_path, monkeypatch)
    complete(settings, request, value)
    expected = {value["session_id"]: original(request)}
    for index in range(4):
        next_request, next_value = saved(settings, request, capture="page-" + str(index))
        expected[next_value["session_id"]] = original(next_request)
    current = query(settings, limit="2")
    before = tables(settings)
    first = service.original_inventory(settings, current, NEW_SECRET)
    assert len(first["items"]) == 2 and first["next_cursor"]
    assert service.original_inventory(settings, current, NEW_SECRET) == first
    second = service.original_inventory(settings, {**current, "cursor": first["next_cursor"]}, NEW_SECRET)
    assert second["request_cursor"] == first["next_cursor"] and len(second["items"]) == 2 and second["next_cursor"]
    assert service.original_inventory(settings, {**current, "cursor": first["next_cursor"]}, NEW_SECRET) == second
    third = service.original_inventory(settings, {**current, "cursor": second["next_cursor"]}, NEW_SECRET)
    assert len(third["items"]) == 1 and third["next_cursor"] is None
    assert first["items"] + second["items"] + third["items"] == [expected[key] for key in sorted(expected)]
    tail = repository.inventory_cursor({**current, "cursor": None}, max(expected))
    empty = service.original_inventory(settings, {**current, "cursor": tail}, NEW_SECRET)
    assert empty["items"] == [] and empty["next_cursor"] is None and empty["request_cursor"] == tail
    assert tables(settings) == before


@pytest.mark.parametrize("count", [0, 1, 32, 33])
def test_default_page_limit_is_32_with_only_one_bounded_lookahead(monkeypatch, tmp_path, count):
    settings, request, _value = _setup(tmp_path, monkeypatch)
    for index in range(count):
        saved(settings, request, capture="bounded-" + str(index))
    current = query(settings)
    calls = []
    real_binding = repository.binding

    def observed(conn, session_id):
        calls.append(session_id)
        return real_binding(conn, session_id)

    monkeypatch.setattr(repository, "binding", observed)
    page = service.original_inventory(settings, current, NEW_SECRET)
    assert len(page["items"]) == min(count, 32)
    assert len(calls) == min(count, 33)
    assert (page["next_cursor"] is not None) == (count == 33)
    if page["next_cursor"] is not None:
        calls.clear()
        tail = service.original_inventory(settings, {**current, "cursor": page["next_cursor"]}, NEW_SECRET)
        assert len(tail["items"]) == 1 and tail["next_cursor"] is None
        assert len(calls) == 2  # One exact boundary check plus one remaining item.


@pytest.mark.parametrize("change", ["registration", "generation", "destination", "limit", "unknown", "extra", "alias", "malformed"])
def test_cursor_is_canonical_scoped_and_requires_an_existing_saved_boundary(monkeypatch, tmp_path, change):
    settings, request, value = _setup(tmp_path, monkeypatch)
    complete(settings, request, value)
    saved(settings, request)
    current = query(settings, limit="1")
    first = service.original_inventory(settings, current, NEW_SECRET)
    token = first["next_cursor"]
    assert token
    decoded = json.loads(base64.urlsafe_b64decode(token + "=" * (-len(token) % 4)))
    if change == "alias":
        token = base64.urlsafe_b64encode(json.dumps(decoded, indent=1).encode()).decode().rstrip("=")
    elif change == "malformed":
        token = "_"
    else:
        if change == "registration": decoded["registration_id"] = str(uuid4())
        elif change == "generation": decoded["registration_generation"] = "3"
        elif change == "destination": decoded["destination_id"] = str(uuid4())
        elif change == "limit": decoded["limit"] = "2"
        elif change == "unknown": decoded["after"] = str(uuid4())
        elif change == "extra": decoded["ignored"] = True
        token = base64.urlsafe_b64encode(repository.canonical(decoded).encode()).decode().rstrip("=")
    with pytest.raises(StorageError, match="inventory_cursor_invalid"):
        service.original_inventory(settings, {**current, "cursor": token}, NEW_SECRET)


def test_receiving_row_cannot_be_forged_into_a_saved_cursor_boundary(monkeypatch, tmp_path):
    settings, request, value = _setup(tmp_path, monkeypatch)
    current = query(settings)
    token = repository.inventory_cursor({**current, "cursor": None}, value["session_id"])
    with pytest.raises(StorageError, match="inventory_evidence_missing"):
        service.original_inventory(settings, {**current, "cursor": token}, NEW_SECRET)


def test_opaque_capture_duplicate_identity_and_conflicting_content_are_never_normalized_or_collapsed(monkeypatch, tmp_path):
    settings, request, _value = _setup(tmp_path, monkeypatch)
    capture = "  ../試験/Capture?x=1#原本  "
    values = [saved(settings, request, capture=capture)[0], saved(settings, request, capture=capture)[0],
        saved(settings, request, capture=capture, generation=str((1 << 64) - 1))[0]]
    current = query(settings)
    response = service.original_inventory(settings, current, NEW_SECRET)
    assert len(response["items"]) == 3
    assert all(item["capture_id"] == capture for item in response["items"])
    assert response["items"].count(original(values[0])) == 2
    assert original(values[2]) in response["items"]


@pytest.mark.parametrize("mode", ["missing_state", "state_evidence", "asset", "job", "claim", "binding", "evidence", "missing_evidence", "noncompleted_evidence"])
def test_corrupt_completed_or_evidence_rows_fail_the_entire_page_instead_of_disappearing(monkeypatch, tmp_path, mode):
    settings, request, value = _setup(tmp_path, monkeypatch)
    complete(settings, request, value)
    current = query(settings)
    with _database(settings) as conn:
        with conn:
            if mode == "missing_state":
                conn.execute("DELETE FROM fr_upload_states WHERE session_id=?", (value["session_id"],))
            elif mode == "state_evidence":
                conn.execute("UPDATE fr_upload_states SET evidence_id=? WHERE session_id=?", (str(uuid4()), value["session_id"]))
            elif mode == "asset":
                conn.execute("UPDATE assets SET server_sha256=? WHERE id=(SELECT asset_id FROM fr_upload_states WHERE session_id=?)", ("f" * 64, value["session_id"]))
            elif mode == "job":
                conn.execute("UPDATE jobs SET status='failed' WHERE id=(SELECT finalize_job_id FROM fr_upload_states WHERE session_id=?)", (value["session_id"],))
            elif mode == "claim":
                conn.execute("UPDATE fr_job_claims SET token=? WHERE session_id=?", (str(uuid4()), value["session_id"]))
            elif mode == "binding":
                tamper_immutable(conn, "fr_binding_no_update", "UPDATE fr_upload_bindings SET content_generation='01' WHERE session_id=?", (value["session_id"],))
            elif mode == "evidence":
                tamper_immutable(conn, "fr_evidence_no_update", "UPDATE fr_storage_evidence SET sha256=? WHERE session_id=?", ("e" * 64, value["session_id"]))
            elif mode == "missing_evidence":
                tamper_immutable(conn, "fr_evidence_no_delete", "DELETE FROM fr_storage_evidence WHERE session_id=?", (value["session_id"],))
            elif mode == "noncompleted_evidence":
                conn.execute("UPDATE fr_upload_states SET status='receiving' WHERE session_id=?", (value["session_id"],))
    before = tables(settings)
    with pytest.raises(StorageError):
        service.original_inventory(settings, current, NEW_SECRET)
    response = TestClient(app).get(PREFIX, params=current, headers=headers())
    assert response.status_code == 409 and "items" not in response.json()
    assert tables(settings) == before


@pytest.mark.parametrize("field,value", [
    ("limit", "0"), ("limit", "33"), ("limit", "01"), ("limit", 32),
    ("registration_generation", "0"), ("registration_generation", "01"),
    ("registration_generation", "9223372036854775808"), ("registration_generation", True),
    ("cursor", ""), ("cursor", "a" * 641), ("cursor", "日本語"),
])
def test_inventory_request_rejects_aliases_unbounded_values_and_overflow(monkeypatch, tmp_path, field, value):
    settings, _request, _binding = _setup(tmp_path, monkeypatch)
    current = query(settings)
    with pytest.raises(ValidationError):
        OriginalInventoryRequest.model_validate({**current, field: value})


def test_duplicate_or_unknown_query_fields_are_rejected_without_reflecting_values(monkeypatch, tmp_path):
    settings, _request, _binding = _setup(tmp_path, monkeypatch)
    current = query(settings)
    client = TestClient(app)
    pairs = list(current.items())
    for params in (pairs + [("limit", "1")], pairs + [("private_path", "redacted-sentinel")]):
        response = client.get(PREFIX, params=params, headers=headers())
        assert response.status_code == 422 and "redacted-sentinel" not in response.text


def test_oversized_capture_is_retained_by_upload_contract_but_fails_metadata_page(monkeypatch, tmp_path):
    settings, request, _value = _setup(tmp_path, monkeypatch)
    large = "界" * 683
    modified = {**request, "capture_id": large}
    assert StorageBindingRequest.model_validate(modified).capture_id == large
    saved(settings, request, capture=large)
    current = query(settings)
    before = tables(settings)
    with pytest.raises(StorageError, match="inventory_item_too_large"):
        service.original_inventory(settings, current, NEW_SECRET)
    assert tables(settings) == before


def test_escaped_response_byte_limit_rejects_whole_page_without_partial_items(monkeypatch, tmp_path):
    settings, request, _value = _setup(tmp_path, monkeypatch)
    for index in range(32):
        saved(settings, request, capture="\0" * 2040 + str(index))
    current = query(settings)
    before = tables(settings)
    with pytest.raises(StorageError, match="inventory_response_too_large"):
        service.original_inventory(settings, current, NEW_SECRET)
    assert tables(settings) == before


def test_broken_schema_never_becomes_an_empty_inventory_success(monkeypatch, tmp_path):
    settings, _request, _value = _setup(tmp_path, monkeypatch)
    current = query(settings)
    with _database(settings) as conn:
        with conn:
            conn.execute("DROP TABLE fr_upload_states")
    with pytest.raises(StorageError) as caught:
        service.original_inventory(settings, current, NEW_SECRET)
    assert caught.value.code == "storage_schema_unavailable"
    response = TestClient(app).get(PREFIX, params=current, headers=headers())
    assert response.status_code == 409
    assert response.json() == {"code": "storage_schema_unavailable", "retryable": False}
    assert "items" not in response.json()
