import Darwin
import Foundation
import Testing
@testable import FrameRelay

/// A new dedicated root with a real movie/full hash/inodes and a positive
/// distribution observation committed through the actual common writer.
/// The remote receipt is explicitly synthetic, not a formal producer proof.
@MainActor struct ProductRenditionFixture {
    let libraryFactory: ProductLibraryFactory
    let services: ProductLibraryServices
    let identity: RegistrationStoreIdentity
    let registration: RegistrationIdentity
    let original: OriginalContent
    let rendition: RenditionIdentity
    let distribution: DistributionReceipt
    let media: TemporaryMediaID
    let root: URL
    let mediaURL: URL
    let sourceURL: URL
    let localReference: CaptureOriginalReference?
    let bytes: Data

    static func make(local: Bool = false, duration: Double = 4) async throws -> Self {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("FrameRelay-local-rendition-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: false)
        let library = ProductLibraryFactory(supportDirectory: support)
        let services = try await library.open()
        return try await seed(services: services, libraryFactory: library,
            capture: "local-rendition-" + UUID().uuidString.lowercased(), local: local, duration: duration)
    }

    static func seed(services: ProductLibraryServices, libraryFactory: ProductLibraryFactory = .shared,
                     capture: String, local: Bool, duration: Double = 4) async throws -> Self {
        let source = services.run.url.appendingPathComponent("source-" + capture + ".mov")
        try #require(!FileManager.default.fileExists(atPath: source.path))
        if duration > 60 {
            guard duration == ProductRenditionPresentationMovie.durationSeconds else { throw CaptureContractError.invalidValue }
            try await ProductRenditionPresentationMovie.write(to: source)
        } else {
            try await SyntheticMovieFixture.write(to: source, withAudio: true, durationSeconds: duration)
        }
        let bytes = try Data(contentsOf: source), content = try renditionContent(bytes)
        let snapshot = try await mediaSnapshot(services.store)
        let registration: RegistrationIdentity
        if let current = snapshot.registrations.last { registration = current.server.registration }
        else { registration = try await inventoryRegister(services.store).server.registration }
        let identity = try #require(try await mediaSnapshot(services.store).storeIdentity)
        let original = OriginalContent(capture: .init(rawValue: capture), generation: .init(rawValue: 1), content: content)
        var localReference: CaptureOriginalReference?
        if local {
            let binding = try await statusKnownOriginal(original, store: services.store)
            let originalURL = try await services.originals.reserve(original: binding.reference)
            try bytes.write(to: originalURL, options: .withoutOverwriting)
            let digest = try await services.originals.digest(for: binding.reference)
            let observation = await services.originals.observeFile(binding.reference)
            try #require(digest.byteCount == content.byteCount && digest.sha256 == content.digest)
            try #require(observation == .present(byteCount: content.byteCount))
            localReference = binding.reference
        }
        let rendition = RenditionIdentity(original: original, inputLogIdentity: "synthetic-not-log",
            transformAssetIdentity: "no-formal-proof", transformAssetVersion: "fixture-only-v1",
            outputConfigurationIdentity: "synthetic-local-movie", conversionVersion: "fixture-only",
            rendition: .init(rawValue: UUID().uuidString.lowercased()), deliveryContent: content,
            publicationGeneration: .init(rawValue: 1))
        _ = try await mediaCommit(services.store, .publication(mediaPublication(rendition, registration: registration)))
        let committedRegistration = try #require(try await mediaSnapshot(services.store).registrations.last)
        _ = try await inventoryCommit(services.store, inventoryObservation(identity, committedRegistration, originals: [original]))
        let leases = RenditionReadLeases(store: services.store)
        let lease = try await leases.acquire(rendition: rendition, registration: registration,
            operation: .init(rawValue: UUID().uuidString), context: .transport(.init(rawValue: UUID().uuidString)))
        let operation = MediaOperationID(rawValue: UUID().uuidString)
        let distribution = DistributionReceipt(operation: operation, rendition: rendition, registration: registration,
            commit: .init(key: .distribution(operation, rendition, registration), previousRevision: 0, committedRevision: 1))
        _ = try await mediaCommit(services.store, .distribution(.init(command: .init(rawValue: UUID().uuidString), lease: lease,
            observation: .init(rawValue: 1), result: .succeeded(distribution))))
        try await leases.release(lease) // No SDK/reader was ever started by this fixture producer.
        let root = try ProductRenditionFactory.root(for: original, run: services.run)
        if !FileManager.default.fileExists(atPath: root.deletingLastPathComponent().path) {
            try FileManager.default.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: false)
        }
        try #require(!FileManager.default.fileExists(atPath: root.path))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try Data().write(to: root.appendingPathComponent("owner.lock"), options: .withoutOverwriting)
        let id = TemporaryMediaID(rawValue: UUID().uuidString)
        let leaf = try TemporaryMediaLeaf.make(contentType: "video/quicktime")
        let state = TemporaryMediaState(id: id, rendition: rendition, registration: registration,
            capturedAt: RenditionFixture.capturedAt, leaf: leaf, contentType: "video/quicktime",
            directoryIdentity: try fileIdentity(root))
        _ = try await mediaCommit(services.store, .temporary(command: .init(rawValue: UUID().uuidString), value: .create(state)))
        let mediaURL = root.appendingPathComponent(leaf)
        try bytes.write(to: mediaURL, options: .withoutOverwriting)
        _ = try await mediaCommit(services.store, .temporary(command: .init(rawValue: UUID().uuidString),
            value: .fileCreated(id, try fileIdentity(mediaURL))))
        _ = try await mediaCommit(services.store, .temporary(command: .init(rawValue: UUID().uuidString),
            value: .stored(id, try .init(lowerBound: 0, upperBound: content.byteCount))))
        let physical = try renditionContent(Data(contentsOf: mediaURL))
        try #require(physical == content)
        _ = try await mediaCommit(services.store, .temporary(command: .init(rawValue: UUID().uuidString), value: .verified(id, content)))
        return .init(libraryFactory: libraryFactory, services: services, identity: identity, registration: registration,
            original: original, rendition: rendition, distribution: distribution, media: id, root: root,
            mediaURL: mediaURL, sourceURL: source, localReference: localReference, bytes: bytes)
    }

    nonisolated static func fileIdentity(_ url: URL) throws -> TemporaryFileIdentity {
        var value = stat()
        guard lstat(url.path, &value) == 0, value.st_mode & S_IFMT != S_IFLNK else { throw BackendContractError.unavailable }
        return .init(device: Int64(value.st_dev), inode: UInt64(value.st_ino))
    }
    func factory(scopes: RenditionScopeRegistry? = nil) -> ProductRenditionFactory {
        ProductRenditionFactory(services: services, scopes: scopes ?? RenditionScopeRegistry(leases: .init(store: services.store)))
    }
    var target: LibraryRenditionTarget { .init(original: original, destination: registration.destination) }
}
