import Foundation

/// One explicit page per call. It has no media, confirmation, ACK or deletion port.
actor RemoteInventoryCoordinator {
    typealias RemoteFactory = @Sendable (RegistrationConnection, DeviceRegistration,
        RegistrationStoreIdentity) -> any RemoteInventoryRemotePort
    private let store: any MediaOperationStorePort
    private let factory: RemoteFactory
    private let admission: @MainActor @Sendable () -> Bool
    private var running = false
    private var session: Session?

    init(store: any MediaOperationStorePort, admission: @escaping @MainActor @Sendable () -> Bool = { true },
         remoteFactory: @escaping RemoteFactory) {
        self.store = store; self.factory = remoteFactory; self.admission = admission
    }

    func discover(connection: RegistrationConnection, registration: DeviceRegistration) async -> RemoteInventoryReport {
        guard !running else { return .init(phase: .busy) }
        running = true; defer { running = false }
        do {
            guard await admission(), !Task.isCancelled else { return .init(phase: .waitingForCapture) }
            guard case .loaded(let initial) = await store.load(), let identity = initial.storeIdentity,
                  connection.destination == registration.server.registration.destination else {
                return .init(phase: .unavailable)
            }
            let boundary = StatusSynchronizationRegistrationBoundary(store: store, identity: identity, registration: registration)
            _ = try await boundary.load()
            let active: Session
            if let session, session.identity == identity,
               PublicationStoreBoundary.exact(session.registration, registration),
               session.connection.endpoint.origin.absoluteString.utf8.elementsEqual(connection.endpoint.origin.absoluteString.utf8),
               session.connection.destination == connection.destination {
                active = session
            } else {
                active = Session(identity: identity, connection: connection, registration: registration,
                    remote: factory(connection, registration, identity))
                session = active
            }
            if let pending = active.pending { return try await reconcile(pending, active: active, boundary: boundary) }
            if active.after == nil { active.seenCursors.removeAll() }
            let after = active.after
            let response = await active.remote.page(registration: registration.server.registration, after: after)
            _ = try await boundary.load()
            guard await admission(), !Task.isCancelled,
                  case .succeeded(let page) = response else { return .init(phase: .unavailable, hasMore: after != nil) }
            try RemoteInventoryValidation.page(page)
            guard page.registration == registration.server.registration,
                  RemoteInventoryValidation.same(page.requestCursor, after),
                  page.nextCursor.map({ !active.seenCursors.contains($0) }) ?? true else {
                return .init(phase: .unavailable, hasMore: after != nil)
            }
            let latest = try await boundary.load()
            let observation = RemoteInventoryObservation(command: .init(rawValue: UUID().uuidString.lowercased()),
                storeIdentity: identity, registration: registration.server.registration,
                requestCursor: after, page: page)
            let mutation = BackendStoreMutation(expectedRevision: latest.revision, change: .remoteInventory(observation),
                expectedStoreIdentity: identity)
            active.pending = mutation
            let result = await store.commit(mutation)
            _ = try await boundary.load()
            return try await finish(result, mutation: mutation, active: active, boundary: boundary)
        } catch { return .init(phase: .unavailable, hasMore: session?.after != nil) }
    }

    private func reconcile(_ mutation: BackendStoreMutation, active: Session,
                           boundary: StatusSynchronizationRegistrationBoundary) async throws -> RemoteInventoryReport {
        _ = try await boundary.load()
        let result = await store.lookupCommit(mutation)
        _ = try await boundary.load()
        return try await finish(result, mutation: mutation, active: active, boundary: boundary)
    }
    private func finish(_ result: BackendCommitResult, mutation: BackendStoreMutation, active: Session,
                        boundary: StatusSynchronizationRegistrationBoundary) async throws -> RemoteInventoryReport {
        let confirmed = try await boundary.load()
        switch result {
        case .committed(let receipt):
            guard receipt.matches(mutation.change.key, revision: mutation.expectedRevision),
                  PublicationStoreBoundary.exact(receipt.key, mutation.change.key),
                  case .remoteInventory(let observation) = mutation.change,
                  confirmed.remoteInventory.contains(where: {
                      $0.isCommitted && PublicationStoreBoundary.exact($0.commit, receipt) && $0.observation == observation
                  }) else { return .init(phase: .reconciliationRequired, hasMore: active.after != nil) }
            if let cursor = observation.requestCursor { active.seenCursors.insert(cursor) }
            active.after = observation.page.nextCursor
            active.pending = nil
            return .init(phase: .recorded, receivedCount: observation.page.originals.count, hasMore: active.after != nil)
        case .rejected:
            active.pending = nil
            return .init(phase: .unavailable, hasMore: active.after != nil)
        case .unknown, .unavailable:
            // Do not rebase an uncertain page or fetch a newer page before its
            // exact mutation can be looked up. Durable rows remain independent.
            return .init(phase: .reconciliationRequired, hasMore: active.after != nil)
        }
    }

    nonisolated private final class Session {
        let identity: RegistrationStoreIdentity
        let connection: RegistrationConnection
        let registration: DeviceRegistration
        let remote: any RemoteInventoryRemotePort
        var after: String?
        var seenCursors = Set<String>()
        var pending: BackendStoreMutation?
        init(identity: RegistrationStoreIdentity, connection: RegistrationConnection,
             registration: DeviceRegistration, remote: any RemoteInventoryRemotePort) {
            self.identity = identity; self.connection = connection; self.registration = registration; self.remote = remote
        }
    }
}
extension RemoteInventoryCoordinator: RemoteInventoryPort {}
