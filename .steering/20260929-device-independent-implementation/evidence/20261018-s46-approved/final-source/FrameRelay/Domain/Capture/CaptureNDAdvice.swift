import Foundation

/// Identifies the actual input signal, never the recording wish or preview transform.
nonisolated enum CaptureNDSignal: String, CaseIterable, Sendable {
    case rec709, sRGB, appleLog, appleLog2
}

nonisolated enum CaptureNDDirection: Equatable, Sendable {
    case darker, lighter, acceptable, difficult, pending
}
nonisolated enum CaptureNDReason: Equatable, Sendable {
    case evaluating, stopped, stale, outOfOrder, contextChanged, policyUnavailable
    case unknownSignal, insufficientSignal, saturated, selectIntent, selectPeople, missingPeople
    case broadHighlights, broadShadows, selectedPeopleBright, selectedPeopleDark, withinReference
    case conflictingPeople, peopleAndBackgroundConflict
}
nonisolated struct CaptureNDAdvice: Equatable, Sendable {
    let direction: CaptureNDDirection
    let reasons: [CaptureNDReason]
    static func pending(_ reason: CaptureNDReason) -> Self { .init(direction: .pending, reasons: [reason]) }
}

/// Code-domain screening bands, NOT calibrated exposure, IRE, headroom, skin-tone,
/// RGB-equality or WB targets. Every supported signal has its own replaceable band.
nonisolated struct CaptureNDBand: Equatable, Sendable {
    let low: Double
    let high: Double
    let broadFraction: Double
    let minimumSpread: Double
}
nonisolated struct CaptureNDPolicy: Equatable, Sendable {
    let version: String
    let maximumResultAge: TimeInterval
    let minimumFrameInterval: TimeInterval
    let maximumSubjectAge: TimeInterval
    let bands: [CaptureNDSignal: CaptureNDBand]

    var isValid: Bool {
        !version.isEmpty && [maximumResultAge, minimumFrameInterval, maximumSubjectAge].allSatisfy { $0.isFinite && $0 > 0 }
            && !bands.isEmpty && bands.values.allSatisfy {
                [$0.low, $0.high, $0.broadFraction, $0.minimumSpread].allSatisfy(\.isFinite)
                && $0.low > 0 && $0.high < 1 && $0.low < $0.high
                && $0.broadFraction > 0 && $0.broadFraction <= 1 && $0.minimumSpread > 0 && $0.minimumSpread < 1
            }
    }

    /// Provisional reference screening only; physical ND density is not measured.
    /// S46 v1 reference use agreed 2026-10-18. Signal-specific code values avoid any
    /// transfer inversion or universal clip-rate/EV target. Device calibration pending.
    static func provisionalV1(maximumResultAge: TimeInterval) -> Self {
        .init(version: "s46-code-domain-reference-v1-uncalibrated", maximumResultAge: maximumResultAge,
              minimumFrameInterval: 0.2, maximumSubjectAge: 0.8, bands: [
                .rec709: .init(low: 0.20, high: 0.75, broadFraction: 0.35, minimumSpread: 0.02),
                .sRGB: .init(low: 0.22, high: 0.78, broadFraction: 0.35, minimumSpread: 0.02),
                .appleLog: .init(low: 0.20, high: 0.68, broadFraction: 0.35, minimumSpread: 0.02),
                .appleLog2: .init(low: 0.20, high: 0.68, broadFraction: 0.35, minimumSpread: 0.02)])
    }
}

nonisolated struct CaptureNDWhiteBalance: Equatable, Sendable {
    enum Mode: Equatable, Sendable { case automatic, measuring, locked, unknown }
    let mode: Mode
    let red: Double
    let green: Double
    let blue: Double
    var isValid: Bool { mode != .unknown && [red, green, blue].allSatisfy { $0.isFinite && $0 > 0 } }
}
nonisolated struct CaptureNDContext: Equatable, Sendable {
    let generation: CaptureGeneration
    let framingRevision: UInt64
    let selectionRevision: UInt64
    let whiteBalanceRevision: UInt64
    let intent: CaptureShootingIntent?
    let analysisRevision: UInt64
    init(generation: CaptureGeneration, framingRevision: UInt64, selectionRevision: UInt64,
         whiteBalanceRevision: UInt64, intent: CaptureShootingIntent?, analysisRevision: UInt64 = 0) {
        self.generation = generation; self.framingRevision = framingRevision; self.selectionRevision = selectionRevision
        self.whiteBalanceRevision = whiteBalanceRevision; self.intent = intent; self.analysisRevision = analysisRevision
    }
}
nonisolated struct CaptureNDRegionEvidence: Equatable, Sendable {
    let person: CapturePersonID?
    let sampleCount: Int
    let lower: Double
    let median: Double
    let upper: Double
    let darkFraction: Double
    let brightFraction: Double
    let clippedFraction: Double
}
nonisolated struct CaptureNDEvidence: Equatable, Sendable {
    let signal: CaptureNDSignal
    let policyVersion: String
    let scene: CaptureNDRegionEvidence
    let people: [CaptureNDRegionEvidence]
    let background: CaptureNDRegionEvidence?
    /// Explicit provenance: these are encoded input statistics, not display IRE or stops.
    let isCalibrated = false
}
nonisolated struct CaptureNDResult: Equatable, Sendable {
    let context: CaptureNDContext
    let sequence: UInt64
    let observedAt: TimeInterval
    let advice: CaptureNDAdvice
    let evidence: CaptureNDEvidence?
}
nonisolated struct CaptureNDSnapshot: Equatable, Sendable {
    let context: CaptureNDContext
    let sequence: UInt64
    let result: CaptureNDResult?
    let advice: CaptureNDAdvice
}

/// No capture command exists at this boundary. It cannot change exposure or gate REC.
nonisolated struct CaptureNDSession: Sendable {
    private(set) var context: CaptureNDContext
    private(set) var validAfter: TimeInterval
    private(set) var result: CaptureNDResult?
    private(set) var advice = CaptureNDAdvice.pending(.evaluating)
    private(set) var highestSequence: UInt64 = 0
    private(set) var lastObservedAt: TimeInterval?
    private var inputSubmittedSinceInvalidation = false
    let policy: CaptureNDPolicy

    /// A conservative observation boundary, not evidence of frame-specific WB gains.
    init(context: CaptureNDContext, policy: CaptureNDPolicy, validAfter: TimeInterval) {
        self.context = context; self.policy = policy
        self.validAfter = validAfter.isFinite ? validAfter : .infinity
    }
    func acceptsInput(observedAt: TimeInterval, now: TimeInterval) -> Bool {
        policy.isValid && observedAt.isFinite && now.isFinite && observedAt >= validAfter
            && observedAt <= now && now - observedAt <= policy.maximumResultAge
    }
    private mutating func advanceValidityBoundary(to now: TimeInterval) {
        validAfter = now.isFinite ? max(validAfter, now) : .infinity
    }
    mutating func willSubmitInput() { inputSubmittedSinceInvalidation = true }
    mutating func update(_ next: CaptureNDContext, now: TimeInterval) {
        guard next != context else { return }
        context = next; advanceValidityBoundary(to: now); inputSubmittedSinceInvalidation = false; invalidate(.contextChanged)
    }
    mutating func invalidate(_ reason: CaptureNDReason) { result = nil; advice = .pending(reason) }
    mutating func invalidateInput(_ reason: CaptureNDReason, now: TimeInterval) {
        guard inputSubmittedSinceInvalidation || advice != .pending(reason) else { return }
        inputSubmittedSinceInvalidation = false
        advanceValidityBoundary(to: now)
        context = .init(generation: context.generation, framingRevision: context.framingRevision,
            selectionRevision: context.selectionRevision, whiteBalanceRevision: context.whiteBalanceRevision,
            intent: context.intent, analysisRevision: context.analysisRevision + 1)
        invalidate(reason)
    }
    @discardableResult mutating func receive(_ value: CaptureNDResult, now: TimeInterval) -> Bool {
        guard value.context == context else { return false }
        guard value.sequence > highestSequence, lastObservedAt.map({ value.observedAt >= $0 }) ?? true else {
            invalidate(.outOfOrder); return false
        }
        highestSequence = value.sequence
        guard acceptsInput(observedAt: value.observedAt, now: now) else { invalidate(.stale); return false }
        lastObservedAt = value.observedAt
        result = value; advice = value.advice; return true
    }
    @discardableResult mutating func expire(now: TimeInterval) -> Bool {
        guard let result, now - result.observedAt > policy.maximumResultAge else { return false }
        invalidate(.stale); return true
    }
    func snapshot(sequence: UInt64) -> CaptureNDSnapshot { .init(context: context, sequence: sequence, result: result, advice: advice) }
}
