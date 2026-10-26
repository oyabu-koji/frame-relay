import Foundation

nonisolated struct PublicationManifest: Equatable, Sendable, Codable {
    let current: RenditionIdentity?
    let revision: UInt64
    let invalidationGeneration: InvalidationGeneration
    let replacementPending: Bool
    let mediaType: String?
}


/// The last server metadata observed for one exact original and registration.
/// It never substitutes for distribution, playback, confirmation or an ACK.
nonisolated struct PublicationManifestObservation: Equatable, Sendable, Codable {
    let command: MediaOperationID
    let storeIdentity: RegistrationStoreIdentity
    let registration: RegistrationIdentity
    let original: OriginalContent
    let manifest: PublicationManifest

    var key: BackendCommitKey { .publicationManifest(command, registration, original) }
}

nonisolated struct StoredPublicationManifest: Equatable, Sendable {
    let observation: PublicationManifestObservation
    let commit: BackendCommitReceipt
    var isCommitted: Bool {
        commit.matches(observation.key, revision: commit.previousRevision)
            && PublicationManifestValidation.exact(commit.key, observation.key)
    }
}

nonisolated enum PublicationManifestValidation {
    static func exact<T: Encodable>(_ lhs: T, _ rhs: T) -> Bool {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let a = try? encoder.encode(lhs), let b = try? encoder.encode(rhs) else { return false }
        return a == b
    }

    static func validate(_ value: PublicationManifest, original: OriginalContent) throws {
        guard (value.current == nil) == (value.mediaType == nil) else {
            throw BackendContractError.identityMismatch
        }
        if let rendition = value.current {
            guard PublicationManifestValidation.exact(rendition.original, original), value.revision > 0,
                  value.mediaType == "video/mp4" || value.mediaType == "video/quicktime" else {
                throw BackendContractError.identityMismatch
            }
        }
    }

    /// Pointer revision and invalidation generation are distinct. A pending
    /// replacement can retain the same pointer; metadata never reinstates it.
    static func successor(_ value: PublicationManifest, to previous: PublicationManifest) throws {
        guard value.revision >= previous.revision,
              value.invalidationGeneration.rawValue >= previous.invalidationGeneration.rawValue else {
            throw BackendContractError.staleGeneration
        }
        if value.revision == previous.revision {
            guard PublicationManifestValidation.exact(value.current, previous.current),
                  value.mediaType == previous.mediaType,
                  !previous.replacementPending || value.replacementPending else {
                throw BackendContractError.identityMismatch
            }
        }
        if let old = previous.current, let current = value.current,
           !PublicationManifestValidation.exact(old, current) {
            guard current.publicationGeneration.rawValue > old.publicationGeneration.rawValue else {
                throw BackendContractError.staleGeneration
            }
        }
    }
}
