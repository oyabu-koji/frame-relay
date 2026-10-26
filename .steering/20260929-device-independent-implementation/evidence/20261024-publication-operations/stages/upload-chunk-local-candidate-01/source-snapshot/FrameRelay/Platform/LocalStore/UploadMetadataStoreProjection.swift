import Foundation

extension MediaStoreProjection {
    /// Reserve both commands before I/O, including against nested commands in
    /// historical plans. Existing operation references are not introductions.
    nonisolated func requireUploadMetadataNamespace(_ change: BackendStoreChange) throws {
        var introduced = [change.key.commandText]
        switch change {
        case .batch(let batch): introduced += batch.requests.map { $0.operation.rawValue }
        case .request(_, let request): introduced.append(request.operation.rawValue)
        case .photoBatch(_, .accept(let batch)):
            introduced.append(batch.operation.rawValue); introduced += batch.targets.map { $0.operation.rawValue }
        case .personControl(let plan): introduced += plan.children.map { $0.command.rawValue }
        case .originalUploadAcceptance(let plan): introduced += plan.request.targets.map { $0.operation.rawValue }
        case .uploadMetadata(.beginQuery(let query)): introduced.append(query.observationCommand.rawValue)
        default: break
        }
        for old in uploadMetadataQueries {
            for id in [old.query.id, old.query.observationCommand] where introduced.contains(id.rawValue) {
                guard case .uploadMetadata(.observe(let observation)) = change,
                      UploadMetadataValidation.exact(id, old.query.observationCommand),
                      UploadMetadataValidation.exact(observation.command, id),
                      UploadMetadataValidation.exact(observation.query, old) else { throw BackendContractError.identityMismatch }
            }
        }
        guard case .uploadMetadata(.beginQuery(let query)) = change else { return }
        for id in [query.id, query.observationCommand] {
            guard !backendCommands.contains(id.rawValue), !requests.contains(where: { $0.operation == id }),
                  !batches.contains(where: { $0.requests.contains { $0.operation == id } }),
                  !personControls.contains(where: { $0.plan.parent == id || $0.plan.children.contains { $0.command == id } }),
                  !originalUploadAcceptances.contains(where: {
                      $0.plan.request.parent == id || $0.plan.request.targets.contains { $0.operation == id }
                  }) else { throw BackendContractError.identityMismatch }
            for b in photoSaveBatches.indices {
                guard photoSaveBatches[b].batch.operation != id else { throw BackendContractError.identityMismatch }
                for t in photoSaveBatches[b].targets.indices {
                    guard photoSaveBatches[b].targets[t].target.operation != id else { throw BackendContractError.identityMismatch }
                }
            }
        }
    }

    nonisolated mutating func applyUploadMetadata(_ change: UploadMetadataChange, receipt: BackendCommitReceipt,
        expectedStoreIdentity: RegistrationStoreIdentity?) throws {
        try MediaStoredValueValidation.uploadMetadata(change)
        let source = change.request
        guard expectedStoreIdentity == source.storeIdentity, receipt.matches(change.key, revision: receipt.previousRevision),
              UploadMetadataValidation.exact(receipt.key, change.key) else { throw BackendContractError.identityMismatch }
        let index = try uploadMetadataRequestIndex(source)
        switch change {
        case .beginQuery(let query):
            switch query.kind {
            case .create: try requireUploadMetadataCreate(index: index, source: source)
            case .lookup(let session):
                guard UploadMetadataValidation.exact(requests[index].session, Optional(session)) else { throw BackendContractError.identityMismatch }
            }
            let generations = uploadMetadataQueries.filter { $0.query.request.operation == source.operation }.map { $0.query.generation }
            let next = try UploadMetadataGeneration.next(lastObservation: requests[index].lastObservation, reservations: generations)
            guard query.generation == next else { throw BackendContractError.staleGeneration }
            let committed = CommittedUploadMetadataQuery(query: query, commit: receipt, expectedStoreIdentity: source.storeIdentity)
            guard committed.isCommitted else { throw BackendContractError.notCommitted }
            try requests[index].markAwaitingUploadMetadata(committed)
            for b in batches.indices where batches[b].requests.contains(where: { $0.operation == source.operation }) {
                try batches[b].update(requests[index])
            }
            uploadMetadataQueries.append(committed)
        case .observe(let observation):
            let query = observation.query.query
            guard let saved = uploadMetadataQueries.first(where: { $0.query.id == query.id }), saved.isCommitted,
                  UploadMetadataValidation.exact(saved, observation.query),
                  let latest = uploadMetadataQueries.filter({ $0.query.request.operation == source.operation })
                    .map({ $0.query.generation.rawValue }).max(), latest == query.generation.rawValue,
                  requests[index].lastObservation.map({ query.generation.rawValue > $0.rawValue }) ?? true else {
                throw BackendContractError.staleGeneration
            }
            if case .lookup(let session) = query.kind {
                guard UploadMetadataValidation.exact(requests[index].session, Optional(session)) else { throw BackendContractError.identityMismatch }
            }
            if let prior = uploadMetadataObservations.last(where: {
                $0.observation.query.query.request.operation == source.operation
                    && $0.observation.response.binding.session == observation.response.binding.session
            }) {
                guard UploadMetadataValidation.exact(prior.observation.response.binding, observation.response.binding) else {
                    throw BackendContractError.identityMismatch
                }
            }
            let record = StoredUploadMetadataObservation(observation: observation, commit: receipt, expectedStoreIdentity: source.storeIdentity)
            guard record.isCommitted else { throw BackendContractError.notCommitted }
            try requests[index].applyUploadMetadata(observation)
            for b in batches.indices where batches[b].requests.contains(where: { $0.operation == source.operation }) {
                try batches[b].update(requests[index])
            }
            uploadMetadataObservations.append(record)
            if let verification = record.verification {
                guard verification.isCommitted else { throw BackendContractError.notCommitted }
                // This is the actual observation authority, not a fabricated
                // .verification key/receipt or a second future commit.
                verifications.append(verification)
            }
        }
    }

    nonisolated func uploadMetadataRequestIndex(_ source: UploadMetadataRequest) throws -> Int {
        try source.validate()
        try requireOriginalUploadRegistration(source.registration)
        guard let index = requests.firstIndex(where: { $0.operation == source.operation }), source.matches(requests[index]),
              originals.contains(where: { UploadMetadataValidation.exact($0.original, source.original) }),
              !originals.contains(where: {
                  $0.original.capture == source.original.capture && !UploadMetadataValidation.exact($0.original, source.original)
              }) else { throw BackendContractError.identityMismatch }
        return index
    }

    nonisolated func requireUploadMetadataCreate(index: Int, source: UploadMetadataRequest) throws {
        let request = requests[index]
        guard request.intent == .running, request.session == nil, request.transport != .completed,
              !request.playbackEnded, request.uploadMetadataHold == nil,
              let state = originals.first(where: { UploadMetadataValidation.exact($0.original, source.original) }),
              let binding = state.binding, OriginalUploadAcceptanceValueValidation.savedBinding(binding),
              state.removal == nil, state.invalidation == nil, state.removalResolution != .removed else {
            throw BackendContractError.wrongStage
        }
        if case .succeeded = request.remote { throw BackendContractError.wrongStage }
    }
}

extension RecordingStoreDocument {
    /// New live POST reservations require the current saved recording. GET and
    /// response replay do not depend on today's recording/file existence.
    nonisolated func requireUploadMetadataCurrentRecordings(_ change: UploadMetadataChange) throws {
        guard case .beginQuery(let query) = change, case .create = query.kind else { return }
        let projection = try replayStore()
        let index = try projection.uploadMetadataRequestIndex(query.request)
        try projection.requireUploadMetadataCreate(index: index, source: query.request)
        guard let binding = projection.originals.first(where: {
            UploadMetadataValidation.exact($0.original, query.request.original)
        })?.binding, let current = entries.first(where: {
            UploadMetadataValidation.exact($0.intent.context.capture, binding.original.capture)
        }), current.revision == 2,
            UploadMetadataValidation.exact(current.intent, binding.saveRecord.intent),
            UploadMetadataValidation.exact(current.result, Optional(binding.saveRecord)),
            UploadMetadataValidation.exact(current.resultToken, Optional(binding.saveCommit.token)),
            binding.saveCommit.matches(binding.saveCommit.token, revision: 1) else { throw BackendContractError.identityMismatch }
    }
}
