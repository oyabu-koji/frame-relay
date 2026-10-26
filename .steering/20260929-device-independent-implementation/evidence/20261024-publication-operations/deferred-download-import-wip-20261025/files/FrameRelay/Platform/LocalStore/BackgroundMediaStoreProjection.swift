extension MediaStoreProjection {
    nonisolated mutating func applyBackgroundTask(command: MediaOperationID, change: BackgroundMediaTaskChange,
        receipt: BackendCommitReceipt, expectedStoreIdentity: RegistrationStoreIdentity?) throws {
        try MediaStoredValueValidation.text(command.rawValue)
        try MediaStoredValueValidation.background(change)
        let intent = change.intent
        guard expectedStoreIdentity == intent.context.storeIdentity,
              receipt.matches(.backgroundTask(command, intent.id), revision: receipt.previousRevision) else {
            throw BackendContractError.identityMismatch
        }
        if case .uploadChunk = intent.source {
            guard UploadMetadataValidation.exact(receipt.key, BackendCommitKey.backgroundTask(command, intent.id)) else {
                throw BackendContractError.identityMismatch
            }
        }
        let event = StoredBackgroundMediaTaskEvent(command: command, change: change, commit: receipt,
            storeIdentity: intent.context.storeIdentity)
        switch change {
        case .prepared:
            if try !requireManagedDownload(intent) { try requireCurrentBackgroundRequest(intent) }
            guard !backgroundTasks.contains(where: { $0.intent.id == intent.id
                || ($0.intent.context.operation == intent.context.operation && $0.intent.context.attempt == intent.context.attempt)
                || ($0.intent.session == intent.session && $0.intent.taskDescription == intent.taskDescription)
                || ($0.intent.session.identifier == intent.session.identifier && $0.intent.session != intent.session)
            }) else { throw BackendContractError.duplicateTarget }
            var state = BackgroundMediaTaskState(intent: intent)
            state.events = [event]
            backgroundTasks.append(state)
        default:
            guard let index = backgroundTasks.firstIndex(where: { $0.intent == intent }) else { throw BackendContractError.identityMismatch }
            if case .resumeRequested = change {
                if try !requireManagedDownload(intent) { try requireCurrentBackgroundRequest(intent) }
            }
            if let ticket = backgroundDownloadTicket(task: intent.id) {
                guard ticket.planned.matches(intent) else { throw BackendContractError.identityMismatch }
                if case .ownerClosed(_, let closure) = change {
                    try requireManagedDownloadOwnerClosure(intent, closure: closure, through: receipt.previousRevision)
                }
                if let binding = backgroundTasks[index].binding {
                    switch change {
                    case .attached: break
                    case .resumeRequested(_, let incoming):
                        guard BackgroundDownloadValue.exact(incoming, binding) else { throw BackendContractError.identityMismatch }
                    case .terminal(_, let incoming):
                        guard BackgroundDownloadValue.exact(incoming.binding, binding) else { throw BackendContractError.identityMismatch }
                    case .ownerClosed(_, let incoming):
                        guard BackgroundDownloadValue.exact(incoming.binding, binding) else { throw BackendContractError.identityMismatch }
                    default: break
                    }
                }
            }
            if case .attached(_, let binding) = change {
                guard !backgroundTasks.enumerated().contains(where: { offset, state in
                    offset != index && state.binding?.session == binding.session
                        && state.binding?.taskIdentifier == binding.taskIdentifier
                }) else { throw BackendContractError.identityMismatch }
            }
            try backgroundTasks[index].apply(change)
            backgroundTasks[index].events.append(event)
        }
    }

    /// Gate generations, original-reader epochs/access, and common media epochs
    /// remain different axes. An exact live lease is valid after another reader
    /// advances access; its presence is never inferred from a generation alone.
    nonisolated private func requireCurrentBackgroundRequest(_ intent: BackgroundMediaTaskIntent) throws {
        let context = intent.context
        try requireCurrentRegistration(context.registration)
        guard let request = requests.first(where: { $0.operation == context.operation }),
              request.target == context.target, request.registration == context.registration,
              request.attempt == context.attempt, request.startCommitted,
              request.intent == .running, request.waits.isEmpty, !request.playbackEnded,
              request.transport == .active,
              let original = originals.first(where: { $0.original == context.target.original }),
              original.removal == nil, original.invalidation == nil,
              original.removalResolution != .removed else { throw BackendContractError.deletionUnresolved }
        switch intent.source {
        case .upload(let session, let lease, _):
            guard request.purpose == .upload, request.session == session,
                  original.binding?.saveRecord.result == .saved,
                  original.readers.contains(lease) else { throw BackendContractError.readersActive }
        case .uploadChunk(let lease, let chunk, _):
            guard request.purpose == .upload,
                  UploadMetadataValidation.exact(request.operation, context.operation),
                  UploadMetadataValidation.exact(request.target, context.target),
                  UploadMetadataValidation.exact(request.registration, context.registration),
                  UploadMetadataValidation.exact(request.session, Optional(chunk.descriptor.range.binding.session)),
                  UploadMetadataValidation.exact(original.original, context.target.original),
                  original.binding?.saveRecord.result == .saved,
                  original.readers.contains(where: { UploadMetadataValidation.exact($0, lease) }) else {
                throw BackendContractError.readersActive
            }
        case .download(let rendition, _, let lease):
            guard request.purpose == .download || request.purpose == .playback,
                  original.mediaReaders.contains(lease),
                  let current = confirmationState(original: rendition.original, registration: context.registration),
                  current.current == rendition, !current.invalidatedRenditions.contains(rendition.rendition) else {
                throw BackendContractError.invalidated
            }
        }
    }
}

extension RecordingStoreDocument {
    /// Only prior facts may establish a new chunk's admission. Replaying an old
    /// event must never use a later stop/GET/release from the finished document.
    @inline(never)
    nonisolated func requireUploadChunkHistory(_ intent: BackgroundMediaTaskIntent, through revision: UInt64,
                                               projection: MediaStoreProjection) throws {
        guard case .uploadChunk = intent.source else { return }
        let journal = chunkBackgroundFacts(through: revision)
        let view = BackgroundUploadChunkAdmissionView(revision: revision, storeIdentity: storeIdentity,
            registrations: projection.registrations, requests: projection.requests, originals: projection.originals,
            queries: projection.uploadMetadataQueries, observations: projection.uploadMetadataObservations,
            tasks: projection.backgroundTasks, journal: journal)
        try BackgroundUploadChunkAdmission.requireCurrentAttempt(intent, view: view)
        try requireChunkReleases(intent, through: revision, view: view)
    }

    @inline(never)
    nonisolated private func chunkBackgroundFacts(through revision: UInt64) -> [OriginalRemovalTransportJournalFact] {
        var facts: [OriginalRemovalTransportJournalFact] = []
        for entry in backendJournal where entry.receipt.committedRevision <= revision {
            facts.append(.init(mutation: entry.mutation, commit: entry.receipt))
        }
        return facts
    }

    @inline(never)
    nonisolated private func requireChunkReleases(_ current: BackgroundMediaTaskIntent, through revision: UInt64,
                                                 view: BackgroundUploadChunkAdmissionView) throws {
        for task in view.tasks where task.intent.context.operation == current.context.operation && task.intent.id != current.id {
            guard case .uploadChunk(let lease, _, _) = task.intent.source,
                  let closed = task.events.last(where: { if case .ownerClosed = $0.change { return true }; return false }) else {
                throw BackendContractError.readersActive
            }
            let stopped = try BackgroundUploadChunkAdmission.stoppedRevision(task, journal: view.journal, through: revision)
            try requireChunkRelease(lease, after: closed.commit.committedRevision, before: stopped, through: revision)
        }
    }

    @inline(never)
    nonisolated private func requireChunkRelease(_ lease: OriginalReadLease, after closed: UInt64,
                                                 before stopped: UInt64, through revision: UInt64) throws {
        var releases = 0
        for entry in originalJournal where entry.receipt.committedRevision <= revision {
            guard case .release(let value) = entry.mutation.change,
                  UploadMetadataValidation.exact(value, lease) else { continue }
            let next = entry.mutation.expectedRevision.addingReportingOverflow(1)
            guard !next.overflow, entry.receipt.committedRevision == next.partialValue,
                  entry.receipt.previousRevision == entry.mutation.expectedRevision,
                  UploadMetadataValidation.exact(entry.receipt.operation, entry.mutation.operation),
                  closed < entry.receipt.committedRevision, entry.receipt.committedRevision < stopped else {
                throw BackendContractError.wrongStage
            }
            releases += 1
        }
        guard releases == 1 else { throw BackendContractError.readersActive }
    }
}
