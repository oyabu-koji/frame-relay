nonisolated enum CapturePhase: Equatable, Sendable {
    case ready
    case starting
    case recording
    case stopping
    case ended
    case blocked(CaptureUnavailableReason)
}

nonisolated enum CaptureLifecycleEffect: Equatable, Sendable {
    case capture(CaptureIOCommand)
    case store(RecordingStoreCommand)
    case recordingCeased(RecordingEndEvidence)
}

nonisolated enum CaptureTransition: Equatable, Sendable {
    case accepted([CaptureLifecycleEffect])
    case rejected(CaptureContractError)
    case cannotRecord([RecordingBlocker])
}

nonisolated enum CaptureIntentPersistence: Equatable, Sendable {
    case notRequested
    case pending(CaptureCommandToken)
    case committed(RecordingCommitReceipt)
    case rejected(CaptureContractError)
    case unknown(CaptureUnavailableReason)
}

/// One capture, owned by the session coordinator. This pure reducer performs no I/O.
/// A new capture gets a new instance/context and must reacquire WB; no lock is inherited.
nonisolated struct CaptureLifecycle: Sendable {
    let context: CaptureContext
    private(set) var phase: CapturePhase = .ready
    private(set) var whiteBalance: CaptureWhiteBalanceState = .automatic
    private(set) var audio: CaptureAudioState
    private(set) var startedAt: CaptureTimeObservation?
    private(set) var end: RecordingEndEvidence?
    private(set) var intentPersistence: CaptureIntentPersistence = .notRequested
    private(set) var failureReason: CaptureUnavailableReason?

    var intentReceipt: RecordingCommitReceipt? {
        guard case .committed(let receipt) = intentPersistence else { return nil }
        return receipt
    }

    private var intent: RecordingIntent?
    private var expectedRevision: UInt64?
    private var intentToken: CaptureCommandToken?
    private var whiteBalanceToken: CaptureCommandToken?
    private var recordingToken: CaptureCommandToken?
    private var automaticToken: CaptureCommandToken?
    private var stopReason: CaptureStopReason?
    private var lastAudioSequence: UInt64?
    private var ordinal: UInt64 = 0

    init(context: CaptureContext, audio: CaptureAudioState) {
        self.context = context
        self.audio = audio
    }

    mutating func begin(_ intent: RecordingIntent, readiness: CaptureReadiness,
                        expectedStoreRevision: UInt64) -> CaptureTransition {
        guard phase == .ready else { return .rejected(.wrongStage) }
        guard intent.context == context, readiness.generation == context.generation else {
            return .rejected(.wrongContext)
        }
        let blockers = readiness.blockers
        guard blockers.isEmpty else { return .cannotRecord(blockers) }
        guard readiness.desired == intent.desired, readiness.applied == intent.applied else {
            return .rejected(.evidenceMismatch)
        }
        guard audio.confirmedFailure == nil, audio.input == readiness.audioInput else {
            return .cannotRecord([.audioNotValid])
        }
        self.intent = intent
        expectedRevision = expectedStoreRevision
        phase = .starting
        let storeToken = nextToken(operation: intent.operation)
        intentToken = storeToken
        intentPersistence = .pending(storeToken)
        let wbToken = nextToken(operation: intent.operation)
        whiteBalanceToken = wbToken
        whiteBalance = .locking(wbToken)
        // WB measurement is requested at acceptance, independently of store latency.
        return .accepted([
            .store(.commitIntent(storeToken, expectedRevision: expectedStoreRevision, intent)),
            .capture(.lockCurrentWhiteBalance(wbToken))
        ])
    }

    mutating func receiveIntentCommit(_ receipt: RecordingCommitReceipt) -> CaptureTransition {
        guard receipt.token.context == context else { return .rejected(.wrongContext) }
        guard let intentToken, let expectedRevision, case .pending = intentPersistence else {
            return .rejected(.duplicateOrOutOfOrder)
        }
        guard receipt.matches(intentToken, revision: expectedRevision) else {
            return .rejected(.revisionConflict)
        }
        intentPersistence = .committed(receipt)
        return advanceStartOrCancel()
    }

    mutating func receiveIntentStoreResult(_ result: RecordingStoreResult) -> CaptureTransition {
        switch result {
        case .committed(let receipt): return receiveIntentCommit(receipt)
        case .rejected(let token, let error):
            guard token.context == context else { return .rejected(.wrongContext) }
            guard token == intentToken, case .pending = intentPersistence else {
                return .rejected(.duplicateOrOutOfOrder)
            }
            intentPersistence = .rejected(error)
        case .unavailable(let token, let reason):
            guard token.context == context else { return .rejected(.wrongContext) }
            guard token == intentToken, case .pending = intentPersistence else {
                return .rejected(.duplicateOrOutOfOrder)
            }
            // It may have committed before its response was lost. Recovery must read it.
            intentPersistence = .unknown(reason)
        }
        guard end == nil else { return .accepted([]) }
        return completeRecording(neverStartedEvidence())
    }

    mutating func stop(operation: CaptureOperationID) -> CaptureTransition {
        requestStop(.user(operation))
    }

    mutating func refreshWhiteBalance(operation: CaptureOperationID) -> CaptureTransition {
        guard phase == .recording, case .locked(let previous) = whiteBalance else {
            return .rejected(.wrongStage)
        }
        let token = nextToken(operation: operation)
        whiteBalanceToken = token
        whiteBalance = .refreshing(token, previous: previous)
        return .accepted([.capture(.refreshAndLockWhiteBalance(token))])
    }

    mutating func receive(_ event: CaptureIOEvent) -> CaptureTransition {
        switch event {
        case .whiteBalanceLocked(let token, let lock):
            guard token.context == context else { return .rejected(.wrongContext) }
            guard token == whiteBalanceToken, end == nil else {
                return .rejected(.duplicateOrOutOfOrder)
            }
            whiteBalanceToken = nil
            whiteBalance = .locked(lock)
            return advanceStartOrCancel()
        case .automaticWhiteBalanceRestored(let token, _):
            guard token.context == context else { return .rejected(.wrongContext) }
            guard token == automaticToken, end != nil else {
                return .rejected(.duplicateOrOutOfOrder)
            }
            automaticToken = nil
            whiteBalance = .automatic
            return .accepted([])
        case .recordingStarted(let token, let at):
            guard token.context == context else { return .rejected(.wrongContext) }
            guard token == recordingToken, startedAt == nil, end == nil else {
                return .rejected(.duplicateOrOutOfOrder)
            }
            startedAt = at
            // A delayed didStart after STOP is evidence, never a return to recording UI.
            if stopReason == nil { phase = .recording }
            return .accepted([])
        case .recordingEnded(let token, let evidence):
            guard token.context == context else { return .rejected(.wrongContext) }
            guard token == recordingToken, end == nil else {
                return .rejected(.duplicateOrOutOfOrder)
            }
            return completeRecording(evidence)
        case .commandFailed(let token, let reason):
            return commandFailed(token: token, reason: reason)
        case .audioObserved(let incomingContext, let sequence, let state):
            guard incomingContext == context else { return .rejected(.wrongContext) }
            guard lastAudioSequence.map({ sequence > $0 }) ?? true else {
                return .rejected(.duplicateOrOutOfOrder)
            }
            lastAudioSequence = sequence
            audio = state
            if let failure = state.confirmedFailure, phase == .starting || phase == .recording {
                return requestStop(.audioFailure(failure))
            }
            if phase == .starting { return advanceStartOrCancel() }
            return .accepted([])
        }
    }

    private mutating func nextToken(operation: CaptureOperationID) -> CaptureCommandToken {
        ordinal += 1
        return CaptureCommandToken(context: context, operation: operation, ordinal: ordinal)
    }

    private mutating func requestStop(_ reason: CaptureStopReason) -> CaptureTransition {
        guard phase == .starting || phase == .recording, stopReason == nil else {
            return .rejected(.wrongStage)
        }
        stopReason = reason
        phase = .stopping
        if let recordingToken {
            return .accepted([.capture(.stopRecording(recordingToken, reason: reason))])
        }
        // No start command exists, so cancellation can finish without waiting for I/O.
        // A late store result is retained separately; old WB work is superseded by Auto.
        return completeRecording(neverStartedEvidence())
    }

    private mutating func advanceStartOrCancel() -> CaptureTransition {
        guard recordingToken == nil, end == nil, let intent,
              intentReceipt != nil, case .locked = whiteBalance else { return .accepted([]) }
        if stopReason != nil {
            return completeRecording(neverStartedEvidence())
        }
        // Recheck a resource that may have changed while WB/store were in flight.
        guard case .valid = audio.input, audio.confirmedFailure == nil else { return .accepted([]) }
        let token = nextToken(operation: intent.operation)
        recordingToken = token
        return .accepted([.capture(.startRecording(token, intent))])
    }

    private mutating func completeRecording(_ evidence: RecordingEndEvidence) -> CaptureTransition {
        guard let intent else { return .rejected(.wrongStage) }
        end = evidence
        phase = .ended
        // Only the actual recording-end contract (or never-started cancellation) unlocks WB.
        whiteBalanceToken = nil
        let token = nextToken(operation: intent.operation)
        automaticToken = token
        whiteBalance = .restoringAutomatic(token)
        return .accepted([.recordingCeased(evidence), .capture(.restoreAutomaticWhiteBalance(token))])
    }

    private func neverStartedEvidence() -> RecordingEndEvidence {
        RecordingEndEvidence(writer: .notStarted, ceasedAt: .unavailable(.notMeasured),
                             lastVideo: .unavailable(.notMeasured), lastAudio: .unavailable(.notMeasured))
    }

    private mutating func commandFailed(token: CaptureCommandToken,
                                        reason: CaptureUnavailableReason) -> CaptureTransition {
        guard token.context == context else { return .rejected(.wrongContext) }
        if token == recordingToken, end == nil {
            // A failed command is not proof the recorder ceased; keep WB fixed until its end.
            if stopReason == nil { return requestStop(.adapterFailure(reason)) }
            return .accepted([])
        }
        if token == automaticToken {
            automaticToken = nil
            whiteBalance = .unavailable(reason)
            return .accepted([])
        }
        if token == whiteBalanceToken, end == nil {
            whiteBalanceToken = nil
            whiteBalance = .unavailable(reason)
            failureReason = reason
            if recordingToken != nil {
                return stopReason == nil ? requestStop(.adapterFailure(reason)) : .accepted([])
            }
            return completeRecording(neverStartedEvidence())
        }
        return .rejected(.duplicateOrOutOfOrder)
    }
}
