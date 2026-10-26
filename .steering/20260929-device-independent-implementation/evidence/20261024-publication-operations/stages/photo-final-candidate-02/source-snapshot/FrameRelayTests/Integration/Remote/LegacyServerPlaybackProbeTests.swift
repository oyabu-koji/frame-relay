import AVFoundation
import Foundation
import Testing
@testable import FrameRelay

/// Opt-in S20 method probe against a separately authorized, isolated listener.
/// No product store, registration, distribution, or confirmation is constructed.
/// Xcode forwards TEST_RUNNER_FR_* as FR_* to the Simulator test host.
@Suite(.serialized) @MainActor struct LegacyServerPlaybackProbeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_LEGACY_PLAYBACK_PROBE"] == "1"))
    func actualHTTPRejectsMissingTokenAndReturnsTheFixedShortRange() async throws {
        let configuration = try LegacyProbeConfiguration()
        let evidence = try LegacyProbeEvidence(configuration: configuration, name: "http")
        let client = LegacyProbeRangeClient(configuration: configuration)
        do {
            try evidence.record("begin", client: client)
            _ = try await client.read(offset: 0, length: 64, authenticated: false)
            try #require(client.snapshot.observations.first?.status == 401)
            try #require(client.snapshot.observations.first?.terminal == true)
            try evidence.record("unauthenticated-terminal", client: client)

            let prefix = try await client.read(offset: 0, length: 64)
            try #require(legacyProbeSHA256(prefix) == configuration.prefixSHA256)
            let middle = try await client.read(offset: 17, length: 31)
            try #require(middle == prefix.subdata(in: 17..<48))
            try #require(client.snapshot.observations.filter(\.identityHeadersMatched).count == 2)
            try #require(client.snapshot.refusedRedirects == 0)
            try evidence.record("fixed-range-matched", client: client)

            let terminated = await client.stopAndObserveTerminal()
            try evidence.record("network-stop", client: client, values: ["terminal": String(terminated)])
            try #require(terminated)
            try #require(client.snapshot.invalidationError == nil)
            let stopped = client.snapshot
            try #require(await legacyProbeRemainsUnchanged(client, snapshot: stopped))
            try evidence.record("post-stop-stable", client: client,
                                values: ["observationWindowSeconds": "0.5"])
        } catch {
            try? evidence.record("failure-before-stop", client: client,
                                 values: ["error": legacyProbeErrorCode(error)])
            let terminated = await client.stopAndObserveTerminal()
            try? evidence.record("failure-after-stop", client: client,
                                 values: ["terminal": String(terminated)])
            throw error
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_LEGACY_PLAYBACK_PROBE"] == "1"))
    func actualPlayerAdvancesThenSDKLoaderAndNetworkReachTerminal() async throws {
        let configuration = try LegacyProbeConfiguration()
        let evidence = try LegacyProbeEvidence(configuration: configuration, name: "player")
        let client = LegacyProbeRangeClient(configuration: configuration)
        let playback = try LegacyProbePlayer(configuration: configuration, client: client)
        do {
            try evidence.record("begin", client: client, values: playback.diagnostics)
            try #require(playback.asset.url.scheme == "fr-s20-probe")
            try #require(playback.asset.referenceRestrictions == .forbidAll)
            playback.start()
            try await playback.waitForActualProgress()
            try evidence.record("actual-progress", client: client, values: playback.diagnostics)
            try #require(playback.prepared)
            try #require(playback.audioTrackCount == 1)
            try #require(playback.videoTrackCount == 1)
            try #require(playback.decodedFrames > 0)
            try #require(playback.loader.deliveredBytes > 0)
            try #require(playback.loader.maximumReadLength <= 65_536)
            // The SDK may already have another range awaiting response headers.
            // Judge bytes actually received, without misclassifying that pending request.
            let receivedRanges = client.snapshot.observations.filter { $0.bodyBytes > 0 }
            try #require(!receivedRanges.isEmpty)
            try #require(receivedRanges.allSatisfy { $0.identityHeadersMatched })
            try #require(client.snapshot.refusedRedirects == 0)

            let stopped = await playback.stop()
            try evidence.record("stop", client: client, values: playback.diagnostics)
            try #require(stopped)
            try #require(playback.player.currentItem == nil)
            try #require(playback.player.rate == 0)
            try #require(playback.loader.isClosed && playback.loader.pendingCount == 0)
            try #require(client.snapshot.invalidationCallback && client.snapshot.activeTasks == 0)
            try #require(client.snapshot.invalidationError == nil)
            let network = client.snapshot
            let deliveredBytes = playback.loader.deliveredBytes
            try #require(await legacyProbeRemainsUnchanged(client, snapshot: network))
            try #require(playback.loader.deliveredBytes == deliveredBytes)
            try #require(playback.loader.pendingCount == 0)
            try #require(playback.player.currentItem == nil && playback.player.rate == 0)
            try evidence.record("post-stop-stable", client: client, values: playback.diagnostics.merging(
                ["observationWindowSeconds": "0.5"], uniquingKeysWith: { _, new in new }))
        } catch {
            // Capture the SDK state before stop removes its current item.
            try? evidence.record("failure-before-stop", client: client, values: playback.diagnostics.merging(
                ["error": legacyProbeErrorCode(error)], uniquingKeysWith: { _, new in new }))
            _ = await playback.stop()
            try? evidence.record("failure-after-stop", client: client, values: playback.diagnostics)
            throw error
        }
    }
}

@MainActor private func legacyProbeRemainsUnchanged(
    _ client: LegacyProbeRangeClient, snapshot: LegacyProbeNetworkSnapshot
) async -> Bool {
    // A continuous observation window, not an immediately satisfied predicate.
    // This duration is a probe value, not an accepted product stop guarantee.
    let deadline = ContinuousClock.now.advanced(by: .milliseconds(500))
    while ContinuousClock.now < deadline {
        guard client.snapshot == snapshot, snapshot.activeTasks == 0,
              snapshot.invalidationCallback else { return false }
        do { try await Task.sleep(for: .milliseconds(20)) } catch { return false }
    }
    return client.snapshot == snapshot
}

@MainActor private final class LegacyProbePlayer {
    let asset: AVURLAsset
    let item: AVPlayerItem
    let player: AVPlayer
    let loader: OriginalResourceLoader
    private let client: LegacyProbeRangeClient
    private let output: AVPlayerItemVideoOutput
    private var preparation: Task<Void, Never>?
    private var teardown: Task<Bool, Never>?
    private var jumpObserver: NSObjectProtocol?
    private var previousPosition: Double?
    private var previousWasPlaying = false
    private var increasingObservations = 0
    private var preparationFinished = false
    private var preparationError: String?
    private var durationSeconds: Double?
    private var observedPosition: Double = 0
    private var drained = false
    private var drainWithinInitialDeadline = false
    private var networkTerminal = false
    private(set) var prepared = false
    private(set) var audioTrackCount = 0
    private(set) var videoTrackCount = 0
    private(set) var decodedFrames = 0

    init(configuration: LegacyProbeConfiguration, client: LegacyProbeRangeClient) throws {
        self.client = client
        guard let url = URL(string: "fr-s20-probe://fixed/\(UUID().uuidString).mov") else {
            throw LegacyProbeError.invalidConfiguration("custom scheme")
        }
        loader = OriginalResourceLoader(resourceURL: url, byteCount: configuration.byteCount) { offset, length in
            try await client.read(offset: offset, length: length)
        }
        asset = AVURLAsset(url: url, options: [
            AVURLAssetReferenceRestrictionsKey: AVAssetReferenceRestrictions.forbidAll.rawValue
        ])
        asset.resourceLoader.setDelegate(loader, queue: .main)
        item = AVPlayerItem(asset: asset)
        output = AVPlayerItemVideoOutput(pixelBufferAttributes:
            CVPixelBufferAttributes(pixelFormatTypes: [.init(rawValue: kCVPixelFormatType_32BGRA)]))
        item.add(output)
        player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = false
        jumpObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.timeJumpedNotification,
            object: item, queue: .main) { [weak self] _ in
                // This observer is explicitly delivered on the main queue.
                MainActor.assumeIsolated {
                    self?.previousPosition = nil
                    self?.previousWasPlaying = false
                    self?.increasingObservations = 0
                }
            }
    }

    func start() {
        guard preparation == nil, teardown == nil else { return }
        preparation = Task { @MainActor in
            defer { preparationFinished = true }
            do {
                audioTrackCount = try await asset.loadTracks(withMediaType: .audio).count
                videoTrackCount = try await asset.loadTracks(withMediaType: .video).count
                let seconds = try await asset.load(.duration).seconds
                guard seconds.isFinite, seconds > 1 else {
                    throw LegacyProbeError.rejected("probe media requires finite duration over one second")
                }
                durationSeconds = seconds
                try Task.checkCancellation()
                guard teardown == nil else { return }
                prepared = true
                player.play()
            } catch { preparationError = legacyProbeErrorCode(error) }
        }
    }

    func waitForActualProgress() async throws {
        // Startup window and sampling interval are provisional test observations.
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if preparationError != nil { throw LegacyProbeError.rejected("asset preparation failed") }
            if item.status == .failed { throw LegacyProbeError.rejected("AVPlayerItem failed") }
            let time = player.currentTime()
            let position = time.seconds
            let playing = player.rate > 0 && player.timeControlStatus == .playing
            if position.isFinite, position >= 0 {
                observedPosition = position
                if let previousPosition, position > previousPosition, previousWasPlaying, playing {
                    increasingObservations += 1
                    if output.hasNewPixelBuffer(forItemTime: time),
                       output.pixelBufferAndDisplayTime(forItemTime: time).pixelBuffer != nil {
                        decodedFrames += 1
                    }
                } else { increasingObservations = 0 }
                previousPosition = position
                previousWasPlaying = playing
                // Prepared/ready and a single time jump are insufficient evidence.
                if prepared, increasingObservations >= 3, position >= 0.15, decodedFrames > 0 { return }
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw LegacyProbeError.timeout("AVPlayer actual progress")
    }

    func stop() async -> Bool {
        if let teardown { return await teardown.value }
        let task = Task { @MainActor in
            // Close admission before SDK cancellation. No new request may slip
            // between detach and drain; cancellation alone is not termination.
            loader.closeAdmission()
            player.pause()
            player.cancelPendingPrerolls()
            item.cancelPendingSeeks()
            player.replaceCurrentItem(with: nil)
            asset.cancelLoading()
            preparation?.cancel()
            if let jumpObserver {
                NotificationCenter.default.removeObserver(jumpObserver)
                self.jumpObserver = nil
            }
            let draining = Task { @MainActor in
                await loader.drain()
                await preparation?.value
                drained = true
            }
            drainWithinInitialDeadline = await legacyProbeEventually(seconds: 10) { self.drained }
            // Normally drain completes first. On timeout still cancel transport
            // for cleanup, preserving the failed drain observation as a failure.
            networkTerminal = await client.stopAndObserveTerminal()
            if !drained { _ = await legacyProbeEventually(seconds: 5) { self.drained } }
            if drained { await draining.value }
            return drainWithinInitialDeadline && drained && networkTerminal
        }
        teardown = task
        return await task.value
    }

    var diagnostics: [String: String] {
        ["prepared": String(prepared), "preparationFinished": String(preparationFinished),
         "preparationError": preparationError ?? "none", "audioTracks": String(audioTrackCount),
         "videoTracks": String(videoTrackCount), "decodedFrames": String(decodedFrames),
         "durationSeconds": durationSeconds.map { String($0) } ?? "unknown",
         "currentSeconds": String(player.currentTime().seconds), "lastObservedSeconds": String(observedPosition),
         "increasingObservations": String(increasingObservations), "rate": String(player.rate),
         "timeControlStatus": String(player.timeControlStatus.rawValue),
         "itemStatus": String(item.status.rawValue), "itemError": item.error.map(legacyProbeErrorCode) ?? "none",
         "playerError": player.error.map(legacyProbeErrorCode) ?? "none",
         "waitingReason": player.reasonForWaitingToPlay?.rawValue ?? "none",
         "sdkDetached": String(player.currentItem == nil), "loaderClosed": String(loader.isClosed),
         "loaderPending": String(loader.pendingCount), "deliveredBytes": String(loader.deliveredBytes),
         "maximumReadLength": String(loader.maximumReadLength), "drained": String(drained),
         "drainWithinInitialDeadline": String(drainWithinInitialDeadline),
         "networkTerminal": String(networkTerminal),
         "audioEvidenceLimit": "track presence plus AVPlayer progression; no device listening assessment"]
    }
}
