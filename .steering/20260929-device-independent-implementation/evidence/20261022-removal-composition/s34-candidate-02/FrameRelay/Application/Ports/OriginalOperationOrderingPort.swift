nonisolated struct RemovalBoundaryRequest: Equatable, Sendable {
    let intent: RemovalIntent
    let eligibility: CleanupEligibility
    let stopped: TransportQuiescence
    let expectedTransport: TransportQuiescence
    let released: AllReadersReleasedReceipt
    let readers: OriginalReadersState
}

/// The implementation persists pending removal intent, preserves reservations across awaits,
/// and reconciles unfinished removal before allowing the next command on that original.
nonisolated protocol OriginalOperationOrderingPort: Sendable {
    func reserveInvalidation(_ record: InvalidationRecord) async -> BackendOutcome<InvalidationPermit>
    func finishInvalidation(_ acknowledgement: InvalidationAcknowledgement) async -> BackendOutcome<InvalidationID>
    func reserveRemoval(_ request: RemovalBoundaryRequest) async -> BackendOutcome<RemovalIntent>
    func reconcileRemoval(_ intent: RemovalIntent,
                          result: BackendOutcome<RemovalResolutionReceipt>) async -> BackendOutcome<RemovalIntent>
}

/// S23/S25 supply actual OS/SDK enumeration. No default implementation infers
/// termination from a new process, missing local binding, or cancellation request.
nonisolated protocol MediaReaderRecoveryPort: Sendable {
    func observeReleased(_ lease: MediaReadLease) async -> BackendOutcome<MediaReadLease>
    func observeQuiescence(original: OriginalContent, accessGeneration: AccessGeneration,
                           epoch: ReaderReconciliationEpoch) async -> BackendOutcome<MediaReaderReconciliation>
}
