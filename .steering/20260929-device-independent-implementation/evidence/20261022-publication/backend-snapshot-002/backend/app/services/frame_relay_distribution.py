"""One real GET consumes one committed distribution, then streams its pinned FD."""
import base64
import binascii
import json
import os
import re

from app.repositories import frame_relay_publication as repository
from app.repositories.frame_relay_publication import PublicationError
from app.schemas import frame_relay_publication as wire
from app.services import frame_relay_files as files


def header_id(value):
    return base64.urlsafe_b64encode(value.encode("utf-8")).rstrip(b"=").decode("ascii")


def parse_header_id(value):
    try:
        if not isinstance(value, str) or re.fullmatch(r"[A-Za-z0-9_-]+", value) is None:
            raise ValueError()
        decoded = base64.urlsafe_b64decode(value + "=" * (-len(value) % 4)).decode("utf-8")
        wire.opaque(decoded)
        if header_id(decoded) != value:
            raise ValueError()
        return decoded
    except (ValueError, UnicodeError, binascii.Error):
        raise PublicationError("publication_header_invalid", 422) from None


def request_range(value, byte_count):
    if value is None:
        return None
    matched = re.fullmatch(r"bytes=(0|[1-9][0-9]*)-(0|[1-9][0-9]*)", value)
    if matched is None:
        raise PublicationError("publication_range_invalid", 422)
    lower, inclusive_upper = map(int, matched.groups())
    if lower > inclusive_upper or inclusive_upper >= byte_count:
        raise PublicationError("publication_range_invalid", 422)
    return {"lower_bound": str(lower), "upper_bound": str(inclusive_upper + 1)}


class AcceptedStream:
    """Ownership ends on completion, cancellation, or before-body failure.

    A pre-publication accepted response retains its old artifact. No new GET is
    authorized by this descriptor. External in-place writes can only be detected
    and aborted; already delivered bytes cannot be recalled.
    """
    def __init__(self, manager, source, fingerprint, settings, item, request):
        self.manager, self.source, self.fingerprint = manager, source, fingerprint
        self.settings, self.item, self.request = settings, item, request
        self.closed = False
        self.delivered_bytes = 0
        selected = request["range"]
        self.lower = 0 if selected is None else int(selected["lower_bound"])
        self.upper = item["byte_count"] if selected is None else int(selected["upper_bound"])
        self.status_code = 200 if selected is None else 206
        rendition = request["rendition"]
        self.headers = {"Content-Type": item["media_type"], "Content-Length": str(self.upper - self.lower),
            "Cache-Control": "no-store", "X-FrameRelay-Wire-Version": wire.VERSION,
            "X-FrameRelay-Distribution-ID": header_id(request["operation_id"]),
            "X-FrameRelay-Rendition-ID": rendition["rendition_id"],
            "X-FrameRelay-Publication-Generation": rendition["publication_generation"],
            "X-FrameRelay-Content-SHA256": item["sha256"], "X-FrameRelay-Content-Bytes": str(item["byte_count"])}
        if selected is not None:
            self.headers["Content-Range"] = f"bytes {self.lower}-{self.upper - 1}/{item['byte_count']}"

    def close(self):
        if not self.closed:
            self.closed = True
            self.manager.__exit__(None, None, None)

    def _unchanged(self):
        if (self.closed or files.fingerprint(os.fstat(self.source.fileno())) != self.fingerprint or
                files.current_fingerprint(self.settings.media_root, self.item["path"]) != self.fingerprint):
            raise PublicationError("publication_artifact_changed")

    def __iter__(self):
        try:
            self._unchanged()
            self.source.seek(self.lower)
            remaining = self.upper - self.lower
            while remaining:
                self._unchanged()
                block = self.source.read(min(65_536, remaining))
                self._unchanged()
                if not block:
                    raise PublicationError("publication_artifact_changed")
                remaining -= len(block)
                self.delivered_bytes += len(block)
                yield block
        finally:
            self.close()


def open_stream(service, *, rendition_id, registration, secret, operation_id, gate, range_header, fault=None):
    reg = wire.Registration.model_validate(registration).model_dump()
    gate = wire.Gate.model_validate(gate).model_dump()
    with service.database() as conn:
        repository.registration(conn, reg, secret)
        request = repository.read_request(conn, operation_id, reg, service.authority)
        _h, item = repository.current_access(conn, request["rendition"], reg, service.authority)
        if (request["rendition"]["rendition_id"] != rendition_id or request["gate"] != gate or
                request["range"] != request_range(range_header, item["byte_count"])):
            raise PublicationError("publication_distribution_mismatch")
        if conn.execute("SELECT 1 FROM fr_get_admissions WHERE registration_id=? AND distribution_operation_id=?",
                        (reg["registration_id"], operation_id)).fetchone():
            raise PublicationError("publication_get_consumed")
    manager = files.verified_reader(service.settings.media_root, item["path"], sha256=item["sha256"],
        byte_count=item["byte_count"], expected_fingerprint=json.loads(item["fingerprint_json"]),
        fault=None if fault is None else lambda _step: fault("artifact_read_block"))
    source, fingerprint = manager.__enter__()
    try:
        if fault is not None:
            fault("after_hash")
        with service.transaction(fault) as conn:
            repository.registration(conn, reg, secret)
            if repository.artifact(conn, rendition_id, service.authority) != item:
                raise PublicationError("publication_artifact_changed")
            if (files.fingerprint(os.fstat(source.fileno())) != fingerprint or
                    files.current_fingerprint(service.settings.media_root, item["path"]) != fingerprint):
                raise PublicationError("publication_artifact_changed")
            repository.admit(conn, request, fingerprint, service.authority)
        return AcceptedStream(manager, source, fingerprint, service.settings, item, request)
    except BaseException:
        manager.__exit__(None, None, None)
        raise
