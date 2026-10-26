"""Append-only receipts bound to one DB identity, intent and private credential."""
from collections.abc import Callable
from datetime import datetime, timezone
import hashlib
import hmac
import re
import sqlite3
from uuid import uuid4

from pydantic import ValidationError

from app.db.frame_relay_migrations import validate_frame_relay_schema
from app.schemas.registrations import RegistrationReceipt


MAX_GENERATION = (1 << 63) - 1


class RegistrationError(Exception):
    def __init__(self, code: str):
        self.code = code
        super().__init__(code)


def destination_identity(conn: sqlite3.Connection) -> str:
    validate_frame_relay_schema(conn)
    row = conn.execute("SELECT destination_id, last_generation FROM fr_destination WHERE singleton = 1").fetchone()
    if row is None or type(row["last_generation"]) is not int or not 0 <= row["last_generation"] <= MAX_GENERATION:
        raise RegistrationError("registration_unavailable")
    if not isinstance(row["destination_id"], str) or re.fullmatch(
        r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", row["destination_id"]
    ) is None:
        raise RegistrationError("registration_unavailable")
    return row["destination_id"]


def _check_destination(conn: sqlite3.Connection, destination_id: str) -> None:
    if destination_identity(conn) != destination_id:
        raise RegistrationError("destination_mismatch")


def _secret_digest(destination_id: str, operation_id: str, secret: str) -> str:
    bound = "frame-relay-registration-v1\0" + destination_id + "\0" + operation_id + "\0" + secret
    return hashlib.sha256(bound.encode("ascii")).hexdigest()


def _authenticate(row: sqlite3.Row, secret: str) -> None:
    _receipt(row)  # Reject damaged identity/timestamp before digest computation.
    if type(row["secret_sha256"]) is not str or re.fullmatch(r"[0-9a-f]{64}", row["secret_sha256"]) is None:
        raise RegistrationError("registration_unavailable")
    expected = _secret_digest(row["destination_id"], row["operation_id"], secret)
    if not hmac.compare_digest(row["secret_sha256"], expected):
        raise RegistrationError("registration_credentials_invalid")


def _receipt(row: sqlite3.Row) -> dict[str, str]:
    if type(row["generation"]) is not int or not 1 <= row["generation"] <= MAX_GENERATION:
        raise RegistrationError("registration_unavailable")
    values = {key: row[key] for key in (
        "destination_id", "operation_id", "registration_id", "generation", "created_at"
    )}
    values["generation"] = str(values["generation"])
    try:
        return RegistrationReceipt.model_validate(values).model_dump()
    except ValidationError:
        raise RegistrationError("registration_unavailable") from None


def lookup_registration(conn: sqlite3.Connection, *, destination_id: str,
                        operation_id: str, secret: str) -> dict[str, str] | None:
    _check_destination(conn, destination_id)
    row = conn.execute("SELECT * FROM fr_registrations WHERE destination_id = ? AND operation_id = ?",
                       (destination_id, operation_id)).fetchone()
    if row is None:
        return None  # Only successful, correctly bound DB lookup proves absence.
    _authenticate(row, secret)
    return _receipt(row)


def authenticate_registration(conn: sqlite3.Connection, *, destination_id: str,
                              registration_id: str, generation: int, secret: str) -> dict[str, str]:
    """Future consumers must check the exact registration/generation, never latest."""
    if type(generation) is not int or not 1 <= generation <= MAX_GENERATION:
        raise RegistrationError("registration_credentials_invalid")
    _check_destination(conn, destination_id)
    row = conn.execute("""SELECT * FROM fr_registrations
        WHERE destination_id = ? AND registration_id = ? AND generation = ?""",
        (destination_id, registration_id, generation)).fetchone()
    if row is None:
        raise RegistrationError("registration_credentials_invalid")
    _authenticate(row, secret)
    return _receipt(row)


def register(conn: sqlite3.Connection, *, destination_id: str, operation_id: str,
             secret: str, fault: Callable[[str], None] | None = None) -> dict[str, str]:
    """Serialize allocations and atomically persist identity, digest and receipt.

    fault is an in-process test seam, never configured by an HTTP request.
    A post-commit exception is deliberately NOT evidence of nonexecution.
    """
    if conn.in_transaction:
        raise RuntimeError("Registration requires its own transaction")
    try:
        conn.execute("BEGIN IMMEDIATE")
        existing = lookup_registration(conn, destination_id=destination_id,
                                       operation_id=operation_id, secret=secret)
        if existing is not None:
            conn.commit()
            return existing
        current = conn.execute("SELECT last_generation FROM fr_destination WHERE singleton = 1").fetchone()[0]
        if current >= MAX_GENERATION:
            raise RegistrationError("registration_generation_exhausted")
        generation = current + 1
        conn.execute("UPDATE fr_destination SET last_generation = ? WHERE singleton = 1", (generation,))
        conn.execute("""INSERT INTO fr_registrations
            (destination_id, operation_id, registration_id, generation, secret_sha256, created_at)
            VALUES (?, ?, ?, ?, ?, ?)""",
            (destination_id, operation_id, str(uuid4()), generation,
             _secret_digest(destination_id, operation_id, secret),
             datetime.now(timezone.utc).isoformat(timespec="microseconds")))
        receipt = lookup_registration(conn, destination_id=destination_id,
                                      operation_id=operation_id, secret=secret)
        if fault is not None:
            fault("before_commit")
        conn.commit()
    except BaseException:
        conn.rollback()
        raise
    if fault is not None:
        fault("after_commit")
    assert receipt is not None
    return receipt
