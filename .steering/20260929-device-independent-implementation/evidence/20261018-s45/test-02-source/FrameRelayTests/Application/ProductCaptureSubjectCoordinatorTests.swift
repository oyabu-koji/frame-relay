import Foundation
import Testing
@testable import FrameRelay

@MainActor
struct ProductCaptureSubjectCoordinatorTests {
    @Test func absentIntentAndAnalysisNeverBlockRECOrStopRecording() async throws {
        let fixture = try CaptureFixture()
        let device = SubjectCoordinatorDevice(fixture: fixture)
        let preferences = ProductCaptureTestPreferences(fixture: fixture)
        let model = makeModel(preferences: preferences, device: device)
        await model.load(); await model.prepare()
        #expect(model.preferences.shootingIntent == nil)
        #expect(model.canRecord)
        #expect(model.subjects == nil)
        await device.emit(sequence: 1, state: .unavailable)
        await eventually { model.subjects != nil }
        #expect(model.canRecord)
        let applied = model.prepared?.applied
        await model.record()
        await eventually { model.capture?.phase == .recording }
        await device.emit(sequence: 2, state: .heldAwaitingSelection)
        await eventually { model.subjects?.sequence == 2 }
        #expect(model.capture?.phase == .recording)
        #expect(model.prepared?.applied == applied)
        #expect(model.preferences.desired == fixture.desired)
        #expect(await device.underlying.startCount == 1)
        await model.chooseShootingIntent(.peopleAndBackground)
        #expect(model.capture?.phase == .recording)
        #expect(model.preferences.shootingIntent == .peopleAndBackground)
        await model.stop()
        await eventually { !model.isBusy }
        await model.leaveCapture()
    }

    @Test func oldGenerationAndReversedSnapshotsCannotRestoreSubjectsAfterLeaving() async throws {
        let fixture = try CaptureFixture()
        let device = SubjectCoordinatorDevice(fixture: fixture)
        let model = makeModel(preferences: ProductCaptureTestPreferences(fixture: fixture), device: device)
        await model.load(); await model.prepare()
        await device.emit(sequence: 4, state: .personPriorityAF)
        await eventually { model.subjects?.sequence == 4 }
        await device.emit(sequence: 3, state: .unavailable)
        await device.emit(sequence: 100, state: .unavailable, foreign: true)
        for _ in 0..<30 { await Task.yield() }
        #expect(model.subjects?.sequence == 4)
        #expect(model.canRecord)
        await model.leaveCapture()
        await device.emit(sequence: 101, state: .personPriorityAF)
        for _ in 0..<30 { await Task.yield() }
        #expect(model.subjects == nil)
    }

    @Test func pendingIntentSaveKeepsRECAndLateCommitRequiresReloadOnNewVisit() async throws {
        let fixture = try CaptureFixture()
        let gate = ProductCaptureTestGate()
        let preferences = ProductCaptureTestPreferences(fixture: fixture, saveGate: gate)
        let device = SubjectCoordinatorDevice(fixture: fixture)
        let model = makeModel(preferences: preferences, device: device)
        await model.load(); await model.prepare()
        let saving = Task { await model.chooseShootingIntent(.scenery) }
        await gate.waitUntilHeld()
        #expect(model.isSavingShootingIntent)
        #expect(model.canRecord)
        await model.record()
        await eventually { model.capture?.phase == .recording }
        await model.stop()
        await eventually { !model.isBusy }
        await model.leaveCapture()
        let visit = model.enterCapture()
        await model.load(visit: visit)
        await gate.release()
        await saving.value
        #expect(!model.preferencesLoaded)
        await model.load(visit: visit)
        #expect(model.preferences.shootingIntent == .scenery)
        #expect(await preferences.load().shootingIntent == .scenery)
        await model.leaveCapture()
    }

    @Test func unconfiguredProductPolicyDoesNotPersistUnapprovedIntentOrIssueSubjectCommands() async throws {
        let fixture = try CaptureFixture()
        let preferences = ProductCaptureTestPreferences(fixture: fixture)
        let device = SubjectCoordinatorDevice(fixture: fixture)
        let model = ProductCaptureCoordinator(preferences: preferences, makeDevice: { _ in device }, save: ProductCaptureTestSave(),
            bindOriginal: { _ in true }, didSave: {}, calendarNow: { Date() })
        model.enterCapture()
        await model.load(); await model.prepare()
        await model.chooseShootingIntent(.scenery)
        #expect(model.preferences.shootingIntent == nil)
        #expect(await preferences.load().shootingIntent == nil)
        #expect(model.canRecord)
        await model.changeSubjects(.tracking(false))
        #expect(await device.commands.isEmpty)
        await model.leaveCapture()
    }

    @Test func existingSchemaWithoutIntentLoadsAndOrdinarySettingsRoundTripRetainsChosenIntent() async throws {
        let fixture = try CaptureFixture()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("preferences.json")
        let store = CapturePreferenceStore(url: url)
        let original = ProductCapturePreferences(desired: fixture.desired, outputCandidate: .sampleWriter)
        try await store.save(original)
        var data = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var preferences = try #require(data["preferences"] as? [String: Any])
        preferences.removeValue(forKey: "shootingIntent"); data["preferences"] = preferences
        try JSONSerialization.data(withJSONObject: data).write(to: url)
        #expect(try await store.load() == original)
        var chosen = original
        chosen.shootingIntent = .peopleAndBackground
        try await store.save(chosen)
        let restored = try await store.load()
        var draft = ProductCaptureSettingsDraft(restored)
        draft.iso = "400"
        let changed = try draft.preferences()
        #expect(changed.shootingIntent == .peopleAndBackground)
        try await store.save(changed)
        #expect(try await CapturePreferenceStore(url: url).load() == changed)
    }

    private func makeModel(preferences: any ProductCapturePreferencePort, device: SubjectCoordinatorDevice) -> ProductCaptureCoordinator {
        let model = ProductCaptureCoordinator(preferences: preferences, makeDevice: { _ in device }, save: ProductCaptureTestSave(),
            bindOriginal: { _ in true }, didSave: {}, subjectPolicy: .init(version: "test-only", lostGrace: 3, noPersonFocus: .tapPosition),
            calendarNow: { Date() })
        model.enterCapture()
        return model
    }
    private func eventually(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<2_000 { if condition() { return }; await Task.yield() }
        #expect(condition())
    }
}

private actor SubjectCoordinatorDevice: ProductCaptureDevicePort {
    let underlying: ProductCaptureTestDevice
    private var generation: CaptureGeneration?
    private let pair = AsyncStream<CaptureSubjectSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private(set) var commands: [CaptureSubjectRequest] = []
    init(fixture: CaptureFixture) { underlying = ProductCaptureTestDevice(fixture: fixture) }
    func events() async -> AsyncStream<CaptureIOEvent> { await underlying.events() }
    func productEvents() async -> AsyncStream<ExplorationDeviceEvent> { await underlying.productEvents() }
    func discoverCameras() async throws -> [ExplorationCameraDescription] { await underlying.discoverCameras() }
    func prepare(_ request: ProductCapturePreparation) async throws -> ExplorationPrepared {
        generation = request.generation
        return try await underlying.prepare(request)
    }
    func previewSource() async -> (any ProductCapturePreviewSource)? { await underlying.previewSource() }
    func submit(_ command: CaptureIOCommand) async -> CaptureCommandAcceptance { await underlying.submit(command) }
    func shutDown() async { await underlying.shutDown() }
    func subjectSnapshots() -> AsyncStream<CaptureSubjectSnapshot> { pair.stream }
    func updateSubjects(_ request: CaptureSubjectRequest) -> CaptureSubjectSnapshot? { commands.append(request); return nil }
    func emit(sequence: UInt64, state: CaptureSubjectFocusState, foreign: Bool = false) {
        guard let generation else { return }
        pair.continuation.yield(.init(context: .init(generation: foreign ? .init(session: .init(rawValue: "obsolete"), settings: 1) : generation,
            framingRevision: 1, selectionRevision: 0), sequence: sequence, candidates: [], exposureTargets: [], protagonist: nil,
            trackingEnabled: false, state: state, focus: .unconfirmed))
    }
}
