import Foundation
import Testing
@testable import FrameRelay

@MainActor struct ProductPhotoCompositionTests {
    @Test func productOpenRefreshAndCapturePreparationNeverQueryOrRequestPhotos() async throws {
        let photos = ProductPhotoLibrarySpy(status: .denied)
        let factory = ProductLibraryFactory(supportDirectory: try photoCompositionParent(), photoLibrary: photos)
        let composition = photoComposition(factory: factory)
        await composition.open()
        let library = try #require(composition.library)
        let capture = try #require(composition.capture)
        await library.refresh()
        await composition.presentationEnded()
        await composition.open()
        #expect(composition.library === library)
        #expect(composition.capture === capture)
        #expect(composition.openingIssue == nil)
        let services = try await factory.open()
        let again = try await factory.open()
        #expect(services.store === again.store)
        #expect(services.reader === again.reader)
        #expect(services.photoReconciliation === again.photoReconciliation)
        let fixture = try CaptureFixture(clip: "capture-with-denied-photo-permission")
        let device = ProductCaptureTestDevice(fixture: fixture)
        let prepared = ProductCaptureFactory.make(services: services, didSave: {}, makeDevice: { _, _, _, _ in device })
        prepared.enterCapture()
        await prepared.load()
        await prepared.updatePreferences(.init(desired: fixture.desired, outputCandidate: .sampleWriter))
        await prepared.prepare()
        #expect(prepared.canRecord)
        await prepared.leaveCapture()
        #expect(await photos.statusRequests.isEmpty)
        #expect(await photos.permissionRequests.isEmpty)
        #expect(await photos.lookups.isEmpty)
        #expect(await photos.additions == 0)
        #expect(try await mediaSnapshot(services.store).photoRegistrations.isEmpty)
    }

    @Test func explicitDeniedReconciliationCommitsToTheSameWriterAndKeepsCaptureAvailable() async throws {
        let photos = ProductPhotoLibrarySpy(status: .notDetermined)
        let parent = try photoCompositionParent()
        let factory = ProductLibraryFactory(supportDirectory: parent, photoLibrary: photos)
        let services = try await factory.open()
        let fixture = try await makePhotoCompositionFixture(services)
        let composition = photoComposition(factory: factory)
        await composition.open()
        let library = try #require(composition.library)
        let capture = try #require(composition.capture)
        let row = try #require(library.item(fixture.intent.key.capture)?.photoRegistrations.first)
        #expect(row.registrationResult.contains("結果不明"))
        #expect(await photos.permissionRequests.isEmpty)
        await library.refresh()
        #expect(await photos.statusRequests.isEmpty)
        #expect(await photos.permissionRequests.isEmpty)
        let before = try await mediaSnapshot(services.store)
        await library.reconcilePhotos(row, capture: fixture.intent.key.capture)
        let after = try await mediaSnapshot(services.store)
        let persisted = try #require(after.photoRegistrations.last)
        #expect(after.revision == before.revision + 1)
        #expect(persisted.registration.intent == fixture.intent)
        #expect(persisted.currentPresence?.authorization == .denied)
        #expect(persisted.currentPresence?.presence == .unavailable)
        #expect(persisted.outcome == .unknown(localIdentifier: fixture.identifier))
        #expect(library.snapshot?.revision == after.revision)
        #expect(library.item(fixture.intent.key.capture)?.status(.photoPresence).contains("読み取り拒否") == true)
        #expect(library.item(fixture.intent.key.capture)?.status(.photos).contains("結果不明") == true)
        #expect(await photos.statusRequests == [.readWrite])
        #expect(await photos.permissionRequests == [.readWrite])
        #expect(await photos.lookups.isEmpty)
        #expect(await photos.additions == 0)
        #expect(composition.capture === capture)
        #expect(composition.openingIssue == nil)
        let save = library.availability(.saveToPhotos, captures: [fixture.intent.key.capture])
        #expect(save.reason?.contains("まだ利用できません") == true)
        #expect(save.reason?.contains("過去の登録記録") == true)
        await library.submit(.saveToPhotos, captures: [fixture.intent.key.capture])
        #expect(library.submission == nil)
        #expect(await photos.additions == 0)
        let reopened = try await ProductLibraryFactory(supportDirectory: parent, photoLibrary: photos).open()
        guard case .loaded(let snapshot) = await reopened.reader.loadLibrary() else {
            Issue.record("Photos projection did not survive the product store reopen"); return
        }
        #expect(snapshot.items.first?.photoRegistrations.first?.record == persisted)
        let newFixture = try CaptureFixture(clip: "record-ready-after-photo-denial")
        let device = ProductCaptureTestDevice(fixture: newFixture)
        let prepared = ProductCaptureFactory.make(services: services, didSave: {}, makeDevice: { _, _, _, _ in device })
        prepared.enterCapture()
        await prepared.load()
        await prepared.updatePreferences(.init(desired: newFixture.desired, outputCandidate: .sampleWriter))
        await prepared.prepare()
        #expect(prepared.canRecord)
        await prepared.leaveCapture()
        #expect(await photos.permissionRequests == [.readWrite])
        // Retain all exact fixture owners through the final checks. No active
        // temporary-media or original files are unlinked by the test.
        _ = fixture.temporary
    }
}

@MainActor private func photoComposition(factory: ProductLibraryFactory) -> ProductComposition {
    ProductComposition(factory: factory, registrationFactory: { store in
        RegistrationCoordinator(store: store, vault: PhotoCompositionEmptyVault(), remote: RegistrationTestRemote())
    })
}

nonisolated private func photoCompositionParent() throws -> URL {
    let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent("FrameRelay-photo-composition-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
    return parent
}

nonisolated private struct PhotoCompositionFixture: Sendable {
    let intent: PhotoRegistrationIntent
    let identifier: PhotoAssetIdentifier
    let temporary: ManagedTemporaryMedia
}

/// Explicit, isolated test data passes through the real product writer and real
/// temporary-media ownership. It makes no image-quality or real Photos claim.
nonisolated private func makePhotoCompositionFixture(_ services: ProductLibraryServices) async throws -> PhotoCompositionFixture {
    let fixture = try CaptureFixture(clip: "s31-composition-photo")
    let bytes = Data(repeating: 0x31, count: 4096)
    let originalURL = try await services.originals.reserve(original: fixture.intent.original)
    try bytes.write(to: originalURL)
    let saved = try syntheticResult(fixture)
    let initial = try await mediaSnapshot(services.store)
    guard case .committed = await services.store.execute(.commitIntent(fixture.token(1), expectedRevision: initial.revision, fixture.intent)),
          case .committed(let saveCommit) = await services.store.execute(.commitResult(fixture.token(4), expectedRevision: initial.revision + 1, saved)) else {
        throw BackendContractError.notCommitted
    }
    let original = OriginalContent(capture: fixture.context.capture, generation: .init(rawValue: 1), content: try renditionContent(bytes))
    let binding = OriginalBinding(original: original, reference: fixture.intent.original, saveRecord: saved, saveCommit: saveCommit)
    _ = try await mediaOriginalCommit(services.store, .bind(binding))
    _ = try await establishRegistrationIdentity(services.store)
    let registration = try await mediaRegister(services.store)
    let rendition = RenditionIdentity(original: original, inputLogIdentity: "synthetic-not-log",
        transformAssetIdentity: "no-quality-claim", transformAssetVersion: "fixture-v1",
        outputConfigurationIdentity: "fixture-output", conversionVersion: "fixture-v1",
        rendition: .init(rawValue: "s31-composition-rendition"), deliveryContent: original.content,
        publicationGeneration: .init(rawValue: 1))
    _ = try await mediaCommit(services.store, .publication(mediaPublication(rendition, registration: registration)))
    let operation = MediaOperationID(rawValue: "s31-composition-download")
    let distribution = DistributionReceipt(operation: operation, rendition: rendition, registration: registration,
        commit: .init(key: .distribution(operation, rendition, registration), previousRevision: 0, committedRevision: 1))
    let command = RetrieveMediaCommand(gate: .init(operation: operation, attempt: .init(rawValue: "s31-fixture-attempt"),
        target: .rendition(rendition), registration: registration, generation: 1), distribution: distribution, range: nil)
    let leases = RenditionReadLeases(store: services.store)
    let scope = try await RenditionMediaScope.open(original: original, leases: leases)
    let temporary = try await ManagedTemporaryMedia.open(root: services.run.url.appendingPathComponent("photo-composition-temporary"),
        leases: leases, scope: scope)
    let receipt = try await temporary.create(command: command, id: .init(rawValue: "s31-composition-media"),
        usageID: .init(rawValue: "s31-composition-download-use"), capturedAt: RenditionFixture.capturedAt, contentType: "video/quicktime")
    try await temporary.store(bytes, range: .init(lowerBound: 0, upperBound: UInt64(bytes.count)), using: receipt.usage)
    let complete = try await temporary.verify(receipt.usage)
    guard case .succeeded(let usage) = await temporary.acquireUsage(complete.id, purpose: .photoHandoff,
        usageID: .init(rawValue: "s31-composition-photo-use")) else { throw BackendContractError.ineligibleOriginal }
    let media = try await temporary.resolvePhotoMedia(usage)
    guard case .succeeded = await temporary.releaseUsage(complete.usage) else { throw BackendContractError.readersActive }
    let intent = try PhotoRegistrationIntent(operation: .init(rawValue: "s31-composition-add-intent"), handoff: media.handoff)
    _ = try await mediaCommit(services.store, .photo(command: intent.operation, value: .intent(intent)))
    let identifier = try PhotoAssetIdentifier(rawValue: "s31-composition-exact-identifier")
    _ = try await mediaCommit(services.store, .photo(command: .init(rawValue: "s31-composition-unknown-result"),
        value: .result(.init(intent: intent, outcome: .unknown(localIdentifier: identifier)))))
    return .init(intent: intent, identifier: identifier, temporary: temporary)
}

private actor ProductPhotoLibrarySpy: PhotoLibraryPort {
    private var status: PhotoLibraryAuthorization
    private(set) var statusRequests: [PhotoLibraryAccess] = []
    private(set) var permissionRequests: [PhotoLibraryAccess] = []
    private(set) var lookups: [PhotoAssetIdentifier] = []
    private(set) var additions = 0
    init(status: PhotoLibraryAuthorization) { self.status = status }
    func authorizationStatus(for access: PhotoLibraryAccess) -> PhotoLibraryAuthorization {
        statusRequests.append(access); return status
    }
    func requestAuthorization(for access: PhotoLibraryAccess) -> PhotoLibraryAuthorization {
        permissionRequests.append(access); status = .denied; return status
    }
    func lookup(_ identifier: PhotoAssetIdentifier) -> PhotoLibraryLookupResult {
        lookups.append(identifier)
        return .init(identifier: identifier, authorization: status, presence: .unavailable)
    }
    func add(_ command: PhotoLibraryAddCommand) -> PhotoRegistrationResult {
        additions += 1
        return .init(intent: command.registration.intent, outcome: .unknown(localIdentifier: nil))
    }
}

nonisolated private struct PhotoCompositionEmptyVault: RegistrationVaultPort {
    func connection(storeIdentity: RegistrationStoreIdentity?) async throws -> RegistrationConnection? { nil }
    func saveConnection(_ connection: RegistrationConnection, bearer: String, storeIdentity: RegistrationStoreIdentity) async throws {
        throw RegistrationAccessError.credentialUnavailable
    }
    func prepareIntent(for destination: DestinationIdentity, storeIdentity: RegistrationStoreIdentity) async throws -> RegistrationIntent {
        throw RegistrationAccessError.credentialUnavailable
    }
    func requireCredential(for intent: RegistrationIntent, storeIdentity: RegistrationStoreIdentity) async throws {
        throw RegistrationAccessError.credentialUnavailable
    }
}
