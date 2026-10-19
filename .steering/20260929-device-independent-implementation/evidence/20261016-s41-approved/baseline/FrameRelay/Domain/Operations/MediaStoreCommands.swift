/// One explicit change to an existing operation. Replay invokes the domain
/// transition rather than accepting caller-written private state flags.
nonisolated enum MediaRequestTransition: Equatable, Sendable, Codable {
    case pause, resume, cancel, endPlayback
    case wait(MediaWaitReason, active: Bool)
    case beginAttempt(TransferAttemptID)
    case stopped(TransportStopReceipt)
    case completed(TransportCompletionReceipt)
    case reconciled(RemoteOperationResult)
}

extension MediaRequest {
    nonisolated mutating func apply(_ transition: MediaRequestTransition) throws {
        switch transition {
        case .pause: pause()
        case .resume: try resume()
        case .cancel: cancel()
        case .endPlayback: try endPlayback()
        case .wait(let reason, let active): setWait(reason, active: active)
        case .beginAttempt(let attempt): try beginAttempt(attempt)
        case .stopped(let receipt): try observeStop(receipt)
        case .completed(let receipt): try observeCompletion(receipt)
        case .reconciled(let result): try reconcile(result)
        }
    }
}

/// An authenticated control-plane observation of a published rendition, not a
/// candidate, distribution receipt, or actual playback. Observation is monotonic
/// within registration + original, not a wall-clock timestamp.
nonisolated struct PublishedRenditionObservation: Equatable, Sendable, Codable {
    let command: MediaOperationID
    let registration: RegistrationIdentity
    let rendition: RenditionIdentity
    let observation: RemoteObservationGeneration
    let invalidationGeneration: InvalidationGeneration
}

nonisolated struct StoredPublication: Equatable, Sendable {
    let observation: PublishedRenditionObservation
    let commit: BackendCommitReceipt
}

nonisolated enum BackendSyncResponse: Equatable, Sendable, Codable {
    case confirmation(MediaOperationID)
    case invalidation(InvalidationID)
}

/// Only the response correlated to this exact durable entry retires its pending
/// delivery. Evidence and tombstones are retained after delivery.
nonisolated struct BackendSyncDelivery: Equatable, Sendable, Codable {
    let command: MediaOperationID
    let entry: BackendSyncEntry
    let registration: RegistrationIdentity
    let response: BackendSyncResponse
}

nonisolated enum MediaReaderOwner: String, CaseIterable, Hashable, Sendable, Codable {
    case transport, renditionPlayer, temporaryMedia
}

nonisolated enum MediaReadContext: Equatable, Sendable, Codable {
    case transport(TransferAttemptID)
    case playback(PlaybackSessionID)
    case temporary(TemporaryMediaID, MediaUsageID)

    var owner: MediaReaderOwner {
        switch self { case .transport: .transport; case .playback: .renditionPlayer; case .temporary: .temporaryMedia }
    }
}

/// Persist before starting SDK/OS I/O; release only after actual completion and
/// handle release. A new instance cannot release another epoch's lease by absence.
nonisolated struct MediaReadLease: Equatable, Sendable, Codable {
    let id: ReadLeaseID
    let target: MediaTarget
    let operation: MediaOperationID
    let registration: RegistrationIdentity
    let context: MediaReadContext
    var owner: MediaReaderOwner { context.owner }
    let epoch: ReaderReconciliationEpoch
    let accessGeneration: AccessGeneration
}

/// Trusted S23/S25 observer input, after enumerating all relevant SDK/OS owners.
/// Not constructed from an empty actor dictionary. The store also checks its
/// current lease set and generation. No production observer is connected in S21.
nonisolated struct MediaReaderReconciliation: Equatable, Sendable, Codable {
    let original: OriginalContent
    let accessGeneration: AccessGeneration
    let epoch: ReaderReconciliationEpoch
    let observations: [MediaReaderOwner: EvidenceID]
}

/// Lease acquisition/transport start is not distribution. `notExecuted` requires
/// the producer to establish that the server never accepted distribution for
/// this exact lease/context and that no delayed or other Range request remains.
/// HTTP failure, zero received bytes, cancellation, or an empty local dictionary
/// are not that evidence; an unresolved response remains unknown. S25 supplies
/// the actual server/SDK reconciliation, which is not connected in S21.
nonisolated struct MediaDistributionObservation: Equatable, Sendable, Codable {
    let command: MediaOperationID
    let lease: MediaReadLease
    let observation: RemoteObservationGeneration
    let result: BackendOutcome<DistributionReceipt>
}

nonisolated struct StoredMediaDistributionObservation: Equatable, Sendable {
    let observation: MediaDistributionObservation
    let commit: BackendCommitReceipt
}
