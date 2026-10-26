CREATE TABLE fr_destination (
    singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
    destination_id TEXT NOT NULL UNIQUE,
    last_generation INTEGER NOT NULL DEFAULT 0
        CHECK (typeof(last_generation) = 'integer' AND last_generation >= 0)
);

CREATE TABLE fr_registrations (
    destination_id TEXT NOT NULL REFERENCES fr_destination(destination_id),
    operation_id TEXT NOT NULL,
    registration_id TEXT NOT NULL UNIQUE,
    generation INTEGER NOT NULL
        CHECK (typeof(generation) = 'integer' AND generation > 0),
    secret_sha256 TEXT NOT NULL CHECK (length(secret_sha256) = 64),
    created_at TEXT NOT NULL,
    PRIMARY KEY (destination_id, operation_id),
    UNIQUE (destination_id, generation)
);

CREATE TRIGGER fr_registration_no_update BEFORE UPDATE ON fr_registrations
BEGIN
    SELECT RAISE(ABORT, 'registration receipts are immutable');
END;

CREATE TRIGGER fr_registration_no_delete BEFORE DELETE ON fr_registrations
BEGIN
    SELECT RAISE(ABORT, 'registration receipts are retained');
END;

CREATE TRIGGER fr_destination_no_identity_change
BEFORE UPDATE OF destination_id, singleton ON fr_destination
BEGIN
    SELECT RAISE(ABORT, 'destination identity is immutable');
END;

CREATE TRIGGER fr_destination_no_delete BEFORE DELETE ON fr_destination
BEGIN
    SELECT RAISE(ABORT, 'destination identity is retained');
END;

CREATE TRIGGER fr_generation_no_decrease
BEFORE UPDATE OF last_generation ON fr_destination
WHEN NEW.last_generation <= OLD.last_generation
BEGIN
    SELECT RAISE(ABORT, 'registration generation must increase');
END;
