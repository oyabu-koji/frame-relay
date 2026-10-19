import Foundation
import Testing
@testable import FrameRelay

@MainActor
struct ProductCaptureNDCoordinatorTests {
    @Test func pendingWarningsAndExpiredNDNeverGateRECAndStoppedStreamClearsOK() async throws {
        let fixture = try CaptureFixture()
        let device = NDCoordinatorDevice(fixture: fixture)
        let model = makeModel(fixture: fixture, device: device, policy: .provisionalV1(maximumResultAge: 0.05))
        await model.load(); await model.prepare()
        #expect(model.canRecord)
        await model.chooseShootingIntent(.scenery)
        await device.emit(.acceptable)
        await eventually { model.ndAdvice.direction == .acceptable }
        try await Task.sleep(for: .milliseconds(80))
        #expect(model.ndAdvice == .pending(.stale))
        #expect(model.canRecord)
        await device.emit(.difficult)
        await eventually { model.ndAdvice.direction == .difficult }
        await model.record()
        await eventually { model.capture?.phase == .recording }
        await device.emit(.pending)
        await eventually { model.ndAdvice.direction == .pending }
        #expect(model.capture?.phase == .recording)
        #expect(model.preferences.desired == fixture.desired)
        await device.emit(.acceptable)
        await eventually { model.ndAdvice.direction == .acceptable }
        await device.endND()
        await eventually { model.ndAdvice == .pending(.stopped) }
        #expect(model.capture?.phase == .recording)
        await model.stop()
        await eventually { !model.isBusy }
        await model.leaveCapture()
        #expect(model.ndSnapshot == nil)
    }

    @Test func intentContextSequenceAndLateVisitCannotRestoreOldOK() async throws {
        let fixture = try CaptureFixture()
        let device = NDCoordinatorDevice(fixture: fixture)
        let model = makeModel(fixture: fixture, device: device)
        await model.load(); await model.prepare(); await model.chooseShootingIntent(.scenery)
        await device.emit(.acceptable, sequence: 3, wb: 2)
        await eventually { model.ndAdvice.direction == .acceptable }
        await device.emit(.acceptable, sequence: 2)
        await eventually { model.ndAdvice == .pending(.outOfOrder) }
        await device.emit(.acceptable, sequence: 4, wb: 1)
        for _ in 0..<30 { await Task.yield() }
        #expect(model.ndAdvice.direction == .pending)
        await model.chooseShootingIntent(.people)
        await device.emit(.acceptable, sequence: 5, wb: 3, intentOverride: .scenery)
        for _ in 0..<30 { await Task.yield() }
        #expect(model.ndAdvice.direction == .pending)
        await model.leaveCapture()
        await device.emit(.acceptable, sequence: 6, wb: 3)
        for _ in 0..<30 { await Task.yield() }
        #expect(model.ndSnapshot == nil)
        #expect(!model.canRecord)
    }

    @Test func policyMissingNeverShowsInjectedSuccessButKeepsRECAvailable() async throws {
        let fixture = try CaptureFixture()
        let device = NDCoordinatorDevice(fixture: fixture)
        let model = makeModel(fixture: fixture, device: device, policy: nil)
        await model.load(); await model.prepare(); await model.chooseShootingIntent(.scenery)
        await device.emit(.acceptable)
        for _ in 0..<30 { await Task.yield() }
        #expect(model.ndAdvice == .pending(.policyUnavailable))
        #expect(model.canRecord)
        await model.leaveCapture()
    }

    private func makeModel(fixture: CaptureFixture, device: NDCoordinatorDevice,
                           policy: CaptureNDPolicy? = .provisionalV1(maximumResultAge: 1)) -> ProductCaptureCoordinator {
        let model = ProductCaptureCoordinator(preferences: ProductCaptureTestPreferences(fixture: fixture),
            makeDevice: { _ in device }, save: ProductCaptureTestSave(), bindOriginal: { _ in true }, didSave: {},
            subjectPolicy: .init(version: "test", lostGrace: 3, noPersonFocus: .tapPosition), ndPolicy: policy, calendarNow: { Date() })
        model.enterCapture(); return model
    }
    private func eventually(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<2_000 { if condition() { return }; await Task.yield() }
        #expect(condition())
    }
}

private actor NDCoordinatorDevice: ProductCaptureDevicePort {
    let underlying: ProductCaptureTestDevice
    private var generation: CaptureGeneration?
    private var intent: CaptureShootingIntent?
    private var sequence: UInt64 = 0
    private let pair = AsyncStream<CaptureNDSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
    init(fixture: CaptureFixture) { underlying = ProductCaptureTestDevice(fixture: fixture) }
    func events() async -> AsyncStream<CaptureIOEvent> { await underlying.events() }
    func productEvents() async -> AsyncStream<ExplorationDeviceEvent> { await underlying.productEvents() }
    func discoverCameras() async throws -> [ExplorationCameraDescription] { await underlying.discoverCameras() }
    func prepare(_ request: ProductCapturePreparation) async throws -> ExplorationPrepared {
        generation = request.generation; return try await underlying.prepare(request)
    }
    func previewSource() async -> (any ProductCapturePreviewSource)? { await underlying.previewSource() }
    func submit(_ command: CaptureIOCommand) async -> CaptureCommandAcceptance { await underlying.submit(command) }
    func shutDown() async { await underlying.shutDown() }
    func ndSnapshots() -> AsyncStream<CaptureNDSnapshot> { pair.stream }
    func updateNDIntent(_ intent: CaptureShootingIntent?, generation: CaptureGeneration) { if self.generation == generation { self.intent = intent } }
    func endND() { pair.continuation.finish() }
    func emit(_ direction: CaptureNDDirection, sequence override: UInt64? = nil, wb: UInt64 = 0,
              intentOverride: CaptureShootingIntent? = nil) {
        guard let generation else { return }
        sequence = override ?? sequence + 1
        let context = CaptureNDContext(generation: generation, framingRevision: 1, selectionRevision: 0,
            whiteBalanceRevision: wb, intent: intentOverride ?? intent)
        let advice = CaptureNDAdvice(direction: direction, reasons: direction == .acceptable ? [.withinReference] : [.evaluating])
        let result = CaptureNDResult(context: context, sequence: sequence, observedAt: ProcessInfo.processInfo.systemUptime,
            advice: advice, evidence: nil)
        pair.continuation.yield(.init(context: context, sequence: sequence, result: result, advice: advice))
    }
}
