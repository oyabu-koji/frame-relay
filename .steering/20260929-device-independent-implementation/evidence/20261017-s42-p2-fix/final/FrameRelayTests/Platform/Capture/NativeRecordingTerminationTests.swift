import Testing
@testable import FrameRelay

struct NativeRecordingTerminationTests {
    @Test(arguments: [false, true], [false, true])
    func failedRefreshStartRemainsPartialAfterStopRelockAndNextClipCanSave(movieFile: Bool,
                                                                         userStopFirst: Bool) throws {
        let first = try CaptureFixture()
        let second = try CaptureFixture(clip: "after-refresh-failure")
        let refreshFailure = CaptureUnavailableReason.adapterFailure(code: "capture_command_failed")
        var order = ExplorationWBCommandOrder(generation: first.context.generation)
        var termination = NativeRecordingTermination()

        for (index, fixture) in [first, second].enumerated() {
            var capture = CaptureLifecycle(context: fixture.context, audio: fixture.audio)
            let tokens = try beginCapture(&capture, fixture: fixture)
            #expect(order.requestLock(tokens.whiteBalance) == true)
            #expect(order.appliedLock(tokens.whiteBalance) == true)
            _ = try captureEffects(capture.receive(.whiteBalanceLocked(tokens.whiteBalance, fixture.lock)))
            let startEffects = try captureEffects(capture.receiveIntentCommit(fixture.receipt(tokens.intent)))
            let start = try #require(startEffects.compactMap { effect -> CaptureCommandToken? in
                if case .capture(.startRecording(let token, _)) = effect { return token }
                return nil
            }.first)
            #expect(order.canStart(fixture.context))
            termination.beginRecording()
            _ = try captureEffects(capture.receive(.recordingStarted(start, fixture.time)))

            var save = try RecordingSaveLifecycle(intent: fixture.intent, intentToken: tokens.intent, revision: 0)
            try save.acceptIntentCommit(fixture.receipt(tokens.intent))
            let stopEffects: [CaptureLifecycleEffect]
            var refresh: CaptureCommandToken?
            if index == 0 {
                let refreshEffects = try captureEffects(capture.refreshWhiteBalance(operation: fixture.intent.operation))
                let token = try #require(refreshEffects.compactMap { effect -> CaptureCommandToken? in
                    if case .capture(.refreshAndLockWhiteBalance(let token)) = effect { return token }
                    return nil
                }.first)
                refresh = token
                #expect(order.requestRefresh(token) == true)
                let earlierStop = userStopFirst
                    ? try captureEffects(capture.stop(operation: fixture.intent.operation)) : nil
                // Inject the failure of refreshWhiteBalance's SDK lock before one-shot
                // measurement. Native records it synchronously before publishing the event.
                termination.recordCommandFailure(.refreshAndLockWhiteBalance(token), activeToken: start,
                    reason: refreshFailure)
                let failureEffects = try captureEffects(capture.receive(.commandFailed(token, refreshFailure)))
                if let earlierStop {
                    stopEffects = earlierStop
                    #expect(failureEffects.isEmpty) // No adapterFailure STOP will reach Native.
                } else {
                    stopEffects = failureEffects
                }
                #expect(capture.failureReason == refreshFailure)
            } else {
                stopEffects = try captureEffects(capture.stop(operation: fixture.intent.operation))
            }

            let stop = try #require(stopEffects.compactMap { effect -> CaptureIOCommand? in
                if case .capture(let command) = effect { return command }
                return nil
            }.first)
            guard case .stopRecording(let token, let reason) = stop else {
                Issue.record("Expected the lifecycle's STOP command"); return
            }
            #expect(token == start)
            let expectedStop: CaptureStopReason = index == 0 && !userStopFirst
                ? .adapterFailure(refreshFailure) : .user(fixture.intent.operation)
            #expect(reason == expectedStop)
            termination.recordStop(reason)

            if let refresh {
                // Native STOP cancels measurement and waits for a successful re-lock.
                #expect(order.holdForStop(fixture.context) == .lockCurrent(refresh))
                #expect(order.measurementCompleted(refresh) == false)
                #expect(!order.shouldStopAfterLock(refresh))
                #expect(order.appliedLock(refresh) == true)
                #expect(order.shouldStopAfterLock(refresh))
                #expect(capture.receive(.whiteBalanceLocked(refresh, fixture.lock)) == .rejected(.duplicateOrOutOfOrder))
            } else {
                #expect(order.holdForStop(fixture.context) == .stop)
                // The old clip cannot apply a late lock over the next clip.
                #expect(order.appliedLock(first.token(4)) == false)
            }
            #expect(capture.phase == .stopping)
            #expect(capture.end == nil)

            // Both real Native completion paths use these same production methods.
            let writer = movieFile ? termination.movieFinished(failure: nil)
                : termination.writerFinished(completed: true)
            let expectedWriter: CaptureWriterTermination = index == 0 ? .interrupted(refreshFailure) : .completed
            #expect(writer == expectedWriter)
            let end = RecordingEndEvidence(writer: writer, ceasedAt: fixture.time,
                lastVideo: fixture.time, lastAudio: fixture.time)
            let endEffects = try captureEffects(capture.receive(.recordingEnded(start, end)))
            #expect(endEffects.contains(.recordingCeased(end)))
            let automatic = try #require(endEffects.compactMap { effect -> CaptureCommandToken? in
                if case .capture(.restoreAutomaticWhiteBalance(let token)) = effect { return token }
                return nil
            }.first)
            #expect(order.requestAutomatic(automatic) == true)
            #expect(order.appliedAutomatic(automatic) == true)
            _ = try captureEffects(capture.receive(.automaticWhiteBalanceRestored(automatic, fixture.time)))
            #expect(capture.whiteBalance == .automatic)

            try save.acceptRecordingEnd(context: fixture.context, evidence: end)
            try save.acceptFile(fixture.file)
            let resultToken = fixture.token(automatic.ordinal + 1)
            // Complete synthetic inspection isolates the lost STOP-reason bug. It does
            // not claim the real inspection adapter or an SDK throw was exercised.
            let command = try save.acceptInspection(fixture.inspection(), resultToken: resultToken)
            let expectedResult: RecordingSaveResult = index == 0 ? .partial(refreshFailure) : .saved
            guard case .commitResult(_, _, let record) = command else {
                Issue.record("Expected a result commit"); return
            }
            #expect(record.result == expectedResult)
            #expect(save.phase == .awaitingResultCommit(expectedResult))
            try save.acceptResultCommit(fixture.receipt(resultToken, previous: 1))
            #expect(save.phase == .committed(expectedResult))
        }
    }

    @Test func unrelatedOrInactiveCommandFailuresDoNotContaminateTheCurrentClip() throws {
        let fixture = try CaptureFixture()
        let old = try CaptureFixture(clip: "old-clip")
        let failure = CaptureUnavailableReason.adapterFailure(code: "capture_command_failed")
        var termination = NativeRecordingTermination()
        termination.beginRecording()
        let unrelated: [CaptureIOCommand] = [
            .lockCurrentWhiteBalance(fixture.token(2)),
            .startRecording(fixture.token(3), fixture.intent),
            .restoreAutomaticWhiteBalance(fixture.token(5)),
            .refreshAndLockWhiteBalance(old.token(4))
        ]
        for command in unrelated {
            termination.recordCommandFailure(command, activeToken: fixture.token(3), reason: failure)
        }
        termination.recordCommandFailure(.refreshAndLockWhiteBalance(fixture.token(4)), activeToken: nil,
            reason: failure)
        #expect(termination.writerFinished(completed: true) == .completed)
        #expect(termination.movieFinished(failure: nil) == .completed)

        // An adapter STOP also carries its failure when the producer did not record it.
        termination.recordStop(.adapterFailure(failure))
        #expect(termination.writerFinished(completed: true) == .interrupted(failure))
        #expect(termination.movieFinished(failure: nil) == .interrupted(failure))
    }

    @Test(arguments: [false, true])
    func userStopKeepsFailureAndSDKFinalizationFailureStillTakesPrecedence(movieFile: Bool) throws {
        let fixture = try CaptureFixture()
        let stopFailure = CaptureUnavailableReason.adapterFailure(code: "wb_refix_failed")
        var termination = NativeRecordingTermination()
        termination.beginRecording()
        termination.recordFailure(stopFailure)
        termination.recordStop(.user(fixture.intent.operation))
        let successfulFinalization = movieFile ? termination.movieFinished(failure: nil)
            : termination.writerFinished(completed: true)
        #expect(successfulFinalization == .interrupted(stopFailure))

        // Preserve Native's existing audio STOP representation and SDK-error priority.
        termination.recordStop(.audioFailure(.routeInterrupted(.init(rawValue: "synthetic-audio-failure"))))
        let audioFinalization = movieFile ? termination.movieFinished(failure: nil)
            : termination.writerFinished(completed: true)
        #expect(audioFinalization == .interrupted(.interrupted))
        let sdkFailure = CaptureUnavailableReason.adapterFailure(code: movieFile ? "movie_finish_1" : "writer_finalize_failed")
        let failedFinalization = movieFile ? termination.movieFinished(failure: sdkFailure)
            : termination.writerFinished(completed: false)
        #expect(failedFinalization == .interrupted(sdkFailure))
    }
}
