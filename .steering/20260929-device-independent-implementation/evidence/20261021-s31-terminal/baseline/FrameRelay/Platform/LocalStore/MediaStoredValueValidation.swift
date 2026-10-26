import Foundation

/// Codable reconstructs values but does not establish their invariants. Every
/// journal event passes these checks and domain transitions on both write/reopen.
nonisolated enum MediaStoredValueValidation {
    static func text(_ value: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BackendContractError.invalidValue
        }
    }
    static func original(_ value: OriginalContent) throws {
        try text(value.capture.rawValue)
        guard value.generation.rawValue > 0 else { throw BackendContractError.invalidValue }
        try RecordingStoreDocument.validateBoundContent(value.content)
    }
    static func registration(_ value: RegistrationIdentity) throws {
        try text(value.destination.rawValue); try text(value.id.rawValue)
        guard value.generation.rawValue > 0 else { throw BackendContractError.invalidValue }
    }
    static func rendition(_ value: RenditionIdentity) throws {
        try original(value.original)
        try RecordingStoreDocument.validateBoundContent(value.deliveryContent)
        for value in [value.inputLogIdentity, value.transformAssetIdentity, value.transformAssetVersion,
                      value.outputConfigurationIdentity, value.conversionVersion, value.rendition.rawValue] {
            try text(value)
        }
        guard value.publicationGeneration.rawValue > 0 else { throw BackendContractError.invalidValue }
    }
    static func target(_ value: MediaTarget) throws {
        switch value { case .original(let value): try original(value); case .rendition(let value): try rendition(value) }
    }
    static func context(_ value: RemoteOperationContext) throws {
        try text(value.operation.rawValue); try registration(value.registration); try target(value.target)
        if let session = value.session { try text(session.rawValue) }
    }
    static func playback(_ value: PlaybackToken) throws {
        try text(value.session.rawValue); try text(value.distribution.operation.rawValue)
        try registration(value.distribution.registration); try rendition(value.distribution.rendition)
        guard value.observation == .played, value.distribution.isCommitted else { throw BackendContractError.notCommitted }
    }
    static func invalidation(_ value: InvalidationRecord) throws {
        try text(value.id.rawValue); try registration(value.registration); try rendition(value.rendition)
        guard value.generation.rawValue > 0 else { throw BackendContractError.invalidValue }
    }
    static func verification(_ value: VerificationEvidence) throws {
        try text(value.id.rawValue); try context(value.context); try text(value.schemaVersion)
        guard value.observedAt.timeIntervalSinceReferenceDate.isFinite else { throw BackendContractError.invalidValue }
        switch value.verification {
        case .assemblyOnly(let content), .finalDestinationReadBack(let content):
            try RecordingStoreDocument.validateBoundContent(content)
        }
        // Unknown schema, failed final save, and assembly-only proof remain facts;
        // storage does not promote them to supported cleanup evidence.
    }
    static func publication(_ value: PublishedRenditionObservation) throws {
        try text(value.command.rawValue); try registration(value.registration); try rendition(value.rendition)
        guard value.observation.rawValue > 0 else { throw BackendContractError.invalidValue }
    }
    static func lease(_ value: OriginalReadLease) throws {
        try text(value.id.rawValue); try text(value.operation.rawValue); try text(value.epoch.rawValue)
        try original(value.original)
        guard value.accessGeneration.rawValue > 0 else { throw BackendContractError.invalidValue }
    }
    static func mediaLease(_ value: MediaReadLease) throws {
        try text(value.id.rawValue); try text(value.operation.rawValue); try text(value.epoch.rawValue)
        try target(value.target); try registration(value.registration)
        guard value.accessGeneration.rawValue > 0 else { throw BackendContractError.invalidValue }
        switch value.context {
        case .transport(let attempt): try text(attempt.rawValue)
        case .playback(let session): try text(session.rawValue)
        case .temporary(let media, let usage): try text(media.rawValue); try text(usage.rawValue)
        }
    }
    static func transition(_ value: MediaRequestTransition) throws {
        switch value {
        case .pause, .resume, .cancel, .endPlayback, .wait: break
        case .beginAttempt(let attempt): try text(attempt.rawValue)
        case .stopped(let receipt):
            try text(receipt.operation.rawValue); try text(receipt.attempt.rawValue)
            try target(receipt.target); try registration(receipt.registration)
        case .completed(let receipt):
            try text(receipt.operation.rawValue); try text(receipt.attempt.rawValue)
            try target(receipt.target); try registration(receipt.registration)
        case .reconciled(let value):
            try context(value.context)
            guard value.observation.rawValue > 0 else { throw BackendContractError.invalidValue }
            if case .succeeded(let evidence) = value.result { try text(evidence.rawValue) }
        }
    }
    static func photo(_ value: PhotoRegistrationChange) throws {
        try value.intent.validate()
        try rendition(value.intent.rendition)
        switch value {
        case .intent: break
        case .result(let result):
            if let identifier = result.outcome.localIdentifier { try text(identifier.rawValue) }
        case .presence(let observation): try observation.validate()
        case .releaseUsage(let release):
            try text(release.successCommand.rawValue)
            try text(release.mediaUse.owner)
            try mediaLease(release.mediaUse.lease)
            guard release.mediaUse.usage == release.intent.usage,
                  release.successCommit.matches(.photo(release.successCommand, release.intent.key),
                      revision: release.successCommit.previousRevision) else {
                throw BackendContractError.identityMismatch
            }
        }
    }
}
