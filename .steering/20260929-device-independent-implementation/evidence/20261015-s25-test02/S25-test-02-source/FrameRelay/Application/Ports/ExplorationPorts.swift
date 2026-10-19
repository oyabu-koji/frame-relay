nonisolated struct ExplorationPreparation: Sendable {
    let ticket: ExplorationTicket
    let generation: CaptureGeneration
    let operation: CaptureOperationID
}

nonisolated struct ExplorationPrepared: Sendable {
    let capabilities: CaptureCapabilities
    let applied: AppliedCaptureSettings
    let audio: CaptureAudioState
}

nonisolated struct ExplorationCameraDescription: Equatable, Sendable {
    let id: String
    let label: String
    let isVirtual: Bool
    let formats: [ExplorationFormatDescription]
}

nonisolated struct ExplorationFormatDescription: Equatable, Sendable {
    let id: String
    let width: Int
    let height: Int
    let frameRateRanges: [ClosedRange<Double>]
    let logEncodings: [CaptureLogEncoding]
    let stabilizationModes: [String]
}

nonisolated struct ExplorationObservation: Codable, Equatable, Sendable {
    let code: String
    let context: CaptureContext?
    let time: CaptureTimeObservation
    let detail: String
}

nonisolated enum ExplorationDeviceEvent: Codable, Equatable, Sendable {
    case capture(CaptureIOEvent)
    case fileFinalized(CaptureFileEvidence)
    case observation(ExplorationObservation)
}

/// Only low-frequency control facts and value observations, never sample buffers,
/// media bytes, arbitrary error descriptions, or private paths.
nonisolated struct ExplorationDiagnosticRecord: Codable, Equatable, Sendable {
    let sequence: UInt64
    let event: ExplorationDeviceEvent
}

nonisolated protocol ExplorationDiagnosticsPort: Sendable {
    /// The store assigns the next sequence; the event retains its observed clock.
    func append(_ event: ExplorationDeviceEvent) async throws -> ExplorationDiagnosticRecord
    func load() async throws -> [ExplorationDiagnosticRecord]
}

nonisolated protocol ExplorationDevicePort: CaptureControlPort {
    func discover() async throws -> [ExplorationCameraDescription]
    func prepare(_ request: ExplorationPreparation) async throws -> ExplorationPrepared
    func explorationEvents() async -> AsyncStream<ExplorationDeviceEvent>
    func shutDown() async
}

nonisolated struct ExplorationServices: Sendable {
    let generation: CaptureGeneration
    let device: any ExplorationDevicePort
    let store: any RecordingStorePort
    let inspection: any CaptureOriginalInspectionPort
    let diagnostics: any ExplorationDiagnosticsPort
}

nonisolated protocol ExplorationFactoryPort: Sendable {
    func runtime() async throws -> ExplorationRuntime
    func makeServices(ticket: ExplorationTicket, output: ExplorationOutputCandidate,
                      store: ExplorationStoreCandidate) async throws -> ExplorationServices
    func nextCaptureIdentity(generation: CaptureGeneration) async -> (CaptureContext, CaptureOperationID, CaptureOriginalReference)
    func currentTime() async -> CaptureTimeObservation
}
