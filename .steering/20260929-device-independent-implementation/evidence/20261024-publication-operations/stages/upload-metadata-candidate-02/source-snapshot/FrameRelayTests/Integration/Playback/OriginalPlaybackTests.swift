import AVFoundation
import Foundation
import Testing
@testable import FrameRelay

@Suite(.serialized) @MainActor struct OriginalPlaybackTests {
    @Test func realPlayerAdvancesDecodesFrameAndReleasesTheOnlyOriginalReader() async throws {
        try await withStorageRun { run in
            let binding = try await makeBindingMovie(run: run)
            let store = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let files = ManagedOriginalStore(run: run)
            let access = ManagedOriginalAccess(store: store, originals: files)
            #expect(await access.bind(binding.reference, operation: .init(rawValue: "bind")) == .succeeded(binding))
            let before = await store.loadRecordings()
            let player = AVOriginalPlayback(access: access, observesDecodedFrames: true)
            let id = PlaybackSessionID(rawValue: "play-one")
            let result = await player.open(binding.original, operation: .init(rawValue: "play"), session: id)
            guard case .succeeded(let progress) = result else { Issue.record("AVPlayer failed to advance: \(result)"); return }
            #expect(progress.session == id)
            #expect(progress.source.lease.original == binding.original)
            #expect(progress.elapsedSeconds > 0)
            #expect(player.audioTrackCount == 1)
            #expect(await playbackEventually { player.decodedFrameCount > 0 })
            let originalURL = try await files.existingURL(for: binding.reference)
            let digestBefore = try await files.digest(for: binding.reference)
            let sdkPlayer = try #require(player.player)
            let asset = try #require(sdkPlayer.currentItem?.asset as? AVURLAsset)
            #expect(asset.url.scheme == "fr-original")
            #expect(asset.url != originalURL)
            #expect(asset.referenceRestrictions == .forbidAll)
            #expect(await access.reconcileReaders(binding.original) == .inProgress)
            await player.stopOriginal(id)
            #expect(player.phase == .stopped)
            #expect(player.player == nil)
            #expect(sdkPlayer.currentItem == nil)
            #expect(sdkPlayer.rate == 0)
            #expect(player.maximumReadLength > 0 && player.maximumReadLength <= 65_536)
            #expect(player.deliveredBytes > 0)
            #expect(player.lastRelease == .succeeded(.init(lease: progress.source.lease)))
            try await assertPlaybackReleased(access, store: store, original: binding.original)
            #expect(try await files.digest(for: binding.reference) == digestBefore)
            guard case .loaded(let recordedBefore) = before, case .loaded(let after) = await store.loadRecordings() else {
                Issue.record("Recording facts unavailable"); return
            }
            #expect(after.recordings == recordedBefore.recordings)
            #expect(after.recordings[0].result?.result == .unknown(.evidenceMissing))
        }
    }

    @Test func thirtySecondProductConfigurationAdvancesWithoutVideoOutputAndReleases() async throws {
        try await withStorageRun { run in
            let binding = try await makePlaybackFixtureBinding(run, durationSeconds: 30)
            let store = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let files = ManagedOriginalStore(run: run)
            let access = ManagedOriginalAccess(store: store, originals: files)
            try #require(await access.bind(binding.reference, operation: .init(rawValue: "bind-30-seconds")) == .succeeded(binding))
            let before = await store.loadRecordings()
            let digestBefore = try await files.digest(for: binding.reference)
            let diagnostics = OriginalPlaybackDiagnostics()
            let player = AVOriginalPlayback(access: access, observesDecodedFrames: false, diagnostics: diagnostics)
            defer {
                if let data = try? JSONEncoder().encode(diagnostics.report) {
                    Attachment.record(String(decoding: data, as: UTF8.self), named: "original-playback-30-seconds-diagnostics.json")
                } else { Issue.record("Could not encode anonymous playback observations") }
            }
            let id = PlaybackSessionID(rawValue: "play-30-seconds-no-video-output")
            let result = await player.open(binding.original, operation: .init(rawValue: "play-30-seconds"), session: id)
            guard case .succeeded(let progress) = result else {
                await player.stopOriginal(id)
                try await assertPlaybackReleased(access, store: store, original: binding.original)
                Issue.record("Thirty-second product configuration did not advance; inspect anonymous diagnostics")
                return
            }
            #expect(progress.source.lease.original == binding.original)
            #expect(progress.elapsedSeconds > 0)
            #expect(player.audioTrackCount == 1)
            #expect(player.decodedFrameCount == 0)
            let sdk = try #require(player.player)
            let duration = try #require(sdk.currentItem).duration.seconds
            #expect(duration.isFinite && abs(duration - 30) < 0.1)
            await player.stopOriginal(id)
            #expect(player.phase == .stopped)
            #expect(sdk.currentItem == nil && sdk.rate == 0)
            #expect(player.lastRelease == .succeeded(.init(lease: progress.source.lease)))
            try await assertPlaybackReleased(access, store: store, original: binding.original)
            #expect(try await files.digest(for: binding.reference) == digestBefore)
            guard case .loaded(let initial) = before, case .loaded(let final) = await store.loadRecordings() else {
                Issue.record("Recording facts unavailable"); return
            }
            #expect(final.recordings == initial.recordings)
            #expect(diagnostics.events.contains { $0.kind == .playCalled })
            #expect(diagnostics.events.contains { $0.kind == .beforeSDKClose && $0.sdk?.itemStatus != nil })
            #expect(diagnostics.events.contains { $0.kind == .loaderDrained && $0.loader?.pending == 0 })
            #expect(diagnostics.events.contains { $0.kind == .releaseSucceeded })
            #expect(diagnostics.events.count <= OriginalPlaybackDiagnostics.capacity)
            #expect(diagnostics.report.totalEvents == diagnostics.events.count + diagnostics.droppedEvents)
            #expect(diagnostics.report.emittedLogEvents <= OriginalPlaybackDiagnostics.capacity)
            #expect(diagnostics.terminal?.kind == .releaseSucceeded)
            #expect(diagnostics.terminal?.beforeSDKClose?.currentItemPresent == true)
            #expect(diagnostics.terminal?.finalSDK?.currentItemPresent == false)
            #expect(diagnostics.terminal?.loader?.pending == 0)
        }
    }

    @Test func stopRequestStopsBufferedPlayerAndAnOldSessionCannotStopTheNextOne() async throws {
        try await withStorageRun { run in
            let binding = try await makeBindingMovie(run: run)
            let store = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let access = ManagedOriginalAccess(store: store, originals: ManagedOriginalStore(run: run))
            _ = await access.bind(binding.reference, operation: .init(rawValue: "bind"))
            let player = AVOriginalPlayback(access: access)
            let first = PlaybackSessionID(rawValue: "first")
            guard case .succeeded(let progress) = await player.open(binding.original, operation: .init(rawValue: "first-play"), session: first) else {
                Issue.record("First playback did not advance"); return
            }
            let sdkPlayer = try #require(player.player)
            #expect(await player.open(binding.original, operation: .init(rawValue: "duplicate"), session: .init(rawValue: "duplicate")) == .notExecuted)
            await access.requestReaderStop(progress.source.lease)
            #expect(await playbackEventually { !player.isBusy })
            #expect(sdkPlayer.currentItem == nil)
            #expect(player.phase == .stopped)
            try await assertPlaybackReleased(access, store: store, original: binding.original)
            let second = PlaybackSessionID(rawValue: "second")
            guard case .succeeded = await player.open(binding.original, operation: .init(rawValue: "second-play"), session: second) else {
                Issue.record("Second playback did not advance"); return
            }
            await player.stopOriginal(first)
            #expect(player.activeSession == second)
            #expect(player.player?.currentItem != nil)
            await player.stopOriginal(second)
            #expect(await player.open(binding.original, operation: .init(rawValue: "reused-session"), session: first) == .notExecuted)
            try await assertPlaybackReleased(access, store: store, original: binding.original)
        }
    }

    @Test func invalidMovieFailsWithoutSavingOrConfirmingAndClosesReader() async throws {
        try await withStorageRun { run in
            let binding = try await makePlaybackFixtureBinding(run)
            let store = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let files = ManagedOriginalStore(run: run)
            let access = ManagedOriginalAccess(store: store, originals: files)
            _ = await access.bind(binding.reference, operation: .init(rawValue: "bind"))
            let player = AVOriginalPlayback(access: access)
            let result = await player.open(binding.original, operation: .init(rawValue: "invalid"), session: .init(rawValue: "invalid-session"))
            guard case .failed = result else { Issue.record("Invalid bytes were treated as playback: \(result)"); return }
            #expect(player.elapsedSeconds == 0)
            #expect(player.phase == .failed)
            #expect(player.player == nil)
            try await assertPlaybackReleased(access, store: store, original: binding.original)
            #expect(try await files.digest(for: binding.reference).sha256 == binding.original.content.digest)
            guard case .loaded(let snapshot) = await store.loadRecordings() else { Issue.record("Missing save record"); return }
            guard case .unknown = binding.saveRecord.result else { Issue.record("Unplayable bytes must retain uncertain save facts"); return }
            #expect(snapshot.recordings[0].result == binding.saveRecord)
        }
    }

    @Test func stopDuringDelayedSDKReadWaitsForRealDrainBeforeReleasingLease() async throws {
        try await withStorageRun { run in
            let binding = try await makeBindingMovie(run: run)
            let store = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let access = ManagedOriginalAccess(store: store, originals: ManagedOriginalStore(run: run))
            _ = await access.bind(binding.reference, operation: .init(rawValue: "bind"))
            let gate = PlaybackReadGate()
            let player = AVOriginalPlayback(access: access, beforeRead: { await gate.hold() })
            let id = PlaybackSessionID(rawValue: "delayed")
            let starting = Task { await player.open(binding.original, operation: .init(rawValue: "delayed-play"), session: id) }
            #expect(await playbackEventually { await gate.isWaiting })
            let source = try #require(player.activeSource)
            let stopping = Task { await player.stopOriginal(id) }
            #expect(await playbackEventually { player.phase == .stopping })
            #expect(await access.releaseRead(source.lease) == .inProgress)
            #expect(await access.reconcileReaders(binding.original) == .inProgress)
            #expect(player.player == nil)
            await gate.release()
            await stopping.value
            #expect(await starting.value == .notExecuted)
            #expect(player.deliveredBytes == 0)
            try await assertPlaybackReleased(access, store: store, original: binding.original)
        }
    }

    @Test func stopBeforeAttachmentWaitsForOutstandingOriginalOpen() async throws {
        try await withStorageRun { run in
            let binding = try await makeBindingMovie(run: run)
            let store = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let files = ManagedOriginalStore(run: run)
            let gate = PlaybackReadGate()
            let opener = PlaybackDelayedOpener(files: files, gate: gate)
            let access = ManagedOriginalAccess(store: store, originals: files, opener: opener)
            _ = await access.bind(binding.reference, operation: .init(rawValue: "bind"))
            let player = AVOriginalPlayback(access: access)
            let id = PlaybackSessionID(rawValue: "opening")
            let starting = Task { await player.open(binding.original, operation: .init(rawValue: "opening-play"), session: id) }
            #expect(await playbackEventually { await gate.isWaiting })
            let stopping = Task { await player.stopOriginal(id) }
            #expect(await playbackEventually { player.phase == .stopping })
            #expect(await access.reconcileReaders(binding.original) == .inProgress)
            await gate.release()
            await stopping.value
            #expect(await starting.value == .notExecuted)
            #expect(player.player == nil)
            #expect(!player.isBusy)
            try await assertPlaybackReleased(access, store: store, original: binding.original)
        }
    }

    @Test func presentationClosedBeforeItsStartTaskRunsDoesNotCreateAReader() async throws {
        try await withStorageRun { run in
            let binding = try await makeBindingMovie(run: run)
            let store = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let access = ManagedOriginalAccess(store: store, originals: ManagedOriginalStore(run: run))
            _ = await access.bind(binding.reference, operation: .init(rawValue: "bind"))
            let player = AVOriginalPlayback(access: access)
            let model = OriginalPlaybackModel(playback: player)
            #expect(model.open(.init(capture: binding.original.capture, reference: binding.reference, original: binding.original),
                               operation: .init(rawValue: "close-immediately")))
            await model.close()
            #expect(model.target == nil)
            #expect(model.canOpen)
            #expect(player.player == nil)
            try await assertPlaybackReleased(access, store: store, original: binding.original)
        }
    }

    @Test func unresolvedDurableReleasePreservesLeaseButDoesNotTrapPresentation() async throws {
        try await withStorageRun { run in
            let binding = try await makeBindingMovie(run: run)
            let disk = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let store = PlaybackReleaseFaultStore(disk: disk)
            let access = ManagedOriginalAccess(store: store, originals: ManagedOriginalStore(run: run))
            _ = await access.bind(binding.reference, operation: .init(rawValue: "bind"))
            let player = AVOriginalPlayback(access: access)
            let model = OriginalPlaybackModel(playback: player)
            #expect(model.open(.init(capture: binding.original.capture, reference: binding.reference, original: binding.original),
                               operation: .init(rawValue: "uncertain-release")))
            #expect(await playbackEventually { player.elapsedSeconds > 0 })
            let source = try #require(player.activeSource)
            await store.failReleases()
            await model.close()
            #expect(model.target == nil)
            #expect(!model.canOpen)
            #expect(player.phase == .releaseNeedsReconciliation)
            #expect(player.player == nil)
            #expect(player.activeSource == source)
            #expect(await access.reconcileReaders(binding.original) == .inProgress)
            // Fault recovery is outside presentation; the real owner can retry the retained release.
            await store.allowReleases()
            #expect(await access.releaseRead(source.lease) == .succeeded(.init(lease: source.lease)))
        }
    }

    @Test func backwardSeekUpdatesCurrentPositionAndResumeShowsActualPlayback() async throws {
        try await withStorageRun { run in
            let binding = try await makeBindingMovie(run: run)
            let store = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let access = ManagedOriginalAccess(store: store, originals: ManagedOriginalStore(run: run))
            _ = await access.bind(binding.reference, operation: .init(rawValue: "bind"))
            let player = AVOriginalPlayback(access: access)
            let id = PlaybackSessionID(rawValue: "seek-session")
            guard case .succeeded = await player.open(binding.original, operation: .init(rawValue: "seek-play"), session: id) else {
                Issue.record("Player did not advance before seek"); return
            }
            #expect(await playbackEventually { player.elapsedSeconds > 0.3 })
            let sdk = try #require(player.player)
            sdk.pause()
            #expect(await playbackEventually { player.phase == .paused })
            #expect(await sdk.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero))
            #expect(await playbackEventually { player.elapsedSeconds < 0.05 })
            #expect(player.phase == .paused)
            sdk.play()
            #expect(await playbackEventually { player.phase == .playing && player.elapsedSeconds > 0.05 })
            await player.stopOriginal(id)
            try await assertPlaybackReleased(access, store: store, original: binding.original)
        }
    }
}

@MainActor private func playbackEventually(_ condition: () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await condition()
}

nonisolated private func assertPlaybackReleased(_ access: ManagedOriginalAccess, store: SQLiteRecordingStore,
                                               original: OriginalContent) async throws {
    guard case .succeeded = await access.reconcileReaders(original),
          case .succeeded(let snapshot) = await store.loadOriginalState() else {
        Issue.record("Original reader/FD release was not committed"); return
    }
    #expect(snapshot.originals.first?.readers.isEmpty == true)
}

private actor PlaybackReadGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var released = false
    var isWaiting: Bool { !waiters.isEmpty }
    func hold() async {
        if released { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        released = true
        let pending = waiters; waiters = []
        pending.forEach { $0.resume() }
    }
}

private struct PlaybackDelayedOpener: ManagedOriginalReadOpeningPort {
    let files: ManagedOriginalStore
    let gate: PlaybackReadGate
    func openBoundRead(_ binding: OriginalBinding) async throws -> ManagedOriginalReadHandle {
        let handle = try await files.openBoundRead(binding)
        await gate.hold()
        return handle
    }
}

private actor PlaybackReleaseFaultStore: RecordingStorePort, OriginalStorePort {
    let disk: SQLiteRecordingStore
    private var rejectsRelease = false
    init(disk: SQLiteRecordingStore) { self.disk = disk }
    func failReleases() { rejectsRelease = true }
    func allowReleases() { rejectsRelease = false }
    func loadRecordings() async -> RecordingStoreLoadResult { await disk.loadRecordings() }
    func loadUnfinished() async -> UnfinishedRecordingLoadResult { await disk.loadUnfinished() }
    func execute(_ command: RecordingStoreCommand) async -> RecordingStoreResult { await disk.execute(command) }
    func loadOriginalState() async -> BackendOutcome<OriginalStoreSnapshot> { await disk.loadOriginalState() }
    func commitOriginal(_ mutation: OriginalStoreMutation) async -> OriginalStoreCommitResult {
        if rejectsRelease, case .release = mutation.change { return .unavailable(.inaccessible) }
        return await disk.commitOriginal(mutation)
    }
}

nonisolated private func makePlaybackFixtureBinding(_ run: ExplorationRunDirectory, durationSeconds: Double? = nil) async throws -> OriginalBinding {
    let fixture = try CaptureFixture()
    let store = try SQLiteRecordingStore(run: run, mode: .createNew)
    let files = ManagedOriginalStore(run: run)
    let coordinator = OriginalSaveCoordinator(store: store, originals: files, inspection: AVOriginalInspectionAdapter(originals: files))
    _ = await coordinator.begin(fixture.intent, token: fixture.token(1))
    let url = try await files.reservedURL(for: fixture.intent.original)
    if let durationSeconds {
        try await SyntheticMovieFixture.write(to: url, withAudio: true, durationSeconds: durationSeconds)
    } else {
        try Data(repeating: 0x37, count: 4096).write(to: url, options: .withoutOverwriting)
    }
    _ = await coordinator.recordingEnded(context: fixture.context, evidence: fixture.end)
    let digest = try await files.digest(for: fixture.intent.original)
    let file = CaptureFileEvidence(context: fixture.context, original: fixture.intent.original,
                                   byteCount: digest.byteCount, finalizedAt: fixture.time)
    guard case .committed(let record, let receipt) = await coordinator.fileFinalized(file, resultToken: fixture.token(4)) else {
        throw BackendContractError.notCommitted
    }
    return .init(original: .init(capture: fixture.context.capture, generation: .init(rawValue: 1),
        content: try .init(byteCount: digest.byteCount, algorithm: "sha256", digest: digest.sha256)),
        reference: fixture.intent.original, saveRecord: record, saveCommit: receipt)
}
