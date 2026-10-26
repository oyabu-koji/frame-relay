import Foundation
import Testing
@testable import FrameRelay

@MainActor
struct ProductCaptureAudioCoordinatorTests {
    @Test func idleAudioChecksSilenceFailuresAndRejectsStaleSequencesAndGenerations() async throws {
        let f = try CaptureFixture()
        let device = ProductCaptureTestDevice(fixture: f)
        let model = try make(f, device: device)
        await open(model)
        var checking = f.audio; checking.input = .checking
        await device.emitAudio(checking, sequence: 1)
        await eventually { model.currentAudio?.input == .checking }
        #expect(!model.canRecord)
        await device.emitAudio(f.audio, sequence: 2)
        await eventually { model.canRecord }
        #expect(model.currentAudio?.level.value?.linearAmplitude == 0)
        var failure = f.audio
        failure.writing = .failed(.writerFailed(.init(rawValue: "write-failure")))
        await device.emitAudio(failure, sequence: 4)
        await eventually { model.currentAudio?.confirmedFailure != nil }
        #expect(!model.canRecord)
        await device.emitAudio(f.audio, sequence: 3)
        await device.emitAudio(f.audio, sequence: 99, generation: f.context.generation)
        for _ in 0..<30 { await Task.yield() }
        #expect(model.currentAudio == failure)
        await model.record()
        #expect(await device.startCount == 0)
        await model.leaveCapture()
    }

    @Test func recoveryRequiresUserRECAndOldClipEventsCannotChangeTheNextClip() async throws {
        let f = try CaptureFixture()
        let device = ProductCaptureTestDevice(fixture: f)
        let model = try make(f, device: device)
        await open(model)
        let failed = audioFailure(f)
        await device.emitAudio(failed, sequence: 1)
        await eventually { model.canRetryAudio }
        await model.retryAudio()
        #expect(model.audioRecovery == .readyForUserREC)
        #expect(model.canRecord)
        #expect(await device.startCount == 0)
        await model.record()
        await eventually { model.capture?.phase == .recording }
        let first = try #require(model.capture?.context)
        await device.emit(.capture(.audioObserved(first, sequence: 10, failed)))
        await eventually { model.canRetryAudio }
        #expect(model.capture?.phase == .ended && !model.isSaving)
        #expect(!model.canRecord)
        await model.retryAudio()
        #expect(model.canRecord)
        await model.record()
        await eventually { model.capture?.phase == .recording }
        #expect(model.currentAudio?.writing == .notStarted)
        let current = model.currentAudio
        await device.emit(.capture(.audioObserved(first, sequence: 100, failed)))
        await device.emitAudio(failed, sequence: 101, capture: first.capture)
        for _ in 0..<30 { await Task.yield() }
        #expect(model.currentAudio == current)
        #expect(model.capture?.phase == .recording)
        #expect(await device.startCount == 2)
        await model.stop()
        await eventually { !model.isSaving }
        await model.leaveCapture()
    }

    @Test func oldControlEventCannotOverwriteNewerSnapshotAndSaveMustSettleBeforeRetry() async throws {
        let f = try CaptureFixture()
        let device = ProductCaptureTestDevice(fixture: f)
        let probe = ProductCaptureTestProbe(holdRefresh: true)
        let fileGate = ProductCaptureTestGate()
        let save = ProductCaptureTestSave(fileGate: fileGate)
        let model = try make(f, device: device, save: save, didSave: { await probe.refresh() })
        await open(model); await model.record()
        await eventually { model.capture?.phase == .recording }
        let context = try #require(model.capture?.context)
        let failed = audioFailure(f)
        await device.emitAudio(failed, sequence: 20, capture: context.capture)
        await fileGate.waitUntilHeld()
        await device.emit(.capture(.audioObserved(context, sequence: 19, f.audio)))
        for _ in 0..<30 { await Task.yield() }
        #expect(model.currentAudio?.confirmedFailure != nil)
        #expect(!model.canRetryAudio)
        await model.retryAudio()
        #expect(await device.audioRecoveryCalls == 0)
        #expect(await save.ends.first?.writer != .completed)
        await fileGate.release()
        await probe.waitForRefresh()
        await eventually { model.canRetryAudio }
        #expect(model.currentAudio?.confirmedFailure != nil)
        await model.retryAudio()
        #expect(await device.audioRecoveryCalls == 1)
        #expect(model.currentAudio?.confirmedFailure == nil)
        await probe.releaseRefresh()
        await model.leaveCapture()
    }

    @Test func retryPolicyBoundsAttemptsAndPermissionDenialRequiresSettings() async throws {
        let f = try CaptureFixture()
        let device = ProductCaptureTestDevice(fixture: f)
        let failure = CaptureAudioFailure.routeInterrupted(.init(rawValue: "route"))
        await device.configureAudioRecovery(outcomes: [.failed(failure)])
        let model = try make(f, device: device, maximumAttempts: 2)
        await open(model)
        await device.emitAudio(audioFailure(f), sequence: 1)
        await eventually { model.canRetryAudio }
        await model.retryAudio()
        #expect(await device.audioRecoveryCalls == 2)
        #expect(model.audioRecovery == .failed)
        #expect(!model.canRecord)
        var denied = f.audio; denied.input = .failed(.permissionDenied)
        await device.emitAudio(denied, sequence: 2)
        await eventually { model.currentAudio?.input == .failed(.permissionDenied) }
        #expect(!model.canRetryAudio)
        await model.retryAudio()
        #expect(await device.audioRecoveryCalls == 2)
        #expect(await device.startCount == 0)
        await model.leaveCapture()
    }

    @Test func timeoutRetainsSDKOwnerUntilRealReleaseAndRejectsLateSuccess() async throws {
        let f = try CaptureFixture()
        let device = ProductCaptureTestDevice(fixture: f)
        await device.configureAudioRecovery(outcomes: [], hold: true)
        let model = try make(f, device: device, timeoutMilliseconds: 10)
        await open(model)
        await device.emitAudio(audioFailure(f), sequence: 1)
        await eventually { model.canRetryAudio }
        let retry = Task { await model.retryAudio() }
        try await Task.sleep(for: .milliseconds(30))
        await eventually { model.audioRecovery == .timedOutWaitingForRelease }
        #expect(model.isBusy)
        #expect(!model.canRecord && !model.canRetryAudio)
        await model.retryAudio()
        #expect(await device.audioRecoveryCalls == 1)
        await device.completeAudioRecovery(.validInput(route: "late success"))
        await retry.value
        #expect(model.audioRecovery == .failed)
        #expect(!model.canRecord)
        #expect(!model.isBusy)
        #expect(await device.startCount == 0)
        await model.leaveCapture()
    }

    @Test func leavingDuringRecoveryRejectsLateSuccessAndReleasesOnlyAfterSDKReturns() async throws {
        let f = try CaptureFixture()
        let device = ProductCaptureTestDevice(fixture: f)
        await device.configureAudioRecovery(outcomes: [], hold: true)
        let model = try make(f, device: device)
        await open(model)
        await device.emitAudio(audioFailure(f), sequence: 1)
        await eventually { model.canRetryAudio }
        let retry = Task { await model.retryAudio() }
        await eventually { model.isRecoveringAudio }
        // Let the operation enter the fake SDK before requesting leave.
        while await device.audioRecoveryCalls == 0 { await Task.yield() }
        let leave = Task { await model.leaveCapture() }
        await eventually { model.captureVisit == nil }
        #expect(await device.shutdowns == 0)
        await device.completeAudioRecovery(.validInput(route: "late success"))
        await retry.value; await leave.value
        #expect(model.prepared == nil)
        #expect(!model.canRecord)
        #expect(await device.shutdowns == 1)
        #expect(await device.startCount == 0)
    }

    @Test func microphonePermissionDeniedBeforePreparationAppearsAsAudioFailure() async throws {
        let f = try CaptureFixture()
        let model = ProductCaptureCoordinator(preferences: ProductCaptureTestPreferences(fixture: f),
            makeDevice: { _ in throw ProductCaptureAudioPreparationError.microphonePermissionDenied },
            save: ProductCaptureTestSave(), bindOriginal: { _ in true }, didSave: {}, calendarNow: { Date() })
        await open(model)
        #expect(model.currentAudio?.confirmedFailure == .permissionDenied)
        #expect(model.issue?.contains("マイク") == true)
        #expect(!model.canRecord && !model.canRetryAudio)
        await model.leaveCapture()
    }

    private func audioFailure(_ f: CaptureFixture) -> CaptureAudioState {
        var result = f.audio
        result.input = .failed(.confirmedNoSamples(.init(rawValue: "synthetic-deadline")))
        return result
    }

    private func make(_ f: CaptureFixture, device: ProductCaptureTestDevice,
                      save: ProductCaptureTestSave? = nil, maximumAttempts: Int = 1,
                      timeoutMilliseconds: Int64 = 10_000,
                      didSave: @escaping @MainActor @Sendable () async -> Void = {}) throws -> ProductCaptureCoordinator {
        let policy = try ProductCaptureAudioPolicy(noArrivalGrace: .init(ticks: 2, timescale: 1),
            recovery: .init(maximumAttempts: maximumAttempts,
                            attemptTimeout: .init(ticks: timeoutMilliseconds, timescale: 1_000)))
        return ProductCaptureCoordinator(preferences: ProductCaptureTestPreferences(fixture: f), makeDevice: { _ in device },
            save: save ?? ProductCaptureTestSave(), bindOriginal: { _ in true }, didSave: didSave, audioPolicy: policy, calendarNow: { Date() })
    }

    private func open(_ model: ProductCaptureCoordinator) async {
        model.enterCapture()
        await model.load(); await model.prepare()
    }

    private func eventually(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<3_000 { if condition() { return }; await Task.yield() }
        #expect(condition())
    }
}
