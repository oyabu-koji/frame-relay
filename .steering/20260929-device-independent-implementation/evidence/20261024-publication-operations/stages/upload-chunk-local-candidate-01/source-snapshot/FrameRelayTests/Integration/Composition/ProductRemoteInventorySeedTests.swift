import CryptoKit
import Foundation
import Security
import Testing
@testable import FrameRelay

/// Test-target-only setup of a dedicated empty normal root. The product App
/// receives no fixture environment, success factory or command on launch.
@Suite(.serialized) @MainActor struct ProductRemoteInventorySeedTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_S28_INVENTORY_SEED"] == "1"))
    func seedDedicatedNormalRoot() async throws {
        let context = try inventorySeedContext()
        try #require(ProcessInfo.processInfo.environment["FR_S28_INVENTORY_VERIFY"] != "1")
        let input = try #require(ProcessInfo.processInfo.environment["FR_S28_INVENTORY_REFUSED_ORIGIN"])
        let endpoint = try RegistrationEndpoint(httpsOrigin: input)
        let parts = try #require(URLComponents(url: endpoint.origin, resolvingAgainstBaseURL: false))
        try #require(parts.host == "127.0.0.1" && parts.port != nil)
        let services = try await ProductLibraryFactory.shared.open()
        let manifestURL = services.run.url.appendingPathComponent("s28-inventory-seed.json")
        try #require(!FileManager.default.fileExists(atPath: manifestURL.path))
        let initial = try await mediaSnapshot(services.store)
        guard case .loaded(let library) = await services.reader.loadLibrary() else { throw BackendContractError.unavailable }
        try #require(initial.revision == 0 && initial.storeIdentity == nil && initial.registrationIntents.isEmpty
            && initial.registrations.isEmpty && initial.remoteInventory.isEmpty && library.items.isEmpty && library.remoteItems.isEmpty)
        try inventoryRequireEmptyProductKeychain()
        let identity = try await establishRegistrationIdentity(services.store)
        let connection = try RegistrationConnection(endpoint: endpoint,
            destination: .init(rawValue: "9a3ba104-985f-4a2d-875d-d458258b9b6b"))
        let vault = KeychainRegistrationVault()
        try await vault.saveConnection(connection, bearer: "synthetic-inventory-bootstrap-" + context.nonce, storeIdentity: identity)
        let intent = try await vault.prepareIntent(for: connection.destination, storeIdentity: identity)
        _ = try await inventorySeedCommit(services.store, .registrationIntent(intent), identity: identity)
        _ = try await inventorySeedCommit(services.store, .registration(.init(intent: intent,
            registration: .init(destination: connection.destination, id: .init(rawValue: UUID().uuidString.lowercased()),
                generation: .init(rawValue: 1)))), identity: identity)
        let registered = try #require(try await mediaSnapshot(services.store).registrations.last)
        let fixture = OriginalRemovalFixture(run: services.run, store: services.store,
            files: services.originals, access: services.access)
        let prefix = "s28i-" + context.nonce
        let local = try await fixture.original(prefix + "-local", unknown: true)
        let conflict = OriginalContent(capture: local.original.capture, generation: local.original.generation,
            content: try .init(byteCount: local.original.content.byteCount, algorithm: "sha256", digest: String(repeating: "f", count: 64)))
        let remoteA = try inventoryOriginal(prefix + "-remote-a")
        let remoteB = try inventoryOriginal(prefix + "-remote-b", digit: "b")
        let observed = inventoryObservation(identity, registered, originals: [local.original, conflict, remoteA, remoteB])
        let receipt = try await inventoryCommit(services.store, observed)
        let localURL = try await services.originals.existingURL(for: local.reference)
        let data = try Data(contentsOf: localURL)
        let sentinel = inventorySeedSentinel(services, nonce: context.nonce)
        try data.write(to: sentinel, options: .withoutOverwriting)
        let manifest = InventorySeedManifest(nonce: context.nonce, simulator: context.simulator, identity: identity,
            registration: registered, origin: input, local: local, observation: observed, observationCommit: receipt,
            sentinel: try renditionContent(data), connectionHash: try inventoryProductKeychainHash("connection"),
            credentialHash: try inventoryProductKeychainHash("initial." + connection.destination.rawValue))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .withoutOverwriting)
        try await inventoryVerifySeed(services, manifest: manifest)
        print("S28_INVENTORY_SEED nonce=\(context.nonce) local=1 remoteRows=3 conflict=1 missingDate=3 logicalOriginals=1 realMOV=retained external=retained mediaRequests=0 confirmation=0 ack=0 fixtureOnly=true")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_S28_INVENTORY_VERIFY"] == "1"))
    func verifyNormalRootAfterUIAndReopen() async throws {
        let context = try inventorySeedContext()
        try #require(ProcessInfo.processInfo.environment["FR_S28_INVENTORY_SEED"] != "1")
        let services = try await ProductLibraryFactory.shared.open()
        let manifestURL = services.run.url.appendingPathComponent("s28-inventory-seed.json")
        let bytes = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(InventorySeedManifest.self, from: bytes)
        try #require(manifest.nonce == context.nonce && manifest.simulator == context.simulator)
        try await inventoryVerifySeed(services, manifest: manifest)
        let unchanged = try Data(contentsOf: manifestURL) == bytes
        try #require(unchanged)
        print("S28_INVENTORY_VERIFY nonce=\(context.nonce) local=1 remoteRows=3 conflict=1 date=unknown realMOV=hash-match external=hash-match manifest=unchanged credentials=hash-match logicalReaders=0 mediaReaders=0 mediaRequests=0 confirmation=0 ack=0")
    }
}

nonisolated private struct InventorySeedManifest: Codable {
    let nonce: String
    let simulator: String
    let identity: RegistrationStoreIdentity
    let registration: DeviceRegistration
    let origin: String
    let local: OriginalBinding
    let observation: RemoteInventoryObservation
    let observationCommit: BackendCommitReceipt
    let sentinel: ContentIdentity
    let connectionHash: String
    let credentialHash: String
}

@MainActor private func inventoryVerifySeed(_ services: ProductLibraryServices, manifest: InventorySeedManifest) async throws {
    let backend = try await mediaSnapshot(services.store)
    let state = try await mediaOriginalSnapshot(services.store)
    try #require(backend.storeIdentity == manifest.identity && backend.registrations == [manifest.registration])
    try #require(backend.registrationIntents.count == 1 && backend.remoteInventory.count == 1)
    try #require(backend.remoteInventory[0].observation == manifest.observation && backend.remoteInventory[0].commit == manifest.observationCommit)
    try #require(backend.requests.isEmpty && backend.verifications.isEmpty && backend.publications.isEmpty
        && backend.confirmations.isEmpty && backend.invalidations.isEmpty && backend.outbox.isEmpty
        && backend.photoRegistrations.isEmpty && backend.backgroundTasks.isEmpty)
    try #require(state.logicalOriginals.count == 1 && state.originals.count == 1 && state.removalBatches.isEmpty)
    try #require(state.originals[0].binding == manifest.local)
    try #require(state.logicalOriginals.allSatisfy { $0.readers.isEmpty && $0.mediaReaders.isEmpty })
    let digest = try await services.originals.digest(for: manifest.local.reference)
    try #require(digest.sha256 == manifest.local.original.content.digest && digest.byteCount == manifest.local.original.content.byteCount)
    let external = try renditionContent(Data(contentsOf: inventorySeedSentinel(services, nonce: manifest.nonce)))
    try #require(external == manifest.sentinel)
    let connectionUnchanged = try inventoryProductKeychainHash("connection") == manifest.connectionHash
    let credentialUnchanged = try inventoryProductKeychainHash("initial." + manifest.registration.server.registration.destination.rawValue) == manifest.credentialHash
    try #require(connectionUnchanged && credentialUnchanged)
    guard case .loaded(let library) = await services.reader.loadLibrary() else { throw BackendContractError.unavailable }
    try #require(library.items.count == 1 && library.items[0].original == manifest.local.original && library.history.isEmpty)
    try #require(library.remoteItems.count == 3 && Set(library.remoteItems.map(\.id)).count == 3)
    try #require(library.remoteItems.filter(\.hasIdentityConflict).count == 1)
    try #require(library.remoteItems.allSatisfy { $0.captureDateDescription == "撮影日時不明" })
}

nonisolated private func inventorySeedContext() throws -> (nonce: String, simulator: String) {
    let env = ProcessInfo.processInfo.environment
    let nonce = try #require(env["FR_S28_INVENTORY_NONCE"])
    let requested = try #require(env["FR_S28_INVENTORY_SIMULATOR_UDID"])
    let actual = try #require(env["SIMULATOR_UDID"])
    try #require(RemoteInventoryValidation.canonicalID(nonce))
    let dedicated = UUID(uuidString: "FCEE8D70-F5E1-4566-91CE-2BFE917582DE")!
    try #require(UUID(uuidString: requested) == dedicated && UUID(uuidString: actual) == dedicated)
    return (nonce, dedicated.uuidString)
}
nonisolated private func inventorySeedSentinel(_ services: ProductLibraryServices, nonce: String) -> URL {
    services.run.url.deletingLastPathComponent().appendingPathComponent("s28-inventory-external-" + nonce + ".mov")
}
nonisolated private func inventoryProductQuery(_ account: String? = nil) -> [String: Any] {
    var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: KeychainRegistrationVault.productService,
        kSecAttrSynchronizable as String: false, kSecUseDataProtectionKeychain as String: true]
    if let account { query[kSecAttrAccount as String] = account }
    return query
}
nonisolated private func inventoryRequireEmptyProductKeychain() throws {
    var query = inventoryProductQuery(); query[kSecReturnAttributes as String] = true
    query[kSecReturnData as String] = false; query[kSecMatchLimit as String] = kSecMatchLimitAll
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecItemNotFound else {
        throw RegistrationAccessError.credentialConflict
    }
}
nonisolated private func inventoryProductKeychainHash(_ account: String) throws -> String {
    var query = inventoryProductQuery(account); query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var value: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess, let data = value as? Data else {
        throw RegistrationAccessError.credentialUnavailable
    }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
nonisolated private func inventorySeedCommit(_ store: any MediaOperationStorePort, _ change: BackendStoreChange,
    identity: RegistrationStoreIdentity) async throws -> BackendCommitReceipt {
    let snapshot = try await mediaSnapshot(store)
    guard case .committed(let receipt) = await store.commit(.init(expectedRevision: snapshot.revision,
        change: change, expectedStoreIdentity: identity)) else { throw BackendContractError.notCommitted }
    return receipt
}
