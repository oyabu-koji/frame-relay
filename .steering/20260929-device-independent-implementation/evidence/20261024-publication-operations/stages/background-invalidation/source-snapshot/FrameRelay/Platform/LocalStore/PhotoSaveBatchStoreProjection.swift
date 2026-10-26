import Foundation

extension MediaStoreProjection {
    nonisolated mutating func applyPhotoBatch(command: MediaOperationID, change: PhotoSaveBatchChange,
        receipt: BackendCommitReceipt, expectedStoreIdentity: RegistrationStoreIdentity?) throws {
        try MediaStoredValueValidation.text(command.rawValue)
        try MediaStoredValueValidation.photoBatch(change)
        guard let identity = expectedStoreIdentity,
              receipt.matches(.photoBatch(command, change.batch), revision: receipt.previousRevision),
              exact(receipt.key, BackendCommitKey.photoBatch(command, change.batch)) else {
            throw BackendContractError.identityMismatch
        }
        switch change {
        case .accept(let batch):
            guard identity == batch.storeIdentity, exact(command, batch.operation),
                  !hasPhotoBatchOperation(batch.operation),
                  !photoRegistrations.contains(where: { $0.registration.intent.operation == batch.operation }) else {
                throw BackendContractError.identityMismatch
            }
            for target in batch.targets {
                guard !photoCommandExists(target.operation),
                      !hasPhotoBatchOperation(target.operation) else {
                    throw BackendContractError.identityMismatch
                }
                try requirePhotoSaveSource(target.source)
                try requirePhotoSaveKeyAvailable(target, excluding: nil)
            }
            let record = PhotoSaveBatchRecord(batch: batch, command: command, commit: receipt,
                expectedStoreIdentity: identity, targets: batch.targets.map { .init(target: $0) })
            guard record.isCommitted else { throw BackendContractError.notCommitted }
            photoSaveBatches.append(record)
        case .beginChild(let batch, let target):
            let (b, t) = try photoBatchPosition(batch: batch, target: target, identity: identity)
            guard exact(command, target.operation), photoSaveBatches[b].targets[t].status == .queued else {
                throw BackendContractError.wrongStage
            }
            try requirePhotoSaveSource(target.source)
            try requirePhotoSaveKeyAvailable(target, excluding: target.operation)
            let child = CommittedPhotoSaveBatchChild(batch: batch, target: target, command: command,
                commit: receipt, expectedStoreIdentity: identity)
            guard child.isCommitted else { throw BackendContractError.notCommitted }
            photoSaveBatches[b].targets[t].status = .starting(child)
        case .notProcessed(let batch, let target, let reason):
            let (b, t) = try photoBatchPosition(batch: batch, target: target, identity: identity)
            guard exact(command, target.operation), photoSaveBatches[b].targets[t].status == .queued else {
                throw BackendContractError.wrongStage
            }
            // Cancelling a queued obsolete source never grants SDK access. It
            // must remain possible after registration/version eligibility changes.
            photoSaveBatches[b].targets[t].status = .notProcessed(.init(batch: batch, target: target, reason: reason,
                command: command, commit: receipt, expectedStoreIdentity: identity))
        }
    }

    nonisolated func photoSaveBatchSnapshot() throws -> [PhotoSaveBatchRecord] {
        try photoSaveBatches.map { value in
            var result = value
            for t in result.targets.indices {
                let target = result.targets[t].target
                let recordIndices = photoRegistrations.indices.filter { photoRegistrations[$0].registration.intent.operation == target.operation }
                guard recordIndices.count <= 1 else { throw BackendContractError.identityMismatch }
                if let index = recordIndices.first {
                    let record = photoRegistrations[index]
                    guard case .starting = result.targets[t].status,
                          exact(record.registration.intent.operation, target.operation),
                          exact(record.registration.intent.retryOf, target.retryOf),
                          record.registration.expectedStoreIdentity == target.source.storeIdentity,
                          photoRecord(record, matches: target.source) else { throw BackendContractError.identityMismatch }
                    result.targets[t].registration = record
                }
            }
            return result
        }
    }

    /// Shared by batch starts and the old standalone intent path. A queued
    /// reservation cannot be bypassed by calling that old path directly.
    nonisolated func requirePhotoBatchBoundary(command: MediaOperationID, change: PhotoRegistrationChange,
        receipt: BackendCommitReceipt, expectedStoreIdentity: RegistrationStoreIdentity?) throws {
        let intent = change.intent
        guard let (b, t) = try photoBatchChildPosition(operation: intent.operation, command: command) else {
            if case .intent = change { try requireStandalonePhotoReservation(intent) }
            return // Old standalone journals retain their historical rules.
        }
        let target = photoSaveBatches[b].targets[t].target
        guard case .starting = photoSaveBatches[b].targets[t].status, exact(intent.operation, target.operation),
              exact(intent.retryOf, target.retryOf), expectedStoreIdentity == target.source.storeIdentity,
              exact(receipt.key, BackendCommitKey.photo(command, change.key)),
              photoIntent(intent, matches: target.source) else { throw BackendContractError.identityMismatch }
        if case .intent = change {
            guard exact(command, target.operation) else { throw BackendContractError.identityMismatch }
            try requirePhotoSaveSource(target.source)
            try requirePhotoSaveKeyAvailable(target, excluding: target.operation)
            return
        }
        guard let index = photoRegistrations.firstIndex(where: { exact($0.registration.intent.operation, target.operation) }),
              exact(photoRegistrations[index].registration.intent, intent), photoRecord(photoRegistrations[index], matches: target.source) else {
            throw BackendContractError.identityMismatch
        }
        // Separate scopes keep the sizeable, mutually exclusive SDK payloads
        // from all receiving simultaneous stack temporaries on an intent path.
        try requirePhotoBatchResult(change, index: index)
        try requirePhotoBatchPresence(change, index: index)
        try requirePhotoBatchRelease(change, index: index)
        try requirePhotoBatchTerminal(change, index: index)
        try requirePhotoBatchTerminalRelease(change, index: index)
    }

    private nonisolated func hasPhotoBatchOperation(_ operation: MediaOperationID) -> Bool {
        for b in photoSaveBatches.indices {
            if photoSaveBatches[b].batch.operation == operation { return true }
            for t in photoSaveBatches[b].targets.indices {
                if photoSaveBatches[b].targets[t].target.operation == operation { return true }
            }
        }
        return false
    }

    private nonisolated func photoBatchChildPosition(operation: MediaOperationID, command: MediaOperationID) throws -> (Int, Int)? {
        var position: (Int, Int)?
        for b in photoSaveBatches.indices {
            for t in photoSaveBatches[b].targets.indices {
                let owner = photoSaveBatches[b].targets[t].target.operation
                if owner == command, !exact(owner, operation) { throw BackendContractError.identityMismatch }
                if owner == operation {
                    guard position == nil else { throw BackendContractError.identityMismatch }
                    position = (b, t)
                }
            }
        }
        return position
    }

    private nonisolated func requireStandalonePhotoReservation(_ intent: PhotoRegistrationIntent) throws {
        for b in photoSaveBatches.indices {
            for t in photoSaveBatches[b].targets.indices {
                let key = photoSaveBatches[b].targets[t].target.key
                guard key == intent.key else { continue }
                guard exact(key, intent.key) else { throw BackendContractError.identityMismatch }
                // Known non-addition still needs a new accepted/start child;
                // standalone calls cannot bypass the old child's decision.
                if case .notProcessed = photoSaveBatches[b].targets[t].status { continue }
                throw BackendContractError.duplicateTarget
            }
        }
    }

    private nonisolated func requirePhotoBatchResult(_ change: PhotoRegistrationChange, index: Int) throws {
        guard case .result(let result) = change else { return }
        if let old = photoRegistrations[index].localIdentifier, let new = result.outcome.localIdentifier, !exact(old, new) {
            throw BackendContractError.identityMismatch
        }
    }

    private nonisolated func requirePhotoBatchPresence(_ change: PhotoRegistrationChange, index: Int) throws {
        guard case .presence(let observation) = change else { return }
        guard exact(photoRegistrations[index].localIdentifier, observation.identifier) else { throw BackendContractError.identityMismatch }
    }

    private nonisolated func requirePhotoBatchRelease(_ change: PhotoRegistrationChange, index: Int) throws {
        guard case .releaseUsage(let release) = change else { return }
        guard exact(photoRegistrations[index].registration.mediaUse, release.mediaUse),
              let success = photoRegistrations[index].results.last, exact(success.command, release.successCommand),
              exact(success.commit, release.successCommit) else { throw BackendContractError.identityMismatch }
    }

    private nonisolated func requirePhotoBatchTerminal(_ change: PhotoRegistrationChange, index: Int) throws {
        guard case .terminal(let terminal) = change else { return }
        guard exact(photoRegistrations[index].registration.mediaUse, terminal.mediaUse) else { throw BackendContractError.identityMismatch }
    }

    private nonisolated func requirePhotoBatchTerminalRelease(_ change: PhotoRegistrationChange, index: Int) throws {
        guard case .releaseTerminalUsage(let release) = change else { return }
        guard let terminal = photoRegistrations[index].usageTerminal, exact(terminal.terminal, release.terminal),
              exact(terminal.command, release.terminalCommand), exact(terminal.commit, release.terminalCommit) else {
            throw BackendContractError.identityMismatch
        }
    }

    private nonisolated func photoBatchPosition(batch: MediaOperationID, target: PhotoSaveBatchTarget,
        identity: RegistrationStoreIdentity) throws -> (Int, Int) {
        guard let b = photoSaveBatches.firstIndex(where: { exact($0.batch.operation, batch) }),
              photoSaveBatches[b].expectedStoreIdentity == identity, target.source.storeIdentity == identity,
              let t = photoSaveBatches[b].targets.firstIndex(where: { exact($0.target, target) }) else {
            throw BackendContractError.identityMismatch
        }
        return (b, t)
    }

    private nonisolated func requirePhotoSaveSource(_ source: PhotoSaveSource) throws {
        try source.validate()
        try requirePhotoSaveRegistration(source)
        try requirePhotoSaveOriginal(source)
        try requirePhotoSavePublication(source)
        try requirePhotoSaveTemporary(source)
    }

    private nonisolated func requirePhotoSaveRegistration(_ source: PhotoSaveSource) throws {
        try requireCurrentRegistration(source.registration)
        guard let registration = registrations.last(where: {
                  exact($0.server.registration.destination, source.registration.destination)
              }), registration.isCommitted, exact(registration.server.registration, source.registration) else {
            throw BackendContractError.ineligibleOriginal
        }
    }

    private nonisolated func requirePhotoSaveOriginal(_ source: PhotoSaveSource) throws {
        guard let index = originals.firstIndex(where: { exact($0.original, source.rendition.original) }),
              originals[index].removal == nil, originals[index].invalidation == nil,
              !originals.indices.contains(where: { originals[$0].original.capture == source.rendition.original.capture
                  && !exact(originals[$0].original, source.rendition.original) }) else {
            throw BackendContractError.ineligibleOriginal
        }
    }

    private nonisolated func requirePhotoSavePublication(_ source: PhotoSaveSource) throws {
        guard let current = confirmationState(original: source.rendition.original, registration: source.registration),
              exact(current.registration, source.registration), exact(current.current, source.rendition),
              !current.invalidatedRenditions.contains(source.rendition.rendition) else {
            throw BackendContractError.ineligibleOriginal
        }
    }

    private nonisolated func requirePhotoSaveTemporary(_ source: PhotoSaveSource) throws {
        guard let media = temporaryMedia.first(where: { exact($0.id, source.media) }),
              exact(media.registration, source.registration), exact(media.rendition, source.rendition),
              exact(media.capturedAt, source.capturedAt), exact(media.leaf, source.leaf), exact(media.contentType, source.contentType),
              media.directoryIdentity == source.directoryIdentity, media.fileIdentity == source.fileIdentity,
              media.complete, exact(media.verifiedContent, Optional(source.rendition.deliveryContent)),
              !media.reclaiming, !media.reclaimed else { throw BackendContractError.ineligibleOriginal }
    }

    private nonisolated func requirePhotoSaveKeyAvailable(_ target: PhotoSaveBatchTarget, excluding owner: MediaOperationID?) throws {
        var previous: Int?
        for index in photoRegistrations.indices where photoRegistrations[index].registration.intent.key == target.key {
            guard exact(photoRegistrations[index].registration.intent.key, target.key) else { throw BackendContractError.identityMismatch }
            previous = index
        }
        if let index = previous {
            guard photoRegistrations[index].outcome?.permitsExplicitRetry == true,
                  exact(target.retryOf, Optional(photoRegistrations[index].registration.intent.operation)),
                  photoRecord(photoRegistrations[index], matches: target.source) else { throw BackendContractError.duplicateTarget }
        } else if target.retryOf != nil { throw BackendContractError.identityMismatch }
        for b in photoSaveBatches.indices {
            for t in photoSaveBatches[b].targets.indices {
                let key = photoSaveBatches[b].targets[t].target.key
                guard key == target.key else { continue }
                guard exact(key, target.key) else { throw BackendContractError.identityMismatch }
                if let owner, exact(owner, photoSaveBatches[b].targets[t].target.operation) { continue }
                if photoChildReservesKey(batch: b, target: t) { throw BackendContractError.duplicateTarget }
            }
        }
    }

    private nonisolated func photoChildReservesKey(batch b: Int, target t: Int) -> Bool {
        switch photoSaveBatches[b].targets[t].status {
        case .queued: return true
        case .notProcessed: return false
        case .starting:
            let operation = photoSaveBatches[b].targets[t].target.operation
            guard let index = photoRegistrations.lastIndex(where: { exact($0.registration.intent.operation, operation) }) else { return true }
            return photoRegistrations[index].outcome?.permitsExplicitRetry != true
        }
    }

    private nonisolated func photoCommandExists(_ operation: MediaOperationID) -> Bool {
        photoRegistrations.contains { record in
            record.registration.intent.operation == operation || record.results.contains { $0.command == operation }
                || record.presenceObservations.contains { $0.command == operation }
                || record.usageRelease?.command == operation || record.usageTerminal?.command == operation
                || record.terminalUsageRelease?.command == operation
        }
    }

    private nonisolated func photoIntent(_ intent: PhotoRegistrationIntent, matches source: PhotoSaveSource) -> Bool {
        exact(intent.rendition, source.rendition) && exact(intent.media, source.media) && exact(intent.capturedAt, source.capturedAt)
    }
    private nonisolated func photoRecord(_ record: PhotoRegistrationRecord, matches source: PhotoSaveSource) -> Bool {
        let registration = record.registration
        return photoIntent(registration.intent, matches: source)
            && exact(registration.mediaUse.lease.registration, source.registration)
            && registration.directoryIdentity == source.directoryIdentity && registration.fileIdentity == source.fileIdentity
            && (registration.expectedStoreIdentity == nil || registration.expectedStoreIdentity == source.storeIdentity)
    }
    private nonisolated func exact<T: Encodable>(_ lhs: T, _ rhs: T) -> Bool { PhotoSaveBatchValueValidation.exact(lhs, rhs) }
}
