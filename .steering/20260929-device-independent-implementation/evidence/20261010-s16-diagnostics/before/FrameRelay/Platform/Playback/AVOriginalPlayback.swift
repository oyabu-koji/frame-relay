import AVFoundation
import Foundation
import Observation

nonisolated enum OriginalPlayerPhase: Equatable, Sendable {
    case idle, preparing, playing, paused, stopping, ended, stopped, failed, releaseNeedsReconciliation
}

/// One original session. No remote URL, transport, rendition token, or confirmation writer.
@MainActor @Observable final class AVOriginalPlayback: OriginalPlaybackPort {
    private let access: ManagedOriginalAccess
    private let beforeRead: (@Sendable () async -> Void)?
    private let observesDecodedFrames: Bool
    private var session: Session?
    private var usedSessions: Set<PlaybackSessionID> = []
    private(set) var player: AVPlayer?
    private(set) var phase: OriginalPlayerPhase = .idle
    private(set) var elapsedSeconds: Double = 0
    private(set) var audioTrackCount = 0
    private(set) var decodedFrameCount = 0
    private(set) var maximumReadLength = 0
    private(set) var deliveredBytes: UInt64 = 0
    private(set) var issue: String?
    private(set) var lastRelease: BackendOutcome<ReadReleaseReceipt> = .notExecuted
    var activeSession: PlaybackSessionID? { session?.id }
    var activeSource: OriginalPlaybackSource? { session?.source }
    var isBusy: Bool { session != nil }

    init(access: ManagedOriginalAccess, observesDecodedFrames: Bool = false,
         beforeRead: (@Sendable () async -> Void)? = nil) {
        self.access = access
        self.observesDecodedFrames = observesDecodedFrames
        self.beforeRead = beforeRead
    }

    func open(_ original: OriginalContent, operation: MediaOperationID,
              session id: PlaybackSessionID) async -> BackendOutcome<OriginalPlaybackProgress> {
        guard session == nil, !usedSessions.contains(id) else { return .notExecuted }
        return await start(Session(id: id, original: original, operation: operation))
    }

    /// The caller retains responsibility for a source rejected as a duplicate.
    @MainActor func playOriginal(_ source: OriginalPlaybackSource,
                      session id: PlaybackSessionID) async -> BackendOutcome<OriginalPlaybackProgress> {
        guard session == nil, !usedSessions.contains(id) else { return .notExecuted }
        let value = Session(id: id, original: source.lease.original, operation: source.lease.operation)
        value.source = source
        return await start(value)
    }

    private func start(_ value: Session) async -> BackendOutcome<OriginalPlaybackProgress> {
        session = value
        usedSessions.insert(value.id)
        phase = .preparing; issue = nil; elapsedSeconds = 0; audioTrackCount = 0; decodedFrameCount = 0
        maximumReadLength = 0; deliveredBytes = 0; lastRelease = .notExecuted
        let setup = Task { @MainActor in await prepare(value) }
        value.setup = setup
        return await withTaskCancellationHandler {
            let error = await setup.value
            guard session === value, !value.stopping else { return .notExecuted }
            if let error {
                issue = "原本を再生できません。媒体と保存記録を確認してください。"
                await stop(value, finalPhase: .failed)
                return value.acquireUnknown ? .unknown : .failed(error)
            }
            return await withCheckedContinuation { continuation in
                value.started = continuation
                value.monitor = Task { @MainActor in
                    let deadline = ContinuousClock.now.advanced(by: .seconds(15))
                    while session === value, !value.stopping {
                        await observe(value, startupDeadline: deadline)
                        if Task.isCancelled { break }
                        // Internal stop observation interval, not an accepted device latency/load target.
                        try? await Task.sleep(for: .milliseconds(50))
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in await self.stopOriginal(value.id) }
        }
    }

    private func prepare(_ value: Session) async -> BackendFailure? {
        if value.source == nil {
            switch await access.acquirePlayback(value.original, operation: value.operation,
                                                leaseID: .init(rawValue: UUID().uuidString)) {
            case .succeeded(let source): value.source = source
            case .unknown, .inProgress: value.acquireUnknown = true; return .inaccessible
            case .failed(let failure): return failure
            case .notExecuted: return .inaccessible
            }
        }
        guard let source = value.source, !value.stopping, !Task.isCancelled else { return .inaccessible }
        switch await access.attachReader(source.lease, id: .init(rawValue: UUID().uuidString)) {
        case .succeeded(let attachment): value.attachment = attachment
        default: return .inaccessible
        }
        guard let attachment = value.attachment, !value.stopping, !Task.isCancelled else { return .inaccessible }
        guard let url = URL(string: "fr-original://local/\(UUID().uuidString).mov") else { return .inaccessible }
        let access = self.access, beforeRead = self.beforeRead
        let loader = OriginalResourceLoader(resourceURL: url, byteCount: source.lease.original.content.byteCount) { offset, count in
            await beforeRead?()
            return try await access.readBytes(attachment, offset: offset, maximumLength: count)
        }
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetReferenceRestrictionsKey: AVAssetReferenceRestrictions.forbidAll.rawValue])
        value.loader = loader; value.asset = asset
        asset.resourceLoader.setDelegate(loader, queue: .main)
        let item = AVPlayerItem(asset: asset)
        value.item = item
        value.jumpObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.timeJumpedNotification,
            object: item, queue: .main) { [weak value] _ in
                // The SDK delivers this observer on the main queue. A seek/jump
                // invalidates the consecutive observations used as progress evidence.
                MainActor.assumeIsolated {
                    value?.previousPosition = nil
                    value?.previousWasPlaying = false
                }
            }
        if observesDecodedFrames {
            let output = AVPlayerItemVideoOutput(pixelBufferAttributes:
                CVPixelBufferAttributes(pixelFormatTypes: [.init(rawValue: kCVPixelFormatType_32BGRA)]))
            item.add(output); value.videoOutput = output
        }
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = false
        value.player = player
        self.player = player
        do {
            let audio = try await asset.loadTracks(withMediaType: .audio)
            guard !value.stopping, !Task.isCancelled else { return .inaccessible }
            audioTrackCount = audio.count
            player.play()
            return nil
        } catch { return .inaccessible }
    }

    private func observe(_ value: Session, startupDeadline: ContinuousClock.Instant) async {
        guard let source = value.source else { return }
        let stopRequested = await access.isReaderStopRequested(source.lease)
        guard session === value, !value.stopping else { return }
        if stopRequested { await stop(value, finalPhase: .stopped); return }
        guard let player = value.player, let item = value.item else { return }
        if item.status == .failed {
            issue = "原本の再生に失敗しました。原本の状態を確認してください。"
            await stop(value, finalPhase: .failed); return
        }
        let time = player.currentTime()
        let seconds = time.seconds
        if seconds.isFinite, seconds >= 0 {
            elapsedSeconds = seconds
            let isPlaying = player.rate > 0 && player.timeControlStatus == .playing
            if let previous = value.previousPosition, seconds > previous,
               value.previousWasPlaying, isPlaying {
                value.hasAdvanced = true
                if let output = value.videoOutput, output.hasNewPixelBuffer(forItemTime: time),
                   output.pixelBufferAndDisplayTime(forItemTime: time).pixelBuffer != nil {
                    decodedFrameCount += 1
                }
                value.started?.resume(returning: .succeeded(.init(source: source, session: value.id, elapsedSeconds: seconds)))
                value.started = nil
            }
            value.previousPosition = seconds
            value.previousWasPlaying = isPlaying
            if player.timeControlStatus == .paused { phase = .paused }
            else { phase = value.hasAdvanced && isPlaying ? .playing : .preparing }
        }
        let duration = item.duration.seconds
        if duration.isFinite, duration > 0, seconds >= duration {
            await stop(value, finalPhase: .ended)
        } else if value.started != nil, ContinuousClock.now >= startupDeadline {
            issue = "再生の進行を確認できませんでした。原本の状態を確認してから再試行してください。"
            await stop(value, finalPhase: .failed)
        }
    }

    @MainActor func stopOriginal(_ id: PlaybackSessionID) async {
        guard let value = session, value.id == id else { return }
        await stop(value, finalPhase: .stopped)
    }

    private func stop(_ value: Session, finalPhase: OriginalPlayerPhase) async {
        if let task = value.teardown { await task.value; return }
        guard session === value else { return }
        value.stopping = true
        phase = .stopping
        closeSDK(value)
        value.setup?.cancel()
        value.monitor?.cancel()
        // Teardown is separate from the monitor/setup tasks. Never join the caller monitor.
        let task = Task { @MainActor in
            _ = await value.setup?.value
            closeSDK(value)
            if let source = value.source { await access.requestReaderStop(source.lease) }
            await value.loader?.drain()
            maximumReadLength = value.loader?.maximumReadLength ?? 0
            deliveredBytes = value.loader?.deliveredBytes ?? 0
            if let attachment = value.attachment {
                guard case .succeeded = await access.readerDidFinish(attachment) else {
                    finishUncertain(value); return
                }
                value.attachment = nil
            }
            if let source = value.source {
                lastRelease = await access.releaseRead(source.lease)
                guard case .succeeded = lastRelease else { finishUncertain(value); return }
            } else if value.acquireUnknown {
                finishUncertain(value); return
            }
            value.started?.resume(returning: finalPhase == .failed ? .failed(.inaccessible) : .notExecuted)
            value.started = nil
            value.item = nil; value.asset = nil; value.loader = nil; value.player = nil
            player = nil; session = nil; phase = finalPhase
        }
        value.teardown = task
        await task.value
    }

    private func closeSDK(_ value: Session) {
        value.loader?.closeAdmission()
        value.player?.pause()
        value.player?.cancelPendingPrerolls()
        value.item?.cancelPendingSeeks()
        value.player?.replaceCurrentItem(with: nil)
        value.asset?.cancelLoading()
        if let observer = value.jumpObserver {
            NotificationCenter.default.removeObserver(observer)
            value.jumpObserver = nil
        }
        player = nil
    }

    private func finishUncertain(_ value: Session) {
        phase = .releaseNeedsReconciliation
        issue = "原本の読み取り終了を照合できません。再生を停止し、管理記録を保持しています。"
        value.started?.resume(returning: .unknown)
        value.started = nil
    }

    @MainActor private final class Session {
        let id: PlaybackSessionID
        let original: OriginalContent
        let operation: MediaOperationID
        var source: OriginalPlaybackSource?
        var attachment: OriginalReaderAttachment?
        var loader: OriginalResourceLoader?
        var asset: AVURLAsset?
        var item: AVPlayerItem?
        var player: AVPlayer?
        var videoOutput: AVPlayerItemVideoOutput?
        var jumpObserver: NSObjectProtocol?
        var previousPosition: Double?
        var previousWasPlaying = false
        var hasAdvanced = false
        var stopping = false
        var acquireUnknown = false
        var setup: Task<BackendFailure?, Never>?
        var monitor: Task<Void, Never>?
        var teardown: Task<Void, Never>?
        var started: CheckedContinuation<BackendOutcome<OriginalPlaybackProgress>, Never>?
        init(id: PlaybackSessionID, original: OriginalContent, operation: MediaOperationID) {
            self.id = id; self.original = original; self.operation = operation
        }
    }
}
