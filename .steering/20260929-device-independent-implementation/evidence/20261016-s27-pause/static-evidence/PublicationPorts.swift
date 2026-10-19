@testable import FrameRelay
import Foundation

nonisolated struct PublicationManifest: Equatable, Sendable {
    let current: RenditionIdentity?
    let revision: UInt64
    let invalidationGeneration: InvalidationGeneration
    let replacementPending: Bool
    let mediaType: String?
}

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
    static func load(_ store: any MediaOperationStorePort, identity: RegistrationStoreIdentity) async throws -> BackendStoreSnapshot {
        guard case .loaded(let value) = await store.load() else { throw BackendContractError.unavailable }
        guard value.storeIdentity == identity else { throw BackendContractError.identityMismatch }
        return value
    }
    static func commit(_ mutation: BackendStoreMutation, store: any MediaOperationStorePort) async -> BackendCommitResult {
        let result = await store.commit(mutation)
        switch result {
        case .unknown, .unavailable: return await store.lookupCommit(mutation)
        default: return result
        }
    }
}
