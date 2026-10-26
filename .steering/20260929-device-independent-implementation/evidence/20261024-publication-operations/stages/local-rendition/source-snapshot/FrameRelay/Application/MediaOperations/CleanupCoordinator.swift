import Foundation

/// An explicit user command owns its fixed batch independently of a view. A
/// restored/unprocessed row is reported, never adopted as permission to unlink.
actor CleanupCoordinator {
    private let store: any OriginalStorePort & MediaOperationStorePort
    private let termination: any OriginalRemovalTerminationPort
    private let execution: any OriginalRemovalExecutionPort
    private var tasks: [MediaOperationID: Task<BackendOutcome<OriginalRemovalBatchRecord>, Never>] = [:]

    init(store: any OriginalStorePort & MediaOperationStorePort,
         termination: any OriginalRemovalTerminationPort, execution: any OriginalRemovalExecutionPort) {
        self.store = store; self.termination = termination; self.execution = execution
    }

    func start(_ batch: OriginalRemovalBatch) async -> BackendOutcome<OriginalRemovalBatchRecord> {
        guard batch.purpose == .cleanup else { return .notExecuted }
        do { try batch.validate() } catch { return .failed(.rejected) }
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
        for target in batch.targets {
            let quiescence: OriginalRemovalQuiescence
            switch await termination.stopForRemoval(target) {
            case .succeeded(let value) where value.target == target && value.transport.target == .original(target.original):
                quiescence = value
            case .failed(.unknownSchema), .failed(.corruptStore), .failed(.authenticationRequired): return .unknown
            default:
                guard await recordNonExecution(batch, target: target, reason: .terminationUnconfirmed) else { return .unknown }
                continue
            }
            guard case .loaded(let proofs) = await store.load() else { return .unknown }
            guard let selection = selectEvidence(target.original, snapshot: proofs) else {
                guard await recordNonExecution(batch, target: target, reason: .ineligible) else { return .unknown }
                continue
            }
            let result = await execution.removeOriginal(batch: batch, target: target, evidence: selection, quiescence: quiescence)
            switch result {
            case .succeeded: break
            case .notExecuted:
                guard await recordNonExecution(batch, target: target, reason: .ineligible) else { return .unknown }
            case .failed(.contentMismatch), .failed(.inaccessible):
                // A file-specific failure cannot silently stop independent
                // targets. The common writer must still prove the exact pending
                // child; uncertainty about the store itself stops this batch.
                guard case .succeeded(let current) = await store.loadOriginalState(),
                      let exact = current.removalBatches.first(where: { $0.batch == batch }),
                      exact.targets.contains(where: { $0.target == target && $0.status == .reserved(batch.intent(for: target)) }) else {
                    return .unknown
                }
                let failure: BackendFailure = result == .failed(.contentMismatch) ? .contentMismatch : .inaccessible
                guard await persist(.removalIssue(batch: batch.operation, target: target, failure: failure),
                    operation: .init(rawValue: UUID().uuidString)) else { return .unknown }
                continue
            default: return .unknown
            }
        }
        guard case .succeeded(let latest) = await store.loadOriginalState(),
              let record = latest.removalBatches.first(where: { $0.batch == batch }) else { return .unknown }
        return .succeeded(record)
    }

    /// This selects commands; the single writer re-evaluates every eligibility
    /// predicate, supported proof schema and invalidation at reservation time.
    private func selectEvidence(_ original: OriginalContent, snapshot: BackendStoreSnapshot) -> CleanupEvidenceSelection? {
        for state in snapshot.confirmationStates where state.current.original == original {
            guard let confirmation = state.validConfirmation,
                  snapshot.registrations.last(where: { $0.server.registration.destination == state.registration.destination })?
                    .server.registration == state.registration,
                  let verification = snapshot.verifications.last(where: {
                      $0.expected.target == .original(original) && $0.expected.registration.destination == state.registration.destination
                  }) else { continue }
            return .init(registration: state.registration, verificationCommand: verification.command,
                         confirmationOperation: confirmation.intent.operation)
        }
        return nil
    }

    private func recordNonExecution(_ batch: OriginalRemovalBatch, target: OriginalRemovalTarget,
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
