import Foundation
@testable import FrameRelay

/// Faults wrap the real common writer; successful underlying commits still
/// reach disk. A hidden lookup simulates interruption before reconciliation.
@MainActor final class TemporaryMediaFaultStore: RecordingStorePort, OriginalStorePort, MediaOperationStorePort {
    enum Stage: Sendable { case acquire, release, reclaimed }
    let base: any MediaDiskStore
    private var stage: Stage?
    private var afterCommit = false
    init(base: any MediaDiskStore) { self.base = base }
    func configure(_ stage: Stage?, afterCommit: Bool = false) {
        self.stage = stage; self.afterCommit = afterCommit
    }
    func matches(_ mutation: BackendStoreMutation) -> Bool {
        guard case .temporary(_, let value) = mutation.change else { return false }
        switch (stage, value) {
        case (.acquire?, .acquire), (.release?, .release), (.reclaimed?, .reclaimed): return true
        default: return false
        }
    }
    @MainActor func commit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        guard matches(mutation) else { return await base.commit(mutation) }
        if afterCommit {
            let result = await base.commit(mutation)
            guard case .committed = result else { return result }
        }
        return .unknown
    }
    @MainActor func lookupCommit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        matches(mutation) ? .unknown : await base.lookupCommit(mutation)
    }
    func load() async -> BackendStoreLoadResult { await base.load() }
    func execute(_ command: RecordingStoreCommand) async -> RecordingStoreResult { await base.execute(command) }
    func loadUnfinished() async -> UnfinishedRecordingLoadResult { await base.loadUnfinished() }
    func loadRecordings() async -> RecordingStoreLoadResult { await base.loadRecordings() }
    func loadOriginalState() async -> BackendOutcome<OriginalStoreSnapshot> { await base.loadOriginalState() }
    func commitOriginal(_ mutation: OriginalStoreMutation) async -> OriginalStoreCommitResult { await base.commitOriginal(mutation) }
    func lookupInvalidation(_ acknowledgement: InvalidationAcknowledgement) async -> BackendOutcome<InvalidationID> {
        await base.lookupInvalidation(acknowledgement)
    }
}
