import Foundation
import Testing
@testable import FrameRelay

/// Every invocation makes a new synthetic root. No existing product fixtures,
/// Photos assets or original files are repaired, removed or reseeded.
@MainActor struct ProductPhotoSaveBatchFixture {
    let parent: URL
    let services: ProductLibraryServices
    let library: ProductLibraryFactory
    let renditions: [ProductRenditionFixture]
    let factory: ProductRenditionFactory
    let capture: CaptureMediaAdmission
    let network: PhotoBatchNetwork
    let photos: PhotoBatchLibrary
    let execution: ProductPhotoSaveBatch

    static func make(locals: [Bool] = [false], photos providedPhotos: PhotoBatchLibrary? = nil) async throws -> Self {
        // Construct the actor in this function body, outside a default-argument thunk.
        let photos: PhotoBatchLibrary
        if let providedPhotos { photos = providedPhotos }
        else { photos = PhotoBatchLibrary(outcomes: [.succeeded(localIdentifier: nil)]) }
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("FrameRelay-photo-batch-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        let library = ProductLibraryFactory(supportDirectory: parent, photoLibrary: photos)
        let services = try await library.open()
        var renditions: [ProductRenditionFixture] = []
        for (index, local) in locals.enumerated() {
            renditions.append(try await ProductRenditionFixture.seed(services: services, libraryFactory: library,
                capture: "photo-batch-\(index)-" + UUID().uuidString, local: local, duration: 1))
        }
        let factory = ProductRenditionFactory(services: services,
            scopes: .init(leases: .init(store: services.store)))
        let capture = CaptureMediaAdmission(), network = PhotoBatchNetwork(.wiFi)
        return .init(parent: parent, services: services, library: library, renditions: renditions,
            factory: factory, capture: capture, network: network, photos: photos,
            execution: ProductPhotoSaveBatch(services: services, factory: factory, capture: capture))
    }

    func coordinator(store: (any MediaOperationStorePort)? = nil,
                     execution: (any PhotoSaveBatchExecutionPort)? = nil,
                     didChange: @escaping @Sendable () async -> Void = {}) -> PhotoSaveBatchCoordinator {
        .init(store: store ?? services.store, execution: execution ?? self.execution, network: network, capture: capture, didChange: didChange)
    }
    func request() async throws -> PhotoSaveBatchRequest {
        .init(operation: .init(rawValue: UUID().uuidString), targets: renditions.map(\.target),
            displayedRevision: try await mediaSnapshot(services.store).revision)
    }
    func assertSourcesUnchanged() throws {
        for rendition in renditions {
            #expect(try Data(contentsOf: rendition.sourceURL) == rendition.bytes)
        }
    }
}

nonisolated final class PhotoBatchNetwork: PhotoSaveStartNetworkPort, @unchecked Sendable {
    private let lock = NSLock()
    private var value: NetworkCondition
    init(_ value: NetworkCondition) { self.value = value }
    func set(_ value: NetworkCondition) { lock.lock(); self.value = value; lock.unlock() }
    func currentCondition() -> NetworkCondition { lock.lock(); defer { lock.unlock() }; return value }
}

/// A controlled local port, not an assertion that PhotoKit succeeded. Native
/// PhotoKit is a separately flagged probe on its own dedicated simulator.
actor PhotoBatchLibrary: PhotoLibraryPort {
    private var outcomes: [PhotoRegistrationOutcome]
    private var blockAdd = false
    private var addContinuation: CheckedContinuation<Void, Never>?
    private(set) var commands: [PhotoLibraryAddCommand] = []
    private(set) var statusCalls: [PhotoLibraryAccess] = []
    private(set) var permissionCalls: [PhotoLibraryAccess] = []
    private(set) var lookupCalls: [PhotoAssetIdentifier] = []
    init(outcomes: [PhotoRegistrationOutcome]) { self.outcomes = outcomes }
    func authorizationStatus(for access: PhotoLibraryAccess) -> PhotoLibraryAuthorization {
        statusCalls.append(access); return .authorized
    }
    func requestAuthorization(for access: PhotoLibraryAccess) -> PhotoLibraryAuthorization {
        permissionCalls.append(access); return .denied
    }
    func lookup(_ identifier: PhotoAssetIdentifier) -> PhotoLibraryLookupResult {
        lookupCalls.append(identifier); return .init(identifier: identifier, authorization: .authorized, presence: .present)
    }
    func holdAdd() { blockAdd = true }
    func finishAdd() { blockAdd = false; addContinuation?.resume(); addContinuation = nil }
    func add(_ command: PhotoLibraryAddCommand) async -> PhotoRegistrationResult {
        commands.append(command)
        if blockAdd { await withCheckedContinuation { addContinuation = $0 } }
        let outcome = outcomes.count > 1 ? outcomes.removeFirst() : outcomes.first ?? .unknown(localIdentifier: nil)
        return .init(intent: command.registration.intent, outcome: outcome)
    }
}

actor PhotoBatchPreparationGate: PhotoSaveBatchExecutionPort {
    let base: ProductPhotoSaveBatch
    private var blocked = false
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var prepared = 0
    init(base: ProductPhotoSaveBatch) { self.base = base }
    func source(for target: LibraryRenditionTarget) async throws -> PhotoSaveSource { try await base.source(for: target) }
    func prepare(_ target: PhotoSaveBatchTarget) async throws -> any PreparedPhotoSavePort {
        let value = try await base.prepare(target)
        prepared += 1
        if blocked { await withCheckedContinuation { continuation = $0 } }
        return value
    }
    func hold() { blocked = true }
    func release() { blocked = false; continuation?.resume(); continuation = nil }
}

/// A real single writer loses only its begin response/lookup, with the original
/// mutation retained verbatim. It never substitutes an optimistic store result.
actor PhotoBatchBeginFaultStore: MediaOperationStorePort {
    let base: SQLiteRecordingStore
    private var hidden = true
    private var blockCommit = true
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var beginMutation: BackendStoreMutation?
    private(set) var beginCommits = 0
    private(set) var lookups: [BackendStoreMutation] = []
    init(base: SQLiteRecordingStore) { self.base = base }
    func load() async -> BackendStoreLoadResult { await base.load() }
    func commit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        guard case .photoBatch(_, .beginChild) = mutation.change else { return await base.commit(mutation) }
        beginMutation = mutation; beginCommits += 1
        _ = await base.commit(mutation)
        if blockCommit { await withCheckedContinuation { continuation = $0 } }
        return .unknown
    }
    func lookupCommit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        lookups.append(mutation)
        if case .photoBatch(_, .beginChild) = mutation.change, hidden { return .unknown }
        return await base.lookupCommit(mutation)
    }
    func reveal() { hidden = false; blockCommit = false; continuation?.resume(); continuation = nil }
}

@MainActor func photoBatchEventually(_ condition: @escaping @MainActor @Sendable () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(8))
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return false
}

nonisolated func photoBatchCommit(_ store: SQLiteRecordingStore, identity: RegistrationStoreIdentity,
                                  command: MediaOperationID, change: PhotoSaveBatchChange) async throws -> BackendCommitReceipt {
    let snapshot = try await mediaSnapshot(store)
    let mutation = BackendStoreMutation(expectedRevision: snapshot.revision,
        change: .photoBatch(command: command, value: change), expectedStoreIdentity: identity)
    guard case .committed(let receipt) = await store.commit(mutation),
          await store.lookupCommit(mutation) == .committed(receipt) else { throw BackendContractError.notCommitted }
    return receipt
}
