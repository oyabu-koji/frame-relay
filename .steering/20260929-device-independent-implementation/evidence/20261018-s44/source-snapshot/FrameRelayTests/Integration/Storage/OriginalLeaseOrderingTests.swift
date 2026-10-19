import Foundation
import Testing
@testable import FrameRelay

struct OriginalLeaseOrderingTests {
    @Test func unknownMovieProvidesBoundedFDReadsButIsNotTransferEligible() async throws {
        try await withStorageRun { run in
            let original = try await makeBindingMovie(run: run)
            let store = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let files = ManagedOriginalStore(run: run)
            let access = ManagedOriginalAccess(store: store, originals: files)
            #expect(await access.bind(original.reference, operation: .init(rawValue: "bind")) == .succeeded(original))
            guard case .described(let description) = await access.describe(original.reference) else { Issue.record("No descriptor"); return }
            #expect(description.saveResult == .unknown(.evidenceMissing))
            #expect(!description.isTransferEligible)
            #expect(await access.acquireRead(original.original, operation: .init(rawValue: "upload"), leaseID: .init(rawValue: "upload-reader")) == .notExecuted)
            let first = try await playbackLease(access, original: original.original, name: "first")
            let second = try await playbackLease(access, original: original.original, name: "second")
            let attachment = try await attach(access, lease: first, name: "SDK-first")
            let otherAttachment = try await attach(access, lease: second, name: "SDK-second")
            let url = try await files.existingURL(for: original.reference)
            let expected = try Data(contentsOf: url)
            #expect(try await access.readBytes(attachment, offset: 0, maximumLength: 64) == expected.prefix(64))
            #expect(try await access.readBytes(otherAttachment, offset: 16, maximumLength: 31) == expected.subdata(in: 16..<47))
            #expect(try await access.readBytes(attachment, offset: original.original.content.byteCount, maximumLength: 64).isEmpty)
            do {
                _ = try await access.readBytes(attachment, offset: 0, maximumLength: 65_537)
                Issue.record("Unbounded reader request was accepted")
            } catch let error as BackendContractError { #expect(error == .invalidValue) }
            await access.requestReaderStop(first)
            #expect(await access.isReaderStopRequested(first))
            #expect(await access.releaseRead(first) == .inProgress)
            #expect(await access.reconcileReaders(original.original) == .inProgress)
            do {
                _ = try await access.readBytes(attachment, offset: 0, maximumLength: 64)
                Issue.record("Stopped SDK reader received more bytes")
            } catch let error as BackendContractError { #expect(error == .wrongStage) }
            // A cancellation request and a stale delayed completion do not detach.
            let staleLease = OriginalReadLease(id: first.id, original: first.original, operation: first.operation,
                accessGeneration: .init(rawValue: 999), epoch: first.epoch)
            #expect(await access.readerDidFinish(.init(lease: staleLease, id: attachment.id)) == .notExecuted)
            #expect(await access.releaseRead(first) == .inProgress)
            #expect(await access.readerDidFinish(attachment) == .succeeded(first.id))
            #expect(await access.releaseRead(first) == .succeeded(.init(lease: first)))
            #expect(await access.reconcileReaders(original.original) == .inProgress)
            #expect(await access.readerDidFinish(otherAttachment) == .succeeded(second.id))
            #expect(await access.releaseRead(second) == .succeeded(.init(lease: second)))
            guard case .succeeded(let released) = await access.reconcileReaders(original.original) else {
                Issue.record("Every SDK reader and descriptor should now be released"); return
            }
            #expect(released.accessGeneration.rawValue == 2)
            #expect(await access.readerDidFinish(attachment) == .notExecuted)
            #expect(try Data(contentsOf: url) == expected)
        }
    }

    @Test(arguments: [false, true])
    func delayedOpeningCannotBeReleasedBeforeItsActualCompletion(cancelTask: Bool) async throws {
        try await withStorageRun { run in
            let binding = try await makeBindingMovie(run: run)
            let store = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let files = ManagedOriginalStore(run: run)
            let opener = DelayedOriginalOpener(files: files)
            let access = ManagedOriginalAccess(store: store, originals: files, opener: opener)
            _ = await access.bind(binding.reference, operation: .init(rawValue: "bind"))
            guard case .succeeded(let before) = await access.reconcileReaders(binding.original) else { Issue.record("No initial reader state"); return }
            let acquiring = Task {
                await access.acquirePlayback(binding.original, operation: .init(rawValue: "delayed-play"),
                                             leaseID: .init(rawValue: "delayed-reader"))
            }
            await opener.waitUntilRequested()
            guard case .succeeded(let state) = await store.loadOriginalState() else { Issue.record("No lease ledger"); return }
            let lease = try #require(state.originals.first?.readers.first)
            #expect(await access.releaseRead(lease) == .inProgress)
            #expect(await access.reconcileReaders(binding.original) == .inProgress)
            let intent = RemovalIntent(operation: .init(rawValue: "discard-during-open"), original: binding.original, purpose: .discard)
            #expect(await access.reserveRemoval(try removalRequest(intent, released: before)) == .notExecuted)
            await access.requestReaderStop(lease)
            if cancelTask { acquiring.cancel() }
            await opener.completeOpening()
            #expect(await acquiring.value == .notExecuted)
            #expect(await opener.completedHandleIsClosedOrOpeningWasCancelled())
            guard case .succeeded(let after) = await access.reconcileReaders(binding.original) else {
                Issue.record("Open completion must close the descriptor before clearing the ledger"); return
            }
            #expect(after.accessGeneration.rawValue == 1)
        }
    }

    @Test func sameSizeInPlaceChangeAfterOpeningIsRejectedByFingerprint() async throws {
        try await withStorageRun { run in
            let binding = try await makeBindingMovie(run: run)
            let store = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let files = ManagedOriginalStore(run: run)
            let access = ManagedOriginalAccess(store: store, originals: files)
            _ = await access.bind(binding.reference, operation: .init(rawValue: "bind"))
            let lease = try await playbackLease(access, original: binding.original, name: "reader")
            let attachment = try await attach(access, lease: lease, name: "SDK")
            _ = try await access.readBytes(attachment, offset: 0, maximumLength: 64)
            let url = try await files.existingURL(for: binding.reference)
            let writer = try FileHandle(forWritingTo: url)
            try writer.write(contentsOf: Data(repeating: 17, count: 1))
            try writer.synchronize()
            try writer.close()
            do {
                _ = try await access.readBytes(attachment, offset: 0, maximumLength: 64)
                Issue.record("In-place content change reached the SDK")
            } catch let error as BackendContractError { #expect(error == .identityMismatch) }
            _ = await access.readerDidFinish(attachment)
            #expect(await access.releaseRead(lease) == .succeeded(.init(lease: lease)))
        }
    }

    @Test func newAdapterCannotTreatOldPersistedReadersAsReleased() async throws {
        try await withStorageRun { run in
            let binding = try await makeBindingMovie(run: run)
            let store = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let files = ManagedOriginalStore(run: run)
            let first = ManagedOriginalAccess(store: store, originals: files)
            _ = await first.bind(binding.reference, operation: .init(rawValue: "bind"))
            let lease = try await playbackLease(first, original: binding.original, name: "old-owner")
            let sdk = try await attach(first, lease: lease, name: "old-sdk")
            let reopened = try SQLiteRecordingStore(run: .openExisting(at: run.url), mode: .openExisting)
            let newOwner = ManagedOriginalAccess(store: reopened, originals: ManagedOriginalStore(run: run))
            #expect(await newOwner.reconcileReaders(binding.original) == .inProgress)
            #expect(await newOwner.recoverPersistedReaders(binding.original) == .unknown)
            #expect(await newOwner.releaseRead(lease) == .notExecuted)
            _ = await first.readerDidFinish(sdk)
            _ = await first.releaseRead(lease)
            guard case .succeeded(let released) = await newOwner.reconcileReaders(binding.original) else {
                Issue.record("Current disk ledger should reflect the real owner's close"); return
            }
            #expect(released.epoch != lease.epoch)
            #expect(released.accessGeneration == lease.accessGeneration)
        }
    }

    @Test func removalAndInvalidationReservationsPersistAndRejectBothConflictOrders() async throws {
        try await withStorageRun { run in
            let binding = try await makeBindingMovie(run: run)
            let store = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let files = ManagedOriginalStore(run: run)
            let access = ManagedOriginalAccess(store: store, originals: files)
            _ = await access.bind(binding.reference, operation: .init(rawValue: "bind"))
            guard case .succeeded(let initial) = await access.reconcileReaders(binding.original) else { Issue.record("No initial release"); return }
            let intent = RemovalIntent(operation: .init(rawValue: "discard"), original: binding.original, purpose: .discard)
            let cleanup = RemovalIntent(operation: .init(rawValue: "cleanup"), original: binding.original, purpose: .cleanup)
            #expect(await access.reserveRemoval(try removalRequest(cleanup, released: initial)) == .notExecuted)
            #expect(await access.reserveRemoval(try removalRequest(intent, released: initial)) == .succeeded(intent))
            let invalidation = invalidationFor(binding)
            #expect(await access.reserveInvalidation(invalidation) == .unknown)
            let reopened = try SQLiteRecordingStore(run: .openExisting(at: run.url), mode: .openExisting)
            let recovered = ManagedOriginalAccess(store: reopened, originals: ManagedOriginalStore(run: run))
            #expect(await recovered.acquirePlayback(binding.original, operation: .init(rawValue: "blocked-play"),
                leaseID: .init(rawValue: "blocked-reader")) == .notExecuted)
            #expect(await recovered.reconcileRemoval(intent, result: .unknown) == .unknown)
            #expect(await recovered.reconcileRemoval(intent, result: .succeeded(.init(intent: intent, resolution: .removed))) == .unknown)
            #expect(await recovered.reconcileRemoval(intent, result: .succeeded(.init(intent: intent, resolution: .notRemoved))) == .succeeded(intent))
            _ = try await mediaRegister(reopened, registration: invalidation.registration)
            _ = try await mediaCommit(reopened, .publication(mediaPublication(invalidation.rendition,
                                                                             registration: invalidation.registration)))
            try await mediaReconcile(reopened, original: binding.original)
            #expect(await recovered.reserveInvalidation(invalidation) == .succeeded(.init(record: invalidation)))
            guard case .succeeded(let current) = await recovered.reconcileReaders(binding.original) else { Issue.record("No current release"); return }
            #expect(await recovered.reserveRemoval(try removalRequest(intent, released: current)) == .unknown)
            let fakeAck = InvalidationAcknowledgement(record: invalidation, commit: .init(key: invalidation.key,
                previousRevision: 100, committedRevision: 101))
            #expect(await recovered.finishInvalidation(fakeAck) == .unknown)
            let again = try SQLiteRecordingStore(run: run, mode: .openExisting)
            guard case .succeeded(let state) = await again.loadOriginalState() else { Issue.record("No persisted ordering"); return }
            #expect(state.originals.first?.invalidation?.record == invalidation)
            #expect(state.originals.first?.removal == nil)
            #expect(state.originals.first?.resolvedRemoval == intent)
            #expect(state.originals.first?.removalResolution == .notRemoved)
            #expect(await files.observeFile(binding.reference) == .present(byteCount: binding.original.content.byteCount))
        }
    }

    @Test func resolvedRemovalRetainsIdentityAndPurposeUntilNextReservation() async throws {
        try await withStorageRun { run in
            // Legacy cleanup history is covered by the fixed schema-3 migration
            // tests. Fresh cleanup now needs actual persisted evidence selection.
            let purpose = RemovalPurpose.discard
            let binding = try await makeBindingMovie(run: run)
            let intent = RemovalIntent(operation: .init(rawValue: "resolved-operation"),
                                       original: binding.original, purpose: purpose)
            try await persistNotRemovedResult(run: run, binding: binding, intent: intent)
            let reopened = try SQLiteRecordingStore(run: .openExisting(at: run.url), mode: .openExisting)
            guard case .succeeded(let snapshot) = await reopened.loadOriginalState() else {
                Issue.record("Expected journal replay after discarding the writer instance"); return
            }
            let state = try #require(snapshot.originals.first)
            #expect(state.removal == nil)
            #expect(state.resolvedRemoval == intent)
            #expect(state.resolvedRemoval?.purpose == purpose)
            #expect(state.resolvedRemoval?.operation == intent.operation)
            #expect(state.resolvedRemoval?.original == binding.original)
            #expect(state.removalResolution == .notRemoved)
            let next = RemovalIntent(operation: .init(rawValue: "next-operation"), original: binding.original,
                                     purpose: .discard)
            let nextMutation = OriginalStoreMutation(operation: .init(rawValue: "reserve-next"),
                expectedRevision: snapshot.revision,
                change: .reserveRemoval(next, expectedInvalidation: state.invalidationGeneration,
                                         expectedAccess: state.accessGeneration))
            guard case .committed = await reopened.commitOriginal(nextMutation) else {
                Issue.record("Expected a new reservation after confirmed not-removed"); return
            }
            let again = try SQLiteRecordingStore(run: .openExisting(at: run.url), mode: .openExisting)
            guard case .succeeded(let pending) = await again.loadOriginalState() else {
                Issue.record("Expected pending operation after another reopen"); return
            }
            #expect(pending.originals.first?.removal == next)
            #expect(pending.originals.first?.resolvedRemoval == nil)
            #expect(pending.originals.first?.removalResolution == nil)
        }
    }

    @Test func staleAllReleasedReceiptCannotAuthorizeRemovalAfterNewReaderGeneration() async throws {
        try await withStorageRun { run in
            let binding = try await makeBindingMovie(run: run)
            let store = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let access = ManagedOriginalAccess(store: store, originals: ManagedOriginalStore(run: run))
            _ = await access.bind(binding.reference, operation: .init(rawValue: "bind"))
            guard case .succeeded(let stale) = await access.reconcileReaders(binding.original) else { Issue.record("No stale observation"); return }
            let lease = try await playbackLease(access, original: binding.original, name: "new-reader")
            let intent = RemovalIntent(operation: .init(rawValue: "discard"), original: binding.original, purpose: .discard)
            #expect(await access.reserveRemoval(try removalRequest(intent, released: stale)) == .notExecuted)
            _ = await access.releaseRead(lease)
            #expect(await access.reserveRemoval(try removalRequest(intent, released: stale)) == .notExecuted)
            guard case .succeeded(let current) = await access.reconcileReaders(binding.original) else { Issue.record("No current observation"); return }
            #expect(await access.reserveRemoval(try removalRequest(intent, released: current)) == .succeeded(intent))
        }
    }

    @Test func sameSizeContentReplacementIsRejectedBeforeAnyBytesAreExposed() async throws {
        try await withStorageRun { run in
            let binding = try await makeBindingMovie(run: run)
            let store = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let files = ManagedOriginalStore(run: run)
            let access = ManagedOriginalAccess(store: store, originals: files)
            _ = await access.bind(binding.reference, operation: .init(rawValue: "bind"))
            let url = try await files.existingURL(for: binding.reference)
            // Only this test's newly generated movie is fault-injected.
            try Data(repeating: 7, count: Int(binding.original.content.byteCount)).write(to: url)
            #expect(await access.acquirePlayback(binding.original, operation: .init(rawValue: "play"),
                leaseID: .init(rawValue: "reader")) == .failed(.contentMismatch))
            #expect(await access.bind(binding.reference, operation: .init(rawValue: "rebind")) == .failed(.contentMismatch))
            #expect(await access.describe(binding.reference) == .unavailable(.contentMismatch))
            guard case .succeeded = await access.reconcileReaders(binding.original) else {
                Issue.record("Failed acquisition must release its registered descriptor ownership"); return
            }
        }
    }

    @Test func recordingWithoutCommittedEndCannotBindContent() async throws {
        try await withStorageRun { run in
            let fixture = try CaptureFixture()
            let store = try SQLiteRecordingStore(run: run, mode: .createNew)
            let files = ManagedOriginalStore(run: run)
            let save = OriginalSaveCoordinator(store: store, originals: files, inspection: AVOriginalInspectionAdapter(originals: files))
            _ = await save.begin(fixture.intent, token: fixture.token(1))
            let url = try await files.reservedURL(for: fixture.intent.original)
            try Data("synthetic-writer-in-progress".utf8).write(to: url, options: .withoutOverwriting)
            let access = ManagedOriginalAccess(store: store, originals: files)
            #expect(await access.bind(fixture.intent.original, operation: .init(rawValue: "premature-bind")) == .notExecuted)
            let state = try await mediaOriginalSnapshot(store)
            #expect(state.revision == 1 && state.originals.isEmpty && state.logicalOriginals.isEmpty)
        }
    }
}

/// Storage-contract input only: exercises both purposes without granting cleanup
/// eligibility or performing deletion. The actual fixture remains not removed.
nonisolated private func persistNotRemovedResult(run: ExplorationRunDirectory, binding: OriginalBinding,
                                                intent: RemovalIntent) async throws {
    let store = try SQLiteRecordingStore(run: run, mode: .openExisting)
    let mutations = [
        OriginalStoreMutation(operation: .init(rawValue: "bind-resolved-test"), expectedRevision: 2, change: .bind(binding)),
        OriginalStoreMutation(operation: .init(rawValue: "reserve-resolved-test"), expectedRevision: 3,
            change: .reserveRemoval(intent, expectedInvalidation: .init(rawValue: 0), expectedAccess: .init(rawValue: 0))),
        OriginalStoreMutation(operation: .init(rawValue: "resolve-not-removed"), expectedRevision: 4,
            change: .resolveRemoval(intent, .notRemoved))
    ]
    for mutation in mutations {
        guard case .committed = await store.commitOriginal(mutation) else { throw BackendContractError.notCommitted }
    }
}

private actor DelayedOriginalOpener: ManagedOriginalReadOpeningPort {
    private let files: ManagedOriginalStore
    private var isRequested = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var openWaiter: CheckedContinuation<Void, Never>?
    private var opened: ManagedOriginalReadHandle?
    private var cancelled = false

    init(files: ManagedOriginalStore) { self.files = files }

    func openBoundRead(_ binding: OriginalBinding) async throws -> ManagedOriginalReadHandle {
        await withCheckedContinuation { continuation in
            openWaiter = continuation
            isRequested = true
            startWaiter?.resume(); startWaiter = nil
        }
        do {
            let actual = try await files.openBoundRead(binding)
            opened = actual
            return actual
        } catch is CancellationError { cancelled = true; throw CancellationError() }
    }
    func waitUntilRequested() async {
        if isRequested { return }
        await withCheckedContinuation { startWaiter = $0 }
    }
    func completeOpening() { openWaiter?.resume(); openWaiter = nil }
    func completedHandleIsClosedOrOpeningWasCancelled() -> Bool {
        if cancelled { return true }
        guard let opened else { return false }
        do { _ = try opened.handle.offset(); return false }
        catch { return true }
    }
}

nonisolated private func playbackLease(_ access: ManagedOriginalAccess, original: OriginalContent,
                                       name: String) async throws -> OriginalReadLease {
    guard case .succeeded(let source) = await access.acquirePlayback(original,
        operation: .init(rawValue: "play-" + name), leaseID: .init(rawValue: name)) else {
        throw BackendContractError.unavailable
    }
    return source.lease
}

nonisolated private func attach(_ access: ManagedOriginalAccess, lease: OriginalReadLease,
                               name: String) async throws -> OriginalReaderAttachment {
    guard case .succeeded(let attachment) = await access.attachReader(lease, id: .init(rawValue: name)) else {
        throw BackendContractError.unavailable
    }
    return attachment
}

nonisolated private func removalRequest(_ intent: RemovalIntent, released: AllReadersReleasedReceipt) throws -> RemovalBoundaryRequest {
    var readers = OriginalReadersState(original: intent.original, epoch: released.epoch, generation: released.accessGeneration)
    try readers.reconcile([])
    return .init(intent: intent, eligibility: .eligible(intent.original, .init(rawValue: 0)),
        stopped: .neverStarted(.original(intent.original)), expectedTransport: .neverStarted(.original(intent.original)),
        released: released, readers: readers)
}

nonisolated private func invalidationFor(_ binding: OriginalBinding) -> InvalidationRecord {
    let rendition = RenditionIdentity(original: binding.original, inputLogIdentity: "synthetic-ordering-only",
        transformAssetIdentity: "synthetic", transformAssetVersion: "synthetic", outputConfigurationIdentity: "synthetic",
        conversionVersion: "synthetic", rendition: .init(rawValue: "synthetic-rendition"),
        deliveryContent: binding.original.content, publicationGeneration: .init(rawValue: 1))
    return .init(id: .init(rawValue: "synthetic-invalidation"), rendition: rendition,
        registration: .init(destination: .init(rawValue: "synthetic-server"), id: .init(rawValue: "synthetic-registration"),
                            generation: .init(rawValue: 1)), generation: .init(rawValue: 1))
}
