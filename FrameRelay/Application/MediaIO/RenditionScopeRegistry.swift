import Foundation

/// Composition must route all its S25 factories through this registry. The
/// required external producer covers scopes/SDK owners outside that boundary.
actor RenditionScopeRegistry {
    private let leases: RenditionReadLeases
    private var scopes: [OriginalContent: [RenditionMediaScope]] = [:]
    private var sealed: Set<OriginalContent> = []
    private var removalSeals: [MediaOperationID: OriginalRemovalAdmissionSeal] = [:]
    private var removalInventories: [MediaOperationID: (seal: OriginalRemovalAdmissionSeal, epoch: ReaderReconciliationEpoch,
        access: AccessGeneration, terminals: [RenditionScopeTerminal])] = [:]
    private var opening: [OriginalContent: Int] = [:]
    private var waiters: [OriginalContent: [CheckedContinuation<Void, Never>]] = [:]
    private var completed: [OriginalContent: [RenditionScopeTerminal]] = [:]
    private var completedObservation: [OriginalContent: MediaReaderReconciliation] = [:]
    init(leases: RenditionReadLeases) { self.leases = leases }

    func open(original: OriginalContent) async throws -> RenditionMediaScope {
        guard !sealed.contains(original), !removalSeals.values.contains(where: { $0.target.original == original }) else { throw BackendContractError.invalidated }
        opening[original, default: 0] += 1
        defer {
            opening[original, default: 0] -= 1
            if opening[original] == 0 {
                let values = waiters.removeValue(forKey: original) ?? []
                for value in values { value.resume() }
            }
        }
        let scope = try await RenditionMediaScope.open(original: original, leases: leases)
        scopes[original, default: []].append(scope)
        guard !sealed.contains(original), !removalSeals.values.contains(where: { $0.target.original == original }) else {
            _ = try? await scope.close()
            throw BackendContractError.invalidated
        }
        return scope
    }

    func stopAndReconcile(original: OriginalContent, external: any PublicationExternalTerminationPort) async throws -> MediaReaderReconciliation {
        sealed.insert(original)
        return try await closeAndReconcile(original: original, external: external)
    }

    func stopForRemoval(_ seal: OriginalRemovalAdmissionSeal,
        external: any PublicationExternalTerminationPort) async throws -> MediaReaderReconciliation {
        if let existing = removalSeals[seal.target.operation], existing != seal { throw BackendContractError.identityMismatch }
        removalSeals[seal.target.operation] = seal
        let result = try await closeAndReconcile(original: seal.target.original, external: external)
        removalInventories[seal.target.operation] = (seal, result.epoch, result.accessGeneration, completed[seal.target.original] ?? [])
        return result
    }

    private func closeAndReconcile(original: OriginalContent, external: any PublicationExternalTerminationPort) async throws -> MediaReaderReconciliation {
        if opening[original, default: 0] > 0 { await withCheckedContinuation { waiters[original, default: []].append($0) } }
        let inventory = scopes[original] ?? []
        // Launch every close before joining. Failure due to another scope's
        // lease must not prevent that other scope from receiving its stop.
        let stops = inventory.map { scope in Task { try await scope.close() } }
        for stop in stops { _ = await stop.result }
        let epoch = try await leases.currentEpoch()
        try await external.stopAndObserve(original: original, epoch: epoch)
        var terminals: [RenditionScopeTerminal] = []
        for scope in inventory { terminals.append(try await scope.close()) }
        let evidence = try await external.observeTerminal(original: original, epoch: epoch)
        guard !evidence.rawValue.isEmpty,
              case .succeeded(let snapshot) = await leases.store.loadOriginalState(), snapshot.reconciliationEpoch == epoch,
              let state = snapshot.logicalOriginals.first(where: { $0.original == original }),
              state.readers.isEmpty, state.mediaReaders.isEmpty,
              terminals.allSatisfy({ $0.original == original && $0.epoch == epoch && $0.factoryAdmissionClosed
                  && $0.accessGeneration.rawValue <= state.accessGeneration.rawValue
                  && $0.registeredOwners == $0.observations.count }) else {
            throw BackendContractError.readersActive
        }
        let observations = Dictionary(uniqueKeysWithValues: MediaReaderOwner.allCases.map {
            ($0, EvidenceID(rawValue: "registry-\($0.rawValue)-\(UUID().uuidString)-\(evidence.rawValue)"))
        })
        let result = MediaReaderReconciliation(original: original, accessGeneration: state.accessGeneration, epoch: epoch, observations: observations)
        let mutation = OriginalStoreMutation(operation: .init(rawValue: UUID().uuidString), expectedRevision: snapshot.revision, change: .reconcileMedia(result))
        guard case .committed = await leases.store.commitOriginal(mutation) else { throw BackendContractError.unknownResult }
        // A scope's terminal retains the generation at which it actually
        // closed. Only this new, common observation binds the fixed inventory
        // and today's external owners/global zero readers to today's access.
        completed[original] = terminals
        completedObservation[original] = result
        return result
    }

    func resumeAfterRemoval(_ release: OriginalRemovalAdmissionRelease) async throws {
        guard removalSeals[release.seal.target.operation] == release.seal,
              let inventory = removalInventories[release.seal.target.operation], inventory.seal == release.seal,
              inventory.epoch == release.epoch, inventory.access == release.access,
              inventory.terminals.count == scopes[release.seal.target.original, default: []].count,
              inventory.terminals.allSatisfy({ $0.original == release.seal.target.original && $0.epoch == release.epoch
                  && $0.accessGeneration.rawValue <= release.access.rawValue && $0.factoryAdmissionClosed
                  && $0.registeredOwners == $0.observations.count }),
              case .succeeded(let snapshot) = await leases.store.loadOriginalState(), release.validates(snapshot) else {
            throw BackendContractError.readersActive
        }
        removalSeals.removeValue(forKey: release.seal.target.operation)
        removalInventories.removeValue(forKey: release.seal.target.operation)
        let original = release.seal.target.original
        if !sealed.contains(original), !removalSeals.values.contains(where: { $0.target.original == original }) {
            scopes.removeValue(forKey: original)
            completed.removeValue(forKey: original)
            completedObservation.removeValue(forKey: original)
        }
    }

    /// A committed tombstone ends this admission barrier. Old scopes remain
    /// sealed; only a new factory scope can consume a later publication.
    func resume(after acknowledgement: InvalidationAcknowledgement) async throws {
        let original = acknowledgement.record.rendition.original
        guard acknowledgement.isCommitted,
              await leases.store.lookupInvalidation(acknowledgement) == .succeeded(acknowledgement.record.id),
              case .succeeded(let snapshot) = await leases.store.loadOriginalState(), let epoch = snapshot.reconciliationEpoch,
              let state = snapshot.logicalOriginals.first(where: { $0.original == original }),
              state.invalidation == nil, state.removal == nil, state.invalidationGeneration == acknowledgement.record.generation,
              state.readersReleased(in: epoch) else { throw BackendContractError.readersActive }
        guard sealed.contains(original) else { return }
        guard let inventory = completed[original], inventory.count == scopes[original, default: []].count,
              let observation = completedObservation[original], observation.epoch == epoch,
              observation.accessGeneration == state.accessGeneration,
              inventory.allSatisfy({ $0.original == original && $0.epoch == epoch && $0.factoryAdmissionClosed
                  && $0.accessGeneration.rawValue <= observation.accessGeneration.rawValue
                  && $0.registeredOwners == $0.observations.count }) else {
            throw BackendContractError.unknownResult
        }
        sealed.remove(original)
        if !removalSeals.values.contains(where: { $0.target.original == original }) {
            scopes.removeValue(forKey: original)
            completed.removeValue(forKey: original)
            completedObservation.removeValue(forKey: original)
        }
    }
}
