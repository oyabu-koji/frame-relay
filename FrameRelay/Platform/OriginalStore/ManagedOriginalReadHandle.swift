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
        guard fstat(descriptor, &info) == 0 else { throw ExplorationStorageError.inaccessible }
        try self.init(info: info)
    }

    init(info: stat) throws {
        guard info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
              info.st_size >= 0 else { throw ExplorationStorageError.inaccessible }
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

/// Pinned before any await. Named root, lock, reservation and leaf must still
/// identify these exact descriptors at unlink; an exchanged path is not followed.
nonisolated struct ManagedOriginalRemovalRoot: Sendable {
    let run: ExplorationRunDirectory
    let directory: FileHandle
    let lock: FileHandle
    let device: Int64
    let inode: UInt64
    let lockIdentity: OriginalFileFingerprint

    init(run: ExplorationRunDirectory) throws {
        try run.validate()
        let fd = open(run.url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw ExplorationStorageError.inaccessible }
        let directory = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else {
            try? directory.close(); throw ExplorationStorageError.unsafePath
        }
        let lockFD = openat(fd, "originals.lock", O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard lockFD >= 0 else { try? directory.close(); throw ExplorationStorageError.inaccessible }
        let lock = FileHandle(fileDescriptor: lockFD, closeOnDealloc: true)
        do {
            lockIdentity = try .init(descriptor: lockFD)
            self.run = run; self.directory = directory; self.lock = lock
            device = Int64(info.st_dev); inode = UInt64(info.st_ino)
            try validate()
        } catch { try? lock.close(); try? directory.close(); throw error }
    }

    func validate() throws {
        try run.validate()
        var opened = stat(), named = stat(), namedLock = stat()
        guard fstat(directory.fileDescriptor, &opened) == 0, lstat(run.url.path, &named) == 0,
              opened.st_mode & S_IFMT == S_IFDIR, named.st_mode & S_IFMT == S_IFDIR,
              Int64(opened.st_dev) == device, UInt64(opened.st_ino) == inode,
              opened.st_dev == named.st_dev, opened.st_ino == named.st_ino,
              fstatat(directory.fileDescriptor, "originals.lock", &namedLock, AT_SYMLINK_NOFOLLOW) == 0,
              try OriginalFileFingerprint(descriptor: lock.fileDescriptor) == lockIdentity,
              try OriginalFileFingerprint(info: namedLock) == lockIdentity else {
            throw ExplorationStorageError.unsafePath
        }
    }
}

nonisolated struct ManagedOriginalRemovalHandle: Sendable {
    let root: ManagedOriginalRemovalRoot
    let reference: CaptureOriginalReference
    let source: FileHandle
    let reservation: FileHandle
    let fingerprint: OriginalFileFingerprint
    let reservationFingerprint: OriginalFileFingerprint

    func close() throws {
        var failed = false
        do { try source.close() } catch { failed = true }
        do { try reservation.close() } catch { failed = true }
        if failed { throw ExplorationStorageError.inaccessible }
    }

    private func validatePresent() throws {
        try root.validate()
        var named = stat(), reserved = stat()
        guard try OriginalFileFingerprint(descriptor: source.fileDescriptor) == fingerprint,
              try OriginalFileFingerprint(descriptor: reservation.fileDescriptor) == reservationFingerprint,
              fstatat(root.directory.fileDescriptor, reference.rawValue + ".reservation", &reserved, AT_SYMLINK_NOFOLLOW) == 0,
              try OriginalFileFingerprint(info: reserved) == reservationFingerprint,
              fstatat(root.directory.fileDescriptor, reference.rawValue + ".mov", &named, AT_SYMLINK_NOFOLLOW) == 0,
              try OriginalFileFingerprint(info: named) == fingerprint else { throw ExplorationStorageError.unsafePath }
    }

    func confirmPresentAndClose() throws {
        try root.validate()
        guard flock(root.lock.fileDescriptor, LOCK_EX) == 0 else { throw ExplorationStorageError.inaccessible }
        defer { flock(root.lock.fileDescriptor, LOCK_UN) }
        try validatePresent()
        try close()
    }

    func unlink() throws {
        try root.validate()
        guard flock(root.lock.fileDescriptor, LOCK_EX) == 0 else { throw ExplorationStorageError.inaccessible }
        defer { flock(root.lock.fileDescriptor, LOCK_UN) }
        try validatePresent()
        let leaf = reference.rawValue + ".mov"
        guard unlinkat(root.directory.fileDescriptor, leaf, 0) == 0 else { throw ExplorationStorageError.inaccessible }
        // No recursive removal, reservation unlink, rename, or external side effect.
        try root.validate()
        var named = stat()
        guard fstatat(root.directory.fileDescriptor, leaf, &named, AT_SYMLINK_NOFOLLOW) != 0,
              errno == ENOENT else { throw ExplorationStorageError.inaccessible }
    }
}

nonisolated struct ManagedOriginalRemovalAbsence: Sendable {
    let root: ManagedOriginalRemovalRoot
    let reference: CaptureOriginalReference
    let reservation: FileHandle
    let reservationFingerprint: OriginalFileFingerprint

    func confirmAbsentAndClose() throws {
        try root.validate()
        guard flock(root.lock.fileDescriptor, LOCK_EX) == 0 else { throw ExplorationStorageError.inaccessible }
        defer { flock(root.lock.fileDescriptor, LOCK_UN) }
        try root.validate()
        var reserved = stat(), named = stat()
        guard try OriginalFileFingerprint(descriptor: reservation.fileDescriptor) == reservationFingerprint,
              fstatat(root.directory.fileDescriptor, reference.rawValue + ".reservation", &reserved, AT_SYMLINK_NOFOLLOW) == 0,
              try OriginalFileFingerprint(info: reserved) == reservationFingerprint else { throw ExplorationStorageError.unsafePath }
        let result = fstatat(root.directory.fileDescriptor, reference.rawValue + ".mov", &named, AT_SYMLINK_NOFOLLOW)
        let observedError = errno
        try root.validate()
        guard result != 0, observedError == ENOENT else { throw ExplorationStorageError.unsafePath }
        try reservation.close()
    }
}

nonisolated enum ManagedOriginalRemovalObservation: Sendable {
    case present(ManagedOriginalRemovalHandle)
    case absent(ManagedOriginalRemovalAbsence)

    var resolution: RemovalResolution {
        switch self { case .present: .notRemoved; case .absent: .removed }
    }
    func confirmAndClose() throws {
        switch self {
        case .present(let handle): try handle.confirmPresentAndClose()
        case .absent(let handle): try handle.confirmAbsentAndClose()
        }
    }
    func close() {
        switch self {
        case .present(let handle): try? handle.close()
        case .absent(let handle): try? handle.reservation.close()
        }
    }
}
