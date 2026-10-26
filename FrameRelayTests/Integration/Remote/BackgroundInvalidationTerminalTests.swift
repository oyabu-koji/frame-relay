import CryptoKit
import Darwin
import Foundation
import Testing
@testable import FrameRelay

/// One new UUID root on the explicitly dedicated simulator only. Native resume
/// remains refused and no task.resume is called. The injected permit, saved
/// classification and Mac metadata below are technical inputs, not production
/// network/Log/Rec.709 or active-upload invalidation acceptance.
@Suite(.serialized) @MainActor struct BackgroundInvalidationTerminalTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_BACKGROUND_INVALIDATION_NATIVE"] == "1"), .timeLimit(.minutes(3)))
    func nativeResumeRefusalCancellationClosesOwnFDThenLaterNormalPollAcksWithoutSending() async throws {
        let environment = ProcessInfo.processInfo.environment
        let dedicated = UUID(uuidString: "64ADDF12-3B84-40E9-BC0A-922CEC02E77A")!
        try #require(environment["SIMULATOR_UDID"].flatMap(UUID.init(uuidString:)) == dedicated)
        try #require(environment["FR_BACKGROUND_INVALIDATION_SIMULATOR_ID"].flatMap(UUID.init(uuidString:)) == dedicated)
        let rootID = try #require(environment["FR_BACKGROUND_INVALIDATION_ROOT_ID"].flatMap(UUID.init(uuidString:)))
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("FrameRelay-background-invalidation-native-" + rootID.uuidString)
        try #require(!FileManager.default.fileExists(atPath: parent.path))
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        let photos = BackgroundInvalidationUnusedPhotos()
        let library = ProductLibraryFactory(supportDirectory: parent, photoLibrary: photos)
        let services = try await library.open(), seed = try await BackgroundProductInvalidationSeed.make(services)
        let originalURL = try await services.originals.existingURL(for: seed.binding.reference)
        let bytes = try Data(contentsOf: originalURL)
        let sentinel = parent.appendingPathComponent("external-sentinel.bin"), sentinelBytes = Data(UUID().uuidString.utf8)
        try sentinelBytes.write(to: sentinel, options: .withoutOverwriting)
        let managed = try ManagedUploadSource(run: services.run, originals: services.access)
        let finish = BackgroundCheckpoint()
        let source = BackgroundInvalidationNativeSource(base: managed, store: services.store, gate: finish)
        let native = try BackgroundMediaSession(identity: seed.fixture.plan.session)
        let sdk = BackgroundInvalidationNativeSession(base: native)
        let expectedSession = seed.fixture.plan.session
        let background = ProductBackgroundMediaFactory(library: library, admission: BackgroundPermitProbe(),
            sessionFactory: { identity in
                guard PublicationStoreBoundary.exact(identity, expectedSession) else { throw BackendContractError.identityMismatch }
                return sdk
            }, sourceFactory: { opened in
                guard opened.store === services.store else { throw BackendContractError.identityMismatch }
                return source
            })
        let remote = StatusMetadataRemote()
        remote.pages = [.succeeded(.init(records: [seed.record], nextAfter: nil))]
        remote.setManifest(seed.rendition, revision: 2, generation: seed.record.generation.rawValue)
        let composition = ProductComposition(factory: library, backgroundFactory: background, registrationFactory: { store in
            RegistrationCoordinator(store: store, vault: BackgroundInvalidationEmptyVault(), remote: RegistrationTestRemote())
        }, statusSynchronizationFactory: { opened, media in
            ProductStatusSynchronization(store: opened.store, access: opened.access, media: media,
                credentials: BackgroundInvalidationNoCredentials(), admission: { true }, background: background,
                remoteFactory: { _, _, _, _ in remote })
        })
        do {
            await composition.open()
            let port = try #require(composition.statusSynchronization)
            // The existing resume-refusal branch issues the real cancel before
            // invalidation is polled. This probe does not count it as a cancel
            // newly issued by stopForInvalidation; that branch has Unit coverage.
            #expect(await background.startUpload(seed.fixture.plan) == .refused(.sdkResumeUnavailable))
            try await finish.waitForArrival()
            let before = try await mediaSnapshot(services.store), task = try #require(before.backgroundTasks.first)
            let binding = try #require(task.binding), terminal = try #require(task.terminal)
            let initialSDK = await sdk.snapshot()
            #expect(initialSDK.created == [binding] && initialSDK.resumes.count == 1 && initialSDK.stops == [binding])
            let attempt = try #require(initialSDK.resumes.first)
            guard case .succeeded(let suspended) = attempt.observations else { throw BackendContractError.unknownResult }
            #expect(suspended.count == 1 && suspended[0].state == .suspended && suspended[0].kind == .upload)
            #expect(PublicationStoreBoundary.exact(suspended[0].session, binding.session))
            #expect(suspended[0].taskIdentifier == binding.taskIdentifier && suspended[0].taskDescription == binding.taskDescription)
            #expect(suspended[0].bytesSent == 0 && suspended[0].bytesReceived == 0)
            #expect(attempt.result == .notExecuted && attempt.terminal == .inProgress)
            #expect(terminal.binding == binding && terminal.outcome == .cancelled)
            #expect(task.stopRequested && task.resumeRequested && task.ownerClosure == nil)
            #expect((await managed.resources()).openHandles == 1)
            #expect(before.invalidations.isEmpty && before.outbox.isEmpty)

            let first = await port.synchronize(connection: seed.connection, registration: seed.registration)
            let waiting = try await mediaSnapshot(services.store)
            #expect(first.phase == .partial && first.unresolvedInvalidations == 1)
            #expect(waiting.invalidations.isEmpty && waiting.outbox.isEmpty && remote.sent.isEmpty)
            #expect(waiting.backgroundTasks[0].terminal == terminal && waiting.backgroundTasks[0].ownerClosure == nil)
            #expect((await managed.resources()).openHandles == 1)
            #expect((await sdk.snapshot()).stops == initialSDK.stops) // No additional invalidation-origin cancel.
            #expect(!(try await mediaOriginalSnapshot(services.store).logicalOriginals[0].readers.isEmpty))
            #expect(try await mediaOriginalSnapshot(services.store).logicalOriginals[0].invalidation?.record == seed.record)

            await finish.release()
            try await backgroundInvalidationWaitForStopped(services.store, operation: seed.fixture.plan.context.operation)
            let closed = try await mediaSnapshot(services.store), observation = try #require(await source.snapshot().first)
            guard case .upload(_, let lease, let identity) = task.intent.source else { throw BackendContractError.identityMismatch }
            #expect(closed.invalidations.isEmpty && remote.sent.isEmpty) // Consumer completion alone did not ACK.
            #expect(observation.lease == lease && observation.closure.uploadSource == identity)
            #expect(observation.terminal == terminal && observation.durableTerminalBeforeFinish == terminal)
            #expect(observation.durableClosureBeforeFinish == nil && observation.closure.binding == binding)
            #expect(observation.closure.tasksJoined && observation.closure.handlesClosed)
            #expect(observation.before.openHandles == 1 && observation.after.openHandles == 0 && observation.after.activeCopies == 0)
            #expect(observation.descriptors.count == 1 && observation.descriptors.allSatisfy { $0.result == -1 && $0.error == EBADF })
            #expect(observation.readersBeforeFinish == [observation.lease])
            #expect(try await mediaOriginalSnapshot(services.store).logicalOriginals[0].readers.isEmpty)

            let second = await port.synchronize(connection: seed.connection, registration: seed.registration)
            let final = try await mediaSnapshot(services.store), ack = try #require(final.invalidations.first)
            #expect(second.phase == .checked && second.unresolvedInvalidations == 0)
            #expect(PublicationStoreBoundary.exact(ack.record, seed.record) && ack.isCommitted)
            #expect(remote.sent == [.invalidation(ack)] && remote.mediaCalls == 0)
            #expect(final.backgroundTasks[0].ownerClosure == observation.closure)
            #expect(final.requests[0].transport == .stopped && final.requests[0].intent == .running && final.requests[0].remote == .notExecuted)
            let inventory = try #require(await backgroundInvalidationInventory(services.store, original: seed.rendition.original))
            let terminalCommit = try #require(taskEvent(final.backgroundTasks[0], terminal: true))
            let closeCommit = try #require(taskEvent(final.backgroundTasks[0], terminal: false))
            let stoppedCommit = try #require(inventory.journal.first { fact in
                if case .requestTransition(_, let operation, _, _, .stopped) = fact.mutation.change { return operation == seed.fixture.plan.context.operation }
                return false
            })
            #expect(terminalCommit.commit.committedRevision < closeCommit.commit.committedRevision)
            #expect(closeCommit.commit.committedRevision < stoppedCommit.commit.committedRevision)
            #expect(stoppedCommit.commit.committedRevision < ack.commit.committedRevision)
            for fact in inventory.journal { #expect(await services.store.lookupCommit(fact.mutation) == .committed(fact.commit)) }
            let original = try #require(try await mediaOriginalSnapshot(services.store).logicalOriginals.first)
            #expect(original.readers.isEmpty && original.mediaReaders.isEmpty && original.invalidation == nil && original.removal == nil)
            #expect(try Data(contentsOf: originalURL) == bytes)
            #expect(try Data(contentsOf: sentinel) == sentinelBytes)
            let exports = await source.exportedFiles()
            #expect(exports.count == 1)
            #expect(try Data(contentsOf: exports[0].url) == bytes)
            let reopened = try SQLiteRecordingStore(run: services.run, mode: .openExisting)
            #expect(try await mediaSnapshot(reopened).invalidations == [ack])
            #expect(try await mediaSnapshot(reopened).backgroundTasks == final.backgroundTasks)
            #expect(await reopened.lookupInvalidation(ack) == .succeeded(seed.record.id))
            #expect(try await mediaOriginalSnapshot(reopened).logicalOriginals[0].readers.isEmpty)
            #expect(await photos.callCount() == 0)

            await sdk.invalidate()
            try await backgroundEventually { await sdk.hasEnded() }
            await sdk.joinForwarder()
            let observed = await sdk.snapshot(), resources = try await managed.closeOwner()
            let actualTerminals = observed.events.compactMap { event -> BackgroundMediaSDKTerminal? in
                if case .taskTerminal(let value) = event.value { return value }; return nil
            }
            #expect(observed.created == [binding] && observed.resumes.count == 1 && observed.stops == [binding])
            #expect(actualTerminals == [terminal] && observed.ended)
            #expect(observed.events.allSatisfy { PublicationStoreBoundary.exact($0.session, binding.session) && $0.stream == observed.events.first?.stream })
            #expect(observed.events.map(\.sequence) == observed.events.indices.map { UInt64($0) + 1 })
            #expect(observed.events.filter { if case .sessionInvalidated(errorCode: nil) = $0.value { return true }; return false }.count == 1)
            #expect(!observed.events.contains { if case .unknownTaskTerminal = $0.value { return true }; return false })
            #expect(!observed.events.contains { if case .downloadArtifactUnavailable = $0.value { return true }; return false })
            #expect(resources.openHandles == 0 && resources.activeCopies == 0)
            let report: [String: Any] = [
                "schema": "fr-background-invalidation-native-v1", "fixtureOnly": true, "customRoot": parent.path,
                "originalSHA256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
                "injectedStrictPermit": true, "injectedMacObservation": "notExecuted", "injectedMetadataRemote": true,
                "sdkCreated": observed.created.count, "nativeResumeAttempts": observed.resumes.count,
                "nativeAcceptedResumes": observed.resumes.filter { if case .succeeded = $0.result { return true }; return false }.count,
                "suspendedBytesSent": suspended[0].bytesSent, "suspendedBytesReceived": suspended[0].bytesReceived,
                "nativeCancelOrigin": "existing startUpload native-resume-refusal stop; not new invalidation stop dispatch",
                "nativeCancelRequests": observed.stops.count, "nativeCancelledCallbacks": actualTerminals.filter { $0.outcome == .cancelled }.count,
                "firstPollHadActualTerminalButOpenOwnFD": true, "firstPollAckCount": waiting.invalidations.count,
                "secondPollAckCount": final.invalidations.count, "ownFDClosedEBADF": observation.descriptors.allSatisfy { $0.result == -1 && $0.error == EBADF },
                "fdScope": "only this ManagedUploadSource retained FD; no claim about SDK-owned descriptors",
                "leaseAbsent": !original.readers.contains(observation.lease), "stoppedBeforeAck": stoppedCommit.commit.committedRevision < ack.commit.committedRevision,
                "diskReopenAckExact": try await mediaSnapshot(reopened).invalidations == [ack], "photoCalls": await photos.callCount(),
                "sessionForwarderEnded": observed.ended, "originalAndSentinelPreserved": try Data(contentsOf: originalURL) == bytes && Data(contentsOf: sentinel) == sentinelBytes
            ]
            Attachment.record(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), as: UTF8.self),
                named: "background-invalidation-native-observation.json")
        } catch {
            await finish.release()
            for binding in await sdk.snapshot().created { await sdk.requestStop(binding) }
            await sdk.invalidate()
            try? await backgroundEventually { await sdk.hasEnded() }
            await sdk.joinForwarder()
            throw error
        }
    }
}

nonisolated private func taskEvent(_ task: BackgroundMediaTaskState, terminal: Bool) -> StoredBackgroundMediaTaskEvent? {
    task.events.first { event in
        if terminal, case .terminal = event.change { return true }
        if !terminal, case .ownerClosed = event.change { return true }
        return false
    }
}
nonisolated private func backgroundInvalidationInventory(_ store: any OriginalStorePort, original: OriginalContent) async -> OriginalRemovalTransportInventory? {
    guard case .succeeded(let value) = await store.loadRemovalTransportInventory(original) else { return nil }; return value
}

nonisolated private struct BackgroundInvalidationNativeResume: Sendable {
    let observations: BackendOutcome<[BackgroundMediaTaskObservation]>
    let terminal: BackendOutcome<BackgroundMediaSDKTerminal>
    let result: BackendOutcome<BackgroundMediaTaskBinding>
}
nonisolated private struct BackgroundInvalidationNativeSDKSnapshot: Sendable {
    let created: [BackgroundMediaTaskBinding]
    let resumes: [BackgroundInvalidationNativeResume]
    let stops: [BackgroundMediaTaskBinding]
    let events: [BackgroundMediaSDKEvent]
    let ended: Bool
}
private actor BackgroundInvalidationNativeSession: BackgroundMediaSessionPort {
    let base: BackgroundMediaSession
    private var taken = false
    private var created: [BackgroundMediaTaskBinding] = []
    private var resumes: [BackgroundInvalidationNativeResume] = []
    private var stops: [BackgroundMediaTaskBinding] = []
    private var observed: [BackgroundMediaSDKEvent] = []
    private var forwarder: Task<Void, Never>?
    private var ended = false
    init(base: BackgroundMediaSession) { self.base = base }
    func events() async throws -> AsyncStream<BackgroundMediaSDKEvent> {
        guard !taken else { throw BackendContractError.wrongStage }; taken = true
        let input = try await base.events(), pair = AsyncStream<BackgroundMediaSDKEvent>.makeStream()
        forwarder = Task {
            for await event in input { observed.append(event); pair.continuation.yield(event) }
            pair.continuation.finish(); ended = true
        }
        return pair.stream
    }
    func createSuspended(_ intent: BackgroundMediaTaskIntent, request: URLRequest, upload: BackgroundMediaUploadFile?) async -> BackendOutcome<BackgroundMediaTaskBinding> {
        let result = await base.createSuspended(intent, request: request, upload: upload)
        if case .succeeded(let binding) = result { created.append(binding) }
        return result
    }
    func enumerate() async -> BackendOutcome<[BackgroundMediaTaskObservation]> { await base.enumerate() }
    func resume(_ binding: BackgroundMediaTaskBinding, permit: BackgroundMediaStrictPermit,
                captureAuthorization: CaptureMediaResumeAuthorization) async -> BackendOutcome<BackgroundMediaTaskBinding> {
        let before = await base.enumerate(), terminal = await base.observeTerminal(binding)
        let result = await base.resume(binding, permit: permit, captureAuthorization: captureAuthorization)
        resumes.append(.init(observations: before, terminal: terminal, result: result)); return result
    }
    func requestStop(_ binding: BackgroundMediaTaskBinding) async { stops.append(binding); await base.requestStop(binding) }
    func observeTerminal(_ binding: BackgroundMediaTaskBinding) async -> BackendOutcome<BackgroundMediaSDKTerminal> { await base.observeTerminal(binding) }
    func invalidate() async { await base.invalidate() }
    func hasEnded() -> Bool { ended }
    func joinForwarder() async { await forwarder?.value }
    func snapshot() -> BackgroundInvalidationNativeSDKSnapshot { .init(created: created, resumes: resumes, stops: stops, events: observed, ended: ended) }
}

nonisolated private struct BackgroundInvalidationFDProbe: Sendable {
    let result: Int32
    let error: Int32
}
nonisolated private struct BackgroundInvalidationNativeFinish: Sendable {
    let lease: OriginalReadLease
    let terminal: BackgroundMediaSDKTerminal
    let closure: BackgroundMediaOwnerClosure
    let before: ManagedUploadSourceResources
    let after: ManagedUploadSourceResources
    let descriptors: [BackgroundInvalidationFDProbe]
    let durableTerminalBeforeFinish: BackgroundMediaSDKTerminal?
    let durableClosureBeforeFinish: BackgroundMediaOwnerClosure?
    let readersBeforeFinish: [OriginalReadLease]
}
private actor BackgroundInvalidationNativeSource: BackgroundMediaUploadSourcePort {
    let base: ManagedUploadSource
    let store: SQLiteRecordingStore
    let gate: BackgroundCheckpoint
    private var exports: [BackgroundMediaUploadFile] = []
    private var finishes: [BackgroundInvalidationNativeFinish] = []
    init(base: ManagedUploadSource, store: SQLiteRecordingStore, gate: BackgroundCheckpoint) { self.base = base; self.store = store; self.gate = gate }
    func create(from lease: OriginalReadLease, id: ManagedUploadSourceID) async throws -> ManagedUploadSourceIdentity { try await base.create(from: lease, id: id) }
    func uploadFile(for identity: ManagedUploadSourceIdentity, lease: OriginalReadLease) async throws -> BackgroundMediaUploadFile {
        let value = try await base.uploadFile(for: identity, lease: lease); exports.append(value); return value
    }
    func retain(_ identity: ManagedUploadSourceIdentity, lease: OriginalReadLease, for binding: BackgroundMediaTaskBinding) async throws {
        try await base.retain(identity, lease: lease, for: binding)
    }
    func finish(_ identity: ManagedUploadSourceIdentity, lease: OriginalReadLease,
                terminal: BackgroundMediaSDKTerminal) async throws -> BackgroundMediaOwnerClosure {
        let before = await base.resources(), snapshot = try await mediaSnapshot(store)
        let task = snapshot.backgroundTasks.first { $0.binding == terminal.binding }
        let readers = try await mediaOriginalSnapshot(store).logicalOriginals.first { $0.original == lease.original }?.readers ?? []
        await gate.checkpoint()
        let closure = try await base.finish(identity, lease: lease, terminal: terminal)
        let descriptors = before.descriptors.map { descriptor -> BackgroundInvalidationFDProbe in
            let result = fcntl(descriptor, F_GETFD)
            return .init(result: result, error: result == -1 ? errno : 0)
        }
        let after = await base.resources()
        finishes.append(.init(lease: lease, terminal: terminal, closure: closure, before: before, after: after,
            descriptors: descriptors, durableTerminalBeforeFinish: task?.terminal,
            durableClosureBeforeFinish: task?.ownerClosure, readersBeforeFinish: readers))
        return closure
    }
    func snapshot() -> [BackgroundInvalidationNativeFinish] { finishes }
    func exportedFiles() -> [BackgroundMediaUploadFile] { exports }
}
