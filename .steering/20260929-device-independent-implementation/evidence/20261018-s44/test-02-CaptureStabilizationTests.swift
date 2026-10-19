import Testing
@testable import FrameRelay

struct CaptureStabilizationTests {
    @Test @MainActor func firstCandidateIsReversibleAndSavedWishesWin() throws {
        let first = ProductCaptureSettingsDraft(.init())
        #expect(first.stabilization == "standard")
        #expect(first.framesPerSecond == 0)
        #expect(first.output.isEmpty)
        let fixture = try CaptureFixture()
        let restored = ProductCaptureSettingsDraft(.init(desired: fixture.desired, outputCandidate: .sampleWriter))
        #expect(restored.stabilization == fixture.desired.configuration.stabilizationMode)
        #expect(restored.iso == String(fixture.desired.exposure.iso))
        #expect(restored.shutterTicks == String(fixture.desired.exposure.shutter.ticks))
        #expect(restored.output == ExplorationOutputCandidate.sampleWriter.rawValue)
    }

    @Test func candidatesAreScopedToSelectedCameraResolutionFPSAndLog() {
        let camera = ExplorationCameraDescription(id: "A", label: "A", isVirtual: false, formats: [
            .init(id: "24log", width: 3840, height: 2160, frameRateRanges: [24...24],
                  logEncodings: [.appleLog], stabilizationModes: ["off", "standard", "cinematic"]),
            .init(id: "30log2", width: 3840, height: 2160, frameRateRanges: [30...30],
                  logEncodings: [.appleLog2], stabilizationModes: ["off", "cinematicExtended"]),
            .init(id: "hd", width: 1920, height: 1080, frameRateRanges: [24...30],
                  logEncodings: [.appleLog], stabilizationModes: ["cinematicExtendedEnhanced"])
        ])
        #expect(ProductCaptureConfigurationMatcher.stabilizationModes(camera: camera, framesPerSecond: 24, log: .appleLog)
            == ["off", "standard", "cinematic"])
        #expect(ProductCaptureConfigurationMatcher.stabilizationModes(camera: camera, framesPerSecond: 30, log: .appleLog2)
            == ["off", "cinematicExtended"])
        #expect(ProductCaptureConfigurationMatcher.stabilizationModes(camera: camera, framesPerSecond: 30, log: .appleLog).isEmpty)
        #expect(ProductCaptureConfigurationMatcher.stabilizationModes(camera: nil, framesPerSecond: 24, log: .appleLog).isEmpty)
        #expect(ProductCaptureConfigurationMatcher.stabilizationAvailability(mode: "standard", camera: "A",
            framesPerSecond: 24, log: .appleLog, cameras: [camera]) == .formatCandidate)
        guard case .unsupported = ProductCaptureConfigurationMatcher.stabilizationAvailability(mode: "standard", camera: "A",
            framesPerSecond: 30, log: .appleLog2, cameras: [camera]) else { Issue.record("Other format must not confer support"); return }
        guard case .unconfirmed = ProductCaptureConfigurationMatcher.stabilizationAvailability(mode: "standard", camera: "B",
            framesPerSecond: 24, log: .appleLog, cameras: [camera]) else { Issue.record("Other camera must not confer support"); return }
        guard case .unsupported = ProductCaptureConfigurationMatcher.stabilizationAvailability(mode: "previewOptimized", camera: "A",
            framesPerSecond: 24, log: .appleLog, cameras: [camera]) else { Issue.record("Preview-only mode is not recording support"); return }
    }

    @Test func requestedPreferredAndActiveRemainSeparateAndFramingNeverInfersCrop() throws {
        let generation = try CaptureFixture().context.generation
        var framing = CaptureFramingState()
        let off = snapshot(generation: generation, sequence: 1, active: "off")
        #expect(!off.matchesRequest)
        #expect(framing.receive(off, generation: generation))
        let initialRevision = framing.revision
        #expect(framing.receive(snapshot(generation: generation, sequence: 3, active: "standard", zoom: 2), generation: generation))
        #expect(framing.revision > initialRevision)
        #expect(framing.snapshot?.matchesRequest == true)
        #expect(framing.snapshot?.zoom == 2)
        #expect(!framing.receive(off, generation: generation))
        let oldGeneration = CaptureGeneration(session: .init(rawValue: "old"), settings: 1)
        #expect(!framing.receive(snapshot(generation: oldGeneration, sequence: 99, active: "off"), generation: generation))
        #expect(framing.snapshot?.sequence == 3)
        #expect(framing.correctedFieldOfView == .unavailable(.apiDoesNotExpose))
        #expect(framing.previewMatchesRecording == .unqueried)
        #expect(framing.receive(snapshot(generation: generation, sequence: 4, active: nil), generation: generation))
        #expect(framing.snapshot?.activeMode.value == nil)
        #expect(framing.invalidation == .evidenceMismatch)
        framing.invalidate(.interrupted)
        #expect(framing.snapshot == nil)
        #expect(framing.invalidation == .interrupted)
        #expect(framing.correctedFieldOfView.value == nil)
        #expect(!framing.receive(snapshot(generation: generation, sequence: 3, active: "standard"), generation: generation))
        #expect(framing.snapshot == nil)
    }

    @Test func recordingAdmissionUsesPreparedScopeAndCurrentGeometry() throws {
        let fixture = try CaptureFixture()
        let configuration = try CaptureConfiguration(camera: "A", width: 3840, height: 2160, framesPerSecond: 24,
            codec: .proRes422LT, logEncoding: .appleLog, stabilizationMode: "standard")
        let desired = try DesiredCaptureSettings(configuration: configuration, exposure: fixture.desired.exposure, zoom: 1)
        let generation = fixture.context.generation
        let initial = snapshot(generation: generation, sequence: 1, active: "standard")
        #expect(initial.matchesRecordingRequest(desired, generation: generation, output: .sampleWriter,
                                                preparedFormatID: "synthetic-format"))
        #expect(!initial.matchesRecordingRequest(desired, generation: generation, output: .movieFile,
                                                 preparedFormatID: "synthetic-format"))
        #expect(!initial.matchesRecordingRequest(desired, generation: generation, output: .sampleWriter,
                                                 preparedFormatID: "previous-format"))
        let movedWhileReserveSuspended = snapshot(generation: generation, sequence: 2, active: "standard", zoom: 2)
        #expect(movedWhileReserveSuspended.matchesRequest)
        #expect(!movedWhileReserveSuspended.matchesRecordingRequest(desired, generation: generation,
            output: .sampleWriter, preparedFormatID: "synthetic-format"))
        #expect(!initial.matchesRecordingRequest(fixture.desired, generation: generation, output: .sampleWriter,
                                                 preparedFormatID: "synthetic-format"))
        var framing = CaptureFramingState()
        #expect(framing.receive(initial, generation: generation, desired: desired, output: .sampleWriter))
        #expect(framing.receive(movedWhileReserveSuspended, generation: generation, desired: fixture.desired, output: .movieFile))
        #expect(framing.snapshot == nil)
        #expect(framing.invalidation == .evidenceMismatch)
        #expect(!framing.receive(initial, generation: generation, desired: desired, output: .sampleWriter))
        #expect(framing.snapshot == nil)
    }

    private func snapshot(generation: CaptureGeneration, sequence: UInt64, active: String?, zoom: Double = 1) -> CaptureStabilizationSnapshot {
        .init(generation: generation, sequence: sequence, output: .sampleWriter, requestedMode: "standard", preferredMode: "standard",
              activeMode: active.map { .observed($0, at: .unavailable(.notMeasured), method: .direct(source: "synthetic")) }
                  ?? .unavailable(.notMeasured), connection: .ready, camera: "A", activePhysicalCamera: "wide",
              formatID: "synthetic-format", width: 3840, height: 2160, zoom: zoom, uncorrectedFieldOfView: 70)
    }
}
