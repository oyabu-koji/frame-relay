"""Unpublished candidate orchestration. No Rec.709 adapter or publication path."""
from contextlib import closing, contextmanager
from dataclasses import asdict, dataclass
import hashlib
import json
import os
import re
import time

from app.db.connection import connect
from app.repositories import frame_relay_conversion as repository
from app.repositories import frame_relay_storage as storage
from app.repositories.frame_relay_storage import StorageError
from app.services import frame_relay_files as files


@dataclass(frozen=True)
class ConversionContext:
    candidate_id: str
    candidate_generation: int
    claim_generation: int
    claim_token: str
    evidence_id: str
    session_id: str
    asset_id: int
    source_sha256: str
    source_byte_count: int


@dataclass(frozen=True)
class CandidateReceipt:
    context: ConversionContext
    adapter_identity: str
    sha256: str
    byte_count: int
    result_kind: str = "unpublished_technical_fixture"


def database(settings):
    return closing(connect(settings.database_path,settings.sqlite_busy_timeout_ms))


def attempt_path(candidate,job):
    return ("tmp/frame-relay/conversion/"+candidate["candidate_id"]+"/"+
            str(job["fr_conversion_generation"])+"-"+job["fr_conversion_token"]+".part")


@contextmanager
def verified_input(settings,value,proof,progress):
    # Keep the same new read-only FD through the synchronous adapter's terminal
    # return. No path reopen is delegated and no SQLite writer spans this read.
    with files.parent(settings.media_root,value["final_path"]) as (directory,name):
        descriptor=os.open(name,os.O_RDONLY|os.O_NOFOLLOW,dir_fd=directory)
        with os.fdopen(descriptor,"rb") as source:
            before=files.fingerprint(os.fstat(source.fileno()))
            if before!=json.loads(proof["fingerprint_json"]):
                raise StorageError("conversion_source_changed")
            count,digest=0,hashlib.sha256()
            while block:=source.read(files.BLOCK):
                count+=len(block);digest.update(block);progress("input_read_block")
                if count>value["byte_count"]:raise StorageError("conversion_source_changed")
            if (count!=value["byte_count"] or digest.hexdigest()!=value["sha256"] or
                    before!=files.fingerprint(os.fstat(source.fileno())) or
                    before!=files.current_fingerprint(settings.media_root,value["final_path"])):
                raise StorageError("conversion_source_changed")
            source.seek(0)
            yield source,before
            if (before!=files.fingerprint(os.fstat(source.fileno())) or
                    before!=files.current_fingerprint(settings.media_root,value["final_path"])):
                raise StorageError("conversion_source_changed")


def cleanup_attempt(settings,job):
    """Only use after this synchronous attempt has terminated; stale owners fail."""
    with database(settings) as conn:
        conn.execute("BEGIN IMMEDIATE")
        try:
            _value,_proof,candidate=repository.current_claim(conn,job)
            files.remove_owned(settings.media_root,attempt_path(candidate,job))
            conn.commit()
        except BaseException:
            conn.rollback();raise


def mark_failed(settings,job,code):
    with database(settings) as conn:
        conn.execute("BEGIN IMMEDIATE")
        try:
            _value,_proof,candidate=repository.current_claim(conn,job)
            files.remove_owned(settings.media_root,attempt_path(candidate,job))
            conn.execute("UPDATE fr_conversion_candidates SET status='failed',failure_code=? WHERE candidate_id=?",
                         (code,candidate["candidate_id"]))
            conn.execute("UPDATE jobs SET status='failed',error_message=?,claimed_at=NULL,lease_expires_at=NULL WHERE id=?",
                         (code,job["id"]))
            conn.commit()
        except BaseException:
            conn.rollback();raise


def process_conversion(*,settings,job,adapter=None,fault=None):
    if job.get("fr_conversion_rejected") is True:return True
    try:
        _process(settings,job,adapter,fault)
    except Exception as error:
        allowed={"conversion_adapter_not_implemented","conversion_adapter_incompatible",
                 "conversion_receipt_invalid","conversion_source_changed","conversion_output_changed",
                 "conversion_stale_claim","conversion_candidate_binding_invalid"}
        code=error.code if isinstance(error,StorageError) and error.code in allowed else "conversion_result_unknown"
        try:
            mark_failed(settings,job,code)
        except StorageError:
            pass  # A newer claim/terminal commit owns its own failure and cleanup.
    return True


def _process(settings,job,adapter,fault):
    last_renewal=time.monotonic()
    def progress(step):
        nonlocal last_renewal
        if fault is not None:fault(step)
        if time.monotonic()-last_renewal>=min(30,settings.job_lease_seconds/3):
            with database(settings) as conn:
                conn.execute("BEGIN IMMEDIATE")
                try:
                    repository.renew_claim(conn,job,min(settings.job_lease_seconds,300));conn.commit()
                except BaseException:
                    conn.rollback();raise
            last_renewal=time.monotonic()

    def fenced_source():
        with database(settings) as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                result=repository.current_claim(conn,job);conn.commit();return result
            except BaseException:
                conn.rollback();raise

    value,proof,candidate=fenced_source()
    # The product currently has no conversion adapter. The verified durable
    # origin and current claim are enough to report that fact; do not reread a
    # potentially large original until an actual adapter can consume it.
    if adapter is None:raise StorageError("conversion_adapter_not_implemented")
    context=ConversionContext(candidate["candidate_id"],candidate["generation"],job["fr_conversion_generation"],
        job["fr_conversion_token"],proof["evidence_id"],value["session_id"],proof["asset_id"],value["sha256"],value["byte_count"])
    temporary=attempt_path(candidate,job)
    with verified_input(settings,value,proof,progress) as (source,fingerprint):
        if (getattr(adapter,"contract_version",None)!="fr-conversion-adapter-v1" or
                getattr(adapter,"result_kind",None)!="unpublished_technical_fixture" or
                not isinstance(getattr(adapter,"identity",None),str) or
                re.fullmatch(r"[a-z0-9][a-z0-9._/-]{0,127}",adapter.identity) is None or
                not callable(getattr(adapter,"accepts_source",None)) or adapter.accepts_source(context) is not True):
            raise StorageError("conversion_adapter_incompatible")
        # No adapter receives the input until both the full read and a fresh
        # current-claim check have succeeded. is_log=0 is deliberately unused.
        if fenced_source()!=(value,proof,candidate):raise StorageError("conversion_candidate_binding_invalid")
        if files.current_fingerprint(settings.media_root,value["final_path"])!=fingerprint:
            raise StorageError("conversion_source_changed")
        with files.exclusive_writer(settings.media_root,temporary) as output:
            receipt=adapter.convert(context=context,source=source,destination=output,progress=progress)
        if (type(receipt) is not CandidateReceipt or receipt.context!=context or
                receipt.adapter_identity!=adapter.identity or receipt.result_kind!="unpublished_technical_fixture" or
                type(receipt.byte_count) is not int or receipt.byte_count<=0 or
                not isinstance(receipt.sha256,str) or re.fullmatch(r"[0-9a-f]{64}",receipt.sha256) is None):
            raise StorageError("conversion_receipt_invalid")
    progress("after_adapter")  # The adapter and both its input/output FDs ended.
    measured=files.read_all(settings.media_root,temporary,fault=lambda _:progress("output_read_block"))
    if measured["byte_count"]!=receipt.byte_count or measured["sha256"]!=receipt.sha256:
        raise StorageError("conversion_output_changed")
    progress("before_candidate_publish")
    with database(settings) as conn:
        conn.execute("BEGIN IMMEDIATE")
        try:
            if repository.current_claim(conn,job)!=(value,proof,candidate):
                raise StorageError("conversion_candidate_binding_invalid")
            if (files.current_fingerprint(settings.media_root,value["final_path"])!=fingerprint or
                    files.current_fingerprint(settings.media_root,temporary)!=measured["fingerprint"]):
                raise StorageError("conversion_source_changed")
            files.publish(settings.media_root,temporary,candidate["candidate_path"])
            files.remove_owned(settings.media_root,temporary)
            conn.commit()
        except BaseException:
            conn.rollback();raise
    progress("after_candidate_publish")
    observed=files.read_all(settings.media_root,candidate["candidate_path"],fault=lambda _:progress("candidate_read_block"))
    if observed["byte_count"]!=receipt.byte_count or observed["sha256"]!=receipt.sha256:
        raise StorageError("conversion_output_changed")
    progress("before_candidate_commit")
    with database(settings) as conn:
        conn.execute("BEGIN IMMEDIATE")
        try:
            if repository.current_claim(conn,job)!=(value,proof,candidate):
                raise StorageError("conversion_candidate_binding_invalid")
            if (files.current_fingerprint(settings.media_root,value["final_path"])!=fingerprint or
                    files.current_fingerprint(settings.media_root,candidate["candidate_path"])!=observed["fingerprint"]):
                raise StorageError("conversion_source_changed")
            result={"schema_version":"fr-unpublished-candidate-v1","receipt":asdict(receipt),
                    "fingerprint":observed["fingerprint"],"published":False,"rec709_verified":False}
            conn.execute("UPDATE fr_conversion_candidates SET status='candidate_ready',output_json=? WHERE candidate_id=?",
                         (storage.canonical(result),candidate["candidate_id"]))
            conn.execute("UPDATE jobs SET status='done',error_message=NULL,claimed_at=NULL,lease_expires_at=NULL WHERE id=?",(job["id"],))
            if fault is not None:fault("after_candidate_update")
            conn.commit()
        except BaseException:
            conn.rollback();raise
    if fault is not None:fault("after_candidate_commit")
