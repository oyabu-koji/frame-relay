import Testing
@testable import FrameRelay

struct CaptureLifecycleTests {
    @Test(arguments: [true, false])
    func requiresIntentCommitAndCurrentWBInEitherCompletionOrder(wbFirst: Bool) throws {
        let fixture = try CaptureFixture()
        var lifecycle = CaptureLifecycle(context: fixture.context, audio: fixture.audio)
        let tokens = try beginCapture(&lifecycle, fixture: fixture)
        #expect(lifecycle.phase == .starting)
        #expect(lifecycle.begin(fixture.intent, readiness: fixture.readiness(), expectedStoreRevision: 0)
                == .rejected(.wrongStage))
        let first: CaptureTransition
        let second: CaptureTransition
        if wbFirst {
            first = lifecycle.receive(.whiteBalanceLocked(tokens.whiteBalance, fixture.lock))
            second = lifecycle.receiveIntentCommit(fixture.receipt(tokens.intent))
        } else {
            first = lifecycle.receiveIntentCommit(fixture.receipt(tokens.intent))
            second = lifecycle.receive(.whiteBalanceLocked(tokens.whiteBalance, fixture.lock))
        }
        #expect(try captureEffects(first).isEmpty)
        let effects = try captureEffects(second)
        #expect(effects.count == 1)
        guard case .capture(.startRecording(_, let intent)) = effects.first else {
            Issue.record("Recorder must be requested after both prerequisites")
            return
        }
        #expect(intent.desired.exposure == fixture.desired.exposure)
        #expect(lifecycle.phase == .starting) // No actual start notice yet.
        #expect(lifecycle.receive(.whiteBalanceLocked(tokens.whiteBalance, fixture.lock))
                == .rejected(.duplicateOrOutOfOrder))
        #expect(lifecycle.receiveIntentCommit(fixture.receipt(tokens.intent))
                == .rejected(.duplicateOrOutOfOrder))
    }

    @Test func immediateSTOPPreventsLatePrerequisitesFromStartingRecorder() throws {
        let fixture = try CaptureFixture()
        var lifecycle = CaptureLifecycle(context: fixture.context, audio: fixture.audio)
        let tokens = try beginCapture(&lifecycle, fixture: fixture)
        let effects = try captureEffects(lifecycle.stop(operation: .init(rawValue: "synthetic-stop")))
        #expect(lifecycle.end?.writer == .notStarted)
        #expect(effects.contains { if case .capture(.restoreAutomaticWhiteBalance) = $0 { return true }; return false })
        #expect(lifecycle.receive(.whiteBalanceLocked(tokens.whiteBalance, fixture.lock))
                == .rejected(.duplicateOrOutOfOrder))
        #expect(try captureEffects(lifecycle.receiveIntentCommit(fixture.receipt(tokens.intent))).isEmpty)
        #expect(lifecycle.phase == .ended)
    }

    @Test func inputIsRecheckedAfterDelayedWBAndStore() throws {
        let fixture = try CaptureFixture()
        var lifecycle = CaptureLifecycle(context: fixture.context, audio: fixture.audio)
        let tokens = try beginCapture(&lifecycle, fixture: fixture)
        var checking = fixture.audio
        checking.input = .checking
        _ = lifecycle.receive(.audioObserved(fixture.context, sequence: 1, checking))
        _ = lifecycle.receive(.whiteBalanceLocked(tokens.whiteBalance, fixture.lock))
        #expect(try captureEffects(lifecycle.receiveIntentCommit(fixture.receipt(tokens.intent))).isEmpty)
        let effects = try captureEffects(lifecycle.receive(.audioObserved(fixture.context, sequence: 2, fixture.audio)))
        #expect(effects.contains { if case .capture(.startRecording) = $0 { return true }; return false })
        #expect(lifecycle.phase == .starting)
    }

    @Test func STOPBeforeDidStartKeepsWBFixedUntilConfirmedEnd() throws {
        let fixture = try CaptureFixture()
        var lifecycle = CaptureLifecycle(context: fixture.context, audio: fixture.audio)
        let recording = try requestRecorderStart(&lifecycle, fixture: fixture)
        let effects = try captureEffects(lifecycle.stop(operation: .init(rawValue: "synthetic-stop")))
        #expect(effects == [.capture(.stopRecording(recording, reason: .user(.init(rawValue: "synthetic-stop"))))])
        #expect(lifecycle.phase == .stopping)
        #expect(lifecycle.whiteBalance == .locked(fixture.lock))
        #expect(lifecycle.stop(operation: .init(rawValue: "synthetic-double-stop")) == .rejected(.wrongStage))
        #expect(try captureEffects(lifecycle.receive(.recordingStarted(recording, fixture.time))).isEmpty)
        #expect(lifecycle.phase == .stopping)
        let endEffects = try captureEffects(lifecycle.receive(.recordingEnded(recording, fixture.end)))
        #expect(lifecycle.phase == .ended)
        let auto = try #require(endEffects.compactMap { effect -> CaptureCommandToken? in
            if case .capture(.restoreAutomaticWhiteBalance(let token)) = effect { return token }
            return nil
        }.first)
        #expect(lifecycle.whiteBalance == .restoringAutomatic(auto))
        #expect(try captureEffects(lifecycle.receive(.automaticWhiteBalanceRestored(auto, fixture.time))).isEmpty)
        #expect(lifecycle.whiteBalance == .automatic)
        #expect(lifecycle.receive(.recordingEnded(recording, fixture.end)) == .rejected(.duplicateOrOutOfOrder))
        #expect(lifecycle.receive(.recordingStarted(recording, fixture.time)) == .rejected(.duplicateOrOutOfOrder))
    }

    @Test func explicitWBRefreshCannotRelockAfterSTOPCompletion() throws {
        let fixture = try CaptureFixture()
        var lifecycle = CaptureLifecycle(context: fixture.context, audio: fixture.audio)
        let recording = try requestRecorderStart(&lifecycle, fixture: fixture)
        _ = lifecycle.receive(.recordingStarted(recording, fixture.time))
        let effects = try captureEffects(lifecycle.refreshWhiteBalance(operation: .init(rawValue: "synthetic-refresh")))
        let refresh = try #require(effects.compactMap { effect -> CaptureCommandToken? in
            if case .capture(.refreshAndLockWhiteBalance(let token)) = effect { return token }
            return nil
        }.first)
        _ = lifecycle.stop(operation: .init(rawValue: "synthetic-stop"))
        #expect(lifecycle.whiteBalance == .refreshing(refresh, previous: fixture.lock))
        _ = lifecycle.receive(.recordingEnded(recording, fixture.end))
        #expect(lifecycle.receive(.whiteBalanceLocked(refresh, fixture.lock)) == .rejected(.duplicateOrOutOfOrder))
        #expect(lifecycle.refreshWhiteBalance(operation: .init(rawValue: "synthetic-late-refresh")) == .rejected(.wrongStage))
        #expect(fixture.intent.desired.exposure == fixture.desired.exposure)
    }

    @Test func nextClipMeasuresNewWBAndRejectsOldClipAndGeneration() throws {
        let first = try CaptureFixture()
        var one = CaptureLifecycle(context: first.context, audio: first.audio)
        let oldRecording = try requestRecorderStart(&one, fixture: first)
        _ = one.receive(.recordingEnded(oldRecording, first.end))

        let second = try CaptureFixture(clip: "synthetic-clip-2")
        var two = CaptureLifecycle(context: second.context, audio: second.audio)
        #expect(two.whiteBalance == .automatic)
        let tokens = try beginCapture(&two, fixture: second)
        #expect(two.whiteBalance == .locking(tokens.whiteBalance))
        #expect(two.receive(.recordingEnded(oldRecording, first.end)) == .rejected(.wrongContext))
        let newLock = CaptureWhiteBalanceLock(gains: try .init(red: 2, green: 1, blue: 1.2),
                                             measuredAt: second.time, appliedAt: second.time)
        _ = two.receive(.whiteBalanceLocked(tokens.whiteBalance, newLock))
        #expect(two.whiteBalance == .locked(newLock))
        #expect(newLock != first.lock)
        let oldGeneration = try CaptureFixture(clip: "synthetic-clip-2", settingsGeneration: 3)
        #expect(two.receive(.whiteBalanceLocked(oldGeneration.token(tokens.whiteBalance.ordinal), first.lock))
                == .rejected(.wrongContext))
    }

    @Test(arguments: [true, false])
    func intentFailureOrUnknownEndsWithoutStartingAndKeepsPersistenceTruth(unknown: Bool) throws {
        let fixture = try CaptureFixture()
        var lifecycle = CaptureLifecycle(context: fixture.context, audio: fixture.audio)
        let tokens = try beginCapture(&lifecycle, fixture: fixture)
        _ = lifecycle.receive(.whiteBalanceLocked(tokens.whiteBalance, fixture.lock))
        let result: RecordingStoreResult = unknown
            ? .unavailable(tokens.intent, .resourceUnavailable)
            : .rejected(tokens.intent, .revisionConflict)
        let effects = try captureEffects(lifecycle.receiveIntentStoreResult(result))
        #expect(lifecycle.end?.writer == .notStarted)
        #expect(lifecycle.intentPersistence == (unknown ? .unknown(.resourceUnavailable) : .rejected(.revisionConflict)))
        #expect(!effects.contains { if case .capture(.startRecording) = $0 { return true }; return false })
        #expect(effects.contains { if case .capture(.restoreAutomaticWhiteBalance) = $0 { return true }; return false })
        #expect(lifecycle.receiveIntentCommit(fixture.receipt(tokens.intent)) == .rejected(.duplicateOrOutOfOrder))
    }

    @Test(arguments: [true, false])
    func confirmedInputOrWriterFailureStopsButZeroLevelDoesNot(writerFailure: Bool) throws {
        let fixture = try CaptureFixture()
        var lifecycle = CaptureLifecycle(context: fixture.context, audio: fixture.audio)
        let recording = try requestRecorderStart(&lifecycle, fixture: fixture)
        _ = lifecycle.receive(.recordingStarted(recording, fixture.time))
        #expect(try captureEffects(lifecycle.receive(.audioObserved(fixture.context, sequence: 1, fixture.audio))).isEmpty)
        #expect(lifecycle.phase == .recording)
        var failed = fixture.audio
        let failure: CaptureAudioFailure = writerFailure
            ? .writerFailed(.init(rawValue: "synthetic-write-failure"))
            : .confirmedNoSamples(.init(rawValue: "synthetic-missing-samples"))
        if writerFailure { failed.writing = .failed(failure) } else { failed.input = .failed(failure) }
        let effects = try captureEffects(lifecycle.receive(.audioObserved(fixture.context, sequence: 3, failed)))
        #expect(effects == [.capture(.stopRecording(recording, reason: .audioFailure(failure)))])
        #expect(lifecycle.phase == .stopping)
        #expect(lifecycle.whiteBalance == .locked(fixture.lock))
        #expect(lifecycle.receive(.audioObserved(fixture.context, sequence: 2, fixture.audio))
                == .rejected(.duplicateOrOutOfOrder))
        #expect(lifecycle.audio.confirmedFailure == failure)
    }
}
