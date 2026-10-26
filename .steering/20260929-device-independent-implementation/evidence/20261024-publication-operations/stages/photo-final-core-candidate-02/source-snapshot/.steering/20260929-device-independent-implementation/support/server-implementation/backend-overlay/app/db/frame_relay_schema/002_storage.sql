CREATE TABLE fr_upload_bindings (
    session_id TEXT PRIMARY KEY,
    destination_id TEXT NOT NULL,
    registration_id TEXT NOT NULL REFERENCES fr_registrations(registration_id),
    registration_generation INTEGER NOT NULL CHECK (registration_generation > 0),
    operation_id TEXT NOT NULL,
    capture_id TEXT NOT NULL,
    content_generation TEXT NOT NULL,
    sha256 TEXT NOT NULL,
    byte_count INTEGER NOT NULL CHECK (byte_count > 0),
    chunk_size INTEGER NOT NULL CHECK (chunk_size > 0),
    final_path TEXT NOT NULL UNIQUE,
    UNIQUE (destination_id, registration_id, operation_id)
);
CREATE TABLE fr_upload_states (
    session_id TEXT PRIMARY KEY REFERENCES fr_upload_bindings(session_id),
    status TEXT NOT NULL CHECK (status IN ('receiving','finalizing','failed','cancelled','completed')),
    finalize_job_id INTEGER UNIQUE REFERENCES jobs(id),
    asset_id INTEGER UNIQUE REFERENCES assets(id),
    evidence_id TEXT UNIQUE,
    failure_code TEXT
);
CREATE TABLE fr_upload_chunks (
    session_id TEXT NOT NULL REFERENCES fr_upload_bindings(session_id),
    chunk_index INTEGER NOT NULL CHECK (chunk_index >= 0),
    byte_count INTEGER NOT NULL CHECK (byte_count > 0),
    sha256 TEXT NOT NULL,
    path TEXT NOT NULL UNIQUE,
    PRIMARY KEY (session_id, chunk_index)
);
CREATE TABLE fr_job_claims (
    job_id INTEGER PRIMARY KEY REFERENCES jobs(id),
    session_id TEXT NOT NULL REFERENCES fr_upload_bindings(session_id),
    generation INTEGER NOT NULL CHECK (generation > 0),
    token TEXT NOT NULL UNIQUE
);
CREATE TABLE fr_storage_evidence (
    evidence_id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL UNIQUE REFERENCES fr_upload_bindings(session_id),
    asset_id INTEGER NOT NULL UNIQUE REFERENCES assets(id),
    schema_version TEXT NOT NULL CHECK (schema_version = 'fr-final-read-v1'),
    sha256 TEXT NOT NULL,
    byte_count INTEGER NOT NULL CHECK (byte_count > 0),
    final_path TEXT NOT NULL UNIQUE,
    fingerprint_json TEXT NOT NULL,
    claim_generation INTEGER NOT NULL,
    claim_token TEXT NOT NULL,
    observed_at TEXT NOT NULL
);
CREATE TRIGGER fr_binding_no_update BEFORE UPDATE ON fr_upload_bindings
BEGIN SELECT RAISE(ABORT, 'immutable FrameRelay binding'); END;
CREATE TRIGGER fr_binding_no_delete BEFORE DELETE ON fr_upload_bindings
BEGIN SELECT RAISE(ABORT, 'immutable FrameRelay binding'); END;
CREATE TRIGGER fr_chunk_no_update BEFORE UPDATE ON fr_upload_chunks
BEGIN SELECT RAISE(ABORT, 'immutable FrameRelay chunk'); END;
CREATE TRIGGER fr_chunk_no_delete BEFORE DELETE ON fr_upload_chunks
BEGIN SELECT RAISE(ABORT, 'immutable FrameRelay chunk'); END;
CREATE TRIGGER fr_evidence_no_update BEFORE UPDATE ON fr_storage_evidence
BEGIN SELECT RAISE(ABORT, 'immutable FrameRelay evidence'); END;
CREATE TRIGGER fr_evidence_no_delete BEFORE DELETE ON fr_storage_evidence
BEGIN SELECT RAISE(ABORT, 'immutable FrameRelay evidence'); END;
