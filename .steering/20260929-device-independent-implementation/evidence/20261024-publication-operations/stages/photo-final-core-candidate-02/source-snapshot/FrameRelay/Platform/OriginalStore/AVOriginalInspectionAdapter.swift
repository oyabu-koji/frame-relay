import Foundation
import AVFoundation
import CoreMedia

/// Direct container observations, kept separate from the stronger Domain format
/// assertion because the exploration adapter has not established actual Log.
nonisolated struct OriginalContainerObservation: Sendable {
    let original: CaptureOriginalReference
    let digest: OriginalContentDigest
    let videoTrackCount: Int
    let audioTrackCount: Int
    let videoCodecs: [UInt32]
    let dimensions: [String]
    let nominalFramesPerSecond: [Double]
    /// A duration, never a timestamp on the sample presentation timeline.
    let duration: CaptureRationalTime?
}

/// D05 candidate. Reading all encoded samples is not actual playback or proof
/// of completeness/quality. No camera/stabilization assertion is made from metadata.
actor AVOriginalInspectionAdapter: CaptureOriginalInspectionPort {
    private let originals: ManagedOriginalStore
    private var observations: [CaptureOriginalReference: OriginalContainerObservation] = [:]

    init(originals: ManagedOriginalStore) { self.originals = originals }

    func observation(for original: CaptureOriginalReference) -> OriginalContainerObservation? {
        observations[original]
    }

    func inspect(_ request: CaptureInspectionRequest) async -> CaptureInspectionResult {
        observations[request.original] = nil
        do {
            let url = try await originals.existingURL(for: request.original)
            let digestBefore = try await originals.digest(for: request.original)
            let asset = AVURLAsset(url: url)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let duration = try await asset.load(.duration)
            var codecs: [UInt32] = []
            var dimensions: [String] = []
            var frameRates: [Double] = []
            for track in videoTracks {
                let formats = try await track.load(.formatDescriptions)
                frameRates.append(Double(try await track.load(.nominalFrameRate)))
                for format in formats {
                    codecs.append(CMFormatDescriptionGetMediaSubType(format))
                    let size = CMVideoFormatDescriptionGetDimensions(format)
                    dimensions.append("\(size.width)x\(size.height)")
                }
            }
            let video = try await inspectTrack(videoTracks, asset: asset, stream: "saved-video")
            let audio = try await inspectTrack(audioTracks, asset: asset, stream: "saved-audio")
            let digestAfter = try await originals.digest(for: request.original)
            guard digestBefore == digestAfter else {
                return .unavailable(request.token, .evidenceMismatch)
            }
            observations[request.original] = OriginalContainerObservation(
                original: request.original, digest: digestAfter, videoTrackCount: videoTracks.count,
                audioTrackCount: audioTracks.count, videoCodecs: codecs, dimensions: dimensions,
                nominalFramesPerSecond: frameRates,
                duration: duration.isNumeric && duration.timescale > 0
                    ? try CaptureRationalTime(ticks: duration.value, timescale: duration.timescale) : nil)
            return .inspected(request.token, CaptureMediaInspection(
                context: request.token.context, original: request.original, video: video, audio: audio,
                format: .unavailable(.adapterFailure(code: "actual-log-parser-not-validated")),
                playback: .unavailable(.notMeasured), completeness: .unknown(.evidenceMissing)))
        } catch is CancellationError {
            return .unavailable(request.token, .interrupted)
        } catch {
            // NSError descriptions can contain private paths. Return a stable code only.
            return .unavailable(request.token, .adapterFailure(code: "original-inspection-unavailable"))
        }
    }

    private func inspectTrack(_ tracks: [AVAssetTrack], asset: AVAsset, stream: String) async throws
        -> CaptureTrackInspection {
        guard let track = tracks.first else { return .missing }
        guard tracks.count == 1 else { return .unavailable(.unsupported) }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        guard reader.canAdd(output) else { return .unavailable(.unsupported) }
        let provider = reader.outputProvider(for: output)
        try reader.start()
        defer { if reader.status == .reading { reader.cancelReading() } }
        var span = OriginalPresentationSpan(stream: stream)
        while let sample = try await provider.next() {
            try Task.checkCancellation()
            guard sample.sampleCount > 0 else { continue }
            let properties = sample.sampleProperties
            if properties.count == sample.sampleCount {
                for property in properties { try span.append(property.timing.presentationTimeStamp) }
            } else { try span.appendUnavailableSamples(sample.sampleCount) }
        }
        return span.inspection(readerCompleted: reader.status == .completed)
    }
}

/// Reader output can arrive in decode order. Bounds are presentation-time minima
/// and maxima over individual samples, never the first/last received buffer.
nonisolated struct OriginalPresentationSpan {
    let stream: String
    private var minimum: CMTime?
    private var maximum: CMTime?
    private var unknownTiming = false
    private(set) var count: UInt64 = 0

    mutating func append(_ time: CMTime) throws {
        try increment(1)
        guard time.isNumeric, time.timescale > 0 else { unknownTiming = true; return }
        if let minimum, minimum.epoch != time.epoch { unknownTiming = true; return }
        if minimum == nil || CMTimeCompare(time, minimum ?? time) < 0 { minimum = time }
        if maximum == nil || CMTimeCompare(time, maximum ?? time) > 0 { maximum = time }
    }

    mutating func appendUnavailableSamples(_ number: Int) throws {
        guard number > 0 else { throw CaptureContractError.invalidValue }
        try increment(UInt64(number))
        unknownTiming = true
    }

    private mutating func increment(_ number: UInt64) throws {
        let total = count.addingReportingOverflow(number)
        guard !total.overflow else { throw CaptureContractError.invalidValue }
        count = total.partialValue
    }

    func inspection(readerCompleted: Bool) -> CaptureTrackInspection {
        guard readerCompleted else { return .unavailable(.evidenceMissing) }
        guard count > 0 else { return .missing }
        let first = !unknownTiming ? minimum.map(observedTime) ?? .unavailable(.evidenceMissing)
            : .unavailable(.evidenceMissing)
        let last = !unknownTiming ? maximum.map(observedTime) ?? .unavailable(.evidenceMissing)
            : .unavailable(.evidenceMissing)
        return .verified(.init(first: first, last: last, count: count))
    }

    private func observedTime(_ time: CMTime) -> CaptureTimeObservation {
        guard time.isValid, time.isNumeric, time.timescale > 0 else { return .unavailable(.evidenceMissing) }
        do {
            let timestamp = try CaptureTimestamp(value: .init(ticks: time.value, timescale: time.timescale),
                clock: .mediaPTS(stream: stream), timelineEpoch: time.epoch,
                resolution: .init(ticks: 1, timescale: time.timescale), uncertainty: nil)
            return .observed(timestamp, .direct(source: "AVAssetReader-individual-sample-PTS"))
        } catch { return .unavailable(.evidenceMissing) }
    }
}
