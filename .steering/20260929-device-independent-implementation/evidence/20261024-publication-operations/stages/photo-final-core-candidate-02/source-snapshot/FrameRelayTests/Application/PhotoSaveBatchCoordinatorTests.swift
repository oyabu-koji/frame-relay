import Foundation
import Testing
@testable import FrameRelay

@Suite(.serialized) @MainActor struct PhotoSaveBatchCoordinatorTests {
    @Test(arguments: [NetworkCondition.unknown, .offline, .cellular])
    func newRequestWithoutObservedWiFiHasZeroJournalUsePermissionAndSDK(condition: NetworkCondition) async throws {
        let f = try await ProductPhotoSaveBatchFixture.make()
        f.network.set(condition)
        let before = try await mediaSnapshot(f.services.store), coordinator = f.coordinator()
        let response = await coordinator.submit(try await f.request())
        guard case .rejected = response else { Issue.record("Unsuitable native path must fail closed"); return }
        #expect(try await mediaSnapshot(f.services.store) == before)
        #expect(await f.factory.openedOwners == 0)
        #expect(await f.photos.statusCalls.isEmpty)
        #expect(await f.photos.permissionCalls.isEmpty)
        #expect(await f.photos.commands.isEmpty)
        try f.assertSourcesUnchanged()
    }

    @Test func acceptedQueueCanContinueOfflineButRestartNeverAutomaticallyStartsIt() async throws {
        let f = try await ProductPhotoSaveBatchFixture.make()
        let owner = try photoBatchCaptureOwner()
        f.capture.begin(owner, phases: [.recording])
        let coordinator = f.coordinator(), request = try await f.request()
        #expect(await coordinator.submit(request) == .accepted)
        await coordinator.waitForIdle()
        #expect(try await mediaSnapshot(f.services.store).photoSaveBatches.first?.targets.first?.status == .queued)
        #expect(await f.factory.openedOwners == 0)
        #expect(await f.photos.commands.isEmpty)
        let reopened = try SQLiteRecordingStore(run: f.services.run, mode: .openExisting)
        let restored = f.coordinator(store: reopened)
        f.capture.end(owner); f.network.set(.offline)
        await restored.captureDidChange(); await restored.waitForIdle()
        #expect(await f.photos.commands.isEmpty)
        await restored.resume(request.operation); await restored.waitForIdle()
        #expect(await f.photos.commands.count == 1)
        let result = try await mediaSnapshot(f.services.store)
        #expect(result.photoSaveBatches.first?.targets.first?.outcome == .succeeded(localIdentifier: nil))
        #expect(result.temporaryMedia.first?.usages.isEmpty == true)
        try f.assertSourcesUnchanged()
    }

    @Test func preparedUseSurvivesCaptureHoldAndWakeReadsLatestOwners() async throws {
        let f = try await ProductPhotoSaveBatchFixture.make()
        let gate = PhotoBatchPreparationGate(base: f.execution)
        await gate.hold()
        let coordinator = f.coordinator(execution: gate), request = try await f.request()
        #expect(await coordinator.submit(request) == .accepted)
        #expect(await photoBatchEventually { await gate.prepared == 1 })
        let first = try photoBatchCaptureOwner(), second = try photoBatchCaptureOwner()
        f.capture.begin(first, phases: [.recording]); f.capture.begin(second, phases: [.saving])
        await gate.release(); await coordinator.waitForIdle()
        let held = try await mediaSnapshot(f.services.store)
        #expect(held.temporaryMedia[0].usages.count == 1 && !held.temporaryMedia[0].reclaimed)
        #expect(held.photoSaveBatches[0].targets[0].status == .queued)
        #expect(await f.photos.commands.isEmpty)
        f.capture.end(first); await coordinator.captureDidChange(); await coordinator.waitForIdle()
        #expect(await f.photos.commands.isEmpty)
        f.network.set(.offline); f.capture.end(second)
        await coordinator.captureDidChange(); await coordinator.waitForIdle()
        #expect(await f.photos.commands.count == 1)
        #expect(await gate.prepared == 1)
        #expect(try await mediaOriginalSnapshot(f.services.store).logicalOriginals.allSatisfy { $0.mediaReaders.isEmpty })
        try f.assertSourcesUnchanged()
    }

    @Test func cancelWhileBeginResponseIsLostNeverStartsSDKAfterExactLookupAndKeepsStartingUncertain() async throws {
        let f = try await ProductPhotoSaveBatchFixture.make()
        let fault = PhotoBatchBeginFaultStore(base: f.services.store)
        let coordinator = f.coordinator(store: fault), request = try await f.request()
        #expect(await coordinator.submit(request) == .accepted)
        #expect(await photoBatchEventually { await fault.beginCommits == 1 })
        await coordinator.cancel(request.operation)
        #expect(await f.photos.commands.isEmpty)
        await fault.reveal(); await coordinator.waitForIdle()
        let result = try await mediaSnapshot(f.services.store)
        guard case .starting(let child) = result.photoSaveBatches[0].targets[0].status else {
            Issue.record("A begun cancellation cannot be promoted to queued-only notProcessed"); return
        }
        #expect(result.photoSaveBatches[0].targets[0].registration == nil && result.photoRegistrations.isEmpty)
        #expect(result.temporaryMedia[0].usages.isEmpty && result.temporaryMedia[0].reclaimed)
        #expect(await f.photos.statusCalls.isEmpty)
        #expect(await f.photos.commands.isEmpty)
        #expect(await fault.beginCommits == 1)
        #expect(await fault.lookups.contains(child.mutation))
        let retained = try #require(await fault.beginMutation)
        #expect(PhotoSaveBatchValueValidation.exact(retained, child.mutation))
        let restored = f.coordinator(store: try SQLiteRecordingStore(run: f.services.run, mode: .openExisting))
        await restored.resume(request.operation); await restored.waitForIdle()
        #expect(await f.photos.commands.isEmpty)
        try f.assertSourcesUnchanged()
    }

    @Test func captureArrivingAtPreparedActorHopKeepsCapabilityForSameChildWake() async throws {
        let f = try await ProductPhotoSaveBatchFixture.make()
        let execution = PhotoBatchPerformGateExecution(base: f.execution)
        let changes = PhotoBatchChangeGate()
        let coordinator = f.coordinator(execution: execution, didChange: { await changes.observe() }), request = try await f.request()
        #expect(await coordinator.submit(request) == .accepted)
        #expect(await photoBatchEventually { await execution.entered() })
        let owner = try photoBatchCaptureOwner()
        f.capture.begin(owner, phases: [.recovery])
        await changes.arm(); await execution.unblock()
        #expect(await photoBatchEventually { await changes.entered })
        let held = try await mediaSnapshot(f.services.store)
        guard case .starting = held.photoSaveBatches[0].targets[0].status else { Issue.record("Expected durable begin"); return }
        #expect(held.temporaryMedia[0].usages.count == 1 && held.photoRegistrations.isEmpty)
        #expect(await f.photos.commands.isEmpty)
        // Wake while the old driver is suspended in its terminal callback.
        // The old driver's defer must drain the request after clearing itself.
        f.capture.end(owner); await coordinator.captureDidChange()
        await changes.release(); await coordinator.waitForIdle()
        #expect(await execution.preparations == 1)
        #expect(await f.photos.commands.count == 1)
        #expect(try await mediaSnapshot(f.services.store).temporaryMedia[0].usages.isEmpty)
    }

    @Test func sameOperationIsIdempotentAndUnicodeAliasCannotBorrowAcceptedRequest() async throws {
        let f = try await ProductPhotoSaveBatchFixture.make()
        let owner = try photoBatchCaptureOwner(); f.capture.begin(owner, phases: [.recording])
        let coordinator = f.coordinator(), base = try await f.request()
        let request = PhotoSaveBatchRequest(operation: .init(rawValue: "photo-\u{00e9}"), targets: base.targets,
            displayedRevision: base.displayedRevision)
        #expect(await coordinator.submit(request) == .accepted)
        await coordinator.waitForIdle()
        let before = try await mediaSnapshot(f.services.store)
        f.network.set(.offline)
        #expect(await coordinator.submit(request) == .accepted)
        let alias = PhotoSaveBatchRequest(operation: .init(rawValue: "photo-e\u{0301}"), targets: base.targets,
            displayedRevision: base.displayedRevision)
        guard case .rejected = await coordinator.submit(alias) else { Issue.record("Unicode-normalized operation alias borrowed an accepted batch"); return }
        await coordinator.cancel(alias.operation)
        await coordinator.waitForIdle()
        #expect(try await mediaSnapshot(f.services.store) == before)
        f.capture.end(owner); await coordinator.captureDidChange(); await coordinator.waitForIdle()
        #expect(await f.photos.commands.count == 1)
        await coordinator.cancel(request.operation); await coordinator.waitForIdle()
        #expect(await f.photos.commands.count == 1)
    }

    @Test func definiteAcceptanceRejectionCannotBecomeANewOfflineCommitOnRepeatedAction() async throws {
        let f = try await ProductPhotoSaveBatchFixture.make()
        let rejecting = PhotoBatchAcceptanceRejectStore(base: f.services.store)
        let coordinator = f.coordinator(store: rejecting), request = try await f.request()
        let before = try await mediaSnapshot(f.services.store)
        guard case .rejected = await coordinator.submit(request) else { Issue.record("Expected definite rejection"); return }
        #expect(await rejecting.attempts == 3)
        f.network.set(.offline)
        guard case .rejected = await coordinator.submit(request) else { Issue.record("Unaccepted proposal bypassed the new-request Wi-Fi gate"); return }
        #expect(await rejecting.attempts == 3)
        #expect(try await mediaSnapshot(f.services.store) == before)
        #expect(await f.factory.openedOwners == 0)
        #expect(await f.photos.statusCalls.isEmpty)
        #expect(await f.photos.commands.isEmpty)
    }

    @Test func cancelAfterPerformStartsCannotReleaseOrRepeatPhotoKit() async throws {
        let f = try await ProductPhotoSaveBatchFixture.make()
        await f.photos.holdAdd()
        let counted = PhotoBatchCountingStore(base: f.services.store)
        let coordinator = f.coordinator(store: counted), request = try await f.request()
        #expect(await coordinator.submit(request) == .accepted)
        #expect(await photoBatchEventually { await f.photos.commands.count == 1 })
        await coordinator.cancel(request.operation)
        let during = try await mediaSnapshot(f.services.store)
        #expect(during.temporaryMedia[0].usages.count == 1 && !during.temporaryMedia[0].reclaimed)
        #expect(during.photoRegistrations[0].outcome == nil)
        await f.photos.finishAdd(); await coordinator.waitForIdle()
        await coordinator.resume(request.operation); await coordinator.waitForIdle()
        #expect(await f.photos.commands.count == 1)
        #expect(try await mediaSnapshot(f.services.store).photoRegistrations[0].outcome == .succeeded(localIdentifier: nil))
        let reads = await counted.reads
        await coordinator.captureDidChange(); await coordinator.waitForIdle()
        #expect(await counted.reads == reads)
    }
}

private actor PhotoBatchAcceptanceRejectStore: MediaOperationStorePort {
    let base: SQLiteRecordingStore
    private(set) var attempts = 0
    init(base: SQLiteRecordingStore) { self.base = base }
    func load() async -> BackendStoreLoadResult { await base.load() }
    func commit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        if case .photoBatch(_, .accept) = mutation.change { attempts += 1; return .rejected(.revisionConflict) }
        return await base.commit(mutation)
    }
    func lookupCommit(_ mutation: BackendStoreMutation) async -> BackendCommitResult { await base.lookupCommit(mutation) }
}

private actor PhotoBatchCountingStore: MediaOperationStorePort {
    let base: SQLiteRecordingStore
    private(set) var reads = 0
    init(base: SQLiteRecordingStore) { self.base = base }
    func load() async -> BackendStoreLoadResult { reads += 1; return await base.load() }
    func commit(_ mutation: BackendStoreMutation) async -> BackendCommitResult { await base.commit(mutation) }
    func lookupCommit(_ mutation: BackendStoreMutation) async -> BackendCommitResult { await base.lookupCommit(mutation) }
}

private actor PhotoBatchChangeGate {
    private var armed = false
    private(set) var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    func arm() { armed = true }
    func observe() async {
        guard armed else { return }
        armed = false; entered = true
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
}

@MainActor private func photoBatchCaptureOwner() throws -> CaptureMediaOwner {
    .init(context: try CaptureFixture(clip: UUID().uuidString).context, visit: UUID(), nonce: UUID())
}

private actor PhotoBatchPerformGateExecution: PhotoSaveBatchExecutionPort {
    let base: ProductPhotoSaveBatch
    private var capability: PhotoBatchPerformGate?
    private(set) var preparations = 0
    init(base: ProductPhotoSaveBatch) { self.base = base }
    func source(for target: LibraryRenditionTarget) async throws -> PhotoSaveSource { try await base.source(for: target) }
    func prepare(_ target: PhotoSaveBatchTarget) async throws -> any PreparedPhotoSavePort {
        let cap = PhotoBatchPerformGate(base: try await base.prepare(target)); capability = cap; preparations += 1
        return cap
    }
    func entered() async -> Bool { await capability?.entered == true }
    func unblock() async { await capability?.unblock() }
}

private actor PhotoBatchPerformGate: PreparedPhotoSavePort {
    let base: any PreparedPhotoSavePort
    private var blocked = true
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var entered = false
    init(base: any PreparedPhotoSavePort) { self.base = base }
    func perform(_ child: CommittedPhotoSaveBatchChild) async -> BackendOutcome<PhotoRegistrationRecord> {
        entered = true
        if blocked { await withCheckedContinuation { continuation = $0 } }
        return await base.perform(child)
    }
    func releaseIfNotStarted() async -> Bool { await base.releaseIfNotStarted() }
    func unblock() { blocked = false; continuation?.resume(); continuation = nil }
}
