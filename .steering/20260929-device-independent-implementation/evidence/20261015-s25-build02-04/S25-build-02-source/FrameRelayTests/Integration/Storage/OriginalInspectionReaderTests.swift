import Foundation
import Testing
@testable import FrameRelay

struct OriginalInspectionReaderTests {
    @Test(arguments: [true, false])
    func newReaderInspectsSyntheticTracksWithoutQualityPromotion(withAudio: Bool) async throws {
        try await withStorageRun { run in
            let fixture = try CaptureFixture()
            let originals = ManagedOriginalStore(run: run)
            let url = try await originals.reserve(original: fixture.intent.original)
            try await SyntheticMovieFixture.write(to: url, withAudio: withAudio)
            let inspector = AVOriginalInspectionAdapter(originals: originals)
            let response = await inspector.inspect(.init(token: fixture.token(4), original: fixture.intent.original))
            guard case .inspected(let token, let inspection) = response else {
                Issue.record("Expected completed Reader inspection of generated fixture"); return
            }
            #expect(token == fixture.token(4))
            #expect(inspection.video.hasSamples)
            if withAudio { #expect(inspection.audio.hasSamples) }
            else { #expect(inspection.audio == .missing) }
            #expect(inspection.playback == .unavailable(.notMeasured))
            #expect(inspection.completeness == .unknown(.evidenceMissing))
            #expect(inspection.format.value == nil)
            let observation = try #require(await inspector.observation(for: fixture.intent.original))
            #expect(observation.videoTrackCount == 1)
            #expect(observation.audioTrackCount == (withAudio ? 1 : 0))
            #expect(observation.dimensions == ["64x64"])
            #expect(observation.digest.byteCount > 0)

            // A new truncated copy only; the complete generated fixture is untouched.
            let truncated = CaptureOriginalReference(rawValue: "synthetic-truncated")
            let truncatedURL = try await originals.reserve(original: truncated)
            let handle = try FileHandle(forReadingFrom: url)
            let prefix: Data
            do { prefix = try handle.read(upToCount: 64) ?? Data(); try handle.close() }
            catch { try handle.close(); throw error }
            try prefix.write(to: truncatedURL, options: .withoutOverwriting)
            let damaged = await inspector.inspect(.init(token: fixture.token(5), original: truncated))
            guard case .unavailable = damaged else {
                Issue.record("Truncated fixture must remain unavailable"); return
            }
        }
    }
}
