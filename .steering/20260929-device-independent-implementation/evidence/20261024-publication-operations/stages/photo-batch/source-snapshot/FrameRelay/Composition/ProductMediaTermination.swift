import Foundation

/// The actual product original player and the S25 factory registry share the
/// same writer. No network operation starts when this container is created.
actor ProductMediaTermination: PublicationExternalTerminationPort {
    let scopes: RenditionScopeRegistry
    private let store: any MediaOperationStorePort & OriginalStorePort
    private let access: ManagedOriginalAccess
    private let player: any OriginalPlaybackTerminationPort
    private var observations: [OriginalContent: Observation] = [:]
    init(store: any MediaOperationStorePort & OriginalStorePort, access: ManagedOriginalAccess,
         player: any OriginalPlaybackTerminationPort) {
        self.store = store; self.access = access; self.player = player
        scopes = RenditionScopeRegistry(leases: RenditionReadLeases(store: store))
    }
    func stopAndObserve(original: OriginalContent, epoch: ReaderReconciliationEpoch) async throws {
        let terminal = try await player.stopAndObserve(original: original)
        guard terminal.original == original, terminal.admissionClosed,
              terminal.createdOwners == terminal.terminals.count,
              terminal.terminals.allSatisfy({ $0.tasksJoined && $0.sdkDetached && ($0.source == nil || $0.release?.lease == $0.source?.lease) }),
              case .succeeded(let snapshot) = await store.loadOriginalState(), snapshot.reconciliationEpoch == epoch,
              let state = snapshot.logicalOriginals.first(where: { $0.original == original }), state.readers.isEmpty else {
            throw BackendContractError.unknownResult
        }
        // Current product has this one original SDK owner. Unknown persisted
        // original/media leases are still checked by this producer and registry;
        // an S23 background producer must be injected when that owner exists.
        observations[original] = .init(epoch: epoch, access: state.accessGeneration, terminal: terminal,
                                      evidence: .init(rawValue: UUID().uuidString))
    }
    func observeTerminal(original: OriginalContent, epoch: ReaderReconciliationEpoch) async throws -> EvidenceID {
        guard let observation = observations[original], observation.epoch == epoch,
              case .succeeded(let snapshot) = await store.loadOriginalState(), snapshot.reconciliationEpoch == epoch,
              let state = snapshot.logicalOriginals.first(where: { $0.original == original }),
              state.accessGeneration == observation.access, state.readers.isEmpty, state.mediaReaders.isEmpty else {
            throw BackendContractError.unknownResult
        }
        return observation.evidence
    }
    func invalidationCoordinator(identity: RegistrationStoreIdentity) -> MediaInvalidationCoordinator {
        .init(store: store, identity: identity, ordering: access, scopes: scopes, external: self)
    }
    func confirmationCoordinator(identity: RegistrationStoreIdentity) -> MediaConfirmationCoordinator { .init(store: store, identity: identity) }
    func outboxCoordinator(identity: RegistrationStoreIdentity, remote: any PublicationRemotePort) -> BackendOutboxCoordinator {
        .init(store: store, identity: identity, remote: remote)
    }
    func remote(connection: RegistrationConnection, credentials: any RegistrationAuthorizationPort,
                identity: RegistrationStoreIdentity) -> URLSessionPublicationRemote {
        .init(connection: connection, credentials: credentials, store: store, identity: identity)
    }
    /// Explicit caller action only. The current common admission producer is
    /// mandatory; constructing/opening the product library performs no GET.
    func publicationBinding(gate: MediaGateLease, sourceOperation: MediaOperationID,
                            connection: RegistrationConnection, credentials: any RegistrationAuthorizationPort,
                            identity: RegistrationStoreIdentity, admission: any RenditionMediaAdmissionPort) async throws -> PublicationHTTPBinding {
        let remote = remote(connection: connection, credentials: credentials, identity: identity)
        return try await PublicationHTTPBinding.open(gate: gate, sourceOperation: sourceOperation, connection: connection,
            remote: remote, admission: admission, store: store, identity: identity)
    }
    func rangeReader(binding: PublicationHTTPBinding, admission: any RenditionMediaAdmissionPort,
                     scope: RenditionMediaScope) async throws -> FixedRenditionRangeReader {
        let client = await FixedRenditionHTTPClient(binding: binding.binding())
        return try await FixedRenditionRangeReader.open(command: binding.command, admission: admission, authorization: binding,
            leases: RenditionReadLeases(store: store), client: client, scope: scope)
    }
    /// Explicit after exact local ACK commit, independent of ACK delivery. The
    /// old rendition remains tombstoned; original and later-version readers use
    /// newly acquired leases and scopes.
    func resume(after acknowledgement: InvalidationAcknowledgement) async throws {
        guard await store.lookupInvalidation(acknowledgement) == .succeeded(acknowledgement.record.id) else { throw BackendContractError.notCommitted }
        try await scopes.resume(after: acknowledgement)
        guard case .succeeded(let snapshot) = await store.loadOriginalState(),
              let state = snapshot.logicalOriginals.first(where: { $0.original == acknowledgement.record.rendition.original }),
              state.invalidation == nil, state.removal == nil,
              state.invalidationGeneration == acknowledgement.record.generation else { throw BackendContractError.staleGeneration }
        try await player.resumeAfterInvalidation(acknowledgement)
    }
    private struct Observation {
        let epoch: ReaderReconciliationEpoch
        let access: AccessGeneration
        let terminal: OriginalPlaybackTermination
        let evidence: EvidenceID
    }
}
