import Foundation
import Testing
@testable import FrameRelay

nonisolated private enum SaveInterruption: CaseIterable, Sendable {
    case afterIntent, afterBytes, afterEnd, afterResult
}

struct OriginalSaveRecoveryTests {
    @Test(arguments: SaveInterruption.allCases)
    fileprivate func realMovieRecoveryNeverPromotesUnknown(interruption: SaveInterruption) async throws {
        try await withStorageRun { run in
            let fixture = try CaptureFixture()
            try await createInterruptedMovie(run: run, fixture: fixture, interruption: interruption)
            // All save/inspection/store instances from the recording scope are gone.
            let store = try SQLiteRecordingStore(run: .openExisting(at: run.url), mode: .openExisting)
            let originals = ManagedOriginalStore(run: run)
            let recovery = OriginalRecovery(store: store, originals: originals)
            guard case .loaded(let revision, let recovered) = await recovery.reconcile() else {
                Issue.record("Expected reopened disk and original reconciliation"); return
            }
            let item = try #require(recovered.first)
            #expect(recovered.count == 1)
            #expect(item.recording.intent == fixture.intent)
            #expect(item.recording.intentToken == fixture.token(1))
            #expect(item.requiresReconciliation)
            if interruption == .afterIntent {
                #expect(item.file == .absent)
                #expect(item.recording.result == nil)
                #expect(revision == 1)
            } else {
                guard case .present(let byteCount) = item.file else {
                    Issue.record("Generated movie must remain present"); return
                }
                #expect(byteCount > 0)
                if interruption == .afterResult {
                    let result = try #require(item.recording.result)
                    #expect(result.result == .unknown(.evidenceMissing))
                    #expect(result.inspection.video.hasSamples)
                    #expect(result.inspection.audio.hasSamples)
                    #expect(result.inspection.format.value == nil)
                    #expect(result.inspection.playback == .unavailable(.notMeasured))
                    #expect(item.recording.resultCommit == fixture.receipt(fixture.token(4), previous: 1))
                    #expect(revision == 2)
                } else {
                    #expect(item.recording.result == nil)
                    #expect(revision == 1)
                }
            }
            let before = await store.loadRecordings()
            #expect(await recovery.reconcile() == .loaded(revision: revision, originals: recovered))
            #expect(await store.loadRecordings() == before)
            // No automatic recording, rewrite, or synthetic save result on restart.
            if interruption == .afterIntent { #expect(await originals.observeFile(fixture.intent.original) == .absent) }
        }
    }

    @Test func fileBeforeEndAndWrongByteCountCannotCommit() async throws {
        try await withStorageRun { run in
            let fixture = try CaptureFixture()
            let store = try SQLiteRecordingStore(run: run, mode: .createNew)
            let originals = ManagedOriginalStore(run: run)
            let coordinator = OriginalSaveCoordinator(store: store, originals: originals,
                inspection: AVOriginalInspectionAdapter(originals: originals))
            #expect(await coordinator.begin(fixture.intent, token: fixture.token(1)) == .ready(fixture.receipt(fixture.token(1))))
            let url = try await originals.reservedURL(for: fixture.intent.original)
            try await SyntheticMovieFixture.write(to: url, withAudio: true)
            let bytes = try await originals.byteCount(for: fixture.intent.original)
            let file = CaptureFileEvidence(context: fixture.context, original: fixture.intent.original,
                                           byteCount: bytes, finalizedAt: fixture.time)
            #expect(await coordinator.fileFinalized(file, resultToken: fixture.token(4)) == .rejected(.duplicateOrOutOfOrder))
            #expect(await coordinator.recordingEnded(context: fixture.context, evidence: fixture.end) == .accepted)
            let wrong = CaptureFileEvidence(context: fixture.context, original: fixture.intent.original,
                                            byteCount: bytes + 1, finalizedAt: fixture.time)
            #expect(await coordinator.fileFinalized(wrong, resultToken: fixture.token(4)) == .requiresReconciliation(.evidenceMismatch))
            guard case .committed(let result, _) = await coordinator.fileFinalized(file, resultToken: fixture.token(4)) else {
                Issue.record("Expected true disk commit of the inspector's unknown result"); return
            }
            #expect(result.result == .unknown(.evidenceMissing))
            #expect(await coordinator.begin(fixture.intent, token: fixture.token(1)) == .rejected(.duplicateOrOutOfOrder))
        }
    }

    @Test(arguments: [RecordingStoreFault.beforeDiskCommit, .afterDiskCommitBeforeReply])
    func interruptedRealMovieResultCommitIsResolvedOnlyByReopen(fault: RecordingStoreFault) async throws {
        try await withStorageRun { run in
            let fixture = try CaptureFixture()
            try await saveMovieWithInterruptedCommit(run: run, fixture: fixture, fault: fault)
            let store = try SQLiteRecordingStore(run: .openExisting(at: run.url), mode: .openExisting)
            let originals = ManagedOriginalStore(run: run)
            let recovery = OriginalRecovery(store: store, originals: originals)
            guard case .loaded(let revision, let items) = await recovery.reconcile() else {
                Issue.record("Expected reopened result-commit boundary"); return
            }
            let item = try #require(items.first)
            #expect(item.requiresReconciliation)
            if case .present(let bytes) = item.file { #expect(bytes > 0) }
            else { Issue.record("Commit failure must preserve the actual movie") }
            if fault == .beforeDiskCommit {
                #expect(revision == 1)
                #expect(item.recording.result == nil)
            } else {
                #expect(revision == 2)
                #expect(item.recording.result?.result == .unknown(.evidenceMissing))
            }
        }
    }

    @Test func brokenMovieCommitsUnknownWithoutClaimingPlaybackOrCompleteness() async throws {
        try await withStorageRun { run in
            let fixture = try CaptureFixture()
            let originals = ManagedOriginalStore(run: run)
            let store = try SQLiteRecordingStore(run: run, mode: .createNew)
            let coordinator = OriginalSaveCoordinator(store: store, originals: originals,
                inspection: AVOriginalInspectionAdapter(originals: originals))
            _ = await coordinator.begin(fixture.intent, token: fixture.token(1))
            let url = try await originals.reservedURL(for: fixture.intent.original)
            try Data("synthetic-incomplete-container".utf8).write(to: url, options: .withoutOverwriting)
            _ = await coordinator.recordingEnded(context: fixture.context,
                evidence: .init(writer: .interrupted(.interrupted), ceasedAt: fixture.time,
                                lastVideo: .unavailable(.notMeasured), lastAudio: .unavailable(.notMeasured)))
            let file = CaptureFileEvidence(context: fixture.context, original: fixture.intent.original,
                byteCount: try await originals.byteCount(for: fixture.intent.original), finalizedAt: fixture.time)
            guard case .committed(let result, _) = await coordinator.fileFinalized(file, resultToken: fixture.token(4)) else {
                Issue.record("Inspection failure should be persisted as unknown"); return
            }
            if case .unknown = result.result {} else { Issue.record("Broken unverified input is not saved") }
            #expect(!result.inspection.video.hasSamples)
            #expect(!result.inspection.audio.hasSamples)
        }
    }

    @Test func snapshotAndRecoveryPreserveAllFourContractClassifications() async throws {
        try await withStorageRun { run in
            let expected = try await writeClassificationContracts(run: run)
            let store = try SQLiteRecordingStore(run: .openExisting(at: run.url), mode: .openExisting)
            let originals = ManagedOriginalStore(run: run)
            let recovery = OriginalRecovery(store: store, originals: originals)
            guard case .loaded(let revision, let recovered) = await recovery.reconcile() else {
                Issue.record("Expected all classification records on reopen"); return
            }
            #expect(revision == 8)
            #expect(recovered.map { $0.recording.result?.result } == expected.map { Optional($0.result) })
            #expect(recovered.allSatisfy { $0.file == .present(byteCount: 4096) })
            let saved = try #require(recovered.first)
            let url = try await originals.existingURL(for: saved.recording.intent.original)
            // Fault injection removes only this test's newly generated, non-media bytes.
            try FileManager.default.removeItem(at: url)
            guard case .loaded(_, let after) = await recovery.reconcile() else {
                Issue.record("Missing local file must not erase the management record"); return
            }
            #expect(after.first?.recording.result?.result == .saved)
            #expect(after.first?.file == .absent)
            #expect(after.first?.requiresReconciliation == true)
            #expect(after.count == 4)
        }
    }

    @Test func inaccessibleReservationIsNotReportedAsMissingOriginal() async throws {
        try await withStorageRun { run in
            let originals = ManagedOriginalStore(run: run)
            let reference = CaptureOriginalReference(rawValue: "synthetic-unreserved")
            #expect(await originals.observeFile(reference) == .unavailable(.resourceUnavailable))
            try await originals.reserveForRecording(reference)
            #expect(await originals.observeFile(reference) == .absent)
            let url = try await originals.reservedURL(for: reference)
            let target = run.url.appendingPathComponent("synthetic-other")
            try Data("unrelated-synthetic".utf8).write(to: target, options: .withoutOverwriting)
            try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
            #expect(await originals.observeFile(reference) == .unavailable(.resourceUnavailable))
            #expect(try Data(contentsOf: target) == Data("unrelated-synthetic".utf8))
        }
    }
}

nonisolated private func createInterruptedMovie(run: ExplorationRunDirectory, fixture: CaptureFixture,
                                               interruption: SaveInterruption) async throws {
    let store = try SQLiteRecordingStore(run: run, mode: .createNew)
    let originals = ManagedOriginalStore(run: run)
    let coordinator = OriginalSaveCoordinator(store: store, originals: originals,
        inspection: AVOriginalInspectionAdapter(originals: originals))
    #expect(await coordinator.begin(fixture.intent, token: fixture.token(1)) == .ready(fixture.receipt(fixture.token(1))))
    if interruption == .afterIntent { return }
    let url = try await originals.reservedURL(for: fixture.intent.original)
    try await SyntheticMovieFixture.write(to: url, withAudio: true)
    if interruption == .afterBytes { return }
    #expect(await coordinator.recordingEnded(context: fixture.context, evidence: fixture.end) == .accepted)
    if interruption == .afterEnd { return }
    let file = CaptureFileEvidence(context: fixture.context, original: fixture.intent.original,
        byteCount: try await originals.byteCount(for: fixture.intent.original), finalizedAt: fixture.time)
    guard case .committed(let record, _) = await coordinator.fileFinalized(file, resultToken: fixture.token(4)) else {
        Issue.record("Expected commit after real container inspection"); return
    }
    #expect(record.result == .unknown(.evidenceMissing))
}

/// Synthetic classification contract inputs only. These bytes and fabricated
/// inspection facts are NOT the real-media path or evidence of camera/Log quality.
nonisolated private func writeClassificationContracts(run: ExplorationRunDirectory) async throws -> [RecordingResultRecord] {
    let store = try SQLiteRecordingStore(run: run, mode: .createNew)
    let originals = ManagedOriginalStore(run: run)
    var records: [RecordingResultRecord] = []
    for index in 0..<4 {
        let fixture = try CaptureFixture(clip: "classification-\(index)")
        let url = try await originals.reserve(original: fixture.intent.original)
        try Data(repeating: UInt8(index), count: 4096).write(to: url, options: .withoutOverwriting)
        _ = await store.execute(.commitIntent(fixture.token(1), expectedRevision: 0, fixture.intent))
        var lifecycle = try RecordingSaveLifecycle(intent: fixture.intent, intentToken: fixture.token(1), revision: 0)
        try lifecycle.acceptIntentCommit(fixture.receipt(fixture.token(1)))
        try lifecycle.acceptRecordingEnd(context: fixture.context, evidence: fixture.end)
        try lifecycle.acceptFile(fixture.file)
        let base = fixture.inspection(audio: index == 1 ? .missing : nil)
        let inspection = CaptureMediaInspection(context: base.context, original: base.original,
            video: base.video, audio: base.audio, format: base.format,
            playback: index == 3 ? .failed(.evidenceMismatch) : base.playback,
            completeness: index == 2 ? .unknown(.evidenceMissing) : base.completeness)
        let command = try lifecycle.acceptInspection(inspection, resultToken: fixture.token(4))
        #expect(await store.execute(command) == .committed(fixture.receipt(fixture.token(4), previous: 1)))
        records.append(try #require(lifecycle.resultRecord))
    }
    #expect(records.map { $0.result } == [.saved, .partial(.evidenceMissing), .unknown(.evidenceMissing), .failed(.evidenceMismatch)])
    return records
}

/// Dispatches result commands to the same real SQLite writer with its bounded
/// fault hook. It does not substitute in-memory commit success or media facts.
private actor ResultCommitFaultStore: RecordingStorePort {
    private let normal: SQLiteRecordingStore
    private let interrupted: SQLiteRecordingStore

    init(run: ExplorationRunDirectory, fault: RecordingStoreFault) throws {
        normal = try SQLiteRecordingStore(run: run, mode: .createNew)
        interrupted = try SQLiteRecordingStore(run: run, mode: .openExisting, fault: fault)
    }
    func execute(_ command: RecordingStoreCommand) async -> RecordingStoreResult {
        switch command {
        case .commitIntent: return await normal.execute(command)
        case .commitResult: return await interrupted.execute(command)
        }
    }
    func loadUnfinished() async -> UnfinishedRecordingLoadResult { await normal.loadUnfinished() }
    func loadRecordings() async -> RecordingStoreLoadResult { await normal.loadRecordings() }
}

nonisolated private func saveMovieWithInterruptedCommit(run: ExplorationRunDirectory, fixture: CaptureFixture,
                                                       fault: RecordingStoreFault) async throws {
    let store = try ResultCommitFaultStore(run: run, fault: fault)
    let originals = ManagedOriginalStore(run: run)
    let coordinator = OriginalSaveCoordinator(store: store, originals: originals,
        inspection: AVOriginalInspectionAdapter(originals: originals))
    #expect(await coordinator.begin(fixture.intent, token: fixture.token(1)) == .ready(fixture.receipt(fixture.token(1))))
    let url = try await originals.reservedURL(for: fixture.intent.original)
    try await SyntheticMovieFixture.write(to: url, withAudio: true)
    _ = await coordinator.recordingEnded(context: fixture.context, evidence: fixture.end)
    let file = CaptureFileEvidence(context: fixture.context, original: fixture.intent.original,
        byteCount: try await originals.byteCount(for: fixture.intent.original), finalizedAt: fixture.time)
    #expect(await coordinator.fileFinalized(file, resultToken: fixture.token(4))
        == .requiresReconciliation(.adapterFailure(code: "store-commit-unavailable")))
}
