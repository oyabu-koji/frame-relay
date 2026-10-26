import Foundation
import Security
import Testing
@testable import FrameRelay

@Suite(.serialized) @MainActor struct ProductStatusSynchronizationTests {
    @Test func injectedRegistrationKeepsExistingBehaviorWithoutProductCredentialFallback() async throws {
        let parent = try statusCompositionParent()
        let keychain = try RegistrationTestKeychain(); defer { keychain.cleanup() }
        let vault = try keychain.vault(), remote = RegistrationTestRemote()
        let composition = ProductComposition(factory: .init(supportDirectory: parent), registrationFactory: { store in
            RegistrationCoordinator(store: store, vault: vault, remote: remote)
        })
        await composition.open()
        let model = try #require(composition.connection)
        #expect(!model.supportsStatusSynchronization && composition.statusSynchronization == nil)
        #expect(await remote.posts == 0)
        #expect(await remote.lookups == 0)
        #expect(await remote.discoveries == 0)
        #expect(composition.library != nil)
    }

    @Test func explicitRegisteredModelOperationUsesOneWriterAndRefreshesLibrary() async throws {
        let factory = ProductLibraryFactory(supportDirectory: try statusCompositionParent())
        let services = try await factory.open()
        let keychain = try RegistrationTestKeychain(); defer { keychain.cleanup() }
        let vault = try keychain.vault(), registrationRemote = RegistrationTestRemote()
        let registration = RegistrationCoordinator(store: services.store, vault: vault, remote: registrationRemote)
        guard case .registered = await registration.register(connection: keychain.connection, bearer: "synthetic-bootstrap") else {
            throw BackendContractError.notCommitted
        }
        let binding = try await statusKnownOriginal(try publicationOriginal("composition-known"), store: services.store)
        let remote = StatusMetadataRemote(); remote.setManifest(statusRendition(binding.original), revision: 1)
        let composition = ProductComposition(factory: factory, registrationFactory: { store in
            RegistrationCoordinator(store: store, vault: vault, remote: registrationRemote)
        }, statusSynchronizationFactory: { opened, media in
            ProductStatusSynchronization(store: opened.store, access: opened.access, media: media, credentials: vault,
                admission: { true }, remoteFactory: { _, _, _, _ in remote })
        })
        await composition.open()
        let model = try #require(composition.connection)
        #expect(model.canSynchronize && remote.afters.isEmpty && remote.manifestCalls.isEmpty)
        #expect(try await mediaSnapshot(services.store).publications.isEmpty)
        await model.synchronizeStatus()
        #expect(model.synchronizationReport?.phase == .checked)
        #expect(composition.library?.item(binding.original.capture)?.status(.publication).contains("公開版の保存記録あり") == true)
        #expect(composition.library?.snapshot?.revision == (try await mediaSnapshot(services.store).revision))
        #expect(try await mediaSnapshot(services.store).confirmations.isEmpty)
        await composition.open()
        #expect(composition.connection === model && remote.afters.count == 1)
        #expect(remote.mediaCalls == 0 && remote.sent.isEmpty)
    }

    @Test func unknownPersistedOwnerDoesNotBecomeAnAckAndIndependentVideoContinues() async throws {
        try await withStorageRun { run in
            let f = try await StatusSynchronizationFixture.make(run: run, names: ["unknown-owner", "other-video"])
            let snapshot = try await mediaOriginalSnapshot(f.store)
            let lease = MediaReadLease(id: .init(rawValue: "old-owner"), target: .rendition(f.renditions[0]),
                operation: .init(rawValue: "old-read"), registration: f.registration.server.registration,
                context: .playback(.init(rawValue: "lost-player")), epoch: try #require(snapshot.reconciliationEpoch),
                accessGeneration: .init(rawValue: 1))
            _ = try await mediaOriginalCommit(f.store, .acquireMedia(lease))
            let record = statusInvalidation(f.renditions[0], registration: f.registration.server.registration)
            f.remote.pages = [.succeeded(.init(records: [record], nextAfter: nil))]
            f.remote.setManifest(statusRendition(f.renditions[1].original, version: 2), revision: 2)
            let player = StatusOriginalPlayer()
            let access = ManagedOriginalAccess(store: f.store, originals: ManagedOriginalStore(run: run))
            let media = ProductMediaTermination(store: f.store, access: access, player: player)
            let port = ProductStatusSynchronization(store: f.store, access: access, media: media,
                credentials: StatusUnavailableCredentials(), admission: { true }, remoteFactory: { _, _, _, _ in f.remote })
            let report = await port.synchronize(connection: try statusConnection(), registration: f.registration)
            #expect(report.phase == .partial && report.unresolvedInvalidations == 1)
            #expect(report.items.last?.disposition == .recorded)
            #expect(try await mediaSnapshot(f.store).invalidations.isEmpty)
            #expect(f.remote.sent.isEmpty && f.remote.mediaCalls == 0)
            #expect(try await mediaOriginalSnapshot(f.store).logicalOriginals.first?.invalidation?.record == record)
        }
    }

    @Test func preparedBackgroundSourceWithoutReadersRemainsUnresolved() async throws {
        try await withStorageRun { run in
            let f = try await StatusSynchronizationFixture.make(run: run)
            let intent = try await statusBackgroundDownload(f, prepared: true)
            if case .download(_, _, let lease) = intent.source { _ = try await mediaOriginalCommit(f.store, .releaseMedia(lease)) }
            let record = statusInvalidation(f.renditions[0], registration: f.registration.server.registration)
            f.remote.pages = [.succeeded(.init(records: [record], nextAfter: nil))]
            let player = StatusOriginalPlayer()
            let access = ManagedOriginalAccess(store: f.store, originals: ManagedOriginalStore(run: run))
            let media = ProductMediaTermination(store: f.store, access: access, player: player)
            let port = ProductStatusSynchronization(store: f.store, access: access, media: media,
                credentials: StatusUnavailableCredentials(), admission: { true }, remoteFactory: { _, _, _, _ in f.remote })
            let report = await port.synchronize(connection: try statusConnection(), registration: f.registration)
            #expect(report.phase == .partial && report.unresolvedInvalidations == 1)
            #expect(player.stops == 0)
            #expect(try await mediaSnapshot(f.store).invalidations.isEmpty && f.remote.sent.isEmpty)
            #expect(try await mediaSnapshot(f.store).backgroundTasks.first?.binding == nil)
        }
    }

    @Test func writerReservationFencesBackgroundPreparationAndNewReaderDuringTerminalAwait() async throws {
        try await withStorageRun { run in
            let f = try await StatusSynchronizationFixture.make(run: run)
            let intent = try await statusBackgroundDownload(f, prepared: false)
            let record = statusInvalidation(f.renditions[0], registration: f.registration.server.registration)
            f.remote.pages = [.succeeded(.init(records: [record], nextAfter: nil))]
            f.remote.setManifest(f.renditions[0], revision: 2, generation: 1)
            let player = StatusOriginalPlayer()
            player.onStop = {
                let before = try await mediaSnapshot(f.store)
                let attempted = BackendStoreMutation(expectedRevision: before.revision,
                    change: .backgroundTask(command: .init(rawValue: "racing-prepare"), value: .prepared(intent)),
                    expectedStoreIdentity: f.identity)
                #expect(await f.store.commit(attempted) == .rejected(.deletionUnresolved))
                guard case .download(_, _, let owned) = intent.source else { throw BackendContractError.invalidValue }
                let other = MediaReadLease(id: .init(rawValue: "racing-acquire"), target: owned.target,
                    operation: owned.operation, registration: owned.registration, context: owned.context,
                    epoch: owned.epoch, accessGeneration: .init(rawValue: 2))
                let current = try await mediaOriginalSnapshot(f.store)
                #expect(await f.store.commitOriginal(.init(operation: .init(rawValue: "racing-acquire"),
                    expectedRevision: current.revision, change: .acquireMedia(other))) == .rejected(.deletionUnresolved))
                // Explicit technical owner terminal: no SDK factory was called
                // before the rejected prepared intent, and this lease is closed.
                _ = try await mediaOriginalCommit(f.store, .releaseMedia(owned))
            }
            let access = ManagedOriginalAccess(store: f.store, originals: ManagedOriginalStore(run: run))
            let media = ProductMediaTermination(store: f.store, access: access, player: player)
            let port = ProductStatusSynchronization(store: f.store, access: access, media: media,
                credentials: StatusUnavailableCredentials(), admission: { true }, remoteFactory: { _, _, _, _ in f.remote })
            let report = await port.synchronize(connection: try statusConnection(), registration: f.registration)
            #expect(report.phase == .checked)
            #expect(try await mediaSnapshot(f.store).backgroundTasks.isEmpty)
            #expect(try await mediaSnapshot(f.store).invalidations.count == 1)
            #expect(f.remote.sent.count == 1 && f.remote.mediaCalls == 0)
            #expect(player.stops == 1 && player.resumes == 1)
        }
    }
}

@MainActor private final class StatusOriginalPlayer: OriginalPlaybackTerminationPort {
    var onStop: (@MainActor () async throws -> Void)?
    private(set) var stops = 0
    private(set) var resumes = 0
    func stopAndObserve(original: OriginalContent) async throws -> OriginalPlaybackTermination {
        stops += 1; try await onStop?()
        return .init(original: original, admissionClosed: true, createdOwners: 0, terminals: [])
    }
    func resumeAfterInvalidation(_ acknowledgement: InvalidationAcknowledgement) async throws { resumes += 1 }
}
nonisolated private struct StatusUnavailableCredentials: RegistrationAuthorizationPort {
    func authorization(for connection: RegistrationConnection, intent: RegistrationIntent?, storeIdentity: RegistrationStoreIdentity) async throws -> RegistrationAuthorization {
        throw RegistrationAccessError.credentialUnavailable
    }
}
nonisolated private func statusConnection() throws -> RegistrationConnection {
    try .init(endpoint: .init(httpsOrigin: "https://127.0.0.1:1"),
              destination: .init(rawValue: "9a3ba104-985f-4a2d-875d-d458258b9b6b"))
}
nonisolated private func statusCompositionParent() throws -> URL {
    let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent("FrameRelay-status-composition-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
    return parent
}
@MainActor private func statusBackgroundDownload(_ f: StatusSynchronizationFixture, prepared: Bool) async throws -> BackgroundMediaTaskIntent {
    let rendition = f.renditions[0], registration = f.registration.server.registration
    let operation = MediaOperationID(rawValue: "background-download"), attempt = TransferAttemptID(rawValue: "background-attempt")
    let before = try await mediaSnapshot(f.store)
    let request = MediaRequest(operation: operation, target: .rendition(rendition), purpose: .download,
        registration: registration, expectedStartRevision: before.revision)
    _ = try await mediaCommit(f.store, .request(command: operation, value: request))
    _ = try await mediaCommit(f.store, .requestTransition(command: .init(rawValue: "download-reconciled"), operation: operation,
        target: request.target, registration: registration, value: .reconciled(.init(
            context: .init(operation: operation, registration: registration, target: request.target, session: nil),
            observation: .init(rawValue: 1), result: .notExecuted))))
    _ = try await mediaCommit(f.store, .requestTransition(command: .init(rawValue: "download-begin"), operation: operation,
        target: request.target, registration: registration, value: .beginAttempt(attempt)))
    let state = try await mediaOriginalSnapshot(f.store)
    let lease = MediaReadLease(id: .init(rawValue: "background-reader"), target: request.target, operation: operation,
        registration: registration, context: .transport(attempt), epoch: try #require(state.reconciliationEpoch), accessGeneration: .init(rawValue: 1))
    _ = try await mediaOriginalCommit(f.store, .acquireMedia(lease))
    let intent = BackgroundMediaTaskIntent(id: .init(rawValue: UUID().uuidString), context: .init(operation: operation, attempt: attempt,
        target: request.target, registration: registration, gateGeneration: 1, storeIdentity: f.identity),
        session: .init(identifier: .init(rawValue: "FrameRelay.status.synthetic." + UUID().uuidString), generation: .init(rawValue: UUID())),
        taskDescription: UUID().uuidString, requestFingerprint: .init(sha256: String(repeating: "b", count: 64)),
        source: .download(rendition: rendition, range: nil, lease: lease))
    if prepared {
        let snapshot = try await mediaSnapshot(f.store)
        guard case .committed = await f.store.commit(.init(expectedRevision: snapshot.revision,
            change: .backgroundTask(command: .init(rawValue: "prepared-background"), value: .prepared(intent)), expectedStoreIdentity: f.identity)) else {
            throw BackendContractError.notCommitted
        }
    }
    return intent
}

/// These three cases are explicit test-target fixtures for the dedicated empty
/// Simulator. The production App has no seed, credential injection or success
/// branch. Existing stores and Keychain records are never reset or overwritten.
@Suite(.serialized) @MainActor struct ProductStatusSynchronizationSeedTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_S28_STATUS_SEED"] == "1"))
    func seedDedicatedRegisteredRoot() async throws {
        let nonce = try statusSeedNonce()
        let services = try await ProductLibraryFactory.shared.open()
        let before = try await mediaSnapshot(services.store)
        let originals = try await mediaOriginalSnapshot(services.store)
        guard case .loaded(let recordings) = await services.store.loadRecordings() else { throw BackendContractError.unavailable }
        try #require(before.revision == 0 && before.storeIdentity == nil && before.registrationIntents.isEmpty
            && before.registrations.isEmpty && before.publications.isEmpty && before.requests.isEmpty && before.backgroundTasks.isEmpty
            && before.confirmations.isEmpty && before.invalidations.isEmpty && before.outbox.isEmpty
            && recordings.recordings.isEmpty && originals.logicalOriginals.isEmpty)
        try #require(try statusProductKeychainIsEmpty())
        let vault = KeychainRegistrationVault()
        try #require(try await vault.connection(storeIdentity: nil) == nil)
        let file = services.run.url.appendingPathComponent("s28-status-seed.json")
        try #require(!FileManager.default.fileExists(atPath: file.path))
        let identity = try await establishRegistrationIdentity(services.store)
        let connection = try statusConnection()
        try await vault.saveConnection(connection, bearer: "s28-synthetic-" + nonce, storeIdentity: identity)
        let intent = try await vault.prepareIntent(for: connection.destination, storeIdentity: identity)
        _ = try await mediaCommit(services.store, .registrationIntent(intent))
        _ = try await mediaCommit(services.store, .registration(.init(intent: intent, registration: .init(destination: connection.destination,
            id: .init(rawValue: UUID().uuidString.lowercased()), generation: .init(rawValue: 1)))))
        let registration = try #require(try await mediaSnapshot(services.store).registrations.last)
        let binding = try await statusKnownOriginal(try publicationOriginal("s28-" + nonce), store: services.store)
        let observation = mediaPublication(statusRendition(binding.original), registration: registration.server.registration)
        let commit = try await mediaCommit(services.store, .publication(observation))
        let manifest = StatusSeedManifest(nonce: nonce, identity: identity, registration: registration, binding: binding,
            observation: observation, commit: commit)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(manifest).write(to: file, options: .withoutOverwriting)
        #expect(try await mediaSnapshot(services.store).confirmations.isEmpty)
        print("S28_STATUS_SEED nonce=\(nonce) registered=true publication=synthetic metadataOnly=true")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_S28_STATUS_VERIFY"] == "1"))
    func verifyDedicatedRegisteredRoot() async throws {
        let nonce = try statusSeedNonce()
        let services = try await ProductLibraryFactory.shared.open()
        let file = services.run.url.appendingPathComponent("s28-status-seed.json")
        let manifest = try JSONDecoder().decode(StatusSeedManifest.self, from: Data(contentsOf: file))
        try #require(manifest.nonce == nonce)
        let snapshot = try await mediaSnapshot(services.store)
        #expect(snapshot.storeIdentity == manifest.identity && snapshot.registrations == [manifest.registration])
        #expect(snapshot.publications.count == 1 && snapshot.publications[0].observation == manifest.observation
            && snapshot.publications[0].commit == manifest.commit)
        #expect(snapshot.confirmations.isEmpty && snapshot.invalidations.isEmpty && snapshot.deliveries.isEmpty
            && snapshot.outbox.isEmpty && snapshot.requests.isEmpty && snapshot.backgroundTasks.isEmpty && snapshot.temporaryMedia.isEmpty)
        let originals = try await mediaOriginalSnapshot(services.store)
        #expect(originals.originals.map(\.binding) == [manifest.binding])
        #expect(originals.logicalOriginals.allSatisfy { $0.readers.isEmpty && $0.mediaReaders.isEmpty && $0.invalidation == nil })
        let restored = await RegistrationCoordinator(store: services.store, vault: KeychainRegistrationVault(),
            remote: RegistrationTestRemote()).restore()
        #expect(registrationIsCommitted(restored))
        print("S28_STATUS_VERIFY nonce=\(nonce) publication=preserved confirmations=0 mediaRecords=0")
    }
}

nonisolated private struct StatusSeedManifest: Codable {
    let nonce: String
    let identity: RegistrationStoreIdentity
    let registration: DeviceRegistration
    let binding: OriginalBinding
    let observation: PublishedRenditionObservation
    let commit: BackendCommitReceipt
}
nonisolated private func statusSeedNonce() throws -> String {
    let env = ProcessInfo.processInfo.environment
    let nonce = env["FR_S28_STATUS_NONCE"] ?? ""
    try #require(UUID(uuidString: nonce)?.uuidString.lowercased() == nonce)
    let expected = try #require(env["FR_S28_STATUS_SIMULATOR_UDID"])
    let actual = try #require(env["SIMULATOR_UDID"])
    try #require(UUID(uuidString: expected) != nil && actual == expected)
    return nonce
}
nonisolated private func statusProductKeychainIsEmpty() throws -> Bool {
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: KeychainRegistrationVault.productService,
        kSecAttrSynchronizable as String: false, kSecUseDataProtectionKeychain as String: true,
        kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return true }
    guard status == errSecSuccess else { throw RegistrationAccessError.credentialUnavailable }
    return false
}

/// A separate explicit HTTP run: the existing publication fixture is used only
/// for the two bounded JSON reads. No distribution, playback or fixture control
/// endpoint is available to this case, and this is not formal quality proof.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["FR_S27_HTTP_FIXTURE"] == "1"
    && ProcessInfo.processInfo.environment["FR_S28_METADATA_ONLY"] == "1"))
@MainActor struct StatusSynchronizationHTTPFixtureTests {
    @Test func metadataOnlyPageAndManifestUseCoordinator() async throws {
        let config = try StatusHTTPConfiguration()
        try await withStorageRun { run in
            let store = try SQLiteRecordingStore(run: run, mode: .createNew)
            let identity = try await establishRegistrationIdentity(store)
            _ = try await mediaCommit(store, .registrationIntent(config.receipt.intent))
            _ = try await mediaCommit(store, .registration(config.receipt))
            let registration = try #require(try await mediaSnapshot(store).registrations.last)
            _ = try await statusKnownOriginal(config.rendition.original, store: store)
            let before = try await mediaSnapshot(store)
            let credentials = PublicationCredentialsFixture(registration: registration, identity: identity,
                material: .init(bearer: config.bearer, secret: config.registrationSecret))
            let remote = StatusObservedHTTPRemote(base: URLSessionPublicationRemote(connection: config.connection,
                credentials: credentials, store: store, identity: identity))
            let coordinator = BackendStatusSynchronizationCoordinator(store: store, identity: identity, registration: registration,
                remote: remote, invalidations: statusInvalidator(store: store, identity: identity, run: run))
            let result = await coordinator.synchronize()
            let saved = try await mediaSnapshot(store)
            let reopened = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let replay = try await mediaSnapshot(reopened)
            let matches = saved == replay
            let observation: [String: Any] = [
                "report_schema": "fr-s28-metadata-observation-v1", "probe_mode": "metadata-only", "fixtureOnly": true,
                "runIdentity": config.runIdentity, "boundedPages": remote.invalidationsStarted,
                "invalidationsStarted": remote.invalidationsStarted, "invalidationsCompleted": remote.invalidationsCompleted,
                "manifestStarted": remote.manifestStarted, "manifestCompleted": remote.manifestCompleted,
                "confirmationSend": remote.confirmationSend, "ackSend": remote.ackSend, "operationLookup": remote.operationLookup,
                "distribute": remote.distributeCount, "lookupDistribution": remote.lookupDistributionCount,
                "durablePublicationCount": saved.publications.count, "newConfirmations": saved.confirmations.count - before.confirmations.count,
                "reopenMatches": matches, "coordinatorAwaitCompleted": true, "sdkTerminalCountsObserved": false,
                "sdkTerminalContract": "PublicationURLSessionRequest awaits task completion and session invalidation"
            ]
            let data = try JSONSerialization.data(withJSONObject: observation, options: [.sortedKeys])
            Attachment.record(String(decoding: data, as: UTF8.self), named: "s28-metadata-observation.json")
            #expect(result.phase == .checked && !result.hasMore && result.unresolvedInvalidations == 0)
            #expect(remote.invalidationsStarted == 1 && remote.invalidationsCompleted == 1)
            #expect(remote.manifestStarted == 1 && remote.manifestCompleted == 1)
            #expect(remote.confirmationSend == 0 && remote.ackSend == 0 && remote.operationLookup == 0)
            #expect(remote.distributeCount == 0 && remote.lookupDistributionCount == 0)
            #expect(before.publications.isEmpty && saved.publications.count == 1)
            #expect(saved.publications.first?.observation.rendition == config.rendition)
            #expect(saved.confirmations.isEmpty && saved.invalidations.isEmpty && saved.outbox.isEmpty
                && saved.requests.isEmpty && saved.backgroundTasks.isEmpty && saved.temporaryMedia.isEmpty)
            #expect(matches && replay.storeIdentity == identity)
            let originals = try await mediaOriginalSnapshot(reopened)
            #expect(originals.logicalOriginals.allSatisfy { $0.readers.isEmpty && $0.mediaReaders.isEmpty })
        }
    }
}

@MainActor private final class StatusObservedHTTPRemote: PublicationRemotePort {
    let base: URLSessionPublicationRemote
    private(set) var invalidationsStarted = 0
    private(set) var invalidationsCompleted = 0
    private(set) var manifestStarted = 0
    private(set) var manifestCompleted = 0
    private(set) var confirmationSend = 0
    private(set) var ackSend = 0
    private(set) var operationLookup = 0
    private(set) var distributeCount = 0
    private(set) var lookupDistributionCount = 0
    init(base: URLSessionPublicationRemote) { self.base = base }
    func manifest(original: OriginalContent, registration: RegistrationIdentity) async -> BackendOutcome<PublicationManifest> {
        manifestStarted += 1
        let value = await base.manifest(original: original, registration: registration)
        manifestCompleted += 1
        return value
    }
    func invalidations(registration: RegistrationIdentity, after: InvalidationID?) async -> BackendOutcome<PublicationInvalidationPage> {
        invalidationsStarted += 1
        let value = await base.invalidations(registration: registration, after: after)
        invalidationsCompleted += 1
        return value
    }
    func send(_ entry: BackendSyncEntry) async -> BackendOutcome<BackendSyncResponse> {
        switch entry { case .confirmation: confirmationSend += 1; case .invalidation: ackSend += 1 }
        return await base.send(entry)
    }
    func lookup(_ entry: BackendSyncEntry) async -> BackendOutcome<BackendSyncResponse> { operationLookup += 1; return await base.lookup(entry) }
    func distribute(_ request: PublicationDistributionRequest) async -> BackendOutcome<PublicationDistribution> { distributeCount += 1; return .failed(.rejected) }
    func lookupDistribution(_ request: PublicationDistributionRequest) async -> BackendOutcome<PublicationDistribution> { lookupDistributionCount += 1; return .failed(.rejected) }
}

@MainActor private struct StatusHTTPConfiguration {
    let connection: RegistrationConnection
    let receipt: RegistrationServerReceipt
    let rendition: RenditionIdentity
    let bearer: String
    let registrationSecret: String
    let runIdentity: String
    init() throws {
        let env = ProcessInfo.processInfo.environment
        guard let origin = env["FR_S27_ORIGIN"], let bearer = env["FR_S27_BEARER"],
              let secret = env["FR_S27_REGISTRATION_SECRET"], let json = env["FR_S27_FIXTURE_JSON"], json.utf8.count <= 16_384 else {
            throw BackendContractError.invalidValue
        }
        let object = try PublicationWire.parse(Data(json.utf8)).object(keys: ["schema_version", "run_identity", "fixture_only",
            "wire_sha256", "source_sha256", "media_type", "registration_receipt", "original", "v1", "v2", "provenance"])
        guard object["schema_version"] == .string("fr-publication-fixture-v1"), object["fixture_only"] == .boolean(true),
              object["wire_sha256"] == .string("455868ebe8d057ad32471a169396333c03cd1bcf2b4a4986f3147935f2617e0a"),
              object["media_type"] == .string("video/quicktime"), object["v2"] == .null else { throw BackendContractError.unsupportedVersion }
        let fields = try object["registration_receipt"]!.object(keys: ["destination_id", "operation_id", "registration_id", "generation", "created_at"])
        let intent = RegistrationIntent(operation: .init(rawValue: try fields["operation_id"]!.opaque()),
            destination: .init(rawValue: try fields["destination_id"]!.opaque()))
        receipt = try RegistrationWire.receipt(PublicationWire.body(object["registration_receipt"]!), intent: intent)
        #if DEBUG && targetEnvironment(simulator)
        connection = try .init(endpoint: .isolatedLoopbackProbe(origin), destination: intent.destination)
        #else
        throw BackendContractError.unavailable
        #endif
        rendition = try PublicationWire.decodeRendition(object["v1"]!)
        guard try PublicationWire.original(rendition.original) == object["original"] else { throw BackendContractError.identityMismatch }
        runIdentity = try object["run_identity"]!.opaque()
        self.bearer = bearer; registrationSecret = secret
    }
}
