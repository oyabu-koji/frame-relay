import Foundation
import Testing
@testable import FrameRelay

struct CaptureSubjectSessionTests {
    @Test func independentExposureSelectionDoesNotChangeProtagonistOrAF() {
        var session = makeSession()
        let first = person(), second = person(x: 0.6)
        #expect(session.receive(result(session, 1, 1, [first, second]), now: 1))
        _ = session.command(.init(context: session.context, command: .selectProtagonist(first.id)), now: 1)
        let focus = session.action
        _ = session.command(.init(context: session.context, command: .toggleExposure(second.id)), now: 1)
        _ = session.command(.init(context: session.context, command: .toggleExposure(first.id)), now: 1)
        #expect(session.exposureTargets == [first.id, second.id])
        #expect(session.protagonist == first.id)
        #expect(session.action == focus)
        #expect(session.state == .following(first.id))
    }

    @Test func lostPersonReturnsWithinGraceButOtherPersonCannotTakeOverAndExpiryRequiresTap() {
        var session = makeSession()
        let selected = person(), other = person(x: 0.6)
        #expect(session.receive(result(session, 1, 1, [selected, other]), now: 1))
        _ = session.command(.init(context: session.context, command: .selectProtagonist(selected.id)), now: 1)
        #expect(session.receive(result(session, 2, 1.2, [other]), now: 1.2))
        #expect(session.state == .lostHolding(selected.id))
        #expect(session.action == .hold)
        let returning = CapturePersonCandidate(id: selected.id, bounds: selected.bounds, continuity: .reacquired)
        #expect(session.receive(result(session, 3, 2, [returning, other]), now: 2))
        #expect(session.state == .following(selected.id))
        #expect(session.receive(result(session, 4, 2.1, [other]), now: 2.1))
        #expect(session.expire(now: 5.2))
        #expect(session.state == .heldAwaitingSelection)
        #expect(session.receive(result(session, 5, 5.3, [returning]), now: 5.3))
        #expect(session.state == .heldAwaitingSelection)
        _ = session.command(.init(context: session.context, command: .selectProtagonist(selected.id)), now: 5.3)
        #expect(session.state == .following(selected.id))
    }

    @Test func staleSequenceTimeSelectionFramingAndGenerationAreRejected() {
        var session = makeSession()
        let first = person()
        let old = result(session, 1, 1, [first])
        #expect(session.receive(old, now: 1))
        #expect(!session.receive(old, now: 1.1))
        #expect(!session.receive(result(session, 2, 0.9, [first]), now: 1.1))
        #expect(!session.receive(result(session, 2, 2, [first]), now: 1.1))
        #expect(!session.receive(result(session, 2, 1, [first]), now: 2))
        _ = session.command(.init(context: session.context, command: .toggleExposure(first.id)), now: 1)
        #expect(!session.receive(old, now: 1.1))
        let priorContext = session.context
        session.invalidateFraming(2)
        #expect(!session.receive(.init(context: priorContext, sequence: 100, observedAt: 1.2, candidates: [first], available: true), now: 1.2))
        #expect(session.candidates.isEmpty)
        #expect(session.exposureTargets.isEmpty)
        let foreign = CaptureSubjectContext(generation: .init(session: .init(rawValue: "other"), settings: 1), framingRevision: 2, selectionRevision: 2)
        #expect(!session.receive(.init(context: foreign, sequence: 101, observedAt: 1.2, candidates: [first], available: true), now: 1.2))
    }

    @Test func trackingOffUsesContinuousPersonPriorityAndSceneTapRequiresFreshConfirmedAbsence() {
        var session = makeSession()
        let first = person()
        #expect(session.receive(result(session, 1, 1, [first]), now: 1))
        _ = session.command(.init(context: session.context, command: .selectProtagonist(first.id)), now: 1)
        _ = session.command(.init(context: session.context, command: .tracking(false)), now: 1)
        #expect(session.protagonist == nil)
        #expect(session.action == .continuous(first.bounds.center, personDriven: true))
        let tap = CaptureSubjectCommand.scenePoint(.init(x: 0.5, y: 0.4))
        #expect(session.command(.init(context: session.context, command: tap), now: 1) == nil)
        #expect(session.receive(result(session, 2, 1.2, []), now: 1.2))
        #expect(session.command(.init(context: session.context, command: tap), now: 1.3) == .continuous(.init(x: 0.5, y: 0.4), personDriven: false))
        #expect(session.state == .sceneAF)
        #expect(session.expire(now: 2.2))
        #expect(session.state == .unavailable)
        #expect(session.command(.init(context: session.context, command: tap), now: 2.2) == nil)
    }

    @Test func unconfiguredScenePolicyAndUnconfirmedIdentityCannotSilentlyBecomeTracking() {
        var session = makeSession(noPerson: .unconfigured)
        #expect(session.receive(result(session, 1, 1, []), now: 1))
        #expect(session.command(.init(context: session.context, command: .scenePoint(.init(x: 0.5, y: 0.5))), now: 1) == nil)
        let first = person()
        #expect(session.receive(result(session, 2, 1.1, [first]), now: 1.1))
        _ = session.command(.init(context: session.context, command: .selectProtagonist(first.id)), now: 1.1)
        #expect(session.receive(result(session, 3, 1.2, [first]), now: 1.2))
        #expect(session.state == .lostHolding(first.id))
        #expect(session.action == .hold)
    }

    @Test func whiteBalanceChangeInvalidatesOldFramesWithoutReplacingSelectedIdentity() {
        var session = makeSession()
        let first = person()
        _ = session.receive(result(session, 1, 1, [first]), now: 1)
        _ = session.command(.init(context: session.context, command: .selectProtagonist(first.id)), now: 1)
        let obsolete = result(session, 2, 1.2, [.init(id: first.id, bounds: first.bounds, continuity: .continuous)])
        session.invalidateWhiteBalance(now: 1.2)
        #expect(session.protagonist == first.id)
        #expect(session.candidates.isEmpty)
        #expect(session.action == .hold)
        #expect(!session.receive(obsolete, now: 1.3))
        let current = result(session, 3, 1.4, [.init(id: first.id, bounds: first.bounds, continuity: .continuous)])
        #expect(session.receive(current, now: 1.4))
        #expect(session.state == .following(first.id))
    }

    @Test func stoppedAnalysisExpiresWithoutAnyFurtherFrames() {
        var session = makeSession()
        let first = person()
        _ = session.receive(result(session, 1, 1, [first]), now: 1)
        _ = session.command(.init(context: session.context, command: .selectProtagonist(first.id)), now: 1)
        #expect(session.expire(now: 1.9))
        #expect(session.candidates.isEmpty)
        #expect(session.state == .lostHolding(first.id))
        #expect(session.action == .hold)
        #expect(session.expire(now: 5))
        #expect(session.state == .heldAwaitingSelection)
    }

    private func makeSession(noPerson: CaptureSubjectPolicy.NoPersonFocus = .tapPosition) -> CaptureSubjectSession {
        .init(context: .init(generation: .init(session: .init(rawValue: "subjects"), settings: 1), framingRevision: 1, selectionRevision: 0),
              policy: .init(version: "test-only", lostGrace: 3, noPersonFocus: noPerson))
    }
    private func person(x: Double = 0.1) -> CapturePersonCandidate {
        .init(id: .init(), bounds: .init(x: x, y: 0.1, width: 0.2, height: 0.5), continuity: .newDetection)
    }
    private func result(_ session: CaptureSubjectSession, _ sequence: UInt64, _ time: Double,
                        _ people: [CapturePersonCandidate]) -> CaptureSubjectAnalysis {
        .init(context: session.context, sequence: sequence, observedAt: time, candidates: people, available: true)
    }
}
