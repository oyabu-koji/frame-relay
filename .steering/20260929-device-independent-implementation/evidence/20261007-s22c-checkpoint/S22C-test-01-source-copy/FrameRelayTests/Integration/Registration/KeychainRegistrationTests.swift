import Foundation
import Security
import Testing
@testable import FrameRelay

struct KeychainRegistrationTests {
    @Test func realKeychainReopenRetainsCredentialBeforeAnyIntentCommit() async throws {
        let fixture = try RegistrationTestKeychain()
        defer { fixture.cleanup() }
        let vault = try fixture.vault()
        try await vault.saveConnection(fixture.connection, bearer: "fixture-bootstrap")
        let first = try await vault.prepareIntent(for: fixture.connection.destination)
        let reopened = try fixture.vault()
        let second = try await reopened.prepareIntent(for: fixture.connection.destination)
        #expect(first == second)
        let material = try await vault.authorization(for: fixture.connection, intent: first)
        let again = try await reopened.authorization(for: fixture.connection, intent: second)
        let secretsMatch = material.secret == again.secret
        #expect(secretsMatch)
        #expect(material.secret?.utf8.count == 64)
    }
    @Test func concurrentAtomicAddsChooseOneOperationAndSecret() async throws {
        let fixture = try RegistrationTestKeychain()
        defer { fixture.cleanup() }
        let first = try fixture.vault(), second = try fixture.vault()
        try await first.saveConnection(fixture.connection, bearer: "fixture-bootstrap")
        async let a = first.prepareIntent(for: fixture.connection.destination)
        async let b = second.prepareIntent(for: fixture.connection.destination)
        let values = try await [a, b]
        #expect(values[0] == values[1])
    }
    @Test func duplicateConnectionCannotReplaceCredentials() async throws {
        let fixture = try RegistrationTestKeychain()
        defer { fixture.cleanup() }
        let vault = try fixture.vault()
        try await vault.saveConnection(fixture.connection, bearer: "first-bootstrap")
        do {
            try await vault.saveConnection(fixture.connection, bearer: "replacement-bootstrap")
            Issue.record("Credential replacement was accepted")
        } catch { #expect(error as? RegistrationAccessError == .credentialConflict) }
        let material = try await vault.authorization(for: fixture.connection, intent: nil)
        let originalKept = material.bearer == "first-bootstrap"
        #expect(originalKept)
    }
    @Test func missingAndMismatchedIntentCredentialAreNotRegenerated() async throws {
        let fixture = try RegistrationTestKeychain()
        defer { fixture.cleanup() }
        let vault = try fixture.vault()
        try await vault.saveConnection(fixture.connection, bearer: "fixture-bootstrap")
        let missing = RegistrationIntent(operation: .init(rawValue: UUID().uuidString.lowercased()), destination: fixture.connection.destination)
        do { try await vault.requireCredential(for: missing); Issue.record("Missing credential accepted") }
        catch { #expect(error as? RegistrationAccessError == .credentialMissing) }
        let saved = try await vault.prepareIntent(for: fixture.connection.destination)
        do { try await vault.requireCredential(for: missing); Issue.record("Wrong operation accepted") }
        catch { #expect(error as? RegistrationAccessError == .credentialConflict) }
        #expect(try await vault.prepareIntent(for: fixture.connection.destination) == saved)
    }
    @Test func corruptExistingKeychainRecordNeverBecomesNewRegistration() async throws {
        let fixture = try RegistrationTestKeychain()
        defer { fixture.cleanup() }
        let vault = try fixture.vault()
        try await vault.saveConnection(fixture.connection, bearer: "fixture-bootstrap")
        _ = try await vault.prepareIntent(for: fixture.connection.destination)
        let query = fixture.query("initial." + fixture.connection.destination.rawValue)
        #expect(SecItemUpdate(query as CFDictionary, [kSecValueData as String: Data("invalid".utf8)] as CFDictionary) == errSecSuccess)
        do { _ = try await vault.prepareIntent(for: fixture.connection.destination); Issue.record("Corrupt credential replaced") }
        catch { #expect(error as? RegistrationAccessError == .corruptCredential) }
    }
}
