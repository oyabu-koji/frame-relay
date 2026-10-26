nonisolated enum RemovalPurpose: Equatable, Sendable, Codable { case cleanup, discard }

nonisolated struct RemovalIntent: Equatable, Sendable, Codable {
    let operation: MediaOperationID
    let original: OriginalContent
    let purpose: RemovalPurpose
}

nonisolated struct InvalidationPermit: Equatable, Sendable, Codable { let record: InvalidationRecord }

nonisolated enum RemovalResolution: Equatable, Sendable, Codable { case removed, notRemoved }
nonisolated struct RemovalResolutionReceipt: Equatable, Sendable {
    let intent: RemovalIntent
    let resolution: RemovalResolution
}

nonisolated enum OriginalOrderingReservation: Equatable, Sendable {
    case idle
    case invalidating(InvalidationPermit)
    case removing(RemovalIntent)
    case recoveringRemoval(RemovalIntent)
}

/// This is an ordering contract. It never deletes a file or claims a removal result.
nonisolated struct OriginalOperationOrdering: Equatable, Sendable {
    let original: OriginalContent
    private(set) var invalidationGeneration: InvalidationGeneration
    private(set) var reservation: OriginalOrderingReservation

    init(original: OriginalContent, invalidationGeneration: InvalidationGeneration,
         unresolvedRemoval: RemovalIntent? = nil) throws {
        guard unresolvedRemoval == nil || unresolvedRemoval?.original == original else {
            throw BackendContractError.identityMismatch
        }
        self.original = original
        self.invalidationGeneration = invalidationGeneration
        reservation = unresolvedRemoval.map { .recoveringRemoval($0) } ?? .idle
    }

    mutating func beginInvalidation(_ record: InvalidationRecord) throws -> InvalidationPermit {
        guard reservation == .idle else { throw BackendContractError.deletionUnresolved }
        guard record.rendition.original == original,
              record.generation.rawValue > invalidationGeneration.rawValue else {
            throw BackendContractError.staleGeneration
        }
        let permit = InvalidationPermit(record: record)
        reservation = .invalidating(permit)
        return permit
    }

    mutating func finishInvalidation(_ acknowledgement: InvalidationAcknowledgement) throws {
        guard case .invalidating(let permit) = reservation,
              permit.record == acknowledgement.record, acknowledgement.isCommitted else {
            throw BackendContractError.notCommitted
        }
        invalidationGeneration = acknowledgement.record.generation
        reservation = .idle
    }

    mutating func beginRemoval(_ intent: RemovalIntent, eligibility: CleanupEligibility,
                              stopped: TransportQuiescence, expectedTransport: TransportQuiescence,
                              released: AllReadersReleasedReceipt, readers: OriginalReadersState) throws {
        guard reservation == .idle else { throw BackendContractError.deletionUnresolved }
        guard intent.original == original, stopped == expectedTransport,
              stopped.target.original == original, readers.original == original,
              readers.validates(released) else { throw BackendContractError.readersActive }
        if intent.purpose == .cleanup {
            guard eligibility == .eligible(original, invalidationGeneration) else {
                throw BackendContractError.invalidated
            }
        }
        reservation = .removing(intent)
    }

    /// Unknown leaves the reservation in place. A later invalidation must keep waiting.
    mutating func reconcileRemoval(_ intent: RemovalIntent,
                                   result: BackendOutcome<RemovalResolutionReceipt>) throws {
        guard reservation == .removing(intent) || reservation == .recoveringRemoval(intent) else {
            throw BackendContractError.identityMismatch
        }
        switch result {
        case .succeeded(let receipt):
            guard receipt.intent == intent else { throw BackendContractError.identityMismatch }
            reservation = .idle
        case .unknown, .inProgress, .failed, .notExecuted:
            reservation = .recoveringRemoval(intent)
        }
    }
}
