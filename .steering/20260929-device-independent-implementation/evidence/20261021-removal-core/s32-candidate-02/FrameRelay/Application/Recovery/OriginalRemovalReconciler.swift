/// Reconciles durable reservations using local observations only. Restoring
/// an accepted/unprocessed batch never calls the physical deletion entry point.
actor OriginalRemovalReconciler {
    private let store: any OriginalStorePort
    private let execution: any OriginalRemovalExecutionPort

    init(store: any OriginalStorePort, execution: any OriginalRemovalExecutionPort) {
        self.store = store; self.execution = execution
    }

    func reconcile() async -> BackendOutcome<[OriginalRemovalBatchRecord]> {
        guard case .succeeded(let snapshot) = await store.loadOriginalState() else { return .unknown }
        for batch in snapshot.removalBatches {
            for target in batch.targets {
                guard case .reserved(let intent) = target.status else { continue }
                // Unknown remains reserved. It is not a reason to retry unlink.
                _ = await execution.observeRemoval(intent)
            }
        }
        guard case .succeeded(let latest) = await store.loadOriginalState() else { return .unknown }
        return .succeeded(latest.removalBatches)
    }
}
