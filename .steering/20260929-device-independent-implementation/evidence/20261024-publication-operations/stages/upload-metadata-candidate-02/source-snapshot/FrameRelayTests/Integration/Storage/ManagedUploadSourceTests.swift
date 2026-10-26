import CryptoKit
import Darwin
import Foundation
import Testing
@testable import FrameRelay

struct ManagedUploadSourceTests {
    @Test(arguments: StorageCandidate.allCases)
    func exactFullCopyUsesBoundedOriginalReadsAndActualDescriptorClose(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let fixture = try await BackgroundUploadFixture.make(run: run, candidate: candidate)
            let owner = try ManagedUploadSource(run: run, originals: fixture.access)
            let source = try await owner.create(from: fixture.lease, id: .init(rawValue: UUID().uuidString))
            let upload = try await owner.uploadFile(for: source, lease: fixture.lease)
            let copied = try Data(contentsOf: upload.url)
            #expect(copied == fixture.bytes)
            #expect(source.content == (try renditionContent(copied)))
            #expect(source.content == fixture.binding.original.content)
            #expect(source.file.size == Int64(fixture.bytes.count))
            let before = await owner.resources()
            #expect(before.activeCopies == 0 && before.openHandles == 1 && before.closedHandles == 1)
            #expect(before.largestOriginalRead == 65_536 && before.copiedBytes == UInt64(fixture.bytes.count))
            let descriptor = try #require(before.descriptors.first)
            #expect(fcntl(descriptor, F_GETFD) >= 0)
            let binding = backgroundFileBinding()
            try await owner.retain(source, lease: fixture.lease, for: binding)
            #expect(await fixture.access.reconcileReaders(fixture.binding.original) == .inProgress)
            // Explicit synthetic terminal input tests file ownership only. Real
            // SDK completion is covered separately by opt-in session tests.
            let terminal = BackgroundMediaSDKTerminal(binding: binding, outcome: .cancelled)
            let closure = try await owner.finish(source, lease: fixture.lease, terminal: terminal)
            #expect(closure == .init(binding: binding, uploadSource: source, tasksJoined: true, handlesClosed: true))
            #expect(backgroundDescriptorNoLongerOwns(descriptor, file: source.file))
            let after = await owner.resources()
            #expect(after.openHandles == 0 && after.closedHandles == 2)
            #expect(try await owner.finish(source, lease: fixture.lease, terminal: terminal) == closure)
            #expect(await owner.resources().closedHandles == 2)
            // Closing our copy neither releases the input lease nor reclaims
            // the original or the managed copy by an invented retention rule.
            #expect(try await mediaOriginalSnapshot(fixture.store).originals.first?.readers == [fixture.lease])
            #expect(try Data(contentsOf: fixture.url) == fixture.bytes)
            #expect(try Data(contentsOf: upload.url) == fixture.bytes)
            #expect(await fixture.access.releaseRead(fixture.lease) == .succeeded(.init(lease: fixture.lease)))
            _ = try await owner.closeOwner()
        }
    }

    @Test func exchangedLeaseSourceAndTaskCannotCloseAnotherOwner() async throws {
        try await withStorageRun { run in
            let fixture = try await BackgroundUploadFixture.make(run: run)
            let owner = try ManagedUploadSource(run: run, originals: fixture.access)
            let source = try await owner.create(from: fixture.lease, id: .init(rawValue: UUID().uuidString))
            let wrongLease = OriginalReadLease(id: fixture.lease.id, original: fixture.lease.original,
                operation: .init(rawValue: "other-operation"), accessGeneration: fixture.lease.accessGeneration,
                epoch: fixture.lease.epoch)
            await backgroundExpectContract(.identityMismatch) {
                _ = try await owner.uploadFile(for: source, lease: wrongLease)
            }
            let wrongSource = ManagedUploadSourceIdentity(id: .init(rawValue: UUID().uuidString),
                directoryDevice: source.directoryDevice, directoryInode: source.directoryInode,
                file: source.file, content: source.content)
            await backgroundExpectContract(.identityMismatch) {
                _ = try await owner.uploadFile(for: wrongSource, lease: fixture.lease)
            }
            let binding = backgroundFileBinding()
            await backgroundExpectContract(.identityMismatch) {
                _ = try await owner.finish(wrongSource, lease: fixture.lease,
                    terminal: .init(binding: binding, outcome: .cancelled))
            }
            _ = try await owner.uploadFile(for: source, lease: fixture.lease)
            try await owner.retain(source, lease: fixture.lease, for: binding)
            let stale = BackgroundMediaTaskBinding(session: .init(identifier: binding.session.identifier,
                generation: .init(rawValue: UUID())), taskIdentifier: binding.taskIdentifier,
                taskDescription: binding.taskDescription)
            await backgroundExpectContract(.identityMismatch) {
                _ = try await owner.finish(source, lease: fixture.lease, terminal: .init(binding: stale, outcome: .cancelled))
            }
            let reusedNumeric = BackgroundMediaTaskBinding(session: binding.session,
                taskIdentifier: binding.taskIdentifier, taskDescription: UUID().uuidString)
            await backgroundExpectContract(.identityMismatch) {
                _ = try await owner.finish(source, lease: fixture.lease, terminal: .init(binding: reusedNumeric, outcome: .cancelled))
            }
            await backgroundExpectContract(.identityMismatch) {
                _ = try await owner.finish(source, lease: wrongLease, terminal: .init(binding: binding, outcome: .cancelled))
            }
            await backgroundExpectContract(.readersActive) { _ = try await owner.closeOwner() }
            #expect(await owner.resources().openHandles == 1)
            #expect(try await mediaOriginalSnapshot(fixture.store).originals.first?.readers == [fixture.lease])
            _ = try await owner.finish(source, lease: fixture.lease, terminal: .init(binding: binding, outcome: .cancelled))
            _ = await fixture.access.releaseRead(fixture.lease)
            _ = try await owner.closeOwner()
        }
    }

    @Test func copyDetectsOriginalChangeBetweenBoundedReadsAndKeepsPartialAsUnknown() async throws {
        try await withStorageRun { run in
            let fixture = try await BackgroundUploadFixture.make(run: run)
            let owner = try ManagedUploadSource(run: run, originals: fixture.access) { offset in
                guard offset == 65_536 else { return }
                let handle = try FileHandle(forWritingTo: fixture.url)
                do {
                    try handle.seek(toOffset: offset)
                    try handle.write(contentsOf: Data([fixture.bytes[Int(offset)] ^ 0xff]))
                    try handle.synchronize(); try handle.close()
                } catch { try? handle.close(); throw error }
            }
            let id = ManagedUploadSourceID(rawValue: UUID().uuidString)
            await backgroundExpectContract(.identityMismatch) { _ = try await owner.create(from: fixture.lease, id: id) }
            let state = await owner.resources()
            #expect(state.activeCopies == 0 && state.openHandles == 0 && state.closedHandles == 1)
            #expect(state.copiedBytes == 65_536 && state.largestOriginalRead == 65_536)
            let partial = run.url.appendingPathComponent("background-upload-sources").appendingPathComponent(id.rawValue + ".upload")
            let originalPartial = try Data(contentsOf: partial)
            #expect(originalPartial == fixture.bytes.prefix(65_536))
            // The same durable source ID cannot silently copy/retry over this
            // unresolved leaf, even though its original reader is now stopped.
            await backgroundExpectContract(.identityMismatch) { _ = try await owner.create(from: fixture.lease, id: id) }
            #expect(try Data(contentsOf: partial) == originalPartial)
            #expect(try await mediaOriginalSnapshot(fixture.store).originals.first?.readers == [fixture.lease])
            #expect(await fixture.access.releaseRead(fixture.lease) == .succeeded(.init(lease: fixture.lease)))
            _ = try await owner.closeOwner()
        }
    }

    @Test func cancellationDrainsActualCopyBeforeDetachingAndNeverExportsPartial() async throws {
        try await withStorageRun { run in
            let fixture = try await BackgroundUploadFixture.make(run: run)
            let barrier = BackgroundCopyBarrier()
            let owner = try ManagedUploadSource(run: run, originals: fixture.access) { offset in
                if offset == 65_536 { await barrier.checkpoint() }
            }
            let id = ManagedUploadSourceID(rawValue: UUID().uuidString)
            let copy = Task { try await owner.create(from: fixture.lease, id: id) }
            await barrier.waitUntilBlocked()
            #expect(await owner.resources().activeCopies == 1)
            #expect(await fixture.access.releaseRead(fixture.lease) == .inProgress)
            await backgroundExpectContract(.readersActive) { _ = try await owner.closeOwner() }
            copy.cancel()
            #expect(await owner.resources().openHandles == 1)
            await barrier.release()
            do { _ = try await copy.value; Issue.record("Cancelled copy returned an exportable identity") }
            catch is CancellationError {} catch { Issue.record("Unexpected copy failure: \(error)") }
            #expect(await owner.resources().openHandles == 0)
            #expect(await owner.resources().activeCopies == 0)
            #expect(try await mediaOriginalSnapshot(fixture.store).originals.first?.readers == [fixture.lease])
            #expect(await fixture.access.releaseRead(fixture.lease) == .succeeded(.init(lease: fixture.lease)))
            _ = try await owner.closeOwner()
        }
    }

    @Test(arguments: ["modified", "replacement", "symlink", "hardlink"])
    func copyPathAndContentExchangesAreRejectedAndForeignFilesKept(exchange: String) async throws {
        try await withStorageRun { run in
            let fixture = try await BackgroundUploadFixture.make(run: run)
            let owner = try ManagedUploadSource(run: run, originals: fixture.access)
            let source = try await owner.create(from: fixture.lease, id: .init(rawValue: UUID().uuidString))
            let upload = try await owner.uploadFile(for: source, lease: fixture.lease)
            let binding = backgroundFileBinding()
            try await owner.retain(source, lease: fixture.lease, for: binding)
            let external = run.url.appendingPathComponent("outside-upload-namespace.bin")
            let sentinel = Data(repeating: 91, count: fixture.bytes.count)
            try sentinel.write(to: external, options: .withoutOverwriting)
            let held = upload.url.deletingLastPathComponent().appendingPathComponent("unknown-retained-copy")
            if exchange == "modified" {
                let writer = try FileHandle(forWritingTo: upload.url)
                try writer.write(contentsOf: Data([fixture.bytes[0] ^ 0xff]))
                try writer.synchronize(); try writer.close()
            } else {
                try FileManager.default.moveItem(at: upload.url, to: held)
                switch exchange {
                case "replacement": try sentinel.write(to: upload.url, options: .withoutOverwriting)
                case "symlink": try FileManager.default.createSymbolicLink(at: upload.url, withDestinationURL: external)
                case "hardlink": #expect(link(external.path, upload.url.path) == 0)
                default: Issue.record("Unknown test exchange")
                }
            }
            await backgroundExpectContract(.identityMismatch) {
                _ = try await owner.uploadFile(for: source, lease: fixture.lease)
            }
            let fd = try #require(await owner.resources().descriptors.first)
            _ = try await owner.finish(source, lease: fixture.lease, terminal: .init(binding: binding, outcome: .cancelled))
            #expect(backgroundDescriptorNoLongerOwns(fd, file: source.file))
            #expect(try Data(contentsOf: external) == sentinel)
            #expect(try Data(contentsOf: fixture.url) == fixture.bytes)
            #expect(FileManager.default.fileExists(atPath: upload.url.path))
            if exchange != "modified" { #expect(try Data(contentsOf: held) == fixture.bytes) }
            _ = await fixture.access.releaseRead(fixture.lease)
            _ = try await owner.closeOwner()
            #expect(try Data(contentsOf: external) == sentinel)
        }
    }

    @Test func exchangedNamespaceRejectsExportButStillClosesOnlyOwnedFD() async throws {
        try await withStorageRun { run in
            let fixture = try await BackgroundUploadFixture.make(run: run)
            let owner = try ManagedUploadSource(run: run, originals: fixture.access)
            let source = try await owner.create(from: fixture.lease, id: .init(rawValue: UUID().uuidString))
            let upload = try await owner.uploadFile(for: source, lease: fixture.lease)
            let binding = backgroundFileBinding()
            try await owner.retain(source, lease: fixture.lease, for: binding)
            let root = upload.url.deletingLastPathComponent()
            let held = run.url.appendingPathComponent("unknown-held-upload-directory", isDirectory: true)
            try FileManager.default.moveItem(at: root, to: held)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            let foreign = root.appendingPathComponent(upload.url.lastPathComponent)
            let sentinel = Data([90, 91, 92])
            try sentinel.write(to: foreign, options: .withoutOverwriting)
            await backgroundExpectContract(.identityMismatch) {
                _ = try await owner.uploadFile(for: source, lease: fixture.lease)
            }
            _ = try await owner.finish(source, lease: fixture.lease, terminal: .init(binding: binding, outcome: .cancelled))
            _ = try await owner.closeOwner()
            #expect(try Data(contentsOf: foreign) == sentinel)
            #expect(try Data(contentsOf: held.appendingPathComponent(upload.url.lastPathComponent)) == fixture.bytes)
            #expect(try Data(contentsOf: fixture.url) == fixture.bytes)
            _ = await fixture.access.releaseRead(fixture.lease)
        }
    }

    @Test func unknownSourceAndExistingTemporaryAreRetainedAndNeverReused() async throws {
        try await withStorageRun { run in
            let fixture = try await BackgroundUploadFixture.make(run: run)
            let owner = try ManagedUploadSource(run: run, originals: fixture.access)
            let id = ManagedUploadSourceID(rawValue: UUID().uuidString)
            let unknown = run.url.appendingPathComponent("background-upload-sources").appendingPathComponent(id.rawValue + ".upload")
            let sentinel = Data([8, 6, 7, 5, 3, 0, 9])
            try sentinel.write(to: unknown, options: .withoutOverwriting)
            let temporary = run.url.appendingPathComponent("temporary", isDirectory: true)
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
            let existing = temporary.appendingPathComponent("already-managed.mov")
            try sentinel.write(to: existing, options: .withoutOverwriting)
            await backgroundExpectContract(.identityMismatch) { _ = try await owner.create(from: fixture.lease, id: id) }
            await backgroundExpectContract(.invalidValue) {
                _ = try await owner.create(from: fixture.lease, id: .init(rawValue: "../outside"))
            }
            #expect(await owner.resources().copiedBytes == 0)
            _ = try await owner.closeOwner()
            #expect(try Data(contentsOf: unknown) == sentinel)
            #expect(try Data(contentsOf: existing) == sentinel)
            #expect(try Data(contentsOf: fixture.url) == fixture.bytes)
            #expect(await fixture.access.releaseRead(fixture.lease) == .succeeded(.init(lease: fixture.lease)))
        }
    }

    @Test func namespaceSymlinkAndDuplicateOwnerAreRejectedWithoutFollowingExternalFiles() async throws {
        try await withStorageRun { run in
            let fixture = try await BackgroundUploadFixture.make(run: run)
            let owner = try ManagedUploadSource(run: run, originals: fixture.access)
            #expect(throws: BackendContractError.readersActive) {
                try ManagedUploadSource(run: run, originals: fixture.access)
            }
            _ = try await owner.closeOwner()
            let root = run.url.appendingPathComponent("background-upload-sources")
            let held = run.url.appendingPathComponent("held-upload-directory")
            try FileManager.default.moveItem(at: root, to: held)
            let external = run.url.appendingPathComponent("external-directory", isDirectory: true)
            try FileManager.default.createDirectory(at: external, withIntermediateDirectories: false)
            let sentinel = external.appendingPathComponent("owner.lock")
            try Data([45]).write(to: sentinel, options: .withoutOverwriting)
            try FileManager.default.createSymbolicLink(at: root, withDestinationURL: external)
            #expect(throws: BackendContractError.identityMismatch) {
                try ManagedUploadSource(run: run, originals: fixture.access)
            }
            #expect(try Data(contentsOf: sentinel) == Data([45]))
            #expect(try Data(contentsOf: fixture.url) == fixture.bytes)
            _ = await fixture.access.releaseRead(fixture.lease)
        }
    }

    @Test func newOwnerDoesNotAdoptOrDeleteAnUnattributedExistingCopy() async throws {
        try await withStorageRun { run in
            let fixture = try await BackgroundUploadFixture.make(run: run)
            let first = try ManagedUploadSource(run: run, originals: fixture.access)
            let source = try await first.create(from: fixture.lease, id: .init(rawValue: UUID().uuidString))
            let upload = try await first.uploadFile(for: source, lease: fixture.lease)
            let binding = backgroundFileBinding()
            try await first.retain(source, lease: fixture.lease, for: binding)
            _ = try await first.finish(source, lease: fixture.lease, terminal: .init(binding: binding, outcome: .cancelled))
            _ = try await first.closeOwner()
            let reopened = try ManagedUploadSource(run: run, originals: fixture.access)
            await backgroundExpectContract(.identityMismatch) {
                _ = try await reopened.uploadFile(for: source, lease: fixture.lease)
            }
            await backgroundExpectContract(.identityMismatch) {
                _ = try await reopened.finish(source, lease: fixture.lease, terminal: .init(binding: binding, outcome: .cancelled))
            }
            _ = try await reopened.closeOwner()
            #expect(try Data(contentsOf: upload.url) == fixture.bytes)
            #expect(try Data(contentsOf: fixture.url) == fixture.bytes)
            #expect(try await mediaOriginalSnapshot(fixture.store).originals.first?.readers == [fixture.lease])
            _ = await fixture.access.releaseRead(fixture.lease)
        }
    }
}

/// Binary file and explicitly synthetic saved-classification inputs. This
/// fixture tests full copy/hash/lease I/O and makes no camera/movie claim.
nonisolated struct BackgroundUploadFixture: Sendable {
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
        let input = try CaptureFixture(clip: "s23-upload-" + UUID().uuidString)
        guard case .committed(let intentCommit) = await store.execute(.commitIntent(input.token(1), expectedRevision: 0, input.intent)) else {
            throw BackendContractError.notCommitted
        }
        let files = ManagedOriginalStore(run: run)
        let url = try await files.reserve(original: input.intent.original)
        let bytes = Data((0..<(3 * 65_536 + 73)).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
        try bytes.write(to: url, options: .withoutOverwriting)
        var lifecycle = try RecordingSaveLifecycle(intent: input.intent, intentToken: input.token(1), revision: 0)
        try lifecycle.acceptIntentCommit(intentCommit)
        try lifecycle.acceptRecordingEnd(context: input.context, evidence: input.end)
        try lifecycle.acceptFile(.init(context: input.context, original: input.intent.original,
            byteCount: UInt64(bytes.count), finalizedAt: input.time))
        _ = try lifecycle.acceptInspection(input.inspection(), resultToken: input.token(4))
        let record = try #require(lifecycle.resultRecord)
        #expect(record.result == .saved)
        guard case .committed = await store.execute(.commitResult(input.token(4), expectedRevision: 1, record)) else {
            throw BackendContractError.notCommitted
        }
        let access = ManagedOriginalAccess(store: store, originals: files)
        guard case .succeeded(let binding) = await access.bind(input.intent.original, operation: .init(rawValue: "bind-source")),
              case .succeeded(let lease) = await access.acquireRead(binding.original,
                operation: .init(rawValue: "exact-upload-" + UUID().uuidString),
                leaseID: .init(rawValue: "exact-reader-" + UUID().uuidString)) else {
            throw BackendContractError.unavailable
        }
        return .init(store: store, files: files, access: access, binding: binding, lease: lease, url: url, bytes: bytes)
    }
}

nonisolated func backgroundFileBinding() -> BackgroundMediaTaskBinding {
    .init(session: .init(identifier: .init(rawValue: "FrameRelay.file-ownership-test." + UUID().uuidString),
        generation: .init(rawValue: UUID())), taskIdentifier: 1, taskDescription: UUID().uuidString)
}

private nonisolated func backgroundDescriptorNoLongerOwns(_ fd: Int32, file: ManagedUploadFileIdentity) -> Bool {
    var info = stat()
    if fstat(fd, &info) != 0 { return errno == EBADF }
    // Concurrent tests may reuse a descriptor number after a genuine close.
    return Int64(info.st_dev) != file.device || UInt64(info.st_ino) != file.inode
}

private nonisolated func backgroundExpectContract(_ expected: BackendContractError,
    _ action: () async throws -> Void) async {
    do { try await action(); Issue.record("Expected contract rejection \(expected)") }
    catch let error as BackendContractError { #expect(error == expected) }
    catch { Issue.record("Unexpected error \(error)") }
}

private actor BackgroundCopyBarrier {
    private var blocked = false
    private var entered: [CheckedContinuation<Void, Never>] = []
    private var pending: CheckedContinuation<Void, Never>?
    func checkpoint() async {
        blocked = true
        let entered = entered; self.entered.removeAll()
        for waiter in entered { waiter.resume() }
        await withCheckedContinuation { pending = $0 }
    }
    func waitUntilBlocked() async {
        if blocked { return }
        await withCheckedContinuation { entered.append($0) }
    }
    func release() { pending?.resume(); pending = nil }
}
