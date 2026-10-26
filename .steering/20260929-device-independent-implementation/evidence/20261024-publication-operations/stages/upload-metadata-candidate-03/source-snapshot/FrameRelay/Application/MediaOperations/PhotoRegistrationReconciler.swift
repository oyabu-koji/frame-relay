import Foundation

/// Checks an exact persisted Photos identifier after the user sees the reason
/// for read access. It requires no download/temporary-media owner.
actor PhotoRegistrationReconciler {
    private let store: any MediaOperationStorePort
    private let identity: RegistrationStoreIdentity
    private let library: any PhotoLibraryPort
    private var running: Set<PhotoRegistrationKey> = []
    private var tasks: [PhotoRegistrationKey: Task<BackendOutcome<PhotoRegistrationRecord>, Never>] = [:]
    private var pending: [MediaOperationID: BackendStoreMutation] = [:]

    init(store: any MediaOperationStorePort, identity: RegistrationStoreIdentity, library: any PhotoLibraryPort) {
        self.store = store; self.identity = identity; self.library = library
    }

    func reconcile(_ key: PhotoRegistrationKey, action: MediaOperationID) async -> BackendOutcome<PhotoRegistrationRecord> {
        guard running.insert(key).inserted else { return .inProgress }
        let task = Task { await self.perform(key, action: action) }
        tasks[key] = task
        return await task.value
    }

    private func perform(_ key: PhotoRegistrationKey, action: MediaOperationID) async -> BackendOutcome<PhotoRegistrationRecord> {
        defer { tasks.removeValue(forKey: key); running.remove(key) }
        do {
            if let mutation = pending[action] {
                guard case .photo(_, let change) = mutation.change, change.key == key,
                      await lookup(mutation) != nil else { return .unknown }
                guard let current = try await currentRecord(key),
                      current.registration.intent == change.intent else { return .unknown }
                pending.removeValue(forKey: action)
                return .succeeded(current)
            }
            guard let record = try await currentRecord(key) else { return .notExecuted }
            if let existing = record.presenceObservations.first(where: { $0.command == action }) {
                let mutation = BackendStoreMutation(expectedRevision: existing.commit.previousRevision,
                    change: .photo(command: action, value: .presence(existing.observation)),
                    expectedStoreIdentity: existing.expectedStoreIdentity)
                return await lookup(mutation) != nil ? .succeeded(record) : .unknown
            }
            let identifier = record.localIdentifier
            let authorization: PhotoLibraryAuthorization
            let presence: PhotoAssetPresence
            if let identifier {
                let status = await library.authorizationStatus(for: .readWrite)
                let access = status == .notDetermined ? await library.requestAuthorization(for: .readWrite) : status
                if access == .authorized || access == .limited {
                    let found = await library.lookup(identifier)
                    guard found.identifier == identifier else { return .unknown }
                    authorization = found.authorization
                    if (found.authorization == .authorized || found.authorization == .limited),
                       found.presence == .present || found.presence == .notFound {
                        presence = found.presence
                    } else { presence = .unavailable }
                } else { authorization = access; presence = .unavailable }
            } else {
                authorization = await library.authorizationStatus(for: .readWrite)
                presence = .correspondenceUnknown
            }
            let next = (record.currentPresence?.generation ?? 0).addingReportingOverflow(1)
            guard !next.overflow else { return .unknown }
            let observation = try PhotoPresenceObservation(intent: record.registration.intent,
                generation: next.partialValue, identifier: identifier, authorization: authorization, presence: presence)
            let committed = await persist(observation, action: action)
            guard case .committed(let receipt) = committed else {
                return committed.isRejected ? .failed(.rejected) : .unknown
            }
            guard let updated = try await currentRecord(key),
                  updated.registration.intent == record.registration.intent,
                  updated.presenceObservations.contains(where: { $0.command == action && $0.observation == observation && $0.commit == receipt }) else { return .unknown }
            return .succeeded(updated)
        } catch { return .unknown }
    }

    private func currentRecord(_ key: PhotoRegistrationKey) async throws -> PhotoRegistrationRecord? {
        try await load().photoRegistrations.last { $0.registration.intent.key == key }
    }

    private func load() async throws -> BackendStoreSnapshot {
        guard case .loaded(let snapshot) = await store.load(), snapshot.storeIdentity == identity else {
            throw BackendContractError.unavailable
        }
        return snapshot
    }

    private func lookup(_ mutation: BackendStoreMutation) async -> BackendCommitReceipt? {
        guard case .committed(let receipt) = await store.lookupCommit(mutation),
              receipt.matches(mutation.change.key, revision: mutation.expectedRevision) else { return nil }
        return receipt
    }

    private func persist(_ observation: PhotoPresenceObservation, action: MediaOperationID) async -> BackendCommitResult {
        let change = BackendStoreChange.photo(command: action, value: .presence(observation))
        for _ in 0..<3 {
            guard let snapshot = try? await load() else { return .unknown }
            let mutation = BackendStoreMutation(expectedRevision: snapshot.revision, change: change, expectedStoreIdentity: identity)
            pending[action] = mutation
            let result = await store.commit(mutation)
            if case .rejected(.revisionConflict) = result { pending.removeValue(forKey: action); continue }
            if case .rejected = result { pending.removeValue(forKey: action); return result }
            guard let receipt = await lookup(mutation) else { return .unknown }
            pending.removeValue(forKey: action)
            return .committed(receipt)
        }
        return .rejected(.revisionConflict)
    }
}

private extension BackendCommitResult {
    nonisolated var isRejected: Bool { if case .rejected = self { return true }; return false }
}
