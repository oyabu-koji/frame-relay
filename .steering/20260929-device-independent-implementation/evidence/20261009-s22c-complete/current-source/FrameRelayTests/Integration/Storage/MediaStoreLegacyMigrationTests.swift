import CoreData
import CryptoKit
import Foundation
import Testing
@testable import FrameRelay

struct MediaStoreLegacyMigrationTests {
    @Test(arguments: StorageCandidate.allCases)
    func schemaThreeReadsPreserveCleanupHistoryAndUnresolvedReaders(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let legacy = try SchemaThreeFixture()
            let bytes = try legacy.encode()
            try installLegacyPayload(bytes, candidate: candidate, run: run)

            // Each helper owns a fresh adapter. A new actor's empty handle map
            // is not evidence that the old epoch's persisted reader has ended.
            try await checkLegacyStateOnce(candidate, run: run, fixture: legacy, revision: 13)
            #expect(try readLegacyPayload(candidate: candidate, run: run) == bytes)
            try await checkLegacyStateOnce(candidate, run: .openExisting(at: run.url),
                                           fixture: legacy, revision: 13)
            #expect(try readLegacyPayload(candidate: candidate, run: run) == bytes)
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func firstMediaCommitMigratesSchemaThreeWithoutLosingLegacyEvidence(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let legacy = try SchemaThreeFixture()
            let bytes = try legacy.encode()
            try installLegacyPayload(bytes, candidate: candidate, run: run)
            let intent = RegistrationIntent(operation: .init(rawValue: "schema4-new-registration"),
                                            destination: .init(rawValue: "schema4-new-destination"))
            let rejected = BackendStoreMutation(expectedRevision: 12, change: .registrationIntent(intent))
            #expect(try await commitMediaOnce(candidate, run: run, mutation: rejected) == .rejected(.revisionConflict))
            #expect(try readLegacyPayload(candidate: candidate, run: run) == bytes)

            let mutation = BackendStoreMutation(expectedRevision: 13, change: .registrationIntent(intent))
            let receipt = BackendCommitReceipt(key: .registrationIntent(intent.operation, intent.destination),
                                               previousRevision: 13, committedRevision: 14)
            try #require(try await commitMediaOnce(candidate, run: run, mutation: mutation) == .committed(receipt))

            let migratedBytes = try readLegacyPayload(candidate: candidate, run: run)
            let persisted = try JSONDecoder().decode(LegacyEvidenceProjection.self, from: migratedBytes)
            #expect(persisted.schema == 5)
            #expect(persisted.legacyRevision == 13)
            #expect(persisted.transactionRevision == 14)
            #expect(persisted.entries == legacy.entries)
            #expect(persisted.originalJournal == legacy.journal)
            // Compare the old JSON subtrees too: migration must not silently
            // replace old evidence with freshly generated receipts or history.
            #expect(try canonicalSubtree("entries", in: migratedBytes) == canonicalSubtree("entries", in: bytes))
            #expect(try canonicalSubtree("originalJournal", in: migratedBytes)
                == canonicalSubtree("originalJournal", in: bytes))

            try await checkLegacyStateOnce(candidate, run: .openExisting(at: run.url), fixture: legacy,
                revision: 14, registration: .init(intent: intent, commit: receipt))
            #expect(try await lookupMediaOnce(candidate, run: run, mutation: mutation) == .committed(receipt))
            #expect(try readLegacyPayload(candidate: candidate, run: run) == migratedBytes)
        }
    }
}

/// Frozen schema-3 envelope, deliberately independent of RecordingStoreDocument
/// and its current encoder/apply methods. Never synthesize a new document and
/// relabel its schema. Domain values below are fixed synthetic historical input,
/// not evidence of an actual recording, deletion, or current cleanup authority.
nonisolated private struct SchemaThreePayload: Encodable {
    let schema = 3
    let entries: [LegacyRecordingEntry]
    let transactionRevision: UInt64
    let originalJournal: [LegacyOriginalJournalEntry]
}

nonisolated private struct LegacyRecordingEntry: Codable, Equatable {
    let intentToken: CaptureCommandToken
    let intent: RecordingIntent
    let revision: UInt64
    let resultToken: CaptureCommandToken
    let result: RecordingResultRecord
}

nonisolated private struct LegacyOriginalJournalEntry: Codable, Equatable {
    let mutation: OriginalStoreMutation
    let receipt: OriginalStoreCommitReceipt
}

nonisolated private struct LegacyEvidenceProjection: Decodable {
    let schema: Int
    let entries: [LegacyRecordingEntry]
    let transactionRevision: UInt64
    let originalJournal: [LegacyOriginalJournalEntry]
    let legacyRevision: UInt64?
}

nonisolated private struct SchemaThreeFixture {
    let entries: [LegacyRecordingEntry]
    let journal: [LegacyOriginalJournalEntry]
    let originals: [OriginalPersistentState]
    let unresolvedReader: OriginalReadLease

    init() throws {
        let completed = try legacyRecording("schema3-cleanup-completed", digest: "a")
        let reserved = try legacyRecording("schema3-cleanup-reserved", digest: "b")
        let reading = try legacyRecording("schema3-reader-unresolved", digest: "c")
        entries = [completed.entry, reserved.entry, reading.entry]
        let completedIntent = RemovalIntent(operation: .init(rawValue: "schema3-cleanup-completed-intent"),
                                            original: completed.binding.original, purpose: .cleanup)
        let reservedIntent = RemovalIntent(operation: .init(rawValue: "schema3-cleanup-reserved-intent"),
                                           original: reserved.binding.original, purpose: .cleanup)
        unresolvedReader = OriginalReadLease(id: .init(rawValue: "schema3-unresolved-lease"),
            original: reading.binding.original, operation: .init(rawValue: "schema3-reader-operation"),
            accessGeneration: .init(rawValue: 1), epoch: .init(rawValue: "schema3-previous-process-epoch"))
        // Six capture commits precede these seven old journal commits. Old
        // cleanup reservations had no S21 verification guard; retain their past
        // meaning without granting a new unlink from an unresolved reservation.
        journal = [
            legacyJournal("schema3-bind-completed", previous: 6, change: .bind(completed.binding)),
            legacyJournal("schema3-reserve-completed", previous: 7,
                change: .reserveRemoval(completedIntent, expectedInvalidation: .init(rawValue: 0),
                                        expectedAccess: .init(rawValue: 0))),
            legacyJournal("schema3-resolve-completed", previous: 8, change: .resolveRemoval(completedIntent, .removed)),
            legacyJournal("schema3-bind-reserved", previous: 9, change: .bind(reserved.binding)),
            legacyJournal("schema3-reserve-unresolved", previous: 10,
                change: .reserveRemoval(reservedIntent, expectedInvalidation: .init(rawValue: 0),
                                        expectedAccess: .init(rawValue: 0))),
            legacyJournal("schema3-bind-reader", previous: 11, change: .bind(reading.binding)),
            legacyJournal("schema3-acquire-unresolved", previous: 12, change: .acquire(unresolvedReader))
        ]
        var completedState = OriginalPersistentState(binding: completed.binding, bindingCommit: journal[0].receipt)
        completedState.resolvedRemoval = completedIntent
        completedState.removalResolution = .removed
        var reservedState = OriginalPersistentState(binding: reserved.binding, bindingCommit: journal[3].receipt)
        reservedState.removal = reservedIntent
        var readingState = OriginalPersistentState(binding: reading.binding, bindingCommit: journal[5].receipt)
        readingState.accessGeneration = .init(rawValue: 1)
        readingState.readers = [unresolvedReader]
        originals = [completedState, reservedState, readingState]
    }

    func encode() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(SchemaThreePayload(entries: entries, transactionRevision: 13,
                                                         originalJournal: journal))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        try #require(Set(object.keys) == ["schema", "entries", "transactionRevision", "originalJournal"])
        try #require(object["schema"] as? Int == 3)
        // Frozen from all four S21-test-03 fixture outputs. A later change to a
        // nested domain Codable must not silently change this schema-3 input.
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try #require(data.count == 29_974)
        try #require(digest == "a2b178bb26ca04d3bd8cbd3b319ec9521a048c4839195d91db613611cc10a9ba")
        print("S21_SCHEMA3_CANONICAL_SHA256=\(digest) byteCount=\(data.count)")
        return data
    }
}

nonisolated private func legacyRecording(_ capture: String, digest: String) throws
    -> (entry: LegacyRecordingEntry, binding: OriginalBinding) {
    let fixture = try CaptureFixture(clip: capture)
    // Preserve an unknown historical result. Cleanup history is not permission
    // to promote it to saved, create verification, or invent a confirmation.
    let record = try syntheticResult(fixture, unknown: true)
    let entry = LegacyRecordingEntry(intentToken: fixture.token(1), intent: fixture.intent, revision: 2,
                                    resultToken: fixture.token(4), result: record)
    let content = try ContentIdentity(byteCount: 4096, algorithm: "sha256", digest: String(repeating: digest, count: 64))
    let binding = OriginalBinding(original: .init(capture: fixture.context.capture,
        generation: .init(rawValue: 1), content: content), reference: fixture.intent.original,
        saveRecord: record, saveCommit: fixture.receipt(fixture.token(4), previous: 1))
    return (entry, binding)
}

nonisolated private func legacyJournal(_ operation: String, previous: UInt64,
                                       change: OriginalStoreChange) -> LegacyOriginalJournalEntry {
    let id = MediaOperationID(rawValue: operation)
    return .init(mutation: .init(operation: id, expectedRevision: previous, change: change),
                 receipt: .init(operation: id, previousRevision: previous, committedRevision: previous + 1))
}

nonisolated private func openLegacyStore(_ candidate: StorageCandidate, run: ExplorationRunDirectory) throws
    -> any RecordingStorePort & OriginalStorePort & MediaOperationStorePort {
    switch candidate {
    case .atomicFile: return try AtomicFileRecordingStore(run: run, mode: .openExisting)
    case .sqlite: return try SQLiteRecordingStore(run: run, mode: .openExisting)
    }
}

nonisolated private func checkLegacyStateOnce(_ candidate: StorageCandidate, run: ExplorationRunDirectory,
    fixture: SchemaThreeFixture, revision: UInt64, registration: CommittedRegistrationIntent? = nil) async throws {
    let store = try openLegacyStore(candidate, run: run)
    let expectedRecordings = fixture.entries.map {
        RecordingStoreEntry(intentToken: $0.intentToken, intent: $0.intent, revision: $0.revision,
                            resultToken: $0.resultToken, result: $0.result)
    }
    try #require(await store.loadRecordings() == .loaded(.init(revision: revision, recordings: expectedRecordings)))
    for (entry, state) in zip(expectedRecordings, fixture.originals) {
        #expect(entry.resultCommit == state.binding.saveCommit)
        #expect(entry.result?.result == .unknown(.notMeasured))
    }
    guard case .succeeded(let state) = await store.loadOriginalState(),
          case .loaded(let backend) = await store.load() else {
        Issue.record("Expected reopened original and media snapshots"); throw BackendContractError.unavailable
    }
    #expect(state.revision == revision)
    #expect(state.originals == fixture.originals)
    #expect(backend.revision == revision)
    #expect(backend.registrationIntents == (registration.map { [$0] } ?? []))
    #expect(backend.registrations.isEmpty)
    #expect(backend.batches.isEmpty)
    #expect(backend.requests.isEmpty)
    #expect(backend.verifications.isEmpty)
    #expect(backend.confirmations.isEmpty)
    #expect(backend.invalidations.isEmpty)
    #expect(backend.outbox.isEmpty)

    let access = ManagedOriginalAccess(store: store, originals: ManagedOriginalStore(run: run))
    #expect(await access.reconcileReaders(fixture.unresolvedReader.original) == .inProgress)
    #expect(await access.recoverPersistedReaders(fixture.unresolvedReader.original) == .unknown)
    guard case .succeeded(let afterRecovery) = await store.loadOriginalState() else {
        Issue.record("Expected unresolved readers to remain readable"); throw BackendContractError.unavailable
    }
    #expect(afterRecovery.revision == revision)
    #expect(afterRecovery.originals == fixture.originals)
}

nonisolated private func commitMediaOnce(_ candidate: StorageCandidate, run: ExplorationRunDirectory,
                                        mutation: BackendStoreMutation) async throws -> BackendCommitResult {
    let store = try openLegacyStore(candidate, run: run)
    return await store.commit(mutation)
}

nonisolated private func lookupMediaOnce(_ candidate: StorageCandidate, run: ExplorationRunDirectory,
                                        mutation: BackendStoreMutation) async throws -> BackendCommitResult {
    let store = try openLegacyStore(candidate, run: run)
    return await store.lookupCommit(mutation)
}

/// The fixture owns this isolated database. No product container or application
/// store is opened here, and existing payloads are never replaced or repaired.
nonisolated private func legacyPayloadContext(run: ExplorationRunDirectory) throws -> NSManagedObjectContext {
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

nonisolated private func installLegacyPayload(_ data: Data, candidate: StorageCandidate,
                                             run: ExplorationRunDirectory) throws {
    // Keep the exact input beside this disposable test store, independently of
    // stdout capture. These evidence files never replace the store payload.
    let fixtureName = "schema3-legacy-fixture.json"
    try data.write(to: run.url.appendingPathComponent(fixtureName), options: .withoutOverwriting)
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let hashLine = Data("\(digest)  \(fixtureName)\n".utf8)
    try hashLine.write(to: run.url.appendingPathComponent("schema3-legacy-fixture.sha256"),
                       options: .withoutOverwriting)
    if candidate == .atomicFile {
        try data.write(to: run.url.appendingPathComponent(candidate.fileName), options: .withoutOverwriting)
    } else {
        try #require(!FileManager.default.fileExists(atPath: run.url.appendingPathComponent(candidate.fileName).path))
        let context = try legacyPayloadContext(run: run)
        try context.performAndWait {
            try #require(context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "Document")) == 0)
            let row = NSEntityDescription.insertNewObject(forEntityName: "Document", into: context)
            row.setValue(data, forKey: "payload")
            try context.save()
        }
    }
}

nonisolated private func readLegacyPayload(candidate: StorageCandidate, run: ExplorationRunDirectory) throws -> Data {
    if candidate == .atomicFile { return try Data(contentsOf: run.url.appendingPathComponent(candidate.fileName)) }
    try ExplorationRunDirectory.requireRegularFile(run.url.appendingPathComponent(candidate.fileName))
    let context = try legacyPayloadContext(run: run)
    return try context.performAndWait {
        let rows = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Document"))
        try #require(rows.count == 1)
        return try #require(rows[0].value(forKey: "payload") as? Data)
    }
}

nonisolated private func canonicalSubtree(_ key: String, in bytes: Data) throws -> Data {
    let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    let value = try #require(object[key])
    return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
}
