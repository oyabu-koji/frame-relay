nonisolated struct RegistrationIntent: Equatable, Sendable, Codable {
    let operation: RegistrationOperationID
    let destination: DestinationIdentity
}

/// A server result is not a durable registration on this device.
nonisolated struct RegistrationServerReceipt: Equatable, Sendable, Codable {
    let intent: RegistrationIntent
    let registration: RegistrationIdentity
}

nonisolated struct CommittedRegistrationIntent: Equatable, Sendable, Codable {
    let intent: RegistrationIntent
    let commit: BackendCommitReceipt

    var isCommitted: Bool {
        commit.matches(.registrationIntent(intent.operation, intent.destination), revision: commit.previousRevision)
    }
}

nonisolated struct DeviceRegistration: Equatable, Sendable, Codable {
    let server: RegistrationServerReceipt
    let intentCommit: BackendCommitReceipt
    let commit: BackendCommitReceipt

    var isCommitted: Bool {
        server.intent.destination == server.registration.destination
            && intentCommit.matches(.registrationIntent(server.intent.operation, server.intent.destination),
                                    revision: intentCommit.previousRevision)
            && commit.previousRevision >= intentCommit.committedRevision
            && commit.matches(.registration(server.intent.operation, server.registration),
                              revision: commit.previousRevision)
    }
}

nonisolated enum RegistrationRecoveryAction: Equatable, Sendable {
    case needsExplicitRegistration
    case lookup(RegistrationIntent)
    case commitServerResult(RegistrationServerReceipt)
    case use(DeviceRegistration)
}

nonisolated struct RegistrationRecovery: Equatable, Sendable {
    private(set) var intent: RegistrationIntent?
    private(set) var server: RegistrationServerReceipt?
    private(set) var registration: DeviceRegistration?
    private(set) var revision: UInt64
    private(set) var intentCommit: BackendCommitReceipt?

    init(revision: UInt64) { self.revision = revision }

    /// Reconstruct only from store-loaded proofs; no fixture-supplied or newly generated identity.
    init(revision: UInt64, savedIntent: CommittedRegistrationIntent, savedRegistration: DeviceRegistration?) throws {
        guard savedIntent.isCommitted, savedIntent.commit.committedRevision <= revision else {
            throw BackendContractError.notCommitted
        }
        if let savedRegistration {
            guard savedRegistration.isCommitted, savedRegistration.server.intent == savedIntent.intent,
                  savedRegistration.intentCommit == savedIntent.commit,
                  savedRegistration.commit.committedRevision <= revision else {
                throw BackendContractError.identityMismatch
            }
        }
        self.revision = revision
        intent = savedIntent.intent
        intentCommit = savedIntent.commit
        registration = savedRegistration
        server = savedRegistration?.server
    }

    var action: RegistrationRecoveryAction {
        if let registration { return .use(registration) }
        if let server { return .commitServerResult(server) }
        if let intent { return .lookup(intent) }
        return .needsExplicitRegistration
    }

    mutating func acceptIntent(_ value: RegistrationIntent, commit: BackendCommitReceipt) throws {
        if intent == value, intentCommit == commit { return }
        guard intent == nil else { throw BackendContractError.wrongStage }
        guard commit.matches(.registrationIntent(value.operation, value.destination),
                             revision: revision) else { throw BackendContractError.notCommitted }
        intent = value
        intentCommit = commit
        revision = commit.committedRevision
    }

    mutating func reconcile(_ result: BackendOutcome<RegistrationServerReceipt>) throws {
        guard let intent else { throw BackendContractError.wrongStage }
        guard case .succeeded(let receipt) = result else { return }
        guard receipt.intent == intent, receipt.registration.destination == intent.destination,
              server == nil || server == receipt else { throw BackendContractError.identityMismatch }
        server = receipt
    }

    mutating func acceptRegistrationCommit(_ commit: BackendCommitReceipt) throws {
        guard let server, let intentCommit else { throw BackendContractError.wrongStage }
        let value = DeviceRegistration(server: server, intentCommit: intentCommit, commit: commit)
        guard value.isCommitted, commit.matches(.registration(server.intent.operation, server.registration),
                                               revision: revision) else { throw BackendContractError.notCommitted }
        registration = value
        revision = commit.committedRevision
    }
}
