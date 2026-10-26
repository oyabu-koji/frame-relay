import Foundation

/// Authenticated, bounded metadata only. It never constructs a media request.
actor URLSessionRemoteInventoryRemote {
    private let connection: RegistrationConnection
    private let credentials: any RegistrationAuthorizationPort
    private let boundary: StatusSynchronizationRegistrationBoundary

    init(connection: RegistrationConnection, credentials: any RegistrationAuthorizationPort,
         store: any MediaOperationStorePort, identity: RegistrationStoreIdentity, registration: DeviceRegistration) {
        self.connection = connection; self.credentials = credentials
        boundary = .init(store: store, identity: identity, registration: registration)
    }

    func page(registration: RegistrationIdentity, after: String?) async -> BackendOutcome<RemoteInventoryPage> {
        do {
            guard PublicationStoreBoundary.exact(registration, boundary.registration.server.registration), !Task.isCancelled else {
                return .failed(.rejected)
            }
            let url = try RemoteInventoryWire.url(connection: connection, registration: registration, after: after)
            let headers = try await authorization()
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15)
            request.httpMethod = "GET"; request.httpShouldHandleCookies = false
            for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
            _ = try await boundary.load()
            let response = try await PublicationURLSessionRequest.perform(request)
            // Keychain is checked again as well as the current journal identity.
            // A changed connection cannot publish a stale page into this store.
            let current = try await authorization()
            guard current == headers, !Task.isCancelled else { return .unknown }
            guard response.status == 200 else {
                return response.status == 401 || response.status == 403 ? .failed(.authenticationRequired) : .unknown
            }
            return .succeeded(try RemoteInventoryWire.page(response.data, registration: registration, after: after))
        } catch is RegistrationAccessError { return .failed(.authenticationRequired) }
        catch { return .unknown }
    }

    private func authorization() async throws -> [String: String] {
        _ = try await boundary.load()
        let material = try await credentials.authorization(for: connection,
            intent: boundary.registration.server.intent, storeIdentity: boundary.identity)
        _ = try await boundary.load()
        guard connection.destination == boundary.registration.server.registration.destination,
              let secret = material.secret, !secret.isEmpty, secret.utf8.count <= 4096,
              secret.utf8.allSatisfy({ (33...126).contains($0) }),
              !material.bearer.isEmpty, material.bearer.utf8.count <= 4096,
              material.bearer.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw RegistrationAccessError.credentialConflict
        }
        return ["Authorization": "Bearer " + material.bearer, "X-FrameRelay-Registration-Secret": secret]
    }
}
extension URLSessionRemoteInventoryRemote: RemoteInventoryRemotePort {}
