import Foundation
import Testing
@testable import FrameRelay

@MainActor
struct ProductCaptureZoomCompositionTests {
    @Test func ordinaryCompositionInjectsVersionedZoomAndKeepsUnagreedISODisabled() async throws {
        let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("FrameRelay-capture-zoom-policy-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        let services = try await ProductLibraryFactory(supportDirectory: parent).open()
        let fixture = try CaptureFixture()
        let device = ZoomProductTestDevice(fixture: fixture)
        let model = ProductCaptureFactory.make(services: services, didSave: {}, makeDeviceWithControls: { _, _, _, _, zoom, iso in
            #expect(zoom == ProductCaptureFactory.provisionalZoomPolicyV1)
            #expect(zoom.version == "s47-provisional-v1")
            #expect(!zoom.isDeviceAdopted)
            #expect(iso == nil)
            return device
        })
        model.enterCapture(); await model.load()
        await model.updatePreferences(.init(desired: fixture.desired, outputCandidate: .sampleWriter))
        await model.prepare()
        for _ in 0..<2_000 { if model.canControlZoom { break }; await Task.yield() }
        try #require(model.canControlZoom)
        model.selectZoomTarget(1.98)
        #expect(model.zoom.forecast?.target == 1.98)
        #expect(model.nearbyZoomStop?.factor == 2)
        #expect(await device.requests.isEmpty)
        try #require(model.canStartZoom)
        await model.startZoom()
        #expect(await device.requests.last?.command == .move(target: 1.98))
        await model.stopZoom(); await model.leaveCapture()
    }
}
