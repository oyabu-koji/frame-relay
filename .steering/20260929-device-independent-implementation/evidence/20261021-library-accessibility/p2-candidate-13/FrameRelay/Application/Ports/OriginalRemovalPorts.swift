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

/// A local factory-admission owner, separate from every invalidation barrier.
nonisolated struct OriginalRemovalAdmissionSeal: Equatable, Sendable {
    let batch: MediaOperationID
    let target: OriginalRemovalTarget
    let nonce: String
}

/// Constructed only from fresh SDK/OS observations and the exact durable row.
/// It permits new factories; it never restarts an old player or transport.
nonisolated struct OriginalRemovalAdmissionRelease: Equatable, Sendable {
    let seal: OriginalRemovalAdmissionSeal
    let epoch: ReaderReconciliationEpoch
    let access: AccessGeneration
    let invalidation: InvalidationGeneration
    let resolution: RemovalResolution?

    func validates(_ snapshot: OriginalStoreSnapshot) -> Bool {
        guard snapshot.reconciliationEpoch == epoch,
              let batch = snapshot.removalBatches.first(where: { $0.batch.operation == seal.batch }),
              let row = batch.targets.first(where: { $0.target == seal.target }),
              let state = snapshot.logicalOriginals.first(where: { $0.original == seal.target.original }),
              state.accessGeneration == access, state.invalidationGeneration == invalidation,
              state.readersReleased(in: epoch) else { return false }
        switch row.status {
        case .notExecuted: return resolution == nil
        case .resolved(let observed): return resolution == observed
        case .unprocessed, .reserved: return false
        }
    }
}

/// Upload history only. Actual SDK/rendition owners require a separate terminal
/// inventory even when this returns true.
nonisolated enum OriginalRemovalTransportHistory {
    static func neverStarted(_ original: OriginalContent, backend: BackendStoreSnapshot) -> Bool {
        backend.requests.filter { $0.target == .original(original) }.allSatisfy {
            $0.attempt == nil && $0.session == nil && $0.transport == .queued
        } && !backend.verifications.contains(where: { $0.expected.target == .original(original) })
    }
}
