import Foundation
import Testing
@testable import FrameRelay

struct RecordingStorePersistenceTests {
    @Test(arguments: StorageCandidate.allCases)
    func commitsSurviveExplicitReopen(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let fixture = try CaptureFixture()
            let store = try candidate.open(run, mode: .createNew)
            #expect(await store.execute(.commitIntent(fixture.token(1), expectedRevision: 0, fixture.intent))
                    == .committed(fixture.receipt(fixture.token(1))))
            let reopened = try candidate.open(try .openExisting(at: run.url), mode: .openExisting)
            #expect(await reopened.loadUnfinished() == .loaded([
                UnfinishedRecording(intent: fixture.intent, revision: 1, lastResult: nil)]))
            let result = try syntheticResult(fixture, unknown: true)
            #expect(await reopened.execute(.commitResult(fixture.token(4), expectedRevision: 1, result))
                    == .committed(fixture.receipt(fixture.token(4), previous: 1)))
            let again = try candidate.open(run, mode: .openExisting)
            #expect(await again.loadUnfinished() == .loaded([
                UnfinishedRecording(intent: fixture.intent, revision: 2, lastResult: .unknown(.notMeasured))]))
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func successfulTechnicalResultIsNotUnfinished(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let fixture = try CaptureFixture()
            let store = try candidate.open(run, mode: .createNew)
            _ = await store.execute(.commitIntent(fixture.token(1), expectedRevision: 0, fixture.intent))
            let result = try syntheticResult(fixture)
            #expect(await store.execute(.commitResult(fixture.token(4), expectedRevision: 1, result))
                    == .committed(fixture.receipt(fixture.token(4), previous: 1)))
            let reopened = try candidate.open(run, mode: .openExisting)
            #expect(await reopened.loadUnfinished() == .loaded([]))
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func distinctOwnersRejectStaleAndDuplicateUpdates(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let fixture = try CaptureFixture()
            let first = try candidate.open(run, mode: .createNew)
            let second = try candidate.open(run, mode: .openExisting)
            async let one = first.execute(.commitIntent(fixture.token(1), expectedRevision: 0, fixture.intent))
            async let two = second.execute(.commitIntent(fixture.token(1), expectedRevision: 0, fixture.intent))
            let outcomes = await [one, two]
            #expect(outcomes.filter { if case .committed = $0 { return true }; return false }.count == 1)
            #expect(outcomes.filter { if case .rejected = $0 { return true }; return false }.count == 1)
            let result = try syntheticResult(fixture)
            #expect(await first.execute(.commitResult(fixture.token(4), expectedRevision: 0, result))
                    == .rejected(fixture.token(4), .revisionConflict))
            #expect(await first.execute(.commitResult(fixture.token(4), expectedRevision: 1, result))
                    == .committed(fixture.receipt(fixture.token(4), previous: 1)))
            #expect(await second.execute(.commitResult(fixture.token(4), expectedRevision: 1, result))
                    == .rejected(fixture.token(4), .revisionConflict))
            #expect(await second.execute(.commitResult(fixture.token(5), expectedRevision: 2, result))
                    == .rejected(fixture.token(5), .duplicateOrOutOfOrder))
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func mismatchedTargetAndFabricatedResultDoNotCommit(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let fixture = try CaptureFixture()
            let other = try CaptureFixture(clip: "other-synthetic")
            let store = try candidate.open(run, mode: .createNew)
            _ = await store.execute(.commitIntent(fixture.token(1), expectedRevision: 0, fixture.intent))
            let result = try syntheticResult(fixture)
            #expect(await store.execute(.commitResult(other.token(4), expectedRevision: 1, result))
                    == .rejected(other.token(4), .wrongContext))
            #expect(await store.execute(.commitResult(fixture.token(1), expectedRevision: 1, result))
                    == .rejected(fixture.token(1), .evidenceMismatch))
            let unknown = try syntheticResult(fixture, unknown: true)
            let fabricated = RecordingResultRecord(intent: unknown.intent, end: unknown.end, file: unknown.file,
                                                  inspection: unknown.inspection, result: .saved)
            #expect(await store.execute(.commitResult(fixture.token(4), expectedRevision: 1, fabricated))
                    == .rejected(fixture.token(4), .evidenceMismatch))
            #expect(await store.loadUnfinished() == .loaded([
                UnfinishedRecording(intent: fixture.intent, revision: 1, lastResult: nil)]))
            #expect(await store.execute(.commitResult(fixture.token(4), expectedRevision: 1, result))
                    == .committed(fixture.receipt(fixture.token(4), previous: 1)))
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func openingNeverCreatesOrReplacesAnExistingStore(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            #expect(throws: ExplorationStorageError.inaccessible) { try candidate.open(run, mode: .openExisting) }
            _ = try candidate.open(run, mode: .createNew)
            #expect(throws: ExplorationStorageError.alreadyExists) { try candidate.open(run, mode: .createNew) }
            // Only this test's newly created synthetic store is fault-injected.
            let corrupt = Data("synthetic-corrupt-store".utf8)
            let file = run.url.appendingPathComponent(candidate.fileName)
            try corrupt.write(to: file, options: .atomic)
            #expect(throws: (any Error).self) { try candidate.open(run, mode: .openExisting) }
            #expect(try Data(contentsOf: file) == corrupt)
        }
    }
}
