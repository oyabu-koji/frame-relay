import Foundation
import Testing
@testable import FrameRelay

@MainActor
struct ProductCaptureZoomCoordinatorTests {
    @Test func previewOnlyThenMovementAndStopsStaySeparateFromRecordingAndIntent() async throws {
        let (model, device, save) = try await make()
        let persisted = model.preferences
        model.selectZoomTarget(2)
        #expect(model.zoom.forecast?.target == 2)
        #expect(model.currentApplied?.values.value?.zoom == 1)
        #expect(await device.requests.isEmpty)
        await model.record()
        try #require(await eventually { model.capture?.phase == .recording })
        let originalIntent = try #require(await save.intents.first)
        await model.startZoom()
        #expect(model.zoom.snapshot?.phase == .moving(target: 2))
        #expect(model.zoom.forecast == nil)
        await device.completeMovement(at: 1.5, moving: true)
        try #require(await eventually { model.currentApplied?.values.value?.zoom == 1.5 })
        await model.stopZoom()
        #expect(model.zoom.snapshot?.phase == .stopped)
        #expect(model.capture?.phase == .recording)
        #expect(await save.intents.first == originalIntent)
        model.selectZoomTarget(2)
        await model.startZoom()
        await model.stop() // REC stop has no zoom command side effect.
        try #require(await eventually { !model.isBusy })
        #expect(model.zoom.snapshot?.phase.isMoving == true)
        #expect(await device.requests.filter { $0.command == .stop }.count == 1)
        await device.completeMovement(at: 2)
        try #require(await eventually { model.canRecord })
        #expect(model.currentDesired?.zoom == 2)
        #expect(model.preferences == persisted)
        await model.record()
        try #require(await eventually { model.capture?.phase == .recording })
        #expect(await save.intents.last?.desired.zoom == 2)
        #expect(await save.intents.last?.applied.values.value?.zoom == 2)
        #expect(await save.intents.first == originalIntent)
        await model.stop(); await model.leaveCapture()
    }

    @Test func staleFramingAndAmbientReadbackCannotAuthorizeOldPreviewOrRewriteWishes() async throws {
        let (model, device, _) = try await make()
        model.selectZoomTarget(2)
        await device.emitAmbient(zoom: 1.2, sequence: 10)
        try #require(await eventually { model.currentApplied?.values.value?.zoom == 1.2 })
        #expect(model.zoom.forecast == nil)
        #expect(model.currentDesired?.zoom == 1)
        #expect(!model.canRecord)
        await model.startZoom()
        #expect(await device.requests.isEmpty)
        await device.emitAmbient(zoom: 1, sequence: 9)
        for _ in 0..<30 { await Task.yield() }
        #expect(model.currentApplied?.values.value?.zoom == 1.2)
        await model.switchLens("unconfirmed")
        #expect(await device.requests.isEmpty)
        #expect(model.zoomIssue != nil)
        await model.leaveCapture()
    }

    @Test func newManualValueWinsOverDelayedControlCompletionEvenWithHigherSequence() async throws {
        let gate = ProductCaptureTestGate()
        let (model, device, _) = try await make()
        await device.holdNext(gate)
        let old = Task { await model.setManualISO(200) }
        await gate.waitUntilHeld()
        await model.setManualISO(240)
        #expect(model.currentApplied?.values.value?.exposure.iso == 240)
        #expect(model.currentDesired?.exposure.iso == 240)
        let oldOperation = try #require(await device.requests.first?.operation)
        await device.emitObsolete(operation: oldOperation, iso: 200, sequence: 100)
        await gate.release(); await old.value
        for _ in 0..<30 { await Task.yield() }
        #expect(model.currentApplied?.values.value?.exposure.iso == 240)
        #expect(model.currentDesired?.exposure.iso == 240)
        #expect(model.canRecord)
        await model.leaveCapture()
    }

    @Test func stopDuringPendingStartWinsAndLateLeaveCannotClearNewVisit() async throws {
        let gate = ProductCaptureTestGate()
        let (model, device, _) = try await make()
        model.selectZoomTarget(2)
        await device.holdNext(gate)
        let moving = Task { await model.startZoom() }
        await gate.waitUntilHeld()
        #expect(model.canStopZoom)
        await model.stopZoom()
        #expect(model.zoom.snapshot?.phase == .stopped)
        await gate.release(); await moving.value
        #expect(model.zoom.snapshot?.phase == .stopped)
        model.selectZoomTarget(2); await model.startZoom()
        let leaveGate = ProductCaptureTestGate()
        await device.holdNext(leaveGate)
        let leaving = Task { await model.leaveCapture() }
        await leaveGate.waitUntilHeld()
        #expect(model.captureVisit == nil)
        #expect(!model.canRecord)
        let nextVisit = model.enterCapture()
        await model.prepare(visit: nextVisit)
        await leaveGate.release(); await leaving.value
        #expect(model.captureVisit == nextVisit)
        #expect(model.prepared != nil)
        await model.leaveCapture()
    }

    @Test func pendingReadbackAndEndedObservationNeverReusePrepareTimeAppliedValues() async throws {
        let (model, device, _) = try await make()
        await device.emitPending()
        try #require(await eventually { model.zoom.snapshot?.applied.values.value == nil })
        #expect(model.currentApplied?.values.value == nil)
        #expect(!model.canRecord)
        await device.finish()
        try #require(await eventually { model.zoom.snapshot == nil })
        #expect(!model.canRecord)
        await model.leaveCapture()
    }

    private func make() async throws -> (ProductCaptureCoordinator, ZoomProductTestDevice, ProductCaptureTestSave) {
        let fixture = try CaptureFixture()
        let device = ZoomProductTestDevice(fixture: fixture)
        let save = ProductCaptureTestSave()
        let model = ProductCaptureCoordinator(preferences: ProductCaptureTestPreferences(fixture: fixture),
            makeDevice: { _ in device }, save: save, bindOriginal: { _ in true }, didSave: {},
            zoomPolicy: .provisionalV1, calendarNow: { Date() })
        model.enterCapture(); await model.load(); await model.prepare()
        try #require(await eventually { model.zoom.snapshot != nil })
        try #require(model.canRecord)
        return (model, device, save)
    }

    private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<2_000 { if condition() { return true }; await Task.yield() }
        return condition()
    }
}

actor ZoomProductTestDevice: ProductCaptureDevicePort {
    private let fixture: CaptureFixture
    private let underlying: ProductCaptureTestDevice
    private let pair = AsyncStream<CaptureZoomSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(16))
    private var snapshot: CaptureZoomSnapshot?
    private var nextGate: ProductCaptureTestGate?
    private(set) var requests: [CaptureZoomRequest] = []
    init(fixture: CaptureFixture) { self.fixture = fixture; underlying = .init(fixture: fixture) }
    func events() async -> AsyncStream<CaptureIOEvent> { await underlying.events() }
    func productEvents() async -> AsyncStream<ExplorationDeviceEvent> { await underlying.productEvents() }
    func discoverCameras() async throws -> [ExplorationCameraDescription] { await underlying.discoverCameras() }
    func previewSource() async -> (any ProductCapturePreviewSource)? { nil }
    func submit(_ command: CaptureIOCommand) async -> CaptureCommandAcceptance { await underlying.submit(command) }
    func shutDown() async { await underlying.shutDown() }
    func zoomSnapshots() -> AsyncStream<CaptureZoomSnapshot> { pair.stream }
    func stabilizationSnapshots() async -> AsyncStream<CaptureStabilizationSnapshot> { await underlying.stabilizationSnapshots() }
    func holdNext(_ gate: ProductCaptureTestGate) { nextGate = gate }
    func prepare(_ request: ProductCapturePreparation) async throws -> ExplorationPrepared {
        let result = try await underlying.prepare(request)
        let snapshot = try zoomTestSnapshot(fixture: fixture, generation: request.generation, sequence: 1, revision: 1)
        self.snapshot = snapshot; pair.continuation.yield(snapshot)
        return .init(capabilities: result.capabilities, applied: result.applied, audio: result.audio, stabilization: snapshot.stabilization)
    }
    func updateZoom(_ request: CaptureZoomRequest) async -> CaptureZoomSnapshot? {
        requests.append(request)
        guard let old = snapshot, old.context.generation == request.context.generation else { return nil }
        let gate = nextGate; nextGate = nil
        let iso: Double
        let phase: CaptureZoomPhase
        switch request.command {
        case .move(let target): phase = .moving(target: target); iso = old.desired.exposure.iso
        case .stop: phase = .stopped; iso = old.desired.exposure.iso
        case .manualISO(let value): phase = .stopped; iso = value
        case .switchLens: return nil
        }
        guard let result = try? zoomTestSnapshot(fixture: fixture, generation: old.context.generation,
            sequence: old.sequence + 1, revision: old.context.revision + 1, zoom: old.desired.zoom,
            iso: iso, phase: phase, operation: request.operation) else { return nil }
        snapshot = result
        await gate?.holdOnce()
        return result
    }
    func completeMovement(at zoom: Double, moving: Bool = false) {
        guard let old = snapshot, let result = try? zoomTestSnapshot(fixture: fixture, generation: old.context.generation,
            sequence: old.sequence + 1, revision: old.context.revision + 1, zoom: zoom,
            iso: old.desired.exposure.iso, phase: moving ? old.phase : .stopped, operation: old.operation) else { return }
        snapshot = result; pair.continuation.yield(result)
    }
    func emitAmbient(zoom: Double, sequence: UInt64) {
        guard let old = snapshot, let result = try? zoomTestSnapshot(fixture: fixture, generation: old.context.generation,
            sequence: sequence, revision: sequence, zoom: zoom) else { return }
        snapshot = result; pair.continuation.yield(result)
    }
    func emitObsolete(operation: UUID, iso: Double, sequence: UInt64) {
        guard let old = snapshot, let result = try? zoomTestSnapshot(fixture: fixture, generation: old.context.generation,
            sequence: sequence, revision: sequence, iso: iso, operation: operation) else { return }
        pair.continuation.yield(result)
    }
    func emitPending() {
        guard let old = snapshot, let result = try? zoomTestSnapshot(fixture: fixture, generation: old.context.generation,
            sequence: old.sequence + 1, revision: old.context.revision + 1, unavailable: true) else { return }
        snapshot = result; pair.continuation.yield(result)
    }
    func finish() { pair.continuation.finish() }
}
