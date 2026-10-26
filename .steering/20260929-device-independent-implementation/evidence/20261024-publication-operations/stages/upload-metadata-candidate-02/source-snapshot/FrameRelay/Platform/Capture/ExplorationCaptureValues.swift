import AVFoundation

nonisolated enum ExplorationCaptureValues {
    static let stabilizationModes: [(String, AVCaptureVideoStabilizationMode)] = [
        ("off", .off), ("standard", .standard), ("cinematic", .cinematic),
        ("cinematicExtended", .cinematicExtended), ("previewOptimized", .previewOptimized),
        ("cinematicExtendedEnhanced", .cinematicExtendedEnhanced)
    ]

    static func stabilizationName(_ value: AVCaptureVideoStabilizationMode) -> String? {
        stabilizationModes.first { $0.1 == value }?.0
    }

    static func codec(_ value: CaptureCodec) -> AVVideoCodecType {
        switch value {
        case .proRes422LT: return .proRes422LT
        case .proRes422: return .proRes422
        case .proRes422Proxy: return .proRes422Proxy
        }
    }

    static func colorSpace(_ value: CaptureLogEncoding) -> AVCaptureColorSpace {
        switch value {
        case .appleLog: return .appleLog
        case .appleLog2: return .appleLog2
        }
    }

    static func time(_ value: CMTime, clock: CaptureClock,
                     source: String, inferred: Bool = false,
                     evidence: [CaptureEvidenceID] = []) -> CaptureTimeObservation {
        guard value.isNumeric, value.timescale > 0 else { return .unavailable(.notMeasured) }
        guard !inferred || !evidence.isEmpty else { return .unavailable(.evidenceMissing) }
        do {
            let timestamp = try CaptureTimestamp(
                value: .init(ticks: value.value, timescale: value.timescale), clock: clock,
                timelineEpoch: value.epoch, resolution: .init(ticks: 1, timescale: value.timescale),
                uncertainty: nil)
            let method: CaptureObservationMethod = inferred
                ? .inferred(method: source, evidence: evidence) : .direct(source: source)
            return .observed(timestamp, method)
        } catch { return .unavailable(.evidenceMismatch) }
    }

    static func now() -> CaptureTimeObservation {
        time(CMClockGetTime(CMClockGetHostTimeClock()), clock: .monotonic(reference: "host"), source: "host-clock")
    }
}
