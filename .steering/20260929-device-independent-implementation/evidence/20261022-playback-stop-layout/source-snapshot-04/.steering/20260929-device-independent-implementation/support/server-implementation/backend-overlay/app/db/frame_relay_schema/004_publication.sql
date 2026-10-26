CREATE TABLE fr_publication_heads (
    original_key TEXT PRIMARY KEY,
    original_json TEXT NOT NULL UNIQUE,
    current_rendition_id TEXT REFERENCES fr_publication_artifacts(rendition_id),
    revision INTEGER NOT NULL DEFAULT 0 CHECK (typeof(revision)='integer' AND revision >= 0),
    last_publication_generation INTEGER NOT NULL DEFAULT 0 CHECK (last_publication_generation >= 0),
    last_invalidation_generation INTEGER NOT NULL DEFAULT 0 CHECK (last_invalidation_generation >= 0),
    current_invalidation_generation INTEGER NOT NULL DEFAULT 0 CHECK (current_invalidation_generation >= 0),
    pending_replacement_id TEXT REFERENCES fr_publication_replacements(replacement_id)
);
CREATE TABLE fr_publication_artifacts (
    rendition_id TEXT PRIMARY KEY,
    candidate_id TEXT NOT NULL UNIQUE REFERENCES fr_conversion_candidates(candidate_id),
    evidence_id TEXT NOT NULL REFERENCES fr_storage_evidence(evidence_id),
    original_key TEXT NOT NULL REFERENCES fr_publication_heads(original_key),
    publication_generation INTEGER NOT NULL CHECK (publication_generation > 0),
    identity_json TEXT NOT NULL,
    path TEXT NOT NULL UNIQUE,
    sha256 TEXT NOT NULL,
    byte_count INTEGER NOT NULL CHECK (byte_count > 0),
    media_type TEXT NOT NULL CHECK (media_type IN ('video/mp4','video/quicktime')),
    fingerprint_json TEXT NOT NULL,
    proof_kind TEXT NOT NULL,
    proof_json TEXT NOT NULL,
    UNIQUE (original_key, publication_generation)
);
CREATE TABLE fr_publication_replacements (
    replacement_id TEXT PRIMARY KEY,
    original_key TEXT NOT NULL REFERENCES fr_publication_heads(original_key),
    previous_rendition_id TEXT NOT NULL REFERENCES fr_publication_artifacts(rendition_id),
    candidate_rendition_id TEXT NOT NULL UNIQUE REFERENCES fr_publication_artifacts(rendition_id),
    invalidation_id TEXT NOT NULL UNIQUE,
    invalidation_generation INTEGER NOT NULL CHECK (invalidation_generation > 0),
    request_json TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('pending','published')),
    UNIQUE (original_key, invalidation_generation)
);
CREATE TABLE fr_publication_operations (
    kind TEXT NOT NULL CHECK (kind IN ('initial','replacement','publication','distribution','confirmation','acknowledgement')),
    operation_id TEXT NOT NULL,
    registration_scope TEXT NOT NULL,
    original_key TEXT NOT NULL REFERENCES fr_publication_heads(original_key),
    request_json TEXT NOT NULL,
    result_json TEXT NOT NULL,
    previous_revision INTEGER NOT NULL,
    committed_revision INTEGER NOT NULL CHECK (committed_revision=previous_revision+1),
    PRIMARY KEY (kind, operation_id, registration_scope)
);
CREATE TABLE fr_publication_recipients (
    rendition_id TEXT NOT NULL REFERENCES fr_publication_artifacts(rendition_id),
    registration_id TEXT NOT NULL REFERENCES fr_registrations(registration_id),
    first_distribution_id TEXT NOT NULL,
    PRIMARY KEY (rendition_id, registration_id)
);
CREATE TABLE fr_get_admissions (
    distribution_operation_id TEXT NOT NULL,
    rendition_id TEXT NOT NULL REFERENCES fr_publication_artifacts(rendition_id),
    registration_id TEXT NOT NULL REFERENCES fr_registrations(registration_id),
    request_json TEXT NOT NULL,
    publication_revision INTEGER NOT NULL,
    fingerprint_json TEXT NOT NULL,
    PRIMARY KEY (registration_id, distribution_operation_id)
);
CREATE TABLE fr_invalidation_acks (
    replacement_id TEXT NOT NULL REFERENCES fr_publication_replacements(replacement_id),
    registration_id TEXT NOT NULL REFERENCES fr_registrations(registration_id),
    request_json TEXT NOT NULL,
    PRIMARY KEY (replacement_id, registration_id)
);
CREATE TRIGGER fr_publication_head_identity BEFORE UPDATE OF original_key,original_json ON fr_publication_heads
BEGIN SELECT RAISE(ABORT,'immutable publication original'); END;
CREATE TRIGGER fr_publication_head_retained BEFORE DELETE ON fr_publication_heads
BEGIN SELECT RAISE(ABORT,'publication heads retained'); END;
CREATE TRIGGER fr_publication_artifact_immutable BEFORE UPDATE ON fr_publication_artifacts
BEGIN SELECT RAISE(ABORT,'immutable publication artifact'); END;
CREATE TRIGGER fr_publication_artifact_retained BEFORE DELETE ON fr_publication_artifacts
BEGIN SELECT RAISE(ABORT,'publication artifacts retained'); END;
CREATE TRIGGER fr_publication_replacement_identity BEFORE UPDATE OF replacement_id,original_key,previous_rendition_id,candidate_rendition_id,invalidation_id,invalidation_generation,request_json ON fr_publication_replacements
BEGIN SELECT RAISE(ABORT,'immutable replacement identity'); END;
CREATE TRIGGER fr_publication_replacement_retained BEFORE DELETE ON fr_publication_replacements
BEGIN SELECT RAISE(ABORT,'replacement records retained'); END;
CREATE TRIGGER fr_publication_operation_immutable BEFORE UPDATE ON fr_publication_operations
BEGIN SELECT RAISE(ABORT,'immutable publication operation'); END;
CREATE TRIGGER fr_publication_operation_retained BEFORE DELETE ON fr_publication_operations
BEGIN SELECT RAISE(ABORT,'publication operations retained'); END;
CREATE TRIGGER fr_publication_recipient_immutable BEFORE UPDATE ON fr_publication_recipients
BEGIN SELECT RAISE(ABORT,'immutable publication recipient'); END;
CREATE TRIGGER fr_publication_recipient_retained BEFORE DELETE ON fr_publication_recipients
BEGIN SELECT RAISE(ABORT,'publication recipients retained'); END;
CREATE TRIGGER fr_get_admission_immutable BEFORE UPDATE ON fr_get_admissions
BEGIN SELECT RAISE(ABORT,'immutable GET admission'); END;
CREATE TRIGGER fr_get_admission_retained BEFORE DELETE ON fr_get_admissions
BEGIN SELECT RAISE(ABORT,'GET admissions retained'); END;
CREATE TRIGGER fr_invalidation_ack_immutable BEFORE UPDATE ON fr_invalidation_acks
BEGIN SELECT RAISE(ABORT,'immutable invalidation acknowledgement'); END;
CREATE TRIGGER fr_invalidation_ack_retained BEFORE DELETE ON fr_invalidation_acks
BEGIN SELECT RAISE(ABORT,'invalidation acknowledgements retained'); END;
CREATE TRIGGER fr_no_legacy_active_pointer BEFORE UPDATE OF active_processed_result_id ON assets
WHEN NEW.active_processed_result_id IS NOT OLD.active_processed_result_id AND
    (EXISTS(SELECT 1 FROM fr_upload_states WHERE asset_id=OLD.id) OR
     EXISTS(SELECT 1 FROM fr_upload_bindings WHERE final_path=OLD.original_path))
BEGIN SELECT RAISE(ABORT,'FrameRelay requires publication ledger'); END;
CREATE TRIGGER fr_no_legacy_confirmation BEFORE UPDATE OF review_status ON assets
WHEN NEW.review_status IS NOT OLD.review_status AND
    (EXISTS(SELECT 1 FROM fr_upload_states WHERE asset_id=OLD.id) OR
     EXISTS(SELECT 1 FROM fr_upload_bindings WHERE final_path=OLD.original_path))
BEGIN SELECT RAISE(ABORT,'FrameRelay requires exact confirmation ledger'); END;
CREATE TRIGGER fr_no_legacy_result_insert BEFORE INSERT ON processed_results
WHEN EXISTS(SELECT 1 FROM fr_upload_states WHERE asset_id=NEW.asset_id) OR
     EXISTS(SELECT 1 FROM assets a JOIN fr_upload_bindings b ON b.final_path=a.original_path WHERE a.id=NEW.asset_id)
BEGIN SELECT RAISE(ABORT,'FrameRelay requires publication artifacts'); END;
