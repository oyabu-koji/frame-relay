import Foundation

extension MediaStoreProjection {
    /// Checks only the new reserved namespace; historical commands keep their
    /// original validation and replay semantics before the first person plan.
    nonisolated func requirePersonControlNamespace(_ change: BackendStoreChange) throws {
        var commands = [change.key.commandText]
        // A batch introduces child operations before those children emit their
        // own commands. Existing-target references (beginChild, notProcessed,
        // requestTransition) introduce only their outer command here.
        switch change {
        case .batch(let batch): commands += batch.requests.map { $0.operation.rawValue }
        case .request(_, let request): commands.append(request.operation.rawValue)
        case .photoBatch(_, .accept(let batch)):
            commands.append(batch.operation.rawValue)
            commands += batch.targets.map { $0.operation.rawValue }
        default: break
        }
        for stored in personControls {
            guard !commands.contains(stored.plan.parent.rawValue),
                  !stored.plan.children.contains(where: { commands.contains($0.command.rawValue) }) else {
                throw BackendContractError.identityMismatch
            }
        }
        guard case .personControl(let plan) = change else { return }
        let ids = [plan.parent] + plan.children.map(\.command)
        for id in ids {
            for b in photoSaveBatches.indices {
                guard photoSaveBatches[b].batch.operation != id else { throw BackendContractError.identityMismatch }
                for t in photoSaveBatches[b].targets.indices {
                    guard photoSaveBatches[b].targets[t].target.operation != id else { throw BackendContractError.identityMismatch }
                }
            }
            guard !backendCommands.contains(id.rawValue),
                  !requests.contains(where: { $0.operation == id }),
                  !personControls.contains(where: { stored in
                      stored.plan.parent == id || stored.plan.children.contains { $0.command == id }
                  }) else { throw BackendContractError.identityMismatch }
        }
    }

    nonisolated mutating func applyPersonControl(_ plan: MediaPersonControlPlan,
        receipt: BackendCommitReceipt, expectedStoreIdentity: RegistrationStoreIdentity?) throws {
        try MediaStoredValueValidation.personControl(plan)
        guard expectedStoreIdentity == plan.storeIdentity,
              receipt.matches(.personControl(plan.parent), revision: receipt.previousRevision),
              MediaPersonControlValueValidation.exact(receipt.key, BackendCommitKey.personControl(plan.parent)) else {
            throw BackendContractError.identityMismatch
        }
        var children: [MediaPersonControlChildRecord] = []
        for child in plan.children {
            let reason = personControlReason(child.target, action: plan.action)
            if let reason { children.append(.init(child: child, decision: .notProcessed(reason))); continue }
            guard let index = requests.firstIndex(where: { MediaPersonControlValueValidation.exact($0.operation, child.target.operation) }) else {
                throw BackendContractError.identityMismatch
            }
            try requests[index].apply(plan.action.transition)
            for b in batches.indices where batches[b].requests.contains(where: { $0.operation == child.target.operation }) {
                try batches[b].update(requests[index])
            }
            children.append(.init(child: child, decision: .recorded))
        }
        let value = StoredMediaPersonControlPlan(plan: plan, commit: receipt, children: children)
        guard value.isCommitted else { throw BackendContractError.notCommitted }
        personControls.append(value)
    }

    nonisolated private func personControlReason(_ target: MediaPersonControlTarget,
        action: MediaPersonControlAction) -> MediaPersonControlNonProcessing? {
        guard let request = requests.first(where: { $0.operation == target.operation }) else { return .missingRequest }
        guard target.matches(request) else { return .identityChanged }
        guard !request.playbackEnded else { return .playbackEnded }
        guard request.transport != .completed else { return .completed }
        if case .succeeded = request.remote { return .completed }
        guard request.intent != .cancelled else { return .cancelled }
        guard action == .resumeIntent else { return nil }
        guard request.intent == .paused else { return .notPaused }
        guard let registration = registrations.last(where: {
            $0.server.registration.destination == target.registration.destination
        }), registration.isCommitted,
            MediaPersonControlValueValidation.exact(registration.server.registration, target.registration) else { return .registrationChanged }
        let original = target.target.original
        guard let state = originals.first(where: { MediaPersonControlValueValidation.exact($0.original, original) }),
              !originals.contains(where: { $0.original.capture == original.capture && !MediaPersonControlValueValidation.exact($0.original, original) }),
              state.removal == nil, state.invalidation == nil, state.removalResolution != .removed else { return .targetUnavailable }
        if case .rendition(let rendition) = target.target {
            guard let current = confirmationStates.first(where: {
                MediaPersonControlValueValidation.exact($0.registration, target.registration)
                    && MediaPersonControlValueValidation.exact($0.current.original, original)
            }), MediaPersonControlValueValidation.exact(current.current, rendition),
                !current.invalidatedRenditions.contains(rendition.rendition) else { return .targetUnavailable }
        }
        return nil
    }
}
