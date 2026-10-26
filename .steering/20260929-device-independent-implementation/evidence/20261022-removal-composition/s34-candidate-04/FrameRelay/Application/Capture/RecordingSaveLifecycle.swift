nonisolated enum RecordingSavePhase: Equatable, Sendable {
    case awaitingIntentCommit
    case recording
    case recordingEnded
    case fileFinalized
    case awaitingResultCommit(RecordingSaveResult)
    case committed(RecordingSaveResult)
}

/// A separate owner for media/store progress. Capture end is not save completion.
/// Disk durability and restart reconciliation are deferred to the selected adapter.
nonisolated struct RecordingSaveLifecycle: Sendable {
    let intent: RecordingIntent
    let intentToken: CaptureCommandToken
    private(set) var phase: RecordingSavePhase = .awaitingIntentCommit
    private(set) var revision: UInt64
    private(set) var end: RecordingEndEvidence?
    private(set) var file: CaptureFileEvidence?
    private(set) var resultRecord: RecordingResultRecord?
    private var resultToken: CaptureCommandToken?

    init(intent: RecordingIntent, intentToken: CaptureCommandToken, revision: UInt64) throws {
        guard intent.context == intentToken.context, intent.operation == intentToken.operation,
              intent.applied.generation == intent.context.generation,
              intent.applied.values.value?.matches(intent.desired) == true else {
            throw CaptureContractError.evidenceMismatch
        }
        self.intent = intent
        self.intentToken = intentToken
        self.revision = revision
    }

    mutating func acceptIntentCommit(_ receipt: RecordingCommitReceipt) throws {
        guard phase == .awaitingIntentCommit else { throw CaptureContractError.duplicateOrOutOfOrder }
        guard receipt.matches(intentToken, revision: revision) else { throw CaptureContractError.revisionConflict }
        revision = receipt.committedRevision
        phase = .recording
    }

    mutating func acceptRecordingEnd(context: CaptureContext, evidence: RecordingEndEvidence) throws {
        guard context == intent.context else { throw CaptureContractError.wrongContext }
        guard phase == .recording else { throw CaptureContractError.duplicateOrOutOfOrder }
        end = evidence
        phase = .recordingEnded
    }

    mutating func acceptFile(_ evidence: CaptureFileEvidence) throws {
        guard evidence.context == intent.context, evidence.original == intent.original else {
            throw CaptureContractError.evidenceMismatch
        }
        guard phase == .recordingEnded else { throw CaptureContractError.duplicateOrOutOfOrder }
        file = evidence
        phase = .fileFinalized
    }

    mutating func acceptInspection(_ inspection: CaptureMediaInspection,
                                  resultToken: CaptureCommandToken) throws -> RecordingStoreCommand {
        guard phase == .fileFinalized, let end, let file else { throw CaptureContractError.wrongStage }
        guard inspection.context == intent.context, inspection.original == intent.original,
              resultToken.context == intent.context, resultToken.operation == intent.operation,
              resultToken.ordinal > intentToken.ordinal else {
            throw CaptureContractError.evidenceMismatch
        }
        let result = classify(end: end, file: file, inspection: inspection)
        let record = RecordingResultRecord(intent: intent, end: end, file: file,
                                           inspection: inspection, result: result)
        resultRecord = record
        self.resultToken = resultToken
        phase = .awaitingResultCommit(result)
        return .commitResult(resultToken, expectedRevision: revision, record)
    }

    mutating func acceptResultCommit(_ receipt: RecordingCommitReceipt) throws {
        guard case .awaitingResultCommit(let result) = phase, let resultToken else {
            throw CaptureContractError.duplicateOrOutOfOrder
        }
        guard receipt.matches(resultToken, revision: revision) else { throw CaptureContractError.revisionConflict }
        revision = receipt.committedRevision
        phase = .committed(result)
    }

    private func classify(end: RecordingEndEvidence, file: CaptureFileEvidence,
                          inspection: CaptureMediaInspection) -> RecordingSaveResult {
        if case .unknown(let reason) = inspection.completeness { return .unknown(reason) }
        guard !inspection.video.isUnknown, !inspection.audio.isUnknown,
              let format = inspection.format.value else { return .unknown(.evidenceMissing) }
        guard format.matches(intent.desired.configuration) else { return .unknown(.evidenceMismatch) }
        switch inspection.playback {
        case .unavailable(let reason): return .unknown(reason)
        case .failed(let reason): return .failed(reason)
        case .verified: break
        }
        guard file.byteCount > 0, inspection.video.hasSamples else { return .failed(.evidenceMissing) }
        if case .partial(let reason) = inspection.completeness { return .partial(reason) }
        guard inspection.audio.hasSamples else { return .partial(.evidenceMissing) }
        switch end.writer {
        case .completed: return .saved
        case .interrupted(let reason), .failed(let reason): return .partial(reason)
        case .notStarted: return .unknown(.evidenceMismatch)
        }
    }
}

nonisolated enum OriginalSaveOperationResult: Equatable, Sendable {
    case ready(RecordingCommitReceipt)
    case accepted
    case committed(RecordingResultRecord, RecordingCommitReceipt)
    case requiresReconciliation(CaptureUnavailableReason)
    case rejected(CaptureContractError)
}

/// Product save owner. The caller starts its writer only after `ready`, reports
/// its actual recording end, then its actual finalized-file evidence. Recovery
/// never fabricates either callback or restarts an interrupted recording.
actor OriginalSaveCoordinator {
    private let store: any RecordingStorePort
    private let originals: any RecordingOriginalFilePort
    private let inspection: any CaptureOriginalInspectionPort
    private var saves: [CaptureID: RecordingSaveLifecycle] = [:]
    private var busy: Set<CaptureID> = []

    init(store: any RecordingStorePort, originals: any RecordingOriginalFilePort,
         inspection: any CaptureOriginalInspectionPort) {
        self.store = store; self.originals = originals; self.inspection = inspection
    }

    func begin(_ intent: RecordingIntent, token: CaptureCommandToken) async -> OriginalSaveOperationResult {
        let capture = intent.context.capture
        guard saves[capture] == nil, busy.insert(capture).inserted else {
            return .rejected(.duplicateOrOutOfOrder)
        }
        defer { busy.remove(capture) }
        do {
            var save = try RecordingSaveLifecycle(intent: intent, intentToken: token, revision: 0)
            guard case .loaded(let snapshot) = await store.loadRecordings() else {
                return .requiresReconciliation(.resourceUnavailable)
            }
            guard !snapshot.recordings.contains(where: { $0.intent.context.capture == capture
                || $0.intent.original == intent.original || $0.intent.operation == intent.operation }) else {
                return .rejected(.duplicateOrOutOfOrder)
            }
            try await originals.reserveForRecording(intent.original)
            switch await store.execute(.commitIntent(token, expectedRevision: 0, intent)) {
            case .committed(let receipt):
                try save.acceptIntentCommit(receipt)
                saves[capture] = save
                return .ready(receipt)
            case .rejected(_, let error): return .rejected(error)
            case .unavailable(_, let reason): return .requiresReconciliation(reason)
            }
        } catch let error as CaptureContractError { return .rejected(error) }
        catch { return .requiresReconciliation(.resourceUnavailable) }
    }

    func recordingEnded(context: CaptureContext, evidence: RecordingEndEvidence) -> OriginalSaveOperationResult {
        guard !busy.contains(context.capture), var save = saves[context.capture] else {
            return .rejected(.wrongStage)
        }
        do {
            try save.acceptRecordingEnd(context: context, evidence: evidence)
            saves[context.capture] = save
            return .accepted
        } catch let error as CaptureContractError { return .rejected(error) }
        catch { return .requiresReconciliation(.evidenceMismatch) }
    }

    func fileFinalized(_ file: CaptureFileEvidence, resultToken: CaptureCommandToken) async -> OriginalSaveOperationResult {
        let capture = file.context.capture
        guard var save = saves[capture], busy.insert(capture).inserted else { return .rejected(.wrongStage) }
        defer { busy.remove(capture) }
        do {
            guard await originals.observeFile(file.original) == .present(byteCount: file.byteCount) else {
                return .requiresReconciliation(.evidenceMismatch)
            }
            try save.acceptFile(file)
            saves[capture] = save
            let request = CaptureInspectionRequest(token: resultToken, original: file.original)
            let inspected: CaptureMediaInspection
            switch await inspection.inspect(request) {
            case .inspected(let token, let value):
                guard token == resultToken else { return .requiresReconciliation(.evidenceMismatch) }
                inspected = value
            case .unavailable(let token, let reason):
                guard token == resultToken else { return .requiresReconciliation(.evidenceMismatch) }
                inspected = CaptureMediaInspection(context: file.context, original: file.original,
                    video: .unavailable(reason), audio: .unavailable(reason), format: .unavailable(reason),
                    playback: .unavailable(reason), completeness: .unknown(reason))
            }
            guard await originals.observeFile(file.original) == .present(byteCount: file.byteCount) else {
                return .requiresReconciliation(.evidenceMismatch)
            }
            let command = try save.acceptInspection(inspected, resultToken: resultToken)
            saves[capture] = save
            switch await store.execute(command) {
            case .committed(let receipt):
                try save.acceptResultCommit(receipt)
                saves[capture] = save
                guard let record = save.resultRecord else { return .requiresReconciliation(.evidenceMissing) }
                return .committed(record, receipt)
            case .rejected(_, let error): return .rejected(error)
            case .unavailable(_, let reason): return .requiresReconciliation(reason)
            }
        } catch let error as CaptureContractError { return .rejected(error) }
        catch { return .requiresReconciliation(.resourceUnavailable) }
    }
}
