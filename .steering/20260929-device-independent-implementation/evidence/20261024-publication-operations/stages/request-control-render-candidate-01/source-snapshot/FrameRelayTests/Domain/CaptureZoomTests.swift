import Foundation
import Testing
@testable import FrameRelay

struct CaptureZoomTests {
    @Test func forecastUsesRatiosWithoutChangingCaptureAndWiderGuideMarksOnlyKnownArea() throws {
        let fixture = try CaptureFixture()
        let snapshot = try zoomTestSnapshot(fixture: fixture, sequence: 1, revision: 1)
        var framing = CaptureFramingState()
        framing.receive(snapshot.stabilization, generation: fixture.context.generation)
        var state = CaptureZoomState()
        state.receive(snapshot, generation: fixture.context.generation)
        state.select(2, framing: framing, policy: .provisionalV1)
        #expect(state.snapshot == snapshot)
        #expect(state.forecast?.guide == .init(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        #expect(state.forecast?.isWider == false)
        let wider = CaptureZoomForecast(context: snapshot.context, framingRevision: 1, sourceZoom: 2, target: 1)
        #expect(wider.isWider)
        #expect(wider.guide == state.forecast?.guide)
    }

    @Test func nearCandidateIsSuggestedWithoutChangingChosenTargetOrClaimingQuality() throws {
        let fixture = try CaptureFixture()
        let snapshot = try zoomTestSnapshot(fixture: fixture, sequence: 1, revision: 1)
        var framing = CaptureFramingState()
        framing.receive(snapshot.stabilization, generation: fixture.context.generation)
        var state = CaptureZoomState()
        state.receive(snapshot, generation: fixture.context.generation)
        state.select(1.98, framing: framing, policy: .provisionalV1)
        #expect(state.forecast?.target == 1.98)
        #expect(CaptureZoomPolicy.provisionalV1.assistedTarget(1.98, range: snapshot.range, stops: snapshot.stops) == 2)
        #expect(CaptureZoomPolicy.provisionalV1.assistedTarget(1.7, range: snapshot.range, stops: snapshot.stops) == 1.7)
        #expect(CaptureZoomPolicy.provisionalV1.assistedTarget(.nan, range: snapshot.range, stops: snapshot.stops) == nil)
        #expect(CaptureZoomPolicy.provisionalV1.assistedTarget(9, range: snapshot.range, stops: snapshot.stops) == nil)
    }

    @Test func changedFramingAndInvalidationKeepSequenceAndRevisionHighWaterMarks() throws {
        let fixture = try CaptureFixture()
        let original = try zoomTestSnapshot(fixture: fixture, sequence: 4, revision: 2)
        var framing = CaptureFramingState()
        framing.receive(original.stabilization, generation: fixture.context.generation)
        var state = CaptureZoomState()
        state.receive(original, generation: fixture.context.generation)
        state.select(2, framing: framing, policy: .provisionalV1)
        let moved = try zoomTestSnapshot(fixture: fixture, sequence: 5, revision: 3, zoom: 1.5)
        let acceptsMoved = state.receive(moved, generation: fixture.context.generation)
        #expect(acceptsMoved)
        #expect(state.forecast == nil)
        state.invalidate()
        let acceptsOriginal = state.receive(original, generation: fixture.context.generation)
        #expect(!acceptsOriginal)
        let oldRevision = try zoomTestSnapshot(fixture: fixture, sequence: 90, revision: 1)
        let acceptsOldRevision = state.receive(oldRevision, generation: fixture.context.generation)
        #expect(!acceptsOldRevision)
        let other = CaptureGeneration(session: .init(rawValue: "old-session"), settings: 1)
        let acceptsOtherGeneration = state.receive(try zoomTestSnapshot(fixture: fixture, generation: other,
            sequence: 100, revision: 100), generation: fixture.context.generation)
        #expect(!acceptsOtherGeneration)
        #expect(state.snapshot == nil)
    }

    @Test func isoCompensationIsBoundedReturnsToBaselineAndUsesLatestManualRevision() throws {
        let policy = CaptureLensISOPolicy(version: "synthetic-policy", maximumStops: 1)
        let initial = CaptureLensISOBaseline(iso: 160, aperture: 2, manualRevision: 1)
        #expect(policy.adjustment(baseline: initial, aperture: 4, limits: 100...800)?.iso == 320)
        #expect(policy.adjustment(baseline: initial, aperture: 4, limits: 100...800)?.wasLimited == true)
        #expect(policy.adjustment(baseline: initial, aperture: 2, limits: 100...800)?.iso == 160)
        let manual = CaptureLensISOBaseline(iso: 240, aperture: 4, manualRevision: 2)
        let result = try #require(policy.adjustment(baseline: manual, aperture: 2, limits: 100...800))
        #expect(result.iso == 120)
        #expect(result.manualRevision == 2)
        #expect(policy.adjustment(baseline: initial, aperture: 4, limits: 500...800) == nil)
        #expect(policy.adjustment(baseline: initial, aperture: .nan, limits: 100...800) == nil)
        #expect(CaptureLensISOPolicy(version: "overflow", maximumStops: 10_000)
            .adjustment(baseline: initial, aperture: 4, limits: 100...800) == nil)
    }
}

nonisolated func zoomTestSnapshot(fixture: CaptureFixture, generation: CaptureGeneration? = nil,
                                 sequence: UInt64, revision: UInt64, zoom: Double = 1,
                                 iso: Double = 160, phase: CaptureZoomPhase = .idle,
                                 operation: UUID? = nil, unavailable: Bool = false,
                                 formatID: String = "synthetic-format") throws -> CaptureZoomSnapshot {
    let generation = generation ?? fixture.context.generation
    let desired = try DesiredCaptureSettings(configuration: fixture.desired.configuration,
        exposure: .init(shutter: fixture.desired.exposure.shutter, iso: iso, aperture: nil), zoom: zoom)
    let config = desired.configuration
    let stabilization = CaptureStabilizationSnapshot(generation: generation, sequence: sequence,
        output: .sampleWriter, requestedMode: config.stabilizationMode, preferredMode: config.stabilizationMode,
        activeMode: .observed(config.stabilizationMode, at: fixture.time, method: .direct(source: "synthetic")),
        connection: .ready, camera: config.camera, activePhysicalCamera: "synthetic-wide", formatID: formatID,
        width: config.width, height: config.height, zoom: zoom, uncorrectedFieldOfView: 70)
    let applied = AppliedCaptureSettings(generation: generation, operation: .init(rawValue: "synthetic-control"),
        values: unavailable ? .unavailable(.notMeasured) : .observed(
            .init(configuration: config, exposure: desired.exposure, zoom: zoom), at: fixture.time,
            method: .direct(source: "synthetic-control")))
    return .init(context: .init(generation: generation, revision: revision), sequence: sequence,
        stabilization: stabilization, range: 1...3,
        stops: [.init(factor: 1, basis: .nativeMinimum), .init(factor: 2, basis: .secondaryNativeResolution)],
        phase: phase, desired: desired, applied: applied,
        lens: .init(activeCamera: "synthetic-wide", aperture: 2, iso: unavailable ? nil : iso,
            baseline: .init(iso: iso, aperture: 2, manualRevision: revision), adjustment: nil,
            switchingSupported: false, constraint: "synthetic-unconfirmed-route"), operation: operation)
}
