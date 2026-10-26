import Foundation

/// Permit producer must prove the strict path/redirect policy before any
/// attempt, source, lease or task is created. No positive default exists.
nonisolated struct BackgroundMediaStrictPermit: Equatable, Sendable {
    let context: BackgroundMediaRequestContext
    let evidence: EvidenceID
}
nonisolated protocol BackgroundMediaStrictAdmissionPort: Sendable {
    func permit(_ context: BackgroundMediaRequestContext) async -> BackendOutcome<BackgroundMediaStrictPermit>
}

/// Invoked only after strict admission and local chunk verification. Request
/// credentials remain transient; there is no whole-upload fallback producer.
nonisolated protocol BackgroundMediaUploadChunkRequestPort: Sendable {
    func makeRequest(context: BackgroundMediaRequestContext, descriptor: UploadChunkDescriptor) async throws -> URLRequest
}

nonisolated struct UnavailableBackgroundMediaUploadChunkRequests: BackgroundMediaUploadChunkRequestPort {
    func makeRequest(context: BackgroundMediaRequestContext, descriptor: UploadChunkDescriptor) async throws -> URLRequest {
        throw BackendContractError.unavailable
    }
}

/// A transient SDK input. This URL is never serialized into the journal.
nonisolated struct BackgroundMediaUploadFile: Equatable, Sendable {
    let identity: ManagedUploadSourceIdentity
    let url: URL
}

/// Delivery sequence belongs to this concrete delegate stream. A serial
/// consumer must await each event's disk/resource work before draining later
/// finish-events. Independent callback Tasks do not establish that ordering.
nonisolated struct BackgroundMediaSDKEvent: Equatable, Sendable {
    let session: BackgroundMediaSessionIdentity
    let stream: UUID
    let sequence: UInt64
    let value: BackgroundMediaSDKEventValue
}
nonisolated enum BackgroundMediaSDKEventValue: Equatable, Sendable {
    case taskTerminal(BackgroundMediaSDKTerminal)
    case unknownTaskTerminal(BackgroundMediaTaskObservation, outcome: BackgroundMediaSDKOutcome)
    case downloadArtifactUnavailable(BackgroundMediaTaskObservation)
    /// Opaque same-process registry reference only; never bytes/URL/FD authority.
    case downloadArtifact(BackgroundDownloadArtifactReference)
    case sessionInvalidated(errorCode: Int?)
    case finishedEvents
}

nonisolated enum BackgroundMediaTaskKind: String, Equatable, Sendable { case upload, download, other }
nonisolated enum BackgroundMediaSDKTaskState: String, Equatable, Sendable { case running, suspended, canceling, completed, unknown }
nonisolated struct BackgroundMediaTaskObservation: Equatable, Sendable {
    let session: BackgroundMediaSessionIdentity
    let taskIdentifier: Int
    let taskDescription: String?
    let kind: BackgroundMediaTaskKind
    let state: BackgroundMediaSDKTaskState
    let bytesSent: Int64
    let bytesReceived: Int64
}

nonisolated protocol BackgroundMediaSessionPort: Sendable {
    /// Exactly one consumer; a second take must fail explicitly.
    func events() async throws -> AsyncStream<BackgroundMediaSDKEvent>
    func createSuspended(_ intent: BackgroundMediaTaskIntent, request: URLRequest,
        upload: BackgroundMediaUploadFile?) async -> BackendOutcome<BackgroundMediaTaskBinding>
    /// Preserve duplicates and unknown tasks; absence is not a terminal receipt.
    func enumerate() async -> BackendOutcome<[BackgroundMediaTaskObservation]>
    /// Consume captureAuthorization synchronously at the actual SDK dispatch,
    /// after any await/queue hop; never treat its earlier issuance as execution.
    func resume(_ binding: BackgroundMediaTaskBinding, permit: BackgroundMediaStrictPermit,
        captureAuthorization: CaptureMediaResumeAuthorization) async -> BackendOutcome<BackgroundMediaTaskBinding>
    /// Request only. Completion comes exclusively from the actual delegate.
    func requestStop(_ binding: BackgroundMediaTaskBinding) async
    func observeTerminal(_ binding: BackgroundMediaTaskBinding) async -> BackendOutcome<BackgroundMediaSDKTerminal>
    /// Session invalidation is a separate event, never all-owner/file closure.
    func invalidate() async
}
