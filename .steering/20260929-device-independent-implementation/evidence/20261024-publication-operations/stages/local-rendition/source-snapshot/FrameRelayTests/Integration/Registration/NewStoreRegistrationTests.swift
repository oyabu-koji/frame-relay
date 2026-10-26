import Foundation
import Testing
@testable import FrameRelay

@Suite(.serialized) @MainActor struct NewStoreRegistrationTests {
    @Test(arguments: [false, true])
    func ordinaryEntrancesRejectForeignBindingAndExplicitActionCreatesOnlyCurrentRegistration(hideReply: Bool) async throws {
        try await withStorageRun { run in
            let f = try await NewRegistrationKeychain.make()
            var currentIdentities: [RegistrationStoreIdentity] = []
            defer { f.cleanup(currentIdentities) }
            let store = try SQLiteRecordingStore(run: run, mode: .createNew)
            let vault = try f.keychain.vault()
            let remote = RegistrationTestRemote()
            if hideReply { await remote.setHideReply() }
            let coordinator = RegistrationCoordinator(store: store, vault: vault, remote: remote)
            #expect(await coordinator.restore() == .unavailable(.credentialConflict))
            #expect(await coordinator.registerSavedConnection() == .unavailable(.credentialConflict))
            #expect(await coordinator.register(connection: f.keychain.connection, bearer: "new-fixture-bearer") == .unavailable(.credentialConflict))
            #expect(!(await coordinator.permitsInitialInput()))
            let initialCalls = [await remote.discoveries, await remote.posts, await remote.lookups]
            #expect(initialCalls == [0, 0, 0])
            #expect(await coordinator.permitsNewStoreRegistration())
            let first = await coordinator.registerNewStore(connection: f.keychain.connection, bearer: "new-fixture-bearer")
            let initial = try await mediaSnapshot(store)
            let identity = try #require(initial.storeIdentity)
            currentIdentities.append(identity)
            #expect(identity != f.oldIdentity)
            let intent = try #require(initial.registrationIntents.first?.intent)
            #expect(intent != f.oldIntent)
            if hideReply { #expect(first == .pending(f.keychain.connection, intent)) }
            else { if case .registered = first {} else { Issue.record("Explicit current-store registration did not complete") } }
            let namespaceBytes = try f.keychain.bytes(newRegistrationCredentialAccount(identity, f.keychain.connection.destination))
            let reopened = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let next = RegistrationCoordinator(store: reopened, vault: try f.keychain.vault(), remote: remote)
            guard case .registered(let connection, let registered) = await next.restore() else { throw BackendContractError.notCommitted }
            #expect(connection == f.keychain.connection && registered.server.intent == intent)
            #expect(!(await next.permitsNewStoreRegistration()))
            let snapshot = try await mediaSnapshot(reopened)
            #expect(snapshot.registrationIntents.count == 1 && snapshot.registrations.count == 1)
            #expect(snapshot.confirmations.isEmpty && snapshot.invalidations.isEmpty && snapshot.outbox.isEmpty)
            let retainedCredential = try f.keychain.bytes(newRegistrationCredentialAccount(identity, f.keychain.connection.destination)) == namespaceBytes
            #expect(retainedCredential)
            let finalCalls = [await remote.posts, await remote.discoveries]
            #expect(finalCalls == [1, 1])
            try f.assertOldBytes()
        }
    }

    @Test func sameStoreConnectionBeforeIntentUsesOrdinaryContinueInsteadOfAnotherNewRegistration() async throws {
        try await withStorageRun { run in
            let f = try await NewRegistrationKeychain.make()
            let store = try SQLiteRecordingStore(run: run, mode: .createNew)
            let identity = try await establishRegistrationIdentity(store)
            defer { f.cleanup([identity]) }
            let vault = try f.keychain.vault()
            try await vault.saveNewStoreConnection(f.keychain.connection, bearer: "new-fixture-bearer", storeIdentity: identity)
            let remote = RegistrationTestRemote()
            let coordinator = RegistrationCoordinator(store: store, vault: vault, remote: remote)
            #expect(await coordinator.restore() == .needsRegistration(f.keychain.connection))
            #expect(!(await coordinator.permitsNewStoreRegistration()))
            #expect(await coordinator.registerNewStore(connection: f.keychain.connection, bearer: "new-fixture-bearer") == .unavailable(.credentialConflict))
            guard case .registered = await coordinator.registerSavedConnection() else { throw BackendContractError.notCommitted }
            #expect(await remote.posts == 1)
            try f.assertOldBytes()
        }
    }

    @Test func identityReplyLossStartsNeitherCredentialsNorNetworkAndCanBeRetriedExplicitly() async throws {
        try await withStorageRun { run in
            let f = try await NewRegistrationKeychain.make()
            var identities: [RegistrationStoreIdentity] = []
            defer { f.cleanup(identities) }
            let base = try SQLiteRecordingStore(run: run, mode: .createNew)
            let store = NewRegistrationStore(base: base)
            await store.loseIdentityReply()
            let remote = RegistrationTestRemote()
            let coordinator = RegistrationCoordinator(store: store, vault: try f.keychain.vault(), remote: remote)
            #expect(await coordinator.registerNewStore(connection: f.keychain.connection, bearer: "new-fixture-bearer") == .unavailable(.storage))
            let identity = try #require(try await mediaSnapshot(base).storeIdentity)
            identities.append(identity)
            #expect(try f.keychain.bytes(newRegistrationConnectionAccount(identity)) == nil)
            let stoppedCalls = [await remote.discoveries, await remote.posts, await remote.lookups]
            #expect(stoppedCalls == [0, 0, 0])
            #expect(try await mediaSnapshot(base).registrationIntents.isEmpty)
            await store.returnIdentityReply()
            guard case .registered = await coordinator.registerNewStore(connection: f.keychain.connection, bearer: "new-fixture-bearer") else {
                throw BackendContractError.notCommitted
            }
            try f.assertOldBytes()
        }
    }

    @Test func awaitAfterDiscoveryRechecksCurrentUUIDBeforeWritingAnyNewNamespace() async throws {
        try await withStorageRun { run in
            let f = try await NewRegistrationKeychain.make()
            var identities: [RegistrationStoreIdentity] = []
            defer { f.cleanup(identities) }
            let base = try SQLiteRecordingStore(run: run, mode: .createNew)
            let store = NewRegistrationStore(base: base)
            let gate = NewRegistrationGate()
            let remote = NewRegistrationDelayedRemote(gate: gate)
            let coordinator = RegistrationCoordinator(store: store, vault: try f.keychain.vault(), remote: remote)
            let registering = Task { await coordinator.registerNewStore(connection: f.keychain.connection, bearer: "new-fixture-bearer") }
            defer { Task { await gate.release() } }
            try await gate.wait()
            let original = try #require(try await mediaSnapshot(base).storeIdentity)
            identities.append(original)
            await store.replaceObservedIdentity()
            await gate.release()
            #expect(await registering.value == .unavailable(.credentialConflict))
            #expect(try f.keychain.bytes(newRegistrationConnectionAccount(original)) == nil)
            #expect(await remote.posts() == 0)
            #expect(try await mediaSnapshot(base).registrationIntents.isEmpty)
            try f.assertOldBytes()
        }
    }

    @Test func concurrentExplicitCallsChooseOneIntentAndModelNeverRetainsDepartedBearer() async throws {
        try await withStorageRun { run in
            let f = try await NewRegistrationKeychain.make()
            var identities: [RegistrationStoreIdentity] = []
            defer { f.cleanup(identities) }
            let store = try SQLiteRecordingStore(run: run, mode: .createNew)
            let remote = RegistrationTestRemote()
            let coordinator = RegistrationCoordinator(store: store, vault: try f.keychain.vault(), remote: remote)
            let model = ConnectionModel(coordinator: coordinator)
            await model.restore()
            #expect(model.permitsNewStoreRegistration && !model.permitsInitialInput)
            model.openNewStoreRegistrationInput()
            model.origin = "https://new-registration.invalid"; model.destination = f.keychain.connection.destination.rawValue
            model.bearer = "departed-fixture-bearer"
            model.cancelNewStoreRegistrationInput()
            #expect(model.bearer.isEmpty && model.origin.isEmpty && model.destination.isEmpty)
            model.openNewStoreRegistrationInput()
            model.origin = "http://new-registration.invalid"; model.destination = f.keychain.connection.destination.rawValue
            model.bearer = "rejected-fixture-bearer"
            await model.registerNewStore()
            #expect(model.state == .unavailable(.configuration) && model.bearer.isEmpty)
            #expect(await remote.discoveries == 0)
            async let first = coordinator.registerNewStore(connection: f.keychain.connection, bearer: "new-fixture-bearer")
            async let second = coordinator.registerNewStore(connection: f.keychain.connection, bearer: "new-fixture-bearer")
            let results = await [first, second]
            #expect(results.contains(where: { if case .registered = $0 { return true }; return false }))
            let final = try await mediaSnapshot(store)
            identities.append(try #require(final.storeIdentity))
            #expect(final.registrationIntents.count == 1 && final.registrations.count == 1)
            #expect(await remote.posts == 1)
            try f.assertOldBytes()
        }
    }
}

private actor NewRegistrationStore {
    let base: any MediaOperationStorePort
    private var losesIdentity = false
    private var replacement: RegistrationStoreIdentity?
    init(base: any MediaOperationStorePort) { self.base = base }
    func loseIdentityReply() { losesIdentity = true }
    func returnIdentityReply() { losesIdentity = false }
    func replaceObservedIdentity() { replacement = .init(rawValue: UUID()) }
    func establishRegistrationIdentity(expectedRevision: UInt64, expectedIdentity: RegistrationStoreIdentity?) async throws -> RegistrationStoreIdentity {
        let result = try await base.establishRegistrationIdentity(expectedRevision: expectedRevision, expectedIdentity: expectedIdentity)
        if losesIdentity { throw BackendContractError.unavailable }
        return result
    }
    func load() async -> BackendStoreLoadResult {
        guard case .loaded(var snapshot) = await base.load() else { return .unavailable(.inaccessible) }
        if let replacement { snapshot.storeIdentity = replacement }
        return .loaded(snapshot)
    }
    func commit(_ mutation: BackendStoreMutation) async -> BackendCommitResult { await base.commit(mutation) }
    func lookupCommit(_ mutation: BackendStoreMutation) async -> BackendCommitResult { await base.lookupCommit(mutation) }
}
extension NewRegistrationStore: MediaOperationStorePort {}

private actor NewRegistrationGate {
    private var arrived = false
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    func checkpoint() async { arrived = true; if !released { await withCheckedContinuation { continuation = $0 } } }
    func hasArrived() -> Bool { arrived }
    func wait() async throws { try await backgroundEventually { await self.hasArrived() } }
    func release() { released = true; continuation?.resume(); continuation = nil }
}

private actor NewRegistrationDelayedRemote {
    let gate: NewRegistrationGate
    let base = RegistrationTestRemote()
    init(gate: NewRegistrationGate) { self.gate = gate }
    func posts() async -> Int { await base.posts }
    func checkConnection(_ connection: RegistrationConnection, bearer: String) async -> BackendOutcome<BackendCapabilities> {
        await gate.checkpoint(); return await base.checkConnection(connection, bearer: bearer)
    }
    func discover(_ connection: RegistrationConnection, storeIdentity: RegistrationStoreIdentity) async -> BackendOutcome<BackendCapabilities> {
        await base.discover(connection, storeIdentity: storeIdentity)
    }
    func register(_ command: RegistrationCommand, at connection: RegistrationConnection, storeIdentity: RegistrationStoreIdentity) async -> BackendOutcome<RegistrationServerReceipt> {
        await base.register(command, at: connection, storeIdentity: storeIdentity)
    }
    func lookup(_ intent: RegistrationIntent, at connection: RegistrationConnection, storeIdentity: RegistrationStoreIdentity) async -> BackendOutcome<RegistrationServerReceipt> {
        await base.lookup(intent, at: connection, storeIdentity: storeIdentity)
    }
}
extension NewRegistrationDelayedRemote: RegistrationRemotePort {}
