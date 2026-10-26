extension MediaStoreProjection {
    mutating func acceptRemovalBatch(_ batch: OriginalRemovalBatch, receipt: OriginalStoreCommitReceipt) throws {
        try batch.validate()
        try MediaStoredValueValidation.text(batch.operation.rawValue)
        guard receipt.operation == batch.operation,
              !removalBatches.contains(where: { $0.batch.operation == batch.operation }),
              batch.targets.allSatisfy({ target in
                  !removalChildOperations.contains(target.operation)
                    && !removalBatches.contains(where: { $0.batch.operation == target.operation })
              }),
              !removalBatches.flatMap(\.targets).contains(where: { $0.target.operation == batch.operation }),
              !removalBatches.flatMap(\.targets).contains(where: { previous in
                  batch.targets.contains(where: { $0.operation == previous.target.operation })
              }) else { throw BackendContractError.identityMismatch }
        for target in batch.targets {
            try MediaStoredValueValidation.text(target.operation.rawValue)
            try ExplorationRunDirectory.validateReference(target.reference)
            try MediaStoredValueValidation.original(target.original)
            guard let binding = originals.first(where: { $0.original == target.original })?.binding,
                  binding.reference == target.reference else { throw BackendContractError.identityMismatch }
        }
        removalBatches.append(.init(batch: batch, commit: receipt,
            targets: batch.targets.map { .init(target: $0) }))
    }

    mutating func removalNotExecuted(batch: MediaOperationID, target: OriginalRemovalTarget,
                                    reason: OriginalRemovalNonExecution) throws {
        guard let b = removalBatches.firstIndex(where: { $0.batch.operation == batch }),
              let t = removalBatches[b].targets.firstIndex(where: { $0.target == target }),
              removalBatches[b].targets[t].status == .unprocessed else { throw BackendContractError.wrongStage }
        removalBatches[b].targets[t].status = .notExecuted(reason)
    }

    mutating func removalReserved(_ intent: RemovalIntent, binding: OriginalBinding?) throws {
        let matches = removalBatches.indices.filter { b in
            removalBatches[b].targets.contains(where: { $0.target.operation == intent.operation })
        }
        guard let b = matches.first else {
            removalChildOperations.insert(intent.operation)
            return // Historical single-intent journal remains readable.
        }
        guard !removalChildOperations.contains(intent.operation), matches.count == 1,
              let t = removalBatches[b].targets.firstIndex(where: { $0.target.operation == intent.operation }),
              let binding, removalBatches[b].targets[t].target.reference == binding.reference,
              removalBatches[b].batch.intent(for: removalBatches[b].targets[t].target) == intent,
              removalBatches[b].targets[t].status == .unprocessed else { throw BackendContractError.identityMismatch }
        removalBatches[b].targets[t].status = .reserved(intent)
        removalChildOperations.insert(intent.operation)
    }

    mutating func removalIssue(batch: MediaOperationID, target: OriginalRemovalTarget, failure: BackendFailure) throws {
        guard failure == .contentMismatch || failure == .inaccessible,
              let b = removalBatches.firstIndex(where: { $0.batch.operation == batch }),
              let t = removalBatches[b].targets.firstIndex(where: { $0.target == target }),
              removalBatches[b].targets[t].status == .reserved(removalBatches[b].batch.intent(for: target)) else {
            throw BackendContractError.wrongStage
        }
        removalBatches[b].targets[t].failure = failure
    }

    mutating func removalResolved(_ intent: RemovalIntent, resolution: RemovalResolution) throws {
        for b in removalBatches.indices {
            if let t = removalBatches[b].targets.firstIndex(where: { $0.target.operation == intent.operation }) {
                guard removalBatches[b].targets[t].status == .reserved(intent) else { throw BackendContractError.identityMismatch }
                removalBatches[b].targets[t].status = .resolved(resolution)
                removalBatches[b].targets[t].failure = nil
            }
        }
    }

    func validatesRemovalBoundary(_ boundary: OriginalRemovalBoundary,
        revision: UInt64, epoch: ReaderReconciliationEpoch) throws {
        guard boundary.expectedRevision == revision, boundary.epoch == epoch,
              let batch = removalBatches.first(where: { $0.batch == boundary.batch }),
              batch.batch.intent(for: boundary.target) == boundary.intent,
              batch.targets.contains(where: { $0.target == boundary.target && $0.status == .reserved(boundary.intent) }),
              let state = originals.first(where: { $0.original == boundary.target.original }),
              state.binding?.reference == boundary.target.reference, state.removal == boundary.intent,
              state.invalidation == nil, state.invalidationGeneration == boundary.expectedInvalidation,
              state.accessGeneration == boundary.expectedAccess, state.readersReleased(in: epoch) else {
            throw BackendContractError.deletionUnresolved
        }
    }
}
