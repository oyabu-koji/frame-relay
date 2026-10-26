import Foundation
import Security
import Testing
@testable import FrameRelay

/// Four independent new complete copies let normal and maximum-text UI runs
/// consume their own bytes. A consumed copy is never repaired or re-seeded.
@Suite(.serialized) @MainActor struct ProductLocalRenditionSeedTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_S28_LOCAL_RENDITION_SEED"] == "1"))
    func seedFreshNormalAndMaximumPairsOnce() async throws {
        let context = try localRenditionSeedContext()
        try #require(context.phase == "seed")
        try #require(ProcessInfo.processInfo.environment["FR_S28_LOCAL_RENDITION_VERIFY"] != "1")
        try #require(ProcessInfo.processInfo.environment["FR_S28_LOCAL_EXPECTED_CONSUMED"] == nil)
        try #require(ProcessInfo.processInfo.environment["FR_S28_LOCAL_EXPECTED_CONFIRMED"] == nil)
        let services = try await ProductLibraryFactory.shared.open()
        let file = services.run.url.appendingPathComponent("s28-local-rendition-seed.json")
        try #require(!FileManager.default.fileExists(atPath: file.path))
        let initial = try await mediaSnapshot(services.store)
        guard case .loaded(let library) = await services.reader.loadLibrary() else { throw BackendContractError.unavailable }
        try #require(initial.revision == 0 && initial.storeIdentity == nil && initial.registrations.isEmpty
            && initial.registrationIntents.isEmpty && initial.temporaryMedia.isEmpty
            && initial.publications.isEmpty && library.items.isEmpty && library.remoteItems.isEmpty)
        try localRenditionRequireEmptyProductKeychain()
        var copies: [LocalRenditionSeedCopy] = []
        for phase in ["normal", "max"] {
            for kind in ["local", "remote"] {
                let capture = "s28lr-" + context.nonce + "-" + phase + "-" + kind
                let fixture = try await ProductRenditionFixture.seed(services: services, capture: capture,
                    local: kind == "local", duration: kind == "local" ? 180 : 30)
                let snapshot = try await mediaSnapshot(services.store)
                let state = try #require(snapshot.temporaryMedia.first { $0.id == fixture.media })
                let binding = try await mediaOriginalSnapshot(services.store).originals.first {
                    $0.binding.original == fixture.original
                }?.binding
                try #require((binding != nil) == (kind == "local"))
                copies.append(.init(phase: phase, kind: kind, original: fixture.original,
                    rendition: fixture.rendition, distribution: fixture.distribution,
                    media: fixture.media, mediaState: state, binding: binding,
                    sourceLeaf: fixture.sourceURL.lastPathComponent,
                    content: try renditionContent(fixture.bytes),
                    sourceIdentity: try ProductRenditionFixture.fileIdentity(fixture.sourceURL)))
            }
        }
        let beforeNegative = try await mediaSnapshot(services.store)
        let registration = try #require(beforeNegative.registrations.last)
        let identity = try #require(beforeNegative.storeIdentity)
        let negative = try inventoryOriginal("s28lr-" + context.nonce + "-unacquired", digit: "e")
        let negativeRendition = RenditionIdentity(original: negative, inputLogIdentity: "synthetic-not-log",
            transformAssetIdentity: "no-formal-proof", transformAssetVersion: "fixture-only-v1",
            outputConfigurationIdentity: "unacquired-fixture", conversionVersion: "fixture-only",
            rendition: .init(rawValue: UUID().uuidString.lowercased()), deliveryContent: negative.content,
            publicationGeneration: .init(rawValue: 1))
        _ = try await mediaCommit(services.store, .publication(mediaPublication(negativeRendition,
            registration: registration.server.registration)))
        _ = try await inventoryCommit(services.store, inventoryObservation(identity, registration, originals: [negative]))
        let first = try #require(copies.first)
        let sentinel = localRenditionSeedSentinel(services, nonce: context.nonce)
        let bytes = try Data(contentsOf: services.run.url.appendingPathComponent(first.sourceLeaf))
        try bytes.write(to: sentinel, options: .withoutOverwriting)
        let final = try await mediaSnapshot(services.store)
        let manifest = LocalRenditionSeedManifest(schema: "fr-s28-local-rendition-seed-v1",
            nonce: context.nonce, simulator: context.simulator, identity: identity,
            registration: registration, copies: copies, negative: negative, negativeRendition: negativeRendition,
            sentinel: try renditionContent(bytes), seedRevision: final.revision)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: file, options: .withoutOverwriting)
        try await localRenditionVerifySeed(services, manifest: manifest, phase: "seed")
        print("S28_LOCAL_RENDITION_SEED nonce=\(context.nonce) copies=4 local=2 remote=2 unacquired=1 uses=0 confirmations=0 photos=0 keychainWrites=0 fixtureOnly=true")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_S28_LOCAL_RENDITION_VERIFY"] == "1"))
    func verifyConsumedCopiesAndRetainedOriginalsAfterUI() async throws {
        let context = try localRenditionSeedContext()
        try #require(ProcessInfo.processInfo.environment["FR_S28_LOCAL_RENDITION_SEED"] != "1")
        let services = try await ProductLibraryFactory.shared.open()
        let file = services.run.url.appendingPathComponent("s28-local-rendition-seed.json")
        let bytes = try Data(contentsOf: file)
        let manifest = try JSONDecoder().decode(LocalRenditionSeedManifest.self, from: bytes)
        try #require(manifest.nonce == context.nonce && manifest.simulator == context.simulator)
        try await localRenditionVerifySeed(services, manifest: manifest, phase: context.phase)
        let reopened = try SQLiteRecordingStore(run: services.run, mode: .openExisting,
            supportedVerificationSchemas: ["fr-final-read-v1"])
        let current = try await mediaSnapshot(services.store)
        let replay = try await mediaSnapshot(reopened)
        try #require(current == replay)
        let unchanged = try Data(contentsOf: file) == bytes
        try #require(unchanged)
        let consumedSet = try localRenditionExpectedConsumption(phase: context.phase)
        let consumed = consumedSet.count
        let confirmed = try localRenditionExpectedConfirmation(consumed: consumedSet).count
        print("S28_LOCAL_RENDITION_VERIFY nonce=\(context.nonce) phase=\(context.phase) consumedAndReclaimed=\(consumed) unusedRetained=\(4 - consumed) sourceHashes=4 managedOriginalHashes=2 sentinel=match manifest=unchanged reopen=equal confirmations=\(confirmed) outbox=\(confirmed) logicalReaders=0 mediaReaders=0 keychainWrites=0")
    }
}

nonisolated private struct LocalRenditionSeedCopy: Codable {
    let phase: String
    let kind: String
    let original: OriginalContent
    let rendition: RenditionIdentity
    let distribution: DistributionReceipt
    let media: TemporaryMediaID
    let mediaState: TemporaryMediaState
    let binding: OriginalBinding?
    let sourceLeaf: String
    let content: ContentIdentity
    let sourceIdentity: TemporaryFileIdentity
}

nonisolated private struct LocalRenditionSeedManifest: Codable {
    let schema: String
    let nonce: String
    let simulator: String
    let identity: RegistrationStoreIdentity
    let registration: DeviceRegistration
    let copies: [LocalRenditionSeedCopy]
    let negative: OriginalContent
    let negativeRendition: RenditionIdentity
    let sentinel: ContentIdentity
    let seedRevision: UInt64
}

@MainActor private func localRenditionVerifySeed(_ services: ProductLibraryServices,
    manifest: LocalRenditionSeedManifest, phase: String) async throws {
    try #require(manifest.schema == "fr-s28-local-rendition-seed-v1" && ["seed", "normal", "max"].contains(phase))
    let expectedConsumption = try localRenditionExpectedConsumption(phase: phase)
    let expectedConfirmation = try localRenditionExpectedConfirmation(consumed: expectedConsumption)
    let consumed = manifest.copies.filter { expectedConsumption.contains($0.phase + "." + $0.kind) }
    let confirmed = manifest.copies.filter { expectedConfirmation.contains($0.phase + "." + $0.kind) }
    let backend = try await mediaSnapshot(services.store)
    let originals = try await mediaOriginalSnapshot(services.store)
    try #require(manifest.copies.count == 4 && Set(manifest.copies.map(\.media)).count == 4)
    try #require(consumed.count == expectedConsumption.count)
    try #require(confirmed.count == expectedConfirmation.count)
    try #require(backend.storeIdentity == manifest.identity && backend.registrations == [manifest.registration])
    try #require(backend.registrationIntents.count == 1 && backend.remoteInventory.count == 5
        && backend.publications.count == 5 && backend.distributionObservations.count == 4
        && backend.temporaryMedia.count == 4)
    try #require(backend.revision >= manifest.seedRevision)
    if phase == "seed" { try #require(backend.revision == manifest.seedRevision) }
    try #require(backend.confirmations.count == confirmed.count && backend.outbox.count == confirmed.count)
    try #require(backend.invalidations.isEmpty && backend.deliveries.isEmpty && backend.requests.isEmpty
        && backend.verifications.isEmpty && backend.photoRegistrations.isEmpty && backend.backgroundTasks.isEmpty)
    try #require(originals.originals.count == 2 && originals.removalBatches.isEmpty)
    try #require(originals.logicalOriginals.allSatisfy {
        $0.readers.isEmpty && $0.mediaReaders.isEmpty && $0.removal == nil && $0.invalidation == nil
    })
    let expectedBindings = manifest.copies.compactMap(\.binding)
    try #require(originals.originals.map(\.binding) == expectedBindings)
    for copy in manifest.copies {
        let state = try #require(backend.temporaryMedia.first { $0.id == copy.media })
        try #require(PublicationStoreBoundary.exact(state.rendition, copy.rendition)
            && PublicationStoreBoundary.exact(state.registration, manifest.registration.server.registration))
        try #require(state.fileIdentity == copy.mediaState.fileIdentity
            && state.directoryIdentity == copy.mediaState.directoryIdentity && state.leaf == copy.mediaState.leaf
            && state.ranges == copy.mediaState.ranges && state.verifiedContent == copy.content && state.usages.isEmpty)
        let root = try ProductRenditionFactory.root(for: copy.original, run: services.run)
        let mediaURL = root.appendingPathComponent(state.leaf)
        let expectedConsumed = expectedConsumption.contains(copy.phase + "." + copy.kind)
        try #require(state.reclaimed == expectedConsumed)
        if expectedConsumed {
            try #require(!FileManager.default.fileExists(atPath: mediaURL.path))
            try #require(state.releasedUsages.count == 2)
        } else {
            try #require(!state.reclaiming && state.releasedUsages.isEmpty)
            let actual = try renditionContent(Data(contentsOf: mediaURL))
            try #require(actual == copy.content)
            let physical = try ProductRenditionFixture.fileIdentity(mediaURL)
            try #require(physical == copy.mediaState.fileIdentity)
        }
        if expectedConfirmation.contains(copy.phase + "." + copy.kind) {
            let record = try #require(backend.confirmations.first {
                PublicationStoreBoundary.exact($0.intent.playback.distribution.rendition, copy.rendition)
            })
            try #require(record.commit.matches(record.intent.key, revision: record.commit.previousRevision)
                && PublicationStoreBoundary.exact(record.commit.key, record.intent.key)
                && PublicationStoreBoundary.exact(record.intent.playback.distribution, copy.distribution)
                && record.intent.playback.invalidationGeneration.rawValue == 0
                && UUID(uuidString: record.intent.playback.session.rawValue) != nil)
            try #require(backend.outbox.contains(.confirmation(record)))
            let confirmation = try #require(backend.confirmationStates.first {
                PublicationStoreBoundary.exact($0.registration, manifest.registration.server.registration)
                    && PublicationStoreBoundary.exact($0.current, copy.rendition)
            })
            try #require(confirmation.validConfirmation == record)
        } else {
            try #require(!backend.confirmations.contains {
                PublicationStoreBoundary.exact($0.intent.playback.distribution.rendition, copy.rendition)
            })
            try #require(!backend.outbox.contains {
                if case .confirmation(let record) = $0 {
                    return PublicationStoreBoundary.exact(record.intent.playback.distribution.rendition, copy.rendition)
                }
                return false
            })
            try #require(backend.confirmationStates.filter {
                PublicationStoreBoundary.exact($0.registration, manifest.registration.server.registration)
                    && PublicationStoreBoundary.exact($0.current, copy.rendition)
            }.allSatisfy { $0.validConfirmation == nil })
        }
        let source = services.run.url.appendingPathComponent(copy.sourceLeaf)
        let sourceContent = try renditionContent(Data(contentsOf: source))
        let sourceIdentity = try ProductRenditionFixture.fileIdentity(source)
        try #require(sourceContent == copy.content && sourceIdentity == copy.sourceIdentity)
        if let binding = copy.binding {
            let digest = try await services.originals.digest(for: binding.reference)
            try #require(digest.sha256 == binding.original.content.digest && digest.byteCount == binding.original.content.byteCount)
        }
    }
    let sentinel = try renditionContent(Data(contentsOf: localRenditionSeedSentinel(services, nonce: manifest.nonce)))
    try #require(sentinel == manifest.sentinel)
    try localRenditionRequireEmptyProductKeychain()
    guard case .loaded(let library) = await services.reader.loadLibrary() else { throw BackendContractError.unavailable }
    try #require(library.items.count == 2 && library.history.isEmpty && library.remoteItems.count == 3)
    try #require(!backend.temporaryMedia.contains { $0.rendition.original == manifest.negative })
    try #require(!backend.confirmations.contains { $0.intent.playback.distribution.rendition.original == manifest.negative })
    let sessions = backend.confirmations.map { $0.intent.playback.session }
    try #require(Set(sessions).count == sessions.count)
}

nonisolated private func localRenditionExpectedConsumption(phase: String) throws -> Set<String> {
    let allowed: Set<String> = ["normal.local", "normal.remote", "max.local", "max.remote"]
    guard let encoded = ProcessInfo.processInfo.environment["FR_S28_LOCAL_EXPECTED_CONSUMED"] else {
        return phase == "max" ? allowed : phase == "normal" ? ["normal.local", "normal.remote"] : []
    }
    return try localRenditionExpectedCopySet(encoded)
}

nonisolated private func localRenditionExpectedConfirmation(consumed: Set<String>) throws -> Set<String> {
    guard let encoded = ProcessInfo.processInfo.environment["FR_S28_LOCAL_EXPECTED_CONFIRMED"] else { return consumed }
    let result = try localRenditionExpectedCopySet(encoded)
    try #require(result.isSubset(of: consumed))
    return result
}

nonisolated private func localRenditionExpectedCopySet(_ encoded: String) throws -> Set<String> {
    let allowed: Set<String> = ["normal.local", "normal.remote", "max.local", "max.remote"]
    try #require(encoded.utf8.count <= 512)
    let values = try JSONDecoder().decode([String].self, from: Data(encoded.utf8))
    let result = Set(values)
    try #require(values.count <= 4 && result.count == values.count && result.isSubset(of: allowed))
    return result
}

nonisolated private func localRenditionSeedContext() throws -> (nonce: String, simulator: String, phase: String) {
    let environment = ProcessInfo.processInfo.environment
    let nonce = try #require(environment["FR_S28_LOCAL_RENDITION_NONCE"])
    let requested = try #require(environment["FR_S28_LOCAL_RENDITION_SIMULATOR_UDID"])
    let actual = try #require(environment["SIMULATOR_UDID"])
    let phase = try #require(environment["FR_S28_LOCAL_RENDITION_PHASE"])
    try #require(RemoteInventoryValidation.canonicalID(nonce) && ["seed", "normal", "max"].contains(phase))
    let requestedIdentity = try #require(UUID(uuidString: requested))
    let actualIdentity = try #require(UUID(uuidString: actual))
    let dedicated: Set<UUID> = [UUID(uuidString: "32123811-3702-4F30-A198-CEC7F743D711")!,
        UUID(uuidString: "D4AFACDE-F4C0-4527-8A0A-1E64A8BB4F03")!,
        UUID(uuidString: "FFAC5EB6-0006-4186-ABD8-503013CA4ECC")!,
        UUID(uuidString: "19086AB5-0EC7-4CE2-ADDE-A7C2939E1675")!,
        UUID(uuidString: "842A7F12-8232-4248-A78A-87757694B6D9")!,
        UUID(uuidString: "76647BEF-D2F9-4883-B6BC-F34AA9F4DA4E")!]
    try #require(requestedIdentity == actualIdentity && dedicated.contains(actualIdentity))
    return (nonce, actualIdentity.uuidString, phase)
}

nonisolated private func localRenditionSeedSentinel(_ services: ProductLibraryServices, nonce: String) -> URL {
    services.run.url.deletingLastPathComponent().appendingPathComponent("s28-local-rendition-external-" + nonce + ".mov")
}

nonisolated private func localRenditionRequireEmptyProductKeychain() throws {
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
