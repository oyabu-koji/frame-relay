import AVFoundation
import CoreVideo
import Foundation
import Observation

nonisolated struct RenditionPlaybackInput: Sendable {
    let reader: any RenditionByteReadingPort
    let contentType: String
}

nonisolated enum RenditionPlayerPhase: Equatable, Sendable {
    case idle, preparing, playing, stopping, stopped, ended, failed, releaseNeedsReconciliation
}

/// The remote factory is bound to a committed distribution producer and the
/// current common gate. Composition/wire integration is deliberately separate.
@MainActor @Observable final class AVRenditionPlayback: PlaybackPort {
    typealias RemoteInput = @Sendable (RetrieveMediaCommand) async throws -> RenditionPlaybackInput
    private let remoteInput: RemoteInput
    private let temporary: ManagedTemporaryMedia
    private let leases: RenditionReadLeases
    private weak var scope: RenditionMediaScope?
    private var permit: RenditionScopePermit?
    private var ownerClosed = false
    private var startedSessions = 0
    private var completedSessions = 0
    private var ownerTerminal: RenditionReadTerminal?
    private var session: Session?
    private var usedSessions: Set<PlaybackSessionID> = []
    private(set) var player: AVPlayer?
    private(set) var phase: RenditionPlayerPhase = .idle
    private(set) var elapsedSeconds: Double = 0
    private(set) var decodedFrames = 0
    private(set) var audioTracks = 0
    private(set) var deliveredBytes: UInt64 = 0
    private(set) var lastTerminal: RenditionReadTerminal?
    private(set) var sdkDetached = false

    private init(leases: RenditionReadLeases, temporary: ManagedTemporaryMedia, scope: RenditionMediaScope,
                 remoteInput: @escaping RemoteInput) {
        self.leases = leases; self.temporary = temporary; self.remoteInput = remoteInput; self.scope = scope
    }
    static func open(leases: RenditionReadLeases, temporary: ManagedTemporaryMedia, scope: RenditionMediaScope,
                     remoteInput: @escaping RemoteInput) async throws -> AVRenditionPlayback {
        let value = AVRenditionPlayback(leases: leases, temporary: temporary, scope: scope, remoteInput: remoteInput)
        value.permit = try await scope.register(owner: .renditionPlayer) { try await value.closeOwner() }
        return value
    }

    @MainActor func play(_ command: PlaybackCommand) async -> BackendOutcome<PlaybackToken> {
        do { guard let permit else { throw BackendContractError.wrongStage }; try await permit.check() }
        catch { return .failed(.rejected) }
        guard !ownerClosed, session == nil, usedSessions.insert(command.session).inserted else { return .failed(.rejected) }
        startedSessions += 1
        let value = Session(command: command)
        session = value; phase = .preparing; elapsedSeconds = 0; decodedFrames = 0
        audioTracks = 0; deliveredBytes = 0; lastTerminal = nil; sdkDetached = false
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                value.started = continuation
                value.setup = Task { @MainActor in
                    do { try await prepare(value) }
                    catch { value.setupFailed = true }
                }
                value.monitor = Task { @MainActor in
                    await value.setup?.value
                    if value.stopping { return }
                    if value.setupFailed { await stop(value, phase: .failed); return }
                    while !Task.isCancelled, session === value, !value.stopping {
                        await observe(value)
                        do { try await Task.sleep(for: .milliseconds(40)) } catch { return }
                    }
                }
            }
        } onCancel: { Task { @MainActor in await self.end(command.session) } }
    }

    private func prepare(_ value: Session) async throws {
        let distribution: DistributionReceipt
        switch value.command.source {
        case .remote(let command):
            guard command.identitiesMatch else { throw BackendContractError.identityMismatch }
            distribution = command.distribution
        case .local(let receipt, let proof):
            guard proof.isCommitted, proof.rendition == receipt.rendition, !receipt.isReleased,
                  receipt.hasCompleteCoverage, receipt.verifiedContent == receipt.rendition.deliveryContent else {
                throw BackendContractError.ineligibleOriginal
            }
            distribution = proof
        }
        value.distribution = distribution
        value.lease = try await leases.acquire(rendition: distribution.rendition, registration: distribution.registration,
            operation: .init(rawValue: UUID().uuidString), context: .playback(value.command.session))
        try await checkCurrent(value)
        try Task.checkCancellation()
        guard !value.stopping else { throw CancellationError() }
        let input: RenditionPlaybackInput
        switch value.command.source {
        case .remote(let command): input = try await remoteInput(command)
        case .local(let receipt, _):
            guard case .succeeded(let usage) = await temporary.acquireUsage(receipt.id, purpose: .playback,
                usageID: .init(rawValue: UUID().uuidString)) else { throw BackendContractError.ineligibleOriginal }
            guard let scope else { throw BackendContractError.unavailable }
            let localReader = try await TemporaryRenditionReader.open(media: temporary, usage: usage, scope: scope)
            value.reader = localReader
            let state = try await temporary.stateFor(receipt.id)
            input = .init(reader: localReader, contentType: state.contentType)
        }
        value.reader = input.reader
        try Task.checkCancellation()
        guard !value.stopping else { throw CancellationError() }
        let suffix = input.contentType == "video/quicktime" ? "mov" : "mp4"
        guard let url = URL(string: "fr-rendition://" + UUID().uuidString + "/media." + suffix) else {
            throw BackendContractError.invalidValue
        }
        let loader = try RenditionResourceLoader(resourceURL: url,
            byteCount: distribution.rendition.deliveryContent.byteCount, mimeType: input.contentType, reader: input.reader)
        value.loader = loader
        let asset = AVURLAsset(url: url, options: [AVURLAssetReferenceRestrictionsKey: AVAssetReferenceRestrictions.forbidAll.rawValue])
        value.asset = asset
        asset.resourceLoader.setDelegate(loader, queue: .main)
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 1
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes:
            CVPixelBufferAttributes(pixelFormatTypes: [.init(rawValue: kCVPixelFormatType_32BGRA)]))
        item.add(output)
        let player = AVPlayer(playerItem: item)
        value.item = item; value.player = player; value.output = output
        self.player = player
        audioTracks = try await asset.loadTracks(withMediaType: .audio).count
        try Task.checkCancellation()
        guard !value.stopping else { throw CancellationError() }
        player.play()
    }

    private func checkCurrent(_ value: Session) async throws {
        guard let permit else { throw BackendContractError.wrongStage }
        try await permit.check()
        guard let lease = value.lease, let distribution = value.distribution else { throw BackendContractError.wrongStage }
        try await leases.check(lease)
        guard case .loaded(let snapshot) = await leases.mediaStore.load(),
              snapshot.confirmationStates.contains(where: {
                  $0.registration == distribution.registration && $0.current == distribution.rendition
                    && $0.generation == value.command.invalidationGeneration
                    && !$0.invalidatedRenditions.contains(distribution.rendition.rendition)
              }) else { throw BackendContractError.staleGeneration }
    }

    private func observe(_ value: Session) async {
        do { try await checkCurrent(value) }
        catch { await stop(value, phase: .failed); return }
        guard session === value, !value.stopping, let player = value.player, let item = value.item else { return }
        if item.status == .failed { await stop(value, phase: .failed); return }
        let time = player.currentTime()
        let position = time.seconds
        let playing = player.rate > 0 && player.timeControlStatus == .playing
        if position.isFinite, position >= 0 {
            elapsedSeconds = position
            if playing, value.wasPlaying, let previous = value.previousPosition, position > previous {
                phase = .playing
                if let output = value.output, output.hasNewPixelBuffer(forItemTime: time),
                   output.pixelBufferAndDisplayTime(forItemTime: time).pixelBuffer != nil { decodedFrames += 1 }
                if let distribution = value.distribution {
                    do {
                        let token = try PlaybackToken(distribution: distribution, session: value.command.session,
                            invalidationGeneration: value.command.invalidationGeneration, observation: .played)
                        value.started?.resume(returning: .succeeded(token)); value.started = nil
                    } catch { await stop(value, phase: .failed); return }
                }
            }
            value.previousPosition = position; value.wasPlaying = playing
        }
        deliveredBytes = value.loader?.deliveredBytes ?? 0
        let duration = item.duration.seconds
        if duration.isFinite, duration > 0, position >= duration { await stop(value, phase: .ended) }
    }

    @MainActor func end(_ id: PlaybackSessionID) async {
        guard let value = session, value.command.session == id else { return }
        await stop(value, phase: .stopped)
    }

    private func stop(_ value: Session, phase finalPhase: RenditionPlayerPhase) async {
        if let teardown = value.teardown { await teardown.value; return }
        guard session === value else { return }
        value.stopping = true; phase = .stopping
        detach(value)
        value.setup?.cancel(); value.monitor?.cancel()
        let task = Task { @MainActor in
            await value.setup?.value
            detach(value)
            // Close the network/file owner while loader tasks unwind; both
            // underlying callbacks and the delegate tasks are joined.
            do {
                if let reader = value.reader { lastTerminal = try await reader.close() }
                await value.loader?.drain()
                deliveredBytes = value.loader?.deliveredBytes ?? 0
                guard value.loader?.pending ?? 0 == 0, sdkDetached else { throw BackendContractError.readersActive }
                if let lease = value.lease { try await leases.release(lease) }
                completedSessions += 1
                phase = finalPhase
            } catch { phase = .releaseNeedsReconciliation }
            value.started?.resume(returning: .failed(.inaccessible)); value.started = nil
            session = nil
        }
        value.teardown = task
        await task.value
    }

    private func closeOwner() async throws -> RenditionReadTerminal {
        if let ownerTerminal { return ownerTerminal }
        ownerClosed = true
        if let session { await stop(session, phase: .stopped) }
        guard startedSessions == completedSessions, player == nil,
              phase != .releaseNeedsReconciliation else { throw BackendContractError.readersActive }
        let value = RenditionReadTerminal(epoch: try await leases.currentEpoch(), started: startedSessions,
            completed: completedSessions, bytes: deliveredBytes, handlesClosed: true)
        ownerTerminal = value
        return value
    }

    private func detach(_ value: Session) {
        value.loader?.closeAdmission()
        value.player?.pause()
        if let output = value.output { value.item?.remove(output) }
        value.player?.replaceCurrentItem(with: nil)
        value.asset?.cancelLoading()
        value.asset?.resourceLoader.setDelegate(nil, queue: nil)
        sdkDetached = value.player?.currentItem == nil
        player = nil; value.player = nil; value.item = nil; value.asset = nil; value.output = nil
    }

    @MainActor private final class Session {
        let command: PlaybackCommand
        var distribution: DistributionReceipt?
        var lease: MediaReadLease?
        var reader: (any RenditionByteReadingPort)?
        var loader: RenditionResourceLoader?
        var asset: AVURLAsset?
        var item: AVPlayerItem?
        var output: AVPlayerItemVideoOutput?
        var player: AVPlayer?
        var stopping = false
        var setupFailed = false
        var previousPosition: Double?
        var wasPlaying = false
        var setup: Task<Void, Never>?
        var monitor: Task<Void, Never>?
        var teardown: Task<Void, Never>?
        var started: CheckedContinuation<BackendOutcome<PlaybackToken>, Never>?
        init(command: PlaybackCommand) { self.command = command }
    }
}
