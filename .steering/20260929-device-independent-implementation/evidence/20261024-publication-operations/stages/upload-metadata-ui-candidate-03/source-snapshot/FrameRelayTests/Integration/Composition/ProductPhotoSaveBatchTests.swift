import Foundation
import Synchronization
import Testing
@testable import FrameRelay

@Suite(.serialized) @MainActor struct ProductPhotoSaveBatchTests {
    @Test func fixedMixedTargetsPersistIndependentOutcomesAndOnlyKnownNonAdditionCanRetryOnce() async throws {
        let photos = PhotoBatchLibrary(outcomes: [.succeeded(localIdentifier: nil), .failed(.rejected), .unknown(localIdentifier: nil)])
        let f = try await ProductPhotoSaveBatchFixture.make(locals: [true, false, false], photos: photos)
        let coordinator = f.coordinator(), request = try await f.request()
        #expect(await coordinator.submit(request) == .accepted)
        await coordinator.waitForIdle()
        let snapshot = try await mediaSnapshot(f.services.store), batch = try #require(snapshot.photoSaveBatches.first)
        #expect(batch.targets.count == 3 && batch.targets.map(\.target.source.rendition) == f.renditions.map(\.rendition))
        #expect(batch.targets.map(\.outcome) == [.succeeded(localIdentifier: nil), .failed(.rejected), .unknown(localIdentifier: nil)])
        #expect(batch.targets.allSatisfy { $0.registration?.registration.intent.operation == $0.target.operation })
        #expect(snapshot.temporaryMedia.map { $0.usages.count } == [0, 0, 0])
        #expect(snapshot.temporaryMedia.map(\.reclaimed) == [true, false, false])
        #expect(await photos.commands.count == 3)
        guard case .loaded(let library) = await f.services.reader.loadLibrary() else { Issue.record("Product reader failed"); return }
        #expect(library.items.count == 1 && library.remoteItems.count == 2)
        #expect(library.photoSaveBatches == snapshot.photoSaveBatches)
        #expect(library.remoteItems.allSatisfy { $0.photoRegistrations.count == 1 })
        #expect(library.remoteItems.allSatisfy { row in
            row.photoRegistrations.allSatisfy {
                PhotoSaveBatchValueValidation.exact($0.record.registration.intent.rendition.original, row.original)
                    && PhotoSaveBatchValueValidation.exact($0.record.registration.mediaUse.lease.registration.destination, row.destination)
            }
        })
        let failed = batch.targets[1], source = failed.target.source
        await photos.holdAdd()
        let retryID = MediaOperationID(rawValue: "retry-\u{00e9}")
        #expect(await coordinator.retry(source: source, previous: failed.target.operation, operation: retryID) == .accepted)
        #expect(await photoBatchEventually { await photos.commands.count == 4 })
        let during = try await mediaSnapshot(f.services.store)
        let media = try #require(during.temporaryMedia.first { $0.id == source.media })
        #expect(media.usages.count == 1 && media.usages[0].usage.purpose == .photoHandoff)
        let previousUse = try #require(failed.registration?.registration.intent.usage)
        #expect(media.usages[0].usage != previousUse)
        // Same durable acceptance is recovered without a new use or add.
        #expect(await coordinator.retry(source: source, previous: failed.target.operation, operation: retryID) == .accepted)
        guard case .rejected = await coordinator.retry(source: source, previous: .init(rawValue: "wrong-previous"), operation: retryID) else {
            Issue.record("Retry reused a different previous intent"); await photos.finishAdd(); return
        }
        guard case .rejected = await coordinator.retry(source: source, previous: failed.target.operation,
            operation: .init(rawValue: "retry-e\u{0301}")) else {
            Issue.record("Retry borrowed an operation through Unicode normalization"); await photos.finishAdd(); return
        }
        await photos.finishAdd(); await coordinator.waitForIdle()
        let final = try await mediaSnapshot(f.services.store)
        let retried = try #require(final.photoRegistrations.last)
        #expect(retried.registration.intent.retryOf == failed.target.operation)
        #expect(retried.registration.intent.usage != previousUse)
        #expect(final.temporaryMedia.first { $0.id == source.media }?.releasedUsages.count == 2)
        #expect(await photos.commands.count == 4)
        let forbidden = await coordinator.retry(source: batch.targets[2].target.source,
            previous: batch.targets[2].target.operation, operation: .init(rawValue: UUID().uuidString))
        guard case .rejected = forbidden else { Issue.record("An unknown addition was made retryable"); return }
        let reopened = try SQLiteRecordingStore(run: f.services.run, mode: .openExisting)
        #expect(try await mediaSnapshot(reopened).photoSaveBatches == final.photoSaveBatches)
        #expect(try await mediaSnapshot(reopened).photoRegistrations == final.photoRegistrations)
        let restored = f.coordinator(store: reopened)
        await restored.captureDidChange(); await restored.resume(request.operation); await restored.waitForIdle()
        #expect(await photos.commands.count == 4)
        #expect(try await mediaOriginalSnapshot(f.services.store).logicalOriginals.allSatisfy { $0.mediaReaders.isEmpty })
        try f.assertSourcesUnchanged()
        for rendition in f.renditions where rendition.localReference != nil {
            let digest = try await f.services.originals.digest(for: try #require(rendition.localReference))
            #expect(digest.sha256 == rendition.original.content.digest && digest.byteCount == rendition.original.content.byteCount)
        }
    }

    @Test func explicitBatchLookupReachesOnlyLiveKnownNonStartedIntentRecoveryWithoutSDK() async throws {
        let f = try await ProductPhotoSaveBatchFixture.make()
        let fault = PhotoBatchIntentFaultStore(base: f.services.store)
        let factory = ProductRenditionFactory(services: f.services, scopes: .init(leases: .init(store: f.services.store)), photoStore: fault)
        let execution = ProductPhotoSaveBatch(services: f.services, factory: factory, capture: f.capture)
        let coordinator = f.coordinator(execution: execution), request = try await f.request()
        #expect(await coordinator.submit(request) == .accepted)
        await coordinator.waitForIdle()
        let uncertain = try await mediaSnapshot(f.services.store)
        #expect(uncertain.photoRegistrations.count == 1 && uncertain.photoRegistrations[0].outcome == nil)
        #expect(uncertain.temporaryMedia[0].usages.count == 1)
        #expect(await f.photos.commands.isEmpty)
        let restartedFactory = f.renditions[0].factory()
        let restartedExecution = ProductPhotoSaveBatch(services: f.services, factory: restartedFactory, capture: f.capture)
        await restartedExecution.reconcileKnownNonStarted(uncertain.photoSaveBatches[0].targets[0].target)
        #expect(try await mediaSnapshot(f.services.store) == uncertain)
        #expect(await restartedFactory.openedOwners == 0)
        await fault.reveal()
        await coordinator.resume(request.operation); await coordinator.waitForIdle()
        let recovered = try await mediaSnapshot(f.services.store)
        #expect(recovered.photoRegistrations[0].usageTerminal?.terminal.termination == .notStarted)
        #expect(recovered.photoRegistrations[0].terminalUsageRelease != nil)
        #expect(recovered.photoRegistrations[0].outcome == nil && recovered.temporaryMedia[0].usages.isEmpty)
        #expect(!recovered.temporaryMedia[0].reclaimed)
        #expect(await f.photos.statusCalls.isEmpty)
        #expect(await f.photos.commands.isEmpty)
        await restartedExecution.reconcileKnownNonStarted(recovered.photoSaveBatches[0].targets[0].target)
        #expect(try await mediaSnapshot(f.services.store) == recovered)
        #expect(await restartedFactory.openedOwners == 0)
        try f.assertSourcesUnchanged()
    }

    @Test func sharedPlaybackAndPhotoUsesRemainIndependentUntilBothRealOwnersTerminate() async throws {
        let f = try await ProductPhotoSaveBatchFixture.make()
        await f.photos.holdAdd()
        let playback = try await f.factory.prepare(f.renditions[0].target)
        let coordinator = f.coordinator(), request = try await f.request()
        #expect(await coordinator.submit(request) == .accepted)
        #expect(await photoBatchEventually { await f.photos.commands.count == 1 })
        let during = try await mediaSnapshot(f.services.store)
        #expect(during.temporaryMedia[0].usages.count == 2)
        #expect(during.temporaryMedia[0].usages.contains { $0.usage.purpose == .playback })
        #expect(during.temporaryMedia[0].usages.contains { $0.usage.purpose == .photoHandoff })
        #expect(await f.factory.openedOwners == 1)
        #expect(await f.factory.release(playback))
        #expect(try await mediaSnapshot(f.services.store).temporaryMedia[0].usages.count == 1)
        #expect(FileManager.default.fileExists(atPath: f.renditions[0].mediaURL.path))
        await f.photos.finishAdd(); await coordinator.waitForIdle()
        #expect(try await mediaSnapshot(f.services.store).temporaryMedia[0].reclaimed)
        #expect(!FileManager.default.fileExists(atPath: f.renditions[0].mediaURL.path))
        #expect(try await mediaOriginalSnapshot(f.services.store).logicalOriginals[0].mediaReaders.isEmpty)
        try f.assertSourcesUnchanged()
    }

    @Test func preparedCapabilityJoinsOnePerformTaskAndRejectsNormalizedChildAliasWithoutReleasingSDKUse() async throws {
        let f = try await ProductPhotoSaveBatchFixture.make()
        let source = try await f.execution.source(for: f.renditions[0].target)
        let target = try PhotoSaveBatchTarget(source: source, operation: .init(rawValue: "child-\u{00e9}"))
        let batch = try PhotoSaveBatch(operation: .init(rawValue: UUID().uuidString), storeIdentity: source.storeIdentity, targets: [target])
        _ = try await photoBatchCommit(f.services.store, identity: source.storeIdentity, command: batch.operation, change: .accept(batch))
        let capability = try await f.execution.prepare(target)
        _ = try await photoBatchCommit(f.services.store, identity: source.storeIdentity, command: target.operation,
            change: .beginChild(batch: batch.operation, target: target))
        let state = try await mediaSnapshot(f.services.store)
        guard case .starting(let child) = state.photoSaveBatches[0].targets[0].status else { throw BackendContractError.notCommitted }
        await f.photos.holdAdd()
        let first = Task { await capability.perform(child) }
        #expect(await photoBatchEventually { await f.photos.commands.count == 1 })
        #expect(!(await capability.releaseIfNotStarted()))
        let aliasID = MediaOperationID(rawValue: "child-e\u{0301}")
        let aliasTarget = try PhotoSaveBatchTarget(source: source, operation: aliasID)
        let alias = CommittedPhotoSaveBatchChild(batch: child.batch, target: aliasTarget, command: aliasID,
            commit: .init(key: .photoBatch(aliasID, child.batch), previousRevision: child.commit.previousRevision,
                committedRevision: child.commit.committedRevision), expectedStoreIdentity: child.expectedStoreIdentity)
        #expect(await capability.perform(alias) == .failed(.rejected))
        let joined = Task { await capability.perform(child) }
        #expect(try await mediaSnapshot(f.services.store).temporaryMedia[0].usages.count == 1)
        await f.photos.finishAdd()
        let original = await first.value, repeated = await joined.value
        #expect(original == repeated)
        #expect(await f.photos.commands.count == 1)
        #expect(!(await capability.releaseIfNotStarted()))
        #expect(try await mediaSnapshot(f.services.store).temporaryMedia[0].usages.isEmpty)
    }

    @Test func actualAVOwnerAndHandoffReleaseJoinThroughBusyInspectionEvenWhenCallerIsCancelled() async throws {
        let f = try await ProductRenditionFixture.make(duration: 30)
        let barrier = PhotoRenditionReleaseBarrierStore(base: f.services.store)
        let leases = RenditionReadLeases(store: barrier)
        let scope = try await RenditionMediaScope.open(original: f.original, leases: leases)
        let temporary = try await ManagedTemporaryMedia.open(root: f.root, leases: leases, scope: scope, createIfMissing: false)
        let player = try await AVRenditionPlayback.open(leases: leases, temporary: temporary, scope: scope) { _ in
            throw BackendContractError.unavailable
        }
        let factory = f.factory()
        let selected = try await factory.selection(f.target)
        guard case .succeeded(let usage) = await temporary.acquireUsage(f.media, purpose: .playback,
            usageID: .init(rawValue: UUID().uuidString)) else { throw BackendContractError.ineligibleOriginal }
        let receipt = try await temporary.stateFor(f.media).receipt(for: usage)
        let source = ProductRenditionSource(selection: selected, owner: .init(scope: scope, temporary: temporary, player: player), receipt: receipt)
        let session = PlaybackSessionID(rawValue: UUID().uuidString)
        defer { Task { await barrier.release(); await player.end(session) } }
        guard case .succeeded(let token) = await player.play(.init(source: .local(receipt, selected.distribution),
            session: session, invalidationGeneration: selected.generation)) else { throw BackendContractError.notCommitted }
        #expect(await photoBatchEventually { player.decodedFrames > 0 })
        #expect(token.distribution == f.distribution && player.decodedFrames > 0 && player.audioTracks == 1)

        // The tag applies only to this inspection, not AVPlayer's concurrently
        // monitored current-state loads. inspect inserts the real busy gate
        // before any tagged load reaches this same-writer barrier.
        let inspection = Task {
            await PhotoRenditionReleaseProbe.$holdTemporaryLoad.withValue(true) { await temporary.inspect(f.media) }
        }
        #expect(await photoBatchEventually { await barrier.entered })
        let first = Task { await factory.release(source) }
        #expect(await photoBatchEventually { await factory.releaseContentions > 0 })
        first.cancel()
        let joined = Task { await factory.release(source) }
        let held = try await mediaSnapshot(f.services.store)
        #expect(held.temporaryMedia[0].usages.count == 2 && !held.temporaryMedia[0].reclaimed)
        #expect(held.temporaryMedia[0].usages.contains { $0.usage == usage })
        await barrier.release()
        guard case .succeeded = await inspection.value else { throw BackendContractError.unknownResult }
        #expect(await first.value)
        #expect(await joined.value)
        let released = try await mediaSnapshot(f.services.store)
        #expect(released.temporaryMedia[0].usages.count == 1)
        #expect(!released.temporaryMedia[0].usages.contains { $0.usage == usage })
        #expect(released.temporaryMedia[0].releasedUsages.filter { $0.usage == usage }.count == 1)
        #expect(FileManager.default.fileExists(atPath: f.mediaURL.path))
        #expect(player.player != nil && player.startedMonitors == 1)

        await player.end(session)
        let stopped = try await mediaSnapshot(f.services.store)
        #expect(player.phase == .stopped && player.sdkDetached && player.player == nil)
        #expect(player.startedMonitors == player.completedMonitors)
        #expect(stopped.temporaryMedia[0].usages.isEmpty && stopped.temporaryMedia[0].reclaimed)
        #expect(stopped.photoRegistrations.isEmpty && stopped.confirmations.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: f.mediaURL.path))
        #expect(try await mediaOriginalSnapshot(f.services.store).logicalOriginals[0].mediaReaders.isEmpty)
        #expect(try Data(contentsOf: f.sourceURL) == f.bytes)
        let disk = try await temporary.usageSnapshot(f.media)
        #expect(disk.uses == 0 && disk.openHandles == 0)
        #expect(await factory.release(source))
    }

    /// This opt-in test adds one synthetic movie on one dedicated simulator.
    /// Its injected acceptance path is not evidence of native Wi-Fi suitability,
    /// ordinary transfer/Rec.709 production, or full-device Photos acceptance.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_S31_NATIVE_PHOTO_BATCH"] == "1"))
    func dedicatedNativePhotoKitOneAdditionThroughProductBatch() async throws {
        let environment = ProcessInfo.processInfo.environment
        let dedicated = UUID(uuidString: "E436C891-9574-42CE-9F29-6C6C1759438B")!
        try #require(environment["FR_S31_PHOTO_SIMULATOR_ID"].flatMap(UUID.init(uuidString:)) == dedicated)
        try #require(environment["SIMULATOR_UDID"].flatMap(UUID.init(uuidString:)) == dedicated)
        let nonce = try #require(environment["FR_S31_PHOTO_NONCE"].flatMap(UUID.init(uuidString:)))
        try #require(nonce == UUID(uuidString: "4de832b4-34b0-4a7a-a94a-1d6eb54f4868"))
        let completion = PhotoBatchNativeCompletion()
        let photos = NativePhotoLibrary(observeCompletion: { value in completion.value.withLock { $0 = value } })
        try #require(await photos.authorizationStatus(for: .addOnly) == .authorized)
        let nativePath = NativePhotoStartNetwork()
        let pathDeadline = ContinuousClock.now.advanced(by: .seconds(2))
        while nativePath.currentCondition() == .unknown, ContinuousClock.now < pathDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        print("S31 native default-route observation: \(nativePath.currentCondition()). Photos probe acceptance uses injected fixture Wi-Fi; no strict transport permit.")
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("FrameRelay-native-photo-batch-" + nonce.uuidString)
        try #require(!FileManager.default.fileExists(atPath: parent.path))
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        let library = ProductLibraryFactory(supportDirectory: parent, photoLibrary: photos), services = try await library.open()
        let f = try await ProductRenditionFixture.seed(services: services, libraryFactory: library,
            capture: "native-photos-" + nonce.uuidString, local: false, duration: 3)
        let factory = f.factory(), capture = CaptureMediaAdmission(), network = PhotoBatchNetwork(.wiFi)
        let coordinator = PhotoSaveBatchCoordinator(store: services.store,
            execution: ProductPhotoSaveBatch(services: services, factory: factory, capture: capture), network: network, capture: capture)
        let request = PhotoSaveBatchRequest(operation: .init(rawValue: UUID().uuidString), targets: [f.target],
            displayedRevision: try await mediaSnapshot(services.store).revision)
        #expect(await coordinator.submit(request) == .accepted)
        await coordinator.waitForIdle()
        let snapshot = try await mediaSnapshot(services.store), record = try #require(snapshot.photoRegistrations.first)
        #expect(completion.value.withLock { $0?.succeeded } == true)
        guard case .succeeded(let identifier)? = record.outcome else { Issue.record("Native PhotoKit did not report success"); return }
        #expect(identifier != nil && snapshot.photoRegistrations.count == 1 && snapshot.photoSaveBatches.count == 1)
        #expect(record.usageTerminal?.terminal.termination == .sdkCompleted && record.terminalUsageRelease != nil)
        #expect(snapshot.temporaryMedia[0].reclaimed && snapshot.temporaryMedia[0].usages.isEmpty)
        #expect(try await mediaOriginalSnapshot(services.store).logicalOriginals[0].mediaReaders.isEmpty)
        #expect(try Data(contentsOf: f.sourceURL) == f.bytes)
        #expect(!FileManager.default.fileExists(atPath: f.mediaURL.path))
        let before = snapshot.revision
        #expect(await coordinator.submit(request) == .accepted)
        await coordinator.waitForIdle()
        #expect(try await mediaSnapshot(services.store).revision == before)
        let reopened = try SQLiteRecordingStore(run: services.run, mode: .openExisting)
        #expect(try await mediaSnapshot(reopened).photoRegistrations == snapshot.photoRegistrations)
        // Keep source, SQLite journal and the added Photos asset for inspection.
    }
}

nonisolated private final class PhotoBatchNativeCompletion: @unchecked Sendable {
    let value = Mutex<NativePhotoLibraryCompletionDiagnostic?>(nil)
}

nonisolated private enum PhotoRenditionReleaseProbe {
    @TaskLocal static var holdTemporaryLoad = false
}

private actor PhotoRenditionReleaseBarrierStore: MediaOperationStorePort, OriginalStorePort {
    let base: SQLiteRecordingStore
    private(set) var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    init(base: SQLiteRecordingStore) { self.base = base }
    func load() async -> BackendStoreLoadResult {
        if PhotoRenditionReleaseProbe.holdTemporaryLoad, !entered {
            entered = true
            await withCheckedContinuation { continuation = $0 }
        }
        return await base.load()
    }
    func commit(_ mutation: BackendStoreMutation) async -> BackendCommitResult { await base.commit(mutation) }
    func lookupCommit(_ mutation: BackendStoreMutation) async -> BackendCommitResult { await base.lookupCommit(mutation) }
    func loadOriginalState() async -> BackendOutcome<OriginalStoreSnapshot> { await base.loadOriginalState() }
    func commitOriginal(_ mutation: OriginalStoreMutation) async -> OriginalStoreCommitResult { await base.commitOriginal(mutation) }
    func lookupOriginalCommit(_ mutation: OriginalStoreMutation) async -> BackendOutcome<OriginalStoreCommitReceipt> {
        await base.lookupOriginalCommit(mutation)
    }
    func release() { continuation?.resume(); continuation = nil }
}

private actor PhotoBatchIntentFaultStore: MediaOperationStorePort {
    let base: SQLiteRecordingStore
    private var hidden = true
    init(base: SQLiteRecordingStore) { self.base = base }
    func load() async -> BackendStoreLoadResult { await base.load() }
    func commit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        let result = await base.commit(mutation)
        if case .photo(_, .intent) = mutation.change { return .unknown }
        return result
    }
    func lookupCommit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        if case .photo(_, .intent) = mutation.change, hidden { return .unknown }
        return await base.lookupCommit(mutation)
    }
    func reveal() { hidden = false }
}
