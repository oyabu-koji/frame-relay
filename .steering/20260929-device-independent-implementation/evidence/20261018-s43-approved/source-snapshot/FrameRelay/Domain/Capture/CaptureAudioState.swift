nonisolated struct CaptureAudioLevel: Equatable, Sendable, Codable {
    let linearAmplitude: Double
    let isClipping: Bool

    init(linearAmplitude: Double, isClipping: Bool) throws {
        guard linearAmplitude.isFinite, linearAmplitude >= 0 else {
            throw CaptureContractError.invalidValue
        }
        self.linearAmplitude = linearAmplitude
        self.isClipping = isClipping
    }
}

nonisolated enum CaptureAudioFailure: Equatable, Sendable, Codable {
    case permissionDenied
    case confirmedNoSamples(CaptureEvidenceID)
    case routeInterrupted(CaptureEvidenceID)
    case writerFailed(CaptureEvidenceID)
}

nonisolated enum CaptureAudioInputState: Equatable, Sendable, Codable {
    case checking
    case valid(route: String)
    case failed(CaptureAudioFailure)
    case recovering(attempt: Int)
}

nonisolated struct CaptureSampleSpan: Equatable, Sendable, Codable {
    let first: CaptureTimeObservation
    let last: CaptureTimeObservation
    let count: UInt64
}

nonisolated enum CaptureAudioArrival: Equatable, Sendable, Codable {
    case unobserved
    case received(CaptureSampleSpan)
    case unavailable(CaptureUnavailableReason)
}

nonisolated enum CaptureAudioWriting: Equatable, Sendable, Codable {
    case notStarted
    case accepted(CaptureSampleSpan)
    case completed(CaptureSampleSpan)
    case failed(CaptureAudioFailure)
    case unavailable(CaptureUnavailableReason)
}

/// None of these axes may be inferred from the audio meter alone.
nonisolated struct CaptureAudioState: Equatable, Sendable, Codable {
    var level: CaptureObservation<CaptureAudioLevel>
    var input: CaptureAudioInputState
    var arrival: CaptureAudioArrival
    var writing: CaptureAudioWriting

    var confirmedFailure: CaptureAudioFailure? {
        if case .failed(let failure) = input { return failure }
        if case .failed(let failure) = writing { return failure }
        return nil
    }
}

nonisolated struct CaptureWhiteBalanceGains: Equatable, Sendable, Codable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) throws {
        guard [red, green, blue].allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw CaptureContractError.invalidValue
        }
        self.red = red
        self.green = green
        self.blue = blue
    }
}

nonisolated struct CaptureWhiteBalanceLock: Equatable, Sendable, Codable {
    let gains: CaptureWhiteBalanceGains
    let measuredAt: CaptureTimeObservation
    let appliedAt: CaptureTimeObservation
}

nonisolated enum CaptureWhiteBalanceState: Equatable, Sendable, Codable {
    case automatic
    case locking(CaptureCommandToken)
    case locked(CaptureWhiteBalanceLock)
    case refreshing(CaptureCommandToken, previous: CaptureWhiteBalanceLock)
    case restoringAutomatic(CaptureCommandToken)
    case unavailable(CaptureUnavailableReason)
}
