import Foundation
import Testing
@testable import FrameRelay

@MainActor
struct ProductCaptureCoordinatorTests {
    @Test func explicitRefreshKeepsRecordingAndManualSettingsThenNextClipMeasuresAgain() async throws {
        let fixture = try CaptureFixture()
        let device = ProductCaptureTestDevice(fixture: fixture, holdRefresh: true)
        let save = ProductCaptureTestSave()
        let model = model(preferences: ProductCaptureTestPreferences(fixture: fixture), device: device, save: save)
        await model.load(); await model.prepare()
        #expect(!model.canRefreshWhiteBalance)
        await model.refreshWhiteBalance()
        #expect(await device.refreshCount == 0)
        await model.record()
        await eventually { model.canRefreshWhiteBalance }
        let values = model.prepared?.applied.values
        let refreshed = CaptureWhiteBalanceLock(gains: try .init(red: 2, green: 1, blue: 1.5),
                                                measuredAt: fixture.time, appliedAt: fixture.time)
        await device.setNextWhiteBalance(refreshed)
        await model.refreshWhiteBalance()
        #expect(model.capture?.phase == .recording)
        #expect(!model.canRefreshWhiteBalance)
        await model.refreshWhiteBalance()
        #expect(await device.refreshCount == 1)
        await device.completeWhiteBalanceMeasurement()
        #expect(!model.canRefreshWhiteBalance) // SDK measurement alone is not an applied lock.
        await device.completeWhiteBalanceLock()
        await eventually { model.canRefreshWhiteBalance }
        #expect(model.capture?.whiteBalance == .locked(refreshed))
        #expect(model.prepared?.applied.values == values)
        #expect(model.preferences.desired?.exposure == fixture.desired.exposure)
        #expect(await device.startCount == 1)
        #expect(await save.ends.isEmpty)
        let oldContext = try #require(model.capture?.context)
        let oldRefresh = try #require(await device.commands.compactMap { command -> CaptureCommandToken? in
            if case .refreshAndLockWhiteBalance(let token) = command { return token }; return nil
        }.first)
        await model.stop()
        await eventually { model.canRecord }
        #expect(model.capture?.whiteBalance == .automatic)
        let second = CaptureWhiteBalanceLock(gains: try .init(red: 1.7, green: 1, blue: 2),
                                             measuredAt: fixture.time, appliedAt: fixture.time)
        await device.setNextWhiteBalance(second)
        await model.record()
        await eventually { model.canRefreshWhiteBalance }
        #expect(model.capture?.context != oldContext)
        #expect(model.capture?.whiteBalance == .locked(second))
        await device.emit(.capture(.whiteBalanceLocked(oldRefresh, refreshed)))
        await device.repeatLastEndAndFile()
        for _ in 0..<20 { await Task.yield() }
        #expect(model.capture?.whiteBalance == .locked(second))
        #expect(model.capture?.phase == .recording)
        #expect(await save.ends.count == 1)
        #expect(await device.startCount == 2)
        await model.stop()
        await eventually { model.canRecord }
        #expect(await save.ends.count == 2)
        #expect(await save.files.count == 2)
        await model.leaveCapture()
    }

    @Test(arguments: ["stop", "leave", "audio", "lockFailure"])
    func refreshCancellationRefixesBeforeTerminationAndOldCallbacksCannotReviveIt(cause: String) async throws {
        let fixture = try CaptureFixture()
        let device = ProductCaptureTestDevice(fixture: fixture, holdRefresh: true)
        let save = ProductCaptureTestSave()
        let model = model(preferences: ProductCaptureTestPreferences(fixture: fixture), device: device, save: save)
        await model.load(); await model.prepare(); await model.record()
        await eventually { model.canRefreshWhiteBalance }
        await model.refreshWhiteBalance()
        let context = try #require(model.capture?.context)
        switch cause {
        case "leave": await model.leaveCapture()
        case "audio":
            var failed = fixture.audio
            failed.input = .failed(.confirmedNoSamples(.init(rawValue: "synthetic-audio")))
            await device.emit(.capture(.audioObserved(context, sequence: 1, failed)))
            await eventually { model.capture?.phase == .stopping }
        case "lockFailure": await device.failWhiteBalanceLock()
        default: await model.stop()
        }
        if cause != "lockFailure" {
            #expect(model.capture?.phase == .stopping)
            #expect(await save.ends.isEmpty)
            #expect(await device.shutdowns == 0)
            await device.completeWhiteBalanceMeasurement() // cancelled KVO is ignored
            #expect(await save.ends.isEmpty)
            await device.completeWhiteBalanceLock()
        }
        await eventually { !model.isSaving }
        if cause == "leave" { await eventually { model.capture == nil } }
        else { await eventually { model.capture?.whiteBalance == .automatic } }
        #expect(await save.ends.count == 1)
        #expect(await save.files.count == 1)
        if cause == "lockFailure" {
            #expect(await save.ends.first?.writer == .interrupted(.adapterFailure(code: "synthetic-wb-lock")))
        }
        await device.completeWhiteBalanceMeasurement()
        await device.completeWhiteBalanceLock()
        for _ in 0..<20 { await Task.yield() }
        #expect(await device.startCount == 1)
        #expect(await save.ends.count == 1)
        #expect(!model.canRefreshWhiteBalance)
        await model.leaveCapture()
    }

    @Test func earlySTOPDoesNotWaitForInitialWBCallbackOrAcceptItAfterTerminal() async throws {
        let fixture = try CaptureFixture()
        let device = ProductCaptureTestDevice(fixture: fixture, holdInitialLock: true)
        let save = ProductCaptureTestSave()
        let model = model(preferences: ProductCaptureTestPreferences(fixture: fixture), device: device, save: save)
        await model.load(); await model.prepare(); await model.record()
        #expect(model.capture?.phase == .starting)
        await model.stop()
        await eventually { !model.isSaving && model.capture?.whiteBalance == .automatic }
        #expect(await device.startCount == 0)
        #expect(await save.ends.first?.writer == .notStarted)
        await device.completeWhiteBalanceLock()
        for _ in 0..<20 { await Task.yield() }
        #expect(model.capture?.whiteBalance == .automatic)
        #expect(await device.startCount == 0)
        #expect(model.saveResult == nil)
        await model.leaveCapture()
    }

    @Test func unsupportedRefreshDoesNotBlockRECOrSubmitAnUnsupportedCommand() async throws {
        let fixture = try CaptureFixture()
        let device = ProductCaptureTestDevice(fixture: fixture, refreshSupported: false)
        let model = model(preferences: ProductCaptureTestPreferences(fixture: fixture), device: device, save: ProductCaptureTestSave())
        await model.load(); await model.prepare()
        #expect(model.canRecord)
        await model.record()
        await eventually { model.capture?.phase == .recording }
        #expect(!model.canRefreshWhiteBalance)
        await model.refreshWhiteBalance()
        #expect(await device.refreshCount == 0)
        #expect(model.capture?.phase == .recording)
        await model.stop()
        await eventually { model.canRecord }
        await model.leaveCapture()
    }

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
        await probe.waitForRefreshCount(1)
        #expect(await probe.bound == [intent.original])
        await probe.waitForRefreshCount(1)
        #expect(await probe.refreshes == 1)
        #expect(await save.ends.count == 1)
        #expect(await save.files.count == 1)
        await device.repeatLastEndAndFile()
        for _ in 0..<20 { await Task.yield() }
        #expect(await save.ends.count == 1)
        #expect(await save.files.count == 1)
        await probe.waitForRefreshCount(1)
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
        await probe.waitForRefreshCount(1)
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
        await probe.waitForRefreshCount(1)
        #expect(await probe.refreshes == 1)
        #expect(await device.startCount == 0)
        #expect(await device.shutdowns == 1)
        #expect(!model.isBusy)
        #expect(model.issue != nil)
    }

    @Test func listRefreshDoesNotHoldNextRECOrChangeItsState() async throws {
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
        #expect(!model.isSaving)
        #expect(model.canRecord)
        await model.record()
        await eventually { model.capture?.phase == .recording }
        let nextContext = try #require(model.capture?.context)
        #expect(nextContext != context)
        #expect(model.preferences.desired == fixture.desired)
        #expect(await save.intents.count == 2)
        await probe.releaseRefresh()
        #expect(model.capture?.context == nextContext)
        #expect(model.capture?.phase == .recording)
        #expect(model.saveResult == nil)
        #expect(model.issue == nil)
        await probe.waitForRefreshCount(1)
        #expect(await probe.refreshes == 1)
        await model.stop()
        await eventually { model.canRecord }
        await probe.waitForRefreshCount(2)
        let originals = await save.intents.map(\.original)
        #expect(await probe.bound == originals)
        await model.leaveCapture()
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

    @Test func nativePreflightRejectionSettlesOnceAndAllowsReprepareAndLeaving() async throws {
        let fixture = try CaptureFixture()
        let device = ProductCaptureTestDevice(fixture: fixture, rejectStart: true)
        let nextDevice = ProductCaptureTestDevice(fixture: fixture)
        let factory = ProductCaptureTestDeviceFactory([device, nextDevice])
        let save = ProductCaptureTestSave()
        let probe = ProductCaptureTestProbe()
        let model = ProductCaptureCoordinator(preferences: ProductCaptureTestPreferences(fixture: fixture),
            makeDevice: { _ in await factory.make() }, save: save,
            bindOriginal: { await probe.bind($0) }, didSave: { await probe.refresh() }, calendarNow: { Date() })
        model.enterCapture()
        await model.load(); await model.prepare(); await model.record()
        await eventually { !model.isBusy && model.capture?.whiteBalance == .automatic }
        #expect(model.capture?.phase == .ended)
        #expect(await save.ends.count == 1)
        #expect(await save.ends.first?.writer == .notStarted)
        #expect(await save.files.isEmpty)
        #expect(await probe.bound.isEmpty)
        await probe.waitForRefreshCount(1)
        #expect(await probe.refreshes == 1)
        #expect(model.saveResult == nil)
        let rejected = try #require(await device.commands.first { if case .startRecording = $0 { return true }; return false })
        #expect(await device.submit(rejected) == .rejected(rejected.token, .evidenceMismatch))
        await model.stop()
        await device.repeatLastEndAndFile()
        for _ in 0..<20 { await Task.yield() }
        #expect(await save.ends.count == 1)
        await probe.waitForRefreshCount(1)
        #expect(await probe.refreshes == 1)
        await model.prepare()
        #expect(model.canRecord)
        await model.record()
        await eventually { model.capture?.phase == .recording }
        // A replay from the rejected capture cannot terminate the new recording.
        await device.repeatLastEndAndFile()
        for _ in 0..<20 { await Task.yield() }
        #expect(model.capture?.phase == .recording)
        await model.leaveCapture()
        await eventually { !model.isBusy && model.prepared == nil }
        #expect(await save.ends.count == 2)
        #expect(await save.ends.last?.writer == .completed)
        #expect(await device.shutdowns == 1)
        #expect(await nextDevice.shutdowns == 1)
    }

    @Test func leavingAfterNativePreflightRejectionReleasesCameraWithoutFileSuccess() async throws {
        let fixture = try CaptureFixture()
        let device = ProductCaptureTestDevice(fixture: fixture, rejectStart: true)
        let save = ProductCaptureTestSave()
        let model = model(preferences: ProductCaptureTestPreferences(fixture: fixture), device: device, save: save)
        await model.load(); await model.prepare(); await model.record()
        await model.leaveCapture()
        await eventually { !model.isBusy && model.prepared == nil }
        #expect(await device.shutdowns == 1)
        #expect(await save.ends.count == 1)
        #expect(await save.ends.first?.writer == .notStarted)
        #expect(await save.files.isEmpty)
        #expect(model.saveResult == nil)
    }

    @Test func delayedSettingsLoadCannotResumeHiddenCapturePreparation() async throws {
        let fixture = try CaptureFixture()
        let gate = ProductCaptureTestGate()
        let preferences = ProductCaptureTestPreferences(fixture: fixture, loadGate: gate)
        let device = ProductCaptureTestDevice(fixture: fixture)
        let factory = ProductCaptureTestDeviceFactory([device])
        let model = makeModel(preferences: preferences, factory: factory)
        let opening = Task { await open(model) }
        await gate.waitUntilHeld()
        await model.leaveCapture()
        await gate.release()
        await opening.value
        #expect(await factory.creations == 0)
        #expect(!model.preferencesLoaded)
        #expect(!model.isBusy)
        #expect(model.prepared == nil)
        // Only a new entry can prepare after the old load returned.
        await open(model)
        #expect(model.canRecord)
        await model.leaveCapture()
    }

    @Test func delayedDiscoveryCannotChainIntoPrepareAfterLeaving() async throws {
        let fixture = try CaptureFixture()
        let gate = ProductCaptureTestGate()
        let device = ProductCaptureTestDevice(fixture: fixture, discoverGate: gate)
        let factory = ProductCaptureTestDeviceFactory([device])
        let model = makeModel(preferences: ProductCaptureTestPreferences(fixture: fixture), factory: factory)
        let opening = Task { await open(model) }
        await gate.waitUntilHeld()
        await model.leaveCapture()
        await gate.release()
        await opening.value
        #expect(await factory.creations == 1)
        #expect(await device.preparations == 0)
        #expect(await device.shutdowns == 1)
        #expect(model.prepared == nil)
        #expect(!model.isBusy)
    }

    @Test(arguments: ["make", "discover", "prepare", "preview"])
    func leavingAtPreparationAwaitDiscardsAndReleasesOnlyItsDevice(stage: String) async throws {
        try await interruptedPreparation(stage: stage, cancel: false)
    }

    @Test(arguments: ["make", "discover", "prepare", "preview"])
    func cancelledPreparationCannotPublishOrRetainCamera(stage: String) async throws {
        try await interruptedPreparation(stage: stage, cancel: true)
    }

    private func interruptedPreparation(stage: String, cancel: Bool) async throws {
        let fixture = try CaptureFixture()
        let gate = ProductCaptureTestGate()
        let device = ProductCaptureTestDevice(fixture: fixture,
            discoverGate: stage == "discover" ? gate : nil,
            prepareGate: stage == "prepare" ? gate : nil,
            previewGate: stage == "preview" ? gate : nil)
        let factory = ProductCaptureTestDeviceFactory([device], makeGate: stage == "make" ? gate : nil)
        let model = makeModel(preferences: ProductCaptureTestPreferences(fixture: fixture), factory: factory)
        let visit = model.enterCapture()
        await model.load(visit: visit)
        let preparing = Task { await model.prepare(visit: visit) }
        await gate.waitUntilHeld()
        if cancel { preparing.cancel() } else { await model.leaveCapture() }
        await gate.release()
        await preparing.value
        #expect(await device.shutdowns == 1)
        #expect(await device.preparations == (["make", "discover"].contains(stage) ? 0 : 1))
        #expect(!(await device.sessionActive))
        #expect(model.prepared == nil)
        #expect(model.previewSource == nil)
        #expect(!model.isBusy)
        #expect(!model.canRecord)
    }

    @Test func oldPreparationCannotPublishOrClearBusyStateOfNewVisit() async throws {
        let fixture = try CaptureFixture()
        let oldGate = ProductCaptureTestGate()
        let newGate = ProductCaptureTestGate()
        let oldDevice = ProductCaptureTestDevice(fixture: fixture, prepareGate: oldGate)
        let newDevice = ProductCaptureTestDevice(fixture: fixture, prepareGate: newGate)
        let factory = ProductCaptureTestDeviceFactory([oldDevice, newDevice])
        let model = makeModel(preferences: ProductCaptureTestPreferences(fixture: fixture), factory: factory)
        let oldVisit = model.enterCapture()
        await model.load(visit: oldVisit)
        let oldPreparation = Task { await model.prepare(visit: oldVisit) }
        await oldGate.waitUntilHeld()
        await model.leaveCapture()
        let newVisit = model.enterCapture()
        let newPreparation = Task { await model.prepare(visit: newVisit) }
        await newGate.waitUntilHeld()
        await oldGate.release()
        await oldPreparation.value
        #expect(model.isPreparing)
        #expect(await oldDevice.shutdowns == 1)
        #expect(await newDevice.shutdowns == 0)
        await newGate.release()
        await newPreparation.value
        #expect(model.canRecord)
        let generation = model.prepared?.applied.generation
        await model.discover(visit: oldVisit)
        await model.prepare(visit: oldVisit)
        #expect(model.prepared?.applied.generation == generation)
        #expect(await factory.creations == 2)
        #expect(await newDevice.shutdowns == 0)
        await model.leaveCapture()
    }

    @Test func oldShutdownCompletionCannotClearNewPreparedDevice() async throws {
        let fixture = try CaptureFixture()
        let gate = ProductCaptureTestGate()
        let oldDevice = ProductCaptureTestDevice(fixture: fixture, shutdownGate: gate)
        let newDevice = ProductCaptureTestDevice(fixture: fixture)
        let factory = ProductCaptureTestDeviceFactory([oldDevice, newDevice])
        let model = makeModel(preferences: ProductCaptureTestPreferences(fixture: fixture), factory: factory)
        let oldVisit = model.enterCapture()
        await model.load(visit: oldVisit); await model.prepare(visit: oldVisit)
        let oldReprepare = Task { await model.prepare(visit: oldVisit) }
        await gate.waitUntilHeld()
        await model.leaveCapture()
        let newVisit = model.enterCapture()
        await model.prepare(visit: newVisit)
        let generation = model.prepared?.applied.generation
        #expect(model.canRecord)
        await gate.release()
        await oldReprepare.value
        #expect(model.canRecord)
        #expect(model.prepared?.applied.generation == generation)
        #expect(await newDevice.shutdowns == 0)
        #expect(await factory.creations == 2)
        await model.leaveCapture()
    }

    @Test func oldSettingsApplyCannotPrepareAfterReentry() async throws {
        let fixture = try CaptureFixture()
        let gate = ProductCaptureTestGate()
        let preferences = ProductCaptureTestPreferences(fixture: fixture, saveGate: gate)
        let device = ProductCaptureTestDevice(fixture: fixture)
        let reconfiguredDevice = ProductCaptureTestDevice(fixture: fixture)
        let factory = ProductCaptureTestDeviceFactory([device, reconfiguredDevice])
        let model = makeModel(preferences: preferences, factory: factory)
        let changed = ProductCapturePreferences(desired: fixture.desired, outputCandidate: .movieFile)
        let oldVisit = model.enterCapture()
        await model.load(visit: oldVisit)
        let applying = Task {
            await model.updatePreferences(changed, visit: oldVisit)
            await model.prepare(visit: oldVisit)
        }
        await gate.waitUntilHeld()
        await model.leaveCapture()
        let newVisit = model.enterCapture()
        await model.load(visit: newVisit)
        await model.prepare(visit: newVisit)
        let generation = model.prepared?.applied.generation
        #expect(model.preferences.outputCandidate == .sampleWriter)
        await gate.release()
        await applying.value
        #expect(!model.preferencesLoaded)
        #expect(!model.canRecord)
        #expect(model.prepared?.applied.generation == generation)
        #expect(await device.shutdowns == 0) // The old save cannot release the new visit's camera.
        await model.load(visit: newVisit)
        #expect(model.preferencesLoaded)
        #expect(model.preferences == changed)
        #expect(model.prepared == nil)
        #expect(!model.canRecord)
        #expect(await device.shutdowns == 1) // This visit's reload retires its obsolete preparation.
        #expect(await factory.creations == 1)
        await model.prepare(visit: newVisit)
        #expect(model.canRecord)
        #expect(await factory.candidates == [.sampleWriter, .movieFile])
        #expect(await reconfiguredDevice.shutdowns == 0)
        await model.leaveCapture()
    }

    private func open(_ model: ProductCaptureCoordinator) async {
        let visit = model.enterCapture()
        await model.load(visit: visit)
        await model.discover(visit: visit)
        await model.prepare(visit: visit)
    }

    private func makeModel(preferences: ProductCaptureTestPreferences,
                           factory: ProductCaptureTestDeviceFactory) -> ProductCaptureCoordinator {
        ProductCaptureCoordinator(preferences: preferences, makeDevice: { await factory.make(candidate: $0) },
            save: ProductCaptureTestSave(), bindOriginal: { _ in true }, didSave: {}, calendarNow: { Date() })
    }

    private func model(preferences: ProductCaptureTestPreferences, device: ProductCaptureTestDevice,
                       save: ProductCaptureTestSave, probe: ProductCaptureTestProbe = .init()) -> ProductCaptureCoordinator {
        let model = ProductCaptureCoordinator(preferences: preferences, makeDevice: { _ in device }, save: save,
            bindOriginal: { await probe.bind($0) }, didSave: { await probe.refresh() },
            calendarNow: { Date(timeIntervalSince1970: 1_700_000_000.1259) })
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

actor ProductCaptureTestPreferences {
    private var value: ProductCapturePreferences
    private let loadGate: ProductCaptureTestGate?
    private let saveGate: ProductCaptureTestGate?
    init(fixture: CaptureFixture? = nil, loadGate: ProductCaptureTestGate? = nil, saveGate: ProductCaptureTestGate? = nil) {
        value = .init(desired: fixture?.desired, outputCandidate: fixture == nil ? nil : .sampleWriter)
        self.loadGate = loadGate; self.saveGate = saveGate
    }
    func load() async -> ProductCapturePreferences { await loadGate?.holdOnce(); return value }
    func save(_ preferences: ProductCapturePreferences) async {
        await saveGate?.holdOnce(); value = preferences
    }
}

extension ProductCaptureTestPreferences: ProductCapturePreferencePort {}

actor ProductCaptureTestProbe {
    private let holdRefresh: Bool
    private var release: CheckedContinuation<Void, Never>?
    private var waiting: CheckedContinuation<Void, Never>?
    private var refreshWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    init(holdRefresh: Bool = false) { self.holdRefresh = holdRefresh }
    private(set) var bound: [CaptureOriginalReference] = []
    private(set) var refreshes = 0
    func bind(_ original: CaptureOriginalReference) -> Bool { bound.append(original); return true }
    func refresh() async {
        refreshes += 1
        let ready = refreshWaiters.filter { $0.0 <= refreshes }
        refreshWaiters.removeAll { $0.0 <= refreshes }
        for (_, waiter) in ready { waiter.resume() }
        if holdRefresh && refreshes == 1 {
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
    func waitForRefreshCount(_ count: Int) async {
        if refreshes >= count { return }
        await withCheckedContinuation { refreshWaiters.append((count, $0)) }
    }
}

actor ProductCaptureTestDevice {
    private let fixture: CaptureFixture
    private let differ: Bool
    private let rejectStart: Bool
    private let unconfirmedFile: Bool
    private let holdInitialLock: Bool
    private let holdRefresh: Bool
    private let refreshSupported: Bool
    private let discoverGate: ProductCaptureTestGate?
    private let prepareGate: ProductCaptureTestGate?
    private let previewGate: ProductCaptureTestGate?
    private let shutdownGate: ProductCaptureTestGate?
    private var admission = NativeRecordingStartAdmission()
    private var wbOrder: ExplorationWBCommandOrder?
    private var generation: CaptureGeneration?
    private var activeToken: CaptureCommandToken?
    private var pendingLock: CaptureCommandToken?
    private var pendingMeasurement: CaptureCommandToken?
    private var pendingStop: CaptureCommandToken?
    private var nextLock: CaptureWhiteBalanceLock
    private(set) var preparations = 0
    private(set) var sessionActive = false
    private let stream: AsyncStream<ExplorationDeviceEvent>
    private let continuation: AsyncStream<ExplorationDeviceEvent>.Continuation
    private let stabilizationPair = AsyncStream<CaptureStabilizationSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(8))
    private var stabilizationEnabled = false
    private var stabilizationActive: String?
    private let audioPair = AsyncStream<ProductCaptureAudioSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private var recoveryOutcomes: [CaptureAudioRecoveryOutcome] = [.validInput(route: "recovered test mic")]
    private var heldRecovery: CheckedContinuation<CaptureAudioRecoveryOutcome, Never>?
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []
    private var holdAudioRecovery = false
    private(set) var audioRecoveryCalls = 0
    private var intent: RecordingIntent?
    private var lastEvents: [ExplorationDeviceEvent] = []
    private(set) var commands: [CaptureIOCommand] = []
    private(set) var shutdowns = 0
    var startCount: Int { commands.filter { if case .startRecording = $0 { return true }; return false }.count }
    var refreshCount: Int { commands.filter { if case .refreshAndLockWhiteBalance = $0 { return true }; return false }.count }
    init(fixture: CaptureFixture, differ: Bool = false, rejectStart: Bool = false,
         discoverGate: ProductCaptureTestGate? = nil, prepareGate: ProductCaptureTestGate? = nil,
         previewGate: ProductCaptureTestGate? = nil, shutdownGate: ProductCaptureTestGate? = nil,
         holdInitialLock: Bool = false, holdRefresh: Bool = false, refreshSupported: Bool = true,
         unconfirmedFile: Bool = false) {
        self.fixture = fixture; self.differ = differ; self.rejectStart = rejectStart
        self.unconfirmedFile = unconfirmedFile
        self.holdInitialLock = holdInitialLock; self.holdRefresh = holdRefresh; self.refreshSupported = refreshSupported
        nextLock = fixture.lock
        self.discoverGate = discoverGate; self.prepareGate = prepareGate
        self.previewGate = previewGate; self.shutdownGate = shutdownGate
        let pair = AsyncStream<ExplorationDeviceEvent>.makeStream()
        stream = pair.stream; continuation = pair.continuation
    }
    func events() -> AsyncStream<CaptureIOEvent> { AsyncStream { $0.finish() } }
    func productEvents() -> AsyncStream<ExplorationDeviceEvent> { stream }
    func audioSnapshots() -> AsyncStream<ProductCaptureAudioSnapshot> { audioPair.stream }
    func stabilizationSnapshots() -> AsyncStream<CaptureStabilizationSnapshot> { stabilizationPair.stream }
    func finishStabilizationObservations() { stabilizationPair.continuation.finish() }
    func configureStabilization(active: String?) { stabilizationEnabled = true; stabilizationActive = active }
    func emitStabilization(sequence: UInt64, active: String?, generation override: CaptureGeneration? = nil,
                           zoom: Double = 1, physicalCamera: String? = "synthetic-wide",
                           formatID: String = "synthetic-format", connection: CaptureStabilizationConnection = .ready) {
        guard let generation = override ?? generation else { return }
        stabilizationPair.continuation.yield(stabilization(generation: generation, sequence: sequence, active: active,
            zoom: zoom, physicalCamera: physicalCamera, formatID: formatID, connection: connection))
    }
    private func stabilization(generation: CaptureGeneration, sequence: UInt64, active: String?, zoom: Double = 1,
                               physicalCamera: String? = "synthetic-wide", formatID: String = "synthetic-format",
                               connection: CaptureStabilizationConnection = .ready) -> CaptureStabilizationSnapshot {
        let c = fixture.desired.configuration
        return .init(generation: generation, sequence: sequence, output: .sampleWriter,
            requestedMode: c.stabilizationMode, preferredMode: c.stabilizationMode,
            activeMode: active.map { .observed($0, at: fixture.time, method: .direct(source: "synthetic")) }
                ?? .unavailable(.notMeasured), connection: connection, camera: c.camera,
            activePhysicalCamera: physicalCamera, formatID: formatID, width: c.width, height: c.height,
            zoom: zoom, uncorrectedFieldOfView: 70)
    }
    func emitAudio(_ state: CaptureAudioState, sequence: UInt64, capture: CaptureID? = nil,
                   generation override: CaptureGeneration? = nil) {
        guard let generation = override ?? generation else { return }
        audioPair.continuation.yield(.init(generation: generation, capture: capture, sequence: sequence, state: state))
    }
    func configureAudioRecovery(outcomes: [CaptureAudioRecoveryOutcome], hold: Bool = false) {
        recoveryOutcomes = outcomes; holdAudioRecovery = hold
    }
    func recoverAudio(_ request: ProductCaptureAudioRecoveryRequest) async -> CaptureAudioRecoveryOutcome {
        audioRecoveryCalls += 1
        if holdAudioRecovery { return await withCheckedContinuation { heldRecovery = $0 } }
        let index = min(audioRecoveryCalls - 1, recoveryOutcomes.count - 1)
        return recoveryOutcomes[index]
    }
    func cancelAudioRecovery(_ request: ProductCaptureAudioRecoveryRequest) async {
        // Models an SDK reconfiguration that cannot release its owner until it returns.
        if heldRecovery != nil { await withCheckedContinuation { cancellationWaiters.append($0) } }
    }
    func completeAudioRecovery(_ result: CaptureAudioRecoveryOutcome) {
        let held = heldRecovery; heldRecovery = nil
        held?.resume(returning: result)
        let waiters = cancellationWaiters; cancellationWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
    func previewSource() async -> (any ProductCapturePreviewSource)? { await previewGate?.holdOnce(); return nil }
    func discoverCameras() async -> [ExplorationCameraDescription] {
        await discoverGate?.holdOnce()
        let c = fixture.desired.configuration
        return [.init(id: c.camera, label: "Synthetic camera", isVirtual: false, formats: [
            .init(id: "transient-index", width: c.width, height: c.height, frameRateRanges: [24...30],
                  logEncodings: [c.logEncoding], stabilizationModes: [c.stabilizationMode])])]
    }
    func shutDown() async {
        shutdowns += 1
        await shutdownGate?.holdOnce()
        sessionActive = false
    }
    func prepare(_ request: ProductCapturePreparation) async throws -> ExplorationPrepared {
        preparations += 1
        sessionActive = true
        await prepareGate?.holdOnce()
        generation = request.generation
        admission = NativeRecordingStartAdmission()
        wbOrder = ExplorationWBCommandOrder(generation: request.generation)
        let c = fixture.capabilities
        let exposure = differ ? try CaptureManualExposure(shutter: fixture.desired.exposure.shutter, iso: 161, aperture: nil) : fixture.desired.exposure
        return .init(capabilities: .init(generation: request.generation, configurations: c.configurations,
            controlsForConfiguration: c.controlsForConfiguration, manualControls: c.manualControls,
            whiteBalanceLock: c.whiteBalanceLock, whiteBalanceRefresh: .supported(refreshSupported)),
            applied: .init(generation: request.generation, operation: request.operation,
                values: .observed(.init(configuration: request.desired.configuration, exposure: exposure, zoom: request.desired.zoom),
                    at: fixture.time, method: .direct(source: "synthetic"))), audio: fixture.audio,
            stabilization: stabilizationEnabled ? stabilization(generation: request.generation,
                sequence: 1, active: stabilizationActive) : nil)
    }
    func submit(_ command: CaptureIOCommand) -> CaptureCommandAcceptance {
        commands.append(command)
        switch command {
        case .lockCurrentWhiteBalance(let token):
            guard wbOrder?.requestLock(token) == true else { return .rejected(token, .evidenceMismatch) }
            pendingLock = token
            if !holdInitialLock { completeWhiteBalanceLock() }
        case .restoreAutomaticWhiteBalance(let token):
            guard wbOrder?.requestAutomatic(token) == true, wbOrder?.appliedAutomatic(token) == true else { return .rejected(token, .evidenceMismatch) }
            emit(.capture(.automaticWhiteBalanceRestored(token, fixture.time)))
        case .startRecording(let token, let intent):
            // Exercise the exact admission/terminal producer used by Native submit, with lost audio.
            let decision = admission.admit(token: token, intentContext: intent.context, generation: generation,
                activeToken: activeToken, ownsWhiteBalanceLock: wbOrder?.canStart(token.context) == true,
                whiteBalanceLocked: true, sessionRunning: sessionActive, audioActive: !rejectStart, observedAt: fixture.time)
            if case .rejected(let terminal) = decision {
                if let terminal { lastEvents = [.capture(terminal)]; emit(.capture(terminal)) }
                return .rejected(token, .evidenceMismatch)
            }
            self.intent = intent
            activeToken = token
            emit(.capture(.recordingStarted(token, fixture.time)))
        case .stopRecording(let token, _):
            guard activeToken == token else { return .rejected(token, .evidenceMismatch) }
            pendingStop = token
            switch wbOrder?.holdForStop(token.context) ?? .stop {
            case .stop: finishRecording(token)
            case .lockCurrent(let refresh):
                pendingLock = refresh
                if !holdRefresh { completeWhiteBalanceLock() }
            case .waitForLock: break
            }
        case .refreshAndLockWhiteBalance(let token):
            guard refreshSupported, wbOrder?.requestRefresh(token) == true else { return .rejected(token, .unsupported) }
            pendingMeasurement = token
            if !holdRefresh { completeWhiteBalanceMeasurement(); completeWhiteBalanceLock() }
        }
        return .accepted(command.token)
    }
    func setNextWhiteBalance(_ lock: CaptureWhiteBalanceLock) { nextLock = lock }
    func completeWhiteBalanceMeasurement() {
        guard let token = pendingMeasurement, wbOrder?.measurementCompleted(token) == true else { return }
        pendingMeasurement = nil
        pendingLock = token
    }
    func completeWhiteBalanceLock() {
        guard let token = pendingLock, wbOrder?.appliedLock(token) == true else { return }
        pendingLock = nil
        emit(.capture(.whiteBalanceLocked(token, nextLock)))
        if wbOrder?.shouldStopAfterLock(token) == true, let stop = pendingStop { finishRecording(stop) }
    }
    func failWhiteBalanceLock() {
        guard let token = pendingLock ?? pendingMeasurement else { return }
        emit(.capture(.commandFailed(token, .adapterFailure(code: "synthetic-wb-lock"))))
        if let activeToken { finishRecording(activeToken, failed: true) }
    }
    private func finishRecording(_ token: CaptureCommandToken, failed: Bool = false) {
        guard activeToken == token, let intent else { return }
        activeToken = nil
        pendingStop = nil
        let end = failed ? RecordingEndEvidence(writer: .interrupted(.adapterFailure(code: "synthetic-wb-lock")),
            ceasedAt: fixture.time, lastVideo: fixture.time, lastAudio: fixture.time) : fixture.end
        lastEvents = [.capture(.recordingEnded(token, end))]
        if unconfirmedFile {
            lastEvents.append(.observation(.init(code: "file_finalization_unconfirmed", context: token.context,
                time: fixture.time, detail: "synthetic")))
        } else {
            lastEvents.append(.fileFinalized(.init(context: intent.context, original: intent.original,
                byteCount: 4096, finalizedAt: fixture.time)))
        }
        for event in lastEvents { emit(event) }
    }
    func emit(_ event: ExplorationDeviceEvent) { continuation.yield(event) }
    func repeatLastEndAndFile() { for event in lastEvents { emit(event) } }
}

extension ProductCaptureTestDevice: ProductCaptureDevicePort {}

actor ProductCaptureTestSave {
    private let delayIntent: Bool
    private let unknownIntent: Bool
    private let fileGate: ProductCaptureTestGate?
    private let endGate: ProductCaptureTestGate?
    private let failResult: Bool
    private var release: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var intents: [RecordingIntent] = []
    private(set) var ends: [RecordingEndEvidence] = []
    private(set) var files: [CaptureFileEvidence] = []
    init(delayIntent: Bool = false, unknownIntent: Bool = false,
         fileGate: ProductCaptureTestGate? = nil, failResult: Bool = false, endGate: ProductCaptureTestGate? = nil) {
        self.delayIntent = delayIntent; self.unknownIntent = unknownIntent
        self.fileGate = fileGate; self.failResult = failResult
        self.endGate = endGate
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
    func recordingEnded(context: CaptureContext, evidence: RecordingEndEvidence) async -> OriginalSaveOperationResult {
        ends.append(evidence)
        await endGate?.holdOnce()
        return .accepted
    }
    func fileFinalized(_ file: CaptureFileEvidence, resultToken: CaptureCommandToken) async -> OriginalSaveOperationResult {
        files.append(file)
        await fileGate?.holdOnce()
        if failResult { return .requiresReconciliation(.interrupted) }
        guard let intent = intents.last, let end = ends.last else { return .rejected(.wrongStage) }
        let inspection = CaptureMediaInspection(context: intent.context, original: intent.original,
            video: .unavailable(.notMeasured), audio: .unavailable(.notMeasured), format: .unavailable(.notMeasured),
            playback: .unavailable(.notMeasured), completeness: .unknown(.notMeasured))
        return .committed(.init(intent: intent, end: end, file: file, inspection: inspection, result: .unknown(.notMeasured)),
                          .init(token: resultToken, previousRevision: 1, committedRevision: 2))
    }
}

extension ProductCaptureTestSave: ProductCaptureSavePort {}

/// A one-use suspension that deliberately ignores cancellation, like a late SDK/store callback.
actor ProductCaptureTestGate {
    private var used = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var waiting: CheckedContinuation<Void, Never>?
    func holdOnce() async {
        guard !used else { return }
        used = true
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
            waiting?.resume(); waiting = nil
        }
    }
    func waitUntilHeld() async {
        if releaseContinuation != nil { return }
        await withCheckedContinuation { waiting = $0 }
    }
    func release() { releaseContinuation?.resume(); releaseContinuation = nil }
}

actor ProductCaptureTestDeviceFactory {
    private let devices: [ProductCaptureTestDevice]
    private let makeGate: ProductCaptureTestGate?
    private(set) var creations = 0
    private(set) var candidates: [ExplorationOutputCandidate] = []
    init(_ devices: [ProductCaptureTestDevice], makeGate: ProductCaptureTestGate? = nil) {
        self.devices = devices; self.makeGate = makeGate
    }
    func make(candidate: ExplorationOutputCandidate = .sampleWriter) async -> ProductCaptureTestDevice {
        candidates.append(candidate)
        let index = min(creations, devices.count - 1)
        creations += 1
        await makeGate?.holdOnce()
        return devices[index]
    }
}
