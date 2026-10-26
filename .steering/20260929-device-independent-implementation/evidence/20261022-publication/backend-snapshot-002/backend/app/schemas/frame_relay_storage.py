from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.schemas.registrations import CanonicalID


class StorageBindingRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    destination_id: CanonicalID
    registration_id: CanonicalID
    registration_generation: str
    operation_id: CanonicalID
    capture_id: str
    content_generation: str
    sha256: Annotated[str, Field(pattern=r"^[0-9a-f]{64}$")]
    byte_count: str

    @field_validator("capture_id")
    @classmethod
    def opaque_capture_identity(cls, value):
        # CaptureID is opaque on the device. Never trim, case-fold, parse it as
        # a UUID, or use it to choose a filesystem path.
        if not value.strip():
            raise ValueError("Expected nonblank capture identity")
        try:
            value.encode("utf-8")
        except UnicodeEncodeError:
            raise ValueError("Expected UTF-8 capture identity") from None
        return value

    @field_validator("registration_generation", "content_generation", "byte_count")
    @classmethod
    def canonical_unsigned(cls, value, info):
        if not value.isascii() or not value.isdigit() or str(int(value)) != value:
            raise ValueError("Expected canonical decimal string")
        maximum = (1 << 63) - 1 if info.field_name == "registration_generation" else (1 << 64) - 1
        if not 1 <= int(value) <= maximum:
            raise ValueError("Integer outside explicit wire range")
        return value
