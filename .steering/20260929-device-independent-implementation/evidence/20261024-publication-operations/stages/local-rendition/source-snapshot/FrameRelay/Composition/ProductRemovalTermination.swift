import Foundation

/// Removal-only admission and fresh observation of the normal root's actual
/// owners. Historical transport never becomes neverStarted or cleanup proof.
@MainActor final class ProductRemovalTermination: OriginalRemovalTerminationPort, PublicationExternalTerminationPort {
    private let store: any MediaOperationStorePort & OriginalStorePort
    private let access: ManagedOriginalAccess
    private let player: any OriginalPlaybackTerminationPort
    let scopes: RenditionScopeRegistry
    private let admission: @MainActor @Sendable () -> Bool
    private let background: (any OriginalRemovalBackgroundPort)?
    private var seals: [MediaOperationID: OriginalRemovalAdmissionSeal] = [:]
    private var stopping: [MediaOperationID: Task<BackendOutcome<OriginalRemovalQuiescence>, Never>] = [:]
    private var observed: [OriginalContent: (epoch: ReaderReconciliationEpoch, access: AccessGeneration, evidence: EvidenceID)] = [:]

    init(store: any MediaOperationStorePort & OriginalStorePort, access: ManagedOriginalAccess,
         player: any OriginalPlaybackTerminationPort, scopes: RenditionScopeRegistry,
         admission: @escaping @MainActor @Sendable () -> Bool,
         background: (any OriginalRemovalBackgroundPort)? = nil) {
        self.store = store; self.access = access; self.player = player; self.scopes = scopes; self.admission = admission
        self.background = background
    }

    func unavailableReason(original: OriginalContent) -> String? {
        seals.values.contains(where: { $0.target.original == original })
            ? "前の削除処理の終了を照合してください。" : nil
    }

    @MainActor func stopForRemoval(_ target: OriginalRemovalTarget) async -> BackendOutcome<OriginalRemovalQuiescence> {
        guard stopping[target.operation] == nil else { return .inProgress }
        let task = Task { await self.performStop(target) }
        stopping[target.operation] = task
        let result = await task.value
        stopping.removeValue(forKey: target.operation)
        return result
    }

    private func performStop(_ target: OriginalRemovalTarget) async -> BackendOutcome<OriginalRemovalQuiescence> {
        guard admission() else { return .notExecuted }
        guard case .succeeded(let initial) = await store.loadOriginalState(),
              let batch = initial.removalBatches.first(where: { $0.targets.contains(where: { PublicationStoreBoundary.exact($0.target, target) && $0.status == .unprocessed }) }),
              case .loaded(let backend) = await store.load() else { return .unknown }
        if background == nil, !Self.neverStarted(target.original, backend: backend) { return .unknown }
        if seals.values.contains(where: { $0.target.original == target.original && $0.target.operation != target.operation }) { return .notExecuted }
        let seal = seals[target.operation] ?? .init(batch: batch.batch.operation, target: target, nonce: UUID().uuidString)
        guard PublicationStoreBoundary.exact(seal.batch, batch.batch.operation), PublicationStoreBoundary.exact(seal.target, target) else { return .unknown }
        seals[target.operation] = seal
        let fence: OriginalRemovalTransportFence?
        if let background {
            guard case .succeeded(let observed) = await background.sealForRemoval(seal),
                  observed.seal.exactlyMatches(seal) else { return .unknown }
            fence = observed
        } else { fence = nil }
        do {
            _ = try await scopes.stopForRemoval(seal, external: self)
            guard admission(), case .loaded(let latest) = await store.load(),
                  case .succeeded(let readers) = await access.reconcileReaders(target.original) else { return .notExecuted }
            if let fence, let background {
                guard fence.validatesHistory(latest), case .succeeded(let current) = await background.sealForRemoval(seal),
                      current.seal.exactlyMatches(seal), current.inventory == fence.inventory,
                      case .succeeded(let originals) = await store.loadOriginalState(),
                      originals.reconciliationEpoch == fence.inventory.epoch else { return .unknown }
                // The compatibility field is one actual receipt; the fence
                // carries and independently validates every stopped request.
                let summary: TransportQuiescence = fence.stops.first.map { .stopped($0) } ?? .neverStarted(.original(target.original))
                return .succeeded(.init(target: target, transport: summary, readers: readers, transportFence: fence))
            }
            guard Self.neverStarted(target.original, backend: latest) else { return .unknown }
            return .succeeded(.init(target: target, transport: .neverStarted(.original(target.original)), readers: readers))
        } catch { return .unknown }
    }

    @MainActor func stopAndObserve(original: OriginalContent, epoch: ReaderReconciliationEpoch) async throws {
        guard let seal = seals.values.first(where: { $0.target.original == original }) else { throw BackendContractError.notCommitted }
        if let background {
            guard case .succeeded(let observed) = await background.sealForRemoval(seal), observed.seal.exactlyMatches(seal),
                  observed.inventory.epoch == epoch else { throw BackendContractError.readersActive }
        }
        let terminal = try await player.stopForRemoval(seal)
        guard terminal.original == original, terminal.admissionClosed,
              terminal.createdOwners == terminal.terminals.count,
              terminal.terminals.allSatisfy({ $0.tasksJoined && $0.sdkDetached && ($0.source == nil || $0.release?.lease == $0.source?.lease) }),
              case .succeeded(let snapshot) = await store.loadOriginalState(), snapshot.reconciliationEpoch == epoch,
              let state = snapshot.logicalOriginals.first(where: { $0.original == original }), state.readers.isEmpty else {
            throw BackendContractError.readersActive
        }
        observed[original] = (epoch, state.accessGeneration, .init(rawValue: UUID().uuidString))
    }

    @MainActor func observeTerminal(original: OriginalContent, epoch: ReaderReconciliationEpoch) async throws -> EvidenceID {
        guard let observation = observed[original], observation.epoch == epoch,
              case .succeeded(let snapshot) = await store.loadOriginalState(), snapshot.reconciliationEpoch == epoch,
              let state = snapshot.logicalOriginals.first(where: { $0.original == original }),
              state.accessGeneration == observation.access, state.readers.isEmpty, state.mediaReaders.isEmpty else {
            throw BackendContractError.readersActive
        }
        return observation.evidence
    }

    /// No old receipt is reused: sealed factories and all actual owners are
    /// observed again under today's epoch/access before releasing this owner.
    func finish(_ record: OriginalRemovalBatchRecord) async -> Bool {
        var complete = true
        for row in record.targets {
            if let stop = stopping[row.target.operation] { _ = await stop.value }
            guard let seal = seals[row.target.operation] else { continue }
            guard PublicationStoreBoundary.exact(seal.batch, record.batch.operation), PublicationStoreBoundary.exact(seal.target, row.target) else { complete = false; continue }
            switch row.status { case .notExecuted, .resolved: break; case .unprocessed, .reserved: complete = false; continue }
            do {
                _ = try await scopes.stopForRemoval(seal, external: self)
                guard case .succeeded(let snapshot) = await store.loadOriginalState(), let epoch = snapshot.reconciliationEpoch,
                      let state = snapshot.logicalOriginals.first(where: { $0.original == row.target.original }) else { complete = false; continue }
                let resolution: RemovalResolution?
                if case .resolved(let value) = row.status { resolution = value } else { resolution = nil }
                let release = OriginalRemovalAdmissionRelease(seal: seal, epoch: epoch, access: state.accessGeneration,
                    invalidation: state.invalidationGeneration, resolution: resolution)
                guard release.validates(snapshot) else { complete = false; continue }
                try await scopes.resumeAfterRemoval(release)
                try await player.resumeAfterRemoval(release)
                if let background, !(await background.releaseAfterRemoval(release)) { complete = false; continue }
                seals.removeValue(forKey: row.target.operation)
                observed.removeValue(forKey: row.target.original)
            } catch { complete = false }
        }
        return complete
    }

    nonisolated static func neverStarted(_ original: OriginalContent, backend: BackendStoreSnapshot) -> Bool {
        OriginalRemovalTransportHistory.neverStarted(original, backend: backend)
    }
}

/// One final MainActor admission before handing the accepted target into its
/// durable S32 operation. REC/saving changes stop later targets, never wait for
/// automatic retry or turn post-save binding work into a REC gate.
@MainActor final class ProductRemovalExecution: OriginalRemovalExecutionPort {
    private let access: ManagedOriginalAccess
    private let admission: @MainActor @Sendable () -> Bool
    init(access: ManagedOriginalAccess, admission: @escaping @MainActor @Sendable () -> Bool) {
        self.access = access; self.admission = admission
    }
    @MainActor func removeOriginal(batch: OriginalRemovalBatch, target: OriginalRemovalTarget,
        evidence: CleanupEvidenceSelection?, quiescence: OriginalRemovalQuiescence) async -> BackendOutcome<RemovalResolutionReceipt> {
        guard admission() else { return .notExecuted }
        return await access.removeOriginal(batch: batch, target: target, evidence: evidence, quiescence: quiescence)
    }
    @MainActor func observeRemoval(_ intent: RemovalIntent) async -> BackendOutcome<RemovalResolutionReceipt> {
        guard admission() else { return .notExecuted }
        return await access.observeRemoval(intent)
    }
}
