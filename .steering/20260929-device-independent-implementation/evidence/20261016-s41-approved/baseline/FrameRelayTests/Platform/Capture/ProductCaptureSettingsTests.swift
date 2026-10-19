import Foundation
import AVFoundation
import Testing
@testable import FrameRelay

struct ProductCaptureSettingsTests {
    @Test func settingStoreReopenPreservesWishesWithoutCapabilitiesOrWBLock() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("settings.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let fixture = try CaptureFixture()
        let wish = ProductCapturePreferences(desired: fixture.desired, outputCandidate: .movieFile)
        let first = CapturePreferenceStore(url: url)
        #expect(try await first.load() == .init())
        try await first.save(wish)
        let reopened = CapturePreferenceStore(url: url)
        #expect(try await reopened.load() == wish)
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let encoded = try #require(object["preferences"] as? [String: Any])
        #expect(Set(encoded.keys) == ["desired", "outputCandidate"])
    }

    @Test(arguments: ["{\"schema\":999,\"preferences\":{}}", "not-json"])
    func unknownOrCorruptSettingsRemainUnchanged(data: String) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("settings.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data(data.utf8)
        try original.write(to: url)
        let store = CapturePreferenceStore(url: url)
        await #expect(throws: (any Error).self) { try await store.load() }
        await #expect(throws: (any Error).self) { try await store.save(.init()) }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func cameraAndFormatEnumerationOrderIsNotRestoredAsIdentity() throws {
        let fixture = try CaptureFixture()
        let configuration = fixture.desired.configuration
        let matching = ExplorationFormatDescription(id: "format-1", width: 3840, height: 2160,
            frameRateRanges: [24...30], logEncodings: [.appleLog], stabilizationModes: [configuration.stabilizationMode])
        let otherFormat = ExplorationFormatDescription(id: "format-2", width: 1920, height: 1080,
            frameRateRanges: [24...30], logEncodings: [.appleLog], stabilizationModes: [configuration.stabilizationMode])
        let wanted = ExplorationCameraDescription(id: configuration.camera, label: "A", isVirtual: false, formats: [matching, otherFormat])
        let other = ExplorationCameraDescription(id: "stable-other-device", label: "B", isVirtual: false, formats: [matching])
        #expect(ProductCaptureConfigurationMatcher.hasCurrentFormat(for: configuration, cameras: [wanted, other]))
        let reordered = ExplorationCameraDescription(id: configuration.camera, label: "A", isVirtual: false, formats: [otherFormat, matching])
        #expect(ProductCaptureConfigurationMatcher.hasCurrentFormat(for: configuration, cameras: [other, reordered]))
        #expect(!ProductCaptureConfigurationMatcher.hasCurrentFormat(for: configuration, cameras: [other]))
        let disappeared = ExplorationCameraDescription(id: configuration.camera, label: "A", isVirtual: false, formats: [otherFormat])
        #expect(!ProductCaptureConfigurationMatcher.hasCurrentFormat(for: configuration, cameras: [other, disappeared]))
    }

    @Test func observedCreationDateSurvivesWriterFinalizationAndAssetReopen() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        defer { try? FileManager.default.removeItem(at: url) }
        let observed = Date(timeIntervalSince1970: 1_700_000_000.125)
        try await SyntheticMovieFixture.write(to: url, withAudio: true, capturedAt: observed)
        let asset = AVURLAsset(url: url)
        let metadata = try await asset.loadMetadata(for: .quickTimeMetadata)
        let creation = try #require(metadata.first(where: { $0.identifier == .quickTimeMetadataCreationDate }))
        let value = try await creation.load(.stringValue)
        let encoded = try #require(value)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        #expect(formatter.date(from: encoded) == observed)
        #expect(CaptureCreationMetadata.items(capturedAt: nil).isEmpty)
    }
}
