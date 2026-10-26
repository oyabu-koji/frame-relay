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

    func connection(storeIdentity: RegistrationStoreIdentity?) throws -> RegistrationConnection? {
        guard let data = try read("connection") else { return nil }
        let value: SavedConnection = try decode(data)
        try requireBinding(version: value.version, actual: value.storeIdentity, expected: storeIdentity)
        guard Self.validBearer(value.bearer) else {
            throw RegistrationAccessError.corruptCredential
        }
        let endpoint: RegistrationEndpoint
        if let probeEndpoint, value.origin == probeEndpoint.origin.absoluteString { endpoint = probeEndpoint }
        else { endpoint = try RegistrationEndpoint(httpsOrigin: value.origin) }
        return try RegistrationConnection(endpoint: endpoint, destination: .init(rawValue: value.destination))
    }

    func saveConnection(_ connection: RegistrationConnection, bearer: String, storeIdentity: RegistrationStoreIdentity) throws {
        guard Self.validBearer(bearer) else { throw RegistrationAccessError.invalidConfiguration }
        if connection.endpoint.origin.scheme != "https", connection.endpoint != probeEndpoint {
            throw RegistrationAccessError.invalidConfiguration
        }
        let record = SavedConnection(version: 2, storeIdentity: storeIdentity, origin: connection.endpoint.origin.absoluteString,
                                     destination: connection.destination.rawValue, bearer: bearer)
        let data = try JSONEncoder().encode(record)
        let saved = try addOrRead(data, account: "connection")
        let existing: SavedConnection = try decode(saved)
        guard existing == record else { throw RegistrationAccessError.credentialConflict }
    }

    func prepareIntent(for destination: DestinationIdentity, storeIdentity: RegistrationStoreIdentity) throws -> RegistrationIntent {
        guard try connection(storeIdentity: storeIdentity)?.destination == destination else { throw RegistrationAccessError.credentialConflict }
        let account = "initial." + destination.rawValue
        if let saved = try read(account) { return try credential(saved, destination: destination, storeIdentity: storeIdentity).intent }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw RegistrationAccessError.credentialUnavailable
        }
        let secret = bytes.map { String(format: "%02x", $0) }.joined()
        let record = SavedCredential(version: 2, storeIdentity: storeIdentity, destination: destination.rawValue,
            operation: UUID().uuidString.lowercased(), secret: secret)
        // An overlapping process may have won the atomic add. Reuse its exact reference.
        let saved = try addOrRead(JSONEncoder().encode(record), account: account)
        return try credential(saved, destination: destination, storeIdentity: storeIdentity).intent
    }

    func requireCredential(for intent: RegistrationIntent, storeIdentity: RegistrationStoreIdentity) throws {
        _ = try matchingCredential(intent, storeIdentity: storeIdentity)
    }

    func authorization(for connection: RegistrationConnection, intent: RegistrationIntent?, storeIdentity: RegistrationStoreIdentity) throws -> RegistrationAuthorization {
        guard try self.connection(storeIdentity: storeIdentity) == connection, let data = try read("connection") else {
            throw RegistrationAccessError.credentialConflict
        }
        let saved: SavedConnection = try decode(data)
        try requireBinding(version: saved.version, actual: saved.storeIdentity, expected: storeIdentity)
        let secret: String?
        if let intent {
            guard intent.destination == connection.destination else { throw RegistrationAccessError.credentialConflict }
            secret = try matchingCredential(intent, storeIdentity: storeIdentity).secret
        } else { secret = nil }
        return .init(bearer: saved.bearer, secret: secret)
    }

    private func matchingCredential(_ intent: RegistrationIntent, storeIdentity: RegistrationStoreIdentity) throws -> SavedCredential {
        guard let data = try read("initial." + intent.destination.rawValue) else {
            throw RegistrationAccessError.credentialMissing
        }
        let saved = try credential(data, destination: intent.destination, storeIdentity: storeIdentity)
        guard saved.intent == intent else { throw RegistrationAccessError.credentialConflict }
        return saved
    }

    private func credential(_ data: Data, destination: DestinationIdentity, storeIdentity: RegistrationStoreIdentity) throws -> SavedCredential {
        let record: SavedCredential = try decode(data)
        try requireBinding(version: record.version, actual: record.storeIdentity, expected: storeIdentity)
        guard record.destination == destination.rawValue,
              RegistrationWireIdentity.isCanonical(record.operation),
              record.secret.utf8.count == 64, record.secret.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw RegistrationAccessError.corruptCredential
        }
        return record
    }

    private func requireBinding(version: Int, actual: RegistrationStoreIdentity?,
                                expected: RegistrationStoreIdentity?) throws {
        // Legacy v1 credentials are preserved, never adopted by a new or migrated store.
        guard version != 1 else { throw RegistrationAccessError.credentialConflict }
        guard version == 2, let actual else { throw RegistrationAccessError.corruptCredential }
        guard actual == expected else { throw RegistrationAccessError.credentialConflict }
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
        let storeIdentity: RegistrationStoreIdentity?
        let origin: String
        let destination: String
        let bearer: String
    }
    nonisolated private struct SavedCredential: Codable {
        let version: Int
        let storeIdentity: RegistrationStoreIdentity?
        let destination: String
        let operation: String
        let secret: String
        var intent: RegistrationIntent {
            .init(operation: .init(rawValue: operation), destination: .init(rawValue: destination))
        }
    }
}
