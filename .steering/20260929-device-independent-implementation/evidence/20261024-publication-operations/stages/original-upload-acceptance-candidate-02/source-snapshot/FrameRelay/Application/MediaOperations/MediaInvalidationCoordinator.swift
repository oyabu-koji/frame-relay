import Foundation

actor MediaInvalidationCoordinator {
    private let store: any MediaOperationStorePort & OriginalStorePort
    private let identity: RegistrationStoreIdentity
    private let ordering: any OriginalOperationOrderingPort
    private let scopes: RenditionScopeRegistry
    private let external: any PublicationExternalTerminationPort
    private var running: Set<OriginalContent> = []
    private var pending: [InvalidationRecord: BackendStoreMutation] = [:]
    init(store: any MediaOperationStorePort & OriginalStorePort, identity: RegistrationStoreIdentity,
         ordering: any OriginalOperationOrderingPort, scopes: RenditionScopeRegistry, external: any PublicationExternalTerminationPort) {
        self.store = store; self.identity = identity; self.ordering = ordering; self.scopes = scopes; self.external = external
    }
    func invalidate(_ record: InvalidationRecord) async -> BackendOutcome<InvalidationAcknowledgement> {
        let original = record.rendition.original
        guard running.insert(original).inserted else { return .inProgress }
        defer { running.remove(original) }
        do {
            let snapshot = try await PublicationStoreBoundary.load(store, identity: identity)
            if let ack = snapshot.invalidations.first(where: { $0.record == record }) {
                guard PublicationStoreBoundary.exact(ack.record, record) else { return .unknown }
                guard await store.lookupInvalidation(ack) == .succeeded(record.id) else { return .unknown }
                return .succeeded(ack)
            }
            if let mutation = pending[record] {
                guard PublicationStoreBoundary.exact(mutation.change, BackendStoreChange.invalidation(record, .init(record: record))) else { return .unknown }
                return await resolve(mutation, record: record, lookupOnly: true)
            }
            guard snapshot.registrations.last(where: { $0.server.registration.destination == record.registration.destination })?.server.registration == record.registration else { return .unknown }
            guard let currentState = snapshot.confirmationStates.first(where: { $0.registration == record.registration && $0.current.original == original }),
                  PublicationStoreBoundary.exact(currentState.registration, record.registration),
                  PublicationStoreBoundary.exact(currentState.current, record.rendition) else { return .unknown }
            guard case .succeeded(let permit) = await ordering.reserveInvalidation(record), permit.record == record else { return .unknown }
            _ = try await scopes.stopAndReconcile(original: original, external: external)
            let current = try await PublicationStoreBoundary.load(store, identity: identity)
            let mutation = BackendStoreMutation(expectedRevision: current.revision, change: .invalidation(record, permit), expectedStoreIdentity: identity)
            pending[record] = mutation
            return await resolve(mutation, record: record, lookupOnly: false)
        } catch { return .unknown }
    }
    private func resolve(_ mutation: BackendStoreMutation, record: InvalidationRecord, lookupOnly: Bool) async -> BackendOutcome<InvalidationAcknowledgement> {
        let result = lookupOnly ? await PublicationStoreBoundary.reconcile(mutation, store: store) : await PublicationStoreBoundary.commit(mutation, store: store)
        guard case .committed(let receipt) = result, receipt.matches(record.key, revision: mutation.expectedRevision) else {
            if case .rejected = result { pending.removeValue(forKey: record) }
            return .unknown
        }
        let ack = InvalidationAcknowledgement(record: record, commit: receipt)
        guard await ordering.finishInvalidation(ack) == .succeeded(record.id) else { return .unknown }
        pending.removeValue(forKey: record)
        return .succeeded(ack)
    }
    /// Reservations survive crashes; only records already in the writer resume.
    func restore() async -> BackendOutcome<[InvalidationAcknowledgement]> {
        do {
            let snapshot = try await PublicationStoreBoundary.load(store, identity: identity)
            guard case .succeeded(let originals) = await store.loadOriginalState() else { return .unknown }
            var results = snapshot.invalidations
            for state in originals.logicalOriginals {
                guard let reservation = state.invalidation else { continue }
                guard case .succeeded(let ack) = await invalidate(reservation.record) else { return .unknown }
                results.append(ack)
            }
            return .succeeded(results)
        } catch { return .unknown }
    }
}
