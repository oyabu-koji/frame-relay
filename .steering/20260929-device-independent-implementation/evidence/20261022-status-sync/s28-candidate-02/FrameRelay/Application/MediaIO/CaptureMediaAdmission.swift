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
