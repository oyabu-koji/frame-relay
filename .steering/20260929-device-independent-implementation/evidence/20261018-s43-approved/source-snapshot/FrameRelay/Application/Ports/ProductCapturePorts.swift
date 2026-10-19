import Foundation

nonisolated protocol ProductCapturePreferencePort: Sendable {
    func load() async throws -> ProductCapturePreferences
    func save(_ preferences: ProductCapturePreferences) async throws
}

nonisolated struct ProductCapturePreparation: Sendable {
    let desired: DesiredCaptureSettings
    let generation: CaptureGeneration
    let operation: CaptureOperationID
}

/// Ticket-free product access. Format indices and exploratory limits are not inputs.
nonisolated protocol ProductCapturePreviewSource: Sendable {}

nonisolated protocol ProductCaptureDevicePort: CaptureControlPort {
    func discoverCameras() async throws -> [ExplorationCameraDescription]
    func prepare(_ request: ProductCapturePreparation) async throws -> ExplorationPrepared
    func audioSnapshots() async -> AsyncStream<ProductCaptureAudioSnapshot>
    func recoverAudio(_ request: ProductCaptureAudioRecoveryRequest) async -> CaptureAudioRecoveryOutcome
    func cancelAudioRecovery(_ request: ProductCaptureAudioRecoveryRequest) async
    func productEvents() async -> AsyncStream<ExplorationDeviceEvent>
    func previewSource() async -> (any ProductCapturePreviewSource)?
    func shutDown() async
}

nonisolated protocol ProductCaptureSavePort: Sendable {
    func begin(_ intent: RecordingIntent, token: CaptureCommandToken) async -> OriginalSaveOperationResult
    func recordingEnded(context: CaptureContext, evidence: RecordingEndEvidence) async -> OriginalSaveOperationResult
    func fileFinalized(_ file: CaptureFileEvidence, resultToken: CaptureCommandToken) async -> OriginalSaveOperationResult
}

extension OriginalSaveCoordinator: ProductCaptureSavePort {}

extension ProductCaptureDevicePort {
    /// Adapters without audio observation remain explicitly unavailable; no fake valid input is made here.
    func audioSnapshots() async -> AsyncStream<ProductCaptureAudioSnapshot> { AsyncStream { $0.finish() } }
    func recoverAudio(_ request: ProductCaptureAudioRecoveryRequest) async -> CaptureAudioRecoveryOutcome {
        .failed(.routeInterrupted(.init(rawValue: "audio-recovery-unavailable")))
    }
    /// Returns only once the matching audio operation can no longer touch SDK resources.
    func cancelAudioRecovery(_ request: ProductCaptureAudioRecoveryRequest) async {}
}
