import Testing
@testable import FrameRelay

struct ProductCaptureAudioLifecycleTests {
    @Test(arguments: [false, true], [false, true])
    func confirmedFaultBeforeOrAfterUserStopCannotSaveAsNormal(movie: Bool, userStopFirst: Bool) throws {
        let fixture = try CaptureFixture()
        var capture = CaptureLifecycle(context: fixture.context, audio: fixture.audio)
        let start = try requestRecorderStart(&capture, fixture: fixture)
        _ = capture.receive(.recordingStarted(start, fixture.time))
        var nativeEnd = NativeRecordingTermination()
        nativeEnd.beginRecording()
        if userStopFirst { _ = capture.stop(operation: fixture.intent.operation) }
        var observation = NativeCaptureAudioObservation(beganAt: 0)
        let failure = CaptureAudioFailure.writerFailed(.init(rawValue: "synthetic-append-failure"))
        observation.fail(failure)
        nativeEnd.recordAudioFailure(.adapterFailure(code: "confirmed_audio_failure"))
        let transition = capture.receive(.audioObserved(fixture.context, sequence: 1, observation.state))
        let effects = try captureEffects(transition)
        if userStopFirst { #expect(effects.isEmpty) }
        else {
            #expect(effects.contains(.capture(.stopRecording(start, reason: .audioFailure(failure)))))
        }
        #expect(capture.phase == .stopping)
        let sdkResult = movie ? nativeEnd.movieFinished(failure: nil) : nativeEnd.writerFinished(completed: true)
        #expect(sdkResult == .interrupted(.adapterFailure(code: "confirmed_audio_failure")))
        // Even a faulty adapter that reports completed cannot erase the lifecycle's audio fact.
        let ended = try captureEffects(capture.receive(.recordingEnded(start, fixture.end)))
        let end = try #require(ended.compactMap { effect -> RecordingEndEvidence? in
            if case .recordingCeased(let end) = effect { return end }; return nil
        }.first)
        #expect(end.writer != .completed)
        var save = try RecordingSaveLifecycle(intent: fixture.intent, intentToken: fixture.token(1), revision: 0)
        try save.acceptIntentCommit(fixture.receipt(fixture.token(1)))
        try save.acceptRecordingEnd(context: fixture.context, evidence: end)
        try save.acceptFile(fixture.file)
        let command = try save.acceptInspection(fixture.inspection(), resultToken: fixture.token(100))
        guard case .commitResult(_, _, let record) = command else { Issue.record("Missing result"); return }
        #expect(record.result == .partial(.adapterFailure(code: "confirmed_audio_failure")))
        nativeEnd.beginRecording()
        #expect(nativeEnd.writerFinished(completed: true) == .completed)
    }

    @Test func delayedGoodAudioCannotClearCurrentFaultAndOldClipIsRejected() throws {
        let fixture = try CaptureFixture()
        let old = try CaptureFixture(clip: "old")
        var capture = CaptureLifecycle(context: fixture.context, audio: fixture.audio)
        let start = try requestRecorderStart(&capture, fixture: fixture)
        _ = capture.receive(.recordingStarted(start, fixture.time))
        var failed = fixture.audio
        failed.input = .failed(.confirmedNoSamples(.init(rawValue: "deadline")))
        _ = capture.receive(.audioObserved(fixture.context, sequence: 10, failed))
        #expect(capture.receive(.audioObserved(fixture.context, sequence: 9, fixture.audio)) == .rejected(.duplicateOrOutOfOrder))
        #expect(capture.receive(.audioObserved(old.context, sequence: 11, fixture.audio)) == .rejected(.wrongContext))
        #expect(capture.audio == failed)
    }
}
