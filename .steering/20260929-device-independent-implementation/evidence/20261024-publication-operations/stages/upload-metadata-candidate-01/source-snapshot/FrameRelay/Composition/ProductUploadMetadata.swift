import Foundation

/// Construction and local receipt reconciliation do not consult credentials.
/// A remote and its current-store connection are resolved only for an explicit
/// coordinator dispatch, or for the existing known-session status-sync pass.
actor ProductUploadMetadata: UploadMetadataPort {
    typealias ConnectionRead = @Sendable (RegistrationStoreIdentity) async throws -> RegistrationConnection?
    typealias RemoteFactory = @Sendable (RegistrationConnection, any RegistrationAuthorizationPort,
        any MediaOperationStorePort) -> any UploadMetadataRemotePort
    private let coordinator: UploadMetadataCoordinator

    init(store: any MediaOperationStorePort, credentials: any RegistrationAuthorizationPort,
         connection: @escaping ConnectionRead, admission: @escaping @MainActor @Sendable () -> Bool,
         didChange: @escaping @Sendable () async -> Void = {},
         remoteFactory: @escaping RemoteFactory = { URLSessionUploadMetadataRemote(connection: $0, credentials: $1, store: $2) }) {
        let remote = ProductUploadMetadataRemote(store: store, credentials: credentials, connection: connection, factory: remoteFactory)
        coordinator = .init(store: store, remote: remote, admission: admission, didChange: didChange)
    }
    func refresh(_ request: UploadMetadataRequest) async -> UploadMetadataResult { await coordinator.refresh(request) }
    func refreshKnownSession(_ request: UploadMetadataRequest) async -> UploadMetadataResult { await coordinator.refreshKnownSession(request) }
    func reconcilePending(_ request: UploadMetadataRequest) async -> UploadMetadataResult { await coordinator.reconcilePending(request) }
}

private actor ProductUploadMetadataRemote: UploadMetadataRemotePort {
    private struct Session {
        let identity: RegistrationStoreIdentity
        let registration: DeviceRegistration
        let connection: RegistrationConnection
        let remote: any UploadMetadataRemotePort
    }
    private let store: any MediaOperationStorePort
    private let credentials: any RegistrationAuthorizationPort
    private let connection: ProductUploadMetadata.ConnectionRead
    private let factory: ProductUploadMetadata.RemoteFactory
    private var sessions: [Session] = []

    init(store: any MediaOperationStorePort, credentials: any RegistrationAuthorizationPort,
         connection: @escaping ProductUploadMetadata.ConnectionRead, factory: @escaping ProductUploadMetadata.RemoteFactory) {
        self.store = store; self.credentials = credentials; self.connection = connection; self.factory = factory
    }
    func create(_ query: CommittedUploadMetadataQuery) async -> BackendOutcome<UploadMetadataResponse> { await perform(query, create: true) }
    func lookup(_ query: CommittedUploadMetadataQuery) async -> BackendOutcome<UploadMetadataResponse> { await perform(query, create: false) }
    private func perform(_ query: CommittedUploadMetadataQuery, create: Bool) async -> BackendOutcome<UploadMetadataResponse> {
        do {
            let request = query.query.request
            _ = try await UploadMetadataScope.dispatch(store, query: query)
            guard let connection = try await self.connection(request.storeIdentity),
                  UploadMetadataValidation.exact(connection.destination, request.registration.server.registration.destination) else {
                return .failed(.authenticationRequired)
            }
            _ = try await UploadMetadataScope.dispatch(store, query: query)
            let remote: any UploadMetadataRemotePort
            if let session = sessions.first(where: {
                $0.identity == request.storeIdentity && UploadMetadataValidation.exact($0.registration, request.registration)
                    && UploadMetadataValidation.exact($0.connection.destination, connection.destination)
                    && $0.connection.endpoint.origin.absoluteString.utf8.elementsEqual(connection.endpoint.origin.absoluteString.utf8)
            }) { remote = session.remote }
            else {
                remote = factory(connection, credentials, store)
                sessions.append(.init(identity: request.storeIdentity, registration: request.registration, connection: connection, remote: remote))
            }
            return create ? await remote.create(query) : await remote.lookup(query)
        } catch is RegistrationAccessError { return .failed(.authenticationRequired) }
        catch { return .unknown }
    }
}
