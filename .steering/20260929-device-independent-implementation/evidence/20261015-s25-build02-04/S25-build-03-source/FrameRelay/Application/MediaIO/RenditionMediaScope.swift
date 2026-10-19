import Foundation

/// Factory registration is retained for the whole scope, including terminated
/// owners. A terminal inventory is not inferred from an empty live dictionary.
actor RenditionMediaScope {
    nonisolated let original: OriginalContent
    nonisolated let epoch: ReaderReconciliationEpoch
    private let leases: RenditionReadLeases
    private var accepting = true
    private var registrations: [Registration] = []
    private var closing: Task<RenditionScopeTerminal, Error>?
    private var terminal: RenditionScopeTerminal?

    private init(original: OriginalContent, epoch: ReaderReconciliationEpoch, leases: RenditionReadLeases) {
        self.original = original; self.epoch = epoch; self.leases = leases
    }
    static func open(original: OriginalContent, leases: RenditionReadLeases) async throws -> RenditionMediaScope {
        let epoch = try await leases.currentEpoch()
        return RenditionMediaScope(original: original, epoch: epoch, leases: leases)
    }

    func register(owner: MediaReaderOwner,
                  stop: @escaping @Sendable () async throws -> RenditionReadTerminal) throws -> RenditionScopePermit {
        guard accepting else { throw BackendContractError.wrongStage }
        let id = UUID()
        registrations.append(.init(id: id, owner: owner, stop: stop))
        return RenditionScopePermit { [weak self] in
            guard let self else { throw BackendContractError.unavailable }
            try await self.admit(id)
        }
    }

    fileprivate func admit(_ id: UUID) throws {
        guard accepting, registrations.contains(where: { $0.id == id }) else { throw BackendContractError.wrongStage }
    }

    func close() async throws -> RenditionScopeTerminal {
        if let terminal { return terminal }
        if let closing { return try await closing.value }
        accepting = false
        let work = Task { try await finishClosing() }
        closing = work
        do { let value = try await work.value; terminal = value; closing = nil; return value }
        catch { closing = nil; throw error }
    }

    private func finishClosing() async throws -> RenditionScopeTerminal {
        // A player owns its resource-loader tasks. Then transports terminate,
        // local reader wrappers drain, and finally the temporary file owner.
        let ordered = registrations.enumerated().sorted {
            let lhs = Self.order($0.element.owner), rhs = Self.order($1.element.owner)
            return lhs == rhs ? $0.offset > $1.offset : lhs < rhs
        }
        var observed: [RenditionOwnerTermination] = []
        for entry in ordered {
            let result: RenditionReadTerminal
            if let prior = entry.element.terminal { result = prior }
            else if let stop = entry.element.stop { result = try await stop() }
            else { throw BackendContractError.unknownResult }
            guard result.epoch == epoch, result.started == result.completed, result.handlesClosed else {
                throw BackendContractError.readersActive
            }
            observed.append(.init(owner: entry.element.owner, evidence: .init(rawValue: entry.element.id.uuidString),
                                  terminal: result))
            registrations[entry.offset].terminal = result
            registrations[entry.offset].stop = nil
        }
        guard case .succeeded(let snapshot) = await leases.store.loadOriginalState(),
              snapshot.reconciliationEpoch == epoch,
              let state = snapshot.logicalOriginals.first(where: { $0.original == original }),
              state.mediaReaders.isEmpty else { throw BackendContractError.readersActive }
        return .init(original: original, epoch: epoch, accessGeneration: state.accessGeneration,
                     factoryAdmissionClosed: true, registeredOwners: registrations.count, observations: observed)
    }

    /// The scope covers its S25 factories. S23 must additionally enumerate its
    /// OS/background owners before a global S21 reconciliation can be committed.
    /// There is intentionally no default "no other owners" implementation.
    func reconcile(external: any RenditionExternalOwnersPort) async throws -> MediaReaderReconciliation {
        let own = try await close()
        let externalEvidence = try await external.observeTerminal(original: original, epoch: epoch)
        guard case .succeeded(let snapshot) = await leases.store.loadOriginalState(),
              snapshot.reconciliationEpoch == epoch,
              let state = snapshot.logicalOriginals.first(where: { $0.original == original }),
              state.accessGeneration == own.accessGeneration, state.mediaReaders.isEmpty, state.readers.isEmpty else {
            throw BackendContractError.readersActive
        }
        // Each owner entry attests to the sealed factory inventory plus its real
        // callback results and the explicitly supplied external-owner observer.
        let evidence = Dictionary(uniqueKeysWithValues: MediaReaderOwner.allCases.map { owner in
            (owner, EvidenceID(rawValue: "s25-\(owner.rawValue)-\(UUID().uuidString)-\(externalEvidence.rawValue)"))
        })
        let result = MediaReaderReconciliation(original: original, accessGeneration: own.accessGeneration,
            epoch: epoch, observations: evidence)
        let mutation = OriginalStoreMutation(operation: .init(rawValue: UUID().uuidString),
            expectedRevision: snapshot.revision, change: .reconcileMedia(result))
        guard case .committed = await leases.store.commitOriginal(mutation) else { throw BackendContractError.unknownResult }
        return result
    }

    private static func order(_ owner: MediaReaderOwner) -> Int {
        switch owner { case .renditionPlayer: 0; case .transport: 1; case .temporaryMedia: 2 }
    }
    private struct Registration {
        let id: UUID
        let owner: MediaReaderOwner
        var stop: (@Sendable () async throws -> RenditionReadTerminal)?
        var terminal: RenditionReadTerminal? = nil
    }
}

nonisolated struct RenditionScopePermit: Sendable {
    private let validate: @Sendable () async throws -> Void
    fileprivate init(validate: @escaping @Sendable () async throws -> Void) { self.validate = validate }
    func check() async throws { try await validate() }
}

nonisolated struct RenditionOwnerTermination: Equatable, Sendable {
    let owner: MediaReaderOwner
    let evidence: EvidenceID
    let terminal: RenditionReadTerminal
}
nonisolated struct RenditionScopeTerminal: Equatable, Sendable {
    let original: OriginalContent
    let epoch: ReaderReconciliationEpoch
    let accessGeneration: AccessGeneration
    let factoryAdmissionClosed: Bool
    let registeredOwners: Int
    let observations: [RenditionOwnerTermination]
}
nonisolated protocol RenditionExternalOwnersPort: Sendable {
    func observeTerminal(original: OriginalContent, epoch: ReaderReconciliationEpoch) async throws -> EvidenceID
}
