import Foundation

extension MediaStoreProjection {
    nonisolated mutating func applyPublicationManifest(_ value: PublicationManifestObservation,
        receipt: BackendCommitReceipt, expectedStoreIdentity: RegistrationStoreIdentity?) throws {
        try MediaStoredValueValidation.text(value.command.rawValue)
        try MediaStoredValueValidation.original(value.original)
        try MediaStoredValueValidation.registration(value.registration)
        try PublicationManifestValidation.validate(value.manifest, original: value.original)
        if let current = value.manifest.current { try MediaStoredValueValidation.rendition(current) }
        guard expectedStoreIdentity == value.storeIdentity,
              receipt.matches(value.key, revision: receipt.previousRevision),
              PublicationStoreBoundary.exact(receipt.key, value.key) else {
            throw BackendContractError.identityMismatch
        }
        try requireCurrentRegistration(value.registration)
        guard let registration = registrations.last(where: {
            PublicationStoreBoundary.exact($0.server.registration.destination, value.registration.destination)
        }), PublicationStoreBoundary.exact(registration.server.registration, value.registration) else {
            throw BackendContractError.identityMismatch
        }
        let known = originals.contains { PublicationStoreBoundary.exact($0.original, value.original) }
            || remoteInventory.contains { page in
                page.isCommitted && page.observation.storeIdentity == value.storeIdentity
                    && PublicationStoreBoundary.exact(page.observation.registration, value.registration)
                    && page.observation.page.originals.contains { PublicationStoreBoundary.exact($0, value.original) }
            }
        guard known else { throw BackendContractError.notCommitted }
        if let prior = publicationManifests.last(where: {
            PublicationStoreBoundary.exact($0.observation.registration, value.registration)
                && PublicationStoreBoundary.exact($0.observation.original, value.original)
        }) { try PublicationManifestValidation.successor(value.manifest, to: prior.observation.manifest) }
        if let publication = publications.last(where: {
            PublicationStoreBoundary.exact($0.observation.registration, value.registration)
                && PublicationStoreBoundary.exact($0.observation.rendition.original, value.original)
        }) {
            guard value.manifest.revision >= publication.observation.observation.rawValue else {
                throw BackendContractError.staleGeneration
            }
            if value.manifest.revision == publication.observation.observation.rawValue {
                guard PublicationStoreBoundary.exact(value.manifest.current, publication.observation.rendition) else {
                    throw BackendContractError.identityMismatch
                }
            }
        }
        // Do not ensureOriginal, adopt a confirmation state, release readers,
        // enqueue an ACK, or remove any historical fact from this metadata event.
        publicationManifests.append(.init(observation: value, commit: receipt))
    }
}
