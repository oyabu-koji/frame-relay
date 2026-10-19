import Foundation

nonisolated struct BackendStoreJournalEntry: Codable {
    let mutation: BackendStoreMutation
    let receipt: BackendCommitReceipt
}

nonisolated struct ReceivedRendition: Hashable {
    let registration: RegistrationIdentity
    let rendition: RenditionIdentity
}

/// Disposable projections of the one persisted document; never a second store.
nonisolated struct MediaStoreProjection {
    var originals: [LogicalOriginalState] = []
    var registrationIntents: [CommittedRegistrationIntent] = []
    var registrations: [DeviceRegistration] = []
    var batches: [TransferBatch] = []
    var requests: [MediaRequest] = []
    var verifications: [StoredVerificationEvidence] = []
    var confirmations: [ConfirmationRecord] = []
    var invalidations: [InvalidationAcknowledgement] = []
    var publications: [StoredPublication] = []
    var confirmationStates: [ConfirmationState] = []
    var deliveries: [BackendSyncDelivery] = []
    var allOutbox: [BackendSyncEntry] = []
    var receivedRenditions: Set<ReceivedRendition> = []
    var mediaUses: [MediaReadLease] = []
    var distributionObservations: [StoredMediaDistributionObservation] = []

    func snapshot(revision: UInt64, storeIdentity: RegistrationStoreIdentity? = nil) throws -> BackendStoreSnapshot {
        .init(revision: revision, registrationIntents: registrationIntents, registrations: registrations,
            batches: batches, requests: requests, verifications: verifications, confirmations: confirmations,
            invalidations: invalidations,
            outbox: allOutbox.filter { entry in !deliveries.contains(where: { $0.entry == entry }) },
            storeIdentity: storeIdentity, publications: publications,
            confirmationStates: try confirmationStates.map { try $0.atStoreRevision(revision) },
            deliveries: deliveries, distributionObservations: distributionObservations)
    }

    mutating func ensureOriginal(_ original: OriginalContent) throws -> Int {
        try MediaStoredValueValidation.original(original)
        if let index = originals.firstIndex(where: { $0.original.capture == original.capture }) {
            guard originals[index].original == original else { throw BackendContractError.identityMismatch }
            return index
        }
        originals.append(.init(original: original))
        return originals.count - 1
    }

    func requireCurrentRegistration(_ registration: RegistrationIdentity) throws {
        try MediaStoredValueValidation.registration(registration)
        guard registrations.last(where: { $0.server.registration.destination == registration.destination })?
            .server.registration == registration else { throw BackendContractError.notCommitted }
    }

    func confirmationState(original: OriginalContent, registration: RegistrationIdentity) -> ConfirmationState? {
        confirmationStates.first { $0.registration == registration && $0.current.original == original }
    }

    func hasUnresolvedDistribution(registration: RegistrationIdentity, rendition: RenditionIdentity) -> Bool {
        mediaUses.contains { lease in
            guard lease.registration == registration, lease.target == .rendition(rendition) else { return false }
            guard let latest = distributionObservations.last(where: { $0.observation.lease == lease }) else { return true }
            switch latest.observation.result { case .notExecuted, .succeeded: return false; default: return true }
        }
    }

    func cleanupSchema(original: OriginalContent, selection: CleanupEvidenceSelection) throws -> String {
        try requireCurrentRegistration(selection.registration)
        guard let local = originals.first(where: { $0.original == original }), let binding = local.binding,
              binding.saveRecord.result == .saved, local.invalidation == nil,
              let state = confirmationState(original: original, registration: selection.registration),
              let confirmation = state.validConfirmation,
              confirmation.intent.operation == selection.confirmationOperation,
              let verification = verifications.last(where: {
                  $0.expected.registration.destination == selection.registration.destination
                    && $0.expected.target == .original(original)
              }), verification.command == selection.verificationCommand, verification.isCommitted,
              verification.evidence.verifies(original, destination: selection.registration.destination,
                                             supportedSchemas: [verification.evidence.schemaVersion]) else {
            throw BackendContractError.ineligibleOriginal
        }
        return verification.evidence.schemaVersion
    }
}

extension RecordingStoreDocument {
    nonisolated mutating func applyBackend(_ mutation: BackendStoreMutation,
        reconciliationEpoch: ReaderReconciliationEpoch? = nil) throws -> BackendCommitReceipt {
        if let expected = mutation.expectedStoreIdentity, expected != storeIdentity {
            throw BackendContractError.identityMismatch
        }
        if let previous = backendJournal.first(where: {
            $0.mutation.change.key.operationIdentity == mutation.change.key.operationIdentity
        }) {
            guard previous.mutation == mutation else { throw BackendContractError.identityMismatch }
            return previous.receipt
        }
        guard mutation.expectedRevision == transactionRevision, transactionRevision < UInt64.max else {
            throw BackendContractError.revisionConflict
        }
        if case .invalidation(let record, _) = mutation.change {
            guard try replayStore().originals.first(where: { $0.original == record.rendition.original })?
                .readersReleased(in: reconciliationEpoch) == true else { throw BackendContractError.readersActive }
        }
        let receipt = BackendCommitReceipt(key: mutation.change.key, previousRevision: transactionRevision,
                                           committedRevision: transactionRevision + 1)
        backendJournal.append(.init(mutation: mutation, receipt: receipt))
        transactionRevision += 1
        try validate()
        return receipt
    }

    nonisolated func lookupBackend(_ mutation: BackendStoreMutation) -> BackendCommitResult {
        if let expected = mutation.expectedStoreIdentity, expected != storeIdentity {
            return .rejected(.identityMismatch)
        }
        guard let stored = backendJournal.first(where: {
            $0.mutation.change.key.operationIdentity == mutation.change.key.operationIdentity
        }) else { return .unknown }
        return stored.mutation == mutation ? .committed(stored.receipt) : .rejected(.identityMismatch)
    }

    nonisolated func replayStore() throws -> MediaStoreProjection {
        var state = MediaStoreProjection()
        var originalOperations = Set<MediaOperationID>()
        var backendOperations = Set<BackendCommitIdentity>()
        var revisions = Set<UInt64>()
        var originalIndex = 0
        var backendIndex = 0
        var previous: UInt64 = 0
        // Capture intent/result receipts have per-capture revisions 1/2. Their
        // historical global positions were not recorded; gaps remain gaps. Count
        // validation accounts for them without inventing historical receipts.
        while originalIndex < originalJournal.count || backendIndex < backendJournal.count {
            let original = originalIndex < originalJournal.count ? originalJournal[originalIndex] : nil
            let backend = backendIndex < backendJournal.count ? backendJournal[backendIndex] : nil
            if let original, backend == nil || original.receipt.committedRevision < backend!.receipt.committedRevision {
                let mutation = original.mutation
                let receipt = original.receipt
                try MediaStoredValueValidation.text(mutation.operation.rawValue)
                guard originalOperations.insert(mutation.operation).inserted,
                      receipt.operation == mutation.operation, receipt.previousRevision == mutation.expectedRevision,
                      receipt.previousRevision < UInt64.max, receipt.committedRevision == receipt.previousRevision + 1,
                      receipt.previousRevision >= previous, receipt.committedRevision <= transactionRevision,
                      revisions.insert(receipt.committedRevision).inserted else { throw BackendContractError.revisionConflict }
                try applyOriginalChange(original, projection: &state)
                previous = receipt.committedRevision
                originalIndex += 1
            } else if let backend {
                let mutation = backend.mutation
                let receipt = backend.receipt
                if let expected = mutation.expectedStoreIdentity, expected != storeIdentity {
                    throw BackendContractError.identityMismatch
                }
                guard backendOperations.insert(mutation.change.key.operationIdentity).inserted,
                      receipt.matches(mutation.change.key, revision: mutation.expectedRevision),
                      receipt.committedRevision > legacyRevision, receipt.previousRevision >= previous,
                      receipt.committedRevision <= transactionRevision,
                      revisions.insert(receipt.committedRevision).inserted else { throw BackendContractError.revisionConflict }
                try applyBackendChange(backend, projection: &state)
                previous = receipt.committedRevision
                backendIndex += 1
            }
        }
        return state
    }

    nonisolated private func applyBackendChange(_ entry: BackendStoreJournalEntry,
                                               projection: inout MediaStoreProjection) throws {
        let change = entry.mutation.change
        let receipt = entry.receipt
        switch change {
        case .registrationIntent(let intent):
            try MediaStoredValueValidation.text(intent.operation.rawValue)
            try MediaStoredValueValidation.text(intent.destination.rawValue)
            guard !projection.registrationIntents.contains(where: { previous in
                previous.intent.destination == intent.destination &&
                !projection.registrations.contains(where: { $0.server.intent == previous.intent })
            }) else {
                throw BackendContractError.wrongStage
            }
            projection.registrationIntents.append(.init(intent: intent, commit: receipt))
        case .registration(let server):
            try MediaStoredValueValidation.registration(server.registration)
            guard server.intent.destination == server.registration.destination,
                  let intent = projection.registrationIntents.first(where: { $0.intent == server.intent }) else {
                throw BackendContractError.identityMismatch
            }
            if let previous = projection.registrations.last(where: { $0.server.registration.destination == server.registration.destination }) {
                guard server.registration.generation.rawValue > previous.server.registration.generation.rawValue else {
                    throw BackendContractError.staleGeneration
                }
            }
            let registration = DeviceRegistration(server: server, intentCommit: intent.commit, commit: receipt)
            guard registration.isCommitted else { throw BackendContractError.notCommitted }
            projection.registrations.append(registration)
        case .batch(var batch):
            try projection.requireCurrentRegistration(batch.registration)
            try MediaStoredValueValidation.text(batch.id.rawValue)
            guard batch.expectedRevision == entry.mutation.expectedRevision, !batch.fixedTargets.isEmpty,
                  batch.fixedTargets.count == batch.requests.count,
                  Set(batch.fixedTargets.map(\.capture)).count == batch.fixedTargets.count,
                  Set(batch.requests.map(\.operation)).count == batch.requests.count else { throw BackendContractError.invalidValue }
            for (original, request) in zip(batch.fixedTargets, batch.requests) {
                try validateInitialRequest(request, projection: projection)
                guard request.target == .original(original), request.purpose == .upload,
                      request.registration == batch.registration, request.expectedStartRevision == batch.expectedRevision else {
                    throw BackendContractError.identityMismatch
                }
            }
            try batch.acceptCommit(receipt)
            projection.batches.append(batch)
            projection.requests.append(contentsOf: batch.requests)
        case .request(let command, var request):
            try MediaStoredValueValidation.text(command.rawValue)
            guard command == request.operation, request.expectedStartRevision == entry.mutation.expectedRevision else {
                throw BackendContractError.identityMismatch
            }
            try validateInitialRequest(request, projection: projection)
            try request.acceptStartCommit(receipt)
            projection.requests.append(request)
        case .requestTransition(let command, let operation, let target, let registration, let transition):
            try MediaStoredValueValidation.text(command.rawValue)
            guard let index = projection.requests.firstIndex(where: { $0.operation == operation }),
                  projection.requests[index].target == target, projection.requests[index].registration == registration else {
                throw BackendContractError.identityMismatch
            }
            try MediaStoredValueValidation.transition(transition)
            if case .beginAttempt = transition {
                try projection.requireCurrentRegistration(registration)
                guard let original = projection.originals.first(where: { $0.original == target.original }),
                      original.removal == nil, original.invalidation == nil else {
                    throw BackendContractError.deletionUnresolved
                }
                if case .rendition(let rendition) = target {
                    guard let current = projection.confirmationState(original: rendition.original, registration: registration),
                          current.current == rendition, !current.invalidatedRenditions.contains(rendition.rendition) else {
                        throw BackendContractError.invalidated
                    }
                }
            }
            try projection.requests[index].apply(transition)
            for batch in projection.batches.indices where projection.batches[batch].requests.contains(where: { $0.operation == operation }) {
                try projection.batches[batch].update(projection.requests[index])
            }
        case .verification(let command, let expected, let evidence):
            try MediaStoredValueValidation.text(command.rawValue)
            try MediaStoredValueValidation.verification(evidence)
            try projection.requireCurrentRegistration(expected.registration)
            guard expected == evidence.context else { throw BackendContractError.identityMismatch }
            if let request = projection.requests.first(where: { $0.operation == expected.operation }) {
                guard request.target == expected.target, request.registration == expected.registration,
                      request.session == nil || request.session == expected.session else { throw BackendContractError.identityMismatch }
            }
            _ = try projection.ensureOriginal(expected.target.original)
            projection.verifications.append(.init(command: command, expected: expected, evidence: evidence, commit: receipt))
        case .publication(let observation):
            try MediaStoredValueValidation.publication(observation)
            try projection.requireCurrentRegistration(observation.registration)
            let originalIndex = try projection.ensureOriginal(observation.rendition.original)
            projection.originals[originalIndex].requiresMediaReconciliation = true
            if let index = projection.confirmationStates.firstIndex(where: {
                $0.registration == observation.registration && $0.current.original == observation.rendition.original
            }) {
                let oldObservation = projection.publications.last {
                    $0.observation.registration == observation.registration &&
                    $0.observation.rendition.original == observation.rendition.original
                }
                guard let oldObservation, observation.observation.rawValue > oldObservation.observation.observation.rawValue else {
                    throw BackendContractError.staleGeneration
                }
                var current = try projection.confirmationStates[index].atStoreRevision(receipt.previousRevision)
                if current.current != observation.rendition {
                    guard projection.originals[originalIndex].invalidation == nil,
                          projection.originals[originalIndex].removal == nil else {
                        throw BackendContractError.deletionUnresolved
                    }
                    let received = projection.receivedRenditions.contains(.init(registration: current.registration,
                                                                                rendition: current.current))
                    guard current.invalidatedRenditions.contains(current.current.rendition)
                        || (!received && !projection.hasUnresolvedDistribution(registration: current.registration,
                                                                              rendition: current.current)) else {
                        throw BackendContractError.awaitingAcknowledgements
                    }
                    try current.adoptObservedPublication(observation.rendition, generation: observation.invalidationGeneration)
                } else {
                    guard observation.invalidationGeneration == current.generation else { throw BackendContractError.staleGeneration }
                }
                projection.confirmationStates[index] = try current.atStoreRevision(receipt.committedRevision)
            } else {
                projection.confirmationStates.append(.init(registration: observation.registration,
                    current: observation.rendition, generation: observation.invalidationGeneration,
                    revision: receipt.committedRevision))
            }
            projection.publications.append(.init(observation: observation, commit: receipt))
        case .confirmation(let intent):
            try MediaStoredValueValidation.playback(intent.playback)
            try MediaStoredValueValidation.text(intent.operation.rawValue)
            let registration = intent.playback.distribution.registration
            let original = intent.playback.distribution.rendition.original
            try projection.requireCurrentRegistration(registration)
            guard let originalIndex = projection.originals.firstIndex(where: { $0.original == original }),
                  projection.originals[originalIndex].removal == nil,
                  projection.originals[originalIndex].invalidation == nil,
                  let index = projection.confirmationStates.firstIndex(where: {
                      $0.registration == registration && $0.current.original == original
                  }) else { throw BackendContractError.wrongStage }
            var current = try projection.confirmationStates[index].atStoreRevision(receipt.previousRevision)
            try current.commitConfirmation(intent, receipt: receipt)
            projection.confirmationStates[index] = current
            projection.receivedRenditions.insert(.init(registration: registration, rendition: intent.playback.distribution.rendition))
            let record = ConfirmationRecord(intent: intent, commit: receipt)
            projection.confirmations.append(record)
            projection.allOutbox.append(.confirmation(record))
        case .invalidation(let record, let permit):
            try MediaStoredValueValidation.invalidation(record)
            try projection.requireCurrentRegistration(record.registration)
            guard permit.record == record,
                  let originalIndex = projection.originals.firstIndex(where: { $0.original == record.rendition.original }),
                  projection.originals[originalIndex].invalidation?.record == record,
                  projection.originals[originalIndex].removal == nil,
                  let index = projection.confirmationStates.firstIndex(where: {
                      $0.registration == record.registration && $0.current.original == record.rendition.original
                  }) else { throw BackendContractError.identityMismatch }
            guard projection.originals[originalIndex].readersReleased else { throw BackendContractError.readersActive }
            var current = try projection.confirmationStates[index].atStoreRevision(receipt.previousRevision)
            let acknowledgement = try current.commitInvalidation(record, receipt: receipt, permit: permit)
            projection.confirmationStates[index] = current
            projection.invalidations.append(acknowledgement)
            projection.allOutbox.append(.invalidation(acknowledgement))
            projection.originals[originalIndex].invalidationGeneration = record.generation
            projection.originals[originalIndex].invalidation = nil
        case .delivered(let delivery):
            try MediaStoredValueValidation.text(delivery.command.rawValue)
            guard delivery.entry.registration == delivery.registration,
                  projection.allOutbox.contains(delivery.entry) else { throw BackendContractError.notCommitted }
            switch (delivery.entry, delivery.response) {
            case (.confirmation(let record), .confirmation(let operation)):
                guard record.intent.operation == operation else { throw BackendContractError.identityMismatch }
            case (.invalidation(let ack), .invalidation(let id)):
                guard ack.record.id == id else { throw BackendContractError.identityMismatch }
            default: throw BackendContractError.identityMismatch
            }
            projection.deliveries.append(delivery)
        case .distribution(let observation):
            try MediaStoredValueValidation.text(observation.command.rawValue)
            try MediaStoredValueValidation.mediaLease(observation.lease)
            guard observation.observation.rawValue > 0, projection.mediaUses.contains(observation.lease),
                  case .rendition(let rendition) = observation.lease.target else { throw BackendContractError.identityMismatch }
            if let prior = projection.distributionObservations.last(where: { $0.observation.lease == observation.lease }) {
                guard observation.observation.rawValue > prior.observation.observation.rawValue else {
                    throw BackendContractError.staleGeneration
                }
                if case .succeeded = prior.observation.result, observation.result != prior.observation.result {
                    throw BackendContractError.identityMismatch
                }
            }
            if case .succeeded(let distribution) = observation.result {
                try MediaStoredValueValidation.text(distribution.operation.rawValue)
                guard distribution.isCommitted, distribution.registration == observation.lease.registration,
                      distribution.rendition == rendition else { throw BackendContractError.identityMismatch }
                projection.receivedRenditions.insert(.init(registration: distribution.registration, rendition: rendition))
            }
            projection.distributionObservations.append(.init(observation: observation, commit: receipt))
        }
    }

    nonisolated private func validateInitialRequest(_ request: MediaRequest, projection: MediaStoreProjection) throws {
        try MediaStoredValueValidation.text(request.operation.rawValue)
        try MediaStoredValueValidation.target(request.target)
        try projection.requireCurrentRegistration(request.registration)
        guard !projection.requests.contains(where: { $0.operation == request.operation }),
              request == MediaRequest(operation: request.operation, target: request.target, purpose: request.purpose,
                                      registration: request.registration, expectedStartRevision: request.expectedStartRevision) else {
            throw BackendContractError.identityMismatch
        }
        switch (request.purpose, request.target) {
        case (.upload, .original(let original)):
            guard let state = projection.originals.first(where: { $0.original == original }),
                  state.binding?.saveRecord.result == .saved, state.removal == nil, state.invalidation == nil,
                  state.removalResolution != .removed else { throw BackendContractError.ineligibleOriginal }
        case (.download, .rendition(let rendition)), (.playback, .rendition(let rendition)):
            guard let state = projection.confirmationState(original: rendition.original, registration: request.registration),
                  state.current == rendition, !state.invalidatedRenditions.contains(rendition.rendition) else {
                throw BackendContractError.identityMismatch
            }
            guard let original = projection.originals.first(where: { $0.original == rendition.original }),
                  original.removal == nil, original.invalidation == nil else {
                throw BackendContractError.deletionUnresolved
            }
        default: throw BackendContractError.identityMismatch
        }
    }
}
