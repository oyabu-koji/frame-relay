import Foundation

/// Common process admission, independent of deletion/invalidation seals. Empty
/// memory after restart is not evidence that persisted capture waits ended.
nonisolated final class CaptureMediaAdmission: PhotoSaveCaptureStartPort, @unchecked Sendable {
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
    private var observers: [UUID: AsyncStream<Snapshot>.Continuation] = [:]

    func changes() -> AsyncStream<Snapshot> {
        let pair = AsyncStream<Snapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        pair.continuation.onTermination = { [weak self] _ in self?.removeObserver(id) }
        lock.lock()
        observers[id] = pair.continuation
        let initial = Snapshot(revision: revision, owners: owners, exhausted: exhausted)
        lock.unlock()
        // Subscription is established before the initial wake. Notifications
        // may coalesce; consumers always obtain a fresh authorization/state.
        pair.continuation.yield(initial)
        return pair.stream
    }

    private func removeObserver(_ id: UUID) { lock.lock(); observers.removeValue(forKey: id); lock.unlock() }

    private func publish(_ value: Snapshot, to continuations: [AsyncStream<Snapshot>.Continuation]) {
        for continuation in continuations { continuation.yield(value) }
    }

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
        lock.lock()
        guard !phases.isEmpty, owners[owner] == nil, !retired.contains(owner) else { lock.unlock(); return }
        advance(); owners[owner] = phases
        let value = Snapshot(revision: revision, owners: owners, exhausted: exhausted), targets = Array(observers.values)
        lock.unlock(); publish(value, to: targets)
    }

    func update(_ owner: CaptureMediaOwner, phases: Set<CaptureMediaPhase>) {
        lock.lock()
        guard owners[owner] != nil, owners[owner] != phases, !phases.isEmpty else { lock.unlock(); return }
        advance(); owners[owner] = phases
        let value = Snapshot(revision: revision, owners: owners, exhausted: exhausted), targets = Array(observers.values)
        lock.unlock(); publish(value, to: targets)
    }

    func end(_ owner: CaptureMediaOwner) {
        lock.lock()
        guard owners.removeValue(forKey: owner) != nil else { lock.unlock(); return }
        retired.insert(owner); advance()
        let value = Snapshot(revision: revision, owners: owners, exhausted: exhausted), targets = Array(observers.values)
        lock.unlock(); publish(value, to: targets)
    }

    fileprivate func performPhotoStart(_ authorization: CaptureMediaResumeAuthorization,
                                       action: () -> Void) -> CapturePhotoStartAttempt {
        lock.lock(); defer { lock.unlock() }
        guard authorization.admission === self, !exhausted, !authorization.consumed else { return .refused }
        guard owners.isEmpty, revision == authorization.revision else { return .held }
        authorization.consumed = true
        action()
        return .performed
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

    func performPhotoStart(_ action: () -> Void) -> CapturePhotoStartAttempt {
        admission.performPhotoStart(self, action: action)
    }
}

nonisolated enum CapturePhotoStartAttempt: Equatable, Sendable { case performed, held, refused }
