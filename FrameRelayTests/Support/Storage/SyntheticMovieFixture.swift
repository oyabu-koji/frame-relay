import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import AudioToolbox
@testable import FrameRelay

/// Two tiny synthetic black frames and optional PCM silence. These are API
/// fixtures, not camera recordings, Log samples, or accepted quality conditions.
nonisolated enum SyntheticMovieFixture {
    static func write(to url: URL, withAudio: Bool) async throws {
        try Task.checkCancellation()
        // Encoding is utility work. Swift Testing can call from a user-initiated
        // task; running AVAssetWriter there makes it synchronously wait on its
        // internal utility queue. Awaiting a detached task's value can escalate
        // its priority again, so suspend on completion without joining that task.
        // The fixture's finite work still finishes before this method returns.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            Task.detached(priority: .utility) {
                do {
                    try await generate(to: url, withAudio: withAudio)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private static func generate(to url: URL, withAudio: Bool) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        guard writer.canAdd(videoInput) else { throw CaptureContractError.invalidValue }
        let attributes = CVPixelBufferCreationAttributes(pixelFormatType: .init(rawValue: kCVPixelFormatType_32BGRA),
                                                        size: .init(width: 64, height: 64))
        let video = writer.inputPixelBufferReceiver(for: videoInput, pixelBufferAttributes: attributes)
        let audioFormat = try CMAudioFormatDescription(audioStreamBasicDescription: AudioStreamBasicDescription(
            mSampleRate: 8000, mFormatID: kAudioFormatLinearPCM,
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
            for index in 0..<2 {
                var pixel = try CVMutablePixelBuffer(attributes)
                pixel.accessUnsafeMutableRawPlaneBytes { planes in
                    for plane in planes { _ = plane.bytes.initializeMemory(as: UInt8.self, repeating: 0) }
                }
                let readonly = CVReadOnlyPixelBuffer(pixel)
                try await video.append(readonly, with: CMTime(value: Int64(index), timescale: 2))
            }
            video.finish()
            if let audio {
                let samples = CMReadySampleBuffer(audioDataBuffer: CMReadOnlyDataBlockBuffer(Data(repeating: 0, count: 16000)),
                    formatDescription: audioFormat, sampleCount: 8000, presentationTimeStamp: .zero)
                try await audio.append(CMReadySampleBuffer(samples))
                audio.finish()
            }
            writer.endSession(atSourceTime: CMTime(value: 1, timescale: 1))
            await writer.finishWriting()
            guard writer.status == .completed else { throw CaptureContractError.evidenceMismatch }
        } catch { writer.cancelWriting(); throw error }
    }
}
