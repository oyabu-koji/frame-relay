import CoreGraphics
import Testing
@testable import FrameRelay

struct NativeCaptureSubjectGeometryTests {
    @Test func outputPixelsAreConvertedBeforeNormalizedPersonBoundsReachAFAndPreview() throws {
        var received: CGRect?
        let geometry = try #require(NativeCaptureSubjectGeometry.capture(width: 1920, height: 1080,
            rotation: 0, mirrored: false) { input in
                received = input
                // SDK conversion supplied for this frame, including its output scaling.
                return CGRect(x: 0.1, y: 0.15, width: 0.8, height: 0.7)
            })
        #expect(received == CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let mapped = try #require(geometry.metadataBounds(fromNormalizedOutput: .init(x: 0.25, y: 0.2, width: 0.5, height: 0.6)))
        #expect(abs(mapped.x - 0.3) < 0.000001)
        #expect(abs(mapped.y - 0.29) < 0.000001)
        #expect(abs(mapped.width - 0.4) < 0.000001)
        #expect(abs(mapped.height - 0.42) < 0.000001)
    }

    @Test func frameAgeUsesCaptureClockInsteadOfMarkingDelayedArrivalAsFresh() {
        #expect(NativeCaptureSubjectGeometry.observedAt(presentationSeconds: 10, clockSeconds: 10.2, uptime: 100, maximumAge: 0.8) == 99.8)
        #expect(NativeCaptureSubjectGeometry.observedAt(presentationSeconds: 10, clockSeconds: 11, uptime: 100, maximumAge: 0.8) == nil)
        #expect(NativeCaptureSubjectGeometry.observedAt(presentationSeconds: 11, clockSeconds: 10, uptime: 100, maximumAge: 0.8) == nil)
        #expect(NativeCaptureSubjectGeometry.observedAt(presentationSeconds: .nan, clockSeconds: 10, uptime: 100, maximumAge: 0.8) == nil)
    }

    @Test func failedCandidateConversionCannotBecomeSuccessfulEmptyDetection() {
        let geometry = NativeCaptureSubjectGeometry(outputAreaInMetadata: .init(x: 0, y: 0, width: 1, height: 1))
        let raw = CaptureSubjectAnalysis(context: .init(generation: .init(session: .init(rawValue: "geometry"), settings: 1),
            framingRevision: 1, selectionRevision: 0), sequence: 1, observedAt: 1,
            candidates: [.init(id: .init(), bounds: .init(x: .nan, y: 0, width: 0.2, height: 0.5), continuity: .newDetection)], available: true)
        let result = geometry.map(raw)
        #expect(!result.available)
        #expect(result.candidates.isEmpty)
    }

    @Test func unsupportedOrientationMirrorAndMissingGeometryRemainUnavailable() {
        for (rotation, mirrored) in [(90.0, false), (0.0, true), (Double.nan, false)] {
            var called = false
            #expect(NativeCaptureSubjectGeometry.capture(width: 1920, height: 1080, rotation: rotation, mirrored: mirrored) { _ in
                called = true; return CGRect(x: 0, y: 0, width: 1, height: 1)
            } == nil)
            #expect(!called)
        }
        #expect(NativeCaptureSubjectGeometry.capture(width: 1920, height: 1080, rotation: 0, mirrored: false) { _ in .zero } == nil)
    }
}
