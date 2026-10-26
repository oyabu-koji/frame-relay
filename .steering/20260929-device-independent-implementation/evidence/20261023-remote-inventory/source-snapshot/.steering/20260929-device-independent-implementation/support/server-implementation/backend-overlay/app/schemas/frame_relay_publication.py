"""Explicit publication wire; never accept synthesized Swift enum JSON."""
from typing import Annotated, Literal
from uuid import UUID
from pydantic import AfterValidator, BaseModel, ConfigDict, StringConstraints, model_validator


def opaque(value):
    if not value or "\0" in value or len(value.encode("utf-8")) > 1024:
        raise ValueError("Invalid opaque identity")
    return value


def unsigned(value):
    if int(value) > (1 << 64) - 1:
        raise ValueError("UInt64 overflow")
    return value


ID = Annotated[str, AfterValidator(opaque)]
UInt = Annotated[str, StringConstraints(pattern=r"^(0|[1-9][0-9]*)$"), AfterValidator(unsigned)]
Positive = Annotated[str, StringConstraints(pattern=r"^[1-9][0-9]*$"), AfterValidator(unsigned)]
Digest = Annotated[str, StringConstraints(pattern=r"^[0-9a-f]{64}$")]
VERSION = "fr-publication-v1"


def canonical_uuid(value):
    if str(UUID(value)) != value:
        raise ValueError("Expected server canonical UUID")
    return value


ServerUUID = Annotated[str, AfterValidator(canonical_uuid)]


class Wire(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)


class Registration(Wire):
    destination_id: ID
    registration_id: ID
    generation: Positive


class Content(Wire):
    algorithm: Literal["sha256"]
    digest: Digest
    byte_count: Positive


class Original(Wire):
    capture_id: ID
    content_generation: UInt
    content: Content


class Rendition(Wire):
    original: Original
    input_log_identity: ID
    transform_asset_identity: ID
    transform_asset_version: ID
    output_configuration_identity: ID
    conversion_version: ID
    rendition_id: ServerUUID
    delivery_content: Content
    publication_generation: Positive


class Gate(Wire):
    operation_id: ID
    attempt_id: ID
    access_generation: UInt


class ByteRange(Wire):
    lower_bound: UInt
    upper_bound: Positive

    @model_validator(mode="after")
    def ordered(self):
        if int(self.lower_bound) >= int(self.upper_bound):
            raise ValueError("Empty or reversed range")
        return self


class LocalCommit(Wire):
    previous_revision: UInt
    committed_revision: UInt

    @model_validator(mode="after")
    def consecutive(self):
        if int(self.committed_revision) != int(self.previous_revision) + 1:
            raise ValueError("Not a committed revision")
        return self


class DistributionReceipt(LocalCommit):
    operation_id: ID
    rendition: Rendition
    registration: Registration


class Invalidation(Wire):
    invalidation_id: ID
    rendition: Rendition
    registration: Registration
    invalidation_generation: Positive


class Confirmation(Wire):
    operation_id: ID
    playback_session_id: ID
    distribution: DistributionReceipt
    invalidation_generation: UInt
    observation: Literal["played"]
    local_commit: LocalCommit


class Acknowledgement(Wire):
    invalidation: Invalidation
    local_commit: LocalCommit


class RegisteredRequest(Wire):
    schema_version: Literal["fr-publication-v1"]
    registration: Registration


class ManifestRequest(RegisteredRequest):
    original: Original


class DistributionRequest(RegisteredRequest):
    operation_id: ID
    rendition: Rendition
    gate: Gate
    purpose: Literal["source", "read"]
    kind: Literal["full", "range", "resume"]
    range: ByteRange | None
    source_operation_id: ID | None

    @model_validator(mode="after")
    def consistent(self):
        if self.purpose == "source":
            if self.kind != "full" or self.range is not None or self.source_operation_id is not None:
                raise ValueError("Invalid source distribution")
        elif self.source_operation_id is None or self.source_operation_id == self.operation_id:
            raise ValueError("Read requires a separate source distribution")
        if (self.kind == "full") != (self.range is None):
            raise ValueError("Range/kind mismatch")
        if self.range is not None and int(self.range.upper_bound) > int(self.rendition.delivery_content.byte_count):
            raise ValueError("Range exceeds rendition")
        return self


class LookupRequest(RegisteredRequest):
    kind: Literal["distribution", "confirmation", "acknowledgement"]
    operation_id: ID


class ConfirmationRequest(RegisteredRequest):
    confirmation: Confirmation


class AcknowledgementRequest(RegisteredRequest):
    acknowledgement: Acknowledgement


class InvalidationsRequest(RegisteredRequest):
    after_invalidation_id: ID | None
    limit: Positive

    @model_validator(mode="after")
    def bounded(self):
        if int(self.limit) > 8:
            raise ValueError("Page limit exceeds 8")
        return self
