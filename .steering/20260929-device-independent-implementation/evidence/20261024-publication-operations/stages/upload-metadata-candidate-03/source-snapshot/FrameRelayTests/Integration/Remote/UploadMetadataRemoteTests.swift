import Foundation
import Testing
@testable import FrameRelay

@Suite(.serialized) @MainActor struct UploadMetadataRemoteTests {
    @Test func absentDispatchWitnessDefaultsClosedAndTheSuspendedNativeOwnerActuallyTerminates() async throws {
        let (f, query) = try await metadataWireQuery(lookup: false)
        let store = MetadataNoDispatchStore(base: f.services.store), observation = UploadMetadataHTTPObservation()
        let credentials = MetadataAuthorizationProbe()
        let remote = URLSessionUploadMetadataRemote(connection: try metadataHTTPSConnection(f), credentials: credentials,
            store: store, observation: observation)
        #expect(await remote.create(query) == .notExecuted)
        #expect(await remote.create(query) == .notExecuted)
        #expect(observation.snapshot.tasksCreated == 1 && observation.snapshot.resumePermits == 0)
        #expect(observation.snapshot.taskCompletions == 1 && observation.snapshot.sessionInvalidations == 1
            && observation.snapshot.continuationResumes == 1 && observation.snapshot.maximumRetainedBytes == 0)
        try await f.assertBytesAndNoMedia()
    }

    @Test func structurallyValidButUnrecordedBeginReceiptCannotEvenConstructAnHTTPTask() async throws {
        let (f, saved) = try await metadataWireQuery(lookup: false), observation = UploadMetadataHTTPObservation()
        let fake = CommittedUploadMetadataQuery(query: saved.query,
            commit: .init(key: saved.query.key, previousRevision: saved.commit.previousRevision + 1,
                committedRevision: saved.commit.committedRevision + 1), expectedStoreIdentity: saved.expectedStoreIdentity)
        #expect(fake.isCommitted)
        let auth = MetadataAuthorizationProbe()
        let remote = URLSessionUploadMetadataRemote(connection: try metadataHTTPSConnection(f), credentials: auth,
            store: f.services.store, observation: observation)
        guard case .succeeded = await remote.create(fake) else {
            #expect(observation.snapshot.tasksCreated == 0 && observation.snapshot.resumePermits == 0)
            #expect(await auth.calls() == 0); return
        }
        Issue.record("A fabricated begin receipt became an HTTP dispatch")
    }

    @Test(arguments: ["pause", "cancel", "generation", "registration"])
    func changeAfterNativeTaskPreparationIsRefusedAtTheWriterResumeBoundary(race: String) async throws {
        let (f, query) = try await metadataWireQuery(lookup: false), gate = MetadataTestCheckpoint()
        let store = MetadataDispatchCheckpointStore(base: f.services.store, gate: gate), observation = UploadMetadataHTTPObservation()
        let remote = URLSessionUploadMetadataRemote(connection: try metadataHTTPSConnection(f), credentials: MetadataAuthorizationProbe(),
            store: store, observation: observation)
        let first = Task { await remote.create(query) }
        await gate.waitUntilHeld()
        #expect(observation.snapshot.tasksCreated == 1 && observation.snapshot.resumePermits == 0)
        if race == "generation" { _ = try await metadataBegin(f) }
        else if race == "registration" {
            _ = try await mediaRegister(f.services.store, registration: .init(destination: f.request.registration.server.registration.destination,
                id: .init(rawValue: UUID().uuidString.lowercased()), generation: .init(rawValue: 2)))
        } else {
            let current = try #require(try await mediaSnapshot(f.services.store).requests.first)
            _ = try await mediaCommit(f.services.store, .requestTransition(command: .init(rawValue: UUID().uuidString),
                operation: current.operation, target: current.target, registration: current.registration, value: race == "pause" ? .pause : .cancel))
        }
        let sameQuery = Task { await remote.create(query) }
        await gate.resume()
        let firstResult = await first.value, sameResult = await sameQuery.value
        #expect(firstResult == .notExecuted && sameResult == .notExecuted)
        #expect(observation.snapshot.tasksCreated == 1 && observation.snapshot.resumePermits == 0)
        #expect(observation.snapshot.taskCompletions == 1 && observation.snapshot.sessionInvalidations == 1
            && observation.snapshot.continuationResumes == 1)
        try await f.assertBytesAndNoMedia()
    }

    @Test(arguments: ["pause", "identity", "credentials"])
    func credentialAwaitMustRecheckScopeWithoutCreatingNativeHTTP(race: String) async throws {
        let (f, query) = try await metadataWireQuery(lookup: false), store = MetadataTestStore(base: f.services.store)
        let auth = MetadataAuthorizationProbe(hook: {
            if race == "identity" { await store.changeObservation("identity") }
            if race == "pause" {
                let current = try? await mediaSnapshot(f.services.store).requests.first
                if let current {
                    _ = try? await mediaCommit(f.services.store, .requestTransition(command: .init(rawValue: UUID().uuidString),
                        operation: current.operation, target: current.target, registration: current.registration, value: .pause))
                }
            }
        }, denied: race == "credentials")
        let observation = UploadMetadataHTTPObservation()
        let remote = URLSessionUploadMetadataRemote(connection: try metadataHTTPSConnection(f), credentials: auth, store: store, observation: observation)
        let result = await remote.create(query)
        if case .succeeded = result { Issue.record("An obsolete credential preflight dispatched") }
        #expect(observation.snapshot.tasksCreated == 0 && observation.snapshot.resumePermits == 0)
        #expect(try await mediaSnapshot(f.services.store).uploadMetadataObservations.isEmpty)
        await store.restoreObservation()
        try await f.assertBytesAndNoMedia()
    }

    /// Main prepares a new isolated server/registration and opts in. This test
    /// sends POST/GET metadata only: no chunks, finalize, DELETE or media bytes.
    @Test(.enabled(if: metadataHTTPFlag("FR_UPLOAD_METADATA_HTTP")))
    func isolatedActualHTTPCreateAndPausedCancelledKnownSessionGETOnly() async throws {
        #if DEBUG && targetEnvironment(simulator)
        let prefix = "FR_UPLOAD_METADATA_HTTP_"
        let nonce = try metadataHTTPValue(prefix + "NONCE")
        try #require(RegistrationWireIdentity.isCanonical(nonce) && metadataHTTPFlag(prefix + "NEW_ISOLATED")
            && !metadataHTTPFlag("FR_UPLOAD_METADATA_HTTP_FAULT"))
        let origin = try metadataHTTPValue(prefix + "ORIGIN")
        let endpoint = try RegistrationEndpoint.isolatedLoopbackProbe(origin)
        let destination = try metadataHTTPValue(prefix + "DESTINATION"), id = try metadataHTTPValue(prefix + "REGISTRATION")
        try #require(RegistrationWireIdentity.isCanonical(destination) && RegistrationWireIdentity.isCanonical(id))
        let generationText = try metadataHTTPValue(prefix + "GENERATION")
        let generation = try #require(UInt64(generationText))
        try #require(generation > 0 && generation <= UInt64(Int64.max) && String(generation) == generationText)
        let f = try await MetadataAppFixture.make(registration: .init(destination: .init(rawValue: destination),
            id: .init(rawValue: id), generation: .init(rawValue: generation)), capture: "metadata-http-" + nonce + "-" + UUID().uuidString)
        let connection = try RegistrationConnection(endpoint: endpoint, destination: .init(rawValue: destination))
        let credentials = MetadataAuthorizationProbe(bearer: try metadataHTTPValue(prefix + "BEARER"), secret: try metadataHTTPValue(prefix + "SECRET"))
        let observation = UploadMetadataHTTPObservation()
        let remote = URLSessionUploadMetadataRemote(connection: connection, credentials: credentials, store: f.services.store, observation: observation)
        let owner = UploadMetadataCoordinator(store: f.services.store, remote: remote)
        let created = try metadataRecorded(await owner.refresh(f.request))
        #expect(created.observation.query.query.kind == .create)
        let post = try #require(try await mediaSnapshot(f.services.store).requests.first)
        #expect(post.session != nil && post.remote == .unknown && !post.hasReconciled && !post.canRun)
        for value in [MediaRequestTransition.pause, .cancel] {
            let current = try #require(try await mediaSnapshot(f.services.store).requests.first)
            _ = try await mediaCommit(f.services.store, .requestTransition(command: .init(rawValue: UUID().uuidString),
                operation: current.operation, target: current.target, registration: current.registration, value: value))
            let record = try metadataRecorded(await owner.refreshKnownSession(f.request))
            guard case .status(let status) = record.observation.response else { throw BackendContractError.invalidValue }
            #expect(status.state == .receiving && status.chunkIndexes.isEmpty && status.evidence == nil)
        }
        let final = try await mediaSnapshot(f.services.store)
        #expect(final.requests[0].intent == .cancelled && final.uploadMetadataQueries.count == 3 && final.uploadMetadataObservations.count == 3)
        #expect(await remote.create(created.observation.query) == .succeeded(created.observation.response))
        #expect(observation.snapshot.tasksCreated == 3 && observation.snapshot.resumePermits == 3)
        #expect(observation.snapshot.taskCompletions == 3 && observation.snapshot.sessionInvalidations == 3
            && observation.snapshot.continuationResumes == 3)
        try await f.assertBytesAndNoMedia()
        print("UPLOAD_METADATA_ACTUAL_HTTP nonce=\(nonce) post=1 get=2 put=0 finalize=0 delete=0 mediaBytes=0 nativeTaskTerminals=3 sessionInvalidations=3 sourceBytes=unchanged logicalReaders=0 mediaReaders=0 technicalMetadataOnly=true")
        #else
        throw BackendContractError.unavailable
        #endif
    }

    /// Optional new loopback listener serves /metadata-probe/{case}. It must
    /// never forward requests to a real service or reuse an existing fixture.
    @Test(.enabled(if: metadataHTTPFlag("FR_UPLOAD_METADATA_HTTP_FAULT")),
          arguments: ["redirect", "oversize", "wrong-mime", "cancel"])
    func isolatedNativeHTTPRefusalBoundsCancellationAndActualTerminals(fault: String) async throws {
        #if DEBUG && targetEnvironment(simulator)
        let prefix = "FR_UPLOAD_METADATA_HTTP_FAULT_"
        let nonce = try metadataHTTPValue(prefix + "NONCE")
        try #require(RegistrationWireIdentity.isCanonical(nonce) && metadataHTTPFlag(prefix + "NEW_ISOLATED")
            && !metadataHTTPFlag("FR_UPLOAD_METADATA_HTTP"))
        let origin = try metadataHTTPValue(prefix + "ORIGIN")
        let endpoint = try RegistrationEndpoint.isolatedLoopbackProbe(origin)
        let (f, query) = try await metadataWireQuery(lookup: false), observation = UploadMetadataHTTPObservation()
        var request = URLRequest(url: endpoint.origin.appendingPathComponent("metadata-probe").appendingPathComponent(fault))
        request.httpMethod = "GET"; request.setValue(nonce, forHTTPHeaderField: "X-FrameRelay-Probe-Nonce")
        let operation = Task { try await GuardedUploadMetadataHTTP.perform(request, query: query, store: f.services.store, observation: observation) }
        if fault == "cancel" {
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while observation.snapshot.resumePermits == 0 && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
            #expect(observation.snapshot.resumePermits == 1)
            operation.cancel()
        }
        do { _ = try await operation.value; Issue.record("A deliberately invalid native response was accepted") } catch { }
        #expect(observation.snapshot.tasksCreated == 1 && observation.snapshot.resumePermits == 1)
        #expect(observation.snapshot.taskCompletions == 1 && observation.snapshot.sessionInvalidations == 1
            && observation.snapshot.continuationResumes == 1 && observation.snapshot.maximumRetainedBytes <= UploadMetadataWire.maximumBytes)
        if fault == "redirect" { #expect(observation.snapshot.redirectsRefused == 1) }
        #expect(try await mediaSnapshot(f.services.store).uploadMetadataObservations.isEmpty)
        try await f.assertBytesAndNoMedia()
        #else
        throw BackendContractError.unavailable
        #endif
    }
}

// Environment values never pass through an assertion macro that could render
// the whole environment dictionary (including the opt-in bearer or secret).
nonisolated private func metadataHTTPFlag(_ key: String) -> Bool { ProcessInfo.processInfo.environment[key] == "1" }
nonisolated private func metadataHTTPValue(_ key: String) throws -> String {
    guard let value = ProcessInfo.processInfo.environment[key], !value.isEmpty else { throw RegistrationAccessError.credentialUnavailable }
    return value
}

actor MetadataAuthorizationProbe: RegistrationAuthorizationPort {
    private let bearer: String
    private let secret: String
    private let hook: @Sendable () async -> Void
    private let denied: Bool
    private var count = 0
    init(bearer: String = "test-only-bearer", secret: String = "test-only-secret",
         hook: @escaping @Sendable () async -> Void = {}, denied: Bool = false) {
        self.bearer = bearer; self.secret = secret; self.hook = hook; self.denied = denied
    }
    func authorization(for connection: RegistrationConnection, intent: RegistrationIntent?, storeIdentity: RegistrationStoreIdentity) async throws -> RegistrationAuthorization {
        count += 1; await hook()
        if denied { throw RegistrationAccessError.credentialUnavailable }
        return .init(bearer: bearer, secret: secret)
    }
    func calls() -> Int { count }
}
private actor MetadataNoDispatchStore: MediaOperationStorePort {
    let base: SQLiteRecordingStore
    init(base: SQLiteRecordingStore) { self.base = base }
    func load() async -> BackendStoreLoadResult { await base.load() }
    func commit(_ mutation: BackendStoreMutation) async -> BackendCommitResult { await base.commit(mutation) }
    func lookupCommit(_ mutation: BackendStoreMutation) async -> BackendCommitResult { await base.lookupCommit(mutation) }
    // Intentionally no dispatch witness: the protocol's default must refuse.
}
private actor MetadataDispatchCheckpointStore: MediaOperationStorePort {
    let base: SQLiteRecordingStore
    let gate: MetadataTestCheckpoint
    init(base: SQLiteRecordingStore, gate: MetadataTestCheckpoint) { self.base = base; self.gate = gate }
    func load() async -> BackendStoreLoadResult { await base.load() }
    func commit(_ mutation: BackendStoreMutation) async -> BackendCommitResult { await base.commit(mutation) }
    func lookupCommit(_ mutation: BackendStoreMutation) async -> BackendCommitResult { await base.lookupCommit(mutation) }
    func performUploadMetadataIfCurrent(_ query: CommittedUploadMetadataQuery, action: @Sendable () -> Void) async -> Bool {
        await gate.hold() // Test checkpoint before entering the real writer lock.
        return await base.performUploadMetadataIfCurrent(query, action: action)
    }
}
