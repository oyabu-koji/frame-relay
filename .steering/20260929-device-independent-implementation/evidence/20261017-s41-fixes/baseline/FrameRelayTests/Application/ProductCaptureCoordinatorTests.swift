import Foundation
import Testing
@testable import FrameRelay

@MainActor
struct ProductCaptureCoordinatorTests {
    @Test func wishesPersistIndependentlyAndMissingChoicesNeverStartRecording() async throws {
        let fixture = try CaptureFixture()
        let preferences = ProductCaptureTestPreferences()
        let device = ProductCaptureTestDevice(fixture: fixture)
        let save = ProductCaptureTestSave()
        let model = model(preferences: preferences, device: device, save: save)
        await model.load()
        await model.record()
        #expect(!model.canRecord)
        #expect(await save.intents.isEmpty)
        let wish = ProductCapturePreferences(desired: fixture.desired, outputCandidate: .sampleWriter)
        await model.updatePreferences(wish)
        #expect(await preferences.load() == wish)
        #expect(model.prepared == nil)
        await model.prepare()
        #expect(model.canRecord)
        #expect(model.capture == nil)
    }

    @Test func unsupportedOrDifferentReadbackCannotBecomeREC() async throws {
        let fixture = try CaptureFixture()
        let device = ProductCaptureTestDevice(fixture: fixture, differ: true)
        let save = ProductCaptureTestSave()
        let model = model(preferences: ProductCaptureTestPreferences(fixture: fixture), device: device, save: save)
        await model.load(); await model.prepare(); await model.record()
        #expect(model.prepared != nil) // Actual readback remains visible.
        #expect(model.issue != nil)
        #expect(!model.canRecord)
        #expect(await save.intents.isEmpty)
        #expect(await device.commands.isEmpty)
    }

    @Test func recorderStartsOnlyAfterIntentCommitThenSavesBindsAndRefreshesOnce() async throws {
        let fixture = try CaptureFixture()
        let device = ProductCaptureTestDevice(fixture: fixture)
        let save = ProductCaptureTestSave(delayIntent: true)
        let probe = ProductCaptureTestProbe()
        let model = model(preferences: ProductCaptureTestPreferences(fixture: fixture), device: device, save: save, probe: probe)
        await model.load(); await model.prepare()
        let start = Task { await model.record() }
        await save.waitForIntent()
        #expect(await device.startCount == 0)
        await save.releaseIntent()
        await start.value
        await eventually { model.capture?.phase == .recording }
        #expect(await device.startCount == 1)
        let intent = try #require(await save.intents.first)
        #expect(intent.trialReference == nil)
        #expect(intent.capturedAt == Date(timeIntervalSince1970: 1_700_000_000.125))
        await model.stop()
        await eventually { model.saveResult != nil && !model.isSaving }
        #expect(model.saveResult == .unknown(.notMeasured))
        #expect(await probe.bound == [intent.original])
        #expect(await probe.refreshes == 1)
        #expect(await save.ends.count == 1)
        #expect(await save.files.count == 1)
        await device.repeatLastEndAndFile()
        for _ in 0..<20 { await Task.yield() }
        #expect(await save.ends.count == 1)
        #expect(await save.files.count == 1)
        #expect(await probe.refreshes == 1)
    }

    @Test func earlySTOPAndLeavingRetainOwnerUntilLateIntentCommitWithoutStartingRecorder() async throws {
        let fixture = try CaptureFixture()
        let device = ProductCaptureTestDevice(fixture: fixture)
        let save = ProductCaptureTestSave(delayIntent: true)
        let probe = ProductCaptureTestProbe()
        let model = model(preferences: ProductCaptureTestPreferences(fixture: fixture), device: device, save: save, probe: probe)
        await model.load(); await model.prepare()
        let start = Task { await model.record() }
        await save.waitForIntent()
        await model.leaveCapture()
        #expect(model.isBusy)
        #expect(await device.shutdowns == 0)
        await save.releaseIntent()
        await start.value
        #expect(!model.isBusy)
        #expect(await device.shutdowns == 1)
        #expect(await device.startCount == 0)
        #expect(await save.ends.first?.writer == .notStarted)
        #expect(await save.files.isEmpty)
        #expect(await probe.bound.isEmpty)
        #expect(await probe.refreshes == 1)
    }

    @Test func backgroundStopKeepsSaveOwnerUntilCompletion() async throws {
        let fixture = try CaptureFixture()
        let device = ProductCaptureTestDevice(fixture: fixture)
        let save = ProductCaptureTestSave()
        let model = model(preferences: ProductCaptureTestPreferences(fixture: fixture), device: device, save: save)
        await model.load(); await model.prepare(); await model.record()
        await eventually { model.capture?.phase == .recording }
        await model.leaveCapture()
        await eventually { !model.isBusy && model.prepared == nil }
        #expect(await save.files.count == 1)
        #expect(await device.shutdowns == 1)
    }

    @Test func uncertainIntentCommitRefreshesListAndLeavingDoesNotStartRecorder() async throws {
        let fixture = try CaptureFixture()
        let device = ProductCaptureTestDevice(fixture: fixture)
        let save = ProductCaptureTestSave(delayIntent: true, unknownIntent: true)
        let probe = ProductCaptureTestProbe()
        let model = model(preferences: ProductCaptureTestPreferences(fixture: fixture), device: device, save: save, probe: probe)
        await model.load(); await model.prepare()
        let start = Task { await model.record() }
        await save.waitForIntent()
        await model.leaveCapture()
        await save.releaseIntent()
        await start.value
        #expect(await probe.refreshes == 1)
        #expect(await device.startCount == 0)
        #expect(await device.shutdowns == 1)
        #expect(!model.isBusy)
        #expect(model.issue != nil)
    }

    @Test func listRefreshMustFinishBeforeNextRECOrReconfiguration() async throws {
        let fixture = try CaptureFixture()
        let device = ProductCaptureTestDevice(fixture: fixture)
        let save = ProductCaptureTestSave()
        let probe = ProductCaptureTestProbe(holdRefresh: true)
        let model = model(preferences: ProductCaptureTestPreferences(fixture: fixture), device: device, save: save, probe: probe)
        await model.load(); await model.prepare(); await model.record()
        await eventually { model.capture?.phase == .recording }
        await model.stop()
        await probe.waitForRefresh()
        let context = try #require(model.capture?.context)
        #expect(model.isSaving)
        #expect(!model.canRecord)
        await model.record()
        await model.updatePreferences(.init())
        await model.prepare()
        #expect(model.capture?.context == context)
        #expect(model.preferences.desired == fixture.desired)
        #expect(await save.intents.count == 1)
        await probe.releaseRefresh()
        await eventually { !model.isBusy }
        #expect(await probe.refreshes == 1)
    }

    @Test func audioInputFailureAfterPreparationBlocksNextREC() async throws {
        let fixture = try CaptureFixture()
        let device = ProductCaptureTestDevice(fixture: fixture)
        let model = model(preferences: ProductCaptureTestPreferences(fixture: fixture), device: device, save: ProductCaptureTestSave())
        await model.load(); await model.prepare(); await model.record()
        await eventually { model.capture?.phase == .recording }
        await model.stop()
        await eventually { model.saveResult != nil && !model.isSaving && model.capture?.whiteBalance == .automatic }
        let context = try #require(model.capture?.context)
        let audio = CaptureAudioState(level: .unavailable(.notMeasured), input: .failed(.permissionDenied),
                                      arrival: .unobserved, writing: .notStarted)
        await device.emit(.capture(.audioObserved(context, sequence: 90, audio)))
        await eventually { model.capture?.audio.input == audio.input }
        #expect(!model.canRecord)
    }

    private func model(preferences: ProductCaptureTestPreferences, device: ProductCaptureTestDevice,
                       save: ProductCaptureTestSave, probe: ProductCaptureTestProbe = .init()) -> ProductCaptureCoordinator {
        ProductCaptureCoordinator(preferences: preferences, makeDevice: { _ in device }, save: save,
            bindOriginal: { await probe.bind($0) }, didSave: { await probe.refresh() },
            calendarNow: { Date(timeIntervalSince1970: 1_700_000_000.1259) })
    }

    private func eventually(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<2_000 {
            if condition() { return }
            await Task.yield()
        }
        #expect(condition())
    }
}

actor ProductCaptureTestPreferences: ProductCapturePreferencePort {
    private var value: ProductCapturePreferences
    init(fixture: CaptureFixture? = nil) {
        value = .init(desired: fixture?.desired, outputCandidate: fixture == nil ? nil : .sampleWriter)
    }
    func load() -> ProductCapturePreferences { value }
    func save(_ preferences: ProductCapturePreferences) { value = preferences }
}

actor ProductCaptureTestProbe {
    private let holdRefresh: Bool
    private var release: CheckedContinuation<Void, Never>?
    private var waiting: CheckedContinuation<Void, Never>?
    init(holdRefresh: Bool = false) { self.holdRefresh = holdRefresh }
    private(set) var bound: [CaptureOriginalReference] = []
    private(set) var refreshes = 0
    func bind(_ original: CaptureOriginalReference) -> Bool { bound.append(original); return true }
    func refresh() async {
        refreshes += 1
        if holdRefresh {
            await withCheckedContinuation { continuation in
                release = continuation
                waiting?.resume(); waiting = nil
            }
        }
    }
    func waitForRefresh() async {
        if release != nil { return }
        await withCheckedContinuation { waiting = $0 }
    }
    func releaseRefresh() { release?.resume(); release = nil }
}

actor ProductCaptureTestDevice: ProductCaptureDevicePort {
    private let fixture: CaptureFixture
    private let differ: Bool
    private let stream: AsyncStream<ExplorationDeviceEvent>
    private let continuation: AsyncStream<ExplorationDeviceEvent>.Continuation
    private var intent: RecordingIntent?
    private var lastEvents: [ExplorationDeviceEvent] = []
    private(set) var commands: [CaptureIOCommand] = []
    private(set) var shutdowns = 0
    var startCount: Int { commands.filter { if case .startRecording = $0 { return true }; return false }.count }
    init(fixture: CaptureFixture, differ: Bool = false) {
        self.fixture = fixture; self.differ = differ
        let pair = AsyncStream<ExplorationDeviceEvent>.makeStream()
        stream = pair.stream; continuation = pair.continuation
    }
    func events() -> AsyncStream<CaptureIOEvent> { AsyncStream { $0.finish() } }
    func productEvents() -> AsyncStream<ExplorationDeviceEvent> { stream }
    func previewSource() -> (any ProductCapturePreviewSource)? { nil }
    func discoverCameras() -> [ExplorationCameraDescription] {
        let c = fixture.desired.configuration
        return [.init(id: c.camera, label: "Synthetic camera", isVirtual: false, formats: [
            .init(id: "transient-index", width: c.width, height: c.height, frameRateRanges: [24...30],
                  logEncodings: [c.logEncoding], stabilizationModes: [c.stabilizationMode])])]
    }
    func shutDown() { shutdowns += 1 }
    func prepare(_ request: ProductCapturePreparation) throws -> ExplorationPrepared {
        let c = fixture.capabilities
        let exposure = differ ? try CaptureManualExposure(shutter: fixture.desired.exposure.shutter, iso: 161, aperture: nil) : fixture.desired.exposure
        return .init(capabilities: .init(generation: request.generation, configurations: c.configurations,
            controlsForConfiguration: c.controlsForConfiguration, manualControls: c.manualControls, whiteBalanceLock: c.whiteBalanceLock),
            applied: .init(generation: request.generation, operation: request.operation,
                values: .observed(.init(configuration: request.desired.configuration, exposure: exposure, zoom: request.desired.zoom),
                    at: fixture.time, method: .direct(source: "synthetic"))), audio: fixture.audio)
    }
    func submit(_ command: CaptureIOCommand) -> CaptureCommandAcceptance {
        commands.append(command)
        switch command {
        case .lockCurrentWhiteBalance(let token): emit(.capture(.whiteBalanceLocked(token, fixture.lock)))
        case .restoreAutomaticWhiteBalance(let token): emit(.capture(.automaticWhiteBalanceRestored(token, fixture.time)))
        case .startRecording(let token, let intent):
            self.intent = intent
            emit(.capture(.recordingStarted(token, fixture.time)))
        case .stopRecording(let token, _):
            guard let intent else { break }
            lastEvents = [.capture(.recordingEnded(token, fixture.end)),
                .fileFinalized(.init(context: intent.context, original: intent.original, byteCount: 4096, finalizedAt: fixture.time))]
            for event in lastEvents { emit(event) }
        case .refreshAndLockWhiteBalance: break
        }
        return .accepted(command.token)
    }
    func emit(_ event: ExplorationDeviceEvent) { continuation.yield(event) }
    func repeatLastEndAndFile() { for event in lastEvents { emit(event) } }
}

actor ProductCaptureTestSave: ProductCaptureSavePort {
    private let delayIntent: Bool
    private let unknownIntent: Bool
    private var release: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var intents: [RecordingIntent] = []
    private(set) var ends: [RecordingEndEvidence] = []
    private(set) var files: [CaptureFileEvidence] = []
    init(delayIntent: Bool = false, unknownIntent: Bool = false) {
        self.delayIntent = delayIntent; self.unknownIntent = unknownIntent
    }
    func waitForIntent() async {
        if !intents.isEmpty { return }
        await withCheckedContinuation { started = $0 }
    }
    func releaseIntent() { release?.resume(); release = nil }
    func begin(_ intent: RecordingIntent, token: CaptureCommandToken) async -> OriginalSaveOperationResult {
        intents.append(intent)
        if delayIntent {
            await withCheckedContinuation { continuation in
                release = continuation
                started?.resume(); started = nil
            }
        }
        if unknownIntent { return .requiresReconciliation(.interrupted) }
        return .ready(.init(token: token, previousRevision: 0, committedRevision: 1))
    }
    func recordingEnded(context: CaptureContext, evidence: RecordingEndEvidence) -> OriginalSaveOperationResult {
        ends.append(evidence); return .accepted
    }
    func fileFinalized(_ file: CaptureFileEvidence, resultToken: CaptureCommandToken) -> OriginalSaveOperationResult {
        files.append(file)
        guard let intent = intents.last, let end = ends.last else { return .rejected(.wrongStage) }
        let inspection = CaptureMediaInspection(context: intent.context, original: intent.original,
            video: .unavailable(.notMeasured), audio: .unavailable(.notMeasured), format: .unavailable(.notMeasured),
            playback: .unavailable(.notMeasured), completeness: .unknown(.notMeasured))
        return .committed(.init(intent: intent, end: end, file: file, inspection: inspection, result: .unknown(.notMeasured)),
                          .init(token: resultToken, previousRevision: 1, committedRevision: 2))
    }
}
