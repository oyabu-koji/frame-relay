import Foundation
import Testing
@testable import FrameRelay

@MainActor
struct ProductCapturePostSaveTests {
    @Test func unconfirmedFileWaitsForEndPersistenceAndDuplicatesCannotRefreshAgain() async throws {
        let fixture = try CaptureFixture()
        let endGate = ProductCaptureTestGate()
        let device = ProductCaptureTestDevice(fixture: fixture, unconfirmedFile: true)
        let save = ProductCaptureTestSave(endGate: endGate)
        let probe = ProductCaptureTestProbe()
        let model = ProductCaptureCoordinator(preferences: ProductCaptureTestPreferences(fixture: fixture),
            makeDevice: { _ in device }, save: save,
            bindOriginal: { await probe.bind($0) }, didSave: { await probe.refresh() }, calendarNow: { Date() })
        model.enterCapture()
        await model.load(); await model.prepare(); await model.record()
        await eventually { model.capture?.phase == .recording }
        await model.stop()
        await endGate.waitUntilHeld()
        #expect(model.isSaving)
        #expect(model.issue == nil)
        #expect(await probe.refreshes == 0)
        await device.repeatLastEndAndFile()
        await endGate.release()
        await eventually { !model.isBusy }
        await probe.waitForRefreshCount(1)
        #expect(model.saveResult == nil)
        #expect(model.issue?.contains("ファイルの確定") == true)
        #expect(await save.files.isEmpty)
        #expect(await probe.bound.isEmpty)
        await device.repeatLastEndAndFile()
        for _ in 0..<20 { await Task.yield() }
        #expect(await probe.refreshes == 1)
        #expect(await save.ends.count == 1)
        await model.leaveCapture()
    }

    @Test(arguments: [false, true])
    func safeSaveWaitsButSlowBindingCannotBlockOrContaminateLaterClips(bindSucceeds: Bool) async throws {
        let fixture = try CaptureFixture()
        let fileGate = ProductCaptureTestGate()
        let bindGate = ProductCaptureTestGate()
        let device = ProductCaptureTestDevice(fixture: fixture)
        let save = ProductCaptureTestSave(fileGate: fileGate)
        let probe = PostSaveProbe(bindGate: bindGate, bindSucceeds: bindSucceeds)
        let model = makeModel(fixture: fixture, devices: [device], save: save, probe: probe)
        await model.load(); await model.prepare(); await model.record()
        await eventually { model.capture?.phase == .recording }
        await model.stop()
        await fileGate.waitUntilHeld()
        #expect(model.isSaving)
        #expect(!model.canRecord)
        await model.record()
        await model.updatePreferences(.init())
        #expect(await save.intents.count == 1)
        #expect(model.preferences.desired == fixture.desired)
        await fileGate.release()
        await bindGate.waitUntilHeld()
        await eventually { model.canRecord }
        #expect(model.saveResult == .unknown(.notMeasured))
        #expect(!model.isSaving)
        await model.record()
        await eventually { model.capture?.phase == .recording }
        await model.stop()
        await eventually { model.canRecord }
        #expect(await save.files.count == 2)
        #expect(await probe.bound.count == 1)
        #expect(await probe.refreshes == 0)
        await model.record()
        await eventually { model.capture?.phase == .recording }
        let third = try #require(model.capture?.context)
        await bindGate.release()
        await probe.waitForRefreshes(2)
        #expect(model.capture?.context == third)
        #expect(model.capture?.phase == .recording)
        #expect(model.isSaving)
        #expect(model.saveResult == nil)
        #expect(model.issue == nil)
        await device.repeatLastEndAndFile()
        await model.stop()
        await eventually { model.canRecord }
        await probe.waitForRefreshes(3)
        let originals = await save.intents.map(\.original)
        #expect(await probe.bound == originals)
        #expect(await probe.events == originals.flatMap { ["bind:\($0.rawValue)", "refresh"] })
        #expect(await save.files.count == 3)
        await device.emit(.observation(.init(code: "file_finalization_unconfirmed", context: third,
            time: fixture.time, detail: "late-terminal")))
        await device.repeatLastEndAndFile()
        for _ in 0..<20 { await Task.yield() }
        #expect(await probe.refreshes == 3)
        #expect(model.issue == nil)
        #expect(model.saveResult == .unknown(.notMeasured))
        await model.leaveCapture()
    }

    @Test func settingsAndNavigationDoNotCancelQueuedOriginalOrAffectNewVisit() async throws {
        let fixture = try CaptureFixture()
        let bindGate = ProductCaptureTestGate()
        let first = ProductCaptureTestDevice(fixture: fixture)
        let second = ProductCaptureTestDevice(fixture: fixture)
        let save = ProductCaptureTestSave()
        let probe = PostSaveProbe(bindGate: bindGate, bindSucceeds: false)
        let model = makeModel(fixture: fixture, devices: [first, second], save: save, probe: probe)
        await model.load(); await model.prepare(); await model.record()
        await eventually { model.capture?.phase == .recording }
        await model.stop()
        await bindGate.waitUntilHeld()
        await eventually { model.canRecord }
        let changed = ProductCapturePreferences(desired: fixture.desired, outputCandidate: .movieFile)
        await model.updatePreferences(changed)
        #expect(model.preferences == changed)
        #expect(await first.shutdowns == 1)
        await model.leaveCapture()
        model.enterCapture()
        await model.load(); await model.prepare(); await model.record()
        await eventually { model.capture?.phase == .recording }
        let context = try #require(model.capture?.context)
        await bindGate.release()
        await probe.waitForRefreshes(1)
        #expect(model.capture?.context == context)
        #expect(model.capture?.phase == .recording)
        #expect(model.preferences == changed)
        #expect(model.issue == nil)
        #expect(model.saveResult == nil)
        await model.stop()
        await eventually { model.canRecord }
        await probe.waitForRefreshes(2)
        let originals = await save.intents.map(\.original)
        #expect(await probe.bound == originals)
        await model.leaveCapture()
    }

    @Test func failedSaveRefreshDoesNotDelayRepreparationOrOverwriteNextRecording() async throws {
        let fixture = try CaptureFixture()
        let first = ProductCaptureTestDevice(fixture: fixture)
        let second = ProductCaptureTestDevice(fixture: fixture)
        let factory = ProductCaptureTestDeviceFactory([first, second])
        let probe = ProductCaptureTestProbe(holdRefresh: true)
        let save = ProductCaptureTestSave(failResult: true)
        let model = ProductCaptureCoordinator(preferences: ProductCaptureTestPreferences(fixture: fixture),
            makeDevice: { await factory.make(candidate: $0) }, save: save,
            bindOriginal: { await probe.bind($0) }, didSave: { await probe.refresh() }, calendarNow: { Date() })
        model.enterCapture()
        await model.load(); await model.prepare(); await model.record()
        await eventually { model.capture?.phase == .recording }
        await model.stop()
        await probe.waitForRefresh()
        #expect(!model.isSaving)
        #expect(model.issue != nil)
        #expect(model.saveResult == nil)
        #expect(await probe.bound.isEmpty)
        await model.prepare(); await model.record()
        await eventually { model.capture?.phase == .recording }
        let context = try #require(model.capture?.context)
        await probe.releaseRefresh()
        #expect(model.capture?.context == context)
        #expect(model.issue == nil)
        #expect(model.isSaving)
        await model.stop()
        await eventually { !model.isBusy }
        await probe.waitForRefreshCount(2)
        await model.leaveCapture()
    }

    private func makeModel(fixture: CaptureFixture, devices: [ProductCaptureTestDevice],
                           save: ProductCaptureTestSave, probe: PostSaveProbe) -> ProductCaptureCoordinator {
        let factory = ProductCaptureTestDeviceFactory(devices)
        let model = ProductCaptureCoordinator(preferences: ProductCaptureTestPreferences(fixture: fixture),
            makeDevice: { await factory.make(candidate: $0) }, save: save,
            bindOriginal: { await probe.bind($0) }, didSave: { await probe.refresh() }, calendarNow: { Date() })
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

private actor PostSaveProbe {
    private let bindGate: ProductCaptureTestGate
    private let bindSucceeds: Bool
    private(set) var bound: [CaptureOriginalReference] = []
    private(set) var events: [String] = []
    private(set) var refreshes = 0
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(bindGate: ProductCaptureTestGate, bindSucceeds: Bool) {
        self.bindGate = bindGate; self.bindSucceeds = bindSucceeds
    }

    func bind(_ original: CaptureOriginalReference) async -> Bool {
        bound.append(original)
        events.append("bind:\(original.rawValue)")
        await bindGate.holdOnce()
        return bindSucceeds
    }

    func refresh() {
        events.append("refresh")
        refreshes += 1
        let ready = waiters.filter { $0.0 <= refreshes }
        waiters.removeAll { $0.0 <= refreshes }
        for (_, waiter) in ready { waiter.resume() }
    }

    func waitForRefreshes(_ count: Int) async {
        if refreshes >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
}
