import Foundation

/// A replaceable compensation proposal. Composition must inject it only after
/// agreement; this type itself does not authorize product adoption.
nonisolated struct CaptureLensISOPolicy: Equatable, Sendable {
    let version: String
    let maximumStops: Double
    var isValid: Bool { !version.isEmpty && maximumStops.isFinite && maximumStops >= 0 }

    func adjustment(baseline: CaptureLensISOBaseline, aperture: Double,
                    limits: ClosedRange<Double>) -> CaptureLensISOAdjustment? {
        guard isValid, baseline.iso.isFinite, baseline.iso > 0,
              baseline.aperture.isFinite, baseline.aperture > 0,
              aperture.isFinite, aperture > 0, limits.lowerBound > 0,
              limits.upperBound.isFinite else { return nil }
        let requested = baseline.iso * pow(aperture / baseline.aperture, 2)
        guard requested.isFinite else { return nil }
        let factor = pow(2, maximumStops)
        guard factor.isFinite, (baseline.iso * factor).isFinite else { return nil }
        let lower = max(baseline.iso / factor, limits.lowerBound)
        let upper = min(baseline.iso * factor, limits.upperBound)
        guard lower <= upper else { return nil }
        let iso = min(max(requested, lower), upper)
        return .init(iso: iso, wasLimited: iso != requested, policyVersion: version,
                     manualRevision: baseline.manualRevision)
    }
}

nonisolated struct CaptureLensISOBaseline: Equatable, Sendable {
    let iso: Double
    let aperture: Double
    let manualRevision: UInt64
}

nonisolated struct CaptureLensISOAdjustment: Equatable, Sendable {
    let iso: Double
    let wasLimited: Bool
    let policyVersion: String
    let manualRevision: UInt64
}

nonisolated struct CaptureLensState: Equatable, Sendable {
    let activeCamera: String?
    let aperture: Double?
    let iso: Double?
    let baseline: CaptureLensISOBaseline?
    let adjustment: CaptureLensISOAdjustment?
    let switchingSupported: Bool
    let constraint: String?
    var candidates: [CaptureLensCandidate] = []
    var isManualExposure: Bool = true
    var shutterSeconds: Double? = nil
    var switchingBehaviorLocked: Bool = false
}

nonisolated struct CaptureLensCandidate: Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let targetZoom: Double
    let available: Bool
    let constraint: String?
}
