/// Per-capture ordering, independent of camera I/O. An old clip cannot re-lock or
/// restore Auto over a later clip, even when ordinals restart at the same value.
nonisolated struct ExplorationWBCommandOrder: Sendable {
    private enum Stage { case locking, locked, restoring, automatic }
    let generation: CaptureGeneration
    private var latest: CaptureCommandToken?
    private var stage: Stage = .automatic
    private var completed: Set<CaptureContext> = []

    mutating func requestLock(_ token: CaptureCommandToken) -> Bool {
        guard token.context.generation == generation, !completed.contains(token.context) else { return false }
        if let latest {
            if latest.context == token.context {
                guard token.ordinal > latest.ordinal, stage != .restoring else { return false }
            } else {
                guard stage == .automatic, completed.contains(latest.context) else { return false }
            }
        }
        latest = token
        stage = .locking
        return true
    }

    mutating func appliedLock(_ token: CaptureCommandToken) -> Bool {
        guard latest == token, stage == .locking else { return false }
        stage = .locked
        return true
    }

    mutating func requestAutomatic(_ token: CaptureCommandToken) -> Bool {
        guard let latest, latest.context == token.context, token.ordinal > latest.ordinal,
              !completed.contains(token.context) else { return false }
        self.latest = token
        stage = .restoring
        return true
    }

    mutating func appliedAutomatic(_ token: CaptureCommandToken) -> Bool {
        guard latest == token, stage == .restoring else { return false }
        completed.insert(token.context)
        stage = .automatic
        return true
    }

    func canStart(_ context: CaptureContext) -> Bool {
        latest?.context == context && stage == .locked && !completed.contains(context)
    }
}
