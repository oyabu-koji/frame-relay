import AVFoundation

/// PCM processing shared by both output candidates and synthetic CMSampleBuffer tests.
/// Zero RMS is a valid sample. Unsupported meter formats do not imply lost input.
nonisolated enum NativeCaptureAudioMeter {
    static func measure(_ sample: CMSampleBuffer) -> CaptureObservation<CaptureAudioLevel> {
        guard CMSampleBufferDataIsReady(sample),
              let description = CMSampleBufferGetFormatDescription(sample),
              CMFormatDescriptionGetMediaType(description) == kCMMediaType_Audio,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              asbd.pointee.mFormatID == kAudioFormatLinearPCM,
              asbd.pointee.mSampleRate.isFinite, asbd.pointee.mSampleRate > 0,
              asbd.pointee.mChannelsPerFrame > 0,
              asbd.pointee.mFramesPerPacket == 1,
              let format = AVAudioFormat(formatDescription: description),
              format.commonFormat != .otherFormat,
              CMSampleBufferGetNumSamples(sample) > 0,
              CMSampleBufferGetNumSamples(sample) <= Int(Int32.max),
              let pcm = AVAudioPCMBuffer(pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))) else {
            return .unavailable(.evidenceMismatch)
        }
        pcm.frameLength = pcm.frameCapacity
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0,
            frameCount: Int32(pcm.frameLength), into: pcm.mutableAudioBufferList) == noErr else {
            return .unavailable(.unsupported)
        }
        let stream = format.streamDescription.pointee
        let bytesPerSample: Int
        switch format.commonFormat {
        case .pcmFormatFloat32, .pcmFormatInt32: bytesPerSample = 4
        case .pcmFormatFloat64: bytesPerSample = 8
        case .pcmFormatInt16: bytesPerSample = 2
        default: return .unavailable(.unsupported)
        }
        let channelsPerBuffer = format.isInterleaved ? Int(format.channelCount) : 1
        guard stream.mFormatID == kAudioFormatLinearPCM,
              stream.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
              stream.mFormatFlags & kAudioFormatFlagIsPacked != 0,
              stream.mBytesPerFrame == channelsPerBuffer * bytesPerSample else { return .unavailable(.unsupported) }
        var squareSum = 0.0
        var clipped = false
        var count = 0
        for buffer in UnsafeMutableAudioBufferListPointer(pcm.mutableAudioBufferList) {
            guard let data = buffer.mData else { return .unavailable(.evidenceMissing) }
            let length = Int(pcm.frameLength).multipliedReportingOverflow(by: Int(buffer.mNumberChannels))
            let byteLength = length.partialValue.multipliedReportingOverflow(by: bytesPerSample)
            guard !length.overflow, !byteLength.overflow, length.partialValue > 0,
                  byteLength.partialValue <= Int(buffer.mDataByteSize) else { return .unavailable(.evidenceMismatch) }
            for index in 0..<length.partialValue {
                let value: Double
                switch format.commonFormat {
                case .pcmFormatFloat32: value = Double(data.assumingMemoryBound(to: Float.self)[index])
                case .pcmFormatFloat64: value = data.assumingMemoryBound(to: Double.self)[index]
                case .pcmFormatInt16:
                    let integer = data.assumingMemoryBound(to: Int16.self)[index]
                    clipped = clipped || integer == .min || integer == .max
                    value = Double(integer) / 32768
                case .pcmFormatInt32:
                    let integer = data.assumingMemoryBound(to: Int32.self)[index]
                    clipped = clipped || integer == .min || integer == .max
                    value = Double(integer) / 2147483648
                default: return .unavailable(.unsupported)
                }
                guard value.isFinite else { return .unavailable(.evidenceMismatch) }
                squareSum += value * value
                clipped = clipped || abs(value) >= 1
                count += 1
            }
        }
        guard count > 0,
              let level = try? CaptureAudioLevel(linearAmplitude: sqrt(squareSum / Double(count)),
                                                isClipping: clipped) else {
            return .unavailable(.evidenceMismatch)
        }
        return .observed(level, at: ExplorationCaptureValues.now(), method: .direct(source: "PCM-RMS-peak"))
    }
}

/// The SDK owner supplies actual route/connection checks and monotonic arrival time.
/// Failure is latched until a user-requested audio reconfiguration; sound level cannot clear it.
nonisolated struct NativeCaptureAudioObservation: Sendable {
    private(set) var state = CaptureAudioState(level: .unavailable(.notMeasured), input: .checking,
                                               arrival: .unobserved, writing: .notStarted)
    private(set) var lastArrival: Double?
    private var beganAt: Double
    private var first: CaptureTimeObservation?
    private var lastPTS: CMTime?
    private var count: UInt64 = 0

    init(beganAt: Double) { self.beganAt = beganAt }

    mutating func reset(at now: Double) { self = Self(beganAt: now) }

    mutating func receive(_ sample: CMSampleBuffer, generation: CaptureGeneration,
                          route: String?, now: Double) -> Bool {
        guard let route, CMSampleBufferDataIsReady(sample), CMSampleBufferGetNumSamples(sample) > 0,
              let description = CMSampleBufferGetFormatDescription(sample),
              CMFormatDescriptionGetMediaType(description) == kCMMediaType_Audio else { return false }
        var lastTiming = CMSampleTimingInfo()
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        guard pts.isNumeric,
              CMSampleBufferGetSampleTimingInfo(sample, at: CMSampleBufferGetNumSamples(sample) - 1,
                                               timingInfoOut: &lastTiming) == noErr,
              lastTiming.presentationTimeStamp.isNumeric,
              lastTiming.presentationTimeStamp.epoch == pts.epoch,
              CMTimeCompare(lastTiming.presentationTimeStamp, pts) >= 0,
              lastPTS.map({ $0.epoch == pts.epoch && CMTimeCompare(pts, $0) > 0 }) ?? true else { return false }
        lastPTS = lastTiming.presentationTimeStamp
        lastArrival = now
        let firstTime = ExplorationCaptureValues.time(pts, clock: .captureSession(generation.session), source: "audio-sample-PTS")
        if first == nil { first = firstTime }
        count += UInt64(CMSampleBufferGetNumSamples(sample))
        state.level = NativeCaptureAudioMeter.measure(sample)
        state.arrival = .received(.init(first: first ?? firstTime,
            last: ExplorationCaptureValues.time(lastTiming.presentationTimeStamp,
                clock: .captureSession(generation.session), source: "audio-sample-PTS"), count: count))
        if state.confirmedFailure == nil { state.input = .valid(route: route) }
        return true
    }

    mutating func checkArrival(now: Double, grace: Double, evidence: CaptureEvidenceID) -> CaptureAudioFailure? {
        guard state.confirmedFailure == nil, now - (lastArrival ?? beganAt) >= grace else { return nil }
        let failure = CaptureAudioFailure.confirmedNoSamples(evidence)
        fail(failure)
        return failure
    }

    mutating func fail(_ failure: CaptureAudioFailure) {
        guard state.confirmedFailure == nil else { return }
        switch failure {
        case .writerFailed: state.writing = .failed(failure)
        default: state.input = .failed(failure)
        }
    }

    mutating func writing(_ value: CaptureAudioWriting) {
        if case .failed = state.writing { return }
        state.writing = value
    }

    mutating func beginClip(movie: Bool) {
        state.writing = movie ? .unavailable(.apiDoesNotExpose) : .notStarted
    }
}
