import Foundation

nonisolated struct BackgroundMediaTaskID: Hashable, Sendable, Codable { let rawValue: String }
nonisolated struct BackgroundMediaSessionID: Hashable, Sendable, Codable { let rawValue: String }
nonisolated struct BackgroundMediaSessionGeneration: Hashable, Sendable, Codable { let rawValue: UUID }

/// The OS session namespace is independent of the Mac's UploadSessionID.
nonisolated struct BackgroundMediaSessionIdentity: Hashable, Sendable, Codable {
    let identifier: BackgroundMediaSessionID
    let generation: BackgroundMediaSessionGeneration
}

/// A digest of the safe, fixed request description, never credentials or a URL.
nonisolated struct BackgroundMediaRequestFingerprint: Equatable, Sendable, Codable { let sha256: String }
nonisolated struct ManagedUploadSourceID: Hashable, Sendable, Codable { let rawValue: String }

/// A Codable copy of the observed file facts. OriginalFileFingerprint stays an
/// ephemeral descriptor observation and is not changed for this journal.
nonisolated struct ManagedUploadFileIdentity: Equatable, Sendable, Codable {
    let device: Int64
    let inode: UInt64
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64
}

nonisolated struct ManagedUploadSourceIdentity: Equatable, Sendable, Codable {
    let id: ManagedUploadSourceID
    let directoryDevice: Int64
    let directoryInode: UInt64
    let file: ManagedUploadFileIdentity
    let content: ContentIdentity
}

nonisolated struct BackgroundMediaRequestContext: Equatable, Sendable, Codable {
    let operation: MediaOperationID
    let attempt: TransferAttemptID
    let target: MediaTarget
    let registration: RegistrationIdentity
    let gateGeneration: UInt64
    let storeIdentity: RegistrationStoreIdentity
}

nonisolated enum BackgroundMediaTaskSource: Equatable, Sendable, Codable {
    case upload(session: UploadSessionID, lease: OriginalReadLease, source: ManagedUploadSourceIdentity)
    case download(rendition: RenditionIdentity, range: MediaByteRange?, lease: MediaReadLease)
}

/// Persist before the suspended task factory is invoked. Its nonce is not
/// authority to adopt an enumerated task after a create/attach interruption.
nonisolated struct BackgroundMediaTaskIntent: Equatable, Sendable, Codable {
    let id: BackgroundMediaTaskID
    let context: BackgroundMediaRequestContext
    let session: BackgroundMediaSessionIdentity
    let taskDescription: String
    let requestFingerprint: BackgroundMediaRequestFingerprint
    let source: BackgroundMediaTaskSource

    func validate() throws {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard !id.rawValue.isEmpty, !context.operation.rawValue.isEmpty, !context.attempt.rawValue.isEmpty,
              context.gateGeneration > 0, !session.identifier.rawValue.isEmpty, session.identifier.rawValue.utf8.count <= 255,
              session.identifier.rawValue.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              let nonce = UUID(uuidString: taskDescription), nonce.uuidString.caseInsensitiveCompare(taskDescription) == .orderedSame,
              requestFingerprint.sha256.utf8.count == 64,
              requestFingerprint.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw BackendContractError.invalidValue
        }
        switch source {
        case .upload(let session, let lease, let source):
            guard !session.rawValue.isEmpty, context.target == .original(lease.original), context.operation == lease.operation,
                  source.content == lease.original.content, UUID(uuidString: source.id.rawValue) != nil,
                  source.directoryInode > 0, source.file.inode > 0, source.file.size > 0,
                  UInt64(source.file.size) == source.content.byteCount,
                  (0..<1_000_000_000).contains(source.file.modifiedNanoseconds),
                  (0..<1_000_000_000).contains(source.file.changedNanoseconds) else { throw BackendContractError.identityMismatch }
        case .download(let rendition, let range, let lease):
            guard context.target == .rendition(rendition), lease.target == context.target,
                  lease.operation == context.operation, lease.registration == context.registration,
                  lease.context == .transport(context.attempt) else { throw BackendContractError.identityMismatch }
            if let range, range.upperBound > rendition.deliveryContent.byteCount { throw BackendContractError.identityMismatch }
        }
    }
}

nonisolated struct BackgroundMediaTaskBinding: Equatable, Sendable, Codable {
    let session: BackgroundMediaSessionIdentity
    let taskIdentifier: Int
    let taskDescription: String
}

/// An actual didComplete callback. None of these outcomes is a Mac save,
/// verification, remote non-execution, or proof that another task has stopped.
nonisolated enum BackgroundMediaSDKOutcome: Equatable, Sendable, Codable {
    case completed, cancelled
    case failed(code: Int)
}
nonisolated struct BackgroundMediaSDKTerminal: Equatable, Sendable, Codable {
    let binding: BackgroundMediaTaskBinding
    let outcome: BackgroundMediaSDKOutcome
}

/// Supplied after this exact SDK owner joined and its own descriptors closed.
/// Recording it does not release a durable original/media lease.
nonisolated struct BackgroundMediaOwnerClosure: Equatable, Sendable, Codable {
    let binding: BackgroundMediaTaskBinding
    let uploadSource: ManagedUploadSourceIdentity?
    let tasksJoined: Bool
    let handlesClosed: Bool
}

nonisolated enum BackgroundMediaTaskChange: Equatable, Sendable, Codable {
    case prepared(BackgroundMediaTaskIntent)
    case attached(BackgroundMediaTaskIntent, BackgroundMediaTaskBinding)
    case resumeRequested(BackgroundMediaTaskIntent, BackgroundMediaTaskBinding)
    case stopRequested(BackgroundMediaTaskIntent)
    case terminal(BackgroundMediaTaskIntent, BackgroundMediaSDKTerminal)
    case ownerClosed(BackgroundMediaTaskIntent, BackgroundMediaOwnerClosure)

    var intent: BackgroundMediaTaskIntent {
        switch self {
        case .prepared(let value), .attached(let value, _), .resumeRequested(let value, _),
             .stopRequested(let value), .terminal(let value, _), .ownerClosed(let value, _): value
        }
    }
}

nonisolated struct StoredBackgroundMediaTaskEvent: Equatable, Sendable {
    let command: MediaOperationID
    let change: BackgroundMediaTaskChange
    let commit: BackendCommitReceipt
    let storeIdentity: RegistrationStoreIdentity

    var mutation: BackendStoreMutation {
        .init(expectedRevision: commit.previousRevision, change: .backgroundTask(command: command, value: change),
            expectedStoreIdentity: storeIdentity)
    }
}

/// Preparation, stop requests, SDK termination, and file closure are separate
/// facts. In particular, an unattached prepared intent stays unresolved.
nonisolated struct BackgroundMediaTaskState: Equatable, Sendable {
    let intent: BackgroundMediaTaskIntent
    private(set) var binding: BackgroundMediaTaskBinding?
    private(set) var resumeRequested = false
    private(set) var stopRequested = false
    private(set) var terminal: BackgroundMediaSDKTerminal?
    private(set) var ownerClosure: BackgroundMediaOwnerClosure?
    var events: [StoredBackgroundMediaTaskEvent] = []

    init(intent: BackgroundMediaTaskIntent) { self.intent = intent }

    mutating func apply(_ change: BackgroundMediaTaskChange) throws {
        try change.intent.validate()
        guard change.intent == intent else { throw BackendContractError.identityMismatch }
        switch change {
        case .prepared: throw BackendContractError.wrongStage
        case .attached(_, let value):
            guard binding == nil, ownerClosure == nil,
                  value.session == intent.session, value.taskDescription == intent.taskDescription,
                  value.taskIdentifier > 0 else { throw BackendContractError.identityMismatch }
            binding = value
        case .resumeRequested(_, let value):
            guard binding == value else { throw BackendContractError.identityMismatch }
            guard !resumeRequested, !stopRequested, terminal == nil, ownerClosure == nil else { throw BackendContractError.wrongStage }
            resumeRequested = true
        case .stopRequested:
            guard ownerClosure == nil else { throw BackendContractError.wrongStage }
            stopRequested = true
        case .terminal(_, let value):
            guard binding == value.binding else { throw BackendContractError.identityMismatch }
            guard ownerClosure == nil, terminal == nil || terminal == value else { throw BackendContractError.wrongStage }
            terminal = value
        case .ownerClosed(_, let value):
            guard binding == value.binding else { throw BackendContractError.identityMismatch }
            guard terminal != nil, ownerClosure == nil, value.tasksJoined, value.handlesClosed else { throw BackendContractError.readersActive }
            switch intent.source {
            case .upload(_, _, let source): guard value.uploadSource == source else { throw BackendContractError.identityMismatch }
            case .download: guard value.uploadSource == nil else { throw BackendContractError.identityMismatch }
            }
            ownerClosure = value
        }
    }
}
