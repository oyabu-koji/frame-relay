import CryptoKit
import Darwin
import Foundation
import Synchronization
import Testing
@testable import FrameRelay

/// New dedicated roots/raw synthetic bytes only. The supplied binding/terminal
/// inputs test local ownership, not strict admission, HTTP, SDK or Mac success.
struct ManagedUploadChunkSourceTests {
    @Test(arguments: StorageCandidate.allCases, [UInt64(0), 1, 2])
    func firstMiddleAndShortLastCopiesUseTheBoundFullOriginalFD(candidate: StorageCandidate, index: UInt64) async throws {
        try await withStorageRun { run in
            let f = try await ChunkSourceFixture.make(run: run, candidate: candidate)
            let before = try chunkSourceFingerprint(f.url), range = try f.range(index: index)
            let owner = try ManagedUploadSource(run: run, originals: f.access)
            let chunk = try await owner.createChunk(from: f.lease, id: .init(rawValue: UUID().uuidString), range: range)
            let file = try await owner.uploadFile(for: chunk.source, lease: f.lease)
            let expected = f.bytes.subdata(in: Int(range.offset)..<Int(range.upperBoundExclusive)), actual = try Data(contentsOf: file.url)
            let expectedContent = try renditionContent(expected)
            #expect(actual == expected && chunk.descriptor.content == expectedContent)
            #expect(chunk.source.content == chunk.descriptor.content && chunk.source.file.size == Int64(expected.count))
            #expect(chunk.source.content != f.binding.original.content)
            let resources = await owner.resources(), fd = try #require(resources.descriptors.first)
            #expect(resources.activeCopies == 0 && resources.openHandles == 1 && resources.closedHandles == 1)
            #expect(resources.copiedBytes == range.length && resources.largestOriginalRead == Int(min(range.length, 65_536)))
            #expect(fcntl(fd, F_GETFD) >= 0)
            let sdk = backgroundFileBinding(), terminal = BackgroundMediaSDKTerminal(binding: sdk, outcome: .cancelled)
            try await owner.retain(chunk.source, lease: f.lease, for: sdk)
            let closed = try await owner.finish(chunk.source, lease: f.lease, terminal: terminal)
            #expect(closed.uploadSource == chunk.source && closed.handlesClosed && closed.tasksJoined)
            #expect(chunkSourceDescriptorClosed(fd, file: chunk.source.file))
            #expect(try await owner.finish(chunk.source, lease: f.lease, terminal: terminal) == closed)
            #expect(await owner.resources().closedHandles == 2)
            #expect(try await mediaOriginalSnapshot(f.store).originals[0].readers == [f.lease])
            let after = try chunkSourceFingerprint(f.url), originalBytes = try Data(contentsOf: f.url)
            #expect(after == before && originalBytes == f.bytes)
            #expect(try await f.files.digest(for: f.binding.reference).sha256 == f.binding.original.content.digest)
            #expect(try Data(contentsOf: file.url) == expected)
            #expect(await f.access.releaseRead(f.lease) == .succeeded(.init(lease: f.lease)))
            _ = try await owner.closeOwner()
        }
    }

    @Test func realPartialWritesAndAnInterruptedSyscallStillRequireIndependentReadback() async throws {
        try await withStorageRun { run in
            let f = try await ChunkSourceFixture.make(run: run), probe = ChunkWriteProbe()
            let owner = try ManagedUploadSource(run: run, originals: f.access, chunkWrite: { fd, bytes, count in
                if probe.next() == 1 { errno = EINTR; return -1 }
                return Darwin.write(fd, bytes, min(count, 17))
            })
            let range = try f.range(index: 0), chunk = try await owner.createChunk(from: f.lease, id: .init(rawValue: UUID().uuidString), range: range)
            let file = try await owner.uploadFile(for: chunk.source, lease: f.lease)
            let actual = try Data(contentsOf: file.url), content = try renditionContent(actual)
            #expect(actual == f.bytes.prefix(Int(range.length)) && probe.count > Int(range.length / 17))
            #expect(chunk.descriptor.content == content)
            try await chunkSourceFinish(owner, chunk: chunk, lease: f.lease)
            #expect(try Data(contentsOf: f.url) == f.bytes)
            _ = await f.access.releaseRead(f.lease); _ = try await owner.closeOwner()
        }
    }

    @Test func aSingleChunkMayMatchTheOriginalHashWhileRemainingASeparateLocalDescriptor() async throws {
        try await withStorageRun { run in
            let f = try await ChunkSourceFixture.make(run: run), owner = try ManagedUploadSource(run: run, originals: f.access)
            let range = try f.range(index: 0, size: UInt64(f.bytes.count) + 1)
            let chunk = try await owner.createChunk(from: f.lease, id: .init(rawValue: UUID().uuidString), range: range)
            let file = try await owner.uploadFile(for: chunk.source, lease: f.lease)
            #expect(range.chunkCount == 1 && chunk.descriptor.content == f.binding.original.content)
            #expect(try Data(contentsOf: file.url) == f.bytes)
            #expect(await owner.resources().largestOriginalRead == 65_536)
            try await chunkSourceFinish(owner, chunk: chunk, lease: f.lease)
            #expect(try await mediaOriginalSnapshot(f.store).originals[0].readers == [f.lease])
            _ = await f.access.releaseRead(f.lease); _ = try await owner.closeOwner()
        }
    }

    @Test func independentlyReadingTheRealOutputRefusesASuccessfulButIncorrectWriter() async throws {
        try await withStorageRun { run in
            let f = try await ChunkSourceFixture.make(run: run), id = ManagedUploadSourceID(rawValue: UUID().uuidString)
            let owner = try ManagedUploadSource(run: run, originals: f.access, chunkWrite: { fd, buffer, count in
                var wrong = Data(bytes: buffer, count: count); wrong[0] ^= 0xff
                return wrong.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!, count) }
            })
            let range = try f.range(index: 0)
            await chunkSourceExpect(.identityMismatch) { _ = try await owner.createChunk(from: f.lease, id: id, range: range) }
            let resources = await owner.resources(), retained = try Data(contentsOf: chunkSourceURL(run, id: id))
            #expect(resources.activeCopies == 0 && resources.openHandles == 0 && resources.closedHandles == 2)
            #expect(retained.count == Int(range.length) && retained != f.bytes.prefix(Int(range.length)))
            #expect(try await mediaOriginalSnapshot(f.store).originals[0].readers == [f.lease])
            #expect(try Data(contentsOf: f.url) == f.bytes)
            _ = await f.access.releaseRead(f.lease); _ = try await owner.closeOwner()
        }
    }

    @Test func aRealPartialWriteThenCapacityFailureRetainsOnlyTheUnknownLeaf() async throws {
        try await withStorageRun { run in
            let f = try await ChunkSourceFixture.make(run: run), probe = ChunkWriteProbe(), id = ManagedUploadSourceID(rawValue: UUID().uuidString)
            let owner = try ManagedUploadSource(run: run, originals: f.access, chunkWrite: { fd, bytes, count in
                if probe.next() == 1 { return Darwin.write(fd, bytes, min(count, 1024)) }
                errno = ENOSPC; return -1
            })
            let range = try f.range(index: 0)
            await chunkSourceExpect(.unavailable) { _ = try await owner.createChunk(from: f.lease, id: id, range: range) }
            let partial = try Data(contentsOf: chunkSourceURL(run, id: id))
            #expect(partial == f.bytes.prefix(1024))
            #expect(await owner.resources().openHandles == 0)
            await chunkSourceExpect(.identityMismatch) { _ = try await owner.createChunk(from: f.lease, id: id, range: range) }
            #expect(try Data(contentsOf: chunkSourceURL(run, id: id)) == partial)
            #expect(try await mediaOriginalSnapshot(f.store).originals[0].readers == [f.lease])
            _ = await f.access.releaseRead(f.lease); _ = try await owner.closeOwner()
        }
    }

    @Test(arguments: ["original", "last-original", "original-name", "output", "namespace", "owner-lock"])
    func changesAtAnAwaitCannotExportAChunkOrDeleteForeignFiles(change: String) async throws {
        try await withStorageRun { run in
            let f = try await ChunkSourceFixture.make(run: run), id = ManagedUploadSourceID(rawValue: UUID().uuidString)
            let range = try f.range(index: 0), leaf = chunkSourceURL(run, id: id), sentinel = Data([81, 82, 83])
            let held = run.url.appendingPathComponent("retained-" + change)
            let owner = try ManagedUploadSource(run: run, originals: f.access) { copied in
                guard copied == (change == "last-original" ? range.length : 65_536) else { return }
                switch change {
                case "original", "last-original":
                    let writer = try FileHandle(forWritingTo: f.url)
                    do { try writer.write(contentsOf: Data([f.bytes[0] ^ 0xff])); try writer.synchronize(); try writer.close() }
                    catch { try? writer.close(); throw error }
                case "original-name":
                    try FileManager.default.moveItem(at: f.url, to: held)
                    try sentinel.write(to: f.url, options: .withoutOverwriting)
                case "output":
                    try FileManager.default.moveItem(at: leaf, to: held)
                    try sentinel.write(to: leaf, options: .withoutOverwriting)
                case "namespace":
                    try FileManager.default.moveItem(at: leaf.deletingLastPathComponent(), to: held)
                    try FileManager.default.createDirectory(at: leaf.deletingLastPathComponent(), withIntermediateDirectories: false)
                    try sentinel.write(to: leaf, options: .withoutOverwriting)
                case "owner-lock":
                    let lock = leaf.deletingLastPathComponent().appendingPathComponent("owner.lock")
                    try FileManager.default.moveItem(at: lock, to: held)
                    try sentinel.write(to: lock, options: .withoutOverwriting)
                default: throw BackendContractError.invalidValue
                }
            }
            await chunkSourceExpect(.identityMismatch) { _ = try await owner.createChunk(from: f.lease, id: id, range: range) }
            let resources = await owner.resources()
            #expect(resources.activeCopies == 0 && resources.openHandles == 0)
            #expect(try await mediaOriginalSnapshot(f.store).originals[0].readers == [f.lease])
            if change == "output" || change == "namespace" { #expect(try Data(contentsOf: leaf) == sentinel) }
            if change == "owner-lock" { #expect(try Data(contentsOf: leaf.deletingLastPathComponent().appendingPathComponent("owner.lock")) == sentinel) }
            if change == "original-name" {
                let named = try Data(contentsOf: f.url), retained = try Data(contentsOf: held)
                #expect(named == sentinel && retained == f.bytes)
            }
            if !change.hasPrefix("original") && change != "last-original" { #expect(try Data(contentsOf: f.url) == f.bytes) }
            _ = await f.access.releaseRead(f.lease); _ = try await owner.closeOwner()
            // Intentionally changed new-fixture files stay retained. No repair,
            // unlink, original replacement adoption or SDK terminal is inferred.
        }
    }

    @Test func cancellationAndConcurrentDuplicateDrainOnlyTheirOwnAttachmentAndKeepTheLeafAcrossReopen() async throws {
        try await withStorageRun { run in
            let f = try await ChunkSourceFixture.make(run: run), gate = ChunkSourceGate(), id = ManagedUploadSourceID(rawValue: UUID().uuidString)
            let range = try f.range(index: 0)
            let owner = try ManagedUploadSource(run: run, originals: f.access) { copied in
                if copied == 65_536 { await gate.hold() }
            }
            let copy = Task { try await owner.createChunk(from: f.lease, id: id, range: range) }
            await gate.waitUntilHeld()
            await chunkSourceExpect(.identityMismatch) { _ = try await owner.createChunk(from: f.lease, id: id, range: range) }
            await chunkSourceExpect(.readersActive) { _ = try await owner.closeOwner() }
            #expect(await f.access.releaseRead(f.lease) == .inProgress)
            copy.cancel()
            let blocked = await owner.resources()
            #expect(blocked.activeCopies == 1 && blocked.openHandles == 1)
            await gate.release()
            do { _ = try await copy.value; Issue.record("Cancelled chunk became exportable") }
            catch is CancellationError {} catch { Issue.record("Unexpected failure: \(error)") }
            let cancelled = await owner.resources()
            #expect(cancelled.activeCopies == 0 && cancelled.openHandles == 0)
            let partial = try Data(contentsOf: chunkSourceURL(run, id: id))
            #expect(partial == f.bytes.prefix(65_536))
            #expect(try await mediaOriginalSnapshot(f.store).originals[0].readers == [f.lease])
            await chunkSourceExpect(.identityMismatch) { _ = try await owner.createChunk(from: f.lease, id: id, range: range) }
            _ = try await owner.closeOwner()
            let reopened = try ManagedUploadSource(run: run, originals: f.access)
            await chunkSourceExpect(.identityMismatch) { _ = try await reopened.createChunk(from: f.lease, id: id, range: range) }
            _ = try await reopened.closeOwner()
            let kept = try Data(contentsOf: chunkSourceURL(run, id: id)), originalBytes = try Data(contentsOf: f.url)
            #expect(kept == partial && originalBytes == f.bytes)
            #expect(await f.access.releaseRead(f.lease) == .succeeded(.init(lease: f.lease)))
        }
    }

    @Test(arguments: ["file", "symlink", "directory"])
    func anExistingUnknownLeafIsNeverOverwrittenOrFollowed(kind: String) async throws {
        try await withStorageRun { run in
            let f = try await ChunkSourceFixture.make(run: run), owner = try ManagedUploadSource(run: run, originals: f.access)
            let id = ManagedUploadSourceID(rawValue: UUID().uuidString), leaf = chunkSourceURL(run, id: id)
            let external = run.url.appendingPathComponent("external-sentinel.bin"), bytes = Data([71, 72, 73])
            try bytes.write(to: external, options: .withoutOverwriting)
            let identity = try chunkSourceFingerprint(external)
            switch kind {
            case "file": try bytes.write(to: leaf, options: .withoutOverwriting)
            case "symlink": try FileManager.default.createSymbolicLink(at: leaf, withDestinationURL: external)
            case "directory": try FileManager.default.createDirectory(at: leaf, withIntermediateDirectories: false)
            default: throw BackendContractError.invalidValue
            }
            let range = try f.range(index: 0)
            await chunkSourceExpect(.identityMismatch) { _ = try await owner.createChunk(from: f.lease, id: id, range: range) }
            let resources = await owner.resources(), sentinel = try Data(contentsOf: external), finalIdentity = try chunkSourceFingerprint(external)
            #expect(resources.activeCopies == 0 && resources.openHandles == 0 && resources.copiedBytes == 0)
            #expect(sentinel == bytes && identity == finalIdentity && FileManager.default.fileExists(atPath: leaf.path))
            #expect(try await mediaOriginalSnapshot(f.store).originals[0].readers == [f.lease])
            _ = await f.access.releaseRead(f.lease); _ = try await owner.closeOwner()
        }
    }

    @Test func wholeAndChunkModesKeepTheirOwnContentAndExactLease() async throws {
        try await withStorageRun { run in
            let f = try await ChunkSourceFixture.make(run: run), owner = try ManagedUploadSource(run: run, originals: f.access)
            let range = try f.range(index: 0), chunk = try await owner.createChunk(from: f.lease, id: .init(rawValue: UUID().uuidString), range: range)
            let original = OriginalContent(capture: .init(rawValue: f.lease.original.capture.rawValue.replacingOccurrences(of: "\u{00e9}", with: "e\u{0301}")),
                generation: f.lease.original.generation, content: f.lease.original.content)
            let alias = OriginalReadLease(id: f.lease.id, original: original, operation: f.lease.operation, accessGeneration: f.lease.accessGeneration, epoch: f.lease.epoch)
            try #require(alias == f.lease && !UploadMetadataValidation.exact(alias, f.lease))
            await chunkSourceExpect(.identityMismatch) { _ = try await owner.uploadFile(for: chunk.source, lease: alias) }
            let wrongRange = try UploadChunkRange(binding: .init(registration: range.binding.registration, operation: range.binding.operation,
                original: original, session: range.binding.session, chunkSize: range.binding.chunkSize), index: 0)
            let before = await owner.resources()
            await chunkSourceExpect(.identityMismatch) { _ = try await owner.createChunk(from: f.lease, id: .init(rawValue: UUID().uuidString), range: wrongRange) }
            #expect(await owner.resources() == before)
            let whole = try await owner.create(from: f.lease, id: .init(rawValue: UUID().uuidString))
            let file = try await owner.uploadFile(for: whole, lease: f.lease)
            let wholeBytes = try Data(contentsOf: file.url)
            #expect(whole.content == f.binding.original.content && wholeBytes == f.bytes)
            #expect(chunk.source.content.byteCount < whole.content.byteCount)
            await chunkSourceExpect(.identityMismatch) { _ = try await owner.createChunk(from: f.lease, id: whole.id, range: range) }
            try await chunkSourceFinish(owner, chunk: chunk, lease: f.lease)
            let sdk = backgroundFileBinding()
            try await owner.retain(whole, lease: f.lease, for: sdk)
            _ = try await owner.finish(whole, lease: f.lease, terminal: .init(binding: sdk, outcome: .cancelled))
            #expect(try await mediaOriginalSnapshot(f.store).originals[0].readers == [f.lease])
            _ = await f.access.releaseRead(f.lease); _ = try await owner.closeOwner()
        }
    }

    @Test func anUnrepresentableLocalRangeRefusesBeforeAttachingOrCreatingAFile() async throws {
        try await withStorageRun { run in
            let f = try await ChunkSourceFixture.make(run: run), range = try f.range(index: 0), owner = try ManagedUploadSource(run: run, originals: f.access)
            let enormous = OriginalContent(capture: f.lease.original.capture, generation: f.lease.original.generation,
                content: try .init(byteCount: UInt64.max, algorithm: "sha256", digest: f.lease.original.content.digest))
            let request = try UploadChunkRange(binding: .init(registration: range.binding.registration, operation: range.binding.operation,
                original: enormous, session: range.binding.session, chunkSize: UInt64.max), index: 0)
            let synthetic = OriginalReadLease(id: f.lease.id, original: enormous, operation: f.lease.operation, accessGeneration: f.lease.accessGeneration, epoch: f.lease.epoch)
            let id = ManagedUploadSourceID(rawValue: UUID().uuidString)
            await chunkSourceExpect(.invalidValue) { _ = try await owner.createChunk(from: synthetic, id: id, range: request) }
            let resources = await owner.resources()
            #expect(resources.activeCopies == 0 && resources.openHandles == 0 && resources.copiedBytes == 0 && resources.largestOriginalRead == 0)
            #expect(!FileManager.default.fileExists(atPath: chunkSourceURL(run, id: id).path))
            #expect(try await mediaOriginalSnapshot(f.store).originals[0].readers == [f.lease])
            #expect(try Data(contentsOf: f.url) == f.bytes)
            _ = await f.access.releaseRead(f.lease); _ = try await owner.closeOwner()
        }
    }
}

private nonisolated struct ChunkSourceFixture: Sendable {
    let store: any MediaDiskStore
    let files: ManagedOriginalStore
    let access: ManagedOriginalAccess
    let binding: OriginalBinding
    let lease: OriginalReadLease
    let url: URL
    let bytes: Data
    static func make(run: ExplorationRunDirectory, candidate: StorageCandidate = .sqlite) async throws -> Self {
        let store: any MediaDiskStore
        switch candidate {
        case .atomicFile: store = try AtomicFileRecordingStore(run: run, mode: .createNew)
        case .sqlite: store = try SQLiteRecordingStore(run: run, mode: .createNew)
        }
        let input = try CaptureFixture(clip: "chunk-caf\u{00e9}-" + UUID().uuidString)
        let intent = RecordingIntent(context: input.context, operation: input.intent.operation,
            original: .init(rawValue: UUID().uuidString), trialReference: input.intent.trialReference,
            desired: input.desired, applied: input.applied, acceptedAt: input.time)
        guard case .committed(let receipt) = await store.execute(.commitIntent(input.token(1), expectedRevision: 0, intent)) else { throw BackendContractError.notCommitted }
        let files = ManagedOriginalStore(run: run), url = try await files.reserve(original: intent.original)
        let bytes = Data((0..<(2 * 131_072 + 73)).map { UInt8(truncatingIfNeeded: ($0 &* 31) ^ ($0 >> 9)) })
        try bytes.write(to: url, options: .withoutOverwriting)
        var lifecycle = try RecordingSaveLifecycle(intent: intent, intentToken: input.token(1), revision: 0)
        try lifecycle.acceptIntentCommit(receipt); try lifecycle.acceptRecordingEnd(context: input.context, evidence: input.end)
        try lifecycle.acceptFile(.init(context: input.context, original: intent.original, byteCount: UInt64(bytes.count), finalizedAt: input.time))
        _ = try lifecycle.acceptInspection(input.inspection(original: intent.original), resultToken: input.token(4))
        let result = try #require(lifecycle.resultRecord)
        try #require(result.result == .saved)
        guard case .committed = await store.execute(.commitResult(input.token(4), expectedRevision: 1, result)) else { throw BackendContractError.notCommitted }
        let access = ManagedOriginalAccess(store: store, originals: files)
        guard case .succeeded(let binding) = await access.bind(intent.original, operation: .init(rawValue: UUID().uuidString)),
              case .succeeded(let lease) = await access.acquireRead(binding.original, operation: .init(rawValue: UUID().uuidString.lowercased()),
                leaseID: .init(rawValue: UUID().uuidString)) else { throw BackendContractError.unavailable }
        return .init(store: store, files: files, access: access, binding: binding, lease: lease, url: url, bytes: bytes)
    }
    func range(index: UInt64, size: UInt64 = 131_072) throws -> UploadChunkRange {
        try .init(binding: .init(registration: .init(destination: .init(rawValue: "11111111-1111-4111-8111-111111111111"),
            id: .init(rawValue: "22222222-2222-4222-8222-222222222222"), generation: .init(rawValue: 1)), operation: lease.operation,
            original: lease.original, session: .init(rawValue: "33333333-3333-4333-8333-333333333333"), chunkSize: size), index: index)
    }
}
private nonisolated final class ChunkWriteProbe: Sendable {
    private let calls = Mutex(0)
    func next() -> Int { calls.withLock { $0 += 1; return $0 } }
    var count: Int { calls.withLock { $0 } }
}
private actor ChunkSourceGate {
    private var held = false
    private var arrival: CheckedContinuation<Void, Never>?, pending: CheckedContinuation<Void, Never>?
    func hold() async { held = true; arrival?.resume(); arrival = nil; await withCheckedContinuation { pending = $0 } }
    func waitUntilHeld() async { if held { return }; await withCheckedContinuation { arrival = $0 } }
    func release() { pending?.resume(); pending = nil }
}
private nonisolated func chunkSourceURL(_ run: ExplorationRunDirectory, id: ManagedUploadSourceID) -> URL {
    run.url.appendingPathComponent("background-upload-sources").appendingPathComponent(id.rawValue + ".upload")
}
private nonisolated func chunkSourceFingerprint(_ url: URL) throws -> OriginalFileFingerprint {
    var value = stat()
    guard lstat(url.path, &value) == 0 else { throw BackendContractError.unavailable }
    return try .init(info: value)
}
private nonisolated func chunkSourceDescriptorClosed(_ fd: Int32, file: ManagedUploadFileIdentity) -> Bool {
    var value = stat()
    if fstat(fd, &value) != 0 { return errno == EBADF }
    return Int64(value.st_dev) != file.device || UInt64(value.st_ino) != file.inode
}
private nonisolated func chunkSourceFinish(_ owner: ManagedUploadSource, chunk: ManagedUploadChunkIdentity, lease: OriginalReadLease) async throws {
    _ = try await owner.uploadFile(for: chunk.source, lease: lease)
    let binding = backgroundFileBinding()
    try await owner.retain(chunk.source, lease: lease, for: binding)
    _ = try await owner.finish(chunk.source, lease: lease, terminal: .init(binding: binding, outcome: .cancelled))
}
private nonisolated func chunkSourceExpect(_ expected: BackendContractError, _ action: () async throws -> Void) async {
    do { try await action(); Issue.record("Expected chunk rejection \(expected)") }
    catch let error as BackendContractError { #expect(error == expected) }
    catch { Issue.record("Unexpected failure \(error)") }
}
