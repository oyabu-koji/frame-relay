extension MediaStoreProjection {
    nonisolated mutating func acceptRemovalBatch(_ batch: OriginalRemovalBatch, receipt: OriginalStoreCommitReceipt) throws {
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

    nonisolated mutating func removalNotExecuted(batch: MediaOperationID, target: OriginalRemovalTarget,
                                    reason: OriginalRemovalNonExecution) throws {
        guard let b = removalBatches.firstIndex(where: { $0.batch.operation == batch }),
              let t = removalBatches[b].targets.firstIndex(where: { $0.target == target }),
              removalBatches[b].targets[t].status == .unprocessed else { throw BackendContractError.wrongStage }
        removalBatches[b].targets[t].status = .notExecuted(reason)
    }

    nonisolated mutating func removalReserved(_ intent: RemovalIntent, binding: OriginalBinding?) throws {
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

    nonisolated mutating func removalIssue(batch: MediaOperationID, target: OriginalRemovalTarget, failure: BackendFailure) throws {
        guard failure == .contentMismatch || failure == .inaccessible,
              let b = removalBatches.firstIndex(where: { $0.batch.operation == batch }),
              let t = removalBatches[b].targets.firstIndex(where: { $0.target == target }),
              removalBatches[b].targets[t].status == .reserved(removalBatches[b].batch.intent(for: target)) else {
            throw BackendContractError.wrongStage
        }
        removalBatches[b].targets[t].failure = failure
    }

    nonisolated mutating func removalResolved(_ intent: RemovalIntent, resolution: RemovalResolution) throws {
        for b in removalBatches.indices {
            if let t = removalBatches[b].targets.firstIndex(where: { $0.target.operation == intent.operation }) {
                guard removalBatches[b].targets[t].status == .reserved(intent) else { throw BackendContractError.identityMismatch }
                removalBatches[b].targets[t].status = .resolved(resolution)
                removalBatches[b].targets[t].failure = nil
            }
        }
    }

    nonisolated func validatesRemovalBoundary(_ boundary: OriginalRemovalBoundary,
        revision: UInt64, epoch: ReaderReconciliationEpoch,
        transportInventory: OriginalRemovalTransportInventory? = nil,
        backend: BackendStoreSnapshot? = nil) throws {
        if let fence = boundary.transportFence {
            guard PublicationStoreBoundary.exact(fence.seal.batch, boundary.batch.operation),
                  PublicationStoreBoundary.exact(fence.seal.target, boundary.target), !fence.seal.nonce.isEmpty,
                  fence.inventory.epoch == epoch, let transportInventory, fence.inventory == transportInventory,
                  let backend, fence.validatesHistory(backend) else { throw BackendContractError.deletionUnresolved }
        } else {
            // Legacy/test callers retain their exact whole-writer CAS fence.
            guard boundary.expectedRevision == revision else { throw BackendContractError.revisionConflict }
        }
        guard boundary.epoch == epoch,
              let batch = removalBatches.first(where: { PublicationStoreBoundary.exact($0.batch, boundary.batch) }),
              batch.batch.intent(for: boundary.target) == boundary.intent,
              batch.targets.contains(where: { PublicationStoreBoundary.exact($0.target, boundary.target) && $0.status == .reserved(boundary.intent) }),
              let state = originals.first(where: { PublicationStoreBoundary.exact($0.original, boundary.target.original) }),
              PublicationStoreBoundary.exact(state.binding?.reference, Optional(boundary.target.reference)),
              PublicationStoreBoundary.exact(state.removal, Optional(boundary.intent)),
              state.invalidation == nil, state.invalidationGeneration == boundary.expectedInvalidation,
              state.accessGeneration == boundary.expectedAccess, state.readersReleased(in: epoch) else {
            throw BackendContractError.deletionUnresolved
        }
    }
}

extension RecordingStoreDocument {
    /// No new persistent schema: this is a filtered view of the existing
    /// immutable journal. Related history detects mutations even after ABA.
    nonisolated func removalTransportInventory(_ original: OriginalContent, epoch: ReaderReconciliationEpoch,
        projection: MediaStoreProjection) throws -> OriginalRemovalTransportInventory {
        guard projection.originals.contains(where: { PublicationStoreBoundary.exact($0.original, original) }) else {
            throw BackendContractError.identityMismatch
        }
        let requests = projection.requests.filter { $0.target.original == original }
        let tasks = projection.backgroundTasks.filter { $0.intent.context.target.original == original }
        let verifications = projection.verifications.filter { $0.expected.target.original == original }
        let destinations = requests.map(\.registration.destination) + tasks.map(\.intent.context.registration.destination)
            + verifications.map(\.expected.registration.destination)
        let registrations = projection.registrations.filter { registration in
            destinations.contains { PublicationStoreBoundary.exact($0, registration.server.registration.destination) }
        }
        let facts = backendJournal.compactMap { entry -> OriginalRemovalTransportJournalFact? in
            let related: Bool
            switch entry.mutation.change {
            case .request(_, let value): related = value.target.original == original
            case .requestTransition(_, _, let target, _, _): related = target.original == original
            case .personControl(let plan):
                related = plan.children.contains { PublicationStoreBoundary.exact($0.target.target.original, original) }
            case .originalUploadAcceptance(let plan):
                related = plan.request.targets.contains { PublicationStoreBoundary.exact($0.binding.original, original) }
            case .uploadMetadata(let value): related = PublicationStoreBoundary.exact(value.request.original, original)
            case .backgroundTask(_, let value): related = value.intent.context.target.original == original
            case .verification(_, let expected, _): related = expected.target.original == original
            case .batch(let value): related = value.fixedTargets.contains(original)
            case .registrationIntent(let value): related = destinations.contains { PublicationStoreBoundary.exact($0, value.destination) }
            case .registration(let value): related = destinations.contains { PublicationStoreBoundary.exact($0, value.registration.destination) }
            default: related = false
            }
            return related ? .init(mutation: entry.mutation, commit: entry.receipt) : nil
        }
        return .init(original: original, epoch: epoch, storeIdentity: storeIdentity, requests: requests, tasks: tasks,
            verifications: verifications, registrations: registrations, journal: facts)
    }
}
