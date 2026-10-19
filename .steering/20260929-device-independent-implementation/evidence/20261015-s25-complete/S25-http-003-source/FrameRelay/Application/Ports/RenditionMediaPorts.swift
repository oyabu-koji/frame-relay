import Foundation

/// Called for every new Range and again before its bytes are delivered. S23
/// supplies the current common media gate; a captured start decision is insufficient.
nonisolated protocol RenditionMediaAdmissionPort: Sendable {
    func check(_ lease: MediaGateLease) async throws
}

/// The control-plane producer must obtain a committed distribution for this
/// exact new request. Old result headers are not a distribution receipt.
nonisolated protocol RenditionRangeAuthorizationPort: Sendable {
    func authorize(_ command: RetrieveMediaCommand) async throws -> RetrieveMediaCommand
}

nonisolated protocol RenditionByteReadingPort: Sendable {
    func read(offset: UInt64, length: Int) async throws -> Data
    /// Return only after underlying callbacks/tasks and durable leases terminate.
    func close() async throws -> RenditionReadTerminal
}

nonisolated struct RenditionReadTerminal: Equatable, Sendable {
    let epoch: ReaderReconciliationEpoch
    let started: Int
    let completed: Int
    let bytes: UInt64
    let handlesClosed: Bool
}

/// A PhotoKit consumer retains this use through the actual performChanges
/// terminal callback. Closing that SDK access does not release the use: S31
/// calls releaseUsage only after committing successful Photos registration.
/// Failure/unknown results keep the use and file. The URL is not a lasting grant.
nonisolated struct TemporaryLocalMedia: Equatable, Sendable {
    let url: URL
    let handoff: PhotoMediaHandoff
}

nonisolated protocol TemporaryLocalMediaPort: Sendable {
    func resolvePhotoMedia(_ usage: TemporaryMediaUsage) async throws -> TemporaryLocalMedia
    /// Observes the real SDK terminal and closes its file access, without
    /// asserting registration success or releasing the durable photo usage.
    func finishPhotoMedia(_ usage: TemporaryMediaUsage) async throws
}

nonisolated protocol TemporaryMediaWritingPort: TemporaryMediaPort {
    func stateFor(_ id: TemporaryMediaID) async throws -> TemporaryMediaState
    func store(_ bytes: Data, range: MediaByteRange, using usage: TemporaryMediaUsage) async throws
    func verify(_ usage: TemporaryMediaUsage) async throws -> TemporaryMediaReceipt
}

nonisolated struct TemporaryMediaDiskUsage: Equatable, Sendable {
    let media: TemporaryMediaID
    let coveredBytes: UInt64
    let logicalFileBytes: UInt64
    let usages: Int
    let openHandles: Int
}

/// Actual regular-file lengths observed in one root. Covered ranges are a
/// separate logical fact; neither total is allocated disk blocks or SDK memory.
nonisolated struct TemporaryMediaRootUsage: Equatable, Sendable {
    let media: [TemporaryMediaDiskUsage]
    let totalFileBytes: UInt64
    let managedFileBytes: UInt64
    let unknownFileBytes: UInt64
    let unknownFiles: Int
    let metadataFileBytes: UInt64
    let usages: Int
    let openHandles: Int
    let closedHandles: Int
}
