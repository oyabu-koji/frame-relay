import Testing
@testable import FrameRelay

struct NativeCaptureLensTests {
    @Test(arguments: 0..<7) func rejectsEachUnsupportedBoundaryBeforeSDKMutation(boundary: Int) {
        let value = NativeCaptureLens.Admission(member: boundary != 0, lockingSupported: boundary != 1,
            formatMatches: boundary != 2, stabilizationMatches: boundary != 3,
            manualExposureSupported: boundary != 4, compensationAvailable: boundary != 5,
            movieOverrideDisabled: boundary != 6)
        #expect(value.failure != nil)
    }

    @Test func bothOutputPathsRequireSameConfirmedContract() {
        let value = NativeCaptureLens.Admission(member: true, lockingSupported: true, formatMatches: true,
            stabilizationMatches: true, manualExposureSupported: true, compensationAvailable: true,
            movieOverrideDisabled: true)
        #expect(value.failure == nil)
    }

    @Test func newerManualValueSupersedesDelayedSwitchCompensation() {
        var order = NativeCaptureLensExposureOrder()
        let compensation = order.begin(manual: false)
        let manual = order.begin(manual: true)
        let oldCompleted = order.complete(compensation)
        #expect(!oldCompleted)
        #expect(order.pending == manual)
        let manualCompleted = order.complete(manual)
        #expect(manualCompleted)
        #expect(order.manualRevision == 1)
        let oldDuplicate = order.complete(compensation)
        let manualDuplicate = order.complete(manual)
        #expect(!oldDuplicate && !manualDuplicate)
    }

    @Test func returningLensUsesLatestManualRevisionAndSessionResetRejectsOldCompletion() {
        var order = NativeCaptureLensExposureOrder()
        let manual = order.begin(manual: true)
        let manualCompleted = order.complete(manual)
        #expect(manualCompleted)
        let outbound = order.begin(manual: false)
        let outboundCompleted = order.complete(outbound)
        #expect(outboundCompleted)
        let returning = order.begin(manual: false)
        #expect(returning.manualRevision == manual.manualRevision)
        order.invalidate()
        let next = order.begin(manual: true)
        let previousCompleted = order.complete(returning)
        let nextCompleted = order.complete(next)
        #expect(!previousCompleted && nextCompleted)
        #expect(next.manualRevision > manual.manualRevision)
    }
}
