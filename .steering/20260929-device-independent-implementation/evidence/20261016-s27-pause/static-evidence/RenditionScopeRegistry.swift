@testable import FrameRelay
import Foundation

/// Composition must route all its S25 factories through this registry. The
/// required external producer covers scopes/SDK owners outside that boundary.
actor RenditionScopeRegistry {
    private let leases: RenditionReadLeases
    private var scopes: [OriginalContent: [RenditionMediaScope]] = [:]
    private var sealed: Set<OriginalContent> = []
    private var opening: [OriginalContent: Int] = [:]
    private var waiters: [OriginalContent: [CheckedContinuation<Void, Never>]] = [:]
    init(leases: RenditionReadLeases) { self.leases = leases }

    func open(original: OriginalContent) async throws -> RenditionMediaScope {
        guard !sealed.contains(original) else { throw BackendContractError.invalidated }
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
        guard !sealed.contains(original) else {
            _ = try? await scope.close()
            throw BackendContractError.invalidated
        }
        return scope
    }

    func stopAndReconcile(original: OriginalContent, external: any PublicationExternalTerminationPort) async throws -> MediaReaderReconciliation {
        sealed.insert(original)
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
                  && $0.accessGeneration == state.accessGeneration && $0.registeredOwners == $0.observations.count }) else {
            throw BackendContractError.readersActive
        }
        let observations = Dictionary(uniqueKeysWithValues: MediaReaderOwner.allCases.map {
            ($0, EvidenceID(rawValue: "registry-\($0.rawValue)-\(UUID().uuidString)-\(evidence.rawValue)"))
        })
        let result = MediaReaderReconciliation(original: original, accessGeneration: state.accessGeneration, epoch: epoch, observations: observations)
        let mutation = OriginalStoreMutation(operation: .init(rawValue: UUID().uuidString), expectedRevision: snapshot.revision, change: .reconcileMedia(result))
        guard case .committed = await leases.store.commitOriginal(mutation) else { throw BackendContractError.unknownResult }
        return result
    }
}
