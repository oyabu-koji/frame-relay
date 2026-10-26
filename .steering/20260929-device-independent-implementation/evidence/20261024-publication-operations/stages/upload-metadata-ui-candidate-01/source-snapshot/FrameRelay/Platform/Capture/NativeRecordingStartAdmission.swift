/// The SDK owner calls this before reserve/start side effects. Rejection is terminal only
/// for a new start belonging to its current, successfully locked capture context.
nonisolated struct NativeRecordingStartAdmission: Sendable {
    enum Decision: Equatable, Sendable {
        case admitted
        case rejected(CaptureIOEvent?)
    }

    private var attempted: Set<CaptureContext> = []

    mutating func admit(token: CaptureCommandToken, intentContext: CaptureContext,
                        generation: CaptureGeneration?, activeToken: CaptureCommandToken?,
                        ownsWhiteBalanceLock: Bool, whiteBalanceLocked: Bool,
                        sessionRunning: Bool, audioActive: Bool,
                        observedAt: CaptureTimeObservation) -> Decision {
        guard token.context.generation == generation, token.context == intentContext,
              activeToken == nil, ownsWhiteBalanceLock, !attempted.contains(token.context) else {
            // Stale/duplicate/unowned requests say nothing about another recorder's termination.
            return .rejected(nil)
        }
        attempted.insert(token.context)
        guard whiteBalanceLocked, sessionRunning, audioActive else {
            return .rejected(.recordingEnded(token, .init(writer: .notStarted, ceasedAt: observedAt,
                lastVideo: .unavailable(.notMeasured), lastAudio: .unavailable(.notMeasured))))
        }
        return .admitted
    }
}
