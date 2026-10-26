import Foundation

/// A read-only candidate, never permission to read a path. The consumer checks
/// the actual root, inode and whole file before passing a live use to AVPlayer.
nonisolated struct LocalRenditionSelection: Equatable, Sendable {
    let identity: RegistrationStoreIdentity
    let registration: RegistrationIdentity
    let rendition: RenditionIdentity
    let generation: InvalidationGeneration
    let media: TemporaryMediaState
    let distribution: DistributionReceipt

    static let unavailableReason = "この登録・公開版に対応する完全取得済みの軽量版と配布記録を確認できません。必要な媒体の取得は、まだ利用できません。"

    static func select(backend: BackendStoreSnapshot, originals: OriginalStoreSnapshot,
                       target: LibraryRenditionTarget) throws -> Self {
        guard backend.revision == originals.revision, let identity = backend.storeIdentity,
              let logical = originals.logicalOriginals.first(where: { exact($0.original, target.original) }),
              logical.removal == nil, logical.invalidation == nil,
              !originals.logicalOriginals.contains(where: {
                  $0.original.capture == target.original.capture && !exact($0.original, target.original)
              }) else { throw BackendContractError.identityMismatch }
        var candidates: [Self] = []
        for registration in backend.registrations {
            let reg = registration.server.registration
            guard registration.isCommitted,
                  target.destination.map({ exact($0, reg.destination) }) ?? true,
                  backend.registrations.last(where: { exact($0.server.registration.destination, reg.destination) })
                    .map({ exact($0, registration) }) == true,
                  let current = backend.confirmationStates.first(where: {
                      exact($0.registration, reg) && exact($0.current.original, target.original)
                  }), !current.invalidatedRenditions.contains(current.current.rendition),
                  backend.publications.contains(where: {
                      exact($0.observation.registration, reg) && exact($0.observation.rendition, current.current)
                          && $0.commit.matches(BackendStoreChange.publication($0.observation).key, revision: $0.commit.previousRevision)
                          && exact($0.commit.key, BackendStoreChange.publication($0.observation).key)
                  }) else { continue }
            let proof = backend.distributionObservations.reversed().compactMap { row -> DistributionReceipt? in
                let observation = row.observation
                let key = BackendCommitKey.distributionObservation(observation.command, observation.lease.id, observation.observation)
                guard row.commit.matches(key, revision: row.commit.previousRevision), exact(row.commit.key, key),
                      exact(observation.lease.registration, reg), exact(observation.lease.target, MediaTarget.rendition(current.current)),
                      case .succeeded(let receipt) = observation.result, receipt.isCommitted,
                      exact(receipt.registration, reg), exact(receipt.rendition, current.current) else { return nil }
                return receipt
            }.first
            guard let proof else { continue }
            let media = backend.temporaryMedia.filter {
                exact($0.registration, reg) && exact($0.rendition, current.current)
                    && !$0.reclaiming && !$0.reclaimed && $0.complete && $0.fileIdentity != nil
                    && exact($0.verifiedContent, current.current.deliveryContent)
            }.sorted { $0.id.rawValue.utf8.lexicographicallyPrecedes($1.id.rawValue.utf8) }
            if let first = media.first {
                candidates.append(.init(identity: identity, registration: reg, rendition: current.current,
                    generation: current.generation, media: first, distribution: proof))
            }
        }
        // A local recording has no destination chooser. Do not silently choose
        // between multiple current registrations with eligible copies.
        guard candidates.count == 1, let value = candidates.first else { throw BackendContractError.ineligibleOriginal }
        return value
    }

    func sameSource(as other: Self) -> Bool {
        identity == other.identity && exact(registration, other.registration) && exact(rendition, other.rendition)
            && generation == other.generation && exact(distribution, other.distribution)
            && media.id == other.media.id && media.leaf == other.media.leaf
            && media.directoryIdentity == other.media.directoryIdentity && media.fileIdentity == other.media.fileIdentity
            && media.contentType == other.media.contentType
    }
    private static func exact<T: Encodable>(_ lhs: T, _ rhs: T) -> Bool { PublicationStoreBoundary.exact(lhs, rhs) }
    private func exact<T: Encodable>(_ lhs: T, _ rhs: T) -> Bool { Self.exact(lhs, rhs) }
}
