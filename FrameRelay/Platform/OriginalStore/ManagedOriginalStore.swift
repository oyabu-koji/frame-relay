import Foundation
import CryptoKit
import Darwin

nonisolated struct OriginalContentDigest: Equatable, Sendable {
    let original: CaptureOriginalReference
    let byteCount: UInt64
    let sha256: String
}

/// Only app-managed opaque IDs resolve to new .mov files in this private run.
/// Reservations persist separately, so reopening cannot reuse an existing ID.
actor ManagedOriginalStore: ExplorationOriginalDestinationPort {
    private let run: ExplorationRunDirectory

    init(run: ExplorationRunDirectory) { self.run = run }

    func reserve(original: CaptureOriginalReference) throws -> URL {
        try ExplorationRunDirectory.validateReference(original)
        return try ExplorationFileLock.withLock(run: run, name: "originals.lock") {
            let url = run.url.appendingPathComponent(original.rawValue + ".mov")
            var info = stat()
            guard lstat(url.path, &info) != 0, errno == ENOENT else { throw ExplorationStorageError.alreadyExists }
            let reservation = run.url.appendingPathComponent(original.rawValue + ".reservation")
            let descriptor = open(reservation.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard descriptor >= 0 else {
                throw errno == EEXIST ? ExplorationStorageError.alreadyExists : .inaccessible
            }
            close(descriptor)
            return url
        }
    }

    func existingURL(for original: CaptureOriginalReference) throws -> URL {
        try run.validate()
        try ExplorationRunDirectory.validateReference(original)
        let reservation = run.url.appendingPathComponent(original.rawValue + ".reservation")
        try ExplorationRunDirectory.requireRegularFile(reservation)
        let url = run.url.appendingPathComponent(original.rawValue + ".mov")
        try ExplorationRunDirectory.requireRegularFile(url)
        return url
    }

    func byteCount(for original: CaptureOriginalReference) throws -> UInt64 {
        let descriptor = try openOriginal(original)
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_size >= 0 else { throw ExplorationStorageError.inaccessible }
        return UInt64(info.st_size)
    }

    /// Sequential, bounded-memory reading. A digest proves these bytes only, not
    /// playability, Log encoding, camera identity, stabilization, or quality.
    func digest(for original: CaptureOriginalReference) throws -> OriginalContentDigest {
        let descriptor = try openOriginal(original)
        defer { close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0 else { throw ExplorationStorageError.inaccessible }
        var hasher = SHA256()
        var total: UInt64 = 0
        let bufferSize = 64 * 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while true {
            try Task.checkCancellation()
            let count = read(descriptor, &buffer, bufferSize)
            if count < 0 {
                if errno == EINTR { continue }
                throw ExplorationStorageError.inaccessible
            }
            if count == 0 { break }
            hasher.update(data: Data(buffer.prefix(count)))
            let next = total.addingReportingOverflow(UInt64(count))
            guard !next.overflow else { throw ExplorationStorageError.inaccessible }
            total = next.partialValue
        }
        var after = stat()
        guard fstat(descriptor, &after) == 0, after.st_size >= 0, before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
              total == UInt64(after.st_size) else { throw ExplorationStorageError.inaccessible }
        return OriginalContentDigest(original: original, byteCount: total,
                                     sha256: hasher.finalize().map { String(format: "%02x", $0) }.joined())
    }

    private func openOriginal(_ original: CaptureOriginalReference) throws -> Int32 {
        let url = try existingURL(for: original)
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw ExplorationStorageError.inaccessible }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else {
            close(descriptor)
            throw ExplorationStorageError.unsafePath
        }
        return descriptor
    }
}
