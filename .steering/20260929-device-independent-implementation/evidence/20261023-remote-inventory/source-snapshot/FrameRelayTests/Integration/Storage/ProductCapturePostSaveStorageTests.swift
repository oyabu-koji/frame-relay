import Foundation
import CryptoKit
import Darwin
import Testing
@testable import FrameRelay

struct ProductCapturePostSaveStorageTests {
    @Test func unboundCommittedMovieReopensAsReconciliationWithoutAuthorizingTransferOrRemoval() async throws {
        try await withStorageRun { run in
            // This fixture commits the actual MOV save but deliberately does not bind it.
            let binding = try await makeBindingMovie(run: run)
            let reopened = try ExplorationRunDirectory.openExisting(at: run.url)
            let store = try SQLiteRecordingStore(run: reopened, mode: .openExisting)
            let files = ManagedOriginalStore(run: reopened)
            let reader = LibraryStoreReader(store: store, files: files)
            guard case .loaded(let snapshot) = await reader.loadLibrary() else {
                Issue.record("Unbound durable save should remain visible"); return
            }
            let item = try #require(snapshot.items.first)
            #expect(snapshot.revision == 2)
            #expect(item.recording.result == binding.saveRecord)
            #expect(item.file == .present(byteCount: binding.original.content.byteCount))
            #expect(item.original == nil)
            #expect(item.requiresReconciliation)
            #expect(item.status(.original).contains("内容の対応未確定"))
            #expect(snapshot.history.isEmpty)
            let access = ManagedOriginalAccess(store: store, originals: files)
            #expect(await access.describe(binding.reference) == .unavailable(.inaccessible))
            #expect(await access.acquireRead(binding.original, operation: .init(rawValue: "unbound-upload"),
                leaseID: .init(rawValue: "unbound-reader")) == .notExecuted)
            #expect(await access.acquirePlayback(binding.original, operation: .init(rawValue: "unbound-play"),
                leaseID: .init(rawValue: "unbound-player")) == .notExecuted)
            let epoch = ReaderReconciliationEpoch(rawValue: "untrusted-test-epoch")
            let released = AllReadersReleasedReceipt(original: binding.original,
                accessGeneration: .init(rawValue: 0), epoch: epoch)
            var readers = OriginalReadersState(original: binding.original, epoch: epoch, generation: .init(rawValue: 0))
            try readers.reconcile([])
            for purpose: RemovalPurpose in [.cleanup, .discard] {
                let intent = RemovalIntent(operation: .init(rawValue: "unbound-remove"), original: binding.original, purpose: purpose)
                let request = RemovalBoundaryRequest(intent: intent, eligibility: .eligible(binding.original, .init(rawValue: 0)),
                    stopped: .neverStarted(.original(binding.original)), expectedTransport: .neverStarted(.original(binding.original)),
                    released: released, readers: readers)
                #expect(await access.reserveRemoval(request) == .notExecuted)
            }
            #expect(await reader.loadLibrary() == .loaded(snapshot))
            guard case .succeeded(let state) = await store.loadOriginalState() else {
                Issue.record("Durable store disappeared"); return
            }
            #expect(state.revision == 2)
            #expect(state.originals.isEmpty)
            #expect(try await files.digest(for: binding.reference).sha256 == binding.original.content.digest)
        }
    }

    @Test(arguments: [false, true])
    func actualDigestDoesNotBlockReservationAndCancellationClosesOnlyAfterReadReturns(cancel: Bool) async throws {
        try await withStorageRun { run in
            let checkpoint = OriginalDigestCheckpoint()
            let files = ManagedOriginalStore(run: run, digestCheckpoint: { await checkpoint.pause($0) })
            let original = CaptureOriginalReference(rawValue: "digest-original")
            let url = try await files.reserve(original: original)
            let bytes = Data((0..<131_101).map { UInt8($0 % 251) })
            try bytes.write(to: url)
            let hashing = Task { try await files.digest(for: original) }
            await checkpoint.waitUntilHeld()
            #expect(await checkpoint.originalDescriptorIsOpen())
            let next = CaptureOriginalReference(rawValue: "next-recording")
            let nextURL = try await files.reserve(original: next)
            #expect(try await files.reservedURL(for: next) == nextURL)
            #expect(await files.observeFile(next) == .absent)
            if cancel { hashing.cancel() }
            // A cancellation request must not close a descriptor the worker still owns.
            #expect(await checkpoint.originalDescriptorIsOpen())
            await checkpoint.release()
            switch await hashing.result {
            case .success(let digest):
                #expect(!cancel)
                #expect(digest.original == original)
                #expect(digest.byteCount == UInt64(bytes.count))
                #expect(digest.sha256 == SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
            case .failure(let error):
                #expect(cancel)
                #expect(error is CancellationError)
            }
            #expect(await !checkpoint.originalDescriptorIsOpen())
            #expect(try Data(contentsOf: url) == bytes)
        }
    }

    @Test(arguments: [false, true])
    func boundReadCancellationAndConcurrentChangeRejectTheActualDescriptor(cancel: Bool) async throws {
        try await withStorageRun { run in
            let binding = try await makeBindingMovie(run: run)
            let checkpoint = OriginalDigestCheckpoint()
            let files = ManagedOriginalStore(run: run, digestCheckpoint: { await checkpoint.pause($0) })
            let opening = Task { try await files.openBoundRead(binding) }
            await checkpoint.waitUntilHeld()
            #expect(await checkpoint.originalDescriptorIsOpen())
            if cancel {
                opening.cancel()
            } else {
                let url = try await files.existingURL(for: binding.reference)
                let writer = try FileHandle(forWritingTo: url)
                try writer.truncate(atOffset: 1)
                try writer.synchronize()
                try writer.close()
            }
            #expect(await checkpoint.originalDescriptorIsOpen())
            await checkpoint.release()
            do {
                let handle = try await opening.value
                try handle.handle.close()
                Issue.record("Cancelled or changed original must not return a bound read")
            } catch {
                if cancel { #expect(error is CancellationError) }
                else { #expect(error is ExplorationStorageError) }
            }
            #expect(await !checkpoint.originalDescriptorIsOpen())
        }
    }
}

private actor OriginalDigestCheckpoint {
    private let gate = ProductCaptureTestGate()
    private var descriptor: Int32?
    private var device: dev_t?
    private var inode: ino_t?

    func pause(_ descriptor: Int32) async {
        self.descriptor = descriptor
        var info = stat()
        if fstat(descriptor, &info) == 0 { device = info.st_dev; inode = info.st_ino }
        await gate.holdOnce()
    }

    func waitUntilHeld() async { await gate.waitUntilHeld() }
    func release() async { await gate.release() }

    func originalDescriptorIsOpen() -> Bool {
        guard let descriptor, let device, let inode else { return false }
        var info = stat()
        return fstat(descriptor, &info) == 0 && info.st_dev == device && info.st_ino == inode
    }
}
