import Foundation

/// Persisted wishes only. Hardware readback, capability and WB locks are never restored as facts.
nonisolated struct ProductCapturePreferences: Equatable, Sendable, Codable {
    var desired: DesiredCaptureSettings?
    var outputCandidate: ExplorationOutputCandidate?

    init(desired: DesiredCaptureSettings? = nil, outputCandidate: ExplorationOutputCandidate? = nil) {
        self.desired = desired
        self.outputCandidate = outputCandidate
    }

    var isValid: Bool {
        guard let desired else { return true }
        let c = desired.configuration
        let e = desired.exposure
        return !c.camera.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && c.width == 3840 && c.height == 2160 && [24, 30].contains(c.framesPerSecond)
            && !c.stabilizationMode.isEmpty && e.shutter.ticks > 0 && e.shutter.timescale > 0
            && e.shutter.seconds.isFinite && e.iso.isFinite && e.iso > 0
            && (e.aperture.map { $0.isFinite && $0 > 0 } ?? true)
            && desired.zoom.isFinite && desired.zoom > 0
    }
}

nonisolated enum ProductCapturePreferenceError: Error, Equatable, Sendable {
    case invalidSettings
    case unknownSchema
    case corruptStore
}
