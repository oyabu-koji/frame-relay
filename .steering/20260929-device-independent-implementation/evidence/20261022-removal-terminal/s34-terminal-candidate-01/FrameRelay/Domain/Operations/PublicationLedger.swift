nonisolated enum MediaRetrievalKind: Equatable, Sendable { case full, range, resume }

nonisolated struct DistributionIntent: Equatable, Sendable {
    let operation: MediaOperationID
    let rendition: RenditionIdentity
    let registration: RegistrationIdentity
    let kind: MediaRetrievalKind

    var key: BackendCommitKey { .distribution(operation, rendition, registration) }
}

nonisolated struct PublicationIntent: Equatable, Sendable {
    let operation: MediaOperationID
    let previous: RenditionIdentity
    let candidate: RenditionIdentity
    let invalidationID: InvalidationID
    let invalidationGeneration: InvalidationGeneration
}

/// The server adapter runs each mutating operation in one short compare-and-commit interval.
/// It must not keep that interval open while sending media bytes or awaiting device ACKs.
nonisolated struct PublicationLedger: Equatable, Sendable {
    let destination: DestinationIdentity
    private(set) var current: RenditionIdentity
    private(set) var generation: InvalidationGeneration
    private(set) var revision: UInt64
    private(set) var recipients: Set<RegistrationIdentity> = []
    private(set) var replacement: PublicationIntent?
    private(set) var acknowledgements: Set<RegistrationIdentity> = []

    init(destination: DestinationIdentity, current: RenditionIdentity,
         generation: InvalidationGeneration, revision: UInt64) {
        self.destination = destination
        self.current = current
        self.generation = generation
        self.revision = revision
    }

    // Reading this descriptor does not register a distribution or grant byte access.
    var manifest: RenditionIdentity { current }

    mutating func commitDistribution(_ intent: DistributionIntent,
                                    receipt: BackendCommitReceipt) throws -> DistributionReceipt {
        guard intent.rendition == current, intent.registration.destination == destination else {
            throw BackendContractError.identityMismatch
        }
        guard receipt.matches(intent.key, revision: revision) else { throw BackendContractError.revisionConflict }
        recipients.insert(intent.registration)
        revision = receipt.committedRevision
        return DistributionReceipt(operation: intent.operation, rendition: current,
                                   registration: intent.registration, commit: receipt)
    }

    mutating func beginReplacement(_ intent: PublicationIntent) throws {
        guard replacement == nil, intent.previous == current,
              intent.candidate.original == current.original,
              intent.candidate.rendition != current.rendition else { throw BackendContractError.identityMismatch }
        guard intent.candidate.publicationGeneration.rawValue > current.publicationGeneration.rawValue,
              intent.invalidationGeneration.rawValue > generation.rawValue else {
            throw BackendContractError.staleGeneration
        }
        replacement = intent
        acknowledgements = []
    }

    var requiredInvalidations: Set<InvalidationRecord> {
        guard let replacement else { return [] }
        return Set(recipients.map {
            InvalidationRecord(id: replacement.invalidationID, rendition: current, registration: $0,
                               generation: replacement.invalidationGeneration)
        })
    }

    mutating func acceptAcknowledgement(_ acknowledgement: InvalidationAcknowledgement) throws {
        guard acknowledgement.isCommitted,
              requiredInvalidations.contains(acknowledgement.record) else {
            throw BackendContractError.identityMismatch
        }
        acknowledgements.insert(acknowledgement.record.registration)
    }

    mutating func commitPublication(_ receipt: BackendCommitReceipt) throws {
        guard let replacement else { throw BackendContractError.wrongStage }
        guard recipients.isSubset(of: acknowledgements) else {
            throw BackendContractError.awaitingAcknowledgements
        }
        guard receipt.matches(.publication(replacement.operation, replacement.candidate), revision: revision) else {
            throw BackendContractError.revisionConflict
        }
        current = replacement.candidate
        generation = replacement.invalidationGeneration
        revision = receipt.committedRevision
        self.replacement = nil
        recipients = []
        acknowledgements = []
    }
}
