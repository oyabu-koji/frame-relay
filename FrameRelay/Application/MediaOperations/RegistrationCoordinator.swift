import Foundation

/// Uses the same writer as capture/library. Its values are projections, never a second journal.
actor RegistrationCoordinator {
    private let store: any MediaOperationStorePort
    private let vault: any RegistrationVaultPort
    private let remote: any RegistrationRemotePort
    private var running = false

    init(store: any MediaOperationStorePort, vault: any RegistrationVaultPort, remote: any RegistrationRemotePort) {
        self.store = store
        self.vault = vault
        self.remote = remote
    }

    func permitsInitialInput() async -> Bool {
        do {
            let snapshot = try await load()
            guard snapshot.registrationIntents.isEmpty, snapshot.registrations.isEmpty else { return false }
            guard try await vault.connection(storeIdentity: snapshot.storeIdentity) == nil else { return false }
            let current = try await load()
            return current.storeIdentity == snapshot.storeIdentity && current.registrationIntents.isEmpty && current.registrations.isEmpty
        } catch { return false }
    }

    func permitsNewStoreRegistration() async -> Bool {
        do {
            let initial = try await load()
            guard initial.registrationIntents.isEmpty, initial.registrations.isEmpty,
                  try await vault.permitsNewStoreRegistration(storeIdentity: initial.storeIdentity) else { return false }
            let current = try await load()
            return current.storeIdentity == initial.storeIdentity && current.registrationIntents.isEmpty && current.registrations.isEmpty
        } catch { return false }
    }

    /// Separate user action: never adopt, replace or erase the foreign binding.
    /// The local UUID must be durably established before discovery or Keychain writes.
    func registerNewStore(connection: RegistrationConnection, bearer: String) async -> RegistrationState {
        guard !running else { return .unavailable(.busy) }
        running = true
        defer { running = false }
        do {
            let initial = try await load()
            guard initial.registrationIntents.isEmpty, initial.registrations.isEmpty,
                  try await vault.permitsNewStoreRegistration(storeIdentity: initial.storeIdentity) else {
                return .unavailable(.credentialConflict)
            }
            let current = try await load()
            guard current.storeIdentity == initial.storeIdentity,
                  current.registrationIntents.isEmpty, current.registrations.isEmpty else {
                return .unavailable(.credentialConflict)
            }
            let identity: RegistrationStoreIdentity
            if let existing = current.storeIdentity { identity = existing }
            else {
                identity = try await store.establishRegistrationIdentity(expectedRevision: current.revision, expectedIdentity: nil)
            }
            _ = try await requireFreshStore(identity)
            guard try await vault.permitsNewStoreRegistration(storeIdentity: identity) else {
                return .unavailable(.credentialConflict)
            }
            _ = try await requireFreshStore(identity)
            let discovery = await remote.checkConnection(connection, bearer: bearer)
            _ = try await requireFreshStore(identity)
            guard case .succeeded(let capabilities) = discovery,
                  capabilities.supports([.registration, .registrationLookup], versions: ["1"], destination: connection.destination) else {
                return .unavailable(issue(discovery))
            }
            try await vault.saveNewStoreConnection(connection, bearer: bearer, storeIdentity: identity)
            _ = try await requireFreshStore(identity)
            return try await begin(connection, identity: identity, requireFreshRegistration: true)
        } catch { return .unavailable(issue(error)) }
    }

    /// Normal launches use a committed registration without POST or capability discovery.
    /// Only a writer-committed pending intent may be reconciled automatically.
    func restore() async -> RegistrationState {
        guard !running else { return .unavailable(.busy) }
        running = true
        defer { running = false }
        do {
            let snapshot = try await load()
            guard let connection = try await vault.connection(storeIdentity: snapshot.storeIdentity) else {
                return snapshot.registrationIntents.isEmpty && snapshot.registrations.isEmpty
                    ? .needsConnection : .unavailable(.credentials)
            }
            guard let identity = snapshot.storeIdentity else { throw RegistrationAccessError.credentialConflict }
            return try await resume(connection, snapshot: try await load(expectedIdentity: identity), identity: identity)
        } catch { return .unavailable(issue(error)) }
    }

    /// Explicit first registration. The server verifies the origin/identity/token before Keychain persistence.
    func register(connection: RegistrationConnection, bearer: String) async -> RegistrationState {
        guard !running else { return .unavailable(.busy) }
        running = true
        defer { running = false }
        do {
            let snapshot = try await load()
            let savedConnection = try await vault.connection(storeIdentity: snapshot.storeIdentity)
            guard savedConnection == nil || savedConnection == connection else { return .unavailable(.credentialConflict) }
            if !snapshot.registrationIntents.isEmpty || !snapshot.registrations.isEmpty {
                guard savedConnection == connection, let identity = snapshot.storeIdentity else { return .unavailable(.credentials) }
                return try await resume(connection, snapshot: try await load(expectedIdentity: identity), identity: identity)
            }
            // Explicit metadata transaction precedes all Keychain writes. An uncertain
            // commit stops here; the next explicit action reads back the durable UUID.
            let identity: RegistrationStoreIdentity
            if let existing = snapshot.storeIdentity { identity = existing }
            else {
                identity = try await store.establishRegistrationIdentity(expectedRevision: snapshot.revision,
                                                                         expectedIdentity: nil)
            }
            _ = try await load(expectedIdentity: identity)
            let discovery = await remote.checkConnection(connection, bearer: bearer)
            guard case .succeeded(let capabilities) = discovery,
                  capabilities.supports([.registration, .registrationLookup], versions: ["1"], destination: connection.destination) else {
                return .unavailable(issue(discovery))
            }
            _ = try await load(expectedIdentity: identity)
            try await vault.saveConnection(connection, bearer: bearer, storeIdentity: identity)
            return try await begin(connection, identity: identity)
        } catch { return .unavailable(issue(error)) }
    }

    /// Resume the explicit action after credentials were saved but before an intent commit.
    func registerSavedConnection() async -> RegistrationState {
        guard !running else { return .unavailable(.busy) }
        running = true
        defer { running = false }
        do {
            let snapshot = try await load()
            guard let connection = try await vault.connection(storeIdentity: snapshot.storeIdentity) else { return .needsConnection }
            guard let identity = snapshot.storeIdentity else { throw RegistrationAccessError.credentialConflict }
            let current = try await load(expectedIdentity: identity)
            if !current.registrationIntents.isEmpty || !current.registrations.isEmpty {
                return try await resume(connection, snapshot: current, identity: identity)
            }
            let discovery = await remote.discover(connection, storeIdentity: identity)
            guard case .succeeded(let capabilities) = discovery,
                  capabilities.supports([.registration, .registrationLookup], versions: ["1"], destination: connection.destination) else {
                return .unavailable(issue(discovery))
            }
            return try await begin(connection, identity: identity)
        } catch { return .unavailable(issue(error)) }
    }

    private func begin(_ connection: RegistrationConnection, identity: RegistrationStoreIdentity,
                       requireFreshRegistration: Bool = false) async throws -> RegistrationState {
        _ = try await load(expectedIdentity: identity)
        if requireFreshRegistration { _ = try await requireFreshStore(identity) }
        let intent = try await vault.prepareIntent(for: connection.destination, storeIdentity: identity)
        guard intent.destination == connection.destination else { return .unavailable(.identity) }
        if requireFreshRegistration { _ = try await requireFreshStore(identity) }
        guard try await persist(.registrationIntent(intent), identity: identity,
            requireFreshRegistration: requireFreshRegistration) else { return .pending(connection, intent) }
        // Lookup also covers a process death after an earlier POST; no new intent is allocated.
        let current = try await load(expectedIdentity: identity)
        return try await resume(connection, snapshot: current, identity: identity)
    }

    private func resume(_ connection: RegistrationConnection, snapshot: BackendStoreSnapshot, identity: RegistrationStoreIdentity) async throws -> RegistrationState {
        let intents = snapshot.registrationIntents.filter { $0.intent.destination == connection.destination }
        guard intents.count == snapshot.registrationIntents.count, intents.count <= 1,
              snapshot.registrations.allSatisfy({ $0.server.intent.destination == connection.destination }) else {
            return .unavailable(.identity)
        }
        guard let saved = intents.first else {
            return snapshot.registrations.isEmpty ? .needsRegistration(connection) : .unavailable(.storage)
        }
        let registrations = snapshot.registrations.filter { $0.server.intent == saved.intent }
        guard registrations.count <= 1, registrations.count == snapshot.registrations.count else { return .unavailable(.identity) }
        try await vault.requireCredential(for: saved.intent, storeIdentity: identity)
        var recovery = try RegistrationRecovery(revision: snapshot.revision, savedIntent: saved,
                                                savedRegistration: registrations.first)
        _ = try await load(expectedIdentity: identity)
        if case .use(let registration) = recovery.action { return .registered(connection, registration) }
        var result = await remote.lookup(saved.intent, at: connection, storeIdentity: identity)
        if result == .notExecuted {
            // A known absence is not permission for a different operation or secret.
            _ = try await load(expectedIdentity: identity)
            result = await remote.register(.init(intent: saved.intent, intentCommit: saved.commit), at: connection, storeIdentity: identity)
        }
        guard case .succeeded = result else {
            if case .failed(let failure) = result { return .unavailable(issue(BackendOutcome<RegistrationServerReceipt>.failed(failure))) }
            return .pending(connection, saved.intent)
        }
        try recovery.reconcile(result)
        guard case .commitServerResult(let receipt) = recovery.action else { return .unavailable(.identity) }
        guard try await persist(.registration(receipt), identity: identity) else { return .pending(connection, saved.intent) }
        let current = try await load(expectedIdentity: identity)
        guard let committedIntent = current.registrationIntents.first(where: { $0.intent == saved.intent }),
              let committed = current.registrations.first(where: { $0.server == receipt }) else { return .unavailable(.storage) }
        let recovered = try RegistrationRecovery(revision: current.revision, savedIntent: committedIntent,
                                                 savedRegistration: committed)
        guard case .use(let value) = recovered.action else { return .unavailable(.storage) }
        return .registered(connection, value)
    }

    /// Rebase only a definite revision conflict. Unknown responses retain the exact mutation for lookup.
    private func persist(_ change: BackendStoreChange, identity: RegistrationStoreIdentity,
                         requireFreshRegistration: Bool = false) async throws -> Bool {
        for _ in 0..<3 {
            let snapshot = try await load(expectedIdentity: identity)
            switch change {
            case .registrationIntent(let intent):
                if let saved = snapshot.registrationIntents.first(where: { $0.intent.operation == intent.operation }) {
                    guard saved.intent == intent, saved.isCommitted else { throw BackendContractError.identityMismatch }
                    return true
                }
                if requireFreshRegistration, !snapshot.registrationIntents.isEmpty || !snapshot.registrations.isEmpty {
                    throw RegistrationAccessError.credentialConflict
                }
            case .registration(let receipt):
                if let saved = snapshot.registrations.first(where: { $0.server.intent.operation == receipt.intent.operation }) {
                    guard saved.server == receipt, saved.isCommitted else { throw BackendContractError.identityMismatch }
                    return true
                }
            default: throw BackendContractError.wrongStage
            }
            let mutation = BackendStoreMutation(expectedRevision: snapshot.revision, change: change, expectedStoreIdentity: identity)
            let result = await store.commit(mutation)
            switch result {
            case .committed(let receipt):
                guard receipt.matches(change.key, revision: snapshot.revision) else { throw BackendContractError.notCommitted }
                return true
            case .rejected(.revisionConflict): continue
            case .unknown, .unavailable:
                if case .committed(let receipt) = await store.lookupCommit(mutation) {
                    guard receipt.matches(change.key, revision: snapshot.revision) else { throw BackendContractError.notCommitted }
                    return true
                }
                return false
            case .rejected(let error): throw error
            }
        }
        return false
    }
    private func requireFreshStore(_ identity: RegistrationStoreIdentity) async throws -> BackendStoreSnapshot {
        let snapshot = try await load(expectedIdentity: identity)
        guard snapshot.registrationIntents.isEmpty, snapshot.registrations.isEmpty else {
            throw RegistrationAccessError.credentialConflict
        }
        return snapshot
    }
    private func load(expectedIdentity: RegistrationStoreIdentity? = nil) async throws -> BackendStoreSnapshot {
        guard case .loaded(let value) = await store.load() else { throw BackendContractError.unavailable }
        if let expectedIdentity, value.storeIdentity != expectedIdentity { throw RegistrationAccessError.credentialConflict }
        return value
    }
    private func issue<T>(_ result: BackendOutcome<T>) -> RegistrationIssue {
        switch result {
        case .failed(.authenticationRequired): .authentication
        case .failed(.connectionUnavailable), .unknown, .inProgress: .connection
        case .failed(.inaccessible): .credentials
        case .failed(.rejected): .identity
        default: .protocolMismatch
        }
    }
    private func issue(_ error: Error) -> RegistrationIssue {
        if let error = error as? RegistrationAccessError {
            switch error {
            case .invalidConfiguration: return .configuration
            case .credentialConflict: return .credentialConflict
            default: return .credentials
            }
        }
        if let error = error as? BackendContractError, error == .identityMismatch { return .identity }
        return .storage
    }
}
