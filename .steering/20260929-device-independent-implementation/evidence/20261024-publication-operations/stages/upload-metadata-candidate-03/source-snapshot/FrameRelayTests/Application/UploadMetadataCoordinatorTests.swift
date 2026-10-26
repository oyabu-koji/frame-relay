import Foundation
import Testing
@testable import FrameRelay

struct UploadMetadataCoordinatorTests {
    @Test func constructionRestoreAndKnownOnlyWithoutSessionNeverCreateAQueryOrHTTP() async throws {
        let f = try await MetadataAppFixture.make(), remote = MetadataTestRemote()
        let owner = UploadMetadataCoordinator(store: f.services.store, remote: remote)
        let before = try await mediaSnapshot(f.services.store)
        #expect(await owner.reconcilePending(f.request) == .unknown)
        #expect(await owner.refreshKnownSession(f.request) == .rejected(.wrongStage))
        #expect(await remote.queries().isEmpty)
        #expect(try await mediaSnapshot(f.services.store) == before)
        try await f.assertBytesAndNoMedia()
    }

    @Test(arguments: [false, true])
    func postOnlyEstablishesSessionAndGetKeepsPauseOrCancelAndIndependentWaits(cancel: Bool) async throws {
        let f = try await MetadataAppFixture.make(), remote = MetadataTestRemote()
        let owner = UploadMetadataCoordinator(store: f.services.store, remote: remote)
        let created = try metadataRecorded(await owner.refresh(f.request))
        let queued = try #require(try await mediaSnapshot(f.services.store).requests.first)
        #expect(queued.session != nil && queued.remote == .unknown && !queued.hasReconciled && !queued.canRun)
        #expect(queued.transport == .queued && queued.attempt == nil && created.observation.query.isCommitted)
        _ = try await mediaCommit(f.services.store, .requestTransition(command: .init(rawValue: UUID().uuidString),
            operation: queued.operation, target: queued.target, registration: queued.registration, value: .wait(.authentication, active: true)))
        _ = try await mediaCommit(f.services.store, .requestTransition(command: .init(rawValue: UUID().uuidString),
            operation: queued.operation, target: queued.target, registration: queued.registration, value: cancel ? .cancel : .pause))
        _ = try metadataRecorded(await owner.refreshKnownSession(f.request))
        let current = try #require(try await mediaSnapshot(f.services.store).requests.first)
        #expect(current.intent == (cancel ? .cancelled : .paused) && current.waits == [.authentication])
        #expect(current.remote == .inProgress && current.transport == .queued && !current.canRun)
        let queries = await remote.queries()
        #expect(queries.count == 2 && queries[0].query.kind == .create)
        #expect(queries[1].query.kind == .lookup(try #require(current.session)))
        #expect(queries.map { $0.query.generation.rawValue } == [1, 2])
        try await f.assertBytesAndNoMedia()
    }

    @Test func requestTasksJoinAndTheRemoteOnlySeesAnActuallyCommittedReservation() async throws {
        let f = try await MetadataAppFixture.make(), gate = MetadataTestCheckpoint()
        let remote = MetadataTestRemote(beforeReply: { query in
            #expect(await f.services.store.lookupCommit(query.mutation) == .committed(query.commit))
            await gate.hold()
        })
        let owner = UploadMetadataCoordinator(store: f.services.store, remote: remote)
        let first = Task { await owner.refresh(f.request) }
        await gate.waitUntilHeld()
        let second = Task { await owner.refresh(f.request) }
        let during = try await mediaSnapshot(f.services.store)
        #expect(during.uploadMetadataQueries.count == 1 && during.uploadMetadataObservations.isEmpty)
        #expect(during.requests[0].uploadMetadataPending?.rawValue == 1 && !during.requests[0].canRun)
        await gate.resume()
        let one = await first.value, two = await second.value
        let calls = await remote.queries()
        #expect(one == two && calls.count == 1)
        #expect(try await mediaSnapshot(f.services.store).uploadMetadataObservations.count == 1)
    }

    @Test(arguments: ["begin", "observe"], ["before", "after"])
    func unknownLocalMutationIsLookedUpExactlyWithoutNewHTTP(stage: String, point: String) async throws {
        let f = try await MetadataAppFixture.make(), remote = MetadataTestRemote()
        let fault = MetadataTestStore(base: f.services.store, stage: stage, loss: point)
        let owner = UploadMetadataCoordinator(store: fault, remote: remote)
        #expect(await owner.refresh(f.request) == .unknown)
        let original = try #require(await fault.mutations().last)
        let httpBefore = await remote.queries().count
        #expect(await owner.refresh(f.request) == .unknown)
        #expect(await remote.queries().count == httpBefore)
        if point == "before" { try await fault.materializeLast() }
        await fault.reveal()
        let result = await owner.reconcilePending(f.request)
        if stage == "begin" {
            #expect(result == .unknown && httpBefore == 0)
            #expect(try await mediaSnapshot(f.services.store).uploadMetadataObservations.isEmpty)
        } else {
            let record = try metadataRecorded(result)
            #expect(UploadMetadataValidation.exact(record.mutation, original) && httpBefore == 1)
        }
        #expect(await fault.mutations().allSatisfy { UploadMetadataValidation.exact($0, original) || stage == "observe" && Self.isBegin($0) })
        #expect(await remote.queries().count == httpBefore)
        let freshRemote = MetadataTestRemote(), fresh = UploadMetadataCoordinator(store: f.services.store, remote: freshRemote)
        _ = await fresh.reconcilePending(f.request)
        #expect(await freshRemote.queries().isEmpty)
        try await f.assertBytesAndNoMedia()
    }

    @Test(arguments: ["begin", "observe"])
    func boundedDefiniteConflictsRejectAndKnownResponseRetryDoesNotRepeatHTTP(stage: String) async throws {
        let f = try await MetadataAppFixture.make(), remote = MetadataTestRemote()
        let fault = MetadataTestStore(base: f.services.store, stage: stage, conflicts: 3)
        let owner = UploadMetadataCoordinator(store: fault, remote: remote)
        #expect(await owner.refresh(f.request) == .rejected(.revisionConflict))
        let before = await remote.queries().count
        #expect(before == (stage == "begin" ? 0 : 1))
        _ = try metadataRecorded(await owner.refresh(f.request))
        #expect(await remote.queries().count == 1)
        #expect(try await mediaSnapshot(f.services.store).uploadMetadataQueries.count == 1)
        try await f.assertBytesAndNoMedia()
    }

    @Test(arguments: ["identity", "record", "lookup"])
    func callbackMustRevalidateAndUnknownKeepsItsOriginalObservationAndOneCallback(faultKind: String) async throws {
        let f = try await MetadataAppFixture.make(), remote = MetadataTestRemote(), probe = MetadataCallbackProbe()
        let fault = MetadataTestStore(base: f.services.store)
        let owner = UploadMetadataCoordinator(store: fault, remote: remote, didChange: {
            await probe.called(); await fault.changeObservation(faultKind)
        })
        #expect(await owner.refresh(f.request) == .unknown)
        let before = try await mediaSnapshot(f.services.store), record = try #require(before.uploadMetadataObservations.first)
        #expect(await owner.reconcilePending(f.request) == .unknown)
        await fault.restoreObservation()
        #expect(await owner.reconcilePending(f.request) == .recorded(record))
        #expect(await probe.count() == 1)
        #expect(await remote.queries().count == 1)
        #expect(try await mediaSnapshot(f.services.store) == before)
        try await f.assertBytesAndNoMedia()
    }

    @Test func newerReservedGenerationRefusesOlderReplyAndReopenNeverReissuesItsHTTP() async throws {
        let f = try await MetadataAppFixture.make()
        let remote = MetadataTestRemote(beforeReply: { _ in _ = try? await metadataBegin(f) })
        let owner = UploadMetadataCoordinator(store: f.services.store, remote: remote)
        #expect(await owner.refresh(f.request) == .rejected(.staleGeneration))
        let after = try await mediaSnapshot(f.services.store)
        #expect(after.uploadMetadataQueries.map { $0.query.generation.rawValue } == [1, 2])
        #expect(after.uploadMetadataObservations.isEmpty && after.requests[0].session == nil && !after.requests[0].canRun)
        let reopened = try SQLiteRecordingStore(run: f.services.run, mode: .openExisting)
        let freshRemote = MetadataTestRemote(), fresh = UploadMetadataCoordinator(store: reopened, remote: freshRemote)
        #expect(await fresh.reconcilePending(f.request) == .unknown)
        #expect(await freshRemote.queries().isEmpty)
    }

    @Test func historicalObservationLookupSurvivesReregistrationWithoutRebasingOrHTTP() async throws {
        let f = try await MetadataAppFixture.make(), remote = MetadataTestRemote()
        let owner = UploadMetadataCoordinator(store: f.services.store, remote: remote)
        let record = try metadataRecorded(await owner.refresh(f.request))
        _ = try await mediaRegister(f.services.store, registration: .init(destination: f.request.registration.server.registration.destination,
            id: .init(rawValue: UUID().uuidString.lowercased()), generation: .init(rawValue: 2)))
        let freshRemote = MetadataTestRemote(), fresh = UploadMetadataCoordinator(store: f.services.store, remote: freshRemote)
        #expect(await fresh.reconcilePending(f.request) == .recorded(record))
        #expect(await fresh.refresh(f.request) == .rejected(.identityMismatch))
        #expect(await freshRemote.queries().isEmpty)
    }

    @Test func reopenedLatestReservationNeverResolvesToAnOlderObservedQuery() async throws {
        let f = try await MetadataAppFixture.make(), firstRemote = MetadataTestRemote()
        let observed = try metadataRecorded(await UploadMetadataCoordinator(store: f.services.store, remote: firstRemote).refresh(f.request))
        let session = try #require(try await mediaSnapshot(f.services.store).requests.first?.session)
        let newest = try await metadataBegin(f, kind: .lookup(session))
        #expect(newest.query.generation.rawValue > observed.observation.query.query.generation.rawValue)
        let before = try await mediaSnapshot(f.services.store)
        let reopened = try SQLiteRecordingStore(run: f.services.run, mode: .openExisting)
        let remote = MetadataTestRemote(), fresh = UploadMetadataCoordinator(store: reopened, remote: remote)
        #expect(await fresh.reconcilePending(f.request) == .unknown)
        #expect(await fresh.reconcilePending(f.request) == .unknown)
        #expect(await remote.queries().isEmpty)
        #expect(try await mediaSnapshot(reopened) == before)
        #expect(await reopened.lookupCommit(newest.mutation) == .committed(newest.commit))
        try await f.assertBytesAndNoMedia()
    }
    nonisolated private static func isBegin(_ mutation: BackendStoreMutation) -> Bool {
        if case .uploadMetadata(.beginQuery) = mutation.change { return true }; return false
    }
}

nonisolated struct MetadataAppFixture: Sendable {
    let library: ProductLibraryFactory
    let services: ProductLibraryServices
    let binding: OriginalBinding
    let request: UploadMetadataRequest
    static func make(registration: RegistrationIdentity? = nil, capture: String? = nil) async throws -> Self {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("FrameRelay-upload-metadata-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let library = ProductLibraryFactory(supportDirectory: root), services = try await library.open()
        _ = try await services.store.establishRegistrationIdentity(expectedRevision: 0, expectedIdentity: nil)
        let identity = registration ?? .init(destination: .init(rawValue: UUID().uuidString.lowercased()),
            id: .init(rawValue: UUID().uuidString.lowercased()), generation: .init(rawValue: 1))
        _ = try await mediaRegister(services.store, registration: identity)
        let binding = try await metadataSeedBinding(services, capture: capture ?? "metadata-caf\u{00e9}-" + UUID().uuidString)
        let before = try await mediaSnapshot(services.store)
        let registration = try #require(before.registrations.last), storeIdentity = try #require(before.storeIdentity)
        let acceptance = try OriginalUploadAcceptanceRequest(parent: .init(rawValue: UUID().uuidString.lowercased()),
            storeIdentity: storeIdentity, registration: registration, scope: .single,
            targets: [.init(operation: .init(rawValue: UUID().uuidString.lowercased()), binding: binding)])
        let accepted = try uploadAppRecorded(await OriginalUploadAcceptanceCoordinator(store: services.store,
            files: services.originals, network: UploadAppNetwork(.wiFi)).accept(acceptance))
        let originalRequest = try #require(accepted.children[0].initialRequest)
        return .init(library: library, services: services, binding: binding,
            request: try .init(storeIdentity: storeIdentity, registration: registration, operation: originalRequest.operation,
                original: binding.original, expectedStartRevision: originalRequest.expectedStartRevision))
    }
    func assertBytesAndNoMedia() async throws {
        let digest = try await services.originals.digest(for: binding.reference)
        #expect(digest.sha256 == binding.original.content.digest && digest.byteCount == binding.original.content.byteCount)
        let backend = try await mediaSnapshot(services.store), originals = try await mediaOriginalSnapshot(services.store)
        #expect(backend.backgroundTasks.isEmpty && backend.temporaryMedia.isEmpty && backend.photoRegistrations.isEmpty && backend.batches.isEmpty)
        #expect(backend.requests.allSatisfy { $0.attempt == nil && $0.transport == .queued })
        #expect(originals.logicalOriginals.allSatisfy { $0.readers.isEmpty && $0.mediaReaders.isEmpty })
    }
}

/// Capture text never selects a filesystem path. Every raw-byte fixture uses
/// a separate safe reference, including reserved punctuation and Unicode cases.
nonisolated private func metadataSeedBinding(_ services: ProductLibraryServices, capture: String) async throws -> OriginalBinding {
    let input = try CaptureFixture(clip: capture)
    let reference = CaptureOriginalReference(rawValue: "upload-metadata-" + UUID().uuidString.lowercased())
    let intent = RecordingIntent(context: input.context, operation: input.intent.operation, original: reference,
        trialReference: input.intent.trialReference, desired: input.desired, applied: input.applied, acceptedAt: input.time)
    guard case .committed(let begun) = await services.store.execute(.commitIntent(input.token(1), expectedRevision: 0, intent)) else {
        throw BackendContractError.notCommitted
    }
    let url = try await services.originals.reserve(original: reference)
    try Data(repeating: 1, count: 4096).write(to: url, options: .withoutOverwriting)
    var lifecycle = try RecordingSaveLifecycle(intent: intent, intentToken: input.token(1), revision: 0)
    try lifecycle.acceptIntentCommit(begun); try lifecycle.acceptRecordingEnd(context: input.context, evidence: input.end)
    try lifecycle.acceptFile(.init(context: input.context, original: reference, byteCount: 4096, finalizedAt: input.time))
    _ = try lifecycle.acceptInspection(input.inspection(original: reference), resultToken: input.token(4))
    let record = try #require(lifecycle.resultRecord)
    guard case .committed(let saved) = await services.store.execute(.commitResult(input.token(4), expectedRevision: 1, record)) else {
        throw BackendContractError.notCommitted
    }
    let digest = try await services.originals.digest(for: reference)
    let binding = OriginalBinding(original: .init(capture: input.context.capture, generation: .init(rawValue: 1),
        content: try .init(byteCount: digest.byteCount, algorithm: "sha256", digest: digest.sha256)), reference: reference,
        saveRecord: record, saveCommit: saved)
    _ = try await mediaOriginalCommit(services.store, .bind(binding))
    return binding
}

nonisolated func metadataBegin(_ f: MetadataAppFixture, kind: UploadMetadataQueryKind = .create,
    store override: (any MediaOperationStorePort)? = nil) async throws -> CommittedUploadMetadataQuery {
    let store: any MediaOperationStorePort = override ?? f.services.store
    let snapshot = try await mediaSnapshot(store), current = try UploadMetadataScope.request(f.request, in: snapshot)
    let query = try UploadMetadataQuery(id: .init(rawValue: UUID().uuidString.lowercased()),
        observationCommand: .init(rawValue: UUID().uuidString.lowercased()), request: f.request, kind: kind,
        generation: UploadMetadataGeneration.next(lastObservation: current.lastObservation,
            reservations: snapshot.uploadMetadataQueries.filter { $0.query.request.operation == f.request.operation }.map { $0.query.generation }))
    guard case .committed = await store.commit(.init(expectedRevision: snapshot.revision, change: .uploadMetadata(.beginQuery(query)),
        expectedStoreIdentity: f.request.storeIdentity)) else { throw BackendContractError.notCommitted }
    return try #require(try await mediaSnapshot(store).uploadMetadataQueries.last)
}
nonisolated func metadataRecorded(_ result: UploadMetadataResult) throws -> StoredUploadMetadataObservation {
    guard case .recorded(let record) = result else { throw BackendContractError.notCommitted }; return record
}

actor MetadataTestRemote: UploadMetadataRemotePort {
    private let beforeReply: @Sendable (CommittedUploadMetadataQuery) async -> Void
    private let state: UploadMetadataState
    private let session = UploadSessionID(rawValue: UUID().uuidString.lowercased())
    private var received: [CommittedUploadMetadataQuery] = []
    init(state: UploadMetadataState = .receiving,
         beforeReply: @escaping @Sendable (CommittedUploadMetadataQuery) async -> Void = { _ in }) {
        self.state = state; self.beforeReply = beforeReply
    }
    func create(_ query: CommittedUploadMetadataQuery) async -> BackendOutcome<UploadMetadataResponse> {
        received.append(query); await beforeReply(query)
        return .succeeded(.created(.init(registration: query.query.request.registration.server.registration,
            operation: query.query.request.operation, original: query.query.request.original, session: session, chunkSize: 4096)))
    }
    func lookup(_ query: CommittedUploadMetadataQuery) async -> BackendOutcome<UploadMetadataResponse> {
        received.append(query); await beforeReply(query)
        guard case .lookup(let session) = query.query.kind else { return .failed(.rejected) }
        let original = query.query.request.original
        let proof: UploadFinalReadEvidence? = state == .completed ? .init(id: .init(rawValue: UUID().uuidString.lowercased()),
            schemaVersion: "fr-final-read-v1", method: "final_destination_read_back", committed: true, finalSaveCompleted: true,
            sha256: original.content.digest, byteCount: original.content.byteCount, observedAt: Date(timeIntervalSince1970: 1_800_000_000)) : nil
        return .succeeded(.status(.init(binding: .init(registration: query.query.request.registration.server.registration,
            operation: query.query.request.operation, original: original, session: session, chunkSize: 4096),
            state: state, evidence: proof, chunkIndexes: state == .completed ? [0] : [], failureCode: nil)))
    }
    func queries() -> [CommittedUploadMetadataQuery] { received }
}

actor MetadataTestStore: MediaOperationStorePort {
    let base: SQLiteRecordingStore
    private let stage: String?
    private let loss: String?
    private var conflicts: Int
    private var hidden = true
    private var identityFault: RegistrationStoreIdentity?
    private var hideRecords = false
    private var unknownLookup = false
    private var seen: [BackendStoreMutation] = []
    init(base: SQLiteRecordingStore, stage: String? = nil, loss: String? = nil, conflicts: Int = 0) {
        self.base = base; self.stage = stage; self.loss = loss; self.conflicts = conflicts
    }
    private func affected(_ mutation: BackendStoreMutation) -> Bool {
        switch mutation.change {
        case .uploadMetadata(.beginQuery): return stage == "begin"
        case .uploadMetadata(.observe): return stage == "observe"
        default: return false
        }
    }
    func load() async -> BackendStoreLoadResult {
        guard case .loaded(var snapshot) = await base.load() else { return .unavailable(.inaccessible) }
        if let identityFault { snapshot.storeIdentity = identityFault }
        if hideRecords { snapshot.uploadMetadataObservations = [] }
        return .loaded(snapshot)
    }
    func commit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        seen.append(mutation)
        if affected(mutation), conflicts > 0 { conflicts -= 1; return .rejected(.revisionConflict) }
        if affected(mutation), hidden, loss == "before" { return .unknown }
        let result = await base.commit(mutation)
        return affected(mutation) && hidden && loss == "after" ? .unknown : result
    }
    func lookupCommit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        if unknownLookup || (affected(mutation) && hidden && loss != nil) { return .unknown }
        return await base.lookupCommit(mutation)
    }
    func performUploadMetadataIfCurrent(_ query: CommittedUploadMetadataQuery, action: @Sendable () -> Void) async -> Bool {
        await base.performUploadMetadataIfCurrent(query, action: action)
    }
    func mutations() -> [BackendStoreMutation] { seen }
    func reveal() { hidden = false }
    func materializeLast() async throws {
        guard let mutation = seen.last, case .committed = await base.commit(mutation) else { throw BackendContractError.notCommitted }
    }
    func changeObservation(_ kind: String) {
        if kind == "identity" { identityFault = .init(rawValue: UUID()) }
        if kind == "record" { hideRecords = true }
        if kind == "lookup" { unknownLookup = true }
    }
    func restoreObservation() { identityFault = nil; hideRecords = false; unknownLookup = false }
}

actor MetadataTestCheckpoint {
    private var held = false, resumed = false
    private var blocked: CheckedContinuation<Void, Never>?, arrived: CheckedContinuation<Void, Never>?
    func hold() async {
        held = true; arrived?.resume(); arrived = nil
        if resumed { return }
        await withCheckedContinuation { blocked = $0 }
    }
    func waitUntilHeld() async { if held { return }; await withCheckedContinuation { arrived = $0 } }
    func resume() { resumed = true; blocked?.resume(); blocked = nil }
}
private actor MetadataCallbackProbe {
    private var countValue = 0
    func called() { countValue += 1 }
    func count() -> Int { countValue }
}
