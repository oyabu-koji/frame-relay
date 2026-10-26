import Testing
@testable import FrameRelay

struct NativeRecordingStartAdmissionTests {
    @Test(arguments: ["whiteBalance", "session", "audio"])
    func currentStartPreflightFailureProducesExactlyOneNeverStartedTerminal(failure: String) throws {
        let fixture = try CaptureFixture()
        let token = fixture.token(3)
        var admission = NativeRecordingStartAdmission()
        let decision = admission.admit(token: token, intentContext: fixture.context,
            generation: fixture.context.generation, activeToken: nil, ownsWhiteBalanceLock: true,
            whiteBalanceLocked: failure != "whiteBalance", sessionRunning: failure != "session",
            audioActive: failure != "audio", observedAt: fixture.time)
        guard case .rejected(.some(.recordingEnded(let endedToken, let evidence))) = decision else {
            Issue.record("Expected a terminal for this SDK-preflight rejection"); return
        }
        #expect(endedToken == token)
        #expect(evidence.writer == .notStarted)
        #expect(evidence.ceasedAt == fixture.time)
        #expect(evidence.lastVideo == .unavailable(.notMeasured))
        #expect(evidence.lastAudio == .unavailable(.notMeasured))
        #expect(admission.admit(token: token, intentContext: fixture.context,
            generation: fixture.context.generation, activeToken: nil, ownsWhiteBalanceLock: true,
            whiteBalanceLocked: false, sessionRunning: false, audioActive: false,
            observedAt: fixture.time) == .rejected(nil))
    }

    @Test(arguments: ["generation", "intent", "active", "lock"])
    func staleOrUnownedStartCannotTerminateAnotherCapture(mismatch: String) throws {
        let fixture = try CaptureFixture()
        let other = try CaptureFixture(clip: "other", settingsGeneration: 5)
        var admission = NativeRecordingStartAdmission()
        #expect(admission.admit(token: fixture.token(3), intentContext: mismatch == "intent" ? other.context : fixture.context,
            generation: mismatch == "generation" ? other.context.generation : fixture.context.generation,
            activeToken: mismatch == "active" ? other.token(3) : nil, ownsWhiteBalanceLock: mismatch != "lock",
            whiteBalanceLocked: false, sessionRunning: false, audioActive: false,
            observedAt: fixture.time) == .rejected(nil))
        // Rejected identities did not consume the valid capture's actual first attempt.
        #expect(admission.admit(token: fixture.token(3), intentContext: fixture.context,
            generation: fixture.context.generation, activeToken: nil, ownsWhiteBalanceLock: true,
            whiteBalanceLocked: true, sessionRunning: true, audioActive: true,
            observedAt: fixture.time) == .admitted)
    }

    @Test func alreadyAdmittedStartNeverBecomesNeverStartedOnReplayOrLaterHardwareFailure() throws {
        let fixture = try CaptureFixture()
        var admission = NativeRecordingStartAdmission()
        #expect(admission.admit(token: fixture.token(3), intentContext: fixture.context,
            generation: fixture.context.generation, activeToken: nil, ownsWhiteBalanceLock: true,
            whiteBalanceLocked: true, sessionRunning: true, audioActive: true,
            observedAt: fixture.time) == .admitted)
        #expect(admission.admit(token: fixture.token(3), intentContext: fixture.context,
            generation: fixture.context.generation, activeToken: fixture.token(3), ownsWhiteBalanceLock: true,
            whiteBalanceLocked: false, sessionRunning: false, audioActive: false,
            observedAt: fixture.time) == .rejected(nil))
        #expect(admission.admit(token: fixture.token(4), intentContext: fixture.context,
            generation: fixture.context.generation, activeToken: nil, ownsWhiteBalanceLock: true,
            whiteBalanceLocked: false, sessionRunning: false, audioActive: false,
            observedAt: fixture.time) == .rejected(nil))
    }
}
