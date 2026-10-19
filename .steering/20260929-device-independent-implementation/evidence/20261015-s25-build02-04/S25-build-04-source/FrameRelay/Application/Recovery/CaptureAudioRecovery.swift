/// Values come from a bound trial. They are not product retry/grace defaults.
nonisolated struct CaptureAudioRecoveryPolicy: Equatable, Sendable {
    let maximumAttempts: Int
    let attemptTimeout: CaptureRationalTime

    init(maximumAttempts: Int, attemptTimeout: CaptureRationalTime) throws {
        guard maximumAttempts > 0, attemptTimeout.ticks > 0 else { throw CaptureContractError.invalidValue }
        self.maximumAttempts = maximumAttempts
        self.attemptTimeout = attemptTimeout
    }
}

nonisolated enum CaptureAudioRecoveryPhase: Equatable, Sendable {
    case idle
    case attempting(Int)
    case readyForUserREC(route: String)
    case exhausted(CaptureAudioFailure)
}

nonisolated enum CaptureAudioRecoveryOutcome: Equatable, Sendable {
    case validInput(route: String)
    case failed(CaptureAudioFailure)
}

nonisolated struct CaptureAudioRecoveryAttempt: Equatable, Sendable {
    let context: CaptureContext
    let ordinal: Int
    let timeout: CaptureRationalTime
}

/// Only audio retries are emitted. Clock scheduling and recovery I/O belong to an adapter.
/// A successful retry can never emit a recording command.
nonisolated struct CaptureAudioRecovery: Sendable {
    let context: CaptureContext
    let policy: CaptureAudioRecoveryPolicy
    private(set) var phase: CaptureAudioRecoveryPhase = .idle

    mutating func begin(after failure: CaptureAudioFailure) throws -> CaptureAudioRecoveryAttempt {
        guard phase == .idle else { throw CaptureContractError.wrongStage }
        // Permission denial requires a user settings change, not repeated audio reconfiguration.
        if failure == .permissionDenied {
            phase = .exhausted(failure)
            throw CaptureContractError.wrongStage
        }
        phase = .attempting(1)
        return CaptureAudioRecoveryAttempt(context: context, ordinal: 1, timeout: policy.attemptTimeout)
    }

    mutating func complete(_ attempt: CaptureAudioRecoveryAttempt,
                           outcome: CaptureAudioRecoveryOutcome) throws -> CaptureAudioRecoveryAttempt? {
        guard attempt.context == context else { throw CaptureContractError.wrongContext }
        guard case .attempting(let current) = phase, current == attempt.ordinal,
              attempt.timeout == policy.attemptTimeout else { throw CaptureContractError.duplicateOrOutOfOrder }
        switch outcome {
        case .validInput(let route):
            phase = .readyForUserREC(route: route)
            return nil
        case .failed(let failure):
            guard current < policy.maximumAttempts, failure != .permissionDenied else {
                phase = .exhausted(failure)
                return nil
            }
            let next = current + 1
            phase = .attempting(next)
            return CaptureAudioRecoveryAttempt(context: context, ordinal: next, timeout: policy.attemptTimeout)
        }
    }
}
