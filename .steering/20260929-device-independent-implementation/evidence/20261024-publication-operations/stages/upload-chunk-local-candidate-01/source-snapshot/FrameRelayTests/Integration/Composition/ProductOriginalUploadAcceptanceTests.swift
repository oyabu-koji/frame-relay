import Foundation
import Testing
@testable import FrameRelay

@Suite(.serialized) @MainActor struct ProductOriginalUploadAcceptanceTests {
    @Test func normalSingleAndMultipleEntrancesShareWriterAndOnlyQueueFixedChildren() async throws {
        let parent = try uploadAppProductParent(), factory = ProductLibraryFactory(supportDirectory: parent)
        let services = try await factory.open()
        _ = try await services.store.establishRegistrationIdentity(expectedRevision: 0, expectedIdentity: nil)
        _ = try await mediaRegister(services.store)
        let bindings = try await uploadAppSeed(store: services.store, files: services.originals, names: ["single", "peer"])
        let probe = UploadAppProductProbe()
        let background = uploadAppBackground(factory, probe: probe)
        let composition = ProductComposition(factory: factory, backgroundFactory: background,
            registrationFactory: { store in
                RegistrationCoordinator(store: store, vault: UploadAppProductVault(probe: probe), remote: UploadAppProductRemote(probe: probe))
            }, uploadStartNetwork: UploadAppNetwork(.wiFi))
        #expect(await probe.counts() == [0, 0, 0, 0])
        await composition.open()
        let model = try #require(composition.library)
        #expect(composition.originalUploadAcceptance != nil && composition.transferCommands != nil && model.hasTransferPort)
        let before = await probe.counts()
        #expect(before[0] == 0 && before[1] == 0 && before[3] == 0)
        await model.submit(.transfer, captures: [bindings[0].original.capture])
        let one = try await mediaSnapshot(services.store)
        #expect(one.originalUploadAcceptances.count == 1 && one.originalUploadAcceptances[0].plan.request.scope == .single)
        #expect(one.originalUploadAcceptances[0].children[0].decision == .accepted && one.requests.count == 1)
        await model.submit(.transfer, captures: Set(bindings.map { $0.original.capture }))
        let multiple = try await mediaSnapshot(services.store), record = try #require(multiple.originalUploadAcceptances.last)
        #expect(record.plan.request.scope == .multiple && record.children.count == 2)
        #expect(record.children.filter { $0.decision == .accepted }.count == 1)
        #expect(record.children.filter { $0.decision == .notProcessed(.alreadyRequested) }.count == 1)
        #expect(multiple.requests.count == 2 && multiple.requests.allSatisfy { $0.transport == .queued && !$0.canRun })
        #expect(multiple.batches.isEmpty && multiple.backgroundTasks.isEmpty && multiple.verifications.isEmpty)
        #expect(multiple.temporaryMedia.isEmpty && multiple.photoRegistrations.isEmpty && multiple.outbox.isEmpty)
        #expect(await probe.counts() == before)
        #expect(model.snapshot?.originalUploadAcceptances == multiple.originalUploadAcceptances)
        #expect(model.snapshot?.items.allSatisfy { $0.operationResults.isEmpty } == true)
        #expect(model.submissions.isEmpty && model.transferMessage?.contains("未処理") == true)
        for binding in bindings { try await uploadAppAssertProductBytes(services, binding: binding) }
        await composition.enteredBackground()
    }

    @Test func captureWaitsAndPersonPauseCoexistWithoutStartingSDKOrClearingOtherConditions() async throws {
        let factory = ProductLibraryFactory(supportDirectory: try uploadAppProductParent())
        let services = try await factory.open()
        _ = try await services.store.establishRegistrationIdentity(expectedRevision: 0, expectedIdentity: nil)
        _ = try await mediaRegister(services.store)
        let binding = try #require(try await uploadAppSeed(store: services.store, files: services.originals, names: ["capture-waits"]).first)
        let probe = UploadAppProductProbe(), background = uploadAppBackground(factory, probe: probe)
        let owner = CaptureMediaOwner(context: try CaptureFixture(clip: UUID().uuidString).context, visit: UUID(), nonce: UUID())
        background.captureAdmission.begin(owner, phases: [.recording])
        let acceptance = ProductOriginalUploadAcceptance.make(services: services, network: UploadAppNetwork(.wiFi), background: background)
        let request = try await uploadAppProductRequest(services, bindings: [binding])
        let record = try uploadAppRecorded(await acceptance.accept(request))
        var current = try #require(try await mediaSnapshot(services.store).requests.first)
        #expect(current.waits.contains(.recording) && current.intent == .running && current.transport == .queued)
        #expect(record.children[0].initialRequest?.waits.isEmpty == true)
        for reason in [MediaWaitReason.authentication, .wiFiUnavailable] {
            _ = try await mediaCommit(services.store, .requestTransition(command: .init(rawValue: UUID().uuidString),
                operation: current.operation, target: current.target, registration: current.registration, value: .wait(reason, active: true)))
        }
        let pause = try MediaPersonControlPlan(parent: .init(rawValue: UUID().uuidString), storeIdentity: request.storeIdentity,
            scope: .single, action: .pause,
            children: [.init(command: .init(rawValue: UUID().uuidString), target: .init(current))])
        guard case .recorded = await background.submitPersonControl(pause) else { throw BackendContractError.notCommitted }
        background.captureAdmission.update(owner, phases: [.saving, .recovery])
        await background.synchronizeCapture()
        current = try #require(try await mediaSnapshot(services.store).requests.first)
        #expect(current.intent == .paused && !current.waits.contains(.recording))
        #expect(current.waits.isSuperset(of: [.saving, .recovery, .authentication, .wiFiUnavailable]))
        background.captureAdmission.end(owner); await background.synchronizeCapture()
        current = try #require(try await mediaSnapshot(services.store).requests.first)
        #expect(current.intent == .paused && current.waits == [.authentication, .wiFiUnavailable])
        #expect(current.transport == .queued && !current.canRun && current.attempt == nil && current.session == nil)
        #expect(await probe.counts() == [0, 0, 0, 0])
        try await uploadAppAssertProductBytes(services, binding: binding)
    }

    @Test func reopenedImmutableLookupDoesNotReplayTransferOrClearUnownedCaptureWaits() async throws {
        let parent = try uploadAppProductParent(), factory = ProductLibraryFactory(supportDirectory: parent)
        let services = try await factory.open()
        _ = try await services.store.establishRegistrationIdentity(expectedRevision: 0, expectedIdentity: nil)
        _ = try await mediaRegister(services.store)
        let bindings = try await uploadAppSeed(store: services.store, files: services.originals, names: ["reopen"])
        let probe = UploadAppProductProbe(), background = uploadAppBackground(factory, probe: probe)
        let request = try await uploadAppProductRequest(services, bindings: bindings)
        let initial = ProductOriginalUploadAcceptance.make(services: services, network: UploadAppNetwork(.wiFi), background: background)
        let record = try uploadAppRecorded(await initial.accept(request))
        let current = try #require(try await mediaSnapshot(services.store).requests.first)
        _ = try await mediaCommit(services.store, .requestTransition(command: .init(rawValue: UUID().uuidString),
            operation: current.operation, target: current.target, registration: current.registration, value: .pause))
        _ = try await mediaCommit(services.store, .requestTransition(command: .init(rawValue: UUID().uuidString),
            operation: current.operation, target: current.target, registration: current.registration, value: .wait(.recording, active: true)))
        let before = try await mediaSnapshot(services.store)
        let newFactory = ProductLibraryFactory(supportDirectory: parent), reopened = try await newFactory.open()
        let freshBackground = uploadAppBackground(newFactory, probe: probe)
        let fresh = ProductOriginalUploadAcceptance.make(services: reopened, network: UploadAppNetwork(.offline), background: freshBackground)
        #expect(try await mediaSnapshot(reopened.store) == before)
        #expect(await fresh.lookupAcceptance(record.plan.request) == .recorded(record))
        #expect(try await mediaSnapshot(reopened.store) == before)
        guard case .loaded(let library) = await reopened.reader.loadLibrary() else { throw BackendContractError.unavailable }
        #expect(library.originalUploadAcceptances == [record] && library.mediaRequests[0].request.intent == .paused)
        #expect(library.mediaRequests[0].request.waits.contains(.recording))
        #expect(library.items[0].uploadCandidateBinding == bindings[0])
        #expect(library.items[0].originalUploadAcceptances == [record] && library.items[0].operationResults.isEmpty)
        #expect(await probe.counts() == [0, 0, 0, 0])
        try await uploadAppAssertProductBytes(reopened, binding: bindings[0])
    }
}

nonisolated private func uploadAppProductParent() throws -> URL {
    let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent("FrameRelay-original-upload-product-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url // Retain only this run's new root until process/container teardown.
}
nonisolated private func uploadAppBackground(_ factory: ProductLibraryFactory,
    probe: UploadAppProductProbe) -> ProductBackgroundMediaFactory {
    ProductBackgroundMediaFactory(library: factory,
        sessionFactory: { _ in await probe.sdk(); throw BackendContractError.unavailable },
        sourceFactory: { _ in await probe.source(); throw BackendContractError.unavailable })
}
nonisolated private func uploadAppProductRequest(_ services: ProductLibraryServices,
    bindings: [OriginalBinding]) async throws -> OriginalUploadAcceptanceRequest {
    let snapshot = try await mediaSnapshot(services.store)
    let identity = try #require(snapshot.storeIdentity), registration = try #require(snapshot.registrations.last)
    return try .init(parent: .init(rawValue: UUID().uuidString), storeIdentity: identity,
        registration: registration, scope: bindings.count == 1 ? .single : .multiple,
        targets: bindings.map { .init(operation: .init(rawValue: UUID().uuidString), binding: $0) })
}
nonisolated private func uploadAppAssertProductBytes(_ services: ProductLibraryServices, binding: OriginalBinding) async throws {
    let digest = try await services.originals.digest(for: binding.reference)
    #expect(digest.sha256 == binding.original.content.digest && digest.byteCount == binding.original.content.byteCount)
    let snapshot = try await mediaOriginalSnapshot(services.store)
    #expect(snapshot.logicalOriginals.allSatisfy { $0.readers.isEmpty && $0.mediaReaders.isEmpty })
    #expect(try await mediaSnapshot(services.store).backgroundTasks.isEmpty)
}

private actor UploadAppProductProbe {
    private var values = [0, 0, 0, 0]
    func sdk() { values[0] += 1 }
    func source() { values[1] += 1 }
    func vault() { values[2] += 1 }
    func remote() { values[3] += 1 }
    func counts() -> [Int] { values }
}
nonisolated private struct UploadAppProductVault: RegistrationVaultPort {
    let probe: UploadAppProductProbe
    func connection(storeIdentity: RegistrationStoreIdentity?) async throws -> RegistrationConnection? {
        await probe.vault(); throw RegistrationAccessError.credentialUnavailable
    }
    func saveConnection(_ connection: RegistrationConnection, bearer: String, storeIdentity: RegistrationStoreIdentity) async throws {
        await probe.vault(); throw RegistrationAccessError.credentialUnavailable
    }
    func prepareIntent(for destination: DestinationIdentity, storeIdentity: RegistrationStoreIdentity) async throws -> RegistrationIntent {
        await probe.vault(); throw RegistrationAccessError.credentialUnavailable
    }
    func requireCredential(for intent: RegistrationIntent, storeIdentity: RegistrationStoreIdentity) async throws {
        await probe.vault(); throw RegistrationAccessError.credentialUnavailable
    }
}
nonisolated private struct UploadAppProductRemote: RegistrationRemotePort {
    let probe: UploadAppProductProbe
    func checkConnection(_ connection: RegistrationConnection, bearer: String) async -> BackendOutcome<BackendCapabilities> {
        await probe.remote(); return .unknown
    }
    func discover(_ connection: RegistrationConnection, storeIdentity: RegistrationStoreIdentity) async -> BackendOutcome<BackendCapabilities> {
        await probe.remote(); return .unknown
    }
    func register(_ command: RegistrationCommand, at connection: RegistrationConnection,
        storeIdentity: RegistrationStoreIdentity) async -> BackendOutcome<RegistrationServerReceipt> {
        await probe.remote(); return .unknown
    }
    func lookup(_ intent: RegistrationIntent, at connection: RegistrationConnection,
        storeIdentity: RegistrationStoreIdentity) async -> BackendOutcome<RegistrationServerReceipt> {
        await probe.remote(); return .unknown
    }
}
