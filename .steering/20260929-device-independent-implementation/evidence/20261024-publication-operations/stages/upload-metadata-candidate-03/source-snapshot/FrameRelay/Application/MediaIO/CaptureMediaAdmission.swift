import Foundation

/// Common process admission, independent of deletion/invalidation seals. Empty
/// memory after restart is not evidence that persisted capture waits ended.
nonisolated final class CaptureMediaAdmission: @unchecked Sendable {
    struct Snapshot: Equatable, Sendable {
        let revision: UInt64
        let owners: [CaptureMediaOwner: Set<CaptureMediaPhase>]
        let exhausted: Bool
        var isHeld: Bool { exhausted || !owners.isEmpty }
        var waits: Set<MediaWaitReason> {
            Set(owners.values.flatMap { $0 }.map { phase -> MediaWaitReason in
                switch phase { case .recording: .recording; case .saving: .saving; case .recovery: .recovery }
            })
        }
    }

    private let lock = NSLock()
    private var revision: UInt64 = 0
    private var owners: [CaptureMediaOwner: Set<CaptureMediaPhase>] = [:]
    private var retired = Set<CaptureMediaOwner>()
    private var exhausted = false

    func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        return .init(revision: revision, owners: owners, exhausted: exhausted)
    }

    /// Process-local dispatch authority only; this is not a network/path permit.
    func authorizeResume() -> CaptureMediaResumeAuthorization? {
        lock.lock(); defer { lock.unlock() }
        guard !exhausted, owners.isEmpty else { return nil }
        return .init(admission: self, revision: revision)
    }

    /// The action must be short and synchronous on its SDK executor. It must
    /// neither dispatch later work nor call back into this admission. The
    /// nonescaping/nonasync signature keeps the actual boundary inside the lock.
    @discardableResult
    func performIfCurrent(_ authorization: CaptureMediaResumeAuthorization,
                          action: () throws -> Void) rethrows -> Bool {
        lock.lock(); defer { lock.unlock() }
        // Check immutable origin before touching state protected by that origin's
        // lock. A different admission cannot consume or validate this value.
        guard authorization.admission === self else { return false }
        guard !exhausted, owners.isEmpty, revision == authorization.revision,
              !authorization.consumed else { return false }
        authorization.consumed = true
        try action()
        return true
    }

    func begin(_ owner: CaptureMediaOwner, phases: Set<CaptureMediaPhase>) {
        lock.lock(); defer { lock.unlock() }
        guard !phases.isEmpty, owners[owner] == nil, !retired.contains(owner) else { return }
        advance(); owners[owner] = phases
    }

    func update(_ owner: CaptureMediaOwner, phases: Set<CaptureMediaPhase>) {
        lock.lock(); defer { lock.unlock() }
        guard owners[owner] != nil, owners[owner] != phases, !phases.isEmpty else { return }
        advance(); owners[owner] = phases
    }

    func end(_ owner: CaptureMediaOwner) {
        lock.lock(); defer { lock.unlock() }
        guard owners.removeValue(forKey: owner) != nil else { return }
        retired.insert(owner); advance()
    }

    private func advance() {
        if revision == UInt64.max { exhausted = true } else { revision += 1 }
    }
}

/// Sealed to its original process admission and revision. Aliases share one
/// consumption. @unchecked Sendable is required for that single mutable bit:
/// consumed is read/written exclusively while its immutable admission's NSLock
/// is held (including rejection before any wrong-origin access). There is no
/// separately synchronized state and no escaping/async action.
nonisolated final class CaptureMediaResumeAuthorization: @unchecked Sendable {
    fileprivate let admission: CaptureMediaAdmission
    fileprivate let revision: UInt64
    fileprivate var consumed = false

    fileprivate init(admission: CaptureMediaAdmission, revision: UInt64) {
        self.admission = admission; self.revision = revision
    }

    @discardableResult
    func performIfCurrent(_ action: () throws -> Void) rethrows -> Bool {
        try admission.performIfCurrent(self, action: action)
    }
}
