nonisolated enum CaptureIOCommand: Equatable, Sendable {
    /// Read the currently obtainable gains and lock them, without waiting for stability.
    case lockCurrentWhiteBalance(CaptureCommandToken)
    /// Explicit user request only. Preserve shutter/ISO/aperture and return to fixed WB.
    case refreshAndLockWhiteBalance(CaptureCommandToken)
    /// Serial adapters invalidate older WB work before applying this command.
    case restoreAutomaticWhiteBalance(CaptureCommandToken)
    case startRecording(CaptureCommandToken, RecordingIntent)
    /// Uses the start token, so a STOP accepted before didStart can still stop that recorder.
    case stopRecording(CaptureCommandToken, reason: CaptureStopReason)

    var token: CaptureCommandToken {
        switch self {
        case .lockCurrentWhiteBalance(let token), .refreshAndLockWhiteBalance(let token),
             .restoreAutomaticWhiteBalance(let token), .startRecording(let token, _),
             .stopRecording(let token, _): return token
        }
    }
}

nonisolated enum CaptureStopReason: Equatable, Sendable {
    case user(CaptureOperationID)
    case audioFailure(CaptureAudioFailure)
    case adapterFailure(CaptureUnavailableReason)
}

nonisolated enum CaptureIOEvent: Codable, Equatable, Sendable {
    case whiteBalanceLocked(CaptureCommandToken, CaptureWhiteBalanceLock)
    case automaticWhiteBalanceRestored(CaptureCommandToken, CaptureTimeObservation)
    /// This is the adapter's start notice, not first saved video/audio evidence.
    case recordingStarted(CaptureCommandToken, CaptureTimeObservation)
    case recordingEnded(CaptureCommandToken, RecordingEndEvidence)
    case commandFailed(CaptureCommandToken, CaptureUnavailableReason)
    case audioObserved(CaptureContext, sequence: UInt64, CaptureAudioState)
}

nonisolated enum CaptureCommandAcceptance: Equatable, Sendable {
    case accepted(CaptureCommandToken)
    case rejected(CaptureCommandToken, CaptureUnavailableReason)
}

/// The adapter owns serial SDK access and checks command freshness before side effects.
/// Acceptance does not prove hardware application, start, stop, or file finalization.
nonisolated protocol CaptureControlPort: Sendable {
    func submit(_ command: CaptureIOCommand) async -> CaptureCommandAcceptance
    func events() async -> AsyncStream<CaptureIOEvent>
}

nonisolated struct CaptureCapabilityQuery: Equatable, Sendable {
    let generation: CaptureGeneration
    let operation: CaptureOperationID
    let controlsForConfiguration: CaptureConfiguration?
}

nonisolated struct CaptureSettingsCommand: Equatable, Sendable {
    let generation: CaptureGeneration
    let operation: CaptureOperationID
    let desired: DesiredCaptureSettings
}

nonisolated enum CaptureSettingsResult: Equatable, Sendable {
    case applied(AppliedCaptureSettings)
    case rejected(CaptureSettingsCommand, CaptureUnavailableReason)
}

nonisolated protocol CaptureConfigurationPort: Sendable {
    func capabilities(for query: CaptureCapabilityQuery) async -> CaptureCapabilities
    func apply(_ command: CaptureSettingsCommand) async -> CaptureSettingsResult
}

nonisolated enum RecordingStoreCommand: Equatable, Sendable {
    case commitIntent(CaptureCommandToken, expectedRevision: UInt64, RecordingIntent)
    case commitResult(CaptureCommandToken, expectedRevision: UInt64, RecordingResultRecord)
}

nonisolated enum RecordingStoreResult: Equatable, Sendable {
    case committed(RecordingCommitReceipt)
    case rejected(CaptureCommandToken, CaptureContractError)
    case unavailable(CaptureCommandToken, CaptureUnavailableReason)
}

nonisolated struct UnfinishedRecording: Equatable, Sendable {
    let intent: RecordingIntent
    let revision: UInt64
    let lastResult: RecordingSaveResult?
}

nonisolated enum UnfinishedRecordingLoadResult: Equatable, Sendable {
    case loaded([UnfinishedRecording])
    case unavailable(CaptureUnavailableReason)
    case unrecognizedSchema
    case corruptStore
}

nonisolated protocol RecordingStorePort: Sendable {
    func execute(_ command: RecordingStoreCommand) async -> RecordingStoreResult
    func loadUnfinished() async -> UnfinishedRecordingLoadResult
}

nonisolated struct CaptureInspectionRequest: Equatable, Sendable {
    let token: CaptureCommandToken
    let original: CaptureOriginalReference
}

nonisolated enum CaptureInspectionResult: Equatable, Sendable {
    case inspected(CaptureCommandToken, CaptureMediaInspection)
    case unavailable(CaptureCommandToken, CaptureUnavailableReason)
}

/// Read-only inspection. This contract has no delete, Photos, or transfer operation.
nonisolated protocol CaptureOriginalInspectionPort: Sendable {
    func inspect(_ request: CaptureInspectionRequest) async -> CaptureInspectionResult
}
