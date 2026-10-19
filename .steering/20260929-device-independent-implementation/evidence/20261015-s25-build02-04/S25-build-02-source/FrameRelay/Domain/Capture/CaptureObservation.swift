nonisolated enum CaptureUnavailableReason: Equatable, Sendable, Codable {
    case notMeasured
    case apiDoesNotExpose
    case permissionDenied
    case resourceUnavailable
    case interrupted
    case unsupported
    case evidenceMissing
    case evidenceMismatch
    case adapterFailure(code: String)
}

nonisolated enum CaptureCapability<Value: Equatable & Sendable>: Equatable, Sendable {
    case unqueried
    case supported(Value)
    case unsupported(CaptureUnavailableReason)
    case unavailable(CaptureUnavailableReason)
}

/// Exact ticks and scale are retained; no conversion to wall-clock floating point.
nonisolated struct CaptureRationalTime: Equatable, Hashable, Sendable, Codable {
    let ticks: Int64
    let timescale: Int32

    init(ticks: Int64, timescale: Int32) throws {
        guard timescale > 0 else { throw CaptureContractError.invalidValue }
        self.ticks = ticks
        self.timescale = timescale
    }

    var seconds: Double { Double(ticks) / Double(timescale) }

    static func == (lhs: Self, rhs: Self) -> Bool {
        let a = lhs.reducedFraction
        let b = rhs.reducedFraction
        return a.0 == b.0 && a.1 == b.1
    }

    func hash(into hasher: inout Hasher) {
        let reduced = reducedFraction
        hasher.combine(reduced.0)
        hasher.combine(reduced.1)
    }

    private var reducedFraction: (Int64, Int32) {
        // Decoded invalid scales stay invalid; they cannot normalize to a valid time.
        guard timescale > 0 else { return (ticks, timescale) }
        var a = ticks.magnitude
        var b = UInt64(timescale)
        while b != 0 { let remainder = a % b; a = b; b = remainder }
        // The divisor is bounded by the positive Int32 scale, including ticks == Int64.min.
        return (ticks / Int64(a), timescale / Int32(a))
    }
}

nonisolated enum CaptureClock: Equatable, Sendable, Codable {
    case mediaPTS(stream: String)
    case captureSession(CaptureSessionID)
    case captureDevice(camera: String)
    case monotonic(reference: String)
    case wallClock(reference: String)
}

nonisolated enum CaptureObservationMethod: Equatable, Sendable, Codable {
    case direct(source: String)
    case inferred(method: String, evidence: [CaptureEvidenceID])
}

nonisolated struct CaptureTimestamp: Equatable, Sendable, Codable {
    let value: CaptureRationalTime
    let clock: CaptureClock
    /// Preserve CMTime epoch / source timeline identity separately from elapsed ticks.
    let timelineEpoch: Int64
    let resolution: CaptureRationalTime
    let uncertainty: CaptureRationalTime?

    init(value: CaptureRationalTime, clock: CaptureClock, timelineEpoch: Int64,
         resolution: CaptureRationalTime, uncertainty: CaptureRationalTime?) throws {
        guard resolution.ticks > 0, uncertainty.map({ $0.ticks >= 0 }) ?? true else {
            throw CaptureContractError.invalidValue
        }
        self.value = value
        self.clock = clock
        self.timelineEpoch = timelineEpoch
        self.resolution = resolution
        self.uncertainty = uncertainty
    }
}

nonisolated enum CaptureTimeObservation: Equatable, Sendable, Codable {
    case observed(CaptureTimestamp, CaptureObservationMethod)
    case unavailable(CaptureUnavailableReason)
}

nonisolated enum CaptureObservation<Value: Equatable & Sendable>: Equatable, Sendable {
    case observed(Value, at: CaptureTimeObservation, method: CaptureObservationMethod)
    case unavailable(CaptureUnavailableReason)

    var value: Value? {
        guard case .observed(let value, _, _) = self else { return nil }
        return value
    }
}

// Persistence adapters must validate decoded values before use.
extension CaptureCapability: Codable where Value: Codable {}
extension CaptureObservation: Codable where Value: Codable {}
