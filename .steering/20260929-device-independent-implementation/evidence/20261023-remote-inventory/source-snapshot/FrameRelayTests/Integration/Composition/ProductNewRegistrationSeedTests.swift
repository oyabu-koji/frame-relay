import CryptoKit
import Foundation
import Security
import Testing
@testable import FrameRelay

/// Explicit opt-in on one new empty Simulator only. This creates synthetic
/// foreign v2 Keychain records and a hash-only manifest, never a registration
/// in the current writer, original media, a fixture branch in the product, or
/// an external request. Existing product Keychain items are never repaired.
@Suite(.serialized) @MainActor struct ProductNewRegistrationSeedTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_NEW_REGISTRATION_SEED"] == "1"))
    func seedEmptyDedicatedRootWithPreservedSyntheticForeignCredentials() async throws {
        let context = try NewRegistrationSeedContext.load()
        try #require(try newRegistrationProductAccounts().isEmpty)
        let services = try await ProductLibraryFactory.shared.open()
        let snapshot = try await mediaSnapshot(services.store)
        try await requireEmptyNewRegistrationRoot(services, expectedRevision: snapshot.revision, identity: snapshot.storeIdentity)
        let manifestURL = services.run.url.appendingPathComponent("s28-new-registration-seed.json")
        try #require(!FileManager.default.fileExists(atPath: manifestURL.path))
        let oldIdentity = RegistrationStoreIdentity(rawValue: context.token)
        try #require(snapshot.storeIdentity != oldIdentity)
        // Attributes only: even an unrelated namespace under the product
        // service refuses seeding. No wildcard deletion or overwrite exists.
        try #require(try newRegistrationProductAccounts().isEmpty)
        let destination = DestinationIdentity(rawValue: "9a3ba104-985f-4a2d-875d-d458258b9b6b")
        let connection = try RegistrationConnection(endpoint: .init(httpsOrigin: "https://previous-registration.invalid"), destination: destination)
        let vault = KeychainRegistrationVault()
        try await vault.saveConnection(connection, bearer: "synthetic-bootstrap-" + context.nonce.uuidString.lowercased(), storeIdentity: oldIdentity)
        let intent = try await vault.prepareIntent(for: destination, storeIdentity: oldIdentity)
        let oldConnection = try newRegistrationProductBytes("connection")
        let oldCredential = try newRegistrationProductBytes("initial." + destination.rawValue)
        let connectionBytes = try #require(oldConnection)
        let credentialBytes = try #require(oldCredential)
        let expectedAccounts: Set<String> = ["connection", "initial." + destination.rawValue]
        try #require(try newRegistrationProductAccounts() == expectedAccounts)
        let manifest = NewRegistrationSeedManifest(token: context.token, nonce: context.nonce, simulator: context.simulator,
            currentIdentity: snapshot.storeIdentity, revision: snapshot.revision, oldIdentity: oldIdentity, oldIntent: intent,
            oldConnectionSHA256: newRegistrationSeedDigest(connectionBytes), oldCredentialSHA256: newRegistrationSeedDigest(credentialBytes))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(manifest).write(to: manifestURL, options: .withoutOverwriting)
        let remote = RegistrationTestRemote()
        let coordinator = RegistrationCoordinator(store: services.store, vault: vault, remote: remote)
        try #require(await coordinator.restore() == .unavailable(.credentialConflict))
        try #require(!(await coordinator.permitsInitialInput()))
        try #require(await coordinator.permitsNewStoreRegistration())
        let calls = [await remote.discoveries, await remote.lookups, await remote.posts]
        try #require(calls == [0, 0, 0])
        try await requireEmptyNewRegistrationRoot(services, expectedRevision: manifest.revision, identity: manifest.currentIdentity)
        print("S28_NEW_REGISTRATION_SEED token=\(context.token.uuidString.lowercased()) nonce=\(context.nonce.uuidString.lowercased()) simulator=\(context.simulator.uuidString) productAccounts=2 currentRegistration=empty hashesOnlyManifest=true noRemoteRequest=true")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_NEW_REGISTRATION_VERIFY"] == "1"))
    func verifyNegativeUIKeepsForeignBytesAndCurrentStoreUnchanged() async throws {
        let context = try NewRegistrationSeedContext.load()
        let services = try await ProductLibraryFactory.shared.open()
        let url = services.run.url.appendingPathComponent("s28-new-registration-seed.json")
        let data = try Data(contentsOf: url)
        let manifest = try JSONDecoder().decode(NewRegistrationSeedManifest.self, from: data)
        try #require(manifest.token == context.token && manifest.nonce == context.nonce && manifest.simulator == context.simulator)
        try await requireEmptyNewRegistrationRoot(services, expectedRevision: manifest.revision, identity: manifest.currentIdentity)
        let connection = try newRegistrationProductBytes("connection")
        let credential = try newRegistrationProductBytes("initial." + manifest.oldIntent.destination.rawValue)
        let connectionBytes = try #require(connection)
        let credentialBytes = try #require(credential)
        try #require(newRegistrationSeedDigest(connectionBytes) == manifest.oldConnectionSHA256)
        try #require(newRegistrationSeedDigest(credentialBytes) == manifest.oldCredentialSHA256)
        let expectedAccounts: Set<String> = ["connection", "initial." + manifest.oldIntent.destination.rawValue]
        try #require(try newRegistrationProductAccounts() == expectedAccounts)
        let vault = KeychainRegistrationVault()
        try await vault.requireCredential(for: manifest.oldIntent, storeIdentity: manifest.oldIdentity)
        let coordinator = RegistrationCoordinator(store: services.store, vault: vault, remote: RegistrationTestRemote())
        try #require(await coordinator.restore() == .unavailable(.credentialConflict))
        try #require(await coordinator.permitsNewStoreRegistration())
        try #require(!(await coordinator.permitsInitialInput()))
        let manifestUnchanged = try Data(contentsOf: url) == data
        try #require(manifestUnchanged)
        print("S28_NEW_REGISTRATION_VERIFY token=\(context.token.uuidString.lowercased()) nonce=\(context.nonce.uuidString.lowercased()) globalHashes=match productAccounts=2 currentUUID=unchanged writerRevision=unchanged intents=0 registrations=0 confirmations=0 outbox=0 originalFiles=0")
    }
}

nonisolated private struct NewRegistrationSeedContext {
    let token: UUID
    let nonce: UUID
    let simulator: UUID
    static func load() throws -> Self {
        let environment = ProcessInfo.processInfo.environment
        let token = try #require(environment["FR_NEW_REGISTRATION_SEED_TOKEN"].flatMap(UUID.init(uuidString:)))
        let nonce = try #require(environment["FR_NEW_REGISTRATION_SEED_NONCE"].flatMap(UUID.init(uuidString:)))
        let requested = try #require(environment["FR_NEW_REGISTRATION_SIMULATOR_ID"].flatMap(UUID.init(uuidString:)))
        let actual = try #require(environment["SIMULATOR_UDID"].flatMap(UUID.init(uuidString:)))
        let allowed = UUID(uuidString: "5B5BD239-98C0-44E9-9EF3-29EB1B9A4EE5")!
        try #require(requested == allowed && actual == requested)
        try #require(token != nonce)
        return .init(token: token, nonce: nonce, simulator: requested)
    }
}

nonisolated private struct NewRegistrationSeedManifest: Codable {
    let token: UUID
    let nonce: UUID
    let simulator: UUID
    let currentIdentity: RegistrationStoreIdentity?
    let revision: UInt64
    let oldIdentity: RegistrationStoreIdentity
    let oldIntent: RegistrationIntent
    let oldConnectionSHA256: String
    let oldCredentialSHA256: String
}

private func requireEmptyNewRegistrationRoot(_ services: ProductLibraryServices, expectedRevision: UInt64,
                                           identity: RegistrationStoreIdentity?) async throws {
    guard case .loaded(let library) = await services.reader.loadLibrary() else { throw BackendContractError.unavailable }
    let backend = try await mediaSnapshot(services.store)
    let original = try await mediaOriginalSnapshot(services.store)
    try #require(library.items.isEmpty && original.originals.isEmpty && original.logicalOriginals.isEmpty)
    try #require(backend.revision == expectedRevision && backend.storeIdentity == identity)
    try #require(backend.registrationIntents.isEmpty && backend.registrations.isEmpty)
    try #require(backend.confirmations.isEmpty && backend.invalidations.isEmpty && backend.outbox.isEmpty)
    try #require(backend.requests.isEmpty && backend.temporaryMedia.isEmpty && backend.backgroundTasks.isEmpty)
    try #require(backend.photoRegistrations.isEmpty && backend.verifications.isEmpty && backend.publications.isEmpty)
    if let identity {
        let accounts = try newRegistrationProductAccounts()
        try #require(!accounts.contains(newRegistrationConnectionAccount(identity)))
        let initialPrefix = "store." + identity.rawValue.uuidString.lowercased() + ".initial."
        try #require(!accounts.contains(where: { $0.hasPrefix(initialPrefix) }))
    }
}

nonisolated private func newRegistrationSeedDigest(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
}

nonisolated private func newRegistrationProductQuery() -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: KeychainRegistrationVault.productService,
     kSecAttrSynchronizable as String: false, kSecUseDataProtectionKeychain as String: true]
}

nonisolated private func newRegistrationProductAccounts() throws -> Set<String> {
    var query = newRegistrationProductQuery()
    query[kSecReturnAttributes as String] = true
    query[kSecReturnData as String] = false
    query[kSecMatchLimit as String] = kSecMatchLimitAll
    var found: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &found)
    if status == errSecItemNotFound { return [] }
    guard status == errSecSuccess else { throw RegistrationAccessError.credentialUnavailable }
    guard let values = found as? [[String: Any]] else { throw RegistrationAccessError.corruptCredential }
    let names = values.compactMap { $0[kSecAttrAccount as String] as? String }
    guard names.count == values.count else { throw RegistrationAccessError.corruptCredential }
    return Set(names)
}

nonisolated private func newRegistrationProductBytes(_ account: String) throws -> Data? {
    var query = newRegistrationProductQuery()
    query[kSecAttrAccount as String] = account
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var found: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &found)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw RegistrationAccessError.credentialUnavailable }
    guard let data = found as? Data, !data.isEmpty, data.count <= 16_384 else { throw RegistrationAccessError.corruptCredential }
    return data
}
