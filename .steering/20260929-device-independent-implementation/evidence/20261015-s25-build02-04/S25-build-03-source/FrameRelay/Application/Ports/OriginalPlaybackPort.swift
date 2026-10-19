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
