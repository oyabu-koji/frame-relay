import Testing
@testable import FrameRelay

struct CaptureReadinessTests {
    @Test func requestedOrSupportedDoesNotMeanApplied() throws {
        let fixture = try CaptureFixture()
        let missing = AppliedCaptureSettings(generation: fixture.context.generation,
                                             operation: .init(rawValue: "synthetic-unread"),
                                             values: .unavailable(.notMeasured))
        #expect(fixture.readiness(applied: missing).blockers == [.appliedValuesUnconfirmed])
        let changed = try CaptureManualExposure(shutter: fixture.desired.exposure.shutter, iso: 200, aperture: nil)
        let actual = AppliedCaptureSettings(
            generation: fixture.context.generation, operation: fixture.applied.operation,
            values: .observed(.init(configuration: fixture.desired.configuration, exposure: changed, zoom: 1),
                              at: fixture.time, method: .direct(source: "synthetic-readback")))
        #expect(fixture.readiness(applied: actual).blockers == [.appliedValuesDiffer])
        #expect(fixture.desired.exposure.iso == 160)
    }

    @Test func unqueriedUnsupportedAndUnavailableRemainDifferent() throws {
        let fixture = try CaptureFixture()
        let possibilities: [(CaptureCapability<Set<CaptureConfiguration>>, RecordingBlocker)] = [
            (.unqueried, .capabilitiesUnqueried),
            (.unsupported(.unsupported), .unsupported(.unsupported)),
            (.unavailable(.permissionDenied), .capabilityUnavailable(.permissionDenied))
        ]
        for (knowledge, blocker) in possibilities {
            let caps = CaptureCapabilities(
                generation: fixture.context.generation, configurations: knowledge,
                controlsForConfiguration: fixture.desired.configuration,
                manualControls: fixture.capabilities.manualControls, whiteBalanceLock: .supported(true))
            #expect(fixture.readiness(capabilities: caps).blockers == [blocker])
        }
    }

    @Test func anotherCamerasManualRangesCannotAuthorizeThisCamera() throws {
        let fixture = try CaptureFixture()
        let cameraB = try CaptureConfiguration(camera: "synthetic-camera-B", width: 3840, height: 2160,
                                              framesPerSecond: 24, codec: .proRes422LT,
                                              logEncoding: .appleLog, stabilizationMode: "synthetic-off")
        let caps = CaptureCapabilities(
            generation: fixture.context.generation,
            configurations: .supported([fixture.desired.configuration, cameraB]),
            controlsForConfiguration: cameraB, manualControls: fixture.capabilities.manualControls,
            whiteBalanceLock: .supported(true))
        #expect(fixture.readiness(capabilities: caps).blockers == [.capabilityScopeMismatch])
    }

    @Test func restoredSettingsMustMatchCurrentCapabilitiesAndGeneration() throws {
        let fixture = try CaptureFixture()
        let caps = CaptureCapabilities(
            generation: fixture.context.generation, configurations: .supported([]),
            controlsForConfiguration: fixture.desired.configuration,
            manualControls: fixture.capabilities.manualControls, whiteBalanceLock: .supported(true))
        #expect(fixture.readiness(capabilities: caps).blockers == [.configurationUnsupported])
        let oldApplied = try CaptureFixture(settingsGeneration: 3).applied
        #expect(fixture.readiness(applied: oldApplied).blockers == [.staleGeneration])
    }

    @Test func silenceAndUnfinishedAnalysisDoNotBlockRECButResourcesDo() throws {
        let fixture = try CaptureFixture()
        #expect(fixture.audio.level.value?.linearAmplitude == 0)
        // The REC rule has no ND/person/WB-stability dependency to wait on.
        #expect(fixture.readiness().blockers.isEmpty)
        #expect(fixture.readiness(input: .checking).blockers == [.audioNotValid])
        #expect(fixture.readiness(camera: .checking, destination: .unavailable(.resourceUnavailable)).blockers
                == [.cameraNotReady, .destinationNotReady])
    }

    @Test func invalidAndDifferentTimelineValuesAreNotSilentlyNormalized() throws {
        #expect(throws: CaptureContractError.invalidValue) { try CaptureRationalTime(ticks: 1, timescale: 0) }
        #expect(throws: CaptureContractError.invalidValue) {
            try CaptureAudioLevel(linearAmplitude: -.infinity, isClipping: false)
        }
        let time = try CaptureRationalTime(ticks: 123, timescale: 600)
        let resolution = try CaptureRationalTime(ticks: 1, timescale: 600)
        let a = try CaptureTimestamp(value: time, clock: .captureDevice(camera: "synthetic-A"),
                                     timelineEpoch: 1, resolution: resolution, uncertainty: nil)
        let b = try CaptureTimestamp(value: time, clock: .captureSession(.init(rawValue: "synthetic-S")),
                                     timelineEpoch: 1, resolution: resolution, uncertainty: nil)
        let c = try CaptureTimestamp(value: time, clock: a.clock,
                                     timelineEpoch: 2, resolution: resolution, uncertainty: nil)
        #expect(a != b)
        #expect(a != c)
        #expect(CaptureTimeObservation.observed(a, .direct(source: "synthetic"))
                != .observed(a, .inferred(method: "synthetic-mapping", evidence: [])))
    }
}
