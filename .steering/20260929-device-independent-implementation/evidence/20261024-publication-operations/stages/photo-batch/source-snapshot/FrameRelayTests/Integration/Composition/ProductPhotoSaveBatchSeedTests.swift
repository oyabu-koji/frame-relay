import AVFoundation
import CryptoKit
import Foundation
import Photos
import Security
import Synchronization
import Testing
import UniformTypeIdentifiers
@testable import FrameRelay

/// Only the three explicitly allocated, empty Simulator product roots are writable.
/// INSPECT never opens a product store, requests permission or changes Photos.
@Suite(.serialized) @MainActor struct ProductPhotoSaveBatchSeedTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_S31_PHOTO_BATCH_INSPECT"] == "1"))
    func inspectDedicatedPhotoLibraryWithoutOpeningProductRoot() async throws {
        let context = try photoSeedContext(mode: "INSPECT")
        try photoSeedRequireEmptyKeychain()
        let assets = try await photoSeedAssets()
        let value = PhotoSeedInspection(schema: "fr-s31-photo-baseline-v1", nonce: context.nonce,
            simulator: context.simulator, phase: context.phase, authorization: "authorizedReadWrite",
            productRootExists: FileManager.default.fileExists(atPath: try photoSeedProductRoot().path), assets: assets)
        print("S31_PHOTO_BATCH_INSPECT " + (try photoSeedJSON(value)))
        print("S31_PHOTO_BATCH_BASELINE_IDS_JSON " + (try photoSeedJSON(assets.map(\.identifier))))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_S31_PHOTO_BATCH_SEED"] == "1"))
    func seedDedicatedSourcesOnceWithManualNormalOrQueuedMaximumEntry() async throws {
        let context = try photoSeedContext(mode: "SEED")
        try photoSeedRequireEmptyKeychain()
        let baseline = try await photoSeedAssets()
        try photoSeedRequireBaselineIDs(baseline)
        let services = try await ProductLibraryFactory.shared.open()
        try await photoSeedRequireUnseededEmptyRoot(services, nonce: context.nonce)
        let scopes = RenditionScopeRegistry(leases: .init(store: services.store))
        let factory = ProductRenditionFactory(services: services, scopes: scopes)
        var sources: [PhotoSeedSource] = []
        var fixtures: [ProductRenditionFixture] = []
        for (role, suffix, local) in [("single", "s", true), ("mixedLocal", "l", true), ("mixedRemote", "r", false)] {
            let fixture = try await ProductRenditionFixture.seed(services: services,
                capture: "ps-" + String(context.nonce.prefix(8)) + "-" + suffix, local: local, duration: 3)
            let source = try await factory.photoSource(fixture.target)
            let snapshot = try await mediaSnapshot(services.store)
            let media = try #require(snapshot.temporaryMedia.first { $0.id == fixture.media })
            let binding = try await mediaOriginalSnapshot(services.store).originals.first {
                PhotoSaveBatchValueValidation.exact($0.binding.original, fixture.original)
            }?.binding
            var preservedOriginal: PhotoSeedFile?
            var reservation: PhotoSeedFile?
            if let binding {
                preservedOriginal = try photoSeedFile(try await services.originals.existingURL(for: binding.reference), base: services.run.url)
                reservation = try photoSeedFile(services.run.url.appendingPathComponent(binding.reference.rawValue + ".reservation"), base: services.run.url)
            }
            try #require((binding != nil) == local)
            sources.append(.init(role: role, source: source, mediaState: media, distribution: fixture.distribution,
                binding: binding, sourceFile: try photoSeedFile(fixture.sourceURL, base: services.run.url),
                originalFile: preservedOriginal, reservationFile: reservation,
                remoteToken: local ? nil : RemoteInventoryOriginalID(destination: source.registration.destination,
                    original: fixture.original).accessibilityToken))
            fixtures.append(fixture)
        }
        var accepted: [PhotoSaveBatch] = []
        if context.entry == "accepted" {
            // Acceptance is test-only injected Wi-Fi. Holding capture admits no
            // preparation, new use, owner or native Photos call in this process.
            let capture = CaptureMediaAdmission()
            let owner = CaptureMediaOwner(context: try CaptureFixture(clip: UUID().uuidString).context,
                visit: UUID(), nonce: UUID())
            capture.begin(owner, phases: [.recording])
            let execution = ProductPhotoSaveBatch(services: services, factory: factory, capture: capture)
            let coordinator = PhotoSaveBatchCoordinator(store: services.store, execution: execution,
                network: PhotoBatchNetwork(.wiFi), capture: capture)
            for indices in [[0], [1, 2]] {
                let revision = try await mediaSnapshot(services.store).revision
                let request = PhotoSaveBatchRequest(operation: .init(rawValue: UUID().uuidString.lowercased()),
                    targets: indices.map { fixtures[$0].target }, displayedRevision: revision)
                let response = await coordinator.submit(request)
                try #require(response == .accepted)
                await coordinator.waitForIdle()
            }
            try #require(capture.snapshot().isHeld)
            accepted = try await mediaSnapshot(services.store).photoSaveBatches.map(\.batch)
        }
        let final = try await mediaSnapshot(services.store)
        let identity = try #require(final.storeIdentity)
        let registration = try #require(final.registrations.last)
        let sentinelURL = photoSeedSentinel(services, nonce: context.nonce)
        try #require(!FileManager.default.fileExists(atPath: sentinelURL.path))
        try fixtures[0].bytes.write(to: sentinelURL, options: .withoutOverwriting)
        let sentinel = try photoSeedFile(sentinelURL, base: services.run.url.deletingLastPathComponent())
        let manifest = PhotoSeedManifest(schema: "fr-s31-photo-batch-seed-v1", nonce: context.nonce,
            simulator: context.simulator, phase: context.phase, entry: context.entry,
            identity: identity, registration: registration, rootIdentity: try ProductRenditionFixture.fileIdentity(services.run.url),
            sources: sources, accepted: accepted, baseline: baseline, sentinel: sentinel, seedRevision: final.revision)
        let file = services.run.url.appendingPathComponent("s31-photo-batch-seed.json")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(manifest)
        try bytes.write(to: file, options: .withoutOverwriting)
        try await photoSeedVerifyPreserved(services, manifest: manifest, consumedRoles: [])
        try #require(final.photoSaveBatches.count == (context.entry == "manual" ? 0 : 2))
        try #require(final.photoRegistrations.isEmpty && final.confirmations.isEmpty && final.outbox.isEmpty)
        try #require(final.temporaryMedia.allSatisfy { $0.usages.isEmpty && $0.releasedUsages.isEmpty && !$0.reclaimed })
        for batch in final.photoSaveBatches {
            try #require(batch.isCommitted)
            for child in batch.targets { try #require(child.status == .queued && child.registration == nil) }
        }
        try #require(await factory.openedOwners == 0)
        try #require(try await photoSeedAssets() == baseline)
        let digest = try renditionContent(bytes).digest
        print("S31_PHOTO_BATCH_MANIFEST_SHA256 " + digest)
        print("S31_PHOTO_BATCH_EXPECTED " + (try photoSeedJSON(photoSeedExpected(manifest, manifestDigest: digest))))
        print("S31_PHOTO_BATCH_SEED phase=\(context.phase) entry=\(context.entry) sources=3 local=2 remote=1 batches=\(accepted.count) photoRecords=0 uses=0 owners=0 keychainWrites=0 fixtureOnly=true")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_S31_PHOTO_BATCH_VERIFY"] == "1"))
    func verifyActualPhotosResultsExactJoinsAndPreservedBaselineAfterUI() async throws {
        let context = try photoSeedContext(mode: "VERIFY")
        try photoSeedRequireEmptyKeychain()
        let services = try await ProductLibraryFactory.shared.open()
        let file = services.run.url.appendingPathComponent("s31-photo-batch-seed.json")
        let bytes = try Data(contentsOf: file)
        let expectedDigest = try #require(ProcessInfo.processInfo.environment["FR_S31_PHOTO_BATCH_MANIFEST_SHA256"])
        try #require(expectedDigest.utf8.count == 64 && (try renditionContent(bytes)).digest == expectedDigest)
        let manifest = try JSONDecoder().decode(PhotoSeedManifest.self, from: bytes)
        try #require(manifest.nonce == context.nonce && manifest.simulator == context.simulator
            && manifest.phase == context.phase && manifest.entry == context.entry)
        let encodedStates = try #require(ProcessInfo.processInfo.environment["FR_S31_PHOTO_BATCH_EXPECTED_STATES_JSON"])
        try #require(encodedStates.utf8.count <= 1024)
        let states = try JSONDecoder().decode([String: String].self, from: Data(encodedStates.utf8))
        let allRoles: Set<String> = ["single", "mixedLocal", "mixedRemote"]
        try #require(Set(states.keys) == allRoles)
        try #require(states.values.allSatisfy { ["unrequested", "queued", "succeeded"].contains($0) })
        let requestedRoles = Set(states.filter { $0.value != "unrequested" }.map { $0.key })
        let succeededRoles = Set(states.filter { $0.value == "succeeded" }.map { $0.key })
        let mixedRequested = requestedRoles.contains("mixedLocal")
        try #require(mixedRequested == requestedRoles.contains("mixedRemote"))
        if manifest.entry == "accepted" { try #require(requestedRoles == allRoles) }
        var expectedBatchRoles: [Set<String>] = []
        if requestedRoles.contains("single") { expectedBatchRoles.append(["single"]) }
        if mixedRequested { expectedBatchRoles.append(["mixedLocal", "mixedRemote"]) }
        let backend = try await mediaSnapshot(services.store)
        try #require(backend.photoSaveBatches.count == expectedBatchRoles.count && backend.photoRegistrations.count == succeededRoles.count)
        try #require(Set(backend.photoSaveBatches.map(\.batch.operation)).count == expectedBatchRoles.count)
        var childIDs = Set<MediaOperationID>(), identifiers = Set<String>()
        var batchRoleSets: [Set<String>] = []
        let actualAssets = try await photoSeedAssets()
        for batch in backend.photoSaveBatches {
            try #require(batch.isCommitted && batch.batch.storeIdentity == manifest.identity)
            try #require(await services.store.lookupCommit(batch.mutation) == .committed(batch.commit))
            var roles = Set<String>()
            for child in batch.targets {
                let matching = manifest.sources.filter { PhotoSaveBatchValueValidation.exact($0.source, child.target.source) }
                let source = try #require(matching.count == 1 ? matching.first : nil)
                try #require(roles.insert(source.role).inserted && childIDs.insert(child.target.operation).inserted)
                try #require(child.target.retryOf == nil)
                let expectedState = try #require(states[source.role])
                try #require(expectedState != "unrequested")
                if expectedState == "queued" {
                    try #require(child.status == .queued && child.registration == nil)
                    continue
                }
                try #require(expectedState == "succeeded")
                guard case .starting(let started) = child.status else { throw BackendContractError.notCommitted }
                try #require(started.isCommitted && started.batch == batch.batch.operation)
                try #require(await services.store.lookupCommit(started.mutation) == .committed(started.commit))
                let record = try #require(child.registration)
                let joined = backend.photoRegistrations.filter { PhotoSaveBatchValueValidation.exact($0.registration.intent.operation, child.target.operation) }
                try #require(joined.count == 1 && joined.first == record)
                try #require(source.source.matches(record.registration) && record.registration.isCommitted)
                try #require(record.registration.expectedStoreIdentity == manifest.identity)
                try #require(await services.store.lookupCommit(record.registration.mutation) == .committed(record.registration.commit))
                try #require(record.results.count == 1 && record.presenceObservations.isEmpty && record.usageRelease == nil)
                guard case .succeeded(let identifier)? = record.outcome, let identifier else {
                    Issue.record("A limited, unknown, failed or identifier-less result does not establish complete native Photos correspondence")
                    throw BackendContractError.notCommitted
                }
                try #require(identifiers.insert(identifier.rawValue).inserted)
                let terminal = try #require(record.usageTerminal)
                let release = try #require(record.terminalUsageRelease)
                let result = try #require(record.results.first)
                try #require(terminal.terminal.termination == .sdkCompleted)
                try #require(PhotoSaveBatchValueValidation.exact(terminal.terminal.intent, record.registration.intent))
                try #require(await services.store.lookupCommit(result.mutation) == .committed(result.commit))
                try #require(await services.store.lookupCommit(terminal.mutation) == .committed(terminal.commit))
                try #require(await services.store.lookupCommit(release.mutation) == .committed(release.commit))
                let asset = try #require(actualAssets.first { $0.identifier == identifier.rawValue })
                try #require(asset.mediaType == PHAssetMediaType.video.rawValue && asset.creationDate == source.source.capturedAt)
                let videos = asset.resources.filter { $0.type == PHAssetResourceType.video.rawValue }
                try #require(videos.count == 1 && videos[0].content == source.source.rendition.deliveryContent)
                try #require(asset.duration > 2.9 && asset.duration < 3.1)
            }
            batchRoleSets.append(roles)
        }
        try #require(childIDs.count == requestedRoles.count && identifiers.count == succeededRoles.count)
        try #require(batchRoleSets.count == expectedBatchRoles.count)
        for expectedRoles in expectedBatchRoles { try #require(batchRoleSets.contains(expectedRoles)) }
        if manifest.entry == "accepted" {
            try #require(backend.photoSaveBatches.map(\.batch) == manifest.accepted)
        } else { try #require(manifest.accepted.isEmpty) }
        let baselineIDs = Set(manifest.baseline.map(\.identifier))
        try #require(baselineIDs.isDisjoint(with: identifiers))
        try #require(Set(actualAssets.map(\.identifier)) == baselineIDs.union(identifiers))
        for baseline in manifest.baseline { try #require(actualAssets.first { $0.identifier == baseline.identifier } == baseline) }
        try await photoSeedVerifyPreserved(services, manifest: manifest, consumedRoles: succeededRoles)
        let reopened = try SQLiteRecordingStore(run: services.run, mode: .openExisting,
            supportedVerificationSchemas: ["fr-final-read-v1"])
        try #require(try await mediaSnapshot(reopened) == backend)
        try #require(try Data(contentsOf: file) == bytes)
        print("S31_PHOTO_BATCH_VERIFY phase=\(context.phase) entry=\(context.entry) batches=\(expectedBatchRoles.count) children=\(childIDs.count) nativeSuccess=\(succeededRoles.count) disjointAssetIDs=\(identifiers.count) baselinePreserved=\(baselineIDs.count) assetSet=baselineUnion\(identifiers.count) resourceHashAndDate=match videoAndAudio=verified sources=3 originals=2 sentinel=match manifest=unchanged keychain=empty reopen=equal readers=0 reclaimed=\(succeededRoles.count) retained=\(3 - succeededRoles.count)")
        print("S31_PHOTO_BATCH_VERIFIED_STATES " + (try photoSeedJSON(states)))
        print("S31_PHOTO_BATCH_RESULTS " + (try photoSeedJSON(identifiers.sorted())))
    }
}

nonisolated private struct PhotoSeedContext {
    let nonce: String
    let simulator: String
    let phase: String
    var entry: String { phase == "normal" ? "manual" : "accepted" }
}
nonisolated private struct PhotoSeedFile: Codable, Equatable {
    let leaf: String
    let byteCount: UInt64
    let sha256: String
    let identity: TemporaryFileIdentity
}
nonisolated private struct PhotoSeedSource: Codable {
    let role: String
    let source: PhotoSaveSource
    let mediaState: TemporaryMediaState
    let distribution: DistributionReceipt
    let binding: OriginalBinding?
    let sourceFile: PhotoSeedFile
    let originalFile: PhotoSeedFile?
    let reservationFile: PhotoSeedFile?
    let remoteToken: String?
}
nonisolated private struct PhotoSeedResource: Codable, Equatable {
    let type: Int
    let contentType: String
    let content: ContentIdentity
}
nonisolated private struct PhotoSeedAsset: Codable, Equatable {
    let identifier: String
    let mediaType: Int
    let creationDate: Date?
    let duration: Double
    let resources: [PhotoSeedResource]
}
nonisolated private struct PhotoSeedInspection: Codable {
    let schema: String
    let nonce: String
    let simulator: String
    let phase: String
    let authorization: String
    let productRootExists: Bool
    let assets: [PhotoSeedAsset]
}
nonisolated private struct PhotoSeedManifest: Codable {
    let schema: String
    let nonce: String
    let simulator: String
    let phase: String
    let entry: String
    let identity: RegistrationStoreIdentity
    let registration: DeviceRegistration
    let rootIdentity: TemporaryFileIdentity
    let sources: [PhotoSeedSource]
    let accepted: [PhotoSaveBatch]
    let baseline: [PhotoSeedAsset]
    let sentinel: PhotoSeedFile
    let seedRevision: UInt64
}
nonisolated private struct PhotoSeedUIExpected: Encodable {
    struct Target: Encodable {
        let role: String
        let capture: String
        let rendition: String
        let media: String
        let sha256: String
        let remoteToken: String?
        let batch: String?
        let child: String?
    }
    let schema: String
    let nonce: String
    let simulator: String
    let phase: String
    let entry: String
    let storeUUID: String
    let manifestSHA256: String
    let targets: [Target]
}

nonisolated private func photoSeedContext(mode: String) throws -> PhotoSeedContext {
    let environment = ProcessInfo.processInfo.environment
    let prefix = "FR_S31_PHOTO_BATCH_"
    try #require(["SEED", "VERIFY", "INSPECT"].filter { environment[prefix + $0] == "1" } == [mode])
    let nonce = try #require(environment[prefix + "NONCE"])
    let phase = try #require(environment[prefix + "PHASE"])
    let requested = try #require(environment[prefix + "SIMULATOR_UDID"].flatMap(UUID.init(uuidString:)))
    let actual = try #require(environment["SIMULATOR_UDID"].flatMap(UUID.init(uuidString:)))
    #if !targetEnvironment(simulator)
    throw BackendContractError.unavailable
    #else
    let normal = UUID(uuidString: "E436C891-9574-42CE-9F29-6C6C1759438B")!
    let finalNormal = UUID(uuidString: "82CD3937-D91E-41D6-8907-3EA37EB7747B")!
    let maximum = UUID(uuidString: "EDAC8594-9259-4266-87DB-90000B5E558C")!
    try #require(requested == actual)
    try #require((actual == normal && phase == "normal" && nonce == "4de832b4-34b0-4a7a-a94a-1d6eb54f4868")
        || (actual == finalNormal && phase == "normal" && nonce == "5a0dfd38-7db4-4369-85cc-8104603487f5")
        || (actual == maximum && phase == "max" && nonce == "4e72ae94-8b6b-4daa-9e06-03cbe1de7e8e"))
    try #require(PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized)
    return .init(nonce: nonce, simulator: actual.uuidString, phase: phase)
    #endif
}

nonisolated private func photoSeedProductRoot() throws -> URL {
    let support = try #require(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
    return support.resolvingSymlinksInPath().appendingPathComponent("FrameRelayLibrary", isDirectory: true)
}
nonisolated private func photoSeedRequireBaselineIDs(_ assets: [PhotoSeedAsset]) throws {
    let encoded = try #require(ProcessInfo.processInfo.environment["FR_S31_PHOTO_BATCH_BASELINE_IDS_JSON"])
    try #require(encoded.utf8.count <= 16_384)
    let values = try JSONDecoder().decode([String].self, from: Data(encoded.utf8))
    try #require(values.count == Set(values).count && Set(values) == Set(assets.map(\.identifier)))
}
nonisolated private func photoSeedJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}
nonisolated private func photoSeedFile(_ url: URL, base: URL) throws -> PhotoSeedFile {
    try #require(url.deletingLastPathComponent().standardizedFileURL == base.standardizedFileURL)
    let bytes = try Data(contentsOf: url)
    return .init(leaf: url.lastPathComponent, byteCount: UInt64(bytes.count),
        sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
        identity: try ProductRenditionFixture.fileIdentity(url))
}
nonisolated private func photoSeedSentinel(_ services: ProductLibraryServices, nonce: String) -> URL {
    services.run.url.deletingLastPathComponent().appendingPathComponent("s31-photo-external-" + nonce + ".mov")
}
@MainActor private func photoSeedRequireUnseededEmptyRoot(_ services: ProductLibraryServices, nonce: String) async throws {
    let expectedRoot = try photoSeedProductRoot()
    try #require(services.run.url.standardizedFileURL == expectedRoot.standardizedFileURL)
    try #require(!FileManager.default.fileExists(atPath: photoSeedSentinel(services, nonce: nonce).path))
    let leaves = try FileManager.default.contentsOfDirectory(atPath: services.run.url.path)
    let allowed: Set<String> = ["run.marker", "recordings.sqlite", "recordings.sqlite-wal", "recordings.sqlite-shm",
        "recordings.sqlite-journal", "recordings-sqlite.lock", "originals.lock"]
    try #require(Set(leaves).isSubset(of: allowed))
    let backend = try await mediaSnapshot(services.store)
    try #require(backend.revision == 0 && backend.storeIdentity == nil)
    try #require(backend.registrationIntents.isEmpty && backend.registrations.isEmpty && backend.batches.isEmpty
        && backend.requests.isEmpty && backend.verifications.isEmpty && backend.confirmations.isEmpty
        && backend.invalidations.isEmpty && backend.outbox.isEmpty && backend.publications.isEmpty
        && backend.confirmationStates.isEmpty && backend.deliveries.isEmpty && backend.distributionObservations.isEmpty
        && backend.temporaryMedia.isEmpty && backend.photoRegistrations.isEmpty && backend.photoSaveBatches.isEmpty
        && backend.backgroundTasks.isEmpty && backend.remoteInventory.isEmpty && backend.publicationManifests.isEmpty)
    let originals = try await mediaOriginalSnapshot(services.store)
    try #require(originals.revision == 0 && originals.originals.isEmpty && originals.logicalOriginals.isEmpty && originals.removalBatches.isEmpty)
    guard case .loaded(let recordings) = await services.store.loadRecordings(),
          case .loaded(let unfinished) = await services.store.loadUnfinished() else { throw BackendContractError.unavailable }
    try #require(recordings.revision == 0 && recordings.recordings.isEmpty && unfinished.isEmpty)
    guard case .loaded(let library) = await services.reader.loadLibrary() else { throw BackendContractError.unavailable }
    try #require(library.items.isEmpty && library.history.isEmpty && library.remoteItems.isEmpty && library.photoSaveBatches.isEmpty)
}
nonisolated private func photoSeedExpected(_ manifest: PhotoSeedManifest, manifestDigest: String) -> PhotoSeedUIExpected {
    .init(schema: "fr-s31-photo-batch-ui-v1", nonce: manifest.nonce, simulator: manifest.simulator,
        phase: manifest.phase, entry: manifest.entry, storeUUID: manifest.identity.rawValue.uuidString, manifestSHA256: manifestDigest,
        targets: manifest.sources.map { source in
            let batch = manifest.accepted.first { $0.targets.contains { PhotoSaveBatchValueValidation.exact($0.source, source.source) } }
            let child = batch?.targets.first { PhotoSaveBatchValueValidation.exact($0.source, source.source) }
            return .init(role: source.role, capture: source.source.rendition.original.capture.rawValue,
                rendition: source.source.rendition.rendition.rawValue, media: source.source.media.rawValue,
                sha256: source.source.rendition.deliveryContent.digest, remoteToken: source.remoteToken,
                batch: batch?.operation.rawValue, child: child?.operation.rawValue)
        })
}

@MainActor private func photoSeedVerifyPreserved(_ services: ProductLibraryServices,
    manifest: PhotoSeedManifest, consumedRoles: Set<String>) async throws {
    try #require(manifest.schema == "fr-s31-photo-batch-seed-v1")
    try #require(manifest.sources.count == 3 && Set(manifest.sources.map(\.role)) == ["single", "mixedLocal", "mixedRemote"])
    let backend = try await mediaSnapshot(services.store)
    let originals = try await mediaOriginalSnapshot(services.store)
    try #require(backend.storeIdentity == manifest.identity && backend.registrations == [manifest.registration])
    try #require(backend.temporaryMedia.count == 3 && backend.publications.count == 3
        && backend.distributionObservations.count == 3 && backend.remoteInventory.count == 3)
    try #require(backend.registrationIntents.count == 1 && backend.invalidations.isEmpty
        && backend.confirmations.isEmpty && backend.outbox.isEmpty && backend.deliveries.isEmpty
        && backend.requests.isEmpty && backend.verifications.isEmpty && backend.backgroundTasks.isEmpty)
    try #require(backend.revision >= manifest.seedRevision)
    try #require(originals.originals.count == 2 && originals.removalBatches.isEmpty)
    try #require(originals.logicalOriginals.allSatisfy { $0.readers.isEmpty && $0.mediaReaders.isEmpty && $0.removal == nil && $0.invalidation == nil })
    try #require(try ProductRenditionFixture.fileIdentity(services.run.url) == manifest.rootIdentity)
    for copy in manifest.sources {
        let consumed = consumedRoles.contains(copy.role)
        let state = try #require(backend.temporaryMedia.first { $0.id == copy.source.media })
        try #require(PhotoSaveBatchValueValidation.exact(state.rendition, copy.source.rendition))
        try #require(PhotoSaveBatchValueValidation.exact(state.registration, copy.source.registration))
        let observations = backend.distributionObservations.filter {
            if case .succeeded(let receipt) = $0.observation.result {
                return PhotoSaveBatchValueValidation.exact(receipt, copy.distribution)
            }
            return false
        }
        try #require(observations.count == 1)
        try #require(state.directoryIdentity == copy.source.directoryIdentity && state.fileIdentity == copy.source.fileIdentity
            && state.leaf == copy.source.leaf && state.contentType == copy.source.contentType
            && state.capturedAt == copy.source.capturedAt && state.ranges == copy.mediaState.ranges
            && state.verifiedContent == copy.source.rendition.deliveryContent && state.usages.isEmpty)
        let root = try ProductRenditionFactory.root(for: copy.source.rendition.original, run: services.run)
        try #require(try ProductRenditionFixture.fileIdentity(root) == copy.source.directoryIdentity)
        let mediaURL = root.appendingPathComponent(state.leaf)
        // Reclamation completion retains its durable reclaiming history marker.
        try #require(state.reclaimed == consumed && state.reclaiming == consumed)
        if consumed {
            try #require(!FileManager.default.fileExists(atPath: mediaURL.path) && state.releasedUsages.count == 1)
        } else {
            try #require(state.releasedUsages.isEmpty)
            try #require(try renditionContent(Data(contentsOf: mediaURL)) == copy.source.rendition.deliveryContent)
            try #require(try ProductRenditionFixture.fileIdentity(mediaURL) == copy.source.fileIdentity)
        }
        try #require(try photoSeedFile(services.run.url.appendingPathComponent(copy.sourceFile.leaf), base: services.run.url) == copy.sourceFile)
        let asset = AVURLAsset(url: services.run.url.appendingPathComponent(copy.sourceFile.leaf))
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let duration = try await asset.load(.duration).seconds
        try #require(video.count == 1 && audio.count == 1 && duration > 2.9 && duration < 3.1)
        if let binding = copy.binding {
            try #require(originals.originals.contains { PhotoSaveBatchValueValidation.exact($0.binding, binding) })
            let digest = try await services.originals.digest(for: binding.reference)
            try #require(digest.byteCount == binding.original.content.byteCount && digest.sha256 == binding.original.content.digest)
            try #require(await services.originals.observeFile(binding.reference) == .present(byteCount: binding.original.content.byteCount))
            let original = try #require(copy.originalFile), reservation = try #require(copy.reservationFile)
            try #require(try photoSeedFile(services.run.url.appendingPathComponent(original.leaf), base: services.run.url) == original)
            try #require(try photoSeedFile(services.run.url.appendingPathComponent(reservation.leaf), base: services.run.url) == reservation)
        } else { try #require(copy.originalFile == nil && copy.reservationFile == nil) }
    }
    let sentinel = photoSeedSentinel(services, nonce: manifest.nonce)
    try #require(try photoSeedFile(sentinel, base: services.run.url.deletingLastPathComponent()) == manifest.sentinel)
    guard case .loaded(let library) = await services.reader.loadLibrary() else { throw BackendContractError.unavailable }
    try #require(library.items.count == 2 && library.remoteItems.count == 1 && library.history.isEmpty)
    try photoSeedRequireEmptyKeychain()
}

@MainActor private func photoSeedAssets() async throws -> [PhotoSeedAsset] {
    try #require(PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized)
    let fetch = PHAsset.fetchAssets(with: nil)
    var assets: [PHAsset] = []
    for index in 0..<fetch.count { assets.append(fetch.object(at: index)) }
    var values: [PhotoSeedAsset] = []
    for asset in assets {
        var resources: [PhotoSeedResource] = []
        for resource in PHAssetResource.assetResources(for: asset) {
            let bytes = try await photoSeedResourceBytes(resource)
            resources.append(.init(type: resource.type.rawValue, contentType: resource.contentType.identifier,
                content: try renditionContent(bytes)))
        }
        resources.sort { ($0.type, $0.contentType, $0.content.digest) < ($1.type, $1.contentType, $1.content.digest) }
        values.append(.init(identifier: asset.localIdentifier, mediaType: asset.mediaType.rawValue,
            creationDate: asset.creationDate, duration: asset.duration, resources: resources))
    }
    try #require(PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized)
    return values.sorted { $0.identifier < $1.identifier }
}

@MainActor private func photoSeedResourceBytes(_ resource: PHAssetResource) async throws -> Data {
    let options = PHAssetResourceRequestOptions(); options.isNetworkAccessAllowed = false
    let received = Mutex((bytes: Data(), overflow: false))
    return try await withCheckedThrowingContinuation { continuation in
        PHAssetResourceManager.default().requestData(for: resource, options: options) { chunk in
            received.withLock { value in
                if value.bytes.count + chunk.count <= 64 * 1_024 * 1_024 { value.bytes.append(chunk) }
                else { value.overflow = true }
            }
        } completionHandler: { error in
            if let error { continuation.resume(throwing: error); return }
            let value = received.withLock { $0 }
            if value.overflow { continuation.resume(throwing: BackendContractError.invalidValue) }
            else { continuation.resume(returning: value.bytes) }
        }
    }
}

nonisolated private func photoSeedRequireEmptyKeychain() throws {
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
