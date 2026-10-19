import Foundation
import Observation

/// A session-lived owner. No I/O starts in init, View.body, or ticket decoding.
@MainActor @Observable
final class ExplorationCoordinator {
    private(set) var ticket: ExplorationTicket?
    private(set) var outputCandidate: ExplorationOutputCandidate?
    private(set) var storeCandidate: ExplorationStoreCandidate?
    private(set) var issues: [ExplorationIssue] = [.ticketMissing]
    private(set) var runtime: ExplorationRuntime?
    private(set) var cameras: [ExplorationCameraDescription] = []
    private(set) var prepared: ExplorationPrepared?
    private(set) var capture: CaptureLifecycle?
    private(set) var save: RecordingSaveLifecycle?
    private(set) var observations: [ExplorationObservation] = []
    private(set) var isPreparing = false
    private(set) var isImporting = false
    private(set) var isStarting = false
    private(set) var saveIssue: String?
    private(set) var diagnosticsReady = false
    private(set) var diagnosticsSequence: UInt64?
    private(set) var diagnosticsIssue: String?

    @ObservationIgnored private let factory: any ExplorationFactoryPort
    @ObservationIgnored private let ticketLoader: @Sendable (URL) async throws -> Data
    @ObservationIgnored private var services: ExplorationServices?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var pendingEnd: (CaptureContext, RecordingEndEvidence)?
    @ObservationIgnored private var pendingDiagnostics: [ExplorationDeviceEvent] = []
    @ObservationIgnored private var eventHandlingDepth = 0
    @ObservationIgnored private var isDrainingDiagnostics = false

    init(factory: any ExplorationFactoryPort,
         ticketLoader: @escaping @Sendable (URL) async throws -> Data = { _ in throw ExplorationIssue.ticketReadFailed }) {
        self.factory = factory
        self.ticketLoader = ticketLoader
    }

    var canChangeInputs: Bool { !isBusy && services == nil }

    func selectOutput(_ value: ExplorationOutputCandidate?) {
        guard canChangeInputs else { issues = [.operationInProgress]; return }
        outputCandidate = value
    }

    func selectStore(_ value: ExplorationStoreCandidate?) {
        guard canChangeInputs else { issues = [.operationInProgress]; return }
        storeCandidate = value
    }

    var isBusy: Bool {
        if isPreparing || isStarting || isImporting { return true }
        if let capture, capture.phase == .starting || capture.phase == .recording || capture.phase == .stopping { return true }
        if let save {
            if case .committed = save.phase {} else { return true }
        }
        return false
    }

    func bindTicket(data: Data) {
        guard !isBusy, services == nil else { issues = [.operationInProgress]; return }
        ticket = nil
        outputCandidate = nil
        storeCandidate = nil
        do {
            let value = try JSONDecoder().decode(ExplorationTicket.self, from: data)
            guard value.validationIssues.isEmpty else { issues = value.validationIssues; return }
            ticket = value
            issues = []
        } catch { issues = [.ticketReadFailed] }
    }

    func importTicket(from selection: URL) async {
        guard canChangeInputs else { issues = [.operationInProgress]; return }
        ticket = nil
        outputCandidate = nil
        storeCandidate = nil
        isImporting = true
        do {
            let bytes = try await ticketLoader(selection)
            isImporting = false
            bindTicket(data: bytes)
        } catch {
            isImporting = false
            issues = [.ticketReadFailed]
        }
    }

    func preparationIssues() async -> [ExplorationIssue] {
        do {
            let value = try await factory.runtime()
            runtime = value
            return ExplorationGate.issues(ticket: ticket, output: outputCandidate, store: storeCandidate, runtime: value)
        } catch { return [.deviceFactsMissing] }
    }

    func prepare() async {
        guard !isBusy, services == nil else { issues = [.operationInProgress]; return }
        isPreparing = true
        defer { isPreparing = false }
        issues = await preparationIssues()
        guard issues.isEmpty, let ticket, let outputCandidate, let storeCandidate else { return }
        do {
            let created = try await factory.makeServices(ticket: ticket, output: outputCandidate, store: storeCandidate)
            services = created
            diagnosticsReady = true
            let stream = await created.device.explorationEvents()
            eventTask = Task { [weak self] in
                for await event in stream {
                    guard !Task.isCancelled else { return }
                    await self?.receive(event)
                }
            }
            cameras = try await created.device.discover()
            let result = try await created.device.prepare(.init(ticket: ticket, generation: created.generation,
                                                                 operation: .init(rawValue: "prepare-\(created.generation.session.rawValue)")))
            prepared = result
            guard result.applied.values.value?.matches(ticket.desired) == true else {
                throw ExplorationIssue.appliedValuesDiffer
            }
        } catch let issue as ExplorationIssue {
            issues = [issue]
            await abandonPreparation()
        } catch {
            issues = [.adapterFailure("prepare_failed")]
            await abandonPreparation()
        }
    }

    private func abandonPreparation() async {
        if let services { await services.device.shutDown() }
        services = nil
        eventTask?.cancel()
        eventTask = nil
        // Readback is retained when it differed, for honest desired/applied display.
    }

    func record() async {
        // Evidence loss remains a run-level fact even if runtime gates later pass.
        guard diagnosticsIssue == nil else { return }
        guard !isBusy, let services, let prepared, let ticket else { issues = [.operationInProgress]; return }
        if let capture, capture.whiteBalance != .automatic { issues = [.operationInProgress]; return }
        isStarting = true
        defer { isStarting = false }
        issues = await preparationIssues()
        guard issues.isEmpty else { return }
        let (context, operation, original) = await factory.nextCaptureIdentity(generation: services.generation)
        let time = await factory.currentTime()
        let intent = RecordingIntent(context: context, operation: operation, original: original,
                                     trialReference: "\(ticket.caseID)-\(ticket.repetitionID)-\(ticket.conditionVersion)",
                                     desired: ticket.desired, applied: prepared.applied, acceptedAt: time)
        var lifecycle = CaptureLifecycle(context: context, audio: prepared.audio)
        let readiness = CaptureReadiness(generation: services.generation, desired: ticket.desired,
                                         capabilities: prepared.capabilities, applied: prepared.applied,
                                         camera: .ready, audioInput: prepared.audio.input,
                                         destination: .ready, recordingResources: .ready)
        let transition = lifecycle.begin(intent, readiness: readiness, expectedStoreRevision: 0)
        capture = lifecycle
        save = nil
        pendingEnd = nil
        saveIssue = nil
        await perform(transition)
    }

    func stop() async {
        guard var lifecycle = capture else { return }
        let transition = lifecycle.stop(operation: .init(rawValue: "stop-\(lifecycle.context.capture.rawValue)"))
        capture = lifecycle
        await perform(transition)
    }

    func refreshWhiteBalance() {
        // P06 does not bind a measurement interval; no false refresh success is shown.
        issues = [.capabilityUnconfirmed("WB合わせ直しの測定区間はP10で束縛")]
    }

    private func perform(_ transition: CaptureTransition) async {
        guard let services else { return }
        switch transition {
        case .rejected(let error):
            appendObservation(code: "transition_rejected", detail: String(describing: error))
        case .cannotRecord(let blockers):
            issues = [.capabilityUnconfirmed(String(describing: blockers))]
        case .accepted(let effects):
            // Reserve the save owner before any await can deliver WB failure/STOP/end.
            for effect in effects {
                if case .store(.commitIntent(let token, let revision, let intent)) = effect {
                    do { save = try RecordingSaveLifecycle(intent: intent, intentToken: token, revision: revision) }
                    catch { saveIssue = "保存意図の契約不一致"; return }
                }
            }
            // Submit current-WB acquisition before awaiting any persistent-store operation.
            for effect in effects {
                if case .capture(let command) = effect {
                    let result = await services.device.submit(command)
                    if case .rejected(let token, let reason) = result {
                        await receive(.capture(.commandFailed(token, reason)))
                    }
                }
            }
            for effect in effects {
                switch effect {
                case .capture: break
                case .store(let command):
                    let result = await services.store.execute(command)
                    if case .committed(let receipt) = result {
                        do {
                            try save?.acceptIntentCommit(receipt)
                            applyPendingEnd()
                        }
                        catch { saveIssue = "保存意図commitの照合が必要です" }
                    } else { saveIssue = "保存意図commitを確認できません。再読込による照合が必要です。" }
                    if var lifecycle = capture {
                        let next = lifecycle.receiveIntentStoreResult(result)
                        capture = lifecycle
                        await perform(next)
                    }
                case .recordingCeased(let evidence):
                    if let context = capture?.context {
                        pendingEnd = (context, evidence)
                        applyPendingEnd()
                    }
                }
            }
        }
    }

    private func applyPendingEnd() {
        guard let (context, evidence) = pendingEnd, save?.phase == .recording else { return }
        do {
            try save?.acceptRecordingEnd(context: context, evidence: evidence)
            pendingEnd = nil
            if evidence.writer == .notStarted {
                saveIssue = "録画開始前に停止しました。媒体検査・結果commitは未実施で、保存意図の手動照合待ちです。"
            }
        } catch { saveIssue = "記録終端と保存意図の照合が必要です" }
    }

    private func receive(_ event: ExplorationDeviceEvent) async {
        guard let diagnostics = services?.diagnostics else { return }
        pendingDiagnostics.append(event)
        eventHandlingDepth += 1
        await applyEvent(event)
        eventHandlingDepth -= 1
        // WB -> start effects run before diagnostic disk I/O. Nested synchronous
        // command refusals retain their receive order in this low-frequency queue.
        if eventHandlingDepth == 0 { await persistDiagnostics(using: diagnostics) }
    }

    private func persistDiagnostics(using diagnostics: any ExplorationDiagnosticsPort) async {
        guard !isDrainingDiagnostics else { return }
        isDrainingDiagnostics = true
        defer { isDrainingDiagnostics = false }
        while !pendingDiagnostics.isEmpty {
            let event = pendingDiagnostics.removeFirst()
            do {
                let record = try await diagnostics.append(event)
                diagnosticsSequence = record.sequence
            } catch {
                let firstFailure = diagnosticsIssue == nil
                diagnosticsIssue = "観測記録の永続化に失敗しました。このrunの新規RECは停止し、原本と保存結果を保持して照合します。"
                if firstFailure, capture?.phase == .starting || capture?.phase == .recording {
                    await stop()
                }
                // File/end/result handling continues independently of diagnostic loss.
            }
        }
    }

    private func applyEvent(_ event: ExplorationDeviceEvent) async {
        switch event {
        case .capture(let event):
            guard var lifecycle = capture else { return }
            let transition = lifecycle.receive(event)
            capture = lifecycle
            appendObservation(code: "capture_event", detail: eventName(event))
            await perform(transition)
        case .fileFinalized(let evidence):
            guard let services, var save, let capture, evidence.context == capture.context else { return }
            do {
                try save.acceptFile(evidence)
                self.save = save
                let token = CaptureCommandToken(context: evidence.context, operation: save.intent.operation,
                                                ordinal: save.intentToken.ordinal + 1)
                let inspection = await services.inspection.inspect(.init(token: token, original: evidence.original))
                guard case .inspected(let responseToken, let value) = inspection, responseToken == token else {
                    saveIssue = "媒体検査を確認できません。正常保存とは表示しません。"
                    return
                }
                guard var latest = self.save, latest.intent.context == evidence.context else { return }
                let command = try latest.acceptInspection(value, resultToken: token)
                self.save = latest
                let result = await services.store.execute(command)
                guard case .committed(let receipt) = result else {
                    saveIssue = "結果commitは未確認です。原本を保持して照合します。"
                    return
                }
                try self.save?.acceptResultCommit(receipt)
            } catch { saveIssue = "ファイル・検査・保存記録の順序または対象の照合が必要です" }
        case .observation(let observation):
            observations.append(observation)
            if observations.count > 100 { observations.removeFirst(observations.count - 100) }
        }
    }

    private func appendObservation(code: String, detail: String) {
        observations.append(.init(code: code, context: capture?.context,
                                  time: .unavailable(.notMeasured), detail: detail))
        if observations.count > 100 { observations.removeFirst(observations.count - 100) }
    }

    private func eventName(_ event: CaptureIOEvent) -> String {
        switch event {
        case .whiteBalanceLocked: return "WB固定適用の通知"
        case .automaticWhiteBalanceRestored: return "待機Autoの通知"
        case .recordingStarted: return "記録開始通知（先頭映像・音声とは別）"
        case .recordingEnded: return "記録終端通知（保存commitとは別）"
        case .commandFailed: return "操作失敗"
        case .audioObserved: return "音声入力・到着・書込の観測"
        }
    }
}
