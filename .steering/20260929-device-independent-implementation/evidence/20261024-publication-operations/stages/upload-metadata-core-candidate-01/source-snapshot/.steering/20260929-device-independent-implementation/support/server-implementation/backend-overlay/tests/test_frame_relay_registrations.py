"""Synthetic registration identities; real disposable SQLite and ASGI requests."""
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
import json
import sqlite3
from threading import Barrier
from uuid import uuid4

from fastapi.testclient import TestClient
from pydantic import ValidationError
import pytest

from app.db.connection import connect
from app.db import frame_relay_migrations as migrations
from app.db.migrations import run_migrations
from app.main import app
from app.repositories import registrations as repository
from app.repositories.assets import insert_asset
from app.repositories.jobs import insert_job
from app.schemas.registrations import RegistrationReceipt
from app.services import registrations as service


SECRET = "a" * 64
OTHER_SECRET = "b" * 64
PREFIX = "/frame-relay/v1"


def _headers(secret=SECRET):
    result = {"Authorization": "Bearer disposable-bootstrap"}
    if secret is not None:
        result["X-FrameRelay-Registration-Secret"] = secret
    return result


def _environment(monkeypatch, tmp_path):
    path = tmp_path / "registration.sqlite3"
    monkeypatch.setenv("DATABASE_PATH", str(path))
    monkeypatch.setenv("MEDIA_ROOT", str(tmp_path / "media"))
    monkeypatch.setenv("API_TOKEN", "disposable-bootstrap")
    return path


def _database(tmp_path):
    path = tmp_path / "registration.sqlite3"
    with closing(connect(path, 5000)) as conn:
        run_migrations(conn)
        migrations.run_frame_relay_migrations(conn)
        destination = repository.destination_identity(conn)
    return path, destination


def _intent(destination):
    return {"destination_id": destination, "operation_id": str(uuid4())}


def _lookup(client, intent, headers=None):
    return client.get(PREFIX + "/registration-intents/" + intent["operation_id"],
                      params={"destination_id": intent["destination_id"]},
                      headers=_headers() if headers is None else headers)


def _capability(client):
    response = client.get(PREFIX + "/capabilities", headers=_headers(None))
    assert response.status_code == 200
    assert response.headers["cache-control"] == "no-store"
    assert response.json()["capabilities"] == ["registration-intent-v1"]
    return response.json()


def _legacy_snapshot(conn):
    schema = [tuple(row) for row in conn.execute(
        "SELECT type, name, tbl_name, sql FROM sqlite_master "
        "WHERE name NOT LIKE 'fr_%' AND tbl_name NOT LIKE 'fr_%' ORDER BY name"
    )]
    tables = [row[1] for row in schema if row[0] == "table"]
    rows = {name: [tuple(row) for row in conn.execute('SELECT * FROM "' + name + '" ORDER BY rowid')]
            for name in tables}
    return schema, rows


def test_capabilities_identity_is_persistent_and_does_not_advertise_future_work(monkeypatch, tmp_path):
    _environment(monkeypatch, tmp_path)
    with TestClient(app) as client:
        first = _capability(client)
    with TestClient(app) as client:
        assert _capability(client) == first
    assert first["protocol_version"] == 1


def test_api_replay_and_response_loss_recover_same_receipt_after_restart(monkeypatch, tmp_path):
    path = _environment(monkeypatch, tmp_path)
    with TestClient(app) as client:
        intent = _intent(_capability(client)["destination_id"])
        first = client.post(PREFIX + "/registrations", json=intent, headers=_headers())
        assert first.status_code == 200
        receipt = first.json()  # Simulate losing this response before client commit.
    with TestClient(app) as client:
        recovered = _lookup(client, intent)
        replay = client.post(PREFIX + "/registrations", json=intent, headers=_headers())
        assert recovered.status_code == replay.status_code == 200
        assert recovered.json() == replay.json() == receipt
    assert receipt["generation"] == "1"
    with closing(connect(path, 5000)) as conn:
        assert conn.execute("SELECT COUNT(*) FROM fr_registrations").fetchone()[0] == 1


def test_api_all_routes_require_bootstrap_authentication(monkeypatch, tmp_path):
    _environment(monkeypatch, tmp_path)
    with TestClient(app) as client:
        intent = _intent(_capability(client)["destination_id"])
        for headers in ({}, {"Authorization": "Bearer wrong", "X-FrameRelay-Registration-Secret": SECRET}):
            assert client.get(PREFIX + "/capabilities", headers=headers).status_code == 401
            assert client.post(PREFIX + "/registrations", json=intent, headers=headers).status_code == 401
            assert _lookup(client, intent, headers).status_code == 401


def test_api_secret_required_and_never_reflected(monkeypatch, tmp_path, caplog):
    path = _environment(monkeypatch, tmp_path)
    with TestClient(app) as client:
        intent = _intent(_capability(client)["destination_id"])
        for secret in (None, "invalid-private-credential", "A" * 64, "a" * 63):
            headers = _headers(secret)
            for response in (client.post(PREFIX + "/registrations", json=intent, headers=headers),
                             _lookup(client, intent, headers)):
                assert response.status_code == 401
                assert secret is None or secret not in response.text
        valid = client.post(PREFIX + "/registrations", json=intent, headers=_headers())
        assert valid.status_code == 200 and SECRET not in valid.text
    with closing(connect(path, 5000)) as conn:
        dump = "\n".join(conn.iterdump())
    assert SECRET not in dump and SECRET not in caplog.text
    assert "invalid-private-credential" not in caplog.text


def test_api_payload_extra_fields_and_noncanonical_ids_rejected_without_reflection(monkeypatch, tmp_path):
    _environment(monkeypatch, tmp_path)
    with TestClient(app) as client:
        intent = _intent(_capability(client)["destination_id"])
        invalid_payloads = [dict(intent, secret="private-body-secret"), dict(intent, generation=2),
                            dict(intent, operation_id=intent["operation_id"].upper()),
                            dict(intent, destination_id="not-an-id"), dict(intent, operation_id=42)]
        for payload in invalid_payloads:
            response = client.post(PREFIX + "/registrations", json=payload, headers=_headers())
            assert response.status_code == 422
            assert response.json() == {"code": "validation_error", "retryable": False}
        assert _lookup(client, intent).status_code == 404


def test_api_existing_intent_cannot_be_claimed_with_new_secret(monkeypatch, tmp_path):
    path = _environment(monkeypatch, tmp_path)
    with TestClient(app) as client:
        intent = _intent(_capability(client)["destination_id"])
        first = client.post(PREFIX + "/registrations", json=intent, headers=_headers()).json()
        for response in (client.post(PREFIX + "/registrations", json=intent, headers=_headers(OTHER_SECRET)),
                         _lookup(client, intent, _headers(OTHER_SECRET))):
            assert response.status_code == 403
            assert response.json()["code"] == "registration_credentials_invalid"
            assert OTHER_SECRET not in response.text
        assert _lookup(client, intent).json() == first
    with closing(connect(path, 5000)) as conn:
        assert conn.execute("SELECT last_generation FROM fr_destination").fetchone()[0] == 1


def test_api_wrong_destination_is_not_absence_or_new_registration(monkeypatch, tmp_path):
    path = _environment(monkeypatch, tmp_path)
    with TestClient(app) as client:
        intent = _intent(str(uuid4()))
        for response in (client.post(PREFIX + "/registrations", json=intent, headers=_headers()),
                         _lookup(client, intent)):
            assert response.status_code == 409
            assert response.json()["code"] == "destination_mismatch"
    with closing(connect(path, 5000)) as conn:
        assert conn.execute("SELECT COUNT(*) FROM fr_registrations").fetchone()[0] == 0


def test_api_only_verified_absence_returns_bound_not_executed(monkeypatch, tmp_path):
    _environment(monkeypatch, tmp_path)
    with TestClient(app) as client:
        intent = _intent(_capability(client)["destination_id"])
        response = _lookup(client, intent)
        assert response.status_code == 404
        assert response.json() == dict(intent, code="registration_not_executed", retryable=False)
        assert response.headers["cache-control"] == "no-store"


def test_database_open_failure_is_not_absence(monkeypatch, tmp_path):
    _environment(monkeypatch, tmp_path)
    with TestClient(app) as client:
        intent = _intent(_capability(client)["destination_id"])
        def fail_open(*args):
            raise sqlite3.OperationalError("synthetic DB open failure")
        monkeypatch.setattr(service, "connect", fail_open)
        response = _lookup(client, intent)
        assert response.status_code == 503
        assert response.json() == {"code": "registration_unavailable", "retryable": True}


def test_real_busy_database_does_not_report_registration_success(monkeypatch, tmp_path):
    path = _environment(monkeypatch, tmp_path)
    with TestClient(app) as client:
        intent = _intent(_capability(client)["destination_id"])
        monkeypatch.setenv("SQLITE_BUSY_TIMEOUT_MS", "1")
        with closing(connect(path, 5000)) as locked:
            locked.execute("BEGIN IMMEDIATE")
            response = client.post(PREFIX + "/registrations", json=intent, headers=_headers())
            locked.rollback()
        assert response.status_code == 503
        assert _lookup(client, intent).status_code == 404


def test_corrupt_database_is_not_absence(monkeypatch, tmp_path):
    _environment(monkeypatch, tmp_path)
    with TestClient(app) as client:
        intent = _intent(_capability(client)["destination_id"])
        corrupt = tmp_path / "corrupt.sqlite3"
        corrupt.write_bytes(b"not a SQLite database" * 50)
        monkeypatch.setenv("DATABASE_PATH", str(corrupt))
        assert _lookup(client, intent).status_code == 503


def test_unknown_schema_is_not_absence_and_startup_refuses_it(monkeypatch, tmp_path):
    path = _environment(monkeypatch, tmp_path)
    with TestClient(app) as client:
        intent = _intent(_capability(client)["destination_id"])
        with closing(connect(path, 5000)) as conn, conn:
            conn.execute("INSERT INTO fr_schema_migrations VALUES ('999_unknown', 'unknown')")
        assert _lookup(client, intent).status_code == 503
    with closing(connect(path, 5000)) as conn:
        with pytest.raises(migrations.FrameRelaySchemaError):
            migrations.run_frame_relay_migrations(conn)


def test_parallel_same_intent_creates_one_receipt_and_one_generation(tmp_path):
    path, destination = _database(tmp_path)
    intent = _intent(destination)
    barrier = Barrier(6)
    def create(_):
        with closing(connect(path, 5000)) as conn:
            barrier.wait(timeout=10)
            return repository.register(conn, **intent, secret=SECRET)
    with ThreadPoolExecutor(max_workers=6) as pool:
        receipts = list(pool.map(create, range(6)))
    assert all(receipt == receipts[0] for receipt in receipts)
    with closing(connect(path, 5000)) as conn:
        assert conn.execute("SELECT COUNT(*) FROM fr_registrations").fetchone()[0] == 1
        assert conn.execute("SELECT last_generation FROM fr_destination").fetchone()[0] == 1


def test_parallel_distinct_intents_allocate_strictly_unique_generations(tmp_path):
    path, destination = _database(tmp_path)
    barrier = Barrier(6)
    def create(_):
        with closing(connect(path, 5000)) as conn:
            barrier.wait(timeout=10)
            return repository.register(conn, **_intent(destination), secret=SECRET)
    with ThreadPoolExecutor(max_workers=6) as pool:
        receipts = list(pool.map(create, range(6)))
    assert sorted(int(receipt["generation"]) for receipt in receipts) == list(range(1, 7))
    assert len({receipt["registration_id"] for receipt in receipts}) == 6


def test_before_commit_fault_rolls_back_and_reopen_proves_absence(tmp_path):
    path, destination = _database(tmp_path)
    intent = _intent(destination)
    def fault(boundary):
        if boundary == "before_commit":
            raise RuntimeError("simulated interruption before commit")
    with closing(connect(path, 5000)) as conn:
        with pytest.raises(RuntimeError):
            repository.register(conn, **intent, secret=SECRET, fault=fault)
    with closing(connect(path, 5000)) as reopened:
        assert repository.lookup_registration(reopened, **intent, secret=SECRET) is None
        assert reopened.execute("SELECT last_generation FROM fr_destination").fetchone()[0] == 0
        assert repository.register(reopened, **intent, secret=SECRET)["generation"] == "1"


def test_after_commit_fault_reopens_exact_receipt_without_reallocation(tmp_path):
    path, destination = _database(tmp_path)
    intent = _intent(destination)
    observed = []
    def fault(boundary):
        if boundary == "after_commit":
            # An independent connection observes the durable receipt before loss.
            with closing(connect(path, 5000)) as reader:
                observed.append(repository.lookup_registration(reader, **intent, secret=SECRET))
            raise RuntimeError("simulated lost response after commit")
    with closing(connect(path, 5000)) as conn:
        with pytest.raises(RuntimeError):
            repository.register(conn, **intent, secret=SECRET, fault=fault)
    with closing(connect(path, 5000)) as reopened:
        assert repository.lookup_registration(reopened, **intent, secret=SECRET) == observed[0]
        assert repository.register(reopened, **intent, secret=SECRET) == observed[0]
        assert reopened.execute("SELECT last_generation FROM fr_destination").fetchone()[0] == 1


def test_new_registration_preserves_old_receipt_and_cannot_authenticate_as_old(tmp_path):
    path, destination = _database(tmp_path)
    old_intent, new_intent = _intent(destination), _intent(destination)
    with closing(connect(path, 5000)) as conn:
        old = repository.register(conn, **old_intent, secret=SECRET)
        new = repository.register(conn, **new_intent, secret=OTHER_SECRET)
    with closing(connect(path, 5000)) as conn:
        assert int(new["generation"]) > int(old["generation"])
        assert old["registration_id"] != new["registration_id"]
        assert repository.lookup_registration(conn, **old_intent, secret=SECRET) == old
        actor = dict(destination_id=destination, registration_id=old["registration_id"], generation=int(old["generation"]))
        assert repository.authenticate_registration(conn, **actor, secret=SECRET) == old
        with pytest.raises(repository.RegistrationError, match="registration_credentials_invalid"):
            repository.authenticate_registration(conn, **actor, secret=OTHER_SECRET)
        actor["generation"] = int(new["generation"])
        with pytest.raises(repository.RegistrationError, match="registration_credentials_invalid"):
            repository.authenticate_registration(conn, **actor, secret=SECRET)


def test_sql_guards_preserve_receipt_destination_and_monotonic_counter(tmp_path):
    path, destination = _database(tmp_path)
    with closing(connect(path, 5000)) as conn:
        receipt = repository.register(conn, **_intent(destination), secret=SECRET)
        for sql in ("DELETE FROM fr_registrations", "UPDATE fr_registrations SET secret_sha256 = 'changed'",
                    "DELETE FROM fr_destination", "UPDATE fr_destination SET destination_id = 'changed'",
                    "UPDATE fr_destination SET last_generation = 0"):
            with pytest.raises(sqlite3.IntegrityError):
                conn.execute(sql)
            conn.rollback()
        assert conn.execute("SELECT COUNT(*) FROM fr_registrations").fetchone()[0] == 1
        assert repository.destination_identity(conn) == destination
        assert conn.execute("SELECT last_generation FROM fr_destination").fetchone()[0] == int(receipt["generation"])


def test_generation_upper_bound_allows_replay_but_refuses_new_allocation(tmp_path):
    path, destination = _database(tmp_path)
    intent = _intent(destination)
    with closing(connect(path, 5000)) as conn:
        with conn:
            conn.execute("UPDATE fr_destination SET last_generation = ?", (repository.MAX_GENERATION - 1,))
        receipt = repository.register(conn, **intent, secret=SECRET)
        assert receipt["generation"] == str(repository.MAX_GENERATION)
        assert repository.register(conn, **intent, secret=SECRET) == receipt
        with pytest.raises(repository.RegistrationError, match="registration_generation_exhausted"):
            repository.register(conn, **_intent(destination), secret=SECRET)
    with closing(connect(path, 5000)) as conn:
        assert conn.execute("SELECT COUNT(*) FROM fr_registrations").fetchone()[0] == 1


def test_corrupted_counter_type_is_unavailable_not_absence(tmp_path):
    path, destination = _database(tmp_path)
    with closing(connect(path, 5000)) as conn:
        with conn:
            conn.execute("PRAGMA ignore_check_constraints = ON")
            conn.execute("UPDATE fr_destination SET last_generation = 'corrupt'")
        for action in (repository.register, repository.lookup_registration):
            with pytest.raises(repository.RegistrationError, match="registration_unavailable"):
                action(conn, **_intent(destination), secret=SECRET)
        assert conn.execute("SELECT COUNT(*) FROM fr_registrations").fetchone()[0] == 0


def test_wire_generation_rejects_numeric_negative_noncanonical_and_overflow(tmp_path):
    path, destination = _database(tmp_path)
    with closing(connect(path, 5000)) as conn:
        receipt = repository.register(conn, **_intent(destination), secret=SECRET)
    assert RegistrationReceipt.model_validate(receipt).generation == "1"
    for generation in (1, 0, "0", "-1", "01", "+1", "1.0", str(1 << 63)):
        with pytest.raises(ValidationError):
            RegistrationReceipt.model_validate(dict(receipt, generation=generation))


def test_legacy_schema_rows_ledger_and_triggers_unchanged_by_registration(tmp_path):
    path = tmp_path / "registration.sqlite3"
    with closing(connect(path, 5000)) as conn:
        run_migrations(conn)
        with conn:
            asset = insert_asset(conn, type="video", filename="synthetic.mov", original_path="originals/synthetic.mov",
                                 size_bytes=10, server_sha256="a" * 64, taken_at=None, latitude=None,
                                 longitude=None, exif_json=None, is_log=False)
            insert_job(conn, job_type="synthetic_unsupported", asset_id=asset["id"], payload_json="{}")
        before = _legacy_snapshot(conn)
        migrations.run_frame_relay_migrations(conn)
        destination = repository.destination_identity(conn)
        repository.register(conn, **_intent(destination), secret=SECRET)
        repository.register(conn, **_intent(destination), secret=OTHER_SECRET)
        migrations.run_frame_relay_migrations(conn)
        assert _legacy_snapshot(conn) == before


def test_migration_failure_rolls_back_new_tables_identity_and_ledger(tmp_path, monkeypatch):
    path = tmp_path / "registration.sqlite3"
    broken = tmp_path / "broken-migration.sql"
    broken.write_text(migrations.SCHEMA.read_text() + "\nSELECT missing FROM nonexistent;\n")
    monkeypatch.setattr(migrations, "SCHEMA", broken)
    with closing(connect(path, 5000)) as conn:
        run_migrations(conn)
        before = _legacy_snapshot(conn)
        with pytest.raises(sqlite3.OperationalError):
            migrations.run_frame_relay_migrations(conn)
        assert conn.execute("SELECT COUNT(*) FROM sqlite_master WHERE name LIKE 'fr_%'").fetchone()[0] == 0
        assert _legacy_snapshot(conn) == before


def test_applied_migration_never_recreates_missing_destination(tmp_path):
    path, destination = _database(tmp_path)
    with closing(connect(path, 5000)) as conn:
        with conn:
            conn.execute("DROP TRIGGER fr_destination_no_delete")
            conn.execute("DELETE FROM fr_destination")
        with pytest.raises(migrations.FrameRelaySchemaError):
            migrations.run_frame_relay_migrations(conn)
        assert conn.execute("SELECT COUNT(*) FROM fr_destination").fetchone()[0] == 0
        with pytest.raises(repository.RegistrationError, match="registration_unavailable"):
            repository.lookup_registration(conn, **_intent(destination), secret=SECRET)


def test_corrupt_receipt_fields_and_digest_are_not_success(monkeypatch, tmp_path):
    path = _environment(monkeypatch, tmp_path)
    with TestClient(app) as client:
        intent = _intent(_capability(client)["destination_id"])
        response = client.post(PREFIX + "/registrations", json=intent, headers=_headers())
        assert response.status_code == 200
        with closing(connect(path, 5000)) as conn:
            original = dict(conn.execute("SELECT * FROM fr_registrations").fetchone())
            with conn:
                conn.execute("DROP TRIGGER fr_registration_no_update")
                conn.execute("PRAGMA ignore_check_constraints = ON")
            for field, value in (("registration_id", "invalid-uuid"), ("registration_id", b"bytes"),
                                 ("created_at", "2026-02-30T00:00:00.000000+00:00"),
                                 ("created_at", "2026-10-06T00:00:00.000000+09:00"),
                                 ("created_at", b"bytes"), ("generation", "corrupt"),
                                 ("secret_sha256", b"a" * 64), ("secret_sha256", "z" * 64)):
                with conn:
                    conn.execute("UPDATE fr_registrations SET " + field + " = ?", (value,))
                for failure in (_lookup(client, intent),
                                client.post(PREFIX + "/registrations", json=intent, headers=_headers())):
                    assert failure.status_code == 503
                    assert failure.json()["code"] == "registration_unavailable"
                with conn:
                    conn.execute("UPDATE fr_registrations SET " + field + " = ?", (original[field],))
        assert _lookup(client, intent).json() == response.json()


def test_registration_actor_rejects_bool_nonint_and_out_of_range_generation(tmp_path):
    path, destination = _database(tmp_path)
    with closing(connect(path, 5000)) as conn:
        receipt = repository.register(conn, **_intent(destination), secret=SECRET)
        for generation in (True, False, "1", 1.0, 0, -1, 1 << 63):
            with pytest.raises(repository.RegistrationError, match="registration_credentials_invalid"):
                repository.authenticate_registration(conn, destination_id=destination,
                    registration_id=receipt["registration_id"], generation=generation, secret=SECRET)
