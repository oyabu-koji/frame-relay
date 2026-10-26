import CryptoKit
import Darwin
import Foundation

nonisolated struct ManagedUploadSourceResources: Equatable, Sendable {
    let activeCopies: Int
    let openHandles: Int
    let closedHandles: Int
    let largestOriginalRead: Int
    let copiedBytes: UInt64
    /// Descriptor numbers are diagnostic observations of this owner's handles,
    /// never URLSession's descriptors and never authority to release a lease.
    let descriptors: [Int32]
}

/// Owns only copies under a dedicated namespace in the existing managed run.
/// The supplied original lease remains owned by its caller. A copy attachment
/// is detached after all reads finish; this type never calls releaseRead.
actor ManagedUploadSource {
    private struct Source {
        let identity: ManagedUploadSourceIdentity
        let lease: OriginalReadLease
        let handle: FileHandle
        var exported = false
        var binding: BackgroundMediaTaskBinding?
        var terminal: BackgroundMediaSDKTerminal?
        var closure: BackgroundMediaOwnerClosure?
    }

    private let originals: ManagedOriginalAccess
    private let namespace: ManagedUploadNamespace
    private let copyCheckpoint: (@Sendable (UInt64) async throws -> Void)?
    private var sources: [ManagedUploadSourceID: Source] = [:]
    private var copying: Set<ManagedUploadSourceID> = []
    private var handles: [ObjectIdentifier: FileHandle] = [:]
    private var closedHandles = 0
    private var largestOriginalRead = 0
    private var copiedBytes: UInt64 = 0
    private var closed = false

    init(run: ExplorationRunDirectory, originals: ManagedOriginalAccess,
         copyCheckpoint: (@Sendable (UInt64) async throws -> Void)? = nil) throws {
        self.originals = originals
        self.copyCheckpoint = copyCheckpoint
        namespace = try ManagedUploadNamespace(run: run)
    }

    /// `id` is durable caller input. An existing leaf, including an interrupted
    /// or unknown copy, is retained and rejected rather than overwritten/retried.
    func create(from lease: OriginalReadLease, id: ManagedUploadSourceID) async throws -> ManagedUploadSourceIdentity {
        try Task.checkCancellation()
        try ManagedUploadNamespace.validateID(id)
        guard !closed, sources[id] == nil, !copying.contains(id),
              lease.original.content.algorithm == "sha256",
              lease.original.content.byteCount <= UInt64(Int64.max),
              ManagedUploadNamespace.isSHA256(lease.original.content.digest) else {
            throw BackendContractError.invalidValue
        }
        copying.insert(id)
        defer { copying.remove(id) }
        try namespace.validate()
        let use = MediaUsageID(rawValue: "background-upload-copy-" + id.rawValue)
        guard case .succeeded(let attachment) = await originals.attachReader(lease, id: use) else {
            throw BackendContractError.identityMismatch
        }
        var attached = true
        var writer: FileHandle?
        var reader: FileHandle?
        do {
            try Task.checkCancellation()
            try namespace.validate()
            let output = try namespace.create(id)
            writer = output
            track(output)
            var hash = SHA256()
            var offset: UInt64 = 0
            while offset < lease.original.content.byteCount {
                try Task.checkCancellation()
                try namespace.validate()
                // ManagedOriginalAccess fingerprints the same original FD
                // before and after each bounded pread.
                let length = Int(min(65_536, lease.original.content.byteCount - offset))
                largestOriginalRead = max(largestOriginalRead, length)
                let bytes = try await originals.readBytes(attachment, offset: offset, maximumLength: length)
                guard !bytes.isEmpty, bytes.count <= length else { throw BackendContractError.unavailable }
                try Task.checkCancellation()
                try namespace.validate()
                try write(bytes, to: output)
                hash.update(data: bytes)
                offset += UInt64(bytes.count)
                copiedBytes += UInt64(bytes.count)
                try await copyCheckpoint?(offset)
            }
            guard Self.digest(hash.finalize()) == lease.original.content.digest else {
                throw BackendContractError.identityMismatch
            }
            // A successful write/hash is not the writer's actual close. The
            // read-only owner is opened only after synchronize + close return.
            try output.synchronize()
            let written = try OriginalFileFingerprint(descriptor: output.fileDescriptor)
            guard written.size == Int64(lease.original.content.byteCount) else {
                throw BackendContractError.identityMismatch
            }
            try close(output)
            writer = nil
            try namespace.validate()
            let input = try namespace.open(id)
            reader = input
            track(input)
            guard try OriginalFileFingerprint(descriptor: input.fileDescriptor) == written else {
                throw BackendContractError.identityMismatch
            }
            // Independently read every output byte, on the retained descriptor,
            // so the returned identity describes the actual copy's full bytes.
            try verify(input, id: id, fingerprint: written, content: lease.original.content)
            try Task.checkCancellation()
            guard await originals.readerDidFinish(attachment) == .succeeded(lease.id) else {
                throw BackendContractError.unknownResult
            }
            attached = false
            try Task.checkCancellation()
            try namespace.validateFile(id, handle: input, fingerprint: written)
            let identity = ManagedUploadSourceIdentity(id: id,
                directoryDevice: namespace.device, directoryInode: namespace.inode,
                file: Self.identity(written), content: lease.original.content)
            sources[id] = Source(identity: identity, lease: lease, handle: input)
            return identity
        } catch {
            // Failed/incomplete leaves are deliberately retained as unknown.
            // No original, existing temporary file, or external URL is unlinked.
            if let writer { try? close(writer) }
            if let reader { try? close(reader) }
            if attached { _ = await originals.readerDidFinish(attachment) }
            throw error
        }
    }

    /// Marks a source as exposed before returning a URL. Holding our descriptor
    /// cannot pin the file descriptor URLSession may open from this URL. Strict
    /// admission remains closed and no network-resume method is provided here.
    func uploadFile(for identity: ManagedUploadSourceIdentity, lease: OriginalReadLease) throws -> BackgroundMediaUploadFile {
        guard !closed, var source = sources[identity.id], source.identity == identity,
              source.lease == lease, source.terminal == nil, source.closure == nil else {
            throw BackendContractError.identityMismatch
        }
        try validate(source)
        source.exported = true
        sources[identity.id] = source
        return .init(identity: identity, url: namespace.url(for: identity.id))
    }

    /// Call immediately after actual suspended SDK creation, including when the
    /// subsequent durable attach fails. An exposed but unattached source stays
    /// unresolved; task absence or cancellation requests cannot close it.
    func retain(_ identity: ManagedUploadSourceIdentity, lease: OriginalReadLease,
                for binding: BackgroundMediaTaskBinding) throws {
        guard !closed, var source = sources[identity.id], source.identity == identity,
              source.lease == lease, source.exported, source.terminal == nil,
              source.closure == nil, source.binding == nil || source.binding == binding,
              binding.taskIdentifier > 0, !binding.taskDescription.isEmpty else {
            throw BackendContractError.identityMismatch
        }
        // Retain the exact created binding even if the URL was exchanged before
        // this check; its genuine completion is still needed to close our FD.
        source.binding = binding
        sources[identity.id] = source
        try validate(source)
    }

    /// Only the exact actual SDK terminal permits this owner's descriptor close.
    /// Files are retained after closure; no retention/reclamation policy or
    /// original-lease release is inferred from this resource observation.
    func finish(_ identity: ManagedUploadSourceIdentity, lease: OriginalReadLease,
                terminal: BackgroundMediaSDKTerminal) throws -> BackgroundMediaOwnerClosure {
        guard var source = sources[identity.id], source.identity == identity,
              source.lease == lease, source.binding == terminal.binding,
              source.terminal == nil || source.terminal == terminal else {
            throw BackendContractError.identityMismatch
        }
        if let closure = source.closure { return closure }
        source.terminal = terminal
        sources[identity.id] = source
        // A changed root/path does not prevent closing the FD we actually own.
        // It also grants no permission to unlink whatever now occupies the path.
        try close(source.handle)
        let closure = BackgroundMediaOwnerClosure(binding: terminal.binding, uploadSource: identity,
            tasksJoined: true, handlesClosed: true)
        source.closure = closure
        sources[identity.id] = source
        return closure
    }

    func resources() -> ManagedUploadSourceResources {
        .init(activeCopies: copying.count, openHandles: handles.count, closedHandles: closedHandles,
            largestOriginalRead: largestOriginalRead, copiedBytes: copiedBytes,
            descriptors: handles.values.map(\.fileDescriptor).sorted())
    }

    /// This does not close live/exposed sources. Every source must first receive
    /// its own terminal and finish; unknown on-disk leaves remain untouched.
    func closeOwner() throws -> ManagedUploadSourceResources {
        guard copying.isEmpty, handles.isEmpty,
              sources.values.allSatisfy({ $0.closure != nil }) else {
            throw BackendContractError.readersActive
        }
        if !closed {
            try namespace.close()
            closed = true
        }
        return resources()
    }

    private func validate(_ source: Source) throws {
        guard source.identity.directoryDevice == namespace.device,
              source.identity.directoryInode == namespace.inode,
              source.identity.content == source.lease.original.content,
              handles[ObjectIdentifier(source.handle)] != nil else {
            throw BackendContractError.identityMismatch
        }
        let fingerprint: OriginalFileFingerprint
        do { fingerprint = try OriginalFileFingerprint(descriptor: source.handle.fileDescriptor) }
        catch { throw BackendContractError.identityMismatch }
        guard Self.identity(fingerprint) == source.identity.file else { throw BackendContractError.identityMismatch }
        try namespace.validateFile(source.identity.id, handle: source.handle, fingerprint: fingerprint)
    }

    private func verify(_ handle: FileHandle, id: ManagedUploadSourceID,
                        fingerprint: OriginalFileFingerprint, content: ContentIdentity) throws {
        var hash = SHA256(), offset: UInt64 = 0
        while offset < content.byteCount {
            try Task.checkCancellation()
            try namespace.validateFile(id, handle: handle, fingerprint: fingerprint)
            let length = Int(min(65_536, content.byteCount - offset))
            var bytes = [UInt8](repeating: 0, count: length)
            var received: Int
            repeat { received = pread(handle.fileDescriptor, &bytes, length, off_t(offset)) }
            while received < 0 && errno == EINTR
            guard received > 0, received <= length else { throw BackendContractError.unavailable }
            try namespace.validateFile(id, handle: handle, fingerprint: fingerprint)
            hash.update(data: Data(bytes.prefix(received)))
            offset += UInt64(received)
        }
        guard Self.digest(hash.finalize()) == content.digest else { throw BackendContractError.identityMismatch }
        try namespace.validateFile(id, handle: handle, fingerprint: fingerprint)
    }

    private func write(_ bytes: Data, to handle: FileHandle) throws {
        try bytes.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { throw BackendContractError.invalidValue }
            var offset = 0
            while offset < buffer.count {
                var count: Int
                repeat { count = Darwin.write(handle.fileDescriptor, base.advanced(by: offset), buffer.count - offset) }
                while count < 0 && errno == EINTR
                guard count > 0 else { throw BackendContractError.unavailable }
                offset += count
            }
        }
    }

    private func track(_ handle: FileHandle) { handles[ObjectIdentifier(handle)] = handle }
    private func close(_ handle: FileHandle) throws {
        guard handles[ObjectIdentifier(handle)] != nil else { return }
        try handle.close()
        handles.removeValue(forKey: ObjectIdentifier(handle))
        closedHandles += 1
    }

    private static func digest(_ hash: SHA256.Digest) -> String {
        hash.map { String(format: "%02x", $0) }.joined()
    }
    private static func identity(_ fingerprint: OriginalFileFingerprint) -> ManagedUploadFileIdentity {
        .init(device: fingerprint.device, inode: fingerprint.inode, size: fingerprint.size,
            modifiedSeconds: fingerprint.modifiedSeconds, modifiedNanoseconds: fingerprint.modifiedNanoseconds,
            changedSeconds: fingerprint.changedSeconds, changedNanoseconds: fingerprint.changedNanoseconds)
    }
}

/// Only ManagedUploadSource accesses these descriptors. Both the named run and
/// the fixed namespace must continue identifying the pinned directories; all
/// source operations use openat/fstatat with no-follow and create-only flags.
private nonisolated final class ManagedUploadNamespace {
    static let name = "background-upload-sources"
    let device: Int64
    let inode: UInt64
    private let run: ExplorationRunDirectory
    private let parent: FileHandle
    private let directory: FileHandle
    private let lock: FileHandle
    private let parentDevice: Int64
    private let parentInode: UInt64
    private let lockIdentity: OriginalFileFingerprint
    private var parentClosed = false
    private var directoryClosed = false
    private var lockClosed = false

    init(run: ExplorationRunDirectory) throws {
        try run.validate()
        let parentFD = Darwin.open(run.url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard parentFD >= 0 else { throw BackendContractError.unavailable }
        let parent = FileHandle(fileDescriptor: parentFD, closeOnDealloc: true)
        var parentStat = stat()
        guard fstat(parentFD, &parentStat) == 0, parentStat.st_mode & S_IFMT == S_IFDIR else {
            try? parent.close(); throw BackendContractError.identityMismatch
        }
        guard mkdirat(parentFD, Self.name, 0o700) == 0 || errno == EEXIST else {
            try? parent.close(); throw BackendContractError.unavailable
        }
        let fd = openat(parentFD, Self.name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { try? parent.close(); throw BackendContractError.identityMismatch }
        let directory = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else {
            try? directory.close(); try? parent.close(); throw BackendContractError.identityMismatch
        }
        let lockFD = openat(fd, "owner.lock", O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
        guard lockFD >= 0 else {
            try? directory.close(); try? parent.close(); throw BackendContractError.unavailable
        }
        let lock = FileHandle(fileDescriptor: lockFD, closeOnDealloc: true)
        do {
            lockIdentity = try OriginalFileFingerprint(descriptor: lockFD)
            guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { throw BackendContractError.readersActive }
            self.run = run; self.parent = parent; self.directory = directory; self.lock = lock
            device = Int64(info.st_dev); inode = UInt64(info.st_ino)
            parentDevice = Int64(parentStat.st_dev); parentInode = UInt64(parentStat.st_ino)
            try validate()
        } catch {
            try? lock.close(); try? directory.close(); try? parent.close(); throw error
        }
    }

    static func validateID(_ id: ManagedUploadSourceID) throws {
        guard let uuid = UUID(uuidString: id.rawValue),
              uuid.uuidString.lowercased() == id.rawValue.lowercased() else {
            throw BackendContractError.invalidValue
        }
    }
    static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private func leaf(_ id: ManagedUploadSourceID) throws -> String {
        try Self.validateID(id)
        return id.rawValue + ".upload"
    }
    func url(for id: ManagedUploadSourceID) -> URL {
        run.url.appendingPathComponent(Self.name, isDirectory: true).appendingPathComponent(id.rawValue + ".upload")
    }

    func validate() throws {
        guard !parentClosed, !directoryClosed, !lockClosed else { throw BackendContractError.wrongStage }
        try run.validate()
        var namedParent = stat(), openedParent = stat(), named = stat(), opened = stat(), namedLock = stat()
        guard lstat(run.url.path, &namedParent) == 0, fstat(parent.fileDescriptor, &openedParent) == 0,
              namedParent.st_mode & S_IFMT == S_IFDIR, openedParent.st_mode & S_IFMT == S_IFDIR,
              Int64(openedParent.st_dev) == parentDevice, UInt64(openedParent.st_ino) == parentInode,
              namedParent.st_dev == openedParent.st_dev, namedParent.st_ino == openedParent.st_ino,
              fstatat(parent.fileDescriptor, Self.name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              fstat(directory.fileDescriptor, &opened) == 0,
              named.st_mode & S_IFMT == S_IFDIR, opened.st_mode & S_IFMT == S_IFDIR,
              Int64(opened.st_dev) == device, UInt64(opened.st_ino) == inode,
              named.st_dev == opened.st_dev, named.st_ino == opened.st_ino,
              fstatat(directory.fileDescriptor, "owner.lock", &namedLock, AT_SYMLINK_NOFOLLOW) == 0,
              try OriginalFileFingerprint(info: namedLock) == lockIdentity,
              try OriginalFileFingerprint(descriptor: lock.fileDescriptor) == lockIdentity else {
            throw BackendContractError.identityMismatch
        }
    }

    func create(_ id: ManagedUploadSourceID) throws -> FileHandle {
        try validate()
        let fd = openat(directory.fileDescriptor, try leaf(id), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw errno == EEXIST ? BackendContractError.identityMismatch : .unavailable }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }
    func open(_ id: ManagedUploadSourceID) throws -> FileHandle {
        try validate()
        let fd = openat(directory.fileDescriptor, try leaf(id), O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw BackendContractError.identityMismatch }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }
    func validateFile(_ id: ManagedUploadSourceID, handle: FileHandle, fingerprint: OriginalFileFingerprint) throws {
        try validate()
        var named = stat()
        guard fstatat(directory.fileDescriptor, try leaf(id), &named, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw BackendContractError.identityMismatch
        }
        do {
            guard try OriginalFileFingerprint(info: named) == fingerprint,
                  try OriginalFileFingerprint(descriptor: handle.fileDescriptor) == fingerprint else {
                throw BackendContractError.identityMismatch
            }
        } catch { throw BackendContractError.identityMismatch }
    }
    func close() throws {
        if !directoryClosed { try directory.close(); directoryClosed = true }
        if !parentClosed { try parent.close(); parentClosed = true }
        if !lockClosed { try lock.close(); lockClosed = true }
    }
}
