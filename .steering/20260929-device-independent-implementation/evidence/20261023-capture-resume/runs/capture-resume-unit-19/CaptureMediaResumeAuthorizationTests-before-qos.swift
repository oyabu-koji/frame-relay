import Foundation
import Testing
@testable import FrameRelay

nonisolated struct CaptureMediaResumeAuthorizationTests {
    @Test func authorizationIsSingleUseOriginBoundAndConsumedEvenWhenTheActionThrows() throws {
        let admission = CaptureMediaAdmission()
        let other = CaptureMediaAdmission()
        let authorization = try #require(admission.authorizeResume())
        var calls = 0
        #expect(!other.performIfCurrent(authorization) { calls += 1 })
        #expect(calls == 0)
        let alias = authorization
        #expect(alias.performIfCurrent { calls += 1 })
        #expect(!authorization.performIfCurrent { calls += 1 })
        #expect(calls == 1)
        let failing = try #require(admission.authorizeResume())
        #expect(throws: CaptureResumeTestError.actionFailed) {
            try failing.performIfCurrent { throw CaptureResumeTestError.actionFailed }
        }
        #expect(!failing.performIfCurrent { calls += 1 })
        #expect(calls == 1)
    }

    @Test(arguments: [CaptureMediaPhase.recording, .saving, .recovery])
    func anyHoldAndBeginEndCycleInvalidatePreviouslyIssuedAuthorizations(phase: CaptureMediaPhase) throws {
        let admission = CaptureMediaAdmission()
        let before = try #require(admission.authorizeResume())
        let first = try captureBoundaryOwner()
        let second = try captureBoundaryOwner()
        admission.begin(first, phases: [phase])
        #expect(admission.authorizeResume() == nil)
        var calls = 0
        #expect(!before.performIfCurrent { calls += 1 })
        admission.begin(second, phases: [.recovery])
        admission.update(first, phases: [.saving])
        admission.end(first)
        #expect(admission.authorizeResume() == nil)
        admission.end(second)
        #expect(!admission.snapshot().isHeld)
        #expect(!before.performIfCurrent { calls += 1 })
        let fresh = try #require(admission.authorizeResume())
        #expect(fresh.performIfCurrent { calls += 1 })
        #expect(calls == 1)
    }

    @Test func synchronousActionFinishesBeforeConcurrentHoldCanReturnAndOldAuthorizationCannotActAgain() throws {
        let admission = CaptureMediaAdmission()
        let authorization = try #require(admission.authorizeResume())
        let owner = try captureBoundaryOwner()
        let actionStarted = DispatchSemaphore(value: 0)
        let finishAction = DispatchSemaphore(value: 0)
        let actionFinished = DispatchSemaphore(value: 0)
        let holdCalled = DispatchSemaphore(value: 0)
        let holdReturned = DispatchSemaphore(value: 0)
        let observations = CaptureResumeThreadObservations()
        let actionThread = Thread {
            let performed = authorization.performIfCurrent {
                observations.append("action-start")
                actionStarted.signal()
                // A test-only, finite gate forces real cross-thread contention;
                // production dispatch actions must contain no waiting or hops.
                if finishAction.wait(timeout: .now() + 5) != .success { observations.append("action-timeout") }
                observations.append("action-end")
            }
            observations.append(performed ? "authorized" : "rejected")
            actionFinished.signal()
        }
        defer { finishAction.signal() }
        actionThread.start()
        try #require(actionStarted.wait(timeout: .now() + 2) == .success)
        let holdThread = Thread {
            observations.append("begin-call")
            holdCalled.signal()
            admission.begin(owner, phases: [.recording])
            observations.append("begin-return")
            holdReturned.signal()
        }
        holdThread.start()
        try #require(holdCalled.wait(timeout: .now() + 2) == .success)
        #expect(holdReturned.wait(timeout: .now() + .milliseconds(50)) == .timedOut)
        finishAction.signal()
        try #require(actionFinished.wait(timeout: .now() + 2) == .success)
        try #require(holdReturned.wait(timeout: .now() + 2) == .success)
        let events = observations.snapshot()
        let actionEnd = try #require(events.firstIndex(of: "action-end"))
        let holdReturn = try #require(events.firstIndex(of: "begin-return"))
        #expect(actionEnd < holdReturn && !events.contains("action-timeout") && events.contains("authorized"))
        #expect(admission.snapshot().owners[owner] == [.recording])
        #expect(!authorization.performIfCurrent { observations.append("late-action") })
        admission.end(owner)
        #expect(!authorization.performIfCurrent { observations.append("late-action") })
        #expect(!observations.snapshot().contains("late-action"))
        Attachment.record(events.joined(separator: "\n"), named: "capture-resume-lock-order.txt")
    }
}

nonisolated private enum CaptureResumeTestError: Error, Equatable { case actionFailed }

/// Thread callbacks share this measurement value. Every mutable access is
/// guarded by lock; @unchecked Sendable describes that explicit synchronization.
nonisolated private final class CaptureResumeThreadObservations: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []
    func append(_ value: String) { lock.lock(); defer { lock.unlock() }; events.append(value) }
    func snapshot() -> [String] { lock.lock(); defer { lock.unlock() }; return events }
}
