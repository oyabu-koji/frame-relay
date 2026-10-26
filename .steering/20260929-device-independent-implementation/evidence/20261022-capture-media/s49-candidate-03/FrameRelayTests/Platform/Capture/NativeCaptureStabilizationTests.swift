import AVFoundation
import Testing
@testable import FrameRelay

struct NativeCaptureStabilizationTests {
    @Test(arguments: [ExplorationOutputCandidate.movieFile, .sampleWriter])
    func bothOutputsRequireConnectionAndRequestedModeSupport(output: ExplorationOutputCandidate) {
        #expect(NativeCaptureStabilization.admission(output: output, requested: "standard", connectionExists: false,
                                                     supportsStabilization: true) != nil)
        #expect(NativeCaptureStabilization.admission(output: output, requested: "off", connectionExists: false,
                                                     supportsStabilization: false) != nil)
        #expect(NativeCaptureStabilization.admission(output: output, requested: "standard", connectionExists: true,
                                                     supportsStabilization: false) == "stabilization_connection_unsupported")
        #expect(NativeCaptureStabilization.admission(output: output, requested: "off", connectionExists: true,
                                                     supportsStabilization: false) == nil)
        #expect(NativeCaptureStabilization.admission(output: output, requested: "cinematic", connectionExists: true,
                                                     supportsStabilization: true) == nil)
        #expect(NativeCaptureStabilization.admission(output: output, requested: "previewOptimized", connectionExists: true,
                                                     supportsStabilization: true) == "stabilization_preview_only")
    }

    @Test func sdkModesRetainStableIDsWithoutTreatingAutoAsAnAppliedKnownMode() {
        #expect(ExplorationCaptureValues.stabilizationModes.map(\.0) == CaptureStabilizationCatalog.modes)
        #expect(ExplorationCaptureValues.stabilizationName(.off) == "off")
        #expect(ExplorationCaptureValues.stabilizationName(.auto) == nil)
    }
}
