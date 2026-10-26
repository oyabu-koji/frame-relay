import Foundation
import Testing
@testable import FrameRelay

@Suite(.serialized) @MainActor struct ProductBackgroundInvalidationTests {
    @Test func normalStatusCancelsSharedOwnerThenNextExplicitPollAcksWhileAnotherVideoContinues() async throws {
        let parent = try backgroundInvalidationProductParent()
        let photos = BackgroundInvalidationUnusedPhotos()
        let library = ProductLibraryFactory(supportDirectory: parent, photoLibrary: photos)
        let services = try await library.open(), seed = try await BackgroundProductInvalidationSeed.make(services)
        let managed = try ManagedUploadSource(run: services.run, originals: services.access)
        let source = BackgroundSourceProbe(base: managed)
        let sdk = BackgroundSessionProbe(identity: seed.fixture.plan.session)
        let background = ProductBackgroundMediaFactory(library: library, admission: BackgroundPermitProbe(),
            sessionFactory: { _ in sdk }, sourceFactory: { opened in
                guard opened.store === services.store else { throw BackendContractError.identityMismatch }
                return source
            })
        let other = try await seed.fixture.originals.original("independent-" + UUID().uuidString)
        let otherV1 = statusRendition(other.original), otherV2 = statusRendition(other.original, version: 2)
        _ = try await mediaCommit(services.store, .publication(mediaPublication(otherV1, registration: seed.record.registration)))
        let remote = StatusMetadataRemote()
        remote.pages = [.succeeded(.init(records: [seed.record], nextAfter: nil))]
        remote.setManifest(seed.rendition, revision: 2, generation: seed.record.generation.rawValue)
        remote.setManifest(otherV2, revision: 2)
        let composition = ProductComposition(factory: library, backgroundFactory: background, registrationFactory: { store in
            RegistrationCoordinator(store: store, vault: BackgroundInvalidationEmptyVault(), remote: RegistrationTestRemote())
        }, statusSynchronizationFactory: { opened, media in
            ProductStatusSynchronization(store: opened.store, access: opened.access, media: media,
                credentials: BackgroundInvalidationNoCredentials(), admission: { true }, background: background,
                remoteFactory: { _, _, _, _ in remote })
        })
        await composition.open()
        let port = try #require(composition.statusSynchronization)
        guard case .started(let started) = await background.startUpload(seed.fixture.plan) else { throw BackendContractError.notCommitted }
        let first = await port.synchronize(connection: seed.connection, registration: seed.registration)
        #expect(first.phase == .partial && first.unresolvedInvalidations == 1)
        #expect(first.items.first(where: { $0.original == other.original })?.disposition == .recorded)
        let reserved = try await mediaOriginalSnapshot(services.store)
        #expect(reserved.logicalOriginals.first(where: { $0.original == seed.rendition.original })?.invalidation?.record == seed.record)
        #expect(try await mediaSnapshot(services.store).invalidations.isEmpty)
        #expect(remote.sent.isEmpty && remote.mediaCalls == 0)
        #expect((await sdk.counts()) == [1, 1, 1])
        #expect((await managed.resources()).openHandles == 1)
        let request = try #require(try await mediaSnapshot(services.store).requests.first)
        #expect(request.intent == .running && request.remote == .notExecuted)

        await sdk.complete(try #require(started.binding), outcome: .cancelled, finishEvents: true)
        try await backgroundInvalidationWaitForStopped(services.store, operation: seed.fixture.plan.context.operation)
        #expect(try await mediaSnapshot(services.store).invalidations.isEmpty) // No automatic ACK from a callback.
        #expect(remote.sent.isEmpty)
        let second = await port.synchronize(connection: seed.connection, registration: seed.registration)
        #expect(second.phase == .checked && second.unresolvedInvalidations == 0)
        let completed = try await mediaSnapshot(services.store), ack = try #require(completed.invalidations.first)
        #expect(PublicationStoreBoundary.exact(ack.record, seed.record) && ack.isCommitted)
        #expect(await services.store.lookupInvalidation(ack) == .succeeded(seed.record.id))
        #expect(remote.sent == [.invalidation(ack)] && remote.mediaCalls == 0)
        #expect(try await mediaOriginalSnapshot(services.store).logicalOriginals.allSatisfy { $0.readers.isEmpty && $0.mediaReaders.isEmpty })
        #expect((await managed.resources()).openHandles == 0)
        #expect(await source.finishCount() == 1)
        let third = await port.synchronize(connection: seed.connection, registration: seed.registration)
        #expect(third.unresolvedInvalidations == 0)
        #expect(try await mediaSnapshot(services.store).invalidations == [ack])
        #expect((await sdk.counts()) == [1, 1, 1])
        #expect(await source.copyCount() == 1)
        let reopened = try SQLiteRecordingStore(run: services.run, mode: .openExisting)
        #expect(try await mediaSnapshot(reopened).invalidations == [ack])
        #expect(try await mediaSnapshot(reopened).backgroundTasks == completed.backgroundTasks)
        let digest = try await services.originals.digest(for: seed.binding.reference)
        #expect(digest.sha256 == seed.rendition.original.content.digest)
        #expect(await services.originals.observeFile(other.reference) == .present(byteCount: other.original.content.byteCount))
        #expect(await photos.callCount() == 0)
        await sdk.finishStream(); _ = try await managed.closeOwner()
    }

    @Test func freshFactoryRefusesAnUnknownLiveSourceAndOnlyObservesItAfterAllDurableTerminals() async throws {
        let library = ProductLibraryFactory(supportDirectory: try backgroundInvalidationProductParent(), photoLibrary: BackgroundInvalidationUnusedPhotos())
        let services = try await library.open(), seed = try await BackgroundProductInvalidationSeed.make(services)
        let managed = try ManagedUploadSource(run: services.run, originals: services.access)
        let sdk = BackgroundSessionProbe(identity: seed.fixture.plan.session)
        let old = ProductBackgroundMediaFactory(library: library, admission: BackgroundPermitProbe(),
            sessionFactory: { _ in sdk }, sourceFactory: { _ in managed })
        guard case .started(let started) = await old.startUpload(seed.fixture.plan) else { throw BackendContractError.notCommitted }
        guard case .succeeded = await services.access.reserveInvalidation(seed.record) else { throw BackendContractError.notCommitted }
        let calls = BackgroundFactoryProbe(), newSDK = BackgroundSessionProbe(identity: seed.fixture.plan.session)
        let fresh = ProductBackgroundMediaFactory(library: library, sessionFactory: { _ in await calls.sdkCreated(); return newSDK },
            sourceFactory: { _ in await calls.sourceCreated(); throw BackendContractError.unavailable })
        #expect(await fresh.stopForInvalidation(seed.record, epoch: seed.epoch) == .unknown)
        #expect(await fresh.observeInvalidation(seed.record, epoch: seed.epoch) == .unknown)
        #expect(await calls.counts() == [0, 0])
        #expect((await managed.resources()).openHandles == 1)
        await sdk.complete(try #require(started.binding), outcome: .cancelled, finishEvents: true)
        try await backgroundInvalidationWaitForStopped(services.store, operation: seed.fixture.plan.context.operation)
        let before = try await mediaSnapshot(services.store)
        guard case .succeeded(let observed) = await fresh.observeInvalidation(seed.record, epoch: seed.epoch) else {
            throw BackendContractError.unknownResult
        }
        #expect(observed.validates(record: seed.record, epoch: seed.epoch, backend: before))
        #expect(await calls.counts() == [1, 0]) // Fresh enumeration only, no source factory/adoption.
        #expect(try await mediaSnapshot(services.store) == before)
        #expect(try await mediaSnapshot(services.store).invalidations.isEmpty)
        await sdk.finishStream(); await newSDK.finishStream(); _ = try await managed.closeOwner()
    }

    @Test func wrapperRequiresTheActualPendingReservationBeforeCallingAnyBackgroundOrPlayerPort() async throws {
        let library = ProductLibraryFactory(supportDirectory: try backgroundInvalidationProductParent(), photoLibrary: BackgroundInvalidationUnusedPhotos())
        let services = try await library.open(), seed = try await BackgroundProductInvalidationSeed.make(services)
        let player = BackgroundInvalidationOriginalPlayer()
        let media = ProductMediaTermination(store: services.store, access: services.access, player: player)
        let background = BackgroundInvalidationCallProbe()
        let wrapper = ProductStatusInvalidationTermination(boundary: .init(store: services.store,
            identity: seed.fixture.plan.context.storeIdentity, registration: seed.registration), originals: services.store,
            media: media, admission: { true }, background: background)
        do { try await wrapper.stopAndObserve(original: seed.rendition.original, epoch: seed.epoch); Issue.record("Missing reservation was accepted") }
        catch {}
        #expect(await background.count() == 0)
        #expect(player.stops == 0)
        guard case .succeeded = await services.access.reserveInvalidation(seed.record) else { throw BackendContractError.notCommitted }
        do { try await wrapper.stopAndObserve(original: seed.rendition.original, epoch: .init(rawValue: UUID().uuidString)); Issue.record("Wrong epoch was accepted") }
        catch {}
        #expect(await background.count() == 0)
        #expect(player.stops == 0)
        #expect(try await mediaSnapshot(services.store).invalidations.isEmpty)
    }
}

@MainActor struct BackgroundProductInvalidationSeed {
    let fixture: BackgroundCoordinatorFixture
    let binding: OriginalBinding
    let rendition: RenditionIdentity
    let record: InvalidationRecord
    let registration: DeviceRegistration
    let epoch: ReaderReconciliationEpoch
    let connection: RegistrationConnection

    static func make(_ services: ProductLibraryServices) async throws -> Self {
        let originals = OriginalRemovalFixture(run: services.run, store: services.store,
            files: services.originals, access: services.access)
        // This new product-only root needs a wire-valid connection identity;
        // the existing coordinator fixture intentionally uses legacy text IDs.
        let binding = try await originals.original("background-product-invalidation-" + UUID().uuidString)
        let registered = try await inventoryRegister(services.store)
        let registration = registered.server.registration
        let initial = try await mediaSnapshot(services.store)
        let identity = try #require(initial.storeIdentity)
        let operation = MediaOperationID(rawValue: UUID().uuidString.lowercased())
        let request = MediaRequest(operation: operation, target: .original(binding.original), purpose: .upload,
            registration: registration, expectedStartRevision: initial.revision)
        _ = try await mediaCommit(services.store, .request(command: operation, value: request))
        let macSession = UploadSessionID(rawValue: UUID().uuidString.lowercased())
        _ = try await mediaCommit(services.store, .requestTransition(command: .init(rawValue: UUID().uuidString.lowercased()),
            operation: operation, target: request.target, registration: registration,
            value: .reconciled(.init(context: .init(operation: operation, registration: registration,
                target: request.target, session: macSession), observation: .init(rawValue: 1), result: .notExecuted))))
        var upload = URLRequest(url: try #require(URL(string: "https://example.invalid/background-media")))
        upload.httpMethod = "PUT"
        let plan = BackgroundMediaUploadPlan(id: .init(rawValue: UUID().uuidString.lowercased()),
            context: .init(operation: operation, attempt: .init(rawValue: UUID().uuidString.lowercased()),
                target: request.target, registration: registration, gateGeneration: 1, storeIdentity: identity),
            session: .init(identifier: .init(rawValue: "test.FrameRelay.background." + UUID().uuidString),
                generation: .init(rawValue: UUID())), taskDescription: UUID().uuidString,
            sourceID: .init(rawValue: UUID().uuidString), macSession: macSession, request: upload)
        let fixture = BackgroundCoordinatorFixture(originals: originals, plan: plan)
        let rendition = statusRendition(fixture.plan.context.target.original)
        _ = try await mediaCommit(services.store, .publication(mediaPublication(rendition, registration: fixture.plan.context.registration)))
        let snapshot = try await mediaSnapshot(services.store), original = try await mediaOriginalSnapshot(services.store)
        return .init(fixture: fixture, binding: try #require(original.originals.first?.binding), rendition: rendition,
            record: statusInvalidation(rendition, registration: fixture.plan.context.registration),
            registration: try #require(snapshot.registrations.last), epoch: try #require(original.reconciliationEpoch),
            connection: try .init(endpoint: .init(httpsOrigin: "https://127.0.0.1:1"), destination: fixture.plan.context.registration.destination))
    }
}

nonisolated func backgroundInvalidationProductParent() throws -> URL {
    let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent("FrameRelay-background-invalidation-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
    return parent
}

nonisolated func backgroundInvalidationWaitForStopped(_ store: any MediaOperationStorePort, operation: MediaOperationID) async throws {
    try await backgroundEventually {
        guard case .loaded(let snapshot) = await store.load() else { return false }
        return snapshot.requests.first(where: { $0.operation == operation })?.transport == .stopped
            && snapshot.backgroundTasks.first(where: { $0.intent.context.operation == operation })?.ownerClosure != nil
    }
}

nonisolated struct BackgroundInvalidationNoCredentials: RegistrationAuthorizationPort {
    func authorization(for connection: RegistrationConnection, intent: RegistrationIntent?, storeIdentity: RegistrationStoreIdentity) async throws -> RegistrationAuthorization {
        throw RegistrationAccessError.credentialUnavailable
    }
}

nonisolated struct BackgroundInvalidationEmptyVault: RegistrationVaultPort {
    func connection(storeIdentity: RegistrationStoreIdentity?) async throws -> RegistrationConnection? { nil }
    func saveConnection(_ connection: RegistrationConnection, bearer: String, storeIdentity: RegistrationStoreIdentity) async throws { throw RegistrationAccessError.credentialUnavailable }
    func prepareIntent(for destination: DestinationIdentity, storeIdentity: RegistrationStoreIdentity) async throws -> RegistrationIntent { throw RegistrationAccessError.credentialUnavailable }
    func requireCredential(for intent: RegistrationIntent, storeIdentity: RegistrationStoreIdentity) async throws { throw RegistrationAccessError.credentialUnavailable }
}

actor BackgroundInvalidationUnusedPhotos: PhotoLibraryPort {
    private var calls = 0
    func authorizationStatus(for access: PhotoLibraryAccess) -> PhotoLibraryAuthorization { calls += 1; return .denied }
    func requestAuthorization(for access: PhotoLibraryAccess) -> PhotoLibraryAuthorization { calls += 1; return .denied }
    func add(_ command: PhotoLibraryAddCommand) -> PhotoRegistrationResult { calls += 1; return .init(intent: command.registration.intent, outcome: .unknown(localIdentifier: nil)) }
    func lookup(_ identifier: PhotoAssetIdentifier) -> PhotoLibraryLookupResult { calls += 1; return .init(identifier: identifier, authorization: .denied, presence: .unavailable) }
    func callCount() -> Int { calls }
}

@MainActor private final class BackgroundInvalidationOriginalPlayer: OriginalPlaybackTerminationPort {
    private(set) var stops = 0
    @MainActor func stopAndObserve(original: OriginalContent) async throws -> OriginalPlaybackTermination {
        stops += 1; return .init(original: original, admissionClosed: true, createdOwners: 0, terminals: [])
    }
    @MainActor func resumeAfterInvalidation(_ acknowledgement: InvalidationAcknowledgement) async throws {}
}

private actor BackgroundInvalidationCallProbe: BackgroundInvalidationTerminationPort {
    private var calls = 0
    func stopForInvalidation(_ record: InvalidationRecord, epoch: ReaderReconciliationEpoch) -> BackendOutcome<BackgroundInvalidationObservation> { calls += 1; return .unknown }
    func observeInvalidation(_ record: InvalidationRecord, epoch: ReaderReconciliationEpoch) -> BackendOutcome<BackgroundInvalidationObservation> { calls += 1; return .unknown }
    func count() -> Int { calls }
}
