import re

from fastapi import APIRouter, Depends, Header
from fastapi.responses import JSONResponse

from app.api.deps import require_bearer_token
from app.repositories.registrations import RegistrationError
from app.schemas.registrations import (
    CanonicalID, RegistrationCapabilities, RegistrationReceipt, RegistrationRequest,
)
from app.services import registrations as service


router = APIRouter(prefix="/frame-relay/v1", tags=["frame-relay-registration"],
                   dependencies=[Depends(require_bearer_token)])


def require_registration_secret(
    value: str | None = Header(default=None, alias="X-FrameRelay-Registration-Secret"),
) -> str:
    # Manual validation keeps the credential out of reflected validation details.
    if value is None or re.fullmatch(r"[0-9a-f]{64}", value) is None:
        from fastapi import HTTPException
        raise HTTPException(status_code=401, detail="Invalid registration credentials")
    return value


def _error(error: RegistrationError) -> JSONResponse:
    code = error.code
    status = {"destination_mismatch": 409, "registration_credentials_invalid": 403,
              "registration_generation_exhausted": 409}.get(code, 503)
    return JSONResponse(status_code=status, content={"code": code, "retryable": status == 503},
                        headers={"Cache-Control": "no-store"})


@router.get("/capabilities", response_model=RegistrationCapabilities)
def capabilities():
    try:
        return JSONResponse(content=service.capabilities(), headers={"Cache-Control": "no-store"})
    except RegistrationError as error:
        return _error(error)


@router.post("/registrations", response_model=RegistrationReceipt)
def register(request: RegistrationRequest, secret: str = Depends(require_registration_secret)):
    try:
        receipt = service.register(**request.model_dump(), secret=secret)
        return JSONResponse(content=receipt, headers={"Cache-Control": "no-store"})
    except RegistrationError as error:
        return _error(error)


@router.get("/registration-intents/{operation_id}", response_model=RegistrationReceipt)
def lookup(operation_id: CanonicalID, destination_id: CanonicalID,
           secret: str = Depends(require_registration_secret)):
    try:
        receipt = service.lookup(destination_id=destination_id, operation_id=operation_id, secret=secret)
        if receipt is None:
            return JSONResponse(status_code=404, content={"code": "registration_not_executed",
                "destination_id": destination_id, "operation_id": operation_id, "retryable": False},
                headers={"Cache-Control": "no-store"})
        return JSONResponse(content=receipt, headers={"Cache-Control": "no-store"})
    except RegistrationError as error:
        return _error(error)
