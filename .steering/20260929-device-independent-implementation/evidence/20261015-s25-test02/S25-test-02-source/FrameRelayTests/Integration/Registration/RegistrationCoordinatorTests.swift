import Foundation
import Security
import Testing
@testable import FrameRelay

struct RegistrationCoordinatorTests {
    @Test func registrationAndNormalRestartUseOneWriterAndNeverDuplicatePOST() async throws {
        try await withStorageRun { run in
            let fixture = try RegistrationTestKeychain()
            defer { fixture.cleanup() }
            let vault = try fixture.vault(), remote = RegistrationTestRemote()
            let store = try SQLiteRecordingStore(run: run, mode: .createNew)
            let coordinator = RegistrationCoordinator(store: store, vault: vault, remote: remote)
            let state = await coordinator.register(connection: fixture.connection, bearer: "fixture-bootstrap")
            #expect(registrationIsCommitted(state))
            let snapshot = try await registrationSnapshot(store)
            #expect(snapshot.registrationIntents.count == 1 && snapshot.registrations.count == 1)
            #expect(snapshot.confirmations.isEmpty && snapshot.outbox.isEmpty)
            let reopened = try SQLiteRecordingStore(run: .openExisting(at: run.url), mode: .openExisting)
            let next = RegistrationCoordinator(store: reopened, vault: try fixture.vault(), remote: remote)
            #expect(registrationIsCommitted(await next.restore()))
            #expect(await remote.posts == 1)
            #expect(await remote.lookups == 1)
            #expect(await remote.discoveries == 1)
        }
    }
    @Test func lostServerResponseReconcilesSameIntentWithoutSecondPOST() async throws {
        try await withStorageRun { run in
            let fixture = try RegistrationTestKeychain()
            defer { fixture.cleanup() }
            let vault = try fixture.vault(), remote = RegistrationTestRemote()
            await remote.setHideReply()
            let store = try SQLiteRecordingStore(run: run, mode: .createNew)
            let coordinator = RegistrationCoordinator(store: store, vault: vault, remote: remote)
            let state = await coordinator.register(connection: fixture.connection, bearer: "fixture-bootstrap")
            if case .pending = state {} else { Issue.record("Lost reply was not pending") }
            #expect(try await registrationSnapshot(store).registrations.isEmpty)
            let next = RegistrationCoordinator(store: try SQLiteRecordingStore(run: run, mode: .openExisting),
                                               vault: try fixture.vault(), remote: remote)
            #expect(registrationIsCommitted(await next.restore()))
            #expect(await remote.posts == 1)
        }
    }
    @Test func credentialOnlyCrashRequiresExplicitContinuationBeforePOST() async throws {
        try await withStorageRun { run in
            let fixture = try RegistrationTestKeychain()
            defer { fixture.cleanup() }
            let vault = try fixture.vault(), remote = RegistrationTestRemote()
            let store = try SQLiteRecordingStore(run: run, mode: .createNew)
            let identity = try await establishRegistrationIdentity(store)
            try await vault.saveConnection(fixture.connection, bearer: "fixture-bootstrap", storeIdentity: identity)
            let originalIntent = try await vault.prepareIntent(for: fixture.connection.destination, storeIdentity: identity)
            let coordinator = RegistrationCoordinator(store: store, vault: try fixture.vault(), remote: remote)
            if case .needsRegistration = await coordinator.restore() {} else { Issue.record("Explicit continuation missing") }
            #expect(await remote.posts == 0)
            #expect(await remote.lookups == 0)
            #expect(try await registrationSnapshot(store).registrationIntents.isEmpty)
            #expect(registrationIsCommitted(await coordinator.registerSavedConnection()))
            #expect(try await registrationSnapshot(store).registrationIntents.first?.intent == originalIntent)
        }
    }
    @Test(arguments: [RecordingStoreFault.beforeDiskCommit, .afterDiskCommitBeforeReply], [false, true])
    func realSQLiteFaultBeforeOrAfterIntentAndResultCommitRecovers(fault: RecordingStoreFault, atRegistration: Bool) async throws {
        try await withStorageRun { run in
            let fixture = try RegistrationTestKeychain()
            defer { fixture.cleanup() }
            let vault = try fixture.vault(), remote = RegistrationTestRemote()
            let initial = try SQLiteRecordingStore(run: run, mode: .createNew)
            let identity = try await establishRegistrationIdentity(initial)
            try await vault.saveConnection(fixture.connection, bearer: "fixture-bootstrap", storeIdentity: identity)
            let originalIntent = try await vault.prepareIntent(for: fixture.connection.destination, storeIdentity: identity)
            if atRegistration {
                let mutation = BackendStoreMutation(expectedRevision: 0, change: .registrationIntent(originalIntent))
                guard case .committed = await initial.commit(mutation) else { Issue.record("Intent preparation failed"); return }
            }
            let faulty = try SQLiteRecordingStore(run: run, mode: .openExisting, fault: fault)
            let interrupted = RegistrationCoordinator(store: faulty, vault: vault, remote: remote)
            if atRegistration { _ = await interrupted.restore() }
            else { _ = await interrupted.registerSavedConnection() }
            let reopened = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let coordinator = RegistrationCoordinator(store: reopened, vault: try fixture.vault(), remote: remote)
            let restored = await coordinator.restore()
            if !atRegistration && fault == .beforeDiskCommit {
                if case .needsRegistration = restored {} else { Issue.record("Uncommitted intent auto-started") }
                #expect(await remote.posts == 0)
                #expect(registrationIsCommitted(await coordinator.registerSavedConnection()))
            } else { #expect(registrationIsCommitted(restored)) }
            let snapshot = try await registrationSnapshot(reopened)
            #expect(snapshot.registrationIntents.count == 1 && snapshot.registrations.count == 1)
            #expect(snapshot.registrationIntents.first?.intent == originalIntent)
            #expect(await remote.posts == 1)
        }
    }
    @Test func unavailableLookupCannotTurnUnknownIntoASecondRegistration() async throws {
        try await withStorageRun { run in
            let fixture = try RegistrationTestKeychain()
            defer { fixture.cleanup() }
            let vault = try fixture.vault(), remote = RegistrationTestRemote()
            let store = try SQLiteRecordingStore(run: run, mode: .createNew)
            await remote.setLookup(.failed(.authenticationRequired))
            let coordinator = RegistrationCoordinator(store: store, vault: vault, remote: remote)
            _ = await coordinator.register(connection: fixture.connection, bearer: "fixture-bootstrap")
            for outcome: BackendOutcome<RegistrationServerReceipt> in [.unknown, .failed(.rejected), .failed(.unknownSchema), .failed(.connectionUnavailable)] {
                await remote.setLookup(outcome)
                _ = await coordinator.restore()
            }
            let snapshot = try await registrationSnapshot(store)
            #expect(snapshot.registrationIntents.count == 1 && snapshot.registrations.isEmpty)
            #expect(await remote.posts == 0)
        }
    }
    @Test func mismatchedReceiptIsNotCommitted() async throws {
        try await withStorageRun { run in
            let fixture = try RegistrationTestKeychain()
            defer { fixture.cleanup() }
            let remote = RegistrationTestRemote()
            await remote.setMismatch()
            let store = try SQLiteRecordingStore(run: run, mode: .createNew)
            let coordinator = RegistrationCoordinator(store: store, vault: try fixture.vault(), remote: remote)
            let state = await coordinator.register(connection: fixture.connection, bearer: "fixture-bootstrap")
            #expect(state == .unavailable(.identity))
            #expect(try await registrationSnapshot(store).registrations.isEmpty)
        }
    }
    @Test func missingPersistedCredentialKeepsRegistrationAndDoesNotPOST() async throws {
        try await withStorageRun { run in
            let fixture = try RegistrationTestKeychain()
            defer { fixture.cleanup() }
            let remote = RegistrationTestRemote()
            let store = try SQLiteRecordingStore(run: run, mode: .createNew)
            let coordinator = RegistrationCoordinator(store: store, vault: try fixture.vault(), remote: remote)
            #expect(registrationIsCommitted(await coordinator.register(connection: fixture.connection, bearer: "fixture-bootstrap")))
            let before = try await registrationSnapshot(store)
            #expect(SecItemDelete(fixture.query("initial." + fixture.connection.destination.rawValue) as CFDictionary) == errSecSuccess)
            let next = RegistrationCoordinator(store: store, vault: try fixture.vault(), remote: remote)
            #expect(await next.restore() == .unavailable(.credentials))
            #expect(try await registrationSnapshot(store) == before)
            #expect(await remote.posts == 1)
        }
    }
    @Test func concurrentExplicitInputsCoalesceAtCoordinatorBoundary() async throws {
        try await withStorageRun { run in
            let fixture = try RegistrationTestKeychain()
            defer { fixture.cleanup() }
            let remote = RegistrationTestRemote()
            let store = try SQLiteRecordingStore(run: run, mode: .createNew)
            let coordinator = RegistrationCoordinator(store: store, vault: try fixture.vault(), remote: remote)
            async let a = coordinator.register(connection: fixture.connection, bearer: "fixture-bootstrap")
            async let b = coordinator.register(connection: fixture.connection, bearer: "fixture-bootstrap")
            let states = await [a, b]
            #expect(states.contains(where: registrationIsCommitted))
            #expect(await remote.posts == 1)
            #expect(try await registrationSnapshot(store).registrations.count == 1)
        }
    }
    @Test(arguments: [false, true], [false, true])
    func newStoreCannotReuseRetainedKeychainAtAnyEntry(registered: Bool, samePath: Bool) async throws {
        try await withStorageRun { run in
            let fixture = try RegistrationTestKeychain()
            defer { fixture.cleanup() }
            let vault = try fixture.vault(), remote = RegistrationTestRemote()
            let original = try SQLiteRecordingStore(run: run, mode: .createNew)
            if registered {
                let initial = RegistrationCoordinator(store: original, vault: vault, remote: remote)
                try #require(registrationIsCommitted(await initial.register(connection: fixture.connection, bearer: "fixture-bootstrap")))
            } else {
                let identity = try await establishRegistrationIdentity(original)
                try await vault.saveConnection(fixture.connection, bearer: "fixture-bootstrap", storeIdentity: identity)
                _ = try await vault.prepareIntent(for: fixture.connection.destination, storeIdentity: identity)
            }
            let originalIdentity = try #require(try await registrationSnapshot(original).storeIdentity)
            let beforeConnection = try fixture.bytes("connection")
            let beforeSecret = try fixture.bytes("initial." + fixture.connection.destination.rawValue)
            let priorPosts = await remote.posts, priorLookups = await remote.lookups, priorDiscovery = await remote.discoveries
            let freshRun: ExplorationRunDirectory
            if samePath { freshRun = try replaceRegistrationTestRun(run) }
            else {
                freshRun = try ExplorationRunDirectory.createNew(at: run.url.deletingLastPathComponent()
                    .appendingPathComponent("FrameRelay-new-store-" + UUID().uuidString))
            }
            let fresh = try SQLiteRecordingStore(run: freshRun, mode: .createNew)
            let next = RegistrationCoordinator(store: fresh, vault: try fixture.vault(), remote: remote)
            #expect(await next.restore() == .unavailable(.credentialConflict))
            #expect(await next.permitsInitialInput() == false)
            #expect(await next.registerSavedConnection() == .unavailable(.credentialConflict))
            #expect(await next.register(connection: fixture.connection, bearer: "fixture-bootstrap") == .unavailable(.credentialConflict))
            #expect(try await registrationSnapshot(fresh).storeIdentity == nil)
            let newIdentity = try await establishRegistrationIdentity(fresh)
            #expect(newIdentity != originalIdentity)
            #expect(await next.restore() == .unavailable(.credentialConflict))
            #expect(await next.registerSavedConnection() == .unavailable(.credentialConflict))
            #expect(await remote.posts == priorPosts)
            #expect(await remote.lookups == priorLookups)
            #expect(await remote.discoveries == priorDiscovery)
            let connectionUnchanged = try fixture.bytes("connection") == beforeConnection
            let secretUnchanged = try fixture.bytes("initial." + fixture.connection.destination.rawValue) == beforeSecret
            #expect(connectionUnchanged)
            #expect(secretUnchanged)
            #expect(try await registrationSnapshot(fresh).registrationIntents.isEmpty)
            #expect(try await registrationSnapshot(fresh).registrations.isEmpty)
        }
    }

    @Test(arguments: [RecordingStoreFault.beforeDiskCommit, .afterDiskCommitBeforeReply])
    func identityCommitMustFinishBeforeKeychainOrNetwork(fault: RecordingStoreFault) async throws {
        try await withStorageRun { run in
            let fixture = try RegistrationTestKeychain()
            defer { fixture.cleanup() }
            let remote = RegistrationTestRemote()
            let faulty = try SQLiteRecordingStore(run: run, mode: .createNew, fault: fault)
            let interrupted = RegistrationCoordinator(store: faulty, vault: try fixture.vault(), remote: remote)
            #expect(await interrupted.register(connection: fixture.connection, bearer: "fixture-bootstrap") == .unavailable(.storage))
            #expect(try fixture.bytes("connection") == nil)
            #expect(try fixture.bytes("initial." + fixture.connection.destination.rawValue) == nil)
            #expect(await remote.posts == 0)
            #expect(await remote.lookups == 0)
            #expect(await remote.discoveries == 0)
            let reopened = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let snapshot = try await registrationSnapshot(reopened)
            #expect((snapshot.storeIdentity == nil) == (fault == .beforeDiskCommit))
            let next = RegistrationCoordinator(store: reopened, vault: try fixture.vault(), remote: remote)
            #expect(await next.restore() == .needsConnection)
            #expect(registrationIsCommitted(await next.register(connection: fixture.connection, bearer: "fixture-bootstrap")))
            if let identity = snapshot.storeIdentity { #expect(try await registrationSnapshot(reopened).storeIdentity == identity) }
            #expect(await remote.posts == 1)
        }
    }

    @Test func replacementDuringAwaitCannotCommitIntentIntoNewStoreAtSameRevision() async throws {
        try await withStorageRun { run in
            let fixture = try RegistrationTestKeychain()
            defer { fixture.cleanup() }
            let first = try SQLiteRecordingStore(run: run, mode: .createNew)
            let switching = RegistrationReplacingStore(base: first, run: run)
            let remote = RegistrationTestRemote()
            let coordinator = RegistrationCoordinator(store: switching, vault: try fixture.vault(), remote: remote)
            #expect(await coordinator.register(connection: fixture.connection, bearer: "fixture-bootstrap") == .unavailable(.identity))
            let snapshot = try await registrationSnapshot(switching)
            #expect(snapshot.revision == 0 && snapshot.registrationIntents.isEmpty && snapshot.registrations.isEmpty)
            #expect(await remote.posts == 0)
            #expect(await remote.lookups == 0)
            #expect(await coordinator.restore() == .unavailable(.credentialConflict))
        }
    }

}


private actor RegistrationReplacingStore: MediaOperationStorePort {
    private var base: SQLiteRecordingStore
    private let run: ExplorationRunDirectory
    private var shouldReplace = true
    init(base: SQLiteRecordingStore, run: ExplorationRunDirectory) { self.base = base; self.run = run }
    func establishRegistrationIdentity(expectedRevision: UInt64,
        expectedIdentity: RegistrationStoreIdentity?) async throws -> RegistrationStoreIdentity {
        try await base.establishRegistrationIdentity(expectedRevision: expectedRevision, expectedIdentity: expectedIdentity)
    }
    func load() async -> BackendStoreLoadResult { await base.load() }
    func lookupCommit(_ mutation: BackendStoreMutation) async -> BackendCommitResult { await base.lookupCommit(mutation) }
    func commit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        if shouldReplace {
            shouldReplace = false
            do {
                let freshRun = try replaceRegistrationTestRun(run)
                base = try SQLiteRecordingStore(run: freshRun, mode: .createNew)
                _ = try await base.establishRegistrationIdentity(expectedRevision: 0, expectedIdentity: nil)
            } catch { return .unavailable(.inaccessible) }
        }
        return await base.commit(mutation)
    }
}
