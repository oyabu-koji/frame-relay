import Foundation
import Synchronization
import Testing
@testable import FrameRelay

@Suite(.serialized) @MainActor struct ProductUploadMetadataTests {
    @Test func constructorAndReopenLocalLookupNeverResolveConnectionCredentialsOrRemote() async throws {
        let f = try await MetadataAppFixture.make(), probe = MetadataProductProbe(), auth = MetadataAuthorizationProbe()
        let remote = MetadataTestRemote(state: .completed), connection = try metadataHTTPSConnection(f)
        let product = ProductUploadMetadata(store: f.services.store, credentials: auth, connection: { _ in
            probe.connectionRead(); return connection
        }, admission: { true }, remoteFactory: { _, _, _ in
            probe.remoteCreated(); return remote
        })
        #expect(probe.counts() == [0, 0])
        #expect(await product.reconcilePending(f.request) == .unknown)
        #expect(await product.refreshKnownSession(f.request) == .rejected(.wrongStage))
        #expect(probe.counts() == [0, 0])
        #expect(await auth.calls() == 0)
        _ = try metadataRecorded(await product.refresh(f.request))
        let checked = try metadataRecorded(await product.refreshKnownSession(f.request))
        let backend = try await mediaSnapshot(f.services.store), proof = try #require(backend.verifications.first)
        #expect(proof.isCommitted && proof.metadataProvenance != nil && proof.commit == checked.commit)
        #expect(proof.commit.key == checked.observation.key && checked.verification == proof)
        #expect(backend.uploadMetadataQueries.count == 2 && backend.uploadMetadataObservations.count == 2)
        #expect(backend.requests[0].transport == .queued && backend.requests[0].attempt == nil && !backend.requests[0].canRun)
        let before = probe.counts(), credentialsBefore = await auth.calls()
        let reopened = try SQLiteRecordingStore(run: f.services.run, mode: .openExisting)
        let fresh = ProductUploadMetadata(store: reopened, credentials: auth, connection: { _ in
            probe.connectionRead(); return connection
        }, admission: { true }, remoteFactory: { _, _, _ in probe.remoteCreated(); return remote })
        #expect(await fresh.reconcilePending(f.request) == .recorded(checked))
        #expect(probe.counts() == before)
        #expect(await auth.calls() == credentialsBefore)
        #expect(try await mediaSnapshot(reopened) == backend)
        try await f.assertBytesAndNoMedia()
    }

    @Test func customRegistrationFactoryNeverGainsAnImplicitMetadataOrKeychainFallback() async throws {
        let f = try await MetadataAppFixture.make()
        let composition = ProductComposition(factory: f.library, registrationFactory: { store in
            RegistrationCoordinator(store: store, vault: MetadataUnavailableVault(), remote: MetadataUnavailableRegistrationRemote())
        })
        #expect(composition.uploadMetadata == nil)
        let before = try await mediaSnapshot(f.services.store)
        await composition.open()
        #expect(composition.uploadMetadata == nil && composition.library?.hasUploadMetadataPort == false)
        #expect(composition.statusSynchronization == nil && composition.remoteInventory == nil)
        #expect(try await mediaSnapshot(f.services.store) == before)
        try await f.assertBytesAndNoMedia()
        await composition.enteredBackground()
    }

    @Test func libraryFixesOriginalInputBeforeAwaitAndUnknownLookupDoesNotAdoptNewDisplayedUUID() async throws {
        let f = try await MetadataAppFixture.make()
        guard case .loaded(let snapshot) = await f.services.reader.loadLibrary() else { throw BackendContractError.unavailable }
        let reader = UploadAppMemoryReader(snapshot), probe = MetadataLibraryProbe()
        let model = LibraryModel(reader: reader, uploadMetadata: LibraryUploadMetadataCommands(metadata: probe))
        await model.refresh()
        let row = try #require(model.snapshot?.mediaRequests.first)
        #expect(UploadMetadataValidation.exact(row.uploadMetadataRequest, Optional(f.request)))
        let first = Task { await model.refreshUploadMetadata(row) }
        await probe.waitForCalls(refreshes: 1)
        #expect(UploadMetadataValidation.exact(probe.refreshes[0], f.request))
        // Presentation fault only. No physical UUID, journal or source changes.
        var changed = snapshot
        let otherIdentity = RegistrationStoreIdentity(rawValue: UUID())
        changed.storeIdentity = otherIdentity
        changed.mediaRequests[0].uploadMetadataRequest = try .init(storeIdentity: otherIdentity,
            registration: f.request.registration, operation: f.request.operation, original: f.request.original,
            expectedStartRevision: f.request.expectedStartRevision)
        await reader.replace(changed); await model.refresh()
        probe.finish(.unknown); await first.value
        let current = try #require(model.snapshot?.mediaRequests.first)
        let lookup = Task { await model.refreshUploadMetadata(current, reconcile: true) }
        await probe.waitForCalls(refreshes: 1, lookups: 1)
        #expect(UploadMetadataValidation.exact(probe.lookups[0], f.request))
        probe.finish(.unknown); await lookup.value
        #expect(probe.refreshes.count == 1 && probe.lookups.count == 1)
        #expect(model.uploadMetadataMessages[row.id]?.contains("未確定") == true)
        #expect(try await mediaSnapshot(f.services.store).uploadMetadataQueries.isEmpty)
    }

    @Test func normalStatusSyncFixesKnownSessionsAndNeverRoutesAnUnknownSessionToPost() async throws {
        let f = try await MetadataAppFixture.make()
        let owner = UploadMetadataCoordinator(store: f.services.store, remote: MetadataTestRemote())
        let stored = try metadataRecorded(await owner.refresh(f.request))
        let other = try #require(try await uploadAppSeed(store: f.services.store, files: f.services.originals,
            names: ["unknown-session-" + UUID().uuidString]).first)
        let acceptance = try OriginalUploadAcceptanceRequest(parent: .init(rawValue: UUID().uuidString.lowercased()),
            storeIdentity: f.request.storeIdentity, registration: f.request.registration, scope: .single,
            targets: [.init(operation: .init(rawValue: UUID().uuidString.lowercased()), binding: other)])
        _ = try uploadAppRecorded(await OriginalUploadAcceptanceCoordinator(store: f.services.store, files: f.services.originals,
            network: UploadAppNetwork(.wiFi)).accept(acceptance))
        let metadata = MetadataStatusProbe(record: stored)
        let player = AVOriginalPlayback(access: f.services.access)
        let media = ProductMediaTermination(store: f.services.store, access: f.services.access, player: player)
        let product = ProductStatusSynchronization(store: f.services.store, access: f.services.access, media: media,
            credentials: MetadataAuthorizationProbe(), admission: { true }, uploadMetadata: metadata,
            remoteFactory: { _, _, _, _ in MetadataPublicationRemote() })
        #expect(await metadata.requests().isEmpty)
        _ = await product.synchronize(connection: try metadataHTTPSConnection(f), registration: f.request.registration)
        let known = await metadata.requests()
        #expect(known.count == 1 && UploadMetadataValidation.exact(known[0], f.request))
        #expect(await metadata.otherCalls() == 0)
        let backend = try await mediaSnapshot(f.services.store)
        #expect(backend.requests.count == 2 && backend.requests.filter { $0.session == nil }.count == 1)
        #expect(backend.uploadMetadataQueries.count == 1 && backend.backgroundTasks.isEmpty)
        let secondDigest = try await f.services.originals.digest(for: other.reference)
        #expect(secondDigest.sha256 == other.original.content.digest && secondDigest.byteCount == other.original.content.byteCount)
        try await f.assertBytesAndNoMedia()
    }

    @Test func serverCancelledIsAnIndependentHoldAndCannotBecomeNotExecutedOrResumePermission() async throws {
        let f = try await MetadataAppFixture.make(), remote = MetadataTestRemote(state: .cancelled)
        let owner = UploadMetadataCoordinator(store: f.services.store, remote: remote)
        _ = try metadataRecorded(await owner.refresh(f.request))
        _ = try metadataRecorded(await owner.refreshKnownSession(f.request))
        let backend = try await mediaSnapshot(f.services.store), current = try #require(backend.requests.first)
        #expect(current.intent == .running && current.remote == .unknown && current.uploadMetadataHold == .serverCancelled)
        #expect(!current.canRun && current.transport == .queued && current.attempt == nil)
        guard case .loaded(let library) = await f.services.reader.loadLibrary() else { throw BackendContractError.unavailable }
        #expect(library.mediaRequests[0].uploadMetadataDescription?.contains("Mac側で取消") == true)
        #expect(backend.verifications.isEmpty && library.items[0].operationResults.isEmpty)
        try await f.assertBytesAndNoMedia()
    }
}

nonisolated private final class MetadataProductProbe: Sendable {
    private let state = Mutex<[Int]>([0, 0])
    func connectionRead() { state.withLock { $0[0] += 1 } }
    func remoteCreated() { state.withLock { $0[1] += 1 } }
    func counts() -> [Int] { state.withLock { $0 } }
}
@MainActor private final class MetadataLibraryProbe: UploadMetadataPort {
    private(set) var refreshes: [UploadMetadataRequest] = [], lookups: [UploadMetadataRequest] = []
    private var response: CheckedContinuation<UploadMetadataResult, Never>?
    private var waiting: (Int, Int, CheckedContinuation<Void, Never>)?
    @MainActor func refresh(_ request: UploadMetadataRequest) async -> UploadMetadataResult {
        refreshes.append(request); return await withCheckedContinuation { response = $0; signal() }
    }
    @MainActor func refreshKnownSession(_ request: UploadMetadataRequest) async -> UploadMetadataResult { .rejected(.wrongStage) }
    @MainActor func reconcilePending(_ request: UploadMetadataRequest) async -> UploadMetadataResult {
        lookups.append(request); return await withCheckedContinuation { response = $0; signal() }
    }
    func waitForCalls(refreshes: Int, lookups: Int = 0) async {
        if self.refreshes.count >= refreshes && self.lookups.count >= lookups { return }
        await withCheckedContinuation { waiting = (refreshes, lookups, $0) }
    }
    private func signal() {
        guard let waiting, refreshes.count >= waiting.0 && lookups.count >= waiting.1 else { return }
        self.waiting = nil; waiting.2.resume()
    }
    func finish(_ value: UploadMetadataResult) { let held = response; response = nil; held?.resume(returning: value) }
}
private actor MetadataStatusProbe: UploadMetadataPort {
    let record: StoredUploadMetadataObservation
    private var known: [UploadMetadataRequest] = []
    private var other = 0
    init(record: StoredUploadMetadataObservation) { self.record = record }
    func refresh(_ request: UploadMetadataRequest) async -> UploadMetadataResult { other += 1; return .unknown }
    func refreshKnownSession(_ request: UploadMetadataRequest) async -> UploadMetadataResult { known.append(request); return .recorded(record) }
    func reconcilePending(_ request: UploadMetadataRequest) async -> UploadMetadataResult { other += 1; return .unknown }
    func requests() -> [UploadMetadataRequest] { known }
    func otherCalls() -> Int { other }
}
nonisolated private struct MetadataUnavailableVault: RegistrationVaultPort {
    func connection(storeIdentity: RegistrationStoreIdentity?) async throws -> RegistrationConnection? { throw RegistrationAccessError.credentialUnavailable }
    func saveConnection(_ connection: RegistrationConnection, bearer: String, storeIdentity: RegistrationStoreIdentity) async throws { throw RegistrationAccessError.credentialUnavailable }
    func prepareIntent(for destination: DestinationIdentity, storeIdentity: RegistrationStoreIdentity) async throws -> RegistrationIntent { throw RegistrationAccessError.credentialUnavailable }
    func requireCredential(for intent: RegistrationIntent, storeIdentity: RegistrationStoreIdentity) async throws { throw RegistrationAccessError.credentialUnavailable }
}
nonisolated private struct MetadataUnavailableRegistrationRemote: RegistrationRemotePort {
    func checkConnection(_ connection: RegistrationConnection, bearer: String) async -> BackendOutcome<BackendCapabilities> { .unknown }
    func discover(_ connection: RegistrationConnection, storeIdentity: RegistrationStoreIdentity) async -> BackendOutcome<BackendCapabilities> { .unknown }
    func register(_ command: RegistrationCommand, at connection: RegistrationConnection, storeIdentity: RegistrationStoreIdentity) async -> BackendOutcome<RegistrationServerReceipt> { .unknown }
    func lookup(_ intent: RegistrationIntent, at connection: RegistrationConnection, storeIdentity: RegistrationStoreIdentity) async -> BackendOutcome<RegistrationServerReceipt> { .unknown }
}
nonisolated private struct MetadataPublicationRemote: PublicationRemotePort {
    func manifest(original: OriginalContent, registration: RegistrationIdentity) async -> BackendOutcome<PublicationManifest> {
        .succeeded(.init(current: nil, revision: 0, invalidationGeneration: .init(rawValue: 0), replacementPending: false, mediaType: nil))
    }
    func invalidations(registration: RegistrationIdentity, after: InvalidationID?) async -> BackendOutcome<PublicationInvalidationPage> { .succeeded(.init(records: [], nextAfter: nil)) }
    func send(_ entry: BackendSyncEntry) async -> BackendOutcome<BackendSyncResponse> { .unknown }
    func lookup(_ entry: BackendSyncEntry) async -> BackendOutcome<BackendSyncResponse> { .unknown }
    func distribute(_ request: PublicationDistributionRequest) async -> BackendOutcome<PublicationDistribution> { .failed(.rejected) }
    func lookupDistribution(_ request: PublicationDistributionRequest) async -> BackendOutcome<PublicationDistribution> { .failed(.rejected) }
}
