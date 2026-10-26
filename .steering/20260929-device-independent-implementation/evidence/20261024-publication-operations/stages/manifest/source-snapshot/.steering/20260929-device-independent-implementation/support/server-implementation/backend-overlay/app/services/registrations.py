from contextlib import closing
import sqlite3

from app.core.settings import load_settings
from app.db.connection import connect
from app.repositories import registrations as repository
from app.repositories.registrations import RegistrationError


def _with_connection(operation, **arguments):
    settings = load_settings()
    try:
        with closing(connect(settings.database_path, settings.sqlite_busy_timeout_ms)) as conn:
            return operation(conn, **arguments)
    except sqlite3.DatabaseError:
        # DB failure is not proof that a registration did not execute.
        raise RegistrationError("registration_unavailable") from None


def capabilities():
    return {"protocol_version": 1, "destination_id": _with_connection(repository.destination_identity),
            "capabilities": ["registration-intent-v1"]}


def register(*, destination_id: str, operation_id: str, secret: str):
    return _with_connection(repository.register, destination_id=destination_id,
                            operation_id=operation_id, secret=secret)


def lookup(*, destination_id: str, operation_id: str, secret: str):
    return _with_connection(repository.lookup_registration, destination_id=destination_id,
                            operation_id=operation_id, secret=secret)
