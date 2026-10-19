import AVFoundation
import Foundation
import Testing
@testable import FrameRelay

@Suite(.serialized) @MainActor
struct ProductCaptureSavePlaybackTests {
    @Test func ordinaryIntentFlowsThroughCommonSaveReopenLibraryAndRealOriginalPlayback() async throws {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("FrameRelay-capture-save-playback-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        // Retain this isolated evidence until process/container teardown. The
        // lifetime of a test function does not prove SQLite descriptors closed.
        let services = try await ProductLibraryFactory(supportDirectory: parent).open()
        let fixture = try CaptureFixture(clip: "ordinary-capture-save-playback")
        let capturedAt = Date(timeIntervalSince1970: 1_600_000_000.25)
        let intent = RecordingIntent(context: fixture.context, operation: fixture.intent.operation,
            original: fixture.intent.original, desired: fixture.desired, applied: fixture.applied,
            acceptedAt: fixture.time, capturedAt: capturedAt)
        let inspector = AVOriginalInspectionAdapter(originals: services.originals)
        let saving = OriginalSaveCoordinator(store: services.store, originals: services.originals,
                                             inspection: inspector)

        try #require(await saving.begin(intent, token: fixture.token(1))
            == .ready(fixture.receipt(fixture.token(1))))
        let pending = try await capturePlaybackRecordingSnapshot(services.store)
        #expect(pending.recordings.count == 1)
        #expect(pending.recordings.first?.intent == intent)
        #expect(pending.recordings.first?.result == nil)
        // The common save owner reserved once, before committing the intent.
        // The producer must consume that reservation instead of reserving again.
        let destination = ProductReservedOriginalDestination(store: services.originals)
        let url = try await destination.reserve(original: intent.original)
        #expect(url == (try await services.originals.reservedURL(for: intent.original)))
        try await SyntheticMovieFixture.write(to: url, withAudio: true, durationSeconds: 3)
        try #require(await saving.recordingEnded(context: fixture.context, evidence: fixture.end) == .accepted)
        guard case .present(let byteCount) = await services.originals.observeFile(intent.original) else {
            Issue.record("The finalized synthetic movie must exist in its managed reservation")
            throw CaptureContractError.evidenceMismatch
        }
        #expect(byteCount > 0)
        let file = CaptureFileEvidence(context: fixture.context, original: intent.original,
                                       byteCount: byteCount, finalizedAt: fixture.time)
        guard case .committed(let record, let receipt) = await saving.fileFinalized(file, resultToken: fixture.token(4)) else {
            Issue.record("Common save did not commit its actual file inspection")
            throw CaptureContractError.wrongStage
        }
        #expect(receipt == fixture.receipt(fixture.token(4), previous: 1))
        #expect(record.intent == intent)
        #expect(record.intent.trialReference == nil)
        #expect(record.intent.capturedAt == capturedAt)
        #expect(record.file.byteCount == byteCount)
        #expect(record.inspection.video.hasSamples)
        #expect(record.inspection.audio.hasSamples)
        // Synthetic H.264 and PCM prove the save/playback connection only. The
        // inspector has no validated actual-Log or complete-playback evidence.
        #expect(record.result == .unknown(.evidenceMissing))
        #expect(record.inspection.playback == .unavailable(.notMeasured))
        #expect(record.inspection.completeness == .unknown(.evidenceMissing))
        let observation = try #require(await inspector.observation(for: intent.original))
        #expect(observation.videoTrackCount == 1 && observation.audioTrackCount == 1)
        #expect(observation.digest.byteCount == byteCount)

        guard case .succeeded(let binding) = await services.access.bind(intent.original,
            operation: .init(rawValue: "bind-ordinary-capture-save-playback")) else {
            Issue.record("The saved original must have a committed content binding")
            throw CaptureContractError.evidenceMismatch
        }
        #expect(binding.saveRecord == record && binding.saveCommit == receipt)
        #expect(binding.original.content.digest == observation.digest.sha256)

        let reopened = try await ProductLibraryFactory(supportDirectory: parent).open()
        #expect(reopened.store !== services.store)
        guard case .loaded(let snapshot) = await reopened.reader.loadLibrary() else {
            Issue.record("The product library must reopen the shared save and content binding")
            throw CaptureContractError.wrongStage
        }
        try #require(snapshot.items.count == 1)
        let item = try #require(snapshot.items.first)
        #expect(snapshot.history.isEmpty)
        #expect(item.id == fixture.context.capture)
        #expect(item.recording.intent == intent)
        #expect(item.recording.intent.capturedAt == capturedAt)
        #expect(item.recording.result == record)
        #expect(item.original == binding.original)
        #expect(item.file == .present(byteCount: byteCount))
        #expect(item.requiresReconciliation)
        let before = try await capturePlaybackRecordingSnapshot(reopened.store)
        let digestBefore = try await reopened.originals.digest(for: intent.original)
        #expect(digestBefore == observation.digest)

        let player = AVOriginalPlayback(access: reopened.access)
        let playbackModel = OriginalPlaybackModel(playback: player)
        let commands = OriginalPlaybackLibraryCommands(model: playbackModel)
        let library = LibraryModel(reader: reopened.reader, commands: commands)
        let source: OriginalPlaybackSource
        do {
            await library.refresh()
            #expect(library.failure == nil)
            #expect(library.item(fixture.context.capture)?.recording.intent.capturedAt == capturedAt)
            try #require(library.availability(.playOriginal, captures: [fixture.context.capture]) == .available)
            await library.submit(.playOriginal, captures: [fixture.context.capture])
            #expect(library.submission?.phase == .playbackHandedOff)
            #expect(playbackModel.target?.original == binding.original)
            #expect(playbackModel.target?.reference == intent.original)
            try #require(await captureSavePlaybackEventually { player.elapsedSeconds > 0 })
            #expect(player.audioTrackCount == 1)
            source = try #require(player.activeSource)
            #expect(source.lease.original == binding.original)
            #expect(await reopened.access.reconcileReaders(binding.original) == .inProgress)
            #expect(library.availability(.playOriginal, captures: [fixture.context.capture]) != .available)
        } catch {
            // Even a failed assertion or cancelled wait must drain the SDK and
            // release its durable original reader before the test exits.
            await playbackModel.close()
            throw error
        }
        await playbackModel.close()
        #expect(playbackModel.target == nil && playbackModel.canOpen)
        #expect(player.player == nil && !player.isBusy)
        #expect(player.lastRelease == .succeeded(.init(lease: source.lease)))
        guard case .succeeded = await reopened.access.reconcileReaders(binding.original),
              case .succeeded(let originalState) = await reopened.store.loadOriginalState() else {
            Issue.record("Playback reader and its file descriptor were not durably released")
            throw CaptureContractError.wrongStage
        }
        #expect(originalState.originals.count == 1)
        #expect(originalState.originals.allSatisfy { $0.readers.isEmpty })
        #expect(originalState.originals.first?.binding == binding)
        #expect(try await reopened.originals.digest(for: intent.original) == digestBefore)
        let after = try await capturePlaybackRecordingSnapshot(reopened.store)
        #expect(after.recordings == before.recordings)
        #expect(after.recordings.first?.result?.result == .unknown(.evidenceMissing))
        await library.refresh()
        #expect(library.item(fixture.context.capture)?.recording.result == record)
        #expect(library.item(fixture.context.capture)?.recording.intent.capturedAt == capturedAt)
        #expect(library.availability(.playOriginal, captures: [fixture.context.capture]) == .available)
    }
}

nonisolated private func capturePlaybackRecordingSnapshot(_ store: SQLiteRecordingStore) async throws
    -> RecordingStoreSnapshot {
    guard case .loaded(let snapshot) = await store.loadRecordings() else {
        Issue.record("The real product recording store must be readable")
        throw CaptureContractError.wrongStage
    }
    return snapshot
}

@MainActor private func captureSavePlaybackEventually(_ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while ContinuousClock.now < deadline {
        if condition() { return true }
        if Task.isCancelled { return false }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}
