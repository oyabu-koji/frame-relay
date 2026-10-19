import Foundation
import Security

/// Immutable records. A duplicate is read and compared; it is never replaced.
/// The writer's registration intent remains the logical operation authority.
actor KeychainRegistrationVault: RegistrationVaultPort, RegistrationAuthorizationPort {
    static let productService = "jp.oyabu.FrameRelay.registration.v1"
    private let service: String
    private let probeEndpoint: RegistrationEndpoint?

    init(service: String = KeychainRegistrationVault.productService) {
        self.service = service
        probeEndpoint = nil
    }
    #if DEBUG && targetEnvironment(simulator)
    init(isolatedTestService: String, probeEndpoint: RegistrationEndpoint) throws {
        guard isolatedTestService.hasPrefix("FrameRelay.registration.tests."),
              isolatedTestService.count > "FrameRelay.registration.tests.".count else {
            throw RegistrationAccessError.invalidConfiguration
        }
        service = isolatedTestService
        self.probeEndpoint = probeEndpoint
    }
    #endif

    func connection() throws -> RegistrationConnection? {
        guard let data = try read("connection") else { return nil }
        let value: SavedConnection = try decode(data)
        guard value.version == 1, Self.validBearer(value.bearer) else {
            throw RegistrationAccessError.corruptCredential
        }
        let endpoint: RegistrationEndpoint
        if let probeEndpoint, value.origin == probeEndpoint.origin.absoluteString { endpoint = probeEndpoint }
        else { endpoint = try RegistrationEndpoint(httpsOrigin: value.origin) }
        return try RegistrationConnection(endpoint: endpoint, destination: .init(rawValue: value.destination))
    }

    func saveConnection(_ connection: RegistrationConnection, bearer: String) throws {
        guard Self.validBearer(bearer) else { throw RegistrationAccessError.invalidConfiguration }
        if connection.endpoint.origin.scheme != "https", connection.endpoint != probeEndpoint {
            throw RegistrationAccessError.invalidConfiguration
        }
        let record = SavedConnection(version: 1, origin: connection.endpoint.origin.absoluteString,
                                     destination: connection.destination.rawValue, bearer: bearer)
        let data = try JSONEncoder().encode(record)
        let saved = try addOrRead(data, account: "connection")
        let existing: SavedConnection = try decode(saved)
        guard existing == record else { throw RegistrationAccessError.credentialConflict }
    }

    func prepareIntent(for destination: DestinationIdentity) throws -> RegistrationIntent {
        guard try connection()?.destination == destination else { throw RegistrationAccessError.credentialConflict }
        let account = "initial." + destination.rawValue
        if let saved = try read(account) { return try credential(saved, destination: destination).intent }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw RegistrationAccessError.credentialUnavailable
        }
        let secret = bytes.map { String(format: "%02x", $0) }.joined()
        let record = SavedCredential(version: 1, destination: destination.rawValue,
            operation: UUID().uuidString.lowercased(), secret: secret)
        // An overlapping process may have won the atomic add. Reuse its exact reference.
        let saved = try addOrRead(JSONEncoder().encode(record), account: account)
        return try credential(saved, destination: destination).intent
    }

    func requireCredential(for intent: RegistrationIntent) throws {
        _ = try matchingCredential(intent)
    }

    func authorization(for connection: RegistrationConnection, intent: RegistrationIntent?) throws -> RegistrationAuthorization {
        guard try self.connection() == connection, let data = try read("connection") else {
            throw RegistrationAccessError.credentialConflict
        }
        let saved: SavedConnection = try decode(data)
        let secret: String?
        if let intent {
            guard intent.destination == connection.destination else { throw RegistrationAccessError.credentialConflict }
            secret = try matchingCredential(intent).secret
        } else { secret = nil }
        return .init(bearer: saved.bearer, secret: secret)
    }

    private func matchingCredential(_ intent: RegistrationIntent) throws -> SavedCredential {
        guard let data = try read("initial." + intent.destination.rawValue) else {
            throw RegistrationAccessError.credentialMissing
        }
        let saved = try credential(data, destination: intent.destination)
        guard saved.intent == intent else { throw RegistrationAccessError.credentialConflict }
        return saved
    }

    private func credential(_ data: Data, destination: DestinationIdentity) throws -> SavedCredential {
        let record: SavedCredential = try decode(data)
        guard record.version == 1, record.destination == destination.rawValue,
              RegistrationWireIdentity.isCanonical(record.operation),
              record.secret.utf8.count == 64, record.secret.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw RegistrationAccessError.corruptCredential
        }
        return record
    }

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false,
         kSecUseDataProtectionKeychain as String: true]
    }
    private func read(_ account: String) throws -> Data? {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw RegistrationAccessError.credentialUnavailable }
        guard let data = item as? Data, !data.isEmpty, data.count <= 16384 else {
            throw RegistrationAccessError.corruptCredential
        }
        return data
    }
    private func addOrRead(_ data: Data, account: String) throws -> Data {
        var query = query(account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw RegistrationAccessError.credentialUnavailable
        }
        guard let saved = try read(account) else { throw RegistrationAccessError.credentialUnavailable }
        return saved
    }
    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw RegistrationAccessError.corruptCredential }
    }
    private static func validBearer(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 4096 && value.utf8.allSatisfy { (33...126).contains($0) }
    }

    nonisolated private struct SavedConnection: Codable, Equatable {
        let version: Int
        let origin: String
        let destination: String
        let bearer: String
    }
    nonisolated private struct SavedCredential: Codable {
        let version: Int
        let destination: String
        let operation: String
        let secret: String
        var intent: RegistrationIntent {
            .init(operation: .init(rawValue: operation), destination: .init(rawValue: destination))
        }
    }
}
