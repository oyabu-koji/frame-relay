"""FrameRelay's separate ledger; never append versions to the legacy ledger."""
import hashlib
from pathlib import Path
import sqlite3
from uuid import uuid4


SCHEMA = Path(__file__).parent / "frame_relay_schema/001_registrations.sql"
VERSION = "001_registrations"
STORAGE_SCHEMA = Path(__file__).parent / "frame_relay_schema/002_storage.sql"


def migration_sources():
    return [(VERSION, SCHEMA), ("002_storage", STORAGE_SCHEMA)]


class FrameRelaySchemaError(sqlite3.DatabaseError):
    pass


def validate_frame_relay_schema(conn: sqlite3.Connection) -> None:
    expected = [(version, hashlib.sha256(path.read_bytes()).hexdigest())
                for version, path in migration_sources()]
    versions = [tuple(row) for row in conn.execute(
        "SELECT version, sha256 FROM fr_schema_migrations ORDER BY version"
    )]
    if versions != expected:
        raise FrameRelaySchemaError("Unsupported FrameRelay schema identity")


def run_frame_relay_migrations(conn: sqlite3.Connection) -> None:
    if conn.in_transaction:
        raise RuntimeError("FrameRelay migration requires its own transaction")
    sources = [(version, path.read_text(encoding="utf-8")) for version, path in migration_sources()]
    expected = [(version, hashlib.sha256(sql.encode()).hexdigest()) for version, sql in sources]
    try:
        conn.execute("BEGIN IMMEDIATE")
        conn.execute("""CREATE TABLE IF NOT EXISTS fr_schema_migrations (
            version TEXT PRIMARY KEY, sha256 TEXT NOT NULL
        )""")
        versions = [tuple(row) for row in conn.execute(
            "SELECT version, sha256 FROM fr_schema_migrations ORDER BY version"
        )]
        if versions != expected[:len(versions)]:
            raise FrameRelaySchemaError("Unsupported FrameRelay schema identity")
        for (version, sql), (_version, digest) in zip(sources[len(versions):], expected[len(versions):]):
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
            if version == VERSION:
                conn.execute("INSERT INTO fr_destination (singleton, destination_id) VALUES (1, ?)",
                             (str(uuid4()),))
            conn.execute("INSERT INTO fr_schema_migrations (version, sha256) VALUES (?, ?)",
                         (version, digest))
        if conn.execute("SELECT COUNT(*) FROM fr_destination WHERE singleton = 1").fetchone()[0] != 1:
            raise FrameRelaySchemaError("FrameRelay destination missing; refusing replacement identity")
        conn.commit()
    except BaseException:
        conn.rollback()
        raise
