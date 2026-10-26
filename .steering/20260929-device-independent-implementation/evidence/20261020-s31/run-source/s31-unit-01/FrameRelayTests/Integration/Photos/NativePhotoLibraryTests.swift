import AVFoundation
import CoreVideo
import Foundation
import Photos
import Synchronization
import Testing
@testable import FrameRelay

/// Explicit, disposable-Simulator probes only. Xcode forwards TEST_RUNNER_FR_*
/// as FR_* to the host. Grant photos-add + photos for `authorized`; deny both
/// for `denied`. This suite never deletes Photos assets, including on failure.
/// Its black H.264 frames and silent PCM are not Log/Rec.709 quality evidence.
@Suite(.serialized) @MainActor struct NativePhotoLibraryTests {
    @Test(.enabled(if: photoProbeIsSimulator
        && ProcessInfo.processInfo.environment["FR_PHOTOS_INTEGRATION"] == "authorized"))
    func realAdditionKeepsSourceUntilCallbackAndExactLookupPreservesDateAndAudio() async throws {
        let photos = NativePhotoLibrary()
        // The probe must have prearranged privacy grants and cannot open an
        // unattended permission prompt on an arbitrary developer library.
        try #require(await photos.authorizationStatus(for: .addOnly) == .authorized)
        try #require(await photos.authorizationStatus(for: .readWrite) == .authorized)
        #expect(await photos.requestAuthorization(for: .addOnly) == .authorized)

        try await withStorageRun { run in
            let fixture = try await PhotoProbeMedia.make(run: run)
            #expect(fixture.command.media.contentType == "video/quicktime")
            let before = try await fixture.media.temporary.usageSnapshot(fixture.usage.media)
            try #require(before.uses == 1 && before.openHandles == 1 && before.fileBytes > 0)

            let result = await photos.add(fixture.command)
            guard case .succeeded(let optionalIdentifier) = result.outcome else {
                try await fixture.media.temporary.finishPhotoMedia(fixture.usage)
                Issue.record("Real PhotoKit addition did not succeed: \(result.outcome)")
                return
            }
            // Successful add returns only after the performChanges callback.
            // The adapter neither moves the source nor releases its use/FD.
            let afterCallback = try await fixture.media.temporary.usageSnapshot(fixture.usage.media)
            #expect(afterCallback.openHandles == 1 && afterCallback.uses == 1)
            #expect(afterCallback.fileBytes == before.fileBytes)
            #expect(try Data(contentsOf: fixture.command.media.url) == fixture.bytes)
            try await fixture.media.temporary.finishPhotoMedia(fixture.usage)
            try #require(result.intent == fixture.command.registration.intent)
            let identifier = try #require(optionalIdentifier)
            _ = try await mediaCommit(fixture.media.store, .photo(
                command: .init(rawValue: UUID().uuidString), value: .result(result)))
            #expect(await fixture.media.temporary.releaseUsage(fixture.usage) == .succeeded(fixture.usage.media))
            let released = try await fixture.media.temporary.usageSnapshot(fixture.usage.media)
            #expect(released.uses == 0 && released.openHandles == 0 && released.fileBytes == 0)
            #expect(!FileManager.default.fileExists(atPath: fixture.command.media.url.path))

            // Read/write is requested separately, for this explicit result
            // inspection. Saving itself used only the add-only API.
            #expect(await photos.requestAuthorization(for: .readWrite) == .authorized)
            let observation = await photos.lookup(identifier)
            #expect(observation.identifier == identifier && observation.authorization == .authorized)
            try #require(observation.presence == .present)
            let asset = try #require(PHAsset.fetchAssets(
                withLocalIdentifiers: [identifier.rawValue], options: nil).firstObject)
            #expect(asset.localIdentifier == identifier.rawValue)
            #expect(asset.mediaType == .video)
            #expect(asset.creationDate == fixture.command.registration.intent.capturedAt)
            let resource = try #require(PHAssetResource.assetResources(for: asset).first { $0.type == .video })
            #expect(try await photoProbeResourceData(resource) == fixture.bytes)
            let audiovisualAsset = try await photoProbeAVAsset(asset)
            #expect(try await audiovisualAsset.loadTracks(withMediaType: .video).count == 1)
            #expect(try await audiovisualAsset.loadTracks(withMediaType: .audio).count == 1)
            try await photoProbeObservePlayback(audiovisualAsset)

            let missing = try PhotoAssetIdentifier(rawValue: UUID().uuidString + "/L0/001")
            let notFound = await photos.lookup(missing)
            #expect(notFound.identifier == missing && notFound.authorization == .authorized)
            #expect(notFound.presence == .notFound)
            // Not-found is an observation of this exact identifier, not a
            // rewrite of the successful add or permission to save it again.
            let durable = try #require(try await mediaSnapshot(fixture.media.store).photoRegistrations.first)
            #expect(durable.outcome == result.outcome && durable.localIdentifier == identifier)
            _ = try await fixture.media.scope.close()
        }
    }

    @Test(.enabled(if: photoProbeIsSimulator
        && ProcessInfo.processInfo.environment["FR_PHOTOS_INTEGRATION"] == "denied"))
    func deniedAddOnlyDoesNotInvokeAnAdditionAndReadLookupStaysUnavailable() async throws {
        let photos = NativePhotoLibrary()
        try #require(await photos.authorizationStatus(for: .addOnly) == .denied)
        try #require(await photos.authorizationStatus(for: .readWrite) == .denied)
        #expect(await photos.requestAuthorization(for: .addOnly) == .denied)
        try await withStorageRun { run in
            let fixture = try await PhotoProbeMedia.make(run: run)
            let result = await photos.add(fixture.command)
            try #require(result.intent == fixture.command.registration.intent)
            // notAttempted is the adapter's proof that performChanges never
            // started; closing this unused SDK access does not claim success.
            try #require(result.outcome == .notAttempted(.authorizationRequired))
            #expect(try await fixture.media.temporary.usageSnapshot(fixture.usage.media).openHandles == 1)
            try await fixture.media.temporary.finishPhotoMedia(fixture.usage)
            _ = try await mediaCommit(fixture.media.store, .photo(
                command: .init(rawValue: UUID().uuidString), value: .result(result)))
            #expect(try await fixture.media.temporary.usageSnapshot(fixture.usage.media).uses == 1)
            let identifier = try PhotoAssetIdentifier(rawValue: UUID().uuidString + "/L0/001")
            let lookup = await photos.lookup(identifier)
            #expect(lookup.identifier == identifier && lookup.authorization == .denied)
            #expect(lookup.presence == .unavailable)
            let durable = try #require(try await mediaSnapshot(fixture.media.store).photoRegistrations.first)
            #expect(durable.outcome == result.outcome && durable.localIdentifier == nil)
            // A denied operation is retained for its explicit next action.
            // Its durable use prevents scope.close from claiming all readers
            // released. No second add, use release, or Photos cleanup occurs.
            let retained = try await fixture.media.temporary.usageSnapshot(fixture.usage.media)
            #expect(retained.uses == 1 && retained.openHandles == 0 && retained.fileBytes > 0)
        }
    }
}

private nonisolated var photoProbeIsSimulator: Bool {
    #if targetEnvironment(simulator)
    true
    #else
    false
    #endif
}

private nonisolated struct PhotoProbeMedia: Sendable {
    let media: RenditionFixture
    let bytes: Data
    let usage: TemporaryMediaUsage
    let command: PhotoLibraryAddCommand

    static func make(run: ExplorationRunDirectory) async throws -> Self {
        let sourceURL = run.url.appendingPathComponent("explicit-photo-probe.mov")
        try await SyntheticMovieFixture.write(to: sourceURL, withAudio: true, durationSeconds: 3,
                                               capturedAt: RenditionFixture.capturedAt)
        let bytes = try Data(contentsOf: sourceURL)
        let media = try await RenditionFixture.make(run: run, content: renditionContent(bytes))
        let complete = try await media.complete(bytes)
        guard case .succeeded(let usage) = await media.temporary.acquireUsage(complete.id,
            purpose: .photoHandoff, usageID: .init(rawValue: UUID().uuidString)) else {
            throw BackendContractError.ineligibleOriginal
        }
        let local = try await media.temporary.resolvePhotoMedia(usage)
        guard case .succeeded = await media.temporary.releaseUsage(complete.usage) else {
            throw BackendContractError.readersActive
        }
        let intent = try PhotoRegistrationIntent(operation: .init(rawValue: UUID().uuidString), handoff: local.handoff)
        let snapshot = try await mediaSnapshot(media.store)
        let mutation = BackendStoreMutation(expectedRevision: snapshot.revision,
            change: .photo(command: intent.operation, value: .intent(intent)))
        guard case .committed(let commit) = await media.store.commit(mutation),
              await media.store.lookupCommit(mutation) == .committed(commit) else {
            throw BackendContractError.notCommitted
        }
        let record = try #require(try await mediaSnapshot(media.store).photoRegistrations.first)
        guard record.registration.intent == intent, record.registration.commit == commit else {
            throw BackendContractError.identityMismatch
        }
        return try .init(media: media, bytes: bytes, usage: usage,
                         command: PhotoLibraryAddCommand(registration: record.registration, media: local))
    }
}

private nonisolated func photoProbeAVAsset(_ asset: PHAsset) async throws -> AVURLAsset {
    let options = PHVideoRequestOptions()
    options.version = .original
    options.isNetworkAccessAllowed = false
    return try await withCheckedThrowingContinuation { continuation in
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { value, _, _ in
            guard let asset = value as? AVURLAsset else {
                continuation.resume(throwing: BackendContractError.unavailable)
                return
            }
            continuation.resume(returning: asset)
        }
    }
}

private nonisolated func photoProbeResourceData(_ resource: PHAssetResource) async throws -> Data {
    let storage = PhotoProbeBytes()
    let options = PHAssetResourceRequestOptions()
    options.isNetworkAccessAllowed = false
    return try await withCheckedThrowingContinuation { continuation in
        PHAssetResourceManager.default().requestData(for: resource, options: options) { data in
            storage.bytes.withLock { $0.append(data) }
        } completionHandler: { error in
            if let error { continuation.resume(throwing: error) }
            else { continuation.resume(returning: storage.bytes.withLock { $0 }) }
        }
    }
}

private nonisolated final class PhotoProbeBytes: Sendable {
    let bytes = Mutex(Data())
}

@MainActor private func photoProbeObservePlayback(_ asset: AVURLAsset) async throws {
    let item = AVPlayerItem(asset: asset)
    let output = AVPlayerItemVideoOutput(pixelBufferAttributes:
        CVPixelBufferAttributes(pixelFormatTypes: [.init(rawValue: kCVPixelFormatType_32BGRA)]))
    item.add(output)
    let player = AVPlayer(playerItem: item)
    player.automaticallyWaitsToMinimizeStalling = false
    defer {
        player.pause()
        player.replaceCurrentItem(with: nil)
        asset.cancelLoading()
    }
    player.play()
    let deadline = ContinuousClock.now.advanced(by: .seconds(15))
    var previous: Double?
    var increasingObservations = 0
    var decodedFrames = 0
    while ContinuousClock.now < deadline {
        guard item.status != .failed else { throw BackendContractError.unavailable }
        let time = player.currentTime()
        let seconds = time.seconds
        if seconds.isFinite, seconds > 0, player.rate > 0, player.timeControlStatus == .playing {
            if let previous, seconds > previous { increasingObservations += 1 }
            previous = seconds
            if output.hasNewPixelBuffer(forItemTime: time),
               output.pixelBufferAndDisplayTime(forItemTime: time).pixelBuffer != nil {
                decodedFrames += 1
            }
            if seconds >= 0.25 && increasingObservations >= 2 && decodedFrames > 0 { return }
        }
        try await Task.sleep(for: .milliseconds(25))
    }
    throw BackendContractError.unavailable
}
