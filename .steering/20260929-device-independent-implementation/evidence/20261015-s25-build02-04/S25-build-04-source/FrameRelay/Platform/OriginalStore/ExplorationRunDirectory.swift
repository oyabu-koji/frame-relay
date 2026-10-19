import Foundation
import Darwin

nonisolated enum ExplorationStorageError: Error, Equatable {
    case invalidReference, unsafePath, alreadyExists, inaccessible, corruptStore, unknownSchema
}

nonisolated enum ExplorationStoreOpenMode: Sendable {
    case createNew, openExisting
}

/// Only a newly created, private exploration directory (or its explicit reopen).
/// No migration, cleanup, deletion, or replacement of an existing directory.
nonisolated struct ExplorationRunDirectory: Sendable {
    let url: URL
    private static let marker = Data("FrameRelay-exploration-run-v1\n".utf8)
    private init(url: URL) { self.url = url }

    static func createNew(at url: URL) throws -> Self {
        let url = url.standardizedFileURL
        try requireDirectory(url.deletingLastPathComponent())
        guard mkdir(url.path, 0o700) == 0 else {
            throw errno == EEXIST ? ExplorationStorageError.alreadyExists : .inaccessible
        }
        // A failed initialization remains visible; never erase it and retry as empty.
        try marker.write(to: url.appendingPathComponent("run.marker"), options: .withoutOverwriting)
        return try openExisting(at: url)
    }

    static func openExisting(at url: URL) throws -> Self {
        let result = Self(url: url.standardizedFileURL)
        try result.validate()
        return result
    }

    func validate() throws {
        try Self.requireDirectory(url)
        let markerURL = url.appendingPathComponent("run.marker")
        try Self.requireRegularFile(markerURL)
        guard try Data(contentsOf: markerURL) == Self.marker else {
            throw ExplorationStorageError.unknownSchema
        }
    }

    static func requireDirectory(_ url: URL) throws {
        guard url.isFileURL, url.standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL else {
            throw ExplorationStorageError.unsafePath
        }
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw ExplorationStorageError.inaccessible }
        guard info.st_mode & S_IFMT == S_IFDIR else { throw ExplorationStorageError.unsafePath }
    }

    static func requireRegularFile(_ url: URL) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw ExplorationStorageError.inaccessible }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else {
            throw ExplorationStorageError.unsafePath
        }
    }

    static func validateReference(_ reference: CaptureOriginalReference) throws {
        guard (1...128).contains(reference.rawValue.utf8.count),
              reference.rawValue.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0)
                  || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else {
            throw ExplorationStorageError.invalidReference
        }
    }
}

/// An advisory process-shared lock for these two exploration adapters. Every
/// owner must use this implementation; unrelated writers are outside the contract.
nonisolated enum ExplorationFileLock {
    static func withLock<T>(run: ExplorationRunDirectory, name: String, _ body: () throws -> T) throws -> T {
        try run.validate()
        let url = run.url.appendingPathComponent(name)
        let descriptor = open(url.path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw ExplorationStorageError.inaccessible }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else {
            throw ExplorationStorageError.unsafePath
        }
        guard flock(descriptor, LOCK_EX) == 0 else { throw ExplorationStorageError.inaccessible }
        defer { flock(descriptor, LOCK_UN) }
        try run.validate()
        return try body()
    }
}
