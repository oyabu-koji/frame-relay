"""Bound, resumable FR receiving. Transport completion is not storage evidence."""
from contextlib import closing
import hashlib
from uuid import uuid4

from app.core.settings import MAX_UPLOAD_CHUNKS, MAX_UPLOAD_SESSION_SIZE_BYTES
from app.db.connection import connect
from app.repositories import frame_relay_storage as repository
from app.repositories.frame_relay_storage import StorageError
from app.repositories.jobs import insert_or_return_job
from app.schemas.frame_relay_storage import StorageBindingRequest
from app.services import frame_relay_files as files


def open_database(settings):
    return closing(connect(settings.database_path, settings.sqlite_busy_timeout_ms))


def create(settings, request, secret):
    request = StorageBindingRequest.model_validate(request).model_dump()
    count = int(request["byte_count"])
    if count > min(settings.upload_session_max_size_bytes, MAX_UPLOAD_SESSION_SIZE_BYTES, (1 << 63) - 1):
        raise StorageError("storage_size_limit")
    if (count + settings.upload_session_chunk_size_bytes - 1) // settings.upload_session_chunk_size_bytes > MAX_UPLOAD_CHUNKS:
        raise StorageError("storage_chunk_limit")
    with open_database(settings) as conn:
        conn.execute("BEGIN IMMEDIATE")
        try:
            repository.available(conn)
            repository.authenticate(conn, request, secret)
            row = conn.execute("""SELECT session_id FROM fr_upload_bindings
                WHERE destination_id=? AND registration_id=? AND operation_id=?""",
                (request["destination_id"], request["registration_id"], request["operation_id"])).fetchone()
            if row is not None:
                value = repository.authorize(conn, row[0], request, secret)
                conn.commit()
                return value
            active = conn.execute("SELECT COUNT(*) FROM fr_upload_states WHERE status IN ('receiving','finalizing','failed')").fetchone()[0]
            if active >= settings.upload_session_active_limit:
                raise StorageError("storage_active_limit")
            session_id = str(uuid4())
            value = {**request, "registration_generation": int(request["registration_generation"]),
                "byte_count": count, "session_id": session_id,
                "chunk_size": settings.upload_session_chunk_size_bytes,
                "final_path": "originals/frame-relay/" + session_id + ".mov"}
            columns = tuple(value)
            conn.execute("INSERT INTO fr_upload_bindings(" + ",".join(columns) + ") VALUES(" +
                         ",".join("?" for _ in columns) + ")", tuple(value[key] for key in columns))
            conn.execute("INSERT INTO fr_upload_states(session_id,status) VALUES(?,'receiving')", (session_id,))
            conn.commit()
            return value
        except BaseException:
            conn.rollback()
            raise


def _state(conn, session_id):
    row = conn.execute("SELECT * FROM fr_upload_states WHERE session_id=?", (session_id,)).fetchone()
    if row is None:
        raise StorageError("storage_state_missing")
    return dict(row)


def _range(value, index, content_range):
    if type(index) is not int or index < 0:
        raise StorageError("storage_chunk_range_invalid")
    start = index * value["chunk_size"]
    end = min(start + value["chunk_size"], value["byte_count"]) - 1
    if start > end or content_range != (start, end, value["byte_count"]):
        raise StorageError("storage_chunk_range_invalid")
    return end - start + 1


async def receive_chunk(settings, session_id, request, secret, index, content_range, digest, body, *, fault=None):
    request = StorageBindingRequest.model_validate(request).model_dump()
    with open_database(settings) as conn:
        value = repository.authorize(conn, session_id, request, secret)
        if _state(conn, session_id)["status"] != "receiving":
            raise StorageError("storage_not_receiving")
    expected = _range(value, index, content_range)
    # Each receiver owns exactly this path until its real stream terminates.
    staging = "tmp/frame-relay/receiving/" + str(uuid4()) + ".part"
    total, hashed = 0, hashlib.sha256()
    try:
        with files.exclusive_writer(settings.media_root, staging) as output:
            async for block in body:
                total += len(block)
                if total > expected:
                    raise StorageError("storage_chunk_size_invalid")
                output.write(block)
                hashed.update(block)
                if fault is not None:
                    fault("receive_block")
        if total != expected or hashed.hexdigest() != digest:
            raise StorageError("storage_chunk_content_invalid")
        path = f"tmp/frame-relay/chunks/{session_id}/{index}.part"
        recovered = None
        try:
            recovered = files.read_all(settings.media_root, path)
        except FileNotFoundError:
            pass
        if recovered is not None and (recovered["byte_count"] != total or recovered["sha256"] != digest):
            raise StorageError("storage_chunk_conflict")
        with open_database(settings) as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                current = repository.authorize(conn, session_id, request, secret)
                if current != value or _state(conn, session_id)["status"] != "receiving":
                    raise StorageError("storage_not_receiving")
                existing = conn.execute("SELECT * FROM fr_upload_chunks WHERE session_id=? AND chunk_index=?", (session_id,index)).fetchone()
                if existing is not None:
                    if existing["sha256"] != digest or existing["byte_count"] != total or existing["path"] != path:
                        raise StorageError("storage_chunk_conflict")
                    if recovered is None:
                        raise StorageError("storage_committed_chunk_missing")
                    if files.current_fingerprint(settings.media_root, path) != recovered["fingerprint"]:
                        raise StorageError("storage_file_changed")
                else:
                    if recovered is not None:
                        if files.current_fingerprint(settings.media_root, path) != recovered["fingerprint"]:
                            raise StorageError("storage_file_changed")
                    else:
                        try:
                            files.current_fingerprint(settings.media_root, path)
                        except FileNotFoundError:
                            pass
                        else:
                            raise StorageError("storage_chunk_retry_required")
                        if not files.publish(settings.media_root, staging, path):
                            # A foreign/racing target appeared after our absent
                            # check. Reopen it independently on a fresh request.
                            raise StorageError("storage_chunk_retry_required")
                    if fault is not None:
                        fault("after_chunk_publish")
                    conn.execute("INSERT INTO fr_upload_chunks VALUES(?,?,?,?,?)", (session_id,index,total,digest,path))
                conn.commit()
            except BaseException:
                conn.rollback()
                raise
        return {"chunk_index": index, "byte_count": str(total), "sha256": digest}
    finally:
        files.remove_owned(settings.media_root, staging)


def evidence(conn, value):
    state = _state(conn, value["session_id"])
    row = conn.execute("SELECT * FROM fr_storage_evidence WHERE session_id=?", (value["session_id"],)).fetchone()
    if state["status"] != "completed":
        if row is not None:
            raise StorageError("storage_evidence_inconsistent")
        return None
    if (row is None or state["evidence_id"] != row["evidence_id"] or state["asset_id"] != row["asset_id"] or
            any(row[key] != value[key] for key in ("sha256", "byte_count", "final_path")) or
            row["schema_version"] != "fr-final-read-v1"):
        raise StorageError("storage_evidence_missing")
    asset = conn.execute("SELECT * FROM assets WHERE id=?", (row["asset_id"],)).fetchone()
    if (asset is None or asset["original_path"] != value["final_path"] or
            asset["size_bytes"] != value["byte_count"] or asset["server_sha256"] != value["sha256"]):
        raise StorageError("storage_evidence_inconsistent")
    finalize_job = conn.execute("SELECT * FROM jobs WHERE id=?", (state["finalize_job_id"],)).fetchone()
    claim = conn.execute("SELECT * FROM fr_job_claims WHERE job_id=?", (state["finalize_job_id"],)).fetchone()
    conversion = conn.execute("SELECT * FROM jobs WHERE dedup_key=?", ("fr-conversion:" + value["session_id"],)).fetchone()
    expected_payload = repository.canonical({"evidence_id": row["evidence_id"],
        "binding_sha256": repository.binding_digest(value), "session_id": value["session_id"],
        "asset_id": row["asset_id"], "schema_version": "fr-final-read-v1"})
    if (finalize_job is None or finalize_job["status"] != "done" or
            finalize_job["job_type"] != "fr_upload_finalize" or finalize_job["asset_id"] is not None or
            finalize_job["dedup_key"] != "fr-finalize:" + value["session_id"] or
            finalize_job["payload_json"] != repository.finalize_payload(value) or
            claim is None or claim["session_id"] != value["session_id"] or
            claim["generation"] != row["claim_generation"] or claim["token"] != row["claim_token"] or
            conversion is None or conversion["job_type"] != "fr_conversion" or
            conversion["status"] != "queued" or conversion["asset_id"] != row["asset_id"] or
            conversion["payload_json"] != expected_payload):
        raise StorageError("storage_evidence_inconsistent")
    return {"evidence_id": row["evidence_id"], "schema_version": row["schema_version"],
        "method": "final_destination_read_back", "committed": True, "final_save_completed": True,
        "sha256": row["sha256"], "byte_count": str(row["byte_count"]), "observed_at": row["observed_at"]}


def lookup(settings, session_id, request, secret):
    request = StorageBindingRequest.model_validate(request).model_dump()
    with open_database(settings) as conn:
        conn.execute("BEGIN")
        value = repository.authorize(conn, session_id, request, secret)
        state = _state(conn, session_id)
        proof = evidence(conn, value)
        chunks = [row[0] for row in conn.execute("SELECT chunk_index FROM fr_upload_chunks WHERE session_id=? ORDER BY chunk_index", (session_id,))]
        conn.rollback()
    return {"binding": public_binding(value), "status": state["status"], "evidence": proof,
        "chunk_indexes": chunks, "failure_code": state["failure_code"]}


def public_binding(value):
    return {key: (str(item) if key in ("registration_generation", "content_generation", "byte_count", "chunk_size") else item)
        for key, item in value.items() if key != "final_path"}


def finalize(settings, session_id, request, secret):
    request = StorageBindingRequest.model_validate(request).model_dump()
    with open_database(settings) as conn:
        conn.execute("BEGIN IMMEDIATE")
        try:
            value = repository.authorize(conn, session_id, request, secret)
            state = _state(conn, session_id)
            if state["status"] == "completed":
                evidence(conn, value)  # Never trust a completed flag alone.
            elif state["status"] == "cancelled":
                raise StorageError("storage_cancelled")
            elif state["status"] != "finalizing":
                expected = (value["byte_count"] + value["chunk_size"] - 1) // value["chunk_size"]
                if conn.execute("SELECT COUNT(*) FROM fr_upload_chunks WHERE session_id=?", (session_id,)).fetchone()[0] != expected:
                    raise StorageError("storage_chunks_missing")
                job, _ = insert_or_return_job(conn, job_type="fr_upload_finalize", asset_id=None,
                    payload_json=repository.finalize_payload(value), dedup_key="fr-finalize:" + session_id)
                if job["status"] not in ("queued", "failed"):
                    raise StorageError("storage_job_state_invalid")
                conn.execute("UPDATE jobs SET status='queued',claimed_at=NULL,lease_expires_at=NULL,error_message=NULL WHERE id=?", (job["id"],))
                conn.execute("UPDATE fr_upload_states SET status='finalizing',finalize_job_id=?,failure_code=NULL WHERE session_id=?", (job["id"],session_id))
            conn.commit()
        except BaseException:
            conn.rollback()
            raise
    return lookup(settings, session_id, request, secret)


def cancel(settings, session_id, request, secret):
    request = StorageBindingRequest.model_validate(request).model_dump()
    with open_database(settings) as conn:
        conn.execute("BEGIN IMMEDIATE")
        try:
            repository.authorize(conn, session_id, request, secret)
            state = _state(conn, session_id)
            if state["status"] in ("completed", "finalizing"):
                raise StorageError("storage_cancel_not_available")
            conn.execute("UPDATE fr_upload_states SET status='cancelled' WHERE session_id=?", (session_id,))
            conn.commit()
        except BaseException:
            conn.rollback()
            raise
    # Retain committed chunks and do not delete active receiver staging. Its
    # late callback rechecks this state and cleans only its own finished stream.
    return lookup(settings, session_id, request, secret)
