import AVFoundation
import CryptoKit
import Darwin
import Foundation
import Photos
import Synchronization
import Testing
@testable import FrameRelay

/// All writes/media changes are confined to a newly created synthetic run.
/// Fake SDK boundaries below never establish PhotoKit or rendition quality.
@Suite(.serialized) @MainActor struct PhotoSaveFinalStartTests {
    @Test(arguments: StorageCandidate.allCases)
    func finalWriterUsesActualIntentAndLiveVerifiedDescriptorsWithoutRequiringALocalOriginal(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run, candidate: candidate)
            let command = try await photoFinalCommand(f)
            let logical = try #require(try await mediaOriginalSnapshot(f.rendition.store).logicalOriginals.first)
            #expect(logical.binding == nil)
            let counter = PhotoFinalCounter()
            let before = try await mediaSnapshot(f.rendition.store)
            #expect(await f.rendition.store.performPhotoSaveIfCurrent(command) { counter.increment() })
            let after = try await mediaSnapshot(f.rendition.store)
            #expect(counter.value == 1 && after == before)
            #expect(try await f.rendition.temporary.usageSnapshot(f.receipt.id).openHandles == 1)
            try await photoFinalRetireNonStart(f, command: command)
            let reopened: any MediaDiskStore = candidate == .sqlite
                ? try SQLiteRecordingStore(run: run, mode: .openExisting) : try AtomicFileRecordingStore(run: run, mode: .openExisting)
            let replay = try await mediaSnapshot(reopened), settled = try await mediaSnapshot(f.rendition.store)
            #expect(replay.photoRegistrations == settled.photoRegistrations)
        }
    }

    @Test(arguments: StorageCandidate.allCases, ["uuid", "intent", "receipt", "terminal", "result", "registration", "epoch", "nil-witness", "wrong-fd", "closed-fd"])
    func freshWriterOrDescriptorDriftRefusesTheSynchronousAction(candidate: StorageCandidate, change: String) async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run, candidate: candidate)
            let actual = try await photoFinalCommand(f)
            var registration = actual.registration, local = actual.media
            if change == "uuid" { registration.expectedStoreIdentity = .init(rawValue: UUID()) }
            if change == "receipt" {
                registration = .init(intent: registration.intent, mediaUse: registration.mediaUse,
                    commit: .init(key: registration.commit.key, previousRevision: registration.commit.previousRevision + 1,
                        committedRevision: registration.commit.committedRevision + 1),
                    expectedStoreIdentity: registration.expectedStoreIdentity,
                    directoryIdentity: registration.directoryIdentity, fileIdentity: registration.fileIdentity)
            }
            if change == "intent" || change == "epoch" {
                var usage = registration.intent.usage
                if change == "epoch" { usage.epoch = .init(rawValue: "unrecorded-writer-epoch") }
                let intent = try PhotoRegistrationIntent(operation: change == "intent"
                    ? .init(rawValue: registration.intent.operation.rawValue + "-foreign") : registration.intent.operation,
                    handoff: .init(media: registration.intent.media, rendition: registration.intent.rendition,
                        capturedAt: registration.intent.capturedAt, usage: usage))
                let use = registration.mediaUse
                registration = .init(intent: intent, mediaUse: use, commit: registration.commit,
                    expectedStoreIdentity: registration.expectedStoreIdentity,
                    directoryIdentity: registration.directoryIdentity, fileIdentity: registration.fileIdentity)
                local = .init(url: local.url, handoff: intent.handoff, contentType: local.contentType, photoReadWitness: local.photoReadWitness)
            }
            if change == "terminal" {
                try await f.media.finishPhotoMedia(f.receipt.usage)
                let terminal = try await f.media.photoUsageTerminal(actual.registration, termination: .notStarted)
                _ = try await mediaCommit(f.rendition.store, .photo(command: .init(rawValue: UUID().uuidString), value: .terminal(terminal)))
            }
            if change == "result" {
                _ = try await mediaCommit(f.rendition.store, .photo(command: .init(rawValue: UUID().uuidString),
                    value: .result(.init(intent: actual.registration.intent, outcome: .notAttempted(.rejected)))))
            }
            if change == "registration" {
                let previous = f.rendition.command.distribution.registration
                _ = try await mediaRegister(f.rendition.store, registration: .init(destination: previous.destination,
                    id: .init(rawValue: UUID().uuidString), generation: .init(rawValue: previous.generation.rawValue + 1)))
            }
            if change == "nil-witness" { local.photoReadWitness = nil }
            if change == "wrong-fd", let witness = local.photoReadWitness {
                local.photoReadWitness = .init(fileDescriptor: witness.directoryDescriptor,
                    directoryDescriptor: witness.directoryDescriptor, fingerprint: witness.fingerprint)
            }
            if change == "closed-fd" { try await f.media.finishPhotoMedia(f.receipt.usage) }
            // Some malformed commands are rejected even before reaching store.
            let counter = PhotoFinalCounter()
            if let command = try? PhotoLibraryAddCommand(registration: registration, media: local) {
                #expect(!(await f.rendition.store.performPhotoSaveIfCurrent(command) { counter.increment() }))
            }
            let additions = await f.library.additions
            #expect(counter.value == 0 && additions.isEmpty)
            if change != "terminal", change != "closed-fd" { try await f.media.finishPhotoMedia(f.receipt.usage) }
            #expect(try await f.rendition.temporary.usageSnapshot(f.receipt.id).openHandles == 0)
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func sameInodeSameSizeContentUpdateAfterFullHashIsRefusedAndNeverRepaired(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run, candidate: candidate)
            let command = try await photoFinalCommand(f)
            let witness = try #require(command.media.photoReadWitness)
            var changed = try Data(contentsOf: command.media.url)
            changed[changed.startIndex] ^= 1
            let writer = try FileHandle(forWritingTo: command.media.url)
            try writer.write(contentsOf: changed); try writer.synchronize(); try writer.close()
            var info = stat()
            try #require(lstat(command.media.url.path, &info) == 0)
            #expect(UInt64(info.st_ino) == witness.fingerprint.inode && Int64(info.st_size) == witness.fingerprint.size)
            let counter = PhotoFinalCounter()
            #expect(!(await f.rendition.store.performPhotoSaveIfCurrent(command) { counter.increment() }))
            let retained = try Data(contentsOf: command.media.url)
            #expect(counter.value == 0 && retained == changed)
            await #expect(throws: BackendContractError.identityMismatch) { try await f.media.finishPhotoMedia(f.receipt.usage) }
            #expect(try await f.rendition.temporary.usageSnapshot(f.receipt.id).openHandles == 0)
            let record = try await f.latest()
            #expect(record.results.isEmpty && record.usageTerminal == nil && record.terminalUsageRelease == nil)
        }
    }

    @Test func defaultStoreAndDefaultGuardedLibraryNeverFallBackToLegacyAdd() async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run)
            let command = try await photoFinalCommand(f)
            let defaultStore = PhotoFinalDefaultStore.make(base: f.rendition.store)
            let counter = PhotoFinalCounter()
            #expect(!(await defaultStore.performPhotoSaveIfCurrent(command) { counter.increment() }))
            let library = PhotoFinalDefaultLibrary.make(), capture = CaptureMediaAdmission()
            let start = try photoFinalAuthorization(command, store: f.rendition.store, capture: capture)
            guard case .completed(let result) = await library.add(command, start: start) else {
                Issue.record("Default guarded witness unexpectedly held"); return
            }
            let legacyCalls = await library.legacyCalls
            #expect(result.outcome == .notAttempted(.rejected) && legacyCalls == 0 && counter.value == 0)
            try await photoFinalRetireNonStart(f, command: command)
        }
    }

    @Test func captureABAAndConsumedAuthorizationDoNotStartAndCancellationWinsBeforeDispatch() async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run), command = try await photoFinalCommand(f)
            let capture = CaptureMediaAdmission(), owner = try captureBoundaryOwner(), counter = PhotoFinalCounter()
            let first = try photoFinalAuthorization(command, store: f.rendition.store, capture: capture)
            capture.begin(owner, phases: [.recording]); capture.end(owner)
            #expect(await first.perform(command) { counter.increment() } == .heldBeforeStart)
            let consumed = try photoFinalAuthorization(command, store: f.rendition.store, capture: capture)
            #expect(try #require(consumed.capture).performIfCurrent {})
            #expect(await consumed.perform(command) { counter.increment() } == .refused)
            let cancelled = try photoFinalAuthorization(command, store: f.rendition.store, capture: capture)
            #expect(cancelled.claim.cancelBeforeStart())
            #expect(await cancelled.perform(command) { counter.increment() } == .cancelledBeforeStart)
            #expect(counter.value == 0)
            try await photoFinalRetireNonStart(f, command: command)
        }
    }
}

@Suite(.serialized) @MainActor struct PhotoSaveFinalStartConcurrencyTests {
    @Test func processClaimsBindFullInputOwnerStoreAndRawUTF8OperationWithoutNormalizingAliases() async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run), registry = PhotoSaveDispatchClaims(), owner = UUID()
            let intent = try PhotoRegistrationIntent(operation: .init(rawValue: "photo-claim-é"),
                handoff: f.receipt.photoHandoff(expected: f.receipt.rendition))
            let first = try #require(registry.reserve(identity: f.identity, intent: intent, receipt: f.receipt, owner: owner))
            #expect(registry.reserve(identity: f.identity, intent: intent, receipt: f.receipt, owner: owner) === first)
            #expect(registry.reserve(identity: f.identity, intent: intent, receipt: f.receipt, owner: UUID()) == nil)
            let changed = TemporaryMediaReceipt(id: f.receipt.id, rendition: f.receipt.rendition,
                capturedAt: f.receipt.capturedAt, ranges: f.receipt.ranges + f.receipt.ranges,
                verifiedContent: f.receipt.verifiedContent, usage: f.receipt.usage, isReleased: f.receipt.isReleased)
            #expect(registry.reserve(identity: f.identity, intent: intent, receipt: changed, owner: owner) == nil)
            let alias = try PhotoRegistrationIntent(operation: .init(rawValue: "photo-claim-e\u{301}"), handoff: intent.handoff)
            #expect(intent.operation == alias.operation)
            let distinct = try #require(registry.reserve(identity: f.identity, intent: alias, receipt: f.receipt, owner: owner))
            #expect(first !== distinct)
            #expect(registry.reserve(identity: .init(rawValue: UUID()), intent: intent, receipt: f.receipt, owner: owner) != nil)
            #expect(first.bind(intent))
            let bytes = try #require(first.dispatchInput(for: intent))
            #expect(first.dispatchInput(for: alias) == nil)
            #expect(first.cancelBeforeStart())
            #expect(first.performIfPending(input: bytes, action: { Issue.record("Cancelled claim started") }) == .cancelledBeforeStart)
            let resolves = await f.media.resolves, releases = await f.media.releases
            #expect(resolves == 0 && releases == 0)
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func aDifferentWriterEpochCannotDispatchTheOldLiveUseEvenWhileItsOwnerRemainsOpen(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run, candidate: candidate), command = try await photoFinalCommand(f)
            let reopened: any MediaDiskStore = candidate == .sqlite
                ? try SQLiteRecordingStore(run: run, mode: .openExisting) : try AtomicFileRecordingStore(run: run, mode: .openExisting)
            let previous = try await mediaOriginalSnapshot(f.rendition.store), next = try await mediaOriginalSnapshot(reopened)
            #expect(previous.reconciliationEpoch != next.reconciliationEpoch)
            #expect(command.registration.mediaUse.lease.epoch == previous.reconciliationEpoch)
            let counter = PhotoFinalCounter()
            #expect(!(await reopened.performPhotoSaveIfCurrent(command) { counter.increment() }))
            let handles = try await f.rendition.temporary.usageSnapshot(f.receipt.id).openHandles
            #expect(counter.value == 0 && handles == 1)
            try await photoFinalRetireNonStart(f, command: command)
        }
    }

    @Test(arguments: ["permission", "native-hop", "writer"])
    func aCaptureHoldAtEveryAwaitGapKeepsTheSameIntentUseAndFDThenStartsOnlyOnce(gap: String) async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run), barrier = PhotoFinalBarrier.make()
            let capture = CaptureMediaAdmission(), owner = try captureBoundaryOwner(), second = try captureBoundaryOwner()
            let library = PhotoFinalLibrary.make(permission: gap == "permission" ? barrier : nil,
                beforeNative: gap == "native-hop" ? barrier : nil)
            let store = PhotoFinalStore.make(base: f.rendition.store, beforeDispatch: gap == "writer" ? barrier : nil)
            let coordinator = PhotoSaveCoordinator(store: store, identity: f.identity, temporaryMedia: f.media,
                library: library, captureStart: capture, dispatchClaims: PhotoSaveDispatchClaims())
            let action = MediaOperationID(rawValue: UUID().uuidString)
            let task = Task { await coordinator.save(f.receipt, action: action) }
            defer { capture.end(owner); capture.end(second); Task { await barrier.release() } }
            try #require(await renditionEventually { await barrier.hasArrived })
            capture.begin(owner, phases: [.recording]); capture.begin(second, phases: [.saving, .recovery])
            await barrier.release()
            try #require(await renditionEventually { await f.media.resolves == 1 })
            try #require(await renditionEventually {
                (try? await f.rendition.temporary.usageSnapshot(f.receipt.id).openHandles) == 1
            })
            let held = try await f.latest(), handles = try await f.rendition.temporary.usageSnapshot(f.receipt.id)
            #expect(held.outcome == nil && held.usageTerminal == nil && handles.openHandles == 1 && handles.uses == 1)
            #expect(library.starts.value == 0)
            capture.end(owner)
            #expect(capture.snapshot().isHeld && library.starts.value == 0)
            capture.update(second, phases: [.recovery]); capture.end(second)
            guard case .succeeded(let saved) = await task.value else { Issue.record("Held save failed to wake"); return }
            let resolves = await f.media.resolves
            #expect(saved.registration == held.registration && saved.outcome == .succeeded(localIdentifier: nil))
            #expect(library.starts.value == 1 && resolves == 1)
            #expect(saved.usageTerminal?.terminal.termination == .sdkCompleted && saved.terminalUsageRelease != nil)
        }
    }

    @Test func explicitCancellationOfAHeldLiveSaveRecordsNonStartAndNeverStartsAfterWake() async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run), capture = CaptureMediaAdmission(), owner = try captureBoundaryOwner()
            let library = PhotoFinalLibrary.make(), coordinator = PhotoSaveCoordinator(store: f.rendition.store,
                identity: f.identity, temporaryMedia: f.media, library: library, captureStart: capture)
            capture.begin(owner, phases: [.saving])
            defer { capture.end(owner) }
            let action = MediaOperationID(rawValue: UUID().uuidString)
            let task = Task { await coordinator.save(f.receipt, action: action) }
            try #require(await renditionEventually { await f.media.resolves == 1 })
            #expect(await coordinator.cancelBeforeStart(action: action))
            guard case .succeeded(let saved) = await task.value else { Issue.record("Cancellation failed to settle non-start"); return }
            capture.end(owner)
            #expect(library.starts.value == 0 && saved.outcome == .notAttempted(.rejected))
            #expect(saved.usageTerminal?.terminal.termination == .notStarted && saved.terminalUsageRelease != nil)
            let state = try await f.rendition.temporary.usageSnapshot(f.receipt.id)
            #expect(state.uses == 0 && state.openHandles == 0 && state.fileBytes > 0)
        }
    }

    @Test(arguments: ["sdk-completion", "closed-fd-before-result"])
    func twoCoordinatorsCannotStartOrTerminateEachOthersUseAtEitherCompletionBoundary(gap: String) async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run), barrier = PhotoFinalBarrier.make(), capture = CaptureMediaAdmission()
            let library = PhotoFinalLibrary.make(completion: gap == "sdk-completion" ? barrier : nil)
            let store = PhotoFinalStore.make(base: f.rendition.store, beforeResult: gap == "closed-fd-before-result" ? barrier : nil)
            let claims = PhotoSaveDispatchClaims()
            let first = PhotoSaveCoordinator(store: store, identity: f.identity, temporaryMedia: f.media,
                library: library, captureStart: capture, dispatchClaims: claims)
            let second = PhotoSaveCoordinator(store: store, identity: f.identity, temporaryMedia: f.media,
                library: library, captureStart: capture, dispatchClaims: claims)
            let action = MediaOperationID(rawValue: UUID().uuidString)
            let task = Task { await first.save(f.receipt, action: action) }
            defer { Task { await barrier.release() } }
            try #require(await renditionEventually { await barrier.hasArrived })
            let before = try await mediaSnapshot(f.rendition.store), commits = await store.commits
            let resources = try await f.rendition.temporary.usageSnapshot(f.receipt.id)
            #expect(resources.uses == 1 && resources.openHandles == (gap == "sdk-completion" ? 1 : 0))
            #expect(await second.save(f.receipt, action: action) == .unknown)
            #expect(await store.commits == commits)
            #expect(try await mediaSnapshot(f.rendition.store) == before)
            let beforeReleases = await f.media.releases
            #expect(library.starts.value == 1 && beforeReleases == 0)
            #expect(!(await first.cancelBeforeStart(action: action)))
            await barrier.release()
            guard case .succeeded(let saved) = await task.value else { Issue.record("Owner save failed after completion"); return }
            #expect(saved.outcome == .succeeded(localIdentifier: nil) && saved.terminalUsageRelease != nil)
            let releases = await f.media.releases
            #expect(library.starts.value == 1 && releases == 1)
            #expect(try await f.rendition.temporary.usageSnapshot(f.receipt.id).uses == 0)
        }
    }

    @Test func anEmptyProcessRegistryNeverTurnsAReopenedIntentIntoPermissionToAdd() async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run)
            let record = try await f.commitIntent(action: UUID().uuidString)
            let reopened = try SQLiteRecordingStore(run: run, mode: .openExisting), library = PhotoFinalLibrary.make()
            let coordinator = PhotoSaveCoordinator(store: reopened, identity: f.identity, temporaryMedia: f.media,
                library: library, captureStart: CaptureMediaAdmission(), dispatchClaims: PhotoSaveDispatchClaims())
            #expect(await coordinator.save(f.receipt, action: record.registration.intent.operation) == .unknown)
            let resolves = await f.media.resolves
            #expect(library.starts.value == 0 && resolves == 0)
            #expect(try await f.latest() == record)
            #expect(await f.media.releases == 0)
        }
    }

    @Test func aFalseStoreReplyAfterItsRealSynchronousActionCannotCloseTheSDKOwnerBeforeCompletion() async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run), completion = PhotoFinalBarrier.make()
            let library = PhotoFinalLibrary.make(completion: completion)
            let store = PhotoFinalStore.make(base: f.rendition.store, falseAfterDispatch: true)
            let coordinator = PhotoSaveCoordinator(store: store, identity: f.identity, temporaryMedia: f.media,
                library: library, captureStart: CaptureMediaAdmission())
            let action = MediaOperationID(rawValue: UUID().uuidString)
            let task = Task { await coordinator.save(f.receipt, action: action) }
            defer { Task { await completion.release() } }
            // This is an actual invocation of the action under the real disk
            // writer/capture/claim locks. Only its following Bool reply is lost.
            try #require(await renditionEventually { await completion.hasArrived })
            #expect(library.starts.value == 1)
            let pending = try await f.latest(), media = try await f.rendition.temporary.usageSnapshot(f.receipt.id)
            #expect(pending.outcome == nil && pending.usageTerminal == nil && pending.terminalUsageRelease == nil)
            #expect(media.openHandles == 1 && media.uses == 1)
            #expect(!(await coordinator.cancelBeforeStart(action: action)))
            task.cancel()
            let finishes = await f.media.finishes, releases = await f.media.releases
            #expect(finishes == 0 && releases == 0)
            #expect(try await f.rendition.temporary.usageSnapshot(f.receipt.id).openHandles == 1)
            await completion.release()
            guard case .succeeded(let saved) = await task.value else { Issue.record("SDK owner lost its actual completion"); return }
            #expect(saved.usageTerminal?.terminal.termination == .sdkCompleted && saved.terminalUsageRelease != nil)
            #expect(await coordinator.save(f.receipt, action: action) == .succeeded(saved))
            let closed = try await f.rendition.temporary.usageSnapshot(f.receipt.id)
            #expect(closed.openHandles == 0 && closed.uses == 0 && library.starts.value == 1)
        }
    }
}

/// Explicitly allocated new Simulator/library only. No permission request,
/// asset deletion, root repair or second run of the fixed nonce is allowed.
@Suite(.serialized) @MainActor struct PhotoSaveFinalStartNativeTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_PHOTO_FINAL_START_NATIVE"] == "1"))
    func dedicatedNativeRefusalsPreserveEveryAssetThenOneNewActionCompletesAndReopens() async throws {
        #if targetEnvironment(simulator)
        let environment = ProcessInfo.processInfo.environment
        let simulator = "F6E8FB66-5889-4AC6-93E8-1F14DCE809B2", nonce = "ec9e835d-94bb-435b-b489-0f0d44fb2947"
        try #require(environment["FR_PHOTO_FINAL_START_SIMULATOR_ID"] == simulator && environment["SIMULATOR_UDID"] == simulator)
        try #require(environment["FR_PHOTO_FINAL_START_NONCE"] == nonce)
        try #require(PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized)
        try #require(PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized)
        let rootURL = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("FrameRelay-photo-final-native-" + nonce)
        let root = try ExplorationRunDirectory.createNew(at: rootURL)
        let baseline = try await photoFinalAssets(), completions = PhotoFinalCounter()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(baseline).write(to: root.url.appendingPathComponent("baseline-assets.json"), options: .withoutOverwriting)
        let native = NativePhotoLibrary(observeCompletion: { _ in completions.increment() })
        for mode in ["stale", "aba", "consumed"] {
            let run = try ExplorationRunDirectory.createNew(at: root.url.appendingPathComponent(mode))
            let f = try await PhotoSaveFixture.make(run: run), command = try await photoFinalCommand(f)
            let capture = CaptureMediaAdmission(), owner = try captureBoundaryOwner()
            let permit = try photoFinalAuthorization(command, store: f.rendition.store, capture: capture)
            if mode == "consumed" { #expect(try #require(permit.capture).performIfCurrent {}) }
            else {
                capture.begin(owner, phases: [.recording])
                if mode == "aba" { capture.end(owner) }
            }
            let refused = await native.add(command, start: permit)
            if mode == "consumed" {
                #expect(refused == .completed(.init(intent: command.registration.intent, outcome: .notAttempted(.rejected))))
            } else { #expect(refused == .heldBeforeStart) }
            capture.end(owner)
            #expect(await native.add(command) == .init(intent: command.registration.intent, outcome: .notAttempted(.rejected)))
            #expect(completions.value == 0)
            try await photoFinalRetireNonStart(f, command: command)
            _ = try await f.rendition.scope.close()
            #expect(try await photoFinalAssets() == baseline)
        }
        let run = try ExplorationRunDirectory.createNew(at: root.url.appendingPathComponent("one-new-action"))
        let source = run.url.appendingPathComponent("source-" + nonce + ".mov")
        try await SyntheticMovieFixture.write(to: source, withAudio: true, durationSeconds: 3, capturedAt: RenditionFixture.capturedAt)
        let bytes = try Data(contentsOf: source)
        let rendition = try await RenditionFixture.make(run: run, content: renditionContent(bytes))
        let complete = try await rendition.complete(bytes)
        guard case .succeeded(let usage) = await rendition.temporary.acquireUsage(complete.id, purpose: .photoHandoff,
            usageID: .init(rawValue: UUID().uuidString)) else { throw BackendContractError.ineligibleOriginal }
        let receipt = try await rendition.temporary.stateFor(complete.id).receipt(for: usage)
        try #require(await rendition.temporary.releaseUsage(complete.usage) == .succeeded(complete.id))
        let identity = try await establishRegistrationIdentity(rendition.store)
        let capture = CaptureMediaAdmission()
        let coordinator = PhotoSaveCoordinator(store: rendition.store, identity: identity, temporaryMedia: rendition.temporary,
            library: native, captureStart: capture)
        let action = MediaOperationID(rawValue: "native-photo-final-" + nonce)
        guard case .succeeded(let saved) = await coordinator.save(receipt, action: action),
              case .succeeded(let optionalIdentifier)? = saved.outcome else { Issue.record("Native final action did not succeed"); return }
        let identifier = try #require(optionalIdentifier)
        #expect(completions.value == 1 && saved.usageTerminal?.terminal.termination == .sdkCompleted && saved.terminalUsageRelease != nil)
        let current = try await photoFinalAssets()
        #expect(Set(current.keys) == Set(baseline.keys).union([identifier.rawValue]))
        let baselineUnchanged = baseline.allSatisfy { current[$0.key] == $0.value }
        #expect(baselineUnchanged)
        let asset = try #require(PHAsset.fetchAssets(withLocalIdentifiers: [identifier.rawValue], options: nil).firstObject)
        #expect(asset.mediaType == .video && asset.creationDate == saved.registration.intent.capturedAt)
        let resource = try #require(PHAssetResource.assetResources(for: asset).first { $0.type == .video })
        #expect(try await photoFinalResourceBytes(resource) == bytes)
        let audiovisual = try await photoFinalAVAsset(asset)
        #expect(try await audiovisual.loadTracks(withMediaType: .video).count == 1)
        #expect(try await audiovisual.loadTracks(withMediaType: .audio).count == 1)
        let released = try await rendition.temporary.usageSnapshot(receipt.id)
        #expect(released.uses == 0 && released.openHandles == 0 && released.fileBytes == 0)
        #expect(try Data(contentsOf: source) == bytes)
        _ = try await rendition.scope.close()
        let reopened = try SQLiteRecordingStore(run: run, mode: .openExisting)
        #expect(try await mediaSnapshot(reopened).photoRegistrations == [saved])
        let restored = PhotoSaveCoordinator(store: reopened, identity: identity, temporaryMedia: rendition.temporary,
            library: native, captureStart: capture, dispatchClaims: PhotoSaveDispatchClaims())
        _ = await restored.restore()
        #expect(await restored.save(receipt, action: action) == .succeeded(saved))
        let afterReopen = try await photoFinalAssets()
        #expect(completions.value == 1 && afterReopen == current)
        try encoder.encode(current).write(to: root.url.appendingPathComponent("final-assets.json"), options: .withoutOverwriting)
        print("PHOTO_FINAL_NATIVE nonce=\(nonce) baseline=\(baseline.count) staleABAConsumedLegacyStarts=0 additions=1 sdkCompletions=1 sourceBytes=unchanged readerFD=0 reopened=true root=\(root.url.path)")
        #else
        throw BackendContractError.unavailable
        #endif
    }
}

private struct PhotoFinalAsset: Equatable, Codable {
    let mediaType: Int
    let date: Date?
    let resources: [String]
}

@MainActor private func photoFinalAssets() async throws -> [String: PhotoFinalAsset] {
    let fetched = PHAsset.fetchAssets(with: nil)
    var assets: [PHAsset] = []
    fetched.enumerateObjects { asset, _, _ in assets.append(asset) }
    var result: [String: PhotoFinalAsset] = [:]
    for asset in assets {
        var resources: [String] = []
        for resource in PHAssetResource.assetResources(for: asset) {
            let bytes = try await photoFinalResourceBytes(resource)
            let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            resources.append("\(resource.type.rawValue):\(bytes.count):" + hash)
        }
        result[asset.localIdentifier] = .init(mediaType: asset.mediaType.rawValue, date: asset.creationDate, resources: resources.sorted())
    }
    return result
}

private nonisolated final class PhotoFinalResourceBuffer: Sendable {
    struct State { var bytes = Data(); var overflow = false }
    let state = Mutex(State())
}

private nonisolated func photoFinalResourceBytes(_ resource: PHAssetResource) async throws -> Data {
    let buffer = PhotoFinalResourceBuffer(), options = PHAssetResourceRequestOptions()
    options.isNetworkAccessAllowed = false
    return try await withCheckedThrowingContinuation { continuation in
        PHAssetResourceManager.default().requestData(for: resource, options: options, dataReceivedHandler: { block in
            buffer.state.withLock { value in
                guard !value.overflow, block.count <= 16_777_216 - value.bytes.count else { value.overflow = true; return }
                value.bytes.append(block)
            }
        }, completionHandler: { error in
            let value = buffer.state.withLock { $0 }
            if let error { continuation.resume(throwing: error) }
            else if value.overflow { continuation.resume(throwing: BackendContractError.invalidValue) }
            else { continuation.resume(returning: value.bytes) }
        })
    }
}

@MainActor private func photoFinalAVAsset(_ asset: PHAsset) async throws -> AVURLAsset {
    let options = PHVideoRequestOptions(); options.version = .original; options.isNetworkAccessAllowed = false
    return try await withCheckedThrowingContinuation { continuation in
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { value, _, _ in
            guard let value = value as? AVURLAsset else { continuation.resume(throwing: BackendContractError.invalidValue); return }
            continuation.resume(returning: value)
        }
    }
}

private nonisolated final class PhotoFinalCounter: Sendable {
    private let stored = Mutex(0)
    func increment() { stored.withLock { $0 += 1 } }
    var value: Int { stored.withLock { $0 } }
}

private nonisolated func photoFinalCommand(_ f: PhotoSaveFixture) async throws -> PhotoLibraryAddCommand {
    let record = try await f.commitIntent(action: UUID().uuidString)
    let local = try await f.media.resolvePhotoMedia(f.receipt.usage)
    return try .init(registration: record.registration, media: local)
}

private nonisolated func photoFinalAuthorization(_ command: PhotoLibraryAddCommand, store: any MediaOperationStorePort,
    capture: CaptureMediaAdmission) throws -> PhotoSaveStartAuthorization {
    let identity = try #require(command.registration.expectedStoreIdentity)
    let claim = try #require(PhotoSaveDispatchClaims().reserve(identity: identity, intent: command.registration.intent,
        receipt: nil, owner: UUID()))
    try #require(claim.bind(command.registration.intent))
    return .init(store: store, capture: try #require(capture.authorizeResume()), claim: claim)
}

private nonisolated func photoFinalRetireNonStart(_ f: PhotoSaveFixture, command: PhotoLibraryAddCommand) async throws {
    try await f.media.finishPhotoMedia(f.receipt.usage)
    let result = PhotoRegistrationResult(intent: command.registration.intent, outcome: .notAttempted(.rejected))
    _ = try await mediaCommit(f.rendition.store, .photo(command: .init(rawValue: UUID().uuidString), value: .result(result)))
    let terminal = try await f.media.photoUsageTerminal(command.registration, termination: .notStarted)
    _ = try await mediaCommit(f.rendition.store, .photo(command: .init(rawValue: UUID().uuidString), value: .terminal(terminal)))
    #expect(await f.media.releaseUsage(f.receipt.usage) == .succeeded(f.receipt.id))
    #expect(try await f.rendition.temporary.usageSnapshot(f.receipt.id).openHandles == 0)
}

private actor PhotoFinalDefaultStore: MediaOperationStorePort {
    nonisolated static func make(base: any MediaOperationStorePort) -> PhotoFinalDefaultStore { PhotoFinalDefaultStore(base: base) }
    let base: any MediaOperationStorePort
    init(base: any MediaOperationStorePort) { self.base = base }
    func load() async -> BackendStoreLoadResult { await base.load() }
    func commit(_ mutation: BackendStoreMutation) async -> BackendCommitResult { await base.commit(mutation) }
    func lookupCommit(_ mutation: BackendStoreMutation) async -> BackendCommitResult { await base.lookupCommit(mutation) }
}

private actor PhotoFinalDefaultLibrary: PhotoLibraryPort {
    nonisolated static func make() -> PhotoFinalDefaultLibrary { PhotoFinalDefaultLibrary() }
    private(set) var legacyCalls = 0
    func authorizationStatus(for access: PhotoLibraryAccess) -> PhotoLibraryAuthorization { .authorized }
    func requestAuthorization(for access: PhotoLibraryAccess) -> PhotoLibraryAuthorization { .authorized }
    func add(_ command: PhotoLibraryAddCommand) -> PhotoRegistrationResult {
        legacyCalls += 1; return .init(intent: command.registration.intent, outcome: .unknown(localIdentifier: nil))
    }
    func lookup(_ identifier: PhotoAssetIdentifier) -> PhotoLibraryLookupResult {
        .init(identifier: identifier, authorization: .authorized, presence: .present)
    }
}

private actor PhotoFinalBarrier {
    nonisolated static func make() -> PhotoFinalBarrier { PhotoFinalBarrier() }
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    private(set) var hasArrived = false
    func hold() async {
        hasArrived = true
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
}

private actor PhotoFinalStore: MediaOperationStorePort {
    nonisolated static func make(base: any MediaOperationStorePort, beforeDispatch: PhotoFinalBarrier? = nil,
        beforeResult: PhotoFinalBarrier? = nil, falseAfterDispatch: Bool = false) -> PhotoFinalStore {
        PhotoFinalStore(base: base, beforeDispatch: beforeDispatch, beforeResult: beforeResult, falseAfterDispatch: falseAfterDispatch)
    }
    let base: any MediaOperationStorePort
    let beforeDispatch: PhotoFinalBarrier?
    let beforeResult: PhotoFinalBarrier?
    let falseAfterDispatch: Bool
    private(set) var commits = 0
    init(base: any MediaOperationStorePort, beforeDispatch: PhotoFinalBarrier? = nil, beforeResult: PhotoFinalBarrier? = nil,
         falseAfterDispatch: Bool = false) {
        self.base = base; self.beforeDispatch = beforeDispatch; self.beforeResult = beforeResult
        self.falseAfterDispatch = falseAfterDispatch
    }
    func load() async -> BackendStoreLoadResult { await base.load() }
    func commit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        commits += 1
        if case .photo(_, .result) = mutation.change { await beforeResult?.hold() }
        return await base.commit(mutation)
    }
    func lookupCommit(_ mutation: BackendStoreMutation) async -> BackendCommitResult { await base.lookupCommit(mutation) }
    func performPhotoSaveIfCurrent(_ command: PhotoLibraryAddCommand, action: @Sendable () -> Void) async -> Bool {
        await beforeDispatch?.hold()
        let performed = await base.performPhotoSaveIfCurrent(command, action: action)
        return falseAfterDispatch ? false : performed
    }
}

private actor PhotoFinalLibrary: PhotoLibraryPort {
    nonisolated static func make(permission: PhotoFinalBarrier? = nil, beforeNative: PhotoFinalBarrier? = nil,
        completion: PhotoFinalBarrier? = nil) -> PhotoFinalLibrary {
        PhotoFinalLibrary(permission: permission, beforeNative: beforeNative, completion: completion)
    }
    nonisolated let starts = PhotoFinalCounter()
    let permission: PhotoFinalBarrier?
    let beforeNative: PhotoFinalBarrier?
    let completion: PhotoFinalBarrier?
    init(permission: PhotoFinalBarrier? = nil, beforeNative: PhotoFinalBarrier? = nil, completion: PhotoFinalBarrier? = nil) {
        self.permission = permission; self.beforeNative = beforeNative; self.completion = completion
    }
    func authorizationStatus(for access: PhotoLibraryAccess) async -> PhotoLibraryAuthorization {
        await permission?.hold(); return .authorized
    }
    func requestAuthorization(for access: PhotoLibraryAccess) -> PhotoLibraryAuthorization { .authorized }
    func add(_ command: PhotoLibraryAddCommand) -> PhotoRegistrationResult {
        .init(intent: command.registration.intent, outcome: .notAttempted(.rejected))
    }
    func add(_ command: PhotoLibraryAddCommand, start: PhotoSaveStartAuthorization) async -> PhotoLibraryAddAttempt {
        await beforeNative?.hold()
        let counter = starts
        switch await start.perform(command, action: { counter.increment() }) {
        case .heldBeforeStart: return .heldBeforeStart
        case .cancelledBeforeStart, .refused:
            return .completed(.init(intent: command.registration.intent, outcome: .notAttempted(.rejected)))
        case .started:
            await completion?.hold()
            return .completed(.init(intent: command.registration.intent, outcome: .succeeded(localIdentifier: nil)))
        }
    }
    func lookup(_ identifier: PhotoAssetIdentifier) -> PhotoLibraryLookupResult {
        .init(identifier: identifier, authorization: .authorized, presence: .present)
    }
}
