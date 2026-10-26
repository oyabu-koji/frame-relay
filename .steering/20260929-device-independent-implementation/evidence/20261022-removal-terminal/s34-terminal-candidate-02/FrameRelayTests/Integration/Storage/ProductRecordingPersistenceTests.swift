import CoreData
import Foundation
import Testing
@testable import FrameRelay

struct ProductRecordingPersistenceTests {
    @Test(arguments: StorageCandidate.allCases)
    func ordinaryRecordingKeepsOneCalendarDateAcrossIntentResultAndReopen(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let fixture = try CaptureFixture()
            let capturedAt = Date(timeIntervalSince1970: 1_600_000_000.25)
            let intent = productIntent(fixture, capturedAt: capturedAt)
            let store = try candidate.open(run, mode: .createNew)
            #expect(await store.execute(.commitIntent(fixture.token(1), expectedRevision: 0, intent))
                == .committed(fixture.receipt(fixture.token(1))))

            let reopened = try candidate.open(.openExisting(at: run.url), mode: .openExisting)
            let pending = try await productSnapshot(reopened)
            #expect(pending.revision == 1)
            #expect(pending.recordings.count == 1)
            #expect(pending.recordings.first?.intent == intent)
            #expect(pending.recordings.first?.intent.trialReference == nil)
            #expect(pending.recordings.first?.intent.capturedAt == capturedAt)
            #expect(pending.recordings.first?.result == nil)

            let result = try productResult(fixture, intent: intent)
            #expect(result.intent.capturedAt == capturedAt)
            #expect(await reopened.execute(.commitResult(fixture.token(4), expectedRevision: 1, result))
                == .committed(fixture.receipt(fixture.token(4), previous: 1)))
            let completedStore = try candidate.open(.openExisting(at: run.url), mode: .openExisting)
            let completed = try await productSnapshot(completedStore)
            #expect(completed.revision == 2)
            #expect(completed.recordings.first?.result == result)
            #expect(completed.recordings.first?.result?.intent.capturedAt == capturedAt)
            #expect(completed.recordings.first?.result?.result == .saved)
            #expect(await completedStore.loadUnfinished() == .loaded([]))
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func changingCalendarDateInResultCannotReplaceCommittedIntent(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let fixture = try CaptureFixture()
            let capturedAt = Date(timeIntervalSince1970: 1_600_000_000)
            let intent = productIntent(fixture, capturedAt: capturedAt)
            let store = try candidate.open(run, mode: .createNew)
            try #require(await store.execute(.commitIntent(fixture.token(1), expectedRevision: 0, intent))
                == .committed(fixture.receipt(fixture.token(1))))
            let altered = try productResult(fixture,
                intent: productIntent(fixture, capturedAt: capturedAt.addingTimeInterval(1)))
            #expect(await store.execute(.commitResult(fixture.token(4), expectedRevision: 1, altered))
                == .rejected(fixture.token(4), .evidenceMismatch))

            let reopened = try candidate.open(run, mode: .openExisting)
            let snapshot = try await productSnapshot(reopened)
            #expect(snapshot.revision == 1)
            #expect(snapshot.recordings.first?.intent == intent)
            #expect(snapshot.recordings.first?.result == nil)
            let correct = try productResult(fixture, intent: intent)
            #expect(await reopened.execute(.commitResult(fixture.token(4), expectedRevision: 1, correct))
                == .committed(fixture.receipt(fixture.token(4), previous: 1)))
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func ordinaryIntentRequiresFiniteCalendarObservationBeforeDiskCommit(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let fixture = try CaptureFixture()
            let store = try candidate.open(run, mode: .createNew)
            let dates: [Date?] = [nil, Date(timeIntervalSinceReferenceDate: .infinity),
                                 Date(timeIntervalSinceReferenceDate: .nan)]
            for capturedAt in dates {
                let intent = productIntent(fixture, capturedAt: capturedAt)
                #expect(await store.execute(.commitIntent(fixture.token(1), expectedRevision: 0, intent))
                    == .rejected(fixture.token(1), .invalidValue))
            }
            let reopened = try candidate.open(run, mode: .openExisting)
            let snapshot = try await productSnapshot(reopened)
            #expect(snapshot.revision == 0)
            #expect(snapshot.recordings.isEmpty)
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func legacySchemaSixStaysUndatedAndMigratesOnlyOnCommit(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let legacyFixture = try CaptureFixture(clip: "legacy-undated-recording")
            let legacyResult = try syntheticResult(legacyFixture, unknown: true)
            let bytes = try JSONEncoder().encode(SchemaSixRecordingPayload(fixture: legacyFixture,
                                                                           result: legacyResult))
            #expect(String(decoding: bytes, as: UTF8.self).contains("\"capturedAt\"") == false)
            try installProductPayload(bytes, candidate: candidate, run: run)

            let store = try candidate.open(run, mode: .openExisting)
            let legacy = try await productSnapshot(store)
            #expect(legacy.revision == 2)
            #expect(legacy.recordings.count == 1)
            #expect(legacy.recordings.first?.intent == legacyFixture.intent)
            #expect(legacy.recordings.first?.result == legacyResult)
            #expect(legacy.recordings.first?.intent.capturedAt == nil)
            #expect(legacy.recordings.first?.result?.intent.capturedAt == nil)
            #expect(try readProductPayload(candidate: candidate, run: run) == bytes)

            let fixture = try CaptureFixture(clip: "ordinary-after-migration")
            let capturedAt = Date(timeIntervalSince1970: 1_600_000_000)
            let intent = productIntent(fixture, capturedAt: capturedAt)
            #expect(await store.execute(.commitIntent(fixture.token(1), expectedRevision: 0, intent))
                == .committed(fixture.receipt(fixture.token(1))))
            let reopened = try candidate.open(.openExisting(at: run.url), mode: .openExisting)
            let after = try await productSnapshot(reopened)
            #expect(after.revision == 3)
            #expect(after.recordings.count == 2)
            #expect(after.recordings.first == legacy.recordings.first)
            #expect(after.recordings.last?.intent == intent)
            let migratedBytes = try readProductPayload(candidate: candidate, run: run)
            let document = try RecordingStoreDocument.decode(migratedBytes)
            #expect(document.schema == RecordingStoreDocument.currentSchema)
            #expect(document.legacyRevision == 0)
            #expect(try firstProductEntryJSON(migratedBytes) == firstProductEntryJSON(bytes))
        }
    }

    @Test func missingLegacyTrialCannotBeReclassifiedAsOrdinaryRecording() throws {
        let fixture = try CaptureFixture()
        let bytes = try JSONEncoder().encode(SchemaSixRecordingPayload(fixture: fixture,
            result: syntheticResult(fixture, unknown: true)))
        var object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var entries = try #require(object["entries"] as? [[String: Any]])
        var intent = try #require(entries[0]["intent"] as? [String: Any])
        intent.removeValue(forKey: "trialReference")
        // A calendar value does not make a malformed schema-6 record legitimate.
        intent["capturedAt"] = 123.0
        entries[0]["intent"] = intent
        var result = try #require(entries[0]["result"] as? [String: Any])
        result["intent"] = intent
        entries[0]["result"] = result
        object["entries"] = entries
        let corrupt = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: ExplorationStorageError.corruptStore) { try RecordingStoreDocument.decode(corrupt) }
    }
}

nonisolated private func productIntent(_ fixture: CaptureFixture, capturedAt: Date?) -> RecordingIntent {
    RecordingIntent(context: fixture.context, operation: fixture.intent.operation, original: fixture.intent.original,
                    desired: fixture.desired, applied: fixture.applied, acceptedAt: fixture.time,
                    capturedAt: capturedAt)
}

nonisolated private func productResult(_ fixture: CaptureFixture, intent: RecordingIntent) throws -> RecordingResultRecord {
    var lifecycle = try RecordingSaveLifecycle(intent: intent, intentToken: fixture.token(1), revision: 0)
    try lifecycle.acceptIntentCommit(fixture.receipt(fixture.token(1)))
    try lifecycle.acceptRecordingEnd(context: fixture.context, evidence: fixture.end)
    try lifecycle.acceptFile(fixture.file)
    _ = try lifecycle.acceptInspection(fixture.inspection(), resultToken: fixture.token(4))
    return try #require(lifecycle.resultRecord)
}

nonisolated private func productSnapshot(_ store: any RecordingStorePort) async throws -> RecordingStoreSnapshot {
    guard case .loaded(let snapshot) = await store.loadRecordings() else {
        Issue.record("Expected readable product recording store")
        throw CaptureContractError.wrongStage
    }
    return snapshot
}

/// Frozen schema-6 envelope and intent: legacy encoding must never acquire the
/// current optional fields or depend on relabeling the current document schema.
nonisolated private struct SchemaSixRecordingPayload: Encodable {
    let schema = 6
    let entries: [LegacyEntry]
    let transactionRevision: UInt64 = 2
    let originalJournal: [OriginalStoreJournalEntry] = []
    let backendJournal: [BackendStoreJournalEntry] = []
    let legacyRevision: UInt64 = 0

    struct LegacyIntent: Encodable {
        let context: CaptureContext
        let operation: CaptureOperationID
        let original: CaptureOriginalReference
        let trialReference: String
        let desired: DesiredCaptureSettings
        let applied: AppliedCaptureSettings
        let acceptedAt: CaptureTimeObservation
    }

    struct LegacyResult: Encodable {
        let intent: LegacyIntent
        let end: RecordingEndEvidence
        let file: CaptureFileEvidence
        let inspection: CaptureMediaInspection
        let result: RecordingSaveResult
    }

    struct LegacyEntry: Encodable {
        let intentToken: CaptureCommandToken
        let intent: LegacyIntent
        let revision: UInt64 = 2
        let resultToken: CaptureCommandToken
        let result: LegacyResult
    }

    init(fixture: CaptureFixture, result: RecordingResultRecord) throws {
        let intent = LegacyIntent(context: fixture.context, operation: fixture.intent.operation,
            original: fixture.intent.original, trialReference: try #require(fixture.intent.trialReference),
            desired: fixture.desired, applied: fixture.applied, acceptedAt: fixture.time)
        entries = [.init(intentToken: fixture.token(1), intent: intent, resultToken: fixture.token(4),
            result: .init(intent: intent, end: result.end, file: result.file, inspection: result.inspection,
                          result: result.result))]
    }
}

nonisolated private func firstProductEntryJSON(_ data: Data) throws -> Data {
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let entries = try #require(object["entries"] as? [[String: Any]])
    return try JSONSerialization.data(withJSONObject: #require(entries.first), options: .sortedKeys)
}

nonisolated private func installProductPayload(_ data: Data, candidate: StorageCandidate,
                                              run: ExplorationRunDirectory) throws {
    if candidate == .atomicFile {
        try data.write(to: run.url.appendingPathComponent(candidate.fileName), options: .withoutOverwriting)
    } else {
        let context = try productPayloadContext(run)
        try context.performAndWait {
            let object = NSEntityDescription.insertNewObject(forEntityName: "Document", into: context)
            object.setValue(data, forKey: "payload")
            try context.save()
        }
    }
}

nonisolated private func readProductPayload(candidate: StorageCandidate, run: ExplorationRunDirectory) throws -> Data {
    if candidate == .atomicFile { return try Data(contentsOf: run.url.appendingPathComponent(candidate.fileName)) }
    let context = try productPayloadContext(run)
    return try context.performAndWait {
        let rows = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Document"))
        try #require(rows.count == 1)
        return try #require(rows.first?.value(forKey: "payload") as? Data)
    }
}

nonisolated private func productPayloadContext(_ run: ExplorationRunDirectory) throws -> NSManagedObjectContext {
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
