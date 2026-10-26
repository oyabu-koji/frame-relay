import Foundation

/// An exact origin, with no path, user information, query or fragment.
/// Loopback HTTP is admitted only by the explicit Simulator probe constructor.
nonisolated struct RegistrationEndpoint: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let origin: URL
    var description: String { "RegistrationEndpoint(redacted)" }
    var debugDescription: String { description }
    private init(_ value: String, permitsProbe: Bool) throws {
        guard value.utf8.count <= 2048, let parts = URLComponents(string: value),
              let url = parts.url, let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty, !value.contains("%"), !value.contains("\\"),
              !value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }),
              parts.port == nil || (1...65535).contains(parts.port!),
              parts.scheme == "https" || (permitsProbe && parts.scheme == "http" && host == "127.0.0.1"),
              url.absoluteString == value else { throw RegistrationAccessError.invalidConfiguration }
        origin = url
    }
    init(httpsOrigin value: String) throws { try self.init(value, permitsProbe: false) }
    #if DEBUG && targetEnvironment(simulator)
    static func isolatedLoopbackProbe(_ value: String) throws -> Self {
        guard URLComponents(string: value)?.host == "127.0.0.1" else {
            throw RegistrationAccessError.invalidConfiguration
        }
        return try Self(value, permitsProbe: true)
    }
    #endif

    func url(path: String, destination: DestinationIdentity? = nil) -> URL {
        var parts = URLComponents(url: origin, resolvingAgainstBaseURL: false)!
        parts.path = "/frame-relay/v1/" + path
        if let destination { parts.queryItems = [.init(name: "destination_id", value: destination.rawValue)] }
        return parts.url!
    }
}

nonisolated struct RegistrationConnection: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let endpoint: RegistrationEndpoint
    let destination: DestinationIdentity
    var description: String { "RegistrationConnection(redacted)" }
    var debugDescription: String { description }
    init(endpoint: RegistrationEndpoint, destination: DestinationIdentity) throws {
        guard RegistrationWireIdentity.isCanonical(destination.rawValue) else {
            throw RegistrationAccessError.invalidConfiguration
        }
        self.endpoint = endpoint
        self.destination = destination
    }
}

nonisolated enum RegistrationAccessError: Error, Equatable, Sendable {
    case invalidConfiguration, credentialMissing, credentialUnavailable, credentialConflict, corruptCredential
}

/// Only Keychain adapters and the transport see these transient header values.
/// Never Codable, store evidence, diagnostic values or URL components.
nonisolated struct RegistrationAuthorization: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let bearer: String
    let secret: String?
    var description: String { "RegistrationAuthorization(redacted)" }
    var debugDescription: String { description }
}

nonisolated protocol RegistrationVaultPort: Sendable {
    func connection(storeIdentity: RegistrationStoreIdentity?) async throws -> RegistrationConnection?
    func saveConnection(_ connection: RegistrationConnection, bearer: String, storeIdentity: RegistrationStoreIdentity) async throws
    /// Persist credential material before returning the operation reference. This is not an intent commit.
    func prepareIntent(for destination: DestinationIdentity, storeIdentity: RegistrationStoreIdentity) async throws -> RegistrationIntent
    func requireCredential(for intent: RegistrationIntent, storeIdentity: RegistrationStoreIdentity) async throws
    /// Read-only eligibility for a separate explicit operation. nil identity is
    /// a display preflight only; writes require the durable current-store UUID.
    func permitsNewStoreRegistration(storeIdentity: RegistrationStoreIdentity?) async throws -> Bool
    func saveNewStoreConnection(_ connection: RegistrationConnection, bearer: String,
                               storeIdentity: RegistrationStoreIdentity) async throws
}

nonisolated extension RegistrationVaultPort {
    func permitsNewStoreRegistration(storeIdentity: RegistrationStoreIdentity?) async throws -> Bool { false }
    func saveNewStoreConnection(_ connection: RegistrationConnection, bearer: String,
                               storeIdentity: RegistrationStoreIdentity) async throws {
        throw RegistrationAccessError.credentialConflict
    }
}

nonisolated protocol RegistrationAuthorizationPort: Sendable {
    func authorization(for connection: RegistrationConnection, intent: RegistrationIntent?, storeIdentity: RegistrationStoreIdentity) async throws -> RegistrationAuthorization
}

nonisolated protocol RegistrationRemotePort: Sendable {
    /// Checks a user-entered connection before retaining it. Never creates an intent.
    func checkConnection(_ connection: RegistrationConnection, bearer: String) async -> BackendOutcome<BackendCapabilities>
    func discover(_ connection: RegistrationConnection, storeIdentity: RegistrationStoreIdentity) async -> BackendOutcome<BackendCapabilities>
    func register(_ command: RegistrationCommand, at connection: RegistrationConnection, storeIdentity: RegistrationStoreIdentity) async -> BackendOutcome<RegistrationServerReceipt>
    func lookup(_ intent: RegistrationIntent, at connection: RegistrationConnection, storeIdentity: RegistrationStoreIdentity) async -> BackendOutcome<RegistrationServerReceipt>
}

nonisolated enum RegistrationWireIdentity {
    static func isCanonical(_ value: String) -> Bool {
        value.utf8.count == 36 && UUID(uuidString: value)?.uuidString.lowercased() == value
    }
}

nonisolated enum RegistrationState: Equatable, Sendable {
    case needsConnection
    case needsRegistration(RegistrationConnection)
    case registered(RegistrationConnection, DeviceRegistration)
    case pending(RegistrationConnection, RegistrationIntent)
    case unavailable(RegistrationIssue)
}

nonisolated enum RegistrationIssue: Equatable, Sendable {
    case configuration, credentials, credentialConflict, storage, identity, authentication, connection, protocolMismatch, busy
}
