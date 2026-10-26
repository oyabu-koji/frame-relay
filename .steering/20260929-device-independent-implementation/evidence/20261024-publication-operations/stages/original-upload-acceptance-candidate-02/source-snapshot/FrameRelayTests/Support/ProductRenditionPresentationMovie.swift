import AVFoundation
import Darwin
import Foundation
import Testing
@testable import FrameRelay

/// A longer presentation-only movie in a new dedicated fixture root. The
/// bounded generator stays unchanged; this concatenates its black/silent
/// 60-second movie without claiming camera, conversion or quality evidence.
nonisolated enum ProductRenditionPresentationMovie {
    static let durationSeconds: Double = 180
    private static let maximumOutputBytes = 4 * 1024 * 1024

    static func write(to url: URL) async throws {
        try Task.checkCancellation()
        guard url.isFileURL, !FileManager.default.fileExists(atPath: url.path) else {
            throw CaptureContractError.invalidValue
        }
        let work = url.deletingLastPathComponent().appendingPathComponent(
            "presentation-" + UUID().uuidString, isDirectory: true)
        // mkdir reserves this new leaf atomically. Even a failed export keeps
        // its base/partial output; no existing leaf is repaired or removed.
        guard mkdir(work.path, 0o700) == 0 else { throw BackendContractError.unavailable }
        let baseURL = work.appendingPathComponent("base-60.mov")
        let exportURL = work.appendingPathComponent("export-180.mov")
        try await SyntheticMovieFixture.write(to: baseURL, withAudio: true, durationSeconds: 60)
        let base = AVURLAsset(url: baseURL)
        let tracks = try await checkedTracks(base, expectedSeconds: 60)
        // Preload formats before the synchronous track-edit API can need them.
        _ = try await tracks.video.load(.formatDescriptions)
        _ = try await tracks.audio.load(.formatDescriptions)
        let composition = AVMutableComposition()
        let video = try #require(composition.addMutableTrack(withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid))
        let audio = try #require(composition.addMutableTrack(withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid))
        let segment = CMTimeRange(start: .zero, duration: CMTime(value: 60, timescale: 1))
        for index in 0..<3 {
            try Task.checkCancellation()
            let start = CMTime(value: Int64(index * 60), timescale: 1)
            try video.insertTimeRange(segment, of: tracks.video, at: start)
            try audio.insertTimeRange(segment, of: tracks.audio, at: start)
        }
        let exporter = try #require(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough))
        exporter.timeRange = CMTimeRange(start: .zero, duration: CMTime(value: 180, timescale: 1))
        try await exporter.export(to: exportURL, as: .mov)
        _ = try await checkedTracks(AVURLAsset(url: exportURL), expectedSeconds: durationSeconds)
        let length = try #require(try exportURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        try #require(length > 0 && length <= maximumOutputBytes)
        let bytes = try Data(contentsOf: exportURL)
        try #require(bytes.count == length)
        // The final caller-specified source also has an atomic no-overwrite
        // boundary, independent of the exporter's output-path behavior.
        try bytes.write(to: url, options: .withoutOverwriting)
        _ = try await checkedTracks(AVURLAsset(url: url), expectedSeconds: durationSeconds)
    }

    private static func checkedTracks(_ asset: AVAsset, expectedSeconds: Double) async throws
        -> (video: AVAssetTrack, audio: AVAssetTrack) {
        let duration = try await asset.load(.duration)
        let videos = try await asset.loadTracks(withMediaType: .video)
        let audios = try await asset.loadTracks(withMediaType: .audio)
        try #require(videos.count == 1 && audios.count == 1)
        let video = try #require(videos.first), audio = try #require(audios.first)
        // One PCM sample is the generator's duration precision. Check the
        // actual video/audio timelines too, rather than an audio-only duration.
        let tolerance = 1.0 / 8000.0 + 0.000000001
        try #require(duration.seconds.isFinite && abs(duration.seconds - expectedSeconds) <= tolerance)
        for track in [video, audio] {
            let range = try await track.load(.timeRange)
            try #require(range.start.seconds.isFinite && abs(range.start.seconds) <= tolerance)
            try #require(range.duration.seconds.isFinite && abs(range.duration.seconds - expectedSeconds) <= tolerance)
        }
        return (video, audio)
    }
}
