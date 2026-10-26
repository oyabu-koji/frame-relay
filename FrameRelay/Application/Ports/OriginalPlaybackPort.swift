nonisolated struct OriginalPlaybackSource: Equatable, Sendable {
    let lease: OriginalReadLease
}

/// SDK readers are separate from the adapter's own file descriptor. Consumers
/// acknowledge completion only after AVPlayer/resource-loader tasks have stopped.
nonisolated struct OriginalReaderAttachment: Equatable, Sendable {
    let lease: OriginalReadLease
    let id: MediaUsageID
}

nonisolated struct OriginalPlaybackProgress: Equatable, Sendable {
    let source: OriginalPlaybackSource
    let session: PlaybackSessionID
    let elapsedSeconds: Double
}

/// Original playback never creates a rendition PlaybackToken or confirmation.
nonisolated protocol OriginalPlaybackPort: Sendable {
    func playOriginal(_ source: OriginalPlaybackSource, session: PlaybackSessionID) async
        -> BackendOutcome<OriginalPlaybackProgress>
    func stopOriginal(_ session: PlaybackSessionID) async
}

nonisolated protocol OriginalPlaybackAccessPort: Sendable {
    func acquirePlayback(_ original: OriginalContent, operation: MediaOperationID,
                         leaseID: ReadLeaseID) async -> BackendOutcome<OriginalPlaybackSource>
    func attachReader(_ lease: OriginalReadLease, id: MediaUsageID) async -> BackendOutcome<OriginalReaderAttachment>
    func readerDidFinish(_ attachment: OriginalReaderAttachment) async -> BackendOutcome<ReadLeaseID>
    func requestReaderStop(_ lease: OriginalReadLease) async
    func isReaderStopRequested(_ lease: OriginalReadLease) async -> Bool
}

/// Injected OS/SDK observer, not a caller assertion. S23 must enumerate every
/// owned background task, SDK reader and previous process/handle owner before
/// returning a release for an old persisted lease. No observer means unknown.
nonisolated protocol OriginalReaderRecoveryPort: Sendable {
    func observeRecoveredRelease(_ lease: OriginalReadLease) async -> BackendOutcome<ReadReleaseReceipt>
}

/// Per-session terminal facts produced only after the retained setup, monitor,
/// loader and teardown have actually finished. Original lease epochs are not
/// the common writer's media-reconciliation epoch.
nonisolated struct OriginalPlaybackOwnerTerminal: Equatable, Sendable {
    let session: PlaybackSessionID
    let original: OriginalContent
    let source: OriginalPlaybackSource?
    let release: ReadReleaseReceipt?
    let tasksJoined: Bool
    let sdkDetached: Bool
}
nonisolated struct OriginalPlaybackTermination: Equatable, Sendable {
    let original: OriginalContent
    let admissionClosed: Bool
    let createdOwners: Int
    let terminals: [OriginalPlaybackOwnerTerminal]
}
nonisolated protocol OriginalPlaybackTerminationPort: Sendable {
    func stopAndObserve(original: OriginalContent) async throws -> OriginalPlaybackTermination
    /// The composition producer verifies this exact durable ACK and the fresh
    /// writer's reservation/generation before admitting a new session.
    func resumeAfterInvalidation(_ acknowledgement: InvalidationAcknowledgement) async throws
    func stopForRemoval(_ seal: OriginalRemovalAdmissionSeal) async throws -> OriginalPlaybackTermination
    func resumeAfterRemoval(_ release: OriginalRemovalAdmissionRelease) async throws
}

extension OriginalPlaybackTerminationPort {
    nonisolated func stopForRemoval(_ seal: OriginalRemovalAdmissionSeal) async throws -> OriginalPlaybackTermination { throw BackendContractError.unavailable }
    nonisolated func resumeAfterRemoval(_ release: OriginalRemovalAdmissionRelease) async throws { throw BackendContractError.unavailable }
}
