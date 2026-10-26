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
    private(set) var captureVisit: UUID?
    private(set) var ndSnapshot: CaptureNDSnapshot?
    private(set) var ndAdvice = CaptureNDAdvice.pending(.policyUnavailable)
    private(set) var subjects: CaptureSubjectSnapshot?
    private(set) var isUpdatingSubjects = false
    private(set) var subjectIssue: String?
    private(set) var isSavingShootingIntent = false
    private(set) var framing = CaptureFramingState()
    private(set) var observedAudio: CaptureAudioState?
    private(set) var audioRecovery: ProductCaptureAudioRecoveryStatus = .idle
    private(set) var isRecoveringAudio = false
    private(set) var zoom = CaptureZoomState()
    private(set) var zoomIssue: String?
    private(set) var isUpdatingZoom = false
    private(set) var sessionDesired: DesiredCaptureSettings?

    @ObservationIgnored private let preferenceStore: any ProductCapturePreferencePort
    @ObservationIgnored private let makeDevice: @Sendable (ExplorationOutputCandidate) async throws -> any ProductCaptureDevicePort
    @ObservationIgnored private let save: any ProductCaptureSavePort
    @ObservationIgnored private let postSave: ProductCapturePostSave
    @ObservationIgnored private let calendarNow: (@Sendable () -> Date)?
    @ObservationIgnored private let captureNow: @Sendable () -> CaptureTimeObservation
    @ObservationIgnored private var device: (any ProductCaptureDevicePort)?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var hasStabilizationObservation = false
    @ObservationIgnored private var stabilizationTask: Task<Void, Never>?
    @ObservationIgnored private let ndPolicy: CaptureNDPolicy?
    @ObservationIgnored private var ndTask: Task<Void, Never>?
    @ObservationIgnored private var ndExpiryTask: Task<Void, Never>?
    @ObservationIgnored private var ndSequence: UInt64?
    @ObservationIgnored private var ndContext: CaptureNDContext?
    @ObservationIgnored private var subjectTask: Task<Void, Never>?
    @ObservationIgnored private var subjectSequence: UInt64?
    @ObservationIgnored private let subjectPolicy: CaptureSubjectPolicy?
    @ObservationIgnored private var audioTask: Task<Void, Never>?
    @ObservationIgnored private var audioSequence: UInt64?
    @ObservationIgnored private let audioPolicy: ProductCaptureAudioPolicy?
    @ObservationIgnored private var recoveryRequest: ProductCaptureAudioRecoveryRequest?
    @ObservationIgnored private var recoveryTimeout: Task<Void, Never>?
    @ObservationIgnored private var recoveryTimedOut = false
    @ObservationIgnored private var generation: CaptureGeneration?
    @ObservationIgnored private var activeIntent: RecordingIntent?
    @ObservationIgnored private var pendingEnd: RecordingEndEvidence?
    @ObservationIgnored private var pendingFile: CaptureFileEvidence?
    @ObservationIgnored private var fileFinalizationUnconfirmed = false
    @ObservationIgnored private var intentReady = false
    @ObservationIgnored private var endDelivered = false
    @ObservationIgnored private var saveFinished = false
    @ObservationIgnored private var drainingSave = false
    @ObservationIgnored private var leaveRequested = false
    @ObservationIgnored private var eventEpoch = UUID()
    @ObservationIgnored private var preparationOwner: UUID?
    @ObservationIgnored private let zoomPolicy: CaptureZoomPolicy?
    @ObservationIgnored private var zoomTask: Task<Void, Never>?
    @ObservationIgnored private var zoomOperation: UUID?
    @ObservationIgnored private var pendingZoomMove = false
    @ObservationIgnored private var hasZoomObservation = false
    @ObservationIgnored private var zoomCommandSequence: UInt64 = 0

    init(preferences: any ProductCapturePreferencePort,
         makeDevice: @escaping @Sendable (ExplorationOutputCandidate) async throws -> any ProductCaptureDevicePort,
         save: any ProductCaptureSavePort,
         bindOriginal: @escaping @Sendable (CaptureOriginalReference) async -> Bool,
         didSave: @escaping @MainActor @Sendable () async -> Void,
         audioPolicy: ProductCaptureAudioPolicy? = nil,
         subjectPolicy: CaptureSubjectPolicy? = nil,
         ndPolicy: CaptureNDPolicy? = nil,
         zoomPolicy: CaptureZoomPolicy? = nil,
         calendarNow: (@Sendable () -> Date)? = nil,
         captureNow: @escaping @Sendable () -> CaptureTimeObservation = { .unavailable(.notMeasured) }) {
        preferenceStore = preferences; self.makeDevice = makeDevice; self.save = save
        postSave = ProductCapturePostSave(bindOriginal: bindOriginal, didSave: didSave)
        self.calendarNow = calendarNow; self.captureNow = captureNow
        self.audioPolicy = audioPolicy
        self.subjectPolicy = subjectPolicy
        self.ndPolicy = ndPolicy?.isValid == true ? ndPolicy : nil
        self.zoomPolicy = zoomPolicy?.isValid == true ? zoomPolicy : nil
        ndAdvice = .pending(self.ndPolicy == nil ? .policyUnavailable : .evaluating)
    }

    var isBusy: Bool {
        isPreparing || isStarting || isSaving || isRecoveringAudio || capture.map {
            $0.phase == .starting || $0.phase == .recording || $0.phase == .stopping
        } == true
    }

    var canRecord: Bool {
        guard !isBusy, !isUpdatingZoom, zoom.snapshot?.phase.isMoving != true,
              !hasZoomObservation || zoom.snapshot != nil,
              !leaveRequested, captureVisit != nil, preferencesLoaded, issue == nil, calendarNow != nil, let generation, let prepared,
              preferences.desired != nil, preferences.outputCandidate != nil,
              currentAudio?.confirmedFailure == nil, currentStabilizationAllowsRecording,
              capture == nil || capture?.whiteBalance == .automatic else { return false }
        return readiness(generation: generation, prepared: prepared).blockers.isEmpty
    }

    var canRefreshWhiteBalance: Bool {
        guard !leaveRequested, captureVisit != nil, capture?.phase == .recording,
              case .locked = capture?.whiteBalance,
              prepared?.capabilities.whiteBalanceRefresh == .supported(true) else { return false }
        return true
    }

    /// Only a visible screen's explicit entry may undo a prior leave request.
    @discardableResult
    func enterCapture() -> UUID {
        let visit = UUID()
        captureVisit = visit
        leaveRequested = false
        preparationOwner = nil
        isPreparing = false
        return visit
    }

    func load(visit requestedVisit: UUID? = nil) async {
        let visit = requestedVisit ?? captureVisit
        guard accepts(visit), !isBusy, !preferencesLoaded else { return }
        let owner = beginPreparation()
        defer { endPreparation(owner) }
        do {
            let loaded = try await preferenceStore.load()
            guard accepts(visit) else { return }
            if loaded != preferences {
                // A previous visit's late settings commit can change the output candidate.
                // This visit's reload must retire its old preparation before publishing it.
                await releaseDevice()
                guard accepts(visit) else { return }
            }
            preferences = loaded
            preferencesLoaded = true
        } catch {
            if accepts(visit) { issue = "撮影設定を読み込めません。保存済み設定を保持しています。" }
        }
    }

    func discover(visit requestedVisit: UUID? = nil) async {
        let visit = requestedVisit ?? captureVisit
        guard accepts(visit), !isBusy else { return }
        let owner = beginPreparation()
        defer { endPreparation(owner) }
        do {
            // This temporary output choice only enumerates hardware, never sets recording preferences.
            let discovery = try await makeDevice(preferences.outputCandidate ?? .movieFile)
            guard accepts(visit) else { await discovery.shutDown(); return }
            do {
                let discovered = try await discovery.discoverCameras()
                await discovery.shutDown()
                guard accepts(visit) else { return }
                cameras = discovered
            } catch {
                await discovery.shutDown()
                throw error
            }
        } catch { if accepts(visit) { issue = message(for: error) } }
    }

    func updatePreferences(_ value: ProductCapturePreferences, visit requestedVisit: UUID? = nil) async {
        let visit = requestedVisit ?? captureVisit
        guard accepts(visit), !isBusy, !isSavingShootingIntent else { return }
        guard value.isValid else { issue = "撮影設定の値を確認してください。"; return }
        // A corrupt/unknown settings file is not silently replaced by an ordinary edit.
        guard preferencesLoaded else { issue = "保存済み設定を読み込めていないため変更できません。"; return }
        let owner = beginPreparation()
        defer { endPreparation(owner) }
        await releaseDevice()
        guard accepts(visit) else { return }
        // A save may commit after its screen has left. The next visit must reload that
        // durable value instead of treating its earlier cached wishes as current.
        preferencesLoaded = false
        do {
            try await preferenceStore.save(value)
            guard accepts(visit) else { preferencesLoaded = false; return }
            preferences = value
            preferencesLoaded = true
            issue = nil
        } catch {
            preferencesLoaded = false
            if accepts(visit) { issue = "撮影設定を保存できませんでした。" }
        }
    }

    func prepare(visit requestedVisit: UUID? = nil) async {
        let visit = requestedVisit ?? captureVisit
        guard accepts(visit), !isBusy else { return }
        guard preferencesLoaded, let desired = preferences.desired, let candidate = preferences.outputCandidate else {
            issue = "撮影設定と記録方式を選択してください。"; return
        }
        let owner = beginPreparation()
        issue = nil
        defer { endPreparation(owner) }
        await releaseDevice()
        guard accepts(visit) else { return }
        let nextGeneration = CaptureGeneration(session: .init(rawValue: UUID().uuidString), settings: 1)
        do {
            let created = try await makeDevice(candidate)
            // Until every preparation await has finished, this invocation owns only this device.
            // An obsolete invocation must never release a newer visit's published device.
            do {
                guard accepts(visit) else { await created.shutDown(); return }
                let stream = await created.productEvents()
                let audioStream = await created.audioSnapshots()
                let stabilizationStream = await created.stabilizationSnapshots()
                let subjectStream = await created.subjectSnapshots()
                let ndStream = await created.ndSnapshots()
                let zoomStream = await created.zoomSnapshots()
                guard accepts(visit) else { await created.shutDown(); return }
                let discovered = try await created.discoverCameras()
                guard accepts(visit) else { await created.shutDown(); return }
                guard ProductCaptureConfigurationMatcher.hasCurrentFormat(for: desired.configuration, cameras: discovered) else {
                    throw ExplorationIssue.capabilityUnconfirmed("camera_or_format_no_longer_available")
                }
                let result = try await created.prepare(.init(desired: desired, generation: nextGeneration,
                    operation: .init(rawValue: "prepare-\(UUID().uuidString)")))
                guard accepts(visit) else { await created.shutDown(); return }
                await created.updateNDIntent(preferences.shootingIntent, generation: nextGeneration)
                let preview = await created.previewSource()
                guard accepts(visit) else { await created.shutDown(); return }
                device = created
                generation = nextGeneration
                cameras = discovered
                prepared = result
                if let snapshot = result.stabilization {
                    hasStabilizationObservation = framing.receive(snapshot, generation: nextGeneration,
                        desired: desired, output: candidate)
                }
                observedAudio = result.audio
                audioSequence = nil
                audioRecovery = .idle
                previewSource = preview
                let epoch = UUID()
                eventEpoch = epoch
                zoomTask = Task { [weak self] in
                    for await snapshot in zoomStream {
                        guard !Task.isCancelled else { return }
                        self?.receiveZoom(snapshot, epoch: epoch)
                    }
                    guard !Task.isCancelled, self?.eventEpoch == epoch else { return }
                    self?.zoom.invalidate()
                }
                eventTask = Task { [weak self] in
                    for await event in stream {
                        guard !Task.isCancelled else { return }
                        await self?.receive(event, epoch: epoch)
                    }
                }
                audioTask = Task { [weak self] in
                    for await snapshot in audioStream {
                        guard !Task.isCancelled else { return }
                        await self?.receiveAudio(snapshot, epoch: epoch)
                    }
                }
                ndTask = Task { [weak self] in
                    for await snapshot in ndStream {
                        guard !Task.isCancelled else { return }
                        self?.receiveND(snapshot, epoch: epoch)
                    }
                    guard !Task.isCancelled else { return }
                    if self?.eventEpoch == epoch { self?.invalidateND(.stopped) }
                }
                subjectTask = Task { [weak self] in
                    for await snapshot in subjectStream {
                        guard !Task.isCancelled else { return }
                        self?.receiveSubjects(snapshot, epoch: epoch)
                    }
                    guard !Task.isCancelled else { return }
                    self?.subjectObservationEnded(epoch: epoch)
                }
                stabilizationTask = Task { [weak self] in
                    for await snapshot in stabilizationStream {
                        guard !Task.isCancelled else { return }
                        self?.receiveStabilization(snapshot, epoch: epoch)
                    }
                    guard !Task.isCancelled else { return }
                    self?.stabilizationObservationEnded(epoch: epoch)
                }
                if readiness(generation: nextGeneration, prepared: result).blockers.contains(where: { $0 != .audioNotValid }) {
                    issue = "希望設定を適用できません。現在の対応条件と実適用値を確認してください。"
                }
            } catch {
                await created.shutDown()
                throw error
            }
        } catch { if accepts(visit) { issue = message(for: error) } }
    }

    private func accepts(_ visit: UUID?) -> Bool {
        visit != nil && captureVisit == visit && !leaveRequested && !Task.isCancelled
    }

    private func beginPreparation() -> UUID {
        let owner = UUID()
        preparationOwner = owner
        isPreparing = true
        return owner
    }

    private func endPreparation(_ owner: UUID) {
        guard preparationOwner == owner else { return }
        preparationOwner = nil
        isPreparing = false
    }

    func record() async {
        guard canRecord, let generation, let prepared, let desired = currentDesired, let applied = currentApplied, let calendarNow else { return }
        invalidateND(.contextChanged)
        isStarting = true
        let context = CaptureContext(generation: generation, capture: .init(rawValue: UUID().uuidString))
        let operation = CaptureOperationID(rawValue: UUID().uuidString)
        // Calendar observation is independent of the monotonic capture timeline.
        // Millisecond precision is shared by store and QuickTime creation-date metadata.
        let observed = calendarNow()
        let capturedAt = Date(timeIntervalSince1970: floor(observed.timeIntervalSince1970 * 1_000) / 1_000)
        let intent = RecordingIntent(context: context, operation: operation,
            original: .init(rawValue: UUID().uuidString), desired: desired, applied: applied,
            acceptedAt: captureNow(), capturedAt: capturedAt)
        var initialAudio = currentAudio ?? prepared.audio
        initialAudio.writing = .notStarted
        observedAudio = initialAudio
        var lifecycle = CaptureLifecycle(context: context, audio: initialAudio)
        let transition = lifecycle.begin(intent, readiness: readiness(generation: generation, prepared: prepared), expectedStoreRevision: 0)
        capture = lifecycle
        activeIntent = intent
        pendingEnd = nil; pendingFile = nil; intentReady = false
        fileFinalizationUnconfirmed = false
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

    /// Called only by the recording screen's explicit user action.
    func refreshWhiteBalance() async {
        guard canRefreshWhiteBalance, var lifecycle = capture else { return }
        let transition = lifecycle.refreshWhiteBalance(operation: .init(rawValue: UUID().uuidString))
        capture = lifecycle
        await perform(transition)
    }

    /// Safe on navigation/background. Capture events and persistence continue until settled.
    func leaveCapture() async {
        let departingDevice = device
        let departingEpoch = eventEpoch
        zoomCommandSequence += 1
        let zoomStop = canStopZoom ? zoom.snapshot.map { CaptureZoomRequest(context: $0.context, command: .stop,
                                                                           sequence: zoomCommandSequence) } : nil
        // Revoke the visit before the first suspension; an old stop completion
        // must never clear a later visit or send a command to its device.
        leaveRequested = true
        zoom.invalidate()
        zoomTask?.cancel(); zoomTask = nil
        invalidateND(.stopped)
        ndTask?.cancel(); ndTask = nil
        subjects = nil
        subjectTask?.cancel(); subjectTask = nil
        framing.invalidate(.interrupted)
        stabilizationTask?.cancel(); stabilizationTask = nil
        captureVisit = nil
        preparationOwner = nil
        isPreparing = false
        if let request = recoveryRequest, let device { await device.cancelAudioRecovery(request) }
        await stop()
        if let zoomStop { _ = await departingDevice?.updateZoom(zoomStop) }
        guard eventEpoch == departingEpoch, captureVisit == nil, leaveRequested else { return }
        await finishLeavingIfPossible()
    }

    var subjectControlsConfigured: Bool { subjectPolicy != nil }
    var allowsSceneTap: Bool {
        subjectPolicy?.noPersonFocus == .tapPosition && subjects?.candidates.isEmpty == true
            && (subjects?.state == .personPriorityAF || subjects?.state == .sceneAF)
    }

    /// Shooting intent is a wish, never a REC admission condition or an exposure command.
    func chooseShootingIntent(_ intent: CaptureShootingIntent) async {
        guard subjectControlsConfigured, preferencesLoaded, !isSavingShootingIntent, !isPreparing,
              let visit = captureVisit, accepts(visit) else { return }
        invalidateND(.contextChanged)
        isSavingShootingIntent = true
        defer { isSavingShootingIntent = false }
        var value = preferences
        value.shootingIntent = intent
        do {
            try await preferenceStore.save(value)
            guard accepts(visit) else { preferencesLoaded = false; return }
            preferences = value
            if let generation { await device?.updateNDIntent(intent, generation: generation) }
            subjectIssue = nil
        } catch { if accepts(visit) { subjectIssue = "撮影意図を保存できませんでした。録画は続けられます。" } }
    }

    func changeSubjects(_ command: CaptureSubjectCommand) async {
        guard subjectControlsConfigured, !isUpdatingSubjects, let subjects, let device,
              !leaveRequested, captureVisit != nil else { return }
        let epoch = eventEpoch
        invalidateND(.contextChanged)
        isUpdatingSubjects = true
        defer { isUpdatingSubjects = false }
        let result = await device.updateSubjects(.init(context: subjects.context, command: command))
        guard epoch == eventEpoch, !leaveRequested else { return }
        if let result { receiveSubjects(result, epoch: epoch) }
        else { self.subjects = nil; subjectIssue = "人物情報が更新されました。現在の候補から指定し直してください。" }
    }

    private func receiveSubjects(_ snapshot: CaptureSubjectSnapshot, epoch: UUID) {
        guard epoch == eventEpoch, !leaveRequested, captureVisit != nil,
              snapshot.context.generation == generation,
              subjectSequence.map({ snapshot.sequence > $0 }) ?? true,
              subjects.map({ snapshot.context.framingRevision >= $0.context.framingRevision
                  && snapshot.context.selectionRevision >= $0.context.selectionRevision
                  && snapshot.context.whiteBalanceRevision >= $0.context.whiteBalanceRevision }) ?? true else { return }
        subjectSequence = snapshot.sequence
        subjects = snapshot
        subjectIssue = nil
    }

    private func subjectObservationEnded(epoch: UUID) {
        guard epoch == eventEpoch else { return }
        subjects = nil
    }

    private func invalidateND(_ reason: CaptureNDReason) {
        ndSnapshot = nil
        ndAdvice = .pending(ndPolicy == nil ? .policyUnavailable : reason)
        ndExpiryTask?.cancel(); ndExpiryTask = nil
    }

    private func receiveND(_ value: CaptureNDSnapshot, epoch: UUID) {
        guard let policy = ndPolicy, epoch == eventEpoch, !leaveRequested, captureVisit != nil,
              !isSavingShootingIntent, !isUpdatingSubjects, value.context.generation == generation,
              value.context.intent == preferences.shootingIntent else { return }
        guard ndSequence.map({ value.sequence > $0 }) ?? true else { invalidateND(.outOfOrder); return }
        ndSequence = value.sequence
        if let previous = ndContext,
           value.context.framingRevision < previous.framingRevision
            || value.context.selectionRevision < previous.selectionRevision
            || value.context.whiteBalanceRevision < previous.whiteBalanceRevision
            || value.context.analysisRevision < previous.analysisRevision { return }
        if let subjects, value.context.framingRevision < subjects.context.framingRevision
            || value.context.selectionRevision < subjects.context.selectionRevision { return }
        ndExpiryTask?.cancel(); ndExpiryTask = nil
        guard value.result != nil || value.advice.direction == .pending else { invalidateND(.contextChanged); return }
        if let result = value.result {
            guard result.context == value.context, result.advice == value.advice else {
                invalidateND(.contextChanged); return
            }
            let age = ProcessInfo.processInfo.systemUptime - result.observedAt
            guard age.isFinite, age >= 0, age <= policy.maximumResultAge else { invalidateND(.stale); return }
            let delay = policy.maximumResultAge - age
            ndExpiryTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard self?.eventEpoch == epoch, self?.ndSnapshot?.sequence == value.sequence else { return }
                self?.invalidateND(.stale)
            }
        }
        ndContext = value.context; ndSnapshot = value; ndAdvice = value.advice
    }

    var currentAudio: CaptureAudioState? { observedAudio ?? prepared?.audio }

    var canRetryAudio: Bool {
        guard !isBusy, !leaveRequested, captureVisit != nil, audioPolicy != nil,
              let failure = currentAudio?.confirmedFailure, failure != .permissionDenied,
              capture == nil || capture?.whiteBalance == .automatic else { return false }
        return device != nil && generation != nil
    }

    /// An explicit user action; successful recovery only enables a later REC.
    func retryAudio() async {
        guard canRetryAudio, let device, let generation, let policy = audioPolicy,
              let failure = currentAudio?.confirmedFailure, let visit = captureVisit else { return }
        isRecoveringAudio = true
        let context = CaptureContext(generation: generation, capture: .init(rawValue: "audio-recovery-" + UUID().uuidString))
        var recovery = CaptureAudioRecovery(context: context, policy: policy.recovery)
        guard var attempt = try? recovery.begin(after: failure) else { isRecoveringAudio = false; return }
        while accepts(visit) {
            let request = ProductCaptureAudioRecoveryRequest(generation: generation, operation: UUID(), ordinal: attempt.ordinal)
            recoveryRequest = request
            recoveryTimedOut = false
            audioRecovery = .attempting(attempt.ordinal)
            observedAudio?.input = .recovering(attempt: attempt.ordinal)
            let timeoutSeconds = attempt.timeout.seconds
            recoveryTimeout = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(timeoutSeconds)) }
                catch { return }
                guard let self, self.recoveryRequest == request else { return }
                self.recoveryTimedOut = true
                self.audioRecovery = .timedOutWaitingForRelease
                // Cancellation is an acknowledged SDK ownership boundary. Until it returns,
                // this owner stays busy even if the uncooperative SDK operation exceeded time.
                await device.cancelAudioRecovery(request)
            }
            let result = await device.recoverAudio(request)
            let timeoutTask = recoveryTimeout
            let timedOut = recoveryTimedOut
            timeoutTask?.cancel()
            if timedOut { await timeoutTask?.value }
            recoveryTimeout = nil
            guard recoveryRequest == request else { break }
            recoveryRequest = nil
            guard accepts(visit) else { break }
            let outcome: CaptureAudioRecoveryOutcome = timedOut
                ? .failed(.routeInterrupted(.init(rawValue: "audio-recovery-timeout"))) : result
            let next = try? recovery.complete(attempt, outcome: outcome)
            switch outcome {
            case .validInput(let route):
                observedAudio?.input = .valid(route: route)
                observedAudio?.writing = .notStarted
                audioRecovery = .readyForUserREC
            case .failed(let failure):
                observedAudio?.input = .failed(failure)
                audioRecovery = .failed
            }
            guard !timedOut, let next else { break }
            attempt = next
        }
        recoveryRequest = nil
        recoveryTimeout?.cancel(); recoveryTimeout = nil
        isRecoveringAudio = false
        await finishLeavingIfPossible()
    }

    var currentStabilization: CaptureStabilizationSnapshot? { framing.snapshot }
    var currentDesired: DesiredCaptureSettings? { sessionDesired ?? preferences.desired }
    var currentApplied: AppliedCaptureSettings? { hasZoomObservation ? zoom.snapshot?.applied : prepared?.applied }

    var canControlZoom: Bool {
        zoomPolicy != nil && device != nil && zoom.snapshot != nil && !isPreparing && !isStarting
            && !isRecoveringAudio && !leaveRequested && captureVisit != nil
            && capture?.phase != .stopping
    }

    var canStartZoom: Bool {
        guard canControlZoom, !isUpdatingZoom, let forecast = zoom.forecast, let snapshot = zoom.snapshot else { return false }
        return !snapshot.phase.isMoving && forecast.context == snapshot.context
            && forecast.framingRevision == framing.revision
    }

    var canStopZoom: Bool { canControlZoom && (pendingZoomMove || zoom.snapshot?.phase.isMoving == true) }

    var nearbyZoomStop: CaptureZoomStop? {
        guard let target = zoom.forecast?.target, let snapshot = zoom.snapshot, let zoomPolicy,
              let assisted = zoomPolicy.assistedTarget(target, range: snapshot.range, stops: snapshot.stops),
              assisted != target else { return nil }
        return snapshot.stops.first { $0.factor == assisted }
    }

    func selectZoomTarget(_ target: Double) {
        guard canControlZoom, !isUpdatingZoom, let zoomPolicy else { return }
        zoom.select(target, framing: framing, policy: zoomPolicy)
        zoomIssue = zoom.forecast == nil ? "構図が更新されました。現在の条件で目標を選び直してください。" : nil
    }

    func startZoom() async {
        guard canStartZoom, let target = zoom.forecast?.target else { return }
        await changeZoom(.move(target: target))
    }

    func stopZoom() async {
        guard canStopZoom else { return }
        await changeZoom(.stop)
    }

    func setManualISO(_ iso: Double) async {
        guard iso.isFinite, iso > 0, case .supported(let limits) = prepared?.capabilities.manualControls,
              limits.iso.contains(iso) else { zoomIssue = "このカメラのISO範囲を確認してください。"; return }
        await changeZoom(.manualISO(iso))
    }

    func switchLens(_ id: String) async {
        guard let lens = zoom.snapshot?.lens, lens.switchingSupported,
              lens.candidates.contains(where: { $0.id == id && $0.available }) else {
            zoomIssue = "現在の記録形式と補正を維持するレンズ切替を確認できません。"; return
        }
        await changeZoom(.switchLens(id))
    }

    private func changeZoom(_ command: CaptureZoomCommand) async {
        let supersedes: Bool
        switch command { case .stop, .manualISO: supersedes = true; default: supersedes = false }
        guard canControlZoom, let device, let snapshot = zoom.snapshot,
              !isUpdatingZoom || supersedes else { return }
        zoomCommandSequence += 1
        let request = CaptureZoomRequest(context: snapshot.context, command: command, sequence: zoomCommandSequence)
        let epoch = eventEpoch
        zoomOperation = request.operation
        if case .move = command { pendingZoomMove = true }
        isUpdatingZoom = true
        zoom.invalidateForecast()
        invalidateND(.contextChanged)
        let result = await device.updateZoom(request)
        guard epoch == eventEpoch, !leaveRequested, zoomOperation == request.operation else { return }
        isUpdatingZoom = false; pendingZoomMove = false
        if let result { receiveZoom(result, epoch: epoch) }
        else { zoomIssue = "条件が更新されたか、操作に対応していません。現在の値を確認して選び直してください。" }
    }

    private func receiveZoom(_ snapshot: CaptureZoomSnapshot, epoch: UUID) {
        guard epoch == eventEpoch, !leaveRequested, captureVisit != nil, let generation,
              snapshot.operation == nil || snapshot.operation == zoomOperation,
              zoom.receive(snapshot, generation: generation) else { return }
        hasZoomObservation = true
        receiveStabilization(snapshot.stabilization, epoch: epoch)
        // Ambient readback can expose a mismatch, but only the latest explicit
        // control command may advance the session wish used for the next REC.
        if let operation = snapshot.operation, operation == zoomOperation,
           let original = preferences.desired,
           snapshot.desired.configuration == original.configuration,
           snapshot.desired.exposure.shutter == original.exposure.shutter,
           snapshot.desired.exposure.aperture == original.exposure.aperture,
           snapshot.applied.values.value?.matches(snapshot.desired) == true {
            sessionDesired = snapshot.desired
        }
        if case .failed(let reason) = snapshot.phase { zoomIssue = reason }
        else if !snapshot.phase.isMoving, let actual = snapshot.applied.values.value,
                let desired = currentDesired, !actual.matches(desired) {
            zoomIssue = "指定した設定と実適用値が一致していません。ISOや倍率の現在値を確認し、対応する値を指定してください。次のRECはまだ開始できません。"
        } else { zoomIssue = nil }
    }

    private var currentStabilizationAllowsRecording: Bool {
        // Existing adapters may provide only the prepare-time applied observation.
        // Missing framing evidence never claims crop/preview equality or overrides that observation.
        guard let snapshot = currentStabilization else {
            return prepared?.stabilization == nil && !hasStabilizationObservation
        }
        guard let desired = currentDesired, let generation, let output = preferences.outputCandidate else { return false }
        return snapshot.matchesRecordingRequest(desired, generation: generation, output: output,
                                                preparedFormatID: prepared?.stabilization?.formatID)
    }

    private func receiveStabilization(_ snapshot: CaptureStabilizationSnapshot, epoch: UUID) {
        guard epoch == eventEpoch, !leaveRequested, captureVisit != nil, let generation else { return }
        if framing.receive(snapshot, generation: generation, desired: preferences.desired, output: preferences.outputCandidate) {
            hasStabilizationObservation = true
            zoom.invalidateForecast()
        }
    }

    private func stabilizationObservationEnded(epoch: UUID) {
        guard epoch == eventEpoch, !leaveRequested, hasStabilizationObservation else { return }
        framing.invalidate(.resourceUnavailable)
        zoom.invalidateForecast()
    }

    var stabilizationConstraint: String? {
        guard prepared != nil, !currentStabilizationAllowsRecording else { return nil }
        guard let snapshot = currentStabilization else {
            return "補正の現在値を確認できません。再準備してください。"
        }
        if !snapshot.matchesRequest { return "希望する補正の実動作が未確認または不一致です。次のRECを開始できません。" }
        return "カメラ・形式・倍率が準備時の条件と一致しません。希望設定を確認して再準備してください。"
    }

    private func receiveAudio(_ snapshot: ProductCaptureAudioSnapshot, epoch: UUID) async {
        guard epoch == eventEpoch, snapshot.generation == generation,
              audioSequence.map({ snapshot.sequence > $0 }) ?? true else { return }
        if let clip = snapshot.capture {
            guard clip == capture?.context.capture else { return }
        } else if capture?.phase == .starting || capture?.phase == .recording || capture?.phase == .stopping {
            return
        }
        audioSequence = snapshot.sequence
        guard !isRecoveringAudio else { return }
        observedAudio = snapshot.state
        if let clip = snapshot.capture, var lifecycle = capture, lifecycle.context.capture == clip {
            let transition = lifecycle.receive(.audioObserved(lifecycle.context, sequence: snapshot.sequence, snapshot.state))
            capture = lifecycle
            await perform(transition)
        }
    }

    private func readiness(generation: CaptureGeneration, prepared: ExplorationPrepared) -> CaptureReadiness {
        .init(generation: generation, desired: currentDesired, capabilities: prepared.capabilities,
              applied: currentApplied, camera: .ready, audioInput: currentAudio?.input ?? prepared.audio.input,
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
                        isSaving = false
                        postSave.enqueue(intent.original, needsBinding: false)
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
            if case .audioObserved(let context, let sequence, _) = event {
                guard context == lifecycle.context,
                      audioSequence.map({ sequence > $0 }) ?? true else { return }
            }
            let transition = lifecycle.receive(event)
            if case .audioObserved(_, let sequence, let state) = event, case .accepted = transition {
                audioSequence = sequence
                observedAudio = state
            }
            capture = lifecycle
            await perform(transition)
        case .fileFinalized(let file):
            guard let intent = activeIntent, file.context == intent.context, file.original == intent.original,
                  !saveFinished, pendingFile == nil else { return }
            pendingFile = file
            await drainSave()
        case .observation(let observation):
            if observation.code == "file_finalization_unconfirmed", let intent = activeIntent,
               observation.context == intent.context, !saveFinished {
                fileFinalizationUnconfirmed = true
                // A concurrent save must retain ownership until its awaited store
                // operation returns. Drain will consume this terminal if no file arrives.
                if !drainingSave, intentReady, endDelivered { finishUnconfirmedFile(intent) }
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
                isSaving = false
                postSave.enqueue(intent.original, needsBinding: false)
                return
            }
            endDelivered = true
        }
        if end.writer == .notStarted {
            issue = "録画は開始されませんでした。保存意図は一覧で要確認として残ります。"
            saveFinished = true
            isSaving = false
            postSave.enqueue(intent.original, needsBinding: false)
            return
        }
        guard let file = pendingFile else {
            if fileFinalizationUnconfirmed { finishUnconfirmedFile(intent) }
            return
        }
        let token = CaptureCommandToken(context: intent.context, operation: intent.operation, ordinal: 100)
        let result = await save.fileFinalized(file, resultToken: token)
        // The durable save terminal is the capture boundary. Content binding and
        // library projection have their own original-scoped lifetime after it.
        saveFinished = true
        isSaving = false
        switch result {
        case .committed(let record, _):
            saveResult = record.result
            postSave.enqueue(intent.original, needsBinding: true)
        default:
            issue = "保存結果を確定できません。一覧で原本と保存記録を確認してください。"
            postSave.enqueue(intent.original, needsBinding: false)
        }
    }

    private func finishUnconfirmedFile(_ intent: RecordingIntent) {
        issue = "録画は停止しましたがファイルの確定を確認できません。一覧で照合してください。"
        saveFinished = true
        isSaving = false
        postSave.enqueue(intent.original, needsBinding: false)
    }

    private func finishLeavingIfPossible() async {
        guard leaveRequested, !isPreparing, !isStarting, !isSaving, !isRecoveringAudio,
              capture == nil || capture?.phase == .ended || capture?.phase == .ready else { return }
        await releaseDevice()
    }

    private func releaseDevice() async {
        eventEpoch = UUID()
        zoom.invalidate(); sessionDesired = nil; zoomOperation = nil; zoomIssue = nil; isUpdatingZoom = false; pendingZoomMove = false; hasZoomObservation = false
        zoomCommandSequence = 0
        zoomTask?.cancel(); zoomTask = nil
        invalidateND(.stopped); ndSequence = nil; ndContext = nil
        ndTask?.cancel(); ndTask = nil
        subjects = nil; subjectSequence = nil; subjectIssue = nil
        subjectTask?.cancel(); subjectTask = nil
        framing.invalidate(.notMeasured)
        hasStabilizationObservation = false
        stabilizationTask?.cancel(); stabilizationTask = nil
        let released = device
        device = nil; previewSource = nil; prepared = nil; generation = nil; capture = nil
        eventTask?.cancel(); eventTask = nil
        audioTask?.cancel(); audioTask = nil
        observedAudio = nil; audioSequence = nil; audioRecovery = .idle
        // Detach before suspension so an old shutdown cannot clear a new preparation.
        if let released { await released.shutDown() }
    }

    private func message(for error: Error) -> String {
        if error is ProductCaptureAudioPreparationError {
            observedAudio = .init(level: .unavailable(.permissionDenied), input: .failed(.permissionDenied),
                arrival: .unobserved, writing: .notStarted)
            return "マイクの使用を許可できません。設定アプリでマイクの許可を確認してください。"
        }
        switch error as? ExplorationIssue {
        case .simulatorHasNoVerifiedCamera: return "Simulatorではカメラ撮影を利用できません。一覧と再生は利用できます。"
        case .permissionDenied: return "カメラとマイクの使用許可を設定で確認してください。"
        case .appliedValuesDiffer: return "希望設定と実際の適用値が一致しません。RECは開始できません。"
        case .capabilityUnconfirmed(let reason) where reason.hasPrefix("stabilization_"):
            switch reason {
            case "stabilization_preview_only": return "選択した補正はプレビュー用で、4K記録には使えません。OFFまたは対応する補正を選んでください。"
            case "stabilization_connection_unsupported": return "選択した記録方式の接続は希望する補正に対応していません。OFFまたは対応モードを選んでください。希望設定は保持しています。"
            default: return "記録出力の補正を確認できません。接続と記録方式を確認して再準備してください。希望設定は保持しています。"
            }
        case .capabilityUnconfirmed: return "現在のカメラ・4K・fps・Log・補正・記録形式の組合せを確認できません。希望は保持しています。条件を確認し、対応モードまたはOFFを選んでください。"
        default: return "カメラを準備できませんでした。条件を確認して再準備してください。"
        }
    }
}
