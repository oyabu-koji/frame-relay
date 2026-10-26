nonisolated enum OriginalDescriptionResult: Equatable, Sendable {
    case described(OriginalDescriptor)
    case unavailable(BackendFailure)
}

nonisolated protocol OriginalAccessPort: Sendable {
    func describe(_ reference: CaptureOriginalReference) async -> OriginalDescriptionResult
    func acquireRead(_ original: OriginalContent, operation: MediaOperationID,
                     leaseID: ReadLeaseID) async -> BackendOutcome<OriginalReadLease>
    /// Request alone does not authorize a removal consumer.
    func releaseRead(_ lease: OriginalReadLease) async -> BackendOutcome<ReadReleaseReceipt>
    func reconcileReaders(_ original: OriginalContent) async -> BackendOutcome<AllReadersReleasedReceipt>
}

nonisolated enum NetworkCondition: Equatable, Sendable { case wiFi, cellular, offline, unknown }

nonisolated protocol NetworkConditionPort: Sendable {
    /// Report the underlying path; a VPN being present is not Wi-Fi evidence.
    func conditions() async -> AsyncStream<NetworkCondition>
}

nonisolated struct MediaGateLease: Equatable, Sendable {
    let operation: MediaOperationID
    let attempt: TransferAttemptID
    let target: MediaTarget
    let registration: RegistrationIdentity
    let generation: UInt64
}

nonisolated struct UploadMediaCommand: Equatable, Sendable {
    let gate: MediaGateLease
    let originalLease: OriginalReadLease
    let session: UploadSessionID

    var identitiesMatch: Bool {
        gate.target == .original(originalLease.original) && gate.operation == originalLease.operation
    }
}

nonisolated struct RetrieveMediaCommand: Equatable, Sendable {
    let gate: MediaGateLease
    let distribution: DistributionReceipt
    let range: MediaByteRange?

    /// Correlation only, never authority for a new GET/Range/resume. The server must recheck
    /// current publication and commit distribution for EACH request before any bytes (T17).
    /// Gate operation/attempt identifies this transport; distribution.operation identifies
    /// the server's distribution transaction and is intentionally a separate operation.
    var identitiesMatch: Bool {
        guard distribution.isCommitted, gate.target == .rendition(distribution.rendition),
              gate.registration == distribution.registration else { return false }
        if let range { return range.upperBound <= distribution.rendition.deliveryContent.byteCount }
        return true
    }
}

nonisolated protocol MediaTransportPort: Sendable {
    func upload(_ command: UploadMediaCommand) async -> BackendOutcome<RemoteOperationResult>
    func retrieve(_ command: RetrieveMediaCommand) async -> BackendOutcome<TemporaryMediaReceipt>
    /// This acknowledges the request only. Consumers await observeStop and release all readers separately.
    func requestStop(_ lease: MediaGateLease) async
    func observeStop(_ lease: MediaGateLease) async -> BackendOutcome<TransportStopReceipt>
}

nonisolated enum PlaybackSource: Equatable, Sendable {
    case remote(RetrieveMediaCommand)
    case local(TemporaryMediaReceipt, DistributionReceipt)
}

nonisolated struct PlaybackCommand: Equatable, Sendable {
    let source: PlaybackSource
    let session: PlaybackSessionID
    let invalidationGeneration: InvalidationGeneration
}

nonisolated protocol PlaybackPort: Sendable {
    func play(_ command: PlaybackCommand) async -> BackendOutcome<PlaybackToken>
    func end(_ session: PlaybackSessionID) async
}

nonisolated protocol TemporaryMediaPort: Sendable {
    func inspect(_ id: TemporaryMediaID) async -> BackendOutcome<TemporaryMediaReceipt>
    func acquireUsage(_ id: TemporaryMediaID, purpose: TemporaryMediaPurpose,
                      usageID: MediaUsageID) async -> BackendOutcome<TemporaryMediaUsage>
    func releaseUsage(_ usage: TemporaryMediaUsage) async -> BackendOutcome<TemporaryMediaID>
}

/// A backend handle, never a bearer string or a registration proof.
nonisolated struct CredentialHandle: Equatable, Sendable { let rawValue: String }
nonisolated protocol CredentialPort: Sendable {
    func credential(for destination: DestinationIdentity) async -> BackendOutcome<CredentialHandle>
}
