"""Same-DB unpublished candidates, exact retry intents and independent claim fences."""
from datetime import datetime, timedelta, timezone
import json
from uuid import UUID, uuid4

from app.repositories import frame_relay_storage as storage
from app.repositories.frame_relay_storage import StorageError


def source(conn, job):
    """A queued job or is_log flag alone never proves source eligibility."""
    from app.services.frame_relay_storage import evidence
    try:
        payload=json.loads(job["payload_json"])
        if not isinstance(payload,dict):raise ValueError()
        value=storage.binding(conn,payload["session_id"])
        proof=evidence(conn,value)
        if proof is None:raise ValueError()
        row=conn.execute("SELECT * FROM fr_storage_evidence WHERE evidence_id=?",(proof["evidence_id"],)).fetchone()
        expected=storage.canonical({"evidence_id":proof["evidence_id"],"binding_sha256":storage.binding_digest(value),
            "session_id":value["session_id"],"asset_id":row["asset_id"],"schema_version":"fr-final-read-v1"})
        if (job["job_type"]!="fr_conversion" or job["asset_id"]!=row["asset_id"] or
                job["dedup_key"]!="fr-conversion:"+value["session_id"] or job["payload_json"]!=expected):
            raise ValueError()
        return value,dict(row)
    except (KeyError,ValueError,TypeError,StorageError):
        raise StorageError("conversion_source_evidence_invalid") from None


def _candidate(conn,candidate_id):
    row=conn.execute("SELECT * FROM fr_conversion_candidates WHERE candidate_id=?",(candidate_id,)).fetchone()
    if row is None:raise StorageError("conversion_candidate_missing")
    value=dict(row)
    try:
        if (str(UUID(candidate_id))!=candidate_id or type(value["generation"]) is not int or
                value["generation"]<=0 or value["candidate_path"]!="candidates/frame-relay/"+candidate_id+".bin"):
            raise ValueError()
    except (ValueError,TypeError,AttributeError):
        raise StorageError("conversion_candidate_invalid") from None
    return value


def _create_candidate(conn,job,value,proof,generation):
    if not 1<=generation<(1<<63):raise StorageError("conversion_generation_exhausted")
    candidate_id=str(uuid4())
    conn.execute("""INSERT INTO fr_conversion_candidates
        (candidate_id,job_id,session_id,evidence_id,asset_id,generation,source_payload,candidate_path,status)
        VALUES(?,?,?,?,?,?,?,?,'queued')""",
        (candidate_id,job["id"],value["session_id"],proof["evidence_id"],proof["asset_id"],generation,
         job["payload_json"],"candidates/frame-relay/"+candidate_id+".bin"))
    conn.execute("""INSERT INTO fr_conversion_heads VALUES(?,?,?)
        ON CONFLICT(job_id) DO UPDATE SET candidate_id=excluded.candidate_id""",
        (job["id"],value["session_id"],candidate_id))
    return _candidate(conn,candidate_id)


def allocate_claim(conn,job):
    """Claim, source check and initial candidate allocation share the jobs transaction."""
    if not conn.in_transaction:raise StorageError("conversion_fence_requires_transaction")
    try:
        value,proof=source(conn,job)
    except StorageError:
        # Reject malformed work terminally instead of leaving a poisoned queued
        # job to be rediscovered forever. No adapter or candidate is allocated.
        conn.execute("UPDATE jobs SET status='failed',claimed_at=NULL,lease_expires_at=NULL,error_message=? WHERE id=?",
            ("conversion_source_evidence_invalid",job["id"]))
        rejected=dict(conn.execute("SELECT * FROM jobs WHERE id=?",(job["id"],)).fetchone())
        return {**rejected,"fr_conversion_rejected":True}
    head=conn.execute("SELECT * FROM fr_conversion_heads WHERE job_id=?",(job["id"],)).fetchone()
    candidate=_create_candidate(conn,job,value,proof,1) if head is None else _candidate(conn,head["candidate_id"])
    if (candidate["source_payload"]!=job["payload_json"] or candidate["job_id"]!=job["id"] or
            candidate["session_id"]!=value["session_id"] or candidate["evidence_id"]!=proof["evidence_id"] or
            candidate["asset_id"]!=proof["asset_id"] or candidate["status"] not in ("queued","running")):
        raise StorageError("conversion_candidate_binding_invalid")
    previous=conn.execute("SELECT generation FROM fr_conversion_claims WHERE job_id=?",(job["id"],)).fetchone()
    generation=1 if previous is None else previous[0]+1
    if not 1<=generation<(1<<63):raise StorageError("conversion_claim_exhausted")
    token=str(uuid4())
    conn.execute("""INSERT INTO fr_conversion_claims VALUES(?,?,?,?) ON CONFLICT(job_id)
        DO UPDATE SET candidate_id=excluded.candidate_id,generation=excluded.generation,token=excluded.token""",
        (job["id"],candidate["candidate_id"],generation,token))
    conn.execute("UPDATE fr_conversion_candidates SET status='running' WHERE candidate_id=?",(candidate["candidate_id"],))
    return {**job,"fr_conversion_candidate":candidate["candidate_id"],
            "fr_conversion_generation":generation,"fr_conversion_token":token}


def current_claim(conn,job):
    if not conn.in_transaction:raise StorageError("conversion_fence_requires_transaction")
    row=conn.execute("SELECT * FROM jobs WHERE id=?",(job["id"],)).fetchone()
    claim=conn.execute("SELECT * FROM fr_conversion_claims WHERE job_id=?",(job["id"],)).fetchone()
    head=conn.execute("SELECT * FROM fr_conversion_heads WHERE job_id=?",(job["id"],)).fetchone()
    if (row is None or row["status"]!="running" or row["job_type"]!="fr_conversion" or
            row["lease_expires_at"] is None or row["lease_expires_at"]<=storage.now_text() or
            any(row[key]!=job.get(key) for key in ("payload_json","asset_id","dedup_key","job_type")) or
            claim is None or claim["candidate_id"]!=job.get("fr_conversion_candidate") or
            claim["generation"]!=job.get("fr_conversion_generation") or claim["token"]!=job.get("fr_conversion_token") or
            head is None or head["candidate_id"]!=claim["candidate_id"]):
        raise StorageError("conversion_stale_claim")
    value,proof=source(conn,dict(row))
    candidate=_candidate(conn,claim["candidate_id"])
    if (candidate["status"]!="running" or candidate["job_id"]!=job["id"] or
            candidate["source_payload"]!=job["payload_json"] or candidate["session_id"]!=value["session_id"] or
            candidate["evidence_id"]!=proof["evidence_id"] or candidate["asset_id"]!=proof["asset_id"] or
            head["session_id"]!=value["session_id"]):
        raise StorageError("conversion_candidate_binding_invalid")
    return value,proof,candidate


def renew_claim(conn,job,seconds):
    current_claim(conn,job)
    if type(seconds) is not int or not 1<=seconds<=300:raise StorageError("conversion_lease_invalid")
    conn.execute("UPDATE jobs SET lease_expires_at=? WHERE id=?",
        ((datetime.now(timezone.utc)+timedelta(seconds=seconds)).isoformat(timespec="microseconds"),job["id"]))


def retry(conn,*,session_id,expected_candidate_id,intent_id,payload_json,fault=None):
    """Replay keeps accepted candidate ID/generation; status is a current observation.

    Internal explicit intent only: no automatic retry policy or user wire implied.
    """
    try:
        if str(UUID(intent_id))!=intent_id:raise ValueError()
    except (TypeError,ValueError,AttributeError):raise StorageError("conversion_retry_invalid") from None
    requested=storage.canonical({"session_id":session_id,"expected_candidate_id":expected_candidate_id,
                                 "intent_id":intent_id,"payload_json":payload_json})
    if conn.in_transaction:raise StorageError("conversion_retry_requires_own_transaction")
    conn.execute("BEGIN IMMEDIATE")
    try:
        replay=conn.execute("SELECT * FROM fr_conversion_retry_intents WHERE intent_id=?",(intent_id,)).fetchone()
        if replay is not None:
            if replay["request_json"]!=requested:raise StorageError("conversion_retry_conflict")
            result=_candidate(conn,replay["candidate_id"])
        else:
            row=conn.execute("SELECT * FROM jobs WHERE dedup_key=?",("fr-conversion:"+session_id,)).fetchone()
            if row is None or row["status"]!="failed" or row["payload_json"]!=payload_json:
                raise StorageError("conversion_retry_not_available")
            job=dict(row);value,proof=source(conn,job)
            head=conn.execute("SELECT * FROM fr_conversion_heads WHERE job_id=?",(job["id"],)).fetchone()
            if head is None or head["candidate_id"]!=expected_candidate_id:
                raise StorageError("conversion_retry_stale_candidate")
            previous=_candidate(conn,head["candidate_id"])
            if previous["status"]!="failed":raise StorageError("conversion_retry_not_available")
            result=_create_candidate(conn,job,value,proof,previous["generation"]+1)
            conn.execute("INSERT INTO fr_conversion_retry_intents VALUES(?,?,?)",(intent_id,requested,result["candidate_id"]))
            conn.execute("UPDATE jobs SET status='queued',error_message=NULL,claimed_at=NULL,lease_expires_at=NULL WHERE id=?",(job["id"],))
            if fault is not None:fault("before_retry_commit")
        conn.commit()
    except BaseException:
        conn.rollback();raise
    if fault is not None:fault("after_retry_commit")
    return result
