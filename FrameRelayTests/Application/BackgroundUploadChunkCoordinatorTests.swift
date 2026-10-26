import Foundation
import Testing
@testable import FrameRelay

/// Actual disposable writers/raw sources plus explicitly injected policy and
/// SDK ports. A fake resume/completion is not native strict/media proof.
@Suite(.serialized) struct BackgroundUploadChunkCoordinatorTests {
    @Test func normalProductConstructionAndReopenNeverCreateAChunkOrAnSDKSession() async throws {
        let support = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("FrameRelay-chunk-product-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: false)
        let run = try ExplorationRunDirectory.createNew(at: support.appendingPathComponent("FrameRelayLibrary", isDirectory: true))
        let f = try await BackgroundUploadChunkStoreFixture.make(run)
        _ = try await f.createSession(); let selected = try await f.get(), plan = try chunkCoordinatorPlan(f, selected: selected)
        let before = try await mediaSnapshot(f.store), factories = BackgroundFactoryProbe(), requests = ChunkCoordinatorRequests()
        let photos = PhotoBatchLibrary(outcomes: [.unknown(localIdentifier: nil)])
        for _ in 0..<2 {
            let library = ProductLibraryFactory(supportDirectory: support, photoLibrary: photos)
            let product = ProductBackgroundMediaFactory(library: library,
                sessionFactory: { _ in await factories.sdkCreated(); throw BackendContractError.unavailable },
                sourceFactory: { _ in await factories.sourceCreated(); throw BackendContractError.unavailable })
            #expect(await product.prepare() == .prepared(knownSessions: 0))
            #expect(await product.startUploadChunk(plan, requests: requests) == .refused(.strictAdmissionUnavailable))
        }
        #expect(await factories.counts() == [0, 0])
        #expect(await requests.count == 0)
        #expect(await photos.commands.isEmpty)
        #expect(try await mediaSnapshot(f.store) == before)
        #expect(!FileManager.default.fileExists(atPath: run.url.appendingPathComponent("background-upload-sources").path))
    }

    @Test func defaultStrictRefusalPrecedesAttemptLeaseSourceRequestAndSDK() async throws {
        try await withStorageRun { run in
            let f = try await BackgroundUploadChunkStoreFixture.make(run)
            _ = try await f.createSession(); let selected = try await f.get(), plan = try chunkCoordinatorPlan(f, selected: selected)
            let factories = BackgroundFactoryProbe(), access = BackgroundAccessProbe(base: f.access), requests = ChunkCoordinatorRequests()
            let owner = BackgroundMediaCoordinator(store: f.store, identity: f.source.storeIdentity, originals: access, removalStore: f.store,
                sessionFactory: { _ in await factories.sdkCreated(); throw BackendContractError.unavailable },
                sourceFactory: { await factories.sourceCreated(); throw BackendContractError.unavailable })
            let before = try await mediaSnapshot(f.store)
            #expect(await owner.startUploadChunk(plan, requests: requests) == .refused(.strictAdmissionUnavailable))
            #expect(await owner.startUploadChunk(plan, requests: requests) == .refused(.strictAdmissionUnavailable))
            #expect(await factories.counts() == [0, 0])
            #expect(await access.counts() == [0, 0])
            #expect(await requests.count == 0)
            #expect(try await mediaSnapshot(f.store) == before)
            #expect(try await mediaOriginalSnapshot(f.store).logicalOriginals[0].readers.isEmpty)
        }
    }

    @Test(arguments: ["created", "finalizing", "indexed", "pending", "paused", "cancelled", "forged-selection"])
    func onlyTheLatestUnreceivedReceivingGetCanReachAnyResourceFactory(reason: String) async throws {
        try await withStorageRun { run in
            let f = try await BackgroundUploadChunkStoreFixture.make(run), created = try await f.createSession()
            let selected: StoredUploadMetadataObservation
            if reason == "created" { selected = created }
            else { selected = try await f.get(state: reason == "finalizing" ? .finalizing : .receiving, indexes: reason == "indexed" ? [0] : []) }
            if reason == "pending" { _ = try await f.begin(.lookup(f.metadataBinding.session)) }
            if reason == "paused" { _ = try await f.transition(.pause) }
            if reason == "cancelled" { _ = try await f.transition(.cancel) }
            var plan = try chunkCoordinatorPlan(f, selected: selected)
            if reason == "forged-selection" {
                var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(plan.metadata)) as? [String: Any])
                object["observationFingerprint"] = String(repeating: "c", count: 64)
                let metadata = try JSONDecoder().decode(UploadChunkMetadataSelection.self, from: JSONSerialization.data(withJSONObject: object))
                plan = .init(id: plan.id, context: plan.context, session: plan.session, taskDescription: plan.taskDescription,
                    sourceID: plan.sourceID, range: plan.range, metadata: metadata)
            }
            let factories = BackgroundFactoryProbe(), access = BackgroundAccessProbe(base: f.access), requests = ChunkCoordinatorRequests()
            let owner = BackgroundMediaCoordinator(store: f.store, identity: f.source.storeIdentity, originals: access, removalStore: f.store,
                admission: BackgroundPermitProbe(), sessionFactory: { _ in await factories.sdkCreated(); throw BackendContractError.unavailable },
                sourceFactory: { await factories.sourceCreated(); throw BackendContractError.unavailable })
            let before = try await mediaSnapshot(f.store)
            #expect(await owner.startUploadChunk(plan, requests: requests) == .refused(.requestNotReady))
            #expect(await factories.counts() == [0, 0])
            #expect(await access.counts() == [0, 0])
            #expect(await requests.count == 0)
            #expect(try await mediaSnapshot(f.store) == before)
        }
    }

    @Test func identicalInputJoinsOneCopyAndAnotherPlanCannotOverlapTheOperation() async throws {
        try await withStorageRun { run in
            let f = try await BackgroundUploadChunkStoreFixture.make(run)
            _ = try await f.createSession(); let selected = try await f.get(), plan = try chunkCoordinatorPlan(f, selected: selected)
            let gate = BackgroundCheckpoint(), managed = try ManagedUploadSource(run: run, originals: f.access)
            let source = ChunkCoordinatorSource(base: managed, copyGate: gate), requests = ChunkCoordinatorRequests(), sdk = BackgroundSessionProbe(identity: plan.session)
            let owner = chunkCoordinator(f, sdk: sdk, source: source)
            let first = Task { await owner.startUploadChunk(plan, requests: requests) }
            try await gate.waitForArrival()
            let joined = Task { await owner.startUploadChunk(plan, requests: requests) }
            let different = try chunkCoordinatorPlan(f, selected: selected, session: plan.session)
            #expect(await owner.startUploadChunk(different, requests: requests) == .refused(.requestNotReady))
            await gate.release()
            let result = await first.value
            #expect(await joined.value == result)
            guard case .started(let started) = result, let binding = started.binding else { throw BackendContractError.notCommitted }
            #expect(await source.counts() == [1, 0])
            #expect(await requests.count == 1)
            #expect(await sdk.counts() == [1, 1, 0])
            await sdk.complete(binding, outcome: .cancelled, finishEvents: true)
            try await chunkCoordinatorWaitForStop(f)
            let terminal = try await mediaSnapshot(f.store).backgroundTasks[0]
            let reopened = BackgroundMediaCoordinator(store: f.store, identity: f.source.storeIdentity, originals: f.access, removalStore: f.store,
                sessionFactory: { _ in throw BackendContractError.unavailable }, sourceFactory: { throw BackendContractError.unavailable })
            #expect(await reopened.startUploadChunk(plan, requests: requests) == .existing(terminal))
            #expect(await requests.count == 1)
            #expect(try Data(contentsOf: f.url) == f.bytes)
            await sdk.finishStream(); _ = try await managed.closeOwner()
        }
    }

    @Test func aLegacyWholeOnlySourceWitnessRefusesInsteadOfFallingBackToAFullCopy() async throws {
        try await withStorageRun { run in
            let f = try await BackgroundUploadChunkStoreFixture.make(run)
            _ = try await f.createSession(); let selected = try await f.get(), plan = try chunkCoordinatorPlan(f, selected: selected)
            let managed = try ManagedUploadSource(run: run, originals: f.access), legacy = BackgroundSourceProbe(base: managed)
            let requests = ChunkCoordinatorRequests(), factories = BackgroundFactoryProbe()
            let owner = BackgroundMediaCoordinator(store: f.store, identity: f.source.storeIdentity, originals: f.access, removalStore: f.store,
                admission: BackgroundPermitProbe(), sessionFactory: { _ in await factories.sdkCreated(); throw BackendContractError.unavailable }, sourceFactory: { legacy })
            #expect(await owner.startUploadChunk(plan, requests: requests) == .unknown)
            #expect(await legacy.copyCount() == 0)
            #expect(await requests.count == 0)
            #expect(await factories.counts() == [0, 0])
            #expect(await managed.resources().openHandles == 0)
            #expect(try await mediaSnapshot(f.store).backgroundTasks.isEmpty)
            #expect(try await mediaOriginalSnapshot(f.store).logicalOriginals[0].readers.count == 1)
            _ = try await managed.closeOwner() // Caller lease remains unresolved.
        }
    }

    @Test func completionDrainsActualSourceFDThenLeaseAndStoppedWithoutWholeSuccess() async throws {
        try await withStorageRun { run in
            let f = try await BackgroundUploadChunkStoreFixture.make(run)
            _ = try await f.createSession(); let selected = try await f.get(), plan = try chunkCoordinatorPlan(f, selected: selected)
            let terminalGate = BackgroundCheckpoint(), closeGate = BackgroundCheckpoint(), releaseGate = BackgroundCheckpoint()
            let store = BackgroundStoreProbe(base: f.store, terminalBarrier: terminalGate)
            let managed = try ManagedUploadSource(run: run, originals: f.access), source = ChunkCoordinatorSource(base: managed, finishGate: closeGate)
            let access = BackgroundAccessProbe(base: f.access, releaseBarrier: releaseGate), sdk = BackgroundSessionProbe(identity: plan.session)
            let owner = chunkCoordinator(f, sdk: sdk, source: source, store: store, access: access)
            let result = await owner.startUploadChunk(plan, requests: ChunkCoordinatorRequests())
            guard case .started(let started) = result, let binding = started.binding else { throw BackendContractError.notCommitted }
            await sdk.complete(binding, outcome: .completed, finishEvents: true)
            try await terminalGate.waitForArrival()
            #expect(try await mediaSnapshot(f.store).backgroundTasks[0].terminal == nil)
            #expect(await managed.resources().openHandles == 1)
            await terminalGate.release(); try await closeGate.waitForArrival()
            let terminal = try await mediaSnapshot(f.store).backgroundTasks[0]
            #expect(terminal.terminal?.outcome == .completed && terminal.ownerClosure == nil)
            #expect(await managed.resources().openHandles == 1)
            #expect(await access.counts() == [1, 0])
            await closeGate.release(); try await releaseGate.waitForArrival()
            #expect(try await mediaSnapshot(f.store).backgroundTasks[0].ownerClosure?.handlesClosed == true)
            #expect(await managed.resources().openHandles == 0)
            #expect(try await mediaOriginalSnapshot(f.store).logicalOriginals[0].readers.count == 1)
            await releaseGate.release(); try await chunkCoordinatorWaitForStop(f)
            let after = try await mediaSnapshot(f.store), request = try #require(after.requests.first)
            #expect(request.transport == .stopped && !request.hasReconciled && request.remote == .inProgress)
            #expect(request.session == f.metadataBinding.session && request.intent == .running)
            #expect(after.verifications.isEmpty && after.confirmations.isEmpty && after.outbox.isEmpty)
            try await chunkCoordinatorRequireProofs(f, task: after.backgroundTasks[0])
            #expect(try Data(contentsOf: f.url) == f.bytes)
            await sdk.finishStream(); _ = try await managed.closeOwner()
        }
    }

    @Test func aGetReservedBeforeThePriorStopCannotAuthorizeTheNextChunkEvenWhenItsReplyIsLater() async throws {
        try await withStorageRun { run in
            let f = try await BackgroundUploadChunkStoreFixture.make(run)
            _ = try await f.createSession(); let selected = try await f.get(), first = try chunkCoordinatorPlan(f, selected: selected)
            let managed = try ManagedUploadSource(run: run, originals: f.access), source = ChunkCoordinatorSource(base: managed)
            let sdk = BackgroundSessionProbe(identity: first.session), requests = ChunkCoordinatorRequests(), owner = chunkCoordinator(f, sdk: sdk, source: source)
            guard case .started(let started) = await owner.startUploadChunk(first, requests: requests), let binding = started.binding else { throw BackendContractError.notCommitted }
            let early = try await f.begin(.lookup(f.metadataBinding.session))
            await sdk.complete(binding, outcome: .cancelled, finishEvents: true)
            try await chunkCoordinatorWaitForStop(f)
            let delayed = try await f.observe(early, .status(.init(binding: f.metadataBinding, state: .receiving, evidence: nil, chunkIndexes: [0], failureCode: nil)))
            try #require(try await mediaSnapshot(f.store).requests[0].canRun)
            let invalid = try chunkCoordinatorPlan(f, selected: delayed, index: 1, session: first.session)
            let before = try await mediaSnapshot(f.store)
            #expect(await owner.startUploadChunk(invalid, requests: requests) == .refused(.requestNotReady))
            #expect(try await mediaSnapshot(f.store) == before)
            #expect(await source.counts() == [1, 0])
            #expect(await requests.count == 1)
            let fresh = try await f.get(indexes: [0]), next = try chunkCoordinatorPlan(f, selected: fresh, index: 1, session: first.session)
            guard case .started(let second) = await owner.startUploadChunk(next, requests: requests), let nextBinding = second.binding else { throw BackendContractError.notCommitted }
            #expect(await source.counts() == [2, 0])
            #expect(await requests.count == 2)
            await sdk.complete(nextBinding, outcome: .cancelled, finishEvents: true)
            try await chunkCoordinatorWaitForStop(f, tasks: 2)
            let final = try await mediaSnapshot(f.store)
            try #require(OriginalRemovalTransportHistory.stoppedTasks(f.source.original, backend: final)?.count == 2)
            for task in final.backgroundTasks { try await chunkCoordinatorRequireProofs(f, task: task) }
            let capture = CaptureMediaAdmission(), captureOwner = try captureBoundaryOwner()
            capture.begin(captureOwner, phases: [.recording]); defer { capture.end(captureOwner) }
            let reopened = BackgroundMediaCoordinator(store: f.store, identity: f.source.storeIdentity, originals: f.access, removalStore: f.store,
                captureAdmission: capture, sessionFactory: { _ in sdk }, sourceFactory: { throw BackendContractError.unavailable })
            #expect(await reopened.waitForCaptureLocalStop(captureOwner) == .ready)
            #expect(try Data(contentsOf: f.url) == f.bytes)
            await sdk.finishStream(); _ = try await managed.closeOwner()
        }
    }

    @Test(arguments: ["pause", "capture", "new-query", "UUID"])
    func aScopeChangeDuringRequestCreationKeepsTheExactOldOwnerAndStartsNoSDK(change: String) async throws {
        try await withStorageRun { run in
            let f = try await BackgroundUploadChunkStoreFixture.make(run)
            _ = try await f.createSession(); let selected = try await f.get(), plan = try chunkCoordinatorPlan(f, selected: selected)
            let managed = try ManagedUploadSource(run: run, originals: f.access), source = ChunkCoordinatorSource(base: managed), gate = BackgroundCheckpoint()
            let requests = ChunkCoordinatorRequests(gate: gate), factories = BackgroundFactoryProbe(), store = ChunkCoordinatorObservedStore(base: f.store)
            let capture = CaptureMediaAdmission(), captureOwner = try captureBoundaryOwner()
            let owner = BackgroundMediaCoordinator(store: store, identity: f.source.storeIdentity, originals: f.access, removalStore: f.store,
                admission: BackgroundPermitProbe(), captureAdmission: capture,
                sessionFactory: { _ in await factories.sdkCreated(); throw BackendContractError.unavailable }, sourceFactory: { source })
            let work = Task { await owner.startUploadChunk(plan, requests: requests) }
            try await gate.waitForArrival()
            if change == "pause" { _ = try await f.transition(.pause) }
            if change == "capture" { capture.begin(captureOwner, phases: [.recording]) }
            if change == "new-query" { _ = try await f.begin(.lookup(f.metadataBinding.session)) }
            if change == "UUID" { await store.overrideIdentity(.init(rawValue: UUID())) }
            await gate.release()
            #expect(await work.value == .unknown)
            capture.end(captureOwner)
            #expect(await factories.counts() == [0, 0])
            #expect(await source.counts() == [1, 0])
            #expect(await managed.resources().openHandles == 1)
            #expect(try await mediaSnapshot(f.store).backgroundTasks.isEmpty)
            #expect(try await mediaOriginalSnapshot(f.store).logicalOriginals[0].readers.count == 1)
            #expect(try Data(contentsOf: f.url) == f.bytes)
            // This newly created unresolved fixture is retained. No SDK terminal,
            // own-FD closure or original lease release is manufactured to clean it.
        }
    }

    @Test func unknownTerminalLookupKeepsItsOriginalEnvelopeAndDoesNotCopyAgain() async throws {
        try await withStorageRun { run in
            let f = try await BackgroundUploadChunkStoreFixture.make(run)
            _ = try await f.createSession(); let selected = try await f.get(), plan = try chunkCoordinatorPlan(f, selected: selected)
            let managed = try ManagedUploadSource(run: run, originals: f.access), source = ChunkCoordinatorSource(base: managed)
            let sdk = BackgroundSessionProbe(identity: plan.session), store = BackgroundStoreProbe(base: f.store), requests = ChunkCoordinatorRequests()
            let owner = chunkCoordinator(f, sdk: sdk, source: source, store: store)
            guard case .started(let started) = await owner.startUploadChunk(plan, requests: requests), let binding = started.binding else { throw BackendContractError.notCommitted }
            await store.hideTerminalLookup(); await sdk.complete(binding, outcome: .cancelled, finishEvents: true)
            try await backgroundEventually { await store.hiddenLookupCount() > 0 }
            let unknown = try await mediaSnapshot(f.store).backgroundTasks[0]
            #expect(unknown.terminal != nil && unknown.ownerClosure == nil)
            #expect(await managed.resources().openHandles == 1)
            await store.allowTerminalLookup()
            try await backgroundEventually {
                await owner.retryHeldEvents()
                return (try? await mediaSnapshot(f.store).requests[0].transport) == .stopped
            }
            let actual = try await mediaSnapshot(f.store).backgroundTasks[0]
            #expect(actual.events.filter { if case .terminal = $0.change { return true }; return false }.count == 1)
            #expect(await source.counts() == [1, 0])
            #expect(await requests.count == 1)
            try await chunkCoordinatorRequireProofs(f, task: actual)
            await sdk.finishStream(); _ = try await managed.closeOwner()
        }
    }
}

nonisolated func chunkCoordinatorPlan(_ f: BackgroundUploadChunkStoreFixture, selected: StoredUploadMetadataObservation,
    index: UInt64 = 0, session: BackgroundMediaSessionIdentity? = nil) throws -> BackgroundMediaUploadChunkPlan {
    .init(id: .init(rawValue: UUID().uuidString), context: .init(operation: f.source.operation, attempt: .init(rawValue: UUID().uuidString),
        target: .original(f.source.original), registration: f.source.registration.server.registration, gateGeneration: 1, storeIdentity: f.source.storeIdentity),
        session: session ?? .init(identifier: .init(rawValue: "FrameRelay.upload-chunk.test." + UUID().uuidString), generation: .init(rawValue: UUID())),
        taskDescription: UUID().uuidString, sourceID: .init(rawValue: UUID().uuidString), range: try f.range(index: index), metadata: try .init(selected))
}
nonisolated func chunkCoordinator(_ f: BackgroundUploadChunkStoreFixture, sdk: any BackgroundMediaSessionPort,
    source: any BackgroundMediaUploadSourcePort, store: (any MediaOperationStorePort)? = nil, access: (any OriginalAccessPort)? = nil) -> BackgroundMediaCoordinator {
    .init(store: store ?? f.store, identity: f.source.storeIdentity, originals: access ?? f.access, removalStore: f.store,
        admission: BackgroundPermitProbe(), sessionFactory: { _ in sdk }, sourceFactory: { source })
}
nonisolated func chunkCoordinatorWaitForStop(_ f: BackgroundUploadChunkStoreFixture, tasks: Int = 1) async throws {
    try await backgroundEventually {
        guard let snapshot = try? await mediaSnapshot(f.store), snapshot.backgroundTasks.count == tasks,
              snapshot.backgroundTasks.allSatisfy({ $0.ownerClosure != nil }) else { return false }
        return snapshot.requests[0].transport == .stopped
    }
}
nonisolated func chunkCoordinatorRequireProofs(_ f: BackgroundUploadChunkStoreFixture, task: BackgroundMediaTaskState) async throws {
    for event in task.events {
        #expect(await f.store.lookupCommit(event.mutation) == .committed(event.commit))
    }
    guard case .succeeded(let inventory) = await f.store.loadRemovalTransportInventory(f.source.original) else { throw BackendContractError.unavailable }
    let revision = try await mediaSnapshot(f.store).revision
    #expect(try BackgroundUploadChunkAdmission.stoppedRevision(task, journal: inventory.journal, through: revision) > 0)
    #expect(try await mediaOriginalSnapshot(f.store).logicalOriginals[0].readers.isEmpty)
}

actor ChunkCoordinatorRequests: BackgroundMediaUploadChunkRequestPort {
    let gate: BackgroundCheckpoint?
    private(set) var count = 0
    init(gate: BackgroundCheckpoint? = nil) { self.gate = gate }
    func makeRequest(context: BackgroundMediaRequestContext, descriptor: UploadChunkDescriptor) async throws -> URLRequest {
        count += 1; await gate?.checkpoint()
        return try chunkWireRequest(descriptor)
    }
}
actor ChunkCoordinatorSource: BackgroundMediaUploadSourcePort {
    let base: ManagedUploadSource
    let copyGate: BackgroundCheckpoint?, finishGate: BackgroundCheckpoint?
    private var chunks = 0, wholes = 0
    init(base: ManagedUploadSource, copyGate: BackgroundCheckpoint? = nil, finishGate: BackgroundCheckpoint? = nil) {
        self.base = base; self.copyGate = copyGate; self.finishGate = finishGate
    }
    func create(from lease: OriginalReadLease, id: ManagedUploadSourceID) async throws -> ManagedUploadSourceIdentity {
        wholes += 1; throw BackendContractError.unavailable
    }
    func createChunk(from lease: OriginalReadLease, id: ManagedUploadSourceID, range: UploadChunkRange) async throws -> ManagedUploadChunkIdentity {
        chunks += 1; await copyGate?.checkpoint()
        return try await base.createChunk(from: lease, id: id, range: range)
    }
    func uploadFile(for identity: ManagedUploadSourceIdentity, lease: OriginalReadLease) async throws -> BackgroundMediaUploadFile { try await base.uploadFile(for: identity, lease: lease) }
    func retain(_ identity: ManagedUploadSourceIdentity, lease: OriginalReadLease, for binding: BackgroundMediaTaskBinding) async throws { try await base.retain(identity, lease: lease, for: binding) }
    func finish(_ identity: ManagedUploadSourceIdentity, lease: OriginalReadLease, terminal: BackgroundMediaSDKTerminal) async throws -> BackgroundMediaOwnerClosure {
        await finishGate?.checkpoint(); return try await base.finish(identity, lease: lease, terminal: terminal)
    }
    func counts() -> [Int] { [chunks, wholes] }
}
private actor ChunkCoordinatorObservedStore: MediaOperationStorePort {
    let base: any MediaOperationStorePort
    private var identity: RegistrationStoreIdentity?
    init(base: any MediaOperationStorePort) { self.base = base }
    func overrideIdentity(_ value: RegistrationStoreIdentity) { identity = value }
    func load() async -> BackendStoreLoadResult {
        let result = await base.load()
        guard let identity, case .loaded(var snapshot) = result else { return result }
        snapshot.storeIdentity = identity; return .loaded(snapshot)
    }
    func commit(_ mutation: BackendStoreMutation) async -> BackendCommitResult { await base.commit(mutation) }
    func lookupCommit(_ mutation: BackendStoreMutation) async -> BackendCommitResult { await base.lookupCommit(mutation) }
}
