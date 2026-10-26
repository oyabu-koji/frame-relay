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
    indirect case uploadChunk(lease: OriginalReadLease, chunk: ManagedUploadChunkIdentity, metadata: UploadChunkMetadataSelection)
    case download(rendition: RenditionIdentity, range: MediaByteRange?, lease: MediaReadLease)

    /// A live owner's inputs, never an authority to reconstruct or close a file.
    var uploadOwnership: BackgroundUploadOwnership? {
        switch self {
        case .upload(let session, let lease, let source):
            .init(macSession: session, originalLease: lease, source: source, descriptor: nil, metadata: nil)
        case .uploadChunk(let lease, let chunk, let metadata):
            .init(macSession: chunk.descriptor.range.binding.session, originalLease: lease, source: chunk.source,
                descriptor: chunk.descriptor, metadata: metadata)
        case .download: nil
        }
    }
}

nonisolated struct BackgroundUploadOwnership: Sendable {
    let macSession: UploadSessionID
    let originalLease: OriginalReadLease
    let source: ManagedUploadSourceIdentity
    let descriptor: UploadChunkDescriptor?
    let metadata: UploadChunkMetadataSelection?
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
        case .uploadChunk(let lease, let chunk, let metadata):
            try chunk.validate(); try metadata.validate()
            let binding = chunk.descriptor.range.binding
            guard UploadMetadataValidation.exact(context.target, MediaTarget.original(lease.original)),
                  UploadMetadataValidation.exact(context.operation, lease.operation),
                  UploadMetadataValidation.exact(binding.original, lease.original),
                  UploadMetadataValidation.exact(binding.operation, context.operation),
                  UploadMetadataValidation.exact(binding.registration, context.registration),
                  metadata.storeIdentity == context.storeIdentity else { throw BackendContractError.identityMismatch }
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
        if case .uploadChunk = intent.source { try requireExactChunkChange(change) }
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
            case .uploadChunk(_, let chunk, _):
                guard UploadMetadataValidation.exact(value.uploadSource, Optional(chunk.source)) else {
                    throw BackendContractError.identityMismatch
                }
            case .download: guard value.uploadSource == nil else { throw BackendContractError.identityMismatch }
            }
            ownerClosure = value
        }
    }

    private func requireExactChunkChange(_ change: BackgroundMediaTaskChange) throws {
        guard UploadMetadataValidation.exact(change.intent, intent) else { throw BackendContractError.identityMismatch }
        let incoming: BackgroundMediaTaskBinding?
        switch change {
        case .prepared, .stopRequested: incoming = nil
        case .attached(_, let value), .resumeRequested(_, let value): incoming = value
        case .terminal(_, let value): incoming = value.binding
        case .ownerClosed(_, let value): incoming = value.binding
        }
        if let incoming {
            guard UploadMetadataValidation.exact(incoming.session, intent.session),
                  incoming.taskDescription.utf8.elementsEqual(intent.taskDescription.utf8) else {
                throw BackendContractError.identityMismatch
            }
            if let binding, !UploadMetadataValidation.exact(incoming, binding) { throw BackendContractError.identityMismatch }
        }
    }
}

/// Ephemeral inputs to a pure guard. Array storage is shared, and this heap view
/// is never encoded into a source, journal event or SDK request.
nonisolated final class BackgroundUploadChunkAdmissionView: Sendable {
    let revision: UInt64
    let storeIdentity: RegistrationStoreIdentity?
    let registrations: [DeviceRegistration]
    let requests: [MediaRequest]
    let originals: [LogicalOriginalState]
    let queries: [CommittedUploadMetadataQuery]
    let observations: [StoredUploadMetadataObservation]
    let tasks: [BackgroundMediaTaskState]
    let journal: [OriginalRemovalTransportJournalFact]

    init(revision: UInt64, storeIdentity: RegistrationStoreIdentity?, registrations: [DeviceRegistration],
         requests: [MediaRequest], originals: [LogicalOriginalState], queries: [CommittedUploadMetadataQuery],
         observations: [StoredUploadMetadataObservation], tasks: [BackgroundMediaTaskState],
         journal: [OriginalRemovalTransportJournalFact]) {
        self.revision = revision; self.storeIdentity = storeIdentity; self.registrations = registrations
        self.requests = requests; self.originals = originals; self.queries = queries
        self.observations = observations; self.tasks = tasks; self.journal = journal
    }
}

/// Shared preliminary/final predicates. The caller supplies fresh, coherent
/// snapshot inputs or the writer's already-validated historical prefix. No
/// positive SDK permission, reader or receipt is constructed here.
nonisolated enum BackgroundUploadChunkAdmission {
    @inline(never)
    static func requireBeforeAttempt(context: BackgroundMediaRequestContext, range: UploadChunkRange,
        metadata: UploadChunkMetadataSelection, taskID: BackgroundMediaTaskID, sourceID: ManagedUploadSourceID,
        view: BackgroundUploadChunkAdmissionView) throws {
        let request = try requestIndex(context: context, range: range, metadata: metadata, view: view)
        guard view.requests[request].canRun, context.attempt != view.requests[request].attempt else {
            throw BackendContractError.wrongStage
        }
        try requireMetadata(context: context, range: range, metadata: metadata, request: request, view: view)
        try requireReaders(context: context, lease: nil, view: view)
        try requireHistory(context: context, metadata: metadata, taskID: taskID, sourceID: sourceID,
            current: nil, view: view)
    }

    /// A committed attempt has no descriptor until its actual copy finishes.
    /// Recheck that intermediate phase without inventing source bytes or a hash.
    @inline(never)
    static func requireReservedAttempt(context: BackgroundMediaRequestContext, range: UploadChunkRange,
        metadata: UploadChunkMetadataSelection, taskID: BackgroundMediaTaskID, sourceID: ManagedUploadSourceID,
        lease: OriginalReadLease?, view: BackgroundUploadChunkAdmissionView) throws {
        try requireActiveAttempt(context: context, range: range, metadata: metadata, taskID: taskID,
            sourceID: sourceID, lease: lease, current: nil, view: view)
    }

    @inline(never)
    static func requireCurrentAttempt(_ intent: BackgroundMediaTaskIntent, view: BackgroundUploadChunkAdmissionView) throws {
        try intent.validate()
        guard case .uploadChunk(let lease, let chunk, let metadata) = intent.source else {
            throw BackendContractError.identityMismatch
        }
        let context = intent.context, range = chunk.descriptor.range
        try requireActiveAttempt(context: context, range: range, metadata: metadata, taskID: intent.id,
            sourceID: chunk.source.id, lease: lease, current: intent, view: view)
    }

    @inline(never)
    private static func requireActiveAttempt(context: BackgroundMediaRequestContext, range: UploadChunkRange,
        metadata: UploadChunkMetadataSelection, taskID: BackgroundMediaTaskID, sourceID: ManagedUploadSourceID,
        lease: OriginalReadLease?, current: BackgroundMediaTaskIntent?, view: BackgroundUploadChunkAdmissionView) throws {
        let request = try requestIndex(context: context, range: range, metadata: metadata, view: view)
        guard UploadMetadataValidation.exact(view.requests[request].attempt, Optional(context.attempt)),
              view.requests[request].transport == .active, view.requests[request].intent == .running,
              view.requests[request].waits.isEmpty, !view.requests[request].playbackEnded else {
            throw BackendContractError.wrongStage
        }
        try requireMetadata(context: context, range: range, metadata: metadata, request: request, view: view)
        try requireReaders(context: context, lease: lease, view: view)
        try requireHistory(context: context, metadata: metadata, taskID: taskID, sourceID: sourceID, current: current, view: view)
        let begin = try beginRevision(context: context, view: view)
        guard metadata.committedRevision < begin, begin <= view.revision else { throw BackendContractError.wrongStage }
    }

    @inline(never)
    private static func requestIndex(context: BackgroundMediaRequestContext, range: UploadChunkRange,
        metadata: UploadChunkMetadataSelection, view: BackgroundUploadChunkAdmissionView) throws -> Int {
        try range.validate(); try metadata.validate()
        guard context.storeIdentity == view.storeIdentity, metadata.storeIdentity == view.storeIdentity,
              context.gateGeneration > 0, metadata.committedRevision <= view.revision,
              UploadMetadataValidation.exact(context.target, MediaTarget.original(range.binding.original)),
              UploadMetadataValidation.exact(context.operation, range.binding.operation),
              UploadMetadataValidation.exact(context.registration, range.binding.registration) else {
            throw BackendContractError.identityMismatch
        }
        let matches = view.requests.indices.filter { view.requests[$0].operation == context.operation }
        guard matches.count == 1, let index = matches.first, view.requests[index].purpose == .upload,
              view.requests[index].startCommitted, UploadMetadataValidation.exact(view.requests[index].operation, context.operation),
              UploadMetadataValidation.exact(view.requests[index].target, context.target),
              UploadMetadataValidation.exact(view.requests[index].registration, context.registration),
              UploadMetadataValidation.exact(view.requests[index].session, Optional(range.binding.session)),
              let current = view.registrations.last(where: { $0.server.registration.destination == context.registration.destination }),
              current.isCommitted, UploadMetadataValidation.exact(current.server.registration, context.registration) else {
            throw BackendContractError.identityMismatch
        }
        return index
    }

    @inline(never)
    private static func requireMetadata(context: BackgroundMediaRequestContext, range: UploadChunkRange,
        metadata: UploadChunkMetadataSelection, request: Int, view: BackgroundUploadChunkAdmissionView) throws {
        let matches = view.observations.indices.filter { metadata.matches(view.observations[$0]) }
        guard matches.count == 1, let index = matches.first else { throw BackendContractError.notCommitted }
        try requireSelectedObservation(at: index, context: context, range: range, metadata: metadata, request: request, view: view)
    }

    @inline(never)
    private static func requireSelectedObservation(at index: Int, context: BackgroundMediaRequestContext, range: UploadChunkRange,
        metadata: UploadChunkMetadataSelection, request: Int, view: BackgroundUploadChunkAdmissionView) throws {
        let saved = view.observations[index], query = saved.observation.query
        guard saved.isCommitted, query.isCommitted, saved.expectedStoreIdentity == view.storeIdentity,
              query.expectedStoreIdentity == view.storeIdentity, query.query.request.matches(view.requests[request]),
              UploadMetadataValidation.exact(query.query.request.original, range.binding.original),
              case .lookup(let session) = query.query.kind, UploadMetadataValidation.exact(session, range.binding.session),
              case .status(let status) = saved.observation.response, status.state == .receiving,
              UploadMetadataValidation.exact(status.binding, range.binding), !status.chunkIndexes.contains(range.index),
              view.requests[request].lastObservation == metadata.observationGeneration,
              view.requests[request].uploadMetadataPending == nil, view.requests[request].uploadMetadataHold == nil,
              view.requests[request].remote == .inProgress,
              let current = view.registrations.last(where: { $0.server.registration.destination == context.registration.destination }),
              UploadMetadataValidation.exact(current, query.query.request.registration) else {
            throw BackendContractError.wrongStage
        }
        let reservations = view.queries.indices.filter { view.queries[$0].query.request.operation == context.operation }
        guard !reservations.isEmpty,
              reservations.allSatisfy({ UploadMetadataValidation.exact(view.queries[$0].query.request.operation, context.operation) }),
              reservations.map({ view.queries[$0].query.generation.rawValue }).max() == metadata.observationGeneration.rawValue,
              reservations.filter({ UploadMetadataValidation.exact(view.queries[$0], query) }).count == 1,
              query.commit.committedRevision <= saved.commit.previousRevision else { throw BackendContractError.staleGeneration }
        try requireFact(query.mutation, receipt: query.commit, view: view)
        try requireFact(saved.mutation, receipt: saved.commit, view: view)
    }

    @inline(never)
    private static func requireReaders(context: BackgroundMediaRequestContext, lease: OriginalReadLease?,
                                       view: BackgroundUploadChunkAdmissionView) throws {
        if let lease {
            guard UploadMetadataValidation.exact(lease.original, context.target.original),
                  UploadMetadataValidation.exact(lease.operation, context.operation) else {
                throw BackendContractError.identityMismatch
            }
        }
        let candidates = view.originals.indices.filter { view.originals[$0].original.capture == context.target.original.capture }
        guard candidates.count == 1, let index = candidates.first,
              UploadMetadataValidation.exact(view.originals[index].original, context.target.original),
              let binding = view.originals[index].binding, OriginalUploadAcceptanceValueValidation.savedBinding(binding),
              UploadMetadataValidation.exact(binding.original, context.target.original),
              view.originals[index].removal == nil, view.originals[index].invalidation == nil,
              view.originals[index].removalResolution != .removed else { throw BackendContractError.deletionUnresolved }
        var count = 0
        for state in view.originals {
            for reader in state.readers where reader.operation == context.operation {
                guard let lease, UploadMetadataValidation.exact(reader, lease) else { throw BackendContractError.readersActive }
                count += 1
            }
        }
        guard count == (lease == nil ? 0 : 1) else { throw BackendContractError.readersActive }
    }

    @inline(never)
    private static func requireHistory(context: BackgroundMediaRequestContext, metadata: UploadChunkMetadataSelection,
        taskID: BackgroundMediaTaskID, sourceID: ManagedUploadSourceID, current: BackgroundMediaTaskIntent?,
        view: BackgroundUploadChunkAdmissionView) throws {
        guard !taskID.rawValue.isEmpty, !context.attempt.rawValue.isEmpty,
              UUID(uuidString: sourceID.rawValue) != nil else { throw BackendContractError.invalidValue }
        let queryRevision = try selectedQueryRevision(metadata, view: view)
        var currentCount = 0
        for task in view.tasks {
            if task.intent.id == taskID {
                guard let current, UploadMetadataValidation.exact(task.intent, current), task.terminal == nil,
                      task.ownerClosure == nil else { throw BackendContractError.duplicateTarget }
                currentCount += 1
                continue
            }
            if let source = task.intent.source.uploadOwnership?.source,
               sameSourceID(source.id, sourceID) { throw BackendContractError.duplicateTarget }
            guard task.intent.context.operation == context.operation else { continue }
            guard UploadMetadataValidation.exact(task.intent.context.operation, context.operation),
                  task.intent.context.attempt != context.attempt,
                  case .uploadChunk(let oldLease, _, _) = task.intent.source,
                  UploadMetadataValidation.exact(task.intent.context.target, context.target),
                  UploadMetadataValidation.exact(task.intent.context.registration, context.registration),
                  task.intent.context.storeIdentity == context.storeIdentity else { throw BackendContractError.identityMismatch }
            if let current, let lease = current.source.uploadOwnership?.originalLease, lease.id == oldLease.id {
                throw BackendContractError.duplicateTarget
            }
            let stopped = try stoppedRevision(task, journal: view.journal, through: view.revision)
            guard queryRevision > stopped, metadata.committedRevision > stopped else { throw BackendContractError.staleGeneration }
        }
        guard currentCount <= 1 else { throw BackendContractError.duplicateTarget }
    }

    private static func selectedQueryRevision(_ metadata: UploadChunkMetadataSelection,
                                              view: BackgroundUploadChunkAdmissionView) throws -> UInt64 {
        let matches = view.queries.indices.filter { UploadMetadataValidation.exact(view.queries[$0].query.id, metadata.queryID) }
        guard matches.count == 1, let index = matches.first else { throw BackendContractError.notCommitted }
        return view.queries[index].commit.committedRevision
    }

    @inline(never)
    static func stoppedRevision(_ task: BackgroundMediaTaskState, journal: [OriginalRemovalTransportJournalFact],
                                through revision: UInt64) throws -> UInt64 {
        try task.intent.validate()
        guard case .uploadChunk(_, let chunk, _) = task.intent.source,
              let binding = task.binding, let terminal = task.terminal, let closure = task.ownerClosure,
              UploadMetadataValidation.exact(binding, terminal.binding), UploadMetadataValidation.exact(binding, closure.binding),
              UploadMetadataValidation.exact(closure.uploadSource, Optional(chunk.source)), closure.tasksJoined, closure.handlesClosed,
              let closed = task.events.last(where: { if case .ownerClosed = $0.change { return true }; return false }),
              case .ownerClosed(_, let actualClosure) = closed.change, UploadMetadataValidation.exact(actualClosure, closure),
              let ended = task.events.last(where: { if case .terminal = $0.change { return true }; return false }),
              case .terminal(_, let actualTerminal) = ended.change, UploadMetadataValidation.exact(actualTerminal, terminal),
              ended.commit.committedRevision < closed.commit.committedRevision,
              let prepared = task.events.first, case .prepared = prepared.change else { throw BackendContractError.readersActive }
        for event in task.events {
            guard event.storeIdentity == task.intent.context.storeIdentity,
                  UploadMetadataValidation.exact(event.change.intent, task.intent) else { throw BackendContractError.identityMismatch }
            try requireFact(event.mutation, receipt: event.commit, identity: task.intent.context.storeIdentity,
                journal: journal, through: revision)
        }
        let context = task.intent.context
        var stops: [UInt64] = []
        for fact in journal {
            guard fact.commit.committedRevision <= revision,
                  case .requestTransition(_, let operation, let target, let registration, .stopped(let value)) = fact.mutation.change,
                  UploadMetadataValidation.exact(operation, context.operation),
                  UploadMetadataValidation.exact(target, context.target), UploadMetadataValidation.exact(registration, context.registration),
                  UploadMetadataValidation.exact(value, TransportStopReceipt(operation: context.operation, attempt: context.attempt,
                    target: context.target, registration: context.registration)) else { continue }
            try requireFact(fact.mutation, receipt: fact.commit, identity: context.storeIdentity, journal: journal, through: revision)
            guard fact.commit.committedRevision > closed.commit.committedRevision else { throw BackendContractError.wrongStage }
            stops.append(fact.commit.committedRevision)
        }
        guard stops.count == 1, let stopped = stops.first else { throw BackendContractError.notCommitted }
        return stopped
    }

    @inline(never)
    private static func beginRevision(context: BackgroundMediaRequestContext, view: BackgroundUploadChunkAdmissionView) throws -> UInt64 {
        var revisions: [UInt64] = []
        for fact in view.journal {
            guard case .requestTransition(_, let operation, let target, let registration, .beginAttempt(let attempt)) = fact.mutation.change,
                  operation == context.operation, attempt == context.attempt else { continue }
            guard UploadMetadataValidation.exact(operation, context.operation), UploadMetadataValidation.exact(attempt, context.attempt),
                  UploadMetadataValidation.exact(target, context.target), UploadMetadataValidation.exact(registration, context.registration) else {
                throw BackendContractError.identityMismatch
            }
            try requireFact(fact.mutation, receipt: fact.commit, view: view)
            revisions.append(fact.commit.committedRevision)
        }
        guard revisions.count == 1, let revision = revisions.first else { throw BackendContractError.notCommitted }
        return revision
    }

    private static func requireFact(_ mutation: BackendStoreMutation, receipt: BackendCommitReceipt,
                                    view: BackgroundUploadChunkAdmissionView) throws {
        guard let identity = view.storeIdentity else { throw BackendContractError.identityMismatch }
        try requireFact(mutation, receipt: receipt, identity: identity, journal: view.journal, through: view.revision)
    }

    @inline(never)
    private static func requireFact(_ mutation: BackendStoreMutation, receipt: BackendCommitReceipt, identity: RegistrationStoreIdentity,
        journal: [OriginalRemovalTransportJournalFact], through revision: UInt64) throws {
        guard mutation.expectedStoreIdentity == identity, receipt.committedRevision <= revision,
              receipt.matches(mutation.change.key, revision: mutation.expectedRevision),
              UploadMetadataValidation.exact(receipt.key, mutation.change.key),
              journal.filter({ UploadMetadataValidation.exact($0.mutation, mutation)
                  && UploadMetadataValidation.exact($0.commit, receipt) }).count == 1 else { throw BackendContractError.notCommitted }
    }

    private static func sameSourceID(_ left: ManagedUploadSourceID, _ right: ManagedUploadSourceID) -> Bool {
        left == right || (UUID(uuidString: left.rawValue) != nil && UUID(uuidString: left.rawValue) == UUID(uuidString: right.rawValue))
    }
}
