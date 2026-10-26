import Foundation
import Security
import Testing
@testable import FrameRelay

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["FR_S28_INVENTORY_HTTP"] == "1"))
@MainActor struct RemoteInventoryHTTPFixtureTests {
    @Test func discoverOriginalsAcrossRegistrationsAndReopen() async throws {
        let env = ProcessInfo.processInfo.environment
        let path = try #require(env["FR_S28_INVENTORY_CONFIG"])
        let configuration = try InventoryHTTPConfiguration.read(path)
        let endpoint: RegistrationEndpoint
        #if DEBUG && targetEnvironment(simulator)
        endpoint = try RegistrationEndpoint.isolatedLoopbackProbe(configuration.origin)
        #else
        throw BackendContractError.unsupportedVersion
        #endif
        let keychain = try RegistrationTestKeychain(endpoint: endpoint, destination: configuration.destinationID)
        var currentIdentity: RegistrationStoreIdentity?
        defer { inventoryHTTPKeychainCleanup(keychain, identity: currentIdentity) }
        let vault = try keychain.vault()
        let oldIdentity = RegistrationStoreIdentity(rawValue: UUID())
        // Only the foreign connection-before-intent shape is prepared. No old
        // server secret is available to the client or inferred as absent remotely.
        try await vault.saveConnection(keychain.connection, bearer: configuration.bearer, storeIdentity: oldIdentity)
        let savedOldBytes = try keychain.bytes("connection")
        let oldBytes = try #require(savedOldBytes)
        let initialWasAbsent = try keychain.bytes("initial." + configuration.destinationID) == nil
        #expect(initialWasAbsent)
        try await withStorageRun { run in
            let store = try SQLiteRecordingStore(run: run, mode: .createNew)
            let registration = RegistrationCoordinator(store: store, vault: vault,
                remote: URLSessionRegistrationRemote(credentials: vault, store: store))
            #expect(await registration.restore() == .unavailable(.credentialConflict))
            let result = await registration.registerNewStore(connection: keychain.connection, bearer: configuration.bearer)
            let afterRegistration = try await mediaSnapshot(store)
            currentIdentity = afterRegistration.storeIdentity
            let identity = try #require(currentIdentity)
            guard case .registered(_, let registered) = result else { throw BackendContractError.notCommitted }
            #expect(identity != oldIdentity)
            #expect(registered.server.registration.id.rawValue != configuration.oldRegistrationID)
            #expect(registered.server.registration.generation.rawValue == 2)
            let newCredentialExists = try keychain.bytes(newRegistrationCredentialAccount(identity, keychain.connection.destination)) != nil
            #expect(newCredentialExists)
            let coordinator = RemoteInventoryCoordinator(store: store, remoteFactory: { connection, registration, boundIdentity in
                URLSessionRemoteInventoryRemote(connection: connection, credentials: vault, store: store,
                    identity: boundIdentity, registration: registration)
            })
            let first = await coordinator.discover(connection: keychain.connection, registration: registered)
            let second = await coordinator.discover(connection: keychain.connection, registration: registered)
            #expect(first == .init(phase: .recorded, receivedCount: 32, hasMore: true))
            #expect(second == .init(phase: .recorded, receivedCount: 1, hasMore: false))
            let reopened = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let snapshot = try await mediaSnapshot(reopened)
            #expect(snapshot.remoteInventory.count == 2)
            let observed = snapshot.remoteInventory.flatMap { $0.observation.page.originals }
            let actual = Set(observed.map { RemoteInventoryOriginalID(destination: keychain.connection.destination, original: $0) })
            let configuredItems = try configuration.expectedItems
            let expected = Set(configuredItems.map { RemoteInventoryOriginalID(destination: keychain.connection.destination, original: $0) })
            #expect(observed.count == 33 && actual.count == 33 && actual == expected)
            #expect(snapshot.remoteInventory.allSatisfy {
                $0.observation.registration == registered.server.registration && $0.observation.storeIdentity == identity
            })
            #expect(snapshot.registrationIntents.count == 1 && snapshot.registrations.count == 1)
            #expect(snapshot.requests.isEmpty && snapshot.verifications.isEmpty && snapshot.publications.isEmpty
                && snapshot.confirmations.isEmpty && snapshot.invalidations.isEmpty && snapshot.outbox.isEmpty)
            #expect(try await mediaOriginalSnapshot(reopened).logicalOriginals.isEmpty)
            let reader = LibraryStoreReader(store: reopened, files: StatusSynchronizationAbsentFiles())
            guard case .loaded(let library) = await reader.loadLibrary() else { throw BackendContractError.unavailable }
            #expect(library.items.isEmpty && library.remoteItems.count == 33 && library.history.isEmpty)
            #expect(library.remoteItems.allSatisfy { $0.captureDateDescription == "撮影日時不明" })
            let oldGlobalPreserved = try keychain.bytes("connection") == oldBytes
            let oldInitialStillAbsent = try keychain.bytes("initial." + configuration.destinationID) == nil
            #expect(oldGlobalPreserved && oldInitialStillAbsent)
            let observation: [String: Any] = ["run_identity": configuration.runIdentity, "pages": 2,
                "item_count": actual.count, "new_registration_generation": registered.server.registration.generation.rawValue,
                "reopened": true, "remote_library_rows": library.remoteItems.count, "local_recordings": library.items.count,
                "old_global_preserved": oldGlobalPreserved, "old_secret_adopted": false,
                "client_media_operations": snapshot.requests.count, "confirmations": snapshot.confirmations.count,
                "acknowledgements": snapshot.invalidations.count, "outbox": snapshot.outbox.count]
            Attachment.record(String(decoding: try JSONSerialization.data(withJSONObject: observation, options: [.sortedKeys]), as: UTF8.self),
                named: "s28-inventory-observation.json")
        }
    }
}

nonisolated private struct InventoryHTTPConfiguration: Decodable {
    let schemaVersion: String
    let runIdentity: String
    let origin: String
    let bearer: String
    let destinationID: String
    let oldRegistrationID: String
    let expected: [ExpectedOriginal]
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", runIdentity = "run_identity", origin, bearer
        case destinationID = "destination_id", oldRegistrationID = "old_registration_id", expected = "expected_items"
    }
    var expectedItems: [OriginalContent] { get throws { try expected.map { try $0.original() } } }
    static func read(_ path: String) throws -> Self {
        let url = URL(fileURLWithPath: path)
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600 else { throw BackendContractError.invalidValue }
        let data = try Data(contentsOf: url)
        guard data.count <= 262_144 else { throw BackendContractError.invalidValue }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.schemaVersion == "fr-s28-inventory-fixture-v1",
              RemoteInventoryValidation.canonicalID(value.runIdentity), RemoteInventoryValidation.canonicalID(value.destinationID),
              RemoteInventoryValidation.canonicalID(value.oldRegistrationID), value.expected.count == 33,
              !value.bearer.isEmpty, value.bearer.utf8.count <= 4096,
              value.bearer.utf8.allSatisfy({ (33...126).contains($0) }) else { throw BackendContractError.invalidValue }
        _ = try value.expectedItems
        return value
    }
    struct ExpectedOriginal: Decodable {
        let capture: String
        let generation: String
        let sha256: String
        let bytes: String
        enum CodingKeys: String, CodingKey { case capture = "capture_id", generation = "content_generation", sha256, bytes = "byte_count" }
        func original() throws -> OriginalContent {
            guard let generationValue = UInt64(generation), String(generationValue) == generation,
                  let byteValue = UInt64(bytes), String(byteValue) == bytes else { throw BackendContractError.invalidValue }
            let result = OriginalContent(capture: .init(rawValue: capture), generation: .init(rawValue: generationValue),
                content: try .init(byteCount: byteValue, algorithm: "sha256", digest: sha256))
            try RemoteInventoryValidation.original(result)
            return result
        }
    }
}

nonisolated private func inventoryHTTPKeychainCleanup(_ fixture: RegistrationTestKeychain, identity: RegistrationStoreIdentity?) {
    precondition(fixture.service.hasPrefix("FrameRelay.registration.tests."))
    var accounts = ["connection", "initial." + fixture.connection.destination.rawValue]
    if let identity {
        accounts += [newRegistrationConnectionAccount(identity), newRegistrationCredentialAccount(identity, fixture.connection.destination)]
    }
    for account in accounts {
        let result = SecItemDelete(fixture.query(account) as CFDictionary)
        #expect(result == errSecSuccess || result == errSecItemNotFound)
    }
}
