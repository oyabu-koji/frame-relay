import Foundation
import Security
import Testing
@testable import FrameRelay

struct KeychainRegistrationTests {
    @Test func realKeychainReopenRetainsCredentialBeforeAnyIntentCommit() async throws {
        let identity = RegistrationStoreIdentity(rawValue: UUID())
        let fixture = try RegistrationTestKeychain()
        defer { fixture.cleanup() }
        let vault = try fixture.vault()
        try await vault.saveConnection(fixture.connection, bearer: "fixture-bootstrap", storeIdentity: identity)
        let first = try await vault.prepareIntent(for: fixture.connection.destination, storeIdentity: identity)
        let reopened = try fixture.vault()
        let second = try await reopened.prepareIntent(for: fixture.connection.destination, storeIdentity: identity)
        #expect(first == second)
        let material = try await vault.authorization(for: fixture.connection, intent: first, storeIdentity: identity)
        let again = try await reopened.authorization(for: fixture.connection, intent: second, storeIdentity: identity)
        let secretsMatch = material.secret == again.secret
        #expect(secretsMatch)
        #expect(material.secret?.utf8.count == 64)
    }
    @Test func concurrentAtomicAddsChooseOneOperationAndSecret() async throws {
        let identity = RegistrationStoreIdentity(rawValue: UUID())
        let fixture = try RegistrationTestKeychain()
        defer { fixture.cleanup() }
        let first = try fixture.vault(), second = try fixture.vault()
        try await first.saveConnection(fixture.connection, bearer: "fixture-bootstrap", storeIdentity: identity)
        async let a = first.prepareIntent(for: fixture.connection.destination, storeIdentity: identity)
        async let b = second.prepareIntent(for: fixture.connection.destination, storeIdentity: identity)
        let values = try await [a, b]
        #expect(values[0] == values[1])
    }
    @Test func duplicateConnectionCannotReplaceCredentials() async throws {
        let identity = RegistrationStoreIdentity(rawValue: UUID())
        let fixture = try RegistrationTestKeychain()
        defer { fixture.cleanup() }
        let vault = try fixture.vault()
        try await vault.saveConnection(fixture.connection, bearer: "first-bootstrap", storeIdentity: identity)
        do {
            try await vault.saveConnection(fixture.connection, bearer: "replacement-bootstrap", storeIdentity: identity)
            Issue.record("Credential replacement was accepted")
        } catch { #expect(error as? RegistrationAccessError == .credentialConflict) }
        let material = try await vault.authorization(for: fixture.connection, intent: nil, storeIdentity: identity)
        let originalKept = material.bearer == "first-bootstrap"
        #expect(originalKept)
    }
    @Test func missingAndMismatchedIntentCredentialAreNotRegenerated() async throws {
        let identity = RegistrationStoreIdentity(rawValue: UUID())
        let fixture = try RegistrationTestKeychain()
        defer { fixture.cleanup() }
        let vault = try fixture.vault()
        try await vault.saveConnection(fixture.connection, bearer: "fixture-bootstrap", storeIdentity: identity)
        let missing = RegistrationIntent(operation: .init(rawValue: UUID().uuidString.lowercased()), destination: fixture.connection.destination)
        do { try await vault.requireCredential(for: missing, storeIdentity: identity); Issue.record("Missing credential accepted") }
        catch { #expect(error as? RegistrationAccessError == .credentialMissing) }
        let saved = try await vault.prepareIntent(for: fixture.connection.destination, storeIdentity: identity)
        do { try await vault.requireCredential(for: missing, storeIdentity: identity); Issue.record("Wrong operation accepted") }
        catch { #expect(error as? RegistrationAccessError == .credentialConflict) }
        #expect(try await vault.prepareIntent(for: fixture.connection.destination, storeIdentity: identity) == saved)
    }
    @Test func corruptExistingKeychainRecordNeverBecomesNewRegistration() async throws {
        let identity = RegistrationStoreIdentity(rawValue: UUID())
        let fixture = try RegistrationTestKeychain()
        defer { fixture.cleanup() }
        let vault = try fixture.vault()
        try await vault.saveConnection(fixture.connection, bearer: "fixture-bootstrap", storeIdentity: identity)
        _ = try await vault.prepareIntent(for: fixture.connection.destination, storeIdentity: identity)
        let query = fixture.query("initial." + fixture.connection.destination.rawValue)
        #expect(SecItemUpdate(query as CFDictionary, [kSecValueData as String: Data("invalid".utf8)] as CFDictionary) == errSecSuccess)
        do { _ = try await vault.prepareIntent(for: fixture.connection.destination, storeIdentity: identity); Issue.record("Corrupt credential replaced") }
        catch { #expect(error as? RegistrationAccessError == .corruptCredential) }
    }
    @Test func differentStoreCannotReadAdoptOrReplaceBoundCredentials() async throws {
        let fixture = try RegistrationTestKeychain()
        defer { fixture.cleanup() }
        let identity = RegistrationStoreIdentity(rawValue: UUID())
        let other = RegistrationStoreIdentity(rawValue: UUID())
        let vault = try fixture.vault()
        try await vault.saveConnection(fixture.connection, bearer: "fixture-bootstrap", storeIdentity: identity)
        let intent = try await vault.prepareIntent(for: fixture.connection.destination, storeIdentity: identity)
        let connectionBytes = try fixture.bytes("connection")
        let secretBytes = try fixture.bytes("initial." + fixture.connection.destination.rawValue)
        for expected: RegistrationStoreIdentity? in [nil, other] {
            do { _ = try await vault.connection(storeIdentity: expected); Issue.record("Store mismatch accepted") }
            catch { #expect(error as? RegistrationAccessError == .credentialConflict) }
        }
        do { try await vault.saveConnection(fixture.connection, bearer: "fixture-bootstrap", storeIdentity: other); Issue.record("Old binding adopted") }
        catch { #expect(error as? RegistrationAccessError == .credentialConflict) }
        do { _ = try await vault.prepareIntent(for: fixture.connection.destination, storeIdentity: other); Issue.record("Old intent adopted") }
        catch { #expect(error as? RegistrationAccessError == .credentialConflict) }
        do { try await vault.requireCredential(for: intent, storeIdentity: other); Issue.record("Old secret accepted") }
        catch { #expect(error as? RegistrationAccessError == .credentialConflict) }
        do { _ = try await vault.authorization(for: fixture.connection, intent: intent, storeIdentity: other); Issue.record("Old secret released") }
        catch { #expect(error as? RegistrationAccessError == .credentialConflict) }
        let connectionUnchanged = try fixture.bytes("connection") == connectionBytes
        let secretUnchanged = try fixture.bytes("initial." + fixture.connection.destination.rawValue) == secretBytes
        #expect(connectionUnchanged)
        #expect(secretUnchanged)
        try await vault.requireCredential(for: intent, storeIdentity: identity)
    }

    @Test(arguments: [false, true])
    func legacyUnboundRecordsArePreservedAndNeverAdopted(credentialOnly: Bool) async throws {
        let fixture = try RegistrationTestKeychain()
        defer { fixture.cleanup() }
        let identity = RegistrationStoreIdentity(rawValue: UUID())
        let vault = try fixture.vault()
        try await vault.saveConnection(fixture.connection, bearer: "fixture-bootstrap", storeIdentity: identity)
        let intent = try await vault.prepareIntent(for: fixture.connection.destination, storeIdentity: identity)
        let account = credentialOnly ? "initial." + fixture.connection.destination.rawValue : "connection"
        let savedBytes = try fixture.bytes(account)
        let original = try #require(savedBytes)
        var object = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
        object["version"] = 1
        object.removeValue(forKey: "storeIdentity")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        #expect(SecItemUpdate(fixture.query(account) as CFDictionary,
            [kSecValueData as String: legacy] as CFDictionary) == errSecSuccess)
        let reopened = try fixture.vault()
        do { _ = try await reopened.prepareIntent(for: fixture.connection.destination, storeIdentity: identity); Issue.record("Legacy credential adopted") }
        catch { #expect(error as? RegistrationAccessError == .credentialConflict) }
        do { _ = try await reopened.authorization(for: fixture.connection, intent: intent, storeIdentity: identity); Issue.record("Legacy authorization released") }
        catch { #expect(error as? RegistrationAccessError == .credentialConflict) }
        let unchanged = try fixture.bytes(account) == legacy
        #expect(unchanged)
    }

    @Test func transportRefusesAStoreMismatchBeforeReleasingAuthorization() async throws {
        try await withStorageRun { run in
            let fixture = try RegistrationTestKeychain()
            defer { fixture.cleanup() }
            let oldIdentity = RegistrationStoreIdentity(rawValue: UUID())
            let vault = try fixture.vault()
            try await vault.saveConnection(fixture.connection, bearer: "fixture-bootstrap", storeIdentity: oldIdentity)
            let intent = try await vault.prepareIntent(for: fixture.connection.destination, storeIdentity: oldIdentity)
            let fresh = try SQLiteRecordingStore(run: run, mode: .createNew)
            let freshIdentity = try await establishRegistrationIdentity(fresh)
            let authorization = RegistrationObservedAuthorization(base: vault)
            let remote = URLSessionRegistrationRemote(credentials: authorization, store: fresh)
            #expect(await remote.discover(fixture.connection, storeIdentity: oldIdentity) == .failed(.rejected))
            #expect(await remote.lookup(intent, at: fixture.connection, storeIdentity: oldIdentity) == .failed(.rejected))
            #expect(await authorization.calls == 0)
            #expect(await remote.discover(fixture.connection, storeIdentity: freshIdentity) == .failed(.rejected))
            #expect(await authorization.calls == 1)
        }
    }

}


private actor RegistrationObservedAuthorization: RegistrationAuthorizationPort {
    let base: any RegistrationAuthorizationPort
    private(set) var calls = 0
    init(base: any RegistrationAuthorizationPort) { self.base = base }
    func authorization(for connection: RegistrationConnection, intent: RegistrationIntent?,
                       storeIdentity: RegistrationStoreIdentity) async throws -> RegistrationAuthorization {
        calls += 1
        return try await base.authorization(for: connection, intent: intent, storeIdentity: storeIdentity)
    }
}
