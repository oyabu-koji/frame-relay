import Foundation
import Testing
@testable import FrameRelay

@MainActor struct RegistrationCompositionTests {
    @Test func productCompositionUsesLibraryWriterAndRetainsModels() async throws {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("FrameRelay-registration-composition-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        let fixture = try RegistrationTestKeychain()
        defer { fixture.cleanup() }
        let vault = try fixture.vault(), remote = RegistrationTestRemote()
        let factory = ProductLibraryFactory(supportDirectory: parent)
        let composition = ProductComposition(factory: factory, registrationFactory: { store in
            RegistrationCoordinator(store: store, vault: vault, remote: remote)
        })
        await composition.open()
        let connection = try #require(composition.connection)
        #expect(connection.permitsInitialInput)
        connection.origin = fixture.connection.endpoint.origin.absoluteString
        connection.destination = fixture.connection.destination.rawValue
        connection.bearer = "fixture-bootstrap"
        await connection.register()
        #expect(registrationIsCommitted(connection.state))
        #expect(connection.bearer.isEmpty)
        let services = try await factory.open()
        #expect(try await registrationSnapshot(services.store).registrations.count == 1)
        await composition.open()
        #expect(composition.connection === connection)
        #expect(composition.library != nil && composition.openingIssue == nil)
    }
    @Test func unavailableCredentialsHideInitialInputAndLeaveLibraryAvailable() async throws {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("FrameRelay-registration-unavailable-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        let composition = ProductComposition(factory: .init(supportDirectory: parent), registrationFactory: { store in
            RegistrationCoordinator(store: store, vault: UnavailableRegistrationVault(), remote: RegistrationTestRemote())
        })
        await composition.open()
        let model = try #require(composition.connection)
        #expect(!model.permitsInitialInput)
        #expect(model.state == .unavailable(.credentials))
        #expect(composition.library != nil && composition.openingIssue == nil)
    }
}

nonisolated private struct UnavailableRegistrationVault: RegistrationVaultPort {
    func connection() async throws -> RegistrationConnection? { throw RegistrationAccessError.credentialUnavailable }
    func saveConnection(_ connection: RegistrationConnection, bearer: String) async throws { throw RegistrationAccessError.credentialUnavailable }
    func prepareIntent(for destination: DestinationIdentity) async throws -> RegistrationIntent { throw RegistrationAccessError.credentialUnavailable }
    func requireCredential(for intent: RegistrationIntent) async throws { throw RegistrationAccessError.credentialUnavailable }
}
