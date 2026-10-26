import Foundation
import Testing
@testable import FrameRelay

@Suite(.serialized) struct BackgroundInvalidationTests {
    @Test func cancellationPollCannotAckEvenWhenTerminalOwnerCloseAndStoppedWinTheAwaitRace() async throws {
        try await withStorageRun { run in
            let f = try await BackgroundInvalidationFixture.make(run, immediateTerminal: true)
            _ = try await f.start(); try await f.reserve()
            #expect(await f.coordinator.stopForInvalidation(f.record, epoch: f.epoch) == .inProgress)
            let completedBeforeReturn = try await mediaSnapshot(f.originals.store)
            #expect(completedBeforeReturn.requests[0].transport == .stopped)
            #expect(completedBeforeReturn.backgroundTasks[0].ownerClosure?.handlesClosed == true)
            #expect(completedBeforeReturn.invalidations.isEmpty && completedBeforeReturn.outbox.isEmpty)
            #expect((await f.managed.resources()).openHandles == 0)
            guard case .succeeded = await f.coordinator.stopForInvalidation(f.record, epoch: f.epoch) else {
                throw BackendContractError.unknownResult
            }
            #expect((await f.sdk.counts()) == [1, 1, 1])
            await f.sdk.finishStream(); _ = try await f.managed.closeOwner()
        }
    }
    @Test func actualReservationStopsKnownUploadWithoutChangingPersonIntentAndOnlyLaterObservationSucceeds() async throws {
        try await withStorageRun { run in
            let f = try await BackgroundInvalidationFixture.make(run)
            let task = try await f.start()
            guard case .upload(_, let originalLease, _) = task.intent.source else {
                throw BackendContractError.wrongStage
            }
            let originalOwnerEpoch = originalLease.epoch
            // The real original owner and the writer's media inventory use
            // independent epochs. Neither can be substituted for the other.
            #expect(originalOwnerEpoch != f.epoch)
            #expect(await f.coordinator.stopForInvalidation(f.record, epoch: f.epoch) == .unknown)
            #expect((await f.sdk.counts())[2] == 0)
            try await f.reserve()
            #expect(await f.coordinator.stopForInvalidation(f.record, epoch: originalOwnerEpoch) == .unknown)
            #expect((await f.sdk.counts())[2] == 0)
            #expect(await f.coordinator.stopForInvalidation(f.record, epoch: f.epoch) == .inProgress)
            let pending = try await mediaSnapshot(f.originals.store)
            #expect(pending.invalidations.isEmpty && pending.outbox.isEmpty)
            #expect(pending.backgroundTasks[0].stopRequested && pending.backgroundTasks[0].terminal == nil)
            #expect(pending.requests[0].intent == .running && pending.requests[0].remote == .notExecuted)
            #expect((await f.managed.resources()).openHandles == 1)
            #expect(await f.coordinator.observeInvalidation(f.record, epoch: f.epoch) == .unknown)
            await f.sdk.complete(try #require(task.binding), outcome: .cancelled, finishEvents: true)
            try await f.waitForStopped()
            guard case .succeeded(let observed) = await f.coordinator.stopForInvalidation(f.record, epoch: f.epoch) else {
                throw BackendContractError.unknownResult
            }
            let final = try await mediaSnapshot(f.originals.store)
            #expect(observed.validates(record: f.record, epoch: f.epoch, backend: final))
            #expect(observed.stops.count == 1 && observed.inventory.tasks.count == 1)
            #expect((await f.sdk.counts()) == [1, 1, 1])
            #expect(final.requests[0].intent == .running && final.requests[0].transport == .stopped)
            #expect(final.invalidations.isEmpty && final.outbox.isEmpty) // This port creates no ACK.
            #expect(try await mediaOriginalSnapshot(f.originals.store).logicalOriginals[0].readers.isEmpty)
            #expect((await f.managed.resources()).openHandles == 0)
            try await f.assertOriginalUnchanged()
            await f.sdk.finishStream(); _ = try await f.managed.closeOwner()
        }
    }

    @Test func eachActualTerminalBoundaryWithholdsObservationUntilTheStoppedCommit() async throws {
        try await withStorageRun { run in
            let terminal = BackgroundCheckpoint(), finish = BackgroundCheckpoint()
            let lease = BackgroundCheckpoint(), stopped = BackgroundCheckpoint()
            let f = try await BackgroundInvalidationFixture.make(run, terminalBarrier: terminal,
                finishBarrier: finish, releaseBarrier: lease, stoppedBarrier: stopped)
            let state = try await f.start(); try await f.reserve()
            #expect(await f.coordinator.stopForInvalidation(f.record, epoch: f.epoch) == .inProgress)
            await f.sdk.complete(try #require(state.binding), outcome: .cancelled, finishEvents: true)
            try await terminal.waitForArrival()
            #expect(await f.coordinator.observeInvalidation(f.record, epoch: f.epoch) == .unknown)
            #expect((await f.managed.resources()).openHandles == 1)
            await terminal.release(); try await finish.waitForArrival()
            #expect(try await mediaSnapshot(f.originals.store).backgroundTasks[0].terminal != nil)
            #expect(try await mediaSnapshot(f.originals.store).backgroundTasks[0].ownerClosure == nil)
            #expect(await f.coordinator.observeInvalidation(f.record, epoch: f.epoch) == .unknown)
            await finish.release(); try await lease.waitForArrival()
            #expect((await f.managed.resources()).openHandles == 0)
            #expect(!(try await mediaOriginalSnapshot(f.originals.store).logicalOriginals[0].readers.isEmpty))
            #expect(await f.coordinator.observeInvalidation(f.record, epoch: f.epoch) == .unknown)
            await lease.release(); try await stopped.waitForArrival()
            #expect(try await mediaOriginalSnapshot(f.originals.store).logicalOriginals[0].readers.isEmpty)
            #expect(try await mediaSnapshot(f.originals.store).requests[0].transport != .stopped)
            #expect(await f.coordinator.observeInvalidation(f.record, epoch: f.epoch) == .unknown)
            await stopped.release(); try await f.waitForStopped()
            guard case .succeeded = await f.coordinator.observeInvalidation(f.record, epoch: f.epoch) else { throw BackendContractError.unknownResult }
            #expect(try await mediaSnapshot(f.originals.store).invalidations.isEmpty)
            try await f.assertOriginalUnchanged()
            await f.sdk.finishStream(); _ = try await f.managed.closeOwner()
        }
    }

    @Test(arguments: ["epoch", "id-alias", "registration", "generation", "original", "store-uuid", "attempt"])
    func wrongReservationIdentityCannotCancelTheKnownSDKOwner(mode: String) async throws {
        try await withStorageRun { run in
            let f = try await BackgroundInvalidationFixture.make(run), task = try await f.start()
            try await f.reserve()
            var record = f.record, epoch = f.epoch
            switch mode {
            case "store-uuid": await f.audit.setFault(.storeUUID)
            case "attempt": await f.audit.setFault(.attempt)
            case "epoch": epoch = .init(rawValue: UUID().uuidString)
            case "id-alias": record = .init(id: .init(rawValue: "invalidation-e\u{0301}"), rendition: record.rendition,
                registration: record.registration, generation: record.generation)
            case "registration": record = .init(id: record.id, rendition: record.rendition,
                registration: .init(destination: record.registration.destination, id: .init(rawValue: "other-registration"),
                    generation: record.registration.generation), generation: record.generation)
            case "generation": record = .init(id: record.id, rendition: record.rendition,
                registration: record.registration, generation: .init(rawValue: record.generation.rawValue + 1))
            default: record = .init(id: record.id, rendition: statusRendition(try publicationOriginal("another-original")),
                registration: record.registration, generation: record.generation)
            }
            let before = try await mediaSnapshot(f.originals.store)
            #expect(await f.coordinator.stopForInvalidation(record, epoch: epoch) == .unknown)
            #expect(await f.coordinator.observeInvalidation(record, epoch: epoch) == .unknown)
            #expect(try await mediaSnapshot(f.originals.store) == before)
            #expect((await f.sdk.counts())[2] == 0)
            await f.audit.setFault(nil)
            await f.sdk.complete(try #require(task.binding), outcome: .cancelled, finishEvents: true)
            try await f.waitForStopped()
            await f.sdk.finishStream(); _ = try await f.managed.closeOwner()
        }
    }

    @Test(arguments: ["unknown", "reused", "wrong-kind", "duplicate", "missing"])
    func untrustedFreshSDKInventoryNeverAuthorizesCancellationOrAnAck(mode: String) async throws {
        try await withStorageRun { run in
            let f = try await BackgroundInvalidationFixture.make(run), task = try await f.start()
            let binding = try #require(task.binding)
            let expected = try #require(await f.sdk.observations().first)
            let other = BackgroundMediaTaskObservation(session: binding.session,
                taskIdentifier: mode == "unknown" ? binding.taskIdentifier + 100 : binding.taskIdentifier,
                taskDescription: "foreign-task", kind: .upload, state: .suspended, bytesSent: 0, bytesReceived: 0)
            switch mode {
            case "unknown": await f.sdk.setObservations([expected, other])
            case "reused": await f.sdk.setObservations([other])
            case "duplicate": await f.sdk.setObservations([expected, expected])
            case "missing": await f.sdk.setObservations([])
            default: await f.sdk.setObservations([.init(session: binding.session, taskIdentifier: binding.taskIdentifier,
                taskDescription: binding.taskDescription, kind: .download, state: .suspended, bytesSent: 0, bytesReceived: 0)])
            }
            try await f.reserve()
            #expect(await f.coordinator.stopForInvalidation(f.record, epoch: f.epoch) == .unknown)
            #expect((await f.sdk.counts())[2] == 0)
            #expect((await f.managed.resources()).openHandles == 1)
            #expect(try await mediaSnapshot(f.originals.store).invalidations.isEmpty)
            await f.sdk.setObservations([expected])
            guard case .succeeded = await f.coordinator.recover(f.plan.session) else { throw BackendContractError.unknownResult }
            await f.sdk.complete(binding, outcome: .cancelled, finishEvents: true)
            try await f.waitForStopped()
            await f.sdk.finishStream(); _ = try await f.managed.closeOwner()
        }
    }

    @Test func unknownStoppedCommitNeedsItsExactLookupAndDoesNotRepeatSourceFinish() async throws {
        try await withStorageRun { run in
            let f = try await BackgroundInvalidationFixture.make(run), task = try await f.start()
            try await f.reserve(); await f.fault.hideStoppedLookup()
            #expect(await f.coordinator.stopForInvalidation(f.record, epoch: f.epoch) == .inProgress)
            await f.sdk.complete(try #require(task.binding), outcome: .cancelled, finishEvents: true)
            try await backgroundEventually { await f.fault.hiddenStoppedCount() > 0 }
            #expect((await f.managed.resources()).openHandles == 0)
            #expect(await f.coordinator.observeInvalidation(f.record, epoch: f.epoch) == .unknown)
            #expect(try await mediaSnapshot(f.originals.store).invalidations.isEmpty)
            await f.fault.allowStoppedLookup()
            guard case .succeeded = await f.coordinator.stopForInvalidation(f.record, epoch: f.epoch) else { throw BackendContractError.unknownResult }
            #expect(await f.source.finishCount() == 1)
            #expect(await f.fault.stoppedCommitCount() == 1)
            #expect((await f.sdk.counts())[2] == 1)
            try await f.assertOriginalUnchanged()
            await f.sdk.finishStream(); _ = try await f.managed.closeOwner()
        }
    }

    @Test func reopenedOwnerRefusesLiveSourceButObservesFullyClosedHistoryWithoutAdoptingItsOldEpochLease() async throws {
        try await withStorageRun { run in
            let f = try await BackgroundInvalidationFixture.make(run), task = try await f.start()
            try await f.reserve()
            let sdk = BackgroundSessionProbe(identity: f.plan.session)
            await sdk.setObservations(await f.sdk.observations())
            let restored = BackgroundMediaCoordinator(store: f.originals.store, identity: f.plan.context.storeIdentity,
                originals: f.originals.access, removalStore: f.originals.store, sessionFactory: { _ in sdk },
                sourceFactory: { throw BackendContractError.unavailable })
            // A replacement coordinator still cannot borrow the original
            // process owner's live lease/source, even with the right store epoch.
            #expect(await restored.stopForInvalidation(f.record, epoch: f.epoch) == .unknown)
            #expect(await restored.observeInvalidation(f.record, epoch: f.epoch) == .unknown)
            #expect((await sdk.counts()) == [0, 0, 0])
            #expect((await f.managed.resources()).openHandles == 1)
            #expect(!(try await mediaOriginalSnapshot(f.originals.store).logicalOriginals[0].readers.isEmpty))
            await f.sdk.complete(try #require(task.binding), outcome: .cancelled, finishEvents: true)
            try await f.waitForStopped()
            await sdk.setObservations([])
            let reopened = try OriginalRemovalFixture.open(run, candidate: f.originals.candidate)
            let epoch = try #require(try await mediaOriginalSnapshot(reopened).reconciliationEpoch)
            let access = ManagedOriginalAccess(store: reopened, originals: f.originals.files)
            let closedHistory = BackgroundMediaCoordinator(store: reopened, identity: f.plan.context.storeIdentity,
                originals: access, removalStore: reopened, sessionFactory: { _ in sdk },
                sourceFactory: { throw BackendContractError.unavailable })
            let before = try await mediaSnapshot(reopened)
            guard case .succeeded(let observed) = await closedHistory.observeInvalidation(f.record, epoch: epoch) else {
                throw BackendContractError.unknownResult
            }
            #expect(observed.validates(record: f.record, epoch: epoch, backend: before))
            #expect(PublicationStoreBoundary.exact(observed.inventory.epoch, epoch))
            #expect(try await mediaSnapshot(reopened) == before) // Observation writes no release/intent/ACK.
            #expect((await sdk.counts()) == [0, 0, 0])
            await sdk.finishStream(); await f.sdk.finishStream(); _ = try await f.managed.closeOwner()
        }
    }

    @Test func anAttachedSDKTaskStillInsideTheStartGapStaysUnresolved() async throws {
        try await withStorageRun { run in
            let attached = BackgroundCheckpoint()
            let f = try await BackgroundInvalidationFixture.make(run, attachBarrier: attached)
            let starting = Task { await f.coordinator.startUpload(f.plan) }
            try await attached.waitForArrival(); try await f.reserve()
            #expect(await f.coordinator.stopForInvalidation(f.record, epoch: f.epoch) == .unknown)
            #expect((await f.sdk.counts()) == [1, 0, 0])
            #expect(try await mediaSnapshot(f.originals.store).backgroundTasks[0].binding == nil)
            await attached.release(); _ = await starting.value
            let state = try #require(try await mediaSnapshot(f.originals.store).backgroundTasks.first)
            await f.sdk.complete(try #require(state.binding), outcome: .cancelled, finishEvents: true)
            try await f.waitForStopped()
            await f.sdk.finishStream(); _ = try await f.managed.closeOwner()
        }
    }

    @Test func aCopyAlreadyInFlightCannotBecomeAStopProofOrAcquireANewSDKOwner() async throws {
        try await withStorageRun { run in
            let f = try await BackgroundInvalidationFixture.make(run), copying = BackgroundCheckpoint()
            let source = BackgroundInvalidationCopyGate(base: f.managed, gate: copying)
            let factories = BackgroundFactoryProbe()
            let coordinator = BackgroundMediaCoordinator(store: f.originals.store, identity: f.plan.context.storeIdentity,
                originals: f.originals.access, removalStore: f.originals.store, admission: BackgroundPermitProbe(),
                sessionFactory: { _ in await factories.sdkCreated(); return f.sdk }, sourceFactory: { source })
            let starting = Task { await coordinator.startUpload(f.plan) }
            try await copying.waitForArrival(); try await f.reserve()
            #expect(await coordinator.stopForInvalidation(f.record, epoch: f.epoch) == .unknown)
            #expect(await coordinator.observeInvalidation(f.record, epoch: f.epoch) == .unknown)
            #expect(await factories.counts() == [0, 0])
            #expect(try await mediaSnapshot(f.originals.store).backgroundTasks.isEmpty)
            #expect(!(try await mediaOriginalSnapshot(f.originals.store).logicalOriginals[0].readers.isEmpty))
            await copying.release(); #expect(await starting.value == .unknown)
            #expect(await factories.counts() == [0, 0])
            #expect(try await mediaSnapshot(f.originals.store).invalidations.isEmpty)
            try await f.assertOriginalUnchanged()
            await f.sdk.finishStream()
            // The interrupted copy's lease is intentionally not inferred closed.
        }
    }

    @MainActor @Test func preparedDownloadIsRejectedWithoutAdoptingItsOldMediaReader() async throws {
        try await withStorageRun { run in
            let f = try await StatusSynchronizationFixture.make(run: run)
            let rendition = f.renditions[0], registration = f.registration.server.registration
            let operation = MediaOperationID(rawValue: UUID().uuidString), attempt = TransferAttemptID(rawValue: UUID().uuidString)
            let before = try await mediaSnapshot(f.store)
            let request = MediaRequest(operation: operation, target: .rendition(rendition), purpose: .download,
                registration: registration, expectedStartRevision: before.revision)
            _ = try await mediaCommit(f.store, .request(command: operation, value: request))
            _ = try await mediaCommit(f.store, .requestTransition(command: .init(rawValue: UUID().uuidString),
                operation: operation, target: request.target, registration: registration,
                value: .reconciled(.init(context: .init(operation: operation, registration: registration, target: request.target, session: nil),
                    observation: .init(rawValue: 1), result: .notExecuted))))
            _ = try await mediaCommit(f.store, .requestTransition(command: .init(rawValue: UUID().uuidString),
                operation: operation, target: request.target, registration: registration, value: .beginAttempt(attempt)))
            let original = try await mediaOriginalSnapshot(f.store), epoch = try #require(original.reconciliationEpoch)
            let lease = MediaReadLease(id: .init(rawValue: UUID().uuidString), target: request.target, operation: operation,
                registration: registration, context: .transport(attempt), epoch: epoch, accessGeneration: .init(rawValue: 1))
            _ = try await mediaOriginalCommit(f.store, .acquireMedia(lease))
            let intent = BackgroundMediaTaskIntent(id: .init(rawValue: UUID().uuidString), context: .init(operation: operation, attempt: attempt,
                target: request.target, registration: registration, gateGeneration: 1, storeIdentity: f.identity),
                session: .init(identifier: .init(rawValue: UUID().uuidString), generation: .init(rawValue: UUID())),
                taskDescription: UUID().uuidString, requestFingerprint: .init(sha256: String(repeating: "a", count: 64)),
                source: .download(rendition: rendition, range: nil, lease: lease))
            let snapshot = try await mediaSnapshot(f.store)
            guard case .committed = await f.store.commit(.init(expectedRevision: snapshot.revision,
                change: .backgroundTask(command: .init(rawValue: UUID().uuidString), value: .prepared(intent)), expectedStoreIdentity: f.identity)) else { throw BackendContractError.notCommitted }
            let access = ManagedOriginalAccess(store: f.store, originals: ManagedOriginalStore(run: run))
            let record = statusInvalidation(rendition, registration: registration)
            guard case .succeeded = await access.reserveInvalidation(record) else { throw BackendContractError.notCommitted }
            let factories = BackgroundFactoryProbe()
            let coordinator = BackgroundMediaCoordinator(store: f.store, identity: f.identity, originals: access, removalStore: f.store,
                sessionFactory: { _ in await factories.sdkCreated(); throw BackendContractError.unavailable },
                sourceFactory: { await factories.sourceCreated(); throw BackendContractError.unavailable })
            #expect(await coordinator.stopForInvalidation(record, epoch: epoch) == .unknown)
            #expect(await coordinator.observeInvalidation(record, epoch: epoch) == .unknown)
            #expect(await factories.counts() == [0, 0])
            #expect(try await mediaOriginalSnapshot(f.store).logicalOriginals[0].mediaReaders == [lease])
            #expect(try await mediaSnapshot(f.store).invalidations.isEmpty)
        }
    }
}

/// New isolated files and real common-writer receipts. The session/permit/Mac
/// notExecuted observation are technical inputs, never native resume evidence.
nonisolated struct BackgroundInvalidationFixture {
    let originals: OriginalRemovalFixture
    let plan: BackgroundMediaUploadPlan
    let rendition: RenditionIdentity
    let record: InvalidationRecord
    let epoch: ReaderReconciliationEpoch
    let managed: ManagedUploadSource
    let source: BackgroundSourceProbe
    let sdk: BackgroundSessionProbe
    let fault: BackgroundStoreProbe
    let audit: BackgroundInvalidationIdentityStore
    let coordinator: BackgroundMediaCoordinator
    let reference: CaptureOriginalReference
    let bytes: Data

    static func make(_ run: ExplorationRunDirectory, terminalBarrier: BackgroundCheckpoint? = nil,
        finishBarrier: BackgroundCheckpoint? = nil, releaseBarrier: BackgroundCheckpoint? = nil,
        stoppedBarrier: BackgroundCheckpoint? = nil, attachBarrier: BackgroundCheckpoint? = nil,
        immediateTerminal: Bool = false) async throws -> Self {
        let f = try await BackgroundCoordinatorFixture.make(run)
        let original = f.plan.context.target.original
        let rendition = statusRendition(original)
        _ = try await mediaCommit(f.originals.store, .publication(mediaPublication(rendition, registration: f.plan.context.registration)))
        let binding = try #require(try await mediaOriginalSnapshot(f.originals.store).originals.first?.binding)
        let url = try await f.originals.files.existingURL(for: binding.reference)
        let bytes = try Data(contentsOf: url)
        let managed = try ManagedUploadSource(run: run, originals: f.originals.access)
        let source = BackgroundSourceProbe(base: managed, finishBarrier: finishBarrier)
        let sdk = BackgroundSessionProbe(identity: f.plan.session)
        let fault = BackgroundStoreProbe(base: f.originals.store, terminalBarrier: terminalBarrier,
            attachBarrier: attachBarrier, stoppedBarrier: stoppedBarrier)
        let access = BackgroundAccessProbe(base: f.originals.access, releaseBarrier: releaseBarrier)
        let audit = BackgroundInvalidationIdentityStore(base: fault)
        let session: any BackgroundMediaSessionPort
        if immediateTerminal { session = BackgroundInvalidationImmediateSession(base: sdk, store: f.originals.store) }
        else { session = sdk }
        let coordinator = BackgroundMediaCoordinator(store: audit, identity: f.plan.context.storeIdentity,
            originals: access, removalStore: f.originals.store, admission: BackgroundPermitProbe(),
            sessionFactory: { _ in session }, sourceFactory: { source })
        return .init(originals: f.originals, plan: f.plan, rendition: rendition,
            record: statusInvalidation(rendition, registration: f.plan.context.registration, id: "invalidation-\u{00e9}"),
            epoch: try #require(try await mediaOriginalSnapshot(f.originals.store).reconciliationEpoch),
            managed: managed, source: source, sdk: sdk, fault: fault, audit: audit, coordinator: coordinator,
            reference: binding.reference, bytes: bytes)
    }
    func start() async throws -> BackgroundMediaTaskState {
        guard case .started(let task) = await coordinator.startUpload(plan) else { throw BackendContractError.notCommitted }
        return task
    }
    func reserve() async throws {
        guard case .succeeded(let permit) = await originals.access.reserveInvalidation(record),
              PublicationStoreBoundary.exact(permit.record, record) else { throw BackendContractError.notCommitted }
    }
    func waitForStopped() async throws {
        try await backgroundEventually {
            guard let snapshot = try? await mediaSnapshot(originals.store) else { return false }
            return snapshot.requests.first(where: { $0.operation == plan.context.operation })?.transport == .stopped
                && snapshot.backgroundTasks.first(where: { $0.intent.id == plan.id })?.ownerClosure != nil
        }
    }
    func assertOriginalUnchanged() async throws {
        let url = try await originals.files.existingURL(for: reference)
        #expect(try Data(contentsOf: url) == bytes)
        let digest = try await originals.files.digest(for: reference)
        #expect(digest.sha256 == plan.context.target.original.content.digest && digest.byteCount == UInt64(bytes.count))
    }
}

/// Invalid observations only; no successful result or changed request is ever
/// written. The underlying source and single writer remain the real fixtures.
actor BackgroundInvalidationIdentityStore: MediaOperationStorePort {
    enum Fault: Sendable { case storeUUID, attempt }
    let base: any MediaOperationStorePort
    private var fault: Fault?
    init(base: any MediaOperationStorePort) { self.base = base }
    func setFault(_ fault: Fault?) { self.fault = fault }
    func load() async -> BackendStoreLoadResult {
        let value = await base.load()
        guard let fault, case .loaded(var snapshot) = value else { return value }
        switch fault {
        case .storeUUID: snapshot.storeIdentity = .init(rawValue: UUID())
        case .attempt:
            if let first = snapshot.requests.first, let encoded = try? JSONEncoder().encode(first),
               var object = (try? JSONSerialization.jsonObject(with: encoded)) as? [String: Any] {
                object["attempt"] = ["rawValue": "different-observed-attempt"]
                if let changed = try? JSONSerialization.data(withJSONObject: object),
                   let request = try? JSONDecoder().decode(MediaRequest.self, from: changed) {
                    var requests = snapshot.requests
                    requests[0] = request
                    snapshot = .init(revision: snapshot.revision, registrationIntents: snapshot.registrationIntents,
                        registrations: snapshot.registrations, batches: snapshot.batches, requests: requests,
                        verifications: snapshot.verifications, confirmations: snapshot.confirmations,
                        invalidations: snapshot.invalidations, outbox: snapshot.outbox, storeIdentity: snapshot.storeIdentity,
                        publications: snapshot.publications, confirmationStates: snapshot.confirmationStates,
                        deliveries: snapshot.deliveries, distributionObservations: snapshot.distributionObservations,
                        temporaryMedia: snapshot.temporaryMedia, photoRegistrations: snapshot.photoRegistrations,
                        photoSaveBatches: snapshot.photoSaveBatches, backgroundTasks: snapshot.backgroundTasks,
                        remoteInventory: snapshot.remoteInventory, publicationManifests: snapshot.publicationManifests)
                }
            }
        }
        return .loaded(snapshot)
    }
    func commit(_ mutation: BackendStoreMutation) async -> BackendCommitResult { await base.commit(mutation) }
    func lookupCommit(_ mutation: BackendStoreMutation) async -> BackendCommitResult { await base.lookupCommit(mutation) }
}

private actor BackgroundInvalidationCopyGate: BackgroundMediaUploadSourcePort {
    let base: ManagedUploadSource
    let gate: BackgroundCheckpoint
    init(base: ManagedUploadSource, gate: BackgroundCheckpoint) { self.base = base; self.gate = gate }
    func create(from lease: OriginalReadLease, id: ManagedUploadSourceID) async throws -> ManagedUploadSourceIdentity {
        await gate.checkpoint(); return try await base.create(from: lease, id: id)
    }
    func uploadFile(for identity: ManagedUploadSourceIdentity, lease: OriginalReadLease) async throws -> BackgroundMediaUploadFile { try await base.uploadFile(for: identity, lease: lease) }
    func retain(_ identity: ManagedUploadSourceIdentity, lease: OriginalReadLease, for binding: BackgroundMediaTaskBinding) async throws { try await base.retain(identity, lease: lease, for: binding) }
    func finish(_ identity: ManagedUploadSourceIdentity, lease: OriginalReadLease, terminal: BackgroundMediaSDKTerminal) async throws -> BackgroundMediaOwnerClosure {
        try await base.finish(identity, lease: lease, terminal: terminal)
    }
}

private actor BackgroundInvalidationImmediateSession: BackgroundMediaSessionPort {
    let base: BackgroundSessionProbe
    let store: any MediaOperationStorePort
    init(base: BackgroundSessionProbe, store: any MediaOperationStorePort) { self.base = base; self.store = store }
    func events() async throws -> AsyncStream<BackgroundMediaSDKEvent> { try await base.events() }
    func enumerate() async -> BackendOutcome<[BackgroundMediaTaskObservation]> { await base.enumerate() }
    func createSuspended(_ intent: BackgroundMediaTaskIntent, request: URLRequest, upload: BackgroundMediaUploadFile?) async -> BackendOutcome<BackgroundMediaTaskBinding> {
        await base.createSuspended(intent, request: request, upload: upload)
    }
    func resume(_ binding: BackgroundMediaTaskBinding, permit: BackgroundMediaStrictPermit,
                captureAuthorization: CaptureMediaResumeAuthorization) async -> BackendOutcome<BackgroundMediaTaskBinding> {
        await base.resume(binding, permit: permit, captureAuthorization: captureAuthorization)
    }
    func requestStop(_ binding: BackgroundMediaTaskBinding) async {
        await base.requestStop(binding)
        await base.complete(binding, outcome: .cancelled, finishEvents: true)
        // Deterministically finish the existing real source/lease consumer
        // before cancellation returns. This is an explicit fake SDK event,
        // independent of the separately flagged native callback probe.
        try? await backgroundEventually {
            guard case .loaded(let snapshot) = await self.store.load() else { return false }
            return snapshot.backgroundTasks.first(where: { $0.binding == binding })?.ownerClosure != nil
                && snapshot.requests.first?.transport == .stopped
        }
    }
    func observeTerminal(_ binding: BackgroundMediaTaskBinding) async -> BackendOutcome<BackgroundMediaSDKTerminal> { await base.observeTerminal(binding) }
    func invalidate() async { await base.invalidate() }
}
