import Testing
@testable import FrameRelay

struct CaptureAudioRecoveryTests {
    @Test func finiteRecoveryRejectsOldResponsesAndExhausts() throws {
        let fixture = try CaptureFixture()
        let policy = try CaptureAudioRecoveryPolicy(maximumAttempts: 2, attemptTimeout: .init(ticks: 3, timescale: 1))
        var recovery = CaptureAudioRecovery(context: fixture.context, policy: policy)
        let failure = CaptureAudioFailure.routeInterrupted(.init(rawValue: "synthetic-route-failure"))
        let first = try recovery.begin(after: failure)
        let retry = try recovery.complete(first, outcome: .failed(failure))
        let second = try #require(retry)
        #expect(throws: CaptureContractError.duplicateOrOutOfOrder) {
            try recovery.complete(first, outcome: .validInput(route: "synthetic-route"))
        }
        #expect(try recovery.complete(second, outcome: .failed(failure)) == nil)
        #expect(recovery.phase == .exhausted(failure))
        #expect(throws: CaptureContractError.wrongStage) { try recovery.begin(after: failure) }
    }

    @Test func successfulRecoveryOnlyReturnsReadyForUserREC() throws {
        let fixture = try CaptureFixture()
        let policy = try CaptureAudioRecoveryPolicy(maximumAttempts: 2, attemptTimeout: .init(ticks: 3, timescale: 1))
        var recovery = CaptureAudioRecovery(context: fixture.context, policy: policy)
        let first = try recovery.begin(after: .confirmedNoSamples(.init(rawValue: "synthetic-gap")))
        #expect(try recovery.complete(first, outcome: .validInput(route: "synthetic-new-route")) == nil)
        #expect(recovery.phase == .readyForUserREC(route: "synthetic-new-route"))
        // Its only possible output is another audio attempt, never a REC command.
        var capture = CaptureLifecycle(context: fixture.context, audio: fixture.audio)
        #expect(capture.phase == .ready)
        _ = try beginCapture(&capture, fixture: fixture) // A new explicit user action is still required.
        #expect(capture.phase == .starting)
    }
}
