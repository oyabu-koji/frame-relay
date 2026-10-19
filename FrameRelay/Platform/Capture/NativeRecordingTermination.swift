/// Recording failure facts outlive WB recovery during STOP. Only a new recorder
/// clears them; a successful lock or file finalization is not a successful take.
nonisolated struct NativeRecordingTermination: Sendable {
    private var failure: CaptureUnavailableReason?

    mutating func beginRecording() {
        failure = nil
    }

    mutating func recordFailure(_ reason: CaptureUnavailableReason) {
        failure = reason
    }

    /// Audio observation may occur after another failure or a user STOP. Preserve
    /// the first recorded cause instead of replacing a WB/resource failure.
    mutating func recordAudioFailure(_ reason: CaptureUnavailableReason = .interrupted) {
        if failure == nil { failure = reason }
    }

    /// Called before publishing a thrown command's failure. A user STOP may have
    /// reached the lifecycle first, so its later command need not carry this reason.
    mutating func recordCommandFailure(_ command: CaptureIOCommand, activeToken: CaptureCommandToken?,
                                       reason: CaptureUnavailableReason) {
        guard case .refreshAndLockWhiteBalance(let token) = command,
              token.context == activeToken?.context else { return }
        failure = reason
    }

    mutating func recordStop(_ reason: CaptureStopReason) {
        switch reason {
        case .user: break
        case .audioFailure: failure = .interrupted
        case .adapterFailure(let reason): failure = reason
        }
    }

    func writerFinished(completed: Bool) -> CaptureWriterTermination {
        movieFinished(failure: completed ? nil : .adapterFailure(code: "writer_finalize_failed"))
    }

    func movieFinished(failure finalizationFailure: CaptureUnavailableReason?) -> CaptureWriterTermination {
        (finalizationFailure ?? failure).map(CaptureWriterTermination.interrupted) ?? .completed
    }
}
