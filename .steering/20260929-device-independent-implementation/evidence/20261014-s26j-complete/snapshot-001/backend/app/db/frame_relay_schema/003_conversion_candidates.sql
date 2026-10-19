CREATE TABLE fr_conversion_candidates (
    candidate_id TEXT PRIMARY KEY,
    job_id INTEGER NOT NULL REFERENCES jobs(id),
    session_id TEXT NOT NULL REFERENCES fr_upload_bindings(session_id),
    evidence_id TEXT NOT NULL REFERENCES fr_storage_evidence(evidence_id),
    asset_id INTEGER NOT NULL REFERENCES assets(id),
    generation INTEGER NOT NULL CHECK (typeof(generation)='integer' AND generation > 0),
    source_payload TEXT NOT NULL,
    candidate_path TEXT NOT NULL UNIQUE,
    status TEXT NOT NULL CHECK (status IN ('queued','running','failed','candidate_ready')),
    failure_code TEXT,
    output_json TEXT,
    UNIQUE (session_id, generation),
    CHECK ((status='candidate_ready') = (output_json IS NOT NULL)),
    CHECK ((status='failed') = (failure_code IS NOT NULL))
);
CREATE TABLE fr_conversion_heads (
    job_id INTEGER PRIMARY KEY REFERENCES jobs(id),
    session_id TEXT NOT NULL UNIQUE REFERENCES fr_upload_bindings(session_id),
    candidate_id TEXT NOT NULL UNIQUE REFERENCES fr_conversion_candidates(candidate_id)
);
CREATE TABLE fr_conversion_claims (
    job_id INTEGER PRIMARY KEY REFERENCES jobs(id),
    candidate_id TEXT NOT NULL REFERENCES fr_conversion_candidates(candidate_id),
    generation INTEGER NOT NULL CHECK (typeof(generation)='integer' AND generation > 0),
    token TEXT NOT NULL UNIQUE
);
CREATE TABLE fr_conversion_retry_intents (
    intent_id TEXT PRIMARY KEY,
    request_json TEXT NOT NULL,
    candidate_id TEXT NOT NULL UNIQUE REFERENCES fr_conversion_candidates(candidate_id)
);
CREATE TRIGGER fr_conversion_candidate_identity_immutable
BEFORE UPDATE OF candidate_id, job_id, session_id, evidence_id, asset_id, generation, source_payload, candidate_path
ON fr_conversion_candidates
BEGIN SELECT RAISE(ABORT, 'immutable conversion candidate identity'); END;
CREATE TRIGGER fr_conversion_candidate_retained BEFORE DELETE ON fr_conversion_candidates
BEGIN SELECT RAISE(ABORT, 'conversion candidates are retained'); END;
CREATE TRIGGER fr_conversion_retry_immutable BEFORE UPDATE ON fr_conversion_retry_intents
BEGIN SELECT RAISE(ABORT, 'immutable conversion retry intent'); END;
CREATE TRIGGER fr_conversion_retry_retained BEFORE DELETE ON fr_conversion_retry_intents
BEGIN SELECT RAISE(ABORT, 'conversion retry intents are retained'); END;
