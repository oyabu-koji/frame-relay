import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import AudioToolbox
@testable import FrameRelay

/// Tiny synthetic black frames and optional PCM silence. These are API
/// fixtures, not camera recordings, Log samples, or accepted quality conditions.
nonisolated enum SyntheticMovieFixture {
    private static let sampleRate: Int32 = 8000

    static func write(to url: URL, withAudio: Bool, durationSeconds: Double = 1) async throws {
        try Task.checkCancellation()
        // Limit this test-only generator to 120 video frames and 960 KB of PCM
        // in total, appending at most 8 KB of audio at a time.
        // Both tracks and the session end use the same nearest audio-sample time.
        guard durationSeconds.isFinite, durationSeconds > 0, durationSeconds <= 60 else {
            throw CaptureContractError.invalidValue
        }
        let sampleCount = Int((durationSeconds * Double(sampleRate)).rounded())
        guard sampleCount > 0 else { throw CaptureContractError.invalidValue }
        // Encoding is utility work. Swift Testing can call from a user-initiated
        // task; running AVAssetWriter there makes it synchronously wait on its
        // internal utility queue. Awaiting a detached task's value can escalate
        // its priority again, so suspend on completion without joining that task.
        // The fixture's finite work still finishes before this method returns.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            Task.detached(priority: .utility) {
                do {
                    try await generate(to: url, withAudio: withAudio, sampleCount: sampleCount)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private static func generate(to url: URL, withAudio: Bool, sampleCount: Int) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        guard writer.canAdd(videoInput) else { throw CaptureContractError.invalidValue }
        let attributes = CVPixelBufferCreationAttributes(pixelFormatType: .init(rawValue: kCVPixelFormatType_32BGRA),
                                                        size: .init(width: 64, height: 64))
        let video = writer.inputPixelBufferReceiver(for: videoInput, pixelBufferAttributes: attributes)
        let audioFormat = try CMAudioFormatDescription(audioStreamBasicDescription: AudioStreamBasicDescription(
            mSampleRate: Double(sampleRate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
            mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0))
        var audio: AVAssetWriterInput.SampleBufferReceiver?
        if withAudio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: audioFormat)
            guard writer.canAdd(input) else { throw CaptureContractError.invalidValue }
            audio = writer.inputReceiver(for: input)
        }
        try writer.start()
        writer.startSession(atSourceTime: .zero)
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                // Each receiver has one producer. An input's backpressure must
                // not prevent the other track from supplying its next sample.
                group.addTask {
                    try await appendVideo(to: video, sampleCount: sampleCount)
                }
                if let audio {
                    group.addTask {
                        try await appendAudio(to: audio, format: audioFormat, sampleCount: sampleCount)
                    }
                }
                do {
                    while let _ = try await group.next() {}
                } catch {
                    // Cancel the writer before group scope joins the other
                    // producer, which may be suspended in receiver.append.
                    writer.cancelWriting()
                    group.cancelAll()
                    throw error
                }
            }
            // Both producers have actually exited and finished their inputs.
            writer.endSession(atSourceTime: CMTime(value: Int64(sampleCount), timescale: sampleRate))
            await writer.finishWriting()
            guard writer.status == .completed else { throw CaptureContractError.evidenceMismatch }
        } catch { writer.cancelWriting(); throw error }
    }

    private static func appendVideo(to receiver: sending AVAssetWriterInput.PixelBufferReceiver,
                                    sampleCount: Int) async throws {
        defer { receiver.finish() }
        let attributes = CVPixelBufferCreationAttributes(pixelFormatType: .init(rawValue: kCVPixelFormatType_32BGRA),
                                                        size: .init(width: 64, height: 64))
        for sampleTime in stride(from: 0, to: sampleCount, by: Int(sampleRate / 2)) {
            try Task.checkCancellation()
            var pixel = try CVMutablePixelBuffer(attributes)
            pixel.accessUnsafeMutableRawPlaneBytes { planes in
                for plane in planes { _ = plane.bytes.initializeMemory(as: UInt8.self, repeating: 0) }
            }
            try await receiver.append(CVReadOnlyPixelBuffer(pixel),
                                      with: CMTime(value: Int64(sampleTime), timescale: sampleRate))
        }
    }

    private static func appendAudio(to receiver: sending AVAssetWriterInput.SampleBufferReceiver,
                                    format: CMAudioFormatDescription, sampleCount: Int) async throws {
        defer { receiver.finish() }
        for sampleTime in stride(from: 0, to: sampleCount, by: Int(sampleRate / 2)) {
            try Task.checkCancellation()
            let chunkCount = min(Int(sampleRate / 2), sampleCount - sampleTime)
            let samples = CMReadySampleBuffer(
                audioDataBuffer: CMReadOnlyDataBlockBuffer(Data(repeating: 0, count: chunkCount * 2)),
                formatDescription: format, sampleCount: chunkCount,
                presentationTimeStamp: CMTime(value: Int64(sampleTime), timescale: sampleRate))
            try await receiver.append(CMReadySampleBuffer(samples))
        }
    }
}
