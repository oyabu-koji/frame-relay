import Foundation

extension MediaStoreProjection {
    nonisolated mutating func applyRemoteInventory(_ value: RemoteInventoryObservation,
        receipt: BackendCommitReceipt, expectedStoreIdentity: RegistrationStoreIdentity?) throws {
        try value.validate()
        guard expectedStoreIdentity == value.storeIdentity else { throw BackendContractError.identityMismatch }
        try requireCurrentRegistration(value.registration)
        guard receipt.matches(value.key, revision: receipt.previousRevision) else { throw BackendContractError.notCommitted }
        remoteInventory.append(.init(observation: value, commit: receipt))
    }
}
