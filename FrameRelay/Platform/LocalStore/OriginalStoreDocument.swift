import Foundation

nonisolated struct OriginalStoreJournalEntry: Codable {
    let mutation: OriginalStoreMutation
    let receipt: OriginalStoreCommitReceipt
    /// Writer-adopted schema at that commit, not today's supported set.
    var acceptedVerificationSchema: String? = nil
}

extension RecordingStoreDocument {
    nonisolated mutating func applyOriginal(_ mutation: OriginalStoreMutation,
        supportedVerificationSchemas: Set<String> = [],
        reconciliationEpoch: ReaderReconciliationEpoch? = nil) throws -> OriginalStoreCommitReceipt {
        if let previous = originalJournal.first(where: { $0.mutation.operation == mutation.operation }) {
            guard previous.mutation == mutation else { throw BackendContractError.identityMismatch }
            return previous.receipt
        }
        guard mutation.expectedRevision == transactionRevision, transactionRevision < UInt64.max else {
            throw BackendContractError.revisionConflict
        }
        var acceptedSchema: String?
        if case .reconcileMedia(let observation) = mutation.change {
            guard observation.epoch == reconciliationEpoch else { throw BackendContractError.staleGeneration }
        }
        switch mutation.change {
        case .reserveCleanup(let intent, _, _, _), .reserveRemoval(let intent, _, _):
            guard try replayStore().originals.first(where: { $0.original == intent.original })?
                .readersReleased(in: reconciliationEpoch) == true else { throw BackendContractError.readersActive }
        default: break
        }
        if case .reserveCleanup(let intent, let selection, _, _) = mutation.change {
            acceptedSchema = try replayStore().cleanupSchema(original: intent.original, selection: selection)
            guard let acceptedSchema, supportedVerificationSchemas.contains(acceptedSchema) else {
                throw BackendContractError.unsupportedVersion
            }
        }
        let receipt = OriginalStoreCommitReceipt(operation: mutation.operation,
            previousRevision: transactionRevision, committedRevision: transactionRevision + 1)
        originalJournal.append(.init(mutation: mutation, receipt: receipt,
                                     acceptedVerificationSchema: acceptedSchema))
        transactionRevision += 1
        try validate()
        return receipt
    }

    nonisolated func replayOriginals() throws -> [OriginalPersistentState] {
        try replayStore().originals.compactMap(\.localProjection)
    }

    nonisolated func applyOriginalChange(_ entry: OriginalStoreJournalEntry,
                                         projection: inout MediaStoreProjection) throws {
        let legacy = entry.receipt.committedRevision <= legacyRevision
        if legacy {
            guard entry.acceptedVerificationSchema == nil else { throw BackendContractError.invalidValue }
            switch entry.mutation.change {
            case .acquireMedia, .releaseMedia, .reconcileMedia, .reserveCleanup:
                throw BackendContractError.invalidValue
            default: break
            }
        }
        if case .bind(let binding) = entry.mutation.change {
            try validateBinding(binding)
            guard !projection.originals.contains(where: { $0.binding?.reference == binding.reference }) else {
                throw BackendContractError.identityMismatch
            }
            let index = try projection.ensureOriginal(binding.original)
            guard projection.originals[index].binding == nil else { throw BackendContractError.identityMismatch }
            projection.originals[index].binding = binding
            projection.originals[index].bindingCommit = entry.receipt
            return
        }
        let original: OriginalContent
        switch entry.mutation.change {
        case .bind: throw BackendContractError.wrongStage
        case .acquire(let lease), .release(let lease): original = lease.original
        case .reserveRemoval(let intent, _, _), .resolveRemoval(let intent, _),
             .reserveCleanup(let intent, _, _, _): original = intent.original
        case .reserveInvalidation(let value): original = value.rendition.original
        case .acquireMedia(let lease), .releaseMedia(let lease): original = lease.target.original
        case .reconcileMedia(let value): original = value.original
        }
        guard let index = projection.originals.firstIndex(where: { $0.original == original }) else {
            throw BackendContractError.identityMismatch
        }
        var state = projection.originals[index]
        switch entry.mutation.change {
        case .bind: break
        case .acquire(let lease):
            try MediaStoredValueValidation.lease(lease)
            guard state.binding != nil, state.removal == nil, state.invalidation == nil,
                  state.removalResolution != .removed else { throw BackendContractError.deletionUnresolved }
            try requireNextAccess(lease.accessGeneration, state: state)
            guard !state.readers.contains(where: { $0.id == lease.id }),
                  !state.mediaReaders.contains(where: { $0.id == lease.id }) else { throw BackendContractError.identityMismatch }
            state.accessGeneration = lease.accessGeneration
            state.mediaReconciliation = nil
            state.readers.append(lease)
        case .release(let lease):
            guard let reader = state.readers.firstIndex(of: lease) else { throw BackendContractError.identityMismatch }
            state.readers.remove(at: reader)
        case .acquireMedia(let lease):
            try MediaStoredValueValidation.mediaLease(lease)
            try projection.requireCurrentRegistration(lease.registration)
            guard state.removal == nil, state.invalidation == nil else { throw BackendContractError.deletionUnresolved }
            try requireNextAccess(lease.accessGeneration, state: state)
            guard !state.readers.contains(where: { $0.id == lease.id }),
                  !state.mediaReaders.contains(where: { $0.id == lease.id }) else { throw BackendContractError.identityMismatch }
            switch lease.target {
            case .rendition(let rendition):
                guard let current = projection.confirmationState(original: original, registration: lease.registration),
                      current.current == rendition, !current.invalidatedRenditions.contains(rendition.rendition) else {
                    throw BackendContractError.identityMismatch
                }
            case .original:
                guard state.binding?.saveRecord.result == .saved,
                      state.removalResolution != .removed else { throw BackendContractError.ineligibleOriginal }
            }
            state.accessGeneration = lease.accessGeneration
            state.requiresMediaReconciliation = true
            state.mediaReconciliation = nil
            state.mediaReaders.append(lease)
            projection.mediaUses.append(lease)
        case .releaseMedia(let lease):
            guard let reader = state.mediaReaders.firstIndex(of: lease) else { throw BackendContractError.identityMismatch }
            state.mediaReaders.remove(at: reader)
        case .reconcileMedia(let observation):
            try MediaStoredValueValidation.text(observation.epoch.rawValue)
            guard observation.accessGeneration == state.accessGeneration, state.readers.isEmpty,
                  state.mediaReaders.isEmpty,
                  Set(observation.observations.keys) == Set(MediaReaderOwner.allCases) else {
                throw BackendContractError.readersActive
            }
            for evidence in observation.observations.values { try MediaStoredValueValidation.text(evidence.rawValue) }
            state.mediaReconciliation = observation
        case .reserveRemoval(let intent, let invalidation, let access):
            if !legacy, intent.purpose == .cleanup { throw BackendContractError.ineligibleOriginal }
            try reserveRemoval(intent, invalidation: invalidation, access: access, legacy: legacy, state: &state)
        case .reserveCleanup(let intent, let selection, let invalidation, let access):
            guard !legacy, intent.purpose == .cleanup,
                  entry.acceptedVerificationSchema == (try projection.cleanupSchema(original: original, selection: selection)) else {
                throw BackendContractError.ineligibleOriginal
            }
            try reserveRemoval(intent, invalidation: invalidation, access: access, legacy: false, state: &state)
        case .resolveRemoval(let intent, let resolution):
            guard state.removal == intent else { throw BackendContractError.identityMismatch }
            state.removal = nil
            state.resolvedRemoval = intent
            state.removalResolution = resolution
        case .reserveInvalidation(let invalidation):
            try MediaStoredValueValidation.invalidation(invalidation.record)
            if !legacy {
                try projection.requireCurrentRegistration(invalidation.registration)
                guard let current = projection.confirmationState(original: original, registration: invalidation.registration),
                      current.current == invalidation.rendition,
                      invalidation.generation.rawValue > current.generation.rawValue else {
                    throw BackendContractError.staleGeneration
                }
            }
            guard state.removal == nil, state.invalidation == nil else { throw BackendContractError.deletionUnresolved }
            guard invalidation.generation.rawValue > state.invalidationGeneration.rawValue else {
                throw BackendContractError.staleGeneration
            }
            state.invalidation = invalidation
        }
        projection.originals[index] = state
    }

    nonisolated private func requireNextAccess(_ generation: AccessGeneration, state: LogicalOriginalState) throws {
        guard state.accessGeneration.rawValue < UInt64.max,
              generation.rawValue == state.accessGeneration.rawValue + 1 else { throw BackendContractError.staleGeneration }
    }

    nonisolated private func reserveRemoval(_ intent: RemovalIntent, invalidation: InvalidationGeneration,
        access: AccessGeneration, legacy: Bool, state: inout LogicalOriginalState) throws {
        try MediaStoredValueValidation.text(intent.operation.rawValue)
        guard state.binding != nil, state.removal == nil, state.invalidation == nil,
              state.removalResolution != .removed else { throw BackendContractError.deletionUnresolved }
        guard state.readers.isEmpty, state.accessGeneration == access,
              legacy || state.readersReleased else { throw BackendContractError.readersActive }
        guard state.invalidationGeneration == invalidation else { throw BackendContractError.staleGeneration }
        state.removal = intent
        state.resolvedRemoval = nil
        state.removalResolution = nil
    }

    nonisolated func validateBinding(_ binding: OriginalBinding) throws {
        try Self.validateBoundContent(binding.original.content)
        guard binding.original.generation.rawValue > 0,
              binding.original.capture == binding.saveRecord.intent.context.capture,
              binding.reference == binding.saveRecord.intent.original,
              binding.original.content.byteCount == binding.saveRecord.file.byteCount,
              binding.saveRecord.end.writer != .notStarted,
              let saved = entries.first(where: { $0.intent.context.capture == binding.original.capture }),
              saved.result == binding.saveRecord, saved.resultToken == binding.saveCommit.token,
              saved.revision == binding.saveCommit.committedRevision,
              binding.saveCommit.matches(binding.saveCommit.token, revision: 1) else {
            throw BackendContractError.identityMismatch
        }
    }

    nonisolated static func validateBoundContent(_ content: ContentIdentity) throws {
        guard content.byteCount > 0, content.algorithm == "sha256", content.digest.utf8.count == 64,
              content.digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw BackendContractError.invalidValue
        }
    }
}
