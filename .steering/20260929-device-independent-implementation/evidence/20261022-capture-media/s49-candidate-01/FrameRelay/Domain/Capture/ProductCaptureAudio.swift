import Foundation

/// A session observation is usable before REC. A clip observation belongs only to that clip.
nonisolated struct ProductCaptureAudioSnapshot: Equatable, Sendable {
    let generation: CaptureGeneration
    let capture: CaptureID?
    let sequence: UInt64
    let state: CaptureAudioState
}

/// Explicitly injected trial/product policy; no implicit grace or retry defaults.
nonisolated struct ProductCaptureAudioPolicy: Sendable {
    let noArrivalGrace: CaptureRationalTime
    let recovery: CaptureAudioRecoveryPolicy

    init(noArrivalGrace: CaptureRationalTime, recovery: CaptureAudioRecoveryPolicy) throws {
        guard noArrivalGrace.ticks > 0 else { throw CaptureContractError.invalidValue }
        self.noArrivalGrace = noArrivalGrace
        self.recovery = recovery
    }
}

nonisolated struct ProductCaptureAudioRecoveryRequest: Equatable, Sendable {
    let generation: CaptureGeneration
    let operation: UUID
    let ordinal: Int
}

nonisolated enum ProductCaptureAudioRecoveryStatus: Equatable, Sendable {
    case idle
    case attempting(Int)
    case timedOutWaitingForRelease
    case readyForUserREC
    case failed
}

nonisolated enum ProductCaptureAudioPreparationError: Error {
    case microphonePermissionDenied
}
