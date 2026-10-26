import Foundation

extension MediaStoreProjection {
    nonisolated mutating func applyPhoto(command: MediaOperationID, change: PhotoRegistrationChange,
                                        receipt: BackendCommitReceipt,
                                        expectedStoreIdentity: RegistrationStoreIdentity?) throws {
        try MediaStoredValueValidation.text(command.rawValue)
        try MediaStoredValueValidation.photo(change)
        try requirePhotoBatchBoundary(command: command, change: change, receipt: receipt, expectedStoreIdentity: expectedStoreIdentity)
        switch change {
        case .intent(let intent):
            guard command == intent.operation else { throw BackendContractError.identityMismatch }
            if let previous = photoRegistrations.last(where: { $0.registration.intent.key == intent.key }) {
                guard let outcome = previous.outcome, outcome.permitsExplicitRetry,
                      intent.retryOf == previous.registration.intent.operation else {
                    throw BackendContractError.duplicateTarget
                }
                // An explicit retry cannot repurpose a conversion ID for other bytes.
                guard previous.registration.intent.rendition == intent.rendition,
                      previous.registration.intent.capturedAt == intent.capturedAt else {
                    throw BackendContractError.identityMismatch
                }
            } else if intent.retryOf != nil {
                throw BackendContractError.identityMismatch
            }
            guard !photoRegistrations.contains(where: { $0.registration.intent.operation == intent.operation }),
                  let media = temporaryMedia.first(where: { $0.id == intent.media }),
                  media.rendition == intent.rendition, media.capturedAt == intent.capturedAt,
                  media.complete, media.verifiedContent == intent.rendition.deliveryContent,
                  media.fileIdentity != nil, !media.reclaiming, !media.reclaimed,
                  let use = media.usages.first(where: { $0.usage == intent.usage }),
                  use.lease.target == .rendition(intent.rendition),
                  use.lease.context == .temporary(intent.media, intent.usage.id),
                  use.lease.epoch == intent.usage.epoch,
                  let original = originals.first(where: { $0.original == intent.rendition.original }),
                  original.removal == nil, original.invalidation == nil,
                  original.mediaReaders.contains(use.lease) else {
                throw BackendContractError.ineligibleOriginal
            }
            try requireCurrentRegistration(media.registration)
            guard let current = confirmationState(original: intent.rendition.original, registration: media.registration),
                  current.current == intent.rendition,
                  !current.invalidatedRenditions.contains(intent.rendition.rendition) else {
                throw BackendContractError.invalidated
            }
            let registration = CommittedPhotoRegistrationIntent(intent: intent, mediaUse: use, commit: receipt,
                expectedStoreIdentity: expectedStoreIdentity, directoryIdentity: media.directoryIdentity,
                fileIdentity: media.fileIdentity)
            guard registration.isCommitted else { throw BackendContractError.notCommitted }
            photoRegistrations.append(.init(registration: registration))
        case .result(let result):
            guard let index = photoRegistrations.firstIndex(where: { $0.registration.intent == result.intent }) else {
                throw BackendContractError.identityMismatch
            }
            let previous = photoRegistrations[index]
            // The same SDK request can supply a delayed terminal after an unknown.
            // Settled terminal outcomes cannot be replaced or reset to not-attempted.
            if let outcome = previous.outcome {
                switch outcome {
                case .unknown:
                    if case .notAttempted = result.outcome { throw BackendContractError.wrongStage }
                case .notAttempted, .failed, .succeeded:
                    guard outcome == result.outcome else { throw BackendContractError.wrongStage }
                }
            }
            if let known = previous.localIdentifier, let incoming = result.outcome.localIdentifier,
               known != incoming { throw BackendContractError.identityMismatch }
            // Once a proven non-addition has been retried, late callbacks for that
            // older request cannot manufacture a new outcome behind the retry.
            if photoRegistrations.contains(where: { $0.registration.intent.retryOf == result.intent.operation }),
               previous.outcome != result.outcome { throw BackendContractError.wrongStage }
            photoRegistrations[index].results.append(.init(command: command, result: result, commit: receipt,
                expectedStoreIdentity: expectedStoreIdentity))
        case .presence(let observation):
            guard let index = photoRegistrations.firstIndex(where: { $0.registration.intent == observation.intent }) else {
                throw BackendContractError.identityMismatch
            }
            let previous = photoRegistrations[index]
            guard observation.identifier == previous.localIdentifier else {
                throw BackendContractError.identityMismatch
            }
            if let old = previous.currentPresence {
                guard observation.generation > old.generation else { throw BackendContractError.staleGeneration }
            }
            photoRegistrations[index].presenceObservations.append(.init(command: command,
                observation: observation, commit: receipt, expectedStoreIdentity: expectedStoreIdentity))
        case .releaseUsage(let release):
            guard let index = photoRegistrations.firstIndex(where: { $0.registration.intent == release.intent }) else {
                throw BackendContractError.identityMismatch
            }
            let record = photoRegistrations[index]
            guard record.usageRelease == nil, record.terminalUsageRelease == nil else { throw BackendContractError.wrongStage }
            guard record.registration.mediaUse == release.mediaUse,
                  record.registration.directoryIdentity == release.directoryIdentity,
                  record.registration.fileIdentity == release.fileIdentity,
                  let success = record.results.last, case .succeeded = success.result.outcome,
                  success.command == release.successCommand, success.commit == release.successCommit,
                  let media = temporaryMedia.first(where: { $0.id == release.intent.media }),
                  media.directoryIdentity == release.directoryIdentity, media.fileIdentity == release.fileIdentity,
                  media.usages.contains(release.mediaUse), release.mediaUse.usage.purpose == .photoHandoff else {
                throw BackendContractError.identityMismatch
            }
            // This narrow successful-registration proof is the only photo path
            // allowed to retire this exact old epoch. General release stays strict.
            try applyTemporary(.release(release.intent.media, release.mediaUse), photoRelease: true)
            photoRegistrations[index].usageRelease = .init(command: command, release: release, commit: receipt,
                expectedStoreIdentity: expectedStoreIdentity)
        case .terminal(let terminal):
            guard let index = photoRegistrations.firstIndex(where: { $0.registration.intent == terminal.intent }) else {
                throw BackendContractError.identityMismatch
            }
            let record = photoRegistrations[index]
            guard record.usageTerminal == nil, record.usageRelease == nil,
                  record.terminalUsageRelease == nil else { throw BackendContractError.wrongStage }
            guard record.registration.mediaUse == terminal.mediaUse,
                  record.registration.directoryIdentity == terminal.directoryIdentity,
                  record.registration.fileIdentity == terminal.fileIdentity,
                  let media = temporaryMedia.first(where: { $0.id == terminal.intent.media }),
                  media.directoryIdentity == terminal.directoryIdentity, media.fileIdentity == terminal.fileIdentity,
                  media.usages.contains(terminal.mediaUse) else { throw BackendContractError.identityMismatch }
            photoRegistrations[index].usageTerminal = .init(command: command, terminal: terminal, commit: receipt,
                expectedStoreIdentity: expectedStoreIdentity)
        case .releaseTerminalUsage(let release):
            guard let index = photoRegistrations.firstIndex(where: { $0.registration.intent == release.intent }) else {
                throw BackendContractError.identityMismatch
            }
            let record = photoRegistrations[index]
            guard record.usageRelease == nil, record.terminalUsageRelease == nil else {
                throw BackendContractError.wrongStage
            }
            guard let terminal = record.usageTerminal, terminal.terminal == release.terminal,
                  terminal.command == release.terminalCommand, terminal.commit == release.terminalCommit,
                  record.registration.mediaUse == release.terminal.mediaUse,
                  record.registration.directoryIdentity == release.terminal.directoryIdentity,
                  record.registration.fileIdentity == release.terminal.fileIdentity,
                  let media = temporaryMedia.first(where: { $0.id == release.intent.media }),
                  media.directoryIdentity == release.terminal.directoryIdentity,
                  media.fileIdentity == release.terminal.fileIdentity,
                  media.usages.contains(release.terminal.mediaUse) else {
                throw BackendContractError.identityMismatch
            }
            try applyTemporary(.release(release.intent.media, release.terminal.mediaUse), photoRelease: true)
            photoRegistrations[index].terminalUsageRelease = .init(command: command, release: release, commit: receipt,
                expectedStoreIdentity: expectedStoreIdentity)
        }
    }

    /// Results in the journal are the retention authority. A released reader is
    /// not permission to unlink an unsuccessful/unknown registration copy. A
    /// successful explicit retry on that same copy ends the earlier retention.
    nonisolated func needsPhotoRetention(_ media: TemporaryMediaID) -> Bool {
        PhotoRegistrationRecord.retainsCopy(media, in: photoRegistrations)
    }
}
