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

/// App-lifetime local consumer. It has no network factory, creates no cache
/// directories or media, and uses the same registry as invalidation/removal.
actor ProductRenditionFactory {
    private let services: ProductLibraryServices
    private let scopes: RenditionScopeRegistry
    private let leases: RenditionReadLeases
    private var owners: [String: ProductRenditionOwner] = [:]
    private var opening: [String: Task<ProductRenditionOwner, Error>] = [:]
    private var confirmations: [RegistrationStoreIdentity: MediaConfirmationCoordinator] = [:]
    private(set) var openedOwners = 0

    init(services: ProductLibraryServices, scopes: RenditionScopeRegistry) {
        self.services = services; self.scopes = scopes
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
        let selected = try await selection(target)
        let owner = try await owner(for: selected.rendition.original)
        try Task.checkCancellation()
        guard await owner.player.phase != .releaseNeedsReconciliation,
              selected.sameSource(as: try await selection(target)) else { throw BackendContractError.staleGeneration }
        guard case .succeeded(let usage) = await owner.temporary.acquireUsage(selected.media.id, purpose: .playback,
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
            _ = await owner.temporary.releaseUsage(usage)
            throw error
        }
    }

    func release(_ source: ProductRenditionSource) async -> Bool {
        await source.owner.temporary.releaseUsage(source.usage) == .succeeded(source.receipt.id)
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
