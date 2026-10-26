import AVFoundation
import Foundation
import Observation
import OSLog

nonisolated enum OriginalPlayerPhase: Equatable, Sendable {
    case idle, preparing, playing, paused, stopping, ended, stopped, failed, releaseNeedsReconciliation
}

/// One original session. No remote URL, transport, rendition token, or confirmation writer.
@MainActor @Observable final class AVOriginalPlayback: OriginalPlaybackPort, OriginalPlaybackTerminationPort {
    private let access: ManagedOriginalAccess
    private let beforeRead: (@Sendable () async -> Void)?
    private let observesDecodedFrames: Bool
    @ObservationIgnored private let diagnostics: OriginalPlaybackDiagnostics?
    private var session: Session?
    private var usedSessions: Set<PlaybackSessionID> = []
    private var admissionClosed: Set<OriginalContent> = []
    private var removalSeals: [MediaOperationID: OriginalRemovalAdmissionSeal] = [:]
    private var removedOriginals: Set<OriginalContent> = []
    private var ownedSessions: [PlaybackSessionID: Session] = [:]
    private var terminalInventory: [OriginalPlaybackOwnerTerminal] = []
    private var createdOwners: [OriginalContent: Int] = [:]
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
         beforeRead: (@Sendable () async -> Void)? = nil,
         diagnostics: OriginalPlaybackDiagnostics? = nil) {
        self.access = access
        self.observesDecodedFrames = observesDecodedFrames
        self.beforeRead = beforeRead
        self.diagnostics = diagnostics ?? OriginalPlaybackDiagnostics.forCurrentProcess()
    }

    func open(_ original: OriginalContent, operation: MediaOperationID,
              session id: PlaybackSessionID) async -> BackendOutcome<OriginalPlaybackProgress> {
        guard session == nil, !usedSessions.contains(id), !admissionClosed.contains(original), !removedOriginals.contains(original),
              !removalSeals.values.contains(where: { $0.target.original == original }) else { return .notExecuted }
        return await start(Session(id: id, original: original, operation: operation))
    }

    /// The caller retains responsibility for a source rejected as a duplicate.
    @MainActor func playOriginal(_ source: OriginalPlaybackSource,
                      session id: PlaybackSessionID) async -> BackendOutcome<OriginalPlaybackProgress> {
        guard session == nil, !usedSessions.contains(id), !admissionClosed.contains(source.lease.original), !removedOriginals.contains(source.lease.original),
              !removalSeals.values.contains(where: { $0.target.original == source.lease.original }) else { return .notExecuted }
        let value = Session(id: id, original: source.lease.original, operation: source.lease.operation)
        value.source = source
        return await start(value)
    }

    private func start(_ value: Session) async -> BackendOutcome<OriginalPlaybackProgress> {
        session = value
        ownedSessions[value.id] = value
        createdOwners[value.original, default: 0] += 1
        diagnostics?.beginSession()
        record(.start, value)
        usedSessions.insert(value.id)
        phase = .preparing; issue = nil; elapsedSeconds = 0; audioTrackCount = 0; decodedFrameCount = 0
        maximumReadLength = 0; deliveredBytes = 0; lastRelease = .notExecuted
        let setup = Task { @MainActor in await prepare(value) }
        value.setup = setup
        return await withTaskCancellationHandler {
            let error = await setup.value
            guard session === value, !value.stopping else { return .notExecuted }
            if let error {
                record(.prepareFailed, value)
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
            record(.acquireBegin, value)
            defer { record(.acquireEnd, value) }
            switch await access.acquirePlayback(value.original, operation: value.operation,
                                                leaseID: .init(rawValue: UUID().uuidString)) {
            case .succeeded(let source): value.source = source
            case .unknown, .inProgress: value.acquireUnknown = true; return .inaccessible
            case .failed(let failure): return failure
            case .notExecuted: return .inaccessible
            }
        }
        guard let source = value.source, !value.stopping, !Task.isCancelled else { return .inaccessible }
        record(.attachBegin, value)
        switch await access.attachReader(source.lease, id: .init(rawValue: UUID().uuidString)) {
        case .succeeded(let attachment): value.attachment = attachment
        default: return .inaccessible
        }
        record(.attachEnd, value)
        guard let attachment = value.attachment, !value.stopping, !Task.isCancelled else { return .inaccessible }
        guard let url = URL(string: "fr-original://local/\(UUID().uuidString).mov") else { return .inaccessible }
        let access = self.access, beforeRead = self.beforeRead
        let loader = OriginalResourceLoader(resourceURL: url, byteCount: source.lease.original.content.byteCount,
                                            diagnostics: diagnostics) { offset, count in
            await beforeRead?()
            return try await access.readBytes(attachment, offset: offset, maximumLength: count)
        }
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetReferenceRestrictionsKey: AVAssetReferenceRestrictions.forbidAll.rawValue])
        value.loader = loader; value.asset = asset
        record(.loaderReady, value)
        asset.resourceLoader.setDelegate(loader, queue: .main)
        let item = AVPlayerItem(asset: asset)
        value.item = item
        value.jumpObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.timeJumpedNotification,
            object: item, queue: .main) { [weak value, weak self] _ in
                // The SDK delivers this observer on the main queue. A seek/jump
                // invalidates the consecutive observations used as progress evidence.
                MainActor.assumeIsolated {
                    if let value { self?.record(.jumped, value) }
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
        record(.playerPublished, value)
        do {
            record(.audioLoadBegin, value)
            let audio = try await asset.loadTracks(withMediaType: .audio)
            record(.audioLoadEnd, value)
            guard !value.stopping, !Task.isCancelled else { return .inaccessible }
            audioTrackCount = audio.count
            player.play()
            record(.playCalled, value)
            return nil
        } catch {
            record(.prepareFailed, value, error: error)
            return .inaccessible
        }
    }

    private func observe(_ value: Session, startupDeadline: ContinuousClock.Instant) async {
        guard let source = value.source else { return }
        let beforeAwait = ProcessInfo.processInfo.systemUptime
        let interval = value.previousMonitorUptime.map { (beforeAwait - $0) * 1000 }
        value.previousMonitorUptime = beforeAwait
        let observesAwait = diagnostics != nil && beforeAwait - value.lastMonitorDiagnostic >= 0.25
        if observesAwait { record(.monitorAwaitBegin, value, monitorIntervalMS: interval) }
        let stopRequested = await access.isReaderStopRequested(source.lease)
        let afterAwait = ProcessInfo.processInfo.systemUptime
        let awaitMS = (afterAwait - beforeAwait) * 1000
        if diagnostics != nil, observesAwait || awaitMS >= 100 {
            record(.monitor, value, monitorIntervalMS: interval, awaitMS: awaitMS)
            value.lastMonitorDiagnostic = afterAwait
        }
        guard session === value, !value.stopping else { return }
        if stopRequested { record(.readerStopObserved, value); await stop(value, finalPhase: .stopped); return }
        guard let player = value.player, let item = value.item else { return }
        if item.status == .failed {
            record(.itemFailed, value)
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
            record(.durationEnded, value)
            await stop(value, finalPhase: .ended)
        } else if value.started != nil, ContinuousClock.now >= startupDeadline {
            record(.startupTimeout, value)
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
        record(.stopBegin, value)
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
            record(.loaderDrained, value)
            maximumReadLength = value.loader?.maximumReadLength ?? 0
            deliveredBytes = value.loader?.deliveredBytes ?? 0
            if let attachment = value.attachment {
                guard case .succeeded = await access.readerDidFinish(attachment) else {
                    finishUncertain(value); return
                }
                value.attachment = nil
            }
            if let source = value.source {
                value.release = await access.releaseRead(source.lease)
                lastRelease = value.release
                guard case .succeeded = value.release else { finishUncertain(value); return }
            } else if value.acquireUnknown {
                finishUncertain(value); return
            }
            record(.releaseSucceeded, value)
            value.started?.resume(returning: finalPhase == .failed ? .failed(.inaccessible) : .notExecuted)
            value.started = nil
            value.item = nil; value.asset = nil; value.loader = nil; value.player = nil
            player = nil; session = nil; phase = finalPhase
        }
        value.teardown = task
        // A separate observer may join the caller monitor after this teardown
        // returns. The monitor never joins itself through stop().
        value.terminalObserver = Task { @MainActor in
            await task.value
            _ = await value.setup?.value
            await value.monitor?.value
            observeTerminal(value)
        }
        await task.value
    }

    @MainActor func stopAndObserve(original: OriginalContent) async throws -> OriginalPlaybackTermination {
        admissionClosed.insert(original)
        return try await stopOwnersAndObserve(original: original)
    }

    @MainActor func stopForRemoval(_ seal: OriginalRemovalAdmissionSeal) async throws -> OriginalPlaybackTermination {
        if let existing = removalSeals[seal.target.operation], existing != seal { throw BackendContractError.identityMismatch }
        removalSeals[seal.target.operation] = seal
        return try await stopOwnersAndObserve(original: seal.target.original)
    }

    private func stopOwnersAndObserve(original: OriginalContent) async throws -> OriginalPlaybackTermination {
        let retained = ownedSessions.values.filter { $0.original == original }
        for value in retained { await stop(value, finalPhase: .stopped) }
        for value in retained {
            _ = await value.setup?.value
            await value.monitor?.value
            await value.terminalObserver?.value
        }
        let terminals = terminalInventory.filter { $0.original == original }
        guard !ownedSessions.values.contains(where: { $0.original == original }),
              terminals.count == createdOwners[original, default: 0],
              terminals.allSatisfy({ $0.tasksJoined && $0.sdkDetached && ($0.source == nil || $0.release?.lease == $0.source?.lease) }) else {
            throw BackendContractError.unknownResult
        }
        return .init(original: original, admissionClosed: true, createdOwners: terminals.count, terminals: terminals)
    }

    @MainActor func resumeAfterInvalidation(_ acknowledgement: InvalidationAcknowledgement) throws {
        guard acknowledgement.isCommitted,
              !ownedSessions.values.contains(where: { $0.original == acknowledgement.record.rendition.original }) else {
            throw BackendContractError.readersActive
        }
        admissionClosed.remove(acknowledgement.record.rendition.original)
    }

    @MainActor func resumeAfterRemoval(_ release: OriginalRemovalAdmissionRelease) async throws {
        let original = release.seal.target.original
        let terminals = terminalInventory.filter { $0.original == original }
        guard removalSeals[release.seal.target.operation] == release.seal,
              !ownedSessions.values.contains(where: { $0.original == original }),
              terminals.count == createdOwners[original, default: 0],
              terminals.allSatisfy({ $0.tasksJoined && $0.sdkDetached && ($0.source == nil || $0.release?.lease == $0.source?.lease) }) else {
            throw BackendContractError.readersActive
        }
        // The producer/registry has checked the exact durable row and common
        // writer epoch. Newly admitted rendition owners must not strand this
        // still-sealed SDK owner after that common boundary has reopened.
        if release.resolution == .removed { removedOriginals.insert(original) }
        removalSeals.removeValue(forKey: release.seal.target.operation)
        // The invalidation owner alone can remove admissionClosed.
    }

    private func observeTerminal(_ value: Session) {
        guard value.stopping, !value.acquireUnknown, value.attachment == nil,
              value.loader == nil, value.item == nil, value.asset == nil, value.player == nil else { return }
        let release: ReadReleaseReceipt?
        if let source = value.source {
            guard case .succeeded(let observed) = value.release, observed.lease == source.lease else { return }
            release = observed
        } else { release = nil }
        terminalInventory.append(.init(session: value.id, original: value.original, source: value.source, release: release,
            tasksJoined: true, sdkDetached: true))
        ownedSessions.removeValue(forKey: value.id)
        value.setup = nil; value.monitor = nil; value.teardown = nil; value.terminalObserver = nil
    }

    private func closeSDK(_ value: Session) {
        record(.beforeSDKClose, value)
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
        record(.afterSDKClose, value)
    }

    private func finishUncertain(_ value: Session) {
        record(.releaseUncertain, value)
        phase = .releaseNeedsReconciliation
        issue = "原本の読み取り終了を照合できません。再生を停止し、管理記録を保持しています。"
        value.started?.resume(returning: .unknown)
        value.started = nil
    }

    /// Presentation events use the same observer and monotonic clock as SDK/loader events.
    func recordPresentation(_ kind: OriginalPlaybackDiagnosticEvent.Kind) {
        record(kind, session)
    }

    private func record(_ kind: OriginalPlaybackDiagnosticEvent.Kind, _ value: Session?,
                        monitorIntervalMS: Double? = nil, awaitMS: Double? = nil, error: (any Error)? = nil) {
        guard let diagnostics else { return }
        let sdk: OriginalPlaybackSDKDiagnostic?
        if let player = value?.player {
            let waiting: String
            switch player.reasonForWaitingToPlay {
            case .some(.toMinimizeStalls): waiting = "minimizeStalls"
            case .some(.evaluatingBufferingRate): waiting = "bufferingRate"
            case .some(.noItemToPlay): waiting = "noItem"
            case .none: waiting = "none"
            default: waiting = "other"
            }
            let item = value?.item
            let seconds = player.currentTime().seconds
            sdk = .init(rate: player.rate, timeControl: player.timeControlStatus.rawValue,
                waiting: waiting, currentItemPresent: player.currentItem != nil, itemStatus: item?.status.rawValue,
                currentSeconds: seconds.isFinite ? seconds : nil,
                itemError: item?.error.map(OriginalPlaybackNumericError.init))
        } else { sdk = nil }
        diagnostics.record(kind, sdk: sdk, loader: value?.loader?.diagnosticSnapshot,
                           monitorIntervalMS: monitorIntervalMS, awaitMS: awaitMS, error: error)
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
        var previousMonitorUptime: Double?
        var lastMonitorDiagnostic: Double = 0
        var previousPosition: Double?
        var previousWasPlaying = false
        var hasAdvanced = false
        var stopping = false
        var acquireUnknown = false
        var setup: Task<BackendFailure?, Never>?
        var monitor: Task<Void, Never>?
        var teardown: Task<Void, Never>?
        var terminalObserver: Task<Void, Never>?
        var release: BackendOutcome<ReadReleaseReceipt> = .notExecuted
        var started: CheckedContinuation<BackendOutcome<OriginalPlaybackProgress>, Never>?
        init(id: PlaybackSessionID, original: OriginalContent, operation: MediaOperationID) {
            self.id = id; self.original = original; self.operation = operation
        }
    }
}

/// Anonymous, bounded technical observation. No media identity, URL, path,
/// credential, NSError text/userInfo, or independent persistent log is retained.
nonisolated struct OriginalPlaybackDiagnosticEvent: Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case modelOpen, modelStartTask, modelStop, modelClose
        case viewAppeared, viewDisappeared, videoViewAppeared, videoViewDisappeared
        case start, acquireBegin, acquireEnd, attachBegin, attachEnd, loaderReady
        case playerPublished, audioLoadBegin, audioLoadEnd, playCalled, prepareFailed
        case monitorAwaitBegin, monitor, jumped, readerStopObserved, itemFailed, startupTimeout, durationEnded
        case stopBegin, beforeSDKClose, afterSDKClose, loaderDrained, releaseSucceeded, releaseUncertain
        case loaderRequest, loaderRejected, loaderReadBegin, loaderReadEnd, loaderReadFailed
        case loaderCancelled, loaderFinished, loaderTaskEnded, loaderClosed
    }
    let sequence: Int
    let uptime: Double
    let session: Int
    let kind: Kind
    let sdk: OriginalPlaybackSDKDiagnostic?
    let loader: OriginalLoaderDiagnostic?
    let monitorIntervalMS: Double?
    let awaitMS: Double?
    let error: OriginalPlaybackNumericError?
}

nonisolated struct OriginalPlaybackNumericError: Codable, Sendable {
    let domain: String
    let code: Int
    init(_ error: any Error) {
        let value = error as NSError
        switch value.domain {
        case AVFoundationErrorDomain: domain = "avfoundation"
        case NSOSStatusErrorDomain: domain = "osstatus"
        case NSURLErrorDomain: domain = "url"
        case NSCocoaErrorDomain: domain = "cocoa"
        default: domain = "other"
        }
        code = value.code
    }
}

nonisolated struct OriginalPlaybackSDKDiagnostic: Codable, Sendable {
    let rate: Float
    let timeControl: Int
    let waiting: String
    let currentItemPresent: Bool
    let itemStatus: Int?
    let currentSeconds: Double?
    let itemError: OriginalPlaybackNumericError?
}

nonisolated struct OriginalPlaybackTerminalDiagnostic: Codable, Sendable {
    let kind: OriginalPlaybackDiagnosticEvent.Kind
    let uptime: Double
    let session: Int
    let beforeSDKClose: OriginalPlaybackSDKDiagnostic?
    let finalSDK: OriginalPlaybackSDKDiagnostic?
    let loader: OriginalLoaderDiagnostic?
    let totalEvents: Int
    let droppedEvents: Int
    let suppressedLogEvents: Int
}

nonisolated struct OriginalPlaybackDiagnosticReport: Codable, Sendable {
    let capacity: Int
    let totalEvents: Int
    let droppedEvents: Int
    let emittedLogEvents: Int
    let suppressedLogEvents: Int
    let terminal: OriginalPlaybackTerminalDiagnostic?
    let events: [OriginalPlaybackDiagnosticEvent]
}

@MainActor final class OriginalPlaybackDiagnostics {
    static let capacity = 512
    private static let logger = Logger(subsystem: "jp.oyabu.FrameRelay.playback", category: "original-diagnostics")
    private let run = UUID().uuidString.lowercased()
    private(set) var events: [OriginalPlaybackDiagnosticEvent] = []
    private(set) var droppedEvents = 0
    private(set) var session = 0
    private var sequence = 0
    private var emitted = 0
    private var emittedByCategory: [LogCategory: Int] = [:]
    private var suppressedLogEvents = 0
    private var beforeSDKClose: OriginalPlaybackSDKDiagnostic?
    private(set) var terminal: OriginalPlaybackTerminalDiagnostic?
    private let encoder = JSONEncoder()

    static func forCurrentProcess() -> OriginalPlaybackDiagnostics? {
        #if DEBUG && targetEnvironment(simulator)
        guard ProcessInfo.processInfo.environment["FR_ORIGINAL_PLAYBACK_DIAGNOSTICS"] == "1" else { return nil }
        return OriginalPlaybackDiagnostics()
        #else
        return nil
        #endif
    }

    var report: OriginalPlaybackDiagnosticReport {
        .init(capacity: Self.capacity, totalEvents: sequence, droppedEvents: droppedEvents,
              emittedLogEvents: emitted, suppressedLogEvents: suppressedLogEvents,
              terminal: terminal, events: events)
    }

    func beginSession() {
        session += 1
        beforeSDKClose = nil
        terminal = nil
    }

    func record(_ kind: OriginalPlaybackDiagnosticEvent.Kind, sdk: OriginalPlaybackSDKDiagnostic? = nil,
                loader: OriginalLoaderDiagnostic? = nil, monitorIntervalMS: Double? = nil,
                awaitMS: Double? = nil, error: (any Error)? = nil) {
        sequence += 1
        let event = OriginalPlaybackDiagnosticEvent(sequence: sequence, uptime: ProcessInfo.processInfo.systemUptime,
            session: session, kind: kind, sdk: sdk, loader: loader,
            monitorIntervalMS: monitorIntervalMS, awaitMS: awaitMS, error: error.map(OriginalPlaybackNumericError.init))
        // Preserve the first setup observations and the latest terminal observations.
        if events.count == Self.capacity { events.remove(at: 128); droppedEvents += 1 }
        events.append(event)
        if kind == .beforeSDKClose, beforeSDKClose == nil || sdk?.currentItemPresent == true {
            beforeSDKClose = sdk
        }
        if kind == .releaseSucceeded || kind == .releaseUncertain {
            // One compact terminal summary retains the immediate pre-close SDK
            // state even after high-frequency loader samples are dropped.
            let summary = OriginalPlaybackTerminalDiagnostic(kind: kind, uptime: event.uptime, session: session,
                beforeSDKClose: beforeSDKClose, finalSDK: sdk, loader: loader,
                totalEvents: sequence, droppedEvents: droppedEvents, suppressedLogEvents: suppressedLogEvents)
            terminal = summary
            guard canEmit(.terminal), let data = try? encoder.encode(summary),
                  let line = String(data: data, encoding: .utf8) else { suppressedLogEvents += 1; return }
            didEmit(.terminal)
            Self.logger.notice("run=\(self.run, privacy: .public) terminal=\(line, privacy: .public)")
            return
        }
        // Loader activity during audio-track loading must not consume the
        // later monitor observations or presentation/terminal event budgets.
        let category: LogCategory
        switch kind {
        case .monitorAwaitBegin, .monitor: category = .monitor
        case .jumped, .loaderRequest, .loaderRejected,
             .loaderReadBegin, .loaderReadEnd, .loaderReadFailed, .loaderCancelled,
             .loaderFinished, .loaderTaskEnded, .loaderClosed: category = .loader
        default: category = .lifecycle
        }
        guard canEmit(category), let data = try? encoder.encode(event),
              let line = String(data: data, encoding: .utf8) else { suppressedLogEvents += 1; return }
        didEmit(category)
        Self.logger.notice("run=\(self.run, privacy: .public) event=\(line, privacy: .public)")
    }

    private enum LogCategory: Hashable {
        case loader, monitor, lifecycle, terminal
        var limit: Int {
            switch self {
            case .loader, .monitor: 192
            case .lifecycle: 96
            case .terminal: 32
            }
        }
    }

    private func canEmit(_ category: LogCategory) -> Bool {
        emitted < Self.capacity && emittedByCategory[category, default: 0] < category.limit
    }

    private func didEmit(_ category: LogCategory) {
        emittedByCategory[category, default: 0] += 1
        emitted += 1
    }
}
