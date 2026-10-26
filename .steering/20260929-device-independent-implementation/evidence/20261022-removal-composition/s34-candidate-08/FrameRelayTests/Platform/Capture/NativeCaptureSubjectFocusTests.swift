import Testing
@testable import FrameRelay

struct NativeCaptureSubjectFocusTests {
    @Test func protagonistAndHoldDisableAutomaticPersonSwitchingWhileOFFKeepsAF() throws {
        let point = CaptureSubjectPoint(x: 0.4, y: 0.6)
        let following = try #require(NativeCaptureSubjectFocus.plan(.continuous(point, personDriven: false),
            continuousSupported: true, lockSupported: true, pointSupported: true))
        #expect(!following.hold && !following.faceDriven && following.point == point)
        let held = try #require(NativeCaptureSubjectFocus.plan(.hold, continuousSupported: true, lockSupported: true, pointSupported: true))
        #expect(held.hold && !held.faceDriven)
        let off = try #require(NativeCaptureSubjectFocus.plan(.personPriority, continuousSupported: true, lockSupported: true, pointSupported: true))
        #expect(!off.hold && off.faceDriven)
    }

    @Test func unsupportedContinuousAFNeverFallsBackToLockOrWrongPoint() {
        #expect(NativeCaptureSubjectFocus.plan(.personPriority, continuousSupported: false, lockSupported: true, pointSupported: true) == nil)
        #expect(NativeCaptureSubjectFocus.plan(.continuous(.init(x: 0.4, y: 0.6), personDriven: false),
            continuousSupported: true, lockSupported: true, pointSupported: false) == nil)
        #expect(NativeCaptureSubjectFocus.plan(.continuous(.init(x: .nan, y: 0.6), personDriven: false),
            continuousSupported: true, lockSupported: true, pointSupported: true) == nil)
        #expect(NativeCaptureSubjectFocus.plan(.hold, continuousSupported: true, lockSupported: false, pointSupported: true) == nil)
    }
}
