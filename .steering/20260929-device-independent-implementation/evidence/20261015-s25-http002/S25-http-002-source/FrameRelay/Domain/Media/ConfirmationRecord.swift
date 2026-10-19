nonisolated struct DistributionReceipt: Equatable, Sendable, Codable {
    let operation: MediaOperationID
    let rendition: RenditionIdentity
    let registration: RegistrationIdentity
    let commit: BackendCommitReceipt

    var isCommitted: Bool {
        commit.matches(.distribution(operation, rendition, registration), revision: commit.previousRevision)
    }
}

nonisolated enum PlaybackObservation: Equatable, Sendable, Codable { case prepared, played }

/// A playback adapter may create this only after observing actual playback of the fixed bytes.
/// There is deliberately no whole-file / whole-duration requirement.
nonisolated struct PlaybackToken: Equatable, Sendable, Codable {
    let distribution: DistributionReceipt
    let session: PlaybackSessionID
    let invalidationGeneration: InvalidationGeneration
    let observation: PlaybackObservation

    init(distribution: DistributionReceipt, session: PlaybackSessionID,
         invalidationGeneration: InvalidationGeneration, observation: PlaybackObservation) throws {
        guard distribution.isCommitted else { throw BackendContractError.notCommitted }
        guard observation == .played else { throw BackendContractError.wrongStage }
        self.distribution = distribution
        self.session = session
        self.invalidationGeneration = invalidationGeneration
        self.observation = observation
    }
}

nonisolated struct ConfirmationIntent: Equatable, Sendable, Codable {
    let operation: MediaOperationID
    let playback: PlaybackToken

    var key: BackendCommitKey {
        .confirmation(operation, playback.session, playback.distribution.rendition, playback.distribution.registration,
                      playback.invalidationGeneration)
    }
}

nonisolated struct ConfirmationRecord: Equatable, Sendable, Codable {
    let intent: ConfirmationIntent
    let commit: BackendCommitReceipt
}

nonisolated struct InvalidationRecord: Hashable, Sendable, Codable {
    let id: InvalidationID
    let rendition: RenditionIdentity
    let registration: RegistrationIdentity
    let generation: InvalidationGeneration

    var key: BackendCommitKey { .invalidation(id, rendition, registration, generation) }
}

nonisolated struct InvalidationAcknowledgement: Equatable, Sendable, Codable {
    let record: InvalidationRecord
    let commit: BackendCommitReceipt

    var isCommitted: Bool { commit.matches(record.key, revision: commit.previousRevision) }
}

nonisolated struct ConfirmationState: Equatable, Sendable {
    let registration: RegistrationIdentity
    private(set) var current: RenditionIdentity
    private(set) var generation: InvalidationGeneration
    private(set) var revision: UInt64
    private(set) var confirmation: ConfirmationRecord?
    private(set) var invalidation: InvalidationAcknowledgement?
    private(set) var invalidatedRenditions: Set<RenditionID> = []

    init(registration: RegistrationIdentity, current: RenditionIdentity,
         generation: InvalidationGeneration, revision: UInt64) {
        self.registration = registration
        self.current = current
        self.generation = generation
        self.revision = revision
    }

    var validConfirmation: ConfirmationRecord? {
        guard let confirmation, isCurrent(confirmation.intent.playback),
              confirmation.commit.matches(confirmation.intent.key,
                                          revision: confirmation.commit.previousRevision) else { return nil }
        return confirmation
    }

    func prepareConfirmation(operation: MediaOperationID, playback: PlaybackToken) throws -> ConfirmationIntent {
        guard isCurrent(playback) else { throw BackendContractError.invalidated }
        return ConfirmationIntent(operation: operation, playback: playback)
    }

    mutating func commitConfirmation(_ intent: ConfirmationIntent, receipt: BackendCommitReceipt) throws {
        guard isCurrent(intent.playback) else { throw BackendContractError.invalidated }
        guard receipt.matches(intent.key, revision: revision) else { throw BackendContractError.revisionConflict }
        confirmation = ConfirmationRecord(intent: intent, commit: receipt)
        revision = receipt.committedRevision
    }

    /// Store must commit the tombstone and ACK outbox atomically, under the original's permit.
    mutating func commitInvalidation(_ record: InvalidationRecord, receipt: BackendCommitReceipt,
                                     permit: InvalidationPermit) throws -> InvalidationAcknowledgement {
        guard permit.record == record, record.registration == registration,
              record.rendition == current else { throw BackendContractError.identityMismatch }
        if let invalidation, invalidation.record == record, invalidation.commit == receipt { return invalidation }
        guard record.generation.rawValue > generation.rawValue else { throw BackendContractError.staleGeneration }
        guard receipt.matches(record.key, revision: revision) else { throw BackendContractError.revisionConflict }
        let acknowledgement = InvalidationAcknowledgement(record: record, commit: receipt)
        invalidatedRenditions.insert(record.rendition.rendition)
        generation = record.generation
        revision = receipt.committedRevision
        invalidation = acknowledgement
        return acknowledgement
    }

    mutating func observePublication(_ rendition: RenditionIdentity) throws {
        guard rendition.original == current.original else { throw BackendContractError.identityMismatch }
        guard rendition.publicationGeneration.rawValue > current.publicationGeneration.rawValue,
              !invalidatedRenditions.contains(rendition.rendition) else {
            throw BackendContractError.staleGeneration
        }
        current = rendition
    }

    /// The writer calls this only on state replayed from its current disk snapshot.
    /// Historical receipts retain their original revisions.
    func atStoreRevision(_ value: UInt64) throws -> Self {
        guard value >= revision else { throw BackendContractError.revisionConflict }
        var copy = self
        copy.revision = value
        return copy
    }

    /// The store checks whether this registration received the old rendition.
    /// A never-received published observation can advance without fabricating a
    /// local ACK; an already invalidated rendition remains tombstoned.
    mutating func adoptObservedPublication(_ rendition: RenditionIdentity,
                                           generation next: InvalidationGeneration) throws {
        guard next.rawValue >= generation.rawValue else { throw BackendContractError.staleGeneration }
        try observePublication(rendition)
        generation = next
    }

    private func isCurrent(_ token: PlaybackToken) -> Bool {
        token.distribution.isCommitted && token.distribution.registration == registration
            && token.distribution.rendition == current && token.invalidationGeneration == generation
            && !invalidatedRenditions.contains(current.rendition)
    }
}
