"""TEST ONLY. Explicit injection, never imported by the production application.

The HTTP supervisor may use this factory only with its reviewed loopback,
disposable DB/media, isolated secret and fixture-only provenance. The canonical
wire is exercised; these bytes/proofs are not a Rec.709 conversion result.
"""
import asyncio
from contextlib import closing
import hashlib
import json

from app.db.connection import connect
from app.repositories import frame_relay_publication as repository
from app.repositories.jobs import claim_next_job
from app.services import frame_relay_storage as storage
from app.services.frame_relay_finalize import process_finalize
from app.services.frame_relay_conversion import CandidateReceipt, process_conversion
from app.services.frame_relay_publication import PublicationService, container_type


class FixturePublicationAuthority:
    def check_candidate(self, conn, candidate, evidence, output, original):
        if (output.get("schema_version") != "fr-unpublished-candidate-v1" or
                output.get("published") is not False or output.get("rec709_verified") is not False or
                output.get("receipt", {}).get("result_kind") != "unpublished_technical_fixture" or
                output["receipt"]["adapter_identity"] != "fr-publication-container-fixture-v1"):
            raise repository.PublicationError("publication_fixture_proof_invalid")
        return {"proof_kind": "technical_fixture", "media_type": "video/quicktime",
            "proof": {"fixture_only": True, "candidate_id": candidate["candidate_id"],
                "evidence_id": evidence["evidence_id"], "output": output},
            "transform": {"input_log_identity": "fixture-only-input-not-log-detection",
                "transform_asset_identity": "fixture-only-copy-not-standard-conversion",
                "transform_asset_version": "fixture-v1", "output_configuration_identity": "fixture-quicktime-not-selected-output",
                "conversion_version": "fixture-v1"}}

    def check_artifact(self, conn, artifact):
        source = repository.candidate(conn, artifact["candidate_id"])
        expected = self.check_candidate(conn, *source)
        if (artifact["proof_kind"] != "technical_fixture" or json.loads(artifact["proof_json"]) != expected["proof"] or
                artifact["media_type"] != expected["media_type"]):
            raise repository.PublicationError("publication_fixture_proof_invalid")


class _FixtureCopyAdapter:
    contract_version = "fr-conversion-adapter-v1"
    result_kind = "unpublished_technical_fixture"
    identity = "fr-publication-container-fixture-v1"

    def __init__(self, movie_bytes):
        if container_type(movie_bytes[:65_536], len(movie_bytes)) != "video/quicktime":
            raise ValueError("Fixture requires actual QuickTime container identity")
        self.movie_bytes = movie_bytes

    def accepts_source(self, _context):
        return True

    def convert(self, *, context, source, destination, progress):
        value = source.read()
        if len(value) != context.source_byte_count or hashlib.sha256(value).hexdigest() != context.source_sha256:
            raise ValueError("Fixture input mismatch")
        destination.write(self.movie_bytes)
        progress("fixture_copy_terminal")
        return CandidateReceipt(context, self.identity, hashlib.sha256(self.movie_bytes).hexdigest(), len(self.movie_bytes))


def fixture_service(settings):
    return PublicationService(settings, authority=FixturePublicationAuthority())


def seed_candidate(settings, registration, secret, movie_bytes, capture_id, operation_id, *, source_bytes=None):
    """Single-owner fixture preparation; do not run beside queued fixture work.

    Repeat with the same capture/source bytes and a new upload operation to get
    a second candidate for the SAME OriginalContent. movie_bytes may differ;
    pass the original source_bytes explicitly in that case. No direct DB seed
    substitutes for S24 receiving/finalization or S26J's fenced conversion.
    """
    data = movie_bytes if source_bytes is None else source_bytes
    request = {"destination_id": registration["destination_id"], "registration_id": registration["registration_id"],
        "registration_generation": registration["generation"], "operation_id": operation_id, "capture_id": capture_id,
        "content_generation": "1", "sha256": hashlib.sha256(data).hexdigest(), "byte_count": str(len(data))}
    value = storage.create(settings, request, secret)
    async def chunks():
        for index, start in enumerate(range(0, len(data), value["chunk_size"])):
            chunk = data[start:start + value["chunk_size"]]
            async def body():
                yield chunk
            await storage.receive_chunk(settings, value["session_id"], request, secret, index,
                (start, start + len(chunk) - 1, len(data)), hashlib.sha256(chunk).hexdigest(), body())
    asyncio.run(chunks())
    storage.finalize(settings, value["session_id"], request, secret)
    def database():
        return closing(connect(settings.database_path, settings.sqlite_busy_timeout_ms))
    with database() as conn:
        job = claim_next_job(conn, settings.job_lease_seconds, {"fr_upload_finalize"})
    if job is None or json.loads(job["payload_json"])["session_id"] != value["session_id"]:
        raise ValueError("Fixture seed is not the sole finalization owner")
    process_finalize(settings=settings, job=job)
    with database() as conn:
        job = claim_next_job(conn, settings.job_lease_seconds, {"fr_conversion"})
    if job is None or json.loads(job["payload_json"])["session_id"] != value["session_id"]:
        raise ValueError("Fixture seed is not the sole conversion owner")
    process_conversion(settings=settings, job=job, adapter=_FixtureCopyAdapter(movie_bytes))
    with database() as conn:
        candidate, evidence, _output, original = repository.candidate(conn, job["fr_conversion_candidate"])
    return {"candidate_id": candidate["candidate_id"], "session_id": value["session_id"],
        "evidence_id": evidence["evidence_id"], "asset_id": evidence["asset_id"], "original": original,
        "movie_sha256": hashlib.sha256(movie_bytes).hexdigest(), "media_type": "video/quicktime", "binding": request}
