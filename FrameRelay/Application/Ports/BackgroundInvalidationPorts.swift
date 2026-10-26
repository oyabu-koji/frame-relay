import Foundation

/// Fresh transport observations only. This is neither a removal admission seal
/// nor a new durable terminal, and it cannot start or resume any SDK task.
nonisolated struct BackgroundStoppedTransportObservation: Equatable, Sendable {
    let inventory: OriginalRemovalTransportInventory
    let stops: [TransportStopReceipt]

    func validatesHistory(_ backend: BackendStoreSnapshot) -> Bool {
        let original = inventory.original
        guard inventory.storeIdentity == backend.storeIdentity, inventory.matchesProjection(backend) else { return false }
        if stops.isEmpty {
            return OriginalRemovalTransportHistory.neverStartedForRemoval(original, backend: backend)
                && backend.backgroundTasks.allSatisfy { $0.intent.context.target.original != original }
                && backend.requests.filter { $0.target.original == original }.allSatisfy {
                    $0.attempt == nil && $0.session == nil && $0.transport == .queued
                }
        }
        guard let actual = OriginalRemovalTransportHistory.stoppedTasks(original, backend: backend),
              PublicationStoreBoundary.exact(stops, actual) else { return false }
        for task in inventory.tasks {
            guard let closed = task.events.last(where: { if case .ownerClosed = $0.change { return true }; return false }),
                  inventory.journal.contains(where: { fact in
                      guard fact.commit.committedRevision > closed.commit.committedRevision,
                            case .requestTransition(_, let operation, let target, let registration, .stopped(let receipt)) = fact.mutation.change else { return false }
                      if case .uploadChunk = task.intent.source,
                         !PublicationStoreBoundary.exact(receipt.attempt, task.intent.context.attempt) { return false }
                      return PublicationStoreBoundary.exact(operation, task.intent.context.operation)
                          && PublicationStoreBoundary.exact(target, task.intent.context.target)
                          && PublicationStoreBoundary.exact(registration, task.intent.context.registration)
                          && stops.contains(where: { PublicationStoreBoundary.exact($0, receipt) })
                  }) else { return false }
        }
        return true
    }
}

/// Bound to an actual pending invalidation and the writer's current process
/// epoch. The registry still observes all its other media owners independently.
nonisolated struct BackgroundInvalidationObservation: Equatable, Sendable {
    let record: InvalidationRecord
    let storeIdentity: RegistrationStoreIdentity
    let transport: BackgroundStoppedTransportObservation

    var inventory: OriginalRemovalTransportInventory { transport.inventory }
    var stops: [TransportStopReceipt] { transport.stops }

    func validates(record expected: InvalidationRecord, epoch: ReaderReconciliationEpoch,
                   backend: BackendStoreSnapshot) -> Bool {
        PublicationStoreBoundary.exact(record, expected)
            && storeIdentity == backend.storeIdentity && inventory.storeIdentity == storeIdentity
            && PublicationStoreBoundary.exact(inventory.epoch, epoch)
            && PublicationStoreBoundary.exact(inventory.original, expected.rendition.original)
            && transport.validatesHistory(backend)
    }
}

nonisolated protocol BackgroundInvalidationTerminationPort: Sendable {
    /// A call that issues cancellation must return inProgress, even if the
    /// callback finishes immediately. A later explicit poll observes completion.
    func stopForInvalidation(_ record: InvalidationRecord, epoch: ReaderReconciliationEpoch)
        async -> BackendOutcome<BackgroundInvalidationObservation>
    /// Observation only. It never adopts old source owners or requests a stop.
    func observeInvalidation(_ record: InvalidationRecord, epoch: ReaderReconciliationEpoch)
        async -> BackendOutcome<BackgroundInvalidationObservation>
}
