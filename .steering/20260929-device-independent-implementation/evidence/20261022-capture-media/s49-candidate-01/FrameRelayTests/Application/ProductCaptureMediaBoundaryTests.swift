import Foundation
import Testing
@testable import FrameRelay

@MainActor struct ProductCaptureMediaBoundaryTests {
    @Test func ownerRevisionRejectsDuplicatesRetiredOwnersAndOldEndWithoutOpeningNewCapture() throws {
        let admission = CaptureMediaAdmission()
        let first = try captureBoundaryOwner()
        let second = try captureBoundaryOwner()
        admission.begin(first, phases: [.recording])
        let begun = admission.snapshot()
        admission.begin(first, phases: [.saving])
        #expect(admission.snapshot() == begun)
        admission.begin(second, phases: [.recovery])
        admission.update(first, phases: [.saving])
        #expect(admission.snapshot().waits == [.saving, .recovery])
        admission.end(first)
        let remaining = admission.snapshot()
        #expect(remaining.isHeld && remaining.owners[second] == [.recovery])
        admission.end(first)
        admission.update(first, phases: [.recording])
        admission.begin(first, phases: [.recording])
        #expect(admission.snapshot() == remaining)
        admission.end(second)
        #expect(!admission.snapshot().isHeld)
        #expect(admission.snapshot().revision > begun.revision)
    }

    @Test(arguments: ["stop", "leave"])
    func preflightHoldsBeforeFirstAwaitAndRevokedTicketCannotIssueAnyRecordingCommand(action: String) async throws {
        let fixture = try CaptureFixture()
        let gate = ProductCaptureTestGate()
        let boundary = CaptureBoundaryProbe(gate: gate)
        let device = ProductCaptureTestDevice(fixture: fixture)
        let save = ProductCaptureTestSave()
        let model = makeModel(fixture, device: device, save: save, boundary: boundary)
        await model.load(); await model.prepare()
        let start = Task { await model.record() }
        await gate.waitUntilHeld()
        #expect(boundary.waitSnapshots.count == 1)
        #expect(boundary.waitSnapshots[0].waits == [.recording])
        #expect(boundary.admission.snapshot().isHeld)
        #expect(model.isStarting && model.capture == nil)
        #expect(await device.commands.isEmpty)
        #expect(await save.intents.isEmpty)
        if action == "stop" { await model.stop() } else { await model.leaveCapture() }
        #expect(!boundary.admission.snapshot().isHeld)
        #expect(!model.isStarting)
        await gate.release()
        await start.value
        #expect(await device.startCount == 0)
        #expect(await save.intents.isEmpty)
        #expect(model.capture == nil)
        await model.leaveCapture()
    }

    @Test func oldPreflightCompletionCannotClearOrBeginNewRecording() async throws {
        let fixture = try CaptureFixture()
        let gate = ProductCaptureTestGate()
        let boundary = CaptureBoundaryProbe(gate: gate)
        let device = ProductCaptureTestDevice(fixture: fixture)
        let save = ProductCaptureTestSave()
        let model = makeModel(fixture, device: device, save: save, boundary: boundary)
        await model.load(); await model.prepare()
        let old = Task { await model.record() }
        await gate.waitUntilHeld()
        let obsolete = try #require(boundary.begun.first)
        await model.stop()
        await model.record()
        try await captureBoundaryEventually { model.capture?.phase == .recording }
        let current = try #require(model.capture?.context)
        await gate.release(); await old.value
        #expect(model.capture?.context == current && model.isSaving)
        #expect(await device.startCount == 1)
        #expect(boundary.admission.snapshot().owners[obsolete] == nil)
        #expect(boundary.admission.snapshot().owners.count == 1)
        await model.stop()
        try await captureBoundaryEventually { !model.isBusy }
        #expect(!boundary.admission.snapshot().isHeld)
        await model.leaveCapture()
    }

    @Test func unknownLocalStopDoesNotBeginLifecycleOrSaving() async throws {
        let fixture = try CaptureFixture()
        let boundary = CaptureBoundaryProbe(result: .unknown)
        let device = ProductCaptureTestDevice(fixture: fixture)
        let save = ProductCaptureTestSave()
        let model = makeModel(fixture, device: device, save: save, boundary: boundary)
        await model.load(); await model.prepare(); await model.record()
        #expect(await save.intents.isEmpty)
        #expect(await device.commands.isEmpty)
        #expect(model.capture == nil && !model.isStarting && !model.isSaving)
        #expect(model.issue?.contains("停止を確認") == true)
        #expect(!boundary.admission.snapshot().isHeld)
        await model.leaveCapture()
    }

    @Test func recAcceptanceClocksStayFixedAcrossLocalStopDelay() async throws {
        let fixture = try CaptureFixture()
        let gate = ProductCaptureTestGate()
        let boundary = CaptureBoundaryProbe(gate: gate)
        let device = ProductCaptureTestDevice(fixture: fixture)
        let save = ProductCaptureTestSave()
        let accepted = Date(timeIntervalSince1970: 1_234_567.125)
        let clock = CaptureBoundaryClock(calendar: accepted, capture: fixture.time)
        let model = ProductCaptureCoordinator(preferences: ProductCaptureTestPreferences(fixture: fixture),
            makeDevice: { _ in device }, save: save, bindOriginal: { _ in true }, didSave: {}, mediaBoundary: boundary,
            calendarNow: { clock.calendar() }, captureNow: { clock.capture() })
        model.enterCapture()
        await model.load(); await model.prepare()
        let start = Task { await model.record() }
        await gate.waitUntilHeld()
        clock.advance(calendar: accepted.addingTimeInterval(30), capture: .unavailable(.notMeasured))
        await gate.release(); await start.value
        let intent = try #require(await save.intents.first)
        #expect(intent.capturedAt == accepted)
        #expect(intent.acceptedAt == fixture.time)
        await model.stop()
        try await captureBoundaryEventually { !model.isBusy }
        await model.leaveCapture()
    }

    @Test(arguments: ["file", "unconfirmed", "failed", "notStarted", "intentUnknown"])
    func recordingAndSavingOwnersEndOnlyAtTheirActualTerminal(exit: String) async throws {
        let fixture = try CaptureFixture()
        let gate = ProductCaptureTestGate()
        let boundary = CaptureBoundaryProbe()
        let device = ProductCaptureTestDevice(fixture: fixture, rejectStart: exit == "notStarted", unconfirmedFile: exit == "unconfirmed")
        let save = ProductCaptureTestSave(unknownIntent: exit == "intentUnknown",
            fileGate: exit == "file" || exit == "failed" ? gate : nil, failResult: exit == "failed",
            endGate: exit == "unconfirmed" || exit == "notStarted" ? gate : nil)
        let model = makeModel(fixture, device: device, save: save, boundary: boundary)
        await model.load(); await model.prepare()
        let recording = Task { await model.record() }
        if exit != "notStarted" { await recording.value }
        if exit != "intentUnknown" {
            if exit != "notStarted" {
                try await captureBoundaryEventually { model.capture?.phase == .recording }
                #expect(boundary.admission.snapshot().waits == [.recording, .saving])
                await model.stop()
            }
            await gate.waitUntilHeld()
            #expect(model.isSaving)
            #expect(boundary.admission.snapshot().waits == [.saving])
            await gate.release()
        }
        await recording.value
        try await captureBoundaryEventually { !model.isBusy }
        #expect(!boundary.admission.snapshot().isHeld)
        #expect(boundary.ended.count == 1)
        await device.repeatLastEndAndFile()
        for _ in 0..<10 { await Task.yield() }
        #expect(boundary.ended.count == 1)
        await model.leaveCapture()
    }

    @Test func audioRecoveryHasIndependentOwnerUntilActualRecoveryAndCancelReturn() async throws {
        let fixture = try CaptureFixture()
        let boundary = CaptureBoundaryProbe()
        let device = ProductCaptureTestDevice(fixture: fixture)
        await device.configureAudioRecovery(outcomes: [], hold: true)
        let model = makeModel(fixture, device: device, save: ProductCaptureTestSave(), boundary: boundary,
            audioPolicy: ProductCaptureFactory.provisionalAudioPolicyV1)
        await model.load(); await model.prepare()
        var failure = fixture.audio
        failure.input = .failed(.routeInterrupted(.init(rawValue: "boundary-test-route")))
        await device.emitAudio(failure, sequence: 1)
        try await captureBoundaryEventually { model.canRetryAudio }
        let retry = Task { await model.retryAudio() }
        try await backgroundEventually { await device.audioRecoveryCalls == 1 }
        #expect(boundary.admission.snapshot().waits == [.recovery])
        let leave = Task { await model.leaveCapture() }
        for _ in 0..<10 { await Task.yield() }
        #expect(model.isRecoveringAudio)
        #expect(boundary.admission.snapshot().waits == [.recovery])
        await device.completeAudioRecovery(.validInput(route: "actual-return"))
        await retry.value; await leave.value
        #expect(!boundary.admission.snapshot().isHeld)
        #expect(await device.startCount == 0)
    }

    @Test func failedEndPersistenceKeepsOldOwnerUntilLateFileReturnWithoutOpeningNewCapture() async throws {
        let fixture = try CaptureFixture()
        let fileGate = ProductCaptureTestGate()
        let boundary = CaptureBoundaryProbe()
        let device = ProductCaptureTestDevice(fixture: fixture)
        let second = ProductCaptureTestDevice(fixture: fixture)
        let devices = ProductCaptureTestDeviceFactory([device, second])
        let save = CaptureEndFailureSave(fileGate: fileGate)
        let model = ProductCaptureCoordinator(preferences: ProductCaptureTestPreferences(fixture: fixture),
            makeDevice: { await devices.make(candidate: $0) }, save: save, bindOriginal: { _ in true }, didSave: {},
            mediaBoundary: boundary, calendarNow: { Date() })
        model.enterCapture()
        await model.load(); await model.prepare(); await model.record()
        try await captureBoundaryEventually { model.capture?.phase == .recording }
        let oldContext = try #require(model.capture?.context)
        let oldOwner = try #require(boundary.begun.first)
        await model.stop()
        await fileGate.waitUntilHeld()
        #expect(!model.isSaving)
        #expect(boundary.admission.snapshot().owners[oldOwner] == [.saving])
        await model.prepare()
        let next = Task { await model.record() }
        try await captureBoundaryEventually { model.capture?.context != oldContext && model.isSaving }
        let newContext = try #require(model.capture?.context)
        #expect(boundary.admission.snapshot().owners.count == 2)
        await fileGate.release(); await next.value
        try await captureBoundaryEventually { model.capture?.phase == .recording }
        #expect(model.capture?.context == newContext && model.issue == nil)
        #expect(boundary.admission.snapshot().owners[oldOwner] == nil)
        #expect(boundary.admission.snapshot().waits == [.recording, .saving])
        await model.stop()
        try await captureBoundaryEventually { !model.isBusy }
        #expect(!boundary.admission.snapshot().isHeld)
        await model.leaveCapture()
    }

    private func makeModel(_ fixture: CaptureFixture, device: ProductCaptureTestDevice, save: ProductCaptureTestSave,
        boundary: CaptureBoundaryProbe, audioPolicy: ProductCaptureAudioPolicy? = nil) -> ProductCaptureCoordinator {
        let model = ProductCaptureCoordinator(preferences: ProductCaptureTestPreferences(fixture: fixture),
            makeDevice: { _ in device }, save: save, bindOriginal: { _ in true }, didSave: {},
            mediaBoundary: boundary, audioPolicy: audioPolicy, calendarNow: { Date() })
        model.enterCapture()
        return model
    }
}

@MainActor final class CaptureBoundaryProbe: CaptureMediaBoundaryPort {
    let admission = CaptureMediaAdmission()
    let gate: ProductCaptureTestGate?
    let result: CaptureMediaLocalStop
    private(set) var begun: [CaptureMediaOwner] = []
    private(set) var ended: [CaptureMediaOwner] = []
    private(set) var waitSnapshots: [CaptureMediaAdmission.Snapshot] = []
    init(gate: ProductCaptureTestGate? = nil, result: CaptureMediaLocalStop = .ready) { self.gate = gate; self.result = result }
    func begin(_ owner: CaptureMediaOwner, phases: Set<CaptureMediaPhase>) { admission.begin(owner, phases: phases); begun.append(owner) }
    func update(_ owner: CaptureMediaOwner, phases: Set<CaptureMediaPhase>) { admission.update(owner, phases: phases) }
    func end(_ owner: CaptureMediaOwner) { admission.end(owner); ended.append(owner) }
    func waitForLocalStop(_ owner: CaptureMediaOwner) async -> CaptureMediaLocalStop {
        waitSnapshots.append(admission.snapshot())
        await gate?.holdOnce()
        return result
    }
}

nonisolated private final class CaptureBoundaryClock: @unchecked Sendable {
    private let lock = NSLock()
    private var wall: Date
    private var monotonic: CaptureTimeObservation
    init(calendar: Date, capture: CaptureTimeObservation) { wall = calendar; monotonic = capture }
    func calendar() -> Date { lock.lock(); defer { lock.unlock() }; return wall }
    func capture() -> CaptureTimeObservation { lock.lock(); defer { lock.unlock() }; return monotonic }
    func advance(calendar: Date, capture: CaptureTimeObservation) {
        lock.lock(); defer { lock.unlock() }; wall = calendar; monotonic = capture
    }
}

private actor CaptureEndFailureSave: ProductCaptureSavePort {
    let base: ProductCaptureTestSave
    private var ends = 0
    init(fileGate: ProductCaptureTestGate) { base = ProductCaptureTestSave(fileGate: fileGate) }
    func begin(_ intent: RecordingIntent, token: CaptureCommandToken) async -> OriginalSaveOperationResult {
        await base.begin(intent, token: token)
    }
    func recordingEnded(context: CaptureContext, evidence: RecordingEndEvidence) async -> OriginalSaveOperationResult {
        ends += 1
        let result = await base.recordingEnded(context: context, evidence: evidence)
        return ends == 1 ? .requiresReconciliation(.interrupted) : result
    }
    func fileFinalized(_ file: CaptureFileEvidence, resultToken: CaptureCommandToken) async -> OriginalSaveOperationResult {
        await base.fileFinalized(file, resultToken: resultToken)
    }
}

nonisolated func captureBoundaryOwner() throws -> CaptureMediaOwner {
    .init(context: try CaptureFixture().context, visit: UUID(), nonce: UUID())
}

@MainActor func captureBoundaryEventually(_ condition: @MainActor () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !condition() {
        guard ContinuousClock.now < deadline else { throw BackendContractError.unavailable }
        await Task.yield()
    }
}
