import Foundation
import Testing
@testable import FrameRelay

/// Opt-in only. Actual Keychain + URLSession + isolated S22 server + the same SQLite writer.
/// The loopback transport proves this chain, not deployed HTTPS/Tailscale or device protection.
@Suite(.serialized) struct RegistrationServerProbeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_REGISTRATION_PROBE"] == "1"))
    func testRegistrationCommitAndReopenUsesSameIdentity() async throws {
        let configuration = try RegistrationProbeConfiguration()
        let evidence = try RegistrationProbeEvidence(name: "reopen")
        try await withStorageRun { run in
            let fixture = try configuration.keychain()
            defer { fixture.cleanup() }
            let vault = try fixture.vault()
            let remote = ObservedRegistrationRemote(base: URLSessionRegistrationRemote(credentials: vault))
            let store = try SQLiteRecordingStore(run: run, mode: .createNew)
            let coordinator = RegistrationCoordinator(store: store, vault: vault, remote: remote)
            let initial = await coordinator.register(connection: fixture.connection, bearer: configuration.bearer)
            try #require(registrationIsCommitted(initial))
            let before = try await registrationSnapshot(store)
            try #require(before.registrationIntents.count == 1 && before.registrations.count == 1)
            try #require(before.confirmations.isEmpty && before.outbox.isEmpty)
            let counts = await remote.counts()
            try #require(counts.posts == 1 && counts.lookups == 1)
            try evidence.record("device-committed", counts: counts, values: ["registrations": 1, "intents": 1])

            let reopened = try SQLiteRecordingStore(run: .openExisting(at: run.url), mode: .openExisting)
            let nextVault = try fixture.vault()
            let nextRemote = ObservedRegistrationRemote(base: URLSessionRegistrationRemote(credentials: nextVault))
            let next = RegistrationCoordinator(store: reopened, vault: nextVault, remote: nextRemote)
            try #require(registrationIsCommitted(await next.restore()))
            try #require(try await registrationSnapshot(reopened) == before)
            let reopenedCounts = await nextRemote.counts()
            try #require(reopenedCounts.posts == 0 && reopenedCounts.lookups == 0 && reopenedCounts.discoveries == 0)
            try evidence.record("reopen-same-registration-no-network", counts: reopenedCounts, values: ["registrations": 1])
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_REGISTRATION_PROBE"] == "1"))
    func testLostResponseAndLocalCommitRecovery() async throws {
        let configuration = try RegistrationProbeConfiguration()
        let evidence = try RegistrationProbeEvidence(name: "recovery")
        for boundary in 0..<3 {
            try await withStorageRun { run in
                let fixture = try configuration.keychain()
                defer { fixture.cleanup() }
                let vault = try fixture.vault()
                let remote = ObservedRegistrationRemote(base: URLSessionRegistrationRemote(credentials: vault), hidesFirstReply: boundary == 0)
                let initial = try SQLiteRecordingStore(run: run, mode: .createNew)
                let interrupted: RegistrationCoordinator
                if boundary == 0 {
                    interrupted = RegistrationCoordinator(store: initial, vault: vault, remote: remote)
                    let state = await interrupted.register(connection: fixture.connection, bearer: configuration.bearer)
                    if case .pending = state {} else { Issue.record("A discarded real reply was treated as committed"); return }
                } else {
                    // Discovery and credential persistence are real; seed only the already-committed intent boundary.
                    let capability = await remote.checkConnection(fixture.connection, bearer: configuration.bearer)
                    guard case .succeeded = capability else { Issue.record("Real discovery failed"); return }
                    try await vault.saveConnection(fixture.connection, bearer: configuration.bearer)
                    let intent = try await vault.prepareIntent(for: fixture.connection.destination)
                    guard case .committed = await initial.commit(.init(expectedRevision: 0, change: .registrationIntent(intent))) else {
                        Issue.record("Intent commit failed"); return
                    }
                    let fault: RecordingStoreFault = boundary == 1 ? .beforeDiskCommit : .afterDiskCommitBeforeReply
                    let faulty = try SQLiteRecordingStore(run: run, mode: .openExisting, fault: fault)
                    interrupted = RegistrationCoordinator(store: faulty, vault: vault, remote: remote)
                    _ = await interrupted.restore()
                }
                let snapshot = try await registrationSnapshot(initial)
                try #require(snapshot.registrationIntents.count == 1)
                if boundary < 2 { try #require(snapshot.registrations.isEmpty) }
                let before = await remote.counts()
                try #require(before.posts == 1)
                try evidence.record("interrupted-\(boundary)", counts: before, values: ["boundary": boundary])
                let reopened = try SQLiteRecordingStore(run: .openExisting(at: run.url), mode: .openExisting)
                let recovered = RegistrationCoordinator(store: reopened, vault: try fixture.vault(), remote: remote)
                try #require(registrationIsCommitted(await recovered.restore()))
                let saved = try await registrationSnapshot(reopened)
                try #require(saved.registrations.count == 1 && saved.registrationIntents.count == 1)
                try #require(saved.registrationIntents == snapshot.registrationIntents)
                let after = await remote.counts()
                try #require(after.posts == 1)
                try evidence.record("recovered-\(boundary)", counts: after, values: ["registrations": 1, "boundary": boundary])
            }
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_REGISTRATION_PROBE"] == "1"))
    func testWrongDestinationAndSecretAreRejected() async throws {
        let configuration = try RegistrationProbeConfiguration()
        let evidence = try RegistrationProbeEvidence(name: "identity")
        try await withStorageRun { run in
            let fixture = try configuration.keychain()
            defer { fixture.cleanup() }
            let vault = try fixture.vault()
            let actual = URLSessionRegistrationRemote(credentials: vault)
            let other = try RegistrationConnection(endpoint: fixture.connection.endpoint,
                destination: .init(rawValue: UUID().uuidString.lowercased()))
            let discovery = await actual.checkConnection(other, bearer: configuration.bearer)
            if case .succeeded = discovery { Issue.record("Wrong destination accepted"); return }
            try await vault.saveConnection(fixture.connection, bearer: configuration.bearer)
            let intent = try await vault.prepareIntent(for: fixture.connection.destination)
            let store = try SQLiteRecordingStore(run: run, mode: .createNew)
            guard case .committed(let commit) = await store.commit(.init(expectedRevision: 0, change: .registrationIntent(intent))) else {
                Issue.record("Intent commit failed"); return
            }
            let command = RegistrationCommand(intent: intent, intentCommit: commit)
            guard case .succeeded(let first) = await actual.register(command, at: fixture.connection) else {
                Issue.record("Real server registration failed"); return
            }
            let invalid = URLSessionRegistrationRemote(credentials: WrongSecretAuthorization(base: vault))
            try #require(await invalid.lookup(intent, at: fixture.connection) == .failed(.authenticationRequired))
            try #require(await invalid.register(command, at: fixture.connection) == .failed(.authenticationRequired))
            guard case .succeeded(let same) = await actual.lookup(intent, at: fixture.connection) else {
                Issue.record("Original credential lost after rejected retry"); return
            }
            try #require(first == same)
            let substituted = ObservedRegistrationRemote(base: actual, substitutesReceipt: true)
            let coordinator = RegistrationCoordinator(store: store, vault: vault, remote: substituted)
            try #require(await coordinator.restore() == .unavailable(.identity))
            try #require(try await registrationSnapshot(store).registrations.isEmpty)
            try evidence.record("wrong-target-secret-and-receipt-rejected", counts: await substituted.counts(),
                                values: ["unchangedServerReceipt": 1, "deviceRegistrations": 0])
        }
    }
}

nonisolated struct RegistrationProbeConfiguration {
    let connection: RegistrationConnection
    let bearer: String
    init() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["FR_REGISTRATION_PROBE"] == "1",
              let value = environment["FR_REGISTRATION_BASE_URL"],
              let destination = environment["FR_REGISTRATION_DESTINATION_ID"],
              let token = environment["FR_REGISTRATION_BOOTSTRAP_TOKEN"], !token.isEmpty else {
            throw RegistrationAccessError.invalidConfiguration
        }
        #if DEBUG && targetEnvironment(simulator)
        connection = try .init(endpoint: .isolatedLoopbackProbe(value), destination: .init(rawValue: destination))
        bearer = token
        #else
        throw RegistrationAccessError.invalidConfiguration
        #endif
    }
    func keychain() throws -> RegistrationTestKeychain {
        try .init(endpoint: connection.endpoint, destination: connection.destination.rawValue)
    }
}

nonisolated struct RegistrationProbeCounts: Codable, Sendable {
    var discoveries = 0
    var posts = 0
    var lookups = 0
}
actor ObservedRegistrationRemote: RegistrationRemotePort {
    let base: any RegistrationRemotePort
    private var observation = RegistrationProbeCounts()
    private var hidesFirstReply: Bool
    private let substitutesReceipt: Bool
    init(base: any RegistrationRemotePort, hidesFirstReply: Bool = false, substitutesReceipt: Bool = false) {
        self.base = base
        self.hidesFirstReply = hidesFirstReply
        self.substitutesReceipt = substitutesReceipt
    }
    func counts() -> RegistrationProbeCounts { observation }
    func checkConnection(_ connection: RegistrationConnection, bearer: String) async -> BackendOutcome<BackendCapabilities> {
        observation.discoveries += 1
        return await base.checkConnection(connection, bearer: bearer)
    }
    func discover(_ connection: RegistrationConnection) async -> BackendOutcome<BackendCapabilities> {
        observation.discoveries += 1
        return await base.discover(connection)
    }
    func lookup(_ intent: RegistrationIntent, at connection: RegistrationConnection) async -> BackendOutcome<RegistrationServerReceipt> {
        observation.lookups += 1
        let result = await base.lookup(intent, at: connection)
        if substitutesReceipt, case .succeeded(let receipt) = result {
            return .succeeded(.init(intent: .init(operation: .init(rawValue: UUID().uuidString.lowercased()), destination: intent.destination),
                                    registration: receipt.registration))
        }
        return result
    }
    func register(_ command: RegistrationCommand, at connection: RegistrationConnection) async -> BackendOutcome<RegistrationServerReceipt> {
        observation.posts += 1
        let result = await base.register(command, at: connection)
        if hidesFirstReply, case .succeeded = result { hidesFirstReply = false; return .unknown }
        return result
    }
}
nonisolated private struct WrongSecretAuthorization: RegistrationAuthorizationPort {
    let base: any RegistrationAuthorizationPort
    func authorization(for connection: RegistrationConnection, intent: RegistrationIntent?) async throws -> RegistrationAuthorization {
        let original = try await base.authorization(for: connection, intent: intent)
        guard let secret = original.secret else { throw RegistrationAccessError.credentialMissing }
        let wrong = (secret.first == "a" ? "b" : "a") + secret.dropFirst()
        return .init(bearer: original.bearer, secret: wrong)
    }
}

/// UUID-isolated technical evidence; no endpoint, credential, response body or private NSError.
nonisolated final class RegistrationProbeEvidence: Sendable {
    let directory: URL
    init(name: String) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "fr-s22c-registration-probe-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        print("S22C_REGISTRATION_PROBE_EVIDENCE " + directory.path)
    }
    func record(_ phase: String, counts: RegistrationProbeCounts = .init(), values: [String: Int] = [:]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(Event(phase: phase, counts: counts, values: values))
            .write(to: directory.appendingPathComponent(phase + ".json"), options: .withoutOverwriting)
    }
    nonisolated private struct Event: Codable {
        let phase: String
        let counts: RegistrationProbeCounts
        let values: [String: Int]
    }
}
