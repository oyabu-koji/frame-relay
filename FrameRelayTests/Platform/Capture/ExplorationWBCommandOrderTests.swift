import Testing
@testable import FrameRelay

struct ExplorationWBCommandOrderTests {
    @Test(arguments: [true, false])
    func stopDuringMeasurementOrDelayedRelockWaitsForAppliedCurrentValues(measurementEnded: Bool) throws {
        let fixture = try CaptureFixture()
        var order = ExplorationWBCommandOrder(generation: fixture.context.generation)
        #expect(order.requestLock(fixture.token(2)) == true)
        #expect(order.appliedLock(fixture.token(2)) == true)
        let refresh = fixture.token(4)
        #expect(order.requestRefresh(refresh) == true)
        #expect(!order.canStart(fixture.context))
        #expect(order.requestRefresh(fixture.token(5)) == false)
        if measurementEnded { #expect(order.measurementCompleted(refresh) == true) }
        #expect(order.holdForStop(fixture.context) == (measurementEnded ? .waitForLock : .lockCurrent(refresh)))
        #expect(order.measurementCompleted(refresh) == false) // delayed/duplicate KVO cannot start another lock
        #expect(order.holdForStop(fixture.context) == .waitForLock)
        #expect(!order.shouldStopAfterLock(refresh))
        #expect(order.appliedLock(fixture.token(2)) == false) // earlier completion delivered out of order
        #expect(order.appliedLock(refresh) == true)
        #expect(order.shouldStopAfterLock(refresh))
        #expect(order.appliedLock(refresh) == false)
        #expect(order.holdForStop(fixture.context) == .stop)
        #expect(order.requestAutomatic(fixture.token(6)) == true)
        #expect(order.appliedAutomatic(fixture.token(6)) == true)
        #expect(order.measurementCompleted(refresh) == false)
        #expect(order.appliedLock(refresh) == false)
    }

    @Test func oneShotMeasurementIsExplicitAndCompletedOnlyOnce() throws {
        let fixture = try CaptureFixture()
        var order = ExplorationWBCommandOrder(generation: fixture.context.generation)
        #expect(order.requestRefresh(fixture.token(1)) == false) // standby cannot start Auto remeasurement
        #expect(order.requestLock(fixture.token(2)) == true)
        #expect(order.requestRefresh(fixture.token(3)) == false) // initial lock not yet applied
        #expect(order.appliedLock(fixture.token(2)) == true)
        #expect(order.measurementCompleted(fixture.token(4)) == false) // no request, even if SDK reports locked
        #expect(order.requestRefresh(fixture.token(4)) == true)
        #expect(order.appliedLock(fixture.token(4)) == false) // measurement is not yet an applied lock
        #expect(order.measurementCompleted(fixture.token(4)) == true)
        #expect(order.measurementCompleted(fixture.token(4)) == false)
        #expect(order.appliedLock(fixture.token(4)) == true)
        #expect(!order.shouldStopAfterLock(fixture.token(4)))
        #expect(order.requestRefresh(fixture.token(5)) == true)
        #expect(order.requestAutomatic(fixture.token(6)) == true) // unexpected recording end supersedes measurement
        #expect(order.measurementCompleted(fixture.token(5)) == false)
        #expect(order.appliedAutomatic(fixture.token(6)) == true)
        let second = try CaptureFixture(clip: "second")
        #expect(order.requestLock(second.token(2)) == true)
        #expect(order.measurementCompleted(fixture.token(5)) == false)
        #expect(order.appliedLock(fixture.token(5)) == false)
        #expect(order.appliedLock(second.token(2)) == true)
    }

    @Test func twoClipsRestartOrdinalsWithoutAcceptingTheOldClip() throws {
        let first = try CaptureFixture()
        let second = try CaptureFixture(clip: "synthetic-second")
        var order = ExplorationWBCommandOrder(generation: first.context.generation)
        let firstLockRequested = order.requestLock(first.token(2))
        #expect(firstLockRequested)
        let firstLockApplied = order.appliedLock(first.token(2))
        #expect(firstLockApplied)
        #expect(order.canStart(first.context))
        #expect(!order.canStart(second.context))
        let prematureSecondLock = order.requestLock(second.token(2))
        #expect(!prematureSecondLock)
        let firstAutoRequested = order.requestAutomatic(first.token(4))
        #expect(firstAutoRequested)
        let supersededFirstLock = order.appliedLock(first.token(2))
        #expect(!supersededFirstLock)
        let firstAutoApplied = order.appliedAutomatic(first.token(4))
        #expect(firstAutoApplied)
        let secondLockRequested = order.requestLock(second.token(2))
        #expect(secondLockRequested)
        let staleFirstLock = order.appliedLock(first.token(2))
        #expect(!staleFirstLock)
        let staleFirstAuto = order.requestAutomatic(first.token(5))
        #expect(!staleFirstAuto)
        let completedFirstLock = order.requestLock(first.token(6))
        #expect(!completedFirstLock)
        let secondLockApplied = order.appliedLock(second.token(2))
        #expect(secondLockApplied)
        #expect(order.canStart(second.context))
        #expect(!order.canStart(first.context))
    }

    @Test func pendingLockSupersededByAutoCannotApplyLater() throws {
        let fixture = try CaptureFixture()
        var order = ExplorationWBCommandOrder(generation: fixture.context.generation)
        let lockRequested = order.requestLock(fixture.token(2))
        #expect(lockRequested)
        let autoRequested = order.requestAutomatic(fixture.token(3))
        #expect(autoRequested)
        let supersededLock = order.appliedLock(fixture.token(2))
        #expect(!supersededLock)
        #expect(!order.canStart(fixture.context))
        let autoApplied = order.appliedAutomatic(fixture.token(3))
        #expect(autoApplied)
        let duplicateAuto = order.appliedAutomatic(fixture.token(3))
        #expect(!duplicateAuto)
    }
}
