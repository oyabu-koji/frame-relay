import Foundation
import Testing
@testable import FrameRelay

@MainActor
struct ProductCaptureStabilizationCoordinatorTests {
    @Test func actualChangesAreVisibleWithoutMutatingWishesOrOtherControls() async throws {
        let fixture = try CaptureFixture()
        let preferences = ProductCaptureTestPreferences(fixture: fixture)
        let device = ProductCaptureTestDevice(fixture: fixture)
        await device.configureStabilization(active: fixture.desired.configuration.stabilizationMode)
        let model = makeModel(preferences: preferences, device: device)
        await model.load(); await model.prepare()
        #expect(model.canRecord)
        let prepared = model.prepared?.applied
        let wishes = model.preferences
        let generation = try #require(model.currentStabilization?.generation)
        let revision = model.framing.revision
        await device.emitStabilization(sequence: 3, active: "off")
        await eventually { model.currentStabilization?.sequence == 3 }
        #expect(!model.canRecord)
        #expect(model.currentStabilization?.activeMode.value == "off")
        #expect(model.framing.revision > revision)
        #expect(model.preferences == wishes)
        #expect(await preferences.load() == wishes)
        #expect(model.prepared?.applied == prepared)
        await device.emitStabilization(sequence: 2, active: fixture.desired.configuration.stabilizationMode)
        await device.emitStabilization(sequence: 100, active: "off",
            generation: .init(session: .init(rawValue: "obsolete"), settings: generation.settings))
        for _ in 0..<30 { await Task.yield() }
        #expect(model.currentStabilization?.sequence == 3)
        await device.emitStabilization(sequence: 4, active: nil, connection: .inactive)
        await eventually { model.currentStabilization?.sequence == 4 }
        #expect(!model.canRecord)
        #expect(model.currentStabilization?.activeMode.value == nil)
        await device.emitStabilization(sequence: 5, active: fixture.desired.configuration.stabilizationMode)
        await eventually { model.canRecord }
        #expect(model.framing.correctedFieldOfView.value == nil)
        #expect(model.framing.previewMatchesRecording == .unqueried)
        await model.leaveCapture()
        #expect(model.currentStabilization == nil)
    }

    @Test func prepareMismatchRemainsVisibleAndDoesNotSubstituteOFF() async throws {
        let fixture = try CaptureFixture()
        let preferences = ProductCaptureTestPreferences(fixture: fixture)
        let device = ProductCaptureTestDevice(fixture: fixture)
        await device.configureStabilization(active: "off")
        let model = makeModel(preferences: preferences, device: device)
        await model.load(); await model.prepare(); await model.record()
        #expect(!model.canRecord)
        #expect(model.currentStabilization?.preferredMode == fixture.desired.configuration.stabilizationMode)
        #expect(model.currentStabilization?.activeMode.value == "off")
        #expect(model.preferences.desired == fixture.desired)
        #expect(await device.startCount == 0)
        #expect(await preferences.load() == model.preferences)
        await model.leaveCapture()
    }

    @Test func recordingRejectsSettingChangesWhileCameraZoomAndModeObservationsInvalidateFraming() async throws {
        let fixture = try CaptureFixture()
        let preferences = ProductCaptureTestPreferences(fixture: fixture)
        let device = ProductCaptureTestDevice(fixture: fixture)
        await device.configureStabilization(active: fixture.desired.configuration.stabilizationMode)
        let model = makeModel(preferences: preferences, device: device)
        await model.load(); await model.prepare(); await model.record()
        await eventually { model.capture?.phase == .recording }
        let original = model.preferences
        let applied = model.prepared?.applied
        let revision = model.framing.revision
        let configuration = fixture.desired.configuration
        let changed = try CaptureConfiguration(camera: configuration.camera, width: configuration.width, height: configuration.height,
            framesPerSecond: configuration.framesPerSecond, codec: configuration.codec, logEncoding: configuration.logEncoding,
            stabilizationMode: "off")
        await model.updatePreferences(.init(desired: try .init(configuration: changed, exposure: fixture.desired.exposure, zoom: 1),
                                           outputCandidate: .movieFile))
        await model.prepare()
        #expect(model.preferences == original)
        #expect(await preferences.load() == original)
        #expect(await device.preparations == 1)
        await device.emitStabilization(sequence: 2, active: "off", zoom: 2, physicalCamera: "synthetic-tele")
        await eventually { model.currentStabilization?.sequence == 2 }
        #expect(model.framing.revision > revision)
        #expect(model.currentStabilization?.activePhysicalCamera == "synthetic-tele")
        #expect(model.currentStabilization?.zoom == 2)
        #expect(model.prepared?.applied == applied)
        #expect(model.preferences == original)
        #expect(model.capture?.phase == .recording)
        #expect(model.framing.correctedFieldOfView.value == nil)
        await model.stop()
        await eventually { !model.isBusy }
        #expect(!model.canRecord)
        await model.leaveCapture()
    }

    @Test func reprepareClearsFramingBeforeAwaitAndRejectsPreviousGenerationAfterwards() async throws {
        let fixture = try CaptureFixture()
        let old = ProductCaptureTestDevice(fixture: fixture)
        await old.configureStabilization(active: fixture.desired.configuration.stabilizationMode)
        let gate = ProductCaptureTestGate()
        let new = ProductCaptureTestDevice(fixture: fixture, prepareGate: gate)
        await new.configureStabilization(active: fixture.desired.configuration.stabilizationMode)
        let factory = ProductCaptureTestDeviceFactory([old, new])
        let model = ProductCaptureCoordinator(preferences: ProductCaptureTestPreferences(fixture: fixture),
            makeDevice: { await factory.make(candidate: $0) }, save: ProductCaptureTestSave(),
            bindOriginal: { _ in true }, didSave: {}, calendarNow: { Date() })
        model.enterCapture()
        await model.load(); await model.prepare()
        let previous = try #require(model.currentStabilization?.generation)
        let preparing = Task { await model.prepare() }
        await gate.waitUntilHeld()
        #expect(model.currentStabilization == nil)
        #expect(!model.canRecord)
        await old.emitStabilization(sequence: 100, active: "off")
        await gate.release()
        await preparing.value
        let current = try #require(model.currentStabilization?.generation)
        #expect(current != previous)
        await new.emitStabilization(sequence: 100, active: "off", generation: previous)
        for _ in 0..<30 { await Task.yield() }
        #expect(model.currentStabilization?.generation == current)
        #expect(model.canRecord)
        await model.leaveCapture()
        await new.emitStabilization(sequence: 101, active: "off")
        for _ in 0..<30 { await Task.yield() }
        #expect(model.currentStabilization == nil)
    }

    @Test func changedFormatCannotReusePreviousRecordingSupport() async throws {
        let fixture = try CaptureFixture()
        let device = ProductCaptureTestDevice(fixture: fixture)
        await device.configureStabilization(active: fixture.desired.configuration.stabilizationMode)
        let model = makeModel(preferences: ProductCaptureTestPreferences(fixture: fixture), device: device)
        await model.load(); await model.prepare()
        #expect(model.canRecord)
        await device.emitStabilization(sequence: 2, active: fixture.desired.configuration.stabilizationMode,
                                       formatID: "new-format")
        await eventually { model.currentStabilization?.sequence == 2 }
        #expect(!model.canRecord)
        await model.leaveCapture()
    }

    @Test func initiallyMissingSnapshotDoesNotRestoreStalePreparationAfterObservationStreamEnds() async throws {
        let fixture = try CaptureFixture()
        let old = ProductCaptureTestDevice(fixture: fixture)
        let new = ProductCaptureTestDevice(fixture: fixture)
        let factory = ProductCaptureTestDeviceFactory([old, new])
        let model = ProductCaptureCoordinator(preferences: ProductCaptureTestPreferences(fixture: fixture),
            makeDevice: { await factory.make(candidate: $0) }, save: ProductCaptureTestSave(),
            bindOriginal: { _ in true }, didSave: {}, calendarNow: { Date() })
        model.enterCapture()
        await model.load(); await model.prepare()
        #expect(model.prepared?.stabilization == nil)
        #expect(model.canRecord)
        await old.emitStabilization(sequence: 1, active: fixture.desired.configuration.stabilizationMode)
        await eventually { model.currentStabilization?.sequence == 1 }
        await old.finishStabilizationObservations()
        await eventually { model.framing.invalidation == .resourceUnavailable }
        #expect(model.currentStabilization == nil)
        #expect(!model.canRecord)
        await model.record()
        #expect(await old.startCount == 0)
        await model.prepare()
        #expect(model.canRecord)
        await model.leaveCapture()
    }

    @Test func legacyDefaultEmptyStabilizationStreamPreservesPrepareTimeRecordingAdmission() async throws {
        let fixture = try CaptureFixture()
        let underlying = ProductCaptureTestDevice(fixture: fixture)
        let legacy = LegacyStabilizationTestDevice(underlying: underlying)
        let stream = await legacy.stabilizationSnapshots()
        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first == nil)
        let model = makeModel(preferences: ProductCaptureTestPreferences(fixture: fixture), device: legacy)
        await model.load(); await model.prepare()
        for _ in 0..<30 { await Task.yield() }
        #expect(model.prepared?.stabilization == nil)
        #expect(model.currentStabilization == nil)
        #expect(model.canRecord)
        await model.record()
        await eventually { model.capture?.phase == .recording }
        #expect(await underlying.startCount == 1)
        await model.stop()
        await eventually { !model.isBusy }
        await model.leaveCapture()
    }

    private func makeModel(preferences: ProductCaptureTestPreferences, device: any ProductCaptureDevicePort) -> ProductCaptureCoordinator {
        let model = ProductCaptureCoordinator(preferences: preferences, makeDevice: { _ in device }, save: ProductCaptureTestSave(),
            bindOriginal: { _ in true }, didSave: {}, calendarNow: { Date() })
        model.enterCapture()
        return model
    }

    private func eventually(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<2_000 {
            if condition() { return }
            await Task.yield()
        }
        #expect(condition())
    }
}

/// Intentionally relies on ProductCaptureDevicePort's default empty stabilization stream.
private actor LegacyStabilizationTestDevice: ProductCaptureDevicePort {
    let underlying: ProductCaptureTestDevice
    init(underlying: ProductCaptureTestDevice) { self.underlying = underlying }
    func events() async -> AsyncStream<CaptureIOEvent> { await underlying.events() }
    func productEvents() async -> AsyncStream<ExplorationDeviceEvent> { await underlying.productEvents() }
    func discoverCameras() async throws -> [ExplorationCameraDescription] { await underlying.discoverCameras() }
    func prepare(_ request: ProductCapturePreparation) async throws -> ExplorationPrepared { try await underlying.prepare(request) }
    func previewSource() async -> (any ProductCapturePreviewSource)? { await underlying.previewSource() }
    func submit(_ command: CaptureIOCommand) async -> CaptureCommandAcceptance { await underlying.submit(command) }
    func shutDown() async { await underlying.shutDown() }
}
