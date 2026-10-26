import Foundation
import Darwin

/// The consuming temporary owner supplies this after its real hash FD closed.
/// Borrowed descriptors grant no close/reopen/repair authority. The import Task
/// retains the owner while the writer checks only short stat/identity facts.
nonisolated struct BackgroundDownloadImportFileWitness: Sendable {
    let url: URL
    let directoryDescriptor: Int32
    let ownerDescriptor: Int32
    let ownerFingerprint: OriginalFileFingerprint
    let fingerprint: OriginalFileFingerprint

    func requireCurrent(_ value: BackgroundDownloadImportObservation) throws {
        guard url.isFileURL, url.lastPathComponent.utf8.elementsEqual(value.leaf.utf8),
              BackgroundDownloadValue.exact(Self.fileFacts(fingerprint), value.targetFile) else { throw BackendContractError.identityMismatch }
        var namedRoot = stat(), root = stat(), namedOwner = stat(), owner = stat(), named = stat(), relative = stat()
        guard lstat(url.deletingLastPathComponent().path, &namedRoot) == 0,
              fstat(directoryDescriptor, &root) == 0, root.st_mode & S_IFMT == S_IFDIR,
              namedRoot.st_mode & S_IFMT == S_IFDIR, root.st_dev == namedRoot.st_dev, root.st_ino == namedRoot.st_ino,
              Int64(root.st_dev) == value.directory.device, UInt64(root.st_ino) == value.directory.inode,
              fstat(ownerDescriptor, &owner) == 0,
              fstatat(directoryDescriptor, "owner.lock", &namedOwner, AT_SYMLINK_NOFOLLOW) == 0,
              try OriginalFileFingerprint(info: owner) == ownerFingerprint,
              try OriginalFileFingerprint(info: namedOwner) == ownerFingerprint,
              lstat(url.path, &named) == 0, fstatat(directoryDescriptor, value.leaf, &relative, AT_SYMLINK_NOFOLLOW) == 0,
              try OriginalFileFingerprint(info: named) == fingerprint,
              try OriginalFileFingerprint(info: relative) == fingerprint else { throw BackendContractError.identityMismatch }
    }

}

nonisolated extension BackgroundDownloadImportFileWitness {
    static func fileFacts(_ value: OriginalFileFingerprint) -> ManagedUploadFileIdentity {
        .init(device: value.device, inode: value.inode, size: value.size,
            modifiedSeconds: value.modifiedSeconds, modifiedNanoseconds: value.modifiedNanoseconds,
            changedSeconds: value.changedSeconds, changedNanoseconds: value.changedNanoseconds)
    }
}

/// Process-local finalization arbitration, distinct from the ingress abort seal.
/// Stop wins until the single atomic writer/capture/latch boundary consumes it.
nonisolated final class BackgroundDownloadImportLatch: @unchecked Sendable {
    let command: MediaOperationID
    let artifact: BackgroundDownloadArtifactReference
    private let lock = NSLock()
    private var stopped = false
    private var consumed = false
    init(command: MediaOperationID, artifact: BackgroundDownloadArtifactReference) { self.command = command; self.artifact = artifact }
    func requestStop() { lock.lock(); stopped = true; lock.unlock() }
    var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    fileprivate func perform(command: MediaOperationID, artifact: BackgroundDownloadArtifactReference, action: () throws -> Void) rethrows -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !stopped, !consumed, BackgroundDownloadValue.exact(self.command, command),
              BackgroundDownloadValue.exact(self.artifact, artifact) else { return false }
        consumed = true
        try action()
        return true
    }
}

nonisolated final class BackgroundDownloadImportAuthorization: Sendable {
    let capture: CaptureMediaResumeAuthorization
    let latch: BackgroundDownloadImportLatch
    let selection: BackgroundDownloadImportSelection
    init(capture: CaptureMediaResumeAuthorization, latch: BackgroundDownloadImportLatch, selection: BackgroundDownloadImportSelection) {
        self.capture = capture; self.latch = latch; self.selection = selection
    }
    /// Called only under the same writer lock. The action is metadata-only,
    /// synchronous, non-reentrant, and must not await/open/read/hash/redispatch.
    func perform(_ value: BackgroundDownloadImportObservation, artifact: BackgroundDownloadArtifactReference,
                 action: () throws -> Void) rethrows -> Bool {
        guard BackgroundDownloadValue.exact(value.selection, selection) else { return false }
        var applied = false
        let current = try capture.performIfCurrent {
            applied = try latch.perform(command: value.command, artifact: artifact, action: action)
        }
        return current && applied
    }
}

nonisolated protocol BackgroundDownloadTemporaryImportPort: TemporaryMediaWritingPort {
    func verifyBackgroundDownload(_ usage: TemporaryMediaUsage, selection: BackgroundDownloadImportSelection,
                                  authorization: BackgroundDownloadImportAuthorization) async throws -> TemporaryMediaReceipt
}
