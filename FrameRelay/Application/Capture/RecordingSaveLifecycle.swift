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
