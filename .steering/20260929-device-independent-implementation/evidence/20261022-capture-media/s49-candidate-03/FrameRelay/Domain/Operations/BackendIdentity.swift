// Opaque values supplied by the boundary; no URL, credential, UUID or wire format is assumed.
nonisolated struct DestinationIdentity: Hashable, Sendable, Codable { let rawValue: String }
nonisolated struct RegistrationID: Hashable, Sendable, Codable { let rawValue: String }
nonisolated struct RegistrationOperationID: Hashable, Sendable, Codable { let rawValue: String }
nonisolated struct MediaOperationID: Hashable, Sendable, Codable { let rawValue: String }
nonisolated struct TransferBatchID: Hashable, Sendable, Codable { let rawValue: String }
nonisolated struct TransferAttemptID: Hashable, Sendable, Codable { let rawValue: String }
nonisolated struct UploadSessionID: Hashable, Sendable, Codable { let rawValue: String }
nonisolated struct BackendJobID: Hashable, Sendable, Codable { let rawValue: String }
nonisolated struct RenditionID: Hashable, Sendable, Codable { let rawValue: String }
nonisolated struct PlaybackSessionID: Hashable, Sendable, Codable { let rawValue: String }
nonisolated struct InvalidationID: Hashable, Sendable, Codable { let rawValue: String }
nonisolated struct ReadLeaseID: Hashable, Sendable, Codable { let rawValue: String }
nonisolated struct ReaderReconciliationEpoch: Hashable, Sendable, Codable { let rawValue: String }
nonisolated struct TemporaryMediaID: Hashable, Sendable, Codable { let rawValue: String }
nonisolated struct MediaUsageID: Hashable, Sendable, Codable { let rawValue: String }
nonisolated struct EvidenceID: Hashable, Sendable, Codable { let rawValue: String }

// These generations cannot be substituted for CaptureGeneration or store revision.
nonisolated struct ContentGeneration: Hashable, Sendable, Codable { let rawValue: UInt64 }
nonisolated struct RegistrationGeneration: Hashable, Sendable, Codable { let rawValue: UInt64 }
nonisolated struct PublicationGeneration: Hashable, Sendable, Codable { let rawValue: UInt64 }
nonisolated struct InvalidationGeneration: Hashable, Sendable, Codable { let rawValue: UInt64 }
nonisolated struct AccessGeneration: Hashable, Sendable, Codable { let rawValue: UInt64 }
nonisolated struct RemoteObservationGeneration: Hashable, Sendable, Codable { let rawValue: UInt64 }

nonisolated struct RegistrationIdentity: Hashable, Sendable, Codable {
    let destination: DestinationIdentity
    let id: RegistrationID
    let generation: RegistrationGeneration
}

nonisolated enum BackendContractError: Error, Equatable, Sendable, Codable {
    case invalidValue, identityMismatch, staleGeneration, revisionConflict
    case wrongStage, notCommitted, unknownResult, unavailable, unsupportedVersion
    case notOnWiFi, ineligibleOriginal, duplicateTarget, awaitingAcknowledgements
    case invalidated, readersActive, deletionUnresolved
}

nonisolated enum BackendFailure: Equatable, Sendable, Codable {
    case connectionUnavailable, authenticationRequired, inaccessible, capacity
    case unknownSchema, corruptStore, contentMismatch, rejected
}

/// Unknown means reconciliation is required, never permission to create a new operation.
nonisolated enum BackendOutcome<Value: Equatable & Sendable>: Equatable, Sendable {
    case notExecuted, inProgress, succeeded(Value), failed(BackendFailure), unknown
}

nonisolated struct BackendCapabilities: Equatable, Sendable {
    let destination: DestinationIdentity
    let wireVersion: String
    let operations: Set<BackendCapability>

    func supports(_ required: Set<BackendCapability>, versions: Set<String>,
                  destination expected: DestinationIdentity) -> Bool {
        destination == expected && versions.contains(wireVersion) && required.isSubset(of: operations)
    }
}

nonisolated enum BackendCapability: Hashable, Sendable, Codable {
    case destinationIdentity, registration, registrationLookup, operationLookup
    case uploadReconciliation, verificationEvidence, renditionManifest, mediaDistribution
    case confirmationSync, invalidationFetch, invalidationAcknowledgement, publicationLookup
}

extension BackendOutcome: Codable where Value: Codable {}
