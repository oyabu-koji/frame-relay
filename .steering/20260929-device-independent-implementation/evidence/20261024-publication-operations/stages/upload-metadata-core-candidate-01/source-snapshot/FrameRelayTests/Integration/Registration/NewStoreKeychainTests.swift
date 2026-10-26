import Foundation
import Security
import Testing
@testable import FrameRelay

struct NewStoreKeychainTests {
    @Test func concreteAndExistentialNewMethodsUseTheSameRealNamespaceAndEligibility() async throws {
        let f = try await NewRegistrationKeychain.make()
        let current = RegistrationStoreIdentity(rawValue: UUID())
        defer { f.cleanup([current]) }
        let concrete = try f.keychain.vault()
        let erased: any RegistrationVaultPort = concrete
        for identity: RegistrationStoreIdentity? in [nil, current] {
            let direct = try await concrete.permitsNewStoreRegistration(storeIdentity: identity)
            let throughPort = try await erased.permitsNewStoreRegistration(storeIdentity: identity)
            #expect(direct && throughPort && direct == throughPort)
        }
        try await concrete.saveNewStoreConnection(f.keychain.connection, bearer: "new-fixture-bearer", storeIdentity: current)
        let initialBytes = try f.keychain.bytes(newRegistrationConnectionAccount(current))
        #expect(initialBytes != nil)
        try await erased.saveNewStoreConnection(f.keychain.connection, bearer: "new-fixture-bearer", storeIdentity: current)
        let sameBytes = try f.keychain.bytes(newRegistrationConnectionAccount(current)) == initialBytes
        #expect(sameBytes)
        #expect(!(try await concrete.permitsNewStoreRegistration(storeIdentity: current)))
        #expect(!(try await erased.permitsNewStoreRegistration(storeIdentity: current)))
        let fromPort = try await erased.connection(storeIdentity: current)
        let directConnection = try await concrete.connection(storeIdentity: current)
        #expect(fromPort == directConnection)
        try f.assertOldBytes()
    }

    @Test func orphanedCurrentCredentialForAnotherDestinationBlocksNewRegistrationWithoutReadingItsSecret() async throws {
        let f = try await NewRegistrationKeychain.make()
        let current = RegistrationStoreIdentity(rawValue: UUID())
        let other = DestinationIdentity(rawValue: UUID().uuidString.lowercased())
        defer { f.cleanup([current], destinations: [other]) }
        let account = newRegistrationCredentialAccount(current, other)
        let unknownBytes = Data("unbound-unknown-current-secret-must-not-be-decoded-or-adopted".utf8)
        var query = f.keychain.query(account)
        query[kSecValueData as String] = unknownBytes
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        #expect(SecItemAdd(query as CFDictionary, nil) == errSecSuccess)
        let vault = try f.keychain.vault()
        #expect(!(try await vault.permitsNewStoreRegistration(storeIdentity: current)))
        do {
            try await vault.saveNewStoreConnection(f.keychain.connection, bearer: "new-fixture-bearer", storeIdentity: current)
            Issue.record("A different-destination orphan authorized a second current binding")
        } catch { #expect(error as? RegistrationAccessError == .credentialConflict) }
        let orphanUnchanged = try f.keychain.bytes(account) == unknownBytes
        #expect(orphanUnchanged)
        #expect(try f.keychain.bytes(newRegistrationConnectionAccount(current)) == nil)
        try f.assertOldBytes()
    }

    @Test(arguments: [false, true])
    func explicitNamespaceKeepsForeignBytesAndSeparatesTheNewIntentAndSecret(includeOldIntent: Bool) async throws {
        let f = try await NewRegistrationKeychain.make(includeOldIntent: includeOldIntent)
        let current = RegistrationStoreIdentity(rawValue: UUID())
        defer { f.cleanup([current]) }
        let vault = try f.keychain.vault()
        #expect(try await vault.permitsNewStoreRegistration(storeIdentity: nil))
        #expect(try await vault.permitsNewStoreRegistration(storeIdentity: current))
        do { _ = try await vault.connection(storeIdentity: current); Issue.record("Ordinary lookup adopted foreign binding") }
        catch { #expect(error as? RegistrationAccessError == .credentialConflict) }
        try await vault.saveNewStoreConnection(f.keychain.connection, bearer: "new-fixture-bearer", storeIdentity: current)
        let intent = try await vault.prepareIntent(for: f.keychain.connection.destination, storeIdentity: current)
        let again = try f.keychain.vault()
        #expect(try await again.connection(storeIdentity: current) == f.keychain.connection)
        #expect(try await again.prepareIntent(for: f.keychain.connection.destination, storeIdentity: current) == intent)
        #expect(!(try await again.permitsNewStoreRegistration(storeIdentity: current)))
        let authorization = try await again.authorization(for: f.keychain.connection, intent: intent, storeIdentity: current)
        #expect(authorization.bearer == "new-fixture-bearer")
        if let old = f.oldIntent {
            #expect(intent != old)
            let oldAuthorization = try await again.authorization(for: f.keychain.connection, intent: old, storeIdentity: f.oldIdentity)
            let secretsAreSeparate = authorization.secret != oldAuthorization.secret
            #expect(secretsAreSeparate)
        } else {
            // Missing initial is a known connection-before-intent Keychain
            // shape, not evidence that an old remote registration never ran.
            #expect(try f.keychain.bytes("initial." + f.keychain.connection.destination.rawValue) == nil)
        }
        try f.assertOldBytes()
    }

    @Test func concurrentCreatesChooseOneCurrentNamespaceAndRejectAnotherDestination() async throws {
        let f = try await NewRegistrationKeychain.make()
        let current = RegistrationStoreIdentity(rawValue: UUID())
        let other = try RegistrationConnection(endpoint: .init(httpsOrigin: "https://another-registration.invalid"),
            destination: .init(rawValue: UUID().uuidString.lowercased()))
        defer { f.cleanup([current], destinations: [other.destination]) }
        let a = try f.keychain.vault(), b = try f.keychain.vault()
        async let savedA: Void = a.saveNewStoreConnection(f.keychain.connection, bearer: "new-fixture-bearer", storeIdentity: current)
        async let savedB: Void = b.saveNewStoreConnection(f.keychain.connection, bearer: "new-fixture-bearer", storeIdentity: current)
        _ = try await (savedA, savedB)
        async let preparedA = a.prepareIntent(for: f.keychain.connection.destination, storeIdentity: current)
        async let preparedB = b.prepareIntent(for: f.keychain.connection.destination, storeIdentity: current)
        let values = try await [preparedA, preparedB]
        #expect(values[0] == values[1])
        do { try await b.saveNewStoreConnection(other, bearer: "new-fixture-bearer", storeIdentity: current); Issue.record("Current store acquired a second destination") }
        catch { #expect(error as? RegistrationAccessError == .credentialConflict) }
        do { _ = try await b.prepareIntent(for: other.destination, storeIdentity: current); Issue.record("Wrong-destination secret created") }
        catch { #expect(error as? RegistrationAccessError == .credentialConflict) }
        #expect(try f.keychain.bytes(newRegistrationCredentialAccount(current, other.destination)) == nil)
        try f.assertOldBytes()
    }

    @Test(arguments: ["connection-v1", "connection-version", "connection-corrupt", "initial-v1", "initial-binding", "initial-corrupt", "current-corrupt"])
    func unboundCorruptAndInconsistentRecordsDoNotAuthorizeAnotherRegistration(corruption: String) async throws {
        let f = try await NewRegistrationKeychain.make()
        let current = RegistrationStoreIdentity(rawValue: UUID())
        defer { f.cleanup([current]) }
        let vault = try f.keychain.vault()
        let account: String
        var bytes: Data
        if corruption == "current-corrupt" {
            try await vault.saveNewStoreConnection(f.keychain.connection, bearer: "new-fixture-bearer", storeIdentity: current)
            account = newRegistrationConnectionAccount(current)
            bytes = Data("invalid-current-record".utf8)
        } else {
            account = corruption.hasPrefix("connection") ? "connection" : "initial." + f.keychain.connection.destination.rawValue
            let storedBytes = try f.keychain.bytes(account)
            let original = try #require(storedBytes)
            if corruption.hasSuffix("corrupt") { bytes = Data("invalid-record".utf8) }
            else {
                var object = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
                if corruption.hasSuffix("v1") { object["version"] = 1; object.removeValue(forKey: "storeIdentity") }
                else if corruption == "connection-version" { object["version"] = 999 }
                else { object["storeIdentity"] = ["rawValue": UUID().uuidString] }
                bytes = try JSONSerialization.data(withJSONObject: object)
            }
        }
        #expect(SecItemUpdate(f.keychain.query(account) as CFDictionary, [kSecValueData as String: bytes] as CFDictionary) == errSecSuccess)
        let permitted = (try? await vault.permitsNewStoreRegistration(storeIdentity: current)) ?? false
        #expect(!permitted)
        do { try await vault.saveNewStoreConnection(f.keychain.connection, bearer: "new-fixture-bearer", storeIdentity: current); Issue.record("Invalid record authorized a new namespace") }
        catch { }
        #expect(try f.keychain.bytes(account) == bytes)
        if corruption == "current-corrupt" {
            do { _ = try await vault.connection(storeIdentity: current); Issue.record("Corrupt current namespace fell back to foreign global record") }
            catch { #expect(error as? RegistrationAccessError == .corruptCredential) }
            try f.assertOldBytes()
        } else { #expect(try f.keychain.bytes(newRegistrationConnectionAccount(current)) == nil) }
    }
}

nonisolated struct NewRegistrationKeychain {
    let keychain: RegistrationTestKeychain
    let oldIdentity: RegistrationStoreIdentity
    let oldIntent: RegistrationIntent?
    let oldConnectionBytes: Data
    let oldCredentialBytes: Data?

    static func make(includeOldIntent: Bool = true) async throws -> Self {
        let keychain = try RegistrationTestKeychain()
        let vault = try keychain.vault()
        let identity = RegistrationStoreIdentity(rawValue: UUID())
        try await vault.saveConnection(keychain.connection, bearer: "old-fixture-bearer", storeIdentity: identity)
        let intent = includeOldIntent ? try await vault.prepareIntent(for: keychain.connection.destination, storeIdentity: identity) : nil
        let connectionBytes = try keychain.bytes("connection")
        return .init(keychain: keychain, oldIdentity: identity, oldIntent: intent,
            oldConnectionBytes: try #require(connectionBytes),
            oldCredentialBytes: try keychain.bytes("initial." + keychain.connection.destination.rawValue))
    }
    func assertOldBytes() throws {
        let connectionUnchanged = try keychain.bytes("connection") == oldConnectionBytes
        let credentialUnchanged = try keychain.bytes("initial." + keychain.connection.destination.rawValue) == oldCredentialBytes
        #expect(connectionUnchanged)
        #expect(credentialUnchanged)
    }
    func cleanup(_ identities: [RegistrationStoreIdentity], destinations: [DestinationIdentity] = []) {
        precondition(keychain.service.hasPrefix("FrameRelay.registration.tests."))
        let destinations = [keychain.connection.destination] + destinations
        var accounts = ["connection", "initial." + keychain.connection.destination.rawValue]
        for identity in identities {
            accounts.append(newRegistrationConnectionAccount(identity))
            accounts += destinations.map { newRegistrationCredentialAccount(identity, $0) }
        }
        for account in Set(accounts) {
            let status = SecItemDelete(keychain.query(account) as CFDictionary)
            #expect(status == errSecSuccess || status == errSecItemNotFound)
        }
    }
}

nonisolated func newRegistrationConnectionAccount(_ identity: RegistrationStoreIdentity) -> String {
    "store." + identity.rawValue.uuidString.lowercased() + ".connection"
}
nonisolated func newRegistrationCredentialAccount(_ identity: RegistrationStoreIdentity, _ destination: DestinationIdentity) -> String {
    "store." + identity.rawValue.uuidString.lowercased() + ".initial." + destination.rawValue
}
