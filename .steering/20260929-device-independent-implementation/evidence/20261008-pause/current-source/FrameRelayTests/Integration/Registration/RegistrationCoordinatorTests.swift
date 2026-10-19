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
            try await vault.saveConnection(fixture.connection, bearer: "fixture-bootstrap")
            let originalIntent = try await vault.prepareIntent(for: fixture.connection.destination)
            let store = try SQLiteRecordingStore(run: run, mode: .createNew)
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
            try await vault.saveConnection(fixture.connection, bearer: "fixture-bootstrap")
            let originalIntent = try await vault.prepareIntent(for: fixture.connection.destination)
            let initial = try SQLiteRecordingStore(run: run, mode: .createNew)
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
}
