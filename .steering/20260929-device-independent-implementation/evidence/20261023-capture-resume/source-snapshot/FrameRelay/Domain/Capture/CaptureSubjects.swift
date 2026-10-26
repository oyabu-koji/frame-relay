import Foundation

nonisolated enum CaptureShootingIntent: String, CaseIterable, Codable, Sendable {
    case people, peopleAndBackground, scenery
}

/// Ephemeral identity, scoped to one analysis session. Never persisted or logged.
nonisolated struct CapturePersonID: Hashable, Sendable {
    let rawValue: UUID
    init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

/// Normalized, unrotated, unmirrored capture-device coordinates; origin at top left.
nonisolated struct CaptureSubjectPoint: Equatable, Sendable {
    let x: Double
    let y: Double
    var isValid: Bool { x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y) }
}

nonisolated struct CaptureSubjectRect: Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    var center: CaptureSubjectPoint { .init(x: x + width / 2, y: y + height / 2) }
    var isValid: Bool {
        [x, y, width, height].allSatisfy(\.isFinite) && x >= 0 && y >= 0 && width > 0 && height > 0
            && x + width <= 1.000001 && y + height <= 1.000001
    }
}

nonisolated enum CapturePersonContinuity: Equatable, Sendable {
    case newDetection, continuous, reacquired
}

nonisolated struct CapturePersonCandidate: Equatable, Sendable, Identifiable {
    let id: CapturePersonID
    let bounds: CaptureSubjectRect
    let continuity: CapturePersonContinuity
}

/// Technical thresholds are versioned provisional implementation settings, not identity proof
/// or device acceptance. Feature-print distance is image similarity, never face recognition.
nonisolated struct CaptureSubjectPolicy: Equatable, Sendable {
    enum NoPersonFocus: Equatable, Sendable { case unconfigured, tapPosition }
    let version: String
    let lostGrace: TimeInterval
    let noPersonFocus: NoPersonFocus
    let minimumFrameInterval: TimeInterval
    let maximumResultAge: TimeInterval
    let maximumPeople: Int
    let detectionConfidence: Float
    let trackingConfidence: Float
    let continuousDistance: Float
    let reacquisitionDistance: Float
    let ambiguityMargin: Float

    init(version: String, lostGrace: TimeInterval, noPersonFocus: NoPersonFocus,
         minimumFrameInterval: TimeInterval = 0.2, maximumResultAge: TimeInterval = 0.8,
         maximumPeople: Int = 8, detectionConfidence: Float = 0.65, trackingConfidence: Float = 0.7,
         continuousDistance: Float = 0.45, reacquisitionDistance: Float = 0.25, ambiguityMargin: Float = 0.12) {
        precondition(lostGrace.isFinite && lostGrace > 0 && minimumFrameInterval > 0 && maximumResultAge > 0)
        precondition((1...16).contains(maximumPeople) && reacquisitionDistance > 0 && continuousDistance > 0 && ambiguityMargin > 0)
        self.version = version; self.lostGrace = lostGrace; self.noPersonFocus = noPersonFocus
        self.minimumFrameInterval = minimumFrameInterval; self.maximumResultAge = maximumResultAge
        self.maximumPeople = maximumPeople; self.detectionConfidence = detectionConfidence
        self.trackingConfidence = trackingConfidence; self.continuousDistance = continuousDistance
        self.reacquisitionDistance = reacquisitionDistance; self.ambiguityMargin = ambiguityMargin
    }
}

nonisolated struct CaptureSubjectContext: Equatable, Sendable {
    let generation: CaptureGeneration
    let framingRevision: UInt64
    let selectionRevision: UInt64
    let whiteBalanceRevision: UInt64

    init(generation: CaptureGeneration, framingRevision: UInt64, selectionRevision: UInt64, whiteBalanceRevision: UInt64 = 0) {
        self.generation = generation; self.framingRevision = framingRevision
        self.selectionRevision = selectionRevision; self.whiteBalanceRevision = whiteBalanceRevision
    }
}

nonisolated struct CaptureSubjectAnalysis: Equatable, Sendable {
    let context: CaptureSubjectContext
    let sequence: UInt64
    let observedAt: TimeInterval
    let candidates: [CapturePersonCandidate]
    let available: Bool
}

nonisolated enum CaptureSubjectFocusState: Equatable, Sendable {
    case detecting, following(CapturePersonID), lostHolding(CapturePersonID), heldAwaitingSelection
    case personPriorityAF, sceneAF, unavailable
}

nonisolated enum CaptureSubjectFocusAction: Equatable, Sendable {
    case hold
    case continuous(CaptureSubjectPoint, personDriven: Bool)
    case personPriority
}

nonisolated enum CaptureSubjectFocusAvailability: Equatable, Sendable {
    case unconfirmed, applied, unsupported, failed
}

nonisolated struct CaptureSubjectSnapshot: Equatable, Sendable {
    let context: CaptureSubjectContext
    let sequence: UInt64
    let candidates: [CapturePersonCandidate]
    let exposureTargets: Set<CapturePersonID>
    let protagonist: CapturePersonID?
    let trackingEnabled: Bool
    let state: CaptureSubjectFocusState
    let focus: CaptureSubjectFocusAvailability
}

nonisolated enum CaptureSubjectCommand: Equatable, Sendable {
    case selectProtagonist(CapturePersonID)
    case toggleExposure(CapturePersonID)
    case tracking(Bool)
    case scenePoint(CaptureSubjectPoint)
}

nonisolated struct CaptureSubjectRequest: Equatable, Sendable {
    let context: CaptureSubjectContext
    let command: CaptureSubjectCommand
}

/// Pure state machine shared by the SDK owner and boundary tests. It never gates REC.
nonisolated struct CaptureSubjectSession: Sendable {
    private(set) var context: CaptureSubjectContext
    private(set) var candidates: [CapturePersonCandidate] = []
    private(set) var exposureTargets: Set<CapturePersonID> = []
    private(set) var protagonist: CapturePersonID?
    private(set) var trackingEnabled = false
    private(set) var state: CaptureSubjectFocusState = .detecting
    private(set) var highestSequence: UInt64 = 0
    private(set) var analysisAvailable = false
    private(set) var lastObservedAt: TimeInterval?
    private(set) var lostAt: TimeInterval?
    private(set) var scenePoint: CaptureSubjectPoint?
    let policy: CaptureSubjectPolicy

    init(context: CaptureSubjectContext, policy: CaptureSubjectPolicy) { self.context = context; self.policy = policy }

    mutating func command(_ request: CaptureSubjectRequest, now: TimeInterval) -> CaptureSubjectFocusAction? {
        guard request.context == context else { return nil }
        switch request.command {
        case .selectProtagonist(let id):
            guard currentCandidates(now: now).contains(where: { $0.id == id }) else { return nil }
            protagonist = id; trackingEnabled = true; lostAt = nil; scenePoint = nil
            state = .following(id)
        case .toggleExposure(let id):
            guard currentCandidates(now: now).contains(where: { $0.id == id }) else { return nil }
            if exposureTargets.contains(id) { exposureTargets.remove(id) } else { exposureTargets.insert(id) }
        case .tracking(let enabled):
            trackingEnabled = enabled; lostAt = nil; scenePoint = nil
            // Enabling is not a new identity decision. A previously lost subject needs a new tap.
            state = enabled ? .heldAwaitingSelection : .personPriorityAF
            if !enabled { protagonist = nil }
        case .scenePoint(let point):
            guard policy.noPersonFocus == .tapPosition, point.isValid, candidates.isEmpty, analysisAvailable,
                  lastObservedAt.map({ now - $0 <= policy.maximumResultAge }) == true else { return nil }
            scenePoint = point; protagonist = nil; trackingEnabled = false; state = .sceneAF
        }
        context = .init(generation: context.generation, framingRevision: context.framingRevision,
                        selectionRevision: context.selectionRevision + 1, whiteBalanceRevision: context.whiteBalanceRevision)
        return action
    }

    @discardableResult
    mutating func receive(_ result: CaptureSubjectAnalysis, now: TimeInterval) -> Bool {
        guard result.context == context, result.sequence > highestSequence,
              result.observedAt.isFinite, now.isFinite, result.observedAt <= now,
              lastObservedAt.map({ result.observedAt >= $0 }) ?? true,
              now - result.observedAt <= policy.maximumResultAge else { return false }
        highestSequence = result.sequence
        lastObservedAt = result.observedAt
        analysisAvailable = result.available && result.candidates.allSatisfy { $0.bounds.isValid }
            && Set(result.candidates.map(\.id)).count == result.candidates.count
        candidates = analysisAvailable ? Array(result.candidates.prefix(policy.maximumPeople)) : []
        exposureTargets.formIntersection(Set(candidates.map(\.id)).union(protagonist.map { [$0] } ?? []))
        if !analysisAvailable { markMissing(now: now); return true }
        if trackingEnabled, let protagonist {
            // New detection IDs alone never establish continuity with the selected person.
            if state != .heldAwaitingSelection,
               candidates.contains(where: { $0.id == protagonist && $0.continuity != .newDetection }),
               lostAt.map({ now - $0 <= policy.lostGrace }) ?? true {
                lostAt = nil; state = .following(protagonist)
            } else { markMissing(now: now) }
        } else if trackingEnabled { state = .heldAwaitingSelection }
        else {
            // A scene point is the no-person fallback. With people visible again,
            // tracking OFF must resume person-priority AF rather than keep that point.
            if !candidates.isEmpty { scenePoint = nil }
            state = scenePoint == nil ? .personPriorityAF : .sceneAF
        }
        return true
    }

    @discardableResult
    mutating func expire(now: TimeInterval) -> Bool {
        var changed = false
        if let lastObservedAt, now - lastObservedAt > policy.maximumResultAge, !candidates.isEmpty || state == .personPriorityAF || state == .sceneAF {
            candidates = []; analysisAvailable = false; markMissing(now: now); changed = true
        }
        if let lostAt, now - lostAt > policy.lostGrace, state != .heldAwaitingSelection {
            state = .heldAwaitingSelection; changed = true
        }
        return changed
    }

    mutating func invalidateAnalysis(now: TimeInterval) {
        analysisAvailable = false
        candidates = []
        markMissing(now: now)
    }

    mutating func invalidateWhiteBalance(now: TimeInterval) {
        context = .init(generation: context.generation, framingRevision: context.framingRevision,
            selectionRevision: context.selectionRevision, whiteBalanceRevision: context.whiteBalanceRevision + 1)
        lastObservedAt = nil
        invalidateAnalysis(now: now)
    }

    mutating func invalidateFraming(_ revision: UInt64) {
        context = .init(generation: context.generation, framingRevision: revision, selectionRevision: context.selectionRevision + 1, whiteBalanceRevision: context.whiteBalanceRevision)
        candidates = []; analysisAvailable = false; exposureTargets = []; lastObservedAt = nil; lostAt = nil; scenePoint = nil
        state = trackingEnabled ? .heldAwaitingSelection : .detecting
    }

    var action: CaptureSubjectFocusAction {
        switch state {
        case .following(let id):
            return candidates.first(where: { $0.id == id }).map { .continuous($0.bounds.center, personDriven: false) } ?? .hold
        case .personPriorityAF:
            // Selection of exposure targets never changes this independent priority rule.
            return candidates.max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height })
                .map { .continuous($0.bounds.center, personDriven: true) } ?? .personPriority
        case .sceneAF: return scenePoint.map { .continuous($0, personDriven: false) } ?? .hold
        case .detecting: return trackingEnabled ? .hold : .personPriority
        case .unavailable: return trackingEnabled ? .hold : .personPriority
        case .lostHolding, .heldAwaitingSelection: return .hold
        }
    }

    func snapshot(sequence: UInt64, focus: CaptureSubjectFocusAvailability) -> CaptureSubjectSnapshot {
        .init(context: context, sequence: sequence, candidates: candidates, exposureTargets: exposureTargets,
              protagonist: protagonist, trackingEnabled: trackingEnabled, state: state, focus: focus)
    }

    private func currentCandidates(now: TimeInterval) -> [CapturePersonCandidate] {
        guard lastObservedAt.map({ now - $0 <= policy.maximumResultAge }) == true else { return [] }
        return candidates
    }

    private mutating func markMissing(now: TimeInterval) {
        if trackingEnabled, let protagonist {
            if state == .heldAwaitingSelection { return }
            if lostAt == nil { lostAt = now }
            state = now - (lostAt ?? now) <= policy.lostGrace ? .lostHolding(protagonist) : .heldAwaitingSelection
        } else { state = .unavailable }
    }
}
