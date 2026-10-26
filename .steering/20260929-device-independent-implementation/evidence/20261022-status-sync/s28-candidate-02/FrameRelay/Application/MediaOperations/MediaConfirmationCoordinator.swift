import Foundation

actor MediaConfirmationCoordinator {
    private let store: any MediaOperationStorePort
    private let identity: RegistrationStoreIdentity
    private var pending: [MediaOperationID: BackendStoreMutation] = [:]
    private var running: Set<MediaOperationID> = []
    init(store: any MediaOperationStorePort, identity: RegistrationStoreIdentity) {
        self.store = store; self.identity = identity
    }

    /// Called only by a singular explicit user action. Receiving a PlaybackToken
    /// or restoring state never calls this method or allocates an action ID.
    func confirm(_ token: PlaybackToken, action: MediaOperationID) async -> BackendOutcome<ConfirmationRecord> {
        guard running.insert(action).inserted else { return .inProgress }
        defer { running.remove(action) }
        do {
            let snapshot = try await PublicationStoreBoundary.load(store, identity: identity)
            let intent = ConfirmationIntent(operation: action, playback: token)
            if let record = snapshot.confirmations.first(where: { $0.intent.operation == action }) {
                guard PublicationStoreBoundary.exact(record.intent, intent) else { return .failed(.rejected) }
                if let unresolved = pending[action], !record.commit.matches(intent.key, revision: unresolved.expectedRevision) { return .unknown }
                return .succeeded(record) // Historical commit, not current validity.
            }
            let mutation: BackendStoreMutation
            let result: BackendCommitResult
            if let existing = pending[action] {
                guard PublicationStoreBoundary.exact(existing.change, .confirmation(intent)) else { return .failed(.rejected) }
                mutation = existing
                result = await PublicationStoreBoundary.reconcile(existing, store: store)
            } else {
                mutation = .init(expectedRevision: snapshot.revision, change: .confirmation(intent), expectedStoreIdentity: identity)
                pending[action] = mutation
                result = await PublicationStoreBoundary.commit(mutation, store: store)
            }
            guard case .committed(let receipt) = result,
                  receipt.matches(intent.key, revision: mutation.expectedRevision) else {
                if case .rejected = result { pending.removeValue(forKey: action); return .failed(.rejected) }
                return .unknown
            }
            let latest = try await PublicationStoreBoundary.load(store, identity: identity)
            let record = ConfirmationRecord(intent: intent, commit: receipt)
            guard latest.confirmations.contains(record) else { return .unknown }
            pending.removeValue(forKey: action)
            return .succeeded(record)
        } catch { return .unknown }
    }

    /// Reopen recovers only durable records. An action lost before its first
    /// commit is not automatically replayed or declared definitely unexecuted.
    func restore() async -> BackendOutcome<[ConfirmationRecord]> {
        do { return .succeeded(try await PublicationStoreBoundary.load(store, identity: identity).confirmations) }
        catch { return .unknown }
    }
}
