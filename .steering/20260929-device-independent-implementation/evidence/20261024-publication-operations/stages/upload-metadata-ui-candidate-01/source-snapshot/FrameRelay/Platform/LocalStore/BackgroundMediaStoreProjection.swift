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
        let event = StoredBackgroundMediaTaskEvent(command: command, change: change, commit: receipt,
            storeIdentity: intent.context.storeIdentity)
        switch change {
        case .prepared:
            try requireCurrentBackgroundRequest(intent)
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
            if case .resumeRequested = change { try requireCurrentBackgroundRequest(intent) }
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
