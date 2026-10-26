import AVFoundation
import Testing
@testable import FrameRelay

struct NativeCaptureAudioObservationTests {
    @Test(arguments: [false, true])
    func actualPCMSeparatesQuietSoundAndFullScale(nonInterleaved: Bool) throws {
        let flags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
            | (nonInterleaved ? kAudioFormatFlagIsNonInterleaved : 0)
        for values: [Float] in [[0, 0, 0, 0], [0.5, -0.5, 0.5, -0.5], [1, -1, 1, -1]] {
            try withPCM(values, flags: flags, channels: 2, nonInterleaved: nonInterleaved) { sample in
                let level = try #require(NativeCaptureAudioMeter.measure(sample).value)
                #expect(abs(level.linearAmplitude - Double(abs(values[0]))) < 0.00001)
                #expect(level.isClipping == (abs(values[0]) == 1))
            }
        }
    }

    @Test func integerPositiveAndNegativeFullScaleAndNearPeakRemainDistinct() throws {
        let flags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked
        for value: Int16 in [0, 16_384, .max, .min] {
            try withPCM([value], flags: flags) { sample in
                let level = try #require(NativeCaptureAudioMeter.measure(sample).value)
                #expect(level.isClipping == (value == .max || value == .min))
                #expect(level.linearAmplitude == abs(Double(value)) / 32_768)
            }
        }
        for value: Int32 in [.max, .min] {
            try withPCM([value], flags: flags) { sample in
                #expect(NativeCaptureAudioMeter.measure(sample).value?.isClipping == true)
            }
        }
        try withPCM([Float(0.999)], flags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked) { sample in
            #expect(NativeCaptureAudioMeter.measure(sample).value?.isClipping == false)
        }
    }

    @Test func nonfiniteMeterDoesNotInventSilenceOrLostInput() throws {
        let fixture = try CaptureFixture()
        for value: Float in [.nan, .infinity] {
            var observation = NativeCaptureAudioObservation(beganAt: 10)
            try withPCM([value], flags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked) { sample in
                #expect(NativeCaptureAudioMeter.measure(sample).value == nil)
                let observedResult1 = observation.receive(sample, generation: fixture.context.generation, route: "test mic", now: 11)
                #expect(observedResult1)
            }
            #expect(observation.state.input == .valid(route: "test mic"))
            #expect(observation.state.confirmedFailure == nil)
            #expect(observation.state.writing == .notStarted)
        }
    }

    @Test func silenceArrivalDeadlineAndReorderedSamplesUseActualSampleObservations() throws {
        let fixture = try CaptureFixture()
        var observation = NativeCaptureAudioObservation(beganAt: 10)
        let evidence = CaptureEvidenceID(rawValue: "synthetic-deadline")
        #expect(observation.state.input == .checking)
        let observedResult2 = observation.checkArrival(now: 11.9, grace: 2, evidence: evidence)
        #expect(observedResult2 == nil)
        try withPCM([Int16(0), 0], flags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                    at: CMTime(value: 100, timescale: 48_000)) { sample in
            let observedResult3 = observation.receive(sample, generation: fixture.context.generation, route: "test mic", now: 11.99)
            #expect(observedResult3)
            let observedResult4 = observation.receive(sample, generation: fixture.context.generation, route: "test mic", now: 12.5)
            #expect(!observedResult4)
        }
        #expect(observation.lastArrival == 11.99)
        #expect(observation.state.level.value?.linearAmplitude == 0)
        #expect(observation.state.input == .valid(route: "test mic"))
        let observedResult5 = observation.checkArrival(now: 13.98, grace: 2, evidence: evidence)
        #expect(observedResult5 == nil)
        let observedResult6 = observation.checkArrival(now: 14, grace: 2, evidence: evidence)
        #expect(observedResult6 == .confirmedNoSamples(evidence))
        try withPCM([Int16(0)], flags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                    at: CMTime(value: 200, timescale: 48_000)) { sample in
            let observedResult7 = observation.receive(sample, generation: fixture.context.generation, route: "test mic", now: 15)
            #expect(observedResult7)
        }
        #expect(observation.state.confirmedFailure == .confirmedNoSamples(evidence))
        observation.reset(at: 16)
        #expect(observation.state.input == .checking)
        #expect(observation.state.arrival == .unobserved)
    }

    @Test func noSamplesIsFiniteAndFailedWriteCannotBecomeCompleted() throws {
        var observation = NativeCaptureAudioObservation(beganAt: 0)
        let fixture = try CaptureFixture()
        let failure = CaptureAudioFailure.writerFailed(.init(rawValue: "append-failure"))
        let observedResult8 = observation.checkArrival(now: 0.9, grace: 1, evidence: .init(rawValue: "no-arrival"))
        #expect(observedResult8 == nil)
        observation.fail(failure)
        let span = CaptureSampleSpan(first: fixture.time, last: fixture.time, count: 1)
        observation.writing(.completed(span))
        #expect(observation.state.writing == .failed(failure))
        observation.reset(at: 2)
        observation.beginClip(movie: true)
        #expect(observation.state.writing == .unavailable(.apiDoesNotExpose))
        let observedResult9 = observation.checkArrival(now: 3, grace: 1, evidence: .init(rawValue: "no-arrival"))
        #expect(observedResult9 != nil)
    }

    @Test func productArrivalDeadlineStillAppliesAfterUserRecoveryReset() throws {
        let policy = ProductCaptureFactory.provisionalAudioPolicyV1
        let evidence = CaptureEvidenceID(rawValue: "product-recovery-no-arrival")
        var observation = NativeCaptureAudioObservation(beganAt: 0)
        let originalFailure = observation.checkArrival(now: 2, grace: policy.noArrivalGrace.seconds, evidence: evidence)
        #expect(originalFailure == .confirmedNoSamples(evidence))
        observation.reset(at: 10)
        #expect(observation.state.input == .checking)
        let beforeDeadline = observation.checkArrival(now: 11.999, grace: policy.noArrivalGrace.seconds, evidence: evidence)
        #expect(beforeDeadline == nil)
        let recoveryFailure = observation.checkArrival(now: 12, grace: policy.noArrivalGrace.seconds, evidence: evidence)
        #expect(recoveryFailure == .confirmedNoSamples(evidence))
        // Reconfiguration does not extend no-arrival detection to the five-second outer timeout.
        #expect(policy.noArrivalGrace.seconds < policy.recovery.attemptTimeout.seconds)
    }

    private func withPCM<Value>(_ values: [Value], flags: AudioFormatFlags, channels: UInt32 = 1,
                                        nonInterleaved: Bool = false, at: CMTime = .zero,
                                        body: (CMSampleBuffer) throws -> Void) throws {
        let size = UInt32(MemoryLayout<Value>.size)
        let bytesPerFrame = size * (nonInterleaved ? 1 : channels)
        let format = try CMAudioFormatDescription(audioStreamBasicDescription: .init(
            mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: flags,
            mBytesPerPacket: bytesPerFrame, mFramesPerPacket: 1, mBytesPerFrame: bytesPerFrame,
            mChannelsPerFrame: channels, mBitsPerChannel: size * 8, mReserved: 0))
        let bytes = values.withUnsafeBytes { Data($0) }
        let sample = CMReadySampleBuffer(audioDataBuffer: CMReadOnlyDataBlockBuffer(bytes),
            formatDescription: format, sampleCount: values.count / Int(channels), presentationTimeStamp: at)
        try sample.withUnsafeSampleBuffer { buffer in try body(buffer) }
    }
}
