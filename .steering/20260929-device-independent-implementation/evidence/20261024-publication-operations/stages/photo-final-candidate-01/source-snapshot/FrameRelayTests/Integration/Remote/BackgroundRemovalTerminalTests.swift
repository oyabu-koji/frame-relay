import CryptoKit
import Darwin
import Foundation
import Testing
@testable import FrameRelay

/// Opt-in, disposable MOVs only. The permit and Mac notExecuted observation
/// come from an explicit fixture. Task creation/enumeration, cancelled terminal
/// and invalidation below come from the real BackgroundMediaSession delegate.
/// The native adapter refuses resume; this probe never calls URLSessionTask.resume.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["FR_BACKGROUND_REMOVAL_SDK_TEST"] == "1"))
@MainActor struct BackgroundRemovalTerminalTests {
    @Test(.timeLimit(.minutes(3)))
    func suspendedUploadActuallyTerminatesBeforeOrdinaryRiskDiscard() async throws {
        let parent = try backgroundRemovalParent()
        let photos = BackgroundRemovalUnusedPhotos()
        let library = ProductLibraryFactory(supportDirectory: parent, photoLibrary: photos)
        let services = try await library.open()
        let originals = OriginalRemovalFixture(run: services.run, store: services.store,
            files: services.originals, access: services.access)
        let fixture = try await BackgroundCoordinatorFixture.make(originals)
        let original = fixture.plan.context.target.original
        let binding = try #require(try await mediaOriginalSnapshot(services.store).originals.first {
            $0.binding.original == original
        }?.binding)
        let keep = try await originals.original("s34-background-keep-" + UUID().uuidString)
        let originalURL = try await services.originals.existingURL(for: binding.reference)
        let bytes = try Data(contentsOf: originalURL)
        #expect(UInt64(bytes.count) == original.content.byteCount && backgroundRemovalHash(bytes) == original.content.digest)
        #expect(bytes.count > 12 && String(decoding: bytes[4..<8], as: UTF8.self) == "ftyp")

        let managed = try ManagedUploadSource(run: services.run, originals: services.access)
        let native: BackgroundMediaSession
        do { native = try BackgroundMediaSession(identity: fixture.plan.session) }
        catch { _ = try? await managed.closeOwner(); throw error }
        let sdk = BackgroundRemovalNativeAudit(base: native)
        let source = BackgroundRemovalSourceAudit(base: managed, store: services.store)
        let background = ProductBackgroundMediaFactory(library: library, admission: BackgroundPermitProbe(),
            sessionFactory: { identity in
                guard identity == fixture.plan.session else { throw BackendContractError.identityMismatch }
                return sdk
            }, sourceFactory: { opened in
                guard opened.store === services.store else { throw BackendContractError.identityMismatch }
                return source
            })
        do {
            // Native resume stays closed even with the test-only permit. The
            // existing coordinator requests cancel and drains its real event.
            #expect(await background.startUpload(fixture.plan) == .refused(.sdkResumeUnavailable))
            try await backgroundRemovalWait("actual terminal, owner close, lease release and stopped commit") {
                let snapshot = try await mediaSnapshot(services.store)
                return snapshot.backgroundTasks.first(where: { $0.intent.id == fixture.plan.id })?.ownerClosure != nil
                    && snapshot.requests.first(where: { $0.operation == fixture.plan.context.operation })?.transport == .stopped
            }
            let media = try await mediaSnapshot(services.store)
            let state = try #require(media.backgroundTasks.first { $0.intent.id == fixture.plan.id })
            let task = try #require(state.binding)
            let terminal = try #require(state.terminal)
            let ownerClosed = try #require(state.ownerClosure)
            guard case .upload(let macSession, let lease, let identity) = state.intent.source else {
                throw BackendContractError.identityMismatch
            }
            let sdkBeforeRemoval = await sdk.snapshot()
            let resume = try #require(sdkBeforeRemoval.resumes.first)
            guard case .succeeded(let suspended) = resume.tasks else { throw BackendContractError.unavailable }
            #expect(sdkBeforeRemoval.created == [task] && sdkBeforeRemoval.resumes.count == 1)
            #expect(resume.binding == task && resume.terminal == .inProgress && resume.result == .notExecuted)
            #expect(suspended.count == 1 && suspended.first?.session == task.session
                && suspended.first?.taskIdentifier == task.taskIdentifier && suspended.first?.taskDescription == task.taskDescription)
            #expect(suspended.first?.kind == .upload && suspended.first?.state == .suspended)
            #expect(suspended.first?.bytesSent == 0 && suspended.first?.bytesReceived == 0)
            #expect(sdkBeforeRemoval.stops == [task])
            #expect(terminal.binding == task && terminal.outcome == .cancelled)
            #expect(state.resumeRequested && state.stopRequested)
            #expect(await native.observeTerminal(task) == .succeeded(terminal))
            #expect(ownerClosed.binding == task && ownerClosed.uploadSource == identity
                && ownerClosed.tasksJoined && ownerClosed.handlesClosed)

            let sourceObservation = await source.snapshot()
            let closed = try #require(sourceObservation.finishes.first)
            let exported = try #require(sourceObservation.exported.first)
            #expect(sourceObservation.created == [identity] && sourceObservation.leases == [lease])
            #expect(sourceObservation.finishes.count == 1 && sourceObservation.exported.count == 1)
            #expect(closed.terminal == terminal && closed.closure == ownerClosed && closed.lease == lease)
            #expect(closed.durableTerminalBeforeFinish == terminal && closed.durableClosureBeforeFinish == nil)
            #expect(closed.readersBeforeFinish == [lease])
            #expect(closed.before.openHandles == 1 && closed.after.openHandles == 0 && closed.after.activeCopies == 0)
            #expect(closed.after.closedHandles == closed.before.closedHandles + 1)
            #expect(closed.descriptors.count == 1 && closed.descriptors.allSatisfy { $0.result == -1 && $0.error == EBADF })
            #expect(closed.after.copiedBytes == original.content.byteCount && closed.after.largestOriginalRead <= 65_536)
            #expect(exported.identity == identity)
            #expect(try Data(contentsOf: exported.url) == bytes)
            let released = try #require(try await mediaOriginalSnapshot(services.store).logicalOriginals.first { $0.original == original })
            #expect(released.readers.isEmpty && released.mediaReaders.isEmpty)
            guard case .succeeded(let readers) = await services.access.reconcileReaders(original) else {
                throw BackendContractError.readersActive
            }
            #expect(readers.original == original)
            let request = try #require(media.requests.first { $0.operation == fixture.plan.context.operation })
            #expect(request.attempt == fixture.plan.context.attempt && request.session == macSession && request.transport == .stopped)
            // This remote observation was injected by BackgroundCoordinatorFixture;
            // zero bytes/cancelled completion did not produce a Mac result.
            #expect(request.remote == .notExecuted && media.verifications.isEmpty && media.confirmations.isEmpty)
            let terminalCommit = try #require(state.events.first { if case .terminal = $0.change { return true }; return false })
            let closedCommit = try #require(state.events.first { if case .ownerClosed = $0.change { return true }; return false })
            guard case .succeeded(let inventory) = await services.store.loadRemovalTransportInventory(original) else {
                throw BackendContractError.unavailable
            }
            let stoppedCommit = try #require(inventory.journal.first {
                if case .requestTransition(_, let operation, _, _, .stopped) = $0.mutation.change {
                    return operation == fixture.plan.context.operation
                }
                return false
            })
            #expect(terminalCommit.commit.committedRevision < closedCommit.commit.committedRevision
                && closedCommit.commit.committedRevision < stoppedCommit.commit.committedRevision)
            #expect(await services.originals.observeFile(binding.reference) == .present(byteCount: original.content.byteCount))

            // Use the normal composition/model. It obtains the new transport
            // seal/fence itself; the test supplies no quiescence or close bool.
            let composition = ProductComposition(factory: library, backgroundFactory: background, registrationFactory: { store in
                RegistrationCoordinator(store: store, vault: BackgroundRemovalEmptyVault(), remote: RegistrationTestRemote())
            })
            await composition.open()
            #expect(composition.openingIssue == nil)
            let model = try #require(composition.library)
            #expect(model.availability(.discard, captures: [original.capture]) == .available)
            let review = try #require(model.prepareRemovalReview(.discard, captures: [original.capture]))
            #expect(review.action == .discard && review.targets.count == 1 && review.targets.first?.original == original)
            model.select(keep.original.capture, selected: true)
            await model.submit(review)
            #expect(model.submission?.request.targets.map(\.capture) == [original.capture])
            #expect(model.submission?.request.discardRiskAcknowledged == true && model.submission?.phase == .awaitingRecordedResult)
            #expect(model.item(original.capture)?.isDiscardHistory == true)
            #expect(model.item(original.capture)?.operationResults.first?.id == review.id
                && model.item(original.capture)?.operationResults.first?.outcome == .succeeded)
            #expect(await services.originals.observeFile(binding.reference) == .absent)
            #expect(!FileManager.default.fileExists(atPath: originalURL.path))
            #expect(await services.originals.observeFile(keep.reference) == .present(byteCount: keep.original.content.byteCount))
            #expect(try Data(contentsOf: exported.url) == bytes) // Our closed copy is retained, never unlinked as the original.

            let reopened = try await ProductLibraryFactory(supportDirectory: parent, photoLibrary: photos).open()
            guard case .loaded(let projection) = await reopened.reader.loadLibrary() else { throw BackendContractError.unavailable }
            let disk = try await mediaOriginalSnapshot(reopened.store)
            let removed = try #require(disk.originals.first { $0.binding == binding })
            let batch = try #require(disk.removalBatches.first { $0.batch.operation == review.id })
            let target = try #require(batch.batch.targets.first)
            #expect(removed.removalResolution == .removed && removed.readers.isEmpty)
            #expect(batch.batch.targets == [target] && target.original == original)
            #expect(batch.batch.authorization == .discardRiskAcknowledged(target))
            #expect(projection.history.map(\.id) == [original.capture])
            #expect(projection.history.first?.operationResults.first?.id == review.id
                && projection.history.first?.operationResults.first?.outcome == .succeeded)
            #expect(projection.recordings.map(\.id) == [keep.original.capture])
            let replay = try await mediaSnapshot(reopened.store)
            #expect(replay.backgroundTasks == media.backgroundTasks && replay.requests == media.requests)
            #expect(await reopened.originals.observeFile(binding.reference) == .absent)
            #expect(await photos.callCount() == 0)

            // The removal fence needs a fresh SDK inventory, so invalidate only
            // after normal deletion and reopen. Wait for the real delegate and
            // join the forwarding task; invalidate() acceptance alone is not it.
            await sdk.invalidate()
            try await backgroundRemovalWait("actual session invalidation and event forwarder end") { await sdk.snapshot().forwarderEnded }
            await sdk.joinForwarder()
            let observed = await sdk.snapshot()
            let terminals = observed.events.compactMap { event -> BackgroundMediaSDKTerminal? in
                if case .taskTerminal(let value) = event.value { return value }; return nil
            }
            let invalidations = observed.events.filter { if case .sessionInvalidated = $0.value { return true }; return false }
            #expect(observed.created == [task] && observed.resumes.count == 1 && observed.stops == [task])
            #expect(terminals == [terminal] && invalidations.count == 1)
            #expect(invalidations.first?.value == .sessionInvalidated(errorCode: nil))
            #expect(observed.events.allSatisfy { $0.session == task.session && $0.stream == observed.events.first?.stream })
            #expect(observed.events.map(\.sequence) == observed.events.indices.map { UInt64($0) + 1 })
            #expect(!observed.events.contains { if case .unknownTaskTerminal = $0.value { return true }; return false })
            #expect(!observed.events.contains { if case .downloadArtifactUnavailable = $0.value { return true }; return false })
            let resources = try await managed.closeOwner()
            #expect(resources.openHandles == 0 && resources.activeCopies == 0)
            let acceptedResumes = observed.resumes.filter { if case .succeeded = $0.result { return true }; return false }.count
            let report: [String: Any] = [
                "report_schema": "fr-s34-background-removal-observation-v1", "fixtureOnly": true,
                "runPath": services.run.url.path, "capture": original.capture.rawValue, "originalBytes": bytes.count,
                "originalSHA256": backgroundRemovalHash(bytes), "injectedStrictPermit": true,
                "injectedMacObservation": "notExecuted; not inferred from SDK cancellation or zero bytes",
                "sdkCreatedTasks": observed.created.count, "nativeResumeRequests": observed.resumes.count,
                "nativeAcceptedResumeRequests": acceptedResumes, "sdkSuspendedBeforeResumeRefusal": suspended.filter { $0.state == .suspended }.count,
                "sdkBytesSentBeforeResumeRefusal": suspended.reduce(Int64(0)) { $0 + $1.bytesSent },
                "sdkBytesReceivedBeforeResumeRefusal": suspended.reduce(Int64(0)) { $0 + $1.bytesReceived },
                "sdkCancelRequests": observed.stops.count, "actualSDKTaskTerminalCallbacks": terminals.count,
                "actualSDKCancelledTerminals": terminals.filter { $0.outcome == .cancelled }.count,
                "actualSDKSessionInvalidations": invalidations.count, "actualSDKEventSequences": observed.events.map(\.sequence),
                "sourceFinishReturns": sourceObservation.finishes.count,
                "sourceFDClosedProbes": closed.descriptors.filter { $0.result == -1 && $0.error == EBADF }.count,
                "ownerClosureMatchesActualFinish": ownerClosed == closed.closure,
                "exactLeaseAbsentAfterStopped": !released.readers.contains(lease), "requestStopped": request.transport == .stopped,
                "riskAcknowledged": model.submission?.request.discardRiskAcknowledged == true,
                "diskReopenRemoved": removed.removalResolution == .removed, "discardHistoryCount": projection.history.count,
                "unrelatedOriginalPresent": await services.originals.observeFile(keep.reference) == .present(byteCount: keep.original.content.byteCount),
                "photoLibraryCalls": await photos.callCount(), "forwarderJoined": observed.forwarderEnded,
                "sourceFDMeaning": "only ManagedUploadSource's retained descriptor; no claim about SDK-owned file descriptors"
            ]
            Attachment.record(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), as: UTF8.self),
                named: "s34-background-removal-observation.json")
        } catch {
            // Failure cleanup requests only the exact tasks we created. Actual
            // callback/source closure remains the product consumer's work.
            for task in await sdk.snapshot().created { await sdk.requestStop(task) }
            await sdk.invalidate()
            do {
                try await backgroundRemovalWait("failed-probe actual invalidation") { await sdk.snapshot().forwarderEnded }
                await sdk.joinForwarder()
            } catch { Issue.record("Actual SDK cleanup remains unconfirmed: \(error)") }
            throw error
        }
    }
}

private nonisolated struct BackgroundRemovalResumeObservation: Sendable {
    let binding: BackgroundMediaTaskBinding
    let tasks: BackendOutcome<[BackgroundMediaTaskObservation]>
    let terminal: BackendOutcome<BackgroundMediaSDKTerminal>
    let result: BackendOutcome<BackgroundMediaTaskBinding>
}

private nonisolated struct BackgroundRemovalSDKObservation: Sendable {
    let created: [BackgroundMediaTaskBinding]
    let resumes: [BackgroundRemovalResumeObservation]
    let stops: [BackgroundMediaTaskBinding]
    let events: [BackgroundMediaSDKEvent]
    let forwarderEnded: Bool
}

/// Observes the real port and forwards each unchanged numbered event once. No
/// terminal, finishedEvents or invalidation event is generated by this wrapper.
private actor BackgroundRemovalNativeAudit: BackgroundMediaSessionPort {
    let base: BackgroundMediaSession
    private var taken = false
    private var created: [BackgroundMediaTaskBinding] = []
    private var resumes: [BackgroundRemovalResumeObservation] = []
    private var stops: [BackgroundMediaTaskBinding] = []
    private var observed: [BackgroundMediaSDKEvent] = []
    private var forwarder: Task<Void, Never>?
    private var forwarderEnded = false
    init(base: BackgroundMediaSession) { self.base = base }
    func events() async throws -> AsyncStream<BackgroundMediaSDKEvent> {
        guard !taken else { throw BackendContractError.wrongStage }
        taken = true
        let incoming = try await base.events()
        let pair = AsyncStream<BackgroundMediaSDKEvent>.makeStream()
        forwarder = Task.detached { [weak self] in
            for await event in incoming {
                await self?.record(event)
                pair.continuation.yield(event)
            }
            pair.continuation.finish()
            await self?.ended()
        }
        return pair.stream
    }
    func createSuspended(_ intent: BackgroundMediaTaskIntent, request: URLRequest,
                         upload: BackgroundMediaUploadFile?) async -> BackendOutcome<BackgroundMediaTaskBinding> {
        let result = await base.createSuspended(intent, request: request, upload: upload)
        if case .succeeded(let task) = result { created.append(task) }
        return result
    }
    func enumerate() async -> BackendOutcome<[BackgroundMediaTaskObservation]> { await base.enumerate() }
    func observeTerminal(_ binding: BackgroundMediaTaskBinding) async -> BackendOutcome<BackgroundMediaSDKTerminal> {
        await base.observeTerminal(binding)
    }
    func resume(_ binding: BackgroundMediaTaskBinding, permit: BackgroundMediaStrictPermit,
                captureAuthorization: CaptureMediaResumeAuthorization) async -> BackendOutcome<BackgroundMediaTaskBinding> {
        let tasks = await base.enumerate()
        let terminal = await base.observeTerminal(binding)
        let result = await base.resume(binding, permit: permit, captureAuthorization: captureAuthorization)
        resumes.append(.init(binding: binding, tasks: tasks, terminal: terminal, result: result))
        return result
    }
    func requestStop(_ binding: BackgroundMediaTaskBinding) async { stops.append(binding); await base.requestStop(binding) }
    func invalidate() async { await base.invalidate() }
    func snapshot() -> BackgroundRemovalSDKObservation {
        .init(created: created, resumes: resumes, stops: stops, events: observed, forwarderEnded: forwarderEnded)
    }
    func joinForwarder() async { await forwarder?.value }
    private func record(_ event: BackgroundMediaSDKEvent) { observed.append(event) }
    private func ended() { forwarderEnded = true }
}

private nonisolated struct BackgroundRemovalFDObservation: Sendable {
    let descriptor: Int32
    let result: Int32
    let error: Int32
}
private nonisolated struct BackgroundRemovalFinishObservation: Sendable {
    let lease: OriginalReadLease
    let terminal: BackgroundMediaSDKTerminal
    let closure: BackgroundMediaOwnerClosure
    let before: ManagedUploadSourceResources
    let after: ManagedUploadSourceResources
    let descriptors: [BackgroundRemovalFDObservation]
    let durableTerminalBeforeFinish: BackgroundMediaSDKTerminal?
    let durableClosureBeforeFinish: BackgroundMediaOwnerClosure?
    let readersBeforeFinish: [OriginalReadLease]
}
private nonisolated struct BackgroundRemovalSourceObservation: Sendable {
    let created: [ManagedUploadSourceIdentity]
    let leases: [OriginalReadLease]
    let exported: [BackgroundMediaUploadFile]
    let finishes: [BackgroundRemovalFinishObservation]
}

private actor BackgroundRemovalSourceAudit: BackgroundMediaUploadSourcePort {
    let base: ManagedUploadSource
    let store: SQLiteRecordingStore
    private var created: [ManagedUploadSourceIdentity] = []
    private var leases: [OriginalReadLease] = []
    private var exported: [BackgroundMediaUploadFile] = []
    private var finishes: [BackgroundRemovalFinishObservation] = []
    init(base: ManagedUploadSource, store: SQLiteRecordingStore) { self.base = base; self.store = store }
    func create(from lease: OriginalReadLease, id: ManagedUploadSourceID) async throws -> ManagedUploadSourceIdentity {
        let result = try await base.create(from: lease, id: id)
        created.append(result); leases.append(lease)
        return result
    }
    func uploadFile(for identity: ManagedUploadSourceIdentity, lease: OriginalReadLease) async throws -> BackgroundMediaUploadFile {
        let result = try await base.uploadFile(for: identity, lease: lease)
        exported.append(result)
        return result
    }
    func retain(_ identity: ManagedUploadSourceIdentity, lease: OriginalReadLease, for binding: BackgroundMediaTaskBinding) async throws {
        try await base.retain(identity, lease: lease, for: binding)
    }
    func finish(_ identity: ManagedUploadSourceIdentity, lease: OriginalReadLease,
                terminal: BackgroundMediaSDKTerminal) async throws -> BackgroundMediaOwnerClosure {
        let before = await base.resources()
        let media = try await mediaSnapshot(store)
        let task = media.backgroundTasks.first { $0.binding == terminal.binding }
        let readers = try await mediaOriginalSnapshot(store).logicalOriginals.first { $0.original == lease.original }?.readers ?? []
        let result = try await base.finish(identity, lease: lease, terminal: terminal)
        // Probe immediately after actual close return, before further audit
        // I/O can reuse these descriptor numbers. A mismatch fails the probe.
        let descriptors = before.descriptors.map { descriptor in
            let observed = fcntl(descriptor, F_GETFD)
            return BackgroundRemovalFDObservation(descriptor: descriptor, result: observed, error: observed == -1 ? errno : 0)
        }
        let after = await base.resources()
        finishes.append(.init(lease: lease, terminal: terminal, closure: result, before: before, after: after,
            descriptors: descriptors, durableTerminalBeforeFinish: task?.terminal,
            durableClosureBeforeFinish: task?.ownerClosure, readersBeforeFinish: readers))
        return result
    }
    func snapshot() -> BackgroundRemovalSourceObservation {
        .init(created: created, leases: leases, exported: exported, finishes: finishes)
    }
}

private actor BackgroundRemovalUnusedPhotos: PhotoLibraryPort {
    private var calls = 0
    func authorizationStatus(for access: PhotoLibraryAccess) -> PhotoLibraryAuthorization { calls += 1; return .denied }
    func requestAuthorization(for access: PhotoLibraryAccess) -> PhotoLibraryAuthorization { calls += 1; return .denied }
    func add(_ command: PhotoLibraryAddCommand) -> PhotoRegistrationResult {
        calls += 1; return .init(intent: command.registration.intent, outcome: .unknown(localIdentifier: nil))
    }
    func lookup(_ identifier: PhotoAssetIdentifier) -> PhotoLibraryLookupResult {
        calls += 1; return .init(identifier: identifier, authorization: .denied, presence: .unavailable)
    }
    func callCount() -> Int { calls }
}

private nonisolated struct BackgroundRemovalEmptyVault: RegistrationVaultPort {
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

private nonisolated enum BackgroundRemovalProbeError: Error { case timeout(String) }
@MainActor private func backgroundRemovalWait(_ label: String, _ condition: @MainActor () async throws -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(30))
    while !(try await condition()) {
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { throw BackgroundRemovalProbeError.timeout(label) }
        try await Task.sleep(for: .milliseconds(25))
    }
}
private nonisolated func backgroundRemovalParent() throws -> URL {
    let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent("FrameRelay-background-removal-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    return parent
}
private nonisolated func backgroundRemovalHash(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
}
