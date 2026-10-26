import Foundation

/// Evaluation controls, not adopted device-quality tolerances. Rates use the SDK's
/// powers-of-two-per-second scale; all factors refer to the selected capture device.
nonisolated struct CaptureZoomPolicy: Equatable, Sendable {
    let version: String
    let rate: Double
    let stopTolerance: Double
    let snapTolerance: Double
    var isDeviceAdopted: Bool = false

    static let provisionalV1 = Self(version: "s47-provisional-v1", rate: 0.5,
        stopTolerance: 0.005, snapTolerance: 0.05)

    var isValid: Bool {
        !version.isEmpty && rate.isFinite && rate > 0 && stopTolerance.isFinite
            && stopTolerance >= 0 && snapTolerance.isFinite && snapTolerance >= 0
    }

    func assistedTarget(_ requested: Double, range: ClosedRange<Double>, stops: [CaptureZoomStop]) -> Double? {
        guard isValid, requested.isFinite, range.contains(requested) else { return nil }
        return stops.filter { range.contains($0.factor) && abs($0.factor - requested) <= snapTolerance }
            .min { abs($0.factor - requested) < abs($1.factor - requested) }?.factor ?? requested
    }
}

nonisolated enum CaptureZoomStopBasis: String, Equatable, Sendable {
    case nativeMinimum, lensSwitch, secondaryNativeResolution, upscaleThreshold
}

/// SDK-derived candidates for this exact snapshot; none certifies video quality.
nonisolated struct CaptureZoomStop: Equatable, Sendable, Identifiable {
    let factor: Double
    let basis: CaptureZoomStopBasis
    var id: String { "\(basis.rawValue)-\(factor)" }
}

nonisolated struct CaptureZoomContext: Equatable, Sendable {
    let generation: CaptureGeneration
    let revision: UInt64
}

nonisolated enum CaptureZoomPhase: Equatable, Sendable {
    case idle
    case moving(target: Double)
    case stopped
    case failed(String)

    var isMoving: Bool { if case .moving = self { true } else { false } }
}

nonisolated struct CaptureZoomSnapshot: Equatable, Sendable {
    let context: CaptureZoomContext
    let sequence: UInt64
    let stabilization: CaptureStabilizationSnapshot
    let range: ClosedRange<Double>
    let stops: [CaptureZoomStop]
    let phase: CaptureZoomPhase
    /// Current session intention and SDK readback. The recording's initial intent
    /// remains immutable; these values become the next REC's readiness inputs.
    let desired: DesiredCaptureSettings
    let applied: AppliedCaptureSettings
    let lens: CaptureLensState
    /// Echo of the explicit command that owns these session values. Ambient
    /// observations carry nil and cannot rewrite the user's current session wish.
    var operation: UUID? = nil
}

nonisolated enum CaptureZoomCommand: Equatable, Sendable {
    case move(target: Double)
    case stop
    case manualISO(Double)
    case switchLens(String)
}

nonisolated struct CaptureZoomRequest: Equatable, Sendable {
    let context: CaptureZoomContext
    let command: CaptureZoomCommand
    /// Monotonic within a preparation generation. Unlike framing revision this
    /// orders user commands even while a prior SDK operation is suspended.
    var sequence: UInt64 = 0
    var operation: UUID = UUID()
}

/// UI-only ratio guide. Wider views contain unobserved areas: never invent pixels
/// or treat unknown stabilization crop as the recorded field of view.
nonisolated struct CaptureZoomForecast: Equatable, Sendable {
    let context: CaptureZoomContext
    let framingRevision: UInt64
    let sourceZoom: Double
    let target: Double
    var isWider: Bool { target < sourceZoom }
    var visibleFraction: Double { min(sourceZoom, target) / max(sourceZoom, target) }
    var guide: CaptureZoomGuideRect {
        .init(x: (1 - visibleFraction) / 2, y: (1 - visibleFraction) / 2,
              width: visibleFraction, height: visibleFraction)
    }
}

nonisolated struct CaptureZoomGuideRect: Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

nonisolated struct CaptureZoomState: Equatable, Sendable {
    private(set) var snapshot: CaptureZoomSnapshot?
    private(set) var forecast: CaptureZoomForecast?
    private var generation: CaptureGeneration?
    private var highestSequence: UInt64?
    private var highestRevision: UInt64?

    @discardableResult
    mutating func receive(_ value: CaptureZoomSnapshot, generation: CaptureGeneration) -> Bool {
        guard value.context.generation == generation, value.applied.generation == generation,
              value.stabilization.generation == generation,
              self.generation != generation || (highestSequence.map { value.sequence > $0 } ?? true),
              self.generation != generation || (highestRevision.map { value.context.revision >= $0 } ?? true),
              value.range.lowerBound.isFinite, value.range.upperBound.isFinite, value.range.lowerBound > 0,
              value.applied.values.value.map({ $0.zoom.isFinite && $0.zoom > 0 }) ?? true else { return false }
        self.generation = generation; highestSequence = value.sequence; highestRevision = value.context.revision
        if snapshot?.context != value.context || snapshot?.applied.values.value != value.applied.values.value || value.phase.isMoving {
            forecast = nil
        }
        snapshot = value
        return true
    }

    mutating func select(_ target: Double, framing: CaptureFramingState, policy: CaptureZoomPolicy) {
        forecast = nil
        guard let snapshot, !snapshot.phase.isMoving, let actual = snapshot.applied.values.value,
              let source = framing.snapshot, source == snapshot.stabilization,
              source.matchesRequest, source.zoom == actual.zoom, policy.isValid,
              target.isFinite, snapshot.range.contains(target) else { return }
        forecast = .init(context: snapshot.context, framingRevision: framing.revision,
                         sourceZoom: actual.zoom, target: target)
    }

    mutating func invalidateForecast() { forecast = nil }
    mutating func invalidate() {
        snapshot = nil; forecast = nil
        // Keep high-water marks so delayed observations cannot resurrect a guide.
    }
}
