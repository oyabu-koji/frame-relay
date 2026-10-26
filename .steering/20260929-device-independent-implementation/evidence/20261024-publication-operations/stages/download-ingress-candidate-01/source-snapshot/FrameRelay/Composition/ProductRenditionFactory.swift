import CryptoKit
import Foundation

nonisolated struct ProductRenditionOwner: Sendable {
    let scope: RenditionMediaScope
    let temporary: ManagedTemporaryMedia
    let player: AVRenditionPlayback
}

nonisolated struct ProductRenditionSource: Sendable {
    let selection: LocalRenditionSelection
    let owner: ProductRenditionOwner
    let receipt: TemporaryMediaReceipt
    var usage: TemporaryMediaUsage { receipt.usage }
}

nonisolated private struct ProductRenditionReleaseKey: Hashable, Sendable {
    let temporary: ObjectIdentifier
    /// Full encoded usage, including media, purpose and epoch. Opaque strings
    /// must not join through Swift's Unicode-normalizing String equality.
    let usage: Data
}

/// App-lifetime local consumer. It has no network factory, creates no cache
/// directories or media, and uses the same registry as invalidation/removal.
actor ProductRenditionFactory {
    private let services: ProductLibraryServices
    private let scopes: RenditionScopeRegistry
    private let leases: RenditionReadLeases
    private let photoStore: any MediaOperationStorePort
    private let photoCaptureStart: (any PhotoSaveCaptureStartPort)?
    private var owners: [String: ProductRenditionOwner] = [:]
    private var opening: [String: Task<ProductRenditionOwner, Error>] = [:]
    private var confirmations: [RegistrationStoreIdentity: MediaConfirmationCoordinator] = [:]
    private var photoCoordinators: [ObjectIdentifier: PhotoSaveCoordinator] = [:]
    private var photoRegistryGeneration: UInt64 = 0
    private var photoRegistryExhausted = false
    private var photoStopTasks: [UUID: Task<CaptureMediaLocalStop, Never>] = [:]
    private var releases: [ProductRenditionReleaseKey: (id: UUID, task: Task<Bool, Never>)] = [:]
    private(set) var openedOwners = 0
    private(set) var releaseContentions = 0

    init(services: ProductLibraryServices, scopes: RenditionScopeRegistry,
         photoStore: (any MediaOperationStorePort)? = nil,
         photoCaptureStart: (any PhotoSaveCaptureStartPort)? = nil) {
        self.services = services; self.scopes = scopes
        self.photoStore = photoStore ?? services.store
        self.photoCaptureStart = photoCaptureStart
        leases = RenditionReadLeases(store: services.store)
    }

    nonisolated static func root(for original: OriginalContent, run: ExplorationRunDirectory) throws -> URL {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let hash = SHA256.hash(data: try encoder.encode(original)).map { String(format: "%02x", $0) }.joined()
        return run.url.appendingPathComponent("renditions-v1", isDirectory: true).appendingPathComponent(hash, isDirectory: true)
    }

    func selection(_ target: LibraryRenditionTarget) async throws -> LocalRenditionSelection {
        for _ in 0..<3 {
            guard case .loaded(let backend) = await services.store.load(),
                  case .succeeded(let originals) = await services.store.loadOriginalState() else {
                throw BackendContractError.unavailable
            }
            if backend.revision != originals.revision { continue }
            return try LocalRenditionSelection.select(backend: backend, originals: originals, target: target)
        }
        throw BackendContractError.revisionConflict
    }

    /// Opening an owner starts no media use or SDK playback. It is separate
    /// from acquiring a handoff and coalesces concurrent factory consumers.
    func openOwner(_ target: LibraryRenditionTarget) async throws -> ProductRenditionOwner {
        let selected = try await selection(target)
        return try await owner(for: selected.rendition.original)
    }

    func prepare(_ target: LibraryRenditionTarget) async throws -> ProductRenditionSource {
        try await prepare(target, purpose: .playback)
    }

    func photoSource(_ target: LibraryRenditionTarget) async throws -> PhotoSaveSource {
        let value = try await selection(target)
        guard let file = value.media.fileIdentity else { throw BackendContractError.ineligibleOriginal }
        return .init(storeIdentity: value.identity, registration: value.registration, rendition: value.rendition,
            media: value.media.id, capturedAt: value.media.capturedAt, directoryIdentity: value.media.directoryIdentity,
            fileIdentity: file, leaf: value.media.leaf, contentType: value.media.contentType)
    }

    func preparePhoto(_ source: PhotoSaveSource) async throws -> ProductRenditionSource {
        let target = LibraryRenditionTarget(original: source.rendition.original, destination: source.registration.destination)
        guard PublicationStoreBoundary.exact(try await photoSource(target), source) else { throw BackendContractError.staleGeneration }
        let value = try await prepare(target, purpose: .photoHandoff)
        do {
            guard PublicationStoreBoundary.exact(try await photoSource(target), source) else { throw BackendContractError.staleGeneration }
            return value
        } catch { _ = await release(value); throw error }
    }

    /// Retry preparation does not allocate an extra use. The existing Photos
    /// coordinator acquires its fresh use once, when the explicit retry runs.
    func photoOwner(_ source: PhotoSaveSource) async throws -> ProductRenditionOwner {
        let target = LibraryRenditionTarget(original: source.rendition.original, destination: source.registration.destination)
        guard PublicationStoreBoundary.exact(try await photoSource(target), source) else { throw BackendContractError.staleGeneration }
        let value = try await owner(for: source.rendition.original)
        guard PublicationStoreBoundary.exact(try await photoSource(target), source) else { throw BackendContractError.staleGeneration }
        return value
    }

    func photoCoordinator(owner: ProductRenditionOwner, identity: RegistrationStoreIdentity) -> PhotoSaveCoordinator {
        let key = ObjectIdentifier(owner.temporary)
        if let existing = photoCoordinators[key] { return existing }
        let value = PhotoSaveCoordinator(store: photoStore, identity: identity,
            temporaryMedia: owner.temporary, library: services.photoLibrary, captureStart: photoCaptureStart)
        photoCoordinators[key] = value
        if photoRegistryGeneration == UInt64.max { photoRegistryExhausted = true }
        else { photoRegistryGeneration += 1 }
        return value
    }

    /// Only this factory's already known owners are joined/recovered. No scope
    /// is opened, old SDK owner adopted, media copied or Photos call replayed.
    func waitForPhotoLocalStop(owner: CaptureMediaOwner) async -> CaptureMediaLocalStop {
        guard let capture = photoCaptureStart as? CaptureMediaAdmission else { return .unknown }
        let changes = capture.changes()
        let pair = AsyncStream<CaptureMediaLocalStop>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        let actual = Task { [self] in
            let result = await observePhotoLocalStop(owner: owner, capture: capture)
            pair.continuation.yield(result); pair.continuation.finish()
            photoStopTasks.removeValue(forKey: id)
            return result
        }
        photoStopTasks[id] = actual
        let monitor = Task {
            for await _ in changes {
                if capture.snapshot().owners[owner] == nil {
                    pair.continuation.yield(.cancelled); pair.continuation.finish()
                    return
                }
            }
        }
        var iterator = pair.stream.makeAsyncIterator()
        let result = await iterator.next() ?? .unknown
        monitor.cancel()
        guard capture.snapshot().owners[owner] != nil else { return .cancelled }
        // The actual join remains retained if this REC/visit was cancelled.
        // Neither cancellation nor a dropped waiter closes the SDK/file owner.
        return result
    }

    private func observePhotoLocalStop(owner: CaptureMediaOwner, capture: CaptureMediaAdmission) async -> CaptureMediaLocalStop {
        for _ in 0..<3 {
            let captureState = capture.snapshot()
            guard captureState.owners[owner] != nil else { return .cancelled }
            guard !photoRegistryExhausted,
                  case .loaded(let initial) = await services.store.load() else { return .unknown }
            let registry = photoRegistryGeneration
            if initial.storeIdentity == nil {
                return await observeUnregisteredPhotoStop(initial, owner: owner, capture: capture,
                    captureRevision: captureState.revision, registry: registry)
            }
            guard let identity = initial.storeIdentity,
                  let claims = PhotoSaveDispatchClaims.shared.generation(for: identity) else { return .unknown }
            let coordinators = Array(photoCoordinators.values)
            for coordinator in coordinators {
                guard await coordinator.waitForCaptureLocalStop() else { return .unknown }
                guard capture.snapshot().owners[owner] != nil else { return .cancelled }
            }
            guard case .loaded(let backend) = await services.store.load(), backend.storeIdentity == identity,
                  case .succeeded(let originals) = await services.store.loadOriginalState() else { return .unknown }
            guard backend.revision == originals.revision else { continue }
            guard PhotoSaveStartStoreBoundary.photoReadersStopped(backend: backend, originals: originals) else { return .unknown }
            for record in backend.photoRegistrations {
                guard let proof = PhotoSaveStartStoreBoundary.localStopProof(record, identity: identity) else { return .unknown }
                for (mutation, expected) in proof {
                    guard case .committed(let actual) = await services.store.lookupCommit(mutation),
                          PhotoSaveBatchValueValidation.exact(actual, expected) else { return .unknown }
                }
            }
            guard capture.snapshot().owners[owner] != nil else { return .cancelled }
            guard case .loaded(let latest) = await services.store.load(), latest.storeIdentity == identity,
                  latest.revision == backend.revision else { continue }
            let finalCapture = capture.snapshot()
            guard finalCapture.owners[owner] != nil else { return .cancelled }
            guard finalCapture.revision == captureState.revision,
                  photoRegistryGeneration == registry, !photoRegistryExhausted,
                  PhotoSaveDispatchClaims.shared.generation(for: identity) == claims else { continue }
            return .ready
        }
        return .unknown
    }

    /// A normal fresh/recording-only library does not need registration or a
    /// generated UUID to record. Nil identity is safe only with no possible
    /// Photos owner/readers and a fresh unchanged same-writer observation.
    private func observeUnregisteredPhotoStop(_ initial: BackendStoreSnapshot, owner: CaptureMediaOwner,
        capture: CaptureMediaAdmission, captureRevision: UInt64, registry: UInt64) async -> CaptureMediaLocalStop {
        guard photoCoordinators.isEmpty, initial.photoRegistrations.isEmpty, initial.photoSaveBatches.isEmpty,
              initial.temporaryMedia.allSatisfy({ $0.usages.isEmpty }),
              case .succeeded(let originals) = await services.store.loadOriginalState(),
              originals.revision == initial.revision,
              originals.logicalOriginals.allSatisfy({ $0.readers.isEmpty && $0.mediaReaders.isEmpty
                  && $0.readersReleased(in: originals.reconciliationEpoch) }),
              case .loaded(let latest) = await services.store.load(), latest.storeIdentity == nil,
              latest.revision == initial.revision else { return .unknown }
        let current = capture.snapshot()
        guard current.owners[owner] != nil else { return .cancelled }
        guard current.revision == captureRevision, photoCoordinators.isEmpty, !photoRegistryExhausted,
              photoRegistryGeneration == registry else { return .unknown }
        return .ready
    }

    func reconcileKnownPhotoSave(_ source: PhotoSaveSource) async {
        let target = LibraryRenditionTarget(original: source.rendition.original, destination: source.registration.destination)
        guard let current = try? await photoSource(target), PublicationStoreBoundary.exact(current, source),
              let root = try? Self.root(for: source.rendition.original, run: services.run),
              let owner = owners[root.lastPathComponent],
              let coordinator = photoCoordinators[ObjectIdentifier(owner.temporary)] else { return }
        // No new owner/coordinator is created. Only this live instance can know
        // that a lost intent response returned before it invoked PhotoKit.
        _ = await coordinator.restore()
    }

    private func prepare(_ target: LibraryRenditionTarget, purpose: TemporaryMediaPurpose) async throws -> ProductRenditionSource {
        let selected = try await selection(target)
        let owner = try await owner(for: selected.rendition.original)
        try Task.checkCancellation()
        guard await owner.player.phase != .releaseNeedsReconciliation,
              selected.sameSource(as: try await selection(target)) else { throw BackendContractError.staleGeneration }
        guard case .succeeded(let usage) = await owner.temporary.acquireUsage(selected.media.id, purpose: purpose,
            usageID: .init(rawValue: UUID().uuidString)) else { throw BackendContractError.ineligibleOriginal }
        do {
            // inspect performs the independent full hash and named/root/inode
            // checks. A snapshot's verifiedContent is not physical file proof.
            guard case .succeeded(let receipt) = await owner.temporary.inspect(selected.media.id),
                  selected.sameSource(as: try await selection(target)) else { throw BackendContractError.identityMismatch }
            try Task.checkCancellation()
            let state = try await owner.temporary.stateFor(selected.media.id)
            let actual = state.receipt(for: usage)
            guard receipt.hasCompleteCoverage, actual.hasCompleteCoverage, !actual.isReleased,
                  actual.verifiedContent == selected.rendition.deliveryContent else { throw BackendContractError.identityMismatch }
            return .init(selection: selected, owner: owner, receipt: actual)
        } catch {
            _ = await release(usage, temporary: owner.temporary)
            throw error
        }
    }

    func release(_ source: ProductRenditionSource) async -> Bool {
        guard PublicationStoreBoundary.exact(source.usage.media, source.receipt.id) else { return false }
        return await release(source.usage, temporary: source.owner.temporary)
    }

    private func release(_ usage: TemporaryMediaUsage, temporary: ManagedTemporaryMedia) async -> Bool {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let encoded = try? encoder.encode(usage) else { return false }
        let key = ProductRenditionReleaseKey(temporary: ObjectIdentifier(temporary), usage: encoded)
        if let existing = releases[key] { return await existing.task.value }
        let id = UUID()
        // This retained task owns cleanup even if its waiting UI task was
        // cancelled. It only releases this live source's exact own usage.
        let task = Task { await self.releaseWhenIdle(usage, temporary: temporary) }
        releases[key] = (id, task)
        let result = await task.value
        if releases[key]?.id == id { releases.removeValue(forKey: key) }
        return result
    }

    private func releaseWhenIdle(_ usage: TemporaryMediaUsage, temporary: ManagedTemporaryMedia) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while true {
            switch await temporary.releaseUsage(usage) {
            case .succeeded(let media): return PublicationStoreBoundary.exact(media, usage.media)
            case .inProgress:
                // A concurrent read/inspection keeps ManagedTemporaryMedia's
                // per-media busy gate across awaits. It has not rejected or
                // released this usage; retry only that definite busy response.
                releaseContentions += 1
                guard ContinuousClock.now < deadline else { return false }
                try? await Task.sleep(for: .milliseconds(5))
            case .unknown, .failed, .notExecuted:
                // Unknown may include a lost durable response. Never infer
                // termination or retry that mutation by treating it as busy.
                return false
            }
        }
    }

    func confirm(_ token: PlaybackToken, action: MediaOperationID,
                 identity: RegistrationStoreIdentity) async -> BackendOutcome<ConfirmationRecord> {
        let coordinator: MediaConfirmationCoordinator
        if let existing = confirmations[identity] { coordinator = existing }
        else {
            coordinator = MediaConfirmationCoordinator(store: services.store, identity: identity)
            confirmations[identity] = coordinator
        }
        return await coordinator.confirm(token, action: action)
    }

    private func owner(for original: OriginalContent) async throws -> ProductRenditionOwner {
        let root = try Self.root(for: original, run: services.run)
        let key = root.lastPathComponent
        if let value = owners[key] {
            do { try await value.scope.checkAdmission(); return value }
            catch { owners.removeValue(forKey: key) }
        }
        if let task = opening[key] { return try await task.value }
        let task = Task { [scopes, leases] in
            let scope = try await scopes.open(original: original)
            let temporary = try await ManagedTemporaryMedia.open(root: root, leases: leases, scope: scope,
                createIfMissing: false)
            let player = try await AVRenditionPlayback.open(leases: leases, temporary: temporary, scope: scope) { _ in
                // This factory consumes already acquired local bytes only.
                throw BackendContractError.unavailable
            }
            try await scope.checkAdmission()
            return ProductRenditionOwner(scope: scope, temporary: temporary, player: player)
        }
        opening[key] = task
        do {
            let value = try await task.value
            opening.removeValue(forKey: key)
            owners[key] = value; openedOwners += 1
            return value
        } catch { opening.removeValue(forKey: key); throw error }
    }
}
