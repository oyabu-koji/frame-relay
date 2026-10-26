import Foundation

nonisolated struct PublicationDistributionRequest: Equatable, Sendable {
    enum Purpose: String, Sendable { case source, read }
    enum Kind: String, Sendable { case full, range, resume }
    let operation: MediaOperationID
    let gate: MediaGateLease
    let rendition: RenditionIdentity
    let purpose: Purpose
    let kind: Kind
    let range: MediaByteRange?
    let source: MediaOperationID?
}
nonisolated struct PublicationDistribution: Equatable, Sendable {
    let receipt: DistributionReceipt
    let mediaType: String
}
nonisolated struct PublicationInvalidationPage: Equatable, Sendable {
    let records: [InvalidationRecord]
    let nextAfter: InvalidationID?
}

/// Metadata only; every media GET still passes the current S23/S25 gate.
nonisolated protocol PublicationRemotePort: Sendable {
    func manifest(original: OriginalContent, registration: RegistrationIdentity) async -> BackendOutcome<PublicationManifest>
    func distribute(_ request: PublicationDistributionRequest) async -> BackendOutcome<PublicationDistribution>
    func lookupDistribution(_ request: PublicationDistributionRequest) async -> BackendOutcome<PublicationDistribution>
    func invalidations(registration: RegistrationIdentity, after: InvalidationID?) async -> BackendOutcome<PublicationInvalidationPage>
    func send(_ entry: BackendSyncEntry) async -> BackendOutcome<BackendSyncResponse>
    func lookup(_ entry: BackendSyncEntry) async -> BackendOutcome<BackendSyncResponse>
}

/// Required producer: close original SDK readers AND enumerate external/OS
/// owners. Absence of local objects, process restart, or cancel requests is not
/// terminal evidence. Product S23 recovery producer is not supplied by S27.
nonisolated protocol PublicationExternalTerminationPort: RenditionExternalOwnersPort {
    func stopAndObserve(original: OriginalContent, epoch: ReaderReconciliationEpoch) async throws
}

nonisolated enum PublicationStoreBoundary {
    /// Local exact comparison only, never a wire encoding. Swift String ==
    /// normalizes canonically equivalent Unicode; opaque identities do not.
    static func exact<T: Encodable>(_ lhs: T, _ rhs: T) -> Bool {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let left = try? encoder.encode(lhs), let right = try? encoder.encode(rhs) else { return false }
        return left == right
    }
    static func load(_ store: any MediaOperationStorePort, identity: RegistrationStoreIdentity) async throws -> BackendStoreSnapshot {
        guard case .loaded(let value) = await store.load() else { throw BackendContractError.unavailable }
        guard value.storeIdentity == identity else { throw BackendContractError.identityMismatch }
        return value
    }
    static func commit(_ mutation: BackendStoreMutation, store: any MediaOperationStorePort) async -> BackendCommitResult {
        let result = await store.commit(mutation)
        switch result {
        case .unknown, .unavailable: return await reconcile(mutation, store: store)
        default: return result
        }
    }
    static func reconcile(_ mutation: BackendStoreMutation, store: any MediaOperationStorePort) async -> BackendCommitResult {
        let result = await store.lookupCommit(mutation)
        if case .committed = result { return result }
        // Lookup conflict/absence does not prove the attempted transaction was
        // never accepted. Preserve its complete payload and expected revision.
        return .unknown
    }
}
