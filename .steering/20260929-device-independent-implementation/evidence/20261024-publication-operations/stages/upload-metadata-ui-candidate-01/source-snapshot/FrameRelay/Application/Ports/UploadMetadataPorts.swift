nonisolated enum UploadMetadataResult: Equatable, Sendable {
    case recorded(StoredUploadMetadataObservation)
    case rejected(BackendContractError)
    case unknown
}

/// Explicit per-request metadata action, GET-only synchronization, and exact
/// pending-writer lookup are distinct entry points. No method sends media.
nonisolated protocol UploadMetadataPort: Sendable {
    func refresh(_ request: UploadMetadataRequest) async -> UploadMetadataResult
    func refreshKnownSession(_ request: UploadMetadataRequest) async -> UploadMetadataResult
    func reconcilePending(_ request: UploadMetadataRequest) async -> UploadMetadataResult
}

/// A durable query reservation is necessary but is not a dispatch permit.
/// Implementations recheck the current exact scope after credential awaits and
/// immediately before dispatch; only a running, session-unknown POST is allowed.
nonisolated protocol UploadMetadataRemotePort: Sendable {
    func create(_ query: CommittedUploadMetadataQuery) async -> BackendOutcome<UploadMetadataResponse>
    func lookup(_ query: CommittedUploadMetadataQuery) async -> BackendOutcome<UploadMetadataResponse>
}
