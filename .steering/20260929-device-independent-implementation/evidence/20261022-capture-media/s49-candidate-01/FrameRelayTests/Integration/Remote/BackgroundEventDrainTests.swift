import Foundation
import Testing
@testable import FrameRelay

@Suite(.serialized)
struct BackgroundEventDrainTests {
    @Test func normalAdmissionRefusesBeforeAttemptLeaseCopyAndSDKFactories() async throws {
        try await withStorageRun { run in
            let fixture = try await BackgroundCoordinatorFixture.make(run)
            let sdk = BackgroundSessionProbe(identity: fixture.plan.session)
            let factories = BackgroundFactoryProbe()
            let access = BackgroundAccessProbe(base: fixture.originals.access)
            let before = try await mediaSnapshot(fixture.originals.store)
            let coordinator = BackgroundMediaCoordinator(store: fixture.originals.store, identity: fixture.plan.context.storeIdentity,
                originals: access, sessionFactory: { _ in await factories.sdkCreated(); return sdk },
                sourceFactory: { await factories.sourceCreated(); throw BackendContractError.unavailable })
            #expect(await coordinator.startUpload(fixture.plan) == .refused(.strictAdmissionUnavailable))
            #expect(await coordinator.startDownload(fixture.plan.context) == .refused(.strictAdmissionUnavailable))
            #expect(await factories.counts() == [0, 0])
            #expect(await access.counts() == [0, 0])
            #expect(try await mediaSnapshot(fixture.originals.store) == before)
            #expect(try await mediaOriginalSnapshot(fixture.originals.store).logicalOriginals[0].readers.isEmpty)
            await sdk.finishStream()
        }
    }

    @Test func completionWaitsForTerminalCommitRealSourceCloseAndOwnLeaseRelease() async throws {
        try await withStorageRun { run in
            let fixture = try await BackgroundCoordinatorFixture.make(run)
            let commit = BackgroundCheckpoint()
            let closing = BackgroundCheckpoint()
            let store = BackgroundStoreProbe(base: fixture.originals.store, terminalBarrier: commit)
            let managed = try ManagedUploadSource(run: run, originals: fixture.originals.access)
            let source = BackgroundSourceProbe(base: managed, finishBarrier: closing)
            let sdk = BackgroundSessionProbe(identity: fixture.plan.session)
            let drained = BackgroundDrainProbe()
            let coordinator = fixture.coordinator(store: store, sdk: sdk, source: source,
                didDrain: { await drained.record($0) })
            guard case .started(let started) = await coordinator.startUpload(fixture.plan), let binding = started.binding else {
                Issue.record("Injected permit/fake suspended SDK did not reach exact attach"); return
            }
            let lease = try #require(started.uploadLease)
            let callsBeforeReplay = await sdk.counts()
            #expect(await coordinator.startUpload(fixture.plan) == .existing(started))
            #expect(await sdk.counts() == callsBeforeReplay)
            #expect(await source.copyCount() == 1)
            #expect((await managed.resources()).openHandles == 1)
            await sdk.complete(binding, outcome: .cancelled, finishEvents: true)
            try await commit.waitForArrival()
            #expect(await drained.count() == 0)
            #expect(try await mediaSnapshot(fixture.originals.store).backgroundTasks[0].terminal == nil)
            #expect(try await mediaOriginalSnapshot(fixture.originals.store).logicalOriginals[0].readers == [lease])
            await commit.release()
            try await closing.waitForArrival()
            #expect(await drained.count() == 0)
            let terminalState = try await mediaSnapshot(fixture.originals.store).backgroundTasks[0]
            #expect(terminalState.terminal?.binding == binding && terminalState.ownerClosure == nil)
            #expect((await managed.resources()).openHandles == 1)
            #expect(try await mediaOriginalSnapshot(fixture.originals.store).logicalOriginals[0].readers == [lease])
            await closing.release()
            try await backgroundEventually { await drained.count() == 1 }
            let final = try await mediaSnapshot(fixture.originals.store)
            #expect(final.backgroundTasks[0].ownerClosure?.handlesClosed == true)
            #expect((await managed.resources()).openHandles == 0)
            #expect(try await mediaOriginalSnapshot(fixture.originals.store).logicalOriginals[0].readers.isEmpty)
            #expect(final.requests[0].remote == .notExecuted)
            #expect(final.verifications.isEmpty && final.confirmations.isEmpty)
            #expect((await store.lookupCount()) > 0)
            await sdk.finishStream()
            _ = try await managed.closeOwner()
        }
    }

    @Test func terminalBeforeAttachDrainsAfterExactCommitWithoutReplayOrReaderLeak() async throws {
        try await withStorageRun { run in
            let fixture = try await BackgroundCoordinatorFixture.make(run)
            let attached = BackgroundCheckpoint()
            let store = BackgroundStoreProbe(base: fixture.originals.store, attachBarrier: attached)
            let managed = try ManagedUploadSource(run: run, originals: fixture.originals.access)
            let source = BackgroundSourceProbe(base: managed)
            let sdk = BackgroundSessionProbe(identity: fixture.plan.session, completeDuringCreation: true)
            let drained = BackgroundDrainProbe()
            let coordinator = fixture.coordinator(store: store, sdk: sdk, source: source,
                didDrain: { await drained.record($0) })
            let start = Task { await coordinator.startUpload(fixture.plan) }
            try await attached.waitForArrival()
            #expect(await drained.count() == 0)
            let gap = try await mediaSnapshot(fixture.originals.store).backgroundTasks[0]
            #expect(gap.binding == nil && gap.terminal == nil && gap.ownerClosure == nil)
            #expect(!((try await mediaOriginalSnapshot(fixture.originals.store)).logicalOriginals[0].readers.isEmpty))
            await attached.release()
            _ = await start.value
            try await backgroundEventually { await drained.count() == 1 }
            let final = try await mediaSnapshot(fixture.originals.store).backgroundTasks[0]
            #expect(final.binding != nil && final.terminal?.binding == final.binding && final.ownerClosure != nil)
            #expect(await coordinator.startUpload(fixture.plan) == .existing(final))
            #expect(await source.copyCount() == 1)
            #expect((await sdk.counts())[0] == 1)
            #expect((await sdk.counts())[1] == 0)
            #expect(try await mediaOriginalSnapshot(fixture.originals.store).logicalOriginals[0].readers.isEmpty)
            await sdk.finishStream()
            _ = try await managed.closeOwner()
        }
    }

    @Test func lostTerminalReplyRetainsExactLookupAndWithholdsFinishUntilConfirmed() async throws {
        try await withStorageRun { run in
            let fixture = try await BackgroundCoordinatorFixture.make(run)
            let store = BackgroundStoreProbe(base: fixture.originals.store)
            let managed = try ManagedUploadSource(run: run, originals: fixture.originals.access)
            let sdk = BackgroundSessionProbe(identity: fixture.plan.session)
            let drained = BackgroundDrainProbe()
            let coordinator = fixture.coordinator(store: store, sdk: sdk, source: BackgroundSourceProbe(base: managed),
                didDrain: { await drained.record($0) })
            guard case .started(let started) = await coordinator.startUpload(fixture.plan), let binding = started.binding else {
                Issue.record("Injected start did not attach"); return
            }
            await store.hideTerminalLookup()
            await sdk.complete(binding, outcome: .completed, finishEvents: true)
            try await backgroundEventually { await store.hiddenLookupCount() > 0 }
            #expect(await drained.count() == 0)
            let durable = try await mediaSnapshot(fixture.originals.store).backgroundTasks[0]
            #expect(durable.terminal != nil && durable.ownerClosure == nil)
            #expect((await managed.resources()).openHandles == 1)
            await store.allowTerminalLookup()
            try await backgroundEventually {
                await coordinator.retryHeldEvents()
                return await drained.count() == 1
            }
            #expect(try await mediaSnapshot(fixture.originals.store).backgroundTasks[0].events.filter {
                if case .terminal = $0.change { return true }; return false
            }.count == 1)
            #expect(try await mediaOriginalSnapshot(fixture.originals.store).logicalOriginals[0].readers.isEmpty)
            await sdk.finishStream()
            _ = try await managed.closeOwner()
        }
    }

    @Test func controlsKeepCompoundWaitsAndDoNotTreatCancelAcknowledgementAsTerminal() async throws {
        try await withStorageRun { run in
            let fixture = try await BackgroundCoordinatorFixture.make(run)
            let managed = try ManagedUploadSource(run: run, originals: fixture.originals.access)
            let sdk = BackgroundSessionProbe(identity: fixture.plan.session)
            let drained = BackgroundDrainProbe()
            let coordinator = fixture.coordinator(sdk: sdk, source: BackgroundSourceProbe(base: managed),
                didDrain: { await drained.record($0) })
            guard case .started(let started) = await coordinator.startUpload(fixture.plan), let binding = started.binding else {
                Issue.record("Injected start did not attach"); return
            }
            for (index, action) in [BackgroundMediaControl.wait(.wiFiUnavailable, active: true), .wait(.saving, active: true), .pause].enumerated() {
                guard case .succeeded = await coordinator.control(fixture.plan.context.operation, action,
                    command: .init(rawValue: "control-\(index)")) else { Issue.record("Control was not durable"); return }
            }
            _ = await coordinator.pauseAll()
            var request = try await mediaSnapshot(fixture.originals.store).requests[0]
            #expect(request.intent == .paused && request.waits == [.wiFiUnavailable, .saving])
            #expect(request.transport == .stopRequested)
            _ = await coordinator.control(request.operation, .resume, command: .init(rawValue: "explicit-resume"))
            request = try await mediaSnapshot(fixture.originals.store).requests[0]
            #expect(request.intent == .running && request.waits == [.wiFiUnavailable, .saving])
            #expect((await sdk.counts())[1] == 1)
            _ = await coordinator.control(request.operation, .cancel, command: .init(rawValue: "explicit-cancel"))
            let pending = try await mediaSnapshot(fixture.originals.store).backgroundTasks[0]
            #expect(pending.stopRequested && pending.terminal == nil && pending.ownerClosure == nil)
            #expect((await managed.resources()).openHandles == 1)
            #expect(!((try await mediaOriginalSnapshot(fixture.originals.store)).logicalOriginals[0].readers.isEmpty))
            await sdk.complete(binding, outcome: .cancelled, finishEvents: true)
            try await backgroundEventually { await drained.count() == 1 }
            request = try await mediaSnapshot(fixture.originals.store).requests[0]
            #expect(request.intent == .cancelled && request.waits == [.wiFiUnavailable, .saving] && request.remote == .notExecuted)
            await sdk.finishStream()
            _ = try await managed.closeOwner()
        }
    }

    @Test func recoveryPreservesAttachGapsDuplicatesUnknownMissingAndNumericReuse() async throws {
        try await withStorageRun { run in
            let fixture = try await BackgroundCoordinatorFixture.make(run)
            let managed = try ManagedUploadSource(run: run, originals: fixture.originals.access)
            let sdk = BackgroundSessionProbe(identity: fixture.plan.session)
            let coordinator = fixture.coordinator(sdk: sdk, source: BackgroundSourceProbe(base: managed))
            guard case .started(let started) = await coordinator.startUpload(fixture.plan), let binding = started.binding else {
                Issue.record("Injected start did not attach"); return
            }
            let recovery = BackgroundMediaRecovery(store: fixture.originals.store, identity: fixture.plan.context.storeIdentity)
            let normal = await sdk.observations()
            guard let observed = normal.first else { Issue.record("Missing fake SDK observation"); return }
            let duplicate = BackgroundMediaTaskObservation(session: observed.session, taskIdentifier: observed.taskIdentifier + 1,
                taskDescription: observed.taskDescription, kind: observed.kind, state: .suspended, bytesSent: 0, bytesReceived: 0)
            await sdk.setObservations([observed, duplicate])
            #expect(try backgroundReport(await recovery.reconcile(fixture.plan.session, session: sdk)).tasks.contains {
                $0.intent == fixture.plan.id && $0.disposition == .duplicateDescription
            })
            let reused = BackgroundMediaTaskObservation(session: observed.session, taskIdentifier: observed.taskIdentifier,
                taskDescription: UUID().uuidString, kind: .upload, state: .suspended, bytesSent: 0, bytesReceived: 0)
            await sdk.setObservations([reused])
            #expect(try backgroundReport(await recovery.reconcile(fixture.plan.session, session: sdk)).tasks.contains {
                $0.intent == fixture.plan.id && $0.disposition == .numericIdentifierReused
            })
            await sdk.setObservations([])
            #expect(try backgroundReport(await recovery.reconcile(fixture.plan.session, session: sdk)).tasks.contains {
                $0.intent == fixture.plan.id && $0.disposition == .missingTask
            })
            #expect(try await mediaSnapshot(fixture.originals.store).backgroundTasks[0] == started)
            #expect((await managed.resources()).openHandles == 1)
            #expect(!((try await mediaOriginalSnapshot(fixture.originals.store)).logicalOriginals[0].readers.isEmpty))
            await sdk.complete(binding, outcome: .cancelled, finishEvents: false)
            try await backgroundEventually { (await managed.resources()).openHandles == 0 }
            await sdk.finishStream()
            _ = try await managed.closeOwner()
        }
    }

    @Test func uniqueEnumeratedDescriptionDoesNotAdoptCreateAttachGap() async throws {
        try await withStorageRun { run in
            let fixture = try await BackgroundCoordinatorFixture.make(run)
            let attached = BackgroundCheckpoint()
            let store = BackgroundStoreProbe(base: fixture.originals.store, attachBarrier: attached)
            let managed = try ManagedUploadSource(run: run, originals: fixture.originals.access)
            let sdk = BackgroundSessionProbe(identity: fixture.plan.session)
            let drained = BackgroundDrainProbe()
            let coordinator = fixture.coordinator(store: store, sdk: sdk, source: BackgroundSourceProbe(base: managed),
                didDrain: { await drained.record($0) })
            let start = Task { await coordinator.startUpload(fixture.plan) }
            try await attached.waitForArrival()
            let before = try await mediaSnapshot(fixture.originals.store)
            let report = try backgroundReport(await BackgroundMediaRecovery(store: fixture.originals.store,
                identity: fixture.plan.context.storeIdentity).reconcile(fixture.plan.session, session: sdk))
            #expect(report.tasks.contains { $0.intent == fixture.plan.id && $0.disposition == .createAttachGap })
            #expect(report.tasks.contains { $0.intent == nil && $0.disposition == .unknownTask })
            #expect(try await mediaSnapshot(fixture.originals.store) == before)
            #expect(before.backgroundTasks[0].binding == nil)
            let counts = await sdk.counts()
            #expect(counts[0] == 1 && counts[1] == 0)
            await attached.release()
            guard case .started(let state) = await start.value, let binding = state.binding else {
                Issue.record("The original live creator did not finish its own exact attach"); return
            }
            await sdk.complete(binding, outcome: .cancelled, finishEvents: true)
            try await backgroundEventually { await drained.count() == 1 }
            await sdk.finishStream()
            _ = try await managed.closeOwner()
        }
    }

    @Test(arguments: [false, true])
    func captureStopWaitsForAllActualLocalBoundariesAndPreservesPersonAndWiFi(cancelled: Bool) async throws {
        try await withStorageRun { run in
            let fixture = try await BackgroundCoordinatorFixture.make(run)
            let terminal = BackgroundCheckpoint(), closing = BackgroundCheckpoint(), releasing = BackgroundCheckpoint(), stopped = BackgroundCheckpoint()
            let store = BackgroundStoreProbe(base: fixture.originals.store, terminalBarrier: terminal, stoppedBarrier: stopped)
            let managed = try ManagedUploadSource(run: run, originals: fixture.originals.access)
            let sdk = BackgroundSessionProbe(identity: fixture.plan.session)
            let admission = CaptureMediaAdmission()
            let access = BackgroundAccessProbe(base: fixture.originals.access, releaseBarrier: releasing)
            let coordinator = fixture.coordinator(store: store, sdk: sdk, source: BackgroundSourceProbe(base: managed, finishBarrier: closing),
                access: access, captureAdmission: admission)
            guard case .started(let state) = await coordinator.startUpload(fixture.plan), let binding = state.binding else {
                Issue.record("Test SDK task did not attach"); return
            }
            _ = await coordinator.control(fixture.plan.context.operation, .wait(.wiFiUnavailable, active: true), command: .init(rawValue: "capture-wifi"))
            _ = await coordinator.control(fixture.plan.context.operation, cancelled ? .cancel : .pause, command: .init(rawValue: "capture-person"))
            let owner = try captureBoundaryOwner()
            admission.begin(owner, phases: [.recording])
            let result = CaptureStopResultProbe()
            let wait = Task { let value = await coordinator.waitForCaptureLocalStop(owner); await result.record(value); return value }
            try await backgroundEventually { (await sdk.counts())[2] > 0 }
            await sdk.complete(binding, outcome: .cancelled, finishEvents: true)
            try await terminal.waitForArrival()
            #expect(await result.value() == nil)
            await terminal.release()
            try await closing.waitForArrival()
            #expect(await result.value() == nil)
            #expect((await managed.resources()).openHandles == 1)
            await closing.release()
            try await releasing.waitForArrival()
            #expect(await result.value() == nil)
            #expect((await managed.resources()).openHandles == 0)
            #expect(!((try await mediaOriginalSnapshot(fixture.originals.store)).logicalOriginals[0].readers.isEmpty))
            await releasing.release()
            try await stopped.waitForArrival()
            #expect(await result.value() == nil)
            #expect(try await mediaOriginalSnapshot(fixture.originals.store).logicalOriginals[0].readers.isEmpty)
            #expect(try await mediaSnapshot(fixture.originals.store).requests[0].transport == .stopRequested)
            await stopped.release()
            #expect(await wait.value == .ready)
            let saved = try await mediaSnapshot(fixture.originals.store).requests[0]
            #expect(saved.transport == .stopped && saved.intent == (cancelled ? .cancelled : .paused))
            #expect(saved.waits == [.recording, .wiFiUnavailable] && saved.remote == .notExecuted)
            let next = try captureBoundaryOwner()
            admission.begin(next, phases: [.recording])
            admission.end(owner)
            #expect(await coordinator.synchronizeCaptureWaits())
            #expect(try await mediaSnapshot(fixture.originals.store).requests[0].waits == [.recording, .wiFiUnavailable])
            admission.end(next)
            #expect(await coordinator.synchronizeCaptureWaits())
            let final = try await mediaSnapshot(fixture.originals.store).requests[0]
            #expect(final.waits == [.wiFiUnavailable] && final.intent == saved.intent && final.remote == saved.remote)
            await sdk.finishStream()
            _ = try await managed.closeOwner()
        }
    }

    @Test func lostStoppedReplyIsLookedUpAfterLeaseReleaseWithoutSecondMutation() async throws {
        try await withStorageRun { run in
            let fixture = try await BackgroundCoordinatorFixture.make(run)
            let store = BackgroundStoreProbe(base: fixture.originals.store)
            let managed = try ManagedUploadSource(run: run, originals: fixture.originals.access)
            let sdk = BackgroundSessionProbe(identity: fixture.plan.session)
            let admission = CaptureMediaAdmission()
            let drained = BackgroundDrainProbe()
            let coordinator = fixture.coordinator(store: store, sdk: sdk, source: managed, captureAdmission: admission,
                didDrain: { await drained.record($0) })
            guard case .started(let state) = await coordinator.startUpload(fixture.plan), let binding = state.binding else {
                Issue.record("Test SDK task did not attach"); return
            }
            let owner = try captureBoundaryOwner(); admission.begin(owner, phases: [.recording])
            await store.hideStoppedLookup()
            await sdk.complete(binding, outcome: .cancelled, finishEvents: true)
            try await backgroundEventually { await store.hiddenStoppedCount() > 0 }
            #expect((await managed.resources()).openHandles == 0)
            #expect(try await mediaOriginalSnapshot(fixture.originals.store).logicalOriginals[0].readers.isEmpty)
            #expect(await drained.count() == 0)
            #expect(await coordinator.waitForCaptureLocalStop(owner) == .unknown)
            await store.allowStoppedLookup()
            try await backgroundEventually { await coordinator.retryHeldEvents(); return await drained.count() == 1 }
            #expect(await coordinator.waitForCaptureLocalStop(owner) == .ready)
            #expect(await store.stoppedCommitCount() == 1)
            #expect(try await mediaSnapshot(fixture.originals.store).requests[0].transport == .stopped)
            admission.end(owner); _ = await coordinator.synchronizeCaptureWaits()
            await sdk.finishStream()
            _ = try await managed.closeOwner()
        }
    }

    @Test func restartEmptyAdmissionDoesNotClearExistingCaptureWaitsOrOtherControlAxes() async throws {
        try await withStorageRun { run in
            let fixture = try await BackgroundCoordinatorFixture.make(run)
            let operation = fixture.plan.context.operation
            for (index, transition) in [MediaRequestTransition.wait(.recording, active: true), .wait(.wiFiUnavailable, active: true), .pause].enumerated() {
                _ = try await mediaCommit(fixture.originals.store, .requestTransition(command: .init(rawValue: "prior-\(index)"),
                    operation: operation, target: fixture.plan.context.target, registration: fixture.plan.context.registration, value: transition))
            }
            let admission = CaptureMediaAdmission()
            let sdk = BackgroundSessionProbe(identity: fixture.plan.session)
            let coordinator = BackgroundMediaCoordinator(store: fixture.originals.store, identity: fixture.plan.context.storeIdentity,
                originals: fixture.originals.access, captureAdmission: admission,
                sessionFactory: { _ in Issue.record("No SDK owner may be created"); return sdk },
                sourceFactory: { Issue.record("No copy may be created"); throw BackendContractError.wrongStage })
            let before = try await mediaSnapshot(fixture.originals.store)
            #expect(await coordinator.synchronizeCaptureWaits())
            #expect(try await mediaSnapshot(fixture.originals.store) == before)
            let owner = try captureBoundaryOwner(); admission.begin(owner, phases: [.saving])
            #expect(await coordinator.waitForCaptureLocalStop(owner) == .ready)
            #expect(try await mediaSnapshot(fixture.originals.store).requests[0].waits == [.recording, .saving, .wiFiUnavailable])
            admission.end(owner)
            #expect(await coordinator.synchronizeCaptureWaits())
            let final = try await mediaSnapshot(fixture.originals.store).requests[0]
            #expect(final.waits == [.recording, .wiFiUnavailable] && final.intent == .paused && final.remote == .notExecuted)
            await sdk.finishStream()
        }
    }

    @Test(arguments: ["copy", "attach"])
    func captureNeverInventsStopForInflightCopyOrCreateAttachGap(stage: String) async throws {
        try await withStorageRun { run in
            let fixture = try await BackgroundCoordinatorFixture.make(run)
            let checkpoint = BackgroundCheckpoint()
            let store = BackgroundStoreProbe(base: fixture.originals.store, attachBarrier: stage == "attach" ? checkpoint : nil)
            let managed = try ManagedUploadSource(run: run, originals: fixture.originals.access,
                copyCheckpoint: stage == "copy" ? { _ in await checkpoint.checkpoint() } : nil)
            let sdk = BackgroundSessionProbe(identity: fixture.plan.session)
            let admission = CaptureMediaAdmission()
            let drained = BackgroundDrainProbe()
            let coordinator = fixture.coordinator(store: store, sdk: sdk, source: managed, captureAdmission: admission,
                didDrain: { await drained.record($0) })
            let starting = Task { await coordinator.startUpload(fixture.plan) }
            try await checkpoint.waitForArrival()
            let owner = try captureBoundaryOwner(); admission.begin(owner, phases: [.recording])
            #expect(await coordinator.waitForCaptureLocalStop(owner) == .unknown)
            #expect(!((try await mediaOriginalSnapshot(fixture.originals.store)).logicalOriginals[0].readers.isEmpty))
            #expect(await drained.count() == 0)
            await checkpoint.release()
            _ = await starting.value
            if stage == "copy" {
                #expect((await sdk.counts())[0] == 0)
                #expect((await managed.resources()).openHandles == 1)
                #expect(await coordinator.waitForCaptureLocalStop(owner) == .unknown)
                // The unexposed copy/source stays unknown; no synthetic terminal
                // is supplied to make this fixture's durable reader disappear.
            } else {
                let state = try await mediaSnapshot(fixture.originals.store).backgroundTasks[0]
                #expect(state.terminal == nil && state.ownerClosure == nil)
                if let binding = state.binding {
                    await sdk.complete(binding, outcome: .cancelled, finishEvents: true)
                    try await backgroundEventually { await drained.count() == 1 }
                    #expect(await coordinator.waitForCaptureLocalStop(owner) == .ready)
                    _ = try await managed.closeOwner()
                }
            }
            admission.end(owner); _ = await coordinator.synchronizeCaptureWaits()
            await sdk.finishStream()
        }
    }

    @Test(arguments: [true, false])
    func reopenedConfirmedStopNeedsNoSourceAdoptionButCannotUseAnotherAttempt(sameAttempt: Bool) async throws {
        try await withStorageRun { run in
            let fixture = try await BackgroundCoordinatorFixture.make(run)
            let managed = try ManagedUploadSource(run: run, originals: fixture.originals.access)
            let sdk = BackgroundSessionProbe(identity: fixture.plan.session)
            let drained = BackgroundDrainProbe()
            let first = fixture.coordinator(sdk: sdk, source: managed, didDrain: { await drained.record($0) })
            guard case .started(let state) = await first.startUpload(fixture.plan), let binding = state.binding else {
                Issue.record("Test SDK task did not attach"); return
            }
            await sdk.complete(binding, outcome: .cancelled, finishEvents: true)
            try await backgroundEventually { await drained.count() == 1 }
            await sdk.finishStream()
            _ = try await managed.closeOwner()
            let store = try OriginalRemovalFixture.open(run, candidate: .sqlite)
            let context = fixture.plan.context
            if !sameAttempt {
                _ = try await mediaCommit(store, .requestTransition(command: .init(rawValue: "next-observation"),
                    operation: context.operation, target: context.target, registration: context.registration,
                    value: .reconciled(.init(context: .init(operation: context.operation, registration: context.registration,
                        target: context.target, session: fixture.plan.macSession), observation: .init(rawValue: 2), result: .notExecuted))))
                _ = try await mediaCommit(store, .requestTransition(command: .init(rawValue: "next-attempt"),
                    operation: context.operation, target: context.target, registration: context.registration,
                    value: .beginAttempt(.init(rawValue: "new-unresolved-attempt"))))
            }
            let admission = CaptureMediaAdmission(), factories = BackgroundFactoryProbe()
            let access = BackgroundAccessProbe(base: fixture.originals.access)
            let reopened = BackgroundMediaCoordinator(store: store, identity: context.storeIdentity, originals: access,
                captureAdmission: admission,
                sessionFactory: { _ in await factories.sdkCreated(); throw BackendContractError.wrongStage },
                sourceFactory: { await factories.sourceCreated(); throw BackendContractError.wrongStage })
            let owner = try captureBoundaryOwner(); admission.begin(owner, phases: [.recording])
            #expect(await reopened.waitForCaptureLocalStop(owner) == (sameAttempt ? .ready : .unknown))
            #expect(await factories.counts() == [0, 0])
            #expect(await access.counts() == [0, 0])
            #expect(try await mediaOriginalSnapshot(store).logicalOriginals[0].readers.isEmpty)
            admission.end(owner); _ = await reopened.synchronizeCaptureWaits()
        }
    }

    @Test func actualLocalTerminalDoesNotOverwriteCompletedRequest() async throws {
        try await withStorageRun { run in
            let fixture = try await BackgroundCoordinatorFixture.make(run)
            let managed = try ManagedUploadSource(run: run, originals: fixture.originals.access)
            let sdk = BackgroundSessionProbe(identity: fixture.plan.session)
            let drained = BackgroundDrainProbe()
            let coordinator = fixture.coordinator(sdk: sdk, source: managed, didDrain: { await drained.record($0) })
            guard case .started(let state) = await coordinator.startUpload(fixture.plan), let binding = state.binding else {
                Issue.record("Test SDK task did not attach"); return
            }
            let context = fixture.plan.context
            _ = try await mediaCommit(fixture.originals.store, .requestTransition(command: .init(rawValue: "already-completed"),
                operation: context.operation, target: context.target, registration: context.registration,
                value: .completed(.init(operation: context.operation, attempt: context.attempt, target: context.target, registration: context.registration))))
            let before = try await mediaSnapshot(fixture.originals.store).requests[0]
            await sdk.complete(binding, outcome: .completed, finishEvents: true)
            try await backgroundEventually { await drained.count() == 1 }
            #expect(try await mediaSnapshot(fixture.originals.store).requests[0] == before)
            await sdk.finishStream()
            _ = try await managed.closeOwner()
        }
    }

    @Test func recoveredOldContextTerminalNeverAdoptsSourceOrChangesNewRegistration() async throws {
        try await withStorageRun { run in
            let fixture = try await BackgroundCoordinatorFixture.make(run)
            let managed = try ManagedUploadSource(run: run, originals: fixture.originals.access)
            let source = BackgroundSourceProbe(base: managed)
            let sdk = BackgroundSessionProbe(identity: fixture.plan.session)
            let first = fixture.coordinator(sdk: sdk, source: source)
            guard case .started(let started) = await first.startUpload(fixture.plan), let binding = started.binding else {
                Issue.record("Injected start did not attach"); return
            }
            // A replacement consumer has no live source ownership. Finish the
            // old fake stream without inventing a terminal/ownerClosed receipt.
            await sdk.finishStream()
            let newRegistration = RegistrationIdentity(destination: fixture.plan.context.registration.destination,
                id: .init(rawValue: "replacement-registration"), generation: .init(rawValue: 2))
            _ = try await mediaRegister(fixture.originals.store, registration: newRegistration)
            let before = try await mediaSnapshot(fixture.originals.store)
            let recoveredSDK = BackgroundSessionProbe(identity: fixture.plan.session)
            let observations = await sdk.observations()
            await recoveredSDK.setObservations(observations)
            let drained = BackgroundDrainProbe()
            let recovered = fixture.coordinator(sdk: recoveredSDK, source: source,
                didDrain: { await drained.record($0) })
            #expect(try backgroundReport(await recovered.recover(fixture.plan.session)).tasks.contains { $0.disposition == .exact })
            await recoveredSDK.completeUnknown(try #require(observations.first), outcome: .cancelled, finishEvents: true)
            try await backgroundEventually { await drained.count() == 1 }
            let final = try await mediaSnapshot(fixture.originals.store)
            #expect(final.backgroundTasks[0].terminal?.binding == binding)
            #expect(final.backgroundTasks[0].intent.context == fixture.plan.context)
            #expect(final.backgroundTasks[0].ownerClosure == nil)
            #expect(final.requests == before.requests && final.registrations == before.registrations)
            #expect((await managed.resources()).openHandles == 1)
            #expect(await source.finishCount() == 0)
            let recoveryOwner = try captureBoundaryOwner()
            let captureAdmission = CaptureMediaAdmission()
            captureAdmission.begin(recoveryOwner, phases: [.recording])
            let observer = fixture.coordinator(sdk: BackgroundSessionProbe(identity: fixture.plan.session), source: source,
                captureAdmission: captureAdmission)
            #expect(await observer.waitForCaptureLocalStop(recoveryOwner) == .unknown)
            #expect(!((try await mediaOriginalSnapshot(fixture.originals.store)).logicalOriginals[0].readers.isEmpty))
            await recoveredSDK.finishStream()
            // The original live owner still needs the exact actual terminal.
            // Explicitly return it here for test resource teardown only; the
            // replacement coordinator never adopts/releases that owner.
            let terminal = BackgroundMediaSDKTerminal(binding: binding, outcome: .cancelled)
            let lease = try #require(started.uploadLease)
            if case .upload(_, _, let identity) = started.intent.source {
                _ = try await managed.finish(identity, lease: lease, terminal: terminal)
            }
            _ = await fixture.originals.access.releaseRead(lease)
            _ = try await managed.closeOwner()
        }
    }
}

nonisolated struct BackgroundCoordinatorFixture {
    let originals: OriginalRemovalFixture
    let plan: BackgroundMediaUploadPlan

    static func make(_ run: ExplorationRunDirectory) async throws -> Self {
        let originals = try OriginalRemovalFixture(run: run)
        return try await make(originals)
    }

    static func make(_ originals: OriginalRemovalFixture) async throws -> Self {
        let binding = try await originals.original("background-" + UUID().uuidString)
        let registration = try await mediaRegister(originals.store)
        let loaded = try await mediaSnapshot(originals.store)
        let identity = try await originals.store.establishRegistrationIdentity(expectedRevision: loaded.revision,
            expectedIdentity: loaded.storeIdentity)
        let operation = MediaOperationID(rawValue: "background-operation-" + UUID().uuidString)
        let current = try await mediaSnapshot(originals.store)
        let request = MediaRequest(operation: operation, target: .original(binding.original), purpose: .upload,
            registration: registration, expectedStartRevision: current.revision)
        _ = try await mediaCommit(originals.store, .request(command: operation, value: request))
        let macSession = UploadSessionID(rawValue: "mac-session-" + UUID().uuidString)
        _ = try await mediaCommit(originals.store, .requestTransition(command: .init(rawValue: "remote-observation"),
            operation: operation, target: request.target, registration: registration,
            value: .reconciled(.init(context: .init(operation: operation, registration: registration,
                target: request.target, session: macSession), observation: .init(rawValue: 1), result: .notExecuted))))
        var actual = URLRequest(url: try #require(URL(string: "https://example.invalid/background-media")))
        actual.httpMethod = "PUT"
        let plan = BackgroundMediaUploadPlan(id: .init(rawValue: "task-" + UUID().uuidString),
            context: .init(operation: operation, attempt: .init(rawValue: "attempt-" + UUID().uuidString),
                target: request.target, registration: registration, gateGeneration: 1, storeIdentity: identity),
            session: .init(identifier: .init(rawValue: "test.FrameRelay.background." + UUID().uuidString),
                generation: .init(rawValue: UUID())), taskDescription: UUID().uuidString,
            sourceID: .init(rawValue: UUID().uuidString), macSession: macSession, request: actual)
        return .init(originals: originals, plan: plan)
    }

    func coordinator(store: (any MediaOperationStorePort)? = nil, sdk: BackgroundSessionProbe,
        source: any BackgroundMediaUploadSourcePort,
        access: (any OriginalAccessPort)? = nil,
        captureAdmission: CaptureMediaAdmission = CaptureMediaAdmission(),
        didDrain: @escaping BackgroundMediaCoordinator.DidDrain = { _ in }) -> BackgroundMediaCoordinator {
        .init(store: store ?? originals.store, identity: plan.context.storeIdentity, originals: access ?? originals.access,
            admission: BackgroundPermitProbe(), captureAdmission: captureAdmission,
            sessionFactory: { _ in sdk }, sourceFactory: { source }, didDrain: didDrain)
    }
}

nonisolated struct BackgroundPermitProbe: BackgroundMediaStrictAdmissionPort {
    func permit(_ context: BackgroundMediaRequestContext) async -> BackendOutcome<BackgroundMediaStrictPermit> {
        .succeeded(.init(context: context, evidence: .init(rawValue: "explicit-test-only-strict-policy")))
    }
}

actor BackgroundSessionProbe: BackgroundMediaSessionPort {
    let identity: BackgroundMediaSessionIdentity
    private let stream: AsyncStream<BackgroundMediaSDKEvent>
    private let continuation: AsyncStream<BackgroundMediaSDKEvent>.Continuation
    private let streamID = UUID()
    private let completeDuringCreation: Bool
    private var taken = false
    private var sequence: UInt64 = 0
    private var creates = 0
    private var resumes = 0
    private var stops = 0
    private var tasks: [BackgroundMediaTaskObservation] = []
    private var terminals: [BackgroundMediaSDKTerminal] = []

    init(identity: BackgroundMediaSessionIdentity, completeDuringCreation: Bool = false) {
        self.identity = identity; self.completeDuringCreation = completeDuringCreation
        let pair = AsyncStream<BackgroundMediaSDKEvent>.makeStream()
        stream = pair.stream; continuation = pair.continuation
    }

    func events() throws -> AsyncStream<BackgroundMediaSDKEvent> {
        guard !taken else { throw BackendContractError.wrongStage }; taken = true; return stream
    }
    func createSuspended(_ intent: BackgroundMediaTaskIntent, request: URLRequest,
                         upload: BackgroundMediaUploadFile?) -> BackendOutcome<BackgroundMediaTaskBinding> {
        creates += 1
        let binding = BackgroundMediaTaskBinding(session: identity, taskIdentifier: creates, taskDescription: intent.taskDescription)
        tasks.append(.init(session: identity, taskIdentifier: creates, taskDescription: intent.taskDescription,
            kind: .upload, state: .suspended, bytesSent: 0, bytesReceived: 0))
        if completeDuringCreation { complete(binding, outcome: .cancelled, finishEvents: true) }
        return .succeeded(binding)
    }
    func enumerate() -> BackendOutcome<[BackgroundMediaTaskObservation]> { .succeeded(tasks) }
    func resume(_ binding: BackgroundMediaTaskBinding, permit: BackgroundMediaStrictPermit) -> BackendOutcome<BackgroundMediaTaskBinding> {
        guard !terminals.contains(where: { $0.binding == binding }) else { return .notExecuted }
        resumes += 1
        return .succeeded(binding)
    }
    func requestStop(_ binding: BackgroundMediaTaskBinding) { stops += 1 }
    func observeTerminal(_ binding: BackgroundMediaTaskBinding) -> BackendOutcome<BackgroundMediaSDKTerminal> {
        terminals.first(where: { $0.binding == binding }).map { .succeeded($0) } ?? .inProgress
    }
    func invalidate() { emit(.sessionInvalidated(errorCode: nil)); continuation.finish() }
    func complete(_ binding: BackgroundMediaTaskBinding, outcome: BackgroundMediaSDKOutcome, finishEvents: Bool) {
        let terminal = BackgroundMediaSDKTerminal(binding: binding, outcome: outcome)
        terminals.append(terminal)
        tasks.removeAll { $0.taskIdentifier == binding.taskIdentifier }
        emit(.taskTerminal(terminal))
        if finishEvents { emit(.finishedEvents) }
    }
    func completeUnknown(_ observation: BackgroundMediaTaskObservation, outcome: BackgroundMediaSDKOutcome, finishEvents: Bool) {
        tasks.removeAll { $0.taskIdentifier == observation.taskIdentifier }
        emit(.unknownTaskTerminal(observation, outcome: outcome))
        if finishEvents { emit(.finishedEvents) }
    }
    func finishEvents() { emit(.finishedEvents) }
    func observations() -> [BackgroundMediaTaskObservation] { tasks }
    func setObservations(_ values: [BackgroundMediaTaskObservation]) { tasks = values }
    func counts() -> [Int] { [creates, resumes, stops] }
    func finishStream() { continuation.finish() }
    private func emit(_ value: BackgroundMediaSDKEventValue) {
        sequence += 1
        continuation.yield(.init(session: identity, stream: streamID, sequence: sequence, value: value))
    }
}

actor BackgroundSourceProbe: BackgroundMediaUploadSourcePort {
    let base: ManagedUploadSource
    let finishBarrier: BackgroundCheckpoint?
    private var copies = 0
    private var finishes = 0
    init(base: ManagedUploadSource, finishBarrier: BackgroundCheckpoint? = nil) { self.base = base; self.finishBarrier = finishBarrier }
    func create(from lease: OriginalReadLease, id: ManagedUploadSourceID) async throws -> ManagedUploadSourceIdentity {
        copies += 1; return try await base.create(from: lease, id: id)
    }
    func uploadFile(for identity: ManagedUploadSourceIdentity, lease: OriginalReadLease) async throws -> BackgroundMediaUploadFile {
        try await base.uploadFile(for: identity, lease: lease)
    }
    func retain(_ identity: ManagedUploadSourceIdentity, lease: OriginalReadLease, for binding: BackgroundMediaTaskBinding) async throws {
        try await base.retain(identity, lease: lease, for: binding)
    }
    func finish(_ identity: ManagedUploadSourceIdentity, lease: OriginalReadLease,
                terminal: BackgroundMediaSDKTerminal) async throws -> BackgroundMediaOwnerClosure {
        finishes += 1
        await finishBarrier?.checkpoint()
        return try await base.finish(identity, lease: lease, terminal: terminal)
    }
    func copyCount() -> Int { copies }
    func finishCount() -> Int { finishes }
}

actor BackgroundStoreProbe: MediaOperationStorePort {
    let base: any MediaOperationStorePort
    let terminalBarrier: BackgroundCheckpoint?
    let attachBarrier: BackgroundCheckpoint?
    let stoppedBarrier: BackgroundCheckpoint?
    private var hideTerminal = false
    private var hidden = 0
    private var lookups = 0
    private var hideStopped = false
    private var hiddenStops = 0
    private var stoppedCommits = 0
    init(base: any MediaOperationStorePort, terminalBarrier: BackgroundCheckpoint? = nil, attachBarrier: BackgroundCheckpoint? = nil,
         stoppedBarrier: BackgroundCheckpoint? = nil) {
        self.base = base; self.terminalBarrier = terminalBarrier; self.attachBarrier = attachBarrier
        self.stoppedBarrier = stoppedBarrier
    }
    func load() async -> BackendStoreLoadResult { await base.load() }
    func commit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        if case .backgroundTask(_, .terminal) = mutation.change { await terminalBarrier?.checkpoint() }
        if case .backgroundTask(_, .attached) = mutation.change { await attachBarrier?.checkpoint() }
        if case .requestTransition(_, _, _, _, .stopped) = mutation.change {
            stoppedCommits += 1
            await stoppedBarrier?.checkpoint()
        }
        let result = await base.commit(mutation)
        if hideTerminal, case .backgroundTask(_, .terminal) = mutation.change, case .committed = result { return .unknown }
        if hideStopped, case .requestTransition(_, _, _, _, .stopped) = mutation.change, case .committed = result { return .unknown }
        return result
    }
    func lookupCommit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        lookups += 1
        if hideTerminal, case .backgroundTask(_, .terminal) = mutation.change { hidden += 1; return .unknown }
        if hideStopped, case .requestTransition(_, _, _, _, .stopped) = mutation.change { hiddenStops += 1; return .unknown }
        return await base.lookupCommit(mutation)
    }
    func hideTerminalLookup() { hideTerminal = true }
    func allowTerminalLookup() { hideTerminal = false }
    func lookupCount() -> Int { lookups }
    func hiddenLookupCount() -> Int { hidden }
    func hideStoppedLookup() { hideStopped = true }
    func allowStoppedLookup() { hideStopped = false }
    func hiddenStoppedCount() -> Int { hiddenStops }
    func stoppedCommitCount() -> Int { stoppedCommits }
}

actor BackgroundFactoryProbe {
    private var sdk = 0, sources = 0
    func sdkCreated() { sdk += 1 }
    func sourceCreated() { sources += 1 }
    func counts() -> [Int] { [sdk, sources] }
}

actor BackgroundAccessProbe: OriginalAccessPort {
    let base: any OriginalAccessPort
    private var acquires = 0, releases = 0
    let releaseBarrier: BackgroundCheckpoint?
    init(base: any OriginalAccessPort, releaseBarrier: BackgroundCheckpoint? = nil) { self.base = base; self.releaseBarrier = releaseBarrier }
    func describe(_ reference: CaptureOriginalReference) async -> OriginalDescriptionResult { await base.describe(reference) }
    func acquireRead(_ original: OriginalContent, operation: MediaOperationID, leaseID: ReadLeaseID) async -> BackendOutcome<OriginalReadLease> {
        acquires += 1; return await base.acquireRead(original, operation: operation, leaseID: leaseID)
    }
    func releaseRead(_ lease: OriginalReadLease) async -> BackendOutcome<ReadReleaseReceipt> {
        releases += 1
        await releaseBarrier?.checkpoint()
        return await base.releaseRead(lease)
    }
    func reconcileReaders(_ original: OriginalContent) async -> BackendOutcome<AllReadersReleasedReceipt> { await base.reconcileReaders(original) }
    func counts() -> [Int] { [acquires, releases] }
}

actor BackgroundDrainProbe {
    private var observations: [BackgroundMediaDrainObservation] = []
    func record(_ observation: BackgroundMediaDrainObservation) { observations.append(observation) }
    func count() -> Int { observations.count }
}

actor CaptureStopResultProbe {
    private var result: CaptureMediaLocalStop?
    func record(_ value: CaptureMediaLocalStop) { result = value }
    func value() -> CaptureMediaLocalStop? { result }
}

actor BackgroundCheckpoint {
    private var arrived = false
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func checkpoint() async {
        arrived = true
        if released { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func waitForArrival() async throws { try await backgroundEventually { await self.hasArrived() } }
    private func hasArrived() -> Bool { arrived }
    func release() { released = true; let waiting = waiters; waiters.removeAll(); waiting.forEach { $0.resume() } }
}

nonisolated func backgroundEventually(_ condition: @escaping @Sendable () async -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !(await condition()) {
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { throw BackendContractError.unavailable }
        try await Task.sleep(for: .milliseconds(5))
    }
}

nonisolated func backgroundReport(_ outcome: BackendOutcome<BackgroundMediaRecoveryReport>) throws -> BackgroundMediaRecoveryReport {
    guard case .succeeded(let report) = outcome else { throw BackendContractError.unknownResult }; return report
}

private extension BackgroundMediaTaskState {
    nonisolated var uploadLease: OriginalReadLease? {
        guard case .upload(_, let lease, _) = intent.source else { return nil }; return lease
    }
}
