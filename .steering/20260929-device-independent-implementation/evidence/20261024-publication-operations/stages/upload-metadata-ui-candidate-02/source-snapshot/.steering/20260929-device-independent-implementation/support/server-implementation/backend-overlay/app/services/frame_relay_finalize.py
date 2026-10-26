"""Publish without replacement, independently reread, then atomically commit proof/job."""
from contextlib import closing
import hashlib
import time
from uuid import uuid4

from app.db.connection import connect
from app.repositories import frame_relay_storage as repository
from app.repositories.frame_relay_storage import StorageError
from app.repositories.jobs import insert_or_return_job
from app.services import frame_relay_files as files


def _connection(settings):
    return closing(connect(settings.database_path, settings.sqlite_busy_timeout_ms))


def _inject(fault, step):
    if fault is not None:
        fault(step)


def assembly_name(value, job):
    # Tokens originate only in the persisted claim; callers cannot select paths.
    return ("tmp/frame-relay/assembly/" + value["session_id"] + "/" +
            str(job["fr_claim_generation"]) + "-" + job["fr_claim_token"] + ".part")


def cleanup_attempt(settings, job):
    with _connection(settings) as conn:
        conn.execute("BEGIN IMMEDIATE")
        try:
            value = repository.current_claim(conn, job)
            files.remove_owned(settings.media_root, assembly_name(value, job))
            conn.commit()
        except BaseException:
            conn.rollback()
            raise


def mark_failed(settings, job, code):
    with _connection(settings) as conn:
        conn.execute("BEGIN IMMEDIATE")
        try:
            value = repository.current_claim(conn, job)
            files.remove_owned(settings.media_root, assembly_name(value, job))
            conn.execute("UPDATE fr_upload_states SET status='failed',failure_code=? WHERE session_id=?",
                         (code, value["session_id"]))
            conn.execute("UPDATE jobs SET status='failed',error_message=?,claimed_at=NULL,lease_expires_at=NULL WHERE id=?", (code,job["id"]))
            conn.commit()
        except BaseException:
            conn.rollback()
            raise


def process_finalize(*, settings, job, fault=None):
    try:
        _process(settings, job, fault)
    except Exception as error:
        code = error.code if isinstance(error, StorageError) else "storage_result_unknown"
        try:
            mark_failed(settings, job, code)
        except StorageError:
            pass  # Lost lease or already committed: no stale failure/cleanup.
    return True


def _process(settings, job, fault):
    with _connection(settings) as conn:
        conn.execute("BEGIN IMMEDIATE")
        try:
            value = repository.current_claim(conn, job)
            chunks = [dict(row) for row in conn.execute("SELECT * FROM fr_upload_chunks WHERE session_id=? ORDER BY chunk_index", (value["session_id"],))]
            conn.commit()
        except BaseException:
            conn.rollback()
            raise
    assembly = assembly_name(value, job)
    last_renewal = time.monotonic()

    def progress(step):
        nonlocal last_renewal
        _inject(fault, step)
        if time.monotonic() - last_renewal >= min(30, settings.job_lease_seconds / 3):
            with _connection(settings) as conn:
                conn.execute("BEGIN IMMEDIATE")
                try:
                    repository.renew_claim(conn, job, min(settings.job_lease_seconds, 300))
                    conn.commit()
                except BaseException:
                    conn.rollback()
                    raise
            last_renewal = time.monotonic()

    try:
        files.current_fingerprint(settings.media_root, value["final_path"])
    except FileNotFoundError:
        expected_chunks = (value["byte_count"] + value["chunk_size"] - 1) // value["chunk_size"]
        if len(chunks) != expected_chunks:
            raise StorageError("storage_chunks_missing")
        total, digest = 0, hashlib.sha256()
        with files.exclusive_writer(settings.media_root, assembly) as output:
            for index, chunk in enumerate(chunks):
                expected_size = min(value["chunk_size"], value["byte_count"] - index * value["chunk_size"])
                expected_path = f"tmp/frame-relay/chunks/{value['session_id']}/{index}.part"
                if chunk["chunk_index"] != index or chunk["byte_count"] != expected_size or chunk["path"] != expected_path:
                    raise StorageError("storage_chunk_binding_mismatch")

                def copy(block):
                    nonlocal total
                    output.write(block)
                    digest.update(block)
                    total += len(block)

                observed = files.read_all(settings.media_root, chunk["path"], consume=copy,
                                          fault=lambda _: progress("assembly_block"))
                if observed["byte_count"] != expected_size or observed["sha256"] != chunk["sha256"]:
                    raise StorageError("storage_chunk_content_invalid")
        if total != value["byte_count"] or digest.hexdigest() != value["sha256"]:
            raise StorageError("storage_assembly_content_invalid")
        _inject(fault, "before_publish")
        with _connection(settings) as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                if repository.current_claim(conn, job) != value:
                    raise StorageError("storage_binding_mismatch")
                files.publish(settings.media_root, assembly, value["final_path"])
                files.remove_owned(settings.media_root, assembly)
                conn.commit()
            except BaseException:
                conn.rollback()
                raise
        _inject(fault, "after_publish")
    # No SQLite transaction spans the independent final-destination read.
    observed = files.read_all(settings.media_root, value["final_path"], fault=progress)
    if observed["byte_count"] != value["byte_count"] or observed["sha256"] != value["sha256"]:
        raise StorageError("storage_final_content_invalid")
    _inject(fault, "after_read")
    with _connection(settings) as conn:
        conn.execute("BEGIN IMMEDIATE")
        try:
            if repository.current_claim(conn, job) != value:
                raise StorageError("storage_binding_mismatch")
            if files.current_fingerprint(settings.media_root, value["final_path"]) != observed["fingerprint"]:
                raise StorageError("storage_file_changed")
            # No legacy file_verified row is adopted. A preexisting path owner is
            # an inconsistency, not proof that the unfinished commit succeeded.
            if conn.execute("SELECT 1 FROM assets WHERE original_path=?", (value["final_path"],)).fetchone():
                raise StorageError("storage_unproven_asset_exists")
            cursor = conn.execute("""INSERT INTO assets(type,filename,original_path,size_bytes,server_sha256,
                is_log,transfer_status,verification_status,preview_status,review_status,delete_candidate_status)
                VALUES('video',?,?,?, ?,0,'uploaded','fr_final_read_verified','not_started','not_reviewed','not_candidate')""",
                (value["session_id"] + ".mov",value["final_path"],value["byte_count"],value["sha256"]))
            asset_id = cursor.lastrowid
            evidence_id = str(uuid4())
            conn.execute("""INSERT INTO fr_storage_evidence VALUES(?,?,?,'fr-final-read-v1',?,?,?,?,?,?,?)""",
                (evidence_id,value["session_id"],asset_id,value["sha256"],value["byte_count"],value["final_path"],
                 repository.canonical(observed["fingerprint"]),job["fr_claim_generation"],job["fr_claim_token"],repository.now_text()))
            _inject(fault, "after_evidence_insert")
            conversion_payload = repository.canonical({"evidence_id": evidence_id,
                "binding_sha256": repository.binding_digest(value), "session_id": value["session_id"],
                "asset_id": asset_id, "schema_version": "fr-final-read-v1"})
            conversion, _ = insert_or_return_job(conn, job_type="fr_conversion", asset_id=asset_id,
                payload_json=conversion_payload, dedup_key="fr-conversion:" + value["session_id"])
            if conversion["status"] != "queued":
                raise StorageError("storage_conversion_job_invalid")
            _inject(fault, "after_job_insert")
            conn.execute("UPDATE fr_upload_states SET status='completed',asset_id=?,evidence_id=?,failure_code=NULL WHERE session_id=?",
                (asset_id,evidence_id,value["session_id"]))
            conn.execute("UPDATE jobs SET status='done',claimed_at=NULL,lease_expires_at=NULL,error_message=NULL WHERE id=?", (job["id"],))
            _inject(fault, "before_commit")
            conn.commit()
        except BaseException:
            conn.rollback()
            raise
    _inject(fault, "after_commit")
