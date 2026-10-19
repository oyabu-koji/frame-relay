import CoreData
import Foundation
import Testing
@testable import FrameRelay

struct RegistrationStoreIdentityTests {
    @Test func identityCommitPersistsWithoutInventingJournalRevision() async throws {
        try await withStorageRun { run in
            let store = try SQLiteRecordingStore(run: run, mode: .createNew)
            let before = try await registrationSnapshot(store)
            #expect(before.storeIdentity == nil && before.revision == 0)
            let identity = try await establishRegistrationIdentity(store)
            let reopened = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let after = try await registrationSnapshot(reopened)
            #expect(after.storeIdentity == identity && after.revision == before.revision)
            #expect(after.registrationIntents.isEmpty && after.registrations.isEmpty)
            #expect(try await establishRegistrationIdentity(reopened) == identity)
        }
    }

    @Test func sameWriterAndSeparateAdaptersConvergeOnOneDurableIdentity() async throws {
        try await withStorageRun { run in
            let first = try SQLiteRecordingStore(run: run, mode: .createNew)
            let second = try SQLiteRecordingStore(run: run, mode: .openExisting)
            async let a = first.establishRegistrationIdentity(expectedRevision: 0, expectedIdentity: nil)
            async let b = first.establishRegistrationIdentity(expectedRevision: 0, expectedIdentity: nil)
            async let c = second.establishRegistrationIdentity(expectedRevision: 0, expectedIdentity: nil)
            let identities = try await [a, b, c]
            #expect(Set(identities).count == 1)
            #expect(try await registrationSnapshot(second).storeIdentity == identities[0])
        }
    }

    @Test func containerRelocationRetainsIdentityAndOldOpenWriterStops() async throws {
        try await withStorageRun { run in
            let store = try SQLiteRecordingStore(run: run, mode: .createNew)
            let identity = try await establishRegistrationIdentity(store)
            let moved = run.url.deletingLastPathComponent().appendingPathComponent("FrameRelay-moved-" + UUID().uuidString)
            // Move the complete isolated container including its SQLite sidecars; retain all evidence.
            try FileManager.default.moveItem(at: run.url, to: moved)
            let reopened = try SQLiteRecordingStore(run: .openExisting(at: moved), mode: .openExisting)
            #expect(try await registrationSnapshot(reopened).storeIdentity == identity)
            #expect(await store.load() == .unavailable(.inaccessible))
        }
    }

    @Test func replacementAtSamePathRejectsOldIdentityEvenAtSameRevision() async throws {
        try await withStorageRun { run in
            let old = try SQLiteRecordingStore(run: run, mode: .createNew)
            let oldIdentity = try await establishRegistrationIdentity(old)
            let replacementRun = try replaceRegistrationTestRun(run)
            let fresh = try SQLiteRecordingStore(run: replacementRun, mode: .createNew)
            let freshIdentity = try await establishRegistrationIdentity(fresh)
            #expect(freshIdentity != oldIdentity)
            #expect(await old.load() == .unavailable(.inaccessible))
            let intent = RegistrationIntent(operation: .init(rawValue: UUID().uuidString.lowercased()),
                destination: .init(rawValue: UUID().uuidString.lowercased()))
            let mutation = BackendStoreMutation(expectedRevision: 0, change: .registrationIntent(intent),
                                                 expectedStoreIdentity: oldIdentity)
            #expect(await fresh.commit(mutation) == .rejected(.identityMismatch))
            #expect(await fresh.lookupCommit(mutation) == .rejected(.identityMismatch))
            #expect(await old.commit(mutation) == .unavailable(.inaccessible))
            #expect(try await registrationSnapshot(fresh).revision == 0)
            #expect(try await registrationSnapshot(fresh).registrationIntents.isEmpty)
        }
    }

    @Test(arguments: [1, 2, 3, 4])
    func legacyReadIsBytePreservingAndOnlyExplicitIdentityCommitMigrates(schema: Int) async throws {
        try await withStorageRun { run in
            // Frozen legacy envelopes, independent of the current document encoder.
            let envelopes = [
                #"{"schema":1,"entries":[]}"#,
                #"{"schema":2,"entries":[],"transactionRevision":0}"#,
                #"{"schema":3,"entries":[],"transactionRevision":0,"originalJournal":[]}"#,
                #"{"schema":4,"entries":[],"transactionRevision":0,"originalJournal":[],"backendJournal":[],"legacyRevision":0}"#
            ]
            let bytes = Data(envelopes[schema - 1].utf8)
            try registrationFixturePayload(run, install: bytes)
            let store = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let before = try await registrationSnapshot(store)
            #expect(before.storeIdentity == nil && before.revision == 0)
            #expect(try registrationFixturePayload(run) == bytes)
            let reopened = try SQLiteRecordingStore(run: run, mode: .openExisting)
            #expect(try await registrationSnapshot(reopened) == before)
            #expect(try registrationFixturePayload(run) == bytes)
            let identity = try await establishRegistrationIdentity(store)
            let document = try RecordingStoreDocument.decode(registrationFixturePayload(run))
            #expect(document.schema == 6 && document.storeIdentity == identity)
            #expect(document.transactionRevision == 0 && document.legacyRevision == 0)
            #expect(document.entries.isEmpty && document.originalJournal.isEmpty && document.backendJournal.isEmpty)
        }
    }

    @Test(arguments: [RecordingStoreFault.beforeDiskCommit, .afterDiskCommitBeforeReply])
    func identityCommitFaultIsReconciledOnlyFromDisk(fault: RecordingStoreFault) async throws {
        try await withStorageRun { run in
            let faulty = try SQLiteRecordingStore(run: run, mode: .createNew, fault: fault)
            do {
                _ = try await faulty.establishRegistrationIdentity(expectedRevision: 0, expectedIdentity: nil)
                Issue.record("Injected commit boundary returned success")
            } catch {}
            let reopened = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let recovered = try await registrationSnapshot(reopened)
            #expect((recovered.storeIdentity == nil) == (fault == .beforeDiskCommit))
            let identity = try await establishRegistrationIdentity(reopened)
            if let committed = recovered.storeIdentity { #expect(identity == committed) }
            #expect(try await registrationSnapshot(reopened).revision == 0)
        }
    }
    @Test func boundJournalRejectsMissingOrSubstitutedDocumentIdentity() throws {
        let identity = RegistrationStoreIdentity(rawValue: UUID())
        var document = RecordingStoreDocument()
        document.storeIdentity = identity
        let intent = RegistrationIntent(operation: .init(rawValue: UUID().uuidString.lowercased()),
            destination: .init(rawValue: UUID().uuidString.lowercased()))
        _ = try document.applyBackend(.init(expectedRevision: 0, change: .registrationIntent(intent),
                                            expectedStoreIdentity: identity))
        let encoded = try JSONEncoder().encode(document)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "storeIdentity")
        #expect(throws: ExplorationStorageError.corruptStore) {
            try RecordingStoreDocument.decode(JSONSerialization.data(withJSONObject: object))
        }
        document.storeIdentity = RegistrationStoreIdentity(rawValue: UUID())
        #expect(throws: ExplorationStorageError.corruptStore) {
            try RecordingStoreDocument.decode(JSONEncoder().encode(document))
        }
    }

}

/// Replaces only this UUID-isolated test container. The old database and its sidecars remain intact.
nonisolated func replaceRegistrationTestRun(_ run: ExplorationRunDirectory) throws -> ExplorationRunDirectory {
    let archived = run.url.deletingLastPathComponent().appendingPathComponent("FrameRelay-replaced-" + UUID().uuidString)
    try FileManager.default.moveItem(at: run.url, to: archived)
    return try .createNew(at: run.url)
}

/// Explicitly closes its fixture-only coordinator; the production writer is never replaced by this helper.
@discardableResult nonisolated private func registrationFixturePayload(_ run: ExplorationRunDirectory,
                                                                      install: Data? = nil) throws -> Data {
    let entity = NSEntityDescription()
    entity.name = "Document"; entity.managedObjectClassName = "NSManagedObject"
    let payload = NSAttributeDescription()
    payload.name = "payload"; payload.attributeType = .binaryDataAttributeType; payload.isOptional = false
    entity.properties = [payload]
    let model = NSManagedObjectModel()
    model.entities = [entity]; model.versionIdentifiers = ["FrameRelay-D04-v1"]
    let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
    let persistent = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil,
        at: run.url.appendingPathComponent("recordings.sqlite"))
    defer { try? coordinator.remove(persistent) }
    let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
    context.persistentStoreCoordinator = coordinator
    return try context.performAndWait {
        if let install {
            try #require(context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "Document")) == 0)
            let row = NSEntityDescription.insertNewObject(forEntityName: "Document", into: context)
            row.setValue(install, forKey: "payload")
            try context.save()
            return install
        }
        let rows = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Document"))
        try #require(rows.count == 1)
        return try #require(rows[0].value(forKey: "payload") as? Data)
    }
}
