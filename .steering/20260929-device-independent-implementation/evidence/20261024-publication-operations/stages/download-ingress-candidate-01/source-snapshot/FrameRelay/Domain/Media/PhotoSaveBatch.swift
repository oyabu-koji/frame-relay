import Foundation

/// An immutable local candidate. Metadata alone never proves current file bytes
/// or grants permission to invoke Photos; the consumer still resolves its own use.
nonisolated struct PhotoSaveSource: Equatable, Sendable, Codable {
    let storeIdentity: RegistrationStoreIdentity
    let registration: RegistrationIdentity
    let rendition: RenditionIdentity
    let media: TemporaryMediaID
    let capturedAt: Date
    let directoryIdentity: TemporaryFileIdentity
    let fileIdentity: TemporaryFileIdentity
    let leaf: String
    let contentType: String
    var key: PhotoRegistrationKey { .init(rendition: rendition) }

    func validate() throws {
        try PhotoRegistrationValueValidation.rendition(rendition)
        for value in [registration.destination.rawValue, registration.id.rawValue, media.rawValue] {
            try PhotoRegistrationValueValidation.text(value)
        }
        try TemporaryMediaLeaf.validate(leaf, contentType: contentType)
        guard registration.generation.rawValue > 0, capturedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw BackendContractError.invalidValue
        }
    }
}

nonisolated struct PhotoSaveBatchTarget: Equatable, Sendable, Codable {
    let source: PhotoSaveSource
    let operation: MediaOperationID
    let retryOf: MediaOperationID?
    var key: PhotoRegistrationKey { source.key }

    init(source: PhotoSaveSource, operation: MediaOperationID, retryOf: MediaOperationID? = nil) throws {
        self.source = source; self.operation = operation; self.retryOf = retryOf
        try validate()
    }
    func validate() throws {
        try source.validate()
        try PhotoRegistrationValueValidation.text(operation.rawValue)
        if let retryOf {
            try PhotoRegistrationValueValidation.text(retryOf.rawValue)
            guard retryOf != operation else { throw BackendContractError.invalidValue }
        }
    }
    private enum CodingKeys: String, CodingKey { case source, operation, retryOf }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(source: values.decode(PhotoSaveSource.self, forKey: .source),
            operation: values.decode(MediaOperationID.self, forKey: .operation),
            retryOf: values.decodeIfPresent(MediaOperationID.self, forKey: .retryOf))
    }
}

/// The order and every target are fixed by the explicit user action. A later
/// candidate or a changed source cannot be substituted into an accepted batch.
nonisolated struct PhotoSaveBatch: Equatable, Sendable, Codable {
    let operation: MediaOperationID
    let storeIdentity: RegistrationStoreIdentity
    let targets: [PhotoSaveBatchTarget]

    init(operation: MediaOperationID, storeIdentity: RegistrationStoreIdentity,
         targets: [PhotoSaveBatchTarget]) throws {
        self.operation = operation; self.storeIdentity = storeIdentity; self.targets = targets
        try validate()
    }
    func validate() throws {
        try PhotoRegistrationValueValidation.text(operation.rawValue)
        guard !targets.isEmpty else { throw BackendContractError.invalidValue }
        var operations = Set<MediaOperationID>()
        var keys: [PhotoRegistrationKey] = []
        for target in targets {
            try target.validate()
            guard target.source.storeIdentity == storeIdentity, target.operation != operation,
                  operations.insert(target.operation).inserted,
                  !keys.contains(where: { PhotoSaveBatchValueValidation.exact($0, target.key) }) else {
                throw BackendContractError.duplicateTarget
            }
            keys.append(target.key)
        }
    }
    private enum CodingKeys: String, CodingKey { case operation, storeIdentity, targets }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(operation: values.decode(MediaOperationID.self, forKey: .operation),
            storeIdentity: values.decode(RegistrationStoreIdentity.self, forKey: .storeIdentity),
            targets: values.decode([PhotoSaveBatchTarget].self, forKey: .targets))
    }
}

nonisolated enum PhotoSaveBatchNonProcessing: Equatable, Sendable, Codable {
    case cancelled, ineligible, unavailable
}

nonisolated enum PhotoSaveBatchChange: Equatable, Sendable, Codable {
    case accept(PhotoSaveBatch)
    case beginChild(batch: MediaOperationID, target: PhotoSaveBatchTarget)
    case notProcessed(batch: MediaOperationID, target: PhotoSaveBatchTarget, reason: PhotoSaveBatchNonProcessing)

    var batch: MediaOperationID {
        switch self {
        case .accept(let value): value.operation
        case .beginChild(let batch, _), .notProcessed(let batch, _, _): batch
        }
    }
}

/// A durable start decision, not a replayable SDK-start capability. After a
/// restart a starting child without a terminal result remains uncertain.
nonisolated struct CommittedPhotoSaveBatchChild: Equatable, Sendable {
    let batch: MediaOperationID
    let target: PhotoSaveBatchTarget
    let command: MediaOperationID
    let commit: BackendCommitReceipt
    let expectedStoreIdentity: RegistrationStoreIdentity
    var isCommitted: Bool {
        PhotoSaveBatchValueValidation.exact(command, target.operation)
            && expectedStoreIdentity == target.source.storeIdentity
            && commit.matches(.photoBatch(command, batch), revision: commit.previousRevision)
            && PhotoSaveBatchValueValidation.exact(commit.key, BackendCommitKey.photoBatch(command, batch))
    }
}

nonisolated struct StoredPhotoSaveBatchNonProcessing: Equatable, Sendable {
    let batch: MediaOperationID
    let target: PhotoSaveBatchTarget
    let reason: PhotoSaveBatchNonProcessing
    let command: MediaOperationID
    let commit: BackendCommitReceipt
    let expectedStoreIdentity: RegistrationStoreIdentity
}

// This disposable projection carries sizeable commit/source values. Boxing the
// phase payload keeps copying a queued row independent of those payload sizes.
nonisolated indirect enum PhotoSaveBatchChildStatus: Equatable, Sendable {
    case queued
    case starting(CommittedPhotoSaveBatchChild)
    case notProcessed(StoredPhotoSaveBatchNonProcessing)
}

nonisolated struct PhotoSaveBatchChildRecord: Equatable, Sendable {
    let target: PhotoSaveBatchTarget
    var status: PhotoSaveBatchChildStatus = .queued
    /// Joined from the existing Photos journal, never a second success state.
    var registration: PhotoRegistrationRecord? = nil
    var outcome: PhotoRegistrationOutcome? { registration?.outcome }
}

nonisolated struct PhotoSaveBatchRecord: Equatable, Sendable {
    let batch: PhotoSaveBatch
    let command: MediaOperationID
    let commit: BackendCommitReceipt
    let expectedStoreIdentity: RegistrationStoreIdentity
    var targets: [PhotoSaveBatchChildRecord]
    var isCommitted: Bool {
        expectedStoreIdentity == batch.storeIdentity && PhotoSaveBatchValueValidation.exact(command, batch.operation)
            && commit.matches(.photoBatch(command, batch.operation), revision: commit.previousRevision)
            && PhotoSaveBatchValueValidation.exact(commit.key, BackendCommitKey.photoBatch(command, batch.operation))
    }
}

nonisolated enum PhotoSaveBatchValueValidation {
    /// Local exact comparison only. Swift String equality normalizes Unicode;
    /// capture/source/command identities in a durable decision must not do so.
    static func exact<T: Encodable>(_ lhs: T, _ rhs: T) -> Bool {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let left = try? encoder.encode(lhs), let right = try? encoder.encode(rhs) else { return false }
        return left == right
    }
}
