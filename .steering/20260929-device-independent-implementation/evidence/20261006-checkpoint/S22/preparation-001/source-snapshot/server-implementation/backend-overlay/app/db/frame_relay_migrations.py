"""FrameRelay's separate ledger; never append versions to the legacy ledger."""
import hashlib
from pathlib import Path
import sqlite3
from uuid import uuid4


SCHEMA = Path(__file__).parent / "frame_relay_schema/001_registrations.sql"
VERSION = "001_registrations"


class FrameRelaySchemaError(sqlite3.DatabaseError):
    pass


def validate_frame_relay_schema(conn: sqlite3.Connection) -> None:
    digest = hashlib.sha256(SCHEMA.read_bytes()).hexdigest()
    versions = [tuple(row) for row in conn.execute(
        "SELECT version, sha256 FROM fr_schema_migrations ORDER BY version"
    )]
    if versions != [(VERSION, digest)]:
        raise FrameRelaySchemaError("Unsupported FrameRelay schema identity")


def run_frame_relay_migrations(conn: sqlite3.Connection) -> None:
    if conn.in_transaction:
        raise RuntimeError("FrameRelay migration requires its own transaction")
    sql = SCHEMA.read_text(encoding="utf-8")
    digest = hashlib.sha256(sql.encode("utf-8")).hexdigest()
    try:
        conn.execute("BEGIN IMMEDIATE")
        conn.execute("""CREATE TABLE IF NOT EXISTS fr_schema_migrations (
            version TEXT PRIMARY KEY, sha256 TEXT NOT NULL
        )""")
        versions = [tuple(row) for row in conn.execute(
            "SELECT version, sha256 FROM fr_schema_migrations ORDER BY version"
        )]
        if versions and versions != [(VERSION, digest)]:
            raise FrameRelaySchemaError("Unsupported FrameRelay schema identity")
        if not versions:
            # executescript would implicitly commit; execute complete statements
            # individually so DDL, destination and ledger stay in one transaction.
            statement = ""
            for line in sql.splitlines(keepends=True):
                statement += line
                if sqlite3.complete_statement(statement):
                    conn.execute(statement)
                    statement = ""
            if statement.strip():
                raise RuntimeError("Incomplete FrameRelay migration")
            conn.execute("INSERT INTO fr_destination (singleton, destination_id) VALUES (1, ?)",
                         (str(uuid4()),))
            conn.execute("INSERT INTO fr_schema_migrations (version, sha256) VALUES (?, ?)",
                         (VERSION, digest))
        if conn.execute("SELECT COUNT(*) FROM fr_destination WHERE singleton = 1").fetchone()[0] != 1:
            raise FrameRelaySchemaError("FrameRelay destination missing; refusing replacement identity")
        conn.commit()
    except BaseException:
        conn.rollback()
        raise
