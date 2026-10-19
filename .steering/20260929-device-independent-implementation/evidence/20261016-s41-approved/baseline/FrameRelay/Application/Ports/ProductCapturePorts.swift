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
