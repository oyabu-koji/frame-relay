/// Supplied by the application owner after stopping actual SDK/OS users.
/// There is deliberately no default producer or positive implementation.
nonisolated struct OriginalRemovalQuiescence: Equatable, Sendable {
    let target: OriginalRemovalTarget
    let transport: TransportQuiescence
    let readers: AllReadersReleasedReceipt
}

nonisolated protocol OriginalRemovalTerminationPort: Sendable {
    func stopForRemoval(_ target: OriginalRemovalTarget) async -> BackendOutcome<OriginalRemovalQuiescence>
}

/// Final writer fence. Hashing has already finished; only the bounded synchronous
/// descriptor check/unlink is permitted inside this transaction, without await.
nonisolated struct OriginalRemovalBoundary: Equatable, Sendable {
    let batch: OriginalRemovalBatch
    let target: OriginalRemovalTarget
    let intent: RemovalIntent
    let expectedRevision: UInt64
    let expectedInvalidation: InvalidationGeneration
    let expectedAccess: AccessGeneration
    let epoch: ReaderReconciliationEpoch
}

nonisolated protocol OriginalRemovalExecutionPort: Sendable {
    func removeOriginal(batch: OriginalRemovalBatch, target: OriginalRemovalTarget,
        evidence: CleanupEvidenceSelection?, quiescence: OriginalRemovalQuiescence)
        async -> BackendOutcome<RemovalResolutionReceipt>
    /// Observation only. A reserved, still-present original is not unlinked.
    func observeRemoval(_ intent: RemovalIntent) async -> BackendOutcome<RemovalResolutionReceipt>
}
