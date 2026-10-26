import Foundation

extension MediaStoreProjection {
    /// Only IDs introduced by this command are checked. References to a child
    /// operation in a transition/result do not introduce that operation again.
    nonisolated func requireOriginalUploadNamespace(_ change: BackendStoreChange) throws {
        var commands = [change.key.commandText]
        switch change {
        case .batch(let batch): commands += batch.requests.map { $0.operation.rawValue }
        case .request(_, let request): commands.append(request.operation.rawValue)
        case .photoBatch(_, .accept(let batch)):
            commands.append(batch.operation.rawValue); commands += batch.targets.map { $0.operation.rawValue }
        case .personControl(let plan): commands += plan.children.map { $0.command.rawValue }
        case .originalUploadAcceptance(let plan): commands += plan.request.targets.map { $0.operation.rawValue }
        default: break
        }
        for stored in originalUploadAcceptances {
            guard !commands.contains(stored.plan.request.parent.rawValue),
                  !stored.plan.request.targets.contains(where: { commands.contains($0.operation.rawValue) }) else {
                throw BackendContractError.identityMismatch
            }
        }
        guard case .originalUploadAcceptance(let plan) = change else { return }
        for id in [plan.request.parent] + plan.request.targets.map(\.operation) {
            guard !backendCommands.contains(id.rawValue), !requests.contains(where: { $0.operation == id }),
                  !personControls.contains(where: {
                      $0.plan.parent == id || $0.plan.children.contains(where: { $0.command == id })
                  }) else { throw BackendContractError.identityMismatch }
            for b in photoSaveBatches.indices {
                guard photoSaveBatches[b].batch.operation != id else { throw BackendContractError.identityMismatch }
                for t in photoSaveBatches[b].targets.indices {
                    guard photoSaveBatches[b].targets[t].target.operation != id else { throw BackendContractError.identityMismatch }
                }
            }
        }
    }

    nonisolated mutating func applyOriginalUploadAcceptance(_ plan: OriginalUploadAcceptancePlan,
        receipt: BackendCommitReceipt, expectedStoreIdentity: RegistrationStoreIdentity?) throws {
        try MediaStoredValueValidation.originalUploadAcceptance(plan)
        try requireOriginalUploadRegistration(plan.request.registration)
        guard expectedStoreIdentity == plan.request.storeIdentity,
              receipt.matches(.originalUploadAcceptance(plan.request.parent), revision: receipt.previousRevision),
              OriginalUploadAcceptanceValueValidation.exact(receipt.key, BackendCommitKey.originalUploadAcceptance(plan.request.parent)) else {
            throw BackendContractError.identityMismatch
        }
        var children: [OriginalUploadAcceptanceChild] = []
        for i in plan.request.targets.indices {
            let target = plan.request.targets[i], presence = plan.presences[i]
            if let reason = originalUploadReason(target, presence: presence, registration: plan.request.registration.server.registration) {
                children.append(.init(target: target, presence: presence, decision: .notProcessed(reason), initialRequest: nil))
            } else {
                var request = MediaRequest(operation: target.operation, target: .original(target.binding.original), purpose: .upload,
                    registration: plan.request.registration.server.registration, expectedStartRevision: receipt.previousRevision)
                try request.acceptOriginalUploadAcceptanceCommit(receipt, plan: plan)
                requests.append(request)
                children.append(.init(target: target, presence: presence, decision: .accepted, initialRequest: request))
            }
        }
        let record = StoredOriginalUploadAcceptance(plan: plan, children: children, commit: receipt,
            expectedStoreIdentity: plan.request.storeIdentity)
        guard record.isCommitted else { throw BackendContractError.notCommitted }
        // No legacy TransferBatch is derived: its .batch receipt has a different contract.
        originalUploadAcceptances.append(record)
    }

    nonisolated func requireOriginalUploadRegistration(_ registration: DeviceRegistration) throws {
        try OriginalUploadAcceptanceValueValidation.registration(registration)
        guard let current = registrations.last(where: {
            $0.server.registration.destination == registration.server.registration.destination
        }), current.isCommitted, OriginalUploadAcceptanceValueValidation.exact(current, registration),
            let intent = registrationIntents.first(where: { $0.intent.operation == current.server.intent.operation }),
            intent.isCommitted, OriginalUploadAcceptanceValueValidation.exact(intent.intent, current.server.intent),
            OriginalUploadAcceptanceValueValidation.exact(intent.commit, current.intentCommit) else {
            throw BackendContractError.identityMismatch
        }
    }

    /// Uses only event-ordered immutable bindings/requests and the frozen stat.
    /// Never reads today's recording projection or the filesystem during replay.
    nonisolated func originalUploadReason(_ target: OriginalUploadAcceptanceTarget,
        presence: OriginalUploadFilePresence, registration: RegistrationIdentity) -> OriginalUploadAcceptanceNonProcessing? {
        let original = target.binding.original
        guard let state = originals.first(where: { OriginalUploadAcceptanceValueValidation.exact($0.original, original) }),
              let binding = state.binding, state.bindingCommit != nil else { return .bindingUnavailable }
        guard !originals.contains(where: {
            $0.original.capture == original.capture && !OriginalUploadAcceptanceValueValidation.exact($0.original, original)
        }), OriginalUploadAcceptanceValueValidation.exact(binding, target.binding) else { return .bindingChanged }
        guard OriginalUploadAcceptanceValueValidation.savedBinding(binding) else { return .saveNotCompleted }
        guard state.removal == nil else { return .removalReserved }
        guard state.invalidation == nil else { return .invalidated }
        guard state.removalResolution != .removed else { return .removed }
        switch presence {
        case .missing: return .fileMissing
        case .inaccessible: return .fileInaccessible
        case .unknown: return .fileUnknown
        case .present(let bytes):
            guard bytes == original.content.byteCount, bytes == binding.saveRecord.file.byteCount else { return .byteCountMismatch }
        }
        if let previous = requests.first(where: {
            $0.purpose == .upload && $0.target.original == original && $0.registration == registration
        }) {
            return OriginalUploadAcceptanceValueValidation.exact(previous.target.original, original)
                && OriginalUploadAcceptanceValueValidation.exact(previous.registration, registration) ? .alreadyRequested : .bindingChanged
        }
        return nil
    }
}

extension OriginalUploadAcceptanceValueValidation {
    nonisolated static func savedBinding(_ binding: OriginalBinding) -> Bool {
        let record = binding.saveRecord, token = binding.saveCommit.token
        return record.result == .saved && record.end.writer != .notStarted
            && binding.original.generation.rawValue > 0
            && binding.original.content.byteCount == record.file.byteCount
            && exact(binding.original.capture, record.intent.context.capture)
            && exact(binding.reference, record.intent.original)
            && exact(record.file.context, record.intent.context) && exact(record.file.original, binding.reference)
            && exact(record.inspection.context, record.intent.context) && exact(record.inspection.original, binding.reference)
            && exact(token.context, record.intent.context) && exact(token.operation, record.intent.operation)
            && binding.saveCommit.matches(token, revision: 1)
    }
}

extension RecordingStoreDocument {
    /// A live new-commit check only. The existing capture result is immutable;
    /// historical decisions use the saved binding at their own journal position.
    nonisolated func requireOriginalUploadCurrentRecordings(_ plan: OriginalUploadAcceptancePlan,
        projection: MediaStoreProjection) throws {
        try projection.requireOriginalUploadRegistration(plan.request.registration)
        for i in plan.request.targets.indices {
            let target = plan.request.targets[i]
            guard projection.originalUploadReason(target, presence: plan.presences[i],
                registration: plan.request.registration.server.registration) == nil else { continue }
            let binding = target.binding
            guard let current = entries.first(where: {
                OriginalUploadAcceptanceValueValidation.exact($0.intent.context.capture, binding.original.capture)
            }), current.revision == 2,
                OriginalUploadAcceptanceValueValidation.exact(current.intent, binding.saveRecord.intent),
                OriginalUploadAcceptanceValueValidation.exact(current.result, Optional(binding.saveRecord)),
                OriginalUploadAcceptanceValueValidation.exact(current.resultToken, Optional(binding.saveCommit.token)),
                binding.saveCommit.matches(binding.saveCommit.token, revision: 1) else {
                throw BackendContractError.identityMismatch
            }
        }
    }
}
