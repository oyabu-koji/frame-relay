import CryptoKit
import Darwin
import Foundation
import Synchronization

nonisolated struct BackgroundDownloadIngressResources: Equatable, Sendable {
    let registeredSlots: Int
    let pinnedArtifacts: Int
    let openHandles: Int
    let closedHandles: Int
    let activeWorkers: Int
    let largestRead: Int
    let readBytes: UInt64
}

/// Stop admission is independent of the worker's executor/FD. It never closes
/// a descriptor while pread or a caller's asynchronous checkpoint is in flight.
nonisolated final class BackgroundDownloadAbortSeal: Sendable {
    private let stopped = Mutex(false)
    func requestStop() { stopped.withLock { $0 = true } }
    var isStopped: Bool { stopped.withLock { $0 } }
}

/// Same-process registry only. No files, SDK tasks, old leaves or numeric FDs
/// are adopted from disk/enumeration. Registration is correlation, not permission.
actor ManagedDownloadIngress {
    nonisolated let ownerGeneration: UUID
    private nonisolated let registry: DownloadIngressRegistry
    nonisolated var pinningPort: any BackgroundDownloadIngressPinningPort { registry }

    /// Optional synchronous fault checkpoint before real pin-error close. It
    /// receives no FD/handle and cannot replace a successful actual close.
    init(pinClose: (@Sendable () throws -> Void)? = nil,
         readCheckpoint: (@Sendable (UInt64) async throws -> Void)? = nil) {
        let generation = UUID(); ownerGeneration = generation
        registry = .init(generation: generation, pinClose: pinClose, checkpoint: readCheckpoint)
    }

    func registerExpected(_ proposal: BackgroundDownloadExpectedProposal, prepared: KnownPreparedDownloadReference,
                          store: any MediaOperationStorePort) async throws -> PreparedDownloadSink {
        try proposal.validate(); try prepared.validate(for: proposal.intent)
        let mutation = try prepared.mutation(for: proposal.intent)
        guard case .loaded(let before) = await store.load(), before.storeIdentity == prepared.storeIdentity,
              Self.matches(proposal, prepared: prepared, snapshot: before),
              case .committed(let receipt) = await store.lookupCommit(mutation), UploadMetadataValidation.exact(receipt, prepared.commit),
              case .loaded(let after) = await store.load(), after.storeIdentity == prepared.storeIdentity,
              after.revision == before.revision, Self.matches(proposal, prepared: prepared, snapshot: after) else {
            throw BackendContractError.notCommitted
        }
        return try registry.register(proposal, prepared: prepared)
    }

    func take(_ reference: BackgroundDownloadArtifactReference) throws -> BackgroundDownloadPinnedSource { try registry.take(reference) }
    func stopAndClose(_ reference: BackgroundDownloadArtifactReference) async throws -> BackgroundDownloadSourceClosure {
        let source = try registry.source(reference)
        source.stop.requestStop()
        return try await source.finishAndClose()
    }
    func closeUnpinnedCreation(binding: BackgroundMediaTaskBinding) async throws -> BackgroundDownloadUnpinnedClosure {
        try await registry.closeUnpinned(binding)
    }
    func resources() -> BackgroundDownloadIngressResources { registry.resources() }

    private static func matches(_ proposal: BackgroundDownloadExpectedProposal, prepared: KnownPreparedDownloadReference,
                                snapshot: BackendStoreSnapshot) -> Bool {
        let matches = snapshot.backgroundTasks.filter { $0.intent.id == prepared.taskID }
        guard matches.count == 1, let task = matches.first,
              UploadMetadataValidation.exact(task.intent, proposal.intent), task.binding == nil,
              task.terminal == nil, task.ownerClosure == nil, task.events.count == 1, let event = task.events.first,
              let actual = try? KnownPreparedDownloadReference(event), UploadMetadataValidation.exact(actual, prepared),
              snapshot.revision >= prepared.commit.committedRevision else { return false }
        return true
    }
}

/// Slot-scoped synchronous port. Only native actual creation binds it. A test
/// injecting a synthetic callback is not thereby a native receive producer.
nonisolated final class PreparedDownloadSink: BackgroundDownloadIngressPinningPort, Sendable {
    private let slot: DownloadIngressSlot
    fileprivate init(_ slot: DownloadIngressSlot) { self.slot = slot }
    func bindKnownCreation(_ intent: BackgroundMediaTaskIntent, binding: BackgroundMediaTaskBinding) -> Bool { slot.bind(intent, binding: binding) }
    func pinKnownCallback(binding: BackgroundMediaTaskBinding, location: URL, response: HTTPURLResponse) -> BackgroundDownloadPinResult {
        slot.pin(binding: binding, location: location, response: response)
    }
    func requestStop(_ binding: BackgroundMediaTaskBinding) { slot.requestStop(binding) }
    func observeKnownTerminal(_ terminal: BackgroundMediaSDKTerminal) { slot.observeTerminal(terminal) }
}

/// The capability is the object, never its hidden FD number. At most one read
/// worker runs; close revokes future reads, joins that exact worker, then closes.
actor BackgroundDownloadPinnedSource {
    nonisolated let reference: BackgroundDownloadArtifactReference
    nonisolated let proposal: BackgroundDownloadExpectedProposal
    nonisolated let prepared: KnownPreparedDownloadReference
    nonisolated let response: BackgroundDownloadResponseFacts
    nonisolated let initialFacts: BackgroundDownloadSourceFacts
    nonisolated let stop: BackgroundDownloadAbortSeal
    private nonisolated let file: DownloadIngressFile
    private let checkpoint: (@Sendable (UInt64) async throws -> Void)?
    private var worker: Task<DownloadIngressReadResult, Error>?
    private var closing: Task<BackgroundDownloadSourceClosure, Error>?
    private(set) var recordedClosure: BackgroundDownloadSourceClosure?
    fileprivate nonisolated var revoked: Bool { file.isRevoked }

    fileprivate init(reference: BackgroundDownloadArtifactReference, proposal: BackgroundDownloadExpectedProposal,
        prepared: KnownPreparedDownloadReference, response: BackgroundDownloadResponseFacts, file: DownloadIngressFile,
        stop: BackgroundDownloadAbortSeal, checkpoint: (@Sendable (UInt64) async throws -> Void)?) {
        self.reference = reference; self.proposal = proposal; self.prepared = prepared; self.response = response
        self.file = file; initialFacts = file.initial; self.stop = stop; self.checkpoint = checkpoint
    }
    func read(offset: UInt64, maximumLength: Int) async throws -> Data {
        let file = file, checkpoint = checkpoint
        let result = try await run {
            let bytes = try file.read(offset: offset, maximumLength: maximumLength)
            try await checkpoint?(offset + UInt64(bytes.count))
            return .bytes(bytes)
        }
        guard case .bytes(let bytes) = result else { throw BackendContractError.unknownResult }; return bytes
    }
    /// Independent full artifact hash only; never TemporaryMediaReceipt or a
    /// whole-original verification. A partial/ranged proposal cannot register.
    func hashFull() async throws -> ContentIdentity {
        let file = file, checkpoint = checkpoint, expected = proposal.rendition.deliveryContent
        let result = try await run {
            var hash = SHA256(), offset: UInt64 = 0
            while offset < expected.byteCount {
                let bytes = try file.read(offset: offset, maximumLength: Int(min(65_536, expected.byteCount - offset)))
                guard !bytes.isEmpty else { throw BackendContractError.unavailable }
                hash.update(data: bytes); offset += UInt64(bytes.count)
                try await checkpoint?(offset)
                try Task.checkCancellation()
                try file.check()
            }
            let content = try ContentIdentity(byteCount: offset, algorithm: "sha256",
                digest: hash.finalize().map { String(format: "%02x", $0) }.joined())
            guard UploadMetadataValidation.exact(content, expected) else { throw BackendContractError.identityMismatch }
            try file.check(); return .digest(content)
        }
        guard case .digest(let content) = result else { throw BackendContractError.unknownResult }; return content
    }
    func finishAndClose() async throws -> BackgroundDownloadSourceClosure {
        if let recordedClosure { return recordedClosure }
        if let closing { return try await closing.value }
        file.revoke()
        let active = worker, file = file, reference = reference
        let work = Task {
            active?.cancel()
            if let active { _ = try? await active.value }
            try file.closeAfterJoin()
            return BackgroundDownloadSourceClosure(reference: reference, workersJoined: true, handlesClosed: true)
        }
        closing = work
        let result = try await work.value
        recordedClosure = result
        return result
    }
    private func run(_ body: @escaping @Sendable () async throws -> DownloadIngressReadResult) async throws -> DownloadIngressReadResult {
        guard worker == nil, closing == nil, recordedClosure == nil, !stop.isStopped, !file.isRevoked else { throw BackendContractError.wrongStage }
        let file = file
        file.metrics.workerStarted()
        let work = Task.detached {
            defer { file.metrics.workerEnded() }
            try Task.checkCancellation(); return try await body()
        }
        worker = work
        defer { worker = nil }
        let result = try await work.value
        guard !stop.isStopped, !file.isRevoked else { throw CancellationError() }
        return result
    }
}

fileprivate nonisolated enum DownloadIngressReadResult: Sendable { case bytes(Data), digest(ContentIdentity) }

fileprivate nonisolated final class DownloadIngressRegistry: BackgroundDownloadIngressPinningPort, Sendable {
    let generation: UUID
    let metrics = DownloadIngressMetrics()
    let pinClose: (@Sendable () throws -> Void)?
    let checkpoint: (@Sendable (UInt64) async throws -> Void)?
    private let slots = Mutex<[DownloadIngressSlot]>([])
    init(generation: UUID, pinClose: (@Sendable () throws -> Void)?, checkpoint: (@Sendable (UInt64) async throws -> Void)?) {
        self.generation = generation; self.pinClose = pinClose; self.checkpoint = checkpoint
    }
    func register(_ proposal: BackgroundDownloadExpectedProposal, prepared: KnownPreparedDownloadReference) throws -> PreparedDownloadSink {
        try slots.withLock { values in
            guard !values.contains(where: { $0.proposal.intent.id == proposal.intent.id }) else { throw BackendContractError.duplicateTarget }
            let slot = DownloadIngressSlot(proposal: proposal, prepared: prepared, generation: generation, metrics: metrics, pinClose: pinClose, checkpoint: checkpoint)
            values.append(slot); return PreparedDownloadSink(slot)
        }
    }
    func bindKnownCreation(_ intent: BackgroundMediaTaskIntent, binding: BackgroundMediaTaskBinding) -> Bool {
        let values = slots.withLock { $0.filter { $0.proposal.intent.id == intent.id } }
        return values.count == 1 && values[0].bind(intent, binding: binding)
    }
    func pinKnownCallback(binding: BackgroundMediaTaskBinding, location: URL, response: HTTPURLResponse) -> BackgroundDownloadPinResult {
        guard let slot = matching(binding) else { return .refused }
        return slot.pin(binding: binding, location: location, response: response)
    }
    func requestStop(_ binding: BackgroundMediaTaskBinding) { matching(binding)?.requestStop(binding) }
    func observeKnownTerminal(_ terminal: BackgroundMediaSDKTerminal) { matching(terminal.binding)?.observeTerminal(terminal) }
    func take(_ reference: BackgroundDownloadArtifactReference) throws -> BackgroundDownloadPinnedSource {
        guard reference.ownerGeneration == generation, let slot = matching(reference.binding) else { throw BackendContractError.identityMismatch }
        return try slot.take(reference)
    }
    func source(_ reference: BackgroundDownloadArtifactReference) throws -> BackgroundDownloadPinnedSource {
        guard reference.ownerGeneration == generation, let slot = matching(reference.binding) else { throw BackendContractError.identityMismatch }
        return try slot.source(reference)
    }
    func closeUnpinned(_ binding: BackgroundMediaTaskBinding) async throws -> BackgroundDownloadUnpinnedClosure {
        guard let slot = matching(binding) else { throw BackendContractError.identityMismatch }
        return try await slot.closeUnpinned()
    }
    private func matching(_ binding: BackgroundMediaTaskBinding) -> DownloadIngressSlot? {
        let all = slots.withLock { $0 }
        let values = all.filter { $0.matches(binding) }
        return values.count == 1 ? values[0] : nil
    }
    func resources() -> BackgroundDownloadIngressResources { metrics.snapshot(slots: slots.withLock { $0.count }) }
}

fileprivate nonisolated final class DownloadIngressSlot: Sendable {
    let proposal: BackgroundDownloadExpectedProposal
    private let prepared: KnownPreparedDownloadReference
    private let generation: UUID, metrics: DownloadIngressMetrics
    private let pinClose: (@Sendable () throws -> Void)?
    private let checkpoint: (@Sendable (UInt64) async throws -> Void)?
    private let abort = BackgroundDownloadAbortSeal()
    private struct State {
        var binding: BackgroundMediaTaskBinding?
        var pinning = false, pinsSealed = false, callbackSeen = false, taken = false, corruptTerminal = false
        var source: BackgroundDownloadPinnedSource?
        var reference: BackgroundDownloadArtifactReference?
        var terminal: BackgroundMediaSDKTerminal?
        var pinWaiters: [CheckedContinuation<Void, Never>] = []
        var unpinnedClosure: BackgroundDownloadUnpinnedClosure?
        var unknownPinHandle: FileHandle?
    }
    private let state = Mutex(State())
    init(proposal: BackgroundDownloadExpectedProposal, prepared: KnownPreparedDownloadReference, generation: UUID,
         metrics: DownloadIngressMetrics, pinClose: (@Sendable () throws -> Void)?, checkpoint: (@Sendable (UInt64) async throws -> Void)?) {
        self.proposal = proposal; self.prepared = prepared; self.generation = generation; self.metrics = metrics; self.pinClose = pinClose; self.checkpoint = checkpoint
    }
    func bind(_ intent: BackgroundMediaTaskIntent, binding: BackgroundMediaTaskBinding) -> Bool {
        state.withLock { value in
            guard value.binding == nil, !value.pinsSealed, !abort.isStopped,
                  UploadMetadataValidation.exact(intent, proposal.intent), UploadMetadataValidation.exact(binding.session, intent.session),
                  binding.taskDescription.utf8.elementsEqual(intent.taskDescription.utf8), binding.taskIdentifier > 0 else { return false }
            value.binding = binding; return true
        }
    }
    func matches(_ binding: BackgroundMediaTaskBinding) -> Bool { state.withLock { UploadMetadataValidation.exact($0.binding, Optional(binding)) } }
    func requestStop(_ binding: BackgroundMediaTaskBinding) { if matches(binding) { abort.requestStop() } }
    func observeTerminal(_ terminal: BackgroundMediaSDKTerminal) {
        state.withLock { value in
            guard UploadMetadataValidation.exact(value.binding, Optional(terminal.binding)) else { return }
            value.pinsSealed = true
            if value.terminal == nil { value.terminal = terminal }
            else if !UploadMetadataValidation.exact(value.terminal, Optional(terminal)) { value.corruptTerminal = true; abort.requestStop() }
        }
    }
    func pin(binding: BackgroundMediaTaskBinding, location: URL, response: HTTPURLResponse) -> BackgroundDownloadPinResult {
        let mayPin = state.withLock { value in
            guard UploadMetadataValidation.exact(value.binding, Optional(binding)), !value.pinsSealed,
                  value.source == nil, !value.pinning, !value.callbackSeen, !abort.isStopped else { return false }
            value.callbackSeen = true; value.pinning = true; return true
        }
        guard mayPin else { return .refused }
        defer { finishPin() }
        var handle: FileHandle?
        do {
            let facts = try DownloadIngressResponse.match(response, proposal: proposal)
            guard location.isFileURL, !abort.isStopped else { throw BackendContractError.wrongStage }
            let fd = Darwin.open(location.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard fd >= 0 else { throw BackendContractError.unavailable }
            let opened = FileHandle(fileDescriptor: fd, closeOnDealloc: true); handle = opened
            let initial = try DownloadIngressFile.facts(fd)
            guard initial.linkCount == 1, initial.size == Int64(proposal.rendition.deliveryContent.byteCount), !abort.isStopped else {
                throw BackendContractError.identityMismatch
            }
            let reference = BackgroundDownloadArtifactReference(id: UUID(), ownerGeneration: generation, binding: binding)
            let published = state.withLock { value -> Bool in
                guard value.pinning, !value.pinsSealed, !abort.isStopped, value.source == nil else { return false }
                let file = DownloadIngressFile(handle: opened, initial: initial, stop: abort, metrics: metrics)
                let source = BackgroundDownloadPinnedSource(reference: reference, proposal: proposal, prepared: prepared,
                    response: facts, file: file, stop: abort, checkpoint: checkpoint)
                value.source = source; value.reference = reference; metrics.pinned()
                return true
            }
            guard published else { throw BackendContractError.wrongStage }
            handle = nil // This exact descriptor belongs to the published cap.
            return .pinned(reference)
        } catch {
            if let handle {
                do {
                    try pinClose?()
                    try handle.close()
                }
                catch {
                    state.withLock { $0.unknownPinHandle = handle; $0.pinsSealed = true }
                    metrics.unknownHandle()
                }
            }
            return .refused
        }
    }
    private func finishPin() {
        let waiting = state.withLock { value in
            value.pinning = false; let result = value.pinWaiters; value.pinWaiters.removeAll(); return result
        }
        waiting.forEach { $0.resume() }
    }
    func take(_ reference: BackgroundDownloadArtifactReference) throws -> BackgroundDownloadPinnedSource {
        try state.withLock { value in
            guard value.reference == reference, !value.taken, let source = value.source,
                  !source.revoked, !abort.isStopped else { throw BackendContractError.identityMismatch }
            value.taken = true; return source
        }
    }
    func source(_ reference: BackgroundDownloadArtifactReference) throws -> BackgroundDownloadPinnedSource {
        try state.withLock { value in
            guard value.reference == reference, let source = value.source else { throw BackendContractError.identityMismatch }; return source
        }
    }
    func closeUnpinned() async throws -> BackgroundDownloadUnpinnedClosure {
        try state.withLock { value in
            guard value.terminal != nil, !value.corruptTerminal, value.binding != nil,
                  value.source == nil, value.unknownPinHandle == nil else { throw BackendContractError.readersActive }
            value.pinsSealed = true; abort.requestStop()
        }
        await withCheckedContinuation { continuation in
            let immediate = state.withLock { value in
                if !value.pinning { return true }; value.pinWaiters.append(continuation); return false
            }
            if immediate { continuation.resume() }
        }
        return try state.withLock { value in
            if let closure = value.unpinnedClosure { return closure }
            guard let binding = value.binding, value.terminal != nil, !value.corruptTerminal, value.pinsSealed,
                  !value.pinning, value.source == nil, value.unknownPinHandle == nil else {
                throw BackendContractError.readersActive
            }
            let result = BackgroundDownloadUnpinnedClosure(ownerGeneration: generation, binding: binding,
                pinsSealed: true, workersJoined: true, handlesClosed: true)
            value.unpinnedClosure = result; return result
        }
    }
}

fileprivate nonisolated final class DownloadIngressFile: Sendable {
    let initial: BackgroundDownloadSourceFacts
    let metrics: DownloadIngressMetrics
    private let handle: FileHandle, stop: BackgroundDownloadAbortSeal
    private struct State { var last: BackgroundDownloadSourceFacts; var revoked = false, attemptedClose = false, closed = false }
    private let state: Mutex<State>
    init(handle: FileHandle, initial: BackgroundDownloadSourceFacts, stop: BackgroundDownloadAbortSeal, metrics: DownloadIngressMetrics) {
        self.handle = handle; self.initial = initial; self.stop = stop; self.metrics = metrics; state = Mutex(.init(last: initial))
    }
    var isRevoked: Bool { state.withLock { $0.revoked } }
    func revoke() { state.withLock { $0.revoked = true } }
    func check() throws {
        guard !stop.isStopped else { throw CancellationError() }
        try state.withLock { value in
            guard !value.revoked, !value.closed else { throw BackendContractError.wrongStage }
            let current = try Self.facts(handle.fileDescriptor)
            guard value.last.permitsSDKUnlinkTransition(to: current) else { throw BackendContractError.identityMismatch }
            value.last = current
        }
    }
    func read(offset: UInt64, maximumLength: Int) throws -> Data {
        guard (1...65_536).contains(maximumLength), offset <= UInt64(initial.size), offset <= UInt64(Int64.max) else { throw BackendContractError.invalidValue }
        try Task.checkCancellation(); try check()
        let count = Int(min(UInt64(maximumLength), UInt64(initial.size) - offset))
        if count == 0 { return Data() }
        var bytes = [UInt8](repeating: 0, count: count), received: Int
        repeat { received = pread(handle.fileDescriptor, &bytes, count, off_t(offset)) } while received < 0 && errno == EINTR
        guard received > 0, received <= count else { throw BackendContractError.unavailable }
        try Task.checkCancellation(); try check()
        metrics.read(received); return Data(bytes.prefix(received))
    }
    func closeAfterJoin() throws {
        let mayClose = state.withLock { value -> Bool in
            if value.closed { return false }
            guard value.revoked, !value.attemptedClose else { return false }
            value.attemptedClose = true; return true
        }
        guard mayClose else {
            guard state.withLock({ $0.closed }) else { throw BackendContractError.unknownResult }; return
        }
        do { try handle.close() }
        catch { throw BackendContractError.unknownResult }
        state.withLock { $0.closed = true }; metrics.closed()
    }
    static func facts(_ descriptor: Int32) throws -> BackgroundDownloadSourceFacts {
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size > 0,
              info.st_nlink <= 1 else { throw BackendContractError.identityMismatch }
        return try .init(device: Int64(info.st_dev), inode: UInt64(info.st_ino), size: Int64(info.st_size),
            modifiedSeconds: Int64(info.st_mtimespec.tv_sec), modifiedNanoseconds: Int64(info.st_mtimespec.tv_nsec),
            changedSeconds: Int64(info.st_ctimespec.tv_sec), changedNanoseconds: Int64(info.st_ctimespec.tv_nsec), linkCount: UInt64(info.st_nlink))
    }
}

fileprivate nonisolated final class DownloadIngressMetrics: Sendable {
    private struct State { var pins = 0, open = 0, closed = 0, workers = 0, largest = 0; var bytes: UInt64 = 0 }
    private let state = Mutex(State())
    func pinned() { state.withLock { $0.pins += 1; $0.open += 1 } }
    func unknownHandle() { state.withLock { $0.open += 1 } }
    func closed() { state.withLock { $0.closed += 1; $0.open -= 1 } }
    func workerStarted() { state.withLock { $0.workers += 1 } }
    func workerEnded() { state.withLock { $0.workers -= 1 } }
    func read(_ length: Int) { state.withLock { $0.largest = max($0.largest, length); $0.bytes += UInt64(length) } }
    func snapshot(slots: Int) -> BackgroundDownloadIngressResources {
        state.withLock { .init(registeredSlots: slots, pinnedArtifacts: $0.pins, openHandles: $0.open, closedHandles: $0.closed,
            activeWorkers: $0.workers, largestRead: $0.largest, readBytes: $0.bytes) }
    }
}

private nonisolated enum DownloadIngressResponse {
    static func match(_ response: HTTPURLResponse, proposal: BackgroundDownloadExpectedProposal) throws -> BackgroundDownloadResponseFacts {
        guard response.statusCode == 200, let url = response.url,
              url.absoluteString.utf8.elementsEqual(proposal.responseURL.absoluteString.utf8), response.allHeaderFields.count <= 64 else {
            throw BackendContractError.identityMismatch
        }
        var headers: [String: String] = [:]
        for (key, raw) in response.allHeaderFields {
            guard let name = key as? String, let value = raw as? String, name.utf8.count <= 128, value.utf8.count <= 8192,
                  headers[name.lowercased()] == nil else { throw BackendContractError.invalidValue }
            headers[name.lowercased()] = value
        }
        let rendition = proposal.rendition, content = rendition.deliveryContent
        let expected = ["content-type": proposal.contentType, "content-length": String(content.byteCount),
            "x-framerelay-wire-version": "fr-publication-v1", "x-framerelay-distribution-id": proposal.distributionHeader,
            "x-framerelay-rendition-id": rendition.rendition.rawValue,
            "x-framerelay-publication-generation": String(rendition.publicationGeneration.rawValue),
            "x-framerelay-content-sha256": content.digest, "x-framerelay-content-bytes": String(content.byteCount), "cache-control": "no-store"]
        guard headers["content-range"] == nil, headers["transfer-encoding"] == nil,
              headers["content-encoding"].map({ $0 == "identity" }) ?? true else { throw BackendContractError.identityMismatch }
        for (name, value) in expected {
            guard headers[name]?.utf8.elementsEqual(value.utf8) == true else { throw BackendContractError.identityMismatch }
        }
        let facts = try BackgroundDownloadResponseFacts(urlFingerprint: proposal.responseURLFingerprint, status: 200, contentType: proposal.contentType,
            contentLength: content.byteCount, wireVersion: "fr-publication-v1", distributionHeader: proposal.distributionHeader,
            renditionID: rendition.rendition, publicationGeneration: rendition.publicationGeneration, content: content, cacheControl: "no-store",
            contentRangeAbsent: true, contentEncoding: headers["content-encoding"] == nil ? .absent : .identity, transferEncodingAbsent: true)
        try facts.validate(); return facts
    }
}
