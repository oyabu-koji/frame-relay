import Foundation

/// A single explicit discard, independent of backup/verification/confirmation.
/// Its durable risk acknowledgement never authorizes a restored automatic retry.
actor DiscardCoordinator {
    private let store: any OriginalStorePort
    private let termination: any OriginalRemovalTerminationPort
    private let execution: any OriginalRemovalExecutionPort
    private var tasks: [MediaOperationID: Task<BackendOutcome<OriginalRemovalBatchRecord>, Never>] = [:]

    init(store: any OriginalStorePort, termination: any OriginalRemovalTerminationPort,
         execution: any OriginalRemovalExecutionPort) {
        self.store = store; self.termination = termination; self.execution = execution
    }

    func start(_ batch: OriginalRemovalBatch) async -> BackendOutcome<OriginalRemovalBatchRecord> {
        guard batch.purpose == .discard else { return .notExecuted }
        do { try batch.validate() } catch { return .failed(.rejected) }
        guard batch.targets.count == 1,
              batch.authorization == .discardRiskAcknowledged(batch.targets[0]) else { return .failed(.rejected) }
        guard tasks[batch.operation] == nil else { return .inProgress }
        let task = Task { await self.perform(batch) }
        tasks[batch.operation] = task
        return await task.value
    }

    private func perform(_ batch: OriginalRemovalBatch) async -> BackendOutcome<OriginalRemovalBatchRecord> {
        defer { tasks.removeValue(forKey: batch.operation) }
        guard case .succeeded(let initial) = await store.loadOriginalState() else { return .unknown }
        if let existing = initial.removalBatches.first(where: { $0.batch.operation == batch.operation }) {
            return existing.batch == batch ? .succeeded(existing) : .failed(.rejected)
        }
        guard await persist(.removalBatch(batch), operation: batch.operation) else { return .unknown }
        let target = batch.targets[0]
        let quiescence: OriginalRemovalQuiescence
        switch await termination.stopForRemoval(target) {
        case .succeeded(let value) where value.target == target && value.transport.target == .original(target.original):
            quiescence = value
        case .failed(.unknownSchema), .failed(.corruptStore), .failed(.authenticationRequired): return .unknown
        default:
            guard await notExecuted(batch, target: target, reason: .terminationUnconfirmed) else { return .unknown }
            return await record(batch)
        }
        let result = await execution.removeOriginal(batch: batch, target: target, evidence: nil, quiescence: quiescence)
        switch result {
        case .succeeded: break
        case .notExecuted:
            guard await notExecuted(batch, target: target, reason: .ineligible) else { return .unknown }
        case .failed(.contentMismatch), .failed(.inaccessible):
            guard case .succeeded(let current) = await store.loadOriginalState(),
                  let exact = current.removalBatches.first(where: { $0.batch == batch }),
                  exact.targets.contains(where: { $0.target == target && $0.status == .reserved(batch.intent(for: target)) }) else {
                return .unknown
            }
            let failure: BackendFailure = result == .failed(.contentMismatch) ? .contentMismatch : .inaccessible
            guard await persist(.removalIssue(batch: batch.operation, target: target, failure: failure),
                operation: .init(rawValue: UUID().uuidString)) else { return .unknown }
        default: return .unknown
        }
        return await record(batch)
    }

    private func record(_ batch: OriginalRemovalBatch) async -> BackendOutcome<OriginalRemovalBatchRecord> {
        guard case .succeeded(let snapshot) = await store.loadOriginalState(),
              let result = snapshot.removalBatches.first(where: { $0.batch == batch }) else { return .unknown }
        return .succeeded(result)
    }

    private func notExecuted(_ batch: OriginalRemovalBatch, target: OriginalRemovalTarget,
                             reason: OriginalRemovalNonExecution) async -> Bool {
        await persist(.removalNotExecuted(batch: batch.operation, target: target, reason: reason),
                      operation: .init(rawValue: UUID().uuidString))
    }

    private func persist(_ change: OriginalStoreChange, operation: MediaOperationID) async -> Bool {
        for _ in 0..<3 {
            guard case .succeeded(let snapshot) = await store.loadOriginalState() else { return false }
            let mutation = OriginalStoreMutation(operation: operation, expectedRevision: snapshot.revision, change: change)
            switch await store.commitOriginal(mutation) {
            case .committed: return true
            case .rejected(.revisionConflict): continue
            case .unavailable:
                if case .succeeded = await store.lookupOriginalCommit(mutation) { return true }
                return false
            case .rejected: return false
            }
        }
        return false
    }
}
