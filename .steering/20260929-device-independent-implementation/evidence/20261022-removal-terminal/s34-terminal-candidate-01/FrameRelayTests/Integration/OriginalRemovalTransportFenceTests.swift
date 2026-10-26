import Foundation
import Testing
@testable import FrameRelay

/// Real MOV/hash/unlink/disk tests. SDK events in this suite are explicitly
/// synthetic; the opt-in native SDK chain is a separate test suite.
@MainActor struct OriginalRemovalTransportFenceTests {
    @Test(arguments: StorageCandidate.allCases, ["pause", "aba", "verification", "registration", "other", "leaf"])
    func hashWindowKeepsExactTargetHistory(candidate: StorageCandidate, change: String) async throws {
        try await withStorageRun { run in
            let fixture = try await HistoricalRemovalFixture.make(run, candidate: candidate)
            try await fixture.complete()
            let keep = try await fixture.originals.original("fence-keep-" + UUID().uuidString)
            let keepURL = try await fixture.originals.files.existingURL(for: keep.reference)
            let keepBytes = try Data(contentsOf: keepURL)
            let barrier = OriginalRemovalDigestBarrier()
            let files = ManagedOriginalStore(run: run, digestCheckpoint: { _ in await barrier.checkpoint() })
            let access = ManagedOriginalAccess(store: fixture.originals.store, originals: files)
            let prepared = try await fixture.prepare(access: access)
            let before = try await mediaSnapshot(fixture.originals.store)
            let executing = Task { await access.removeOriginal(batch: prepared.batch, target: prepared.batch.targets[0],
                evidence: nil, quiescence: prepared.quiescence) }
            defer { Task { await barrier.resume() } }
            try await barrier.wait()
            try await fixture.mutate(change, keep: keep)
            await barrier.resume()
            let outcome = await executing.value
            if change == "leaf" {
                switch outcome {
                case .succeeded(let result): #expect(result.resolution == .notRemoved)
                case .failed(let failure): #expect(failure == .inaccessible || failure == .contentMismatch)
                default: Issue.record("A reached file checkpoint must reject the replacement without reporting removal")
                }
            } else {
                guard case .succeeded(let result) = outcome else { throw BackendContractError.notCommitted }
                #expect(result.resolution == (change == "other" ? .removed : .notRemoved))
            }
            #expect(await files.observeFile(fixture.binding.reference) == (change == "other" ? .absent : .present(byteCount: fixture.binding.original.content.byteCount)))
            if change == "aba" {
                #expect(try await mediaSnapshot(fixture.originals.store).requests == before.requests)
            }
            #expect(try Data(contentsOf: keepURL) == keepBytes)
            let reopened = try OriginalRemovalFixture.open(run, candidate: candidate)
            let record = try #require(try await mediaOriginalSnapshot(reopened).removalBatches.first)
            if change == "leaf" { #expect(record.targets[0].status != .resolved(.removed)) }
            else { #expect(record.targets[0].status == .resolved(change == "other" ? .removed : .notRemoved)) }
            #expect(try await mediaSnapshot(reopened).confirmations == before.confirmations)
            try await fixture.close()
        }
    }

    @Test(arguments: StorageCandidate.allCases, ["aba", "registration", "other", "leaf"])
    func finalWriterGuardRebuildsInventoryAndPermitsIndependentRevision(candidate: StorageCandidate, change: String) async throws {
        try await withStorageRun { run in
            let fixture = try await HistoricalRemovalFixture.make(run, candidate: candidate)
            try await fixture.complete()
            let keep = try await fixture.originals.original("boundary-keep-" + UUID().uuidString)
            let store = HistoricalRemovalBoundaryStore(base: fixture.originals.store)
            let access = ManagedOriginalAccess(store: store, originals: fixture.originals.files)
            let prepared = try await fixture.prepare(access: access, store: store)
            store.beforeBoundary = { try await fixture.mutate(change, keep: keep) }
            guard case .succeeded(let result) = await access.removeOriginal(batch: prepared.batch,
                target: prepared.batch.targets[0], evidence: nil, quiescence: prepared.quiescence) else { throw BackendContractError.notCommitted }
            #expect(store.boundaryCalls == 1)
            #expect(result.resolution == (change == "other" ? .removed : .notRemoved))
            #expect(await fixture.originals.files.observeFile(keep.reference) == .present(byteCount: keep.original.content.byteCount))
            #expect(await fixture.originals.files.observeFile(fixture.binding.reference) == (change == "other" ? .absent : .present(byteCount: fixture.binding.original.content.byteCount)))
            try await fixture.close()
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func callerCannotOmitTasksOrReuseAnEpochAndNewAttempt(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let fixture = try await HistoricalRemovalFixture.make(run, candidate: candidate)
            try await fixture.complete()
            let prepared = try await fixture.prepare()
            let fence = try #require(prepared.quiescence.transportFence)
            let inventory = fence.inventory
            for omitTask in [false, true] {
                let wrong = OriginalRemovalTransportInventory(original: inventory.original,
                    epoch: omitTask ? inventory.epoch : .init(rawValue: "old-writer-epoch"),
                    storeIdentity: inventory.storeIdentity, requests: inventory.requests,
                    tasks: omitTask ? [] : inventory.tasks, verifications: inventory.verifications,
                    registrations: inventory.registrations, journal: inventory.journal)
                let quiescence = OriginalRemovalQuiescence(target: prepared.batch.targets[0], transport: prepared.quiescence.transport,
                    readers: prepared.quiescence.readers, transportFence: .init(seal: fence.seal, inventory: wrong, stops: fence.stops))
                #expect(await fixture.originals.access.removeOriginal(batch: prepared.batch, target: prepared.batch.targets[0],
                    evidence: nil, quiescence: quiescence) == .notExecuted)
            }
            let context = fixture.plan.context
            _ = try await mediaCommit(fixture.originals.store, .requestTransition(command: .init(rawValue: UUID().uuidString),
                operation: context.operation, target: context.target, registration: context.registration,
                value: .reconciled(.init(context: .init(operation: context.operation, registration: context.registration,
                    target: context.target, session: fixture.plan.macSession), observation: .init(rawValue: 2), result: .notExecuted))))
            _ = try await mediaCommit(fixture.originals.store, .requestTransition(command: .init(rawValue: UUID().uuidString),
                operation: context.operation, target: context.target, registration: context.registration,
                value: .beginAttempt(.init(rawValue: "new-unresolved-attempt"))))
            #expect(await fixture.originals.access.removeOriginal(batch: prepared.batch, target: prepared.batch.targets[0],
                evidence: nil, quiescence: prepared.quiescence) == .notExecuted)
            #expect(await fixture.originals.files.observeFile(fixture.binding.reference) == .present(byteCount: fixture.binding.original.content.byteCount))
            try await fixture.close()
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func reservedWriterRejectsNewAttemptAndTaskFactories(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let fixture = try await HistoricalRemovalFixture.make(run, candidate: candidate)
            try await fixture.complete()
            let barrier = OriginalRemovalDigestBarrier()
            let files = ManagedOriginalStore(run: run, digestCheckpoint: { _ in await barrier.checkpoint() })
            let access = ManagedOriginalAccess(store: fixture.originals.store, originals: files)
            let prepared = try await fixture.prepare(access: access)
            let executing = Task { await access.removeOriginal(batch: prepared.batch, target: prepared.batch.targets[0],
                evidence: nil, quiescence: prepared.quiescence) }
            defer { Task { await barrier.resume() } }
            try await barrier.wait()
            let context = fixture.plan.context
            let before = try await mediaSnapshot(fixture.originals.store)
            let attempt = BackendStoreMutation(expectedRevision: before.revision,
                change: .requestTransition(command: .init(rawValue: UUID().uuidString), operation: context.operation,
                    target: context.target, registration: context.registration, value: .beginAttempt(.init(rawValue: "forbidden-attempt"))))
            #expect(await fixture.originals.store.commit(attempt) == .rejected(.deletionUnresolved))
            let old = try #require(before.backgroundTasks.first?.intent)
            let new = BackgroundMediaTaskIntent(id: .init(rawValue: "forbidden-new-task"), context: old.context,
                session: old.session, taskDescription: UUID().uuidString, requestFingerprint: old.requestFingerprint, source: old.source)
            #expect(await fixture.originals.store.commit(.init(expectedRevision: before.revision,
                change: .backgroundTask(command: .init(rawValue: UUID().uuidString), value: .prepared(new)),
                expectedStoreIdentity: context.storeIdentity)) == .rejected(.deletionUnresolved))
            #expect(try await mediaSnapshot(fixture.originals.store) == before)
            await barrier.resume()
            guard case .succeeded(let result) = await executing.value else { throw BackendContractError.notCommitted }
            #expect(result.resolution == .removed)
            try await fixture.close()
        }
    }

    @Test func canonicalInventoryRetainsOpaqueUTF8() async throws {
        try await withStorageRun { run in
            let fixture = try await HistoricalRemovalFixture.make(run)
            try await fixture.complete()
            guard case .succeeded(let inventory) = await fixture.originals.store.loadRemovalTransportInventory(fixture.binding.original) else {
                throw BackendContractError.unavailable
            }
            let composed = OriginalContent(capture: .init(rawValue: "\u{00e9}"), generation: inventory.original.generation, content: inventory.original.content)
            let decomposed = OriginalContent(capture: .init(rawValue: "e\u{0301}"), generation: inventory.original.generation, content: inventory.original.content)
            func replaced(_ original: OriginalContent) -> OriginalRemovalTransportInventory {
                .init(original: original, epoch: inventory.epoch, storeIdentity: inventory.storeIdentity, requests: inventory.requests,
                    tasks: inventory.tasks, verifications: inventory.verifications, registrations: inventory.registrations, journal: inventory.journal)
            }
            #expect(composed == decomposed)
            #expect(replaced(composed) != replaced(decomposed))
            #expect(inventory == inventory)
            let reopened = try OriginalRemovalFixture.open(run, candidate: .sqlite)
            guard case .succeeded(let reloaded) = await reopened.loadRemovalTransportInventory(fixture.binding.original) else { throw BackendContractError.unavailable }
            #expect(inventory.epoch != reloaded.epoch)
            #expect(PublicationStoreBoundary.exact(inventory.journal, reloaded.journal))
            try await fixture.close()
        }
    }

    @Test(arguments: StorageCandidate.allCases, [false, true])
    func allHistoricalRequestsNeedTheirOwnReceipt(candidate: StorageCandidate, omitReceipt: Bool) async throws {
        try await withStorageRun { run in
            let fixture = try await HistoricalRemovalFixture.make(run, candidate: candidate)
            try await fixture.complete()
            let context = fixture.plan.context
            let operation = MediaOperationID(rawValue: "second-operation")
            let snapshot = try await mediaSnapshot(fixture.originals.store)
            let request = MediaRequest(operation: operation, target: context.target, purpose: .upload,
                registration: context.registration, expectedStartRevision: snapshot.revision)
            _ = try await mediaCommit(fixture.originals.store, .request(command: operation, value: request))
            let session = UploadSessionID(rawValue: "second-Mac-session")
            _ = try await mediaCommit(fixture.originals.store, .requestTransition(command: .init(rawValue: "second-remote"),
                operation: operation, target: context.target, registration: context.registration,
                value: .reconciled(.init(context: .init(operation: operation, registration: context.registration,
                    target: context.target, session: session), observation: .init(rawValue: 1), result: .notExecuted))))
            let plan = BackgroundMediaUploadPlan(id: .init(rawValue: "second-task"),
                context: .init(operation: operation, attempt: .init(rawValue: "second-attempt"), target: context.target,
                    registration: context.registration, gateGeneration: 1, storeIdentity: context.storeIdentity),
                session: fixture.plan.session, taskDescription: UUID().uuidString, sourceID: .init(rawValue: UUID().uuidString),
                macSession: session, request: fixture.plan.request)
            guard case .started(let started) = await fixture.coordinator.startUpload(plan), let binding = started.binding else { throw BackendContractError.notCommitted }
            await fixture.sdk.complete(binding, outcome: .cancelled, finishEvents: true)
            try await backgroundEventually {
                guard let current = try? await mediaSnapshot(fixture.originals.store) else { return false }
                return current.requests.count == 2 && current.requests.allSatisfy { $0.transport == .stopped }
            }
            let prepared = try await fixture.prepare()
            let fence = try #require(prepared.quiescence.transportFence)
            #expect(fence.stops.count == 2 && fence.inventory.tasks.count == 2)
            let selected = omitReceipt ? OriginalRemovalTransportFence(seal: fence.seal, inventory: fence.inventory,
                stops: Array(fence.stops.prefix(1))) : fence
            let quiescence = OriginalRemovalQuiescence(target: prepared.batch.targets[0], transport: prepared.quiescence.transport,
                readers: prepared.quiescence.readers, transportFence: selected)
            guard case .succeeded(let result) = await fixture.originals.access.removeOriginal(batch: prepared.batch,
                target: prepared.batch.targets[0], evidence: nil, quiescence: quiescence) else { throw BackendContractError.notCommitted }
            #expect(result.resolution == (omitReceipt ? .notRemoved : .removed))
            #expect(await fixture.originals.files.observeFile(fixture.binding.reference) == (omitReceipt ? .present(byteCount: fixture.binding.original.content.byteCount) : .absent))
            try await fixture.close()
        }
    }
}

nonisolated struct HistoricalRemovalFixture: Sendable {
    let originals: OriginalRemovalFixture
    let binding: OriginalBinding
    let plan: BackgroundMediaUploadPlan
    let managed: ManagedUploadSource
    let sdk: BackgroundSessionProbe
    let coordinator: BackgroundMediaCoordinator

    static func make(_ run: ExplorationRunDirectory, candidate: StorageCandidate = .sqlite) async throws -> Self {
        let originals = try OriginalRemovalFixture(run: run, candidate: candidate)
        let setup = try await BackgroundCoordinatorFixture.make(originals)
        let binding = try #require(try await mediaOriginalSnapshot(originals.store).originals.first?.binding)
        let managed = try ManagedUploadSource(run: run, originals: originals.access)
        let sdk = BackgroundSessionProbe(identity: setup.plan.session)
        let coordinator = BackgroundMediaCoordinator(store: originals.store, identity: setup.plan.context.storeIdentity,
            originals: originals.access, removalStore: originals.store, admission: BackgroundPermitProbe(),
            sessionFactory: { _ in sdk }, sourceFactory: { managed })
        guard case .started = await coordinator.startUpload(setup.plan) else { throw BackendContractError.notCommitted }
        return .init(originals: originals, binding: binding, plan: setup.plan, managed: managed, sdk: sdk, coordinator: coordinator)
    }

    func complete() async throws {
        let binding = try #require(try await mediaSnapshot(originals.store).backgroundTasks.first?.binding)
        await sdk.complete(binding, outcome: .cancelled, finishEvents: true)
        try await backgroundEventually {
            guard let snapshot = try? await mediaSnapshot(originals.store) else { return false }
            return snapshot.requests.first?.transport == .stopped && snapshot.backgroundTasks.first?.ownerClosure?.handlesClosed == true
        }
        #expect((await managed.resources()).openHandles == 0)
    }

    @MainActor func prepare(access suppliedAccess: ManagedOriginalAccess? = nil,
        store suppliedStore: (any MediaDiskStore)? = nil) async throws
        -> (batch: OriginalRemovalBatch, quiescence: OriginalRemovalQuiescence) {
        let store = suppliedStore ?? originals.store
        let access = suppliedAccess ?? originals.access
        let batch = try originals.discardBatch(binding, name: "fenced-" + UUID().uuidString)
        let before = try await mediaOriginalSnapshot(store)
        guard case .committed = await store.commitOriginal(.init(operation: batch.operation, expectedRevision: before.revision,
            change: .removalBatch(batch))) else { throw BackendContractError.notCommitted }
        let player = AVOriginalPlayback(access: access)
        let termination = ProductRemovalTermination(store: store, access: access, player: player,
            scopes: RenditionScopeRegistry(leases: RenditionReadLeases(store: store)), admission: { true }, background: coordinator)
        guard case .succeeded(let quiescence) = await termination.stopForRemoval(batch.targets[0]) else { throw BackendContractError.readersActive }
        #expect(quiescence.transportFence?.stops.isEmpty == false)
        return (batch, quiescence)
    }

    @MainActor func mutate(_ change: String, keep: OriginalBinding) async throws {
        let context = plan.context
        func transition(_ value: MediaRequestTransition) async throws {
            _ = try await mediaCommit(originals.store, .requestTransition(command: .init(rawValue: UUID().uuidString),
                operation: context.operation, target: context.target, registration: context.registration, value: value))
        }
        switch change {
        case "pause": try await transition(.pause)
        case "aba": try await transition(.pause); try await transition(.resume)
        case "verification":
            let remote = RemoteOperationContext(operation: context.operation, registration: context.registration,
                target: context.target, session: plan.macSession)
            let proof = VerificationEvidence(id: .init(rawValue: "changed-proof"), context: remote, finalSaveCompleted: true,
                verification: .assemblyOnly(binding.original.content), committed: true, schemaVersion: "not-cleanup-authority", observedAt: .distantPast)
            _ = try await mediaCommit(originals.store, .verification(command: .init(rawValue: UUID().uuidString), expected: remote, evidence: proof))
        case "registration":
            _ = try await mediaRegister(originals.store, registration: .init(destination: context.registration.destination,
                id: .init(rawValue: "new-registration"), generation: .init(rawValue: 2)))
        case "other": try await mediaReconcile(originals.store, original: keep.original)
        case "leaf":
            let movie = try await originals.files.existingURL(for: binding.reference)
            let bytes = try Data(contentsOf: movie)
            try FileManager.default.moveItem(at: movie, to: originals.run.url.appendingPathComponent("held-original.mov"))
            try bytes.write(to: movie, options: .withoutOverwriting)
        default: throw BackendContractError.invalidValue
        }
    }

    func close() async throws { await sdk.finishStream(); _ = try await managed.closeOwner() }
}

@MainActor final class HistoricalRemovalBoundaryStore: RecordingStorePort, OriginalStorePort, MediaOperationStorePort {
    let base: any MediaDiskStore
    var beforeBoundary: (@MainActor @Sendable () async throws -> Void)?
    private(set) var boundaryCalls = 0
    init(base: any MediaDiskStore) { self.base = base }
    @MainActor func performRemovalBoundary(_ boundary: OriginalRemovalBoundary,
        effect: @Sendable () throws -> Void) async -> BackendOutcome<RemovalResolutionReceipt> {
        boundaryCalls += 1
        if let work = beforeBoundary {
            beforeBoundary = nil
            do { try await work() } catch { return .unknown }
        }
        return await base.performRemovalBoundary(boundary, effect: effect)
    }
    @MainActor func execute(_ command: RecordingStoreCommand) async -> RecordingStoreResult { await base.execute(command) }
    @MainActor func loadUnfinished() async -> UnfinishedRecordingLoadResult { await base.loadUnfinished() }
    @MainActor func loadRecordings() async -> RecordingStoreLoadResult { await base.loadRecordings() }
    @MainActor func loadOriginalState() async -> BackendOutcome<OriginalStoreSnapshot> { await base.loadOriginalState() }
    @MainActor func loadRemovalTransportInventory(_ original: OriginalContent) async -> BackendOutcome<OriginalRemovalTransportInventory> {
        await base.loadRemovalTransportInventory(original)
    }
    @MainActor func commitOriginal(_ mutation: OriginalStoreMutation) async -> OriginalStoreCommitResult { await base.commitOriginal(mutation) }
    @MainActor func lookupOriginalCommit(_ mutation: OriginalStoreMutation) async -> BackendOutcome<OriginalStoreCommitReceipt> { await base.lookupOriginalCommit(mutation) }
    @MainActor func commitRemovalObservation(_ mutation: OriginalStoreMutation,
        check: @Sendable () throws -> Void) async -> OriginalStoreCommitResult { await base.commitRemovalObservation(mutation, check: check) }
    @MainActor func lookupInvalidation(_ acknowledgement: InvalidationAcknowledgement) async -> BackendOutcome<InvalidationID> { await base.lookupInvalidation(acknowledgement) }
    @MainActor func load() async -> BackendStoreLoadResult { await base.load() }
    @MainActor func commit(_ mutation: BackendStoreMutation) async -> BackendCommitResult { await base.commit(mutation) }
    @MainActor func lookupCommit(_ mutation: BackendStoreMutation) async -> BackendCommitResult { await base.lookupCommit(mutation) }
}
