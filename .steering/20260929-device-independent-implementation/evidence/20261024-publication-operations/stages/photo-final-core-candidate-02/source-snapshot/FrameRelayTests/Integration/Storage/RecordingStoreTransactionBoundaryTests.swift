import Foundation
import CoreData
import Testing
@testable import FrameRelay

struct RecordingStoreTransactionBoundaryTests {
    @Test(arguments: StorageCandidate.allCases,
          [RecordingStoreFault.beforeDiskCommit, .afterDiskCommitBeforeReply])
    func interruptedIntentIsReconciledFromDisk(candidate: StorageCandidate, fault: RecordingStoreFault) async throws {
        try await withStorageRun { run in
            let fixture = try CaptureFixture()
            let outcome = try await executeOnce(candidate, run: run, mode: .createNew, fault: fault,
                command: .commitIntent(fixture.token(1), expectedRevision: 0, fixture.intent))
            #expect(outcome == .unavailable(fixture.token(1), .adapterFailure(code: "store-commit-unavailable")))
            // executeOnce owns and discards the complete adapter, including its context.
            let reopened = try candidate.open(try .openExisting(at: run.url), mode: .openExisting)
            let expected: [UnfinishedRecording] = fault == .beforeDiskCommit ? [] : [
                .init(intent: fixture.intent, revision: 1, lastResult: nil)]
            #expect(await reopened.loadUnfinished() == .loaded(expected))
        }
    }

    @Test(arguments: StorageCandidate.allCases,
          [RecordingStoreFault.beforeDiskCommit, .afterDiskCommitBeforeReply])
    func interruptedResultRetainsIntentAndOnlyCommittedResult(candidate: StorageCandidate,
                                                             fault: RecordingStoreFault) async throws {
        try await withStorageRun { run in
            let fixture = try CaptureFixture()
            _ = try await executeOnce(candidate, run: run, mode: .createNew,
                command: .commitIntent(fixture.token(1), expectedRevision: 0, fixture.intent))
            let record = try syntheticResult(fixture, unknown: true)
            let outcome = try await executeOnce(candidate, run: run, mode: .openExisting, fault: fault,
                command: .commitResult(fixture.token(4), expectedRevision: 1, record))
            #expect(outcome == .unavailable(fixture.token(4), .adapterFailure(code: "store-commit-unavailable")))
            let reopened = try candidate.open(try .openExisting(at: run.url), mode: .openExisting)
            let committed = fault == .afterDiskCommitBeforeReply
            #expect(await reopened.loadUnfinished() == .loaded([
                .init(intent: fixture.intent, revision: committed ? 2 : 1,
                      lastResult: committed ? .unknown(.notMeasured) : nil)]))
            // The old expected revision cannot overwrite a committed result.
            let retry = await reopened.execute(.commitResult(fixture.token(4), expectedRevision: 1, record))
            if committed { #expect(retry == .rejected(fixture.token(4), .revisionConflict)) }
            else { #expect(retry == .committed(fixture.receipt(fixture.token(4), previous: 1))) }
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func legacySchemaPreservesRecordingEvidenceAndMigratesOnNextCommit(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let fixture = try CaptureFixture()
            var document = RecordingStoreDocument()
            _ = try document.apply(.commitIntent(fixture.token(1), expectedRevision: 0, fixture.intent))
            let record = try syntheticResult(fixture, unknown: true)
            _ = try document.apply(.commitResult(fixture.token(4), expectedRevision: 1, record))
            var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
            object["schema"] = 1
            object.removeValue(forKey: "transactionRevision")
            let legacy = try JSONSerialization.data(withJSONObject: object)
            try writeLegacy(legacy, candidate: candidate, run: run)
            let old = try readPayload(candidate: candidate, run: run)
            #expect(try RecordingStoreDocument.decode(old).transactionRevision == 2)
            let migrated = try RecordingStoreDocument.decode(old)
            #expect(migrated.entries.first?.result == record)
            #expect(migrated.entries.first?.intentToken == fixture.token(1))
            #expect(migrated.entries.first?.resultToken == fixture.token(4))
            // Merely opening and reading does not rewrite legacy evidence.
            #expect(try await readOnce(candidate, run: run) == .loaded([
                .init(intent: fixture.intent, revision: 2, lastResult: .unknown(.notMeasured))]))
            #expect(try readPayload(candidate: candidate, run: run) == old)
            let next = try CaptureFixture(clip: "second-synthetic")
            #expect(try await executeOnce(candidate, run: run, mode: .openExisting,
                command: .commitIntent(next.token(1), expectedRevision: 0, next.intent))
                == .committed(next.receipt(next.token(1))))
            let persistedData = try readPayload(candidate: candidate, run: run)
            let persistedHeader = try #require(JSONSerialization.jsonObject(with: persistedData) as? [String: Any])
            #expect(persistedHeader["schema"] as? Int == RecordingStoreDocument.currentSchema)
            let persisted = try RecordingStoreDocument.decode(persistedData)
            #expect(persisted.schema == RecordingStoreDocument.currentSchema)
            #expect(persisted.transactionRevision == 3)
            #expect(persisted.entries.first?.result == record)
            #expect(persisted.entries.count == 2)
        }
    }

    @Test func currentSchemaRequiresItsTransactionRevision() throws {
        let noRevision = Data("{\"schema\":2,\"entries\":[]}".utf8)
        #expect(throws: ExplorationStorageError.corruptStore) { try RecordingStoreDocument.decode(noRevision) }
        let inconsistent = Data("{\"schema\":2,\"entries\":[],\"transactionRevision\":1}".utf8)
        #expect(throws: ExplorationStorageError.corruptStore) { try RecordingStoreDocument.decode(inconsistent) }
    }
}

nonisolated private func executeOnce(_ candidate: StorageCandidate, run: ExplorationRunDirectory,
    mode: ExplorationStoreOpenMode, fault: RecordingStoreFault? = nil,
    command: RecordingStoreCommand) async throws -> RecordingStoreResult {
    let store: any RecordingStorePort
    switch candidate {
    case .atomicFile: store = try AtomicFileRecordingStore(run: run, mode: mode, fault: fault)
    case .sqlite: store = try SQLiteRecordingStore(run: run, mode: mode, fault: fault)
    }
    return await store.execute(command)
}

nonisolated private func readOnce(_ candidate: StorageCandidate, run: ExplorationRunDirectory) async throws
    -> UnfinishedRecordingLoadResult {
    let store = try candidate.open(run, mode: .openExisting)
    return await store.loadUnfinished()
}

/// Builds only a new test-owned schema-1 envelope using the existing Core Data model.
nonisolated private func legacyContext(run: ExplorationRunDirectory) throws -> NSManagedObjectContext {
    let entity = NSEntityDescription()
    entity.name = "Document"; entity.managedObjectClassName = "NSManagedObject"
    let payload = NSAttributeDescription()
    payload.name = "payload"; payload.attributeType = .binaryDataAttributeType; payload.isOptional = false
    entity.properties = [payload]
    let model = NSManagedObjectModel()
    model.entities = [entity]; model.versionIdentifiers = ["FrameRelay-D04-v1"]
    let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
    try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil,
        at: run.url.appendingPathComponent("recordings.sqlite"))
    let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
    context.persistentStoreCoordinator = coordinator
    return context
}

nonisolated private func writeLegacy(_ data: Data, candidate: StorageCandidate, run: ExplorationRunDirectory) throws {
    if candidate == .atomicFile {
        try data.write(to: run.url.appendingPathComponent(candidate.fileName), options: .withoutOverwriting)
    } else {
        let context = try legacyContext(run: run)
        try context.performAndWait {
            let object = NSEntityDescription.insertNewObject(forEntityName: "Document", into: context)
            object.setValue(data, forKey: "payload")
            try context.save()
        }
    }
}

nonisolated private func readPayload(candidate: StorageCandidate, run: ExplorationRunDirectory) throws -> Data {
    if candidate == .atomicFile { return try Data(contentsOf: run.url.appendingPathComponent(candidate.fileName)) }
    let context = try legacyContext(run: run)
    return try context.performAndWait {
        let row = try #require(context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Document")).first)
        return try #require(row.value(forKey: "payload") as? Data)
    }
}
