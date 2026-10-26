import Foundation

nonisolated struct LibraryRemovalOperation: Equatable, Sendable, Identifiable {
    let batch: MediaOperationID
    let purpose: RemovalPurpose
    let target: OriginalRemovalTarget
    let status: OriginalRemovalTargetStatus
    let failure: BackendFailure?
    var id: MediaOperationID { target.operation }
    var action: LibraryAction { purpose == .cleanup ? .cleanup : .discard }
}

nonisolated protocol LibraryRemovalReconciliationPort: Sendable {
    func reconcile(_ operation: LibraryRemovalOperation) async -> BackendOutcome<OriginalRemovalBatchRecord>
}

@MainActor final class LibraryRemovalCommands: LibraryCommandPort, LibraryRemovalReconciliationPort {
    private let base: any LibraryCommandPort
    private let reader: any LibraryReadPort
    private let store: any OriginalStorePort
    private let discard: DiscardCoordinator
    private let cleanup: CleanupCoordinator?
    private let execution: any OriginalRemovalExecutionPort
    private let termination: ProductRemovalTermination
    private let admission: @MainActor @Sendable () -> Bool
    private var pending: [MediaOperationID: OriginalRemovalBatch] = [:]

    init(base: any LibraryCommandPort, reader: any LibraryReadPort, store: any OriginalStorePort,
         discard: DiscardCoordinator, cleanup: CleanupCoordinator? = nil,
         execution: any OriginalRemovalExecutionPort, termination: ProductRemovalTermination,
         admission: @escaping @MainActor @Sendable () -> Bool) {
        self.base = base; self.reader = reader; self.store = store; self.discard = discard
        self.cleanup = cleanup
        self.execution = execution; self.termination = termination; self.admission = admission
    }

    func availability(_ action: LibraryAction, items: [LibraryItem]) -> LibraryActionAvailability {
        guard action == .discard || action == .cleanup else { return base.availability(action, items: items) }
        guard admission() else { return .unavailable("録画と保存の終了後に操作してください。") }
        if action == .cleanup {
            guard cleanup != nil else { return .unavailable(action.unavailableReason) }
            guard !items.isEmpty, items.allSatisfy({ item in
                guard !item.isDiscardHistory, item.original != nil else { return false }
                if case .present = item.file { return true }; return false
            }) else { return .unavailable("原本があり、内容と保存記録の対応が確定した動画を選んでください。") }
            guard items.contains(where: { item in
                item.cleanupUnavailableReason == nil && item.removalUnavailableReason == nil
                    && item.original.map { termination.unavailableReason(original: $0) == nil } == true
            }) else {
                return .unavailable(items.first?.cleanupUnavailableReason ?? items.first?.removalUnavailableReason
                    ?? "保存検証・有効な明示確認と原本の使用終了を確認できる対象がありません。")
            }
            return .available
        }
        guard items.count == 1, let item = items.first, !item.isDiscardHistory else { return .unavailable("破棄は通常一覧の動画を1本ずつ選んでください。") }
        guard let original = item.original, case .present = item.file else { return .unavailable("原本の内容と保存記録の対応を確認できません。原本を保持しています。") }
        if let reason = item.removalUnavailableReason ?? termination.unavailableReason(original: original) { return .unavailable(reason) }
        return .available
    }

    @MainActor func submit(_ request: LibraryCommandRequest) async -> LibraryCommandResponse {
        guard request.action == .discard || request.action == .cleanup else { return await base.submit(request) }
        guard !request.targets.isEmpty,
              Set(request.targets.map(\.capture)).count == request.targets.count,
              Set(request.targets.map(\.reference)).count == request.targets.count,
              request.targets.allSatisfy({ $0.original?.capture == $0.capture }),
              (request.action == .discard ? request.targets.count == 1 && request.discardRiskAcknowledged
                : cleanup != nil && !request.discardRiskAcknowledged) else {
            return .rejected("容量整理の対象、または1本ずつの破棄対象と消失リスクを確認してください。")
        }
        guard case .succeeded(let current) = await store.loadOriginalState() else { return .unknown }
        if let existing = current.removalBatches.first(where: { $0.batch.operation == request.id }) {
            guard matches(existing.batch, request) else { return .rejected("同じ操作IDの対象または確認内容が異なります。") }
            return await termination.finish(existing) ? .accepted : .unknown
        }
        if let retained = pending[request.id] {
            return matches(retained, request) ? .unknown : .rejected("同じ操作IDの対象が異なります。")
        }
        guard case .loaded(let library) = await reader.loadLibrary() else { return .unknown }
        let items = request.targets.compactMap { fixed in library.recordings.first(where: {
            $0.id == fixed.capture && $0.recording.intent.original == fixed.reference && $0.original == fixed.original
        }) }
        guard items.count == request.targets.count,
              availability(request.action, items: items) == .available else {
            return .rejected("確認した対象の内容または状態が変わりました。再読み込みして対象と消失リスクを確認し直してください。")
        }
        let targets = request.targets.compactMap { fixed -> OriginalRemovalTarget? in
            guard let original = fixed.original else { return nil }
            return .init(original: original, reference: fixed.reference, operation: .init(rawValue: UUID().uuidString))
        }
        guard let first = targets.first,
              let batch = try? OriginalRemovalBatch(operation: request.id,
                purpose: request.action == .cleanup ? .cleanup : .discard, targets: targets,
                authorization: request.action == .cleanup ? .cleanup : .discardRiskAcknowledged(first)) else {
            return .rejected("対象の確認内容を保存できません。")
        }
        pending[request.id] = batch
        let result: BackendOutcome<OriginalRemovalBatchRecord>
        if request.action == .cleanup, let cleanup { result = await cleanup.start(batch) }
        else { result = await discard.start(batch) }
        switch result {
        case .succeeded(let record):
            return await termination.finish(record) ? .accepted : .unknown
        case .failed(.rejected), .notExecuted: return .rejected("対象の状態を確認できません。保存記録を再読み込みしてください。")
        default: return .unknown
        }
    }

    @MainActor func reconcile(_ operation: LibraryRemovalOperation) async -> BackendOutcome<OriginalRemovalBatchRecord> {
        guard admission(), case .succeeded(let snapshot) = await store.loadOriginalState(),
              let record = snapshot.removalBatches.first(where: { $0.batch.operation == operation.batch }),
              record.batch.purpose == operation.purpose,
              let row = record.targets.first(where: { $0.target == operation.target }), row.status == operation.status else { return .notExecuted }
        switch row.status {
        case .reserved(let intent):
            let observed = await execution.observeRemoval(intent)
            guard case .succeeded = observed else { return .unknown }
        case .unprocessed:
            // Explicit result-check only: the atomic journal proves that this
            // child never acquired a physical-removal reservation.
            guard !snapshot.logicalOriginals.contains(where: {
                $0.removal?.operation == operation.id || $0.resolvedRemoval?.operation == operation.id
            }) else { return .unknown }
            let mutation = OriginalStoreMutation(operation: .init(rawValue: UUID().uuidString), expectedRevision: snapshot.revision,
                change: .removalNotExecuted(batch: operation.batch, target: operation.target, reason: .unavailable))
            switch await store.commitOriginal(mutation) {
            case .committed: break
            case .unavailable:
                guard case .succeeded = await store.lookupOriginalCommit(mutation) else { return .unknown }
            case .rejected: return .unknown
            }
        case .notExecuted, .resolved: break
        }
        guard case .succeeded(let latest) = await store.loadOriginalState(),
              let exact = latest.removalBatches.first(where: { $0.batch.operation == operation.batch }) else { return .unknown }
        return await termination.finish(exact) ? .succeeded(exact) : .unknown
    }

    private func matches(_ batch: OriginalRemovalBatch, _ request: LibraryCommandRequest) -> Bool {
        batch.operation == request.id
            && ((request.action == .cleanup && batch.purpose == .cleanup && batch.authorization == .cleanup && !request.discardRiskAcknowledged)
                || (request.action == .discard && batch.purpose == .discard && request.discardRiskAcknowledged
                    && batch.targets.count == 1 && batch.authorization == .discardRiskAcknowledged(batch.targets[0])))
            && batch.targets.map { LibraryCommandTarget(capture: $0.original.capture, reference: $0.reference, original: $0.original) } == request.targets
    }
}
