import Foundation
import Testing
@testable import FrameRelay

@MainActor struct ProductHistoricalRemovalTests {
    @Test func unregisteredNeverStartedInventorySealAndNormalDiscardNeedNoSDKFactory() async throws {
        let library = ProductLibraryFactory(supportDirectory: try historicalRemovalParent())
        let services = try await library.open()
        let fixture = OriginalRemovalFixture(run: services.run, store: services.store, files: services.originals, access: services.access)
        let binding = try await fixture.original("no-registration-normal-discard", unknown: true)
        guard case .succeeded(let concrete) = await services.store.loadRemovalTransportInventory(binding.original) else {
            Issue.record("No-registration concrete writer inventory must be observable")
            throw BackendContractError.unavailable
        }
        let port: any OriginalStorePort = services.store
        guard case .succeeded(let erased) = await port.loadRemovalTransportInventory(binding.original) else { throw BackendContractError.unavailable }
        #expect(concrete == erased && concrete.storeIdentity == nil)
        let counters = BackgroundFactoryProbe()
        let background = ProductBackgroundMediaFactory(library: library,
            sessionFactory: { _ in await counters.sdkCreated(); throw BackendContractError.unavailable },
            sourceFactory: { _ in await counters.sourceCreated(); throw BackendContractError.unavailable })
        let batch = try fixture.discardBatch(binding, name: "observe-only-before-normal-risk")
        let before = try await mediaOriginalSnapshot(services.store)
        guard case .committed = await services.store.commitOriginal(.init(operation: batch.operation, expectedRevision: before.revision,
            change: .removalBatch(batch))) else { throw BackendContractError.notCommitted }
        let seal = OriginalRemovalAdmissionSeal(batch: batch.operation, target: batch.targets[0], nonce: UUID().uuidString)
        guard case .succeeded(let observed) = await background.sealForRemoval(seal) else {
            Issue.record("The no-registration factory must seal its exact unstarted inventory")
            throw BackendContractError.readersActive
        }
        #expect(observed.inventory == concrete && observed.stops.isEmpty)
        #expect(await counters.counts() == [0, 0])
        _ = try await mediaOriginalCommit(services.store, .removalNotExecuted(batch: batch.operation, target: batch.targets[0], reason: .unavailable))
        let ready = try await mediaOriginalSnapshot(services.store)
        let state = try #require(ready.logicalOriginals.first)
        let epoch = try #require(ready.reconciliationEpoch)
        #expect(await background.releaseAfterRemoval(.init(seal: seal, epoch: epoch,
            access: state.accessGeneration, invalidation: state.invalidationGeneration, resolution: nil)))
        let composition = historicalRemovalComposition(library, background: background)
        await composition.open()
        let model = try #require(composition.library)
        #expect(model.availability(.discard, captures: [binding.original.capture]) == .available)
        let review = try #require(model.prepareRemovalReview(.discard, captures: [binding.original.capture]))
        await model.submit(review)
        #expect(model.submission?.phase == .awaitingRecordedResult)
        #expect(model.submission?.request.discardRiskAcknowledged == true)
        #expect(model.item(binding.original.capture)?.isDiscardHistory == true)
        #expect(model.item(binding.original.capture)?.operationResults.contains(where: { $0.id == review.id && $0.outcome == .succeeded }) == true)
        #expect(await services.originals.observeFile(binding.reference) == .absent)
        #expect(try await mediaSnapshot(services.store).storeIdentity == nil)
        #expect(await counters.counts() == [0, 0])
    }

    @Test func normalCompositionRequiresExplicitRiskAndProjectsHistoricalDiscardAfterReopen() async throws {
        let parent = try historicalRemovalParent()
        let library = ProductLibraryFactory(supportDirectory: parent)
        let services = try await library.open()
        let originals = OriginalRemovalFixture(run: services.run, store: services.store, files: services.originals, access: services.access)
        let setup = try await BackgroundCoordinatorFixture.make(originals)
        let binding = try #require(try await mediaOriginalSnapshot(services.store).originals.first?.binding)
        let keep = try await originals.original("historical-keep")
        let sdk = BackgroundSessionProbe(identity: setup.plan.session)
        let source = try ManagedUploadSource(run: services.run, originals: services.access)
        let background = ProductBackgroundMediaFactory(library: library, admission: BackgroundPermitProbe(),
            sessionFactory: { _ in sdk }, sourceFactory: { _ in source })
        guard case .started(let task) = await background.startUpload(setup.plan), let sdkBinding = task.binding else { throw BackendContractError.notCommitted }
        await sdk.complete(sdkBinding, outcome: .cancelled, finishEvents: true)
        try await backgroundEventually { (try? await mediaSnapshot(services.store).requests.first?.transport) == .stopped }
        let before = try await mediaSnapshot(services.store)
        let mac = parent.appendingPathComponent("Mac-sentinel.mov")
        let photos = parent.appendingPathComponent("Photos-sentinel.mov")
        let sentinel = Data("external-copy-must-remain".utf8)
        try sentinel.write(to: mac, options: .withoutOverwriting)
        try sentinel.write(to: photos, options: .withoutOverwriting)
        let composition = historicalRemovalComposition(library, background: background)
        await composition.open()
        let model = try #require(composition.library)
        #expect(model.availability(.discard, captures: [binding.original.capture]) == .available)
        #expect(model.availability(.cleanup, captures: [binding.original.capture]).reason != nil)
        let review = try #require(model.prepareRemovalReview(.discard, captures: [binding.original.capture]))
        #expect(review.targets.count == 1 && review.targets.first?.original == binding.original)
        #expect(await services.originals.observeFile(binding.reference) == .present(byteCount: binding.original.content.byteCount))
        #expect(try await mediaOriginalSnapshot(services.store).removalBatches.isEmpty)
        model.select(keep.original.capture, selected: true)
        await model.submit(review)
        #expect(model.submission?.request.discardRiskAcknowledged == true)
        #expect(model.submission?.request.targets.map(\.capture) == [binding.original.capture])
        #expect(model.submission?.phase == .awaitingRecordedResult)
        #expect(model.item(binding.original.capture)?.isDiscardHistory == true)
        #expect(model.item(binding.original.capture)?.operationResults.first?.id == review.id)
        #expect(model.item(binding.original.capture)?.operationResults.first?.outcome == .succeeded)
        #expect(await services.originals.observeFile(binding.reference) == .absent)
        #expect(await services.originals.observeFile(keep.reference) == .present(byteCount: keep.original.content.byteCount))
        #expect(try Data(contentsOf: mac) == sentinel && Data(contentsOf: photos) == sentinel)
        let after = try await mediaSnapshot(services.store)
        #expect(after.requests == before.requests && after.verifications == before.verifications)
        #expect(after.confirmations == before.confirmations && after.photoRegistrations == before.photoRegistrations)
        let reopened = try await ProductLibraryFactory(supportDirectory: parent).open()
        guard case .loaded(let snapshot) = await reopened.reader.loadLibrary() else { throw BackendContractError.unavailable }
        #expect(snapshot.history.map(\.id) == [binding.original.capture])
        #expect(snapshot.history.first?.operationResults.first?.id == review.id)
        #expect(snapshot.history.first?.recording.result == binding.saveRecord)
        #expect((await source.resources()).openHandles == 0)
        await sdk.finishStream(); _ = try await source.closeOwner()
    }

    @Test func activeUnknownNeverStopsAutomaticallyAndOnlyFreshExactReleaseReopensAdmission() async throws {
        let library = ProductLibraryFactory(supportDirectory: try historicalRemovalParent())
        let services = try await library.open()
        let originals = OriginalRemovalFixture(run: services.run, store: services.store, files: services.originals, access: services.access)
        let setup = try await BackgroundCoordinatorFixture.make(originals)
        let binding = try #require(try await mediaOriginalSnapshot(services.store).originals.first?.binding)
        let sdk = BackgroundSessionProbe(identity: setup.plan.session)
        let source = try ManagedUploadSource(run: services.run, originals: services.access)
        let background = ProductBackgroundMediaFactory(library: library, admission: BackgroundPermitProbe(),
            sessionFactory: { _ in sdk }, sourceFactory: { _ in source })
        guard case .started(let task) = await background.startUpload(setup.plan), let sdkBinding = task.binding else { throw BackendContractError.notCommitted }
        let composition = historicalRemovalComposition(library, background: background)
        await composition.open()
        let model = try #require(composition.library)
        #expect(model.prepareRemovalReview(.discard, captures: [binding.original.capture]) == nil)
        let batch = try originals.discardBatch(binding)
        let before = try await mediaOriginalSnapshot(services.store)
        guard case .committed = await services.store.commitOriginal(.init(operation: batch.operation, expectedRevision: before.revision,
            change: .removalBatch(batch))) else { throw BackendContractError.notCommitted }
        let seal = OriginalRemovalAdmissionSeal(batch: batch.operation, target: batch.targets[0], nonce: UUID().uuidString)
        #expect(await background.sealForRemoval(seal) == .unknown)
        #expect(await background.startUpload(setup.plan) == .refused(.removalBoundaryActive))
        #expect((await sdk.counts())[2] == 0)
        #expect((await source.resources()).openHandles == 1)
        #expect(try await mediaOriginalSnapshot(services.store).originals.first?.readers.count == 1)
        await sdk.complete(sdkBinding, outcome: .cancelled, finishEvents: true)
        try await backgroundEventually { (try? await mediaSnapshot(services.store).requests.first?.transport) == .stopped }
        guard case .succeeded = await background.sealForRemoval(seal) else { throw BackendContractError.readersActive }
        _ = try await mediaOriginalCommit(services.store, .removalNotExecuted(batch: batch.operation, target: batch.targets[0], reason: .terminationUnconfirmed))
        let ready = try await mediaOriginalSnapshot(services.store)
        let state = try #require(ready.logicalOriginals.first)
        let epoch = try #require(ready.reconciliationEpoch)
        let stale = OriginalRemovalAdmissionRelease(seal: seal, epoch: epoch, access: state.accessGeneration,
            invalidation: state.invalidationGeneration, resolution: nil)
        let wrongSeal = OriginalRemovalAdmissionSeal(batch: seal.batch, target: seal.target, nonce: "wrong-nonce")
        #expect(!(await background.releaseAfterRemoval(.init(seal: wrongSeal, epoch: epoch, access: state.accessGeneration,
            invalidation: state.invalidationGeneration, resolution: nil))))
        guard case .succeeded(let lease) = await services.access.acquireRead(binding.original,
            operation: .init(rawValue: "independent-reader"), leaseID: .init(rawValue: "independent-reader")),
              case .succeeded = await services.access.releaseRead(lease) else { throw BackendContractError.readersActive }
        #expect(!(await background.releaseAfterRemoval(stale)))
        let fresh = try #require(try await mediaOriginalSnapshot(services.store).logicalOriginals.first)
        #expect(await background.releaseAfterRemoval(.init(seal: seal, epoch: epoch, access: fresh.accessGeneration,
            invalidation: fresh.invalidationGeneration, resolution: nil)))
        let counts = await sdk.counts()
        guard case .existing = await background.startUpload(setup.plan) else { throw BackendContractError.notCommitted }
        #expect(await sdk.counts() == counts)
        #expect(await services.originals.observeFile(binding.reference) == .present(byteCount: binding.original.content.byteCount))
        await sdk.finishStream(); _ = try await source.closeOwner()
    }

    @Test(arguments: ["terminal", "source", "lease", "stopped", "lookup"])
    func everyUnconfirmedTerminalBoundaryKeepsOriginalAndAdmissionClosed(point: String) async throws {
        try await withStorageRun { run in
            let originals = try OriginalRemovalFixture(run: run)
            let setup = try await BackgroundCoordinatorFixture.make(originals)
            let original = setup.plan.context.target.original
            let barrier = BackgroundCheckpoint()
            let store = BackgroundStoreProbe(base: originals.store, terminalBarrier: point == "terminal" ? barrier : nil,
                stoppedBarrier: point == "stopped" ? barrier : nil)
            let managed = try ManagedUploadSource(run: run, originals: originals.access)
            let source = BackgroundSourceProbe(base: managed, finishBarrier: point == "source" ? barrier : nil)
            let access = BackgroundAccessProbe(base: originals.access, releaseBarrier: point == "lease" ? barrier : nil)
            let sdk = BackgroundSessionProbe(identity: setup.plan.session)
            let coordinator = BackgroundMediaCoordinator(store: store, identity: setup.plan.context.storeIdentity,
                originals: access, removalStore: originals.store, admission: BackgroundPermitProbe(),
                sessionFactory: { _ in sdk }, sourceFactory: { source })
            guard case .started(let task) = await coordinator.startUpload(setup.plan), let binding = task.binding else { throw BackendContractError.notCommitted }
            if point == "lookup" { await store.hideTerminalLookup() }
            await sdk.complete(binding, outcome: .cancelled, finishEvents: true)
            if point == "lookup" { try await backgroundEventually { await store.hiddenLookupCount() > 0 } }
            else { try await barrier.waitForArrival() }
            let target = OriginalRemovalTarget(original: original, reference: try #require(try await mediaOriginalSnapshot(originals.store).originals.first?.binding.reference),
                operation: .init(rawValue: "never-started-discard-child"))
            let seal = OriginalRemovalAdmissionSeal(batch: .init(rawValue: "never-started-discard-batch"), target: target, nonce: UUID().uuidString)
            #expect(await coordinator.sealForRemoval(seal) == .unknown)
            #expect(await coordinator.startUpload(setup.plan) == .refused(.removalBoundaryActive))
            #expect((await sdk.counts())[2] == 0)
            #expect(await originals.files.observeFile(target.reference) == .present(byteCount: original.content.byteCount))
            if point == "lookup" { await store.allowTerminalLookup(); await coordinator.retryHeldEvents() }
            else { await barrier.release() }
            try await backgroundEventually { (try? await mediaSnapshot(originals.store).requests.first?.transport) == .stopped }
            guard case .succeeded(let fence) = await coordinator.sealForRemoval(seal) else { throw BackendContractError.readersActive }
            #expect(fence.stops.count == 1)
            #expect((await managed.resources()).openHandles == 0)
            #expect(try await mediaOriginalSnapshot(originals.store).originals.first?.readers.isEmpty == true)
            #expect(await originals.files.observeFile(target.reference) == .present(byteCount: original.content.byteCount))
            await sdk.finishStream(); _ = try await managed.closeOwner()
        }
    }

    @Test func reopenedUnknownSourceAndOldLeaseStayUnreleased() async throws {
        try await withStorageRun { run in
            let fixture = try await HistoricalRemovalFixture.make(run)
            let old = try await mediaOriginalSnapshot(fixture.originals.store)
            let reopened = try OriginalRemovalFixture.open(run, candidate: .sqlite)
            let access = ManagedOriginalAccess(store: reopened, originals: ManagedOriginalStore(run: run))
            let replacements = BackgroundFactoryProbe()
            let observer = BackgroundMediaCoordinator(store: reopened, identity: fixture.plan.context.storeIdentity,
                originals: access, removalStore: reopened, sessionFactory: { _ in
                    await replacements.sdkCreated(); throw BackendContractError.unavailable
                }, sourceFactory: { await replacements.sourceCreated(); throw BackendContractError.unavailable })
            let batch = try fixture.originals.discardBatch(fixture.binding)
            let seal = OriginalRemovalAdmissionSeal(batch: batch.operation, target: batch.targets[0], nonce: UUID().uuidString)
            #expect(await observer.sealForRemoval(seal) == .unknown)
            #expect(await replacements.counts() == [0, 0])
            #expect(try await mediaOriginalSnapshot(reopened).originals.first?.readers == old.originals.first?.readers)
            #expect((await fixture.managed.resources()).openHandles == 1)
            try await fixture.complete(); try await fixture.close()
        }
    }

    @Test(arguments: ["copy", "attach"])
    func unfinishedCopyAndAttachmentGapStayUnknownWithoutAutomaticStop(point: String) async throws {
        try await withStorageRun { run in
            let originals = try OriginalRemovalFixture(run: run)
            let setup = try await BackgroundCoordinatorFixture.make(originals)
            let barrier = BackgroundCheckpoint()
            let store = BackgroundStoreProbe(base: originals.store, attachBarrier: point == "attach" ? barrier : nil)
            let managed = try ManagedUploadSource(run: run, originals: originals.access)
            let source = HistoricalRemovalCopyDelay(base: managed, checkpoint: point == "copy" ? barrier : nil)
            let sdk = BackgroundSessionProbe(identity: setup.plan.session)
            let coordinator = BackgroundMediaCoordinator(store: store, identity: setup.plan.context.storeIdentity,
                originals: originals.access, removalStore: originals.store, admission: BackgroundPermitProbe(),
                sessionFactory: { _ in sdk }, sourceFactory: { source })
            let starting = Task { await coordinator.startUpload(setup.plan) }
            defer { Task { await barrier.release() } }
            try await barrier.waitForArrival()
            let binding = try #require(try await mediaOriginalSnapshot(originals.store).originals.first?.binding)
            let batch = try originals.discardBatch(binding)
            let seal = OriginalRemovalAdmissionSeal(batch: batch.operation, target: batch.targets[0], nonce: UUID().uuidString)
            #expect(await coordinator.sealForRemoval(seal) == .unknown)
            await barrier.release()
            #expect(await starting.value == .unknown)
            let calls = await sdk.counts()
            #expect(calls[1] == 0 && calls[2] == 0)
            #expect(await originals.files.observeFile(binding.reference) == .present(byteCount: binding.original.content.byteCount))
            if point == "attach" {
                let task = try #require(try await mediaSnapshot(originals.store).backgroundTasks.first?.binding)
                await sdk.complete(task, outcome: .cancelled, finishEvents: true)
                try await backgroundEventually { (try? await mediaSnapshot(originals.store).requests.first?.transport) == .stopped }
                _ = try await managed.closeOwner()
            } else {
                #expect(try await mediaSnapshot(originals.store).backgroundTasks.isEmpty)
                #expect((await managed.resources()).openHandles == 1)
                #expect(try await mediaOriginalSnapshot(originals.store).originals.first?.readers.count == 1)
                do { _ = try await managed.closeOwner(); Issue.record("An unknown unexposed copy must remain owned") }
                catch { #expect(error as? BackendContractError == .readersActive) }
            }
            await sdk.finishStream()
        }
    }

    @Test(arguments: ["unknown", "reused", "duplicate"])
    func unknownOrReusedSDKInventoryNeverAuthorizesRemoval(kind: String) async throws {
        try await withStorageRun { run in
            let fixture = try await HistoricalRemovalFixture.make(run)
            try await fixture.complete()
            let state = try #require(try await mediaSnapshot(fixture.originals.store).backgroundTasks.first)
            let binding = try #require(state.binding)
            let observation = BackgroundMediaTaskObservation(session: binding.session,
                taskIdentifier: kind == "unknown" ? Int.max : binding.taskIdentifier,
                taskDescription: kind == "duplicate" ? binding.taskDescription : UUID().uuidString,
                kind: .upload, state: .suspended, bytesSent: 0, bytesReceived: 0)
            await fixture.sdk.setObservations(kind == "duplicate" ? [observation, observation] : [observation])
            let batch = try fixture.originals.discardBatch(fixture.binding)
            let seal = OriginalRemovalAdmissionSeal(batch: batch.operation, target: batch.targets[0], nonce: UUID().uuidString)
            #expect(await fixture.coordinator.sealForRemoval(seal) == .unknown)
            #expect((await fixture.sdk.counts())[2] == 0)
            #expect(await fixture.originals.files.observeFile(fixture.binding.reference) == .present(byteCount: fixture.binding.original.content.byteCount))
            #expect(try await mediaOriginalSnapshot(fixture.originals.store).removalBatches.isEmpty)
            try await fixture.close()
        }
    }
}

private actor HistoricalRemovalCopyDelay: BackgroundMediaUploadSourcePort {
    let base: ManagedUploadSource
    let checkpoint: BackgroundCheckpoint?
    init(base: ManagedUploadSource, checkpoint: BackgroundCheckpoint?) { self.base = base; self.checkpoint = checkpoint }
    func create(from lease: OriginalReadLease, id: ManagedUploadSourceID) async throws -> ManagedUploadSourceIdentity {
        let identity = try await base.create(from: lease, id: id)
        await checkpoint?.checkpoint()
        return identity
    }
    func uploadFile(for identity: ManagedUploadSourceIdentity, lease: OriginalReadLease) async throws -> BackgroundMediaUploadFile {
        try await base.uploadFile(for: identity, lease: lease)
    }
    func retain(_ identity: ManagedUploadSourceIdentity, lease: OriginalReadLease, for binding: BackgroundMediaTaskBinding) async throws {
        try await base.retain(identity, lease: lease, for: binding)
    }
    func finish(_ identity: ManagedUploadSourceIdentity, lease: OriginalReadLease,
        terminal: BackgroundMediaSDKTerminal) async throws -> BackgroundMediaOwnerClosure {
        try await base.finish(identity, lease: lease, terminal: terminal)
    }
}

@MainActor private func historicalRemovalComposition(_ library: ProductLibraryFactory,
    background: ProductBackgroundMediaFactory) -> ProductComposition {
    .init(factory: library, backgroundFactory: background, registrationFactory: { store in
        RegistrationCoordinator(store: store, vault: HistoricalRemovalEmptyVault(), remote: RegistrationTestRemote())
    })
}

nonisolated private func historicalRemovalParent() throws -> URL {
    let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent("FrameRelay-historical-removal-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
    return parent
}

nonisolated private struct HistoricalRemovalEmptyVault: RegistrationVaultPort {
    func connection(storeIdentity: RegistrationStoreIdentity?) async throws -> RegistrationConnection? { nil }
    func saveConnection(_ connection: RegistrationConnection, bearer: String, storeIdentity: RegistrationStoreIdentity) async throws {
        throw RegistrationAccessError.credentialUnavailable
    }
    func prepareIntent(for destination: DestinationIdentity, storeIdentity: RegistrationStoreIdentity) async throws -> RegistrationIntent {
        throw RegistrationAccessError.credentialUnavailable
    }
    func requireCredential(for intent: RegistrationIntent, storeIdentity: RegistrationStoreIdentity) async throws {
        throw RegistrationAccessError.credentialUnavailable
    }
}
