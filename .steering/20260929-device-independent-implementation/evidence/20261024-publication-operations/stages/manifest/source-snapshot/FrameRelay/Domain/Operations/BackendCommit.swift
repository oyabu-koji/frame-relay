import Foundation

/// Persisted in the common writer document; never derived from a path or a file identifier.
nonisolated struct RegistrationStoreIdentity: Equatable, Hashable, Sendable, Codable {
    let rawValue: UUID
}

/// An exact semantic key, not a response code or an in-memory save notification.
nonisolated enum BackendCommitKey: Hashable, Sendable, Codable {
    case registrationIntent(RegistrationOperationID, DestinationIdentity)
    case registration(RegistrationOperationID, RegistrationIdentity)
    case batch(TransferBatchID, [BatchTarget], RegistrationIdentity)
    case request(MediaOperationID, MediaTarget, RegistrationIdentity)
    case confirmation(MediaOperationID, PlaybackSessionID, RenditionIdentity, RegistrationIdentity, InvalidationGeneration)
    case invalidation(InvalidationID, RenditionIdentity, RegistrationIdentity, InvalidationGeneration)
    case distribution(MediaOperationID, RenditionIdentity, RegistrationIdentity)
    case publication(MediaOperationID, RenditionIdentity)
    case verification(MediaOperationID, EvidenceID, RemoteOperationContext)
    case requestTransition(MediaOperationID, MediaOperationID, MediaTarget, RegistrationIdentity)
    case observedPublication(MediaOperationID, RegistrationIdentity, RenditionIdentity, RemoteObservationGeneration)
    case outboxDelivery(MediaOperationID, UInt64, RegistrationIdentity)
    case distributionObservation(MediaOperationID, ReadLeaseID, RemoteObservationGeneration)
    case temporary(MediaOperationID, TemporaryMediaID)
    case photo(MediaOperationID, PhotoRegistrationKey)
    case backgroundTask(MediaOperationID, BackgroundMediaTaskID)
    case remoteInventory(MediaOperationID, RegistrationIdentity)
    case publicationManifest(MediaOperationID, RegistrationIdentity, OriginalContent)

    var operationIdentity: BackendCommitIdentity {
        switch self {
        case .registrationIntent(let id, _): .registrationIntent(id)
        case .registration(let id, _): .registration(id)
        case .batch(let id, _, _): .batch(id)
        case .request(let id, _, _): .request(id)
        case .confirmation(let id, _, _, _, _): .confirmation(id)
        case .invalidation(let id, _, let registration, _): .invalidation(id, registration)
        case .distribution(let id, _, _): .distribution(id)
        case .publication(let id, _): .publication(id)
        case .verification(let id, _, _): .verification(id)
        case .requestTransition(let id, _, _, _): .requestTransition(id)
        case .observedPublication(let id, _, _, _): .observedPublication(id)
        case .outboxDelivery(let id, _, _): .outboxDelivery(id)
        case .distributionObservation(let id, _, _): .distributionObservation(id)
        case .temporary(let id, _): .temporary(id)
        case .photo(let id, _): .photo(id)
        case .backgroundTask(let id, _): .backgroundTask(id)
        case .remoteInventory(let id, _): .remoteInventory(id)
        case .publicationManifest(let id, _, _): .publicationManifest(id)
        }
    }
}

/// Same operation identity with a different key or mutation must be rejected, never overwritten.
nonisolated enum BackendCommitIdentity: Hashable, Sendable, Codable {
    case registrationIntent(RegistrationOperationID), registration(RegistrationOperationID)
    case batch(TransferBatchID), request(MediaOperationID), confirmation(MediaOperationID)
    case invalidation(InvalidationID, RegistrationIdentity)
    case distribution(MediaOperationID), publication(MediaOperationID)
    case verification(MediaOperationID)
    case requestTransition(MediaOperationID), observedPublication(MediaOperationID), outboxDelivery(MediaOperationID)
    case distributionObservation(MediaOperationID)
    case temporary(MediaOperationID)
    case photo(MediaOperationID)
    case backgroundTask(MediaOperationID)
    case remoteInventory(MediaOperationID)
    case publicationManifest(MediaOperationID)
}

nonisolated struct BackendCommitReceipt: Equatable, Sendable, Codable {
    let key: BackendCommitKey
    let previousRevision: UInt64
    let committedRevision: UInt64

    func matches(_ expected: BackendCommitKey, revision: UInt64) -> Bool {
        let next = revision.addingReportingOverflow(1)
        return !next.overflow && key == expected && previousRevision == revision
            && committedRevision == next.partialValue
    }
}

nonisolated enum BackendCommitResult: Equatable, Sendable, Codable {
    case committed(BackendCommitReceipt)
    case rejected(BackendContractError)
    case unavailable(BackendFailure)
    case unknown
}
