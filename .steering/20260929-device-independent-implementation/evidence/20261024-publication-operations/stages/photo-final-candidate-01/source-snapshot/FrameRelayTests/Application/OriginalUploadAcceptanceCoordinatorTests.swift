import Foundation
import Synchronization
import Testing
@testable import FrameRelay

/// UUID-only, newly created roots. Raw synthetic bytes and saved classification
/// inputs test acceptance; they are not camera, Log, strict-route or sender proof.
struct OriginalUploadAcceptanceCoordinatorTests {
    @Test(arguments: [NetworkCondition.unknown, .cellular, .offline])
    func initialNonWiFiHasNoCommandOrFileObservation(condition: NetworkCondition) async throws {
        let f = try await UploadAppFixture.make(), request = try await f.request()
        let before = try await mediaSnapshot(f.store), files = UploadAppFiles(base: f.files)
        let store = UploadAppFaultStore(base: f.store)
        let owner = OriginalUploadAcceptanceCoordinator(store: store, files: files, network: UploadAppNetwork(condition))
        #expect(await owner.accept(request) == .rejected(.notOnWiFi))
        let mutations = await store.mutations(), observations = await files.count()
        #expect(mutations.isEmpty && observations == 0)
        #expect(try await mediaSnapshot(f.store) == before)
        try await f.assertUnchanged()
    }

    @Test func fixedMixedTargetsRecordMissingPeerWithoutShrinkingOrOpeningAReadLease() async throws {
        let f = try await UploadAppFixture.make(names: ["present", "missing"]), request = try await f.request()
        let files = UploadAppFiles(base: f.files, overrides: [f.bindings[1].reference: .absent])
        let owner = OriginalUploadAcceptanceCoordinator(store: f.store, files: files, network: UploadAppNetwork(.wiFi))
        let record = try uploadAppRecorded(await owner.accept(request))
        #expect(record.plan.request == request && record.children.count == 2)
        #expect(record.plan.presences == [.present(byteCount: 4096), .missing])
        #expect(record.children.map(\.decision) == [.accepted, .notProcessed(.fileMissing)])
        let snapshot = try await mediaSnapshot(f.store)
        #expect(snapshot.requests.count == 1 && snapshot.batches.isEmpty)
        #expect(snapshot.requests[0].transport == .queued && snapshot.requests[0].intent == .running)
        #expect(snapshot.requests[0].startCommitted && !snapshot.requests[0].canRun)
        #expect(snapshot.requests[0].session == nil && snapshot.requests[0].attempt == nil)
        #expect(snapshot.backgroundTasks.isEmpty && snapshot.temporaryMedia.isEmpty && snapshot.verifications.isEmpty)
        #expect(await files.count() == 2)
        try await f.assertUnchanged()
    }

    @Test(arguments: ["before", "after"])
    func unknownKeepsExactEnvelopeAndReopenedOwnerLooksUpImmutableAcceptanceAfterPause(point: String) async throws {
        let f = try await UploadAppFixture.make(), request = try await f.request()
        let fault = UploadAppFaultStore(base: f.store, loss: point), files = UploadAppFiles(base: f.files)
        let network = UploadAppNetwork(.wiFi)
        let owner = OriginalUploadAcceptanceCoordinator(store: fault, files: files, network: network)
        #expect(await owner.accept(request) == .unknown)
        network.set(.offline)
        let original = try #require(await fault.mutations().first)
        #expect(await owner.accept(request) == .unknown)
        #expect(await fault.mutations().count == 1)
        let changed = try OriginalUploadAcceptanceRequest(parent: request.parent, storeIdentity: request.storeIdentity,
            registration: request.registration, scope: request.scope,
            targets: [.init(operation: .init(rawValue: UUID().uuidString), binding: request.targets[0].binding)])
        #expect(await owner.lookupAcceptance(changed) == .rejected(.identityMismatch))
        if point == "before" { try await fault.materializeOriginal() }
        let initial = try #require(try await mediaSnapshot(f.store).requests.first)
        _ = try await mediaCommit(f.store, .requestTransition(command: .init(rawValue: UUID().uuidString),
            operation: initial.operation, target: initial.target, registration: initial.registration, value: .pause))
        let reopened = try SQLiteRecordingStore(run: f.run, mode: .openExisting)
        let fresh = OriginalUploadAcceptanceCoordinator(store: reopened, files: files, network: UploadAppNetwork(.offline))
        let recovered = try uploadAppRecorded(await fresh.lookupAcceptance(request))
        #expect(OriginalUploadAcceptanceValueValidation.exact(recovered.mutation, original))
        #expect(recovered.children[0].initialRequest?.intent == .running)
        #expect(try await mediaSnapshot(reopened).requests[0].intent == .paused)
        await fault.reveal()
        #expect(await owner.lookupAcceptance(request) == .recorded(recovered))
        let mutations = await fault.mutations(), observations = await files.count()
        #expect(mutations.count == 1 && observations == 1)
        #expect(await fault.lookups().allSatisfy { OriginalUploadAcceptanceValueValidation.exact($0, original) })
        try await f.assertUnchanged()
    }

    @Test(arguments: ["missing", "inaccessible", "unknown", "size"])
    func everyFileObservationKeepsTheFixedChildAsAnIndependentNotProcessedResult(observation: String) async throws {
        let f = try await UploadAppFixture.make(), request = try await f.request()
        let file: OriginalFileObservation
        let reason: OriginalUploadAcceptanceNonProcessing
        switch observation {
        case "missing": file = .absent; reason = .fileMissing
        case "inaccessible": file = .unavailable(.resourceUnavailable); reason = .fileInaccessible
        case "unknown": file = .unavailable(.notMeasured); reason = .fileUnknown
        default: file = .present(byteCount: 4095); reason = .byteCountMismatch
        }
        let files = UploadAppFiles(base: f.files, overrides: [f.bindings[0].reference: file])
        let owner = OriginalUploadAcceptanceCoordinator(store: f.store, files: files, network: UploadAppNetwork(.wiFi))
        let record = try uploadAppRecorded(await owner.accept(request))
        #expect(record.children.count == 1 && record.children[0].target == request.targets[0])
        #expect(record.children[0].decision == .notProcessed(reason) && record.children[0].initialRequest == nil)
        #expect(try await mediaSnapshot(f.store).requests.isEmpty)
        try await f.assertUnchanged()
    }

    @Test func actorReentryDoesNotStatOrCommitTheSameRequestTwice() async throws {
        let f = try await UploadAppFixture.make(), request = try await f.request()
        let gate = UploadAppCheckpoint(), fault = UploadAppFaultStore(base: f.store)
        let files = UploadAppFiles(base: f.files, afterObservation: { _ in await gate.hold() })
        let owner = OriginalUploadAcceptanceCoordinator(store: fault, files: files, network: UploadAppNetwork(.wiFi))
        let first = Task { await owner.accept(request) }
        await gate.waitUntilHeld()
        #expect(await owner.accept(request) == .unknown)
        let changed = try OriginalUploadAcceptanceRequest(parent: request.parent, storeIdentity: request.storeIdentity,
            registration: request.registration, scope: .single,
            targets: [.init(operation: .init(rawValue: UUID().uuidString), binding: request.targets[0].binding)])
        #expect(await owner.accept(changed) == .rejected(.identityMismatch))
        await gate.resume()
        let record = try uploadAppRecorded(await first.value)
        let mutations = await fault.mutations(), observations = await files.count()
        #expect(mutations.count == 1 && observations == 1 && record.plan.request == request)
        try await f.assertUnchanged()
    }

    @Test func definiteConflictsExhaustAsRejectionAndDoNotLeaveAnUnknownReservation() async throws {
        let f = try await UploadAppFixture.make(), request = try await f.request()
        let fault = UploadAppFaultStore(base: f.store, conflicts: 3)
        let owner = OriginalUploadAcceptanceCoordinator(store: fault, files: f.files, network: UploadAppNetwork(.wiFi))
        #expect(await owner.accept(request) == .rejected(.revisionConflict))
        let mutations = await fault.mutations(), lookups = await fault.lookups()
        #expect(mutations.count == 3 && lookups.isEmpty)
        #expect(try await mediaSnapshot(f.store).originalUploadAcceptances.isEmpty)
        let record = try uploadAppRecorded(await owner.accept(request))
        #expect(record.plan.request == request && record.children[0].decision == .accepted)
        try await f.assertUnchanged()
    }

    @Test(arguments: ["identity", "registration", "binding", "network", "revision"])
    func statBoundaryRechecksIdentityRegistrationBindingPathAndRevision(race: String) async throws {
        let f = try await UploadAppFixture.make(), request = try await f.request()
        let fault = UploadAppFaultStore(base: f.store), network = UploadAppNetwork(.wiFi)
        let files = UploadAppFiles(base: f.files, afterObservation: { count in
            guard count == 1 else { return }
            switch race {
            case "identity": await fault.changeObservedIdentity()
            case "binding": await fault.changeObservedBinding(f.bindings[0])
            case "network": network.set(.cellular)
            case "registration":
                _ = try? await mediaRegister(f.store, registration: .init(destination: request.registration.server.registration.destination,
                    id: .init(rawValue: UUID().uuidString), generation: .init(rawValue: 2)))
            default:
                _ = try? await mediaCommit(f.store, .publication(mediaPublication(statusRendition(f.bindings[0].original),
                    registration: request.registration.server.registration)))
            }
        })
        let owner = OriginalUploadAcceptanceCoordinator(store: fault, files: files, network: network)
        let result = await owner.accept(request)
        if race == "revision" {
            let record = try uploadAppRecorded(result)
            #expect(record.plan.request == request && record.children[0].decision == .accepted)
            let observations = await files.count(), mutations = await fault.mutations()
            #expect(observations == 2 && mutations.count == 1)
        } else {
            #expect(result == .rejected(race == "network" ? .notOnWiFi : .identityMismatch))
            #expect(await fault.mutations().isEmpty)
            #expect(try await mediaSnapshot(f.store).originalUploadAcceptances.isEmpty)
        }
        try await f.assertUnchanged()
    }

    @Test func nativeObservationAdapterSharesObservationWithoutGrantingAnSDKPermit() {
        let photo = UploadAppPhotoNetwork(.unknown), adapter = NativeUploadStartNetwork(observation: photo)
        #expect(adapter.currentCondition() == .unknown)
        photo.set(.wiFi); #expect(adapter.currentCondition() == .wiFi)
        photo.set(.cellular); #expect(adapter.currentCondition() == .cellular)
    }

    @Test(arguments: ["identity", "record", "lookup"])
    func callbackBoundaryRetainsOriginalEnvelopeUntilTheSameWriterObservationRecovers(faultKind: String) async throws {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("FrameRelay-original-upload-callback-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        let library = ProductLibraryFactory(supportDirectory: parent), services = try await library.open()
        _ = try await services.store.establishRegistrationIdentity(expectedRevision: 0, expectedIdentity: nil)
        _ = try await mediaRegister(services.store)
        let bindings = try await uploadAppSeed(store: services.store, files: services.originals, names: ["callback"])
        let f = UploadAppFixture(run: services.run, store: services.store, files: services.originals, bindings: bindings)
        let request = try await f.request(), fault = UploadAppFaultStore(base: f.store), files = UploadAppFiles(base: f.files)
        let gate = UploadAppCheckpoint(), probe = UploadAppCallbackProbe()
        let background = ProductBackgroundMediaFactory(library: library,
            sessionFactory: { _ in await probe.sdkCreated(); throw BackendContractError.unavailable },
            sourceFactory: { _ in await probe.sourceCreated(); throw BackendContractError.unavailable })
        let owner = OriginalUploadAcceptanceCoordinator(store: fault, files: files, network: UploadAppNetwork(.wiFi),
            didRecord: {
                await probe.callbackStarted()
                await background.synchronizeCapture()
                await fault.changeAcceptanceObservation(faultKind)
                await gate.hold()
            })
        let first = Task { await owner.accept(request) }
        await gate.waitUntilHeld()
        // These faults affect this probe's observations only. The physical
        // writer UUID, committed record and source bytes are never rewritten.
        let actual = try await mediaSnapshot(f.store), record = try #require(actual.originalUploadAcceptances.first)
        let original = try #require(await fault.mutations().first)
        #expect(actual.storeIdentity == request.storeIdentity && record.isCommitted)
        #expect(OriginalUploadAcceptanceValueValidation.exact(record.mutation, original))
        #expect(await owner.accept(request) == .unknown)
        #expect(await owner.lookupAcceptance(request) == .unknown)
        await gate.resume()
        #expect(await first.value == .unknown)
        // A retained envelope takes the lookup-only branch even while the
        // observed UUID or record is unavailable, without restat/reproposal.
        #expect(await owner.lookupAcceptance(request) == .unknown)
        #expect(try await mediaSnapshot(f.store) == actual)
        await fault.restoreAcceptanceObservation()
        #expect(await owner.lookupAcceptance(request) == .recorded(record))
        #expect(try await mediaSnapshot(f.store) == actual)
        let mutations = await fault.mutations(), observations = await files.count(), lookups = await fault.lookups()
        #expect(mutations.count == 1 && observations == 1)
        #expect(lookups.allSatisfy { OriginalUploadAcceptanceValueValidation.exact($0, original) })
        #expect(await probe.counts() == [1, 0, 0])
        try await f.assertUnchanged()
    }
}

nonisolated struct UploadAppFixture: Sendable {
    let run: ExplorationRunDirectory
    let store: SQLiteRecordingStore
    let files: ManagedOriginalStore
    let bindings: [OriginalBinding]

    static func make(names: [String] = ["saved"]) async throws -> Self {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("FrameRelay-original-upload-app-" + UUID().uuidString, isDirectory: true)
        let run = try ExplorationRunDirectory.createNew(at: root)
        let store = try SQLiteRecordingStore(run: run, mode: .createNew)
        let files = ManagedOriginalStore(run: run)
        _ = try await store.establishRegistrationIdentity(expectedRevision: 0, expectedIdentity: nil)
        _ = try await mediaRegister(store)
        return .init(run: run, store: store, files: files,
            bindings: try await uploadAppSeed(store: store, files: files, names: names))
    }
    func request(parent: String = UUID().uuidString) async throws -> OriginalUploadAcceptanceRequest {
        let snapshot = try await mediaSnapshot(store)
        let identity = try #require(snapshot.storeIdentity), registration = try #require(snapshot.registrations.last)
        return try .init(parent: .init(rawValue: parent), storeIdentity: identity,
            registration: registration, scope: bindings.count == 1 ? .single : .multiple,
            targets: bindings.map { .init(operation: .init(rawValue: UUID().uuidString), binding: $0) })
    }
    func assertUnchanged() async throws {
        for binding in bindings {
            let digest = try await files.digest(for: binding.reference)
            #expect(digest.byteCount == binding.original.content.byteCount && digest.sha256 == binding.original.content.digest)
        }
        let state = try await mediaOriginalSnapshot(store)
        #expect(state.logicalOriginals.allSatisfy { $0.readers.isEmpty && $0.mediaReaders.isEmpty })
        #expect(try await mediaSnapshot(store).backgroundTasks.isEmpty)
    }
}

nonisolated func uploadAppSeed(store: SQLiteRecordingStore, files: ManagedOriginalStore,
    names: [String]) async throws -> [OriginalBinding] {
    var bindings: [OriginalBinding] = []
    for (index, name) in names.enumerated() {
        let input = try CaptureFixture(clip: "upload-app-" + name)
        guard case .committed = await store.execute(.commitIntent(input.token(1), expectedRevision: 0, input.intent)) else {
            throw BackendContractError.notCommitted
        }
        let url = try await files.reserve(original: input.intent.original)
        // Newly created disposable fixture bytes, explicitly not a movie proof.
        try Data(repeating: UInt8((index % 255) + 1), count: 4096).write(to: url, options: .withoutOverwriting)
        let record = try syntheticResult(input)
        guard case .committed(let saved) = await store.execute(.commitResult(input.token(4), expectedRevision: 1, record)) else {
            throw BackendContractError.notCommitted
        }
        let digest = try await files.digest(for: input.intent.original)
        let binding = OriginalBinding(original: .init(capture: input.context.capture, generation: .init(rawValue: 1),
            content: try .init(byteCount: digest.byteCount, algorithm: "sha256", digest: digest.sha256)),
            reference: input.intent.original, saveRecord: record, saveCommit: saved)
        _ = try await mediaOriginalCommit(store, .bind(binding)); bindings.append(binding)
    }
    return bindings
}

nonisolated func uploadAppRecorded(_ result: OriginalUploadAcceptanceResult) throws -> StoredOriginalUploadAcceptance {
    guard case .recorded(let record) = result else { throw BackendContractError.notCommitted }
    return record
}

nonisolated final class UploadAppNetwork: OriginalUploadStartNetworkPort, Sendable {
    private let value: Mutex<NetworkCondition>
    init(_ value: NetworkCondition) { self.value = Mutex(value) }
    func currentCondition() -> NetworkCondition { value.withLock { $0 } }
    func set(_ next: NetworkCondition) { value.withLock { $0 = next } }
}
nonisolated final class UploadAppPhotoNetwork: PhotoSaveStartNetworkPort, Sendable {
    private let value: Mutex<NetworkCondition>
    init(_ value: NetworkCondition) { self.value = Mutex(value) }
    func currentCondition() -> NetworkCondition { value.withLock { $0 } }
    func set(_ next: NetworkCondition) { value.withLock { $0 = next } }
}

actor UploadAppFiles: RecordingOriginalFilePort {
    private let base: any RecordingOriginalFilePort
    private let overrides: [CaptureOriginalReference: OriginalFileObservation]
    private let afterObservation: @Sendable (Int) async -> Void
    private var observed = 0
    init(base: any RecordingOriginalFilePort, overrides: [CaptureOriginalReference: OriginalFileObservation] = [:],
        afterObservation: @escaping @Sendable (Int) async -> Void = { _ in }) {
        self.base = base; self.overrides = overrides; self.afterObservation = afterObservation
    }
    func reserveForRecording(_ original: CaptureOriginalReference) async throws { throw BackendContractError.wrongStage }
    func observeFile(_ original: CaptureOriginalReference) async -> OriginalFileObservation {
        observed += 1
        let value: OriginalFileObservation
        if let override = overrides[original] { value = override }
        else { value = await base.observeFile(original) }
        await afterObservation(observed)
        return value
    }
    func count() -> Int { observed }
}

actor UploadAppFaultStore: RecordingStorePort, OriginalStorePort, MediaOperationStorePort {
    private let base: SQLiteRecordingStore
    private let loss: String?
    private var hidden = true
    private var conflicts: Int
    private var identityFault: RegistrationStoreIdentity?
    private var bindingFault: OriginalBinding?
    private var hideAcceptanceRecord = false
    private var unknownAcceptanceLookup = false
    private var seen: [BackendStoreMutation] = []
    private var queried: [BackendStoreMutation] = []
    init(base: SQLiteRecordingStore, loss: String? = nil, conflicts: Int = 0) {
        self.base = base; self.loss = loss; self.conflicts = conflicts
    }
    func load() async -> BackendStoreLoadResult {
        let result = await base.load()
        guard case .loaded(var value) = result else { return result }
        if let identityFault { value.storeIdentity = identityFault }
        if hideAcceptanceRecord { value.originalUploadAcceptances = [] }
        return .loaded(value)
    }
    func commit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        guard case .originalUploadAcceptance = mutation.change else { return await base.commit(mutation) }
        seen.append(mutation)
        if conflicts > 0 { conflicts -= 1; return .rejected(.revisionConflict) }
        if hidden, loss == "before" { return .unknown }
        let result = await base.commit(mutation)
        return hidden && loss == "after" ? .unknown : result
    }
    func lookupCommit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        queried.append(mutation)
        if unknownAcceptanceLookup || (hidden && loss != nil) { return .unknown }
        return await base.lookupCommit(mutation)
    }
    func execute(_ command: RecordingStoreCommand) async -> RecordingStoreResult { await base.execute(command) }
    func loadUnfinished() async -> UnfinishedRecordingLoadResult { await base.loadUnfinished() }
    func loadRecordings() async -> RecordingStoreLoadResult { await base.loadRecordings() }
    func loadOriginalState() async -> BackendOutcome<OriginalStoreSnapshot> {
        let result = await base.loadOriginalState()
        guard let bindingFault, case .succeeded(let value) = result else { return result }
        let originals = value.originals.map { row in
            row.binding.original.capture == bindingFault.original.capture
                ? OriginalPersistentState(binding: bindingFault, bindingCommit: row.bindingCommit) : row
        }
        return .succeeded(.init(revision: value.revision, originals: originals, logicalOriginals: value.logicalOriginals,
            reconciliationEpoch: value.reconciliationEpoch, removalBatches: value.removalBatches))
    }
    func commitOriginal(_ mutation: OriginalStoreMutation) async -> OriginalStoreCommitResult { await base.commitOriginal(mutation) }
    func reveal() { hidden = false }
    func changeObservedIdentity() { identityFault = .init(rawValue: UUID()) }
    func changeObservedBinding(_ binding: OriginalBinding) {
        bindingFault = .init(original: binding.original, reference: .init(rawValue: binding.reference.rawValue + "-changed"),
            saveRecord: binding.saveRecord, saveCommit: binding.saveCommit)
    }
    func changeAcceptanceObservation(_ kind: String) {
        switch kind {
        case "identity": identityFault = .init(rawValue: UUID())
        case "record": hideAcceptanceRecord = true
        default: unknownAcceptanceLookup = true
        }
    }
    func restoreAcceptanceObservation() {
        identityFault = nil; hideAcceptanceRecord = false; unknownAcceptanceLookup = false
    }
    func materializeOriginal() async throws {
        guard let mutation = seen.first, case .committed = await base.commit(mutation) else { throw BackendContractError.notCommitted }
    }
    func mutations() -> [BackendStoreMutation] { seen }
    func lookups() -> [BackendStoreMutation] { queried }
}

private actor UploadAppCallbackProbe {
    private var values = [0, 0, 0]
    func callbackStarted() { values[0] += 1 }
    func sdkCreated() { values[1] += 1 }
    func sourceCreated() { values[2] += 1 }
    func counts() -> [Int] { values }
}

private actor UploadAppCheckpoint {
    private var isHeld = false
    private var isResumed = false
    private var blocked: CheckedContinuation<Void, Never>?
    private var arrived: CheckedContinuation<Void, Never>?
    func hold() async {
        isHeld = true; arrived?.resume(); arrived = nil
        if isResumed { return }
        await withCheckedContinuation { blocked = $0 }
    }
    func waitUntilHeld() async {
        if isHeld { return }
        await withCheckedContinuation { arrived = $0 }
    }
    func resume() { isResumed = true; blocked?.resume(); blocked = nil }
}
