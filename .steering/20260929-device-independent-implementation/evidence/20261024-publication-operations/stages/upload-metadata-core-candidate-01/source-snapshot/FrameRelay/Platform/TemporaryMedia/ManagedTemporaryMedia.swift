import CryptoKit
import Darwin
import Foundation

/// Actor-confined file handles and common-writer metadata. No independent
/// manifest database, retention timer, or arbitrary capacity policy is used.
actor ManagedTemporaryMedia: TemporaryMediaWritingPort, TemporaryLocalMediaPort, PhotoTemporaryUsageRecoveryPort {
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
    /// Set before either close call: a partial/failed close is never permission
    /// to ask Foundation for a closed FileHandle's descriptor again.
    private var rootHandlesOpen = true
    private var terminal: RenditionReadTerminal?
    private var busy: Set<TemporaryMediaID> = []
    private var handles: [MediaUsageID: OpenUse] = [:]
    private var photoConsumers: Set<MediaUsageID> = []
    private var finishedPhotoUsages: Set<MediaUsageID> = []
    private var photoLifetime: ManagedTemporaryMedia?
    private var integrityFailures: Set<TemporaryMediaID> = []
    private var closedHandles = 0
    private var openedHandles = 0
    private var allFileHandles: [ObjectIdentifier: FileHandle] = [:]
    private var photoRecoveryMutations: [MediaOperationID: BackendStoreMutation] = [:]
    private var photoRecoveries: [MediaOperationID: PhotoRecovery] = [:]

    private init(root: URL, leases: RenditionReadLeases, original: OriginalContent, epoch: ReaderReconciliationEpoch, createIfMissing: Bool) throws {
        let normalized = root.standardizedFileURL
        // Resolving an absent directory may remove its URL's trailing slash.
        // Compare filesystem paths while still rejecting symlink redirection.
        guard normalized.isFileURL, normalized.resolvingSymlinksInPath().path == normalized.path else {
            throw BackendContractError.invalidValue
        }
        if !FileManager.default.fileExists(atPath: normalized.path) {
            guard createIfMissing else { throw BackendContractError.unavailable }
            try FileManager.default.createDirectory(at: normalized, withIntermediateDirectories: false)
        }
        let descriptor = Darwin.open(normalized.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard descriptor >= 0 else { throw BackendContractError.unavailable }
        directory = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw BackendContractError.unavailable }
        directoryIdentity = .init(device: Int64(info.st_dev), inode: UInt64(info.st_ino))
        let lock = openat(descriptor, "owner.lock", O_RDWR | O_NOFOLLOW | (createIfMissing ? O_CREAT : 0), S_IRUSR | S_IWUSR)
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

    static func open(root: URL, leases: RenditionReadLeases, scope: RenditionMediaScope,
                     createIfMissing: Bool = true) async throws -> ManagedTemporaryMedia {
        let value = try ManagedTemporaryMedia(root: root, leases: leases, original: scope.original, epoch: scope.epoch,
            createIfMissing: createIfMissing)
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
            leaf: try TemporaryMediaLeaf.make(contentType: contentType), contentType: contentType,
            directoryIdentity: directoryIdentity)
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
        if usage.purpose == .photoHandoff {
            guard case .loaded(let snapshot) = await leases.mediaStore.load() else { return .unknown }
            if let record = snapshot.photoRegistrations.last(where: { $0.registration.intent.usage == usage }) {
                if record.usageTerminal != nil { return await recoverTerminalPhotoUsage(record) }
                if case .succeeded? = record.outcome { return await recoverSuccessfulPhotoUsage(record) }
                return .unknown
            }
        }
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
        return .init(url: root.appendingPathComponent(state.leaf), handoff: handoff, contentType: state.contentType)
    }

    /// Called after actual PhotoKit completion or definite SDK non-start, never
    /// merely because a caller requested cancellation.
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
        finishedPhotoUsages.insert(usage.id)
    }

    func photoUsageTerminal(_ registration: CommittedPhotoRegistrationIntent,
                            termination: PhotoUsageTermination) async throws -> PhotoUsageTerminal {
        let intent = registration.intent
        guard busy.insert(intent.media).inserted else { throw BackendContractError.readersActive }
        defer { busy.remove(intent.media) }
        let state = try await stateFor(intent.media)
        let use = try await requireUse(intent.usage, state: state, allowInvalidated: true)
        guard registration.isCommitted, registration.mediaUse == use,
              registration.directoryIdentity == directoryIdentity,
              state.directoryIdentity == registration.directoryIdentity,
              state.fileIdentity == registration.fileIdentity,
              !photoConsumers.contains(intent.usage.id), handles[intent.usage.id] == nil,
              !hasUnassignedHandles, !integrityFailures.contains(state.id) else { throw BackendContractError.identityMismatch }
        if termination == .sdkCompleted {
            guard finishedPhotoUsages.contains(intent.usage.id) else { throw BackendContractError.readersActive }
        }
        try validateFileIdentity(state)
        return try .init(registration: registration, termination: termination)
    }

    /// The kernel root lock excludes an older live file owner. A successful
    /// record is accepted only after rereading and exact lookup under the same
    /// writer; it releases that photo use, never all old-epoch readers.
    func recoverSuccessfulPhotoUsage(_ proposed: PhotoRegistrationRecord) async -> BackendOutcome<TemporaryMediaID> {
        await recoverPhotoUsage(proposed, requiringTerminal: false)
    }

    func recoverTerminalPhotoUsage(_ proposed: PhotoRegistrationRecord) async -> BackendOutcome<TemporaryMediaID> {
        await recoverPhotoUsage(proposed, requiringTerminal: true)
    }

    private func recoverPhotoUsage(_ proposed: PhotoRegistrationRecord,
                                  requiringTerminal: Bool) async -> BackendOutcome<TemporaryMediaID> {
        let intent = proposed.registration.intent
        guard intent.rendition.original == original else { return .notExecuted }
        if let current = photoRecoveries[intent.operation] {
            guard current.requiringTerminal == requiringTerminal,
                  samePhotoRecoveryAuthority(current.record, proposed) else { return .unknown }
            return await current.task.value
        }
        let id = UUID()
        let task = Task { await self.performPhotoRecovery(proposed, requiringTerminal: requiringTerminal) }
        photoRecoveries[intent.operation] = .init(id: id, record: proposed, requiringTerminal: requiringTerminal, task: task)
        let result = await task.value
        if photoRecoveries[intent.operation]?.id == id { photoRecoveries.removeValue(forKey: intent.operation) }
        return result
    }

    /// The scope and a caller may retire the same terminal use concurrently.
    /// Their exact recovery shares one task; no scope-close task is joined here.
    private func performPhotoRecovery(_ proposed: PhotoRegistrationRecord,
                                     requiringTerminal: Bool) async -> BackendOutcome<TemporaryMediaID> {
        let intent = proposed.registration.intent
        guard busy.insert(intent.media).inserted else { return .inProgress }
        defer { busy.remove(intent.media) }
        do {
            let store = leases.mediaStore
            guard case .loaded(let snapshot) = await store.load(),
                  let record = snapshot.photoRegistrations.first(where: { $0.registration.intent == intent }),
                  record.registration == proposed.registration, record.results == proposed.results,
                  record.usageTerminal == proposed.usageTerminal,
                  let state = snapshot.temporaryMedia.first(where: { $0.id == intent.media }),
                  state.rendition.original == original, state.directoryIdentity == directoryIdentity,
                  record.registration.directoryIdentity == directoryIdentity,
                  state.fileIdentity == record.registration.fileIdentity,
                  !photoConsumers.contains(intent.usage.id), handles[intent.usage.id] == nil,
                  !hasUnassignedHandles, !integrityFailures.contains(state.id) else { return .unknown }
            if let expected = record.registration.expectedStoreIdentity {
                guard snapshot.storeIdentity == expected else { return .unknown }
            }
            guard case .committed(let intentCommit) = await store.lookupCommit(record.registration.mutation),
                  intentCommit == record.registration.commit else { return .unknown }
            if requiringTerminal {
                guard let terminal = record.usageTerminal,
                      case .committed(let terminalCommit) = await store.lookupCommit(terminal.mutation),
                      terminalCommit == terminal.commit else { return .unknown }
            } else {
                guard let success = record.results.last, case .succeeded = success.result.outcome,
                      case .committed(let successCommit) = await store.lookupCommit(success.mutation),
                      successCommit == success.commit else { return .unknown }
            }
            // Successful cleanup additionally confirms the exact result. A
            // terminal alone releases the reader, never an uncertain copy.
            if let success = record.results.last, case .succeeded = success.result.outcome {
                guard case .committed(let resultCommit) = await store.lookupCommit(success.mutation),
                      resultCommit == success.commit else { return .unknown }
            }
            if state.releasedUsages.contains(record.registration.mediaUse) {
                guard !state.usages.contains(record.registration.mediaUse),
                      await confirmsReleasedPhotoUse(record) else { return .unknown }
                if !rootHandlesOpen {
                    // A durable single-use release is not an owner terminal.
                    // This branch additionally requires this owner to have
                    // actually closed every descriptor. It performs reads only.
                    guard let terminal, terminal.epoch == epoch,
                          terminal.started == terminal.completed, terminal.handlesClosed,
                          case .loaded(let latest) = await store.load(), latest.storeIdentity == snapshot.storeIdentity,
                          let current = latest.photoRegistrations.first(where: { $0.registration.intent == intent }),
                          samePhotoRecoveryAuthority(current, record), current.usageRelease == record.usageRelease,
                          current.terminalUsageRelease == record.terminalUsageRelease,
                          let media = latest.temporaryMedia.first(where: { $0.id == intent.media }),
                          media.rendition == state.rendition, media.directoryIdentity == directoryIdentity,
                          media.fileIdentity == state.fileIdentity, media.releasedUsages.contains(record.registration.mediaUse),
                          !media.usages.contains(record.registration.mediaUse) else { return .unknown }
                    photoRecoveryMutations.removeValue(forKey: intent.operation)
                    return .succeeded(state.id)
                }
                try requireRoot()
                if !state.reclaiming, !state.reclaimed { try validateFileIdentity(state) }
                try await reclaimIfEligible(state)
                photoRecoveryMutations.removeValue(forKey: intent.operation)
                return .succeeded(state.id)
            }
            try requireRoot()
            if !state.reclaiming, !state.reclaimed { try validateFileIdentity(state) }
            guard state.usages.contains(record.registration.mediaUse), !state.reclaimed, !state.reclaiming else { return .unknown }
            let change: PhotoRegistrationChange = requiringTerminal
                ? .releaseTerminalUsage(try PhotoTerminalUsageRelease(record: record))
                : .releaseUsage(try PhotoUsageRelease(record: record))
            for _ in 0..<3 {
                let mutation: BackendStoreMutation
                if let retained = photoRecoveryMutations[intent.operation] {
                    mutation = retained
                } else {
                    guard case .loaded(let current) = await store.load() else { return .unknown }
                    mutation = .init(expectedRevision: current.revision,
                        change: .photo(command: .init(rawValue: UUID().uuidString), value: change),
                        expectedStoreIdentity: record.registration.expectedStoreIdentity)
                    photoRecoveryMutations[intent.operation] = mutation
                    let result = await store.commit(mutation)
                    if case .rejected(.revisionConflict) = result {
                        photoRecoveryMutations.removeValue(forKey: intent.operation); continue
                    }
                    if case .rejected = result { photoRecoveryMutations.removeValue(forKey: intent.operation); return .unknown }
                }
                guard case .committed(let receipt) = await store.lookupCommit(mutation),
                      receipt.matches(mutation.change.key, revision: mutation.expectedRevision) else { return .unknown }
                photoRecoveryMutations.removeValue(forKey: intent.operation)
                let latest = try await stateFor(state.id)
                guard latest.releasedUsages.contains(record.registration.mediaUse),
                      !latest.usages.contains(record.registration.mediaUse) else { return .unknown }
                finishedPhotoUsages.remove(intent.usage.id)
                try await reclaimIfEligible(latest)
                return .succeeded(state.id)
            }
            return .unknown
        } catch { return .unknown }
    }

    private func samePhotoRecoveryAuthority(_ lhs: PhotoRegistrationRecord, _ rhs: PhotoRegistrationRecord) -> Bool {
        lhs.registration == rhs.registration && lhs.results == rhs.results && lhs.usageTerminal == rhs.usageTerminal
    }

    /// Check the writer's exact original authorization and release, not merely
    /// membership of a usage ID in a projection. Neither path retires a peer.
    private func confirmsReleasedPhotoUse(_ record: PhotoRegistrationRecord) async -> Bool {
        let store = leases.mediaStore
        if let release = record.terminalUsageRelease {
            guard let expected = try? PhotoTerminalUsageRelease(record: record), release.release == expected,
                  case .committed(let receipt) = await store.lookupCommit(release.mutation), receipt == release.commit else { return false }
            return true
        }
        guard let release = record.usageRelease, let directory = record.registration.directoryIdentity,
              let file = record.registration.fileIdentity,
              release.release.intent == record.registration.intent, release.release.mediaUse == record.registration.mediaUse,
              release.release.directoryIdentity == directory, release.release.fileIdentity == file,
              let success = record.results.first(where: {
                  $0.command == release.release.successCommand && $0.commit == release.release.successCommit
              }), case .succeeded = success.result.outcome,
              case .committed(let successCommit) = await store.lookupCommit(success.mutation), successCommit == success.commit,
              case .committed(let receipt) = await store.lookupCommit(release.mutation), receipt == release.commit else { return false }
        return true
    }

    private struct PhotoRecovery {
        let id: UUID
        let record: PhotoRegistrationRecord
        let requiringTerminal: Bool
        let task: Task<BackendOutcome<TemporaryMediaID>, Never>
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
        guard !(try await retainsPhotoCopy(state.id)) else { throw BackendContractError.readersActive }
        try requireRoot()
        var info = stat()
        if fstatat(directory.fileDescriptor, state.leaf, &info, AT_SYMLINK_NOFOLLOW) == 0 {
            try validateFileIdentity(state)
            guard unlinkat(directory.fileDescriptor, state.leaf, 0) == 0 else { throw BackendContractError.unavailable }
        } else if errno != ENOENT { throw BackendContractError.unavailable }
        try await persist(.reclaimed(state.id))
    }

    private func retainsPhotoCopy(_ id: TemporaryMediaID) async throws -> Bool {
        guard case .loaded(let snapshot) = await leases.mediaStore.load() else { throw BackendContractError.unavailable }
        return PhotoRegistrationRecord.retainsCopy(id, in: snapshot.photoRegistrations)
    }

    private func reclaimIfEligible(_ state: TemporaryMediaState) async throws {
        guard state.usages.isEmpty, !state.reclaimed, !(try await retainsPhotoCopy(state.id)) else { return }
        if !state.reclaiming { try await persist(.reclaim(state.id)) }
        try await finishReclamation(try await stateFor(state.id))
    }

    private func closeOwner() async throws -> RenditionReadTerminal {
        if let terminal { return terminal }
        closed = true
        guard busy.isEmpty, photoConsumers.isEmpty else { throw BackendContractError.readersActive }
        guard case .loaded(let snapshot) = await leases.mediaStore.load() else { throw BackendContractError.unavailable }
        var pendingPhotoUsage = false
        for state in snapshot.temporaryMedia where state.rendition.original == original && state.directoryIdentity == directoryIdentity {
            for record in state.usages {
                if record.usage.purpose == .photoHandoff {
                    guard let photo = snapshot.photoRegistrations.last(where: { $0.registration.mediaUse == record }) else {
                        pendingPhotoUsage = true; continue
                    }
                    let released: BackendOutcome<TemporaryMediaID>
                    if photo.usageTerminal != nil { released = await recoverTerminalPhotoUsage(photo) }
                    else if case .succeeded? = photo.outcome { released = await recoverSuccessfulPhotoUsage(photo) }
                    else { pendingPhotoUsage = true; continue }
                    guard released == .succeeded(state.id) else { throw BackendContractError.unknownResult }
                    continue
                }
                guard record.owner == owner, record.lease.epoch == epoch else { throw BackendContractError.staleGeneration }
                guard case .succeeded = await releaseUsage(record.usage) else { throw BackendContractError.unknownResult }
            }
            try await reclaimIfEligible(try await stateFor(state.id))
        }
        let currentEpoch = try await leases.currentEpoch()
        guard !pendingPhotoUsage, busy.isEmpty, handles.isEmpty, allFileHandles.isEmpty, openedHandles == closedHandles,
              epoch == currentEpoch, rootHandlesOpen else { throw BackendContractError.readersActive }
        rootHandlesOpen = false
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
        try TemporaryMediaLeaf.validate(state.leaf, contentType: state.contentType)
        guard state.directoryIdentity == directoryIdentity else { throw BackendContractError.invalidValue }
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
        guard rootHandlesOpen else { throw BackendContractError.identityMismatch }
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

    /// A helper FD whose close failed must not disappear behind a removed
    /// consumer entry. Known handles owned by other consumers stay untouched.
    private var hasUnassignedHandles: Bool {
        allFileHandles.keys.contains { identifier in
            !handles.values.contains { ObjectIdentifier($0.handle) == identifier }
        }
    }
}
