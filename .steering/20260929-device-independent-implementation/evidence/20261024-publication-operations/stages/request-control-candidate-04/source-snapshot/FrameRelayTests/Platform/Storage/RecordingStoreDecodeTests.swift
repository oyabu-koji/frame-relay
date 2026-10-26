import Foundation
import CoreData
import Testing
@testable import FrameRelay

struct RecordingStoreDecodeTests {
    @Test func danglingStoreAndSQLiteSidecarLinksCannotCreateTheirTargets() async throws {
        for candidate in StorageCandidate.allCases {
            try await withStorageRun { run in
                let target = run.url.appendingPathComponent("synthetic-link-target")
                let link = run.url.appendingPathComponent(candidate.fileName)
                try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
                #expect(throws: ExplorationStorageError.alreadyExists) { try candidate.open(run, mode: .createNew) }
                #expect(!FileManager.default.fileExists(atPath: target.path))
            }
        }
        try await withStorageRun { run in
            let target = run.url.appendingPathComponent("synthetic-sidecar-target")
            let link = run.url.appendingPathComponent("recordings.sqlite-wal")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            #expect(throws: ExplorationStorageError.alreadyExists) {
                try SQLiteRecordingStore(run: run, mode: .createNew)
            }
            #expect(!FileManager.default.fileExists(atPath: target.path))
        }
    }

    @Test func unknownFileSchemaIsNotReset() async throws {
        try await withStorageRun { run in
            let file = run.url.appendingPathComponent("recordings.json")
            let future = Data("{\"schema\":999,\"entries\":[]}".utf8)
            try future.write(to: file, options: .withoutOverwriting)
            #expect(throws: ExplorationStorageError.unknownSchema) {
                try AtomicFileRecordingStore(run: run, mode: .openExisting)
            }
            #expect(try Data(contentsOf: file) == future)
        }
    }

    @Test func incompatibleSQLiteModelIsRejected() async throws {
        try await withStorageRun { run in
            let model = NSManagedObjectModel()
            let entity = NSEntityDescription()
            entity.name = "FutureSchema"; entity.managedObjectClassName = "NSManagedObject"
            model.entities = [entity]
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
            let file = run.url.appendingPathComponent("recordings.sqlite")
            let persistent = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType,
                configurationName: nil, at: file)
            try coordinator.remove(persistent)
            let before = try Data(contentsOf: file)
            #expect(throws: ExplorationStorageError.unknownSchema) {
                try SQLiteRecordingStore(run: run, mode: .openExisting)
            }
            #expect(try Data(contentsOf: file) == before)
        }
    }

    @Test func decodedInvalidValuesAndTargetsAreRejected() throws {
        let fixture = try CaptureFixture()
        var document = RecordingStoreDocument()
        _ = try document.apply(.commitIntent(fixture.token(1), expectedRevision: 0, fixture.intent))
        let valid = try JSONEncoder().encode(document)
        var object = try #require(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        var entries = try #require(object["entries"] as? [[String: Any]])
        var intent = try #require(entries[0]["intent"] as? [String: Any])
        var desired = try #require(intent["desired"] as? [String: Any])
        desired["zoom"] = 0
        intent["desired"] = desired
        entries[0]["intent"] = intent
        object["entries"] = entries
        let malformed = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: ExplorationStorageError.corruptStore) { try RecordingStoreDocument.decode(malformed) }
        #expect(throws: ExplorationStorageError.corruptStore) {
            try RecordingStoreDocument.decode(Data("{\"schema\":1,\"entries\":null}".utf8))
        }
    }
}
