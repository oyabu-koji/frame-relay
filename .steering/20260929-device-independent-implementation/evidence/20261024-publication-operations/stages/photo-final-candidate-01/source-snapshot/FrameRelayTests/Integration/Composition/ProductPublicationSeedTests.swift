import Foundation
import Security
import Testing
@testable import FrameRelay

/// A one-time, test-target-only seed of a fresh normal App root. All publication
/// metadata is synthetic; no network, standard transform or Photos is claimed.
@Suite(.serialized) @MainActor struct ProductPublicationSeedTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_S28_PUBLICATION_SEED"] == "1"))
    func seedFreshDedicatedNormalRoot() async throws {
        let context = try publicationSeedContext()
        try #require(ProcessInfo.processInfo.environment["FR_S28_PUBLICATION_VERIFY"] != "1")
        let services = try await ProductLibraryFactory.shared.open()
        let manifestURL = services.run.url.appendingPathComponent("s28-publication-seed.json")
        try #require(!FileManager.default.fileExists(atPath: manifestURL.path))
        let initial = try await mediaSnapshot(services.store)
        guard case .loaded(let library) = await services.reader.loadLibrary() else { throw BackendContractError.unavailable }
        try #require(initial.revision == 0 && initial.storeIdentity == nil && initial.registrationIntents.isEmpty
            && initial.registrations.isEmpty && initial.remoteInventory.isEmpty && initial.publicationManifests.isEmpty
            && library.items.isEmpty && library.remoteItems.isEmpty)
        try publicationRequireEmptyProductKeychain()
        let identity = try await establishRegistrationIdentity(services.store)
        let destination = DestinationIdentity(rawValue: "43c78072-535b-4590-8645-b8ecdf16cd78")
        let prefix = "s28p-" + context.nonce
        let pending = try inventoryOriginal(prefix + "-remote-pending", digit: "b")
        let unpublished = try inventoryOriginal(prefix + "-remote-unpublished", digit: "c")
        let historical = try inventoryOriginal(prefix + "-remote-history", digit: "d")
        let old = try await publicationSeedRegister(services.store, identity: identity, destination: destination, generation: 1)
        let oldCatalog = inventoryObservation(identity, old, originals: [historical])
        let oldCatalogCommit = try await inventoryCommit(services.store, oldCatalog)
        let oldRendition = publicationSeedRendition(historical, version: 9,
            id: "00000000-0000-4000-8000-000000009099")
        let oldManifest = PublicationManifestObservation(command: .init(rawValue: UUID().uuidString.lowercased()),
            storeIdentity: identity, registration: old.server.registration, original: historical,
            manifest: .init(current: oldRendition, revision: 9, invalidationGeneration: .init(rawValue: 0),
                replacementPending: false, mediaType: "video/quicktime"))
        let oldManifestCommit = try await publicationSeedCommit(services.store, .publicationManifest(oldManifest), identity: identity)
        let current = try await publicationSeedRegister(services.store, identity: identity, destination: destination, generation: 2)
        let fixture = OriginalRemovalFixture(run: services.run, store: services.store,
            files: services.originals, access: services.access)
        // The real H264/PCM MOV retains the actual inspection's unknown Log
        // classification. Its bytes do not serve as a published rendition.
        let local = try await fixture.original(prefix + "-local", unknown: true)
        let catalog = inventoryObservation(identity, current, originals: [local.original, pending, unpublished, historical])
        let catalogCommit = try await inventoryCommit(services.store, catalog)
        let localRendition = publicationSeedRendition(local.original, version: 1,
            id: "00000000-0000-4000-8000-000000001011")
        let pendingRendition = publicationSeedRendition(pending, version: 2,
            id: "00000000-0000-4000-8000-000000002022")
        let remote = StatusMetadataRemote()
        remote.manifests = [
            (local.original, .succeeded(.init(current: localRendition, revision: 1,
                invalidationGeneration: .init(rawValue: 0), replacementPending: false, mediaType: "video/quicktime"))),
            (pending, .succeeded(.init(current: pendingRendition, revision: 2,
                invalidationGeneration: .init(rawValue: 0), replacementPending: true, mediaType: "video/quicktime"))),
            (unpublished, .succeeded(.init(current: nil, revision: 0,
                invalidationGeneration: .init(rawValue: 0), replacementPending: false, mediaType: nil)))
        ]
        let coordinator = BackendStatusSynchronizationCoordinator(store: services.store, identity: identity,
            registration: current, remote: remote,
            invalidations: statusInvalidator(store: services.store, identity: identity, run: services.run))
        let result = await coordinator.synchronize()
        // The historical-only original has no current-registration response.
        // Its old metadata remains durable and must not appear as current.
        try #require(result.phase == .partial && result.items.count == 4)
        try #require(remote.manifestCalls.count == 4 && remote.mediaCalls == 0 && remote.sent.isEmpty)
        let backend = try await mediaSnapshot(services.store)
        try #require(backend.publicationManifests.count == 4)
        let observations = backend.publicationManifests.map {
            PublicationSeedObservation(observation: $0.observation, commit: $0.commit)
        }
        try #require(observations.first?.observation == oldManifest && observations.first?.commit == oldManifestCommit)
        let source = try await services.originals.existingURL(for: local.reference)
        let bytes = try Data(contentsOf: source)
        let sentinel = publicationSeedSentinel(services, nonce: context.nonce)
        try bytes.write(to: sentinel, options: .withoutOverwriting)
        let manifest = PublicationSeedManifest(nonce: context.nonce, simulator: context.simulator, identity: identity,
            oldRegistration: old, registration: current, local: local,
            oldCatalog: oldCatalog, oldCatalogCommit: oldCatalogCommit, catalog: catalog, catalogCommit: catalogCommit,
            observations: observations, localRendition: localRendition, pendingRendition: pendingRendition,
            oldRendition: oldRendition, sentinel: try renditionContent(bytes), revision: backend.revision)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .withoutOverwriting)
        try await publicationVerifySeed(services, manifest: manifest)
        print("S28_PUBLICATION_SEED nonce=\(context.nonce) local=1 remoteRows=3 manifests=4 currentManifests=3 historical=1 currentPublications=2 realMOV=retained sentinel=retained mediaRequests=0 confirmation=0 ack=0 keychainWrites=0 fixtureOnly=true")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_S28_PUBLICATION_VERIFY"] == "1"))
    func verifyAfterUIAndIndependentStoreReopen() async throws {
        let context = try publicationSeedContext()
        try #require(ProcessInfo.processInfo.environment["FR_S28_PUBLICATION_SEED"] != "1")
        let services = try await ProductLibraryFactory.shared.open()
        let file = services.run.url.appendingPathComponent("s28-publication-seed.json")
        let bytes = try Data(contentsOf: file)
        let manifest = try JSONDecoder().decode(PublicationSeedManifest.self, from: bytes)
        try #require(manifest.nonce == context.nonce && manifest.simulator == context.simulator)
        try await publicationVerifySeed(services, manifest: manifest)
        let reopened = try SQLiteRecordingStore(run: services.run, mode: .openExisting,
            supportedVerificationSchemas: ["fr-final-read-v1"])
        let actual = try await mediaSnapshot(services.store)
        let replay = try await mediaSnapshot(reopened)
        try #require(actual == replay)
        let manifestUnchanged = try Data(contentsOf: file) == bytes
        try #require(manifestUnchanged)
        print("S28_PUBLICATION_VERIFY nonce=\(context.nonce) local=1 remoteRows=3 manifest=unchanged original=hash-match sentinel=hash-match writerReopen=equal logicalReaders=0 mediaReaders=0 confirmation=0 ack=0 photos=0 keychainWrites=0")
    }
}

nonisolated private struct PublicationSeedObservation: Codable {
    let observation: PublicationManifestObservation
    let commit: BackendCommitReceipt
}

nonisolated private struct PublicationSeedManifest: Codable {
    let nonce: String
    let simulator: String
    let identity: RegistrationStoreIdentity
    let oldRegistration: DeviceRegistration
    let registration: DeviceRegistration
    let local: OriginalBinding
    let oldCatalog: RemoteInventoryObservation
    let oldCatalogCommit: BackendCommitReceipt
    let catalog: RemoteInventoryObservation
    let catalogCommit: BackendCommitReceipt
    let observations: [PublicationSeedObservation]
    let localRendition: RenditionIdentity
    let pendingRendition: RenditionIdentity
    let oldRendition: RenditionIdentity
    let sentinel: ContentIdentity
    let revision: UInt64
}

@MainActor private func publicationVerifySeed(_ services: ProductLibraryServices, manifest: PublicationSeedManifest) async throws {
    let backend = try await mediaSnapshot(services.store)
    let state = try await mediaOriginalSnapshot(services.store)
    try #require(backend.storeIdentity == manifest.identity && backend.revision == manifest.revision)
    try #require(backend.registrations == [manifest.oldRegistration, manifest.registration] && backend.registrationIntents.count == 2)
    try #require(backend.remoteInventory.count == 2 && backend.publicationManifests.count == manifest.observations.count)
    try #require(backend.remoteInventory[0].observation == manifest.oldCatalog && backend.remoteInventory[0].commit == manifest.oldCatalogCommit)
    try #require(backend.remoteInventory[1].observation == manifest.catalog && backend.remoteInventory[1].commit == manifest.catalogCommit)
    for (stored, expected) in zip(backend.publicationManifests, manifest.observations) {
        try #require(PublicationStoreBoundary.exact(stored.observation, expected.observation)
            && PublicationStoreBoundary.exact(stored.commit, expected.commit) && stored.isCommitted)
    }
    try #require(backend.publications.count == 2 && backend.publications.allSatisfy {
        $0.observation.registration == manifest.registration.server.registration
    })
    try #require(backend.requests.isEmpty && backend.verifications.isEmpty && backend.confirmations.isEmpty
        && backend.invalidations.isEmpty && backend.outbox.isEmpty && backend.deliveries.isEmpty
        && backend.photoRegistrations.isEmpty && backend.backgroundTasks.isEmpty && backend.temporaryMedia.isEmpty
        && backend.distributionObservations.isEmpty)
    try #require(state.originals.count == 1 && state.originals[0].binding == manifest.local && state.removalBatches.isEmpty)
    try #require(state.logicalOriginals.allSatisfy {
        $0.readers.isEmpty && $0.mediaReaders.isEmpty && $0.invalidation == nil && $0.removal == nil
    })
    let digest = try await services.originals.digest(for: manifest.local.reference)
    try #require(digest.sha256 == manifest.local.original.content.digest && digest.byteCount == manifest.local.original.content.byteCount)
    let sentinel = try renditionContent(Data(contentsOf: publicationSeedSentinel(services, nonce: manifest.nonce)))
    try #require(sentinel == manifest.sentinel)
    try publicationRequireEmptyProductKeychain()
    guard case .loaded(let library) = await services.reader.loadLibrary() else { throw BackendContractError.unavailable }
    try #require(library.items.count == 1 && library.items[0].original == manifest.local.original && library.history.isEmpty)
    try #require(library.items[0].status(.publication).contains(manifest.localRendition.rendition.rawValue))
    try #require(library.items[0].status(.retrieval).contains("オフライン再生不可"))
    try #require(library.items[0].status(.confirmation).contains("明示確認なし"))
    try #require(library.remoteItems.count == 3 && library.remoteItems.allSatisfy { !$0.hasIdentityConflict })
    try #require(library.remoteItems.allSatisfy { $0.captureDateDescription == "撮影日時不明" })
}

nonisolated private func publicationSeedContext() throws -> (nonce: String, simulator: String) {
    let environment = ProcessInfo.processInfo.environment
    let nonce = try #require(environment["FR_S28_PUBLICATION_NONCE"])
    let requested = try #require(environment["FR_S28_PUBLICATION_SIMULATOR_UDID"])
    let actual = try #require(environment["SIMULATOR_UDID"])
    try #require(RemoteInventoryValidation.canonicalID(nonce))
    let dedicated = UUID(uuidString: "8D2B4837-8EC9-4A8B-9511-6914BFD0EE85")!
    try #require(UUID(uuidString: requested) == dedicated && UUID(uuidString: actual) == dedicated)
    return (nonce, dedicated.uuidString)
}

@MainActor private func publicationSeedRegister(_ store: any MediaOperationStorePort, identity: RegistrationStoreIdentity,
    destination: DestinationIdentity, generation: UInt64) async throws -> DeviceRegistration {
    let intent = RegistrationIntent(operation: .init(rawValue: UUID().uuidString.lowercased()), destination: destination)
    _ = try await publicationSeedCommit(store, .registrationIntent(intent), identity: identity)
    let registration = RegistrationIdentity(destination: destination, id: .init(rawValue: UUID().uuidString.lowercased()),
        generation: .init(rawValue: generation))
    _ = try await publicationSeedCommit(store, .registration(.init(intent: intent, registration: registration)), identity: identity)
    return try #require(try await mediaSnapshot(store).registrations.last)
}

nonisolated private func publicationSeedRendition(_ original: OriginalContent, version: UInt64, id: String) -> RenditionIdentity {
    .init(original: original, inputLogIdentity: "technical-publication-fixture", transformAssetIdentity: "no-formal-proof",
        transformAssetVersion: "fixture-v1", outputConfigurationIdentity: "fixture-output", conversionVersion: "fixture-conversion",
        rendition: .init(rawValue: id), deliveryContent: original.content, publicationGeneration: .init(rawValue: version))
}

nonisolated private func publicationSeedSentinel(_ services: ProductLibraryServices, nonce: String) -> URL {
    services.run.url.deletingLastPathComponent().appendingPathComponent("s28-publication-external-" + nonce + ".mov")
}

nonisolated private func publicationRequireEmptyProductKeychain() throws {
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: KeychainRegistrationVault.productService,
        kSecAttrSynchronizable as String: false, kSecUseDataProtectionKeychain as String: true,
        kSecReturnAttributes as String: true, kSecReturnData as String: false,
        kSecMatchLimit as String: kSecMatchLimitAll]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecItemNotFound else {
        throw RegistrationAccessError.credentialConflict
    }
}

nonisolated private func publicationSeedCommit(_ store: any MediaOperationStorePort, _ change: BackendStoreChange,
    identity: RegistrationStoreIdentity) async throws -> BackendCommitReceipt {
    let snapshot = try await mediaSnapshot(store)
    guard case .committed(let receipt) = await store.commit(.init(expectedRevision: snapshot.revision,
        change: change, expectedStoreIdentity: identity)) else { throw BackendContractError.notCommitted }
    return receipt
}
