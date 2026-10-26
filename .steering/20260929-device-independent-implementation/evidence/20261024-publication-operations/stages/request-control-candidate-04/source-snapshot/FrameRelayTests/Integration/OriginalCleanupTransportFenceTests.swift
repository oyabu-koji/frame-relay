import Foundation
import Testing
@testable import FrameRelay

/// Same real file/hash/disk boundary as discard. The input proof and SDK events
/// are test contracts tied to the exact S23 request, never real-network proof.
@MainActor struct OriginalCleanupTransportFenceTests {
    @Test(arguments: StorageCandidate.allCases, ["aba", "verification", "registration", "other"])
    func cleanupHashWindowRechecksExactHistoryAndCurrentProof(candidate: StorageCandidate, change: String) async throws {
        try await withStorageRun { run in
            let fixture = try await HistoricalRemovalFixture.make(run, candidate: candidate)
            try await fixture.complete()
            let keep = try await fixture.originals.original("cleanup-fence-keep")
            let barrier = OriginalRemovalDigestBarrier()
            let files = ManagedOriginalStore(run: run, digestCheckpoint: { _ in await barrier.checkpoint() })
            let access = ManagedOriginalAccess(store: fixture.originals.store, originals: files)
            let prepared = try await cleanupPrepared(fixture, access: access)
            let before = try await mediaSnapshot(fixture.originals.store)
            let executing = Task { await access.removeOriginal(batch: prepared.batch, target: prepared.batch.targets[0],
                evidence: prepared.evidence, quiescence: prepared.quiescence) }
            defer { Task { await barrier.resume() } }
            try await barrier.wait()
            try await fixture.mutate(change, keep: keep)
            await barrier.resume()
            guard case .succeeded(let result) = await executing.value else { throw BackendContractError.notCommitted }
            #expect(result.resolution == (change == "other" ? .removed : .notRemoved))
            #expect(await files.observeFile(fixture.binding.reference) == (change == "other" ? .absent : .present(byteCount: fixture.binding.original.content.byteCount)))
            #expect(await files.observeFile(keep.reference) == .present(byteCount: keep.original.content.byteCount))
            let reopened = try OriginalRemovalFixture.open(run, candidate: candidate)
            let state = try await mediaOriginalSnapshot(reopened)
            #expect(state.removalBatches.first?.targets.first?.status == .resolved(change == "other" ? .removed : .notRemoved))
            #expect(try await mediaSnapshot(reopened).confirmations == before.confirmations)
            try await fixture.close()
        }
    }

    @Test(arguments: StorageCandidate.allCases, ["verification", "registration", "other"])
    func cleanupFinalWriterRebuildsInventoryInsteadOfAcceptingAnOldProof(candidate: StorageCandidate, change: String) async throws {
        try await withStorageRun { run in
            let fixture = try await HistoricalRemovalFixture.make(run, candidate: candidate)
            try await fixture.complete()
            let keep = try await fixture.originals.original("cleanup-final-keep")
            let store = HistoricalRemovalBoundaryStore(base: fixture.originals.store)
            let access = ManagedOriginalAccess(store: store, originals: fixture.originals.files)
            let prepared = try await cleanupPrepared(fixture, access: access, store: store)
            store.beforeBoundary = { try await fixture.mutate(change, keep: keep) }
            guard case .succeeded(let result) = await access.removeOriginal(batch: prepared.batch,
                target: prepared.batch.targets[0], evidence: prepared.evidence, quiescence: prepared.quiescence) else {
                throw BackendContractError.notCommitted
            }
            #expect(store.boundaryCalls == 1)
            #expect(result.resolution == (change == "other" ? .removed : .notRemoved))
            #expect(await fixture.originals.files.observeFile(fixture.binding.reference) == (change == "other" ? .absent : .present(byteCount: fixture.binding.original.content.byteCount)))
            #expect(await fixture.originals.files.observeFile(keep.reference) == .present(byteCount: keep.original.content.byteCount))
            try await fixture.close()
        }
    }

    @Test(arguments: StorageCandidate.allCases, ["unsupported", "wrong-confirmation", "omitted-task"])
    func transportTerminalCannotReplaceCleanupAuthority(candidate: StorageCandidate, fault: String) async throws {
        try await withStorageRun { run in
            let fixture = try await HistoricalRemovalFixture.make(run, candidate: candidate)
            try await fixture.complete()
            let prepared = try await cleanupPrepared(fixture, schema: fault == "unsupported" ? "unsupported" : "s32-contract")
            let evidence: CleanupEvidenceSelection
            if fault == "wrong-confirmation" {
                evidence = .init(registration: prepared.evidence.registration,
                    verificationCommand: prepared.evidence.verificationCommand,
                    confirmationOperation: .init(rawValue: "unrelated-confirmation"))
            } else { evidence = prepared.evidence }
            let quiescence: OriginalRemovalQuiescence
            if fault == "omitted-task" {
                let fence = try #require(prepared.quiescence.transportFence)
                let inventory = fence.inventory
                let incomplete = OriginalRemovalTransportInventory(original: inventory.original, epoch: inventory.epoch,
                    storeIdentity: inventory.storeIdentity, requests: inventory.requests, tasks: [],
                    verifications: inventory.verifications, registrations: inventory.registrations, journal: inventory.journal)
                quiescence = .init(target: prepared.batch.targets[0], transport: prepared.quiescence.transport,
                    readers: prepared.quiescence.readers, transportFence: .init(seal: fence.seal, inventory: incomplete, stops: fence.stops))
            } else { quiescence = prepared.quiescence }
            #expect(await fixture.originals.access.removeOriginal(batch: prepared.batch, target: prepared.batch.targets[0],
                evidence: evidence, quiescence: quiescence) == .notExecuted)
            #expect(await fixture.originals.files.observeFile(fixture.binding.reference) == .present(byteCount: fixture.binding.original.content.byteCount))
            #expect(try await mediaOriginalSnapshot(fixture.originals.store).removalBatches.first?.targets.first?.status == .unprocessed)
            try await fixture.close()
        }
    }

    @Test(arguments: [1, 2, 3])
    func captureAdmissionKeepsCleanupOriginalBeforeStopAfterStopAndExecution(denyAt: Int) async throws {
        try await withStorageRun { run in
            let fixture = try await HistoricalRemovalFixture.make(run)
            try await fixture.complete()
            let context = cleanupRemoteContext(fixture.plan)
            _ = try await cleanupContractEvidence(fixture.originals, binding: fixture.binding, context: context, schema: "s32-contract")
            let gate = CleanupAdmission(denyAt: denyAt)
            let adapter = AVOriginalPlayback(access: fixture.originals.access)
            let termination = ProductRemovalTermination(store: fixture.originals.store, access: fixture.originals.access,
                player: adapter, scopes: RenditionScopeRegistry(leases: RenditionReadLeases(store: fixture.originals.store)),
                admission: { gate.permit() }, background: fixture.coordinator)
            let execution = ProductRemovalExecution(access: fixture.originals.access, admission: { gate.permit() })
            let batch = try fixture.originals.batch([fixture.binding])
            let coordinator = CleanupCoordinator(store: fixture.originals.store, termination: termination, execution: execution)
            guard case .succeeded(let result) = await coordinator.start(batch) else { throw BackendContractError.notCommitted }
            #expect(result.targets.first?.status == .notExecuted(denyAt == 3 ? .ineligible : .terminationUnconfirmed))
            #expect(await fixture.originals.files.observeFile(fixture.binding.reference) == .present(byteCount: fixture.binding.original.content.byteCount))
            #expect(try await mediaOriginalSnapshot(fixture.originals.store).originals.first?.removal == nil)
            try await fixture.close()
        }
    }
}

@MainActor private func cleanupPrepared(_ fixture: HistoricalRemovalFixture,
    access suppliedAccess: ManagedOriginalAccess? = nil, store suppliedStore: (any MediaDiskStore)? = nil,
    schema: String = "s32-contract") async throws
    -> (batch: OriginalRemovalBatch, evidence: CleanupEvidenceSelection, quiescence: OriginalRemovalQuiescence) {
    let store = suppliedStore ?? fixture.originals.store
    let access = suppliedAccess ?? fixture.originals.access
    let evidence = try await cleanupContractEvidence(fixture.originals, binding: fixture.binding,
        context: cleanupRemoteContext(fixture.plan), schema: schema).0
    let batch = try fixture.originals.batch([fixture.binding], name: "fenced-cleanup-" + UUID().uuidString)
    let before = try await mediaOriginalSnapshot(store)
    guard case .committed = await store.commitOriginal(.init(operation: batch.operation, expectedRevision: before.revision,
        change: .removalBatch(batch))) else { throw BackendContractError.notCommitted }
    let adapter = AVOriginalPlayback(access: access)
    let termination = ProductRemovalTermination(store: store, access: access, player: adapter,
        scopes: RenditionScopeRegistry(leases: RenditionReadLeases(store: store)), admission: { true }, background: fixture.coordinator)
    guard case .succeeded(let quiescence) = await termination.stopForRemoval(batch.targets[0]) else { throw BackendContractError.readersActive }
    return (batch, evidence, quiescence)
}

nonisolated private func cleanupRemoteContext(_ plan: BackgroundMediaUploadPlan) -> RemoteOperationContext {
    .init(operation: plan.context.operation, registration: plan.context.registration, target: plan.context.target, session: plan.macSession)
}

@MainActor private final class CleanupAdmission {
    let denyAt: Int
    private var calls = 0
    init(denyAt: Int) { self.denyAt = denyAt }
    func permit() -> Bool { calls += 1; return calls != denyAt }
}
