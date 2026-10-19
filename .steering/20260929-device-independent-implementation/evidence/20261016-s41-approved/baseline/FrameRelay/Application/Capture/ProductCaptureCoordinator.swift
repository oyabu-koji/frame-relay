import Foundation
import Observation

/// Composition-lived owner. View disappearance never cancels an in-flight intent or save.
@MainActor @Observable
final class ProductCaptureCoordinator {
    private(set) var preferences = ProductCapturePreferences()
    private(set) var cameras: [ExplorationCameraDescription] = []
    private(set) var prepared: ExplorationPrepared?
    private(set) var capture: CaptureLifecycle?
    private(set) var previewSource: (any ProductCapturePreviewSource)?
    private(set) var saveResult: RecordingSaveResult?
    private(set) var issue: String?
    private(set) var isPreparing = false
    private(set) var isStarting = false
    private(set) var isSaving = false
    private(set) var preferencesLoaded = false

    @ObservationIgnored private let preferenceStore: any ProductCapturePreferencePort
    @ObservationIgnored private let makeDevice: @Sendable (ExplorationOutputCandidate) async throws -> any ProductCaptureDevicePort
    @ObservationIgnored private let save: any ProductCaptureSavePort
    @ObservationIgnored private let bindOriginal: @Sendable (CaptureOriginalReference) async -> Bool
    @ObservationIgnored private let didSave: @MainActor @Sendable () async -> Void
    @ObservationIgnored private let calendarNow: (@Sendable () -> Date)?
    @ObservationIgnored private let captureNow: @Sendable () -> CaptureTimeObservation
    @ObservationIgnored private var device: (any ProductCaptureDevicePort)?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var generation: CaptureGeneration?
    @ObservationIgnored private var activeIntent: RecordingIntent?
    @ObservationIgnored private var pendingEnd: RecordingEndEvidence?
    @ObservationIgnored private var pendingFile: CaptureFileEvidence?
    @ObservationIgnored private var intentReady = false
    @ObservationIgnored private var endDelivered = false
    @ObservationIgnored private var saveFinished = false
    @ObservationIgnored private var drainingSave = false
    @ObservationIgnored private var leaveRequested = false
    @ObservationIgnored private var eventEpoch = UUID()

    init(preferences: any ProductCapturePreferencePort,
         makeDevice: @escaping @Sendable (ExplorationOutputCandidate) async throws -> any ProductCaptureDevicePort,
         save: any ProductCaptureSavePort,
         bindOriginal: @escaping @Sendable (CaptureOriginalReference) async -> Bool,
         didSave: @escaping @MainActor @Sendable () async -> Void,
         calendarNow: (@Sendable () -> Date)? = nil,
         captureNow: @escaping @Sendable () -> CaptureTimeObservation = { .unavailable(.notMeasured) }) {
        preferenceStore = preferences; self.makeDevice = makeDevice; self.save = save
        self.bindOriginal = bindOriginal; self.didSave = didSave
        self.calendarNow = calendarNow; self.captureNow = captureNow
    }

    var isBusy: Bool {
        isPreparing || isStarting || isSaving || capture.map {
            $0.phase == .starting || $0.phase == .recording || $0.phase == .stopping
        } == true
    }

    var canRecord: Bool {
        guard !isBusy, !leaveRequested, issue == nil, calendarNow != nil, let generation, let prepared,
              preferences.desired != nil, preferences.outputCandidate != nil,
              capture == nil || capture?.whiteBalance == .automatic else { return false }
        return readiness(generation: generation, prepared: prepared).blockers.isEmpty
    }

    func load() async {
        guard !isBusy, !preferencesLoaded else { return }
        do {
            preferences = try await preferenceStore.load()
            preferencesLoaded = true
        } catch { issue = "撮影設定を読み込めません。保存済み設定を保持しています。" }
    }

    func discover() async {
        guard !isBusy else { return }
        isPreparing = true
        defer { isPreparing = false }
        do {
            // This temporary output choice only enumerates hardware, never sets recording preferences.
            let discovery = try await makeDevice(preferences.outputCandidate ?? .movieFile)
            cameras = try await discovery.discoverCameras()
            await discovery.shutDown()
        } catch { issue = message(for: error) }
    }

    func updatePreferences(_ value: ProductCapturePreferences) async {
        guard !isBusy else { return }
        guard value.isValid else { issue = "撮影設定の値を確認してください。"; return }
        // A corrupt/unknown settings file is not silently replaced by an ordinary edit.
        guard preferencesLoaded else { issue = "保存済み設定を読み込めていないため変更できません。"; return }
        isPreparing = true
        defer { isPreparing = false }
        await releaseDevice()
        do {
            try await preferenceStore.save(value)
            preferences = value
            issue = nil
        } catch { issue = "撮影設定を保存できませんでした。" }
    }

    func prepare() async {
        guard !isBusy else { return }
        guard preferencesLoaded, let desired = preferences.desired, let candidate = preferences.outputCandidate else {
            issue = "撮影設定と記録方式を選択してください。"; return
        }
        isPreparing = true
        leaveRequested = false
        issue = nil
        defer { isPreparing = false }
        await releaseDevice()
        let nextGeneration = CaptureGeneration(session: .init(rawValue: UUID().uuidString), settings: 1)
        do {
            let created = try await makeDevice(candidate)
            device = created
            let epoch = UUID()
            eventEpoch = epoch
            let stream = await created.productEvents()
            eventTask = Task { [weak self] in
                for await event in stream {
                    guard !Task.isCancelled else { return }
                    await self?.receive(event, epoch: epoch)
                }
            }
            cameras = try await created.discoverCameras()
            guard ProductCaptureConfigurationMatcher.hasCurrentFormat(for: desired.configuration, cameras: cameras) else {
                throw ExplorationIssue.capabilityUnconfirmed("camera_or_format_no_longer_available")
            }
            let result = try await created.prepare(.init(desired: desired, generation: nextGeneration,
                operation: .init(rawValue: "prepare-\(UUID().uuidString)")))
            generation = nextGeneration
            prepared = result
            previewSource = await created.previewSource()
            if !readiness(generation: nextGeneration, prepared: result).blockers.isEmpty {
                issue = "希望設定を適用できません。現在の対応条件と実適用値を確認してください。"
            }
            if leaveRequested { await releaseDevice() }
        } catch {
            issue = message(for: error)
            await releaseDevice()
        }
    }

    func record() async {
        guard canRecord, let generation, let prepared, let desired = preferences.desired, let calendarNow else { return }
        isStarting = true
        let context = CaptureContext(generation: generation, capture: .init(rawValue: UUID().uuidString))
        let operation = CaptureOperationID(rawValue: UUID().uuidString)
        // Calendar observation is independent of the monotonic capture timeline.
        // Millisecond precision is shared by store and QuickTime creation-date metadata.
        let observed = calendarNow()
        let capturedAt = Date(timeIntervalSince1970: floor(observed.timeIntervalSince1970 * 1_000) / 1_000)
        let intent = RecordingIntent(context: context, operation: operation,
            original: .init(rawValue: UUID().uuidString), desired: desired, applied: prepared.applied,
            acceptedAt: captureNow(), capturedAt: capturedAt)
        var lifecycle = CaptureLifecycle(context: context, audio: capture?.audio ?? prepared.audio)
        let transition = lifecycle.begin(intent, readiness: readiness(generation: generation, prepared: prepared), expectedStoreRevision: 0)
        capture = lifecycle
        activeIntent = intent
        pendingEnd = nil; pendingFile = nil; intentReady = false
        endDelivered = false; saveFinished = false; saveResult = nil
        await perform(transition)
        isStarting = false
        await finishLeavingIfPossible()
    }

    func stop() async {
        guard var lifecycle = capture else { return }
        let transition = lifecycle.stop(operation: .init(rawValue: UUID().uuidString))
        capture = lifecycle
        await perform(transition)
    }

    /// Safe on navigation/background. Capture events and persistence continue until settled.
    func leaveCapture() async {
        leaveRequested = true
        await stop()
        await finishLeavingIfPossible()
    }

    private func readiness(generation: CaptureGeneration, prepared: ExplorationPrepared) -> CaptureReadiness {
        .init(generation: generation, desired: preferences.desired, capabilities: prepared.capabilities,
              applied: prepared.applied, camera: .ready, audioInput: capture?.audio.input ?? prepared.audio.input,
              destination: .ready, recordingResources: .ready)
    }

    private func perform(_ transition: CaptureTransition) async {
        guard let device else { return }
        guard case .accepted(let effects) = transition else { return }
        // WB may complete or STOP may arrive while common-save begin is suspended.
        for effect in effects {
            if case .store(.commitIntent) = effect { isSaving = true }
        }
        for effect in effects {
            if case .capture(let command) = effect {
                if case .rejected(let token, let reason) = await device.submit(command) {
                    await receive(.capture(.commandFailed(token, reason)), epoch: eventEpoch)
                }
            }
        }
        for effect in effects {
            switch effect {
            case .capture: break
            case .store(.commitIntent(let token, _, let intent)):
                let result = await save.begin(intent, token: token)
                let storeResult: RecordingStoreResult
                switch result {
                case .ready(let receipt): intentReady = true; storeResult = .committed(receipt)
                case .rejected(let error):
                    storeResult = .rejected(token, error)
                    issue = "保存意図を確定できません。録画は開始しませんでした。"
                    saveFinished = true
                default:
                    storeResult = .unavailable(token, .resourceUnavailable)
                    issue = "保存意図の結果が不明です。一覧から記録を確認してください。"
                    saveFinished = true
                }
                if var lifecycle = capture, lifecycle.context == token.context {
                    let next = lifecycle.receiveIntentStoreResult(storeResult)
                    capture = lifecycle
                    await perform(next)
                    await drainSave()
                    if !intentReady {
                        await didSave()
                        isSaving = false
                    }
                }
            case .store(.commitResult): break // Result writes belong exclusively to OriginalSaveCoordinator.
            case .recordingCeased(let end):
                pendingEnd = end
                await drainSave()
            }
        }
    }

    private func receive(_ event: ExplorationDeviceEvent, epoch: UUID) async {
        guard epoch == eventEpoch else { return }
        switch event {
        case .capture(let event):
            guard var lifecycle = capture else { return }
            let transition = lifecycle.receive(event)
            capture = lifecycle
            await perform(transition)
        case .fileFinalized(let file):
            guard let intent = activeIntent, file.context == intent.context, file.original == intent.original,
                  !saveFinished, pendingFile == nil else { return }
            pendingFile = file
            await drainSave()
        case .observation(let observation):
            if observation.code == "file_finalization_unconfirmed", observation.context == activeIntent?.context {
                issue = "録画は停止しましたがファイルの確定を確認できません。一覧で照合してください。"
                saveFinished = true
                await didSave()
                isSaving = false
            }
        }
        await finishLeavingIfPossible()
    }

    private func drainSave() async {
        guard !drainingSave, intentReady, !saveFinished, let intent = activeIntent, let end = pendingEnd else { return }
        drainingSave = true
        defer { drainingSave = false }
        if !endDelivered {
            guard case .accepted = await save.recordingEnded(context: intent.context, evidence: end) else {
                issue = "記録終端の保存照合が必要です。"; saveFinished = true
                await didSave(); isSaving = false; return
            }
            endDelivered = true
        }
        if end.writer == .notStarted {
            issue = "録画開始前に停止しました。保存意図は一覧で要確認として残ります。"
            saveFinished = true
            await didSave(); isSaving = false; return
        }
        guard let file = pendingFile else { return }
        let token = CaptureCommandToken(context: intent.context, operation: intent.operation, ordinal: 100)
        let result = await save.fileFinalized(file, resultToken: token)
        saveFinished = true
        switch result {
        case .committed(let record, _):
            saveResult = record.result
            if !(await bindOriginal(intent.original)) {
                issue = "保存結果を記録しました。原本と一覧の対応は確認が必要です。"
            }
        default: issue = "保存結果を確定できません。一覧で原本と保存記録を確認してください。"
        }
        await didSave()
        isSaving = false
    }

    private func finishLeavingIfPossible() async {
        guard leaveRequested, !isPreparing, !isStarting, !isSaving,
              capture == nil || capture?.phase == .ended || capture?.phase == .ready else { return }
        await releaseDevice()
    }

    private func releaseDevice() async {
        eventEpoch = UUID()
        if let device { await device.shutDown() }
        device = nil; previewSource = nil; prepared = nil; generation = nil; capture = nil
        eventTask?.cancel(); eventTask = nil
    }

    private func message(for error: Error) -> String {
        switch error as? ExplorationIssue {
        case .simulatorHasNoVerifiedCamera: return "Simulatorではカメラ撮影を利用できません。一覧と再生は利用できます。"
        case .permissionDenied: return "カメラとマイクの使用許可を設定で確認してください。"
        case .appliedValuesDiffer: return "希望設定と実際の適用値が一致しません。RECは開始できません。"
        case .capabilityUnconfirmed: return "現在のカメラでは選択した条件を確認できません。設定を変更してください。"
        default: return "カメラを準備できませんでした。条件を確認して再準備してください。"
        }
    }
}
