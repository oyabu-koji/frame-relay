import Foundation
import Testing
@testable import FrameRelay

@MainActor
struct ExplorationCoordinatorTests {
    @Test func initializationAndSimulatorPreparationCannotCreateMediaOrRequestCapture() async throws {
        let fixture = try CaptureFixture()
        let factory = TestExplorationFactory(fixture: fixture, runtime: .simulator)
        let model = ExplorationCoordinator(factory: factory)
        #expect(await factory.makeCount == 0)
        #expect(await factory.device.commands.isEmpty)
        #expect(await factory.diagnostics.attempts.isEmpty)
        #expect(!model.diagnosticsReady)
        await model.prepare()
        #expect(model.issues.contains(.simulatorHasNoVerifiedCamera))
        #expect(model.issues.contains(.ticketMissing))
        #expect(model.prepared == nil)
        #expect(model.capture == nil)
        #expect(await factory.makeCount == 0)
    }

    @Test func D02UnverifiedOnlyBlocksDisplayAlongsideRecording() throws {
        let fixture = try CaptureFixture()
        let runtime = ExplorationRuntime.physicalDevice(osVersion: "27.0.0", availableBytes: 1_000_000_000)
        let recording = try explorationTicket(fixture: fixture)
        #expect(ExplorationGate.issues(ticket: recording, output: .movieFile, store: .sqlite, runtime: runtime).isEmpty)
        let display = try explorationTicket(fixture: fixture, display: .standardRec709AlongsideRecording)
        #expect(ExplorationGate.issues(ticket: display, output: .movieFile, store: .sqlite, runtime: runtime)
                == [.rec709TransformUnverified])
        #expect(ExplorationGate.issues(ticket: recording, output: nil, store: .sqlite, runtime: runtime)
                == [.candidateMissing])
        #expect(ExplorationGate.issues(ticket: recording, output: .movieFile, store: .sqlite,
                                       runtime: .physicalDevice(osVersion: "different", availableBytes: 1))
                == [.osVersionDiffers, .capacityInsufficient])
    }

    @Test func preparationFreezesCandidatesAndDoesNotTreatCapabilityAsRecording() async throws {
        let fixture = try CaptureFixture()
        let factory = TestExplorationFactory(fixture: fixture)
        let model = ExplorationCoordinator(factory: factory)
        model.bindTicket(data: try JSONEncoder().encode(explorationTicket(fixture: fixture)))
        model.selectOutput(.movieFile)
        model.selectStore(.atomicFile)
        await model.prepare()
        #expect(model.prepared != nil)
        #expect(model.capture == nil)
        model.selectOutput(.sampleWriter)
        model.selectStore(.sqlite)
        #expect(model.outputCandidate == .movieFile)
        #expect(model.storeCandidate == .atomicFile)
        #expect(model.issues == [.operationInProgress])
    }

    @Test(arguments: [true, false])
    func earlyWBRejectionOrSTOPRetainsEndUntilLateIntentCommit(rejectWB: Bool) async throws {
        let fixture = try CaptureFixture()
        let factory = TestExplorationFactory(fixture: fixture, rejectWB: rejectWB)
        let model = ExplorationCoordinator(factory: factory)
        model.bindTicket(data: try JSONEncoder().encode(explorationTicket(fixture: fixture)))
        model.selectOutput(.sampleWriter)
        model.selectStore(.atomicFile)
        await model.prepare()
        let recordingTask = Task { await model.record() }
        await factory.store.waitForIntent()
        #expect(model.save?.phase == .awaitingIntentCommit)
        if !rejectWB { await model.stop() }
        #expect(model.capture?.end?.writer == .notStarted)
        await factory.store.releaseIntent()
        await recordingTask.value
        #expect(model.save?.phase == .recordingEnded)
        #expect(model.saveIssue?.contains("手動照合待ち") == true)
        let commands = await factory.device.commands
        #expect(!commands.contains { if case .startRecording = $0 { return true }; return false })
        #expect(commands.contains { if case .restoreAutomaticWhiteBalance = $0 { return true }; return false })
        #expect(model.isBusy) // Unfinished persistence is not silently normalized to saved.
    }

    @Test func malformedDecodedNumbersAndNewInvalidImportDoNotReuseOldTicket() throws {
        let fixture = try CaptureFixture()
        let ticket = try explorationTicket(fixture: fixture)
        let data = try JSONEncoder().encode(ticket)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var settings = try #require(object["desired"] as? [String: Any])
        var configuration = try #require(settings["configuration"] as? [String: Any])
        configuration["framesPerSecond"] = Int64.max
        settings["configuration"] = configuration
        object["desired"] = settings
        let invalidData = try JSONSerialization.data(withJSONObject: object)
        let invalid = try JSONDecoder().decode(ExplorationTicket.self, from: invalidData)
        #expect(invalid.validationIssues.contains(.settingsInvalid))
        let model = ExplorationCoordinator(factory: TestExplorationFactory(fixture: fixture))
        model.bindTicket(data: data)
        #expect(model.ticket != nil)
        model.bindTicket(data: invalidData)
        #expect(model.ticket == nil)
    }

    @Test func ticketTransportFailureUnbindsThePreviousTicketAndCandidates() async throws {
        let fixture = try CaptureFixture()
        let factory = TestExplorationFactory(fixture: fixture)
        let model = ExplorationCoordinator(factory: factory, ticketLoader: { _ in throw ExplorationIssue.ticketReadFailed })
        model.bindTicket(data: try JSONEncoder().encode(explorationTicket(fixture: fixture)))
        model.selectOutput(.movieFile)
        model.selectStore(.sqlite)
        await model.importTicket(from: URL(fileURLWithPath: "/synthetic-selected-ticket-not-read"))
        #expect(model.ticket == nil)
        #expect(model.outputCandidate == nil)
        #expect(model.storeCandidate == nil)
        #expect(model.issues == [.ticketReadFailed])
        await model.prepare()
        #expect(model.issues.contains(.ticketMissing))
        #expect(await factory.makeCount == 0)
    }

    @Test func receivedObservationsPersistInReceiveOrderWithOriginalTimes() async throws {
        let fixture = try CaptureFixture()
        let factory = TestExplorationFactory(fixture: fixture)
        let model = ExplorationCoordinator(factory: factory)
        model.bindTicket(data: try JSONEncoder().encode(explorationTicket(fixture: fixture)))
        model.selectOutput(.movieFile)
        model.selectStore(.atomicFile)
        await model.prepare()
        let first = ExplorationDeviceEvent.observation(.init(code: "synthetic_first", context: fixture.context,
                                                             time: fixture.time, detail: "synthetic_value_only"))
        let second = ExplorationDeviceEvent.observation(.init(code: "synthetic_second", context: fixture.context,
                                                              time: .unavailable(.notMeasured), detail: "synthetic_value_only"))
        await factory.device.emit(first)
        await factory.device.emit(second)
        await factory.diagnostics.waitForAttemptCount(2)
        let records = await factory.diagnostics.load()
        #expect(records.map(\.event) == [first, second])
        #expect(records.map(\.sequence) == [1, 2])
        #expect(model.diagnosticsIssue == nil)
    }

    @Test(arguments: [false, true])
    func diagnosticFailurePersistsAndBlocksNewRECWithoutDiscardingAnEarlyEnd(startActive: Bool) async throws {
        let fixture = try CaptureFixture()
        let factory = TestExplorationFactory(fixture: fixture, failDiagnostics: true)
        let model = ExplorationCoordinator(factory: factory)
        model.bindTicket(data: try JSONEncoder().encode(explorationTicket(fixture: fixture)))
        model.selectOutput(.sampleWriter)
        model.selectStore(.atomicFile)
        await model.prepare()
        let recordingTask: Task<Void, Never>?
        if startActive {
            recordingTask = Task { await model.record() }
            await factory.store.waitForIntent()
        } else { recordingTask = nil }
        let event = ExplorationDeviceEvent.observation(.init(code: "synthetic_diagnostic_failure", context: fixture.context,
                                                             time: fixture.time, detail: "synthetic_value_only"))
        await factory.device.emit(event)
        await factory.device.emit(event)
        // The second attempt follows handling and stopping for the first failure.
        await factory.diagnostics.waitForAttemptCount(2)
        #expect(model.diagnosticsIssue != nil)
        if startActive {
            #expect(model.capture?.end?.writer == .notStarted)
            await factory.store.releaseIntent()
            await recordingTask?.value
            #expect(model.save?.phase == .recordingEnded)
        } else { #expect(model.capture == nil) }
        let identityCount = await factory.identityCount
        #expect(await model.preparationIssues().isEmpty)
        await model.record()
        #expect(await factory.identityCount == identityCount)
        #expect(model.diagnosticsIssue != nil)
        let commands = await factory.device.commands
        #expect(!commands.contains { if case .startRecording = $0 { return true }; return false })
        #expect(commands.filter { if case .restoreAutomaticWhiteBalance = $0 { return true }; return false }.count == (startActive ? 1 : 0))
    }
}

nonisolated private func explorationTicket(fixture: CaptureFixture,
                                          display: ExplorationDisplayCondition = .recordingOnly) throws -> ExplorationTicket {
    // Synthetic exploration bounds, never installed as app defaults or phone facts.
    ExplorationTicket(schemaVersion: 1, environmentReference: "synthetic-env", authorizationRecordReference: "synthetic-scope",
                      existingDataScopeReference: "synthetic-data-scope", evidenceVaultReference: "synthetic-vault",
                      caseID: "synthetic-case", repetitionID: "synthetic-repeat", conditionVersion: "synthetic-v1",
                      reportedDeviceModel: "synthetic-device", actualOSVersion: "27.0.0", totalCapacityBytes: 2_000_000_000,
                      availableCapacityBytes: 1_000_000_000, formatID: "format-1", desired: fixture.desired, display: display,
                      maximumDuration: try .init(ticks: 10, timescale: 1), maximumFileBytes: 10_000_000, minimumRemainingBytes: 100_000_000)
}

private actor TestExplorationFactory: ExplorationFactoryPort {
    let fixture: CaptureFixture
    let runtimeValue: ExplorationRuntime
    let device: TestExplorationDevice
    let store: TestExplorationStore
    let diagnostics: TestExplorationDiagnostics
    private(set) var makeCount = 0
    private(set) var identityCount = 0

    init(fixture: CaptureFixture,
         runtime: ExplorationRuntime = .physicalDevice(osVersion: "27.0.0", availableBytes: 1_000_000_000),
         rejectWB: Bool = false, failDiagnostics: Bool = false) {
        self.fixture = fixture
        runtimeValue = runtime
        store = TestExplorationStore()
        device = TestExplorationDevice(fixture: fixture, rejectWB: rejectWB)
        diagnostics = TestExplorationDiagnostics(fails: failDiagnostics)
    }

    func runtime() -> ExplorationRuntime { runtimeValue }
    func makeServices(ticket: ExplorationTicket, output: ExplorationOutputCandidate,
                      store: ExplorationStoreCandidate) -> ExplorationServices {
        makeCount += 1
        return ExplorationServices(generation: fixture.context.generation, device: device,
                                   store: self.store, inspection: TestExplorationInspection(), diagnostics: diagnostics)
    }
    func nextCaptureIdentity(generation: CaptureGeneration) -> (CaptureContext, CaptureOperationID, CaptureOriginalReference) {
        identityCount += 1
        return (fixture.context, fixture.intent.operation, fixture.intent.original)
    }
    func currentTime() -> CaptureTimeObservation { fixture.time }
}

private actor TestExplorationDevice: ExplorationDevicePort {
    let fixture: CaptureFixture
    let rejectWB: Bool
    let stream: AsyncStream<ExplorationDeviceEvent>
    let continuation: AsyncStream<ExplorationDeviceEvent>.Continuation
    private(set) var commands: [CaptureIOCommand] = []
    init(fixture: CaptureFixture, rejectWB: Bool) {
        self.fixture = fixture
        self.rejectWB = rejectWB
        (stream, continuation) = AsyncStream.makeStream()
    }
    func discover() -> [ExplorationCameraDescription] { [] }
    func prepare(_ request: ExplorationPreparation) -> ExplorationPrepared {
        ExplorationPrepared(capabilities: fixture.capabilities, applied: fixture.applied, audio: fixture.audio)
    }
    func events() -> AsyncStream<CaptureIOEvent> { AsyncStream { $0.finish() } }
    func explorationEvents() -> AsyncStream<ExplorationDeviceEvent> { stream }
    func shutDown() { continuation.finish() }
    func emit(_ event: ExplorationDeviceEvent) { continuation.yield(event) }
    func submit(_ command: CaptureIOCommand) -> CaptureCommandAcceptance {
        commands.append(command)
        if case .lockCurrentWhiteBalance = command, rejectWB {
            return .rejected(command.token, .resourceUnavailable)
        }
        return .accepted(command.token)
    }
}

private actor TestExplorationStore: RecordingStorePort {
    private var pending: (CaptureCommandToken, UInt64, CheckedContinuation<RecordingStoreResult, Never>)?
    private var waiter: CheckedContinuation<Void, Never>?

    init() {}

    func execute(_ command: RecordingStoreCommand) async -> RecordingStoreResult {
        switch command {
        case .commitIntent(let token, let revision, _):
            return await withCheckedContinuation { continuation in
                pending = (token, revision, continuation)
                waiter?.resume()
                waiter = nil
            }
        case .commitResult(let token, _, _): return .unavailable(token, .notMeasured)
        }
    }
    func waitForIntent() async {
        if pending != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func releaseIntent() {
        guard let (token, revision, continuation) = pending else { return }
        pending = nil
        continuation.resume(returning: .committed(.init(token: token, previousRevision: revision, committedRevision: revision + 1)))
    }
    func loadUnfinished() -> UnfinishedRecordingLoadResult { .loaded([]) }
}

private actor TestExplorationInspection: CaptureOriginalInspectionPort {
    init() {}
    func inspect(_ request: CaptureInspectionRequest) -> CaptureInspectionResult { .unavailable(request.token, .notMeasured) }
}

private actor TestExplorationDiagnostics: ExplorationDiagnosticsPort {
    let fails: Bool
    private(set) var attempts: [ExplorationDeviceEvent] = []
    private var records: [ExplorationDiagnosticRecord] = []
    private var waiter: (Int, CheckedContinuation<Void, Never>)?

    init(fails: Bool) { self.fails = fails }

    func append(_ event: ExplorationDeviceEvent) throws -> ExplorationDiagnosticRecord {
        attempts.append(event)
        defer {
            if let (count, continuation) = waiter, attempts.count >= count {
                waiter = nil
                continuation.resume()
            }
        }
        if fails { throw ExplorationIssue.storageUnavailable }
        let record = ExplorationDiagnosticRecord(sequence: UInt64(records.count + 1), event: event)
        records.append(record)
        return record
    }

    func load() -> [ExplorationDiagnosticRecord] { records }

    func waitForAttemptCount(_ count: Int) async {
        if attempts.count >= count { return }
        await withCheckedContinuation { waiter = (count, $0) }
    }
}
