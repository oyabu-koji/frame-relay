import Foundation
import Testing
@testable import FrameRelay

/// Injected SDK action only. Real managed copy/FD/lease/terminal persistence is
/// exercised, while strict path proof and positive native resume remain absent.
@Suite(.serialized) @MainActor struct BackgroundCaptureResumeTests {
    @Test(arguments: [CaptureMediaPhase.recording, .saving, .recovery], [false, true])
    func holdAfterCoordinatorFinalIssuanceRejectsTheActionOnTheSDKExecutor(phase: CaptureMediaPhase,
                                                                        endBeforeDispatch: Bool) async throws {
        try await withStorageRun { run in
            let f = try await BackgroundCoordinatorFixture.make(run)
            let source = try ManagedUploadSource(run: run, originals: f.originals.access)
            let barrier = BackgroundCheckpoint()
            let sdk = BackgroundSessionProbe(identity: f.plan.session, resumeBarrier: barrier)
            let admission = CaptureMediaAdmission()
            let coordinator = f.coordinator(sdk: sdk, source: source, captureAdmission: admission)
            let starting = Task { await coordinator.startUpload(f.plan) }
            defer { Task { await barrier.release() } }
            try await barrier.waitForArrival()
            let before = try await mediaSnapshot(f.originals.store)
            #expect(before.backgroundTasks.first?.resumeRequested == true)
            #expect((await sdk.counts())[1] == 0)
            #expect((await source.resources()).openHandles == 1)
            let owner = try captureBoundaryOwner()
            admission.begin(owner, phases: [phase])
            #expect(await coordinator.synchronizeCaptureWaits())
            #expect(try await mediaSnapshot(f.originals.store).requests.first?.waits == admission.snapshot().waits)
            if endBeforeDispatch {
                admission.end(owner)
                #expect(await coordinator.synchronizeCaptureWaits())
            }
            await barrier.release()
            #expect(await starting.value == .refused(.sdkResumeUnavailable))
            let counts = await sdk.counts()
            #expect(counts[0] == 1 && counts[1] == 0 && counts[2] == 1)
            let task = try #require(try await mediaSnapshot(f.originals.store).backgroundTasks.first)
            let binding = try #require(task.binding)
            #expect(task.stopRequested && task.terminal == nil && task.ownerClosure == nil)
            // Stop is only requested so far: the actual owned reader/copy stays
            // retained until the callback and FD/lease terminal below.
            #expect((await source.resources()).openHandles == 1)
            #expect(try await mediaOriginalSnapshot(f.originals.store).originals.first?.readers.count == 1)
            await sdk.complete(binding, outcome: .cancelled, finishEvents: true)
            try await backgroundEventually {
                let resources = await source.resources()
                let transport = try? await mediaSnapshot(f.originals.store).requests.first?.transport
                return resources.openHandles == 0 && transport == .stopped
            }
            if !endBeforeDispatch { admission.end(owner) }
            #expect(await coordinator.synchronizeCaptureWaits())
            #expect((await sdk.counts())[1] == 0)
            #expect(try await mediaOriginalSnapshot(f.originals.store).originals.first?.readers.isEmpty == true)
            await sdk.finishStream(); _ = try await source.closeOwner()
        }
    }

    @Test func idleCoordinatorPassesOneAuthorizationToOneInjectedDispatch() async throws {
        try await withStorageRun { run in
            let f = try await BackgroundCoordinatorFixture.make(run)
            let source = try ManagedUploadSource(run: run, originals: f.originals.access)
            let sdk = BackgroundSessionProbe(identity: f.plan.session)
            let coordinator = f.coordinator(sdk: sdk, source: source)
            guard case .started(let task) = await coordinator.startUpload(f.plan), let binding = task.binding else {
                throw BackendContractError.notCommitted
            }
            #expect((await sdk.counts())[1] == 1)
            #expect((await source.resources()).openHandles == 1)
            await sdk.complete(binding, outcome: .cancelled, finishEvents: true)
            try await backgroundEventually { (await source.resources()).openHandles == 0 }
            #expect((await sdk.counts())[1] == 1)
            await sdk.finishStream(); _ = try await source.closeOwner()
        }
    }
}
