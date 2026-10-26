import Testing
@testable import FrameRelay

/// All capabilities, clocks, IDs and numerical values here are synthetic test inputs.
/// None describe the user's phone, an accepted quality threshold, or product defaults.
nonisolated struct CaptureFixture {
    let context: CaptureContext
    let time: CaptureTimeObservation
    let desired: DesiredCaptureSettings
    let capabilities: CaptureCapabilities
    let applied: AppliedCaptureSettings
    let audio: CaptureAudioState
    let lock: CaptureWhiteBalanceLock
    let intent: RecordingIntent

    init(clip: String = "synthetic-clip-1", settingsGeneration: UInt64 = 4) throws {
        let generation = CaptureGeneration(session: .init(rawValue: "synthetic-session"), settings: settingsGeneration)
        context = CaptureContext(generation: generation, capture: .init(rawValue: clip))
        let timestamp = try CaptureTimestamp(
            value: .init(ticks: 120, timescale: 600), clock: .monotonic(reference: "synthetic-clock"),
            timelineEpoch: 0, resolution: .init(ticks: 1, timescale: 600), uncertainty: nil)
        time = .observed(timestamp, .direct(source: "synthetic-input"))
        let configuration = try CaptureConfiguration(
            camera: "synthetic-camera-A", width: 3840, height: 2160, framesPerSecond: 24,
            codec: .proRes422LT, logEncoding: .appleLog, stabilizationMode: "synthetic-off")
        let exposure = try CaptureManualExposure(shutter: .init(ticks: 1, timescale: 50), iso: 160, aperture: nil)
        desired = try DesiredCaptureSettings(configuration: configuration, exposure: exposure, zoom: 1)
        capabilities = CaptureCapabilities(
            generation: generation, configurations: .supported([configuration]),
            controlsForConfiguration: configuration,
            manualControls: .supported(.init(shutterSeconds: 0.001...0.04, iso: 100...800,
                                             aperture: .unsupported(.unsupported), zoom: 1...3)),
            whiteBalanceLock: .supported(true))
        applied = AppliedCaptureSettings(
            generation: generation, operation: .init(rawValue: "synthetic-apply"),
            values: .observed(.init(configuration: configuration, exposure: exposure, zoom: 1),
                              at: time, method: .direct(source: "synthetic-readback")))
        audio = CaptureAudioState(
            level: .observed(try .init(linearAmplitude: 0, isClipping: false),
                             at: time, method: .direct(source: "synthetic-meter")),
            input: .valid(route: "synthetic-microphone"), arrival: .unobserved, writing: .notStarted)
        lock = CaptureWhiteBalanceLock(gains: try .init(red: 1.4, green: 1, blue: 1.8),
                                       measuredAt: time, appliedAt: time)
        intent = RecordingIntent(context: context, operation: .init(rawValue: "synthetic-rec-\(clip)"),
                                 original: .init(rawValue: "synthetic-original-\(clip)"),
                                 trialReference: "synthetic-trial", desired: desired,
                                 applied: applied, acceptedAt: time)
    }

    func readiness(capabilities override: CaptureCapabilities? = nil,
                   applied appliedOverride: AppliedCaptureSettings? = nil,
                   camera: CaptureResourceReadiness = .ready,
                   input: CaptureAudioInputState? = nil,
                   destination: CaptureResourceReadiness = .ready) -> CaptureReadiness {
        CaptureReadiness(generation: context.generation, desired: desired,
                         capabilities: override ?? capabilities, applied: appliedOverride ?? applied,
                         camera: camera, audioInput: input ?? audio.input,
                         destination: destination, recordingResources: .ready)
    }

    var end: RecordingEndEvidence {
        RecordingEndEvidence(writer: .completed, ceasedAt: time, lastVideo: time, lastAudio: time)
    }

    var file: CaptureFileEvidence {
        CaptureFileEvidence(context: context, original: intent.original, byteCount: 4096, finalizedAt: time)
    }

    func inspection(audio audioOverride: CaptureTrackInspection? = nil,
                    original: CaptureOriginalReference? = nil) -> CaptureMediaInspection {
        let span = CaptureSampleSpan(first: time, last: time, count: 10)
        let configuration = desired.configuration
        return CaptureMediaInspection(
            context: context, original: original ?? intent.original,
            video: .verified(span), audio: audioOverride ?? .verified(span),
            format: .observed(.init(width: configuration.width, height: configuration.height,
                                    nominalFramesPerSecond: Double(configuration.framesPerSecond),
                                    codec: configuration.codec, logEncoding: configuration.logEncoding),
                               at: time, method: .direct(source: "synthetic-inspection")),
            playback: .verified, completeness: .complete)
    }

    func token(_ ordinal: UInt64) -> CaptureCommandToken {
        CaptureCommandToken(context: context, operation: intent.operation, ordinal: ordinal)
    }

    func receipt(_ token: CaptureCommandToken, previous: UInt64 = 0) -> RecordingCommitReceipt {
        RecordingCommitReceipt(token: token, previousRevision: previous, committedRevision: previous + 1)
    }
}

nonisolated func captureEffects(_ transition: CaptureTransition) throws -> [CaptureLifecycleEffect] {
    guard case .accepted(let effects) = transition else {
        Issue.record("Expected accepted transition, got \(transition)")
        throw CaptureContractError.wrongStage
    }
    return effects
}

nonisolated func beginCapture(_ lifecycle: inout CaptureLifecycle, fixture: CaptureFixture)
    throws -> (intent: CaptureCommandToken, whiteBalance: CaptureCommandToken) {
    let effects = try captureEffects(lifecycle.begin(fixture.intent, readiness: fixture.readiness(),
                                                    expectedStoreRevision: 0))
    let store = try #require(effects.compactMap { effect -> CaptureCommandToken? in
        if case .store(.commitIntent(let token, _, _)) = effect { return token }
        return nil
    }.first)
    let wb = try #require(effects.compactMap { effect -> CaptureCommandToken? in
        if case .capture(.lockCurrentWhiteBalance(let token)) = effect { return token }
        return nil
    }.first)
    return (store, wb)
}

nonisolated func requestRecorderStart(_ lifecycle: inout CaptureLifecycle, fixture: CaptureFixture)
    throws -> CaptureCommandToken {
    let tokens = try beginCapture(&lifecycle, fixture: fixture)
    _ = try captureEffects(lifecycle.receive(.whiteBalanceLocked(tokens.whiteBalance, fixture.lock)))
    let effects = try captureEffects(lifecycle.receiveIntentCommit(fixture.receipt(tokens.intent)))
    return try #require(effects.compactMap { effect -> CaptureCommandToken? in
        if case .capture(.startRecording(let token, _)) = effect { return token }
        return nil
    }.first)
}
