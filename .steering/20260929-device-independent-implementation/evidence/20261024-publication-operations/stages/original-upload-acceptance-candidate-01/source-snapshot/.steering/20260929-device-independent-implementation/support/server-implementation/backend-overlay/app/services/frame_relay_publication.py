"""Publication orchestration. Production quality evidence is deliberately absent."""
from contextlib import closing, contextmanager
import json
from uuid import uuid4

from app.db.connection import connect
from app.repositories import frame_relay_publication as repository
from app.repositories.frame_relay_publication import PublicationError
from app.services import frame_relay_files as files
from app.schemas import frame_relay_publication as wire


class ProductionPublicationAuthority:
    """No boolean, legacy is_log, or S26J candidate can replace S26's proof."""
    def check_candidate(self, conn, candidate, evidence, output, original):
        raise PublicationError("publication_proof_not_implemented", 503)

    def check_artifact(self, conn, artifact):
        # Also reject a fixture-populated DB when restarted by normal routers.
        raise PublicationError("publication_proof_not_implemented", 503)


def envelope(request, result):
    return {"schema_version": wire.VERSION, "request": request, "result": result}


def json_bytes(value):
    return json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(",", ":")).encode("utf-8")


def container_type(prefix, size):
    """Bounded ISO BMFF container identity only; no codec/Rec.709 claim."""
    if len(prefix) < 16 or prefix[4:8] != b"ftyp":
        raise PublicationError("publication_container_unsupported")
    box_size = int.from_bytes(prefix[:4], "big")
    if box_size < 16 or box_size > 65_536 or box_size > size or box_size > len(prefix) or box_size % 4:
        raise PublicationError("publication_container_invalid")
    brand = prefix[8:12]
    if brand == b"qt  ":
        return "video/quicktime"
    if brand in (b"isom", b"iso2", b"mp41", b"mp42", b"avc1", b"M4V "):
        return "video/mp4"
    raise PublicationError("publication_container_unsupported")


class PublicationService:
    def __init__(self, settings, *, authority=None):
        self.settings = settings
        self.authority = ProductionPublicationAuthority() if authority is None else authority

    def database(self):
        return closing(connect(self.settings.database_path, self.settings.sqlite_busy_timeout_ms))

    @contextmanager
    def transaction(self, fault=None):
        with self.database() as conn:
            conn.execute("BEGIN IMMEDIATE")
            try:
                yield conn
                if fault is not None:
                    fault("before_commit")
                conn.commit()
            except BaseException:
                conn.rollback()
                raise
            if fault is not None:
                fault("after_commit")

    def _draft(self, candidate_id, fault):
        with self.database() as conn:
            source = repository.candidate(conn, candidate_id)
            approved = self.authority.check_candidate(conn, *source)
        item, _evidence, output, _original = source
        receipt = output["receipt"]
        rendition_id = str(uuid4())
        relative = files.SEALED_PREFIX + rendition_id + ".media"
        # A new inode, not an alias to the candidate or an open adapter writer.
        with files.sealed_writer(self.settings.media_root, relative) as target:
            copied = files.read_all(self.settings.media_root, item["candidate_path"], consume=target.write,
                                    fault=None if fault is None else lambda _step: fault("candidate_read_block"))
            if (copied["fingerprint"] != output["fingerprint"] or copied["sha256"] != receipt["sha256"] or
                    copied["byte_count"] != receipt["byte_count"]):
                raise PublicationError("publication_candidate_changed")
        prefix = bytearray()
        def capture(block):
            prefix.extend(block[:max(0, 65_536 - len(prefix))])
        measured = files.read_all(self.settings.media_root, relative, consume=capture,
            fault=None if fault is None else lambda _step: fault("artifact_read_block"))
        if measured["sha256"] != copied["sha256"] or measured["byte_count"] != copied["byte_count"]:
            raise PublicationError("publication_artifact_changed")
        media_type = container_type(prefix, measured["byte_count"])
        if media_type != approved["media_type"]:
            raise PublicationError("publication_container_mismatch")
        return {"source": source, "candidate_id": candidate_id, "rendition_id": rendition_id,
                "path": relative, **measured, **approved, "media_type": media_type}

    def _draft_current(self, draft):
        if files.current_fingerprint(self.settings.media_root, draft["path"]) != draft["fingerprint"]:
            raise PublicationError("publication_artifact_changed")
        if files.current_fingerprint(self.settings.media_root, draft["source"][0]["candidate_path"]) != draft["source"][2]["fingerprint"]:
            raise PublicationError("publication_candidate_changed")

    def _internal_replay(self, kind, operation_id, request):
        with self.database() as conn:
            result = repository.replay(conn, kind, operation_id, request)
            if result is not None:
                repository.artifact(conn, result["rendition"]["rendition_id"], self.authority)
            return result

    def publish_initial(self, *, operation_id, candidate_id, expected_revision, fault=None):
        request = {"operation_id": operation_id, "candidate_id": candidate_id, "expected_revision": expected_revision}
        previous = self._internal_replay("initial", operation_id, request)
        if previous is not None:
            return previous
        draft = self._draft(candidate_id, fault)
        with self.transaction(fault) as conn:
            previous = repository.replay(conn, "initial", operation_id, request)
            if previous is not None:
                return previous
            h = repository.head(conn, draft["source"][3], create=True)
            if h["current_rendition_id"] is not None or h["revision"] != expected_revision:
                raise PublicationError("publication_revision_conflict")
            self._draft_current(draft)
            item = repository.install_artifact(conn, h, draft, self.authority)
            result = {"rendition": repository.identity(item), "media_type": item["media_type"],
                      "previous_revision": str(h["revision"]), "committed_revision": str(repository.increment(h["revision"]))}
            conn.execute("UPDATE fr_publication_heads SET current_rendition_id=? WHERE original_key=?",
                         (item["rendition_id"], h["original_key"]))
            repository.record(conn, h, "initial", operation_id, request, result)
        return result

    def begin_replacement(self, *, operation_id, candidate_id, invalidation_id, expected_revision, fault=None):
        request = {"operation_id": operation_id, "candidate_id": candidate_id, "invalidation_id": invalidation_id,
                   "expected_revision": expected_revision}
        previous = self._internal_replay("replacement", operation_id, request)
        if previous is not None:
            return previous
        draft = self._draft(candidate_id, fault)
        with self.transaction(fault) as conn:
            previous = repository.replay(conn, "replacement", operation_id, request)
            if previous is not None:
                return previous
            h = repository.head(conn, draft["source"][3])
            if (h is None or h["current_rendition_id"] is None or h["pending_replacement_id"] is not None or
                    h["revision"] != expected_revision):
                raise PublicationError("publication_revision_conflict")
            repository.artifact(conn, h["current_rendition_id"], self.authority)
            self._draft_current(draft)
            item = repository.install_artifact(conn, h, draft, self.authority)
            generation = repository.increment(h["last_invalidation_generation"])
            conn.execute("INSERT INTO fr_publication_replacements VALUES(?,?,?,?,?,?,?,'pending')",
                (operation_id, h["original_key"], h["current_rendition_id"], item["rendition_id"],
                 invalidation_id, generation, repository.canonical(request)))
            conn.execute("UPDATE fr_publication_heads SET pending_replacement_id=?,last_invalidation_generation=? WHERE original_key=?",
                         (operation_id, generation, h["original_key"]))
            result = {"replacement_id": operation_id, "rendition": repository.identity(item), "media_type": item["media_type"],
                      "invalidation_id": invalidation_id, "invalidation_generation": str(generation)}
            repository.record(conn, h, "replacement", operation_id, request, result)
        return result

    def publish_replacement(self, *, operation_id, replacement_id, expected_revision, fault=None):
        request = {"operation_id": operation_id, "replacement_id": replacement_id, "expected_revision": expected_revision}
        previous = self._internal_replay("publication", operation_id, request)
        if previous is not None:
            return previous
        with self.database() as conn:
            row = conn.execute("SELECT * FROM fr_publication_replacements WHERE replacement_id=?", (replacement_id,)).fetchone()
            if row is None:
                raise PublicationError("publication_replacement_missing", 404)
            replacement = dict(row)
            item = repository.artifact(conn, replacement["candidate_rendition_id"], self.authority)
        with files.verified_reader(self.settings.media_root, item["path"], sha256=item["sha256"],
                byte_count=item["byte_count"], expected_fingerprint=json.loads(item["fingerprint_json"]),
                fault=None if fault is None else lambda _step: fault("artifact_read_block")) as (_stream, fingerprint):
            with self.transaction(fault) as conn:
                previous = repository.replay(conn, "publication", operation_id, request)
                if previous is not None:
                    return previous
                h = repository.head(conn, repository.identity(item)["original"])
                current = conn.execute("SELECT * FROM fr_publication_replacements WHERE replacement_id=?", (replacement_id,)).fetchone()
                if (dict(current) != replacement or replacement["status"] != "pending" or
                        h["pending_replacement_id"] != replacement_id or h["revision"] != expected_revision or
                        h["current_rendition_id"] != replacement["previous_rendition_id"]):
                    raise PublicationError("publication_revision_conflict")
                if repository.artifact(conn, item["rendition_id"], self.authority) != item:
                    raise PublicationError("publication_artifact_changed")
                if files.current_fingerprint(self.settings.media_root, item["path"]) != fingerprint:
                    raise PublicationError("publication_artifact_changed")
                if not repository.all_acknowledged(conn, replacement):
                    raise PublicationError("publication_awaiting_acknowledgements")
                conn.execute("""UPDATE fr_publication_heads SET current_rendition_id=?,current_invalidation_generation=?,
                    pending_replacement_id=NULL WHERE original_key=?""",
                    (item["rendition_id"], replacement["invalidation_generation"], h["original_key"]))
                conn.execute("UPDATE fr_publication_replacements SET status='published' WHERE replacement_id=?", (replacement_id,))
                result = {"rendition": repository.identity(item), "media_type": item["media_type"],
                    "previous_revision": str(h["revision"]), "committed_revision": str(repository.increment(h["revision"]))}
                repository.record(conn, h, "publication", operation_id, request, result)
        return result

    def manifest(self, request, secret):
        request = wire.ManifestRequest.model_validate(request).model_dump()
        with self.database() as conn:
            repository.registration(conn, request["registration"], secret)
            h = repository.head(conn, request["original"])
            item = None if h is None or h["current_rendition_id"] is None else repository.artifact(conn, h["current_rendition_id"], self.authority)
            result = {"current": None if item is None else repository.identity(item),
                      "media_type": None if item is None else item["media_type"],
                      "revision": "0" if h is None else str(h["revision"]),
                      "invalidation_generation": "0" if h is None else str(h["current_invalidation_generation"]),
                      "replacement_pending": h is not None and h["pending_replacement_id"] is not None}
        return envelope(request, result)

    def accept_distribution(self, request, secret, *, fault=None):
        request = wire.DistributionRequest.model_validate(request).model_dump()
        with self.transaction(fault) as conn:
            repository.registration(conn, request["registration"], secret)
            result = repository.distribution(conn, request, self.authority)
        return envelope(request, result)

    def lookup(self, request, secret):
        request = wire.LookupRequest.model_validate(request).model_dump()
        with self.database() as conn:
            repository.registration(conn, request["registration"], secret)
            row = repository.operation(conn, request["kind"], request["operation_id"], request["registration"]["registration_id"])
            if row is None:
                raise PublicationError("publication_operation_not_executed", 404)
            original_request, original_result = json.loads(row["request_json"]), json.loads(row["result_json"])
            if original_request["registration"] != request["registration"]:
                raise PublicationError("publication_operation_conflict")
            if request["kind"] == "distribution":
                rendition = original_request["rendition"]
            elif request["kind"] == "confirmation":
                rendition = original_request["confirmation"]["distribution"]["rendition"]
            else:
                rendition = original_request["acknowledgement"]["invalidation"]["rendition"]
            repository.artifact(conn, rendition["rendition_id"], self.authority)
        return envelope(request, {"original_request": original_request, "original_result": original_result})

    def invalidations(self, request, secret):
        request = wire.InvalidationsRequest.model_validate(request).model_dump()
        with self.database() as conn:
            repository.registration(conn, request["registration"], secret)
            values = repository.pending_invalidations(conn, request["registration"], self.authority,
                request["after_invalidation_id"], int(request["limit"]))
        accepted = []
        encoded = json_bytes(envelope(request, {"invalidations": [], "next_after": None}))
        for index, value in enumerate(values[:int(request["limit"])]):
            more = index + 1 < len(values)
            candidate = json_bytes(envelope(request, {"invalidations": accepted + [value],
                "next_after": value["invalidation_id"] if more else None}))
            if len(candidate) > 196_608:
                if not accepted:
                    raise PublicationError("publication_invalidation_too_large", 503)
                break
            accepted.append(value)
            encoded = candidate
        # Return these exact bytes, not a second serializer's interpretation.
        return encoded

    def acknowledge(self, request, secret, *, fault=None):
        request = wire.AcknowledgementRequest.model_validate(request).model_dump()
        with self.transaction(fault) as conn:
            repository.registration(conn, request["registration"], secret)
            result = repository.acknowledge(conn, request, self.authority)
        return envelope(request, result)

    def confirm(self, request, secret, *, fault=None):
        request = wire.ConfirmationRequest.model_validate(request).model_dump()
        with self.transaction(fault) as conn:
            repository.registration(conn, request["registration"], secret)
            result = repository.confirm(conn, request, self.authority)
        return envelope(request, result)
