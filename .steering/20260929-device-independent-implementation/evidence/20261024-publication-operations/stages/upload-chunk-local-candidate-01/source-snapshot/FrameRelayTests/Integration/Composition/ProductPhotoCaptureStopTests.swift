import Darwin
import Foundation
import Synchronization
import Testing
@testable import FrameRelay

/// New dedicated product roots and raw synthetic cached bytes only. The Photos
/// port below is the existing controlled test port. Its injected completion is
/// not native PhotoKit success, formal media quality, or all-media stop proof.
@Suite(.serialized) @MainActor struct ProductPhotoCaptureStopTests {
    @Test(arguments: [false, true])
    func anUnregisteredPhotoFreeRootIsReadyWithoutCreatingAStoreUUID(recordingOnly: Bool) async throws {
        let f = try await photoCaptureStopUnregisteredFixture(), owner = try captureBoundaryOwner()
        if recordingOnly {
            // Existing recording metadata is a synthetic typed fixture input;
            // no original file, media SDK or Photos intent is created.
            let recording = try CaptureFixture(clip: "photo-free-recording-" + UUID().uuidString)
            let result = try syntheticResult(recording)
            guard case .committed = await f.services.store.execute(.commitIntent(recording.token(1), expectedRevision: 0, recording.intent)),
                  case .committed = await f.services.store.execute(.commitResult(recording.token(4), expectedRevision: 1, result)) else {
                throw BackendContractError.notCommitted
            }
        }
        let before = try await mediaSnapshot(f.services.store), originals = try await mediaOriginalSnapshot(f.services.store)
        let recordings = await f.services.store.loadRecordings()
        guard case .loaded(let saved) = recordings else { throw BackendContractError.unavailable }
        try #require(before.storeIdentity == nil && before.photoRegistrations.isEmpty
            && before.photoSaveBatches.isEmpty && before.temporaryMedia.isEmpty
            && before.registrationIntents.isEmpty && before.registrations.isEmpty)
        #expect(saved.revision == before.revision && saved.recordings.count == (recordingOnly ? 1 : 0))
        f.capture.begin(owner, phases: [.recording]); defer { f.capture.end(owner) }
        let admission = f.capture.snapshot()
        #expect(await f.factory.waitForPhotoLocalStop(owner: owner) == .ready)
        #expect(try await mediaSnapshot(f.services.store) == before)
        #expect(await f.services.store.loadRecordings() == recordings)
        let after = try await mediaOriginalSnapshot(f.services.store)
        #expect(after.revision == originals.revision && after.originals == originals.originals
            && after.logicalOriginals == originals.logicalOriginals && f.capture.snapshot() == admission)
        #expect(await f.factory.openedOwners == 0)
        try await photoCaptureStopRequireNoPhotoCalls(f.photos)
    }

    @Test func aNilUUIDDoesNotHideAnUnresolvedOldPhotoUse() async throws {
        let f = try await photoCaptureStopUnregisteredFixture(), owner = try captureBoundaryOwner()
        let registration = try await mediaRegister(f.services.store)
        let bytes = Data(repeating: 0x63, count: 4096), content = try renditionContent(bytes)
        let original = OriginalContent(capture: .init(rawValue: "unresolved-photo-" + UUID().uuidString), generation: .init(rawValue: 1), content: content)
        let rendition = RenditionIdentity(original: original, inputLogIdentity: "synthetic-not-log", transformAssetIdentity: "no-formal-proof",
            transformAssetVersion: "old-photo-use-fixture", outputConfigurationIdentity: "unowned-raw-bytes", conversionVersion: "fixture-only",
            rendition: .init(rawValue: UUID().uuidString), deliveryContent: content, publicationGeneration: .init(rawValue: 1))
        _ = try await mediaCommit(f.services.store, .publication(mediaPublication(rendition, registration: registration)))
        let root = f.services.run.url.appendingPathComponent("unresolved-photo-cache", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let media = TemporaryMediaID(rawValue: UUID().uuidString), leaf = try TemporaryMediaLeaf.make(contentType: "video/quicktime")
        let state = TemporaryMediaState(id: media, rendition: rendition, registration: registration,
            capturedAt: RenditionFixture.capturedAt, leaf: leaf, contentType: "video/quicktime", directoryIdentity: try photoCaptureStopFileIdentity(root))
        _ = try await mediaCommit(f.services.store, .temporary(command: .init(rawValue: UUID().uuidString), value: .create(state)))
        let file = root.appendingPathComponent(leaf); try bytes.write(to: file, options: .withoutOverwriting)
        _ = try await mediaCommit(f.services.store, .temporary(command: .init(rawValue: UUID().uuidString), value: .fileCreated(media, try photoCaptureStopFileIdentity(file))))
        _ = try await mediaCommit(f.services.store, .temporary(command: .init(rawValue: UUID().uuidString), value: .stored(media, try .init(lowerBound: 0, upperBound: content.byteCount))))
        _ = try await mediaCommit(f.services.store, .temporary(command: .init(rawValue: UUID().uuidString), value: .verified(media, content)))
        let leases = RenditionReadLeases(store: f.services.store)
        let current = try #require(try await mediaSnapshot(f.services.store).temporaryMedia.first)
        let use = try await leases.acquireTemporary(current, purpose: .photoHandoff,
            usageID: .init(rawValue: UUID().uuidString), owner: "unresolved-old-photo-owner")
        let before = try await mediaSnapshot(f.services.store)
        try #require(before.storeIdentity == nil && before.photoRegistrations.isEmpty && before.temporaryMedia[0].usages == [use])
        f.capture.begin(owner, phases: [.recording]); defer { f.capture.end(owner) }
        #expect(await f.factory.waitForPhotoLocalStop(owner: owner) == .unknown)
        #expect(try await mediaSnapshot(f.services.store) == before)
        #expect(try await mediaOriginalSnapshot(f.services.store).logicalOriginals[0].mediaReaders == [use.lease])
        #expect(try Data(contentsOf: file) == bytes)
        #expect(await f.factory.openedOwners == 0)
        try await photoCaptureStopRequireNoPhotoCalls(f.photos)
        // No UUID bootstrap, old-owner adoption, fake terminal or release.
        // This new root deliberately retains its unresolved reader and bytes.
    }

    @Test func heldBeforeSDKDrainsWithoutEndingCaptureOrCancellingTheBatch() async throws {
        let f = try await PhotoCaptureStopFixture.make(count: 2), owner = try captureBoundaryOwner()
        let admission = f.capture
        let batch = f.batch(), request = try await f.request(indices: [0, 1])
        await f.photos.beforeNextGuardedStart { admission.begin(owner, phases: [.recording]) }
        #expect(await batch.submit(request) == .accepted)
        try await photoCaptureStopEventually {
            let snapshot = try? await mediaSnapshot(f.services.store)
            let attempts = await f.photos.guardedAttempts
            return snapshot?.photoRegistrations.count == 1 && f.capture.snapshot().owners[owner] != nil
                && attempts == 1
        }
        let first = try await mediaSnapshot(f.services.store), record = try #require(first.photoRegistrations.first)
        let media = try #require(first.temporaryMedia.first { $0.id == record.registration.intent.media })
        #expect(record.outcome == nil && record.usageTerminal == nil && media.usages.count == 1)
        #expect(await f.photos.commands.isEmpty)
        defer { f.capture.end(owner) }
        // No capture end/wake is issued before this joins. The pending claim's
        // cancellation must wake its held save and drain the exact same use.
        let stopped = PhotoCaptureStopBox<Bool>()
        let stop = Task { let value = await batch.stopLiveStartsForCapture(); stopped.set(value); return value }
        try await photoCaptureStopEventually { stopped.value != nil }
        #expect(await stop.value)
        #expect(await f.factory.waitForPhotoLocalStop(owner: owner) == .ready)
        await batch.waitForIdle()
        let final = try await mediaSnapshot(f.services.store), saved = try #require(final.photoRegistrations.first)
        #expect(f.capture.snapshot().owners[owner] == [.recording])
        #expect(saved.registration == record.registration && saved.outcome == .notAttempted(.rejected))
        #expect(saved.usageTerminal?.terminal.termination == .notStarted && saved.terminalUsageRelease != nil)
        #expect(final.temporaryMedia.first { $0.id == media.id }?.usages.isEmpty == true)
        #expect(final.temporaryMedia.first { $0.id == media.id }?.reclaimed == false)
        #expect(final.photoSaveBatches[0].targets.count == 2)
        if case .queued = final.photoSaveBatches[0].targets[1].status {} else { Issue.record("REC changed the untouched child decision") }
        photoCaptureStopRequireNoPersonCancellation(final)
        try await photoCaptureStopRequireLocalProof(f, expectedRecords: 1)
        #expect(await f.photos.commands.isEmpty)
        try f.requireSourceBytes()
    }

    @Test(arguments: [false, true])
    func acceptedSDKMustCompleteAndReleaseItsFDAndUseEvenWhenTheExternalResultIsUnknown(unknown: Bool) async throws {
        let f = try await PhotoCaptureStopFixture.make(unknown: unknown), owner = try captureBoundaryOwner()
        let batch = f.batch(), request = try await f.request()
        await f.photos.holdAdd()
        defer { f.capture.end(owner); Task { await f.photos.finishAdd() } }
        #expect(await batch.submit(request) == .accepted)
        try await photoCaptureStopEventually { await f.photos.commands.count == 1 }
        let command = try #require(await f.photos.commands.first)
        f.capture.begin(owner, phases: [.recording])
        let result = PhotoCaptureStopBox<CaptureMediaLocalStop>()
        let task = Task {
            let value: CaptureMediaLocalStop
            if await batch.stopLiveStartsForCapture() { value = await f.factory.waitForPhotoLocalStop(owner: owner) }
            else { value = .unknown }
            result.set(value); return value
        }
        for _ in 0..<12 { await Task.yield() }
        #expect(result.value == nil)
        let during = try await mediaSnapshot(f.services.store), active = try #require(during.photoRegistrations.first)
        #expect(active.outcome == nil && active.usageTerminal == nil && active.terminalUsageRelease == nil)
        #expect(during.temporaryMedia[0].usages.count == 1 && !photoCaptureStopWitnessInvalid(command))
        await f.photos.finishAdd()
        try await photoCaptureStopEventually { result.value != nil }
        #expect(await task.value == .ready)
        await batch.waitForIdle()
        let final = try await mediaSnapshot(f.services.store), saved = try #require(final.photoRegistrations.first)
        #expect(saved.outcome == (unknown ? .unknown(localIdentifier: nil) : .succeeded(localIdentifier: nil)))
        #expect(saved.usageTerminal?.terminal.termination == .sdkCompleted && saved.terminalUsageRelease != nil)
        #expect(photoCaptureStopWitnessInvalid(command))
        photoCaptureStopRequireNoPersonCancellation(final)
        try await photoCaptureStopRequireLocalProof(f, expectedRecords: 1)
        #expect(await f.photos.commands.count == 1)
        if unknown { #expect(!final.temporaryMedia[0].reclaimed) }
        try f.requireSourceBytes()
    }

    @Test func anAlreadyInflightPreparationIsJoinedAndReleasedWithoutCreatingAPhotoIntent() async throws {
        let f = try await PhotoCaptureStopFixture.make(), owner = try captureBoundaryOwner(), gate = PhotoCaptureStopGate()
        let preparation = PhotoCaptureStopPreparation(base: f.execution, gate: gate), batch = f.batch(execution: preparation)
        let request = try await f.request()
        #expect(await batch.submit(request) == .accepted)
        await gate.waitUntilHeld()
        f.capture.begin(owner, phases: [.recording])
        defer { f.capture.end(owner); Task { await gate.release() } }
        let stopped = PhotoCaptureStopBox<Bool>()
        let task = Task { let value = await batch.stopLiveStartsForCapture(); stopped.set(value); return value }
        for _ in 0..<12 { await Task.yield() }
        let held = try await mediaSnapshot(f.services.store)
        #expect(stopped.value == nil && held.photoRegistrations.isEmpty && held.temporaryMedia[0].usages.count == 1)
        await gate.release()
        try await photoCaptureStopEventually { stopped.value != nil }
        #expect(await task.value)
        #expect(await f.factory.waitForPhotoLocalStop(owner: owner) == .ready)
        await batch.waitForIdle()
        let final = try await mediaSnapshot(f.services.store)
        #expect(final.photoRegistrations.isEmpty && final.temporaryMedia[0].usages.isEmpty)
        // Existing last-use reclamation may remove this new cache; this is not
        // a person cancellation or a new Photos result/retention policy.
        photoCaptureStopRequireNoPersonCancellation(final)
        if case .queued = final.photoSaveBatches[0].targets[0].status {} else { Issue.record("Prepared stop manufactured a child result") }
        #expect(await f.photos.commands.isEmpty)
        #expect(try await mediaOriginalSnapshot(f.services.store).logicalOriginals.allSatisfy { $0.mediaReaders.isEmpty })
        try f.requireSourceBytes()
    }

    @Test(arguments: ["owner", "registry"])
    func aWaitCannotReturnReadyForAnObsoleteCaptureOwnerOrANewPhotoOwner(change: String) async throws {
        let f = try await PhotoCaptureStopFixture.make(count: change == "registry" ? 2 : 1)
        let owner = try captureBoundaryOwner(), next = try captureBoundaryOwner(), batch = f.batch(), request = try await f.request()
        await f.photos.holdAdd()
        defer { f.capture.end(owner); f.capture.end(next); Task { await f.photos.finishAdd() } }
        #expect(await batch.submit(request) == .accepted)
        try await photoCaptureStopEventually { await f.photos.commands.count == 1 }
        f.capture.begin(owner, phases: [.recording])
        let result = PhotoCaptureStopBox<CaptureMediaLocalStop>()
        let task = Task { let value = await f.factory.waitForPhotoLocalStop(owner: owner); result.set(value); return value }
        for _ in 0..<12 { await Task.yield() }
        #expect(result.value == nil)
        var prepared: ProductRenditionSource?
        if change == "owner" { f.capture.end(owner); f.capture.begin(next, phases: [.recording]) }
        else {
            let source = try await f.factory.photoSource(f.targets[1])
            let added = try await f.factory.preparePhoto(source)
            _ = await f.factory.photoCoordinator(owner: added.owner, identity: source.storeIdentity)
            prepared = added
        }
        await f.photos.finishAdd()
        try await photoCaptureStopEventually { result.value != nil }
        let old = await task.value
        #expect(old == (change == "owner" ? .cancelled : .unknown))
        await batch.waitForIdle()
        if let prepared { #expect(await f.factory.release(prepared)) }
        #expect(await f.factory.waitForPhotoLocalStop(owner: change == "owner" ? next : owner) == .ready)
        photoCaptureStopRequireNoPersonCancellation(try await mediaSnapshot(f.services.store))
        try f.requireSourceBytes()
    }

    @Test func anUnknownLocalTerminalLookupRemainsWaitingAfterSDKCompletionAndFDClosure() async throws {
        let f = try await PhotoCaptureStopFixture.make(hideTerminalLookup: true), owner = try captureBoundaryOwner()
        let batch = f.batch(), request = try await f.request()
        await f.photos.holdAdd()
        defer { f.capture.end(owner); Task { await f.photos.finishAdd() } }
        #expect(await batch.submit(request) == .accepted)
        try await photoCaptureStopEventually { await f.photos.commands.count == 1 }
        let command = try #require(await f.photos.commands.first)
        f.capture.begin(owner, phases: [.recording])
        await f.photos.finishAdd(); await batch.waitForIdle()
        _ = await batch.stopLiveStartsForCapture()
        #expect(await f.factory.waitForPhotoLocalStop(owner: owner) == .unknown)
        let state = try await mediaSnapshot(f.services.store), record = try #require(state.photoRegistrations.first)
        #expect(record.usageTerminal != nil && photoCaptureStopWitnessInvalid(command))
        let stillOwned = state.temporaryMedia[0].usages.contains(record.registration.mediaUse)
        let original = try #require(try await mediaOriginalSnapshot(f.services.store).logicalOriginals.first)
        #expect(original.mediaReaders.contains(record.registration.mediaUse.lease) == stillOwned)
        #expect(record.terminalUsageRelease != nil || stillOwned)
        photoCaptureStopRequireNoPersonCancellation(state)
        #expect(await f.photos.commands.count == 1)
        // Actual recovery may already have retired the use. Its unknown local
        // commit lookup still cannot be promoted to ready. The test repairs no
        // journal and never creates a release from the SDK callback alone.
        try f.requireSourceBytes()
    }

    @Test(arguments: ["stop", "leave"])
    func aLatePhotoDrainCannotStartAnOldRECOrClearTheNextREC(action: String) async throws {
        let f = try await PhotoCaptureStopFixture.make(), batch = f.batch(), request = try await f.request()
        await f.photos.holdAdd()
        defer { Task { await f.photos.finishAdd() } }
        #expect(await batch.submit(request) == .accepted)
        try await photoCaptureStopEventually { await f.photos.commands.count == 1 }
        let background = ProductBackgroundMediaFactory(library: f.library, captureAdmission: f.capture)
        let entered = PhotoCaptureStopOwners(), factory = f.factory
        let boundary = ProductCaptureMediaBoundary(background: background, photoLocalStop: { owner in
            entered.append(owner)
            guard await batch.stopLiveStartsForCapture() else { return .unknown }
            return await factory.waitForPhotoLocalStop(owner: owner)
        })
        let capture = try CaptureFixture(), first = ProductCaptureTestDevice(fixture: capture), second = ProductCaptureTestDevice(fixture: capture)
        let devices = ProductCaptureTestDeviceFactory([first, second]), save = ProductCaptureTestSave()
        let model = ProductCaptureCoordinator(preferences: ProductCaptureTestPreferences(fixture: capture),
            makeDevice: { await devices.make(candidate: $0) }, save: save, bindOriginal: { _ in true }, didSave: {},
            mediaBoundary: boundary, calendarNow: { Date() }, captureNow: { capture.time })
        model.enterCapture(); await model.load(); await model.prepare()
        try #require(model.canRecord)
        let oldDone = PhotoCaptureStopBox<Bool>(), newDone = PhotoCaptureStopBox<Bool>()
        let old = Task { await model.record(); oldDone.set(true) }
        try await photoCaptureStopEventually { entered.values.count == 1 && model.isStarting }
        let oldOwner = try #require(entered.values.first)
        if action == "stop" { await model.stop() } else { await model.leaveCapture() }
        #expect(f.capture.snapshot().owners[oldOwner] == nil)
        model.enterCapture(); await model.prepare()
        try #require(model.canRecord)
        let new = Task { await model.record(); newDone.set(true) }
        try await photoCaptureStopEventually { entered.values.count == 2 && model.isStarting }
        let newOwner = entered.values[1]
        #expect(newOwner != oldOwner && f.capture.snapshot().owners[newOwner] != nil)
        #expect(await first.startCount == 0)
        #expect(await second.startCount == 0)
        await f.photos.finishAdd()
        try await photoCaptureStopEventually { oldDone.value == true && newDone.value == true }
        await old.value; await new.value
        try await photoCaptureStopEventually { model.capture?.phase == .recording }
        #expect(model.capture?.context == newOwner.context)
        #expect(await first.startCount == 0)
        #expect(await second.startCount == 1)
        #expect(f.capture.snapshot().owners[oldOwner] == nil && f.capture.snapshot().owners[newOwner] != nil)
        await model.stop()
        try await photoCaptureStopEventually { !model.isBusy }
        await model.leaveCapture(); await batch.waitForIdle()
        #expect(!f.capture.snapshot().isHeld)
        photoCaptureStopRequireNoPersonCancellation(try await mediaSnapshot(f.services.store))
        try await photoCaptureStopRequireLocalProof(f, expectedRecords: 1)
        try f.requireSourceBytes()
    }
}

private nonisolated final class PhotoCaptureStopBox<Value: Sendable>: Sendable {
    private let state = Mutex<Value?>(nil)
    func set(_ value: Value) { state.withLock { $0 = value } }
    var value: Value? { state.withLock { $0 } }
}
private nonisolated final class PhotoCaptureStopOwners: Sendable {
    private let state = Mutex<[CaptureMediaOwner]>([])
    func append(_ value: CaptureMediaOwner) { state.withLock { $0.append(value) } }
    var values: [CaptureMediaOwner] { state.withLock { $0 } }
}
@MainActor private func photoCaptureStopEventually(_ condition: @MainActor () async throws -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !(try await condition()) {
        guard ContinuousClock.now < deadline else { throw BackendContractError.unavailable }
        try await Task.sleep(for: .milliseconds(10))
    }
}
private nonisolated func photoCaptureStopWitnessInvalid(_ command: PhotoLibraryAddCommand) -> Bool {
    guard let witness = command.media.photoReadWitness, !witness.isCurrent else { return false }
    guard let current = try? OriginalFileFingerprint(descriptor: witness.fileDescriptor) else { return true }
    return current != witness.fingerprint
}
private nonisolated func photoCaptureStopRequireNoPersonCancellation(_ snapshot: BackendStoreSnapshot) {
    #expect(snapshot.photoSaveBatches.allSatisfy { batch in batch.targets.allSatisfy { child in
        if case .notProcessed(let record) = child.status { return record.reason != .cancelled }; return true
    } })
    #expect(snapshot.requests.allSatisfy { $0.intent != .cancelled })
}
@MainActor private func photoCaptureStopRequireLocalProof(_ f: PhotoCaptureStopFixture, expectedRecords: Int) async throws {
    let snapshot = try await mediaSnapshot(f.services.store), originals = try await mediaOriginalSnapshot(f.services.store)
    try #require(snapshot.storeIdentity == f.identity && snapshot.revision == originals.revision
        && snapshot.photoRegistrations.count == expectedRecords)
    #expect(snapshot.temporaryMedia.allSatisfy { $0.usages.filter { $0.usage.purpose == .photoHandoff }.isEmpty })
    #expect(originals.logicalOriginals.allSatisfy { $0.mediaReaders.isEmpty && $0.readers.isEmpty })
    for record in snapshot.photoRegistrations {
        let terminal = try #require(record.usageTerminal), release = try #require(record.terminalUsageRelease)
        #expect(record.registration.expectedStoreIdentity == f.identity && terminal.expectedStoreIdentity == f.identity
            && release.expectedStoreIdentity == f.identity)
        #expect(PhotoSaveBatchValueValidation.exact(terminal.terminal.intent, record.registration.intent)
            && PhotoSaveBatchValueValidation.exact(release.release.terminal, terminal.terminal))
        let terminalMutation = BackendStoreMutation(expectedRevision: terminal.commit.previousRevision,
            change: .photo(command: terminal.command, value: .terminal(terminal.terminal)), expectedStoreIdentity: terminal.expectedStoreIdentity)
        let releaseMutation = BackendStoreMutation(expectedRevision: release.commit.previousRevision,
            change: .photo(command: release.command, value: .releaseTerminalUsage(release.release)), expectedStoreIdentity: release.expectedStoreIdentity)
        #expect(await f.services.store.lookupCommit(record.registration.mutation) == .committed(record.registration.commit))
        #expect(await f.services.store.lookupCommit(terminalMutation) == .committed(terminal.commit))
        #expect(await f.services.store.lookupCommit(releaseMutation) == .committed(release.commit))
    }
}

private actor PhotoCaptureStopGate {
    private var held = false, released = false
    private var arrival: CheckedContinuation<Void, Never>?, blocked: CheckedContinuation<Void, Never>?
    func hold() async {
        held = true; arrival?.resume(); arrival = nil
        if !released { await withCheckedContinuation { blocked = $0 } }
    }
    func waitUntilHeld() async { if held { return }; await withCheckedContinuation { arrival = $0 } }
    func release() { released = true; blocked?.resume(); blocked = nil }
}
private actor PhotoCaptureStopPreparation: PhotoSaveBatchExecutionPort {
    let base: ProductPhotoSaveBatch; let gate: PhotoCaptureStopGate
    init(base: ProductPhotoSaveBatch, gate: PhotoCaptureStopGate) { self.base = base; self.gate = gate }
    func source(for target: LibraryRenditionTarget) async throws -> PhotoSaveSource { try await base.source(for: target) }
    func prepare(_ target: PhotoSaveBatchTarget) async throws -> any PreparedPhotoSavePort {
        let value = try await base.prepare(target); await gate.hold(); return value
    }
}
private actor PhotoCaptureStopProofStore: MediaOperationStorePort {
    let base: SQLiteRecordingStore
    init(base: SQLiteRecordingStore) { self.base = base }
    func load() async -> BackendStoreLoadResult { await base.load() }
    func commit(_ mutation: BackendStoreMutation) async -> BackendCommitResult { await base.commit(mutation) }
    func lookupCommit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        if case .photo(_, .terminal) = mutation.change { return .unknown }
        if case .photo(_, .releaseTerminalUsage) = mutation.change { return .unknown }
        return await base.lookupCommit(mutation)
    }
    func performPhotoSaveIfCurrent(_ command: PhotoLibraryAddCommand, action: @Sendable () -> Void) async -> Bool {
        await base.performPhotoSaveIfCurrent(command, action: action)
    }
}

/// No movie encoder or SDK is needed: the controlled port consumes raw cached
/// bytes with explicitly synthetic publication/distribution contract inputs.
@MainActor private struct PhotoCaptureStopFixture {
    let library: ProductLibraryFactory; let services: ProductLibraryServices
    let identity: RegistrationStoreIdentity
    let factory: ProductRenditionFactory; let capture: CaptureMediaAdmission; let photos: PhotoBatchLibrary
    let execution: ProductPhotoSaveBatch; let targets: [LibraryRenditionTarget]; let sources: [URL]; let bytes: Data

    static func make(count: Int = 1, unknown: Bool = false, hideTerminalLookup: Bool = false) async throws -> Self {
        let photos = PhotoBatchLibrary(outcomes: [unknown ? .unknown(localIdentifier: nil) : .succeeded(localIdentifier: nil)])
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("FrameRelay-photo-capture-stop-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        let library = ProductLibraryFactory(supportDirectory: parent, photoLibrary: photos), services = try await library.open()
        let registration = try await inventoryRegister(services.store)
        let identity = try #require(try await mediaSnapshot(services.store).storeIdentity)
        let bytes = Data((0..<4096).map { UInt8($0 % 251) }), content = try renditionContent(bytes)
        var targets: [LibraryRenditionTarget] = [], sources: [URL] = []
        for index in 0..<count {
            let original = OriginalContent(capture: .init(rawValue: "photo-stop-\(index)-" + UUID().uuidString), generation: .init(rawValue: 1), content: content)
            let rendition = RenditionIdentity(original: original, inputLogIdentity: "synthetic-not-log", transformAssetIdentity: "no-formal-proof",
                transformAssetVersion: "capture-stop-test", outputConfigurationIdentity: "raw-controlled-photo-input", conversionVersion: "fixture-only",
                rendition: .init(rawValue: UUID().uuidString), deliveryContent: content, publicationGeneration: .init(rawValue: 1))
            _ = try await mediaCommit(services.store, .publication(mediaPublication(rendition, registration: registration.server.registration)))
            let leases = RenditionReadLeases(store: services.store)
            let lease = try await leases.acquire(rendition: rendition, registration: registration.server.registration,
                operation: .init(rawValue: UUID().uuidString), context: .transport(.init(rawValue: UUID().uuidString)))
            let operation = MediaOperationID(rawValue: UUID().uuidString)
            let distribution = DistributionReceipt(operation: operation, rendition: rendition, registration: registration.server.registration,
                commit: .init(key: .distribution(operation, rendition, registration.server.registration), previousRevision: 0, committedRevision: 1))
            _ = try await mediaCommit(services.store, .distribution(.init(command: .init(rawValue: UUID().uuidString),
                lease: lease, observation: .init(rawValue: 1), result: .succeeded(distribution))))
            try await leases.release(lease)
            let root = try ProductRenditionFactory.root(for: original, run: services.run)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data().write(to: root.appendingPathComponent("owner.lock"), options: .withoutOverwriting)
            let media = TemporaryMediaID(rawValue: UUID().uuidString), leaf = try TemporaryMediaLeaf.make(contentType: "video/quicktime")
            let state = TemporaryMediaState(id: media, rendition: rendition, registration: registration.server.registration,
                capturedAt: RenditionFixture.capturedAt, leaf: leaf, contentType: "video/quicktime", directoryIdentity: try photoCaptureStopFileIdentity(root))
            _ = try await mediaCommit(services.store, .temporary(command: .init(rawValue: UUID().uuidString), value: .create(state)))
            let file = root.appendingPathComponent(leaf); try bytes.write(to: file, options: .withoutOverwriting)
            _ = try await mediaCommit(services.store, .temporary(command: .init(rawValue: UUID().uuidString), value: .fileCreated(media, try photoCaptureStopFileIdentity(file))))
            _ = try await mediaCommit(services.store, .temporary(command: .init(rawValue: UUID().uuidString), value: .stored(media, try .init(lowerBound: 0, upperBound: content.byteCount))))
            _ = try await mediaCommit(services.store, .temporary(command: .init(rawValue: UUID().uuidString), value: .verified(media, content)))
            let source = services.run.url.appendingPathComponent("retained-synthetic-source-\(index)-" + UUID().uuidString + ".bin")
            try bytes.write(to: source, options: .withoutOverwriting); sources.append(source)
            targets.append(.init(original: original, destination: registration.server.registration.destination))
        }
        let capture = CaptureMediaAdmission()
        let store: any MediaOperationStorePort = hideTerminalLookup ? PhotoCaptureStopProofStore(base: services.store) : services.store
        let factory = ProductRenditionFactory(services: services, scopes: .init(leases: .init(store: services.store)), photoStore: store, photoCaptureStart: capture)
        return .init(library: library, services: services, identity: identity, factory: factory, capture: capture, photos: photos,
            execution: .init(services: services, factory: factory, capture: capture), targets: targets, sources: sources, bytes: bytes)
    }
    func batch(execution: (any PhotoSaveBatchExecutionPort)? = nil) -> PhotoSaveBatchCoordinator {
        .init(store: services.store, execution: execution ?? self.execution, network: PhotoBatchNetwork(.wiFi), capture: capture)
    }
    func request(indices: [Int] = [0]) async throws -> PhotoSaveBatchRequest {
        .init(operation: .init(rawValue: UUID().uuidString), targets: indices.map { targets[$0] }, displayedRevision: try await mediaSnapshot(services.store).revision)
    }
    func requireSourceBytes() throws { for source in sources { #expect(try Data(contentsOf: source) == bytes) } }
}
private nonisolated func photoCaptureStopFileIdentity(_ url: URL) throws -> TemporaryFileIdentity {
    var value = stat()
    guard lstat(url.path, &value) == 0, value.st_mode & S_IFMT != S_IFLNK else { throw BackendContractError.identityMismatch }
    return .init(device: Int64(value.st_dev), inode: UInt64(value.st_ino))
}

@MainActor private func photoCaptureStopUnregisteredFixture() async throws ->
    (services: ProductLibraryServices, factory: ProductRenditionFactory, capture: CaptureMediaAdmission, photos: PhotoBatchLibrary) {
    let photos = PhotoBatchLibrary(outcomes: [.unknown(localIdentifier: nil)])
    let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent("FrameRelay-photo-free-capture-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
    let library = ProductLibraryFactory(supportDirectory: parent, photoLibrary: photos), services = try await library.open()
    let capture = CaptureMediaAdmission()
    let factory = ProductRenditionFactory(services: services, scopes: .init(leases: .init(store: services.store)), photoCaptureStart: capture)
    // No registration/bootstrap API and no credential object is constructed.
    return (services, factory, capture, photos)
}
private nonisolated func photoCaptureStopRequireNoPhotoCalls(_ photos: PhotoBatchLibrary) async throws {
    let status = await photos.statusCalls, permissions = await photos.permissionCalls
    let additions = await photos.commands, lookups = await photos.lookupCalls, guarded = await photos.guardedAttempts
    #expect(status.isEmpty && permissions.isEmpty && additions.isEmpty && lookups.isEmpty && guarded == 0)
}
