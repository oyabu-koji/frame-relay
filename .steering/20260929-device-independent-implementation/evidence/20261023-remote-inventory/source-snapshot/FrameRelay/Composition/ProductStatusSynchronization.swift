import Foundation

/// App-lifetime owner of the metadata coordinators. Registration restoration
/// and constructing this container perform no request and create no intent.
actor ProductStatusSynchronization: StatusSynchronizationPort {
    typealias RemoteFactory = @Sendable (RegistrationConnection, any RegistrationAuthorizationPort,
        any MediaOperationStorePort, RegistrationStoreIdentity) -> any PublicationRemotePort
    private let store: any MediaOperationStorePort & OriginalStorePort
    private let access: ManagedOriginalAccess
    private let media: ProductMediaTermination
    private let credentials: any RegistrationAuthorizationPort
    private let admission: @MainActor @Sendable () -> Bool
    private let remoteFactory: RemoteFactory
    private var sessions: [Session] = []
    private var running = false

    init(store: any MediaOperationStorePort & OriginalStorePort, access: ManagedOriginalAccess,
         media: ProductMediaTermination, credentials: any RegistrationAuthorizationPort,
         admission: @escaping @MainActor @Sendable () -> Bool,
         remoteFactory: @escaping RemoteFactory = { connection, credentials, store, identity in
             URLSessionPublicationRemote(connection: connection, credentials: credentials, store: store, identity: identity)
         }) {
        self.store = store; self.access = access; self.media = media; self.credentials = credentials
        self.admission = admission; self.remoteFactory = remoteFactory
    }

    func synchronize(connection: RegistrationConnection, registration: DeviceRegistration) async -> StatusSynchronizationReport {
        guard !running else { return .init(phase: .busy) }
        running = true; defer { running = false }
        do {
            guard await admission() else { return .init(phase: .waitingForCapture) }
            guard case .loaded(let initial) = await store.load(), let identity = initial.storeIdentity,
                  PublicationStoreBoundary.exact(connection.destination, registration.server.registration.destination) else {
                return .init(phase: .unavailable)
            }
            let boundary = StatusSynchronizationRegistrationBoundary(store: store, identity: identity, registration: registration)
            _ = try await boundary.load()
            let coordinator: BackendStatusSynchronizationCoordinator
            if let existing = sessions.first(where: {
                $0.identity == identity && PublicationStoreBoundary.exact($0.registration, registration)
                    && PublicationStoreBoundary.exact($0.connection.destination, connection.destination)
                    && $0.connection.endpoint.origin.absoluteString.utf8.elementsEqual(connection.endpoint.origin.absoluteString.utf8)
            }) { coordinator = existing.coordinator }
            else {
                let external = ProductStatusInvalidationTermination(boundary: boundary, media: media, admission: admission)
                let invalidations = MediaInvalidationCoordinator(store: store, identity: identity, ordering: access,
                    scopes: media.scopes, external: external)
                coordinator = BackendStatusSynchronizationCoordinator(store: store, identity: identity, registration: registration,
                    remote: remoteFactory(connection, credentials, store, identity), invalidations: invalidations,
                    admission: admission, didInvalidate: { [media] ack in try await media.resume(after: ack) })
                sessions.append(.init(identity: identity, connection: connection, registration: registration, coordinator: coordinator))
            }
            let result = await coordinator.synchronize()
            _ = try await boundary.load()
            return result
        } catch { return .init(phase: .unavailable) }
    }

    private struct Session {
        let identity: RegistrationStoreIdentity
        let connection: RegistrationConnection
        let registration: DeviceRegistration
        let coordinator: BackendStatusSynchronizationCoordinator
    }
}

/// The current product external producer owns the original player. It cannot
/// attest to an old upload source or background SDK owner. Even a prepared
/// intent without an attached task is retained as unresolved for that video.
///
/// The coordinator commits reserveInvalidation BEFORE calling this wrapper.
/// That reservation fences acquire/acquireMedia and background prepared/resume
/// in the same writer. A copy already in flight owns a durable reader lease;
/// an attached task already owns a durable prepared intent. Neither can enter
/// unnoticed between this inventory and the final invalidation commit.
actor ProductStatusInvalidationTermination: PublicationExternalTerminationPort {
    private let boundary: StatusSynchronizationRegistrationBoundary
    private let media: ProductMediaTermination
    private let admission: @MainActor @Sendable () -> Bool
    init(boundary: StatusSynchronizationRegistrationBoundary, media: ProductMediaTermination,
         admission: @escaping @MainActor @Sendable () -> Bool) {
        self.boundary = boundary; self.media = media; self.admission = admission
    }
    private func check(_ original: OriginalContent) async throws {
        guard await admission(), !Task.isCancelled else { throw BackendContractError.unavailable }
        let snapshot = try await boundary.load()
        // Conservative equality here also refuses canonically equivalent but
        // byte-distinct historical owners; it never grants an identity match.
        guard !snapshot.backgroundTasks.contains(where: { $0.intent.context.target.original == original }),
              OriginalRemovalTransportHistory.neverStarted(original, backend: snapshot) else {
            throw BackendContractError.readersActive
        }
    }
    func stopAndObserve(original: OriginalContent, epoch: ReaderReconciliationEpoch) async throws {
        try await check(original)
        try await media.stopAndObserve(original: original, epoch: epoch)
        try await check(original)
    }
    func observeTerminal(original: OriginalContent, epoch: ReaderReconciliationEpoch) async throws -> EvidenceID {
        try await check(original)
        let result = try await media.observeTerminal(original: original, epoch: epoch)
        try await check(original)
        return result
    }
}
