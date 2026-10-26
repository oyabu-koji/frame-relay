import Foundation

/// A rendition ID identifies a conversion of one capture. Other rendition
/// metadata remains in the intent and cannot create a second registration key.
nonisolated struct PhotoRegistrationKey: Hashable, Sendable, Codable {
    let capture: CaptureID
    let rendition: RenditionID

    init(rendition: RenditionIdentity) {
        capture = rendition.original.capture
        self.rendition = rendition.rendition
    }

    private enum CodingKeys: String, CodingKey { case capture, rendition }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        capture = try values.decode(CaptureID.self, forKey: .capture)
        rendition = try values.decode(RenditionID.self, forKey: .rendition)
        try PhotoRegistrationValueValidation.text(capture.rawValue)
        try PhotoRegistrationValueValidation.text(rendition.rawValue)
    }
}

nonisolated struct PhotoAssetIdentifier: Hashable, Sendable, Codable {
    let rawValue: String

    init(rawValue: String) throws {
        try PhotoRegistrationValueValidation.text(rawValue)
        self.rawValue = rawValue
    }

    private enum CodingKeys: String, CodingKey { case rawValue }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(rawValue: values.decode(String.self, forKey: .rawValue))
    }
}

nonisolated enum PhotoLibraryAccess: Equatable, Sendable, Codable { case addOnly, readWrite }
nonisolated enum PhotoLibraryAuthorization: Equatable, Sendable, Codable {
    case notDetermined, restricted, denied, authorized, limited, unknown
}

nonisolated enum PhotoLibraryFailure: Equatable, Sendable, Codable {
    case authorizationRequired, restricted, inaccessible, invalidMedia, rejected
}

nonisolated struct PhotoRegistrationIntent: Equatable, Sendable, Codable {
    let operation: MediaOperationID
    let rendition: RenditionIdentity
    let media: TemporaryMediaID
    let usage: TemporaryMediaUsage
    let capturedAt: Date
    /// Explicit retry of a proven non-addition; never permission to retry an unknown.
    let retryOf: MediaOperationID?

    var key: PhotoRegistrationKey { .init(rendition: rendition) }
    var handoff: PhotoMediaHandoff {
        .init(media: media, rendition: rendition, capturedAt: capturedAt, usage: usage)
    }

    init(operation: MediaOperationID, handoff: PhotoMediaHandoff, retryOf: MediaOperationID? = nil) throws {
        self.operation = operation
        rendition = handoff.rendition
        media = handoff.media
        usage = handoff.usage
        capturedAt = handoff.capturedAt
        self.retryOf = retryOf
        try validate()
    }

    func validate() throws {
        try PhotoRegistrationValueValidation.text(operation.rawValue)
        try PhotoRegistrationValueValidation.rendition(rendition)
        try PhotoRegistrationValueValidation.text(media.rawValue)
        try PhotoRegistrationValueValidation.text(usage.id.rawValue)
        guard usage.media == media, usage.purpose == .photoHandoff,
              let epoch = usage.epoch, capturedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw BackendContractError.invalidValue
        }
        try PhotoRegistrationValueValidation.text(epoch.rawValue)
        if let retryOf {
            try PhotoRegistrationValueValidation.text(retryOf.rawValue)
            guard retryOf != operation else { throw BackendContractError.invalidValue }
        }
    }

    private enum CodingKeys: String, CodingKey { case operation, rendition, media, usage, capturedAt, retryOf }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(operation: values.decode(MediaOperationID.self, forKey: .operation),
            handoff: .init(media: values.decode(TemporaryMediaID.self, forKey: .media),
                rendition: values.decode(RenditionIdentity.self, forKey: .rendition),
                capturedAt: values.decode(Date.self, forKey: .capturedAt),
                usage: values.decode(TemporaryMediaUsage.self, forKey: .usage)),
            retryOf: values.decodeIfPresent(MediaOperationID.self, forKey: .retryOf))
    }
}

/// Replay retains the exact old owner/lease/epoch, including after SDK termination
/// and application restart. It is not itself evidence that an SDK owner ended.
nonisolated struct CommittedPhotoRegistrationIntent: Equatable, Sendable {
    let intent: PhotoRegistrationIntent
    let mediaUse: TemporaryMediaUseRecord
    let commit: BackendCommitReceipt
    var expectedStoreIdentity: RegistrationStoreIdentity? = nil
    var directoryIdentity: TemporaryFileIdentity? = nil
    var fileIdentity: TemporaryFileIdentity? = nil

    var isCommitted: Bool {
        mediaUse.usage == intent.usage
            && mediaUse.lease.target == .rendition(intent.rendition)
            && mediaUse.lease.context == .temporary(intent.media, intent.usage.id)
            && mediaUse.lease.epoch == intent.usage.epoch
            && !mediaUse.owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && commit.matches(.photo(intent.operation, intent.key), revision: commit.previousRevision)
    }
}

nonisolated enum PhotoRegistrationOutcome: Equatable, Sendable, Codable {
    /// The add API was never invoked. A new explicit retry can be considered.
    case notAttempted(PhotoLibraryFailure)
    /// True PhotoKit terminal success, independent of whether the identifier survived.
    case succeeded(localIdentifier: PhotoAssetIdentifier?)
    /// Terminal proof that no addition was committed. Ambiguous errors are unknown.
    case failed(PhotoLibraryFailure)
    case unknown(localIdentifier: PhotoAssetIdentifier?)

    var localIdentifier: PhotoAssetIdentifier? {
        switch self {
        case .succeeded(let value), .unknown(let value): value
        case .notAttempted, .failed: nil
        }
    }
    var permitsExplicitRetry: Bool {
        switch self { case .notAttempted, .failed: true; case .succeeded, .unknown: false }
    }
}

nonisolated struct PhotoRegistrationResult: Equatable, Sendable, Codable {
    let intent: PhotoRegistrationIntent
    let outcome: PhotoRegistrationOutcome
}

/// Not-found is only an observation within the current readable scope. It is
/// never evidence that the earlier addition failed or permission to add again.
nonisolated enum PhotoAssetPresence: Equatable, Sendable, Codable {
    case present, notFound, unavailable, correspondenceUnknown
}

nonisolated struct PhotoPresenceObservation: Equatable, Sendable, Codable {
    let intent: PhotoRegistrationIntent
    let generation: UInt64
    let identifier: PhotoAssetIdentifier?
    let authorization: PhotoLibraryAuthorization
    let presence: PhotoAssetPresence

    init(intent: PhotoRegistrationIntent, generation: UInt64, identifier: PhotoAssetIdentifier?,
         authorization: PhotoLibraryAuthorization, presence: PhotoAssetPresence) throws {
        self.intent = intent
        self.generation = generation
        self.identifier = identifier
        self.authorization = authorization
        self.presence = presence
        try validate()
    }

    func validate() throws {
        try intent.validate()
        guard generation > 0 else { throw BackendContractError.invalidValue }
        if let identifier { try PhotoRegistrationValueValidation.text(identifier.rawValue) }
        switch presence {
        case .present, .notFound:
            guard identifier != nil, authorization == .authorized || authorization == .limited else {
                throw BackendContractError.invalidValue
            }
        case .correspondenceUnknown:
            guard identifier == nil else { throw BackendContractError.invalidValue }
        case .unavailable:
            guard identifier != nil else { throw BackendContractError.invalidValue }
        }
    }

    private enum CodingKeys: String, CodingKey { case intent, generation, identifier, authorization, presence }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(intent: values.decode(PhotoRegistrationIntent.self, forKey: .intent),
            generation: values.decode(UInt64.self, forKey: .generation),
            identifier: values.decodeIfPresent(PhotoAssetIdentifier.self, forKey: .identifier),
            authorization: values.decode(PhotoLibraryAuthorization.self, forKey: .authorization),
            presence: values.decode(PhotoAssetPresence.self, forKey: .presence))
    }
}

/// Exact successful registration and the original usage to retire. The writer
/// checks these against its own replayed records; a caller-supplied receipt alone
/// cannot authorize releasing an old epoch or another consumer's usage.
nonisolated struct PhotoUsageRelease: Equatable, Sendable, Codable {
    let intent: PhotoRegistrationIntent
    let mediaUse: TemporaryMediaUseRecord
    let directoryIdentity: TemporaryFileIdentity
    let fileIdentity: TemporaryFileIdentity
    let successCommand: MediaOperationID
    let successCommit: BackendCommitReceipt

    init(record: PhotoRegistrationRecord) throws {
        guard let success = record.results.last, case .succeeded = success.result.outcome,
              let directoryIdentity = record.registration.directoryIdentity,
              let fileIdentity = record.registration.fileIdentity,
              success.commit.matches(.photo(success.command, record.registration.intent.key),
                                     revision: success.commit.previousRevision) else {
            throw BackendContractError.notCommitted
        }
        intent = record.registration.intent
        mediaUse = record.registration.mediaUse
        self.directoryIdentity = directoryIdentity
        self.fileIdentity = fileIdentity
        successCommand = success.command
        successCommit = success.commit
    }
}

/// SDK lifetime and Photos registration outcome are separate facts. A terminal
/// proves either definite non-start or the real completion plus closed local
/// access. It never promotes an unknown addition to success.
nonisolated enum PhotoUsageTermination: Equatable, Sendable, Codable {
    case notStarted, sdkCompleted
}

nonisolated struct PhotoUsageTerminal: Equatable, Sendable, Codable {
    let intent: PhotoRegistrationIntent
    let mediaUse: TemporaryMediaUseRecord
    let directoryIdentity: TemporaryFileIdentity
    let fileIdentity: TemporaryFileIdentity
    let termination: PhotoUsageTermination

    init(registration: CommittedPhotoRegistrationIntent, termination: PhotoUsageTermination) throws {
        guard registration.isCommitted, let directoryIdentity = registration.directoryIdentity,
              let fileIdentity = registration.fileIdentity else { throw BackendContractError.notCommitted }
        intent = registration.intent
        mediaUse = registration.mediaUse
        self.directoryIdentity = directoryIdentity
        self.fileIdentity = fileIdentity
        self.termination = termination
    }
}

/// Releases the original photo reader using an exact committed terminal, even
/// when the external addition remains unknown. Retention of its copy is derived
/// independently from registration results under the same writer.
nonisolated struct PhotoTerminalUsageRelease: Equatable, Sendable, Codable {
    let terminal: PhotoUsageTerminal
    let terminalCommand: MediaOperationID
    let terminalCommit: BackendCommitReceipt
    var intent: PhotoRegistrationIntent { terminal.intent }

    init(record: PhotoRegistrationRecord) throws {
        guard let value = record.usageTerminal,
              value.commit.matches(.photo(value.command, record.registration.intent.key),
                                   revision: value.commit.previousRevision) else {
            throw BackendContractError.notCommitted
        }
        terminal = value.terminal
        terminalCommand = value.command
        terminalCommit = value.commit
    }
}

nonisolated enum PhotoRegistrationChange: Equatable, Sendable, Codable {
    case intent(PhotoRegistrationIntent)
    case result(PhotoRegistrationResult)
    case presence(PhotoPresenceObservation)
    case releaseUsage(PhotoUsageRelease)
    case terminal(PhotoUsageTerminal)
    case releaseTerminalUsage(PhotoTerminalUsageRelease)

    var intent: PhotoRegistrationIntent {
        switch self {
        case .intent(let value): value
        case .result(let value): value.intent
        case .presence(let value): value.intent
        case .releaseUsage(let value): value.intent
        case .terminal(let value): value.intent
        case .releaseTerminalUsage(let value): value.intent
        }
    }
    var key: PhotoRegistrationKey { intent.key }
}

nonisolated struct StoredPhotoRegistrationResult: Equatable, Sendable {
    let command: MediaOperationID
    let result: PhotoRegistrationResult
    let commit: BackendCommitReceipt
    var expectedStoreIdentity: RegistrationStoreIdentity? = nil
}

nonisolated struct StoredPhotoPresenceObservation: Equatable, Sendable {
    let command: MediaOperationID
    let observation: PhotoPresenceObservation
    let commit: BackendCommitReceipt
    var expectedStoreIdentity: RegistrationStoreIdentity? = nil
}

nonisolated struct StoredPhotoUsageRelease: Equatable, Sendable {
    let command: MediaOperationID
    let release: PhotoUsageRelease
    let commit: BackendCommitReceipt
    var expectedStoreIdentity: RegistrationStoreIdentity? = nil
}

nonisolated struct StoredPhotoUsageTerminal: Equatable, Sendable {
    let command: MediaOperationID
    let terminal: PhotoUsageTerminal
    let commit: BackendCommitReceipt
    var expectedStoreIdentity: RegistrationStoreIdentity? = nil
}

nonisolated struct StoredPhotoTerminalUsageRelease: Equatable, Sendable {
    let command: MediaOperationID
    let release: PhotoTerminalUsageRelease
    let commit: BackendCommitReceipt
    var expectedStoreIdentity: RegistrationStoreIdentity? = nil
}

/// A disposable projection of the common writer, never a second metadata store.
nonisolated struct PhotoRegistrationRecord: Equatable, Sendable {
    let registration: CommittedPhotoRegistrationIntent
    var results: [StoredPhotoRegistrationResult] = []
    var presenceObservations: [StoredPhotoPresenceObservation] = []
    var usageRelease: StoredPhotoUsageRelease? = nil
    var usageTerminal: StoredPhotoUsageTerminal? = nil
    var terminalUsageRelease: StoredPhotoTerminalUsageRelease? = nil

    var outcome: PhotoRegistrationOutcome? { results.last?.result.outcome }
    var localIdentifier: PhotoAssetIdentifier? {
        results.reversed().compactMap { $0.result.outcome.localIdentifier }.first
    }
    var currentPresence: PhotoPresenceObservation? { presenceObservations.last?.observation }

    /// A terminal releases a reader, not its unsuccessful registration copy.
    /// Success of the latest explicit attempt on that same copy ends retention.
    static func retainsCopy(_ media: TemporaryMediaID, in records: [Self]) -> Bool {
        guard let last = records.last(where: { $0.registration.intent.media == media }) else { return false }
        if case .succeeded? = last.outcome { return false }
        return true
    }
}

/// Domain validation is also used by decoders; journal replay additionally
/// verifies the historical TemporaryMedia state under the single writer.
nonisolated enum PhotoRegistrationValueValidation {
    static func text(_ value: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BackendContractError.invalidValue
        }
    }
    static func rendition(_ value: RenditionIdentity) throws {
        try text(value.original.capture.rawValue)
        guard value.original.generation.rawValue > 0, value.publicationGeneration.rawValue > 0 else {
            throw BackendContractError.invalidValue
        }
        for content in [value.original.content, value.deliveryContent] {
            guard content.byteCount > 0, content.algorithm == "sha256", content.digest.count == 64,
                  content.digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                throw BackendContractError.invalidValue
            }
        }
        for textValue in [value.rendition.rawValue, value.inputLogIdentity, value.transformAssetIdentity,
                          value.transformAssetVersion, value.outputConfigurationIdentity, value.conversionVersion] {
            try text(textValue)
        }
    }
}
