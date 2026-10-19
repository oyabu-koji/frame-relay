"""FR publication ledger. Call mutations only inside a short owned transaction."""
import hashlib
import json
from uuid import UUID

from app.db.frame_relay_migrations import validate_frame_relay_schema
from app.repositories import frame_relay_conversion as conversion
from app.repositories import registrations
from app.repositories.frame_relay_storage import canonical
from app.schemas import frame_relay_publication as wire


MAX_COUNTER = (1 << 63) - 1


class PublicationError(Exception):
    def __init__(self, code, status=409):
        self.code, self.status = code, status
        super().__init__(code)


def original_key(original):
    return hashlib.sha256(canonical(original).encode("utf-8")).hexdigest()


def registration(conn, identity, secret):
    registrations.authenticate_registration(conn, destination_id=identity["destination_id"],
        registration_id=identity["registration_id"], generation=int(identity["generation"]), secret=secret)


def public_registration(conn, registration_id):
    row = conn.execute("SELECT * FROM fr_registrations WHERE registration_id=?", (registration_id,)).fetchone()
    if row is None:
        raise PublicationError("publication_registration_missing", 503)
    return {"destination_id": row["destination_id"], "registration_id": registration_id,
            "generation": str(row["generation"])}


def head(conn, original, *, create=False):
    validate_frame_relay_schema(conn)
    key = original_key(original)
    row = conn.execute("SELECT * FROM fr_publication_heads WHERE original_key=?", (key,)).fetchone()
    if row is None and create:
        conn.execute("INSERT INTO fr_publication_heads(original_key,original_json) VALUES(?,?)", (key, canonical(original)))
        row = conn.execute("SELECT * FROM fr_publication_heads WHERE original_key=?", (key,)).fetchone()
    if row is not None and row["original_json"] != canonical(original):
        raise PublicationError("publication_original_conflict")
    return None if row is None else dict(row)


def increment(value):
    if type(value) is not int or not 0 <= value < MAX_COUNTER:
        raise PublicationError("publication_generation_exhausted")
    return value + 1


def operation(conn, kind, operation_id, registration_id=""):
    scope = registration_id
    row = conn.execute("SELECT * FROM fr_publication_operations WHERE kind=? AND operation_id=? AND registration_scope=?",
                       (kind, operation_id, scope)).fetchone()
    return None if row is None else dict(row)


def replay(conn, kind, operation_id, request, registration_id=""):
    row = operation(conn, kind, operation_id, registration_id)
    if row is None:
        return None
    if row["request_json"] != canonical(request):
        raise PublicationError("publication_operation_conflict")
    return json.loads(row["result_json"])


def record(conn, h, kind, operation_id, request, result, registration_id=""):
    if not conn.in_transaction:
        raise PublicationError("publication_transaction_required", 503)
    next_revision = increment(h["revision"])
    scope = registration_id
    conn.execute("""INSERT INTO fr_publication_operations VALUES(?,?,?,?,?,?,?,?)""",
                 (kind, operation_id, scope, h["original_key"], canonical(request), canonical(result),
                  h["revision"], next_revision))
    changed = conn.execute("UPDATE fr_publication_heads SET revision=? WHERE original_key=? AND revision=?",
                          (next_revision, h["original_key"], h["revision"])).rowcount
    if changed != 1:
        raise PublicationError("publication_revision_conflict")


def candidate(conn, candidate_id):
    item = conversion._candidate(conn, candidate_id)
    job = conn.execute("SELECT * FROM jobs WHERE id=?", (item["job_id"],)).fetchone()
    if job is None:
        raise PublicationError("publication_candidate_invalid")
    binding, evidence = conversion.source(conn, dict(job))
    if (item["status"] != "candidate_ready" or job["status"] != "done" or
            item["source_payload"] != job["payload_json"] or item["session_id"] != binding["session_id"] or
            item["evidence_id"] != evidence["evidence_id"] or item["asset_id"] != evidence["asset_id"]):
        raise PublicationError("publication_candidate_invalid")
    output = json.loads(item["output_json"])
    receipt = output.get("receipt", {})
    context = receipt.get("context", {})
    expected = {"candidate_id": candidate_id, "candidate_generation": item["generation"],
        "evidence_id": evidence["evidence_id"], "session_id": binding["session_id"],
        "asset_id": evidence["asset_id"], "source_sha256": binding["sha256"], "source_byte_count": binding["byte_count"]}
    if any(context.get(key) != value for key, value in expected.items()):
        raise PublicationError("publication_candidate_invalid")
    original = {"capture_id": binding["capture_id"], "content_generation": binding["content_generation"],
                "content": {"algorithm": "sha256", "digest": binding["sha256"], "byte_count": str(binding["byte_count"])}}
    wire.Original.model_validate(original)
    return item, evidence, output, original


def artifact(conn, rendition_id, authority):
    row = conn.execute("SELECT * FROM fr_publication_artifacts WHERE rendition_id=?", (rendition_id,)).fetchone()
    if row is None:
        raise PublicationError("publication_rendition_missing", 404)
    value = dict(row)
    try:
        if str(UUID(rendition_id)) != rendition_id or value["path"] != "publications/frame-relay/" + rendition_id + ".media":
            raise ValueError()
        identity = wire.Rendition.model_validate(json.loads(value["identity_json"])).model_dump()
        if (identity["rendition_id"] != rendition_id or original_key(identity["original"]) != value["original_key"] or
                int(identity["publication_generation"]) != value["publication_generation"] or
                identity["delivery_content"] != {"algorithm": "sha256", "digest": value["sha256"], "byte_count": str(value["byte_count"])}):
            raise ValueError()
    except (ValueError, TypeError, KeyError):
        raise PublicationError("publication_artifact_invalid", 503) from None
    authority.check_artifact(conn, value)
    return value


def install_artifact(conn, h, draft, authority):
    # Recheck the source and authority inside the commit; bytes were read outside.
    current = candidate(conn, draft["candidate_id"])
    if current != draft["source"]:
        raise PublicationError("publication_candidate_changed")
    authority.check_candidate(conn, *current)
    generation = increment(h["last_publication_generation"])
    identity = {**draft["transform"], "original": current[3], "rendition_id": draft["rendition_id"],
        "delivery_content": {"algorithm": "sha256", "digest": draft["sha256"], "byte_count": str(draft["byte_count"])},
        "publication_generation": str(generation)}
    identity = wire.Rendition.model_validate(identity).model_dump()
    conn.execute("INSERT INTO fr_publication_artifacts VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)",
        (draft["rendition_id"], draft["candidate_id"], current[1]["evidence_id"], h["original_key"], generation,
         canonical(identity), draft["path"], draft["sha256"], draft["byte_count"], draft["media_type"], canonical(draft["fingerprint"]),
         draft["proof_kind"], canonical(draft["proof"])))
    conn.execute("UPDATE fr_publication_heads SET last_publication_generation=? WHERE original_key=?", (generation, h["original_key"]))
    return artifact(conn, draft["rendition_id"], authority)


def identity(item):
    return json.loads(item["identity_json"])


def current_access(conn, rendition, reg, authority):
    item = artifact(conn, rendition["rendition_id"], authority)
    h = head(conn, rendition["original"])
    if identity(item) != rendition or h is None or h["current_rendition_id"] != rendition["rendition_id"]:
        raise PublicationError("publication_stale_rendition")
    invalidated = conn.execute("""SELECT 1 FROM fr_invalidation_acks a
        JOIN fr_publication_replacements r ON r.replacement_id=a.replacement_id
        WHERE r.previous_rendition_id=? AND a.registration_id=?""",
        (rendition["rendition_id"], reg["registration_id"])).fetchone()
    if invalidated:
        raise PublicationError("publication_invalidated")
    return h, item


def distribution(conn, request, authority):
    rendition, reg = request["rendition"], request["registration"]
    # A production process must also reject historical receipts from a fixture DB.
    artifact(conn, rendition["rendition_id"], authority)
    previous = replay(conn, "distribution", request["operation_id"], request, reg["registration_id"])
    if previous is not None:
        return previous
    h, item = current_access(conn, rendition, reg, authority)
    if request["purpose"] == "read":
        source = operation(conn, "distribution", request["source_operation_id"], reg["registration_id"])
        source_request = None if source is None else json.loads(source["request_json"])
        if (source_request is None or source_request["purpose"] != "source" or
                any(source_request[key] != request[key] for key in ("rendition", "registration", "gate"))):
            raise PublicationError("publication_source_distribution_mismatch")
    receipt = {"operation_id": request["operation_id"], "rendition": rendition, "registration": reg,
               "previous_revision": str(h["revision"]), "committed_revision": str(increment(h["revision"]))}
    result = {"receipt": receipt, "media_type": item["media_type"]}
    conn.execute("INSERT OR IGNORE INTO fr_publication_recipients VALUES(?,?,?)",
                 (rendition["rendition_id"], reg["registration_id"], request["operation_id"]))
    record(conn, h, "distribution", request["operation_id"], request, result, reg["registration_id"])
    return result


def read_request(conn, operation_id, reg, authority):
    row = operation(conn, "distribution", operation_id, reg["registration_id"])
    if row is None:
        raise PublicationError("publication_operation_not_executed", 404)
    request = json.loads(row["request_json"])
    if request["purpose"] != "read" or request["registration"] != reg:
        raise PublicationError("publication_distribution_mismatch")
    artifact(conn, request["rendition"]["rendition_id"], authority)
    return request


def admit(conn, request, fingerprint, authority):
    h, item = current_access(conn, request["rendition"], request["registration"], authority)
    accepted = read_request(conn, request["operation_id"], request["registration"], authority)
    if accepted != request or json.loads(item["fingerprint_json"]) != fingerprint:
        raise PublicationError("publication_distribution_mismatch")
    if conn.execute("SELECT 1 FROM fr_get_admissions WHERE registration_id=? AND distribution_operation_id=?",
                    (request["registration"]["registration_id"], request["operation_id"])).fetchone():
        raise PublicationError("publication_get_consumed")
    conn.execute("INSERT INTO fr_get_admissions VALUES(?,?,?,?,?,?)",
        (request["operation_id"], request["rendition"]["rendition_id"], request["registration"]["registration_id"],
         canonical(request), h["revision"], canonical(fingerprint)))


def invalidation(conn, replacement, registration_id, authority):
    item = artifact(conn, replacement["previous_rendition_id"], authority)
    return {"invalidation_id": replacement["invalidation_id"], "rendition": identity(item),
            "registration": public_registration(conn, registration_id),
            "invalidation_generation": str(replacement["invalidation_generation"])}


def pending_invalidations(conn, reg, authority, after, limit):
    rows = conn.execute("""SELECT r.* FROM fr_publication_replacements r
        JOIN fr_publication_recipients p ON p.rendition_id=r.previous_rendition_id
        WHERE r.status='pending' AND p.registration_id=? AND (? IS NULL OR r.invalidation_id COLLATE BINARY > ?) AND NOT EXISTS
        (SELECT 1 FROM fr_invalidation_acks a WHERE a.replacement_id=r.replacement_id AND a.registration_id=p.registration_id)
        ORDER BY r.invalidation_id COLLATE BINARY LIMIT ?""", (reg["registration_id"], after, after, limit + 1)).fetchall()
    return [invalidation(conn, dict(row), reg["registration_id"], authority) for row in rows]


def acknowledge(conn, request, authority):
    reg = request["registration"]
    record_value = request["acknowledgement"]["invalidation"]
    if record_value["registration"] != reg:
        raise PublicationError("publication_ack_mismatch")
    artifact(conn, record_value["rendition"]["rendition_id"], authority)
    old = replay(conn, "acknowledgement", record_value["invalidation_id"], request, reg["registration_id"])
    if old is not None:
        return old
    row = conn.execute("SELECT * FROM fr_publication_replacements WHERE invalidation_id=?", (record_value["invalidation_id"],)).fetchone()
    if row is None or row["status"] != "pending":
        raise PublicationError("publication_ack_mismatch")
    replacement = dict(row)
    expected = invalidation(conn, replacement, reg["registration_id"], authority)
    recipient = conn.execute("SELECT 1 FROM fr_publication_recipients WHERE rendition_id=? AND registration_id=?",
        (replacement["previous_rendition_id"], reg["registration_id"])).fetchone()
    h = head(conn, record_value["rendition"]["original"])
    if expected != record_value or recipient is None or h["pending_replacement_id"] != replacement["replacement_id"]:
        raise PublicationError("publication_ack_mismatch")
    conn.execute("INSERT INTO fr_invalidation_acks VALUES(?,?,?)", (replacement["replacement_id"], reg["registration_id"], canonical(request)))
    result = {"invalidation_id": record_value["invalidation_id"], "accepted": True}
    record(conn, h, "acknowledgement", record_value["invalidation_id"], request, result, reg["registration_id"])
    return result


def confirm(conn, request, authority):
    reg, proof = request["registration"], request["confirmation"]
    distribution_proof = proof["distribution"]
    artifact(conn, distribution_proof["rendition"]["rendition_id"], authority)
    previous = replay(conn, "confirmation", proof["operation_id"], request, reg["registration_id"])
    if previous is not None:
        return previous
    known = operation(conn, "distribution", distribution_proof["operation_id"], reg["registration_id"])
    if (distribution_proof["registration"] != reg or known is None or
            json.loads(known["result_json"])["receipt"] != distribution_proof):
        raise PublicationError("publication_confirmation_mismatch")
    h, _item = current_access(conn, distribution_proof["rendition"], reg, authority)
    if int(proof["invalidation_generation"]) != h["current_invalidation_generation"]:
        raise PublicationError("publication_confirmation_mismatch")
    result = {"operation_id": proof["operation_id"], "accepted": True}
    record(conn, h, "confirmation", proof["operation_id"], request, result, reg["registration_id"])
    return result


def all_acknowledged(conn, replacement):
    return conn.execute("""SELECT 1 FROM fr_publication_recipients p
        WHERE p.rendition_id=? AND NOT EXISTS(SELECT 1 FROM fr_invalidation_acks a
        WHERE a.replacement_id=? AND a.registration_id=p.registration_id) LIMIT 1""",
        (replacement["previous_rendition_id"], replacement["replacement_id"])).fetchone() is None
