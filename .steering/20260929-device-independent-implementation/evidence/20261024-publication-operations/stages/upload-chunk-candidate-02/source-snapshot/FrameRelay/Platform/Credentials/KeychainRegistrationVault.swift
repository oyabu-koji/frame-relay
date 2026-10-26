import Foundation
import Security

/// Immutable records. A duplicate is read and compared; it is never replaced.
/// The writer's registration intent remains the logical operation authority.
actor KeychainRegistrationVault {
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
        guard let data = try read(connectionAccount(storeIdentity)) else { return nil }
        let value: SavedConnection = try decode(data)
        try requireBinding(version: value.version, actual: value.storeIdentity, expected: storeIdentity)
        return try checkedConnection(value)
    }

    func saveConnection(_ connection: RegistrationConnection, bearer: String, storeIdentity: RegistrationStoreIdentity) throws {
        guard Self.validBearer(bearer) else { throw RegistrationAccessError.invalidConfiguration }
        if connection.endpoint.origin.scheme != "https", connection.endpoint != probeEndpoint {
            throw RegistrationAccessError.invalidConfiguration
        }
        let record = SavedConnection(version: 2, storeIdentity: storeIdentity, origin: connection.endpoint.origin.absoluteString,
                                     destination: connection.destination.rawValue, bearer: bearer)
        let data = try JSONEncoder().encode(record)
        let saved = try addOrRead(data, account: connectionAccount(storeIdentity))
        let existing: SavedConnection = try decode(saved)
        guard existing == record else { throw RegistrationAccessError.credentialConflict }
    }

    func permitsNewStoreRegistration(storeIdentity: RegistrationStoreIdentity?) async throws -> Bool {
        try permitsNewStoreRegistrationNow(storeIdentity: storeIdentity)
    }

    private func permitsNewStoreRegistrationNow(storeIdentity: RegistrationStoreIdentity?) throws -> Bool {
        if let storeIdentity, try read(namespacedConnection(storeIdentity)) != nil { return false }
        guard let data = try read("connection") else { return false }
        let value: SavedConnection = try decode(data)
        guard value.version != 1 else { throw RegistrationAccessError.credentialConflict }
        guard value.version == 2, let oldIdentity = value.storeIdentity else { throw RegistrationAccessError.corruptCredential }
        _ = try checkedConnection(value)
        guard oldIdentity != storeIdentity else { return false }
        if let storeIdentity, try hasNamespacedInitial(storeIdentity) { return false }
        if let initial = try read("initial." + value.destination) {
            _ = try credential(initial, destination: .init(rawValue: value.destination), storeIdentity: oldIdentity)
        }
        // Confirmed Keychain absence is the existing saveConnection-before-
        // prepareIntent state. It establishes only Keychain absence; no remote
        // outcome is inferred and no secret is adopted.
        return true
    }

    func saveNewStoreConnection(_ connection: RegistrationConnection, bearer: String,
                                storeIdentity: RegistrationStoreIdentity) async throws {
        try saveNewStoreConnectionNow(connection, bearer: bearer, storeIdentity: storeIdentity)
    }

    private func saveNewStoreConnectionNow(_ connection: RegistrationConnection, bearer: String,
                                         storeIdentity: RegistrationStoreIdentity) throws {
        guard Self.validBearer(bearer), connection.endpoint.origin.scheme == "https" || connection.endpoint == probeEndpoint else {
            throw RegistrationAccessError.invalidConfiguration
        }
        let record = SavedConnection(version: 2, storeIdentity: storeIdentity, origin: connection.endpoint.origin.absoluteString,
                                     destination: connection.destination.rawValue, bearer: bearer)
        let account = namespacedConnection(storeIdentity)
        if let existing = try read(account) {
            let value: SavedConnection = try decode(existing)
            try requireBinding(version: value.version, actual: value.storeIdentity, expected: storeIdentity)
            _ = try checkedConnection(value)
            guard value == record else { throw RegistrationAccessError.credentialConflict }
            return
        }
        guard try permitsNewStoreRegistrationNow(storeIdentity: storeIdentity) else {
            // An overlapping accepted action may have completed the atomic add
            // between our first read and the eligibility read. Reuse only its
            // identical connection; an orphaned initial is never adopted.
            if let data = try read(account) {
                let existing: SavedConnection = try decode(data)
                try requireBinding(version: existing.version, actual: existing.storeIdentity, expected: storeIdentity)
                _ = try checkedConnection(existing)
                if existing == record { return }
            }
            throw RegistrationAccessError.credentialConflict
        }
        let saved: SavedConnection = try decode(addOrRead(JSONEncoder().encode(record), account: account))
        guard saved == record else { throw RegistrationAccessError.credentialConflict }
    }

    func prepareIntent(for destination: DestinationIdentity, storeIdentity: RegistrationStoreIdentity) throws -> RegistrationIntent {
        guard try connection(storeIdentity: storeIdentity)?.destination == destination else { throw RegistrationAccessError.credentialConflict }
        let account = try credentialAccount(destination, storeIdentity: storeIdentity)
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
        guard try self.connection(storeIdentity: storeIdentity) == connection,
              let data = try read(connectionAccount(storeIdentity)) else {
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
        guard let data = try read(credentialAccount(intent.destination, storeIdentity: storeIdentity)) else {
            throw RegistrationAccessError.credentialMissing
        }
        let saved = try credential(data, destination: intent.destination, storeIdentity: storeIdentity)
        guard saved.intent == intent else { throw RegistrationAccessError.credentialConflict }
        return saved
    }

    private func namespacedConnection(_ identity: RegistrationStoreIdentity) -> String {
        "store." + identity.rawValue.uuidString.lowercased() + ".connection"
    }
    /// No secret data is requested. A lost current connection plus any current
    /// UUID's initial account is an interrupted/unknown current binding, even
    /// when its destination differs from the new input or its bytes are corrupt.
    private func hasNamespacedInitial(_ identity: RegistrationStoreIdentity) throws -> Bool {
        var attributes = query("")
        attributes.removeValue(forKey: kSecAttrAccount as String)
        attributes[kSecReturnAttributes as String] = true
        attributes[kSecReturnData as String] = false
        attributes[kSecMatchLimit as String] = kSecMatchLimitAll
        var found: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &found)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw RegistrationAccessError.credentialUnavailable }
        guard let items = found as? [[String: Any]] else { throw RegistrationAccessError.corruptCredential }
        let prefix = "store." + identity.rawValue.uuidString.lowercased() + ".initial."
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String else { throw RegistrationAccessError.corruptCredential }
            if account.hasPrefix(prefix) { return true }
        }
        return false
    }
    private func connectionAccount(_ identity: RegistrationStoreIdentity?) throws -> String {
        if let identity {
            let account = namespacedConnection(identity)
            // Presence chooses this namespace even when decoding later fails;
            // corrupt current records never fall back to a foreign global one.
            if try read(account) != nil { return account }
        }
        return "connection"
    }
    private func credentialAccount(_ destination: DestinationIdentity, storeIdentity: RegistrationStoreIdentity) throws -> String {
        let connection = try connectionAccount(storeIdentity)
        if connection == "connection" { return "initial." + destination.rawValue }
        return "store." + storeIdentity.rawValue.uuidString.lowercased() + ".initial." + destination.rawValue
    }
    private func checkedConnection(_ value: SavedConnection) throws -> RegistrationConnection {
        guard Self.validBearer(value.bearer) else { throw RegistrationAccessError.corruptCredential }
        let endpoint: RegistrationEndpoint
        if let probeEndpoint, value.origin == probeEndpoint.origin.absoluteString { endpoint = probeEndpoint }
        else { endpoint = try RegistrationEndpoint(httpsOrigin: value.origin) }
        return try RegistrationConnection(endpoint: endpoint, destination: .init(rawValue: value.destination))
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
extension KeychainRegistrationVault: RegistrationVaultPort, RegistrationAuthorizationPort {}
