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
            return try await vault.connection() == nil
        } catch { return false }
    }

    /// Normal launches use a committed registration without POST or capability discovery.
    /// Only a writer-committed pending intent may be reconciled automatically.
    func restore() async -> RegistrationState {
        guard !running else { return .unavailable(.busy) }
        running = true
        defer { running = false }
        do {
            let snapshot = try await load()
            guard let connection = try await vault.connection() else {
                return snapshot.registrationIntents.isEmpty && snapshot.registrations.isEmpty
                    ? .needsConnection : .unavailable(.credentials)
            }
            return try await resume(connection, snapshot: snapshot)
        } catch { return .unavailable(issue(error)) }
    }

    /// Explicit first registration. The server verifies the origin/identity/token before Keychain persistence.
    func register(connection: RegistrationConnection, bearer: String) async -> RegistrationState {
        guard !running else { return .unavailable(.busy) }
        running = true
        defer { running = false }
        do {
            let snapshot = try await load()
            if !snapshot.registrationIntents.isEmpty || !snapshot.registrations.isEmpty {
                guard try await vault.connection() == connection else { return .unavailable(.identity) }
                return try await resume(connection, snapshot: snapshot)
            }
            let discovery = await remote.checkConnection(connection, bearer: bearer)
            guard case .succeeded(let capabilities) = discovery,
                  capabilities.supports([.registration, .registrationLookup], versions: ["1"], destination: connection.destination) else {
                return .unavailable(issue(discovery))
            }
            try await vault.saveConnection(connection, bearer: bearer)
            return try await begin(connection)
        } catch { return .unavailable(issue(error)) }
    }

    /// Resume the explicit action after credentials were saved but before an intent commit.
    func registerSavedConnection() async -> RegistrationState {
        guard !running else { return .unavailable(.busy) }
        running = true
        defer { running = false }
        do {
            guard let connection = try await vault.connection() else { return .needsConnection }
            let snapshot = try await load()
            if !snapshot.registrationIntents.isEmpty || !snapshot.registrations.isEmpty {
                return try await resume(connection, snapshot: snapshot)
            }
            let discovery = await remote.discover(connection)
            guard case .succeeded(let capabilities) = discovery,
                  capabilities.supports([.registration, .registrationLookup], versions: ["1"], destination: connection.destination) else {
                return .unavailable(issue(discovery))
            }
            return try await begin(connection)
        } catch { return .unavailable(issue(error)) }
    }

    private func begin(_ connection: RegistrationConnection) async throws -> RegistrationState {
        let intent = try await vault.prepareIntent(for: connection.destination)
        guard intent.destination == connection.destination else { return .unavailable(.identity) }
        guard try await persist(.registrationIntent(intent)) else { return .pending(connection, intent) }
        // Lookup also covers a process death after an earlier POST; no new intent is allocated.
        let current = try await load()
        return try await resume(connection, snapshot: current)
    }

    private func resume(_ connection: RegistrationConnection, snapshot: BackendStoreSnapshot) async throws -> RegistrationState {
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
        try await vault.requireCredential(for: saved.intent)
        var recovery = try RegistrationRecovery(revision: snapshot.revision, savedIntent: saved,
                                                savedRegistration: registrations.first)
        if case .use(let registration) = recovery.action { return .registered(connection, registration) }
        var result = await remote.lookup(saved.intent, at: connection)
        if result == .notExecuted {
            // A known absence is not permission for a different operation or secret.
            result = await remote.register(.init(intent: saved.intent, intentCommit: saved.commit), at: connection)
        }
        guard case .succeeded = result else {
            if case .failed(let failure) = result { return .unavailable(issue(BackendOutcome<RegistrationServerReceipt>.failed(failure))) }
            return .pending(connection, saved.intent)
        }
        try recovery.reconcile(result)
        guard case .commitServerResult(let receipt) = recovery.action else { return .unavailable(.identity) }
        guard try await persist(.registration(receipt)) else { return .pending(connection, saved.intent) }
        let current = try await load()
        guard let committedIntent = current.registrationIntents.first(where: { $0.intent == saved.intent }),
              let committed = current.registrations.first(where: { $0.server == receipt }) else { return .unavailable(.storage) }
        let recovered = try RegistrationRecovery(revision: current.revision, savedIntent: committedIntent,
                                                 savedRegistration: committed)
        guard case .use(let value) = recovered.action else { return .unavailable(.storage) }
        return .registered(connection, value)
    }

    /// Rebase only a definite revision conflict. Unknown responses retain the exact mutation for lookup.
    private func persist(_ change: BackendStoreChange) async throws -> Bool {
        for _ in 0..<3 {
            let snapshot = try await load()
            switch change {
            case .registrationIntent(let intent):
                if let saved = snapshot.registrationIntents.first(where: { $0.intent.operation == intent.operation }) {
                    guard saved.intent == intent, saved.isCommitted else { throw BackendContractError.identityMismatch }
                    return true
                }
            case .registration(let receipt):
                if let saved = snapshot.registrations.first(where: { $0.server.intent.operation == receipt.intent.operation }) {
                    guard saved.server == receipt, saved.isCommitted else { throw BackendContractError.identityMismatch }
                    return true
                }
            default: throw BackendContractError.wrongStage
            }
            let mutation = BackendStoreMutation(expectedRevision: snapshot.revision, change: change)
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
    private func load() async throws -> BackendStoreSnapshot {
        guard case .loaded(let value) = await store.load() else { throw BackendContractError.unavailable }
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
