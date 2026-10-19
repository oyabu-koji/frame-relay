import Testing
@testable import FrameRelay

struct NativeCaptureZoomTests {
    @Test func sdkCandidatesAreFilteredByActualRangeWithoutInventedIntegerStops() {
        let stops = NativeCaptureZoom.stops(range: 1.2...4.5, upscale: 1.8,
            secondary: [2.4, .nan, 8], switches: [1.5, 3.7, 1.5])
        #expect(stops.map(\.factor) == [1.2, 1.5, 1.8, 2.4, 3.7])
        #expect(stops.first?.basis == .nativeMinimum)
        #expect(!stops.contains { $0.factor == 2 || $0.factor == 3 || $0.factor == 4 })
    }

    @Test(arguments: [true, false]) func lateReadbackNeverExtendsTarget(inward: Bool) {
        var ramp = NativeCaptureZoomRamp(start: inward ? 1 : 4, target: 2)
        #expect(ramp.stopFactor(observed: inward ? 2.2 : 1.8, isRamping: true, tolerance: 0.005) == 2)
        #expect(ramp.stopFactor(observed: inward ? 1.5 : 2.5, isRamping: true, tolerance: 0.005) == nil)
        #expect(ramp.stopFactor(observed: inward ? 1.998 : 2.002, isRamping: true, tolerance: 0.005)
            == (inward ? 1.998 : 2.002))
    }

    @Test func sdkCancelledRampRetainsItsObservedPosition() {
        var ramp = NativeCaptureZoomRamp(start: 1, target: 4)
        #expect(ramp.stopFactor(observed: 1, isRamping: false, tolerance: 0.005) == nil)
        #expect(ramp.stopFactor(observed: 2.15, isRamping: false, tolerance: 0.005) == 2.15)
        #expect(ramp.stopFactor(observed: .nan, isRamping: true, tolerance: 0.005) == nil)
    }

    @Test func delayedMoveCannotRestartAfterNewerStopOrManualOperation() {
        var order = NativeCaptureZoomCommandOrder()
        #expect(order.admit(1))
        #expect(order.admit(3))
        #expect(!order.admit(2))
        #expect(!order.admit(3))
        #expect(order.admit(4))
    }
}
