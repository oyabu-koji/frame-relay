import Foundation

extension MediaStoreProjection {
    /// New commands, not references to old operations. Global String equality
    /// catches normalized aliases; actual payload joins always use UTF-8 exact.
    nonisolated func requireBackgroundDownloadNamespace(_ change: BackendStoreChange) throws {
        var introduced = [change.key.commandText]
        switch change {
        case .batch(let batch): introduced += batch.requests.map { $0.operation.rawValue }
        case .request(_, let value): introduced.append(value.operation.rawValue)
        case .photoBatch(_, .accept(let value)): introduced += [value.operation.rawValue] + value.targets.map { $0.operation.rawValue }
        case .personControl(let value): introduced += value.children.map { $0.command.rawValue }
        case .originalUploadAcceptance(let value): introduced += value.request.targets.map { $0.operation.rawValue }
        case .uploadMetadata(.beginQuery(let value)): introduced.append(value.observationCommand.rawValue)
        default: break
        }
        for old in backgroundDownloadObservations {
            guard !introduced.contains(old.change.command.rawValue) else { throw BackendContractError.identityMismatch }
        }
        guard case .backgroundDownload(let value) = change else { return }
        let id = value.command
        guard !backendCommands.contains(id.rawValue), !requests.contains(where: { $0.operation == id }),
              !batches.contains(where: { $0.requests.contains { $0.operation == id } }),
              !personControls.contains(where: { $0.plan.parent == id || $0.plan.children.contains { $0.command == id } }),
              !originalUploadAcceptances.contains(where: { $0.plan.request.parent == id || $0.plan.request.targets.contains { $0.operation == id } }),
              !uploadMetadataQueries.contains(where: { $0.query.id == id || $0.query.observationCommand == id }),
              !photoSaveBatches.contains(where: { $0.batch.operation == id || $0.targets.contains { $0.target.operation == id } }) else {
            throw BackendContractError.identityMismatch
        }
    }

    nonisolated func backgroundDownloadRecord(_ ref: BackgroundDownloadObservationReference,
                                              through: UInt64) throws -> StoredBackgroundDownloadObservation {
        try ref.validate()
        guard ref.commit.committedRevision <= through,
              let saved = backgroundDownloadObservations.first(where: { $0.change.command == ref.command }), ref.matches(saved) else {
            throw BackendContractError.notCommitted
        }
        return saved
    }

    nonisolated func backgroundDownloadTicket(task: BackgroundMediaTaskID) -> BackgroundDownloadIssuedTicket? {
        for value in backgroundDownloadObservations {
            if case .issuedTicket(let ticket) = value.change, ticket.planned.taskID == task { return ticket }
        }
        return nil
    }

    /// Nil means the old path. A claimed task with mismatching bytes is refused,
    /// never silently sent down the legacy admission branch.
    nonisolated func requireManagedDownload(_ intent: BackgroundMediaTaskIntent) throws -> Bool {
        guard let ticket = backgroundDownloadTicket(task: intent.id) else { return false }
        guard ticket.planned.matches(intent) else { throw BackendContractError.identityMismatch }
        try requireDownloadScope(ticket.planned, registration: ticket.registration, active: true)
        return true
    }

    nonisolated func requireDownloadScope(_ planned: BackgroundDownloadPlannedIntentReference,
                                         registration: DeviceRegistration, active: Bool) throws {
        try planned.validate(); try requireOriginalUploadRegistration(registration)
        let context = planned.context
        guard let request = requests.first(where: { $0.operation == context.operation }),
              BackgroundDownloadValue.exact(request.operation, context.operation),
              BackgroundDownloadValue.exact(request.target, context.target),
              BackgroundDownloadValue.exact(request.registration, context.registration),
              BackgroundDownloadValue.exact(request.attempt, Optional(context.attempt)), request.startCommitted,
              request.purpose == .download || request.purpose == .playback,
              let original = originals.first(where: { BackgroundDownloadValue.exact($0.original, planned.rendition.original) }),
              !originals.contains(where: { $0.original.capture == planned.rendition.original.capture && !BackgroundDownloadValue.exact($0.original, planned.rendition.original) }),
              original.removal == nil, original.invalidation == nil,
              let current = confirmationState(original: planned.rendition.original, registration: context.registration),
              BackgroundDownloadValue.exact(current.registration, context.registration),
              BackgroundDownloadValue.exact(current.current, planned.rendition),
              !current.invalidatedRenditions.contains(planned.rendition.rendition) else { throw BackendContractError.invalidated }
        if active {
            guard request.intent == .running, request.waits.isEmpty, !request.playbackEnded, request.transport == .active,
                  original.mediaReaders.contains(where: { BackgroundDownloadValue.exact($0, planned.transportLease) }) else {
                throw BackendContractError.readersActive
            }
        }
        // Physical/local original and past resolvedRemoved are deliberately not
        // requirements for an independent current rendition.
    }

    nonisolated func requireManagedDownloadOwnerClosure(_ intent: BackgroundMediaTaskIntent,
        closure: BackgroundMediaOwnerClosure, through: UInt64) throws {
        guard let ticket = backgroundDownloadTicket(task: intent.id) else { return }
        guard ticket.planned.matches(intent), let saved = backgroundDownloadObservations.last(where: {
            $0.change.taskID == intent.id && $0.change.stage == .sourceClosed
        }), saved.isCommitted, saved.commit.committedRevision <= through,
            case .sourceClosed(let closed) = saved.change,
            BackgroundDownloadValue.exact(closed.source.binding, closure.binding), closure.tasksJoined, closure.handlesClosed else {
            throw BackendContractError.readersActive
        }
    }

    nonisolated func requireReservedDownloadTemporary(_ change: TemporaryMediaChange, authenticImport: Bool) throws {
        for saved in backgroundDownloadObservations {
            guard case .response(let response) = saved.change, response.media == change.id else { continue }
            guard BackgroundDownloadValue.exact(response.media, change.id) else { throw BackendContractError.identityMismatch }
            if case .verified = change, !authenticImport { throw BackendContractError.notCommitted }
            if case .create(let value) = change {
                let ticketRecord = try backgroundDownloadRecord(response.ticket, through: saved.commit.previousRevision)
                guard case .issuedTicket(let ticket) = ticketRecord.change, let date = ticket.captureDate,
                      value.capturedAt == date.capturedAt, BackgroundDownloadValue.exact(value.rendition, ticket.planned.rendition),
                      BackgroundDownloadValue.exact(value.registration, ticket.planned.context.registration),
                      value.contentType.utf8.elementsEqual(ticket.contentType.utf8) else { throw BackendContractError.identityMismatch }
            }
            if case .acquire(_, let use) = change, !temporaryMedia.contains(where: { $0.id == response.media && $0.verifiedContent != nil }) {
                guard BackgroundDownloadValue.exact(use.usage.id, response.usage), use.usage.purpose == .playback else { throw BackendContractError.identityMismatch }
            }
        }
    }
}

extension RecordingStoreDocument {
    @inline(never)
    nonisolated func applyBackgroundDownload(_ value: BackgroundDownloadStoreChange, receipt: BackendCommitReceipt,
        expectedStoreIdentity: RegistrationStoreIdentity?, projection: inout MediaStoreProjection) throws {
        try MediaStoredValueValidation.backgroundDownload(value)
        guard expectedStoreIdentity == value.storeIdentity, storeIdentity == value.storeIdentity,
              receipt.matches(value.key, revision: receipt.previousRevision), BackgroundDownloadValue.exact(receipt.key, value.key) else {
            throw BackendContractError.identityMismatch
        }
        switch value {
        case .issuedTicket(let ticket): try requireDownloadTicket(ticket, through: receipt.previousRevision, projection: projection)
        case .response(let response): try requireDownloadResponse(response, through: receipt.previousRevision, projection: projection)
        case .sourceClosed(let closed): try requireDownloadSourceClosed(closed, through: receipt.previousRevision, projection: projection)
        case .imported(let imported):
            _ = try requireDownloadImport(imported, through: receipt.previousRevision, projection: projection)
            try projection.applyTemporary(.verified(imported.media, imported.content), downloadImport: true)
        }
        let saved = StoredBackgroundDownloadObservation(change: value, commit: receipt, expectedStoreIdentity: value.storeIdentity)
        guard saved.isCommitted else { throw BackendContractError.notCommitted }
        projection.backgroundDownloadObservations.append(saved)
    }

    @inline(never)
    nonisolated func downloadBackendEntry(_ ref: BackgroundDownloadBackendReference, through: UInt64) throws -> BackendStoreJournalEntry {
        try ref.validate()
        guard ref.storeIdentity == storeIdentity, ref.commit.committedRevision <= through,
              let entry = backendJournal.first(where: { $0.receipt.committedRevision == ref.commit.committedRevision }),
              ref.matches(entry.mutation, receipt: entry.receipt) else { throw BackendContractError.notCommitted }
        return entry
    }

    @inline(never)
    nonisolated func downloadLeaseEntry(_ ref: BackgroundDownloadLeaseReference, through: UInt64) throws -> OriginalStoreJournalEntry {
        try ref.validate()
        guard ref.commit.committedRevision <= through,
              let entry = originalJournal.first(where: { $0.receipt.committedRevision == ref.commit.committedRevision }),
              ref.matches(entry.mutation, receipt: entry.receipt) else { throw BackendContractError.notCommitted }
        return entry
    }

    @inline(never)
    nonisolated private func requireDownloadTicket(_ ticket: BackgroundDownloadIssuedTicket, through: UInt64,
                                                   projection: MediaStoreProjection) throws {
        let planned = ticket.planned, context = planned.context
        try projection.requireDownloadScope(planned, registration: ticket.registration, active: true)
        guard !projection.backgroundTasks.contains(where: { $0.intent.id == planned.taskID ||
            ($0.intent.context.operation == context.operation && $0.intent.context.attempt == context.attempt) }),
              !projection.backgroundDownloadObservations.contains(where: {
                  if case .issuedTicket(let old) = $0.change {
                      return old.planned.taskID == planned.taskID || (old.planned.context.operation == context.operation && old.planned.context.attempt == context.attempt)
                  }; return false
              }) else { throw BackendContractError.duplicateTarget }
        let begin = try downloadBackendEntry(ticket.begin, through: through)
        guard case .requestTransition(_, let operation, let target, let registration, .beginAttempt(let attempt)) = begin.mutation.change,
              BackgroundDownloadValue.exact(operation, context.operation), BackgroundDownloadValue.exact(target, context.target),
              BackgroundDownloadValue.exact(registration, context.registration), BackgroundDownloadValue.exact(attempt, context.attempt) else {
            throw BackendContractError.identityMismatch
        }
        let lease = try downloadLeaseEntry(ticket.lease, through: through)
        guard case .acquireMedia(let actual) = lease.mutation.change, BackgroundDownloadValue.exact(actual, planned.transportLease),
              ticket.begin.commit.committedRevision < ticket.lease.commit.committedRevision else { throw BackendContractError.wrongStage }
    }

    @inline(never)
    nonisolated private func downloadTask(_ prepared: BackgroundDownloadBackendReference,
        attached: BackgroundDownloadBackendReference, ticket: BackgroundDownloadObservationReference,
        through: UInt64, projection: MediaStoreProjection) throws -> BackgroundMediaTaskState {
        let record = try projection.backgroundDownloadRecord(ticket, through: through)
        guard case .issuedTicket(let issued) = record.change,
              let task = projection.backgroundTasks.first(where: { $0.intent.id == ticket.taskID }), issued.planned.matches(task.intent) else {
            throw BackendContractError.identityMismatch
        }
        let p = try downloadBackendEntry(prepared, through: through), a = try downloadBackendEntry(attached, through: through)
        guard case .backgroundTask(_, .prepared(let pi)) = p.mutation.change,
              case .backgroundTask(_, .attached(let ai, let binding)) = a.mutation.change,
              BackgroundDownloadValue.exact(pi, task.intent), BackgroundDownloadValue.exact(ai, task.intent),
              BackgroundDownloadValue.exact(task.binding, Optional(binding)),
              record.commit.committedRevision < prepared.commit.committedRevision,
              prepared.commit.committedRevision < attached.commit.committedRevision else { throw BackendContractError.wrongStage }
        return task
    }

    @inline(never)
    nonisolated private func requireDownloadResponse(_ value: BackgroundDownloadResponseObservation,
        through: UInt64, projection: MediaStoreProjection) throws {
        let task = try downloadTask(value.prepared, attached: value.attached, ticket: value.ticket, through: through, projection: projection)
        let record = try projection.backgroundDownloadRecord(value.ticket, through: through)
        guard case .issuedTicket(let ticket) = record.change,
              BackgroundDownloadValue.exact(task.binding, Optional(value.artifact.binding)),
              value.response.urlFingerprint == ticket.responseURLFingerprint, value.response.contentType == ticket.contentType,
              value.response.distributionHeader == Data(ticket.ticket.operation.rawValue.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: ""),
              BackgroundDownloadValue.exact(value.response.renditionID, ticket.planned.rendition.rendition),
              value.response.publicationGeneration == ticket.planned.rendition.publicationGeneration,
              BackgroundDownloadValue.exact(value.response.content, ticket.planned.rendition.deliveryContent),
              !projection.temporaryMedia.contains(where: { $0.id == value.media || $0.usages.contains { $0.usage.id == value.usage } || $0.releasedUsages.contains { $0.usage.id == value.usage } }),
              !projection.backgroundDownloadObservations.contains(where: {
                  guard case .response(let old) = $0.change else { return false }
                  return old.taskID == value.taskID || old.artifact.id == value.artifact.id || old.media == value.media || old.usage == value.usage
              }), task.ownerClosure == nil else { throw BackendContractError.identityMismatch }
    }

    @inline(never)
    nonisolated private func requireDownloadSourceClosed(_ value: BackgroundDownloadSourceClosedObservation,
        through: UInt64, projection: MediaStoreProjection) throws {
        let task = try downloadTask(value.prepared, attached: value.attached, ticket: value.ticket, through: through, projection: projection)
        let terminal = try downloadBackendEntry(value.terminal, through: through)
        guard case .backgroundTask(_, .terminal(let ti, let actual)) = terminal.mutation.change,
              BackgroundDownloadValue.exact(ti, task.intent), BackgroundDownloadValue.exact(task.terminal, Optional(actual)),
              BackgroundDownloadValue.exact(value.source.binding, actual.binding), value.attached.commit.committedRevision < value.terminal.commit.committedRevision,
              task.ownerClosure == nil,
              !projection.backgroundDownloadObservations.contains(where: { $0.change.stage == .sourceClosed && $0.change.taskID == value.taskID }) else {
            throw BackendContractError.readersActive
        }
        if case .artifact(let artifact, let initial, _, _) = value.source,
           let response = projection.backgroundDownloadObservations.first(where: { $0.change.stage == .response && $0.change.taskID == value.taskID }) {
            guard case .response(let observed) = response.change, BackgroundDownloadValue.exact(observed.artifact, artifact),
                  BackgroundDownloadValue.exact(observed.source, initial) else { throw BackendContractError.identityMismatch }
        }
        if case .unpinned = value.source {
            guard !projection.backgroundDownloadObservations.contains(where: { $0.change.stage == .response && $0.change.taskID == value.taskID }) else {
                throw BackendContractError.readersActive
            }
        }
    }

    /// Historical metadata checks only; physical/capture/latch authority belongs
    /// exclusively to the guarded live writer entry below, never replay.
    @inline(never)
    nonisolated func requireDownloadImport(_ value: BackgroundDownloadImportObservation, through: UInt64,
        projection: MediaStoreProjection) throws -> BackgroundDownloadArtifactReference {
        let selection = value.selection
        let responseRecord = try projection.backgroundDownloadRecord(selection.response, through: through)
        let closeRecord = try projection.backgroundDownloadRecord(selection.sourceClosed, through: through)
        guard case .response(let response) = responseRecord.change, case .sourceClosed(let closed) = closeRecord.change,
              BackgroundDownloadValue.exact(closed.ticket, response.ticket),
              case .artifact(let artifact, let initial, _, let sourceContent) = closed.source,
              BackgroundDownloadValue.exact(artifact, response.artifact), BackgroundDownloadValue.exact(initial, response.source),
              BackgroundDownloadValue.exact(sourceContent, Optional(selection.sourceContent)),
              let task = projection.backgroundTasks.first(where: { $0.intent.id == value.taskID }),
              task.terminal?.outcome == .completed,
              let owner = task.ownerClosure, owner.tasksJoined, owner.handlesClosed,
              BackgroundDownloadValue.exact(owner.binding, artifact.binding) else { throw BackendContractError.readersActive }
        let ticketRecord = try projection.backgroundDownloadRecord(response.ticket, through: through)
        guard case .issuedTicket(let ticket) = ticketRecord.change,
              BackgroundDownloadValue.exact(ticket.captureDate, Optional(selection.captureDate)), ticket.planned.matches(task.intent) else {
            throw BackendContractError.identityMismatch
        }
        try projection.requireDownloadScope(ticket.planned, registration: ticket.registration, active: false)
        let ownerEntry = try downloadBackendEntry(selection.ownerClosed, through: through)
        guard case .backgroundTask(_, .ownerClosed(let oi, let oc)) = ownerEntry.mutation.change,
              BackgroundDownloadValue.exact(oi, task.intent), BackgroundDownloadValue.exact(oc, owner),
              closeRecord.commit.committedRevision < selection.ownerClosed.commit.committedRevision else { throw BackendContractError.wrongStage }
        let released = try downloadLeaseEntry(selection.leaseReleased, through: through)
        guard case .releaseMedia(let lease) = released.mutation.change,
              BackgroundDownloadValue.exact(lease, ticket.planned.transportLease),
              selection.ownerClosed.commit.committedRevision < selection.leaseReleased.commit.committedRevision,
              projection.originals.contains(where: { BackgroundDownloadValue.exact($0.original, ticket.planned.rendition.original)
                  && !$0.mediaReaders.contains(where: { BackgroundDownloadValue.exact($0, lease) }) }),
              responseRecord.commit.committedRevision < closeRecord.commit.committedRevision,
              !projection.backgroundDownloadObservations.contains(where: { $0.change.stage == .imported && $0.change.taskID == value.taskID }) else {
            throw BackendContractError.readersActive
        }
        try requireDownloadTarget(value, response: response, ticket: ticket, projection: projection)
        return artifact
    }

    @inline(never)
    nonisolated private func requireDownloadTarget(_ value: BackgroundDownloadImportObservation,
        response: BackgroundDownloadResponseObservation, ticket: BackgroundDownloadIssuedTicket, projection: MediaStoreProjection) throws {
        guard BackgroundDownloadValue.exact(value.media, response.media), BackgroundDownloadValue.exact(value.use.usage.id, response.usage),
              let state = projection.temporaryMedia.first(where: { $0.id == value.media }),
              BackgroundDownloadValue.exact(state.id, value.media), state.complete, state.verifiedContent == nil,
              !state.reclaiming, !state.reclaimed, state.capturedAt == value.selection.captureDate.capturedAt,
              BackgroundDownloadValue.exact(state.rendition, ticket.planned.rendition),
              BackgroundDownloadValue.exact(state.registration, ticket.planned.context.registration),
              state.leaf.utf8.elementsEqual(value.leaf.utf8), state.contentType.utf8.elementsEqual(value.contentType.utf8),
              state.directoryIdentity == value.directory, state.fileIdentity == value.file,
              state.usages.contains(where: { BackgroundDownloadValue.exact($0, value.use) }),
              value.use.usage.purpose == .playback,
              value.use.lease.epoch == ticket.planned.transportLease.epoch, value.use.usage.epoch == value.use.lease.epoch,
              BackgroundDownloadValue.exact(value.use.lease.target, MediaTarget.rendition(state.rendition)),
              BackgroundDownloadValue.exact(value.use.lease.context, MediaReadContext.temporary(value.media, value.use.usage.id)),
              BackgroundDownloadValue.exact(value.use.lease.registration, state.registration),
              projection.originals.contains(where: { BackgroundDownloadValue.exact($0.original, state.rendition.original)
                  && $0.mediaReaders.contains(where: { BackgroundDownloadValue.exact($0, value.use.lease) }) }),
              BackgroundDownloadValue.exact(value.content, state.rendition.deliveryContent) else { throw BackendContractError.identityMismatch }
    }

    /// Capture facts are checked only for NEW live observations. Historical
    /// replay never rebinds an old observation to today's recording entry.
    @inline(never)
    nonisolated func requireDownloadCaptureDate(_ change: BackgroundDownloadStoreChange) throws {
        let date: BackgroundDownloadCaptureDateReference?
        switch change { case .issuedTicket(let ticket): date = ticket.captureDate; case .imported(let value): date = value.selection.captureDate; default: return }
        guard let date else { return }
        try date.validate()
        guard entries.contains(where: { date.matches($0.intent) }) else { throw BackendContractError.identityMismatch }
    }
}

extension MediaStoreProjection {
    nonisolated func backgroundDownloadOriginal(_ value: BackgroundDownloadStoreChange) -> OriginalContent? {
        if case .issuedTicket(let ticket) = value { return ticket.planned.rendition.original }
        return backgroundDownloadTicket(task: value.taskID)?.planned.rendition.original
    }
}

extension RecordingStoreDocument {
    @inline(never)
    nonisolated func requireDownloadLeaseRelease(_ entry: OriginalStoreJournalEntry, projection: MediaStoreProjection) throws {
        guard case .releaseMedia(let lease) = entry.mutation.change else { return }
        for saved in projection.backgroundDownloadObservations {
            guard case .issuedTicket(let ticket) = saved.change,
                  BackgroundDownloadValue.exact(ticket.planned.transportLease, lease) else { continue }
            guard let task = projection.backgroundTasks.first(where: { $0.intent.id == ticket.planned.taskID }),
                  ticket.planned.matches(task.intent), let owner = task.ownerClosure,
                  let closed = task.events.last(where: { if case .ownerClosed = $0.change { return true }; return false }),
                  closed.commit.committedRevision < entry.receipt.committedRevision else { throw BackendContractError.readersActive }
            try projection.requireManagedDownloadOwnerClosure(task.intent, closure: owner, through: closed.commit.previousRevision)
        }
    }
}
