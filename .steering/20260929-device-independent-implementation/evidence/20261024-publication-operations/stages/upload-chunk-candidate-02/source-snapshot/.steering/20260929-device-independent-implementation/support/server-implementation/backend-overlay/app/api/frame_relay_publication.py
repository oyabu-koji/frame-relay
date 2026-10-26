"""Canonical product wire; only the normal production authority is wired here."""
import json
import sqlite3

from fastapi import APIRouter, Depends, Request
from fastapi.responses import Response, StreamingResponse
from pydantic import ValidationError
from starlette.concurrency import run_in_threadpool

from app.api.deps import require_bearer_token
from app.api.registrations import require_registration_secret
from app.core.settings import load_settings
from app.repositories.frame_relay_publication import PublicationError
from app.repositories.frame_relay_storage import StorageError
from app.repositories.registrations import RegistrationError
from app.services.frame_relay_publication import PublicationService, json_bytes
from app.services.frame_relay_distribution import open_stream, parse_header_id


def response(value, status=200):
    encoded = value if isinstance(value, bytes) else json_bytes(value)
    return Response(content=encoded, status_code=status, media_type="application/json", headers={"Cache-Control": "no-store"})


def error_response(error):
    if isinstance(error, PublicationError):
        code, status = error.code, error.status
    elif isinstance(error, RegistrationError):
        code = error.code
        status = 403 if code == "registration_credentials_invalid" else 409 if code == "destination_mismatch" else 503
    elif isinstance(error, (ValidationError, ValueError, UnicodeError)):
        code, status = "publication_request_invalid", 422
    elif isinstance(error, StorageError):
        code, status = "publication_artifact_changed", 409
    else:
        code, status = "publication_result_unknown", 503
    return response({"schema_version": "fr-publication-v1", "code": code, "retryable": status == 503}, status)


ERRORS = (PublicationError, RegistrationError, ValidationError, StorageError, sqlite3.DatabaseError, OSError, ValueError)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate key")
        result[key] = value
    return result


async def request_json(request):
    data = bytearray()
    async for block in request.stream():
        data.extend(block)
        if len(data) > 262_144:
            raise PublicationError("publication_request_too_large", 422)
    def nonfinite(_value):
        raise ValueError("Non-finite JSON")
    return json.loads(data.decode("utf-8"), object_pairs_hook=unique_object, parse_constant=nonfinite)


class PinnedResponse(StreamingResponse):
    def __init__(self, accepted):
        self.accepted = accepted
        super().__init__(iter(accepted), status_code=accepted.status_code, headers=accepted.headers)

    async def __call__(self, scope, receive, send):
        try:
            await super().__call__(scope, receive, send)
        finally:
            # Includes body-not-started, disconnect, iterator exception and task cancellation.
            self.accepted.close()


def create_router(service_provider):
    """Tests may supply a tests-owned factory; no config or HTTP selects authority."""
    router = APIRouter(prefix="/frame-relay/v1/publication", tags=["frame-relay-publication"],
                       dependencies=[Depends(require_bearer_token)])

    def control(method_name):
        async def endpoint(request: Request, secret: str = Depends(require_registration_secret)):
            try:
                payload = await request_json(request)
                service = service_provider()
                return response(await run_in_threadpool(getattr(service, method_name), payload, secret))
            except ERRORS as error:
                return error_response(error)
        return endpoint

    for path, method in (("/manifest", "manifest"), ("/distributions", "accept_distribution"),
            ("/operations/lookup", "lookup"), ("/confirmations", "confirm"),
            ("/invalidations", "invalidations"), ("/acknowledgements", "acknowledge")):
        router.add_api_route(path, control(method), methods=["POST"])

    @router.get("/media/{rendition_id}")
    def media(rendition_id: str, request: Request, secret: str = Depends(require_registration_secret)):
        try:
            query = request.query_params
            if len(query.multi_items()) != len(query) or set(query) != {"destination_id", "registration_id", "registration_generation"}:
                raise PublicationError("publication_request_invalid", 422)
            def header(name, *, optional=False):
                values = request.headers.getlist(name)
                if len(values) > 1 or (not values and not optional):
                    raise PublicationError("publication_header_invalid", 422)
                return values[0] if values else None
            if header("Accept-Encoding") != "identity":
                raise PublicationError("publication_encoding_invalid", 422)
            accepted = open_stream(service_provider(), rendition_id=rendition_id,
                registration={"destination_id": query["destination_id"], "registration_id": query["registration_id"],
                              "generation": query["registration_generation"]}, secret=secret,
                operation_id=parse_header_id(header("X-FrameRelay-Distribution-ID")),
                gate={"operation_id": parse_header_id(header("X-FrameRelay-Transport-ID")),
                      "attempt_id": parse_header_id(header("X-FrameRelay-Attempt-ID")),
                      "access_generation": header("X-FrameRelay-Access-Generation")},
                range_header=header("Range", optional=True))
            return PinnedResponse(accepted)
        except ERRORS as error:
            return error_response(error)
    return router


router = create_router(lambda: PublicationService(load_settings()))
