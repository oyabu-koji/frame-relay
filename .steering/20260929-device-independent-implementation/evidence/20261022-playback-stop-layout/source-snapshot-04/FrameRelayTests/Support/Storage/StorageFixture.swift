import Foundation
import Testing
@testable import FrameRelay

nonisolated enum StorageCandidate: String, CaseIterable, Sendable {
    case atomicFile, sqlite

    func open(_ run: ExplorationRunDirectory, mode: ExplorationStoreOpenMode) throws -> any RecordingStorePort {
        switch self {
        case .atomicFile: return try AtomicFileRecordingStore(run: run, mode: mode)
        case .sqlite: return try SQLiteRecordingStore(run: run, mode: mode)
        }
    }

    var fileName: String { self == .atomicFile ? "recordings.json" : "recordings.sqlite" }
}

nonisolated func withStorageRun(_ body: (ExplorationRunDirectory) async throws -> Void) async throws {
    let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent("FrameRelay-synthetic-storage-" + UUID().uuidString, isDirectory: true)
    let run = try ExplorationRunDirectory.createNew(at: url)
    // Keep this UUID-isolated fixture as diagnostic evidence. Returning from the
    // body does not prove every Core Data coordinator/SQLite descriptor closed;
    // unlinking here can invalidate a still-live SQLite store. Cleanup belongs
    // after test-process/container teardown, never a timed delay or guessed ARC
    // lifetime. Retain failed fixtures as well, without hiding the body's error.
    try await body(run)
}

nonisolated func syntheticResult(_ fixture: CaptureFixture, unknown: Bool = false) throws -> RecordingResultRecord {
    var lifecycle = try RecordingSaveLifecycle(intent: fixture.intent, intentToken: fixture.token(1), revision: 0)
    try lifecycle.acceptIntentCommit(fixture.receipt(fixture.token(1)))
    try lifecycle.acceptRecordingEnd(context: fixture.context, evidence: fixture.end)
    try lifecycle.acceptFile(fixture.file)
    let inspection: CaptureMediaInspection
    if unknown {
        inspection = CaptureMediaInspection(context: fixture.context, original: fixture.intent.original,
            video: .unavailable(.notMeasured), audio: .unavailable(.notMeasured),
            format: .unavailable(.notMeasured), playback: .unavailable(.notMeasured),
            completeness: .unknown(.notMeasured))
    } else { inspection = fixture.inspection() }
    _ = try lifecycle.acceptInspection(inspection, resultToken: fixture.token(4))
    return try #require(lifecycle.resultRecord)
}
