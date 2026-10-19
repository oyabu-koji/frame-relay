import CryptoKit
import Darwin
import Foundation

/// Actor-confined file handles and common-writer metadata. No independent
/// manifest database, retention timer, or arbitrary capacity policy is used.
actor ManagedTemporaryMedia: TemporaryMediaWritingPort, TemporaryLocalMediaPort {
    private let root: URL
    private let directory: FileHandle
    private let rootLock: FileHandle
    private let directoryIdentity: TemporaryFileIdentity
    private let leases: RenditionReadLeases
    private let original: OriginalContent
    private let epoch: ReaderReconciliationEpoch
    private let owner = UUID().uuidString
    private var permit: RenditionScopePermit?
    private var closed = false
    private var terminal: RenditionReadTerminal?
    private var busy: Set<TemporaryMediaID> = []
    private var handles: [MediaUsageID: OpenUse] = [:]
    private var photoConsumers: Set<MediaUsageID> = []
    private var photoLifetime: ManagedTemporaryMedia?
    private var integrityFailures: Set<TemporaryMediaID> = []
    private var closedHandles = 0
    private var openedHandles = 0
    private var allFileHandles: [ObjectIdentifier: FileHandle] = [:]

    private init(root: URL, leases: RenditionReadLeases, original: OriginalContent, epoch: ReaderReconciliationEpoch) throws {
        let normalized = root.standardizedFileURL
        // Resolving an absent directory may remove its URL's trailing slash.
        // Compare filesystem paths while still rejecting symlink redirection.
        guard normalized.isFileURL, normalized.resolvingSymlinksInPath().path == normalized.path else {
            throw BackendContractError.invalidValue
        }
        if !FileManager.default.fileExists(atPath: normalized.path) {
            try FileManager.default.createDirectory(at: normalized, withIntermediateDirectories: false)
        }
        let descriptor = Darwin.open(normalized.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw BackendContractError.unavailable }
        directory = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw BackendContractError.unavailable }
        directoryIdentity = .init(device: Int64(info.st_dev), inode: UInt64(info.st_ino))
        let lock = openat(descriptor, "owner.lock", O_RDWR | O_CREAT | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard lock >= 0 else { throw BackendContractError.unavailable }
        let lockHandle = FileHandle(fileDescriptor: lock, closeOnDealloc: true)
        _ = try OriginalFileFingerprint(descriptor: lock)
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            try lockHandle.close(); throw BackendContractError.readersActive
        }
        rootLock = lockHandle
        self.root = normalized; self.leases = leases
        self.original = original; self.epoch = epoch
    }

    static func open(root: URL, leases: RenditionReadLeases, scope: RenditionMediaScope) async throws -> ManagedTemporaryMedia {
        let value = try ManagedTemporaryMedia(root: root, leases: leases, original: scope.original, epoch: scope.epoch)
        let permit = try await scope.register(owner: .temporaryMedia) { try await value.closeOwner() }
        await value.activate(permit)
        return value
    }
    private func activate(_ permit: RenditionScopePermit) { self.permit = permit }
    private func admit() async throws {
        guard !closed, let permit else { throw BackendContractError.wrongStage }
        try await permit.check()
    }

    func create(command: RetrieveMediaCommand, id: TemporaryMediaID, usageID: MediaUsageID,
                capturedAt: Date, contentType: String) async throws -> TemporaryMediaReceipt {
        try await admit()
        guard command.identitiesMatch, command.distribution.rendition.original == original,
              busy.insert(id).inserted else { throw BackendContractError.invalidValue }
        defer { busy.remove(id) }
        let state = TemporaryMediaState(id: id, rendition: command.distribution.rendition,
            registration: command.distribution.registration, capturedAt: capturedAt,
            leaf: UUID().uuidString, contentType: contentType, directoryIdentity: directoryIdentity)
        try await persist(.create(state))
        try await admit()
        let handle = try openFile(state, flags: O_WRONLY | O_CREAT | O_EXCL)
        let identity = try identityOf(handle)
        try handle.synchronize(); try closeHandle(handle)
        try await persist(.fileCreated(state.id, identity))
        let use = try await acquire(try await stateFor(state.id), purpose: .playback, usageID: usageID)
        return try await stateFor(id).receipt(for: use)
    }

    func store(_ bytes: Data, range: MediaByteRange, using usage: TemporaryMediaUsage) async throws {
        guard busy.insert(usage.media).inserted else { throw BackendContractError.readersActive }
        defer { busy.remove(usage.media) }
        let state = try await stateFor(usage.media)
        _ = try await requireUse(usage, state: state)
        guard state.verifiedContent == nil, range.upperBound <= state.rendition.deliveryContent.byteCount,
              UInt64(bytes.count) == range.upperBound - range.lowerBound,
              !state.usages.contains(where: { handles[$0.usage.id] != nil }) else { throw BackendContractError.invalidValue }
        let handle = try openFile(state, flags: O_WRONLY)
        do {
            try handle.seek(toOffset: range.lowerBound)
            try handle.write(contentsOf: bytes)
            try handle.synchronize()
            try closeHandle(handle)
        } catch { try closeHandle(handle); throw error }
        try await persist(.stored(state.id, range))
    }

    func verify(_ usage: TemporaryMediaUsage) async throws -> TemporaryMediaReceipt {
        guard busy.insert(usage.media).inserted else { throw BackendContractError.readersActive }
        defer { busy.remove(usage.media) }
        let state = try await stateFor(usage.media)
        _ = try await requireUse(usage, state: state)
        guard state.complete else { throw BackendContractError.ineligibleOriginal }
        try verifyFile(state)
        try await persist(.verified(state.id, state.rendition.deliveryContent))
        return try await stateFor(state.id).receipt(for: usage)
    }

    func inspect(_ id: TemporaryMediaID) async -> BackendOutcome<TemporaryMediaReceipt> {
        guard busy.insert(id).inserted else { return .inProgress }
        defer { busy.remove(id) }
        do {
            try await admit()
            let state = try await stateFor(id)
            guard !state.reclaimed, let usage = state.usages.first?.usage else { return .notExecuted }
            if state.verifiedContent != nil { try verifyFile(state) }
            else { let handle = try openFile(state, flags: O_RDONLY); try closeHandle(handle) }
            return .succeeded(state.receipt(for: usage))
        } catch { return .failed(.contentMismatch) }
    }

    func acquireUsage(_ id: TemporaryMediaID, purpose: TemporaryMediaPurpose,
                      usageID: MediaUsageID) async -> BackendOutcome<TemporaryMediaUsage> {
        guard busy.insert(id).inserted else { return .inProgress }
        defer { busy.remove(id) }
        do {
            try await admit()
            let state = try await stateFor(id)
            if purpose == .photoHandoff {
                guard state.complete, state.verifiedContent == state.rendition.deliveryContent else {
                    throw BackendContractError.ineligibleOriginal
                }
                try verifyFile(state)
            }
            return .succeeded(try await acquire(state, purpose: purpose, usageID: usageID))
        } catch BackendContractError.unknownResult { return .unknown }
        catch { return .failed(.rejected) }
    }

    func releaseUsage(_ usage: TemporaryMediaUsage) async -> BackendOutcome<TemporaryMediaID> {
        guard busy.insert(usage.media).inserted else { return .inProgress }
        defer { busy.remove(usage.media) }
        do {
            let state = try await stateFor(usage.media)
            guard state.directoryIdentity == directoryIdentity else { throw BackendContractError.identityMismatch }
            if state.releasedUsages.contains(where: { $0.usage == usage && $0.owner == owner }) {
                try await finishReclamation(state)
                return .succeeded(state.id)
            }
            let record = try await requireUse(usage, state: state, allowInvalidated: true)
            guard !photoConsumers.contains(usage.id) else { return .inProgress }
            if let opened = handles[usage.id] {
                do { try validateNamed(opened, state: state) }
                catch { integrityFailures.insert(state.id) }
                try closeHandle(opened.handle)
                handles.removeValue(forKey: usage.id)
            }
            guard !integrityFailures.contains(state.id) else { throw BackendContractError.identityMismatch }
            try validateFileIdentity(state)
            try await persist(.release(state.id, record))
            let current = try await stateFor(state.id)
            try await finishReclamation(current)
            return .succeeded(state.id)
        } catch { return .unknown }
    }

    /// Local reads require a verified complete copy and a live current lease,
    /// but never call the network gate. Offline is not a local file prohibition.
    func read(_ usage: TemporaryMediaUsage, offset: UInt64, length: Int) async throws -> Data {
        guard busy.insert(usage.media).inserted else { throw BackendContractError.readersActive }
        defer { busy.remove(usage.media) }
        let state = try await stateFor(usage.media)
        _ = try await requireUse(usage, state: state)
        guard usage.purpose == .playback, state.complete, state.verifiedContent == state.rendition.deliveryContent,
              length > 0, length <= 65_536, offset < state.rendition.deliveryContent.byteCount,
              UInt64(length) <= state.rendition.deliveryContent.byteCount - offset else {
            throw BackendContractError.ineligibleOriginal
        }
        let opened: OpenUse
        if let existing = handles[usage.id] { opened = existing }
        else {
            let handle = try openFile(state, flags: O_RDONLY)
            do {
                try verifyHandle(handle, state: state)
                opened = OpenUse(handle: handle, fingerprint: try OriginalFileFingerprint(descriptor: handle.fileDescriptor))
                handles[usage.id] = opened
            } catch { try closeHandle(handle); throw error }
        }
        try validateNamed(opened, state: state)
        try opened.handle.seek(toOffset: offset)
        let bytes = try opened.handle.read(upToCount: length) ?? Data()
        guard bytes.count == length,
              try OriginalFileFingerprint(descriptor: opened.handle.fileDescriptor) == opened.fingerprint else {
            throw BackendContractError.identityMismatch
        }
        try validateNamed(opened, state: state)
        return bytes
    }

    func resolvePhotoMedia(_ usage: TemporaryMediaUsage) async throws -> TemporaryLocalMedia {
        guard busy.insert(usage.media).inserted else { throw BackendContractError.readersActive }
        defer { busy.remove(usage.media) }
        let state = try await stateFor(usage.media)
        _ = try await requireUse(usage, state: state)
        let handoff = try state.receipt(for: usage).photoHandoff(expected: state.rendition)
        guard !photoConsumers.contains(usage.id) else { throw BackendContractError.readersActive }
        let handle = try openFile(state, flags: O_RDONLY)
        do {
            try verifyHandle(handle, state: state)
            handles[usage.id] = OpenUse(handle: handle, fingerprint: try OriginalFileFingerprint(descriptor: handle.fileDescriptor))
            if let opened = handles[usage.id] { try validateNamed(opened, state: state) }
        } catch { try closeHandle(handle); handles.removeValue(forKey: usage.id); throw error }
        photoConsumers.insert(usage.id)
        photoLifetime = self
        return .init(url: root.appendingPathComponent(state.leaf), handoff: handoff)
    }

    /// Called from the actual PhotoKit terminal callback, never requestStop.
    func finishPhotoMedia(_ usage: TemporaryMediaUsage) async throws {
        guard busy.insert(usage.media).inserted else { throw BackendContractError.readersActive }
        defer { busy.remove(usage.media) }
        let state = try await stateFor(usage.media)
        _ = try await requireUse(usage, state: state, allowInvalidated: true)
        guard photoConsumers.contains(usage.id), let opened = handles[usage.id] else {
            throw BackendContractError.identityMismatch
        }
        let samePath: Bool
        do { try validateNamed(opened, state: state); samePath = true }
        catch { samePath = false; integrityFailures.insert(state.id) }
        try closeHandle(opened.handle)
        handles.removeValue(forKey: usage.id); photoConsumers.remove(usage.id)
        if photoConsumers.isEmpty { photoLifetime = nil }
        guard samePath else { throw BackendContractError.identityMismatch }
    }

    func usageSnapshot(_ id: TemporaryMediaID) async throws -> (covered: UInt64, fileBytes: UInt64, uses: Int, openHandles: Int, closedHandles: Int) {
        let root = try await rootUsageSnapshot()
        guard let item = root.media.first(where: { $0.media == id }) else { throw BackendContractError.unavailable }
        return (item.coveredBytes, item.logicalFileBytes, item.usages, item.openHandles, root.closedHandles)
    }

    func rootUsageSnapshot() async throws -> TemporaryMediaRootUsage {
        guard try await leases.currentEpoch() == epoch else { throw BackendContractError.staleGeneration }
        guard case .loaded(let snapshot) = await leases.mediaStore.load() else { throw BackendContractError.unavailable }
        guard busy.isEmpty else { throw BackendContractError.readersActive }
        try requireRoot()
        let states = snapshot.temporaryMedia.filter { $0.directoryIdentity == directoryIdentity }
        let knownLeaves = Set(states.map(\.leaf))
        var files: [String: (identity: TemporaryFileIdentity, bytes: UInt64)] = [:]
        var total: UInt64 = 0, unknown: UInt64 = 0, metadata: UInt64 = 0
        var unknownCount = 0
        for name in try FileManager.default.contentsOfDirectory(atPath: root.path) {
            var info = stat()
            guard fstatat(directory.fileDescriptor, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
                throw BackendContractError.unavailable
            }
            guard info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1, info.st_size >= 0 else {
                throw BackendContractError.identityMismatch
            }
            let bytes = UInt64(info.st_size)
            total = try addBytes(total, bytes)
            if name == "owner.lock" { metadata = bytes }
            else {
                files[name] = (.init(device: Int64(info.st_dev), inode: UInt64(info.st_ino)), bytes)
                if !knownLeaves.contains(name) { unknown = try addBytes(unknown, bytes); unknownCount += 1 }
            }
        }
        var items: [TemporaryMediaDiskUsage] = []
        var managed: UInt64 = 0
        for state in states {
            let bytes: UInt64
            if let file = files[state.leaf] {
                guard !state.reclaimed, state.fileIdentity == file.identity else { throw BackendContractError.identityMismatch }
                bytes = file.bytes
            } else {
                // Absence is expected only after a committed reclaim intent;
                // missing active media and stat errors are never zero usage.
                guard (state.reclaiming || state.reclaimed), state.usages.isEmpty else {
                    throw BackendContractError.unavailable
                }
                bytes = 0
            }
            managed = try addBytes(managed, bytes)
            items.append(.init(media: state.id, coveredBytes: state.coveredByteCount, logicalFileBytes: bytes,
                usages: state.usages.count, openHandles: state.usages.filter { handles[$0.usage.id] != nil }.count))
        }
        try requireRoot()
        return .init(media: items, totalFileBytes: total, managedFileBytes: managed, unknownFileBytes: unknown,
            unknownFiles: unknownCount, metadataFileBytes: metadata, usages: items.reduce(0) { $0 + $1.usages },
            openHandles: allFileHandles.count, closedHandles: closedHandles)
    }

    private func addBytes(_ value: UInt64, _ addition: UInt64) throws -> UInt64 {
        let sum = value.addingReportingOverflow(addition)
        guard !sum.overflow else { throw BackendContractError.invalidValue }
        return sum.partialValue
    }

    func stateFor(_ id: TemporaryMediaID) async throws -> TemporaryMediaState {
        guard case .loaded(let snapshot) = await leases.mediaStore.load(),
              let state = snapshot.temporaryMedia.first(where: { $0.id == id }) else {
            throw BackendContractError.unavailable
        }
        return state
    }

    /// Only a committed reclaim intent can be replayed after a crash. Old
    /// active usages remain unknown; a fresh process never releases them by absence.
    func recoverReclamation(_ id: TemporaryMediaID) async throws {
        try await admit()
        guard busy.insert(id).inserted else { throw BackendContractError.readersActive }
        defer { busy.remove(id) }
        let state = try await stateFor(id)
        guard state.directoryIdentity == directoryIdentity, state.reclaiming, state.usages.isEmpty else {
            throw BackendContractError.wrongStage
        }
        try await finishReclamation(state)
    }

    private func finishReclamation(_ state: TemporaryMediaState) async throws {
        guard state.reclaiming, !state.reclaimed else { return }
        guard state.usages.isEmpty, !integrityFailures.contains(state.id) else { throw BackendContractError.readersActive }
        try requireRoot()
        var info = stat()
        if fstatat(directory.fileDescriptor, state.leaf, &info, AT_SYMLINK_NOFOLLOW) == 0 {
            try validateFileIdentity(state)
            guard unlinkat(directory.fileDescriptor, state.leaf, 0) == 0 else { throw BackendContractError.unavailable }
        } else if errno != ENOENT { throw BackendContractError.unavailable }
        try await persist(.reclaimed(state.id))
    }

    private func closeOwner() async throws -> RenditionReadTerminal {
        if let terminal { return terminal }
        closed = true
        guard busy.isEmpty, photoConsumers.isEmpty else { throw BackendContractError.readersActive }
        guard case .loaded(let snapshot) = await leases.mediaStore.load() else { throw BackendContractError.unavailable }
        var pendingPhotoUsage = false
        for state in snapshot.temporaryMedia where state.rendition.original == original && state.directoryIdentity == directoryIdentity {
            for record in state.usages {
                guard record.owner == owner, record.lease.epoch == epoch else { throw BackendContractError.staleGeneration }
                // A finished SDK callback is not a successful Photos registration.
                // S31 explicitly releases this right after its success commit.
                if record.usage.purpose == .photoHandoff { pendingPhotoUsage = true; continue }
                guard case .succeeded = await releaseUsage(record.usage) else { throw BackendContractError.unknownResult }
            }
            if state.usages.isEmpty, !state.reclaiming, !state.reclaimed { try await persist(.reclaim(state.id)) }
            try await finishReclamation(try await stateFor(state.id))
        }
        guard !pendingPhotoUsage, handles.isEmpty, allFileHandles.isEmpty, openedHandles == closedHandles,
              epoch == (try await leases.currentEpoch()) else { throw BackendContractError.readersActive }
        try directory.close()
        try rootLock.close()
        let result = RenditionReadTerminal(epoch: epoch, started: openedHandles, completed: closedHandles,
                                          bytes: 0, handlesClosed: true)
        terminal = result
        return result
    }

    private func acquire(_ state: TemporaryMediaState, purpose: TemporaryMediaPurpose,
                         usageID: MediaUsageID) async throws -> TemporaryMediaUsage {
        if let existing = state.usages.first(where: { $0.usage.id == usageID }) {
            guard existing.owner == owner, existing.usage.purpose == purpose else { throw BackendContractError.identityMismatch }
            _ = try await requireUse(existing.usage, state: state)
            return existing.usage
        }
        guard !state.reclaiming, !state.reclaimed,
              !state.usages.contains(where: { $0.usage.id == usageID }) else { throw BackendContractError.wrongStage }
        try await admit()
        guard state.directoryIdentity == directoryIdentity else { throw BackendContractError.identityMismatch }
        return try await leases.acquireTemporary(state, purpose: purpose, usageID: usageID, owner: owner).usage
    }

    private func requireUse(_ usage: TemporaryMediaUsage, state: TemporaryMediaState,
                            allowInvalidated: Bool = false) async throws -> TemporaryMediaUseRecord {
        guard !state.reclaimed, let record = state.usages.first(where: { $0.usage == usage }),
              record.owner == owner, state.directoryIdentity == directoryIdentity,
              usage.epoch == (try await leases.currentEpoch()) else { throw BackendContractError.staleGeneration }
        if !allowInvalidated { try await admit(); try await leases.check(record.lease) }
        return record
    }

    private func persist(_ change: TemporaryMediaChange) async throws {
        try await leases.commit(.temporary(command: .init(rawValue: UUID().uuidString), value: change))
    }

    private func openFile(_ state: TemporaryMediaState, flags: Int32) throws -> FileHandle {
        try requireRoot()
        guard state.directoryIdentity == directoryIdentity, UUID(uuidString: state.leaf) != nil else { throw BackendContractError.invalidValue }
        let fd = openat(directory.fileDescriptor, state.leaf, flags | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw BackendContractError.unavailable }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        openedHandles += 1
        allFileHandles[ObjectIdentifier(handle)] = handle
        do { _ = try OriginalFileFingerprint(descriptor: fd) }
        catch { try closeHandle(handle); throw error }
        if let identity = state.fileIdentity, identity != (try identityOf(handle)) {
            try closeHandle(handle); throw BackendContractError.identityMismatch
        }
        return handle
    }

    private func closeHandle(_ handle: FileHandle) throws {
        guard allFileHandles[ObjectIdentifier(handle)] != nil else { return }
        try handle.close()
        allFileHandles.removeValue(forKey: ObjectIdentifier(handle))
        closedHandles += 1
    }

    private func identityOf(_ handle: FileHandle) throws -> TemporaryFileIdentity {
        let value = try OriginalFileFingerprint(descriptor: handle.fileDescriptor)
        return .init(device: value.device, inode: value.inode)
    }

    private func validateFileIdentity(_ state: TemporaryMediaState) throws {
        try requireRoot()
        var info = stat()
        guard state.directoryIdentity == directoryIdentity, let identity = state.fileIdentity,
              fstatat(directory.fileDescriptor, state.leaf, &info, AT_SYMLINK_NOFOLLOW) == 0,
              info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1,
              identity == TemporaryFileIdentity(device: Int64(info.st_dev), inode: UInt64(info.st_ino)) else {
            throw BackendContractError.identityMismatch
        }
    }

    private func validateNamed(_ opened: OpenUse, state: TemporaryMediaState) throws {
        try validateFileIdentity(state)
        guard try OriginalFileFingerprint(descriptor: opened.handle.fileDescriptor) == opened.fingerprint else {
            throw BackendContractError.identityMismatch
        }
        let named = try openFile(state, flags: O_RDONLY)
        do {
            let fingerprint = try OriginalFileFingerprint(descriptor: named.fileDescriptor)
            try closeHandle(named)
            guard fingerprint == opened.fingerprint else { throw BackendContractError.identityMismatch }
        } catch { try closeHandle(named); throw error }
    }

    private func requireRoot() throws {
        var opened = stat()
        var named = stat()
        var openedLock = stat()
        var namedLock = stat()
        guard root.resolvingSymlinksInPath().path == root.path,
              fstat(directory.fileDescriptor, &opened) == 0, lstat(root.path, &named) == 0,
              named.st_mode & S_IFMT == S_IFDIR, opened.st_dev == named.st_dev,
              opened.st_ino == named.st_ino,
              fstat(rootLock.fileDescriptor, &openedLock) == 0,
              fstatat(directory.fileDescriptor, "owner.lock", &namedLock, AT_SYMLINK_NOFOLLOW) == 0,
              namedLock.st_mode & S_IFMT == S_IFREG, namedLock.st_nlink == 1,
              openedLock.st_dev == namedLock.st_dev, openedLock.st_ino == namedLock.st_ino else {
            throw BackendContractError.identityMismatch
        }
    }

    private func verifyFile(_ state: TemporaryMediaState) throws {
        let handle = try openFile(state, flags: O_RDONLY)
        do { try verifyHandle(handle, state: state); try closeHandle(handle) }
        catch { try closeHandle(handle); throw error }
    }

    private func verifyHandle(_ handle: FileHandle, state: TemporaryMediaState) throws {
        let before = try OriginalFileFingerprint(descriptor: handle.fileDescriptor)
        guard before.size >= 0, UInt64(before.size) == state.rendition.deliveryContent.byteCount else {
            throw BackendContractError.identityMismatch
        }
        try handle.seek(toOffset: 0)
        var hash = SHA256()
        while let bytes = try handle.read(upToCount: 65_536), !bytes.isEmpty { hash.update(data: bytes) }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == state.rendition.deliveryContent.digest,
              try OriginalFileFingerprint(descriptor: handle.fileDescriptor) == before else {
            throw BackendContractError.identityMismatch
        }
    }

    private struct OpenUse {
        let handle: FileHandle
        let fingerprint: OriginalFileFingerprint
    }
}
