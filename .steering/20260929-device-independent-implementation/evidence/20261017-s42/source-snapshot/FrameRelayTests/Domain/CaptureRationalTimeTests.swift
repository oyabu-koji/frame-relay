import Foundation
import Testing
@testable import FrameRelay

struct CaptureRationalTimeTests {
    @Test func exactFractionsHaveEqualHashesWithoutChangingTheirRepresentation() throws {
        let desired = try CaptureRationalTime(ticks: 1, timescale: 50)
        let readback = try CaptureRationalTime(ticks: 12_000, timescale: 600_000)
        #expect(desired == readback)
        #expect(Set([desired, readback]).count == 1)
        #expect(readback.ticks == 12_000)
        #expect(readback.timescale == 600_000)
        #expect(try desired != CaptureRationalTime(ticks: 12_001, timescale: 600_000))
    }

    @Test func zeroNegativeAndMinimumIntegerHaveNoAbsoluteValueOverflow() throws {
        #expect(try CaptureRationalTime(ticks: 0, timescale: 1) == CaptureRationalTime(ticks: 0, timescale: Int32.max))
        #expect(try CaptureRationalTime(ticks: -2, timescale: 4) == CaptureRationalTime(ticks: -1, timescale: 2))
        #expect(try CaptureRationalTime(ticks: Int64.min, timescale: 2)
                == CaptureRationalTime(ticks: Int64.min / 2, timescale: 1))
        let smallest = try CaptureRationalTime(ticks: Int64.min, timescale: 1)
        #expect(Set([smallest, smallest]).count == 1)
    }

    @Test func invalidDecodedScaleDoesNotNormalizeIntoValidTime() throws {
        let invalid = try JSONDecoder().decode(CaptureRationalTime.self, from: Data(#"{"ticks":-1,"timescale":-1}"#.utf8))
        let zeroScale = try JSONDecoder().decode(CaptureRationalTime.self, from: Data(#"{"ticks":0,"timescale":0}"#.utf8))
        #expect(try invalid != CaptureRationalTime(ticks: 1, timescale: 1))
        #expect(try zeroScale != CaptureRationalTime(ticks: 0, timescale: 1))
        #expect(Set([invalid, zeroScale]).count == 2)
    }
}
