import Foundation
import Testing
@testable import FrameRelay

struct CaptureSubjectSessionTests {
    @Test func independentExposureSelectionDoesNotChangeProtagonistOrAF() {
        var session = makeSession()
        let first = person(), second = person(x: 0.6)
        let outcome1 = session.receive(result(session, 1, 1, [first, second]), now: 1)
        #expect(outcome1)
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
        let outcome2 = session.receive(result(session, 1, 1, [selected, other]), now: 1)
        #expect(outcome2)
        _ = session.command(.init(context: session.context, command: .selectProtagonist(selected.id)), now: 1)
        let outcome3 = session.receive(result(session, 2, 1.2, [other]), now: 1.2)
        #expect(outcome3)
        #expect(session.state == .lostHolding(selected.id))
        #expect(session.action == .hold)
        let returning = CapturePersonCandidate(id: selected.id, bounds: selected.bounds, continuity: .reacquired)
        let outcome4 = session.receive(result(session, 3, 2, [returning, other]), now: 2)
        #expect(outcome4)
        #expect(session.state == .following(selected.id))
        let outcome5 = session.receive(result(session, 4, 2.1, [other]), now: 2.1)
        #expect(outcome5)
        let outcome6 = session.expire(now: 5.2)
        #expect(outcome6)
        #expect(session.state == .heldAwaitingSelection)
        let outcome7 = session.receive(result(session, 5, 5.3, [returning]), now: 5.3)
        #expect(outcome7)
        #expect(session.state == .heldAwaitingSelection)
        _ = session.command(.init(context: session.context, command: .selectProtagonist(selected.id)), now: 5.3)
        #expect(session.state == .following(selected.id))
    }

    @Test func staleSequenceTimeSelectionFramingAndGenerationAreRejected() {
        var session = makeSession()
        let first = person()
        let old = result(session, 1, 1, [first])
        let outcome8 = session.receive(old, now: 1)
        #expect(outcome8)
        let outcome9 = session.receive(old, now: 1.1)
        #expect(!outcome9)
        let outcome10 = session.receive(result(session, 2, 0.9, [first]), now: 1.1)
        #expect(!outcome10)
        let outcome11 = session.receive(result(session, 2, 2, [first]), now: 1.1)
        #expect(!outcome11)
        let outcome12 = session.receive(result(session, 2, 1, [first]), now: 2)
        #expect(!outcome12)
        _ = session.command(.init(context: session.context, command: .toggleExposure(first.id)), now: 1)
        let outcome13 = session.receive(old, now: 1.1)
        #expect(!outcome13)
        let priorContext = session.context
        session.invalidateFraming(2)
        let outcome14 = session.receive(.init(context: priorContext, sequence: 100, observedAt: 1.2, candidates: [first], available: true), now: 1.2)
        #expect(!outcome14)
        #expect(session.candidates.isEmpty)
        #expect(session.exposureTargets.isEmpty)
        let foreign = CaptureSubjectContext(generation: .init(session: .init(rawValue: "other"), settings: 1), framingRevision: 2, selectionRevision: 2)
        let outcome15 = session.receive(.init(context: foreign, sequence: 101, observedAt: 1.2, candidates: [first], available: true), now: 1.2)
        #expect(!outcome15)
    }

    @Test func trackingOffUsesContinuousPersonPriorityAndSceneTapRequiresFreshConfirmedAbsence() {
        var session = makeSession()
        let first = person()
        let outcome16 = session.receive(result(session, 1, 1, [first]), now: 1)
        #expect(outcome16)
        _ = session.command(.init(context: session.context, command: .selectProtagonist(first.id)), now: 1)
        _ = session.command(.init(context: session.context, command: .tracking(false)), now: 1)
        #expect(session.protagonist == nil)
        #expect(session.action == .continuous(first.bounds.center, personDriven: true))
        let tap = CaptureSubjectCommand.scenePoint(.init(x: 0.5, y: 0.4))
        let outcome17 = session.command(.init(context: session.context, command: tap), now: 1)
        #expect(outcome17 == nil)
        let outcome18 = session.receive(result(session, 2, 1.2, []), now: 1.2)
        #expect(outcome18)
        let outcome19 = session.command(.init(context: session.context, command: tap), now: 1.3)
        #expect(outcome19 == .continuous(.init(x: 0.5, y: 0.4), personDriven: false))
        #expect(session.state == .sceneAF)
        let outcome20 = session.expire(now: 2.2)
        #expect(outcome20)
        #expect(session.state == .unavailable)
        let outcome21 = session.command(.init(context: session.context, command: tap), now: 2.2)
        #expect(outcome21 == nil)
    }

    @Test func unconfiguredScenePolicyAndUnconfirmedIdentityCannotSilentlyBecomeTracking() {
        var session = makeSession(noPerson: .unconfigured)
        let outcome22 = session.receive(result(session, 1, 1, []), now: 1)
        #expect(outcome22)
        let outcome23 = session.command(.init(context: session.context, command: .scenePoint(.init(x: 0.5, y: 0.5))), now: 1)
        #expect(outcome23 == nil)
        let first = person()
        let outcome24 = session.receive(result(session, 2, 1.1, [first]), now: 1.1)
        #expect(outcome24)
        _ = session.command(.init(context: session.context, command: .selectProtagonist(first.id)), now: 1.1)
        let outcome25 = session.receive(result(session, 3, 1.2, [first]), now: 1.2)
        #expect(outcome25)
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
        let outcome26 = session.receive(obsolete, now: 1.3)
        #expect(!outcome26)
        let current = result(session, 3, 1.4, [.init(id: first.id, bounds: first.bounds, continuity: .continuous)])
        let outcome27 = session.receive(current, now: 1.4)
        #expect(outcome27)
        #expect(session.state == .following(first.id))
    }

    @Test func failedDetectionIsNotConfirmedAbsenceForSceneTap() {
        var session = makeSession()
        let initial = session.receive(result(session, 1, 1, []), now: 1)
        #expect(initial)
        let failure = CaptureSubjectAnalysis(context: session.context, sequence: 2, observedAt: 1.2, candidates: [], available: false)
        let received = session.receive(failure, now: 1.2)
        #expect(received)
        #expect(!session.analysisAvailable)
        let rejected = session.command(.init(context: session.context, command: .scenePoint(.init(x: 0.4, y: 0.5))), now: 1.2)
        #expect(rejected == nil)
        let recovered = session.receive(result(session, 3, 1.4, []), now: 1.4)
        #expect(recovered)
        let accepted = session.command(.init(context: session.context, command: .scenePoint(.init(x: 0.4, y: 0.5))), now: 1.4)
        #expect(accepted == .continuous(.init(x: 0.4, y: 0.5), personDriven: false))
    }

    @Test func invalidOrAmbiguousCandidatePayloadCannotBecomeConfirmedAbsence() {
        var session = makeSession()
        let first = person()
        let duplicate = session.receive(result(session, 1, 1, [first, first]), now: 1)
        #expect(duplicate)
        #expect(!session.analysisAvailable)
        let invalid = CapturePersonCandidate(id: .init(), bounds: .init(x: .nan, y: 0, width: 0.2, height: 0.5), continuity: .newDetection)
        let received = session.receive(result(session, 2, 1.2, [invalid]), now: 1.2)
        #expect(received)
        #expect(!session.analysisAvailable)
        let tap = session.command(.init(context: session.context, command: .scenePoint(.init(x: 0.4, y: 0.5))), now: 1.2)
        #expect(tap == nil)
    }

    @Test func personArrivalAfterSceneTapRestoresPersonPriorityWithoutSelectingProtagonist() {
        var session = makeSession()
        _ = session.receive(result(session, 1, 1, []), now: 1)
        _ = session.command(.init(context: session.context, command: .scenePoint(.init(x: 0.4, y: 0.5))), now: 1)
        #expect(session.state == .sceneAF)
        let appeared = person()
        let received = session.receive(result(session, 2, 1.2, [appeared]), now: 1.2)
        #expect(received)
        #expect(session.state == .personPriorityAF)
        #expect(session.scenePoint == nil)
        #expect(session.protagonist == nil)
        #expect(!session.trackingEnabled)
        #expect(session.action == .continuous(appeared.bounds.center, personDriven: true))
    }

    @Test func stoppedAnalysisExpiresWithoutAnyFurtherFrames() {
        var session = makeSession()
        let first = person()
        _ = session.receive(result(session, 1, 1, [first]), now: 1)
        _ = session.command(.init(context: session.context, command: .selectProtagonist(first.id)), now: 1)
        let outcome28 = session.expire(now: 1.9)
        #expect(outcome28)
        #expect(session.candidates.isEmpty)
        #expect(session.state == .lostHolding(first.id))
        #expect(session.action == .hold)
        let outcome29 = session.expire(now: 5)
        #expect(outcome29)
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
