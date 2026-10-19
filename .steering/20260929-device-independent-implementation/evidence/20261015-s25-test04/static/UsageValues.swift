@testable import FrameRelay
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
