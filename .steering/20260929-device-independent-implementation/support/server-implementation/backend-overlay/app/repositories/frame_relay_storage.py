"""Same-DB immutable upload ownership and fenced worker claims; no credentials stored."""
from contextlib import closing
from datetime import datetime, timedelta, timezone
from functools import wraps
import base64
import binascii
import hashlib
import inspect
import json
import sqlite3
from uuid import UUID, uuid4

from app.db.connection import connect
from app.db.frame_relay_migrations import validate_frame_relay_schema
from app.repositories.registrations import authenticate_registration
from app.schemas.frame_relay_storage import StorageBindingRequest


class StorageError(RuntimeError):
    def __init__(self, code):
        self.code = code
        super().__init__(code)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def now_text():
    return datetime.now(timezone.utc).isoformat(timespec="microseconds")


def available(conn):
    names = {row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    if "fr_schema_migrations" not in names:
        if any(name.startswith("fr_") for name in names):
            raise StorageError("storage_schema_unavailable")
        return False  # A truly legacy-only database, not a broken FR ledger.
    validate_frame_relay_schema(conn)
    if not {"fr_upload_bindings", "fr_upload_states", "fr_upload_chunks",
            "fr_job_claims", "fr_storage_evidence"}.issubset(names):
        raise StorageError("storage_schema_unavailable")
    return True


def binding(conn, session_id):
    if not available(conn):
        raise StorageError("storage_schema_unavailable")
    row = conn.execute("SELECT * FROM fr_upload_bindings WHERE session_id=?", (session_id,)).fetchone()
    if row is None:
        raise StorageError("storage_binding_missing")
    value = dict(row)
    try:
        StorageBindingRequest.model_validate({key: str(value[key]) if key in
            ("registration_generation", "byte_count") else value[key]
            for key in StorageBindingRequest.model_fields})
        if (type(value["byte_count"]) is not int or type(value["registration_generation"]) is not int or
                type(value["chunk_size"]) is not int or value["chunk_size"] <= 0 or
                str(UUID(value["session_id"])) != value["session_id"] or
                value["final_path"] != "originals/frame-relay/" + value["session_id"] + ".mov"):
            raise ValueError("Invalid binding storage identity")
        if conn.execute("SELECT 1 FROM fr_registrations WHERE destination_id=? AND registration_id=? AND generation=?",
            (value["destination_id"],value["registration_id"],value["registration_generation"])).fetchone() is None:
            raise ValueError("Binding registration is missing")
    except (ValueError, TypeError, KeyError):
        raise StorageError("storage_binding_invalid") from None
    return value


def binding_digest(value):
    return hashlib.sha256(canonical(value).encode()).hexdigest()


def finalize_payload(value):
    return canonical({"session_id": value["session_id"], "binding_sha256": binding_digest(value)})


def authenticate(conn, value, secret):
    return authenticate_registration(conn, destination_id=value["destination_id"],
        registration_id=value["registration_id"], generation=int(value["registration_generation"]),
        secret=secret)


def authorize(conn, session_id, requested, secret):
    value = binding(conn, session_id)
    authenticate(conn, requested, secret)
    for key in ("destination_id", "registration_id", "registration_generation", "operation_id",
                "capture_id", "content_generation", "sha256", "byte_count"):
        if str(value[key]) != str(requested[key]):
            raise StorageError("storage_binding_mismatch")
    return value


INVENTORY_CURSOR_VERSION = "fr-original-inventory-v1"
INVENTORY_CAPTURE_MAX_BYTES = 2048


def inventory_cursor(request, after):
    # A cursor is a scoped keyset, not an authorization credential. Replaying
    # the same cursor is harmless; registration authentication is still required.
    value = {key: request[key] for key in ("destination_id", "registration_id", "registration_generation", "limit")}
    value.update({"version": INVENTORY_CURSOR_VERSION, "after": after})
    return base64.urlsafe_b64encode(canonical(value).encode("ascii")).decode("ascii").rstrip("=")


def inventory_after(request):
    token = request["cursor"]
    if token is None:
        return None
    try:
        value = json.loads(base64.b64decode(token + "=" * (-len(token) % 4), altchars=b"-_", validate=True))
        after = value["after"]
        if (not isinstance(after, str) or str(UUID(after)) != after or
                inventory_cursor(request, after) != token):
            raise ValueError("Noncanonical or differently scoped cursor")
    except (ValueError, TypeError, KeyError, binascii.Error):
        raise StorageError("storage_inventory_cursor_invalid") from None
    return after


def inventory_capture_bound(conn, session_id, destination):
    # Check the byte length before materializing a possibly oversized opaque
    # identity. The existing upload API's identity contract is unchanged.
    row = conn.execute("SELECT length(CAST(capture_id AS BLOB)) FROM fr_upload_bindings "
        "WHERE session_id=? AND destination_id=?", (session_id, destination)).fetchone()
    if row is None:
        raise StorageError("storage_inventory_cursor_invalid")
    if type(row[0]) is not int or not 1 <= row[0] <= INVENTORY_CAPTURE_MAX_BYTES:
        raise StorageError("storage_inventory_item_too_large")


def inventory_sessions(conn, request, secret):
    if not conn.in_transaction or not available(conn):
        raise StorageError("storage_schema_unavailable")
    authenticate(conn, request, secret)
    after = inventory_after(request)
    if after is not None:
        inventory_capture_bound(conn, after, request["destination_id"])
    # Missing states and evidence attached to a non-completed state are also
    # candidates: the service must reject their inconsistency, never omit them
    # and return a misleading empty or shortened successful page.
    rows = conn.execute("""SELECT b.session_id FROM fr_upload_bindings b
        LEFT JOIN fr_upload_states s ON s.session_id=b.session_id
        LEFT JOIN fr_storage_evidence e ON e.session_id=b.session_id
        WHERE b.destination_id=? AND (? IS NULL OR b.session_id>?)
          AND (s.status='completed' OR s.session_id IS NULL OR e.session_id IS NOT NULL)
        ORDER BY b.session_id COLLATE BINARY LIMIT ?""",
        (request["destination_id"], after, after, int(request["limit"]) + 1)).fetchall()
    return after, [row[0] for row in rows]


def allocate_claim(conn, job):
    """Called inside claim_next_job's transaction, before its commit."""
    if not conn.in_transaction or job["job_type"] != "fr_upload_finalize":
        raise StorageError("storage_claim_invalid")
    try:
        payload = json.loads(job["payload_json"])
        value = binding(conn, payload["session_id"])
    except (TypeError, KeyError, json.JSONDecodeError):
        raise StorageError("storage_job_payload_invalid") from None
    state = conn.execute("SELECT * FROM fr_upload_states WHERE session_id=?", (value["session_id"],)).fetchone()
    if (job["payload_json"] != finalize_payload(value) or state is None or
            state["finalize_job_id"] != job["id"] or state["status"] != "finalizing"):
        raise StorageError("storage_job_binding_mismatch")
    previous = conn.execute("SELECT generation FROM fr_job_claims WHERE job_id=?", (job["id"],)).fetchone()
    generation = 1 if previous is None else previous[0] + 1
    if not 1 <= generation < (1 << 63):
        raise StorageError("storage_claim_exhausted")
    token = str(uuid4())
    conn.execute("""INSERT INTO fr_job_claims(job_id,session_id,generation,token) VALUES(?,?,?,?)
        ON CONFLICT(job_id) DO UPDATE SET generation=excluded.generation, token=excluded.token""",
        (job["id"], value["session_id"], generation, token))
    return {**job, "fr_claim_generation": generation, "fr_claim_token": token}


def current_claim(conn, job):
    if not conn.in_transaction:
        raise StorageError("storage_fence_requires_transaction")
    available(conn)
    row = conn.execute("""SELECT j.*, c.session_id, c.generation AS fr_claim_generation,
        c.token AS fr_claim_token FROM jobs j JOIN fr_job_claims c ON j.id=c.job_id WHERE j.id=?""",
        (job["id"],)).fetchone()
    if (row is None or row["status"] != "running" or row["job_type"] != "fr_upload_finalize" or
            row["lease_expires_at"] is None or row["lease_expires_at"] <= now_text() or
            any(row[key] != job.get(key) for key in
                ("fr_claim_generation", "fr_claim_token", "payload_json", "job_type", "dedup_key"))):
        raise StorageError("storage_stale_claim")
    value = binding(conn, row["session_id"])
    state = conn.execute("SELECT * FROM fr_upload_states WHERE session_id=?", (value["session_id"],)).fetchone()
    if (state is None or state["status"] != "finalizing" or state["finalize_job_id"] != job["id"] or
            row["payload_json"] != finalize_payload(value)):
        raise StorageError("storage_job_binding_mismatch")
    return value


def renew_claim(conn, job, seconds):
    current_claim(conn, job)
    if type(seconds) is not int or not 1 <= seconds <= 300:
        raise StorageError("storage_lease_invalid")
    conn.execute("UPDATE jobs SET lease_expires_at=? WHERE id=?",
        ((datetime.now(timezone.utc) + timedelta(seconds=seconds)).isoformat(timespec="microseconds"), job["id"]))


def deny_legacy_session(conn, session_id):
    if available(conn) and conn.execute("SELECT 1 FROM fr_upload_bindings WHERE session_id=?", (session_id,)).fetchone():
        raise StorageError("frame_relay_session_requires_bound_api")
    if available(conn) and conn.execute("SELECT 1 FROM fr_upload_states WHERE session_id=?", (session_id,)).fetchone():
        raise StorageError("storage_binding_missing")


def managed_asset(conn, asset_id):
    ready = available(conn)
    row = conn.execute("SELECT original_path FROM assets WHERE id=?", (asset_id,)).fetchone()
    path = None if row is None else row[0]
    found = ready and conn.execute("SELECT 1 FROM fr_upload_bindings WHERE final_path=?", (path,)).fetchone()
    state = ready and conn.execute("SELECT 1 FROM fr_upload_states WHERE asset_id=?", (asset_id,)).fetchone()
    if (state or (isinstance(path, str) and path.startswith("originals/frame-relay/"))) and not found:
        raise StorageError("storage_binding_missing")
    return bool(found)


def deny_legacy_asset(conn, asset_id):
    if managed_asset(conn, asset_id):
        # S24 creates only evidence-bound queued work. Conversion/publication are
        # S26/S27 responsibilities, not an invitation to use legacy early returns.
        raise StorageError("frame_relay_conversion_not_implemented")


def legacy_entry(function):
    """Guard explicit legacy entry points before their early returns or error writes."""
    signature = inspect.signature(function)

    def check(conn, values):
        available(conn)  # Never bypass a broken FR schema.
        if values.get("session_id") is not None:
            deny_legacy_session(conn, values["session_id"])
        if values.get("session") is not None:
            deny_legacy_session(conn, values["session"]["id"])
        asset_ids = [values.get("asset_id")]
        if values.get("asset") is not None:
            asset_ids.append(values["asset"].get("id"))
        if values.get("outcome") is not None:
            asset_ids.append(values["outcome"].asset_id)
        job = values.get("job")
        job_id = values.get("job_id") or (job or {}).get("id")
        if job is not None:
            asset_ids.append(job.get("asset_id"))
            if str(job.get("job_type", "")).startswith("fr_"):
                raise StorageError("frame_relay_job_requires_fenced_worker")
            try:
                supplied_payload = json.loads(job.get("payload_json"))
            except (TypeError, json.JSONDecodeError):
                supplied_payload = {}
            if isinstance(supplied_payload, dict) and supplied_payload.get("session_id") is not None:
                deny_legacy_session(conn, supplied_payload["session_id"])
        tables = {row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        for key, table in (("attempt_id", "formal_preview_attempts"), ("rendition_id", "renditions")):
            if values.get(key) is not None and table in tables:
                target = conn.execute("SELECT asset_id FROM " + table + " WHERE id=?", (values[key],)).fetchone()
                if target is not None:
                    asset_ids.append(target[0])
        if job_id is not None:
            row = conn.execute("SELECT * FROM jobs WHERE id=?", (job_id,)).fetchone()
            if row is not None:
                if row["job_type"].startswith("fr_"):
                    raise StorageError("frame_relay_job_requires_fenced_worker")
                asset_ids.append(row["asset_id"])
                try:
                    payload = json.loads(row["payload_json"])
                except (TypeError, json.JSONDecodeError):
                    payload = {}
                if isinstance(payload, dict) and payload.get("session_id") is not None:
                    deny_legacy_session(conn, payload["session_id"])
        for asset_id in asset_ids:
            if asset_id is not None:
                deny_legacy_asset(conn, asset_id)

    def authorize_call(args, kwargs):
        values = signature.bind(*args, **kwargs).arguments
        if values.get("conn") is not None:
            check(values["conn"], values)
        else:
            settings = values["settings"]
            with closing(connect(settings.database_path, settings.sqlite_busy_timeout_ms)) as conn:
                check(conn, values)

    if inspect.iscoroutinefunction(function):
        @wraps(function)
        async def asynchronous(*args, **kwargs):
            authorize_call(args, kwargs)
            return await function(*args, **kwargs)
        return asynchronous

    @wraps(function)
    def synchronous(*args, **kwargs):
        authorize_call(args, kwargs)
        return function(*args, **kwargs)
    return synchronous
