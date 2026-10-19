import Foundation
import Testing
@testable import FrameRelay

struct ExplorationDiagnosticsStoreTests {
    @Test func appendReadbackAndReopenPreserveMoreThanDisplayHistory() async throws {
        try await withStorageRun { run in
            let fixture = try CaptureFixture()
            let store = try ExplorationDiagnosticsStore(run: run, mode: .createNew)
            var expected: [ExplorationDiagnosticRecord] = []
            let prefix: [ExplorationDeviceEvent] = [
                .capture(.whiteBalanceLocked(fixture.token(2), fixture.lock)),
                .capture(.recordingStarted(fixture.token(3), fixture.time)),
                .fileFinalized(fixture.file)]
            for event in prefix { expected.append(try await store.append(event)) }
            // The UI may show 100 observations; persistent control evidence must
            // retain every record. These are synthetic codes, not per-frame logs.
            for index in 0..<101 {
                expected.append(try await store.append(.observation(.init(code: "synthetic-control",
                    context: fixture.context, time: fixture.time, detail: "step-\(index)"))))
            }
            #expect(expected.map(\.sequence) == Array(UInt64(1)...UInt64(104)))
            #expect(try await store.load() == expected)
            let reopened = try ExplorationDiagnosticsStore(run: .openExisting(at: run.url), mode: .openExisting)
            #expect(try await reopened.load() == expected)
        }
    }

    @Test func distinctOwnersAppendWithoutLostRecords() async throws {
        try await withStorageRun { run in
            let fixture = try CaptureFixture()
            let first = try ExplorationDiagnosticsStore(run: run, mode: .createNew)
            let second = try ExplorationDiagnosticsStore(run: run, mode: .openExisting)
            let eventOne = ExplorationDeviceEvent.capture(.recordingStarted(fixture.token(3), fixture.time))
            let eventTwo = ExplorationDeviceEvent.capture(.recordingEnded(fixture.token(4), fixture.end))
            async let one = first.append(eventOne)
            async let two = second.append(eventTwo)
            let records = try await [one, two]
            #expect(records.map(\.sequence).sorted() == [1, 2])
            #expect(try await second.load() == records.sorted { $0.sequence < $1.sequence })
        }
    }

    @Test func explicitOpenCreateAndExistingFilesRemainProtected() async throws {
        try await withStorageRun { run in
            #expect(throws: ExplorationStorageError.inaccessible) {
                try ExplorationDiagnosticsStore(run: run, mode: .openExisting)
            }
            _ = try ExplorationDiagnosticsStore(run: run, mode: .createNew)
            #expect(throws: ExplorationStorageError.alreadyExists) {
                try ExplorationDiagnosticsStore(run: run, mode: .createNew)
            }
        }
        try await withStorageRun { run in
            let target = run.url.appendingPathComponent("synthetic-uncreated-target")
            let link = run.url.appendingPathComponent("diagnostics.json")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            #expect(throws: ExplorationStorageError.alreadyExists) {
                try ExplorationDiagnosticsStore(run: run, mode: .createNew)
            }
            #expect(!FileManager.default.fileExists(atPath: target.path))
        }
    }

    @Test func unknownSchemaAndCorruptionAreNotReinitialized() async throws {
        let inputs: [(String, ExplorationStorageError)] = [
            ("{\"schema\":999,\"events\":[]}", .unknownSchema),
            ("{\"schema\":1,\"events\":null}", .corruptStore),
            ("synthetic-broken-json", .corruptStore)]
        for (text, expected) in inputs {
            try await withStorageRun { run in
                let file = run.url.appendingPathComponent("diagnostics.json")
                let bytes = Data(text.utf8)
                try bytes.write(to: file, options: .withoutOverwriting)
                #expect(throws: expected) { try ExplorationDiagnosticsStore(run: run, mode: .openExisting) }
                #expect(try Data(contentsOf: file) == bytes)
            }
        }
    }

    @Test func tamperedSequenceAndInvalidEventAreRejected() async throws {
        try await withStorageRun { run in
            let fixture = try CaptureFixture()
            let store = try ExplorationDiagnosticsStore(run: run, mode: .createNew)
            _ = try await store.append(.capture(.recordingStarted(fixture.token(3), fixture.time)))
            let file = run.url.appendingPathComponent("diagnostics.json")
            var document = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            var records = try #require(document["events"] as? [[String: Any]])
            records[0]["sequence"] = 2
            document["events"] = records
            let corrupted = try JSONSerialization.data(withJSONObject: document)
            try corrupted.write(to: file, options: .atomic)
            await #expect(throws: ExplorationStorageError.corruptStore) { try await store.load() }
            await #expect(throws: ExplorationStorageError.corruptStore) {
                try await store.append(.fileFinalized(fixture.file))
            }
            #expect(try Data(contentsOf: file) == corrupted)
        }
        try await withStorageRun { run in
            let fixture = try CaptureFixture()
            let store = try ExplorationDiagnosticsStore(run: run, mode: .createNew)
            let event = ExplorationDeviceEvent.observation(.init(code: "synthetic-control", context: fixture.context,
                time: fixture.time, detail: "/synthetic/path-not-allowed"))
            await #expect(throws: CaptureContractError.invalidValue) { try await store.append(event) }
            #expect(try await store.load().isEmpty)
        }
    }
}
