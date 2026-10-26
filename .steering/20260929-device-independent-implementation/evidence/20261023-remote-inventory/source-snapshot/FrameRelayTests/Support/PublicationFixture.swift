import Foundation
import Testing
@testable import FrameRelay

/// Explicit technical fixture. It does not assert Rec.709 or product authority.
@MainActor struct PublicationFixture {
    let store: PublicationFaultStore
    let identity: RegistrationStoreIdentity
    let registration: RegistrationIdentity
    let rendition: RenditionIdentity
    let token: PlaybackToken
    let registry: RenditionScopeRegistry
    let ordering: ManagedOriginalAccess
    let external: PublicationExternalFixture
    static func make(run: ExplorationRunDirectory) async throws -> Self {
        let base = try SQLiteRecordingStore(run: run, mode: .createNew)
        let store = PublicationFaultStore(base: base)
        let identity = try await establishRegistrationIdentity(base)
        let registration = try await mediaRegister(base)
        let original = try publicationOriginal("s27-fixture")
        let old = publicationRendition(original)
        let rendition = RenditionIdentity(original: original, inputLogIdentity: old.inputLogIdentity,
            transformAssetIdentity: old.transformAssetIdentity, transformAssetVersion: old.transformAssetVersion,
            outputConfigurationIdentity: old.outputConfigurationIdentity, conversionVersion: old.conversionVersion,
            rendition: .init(rawValue: "d380d397-5a2f-4186-bd4c-e07b1df6d15e"), deliveryContent: old.deliveryContent, publicationGeneration: old.publicationGeneration)
        _ = try await mediaCommit(base, .publication(mediaPublication(rendition, registration: registration)))
        let token = try publicationToken(rendition, registration: registration)
        return .init(store: store, identity: identity, registration: registration, rendition: rendition, token: token,
            registry: RenditionScopeRegistry(leases: RenditionReadLeases(store: store)),
            ordering: ManagedOriginalAccess(store: store, originals: ManagedOriginalStore(run: run)), external: PublicationExternalFixture())
    }
    var invalidation: InvalidationRecord { .init(id: .init(rawValue: "s27-invalidation"), rendition: rendition, registration: registration, generation: .init(rawValue: 1)) }
    func confirmations() -> MediaConfirmationCoordinator { .init(store: store, identity: identity) }
    func invalidations() -> MediaInvalidationCoordinator {
        .init(store: store, identity: identity, ordering: ordering, scopes: registry, external: external)
    }
}

@MainActor final class PublicationFaultStore: RecordingStorePort, OriginalStorePort, MediaOperationStorePort {
    enum Stage { case confirmation, invalidation, delivery }
    let base: any MediaDiskStore
    var stage: Stage?
    var afterCommit = false
    var hideLookup = false
    private(set) var mutations: [BackendStoreMutation] = []
    private(set) var lookups: [BackendStoreMutation] = []
    init(base: any MediaDiskStore) { self.base = base }
    func matches(_ mutation: BackendStoreMutation) -> Bool {
        switch (stage, mutation.change) {
        case (.confirmation?, .confirmation), (.invalidation?, .invalidation), (.delivery?, .delivered): true
        default: false
        }
    }
    @MainActor func commit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        mutations.append(mutation)
        guard matches(mutation) else { return await base.commit(mutation) }
        if afterCommit {
            let result = await base.commit(mutation)
            guard case .committed = result else { return result }
        }
        return .unknown
    }
    @MainActor func lookupCommit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        lookups.append(mutation)
        return hideLookup && matches(mutation) ? .unknown : await base.lookupCommit(mutation)
    }
    @MainActor func load() async -> BackendStoreLoadResult { await base.load() }
    @MainActor func execute(_ command: RecordingStoreCommand) async -> RecordingStoreResult { await base.execute(command) }
    @MainActor func loadUnfinished() async -> UnfinishedRecordingLoadResult { await base.loadUnfinished() }
    @MainActor func loadRecordings() async -> RecordingStoreLoadResult { await base.loadRecordings() }
    @MainActor func loadOriginalState() async -> BackendOutcome<OriginalStoreSnapshot> { await base.loadOriginalState() }
    @MainActor func commitOriginal(_ mutation: OriginalStoreMutation) async -> OriginalStoreCommitResult { await base.commitOriginal(mutation) }
    @MainActor func lookupInvalidation(_ acknowledgement: InvalidationAcknowledgement) async -> BackendOutcome<InvalidationID> { await base.lookupInvalidation(acknowledgement) }
}

@MainActor final class PublicationExternalFixture: PublicationExternalTerminationPort {
    var available = true
    var onStop: (@MainActor () async throws -> Void)?
    private(set) var stops = 0
    @MainActor func stopAndObserve(original: OriginalContent, epoch: ReaderReconciliationEpoch) async throws {
        stops += 1
        try await onStop?()
        guard available else { throw BackendContractError.unknownResult }
    }
    @MainActor func observeTerminal(original: OriginalContent, epoch: ReaderReconciliationEpoch) async throws -> EvidenceID {
        guard available else { throw BackendContractError.unknownResult }
        return .init(rawValue: "explicit-test-inventory-\(epoch.rawValue)")
    }
}

@MainActor final class PublicationRemoteFixture: PublicationRemotePort {
    var loseResponse = false
    var credentialsAvailable = true
    private(set) var sent: [BackendSyncEntry] = []
    @MainActor func manifest(original: OriginalContent, registration: RegistrationIdentity) async -> BackendOutcome<PublicationManifest> { .unknown }
    @MainActor func distribute(_ request: PublicationDistributionRequest) async -> BackendOutcome<PublicationDistribution> { .unknown }
    @MainActor func lookupDistribution(_ request: PublicationDistributionRequest) async -> BackendOutcome<PublicationDistribution> { .unknown }
    @MainActor func invalidations(registration: RegistrationIdentity, after: InvalidationID?) async -> BackendOutcome<PublicationInvalidationPage> { .unknown }
    @MainActor func send(_ entry: BackendSyncEntry) async -> BackendOutcome<BackendSyncResponse> {
        guard credentialsAvailable else { return .failed(.authenticationRequired) }
        if !sent.contains(entry) { sent.append(entry) }
        return loseResponse ? .unknown : .succeeded(response(entry))
    }
    @MainActor func lookup(_ entry: BackendSyncEntry) async -> BackendOutcome<BackendSyncResponse> {
        guard credentialsAvailable else { return .failed(.authenticationRequired) }
        return sent.contains(entry) ? .succeeded(response(entry)) : .notExecuted
    }
    private func response(_ entry: BackendSyncEntry) -> BackendSyncResponse {
        switch entry { case .confirmation(let value): .confirmation(value.intent.operation); case .invalidation(let value): .invalidation(value.record.id) }
    }
}

/// Credentials are explicit test values; never written to the journal or attachments.
@MainActor final class PublicationCredentialsFixture: RegistrationAuthorizationPort {
    let registration: DeviceRegistration
    let identity: RegistrationStoreIdentity
    let material: RegistrationAuthorization
    private(set) var requested: [RegistrationIntent?] = []
    init(registration: DeviceRegistration, identity: RegistrationStoreIdentity, material: RegistrationAuthorization) {
        self.registration = registration; self.identity = identity; self.material = material
    }
    @MainActor func authorization(for connection: RegistrationConnection, intent: RegistrationIntent?, storeIdentity: RegistrationStoreIdentity) async throws -> RegistrationAuthorization {
        requested.append(intent)
        guard storeIdentity == identity, intent == registration.server.intent,
              connection.destination == registration.server.registration.destination else { throw RegistrationAccessError.credentialMissing }
        return material
    }
}

nonisolated func publicationOriginal(_ name: String) throws -> OriginalContent {
    .init(capture: .init(rawValue: name), generation: .init(rawValue: 1),
          content: try .init(byteCount: 4096, algorithm: "sha256", digest: String(repeating: "a", count: 64)))
}
nonisolated func publicationRendition(_ original: OriginalContent) -> RenditionIdentity {
    .init(original: original, inputLogIdentity: "technical-fixture", transformAssetIdentity: "no-quality-proof",
        transformAssetVersion: "fixture-v1", outputConfigurationIdentity: "fixture-output", conversionVersion: "fixture-conversion",
        rendition: .init(rawValue: "d380d397-5a2f-4186-bd4c-e07b1df6d15e"), deliveryContent: original.content, publicationGeneration: .init(rawValue: 1))
}
nonisolated func publicationToken(_ rendition: RenditionIdentity, registration: RegistrationIdentity) throws -> PlaybackToken {
    let operation = MediaOperationID(rawValue: "fixture-source")
    let distribution = DistributionReceipt(operation: operation, rendition: rendition, registration: registration,
        commit: .init(key: .distribution(operation, rendition, registration), previousRevision: 20, committedRevision: 21))
    return try .init(distribution: distribution, session: .init(rawValue: "fixture-session"), invalidationGeneration: .init(rawValue: 0), observation: .played)
}
