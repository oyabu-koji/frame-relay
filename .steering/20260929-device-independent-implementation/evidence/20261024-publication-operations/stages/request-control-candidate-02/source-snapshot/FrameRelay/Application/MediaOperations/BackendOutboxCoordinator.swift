import Foundation

actor BackendOutboxCoordinator {
    private let store: any MediaOperationStorePort
    private let identity: RegistrationStoreIdentity
    private let remote: any PublicationRemotePort
    private var running = false
    private var pending: [UInt64: BackendStoreMutation] = [:]
    init(store: any MediaOperationStorePort, identity: RegistrationStoreIdentity, remote: any PublicationRemotePort) {
        self.store = store; self.identity = identity; self.remote = remote
    }
    /// Reconcile durable entries first, including after process death. The
    /// remote binds each old entry to its own registration credential.
    func synchronize() async -> BackendOutcome<Int> {
        guard !running else { return .inProgress }
        running = true; defer { running = false }
        do {
            let initial = try await PublicationStoreBoundary.load(store, identity: identity)
            var delivered = 0
            var unresolved = false
            for entry in initial.outbox {
                if let mutation = pending[entry.commit.committedRevision] {
                    guard case .committed(let receipt) = await store.lookupCommit(mutation),
                          receipt.matches(mutation.change.key, revision: mutation.expectedRevision) else { unresolved = true; continue }
                    pending.removeValue(forKey: entry.commit.committedRevision)
                    delivered += 1; continue
                }
                var response = await remote.lookup(entry)
                if response == .notExecuted {
                    _ = try await PublicationStoreBoundary.load(store, identity: identity)
                    response = await remote.send(entry)
                    if response == .unknown { response = await remote.lookup(entry) }
                }
                guard case .succeeded(let value) = response else { unresolved = true; continue }
                let latest = try await PublicationStoreBoundary.load(store, identity: identity)
                if !latest.outbox.contains(entry) { continue }
                let delivery = BackendSyncDelivery(command: .init(rawValue: UUID().uuidString), entry: entry,
                    registration: entry.registration, response: value)
                let mutation = BackendStoreMutation(expectedRevision: latest.revision, change: .delivered(delivery), expectedStoreIdentity: identity)
                pending[entry.commit.committedRevision] = mutation
                let result = await PublicationStoreBoundary.commit(mutation, store: store)
                guard case .committed(let receipt) = result,
                      receipt.matches(mutation.change.key, revision: mutation.expectedRevision) else {
                    if case .rejected = result { pending.removeValue(forKey: entry.commit.committedRevision) }
                    unresolved = true; continue
                }
                pending.removeValue(forKey: entry.commit.committedRevision)
                delivered += 1
            }
            return unresolved ? .unknown : .succeeded(delivered)
        } catch { return .unknown }
    }
}
