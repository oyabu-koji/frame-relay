from datetime import datetime, timezone
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, StringConstraints, field_validator


CanonicalID = Annotated[str, StringConstraints(
    strict=True, pattern=r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
    min_length=36, max_length=36,
)]


class RegistrationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, strict=True)
    destination_id: CanonicalID
    operation_id: CanonicalID


class RegistrationReceipt(RegistrationRequest):
    registration_id: CanonicalID
    generation: Annotated[str, StringConstraints(strict=True, pattern=r"^[1-9][0-9]{0,18}$")]
    created_at: Annotated[str, StringConstraints(strict=True,
        pattern=r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}\+00:00$")]

    @field_validator("generation")
    @classmethod
    def generation_in_range(cls, value: str) -> str:
        if int(value) > (1 << 63) - 1:
            raise ValueError("Generation out of range")
        return value

    @field_validator("created_at")
    @classmethod
    def timestamp_is_utc(cls, value: str) -> str:
        parsed = datetime.fromisoformat(value)
        if parsed.tzinfo != timezone.utc or parsed.isoformat(timespec="microseconds") != value:
            raise ValueError("Timestamp must be canonical UTC")
        return value


class RegistrationCapabilities(BaseModel):
    protocol_version: Literal[1] = 1
    destination_id: CanonicalID
    capabilities: list[Literal["registration-intent-v1"]]
