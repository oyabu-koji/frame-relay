import Testing
@testable import FrameRelay

struct ExplorationWBCommandOrderTests {
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
