from fastapi import APIRouter, Depends, Header, Request, HTTPException
from fastapi.responses import JSONResponse
from pydantic import ValidationError

from app.api.deps import require_bearer_token
from app.api.registrations import require_registration_secret
from app.core.settings import load_settings
from app.schemas.frame_relay_storage import StorageBindingRequest
from app.schemas.upload_sessions import parse_content_range, validate_chunk_sha256
from app.services import frame_relay_storage as service
from app.repositories.frame_relay_storage import StorageError


router = APIRouter(prefix="/frame-relay/v1/uploads", tags=["frame-relay-storage"],
    dependencies=[Depends(require_bearer_token)])


def response(value):
    return JSONResponse(content=value, headers={"Cache-Control": "no-store"})


def require_binding(request: Request):
    if len(request.query_params.multi_items()) != len(request.query_params):
        raise HTTPException(status_code=422, detail="Invalid storage binding")
    try:
        return StorageBindingRequest.model_validate(dict(request.query_params))
    except ValidationError:
        raise HTTPException(status_code=422, detail="Invalid storage binding") from None


@router.post("")
def create(request: StorageBindingRequest, secret: str = Depends(require_registration_secret)):
    value = service.create(load_settings(), request.model_dump(), secret)
    return response({"binding": service.public_binding(value)})


@router.get("/{session_id}")
def lookup(session_id: str, binding: StorageBindingRequest = Depends(require_binding),
           secret: str = Depends(require_registration_secret)):
    return response(service.lookup(load_settings(), session_id, binding.model_dump(), secret))


@router.post("/{session_id}/finalize")
def finalize(session_id: str, binding: StorageBindingRequest = Depends(require_binding),
             secret: str = Depends(require_registration_secret)):
    return response(service.finalize(load_settings(), session_id, binding.model_dump(), secret))


@router.delete("/{session_id}")
def cancel(session_id: str, binding: StorageBindingRequest = Depends(require_binding),
           secret: str = Depends(require_registration_secret)):
    return response(service.cancel(load_settings(), session_id, binding.model_dump(), secret))


@router.put("/{session_id}/chunks/{index}")
async def chunk(session_id: str, index: int, request: Request,
                binding: StorageBindingRequest = Depends(require_binding), secret: str = Depends(require_registration_secret),
                content_range: str | None = Header(default=None, alias="Content-Range"),
                sha256: str | None = Header(default=None, alias="X-Chunk-SHA256")):
    try:
        parsed = parse_content_range(content_range)
        digest = validate_chunk_sha256(sha256)
    except ValueError:
        raise StorageError("storage_chunk_request_invalid") from None
    return response(await service.receive_chunk(load_settings(), session_id, binding.model_dump(), secret,
        index, parsed, digest, request.stream()))
