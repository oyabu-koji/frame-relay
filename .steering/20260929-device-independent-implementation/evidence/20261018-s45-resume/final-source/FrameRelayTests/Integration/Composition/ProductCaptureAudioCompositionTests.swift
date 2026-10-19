import Foundation
import Testing
@testable import FrameRelay

@MainActor
struct ProductCaptureAudioCompositionTests {
    @Test func productPolicyAllowsOneAttemptPerUserActionAndWaitsForReleaseAfterFiveSeconds() async throws {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("FrameRelay-capture-audio-policy-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        // Keep the isolated store until process teardown; test completion does not close SQLite descriptors.
        let services = try await ProductLibraryFactory(supportDirectory: parent).open()
        let fixture = try CaptureFixture()
        let device = ProductCaptureTestDevice(fixture: fixture)
        let failure = CaptureAudioFailure.confirmedNoSamples(.init(rawValue: "product-no-arrival"))
        let expectedGrace = try CaptureRationalTime(ticks: 2, timescale: 1)
        let expectedTimeout = try CaptureRationalTime(ticks: 5, timescale: 1)
        await device.configureAudioRecovery(outcomes: [.failed(failure)])
        let model = ProductCaptureFactory.make(services: services, didSave: {}, makeDevice: { candidate, policy, _ in
            #expect(candidate == .sampleWriter)
            #expect(policy.noArrivalGrace == expectedGrace)
            #expect(policy.recovery.maximumAttempts == 1)
            #expect(policy.recovery.attemptTimeout == expectedTimeout)
            return device
        })
        model.enterCapture()
        await model.load()
        await model.updatePreferences(.init(desired: fixture.desired, outputCandidate: .sampleWriter))
        await model.prepare()
        try #require(model.canRecord)
        var audio = fixture.audio
        audio.input = .failed(failure)
        await device.emitAudio(audio, sequence: 1)
        try #require(await eventually { model.canRetryAudio })

        await model.retryAudio()
        #expect(await device.audioRecoveryCalls == 1)
        #expect(model.audioRecovery == .failed)
        #expect(model.canRetryAudio && !model.canRecord)

        await device.configureAudioRecovery(outcomes: [], hold: true)
        let beganAt = ContinuousClock.now
        let retry = Task { await model.retryAudio() }
        try #require(await eventually { model.isRecoveringAudio })
        #expect(await eventually { await device.audioRecoveryCalls == 2 })
        await model.retryAudio()
        #expect(await device.audioRecoveryCalls == 2)
        #expect(await eventually(timeout: .seconds(8)) { model.audioRecovery == .timedOutWaitingForRelease })
        #expect(beganAt.duration(to: .now) >= .seconds(5))
        #expect(model.isBusy && !model.canRecord && !model.canRetryAudio)
        await model.retryAudio()
        #expect(await device.audioRecoveryCalls == 2)

        await device.completeAudioRecovery(.validInput(route: "late test mic"))
        await retry.value
        #expect(model.audioRecovery == .failed)
        #expect(model.canRetryAudio && !model.canRecord && !model.isBusy)
        #expect(await device.startCount == 0)

        await device.configureAudioRecovery(outcomes: [.validInput(route: "fresh test mic")])
        await model.retryAudio()
        #expect(await device.audioRecoveryCalls == 3)
        #expect(model.audioRecovery == .readyForUserREC)
        #expect(model.canRecord && !model.canRetryAudio)
        #expect(await device.startCount == 0)
        await model.leaveCapture()
    }

    private func eventually(timeout: Duration = .seconds(2), _ condition: @MainActor () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            do { try await Task.sleep(for: .milliseconds(10)) }
            catch { return false }
        }
        return await condition()
    }
}
