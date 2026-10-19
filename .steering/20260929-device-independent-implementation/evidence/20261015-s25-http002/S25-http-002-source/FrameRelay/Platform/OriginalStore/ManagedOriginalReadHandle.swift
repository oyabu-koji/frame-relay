import Foundation
import Darwin

nonisolated struct OriginalFileFingerprint: Equatable, Sendable {
    let device: Int64
    let inode: UInt64
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64

    init(descriptor: Int32) throws {
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_nlink == 1, info.st_size >= 0 else { throw ExplorationStorageError.inaccessible }
        device = Int64(info.st_dev); inode = UInt64(info.st_ino); size = Int64(info.st_size)
        modifiedSeconds = Int64(info.st_mtimespec.tv_sec); modifiedNanoseconds = Int64(info.st_mtimespec.tv_nsec)
        changedSeconds = Int64(info.st_ctimespec.tv_sec); changedNanoseconds = Int64(info.st_ctimespec.tv_nsec)
    }
}

nonisolated struct ManagedOriginalReadHandle: Sendable {
    let handle: FileHandle
    let fingerprint: OriginalFileFingerprint
}

/// A narrow injectable opening boundary; implementations still open and hash an
/// actual managed file. Used to observe cancellation while real open is pending.
nonisolated protocol ManagedOriginalReadOpeningPort: Sendable {
    func openBoundRead(_ binding: OriginalBinding) async throws -> ManagedOriginalReadHandle
}
