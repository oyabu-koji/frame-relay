import CoreMedia
import Testing
@testable import FrameRelay

struct OriginalPresentationSpanTests {
    @Test func tracksPresentationExtremaAcrossDecodeOrderAndTimescales() throws {
        var span = OriginalPresentationSpan(stream: "synthetic-video")
        for time in [CMTime(value: 2, timescale: 24), CMTime(value: 0, timescale: 24),
                     CMTime(value: 2, timescale: 48)] { try span.append(time) }
        guard case .verified(let samples) = span.inspection(readerCompleted: true),
              case .observed(let first, _) = samples.first,
              case .observed(let last, _) = samples.last else {
            Issue.record("Expected sample-level presentation bounds"); return
        }
        #expect(samples.count == 3)
        #expect(first.value.ticks == 0)
        #expect(last.value == (try CaptureRationalTime(ticks: 2, timescale: 24)))
        #expect(span.inspection(readerCompleted: false) == .unavailable(.evidenceMissing))
    }

    @Test func missingPerSampleTimesAndEpochMismatchNeverGuessEndpoints() throws {
        var missing = OriginalPresentationSpan(stream: "synthetic-audio")
        try missing.append(.zero)
        try missing.appendUnavailableSamples(3)
        #expect(missing.inspection(readerCompleted: true) == .verified(.init(
            first: .unavailable(.evidenceMissing), last: .unavailable(.evidenceMissing), count: 4)))
        var epochs = OriginalPresentationSpan(stream: "synthetic-video")
        try epochs.append(.zero)
        try epochs.append(CMTime(value: 1, timescale: 24, flags: .valid, epoch: 1))
        #expect(epochs.inspection(readerCompleted: true) == .verified(.init(
            first: .unavailable(.evidenceMissing), last: .unavailable(.evidenceMissing), count: 2)))
    }
}
