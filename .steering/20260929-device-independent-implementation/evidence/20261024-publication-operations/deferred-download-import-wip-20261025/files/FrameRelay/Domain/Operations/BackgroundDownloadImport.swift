import CryptoKit
import Foundation

/// LOCAL writer stages. An issued control-plane ticket is not an observed GET.
nonisolated enum BackgroundDownloadObservationStage: String, Equatable, Sendable, Codable {
    case issuedTicket, response, sourceClosed, imported
}

nonisolated enum BackgroundDownloadValue {
    static func exact<T: Encodable>(_ a: T, _ b: T) -> Bool { UploadMetadataValidation.exact(a, b) }
    static func fingerprint<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func digest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    static func text(_ value: String) throws {
        guard !value.isEmpty, !value.contains("\0") else { throw BackendContractError.invalidValue }
    }
}

/// Compact facts only. Every reference must be joined to an actual prefix entry.
nonisolated struct BackgroundDownloadBackendReference: Equatable, Sendable, Codable {
    let storeIdentity: RegistrationStoreIdentity
    let command: MediaOperationID
    let fingerprint: String
    let commit: BackendCommitReceipt
    init(_ mutation: BackendStoreMutation, commit: BackendCommitReceipt) throws {
        guard let identity = mutation.expectedStoreIdentity, commit.matches(mutation.change.key, revision: mutation.expectedRevision),
              BackgroundDownloadValue.exact(commit.key, mutation.change.key) else { throw BackendContractError.notCommitted }
        storeIdentity = identity; command = .init(rawValue: mutation.change.key.commandText)
        fingerprint = BackgroundDownloadValue.fingerprint(mutation); self.commit = commit
        try validate()
    }
    func validate() throws {
        try BackgroundDownloadValue.text(command.rawValue)
        guard BackgroundDownloadValue.digest(fingerprint), commit.key.commandText.utf8.elementsEqual(command.rawValue.utf8),
              commit.matches(commit.key, revision: commit.previousRevision) else { throw BackendContractError.notCommitted }
    }
    func matches(_ mutation: BackendStoreMutation, receipt: BackendCommitReceipt) -> Bool {
        mutation.expectedStoreIdentity == storeIdentity && BackgroundDownloadValue.exact(receipt, commit)
            && BackgroundDownloadValue.fingerprint(mutation).utf8.elementsEqual(fingerprint.utf8)
    }
}

nonisolated struct BackgroundDownloadLeaseReference: Equatable, Sendable, Codable {
    let command: MediaOperationID
    let fingerprint: String
    let commit: OriginalStoreCommitReceipt
    init(_ mutation: OriginalStoreMutation, commit: OriginalStoreCommitReceipt) throws {
        command = mutation.operation; fingerprint = BackgroundDownloadValue.fingerprint(mutation); self.commit = commit
        try validate()
        guard matches(mutation, receipt: commit) else { throw BackendContractError.notCommitted }
    }
    func validate() throws {
        try BackgroundDownloadValue.text(command.rawValue)
        let next = commit.previousRevision.addingReportingOverflow(1)
        guard !next.overflow, next.partialValue == commit.committedRevision,
              BackgroundDownloadValue.exact(command, commit.operation), BackgroundDownloadValue.digest(fingerprint) else {
            throw BackendContractError.notCommitted
        }
    }
    func matches(_ mutation: OriginalStoreMutation, receipt: OriginalStoreCommitReceipt) -> Bool {
        BackgroundDownloadValue.exact(mutation.operation, command) && mutation.expectedRevision == commit.previousRevision
            && BackgroundDownloadValue.exact(receipt, commit) && BackgroundDownloadValue.fingerprint(mutation) == fingerprint
    }
}

/// Pre-P reference: no prepared-task cycle, no full snapshot/mutation embedded.
nonisolated struct BackgroundDownloadPlannedIntentReference: Equatable, Sendable, Codable {
    let taskID: BackgroundMediaTaskID
    let context: BackgroundMediaRequestContext
    let rendition: RenditionIdentity
    let transportLease: MediaReadLease
    let intentFingerprint: String
    init(_ intent: BackgroundMediaTaskIntent) throws {
        try intent.validate()
        guard case .download(let rendition, nil, let lease) = intent.source else { throw BackendContractError.invalidValue }
        taskID = intent.id; context = intent.context; self.rendition = rendition; transportLease = lease
        intentFingerprint = BackgroundDownloadValue.fingerprint(intent)
        try validate()
    }
    func validate() throws {
        try BackgroundDownloadValue.text(taskID.rawValue)
        try UploadMetadataValidation.original(rendition.original)
        guard BackgroundDownloadValue.digest(intentFingerprint), context.gateGeneration > 0,
              BackgroundDownloadValue.exact(context.target, MediaTarget.rendition(rendition)),
              BackgroundDownloadValue.exact(transportLease.target, context.target),
              BackgroundDownloadValue.exact(transportLease.operation, context.operation),
              BackgroundDownloadValue.exact(transportLease.registration, context.registration),
              BackgroundDownloadValue.exact(transportLease.context, MediaReadContext.transport(context.attempt)) else {
            throw BackendContractError.identityMismatch
        }
    }
    func matches(_ intent: BackgroundMediaTaskIntent) -> Bool {
        BackgroundDownloadValue.exact(taskID, intent.id) && BackgroundDownloadValue.exact(context, intent.context)
            && BackgroundDownloadValue.fingerprint(intent) == intentFingerprint
    }
}

nonisolated struct BackgroundDownloadReadTicketRequest: Equatable, Sendable, Codable {
    let operation: MediaOperationID
    let source: MediaOperationID
    let context: BackgroundMediaRequestContext
    let rendition: RenditionIdentity
    init(_ request: PublicationDistributionRequest, context: BackgroundMediaRequestContext) throws {
        guard request.purpose == .read, request.kind == .full, request.range == nil, let source = request.source,
              BackgroundDownloadValue.exact(request.gate.operation, context.operation),
              BackgroundDownloadValue.exact(request.gate.attempt, context.attempt),
              BackgroundDownloadValue.exact(request.gate.target, context.target),
              BackgroundDownloadValue.exact(request.gate.registration, context.registration),
              request.gate.generation == context.gateGeneration else { throw BackendContractError.identityMismatch }
        operation = request.operation; self.source = source; self.context = context; rendition = request.rendition
        try validate()
    }
    func validate() throws {
        try BackgroundDownloadValue.text(operation.rawValue); try BackgroundDownloadValue.text(source.rawValue)
        guard !BackgroundDownloadValue.exact(operation, source),
              BackgroundDownloadValue.exact(context.target, MediaTarget.rendition(rendition)) else { throw BackendContractError.identityMismatch }
    }
}

/// Actual calendar capture observation, never acceptedAt (monotonic) or a fallback clock.
nonisolated struct BackgroundDownloadCaptureDateReference: Equatable, Sendable, Codable {
    let capture: CaptureID
    let original: CaptureOriginalReference
    let intentFingerprint: String
    let capturedAt: Date
    init(_ intent: RecordingIntent) throws {
        guard let date = intent.capturedAt, date.timeIntervalSinceReferenceDate.isFinite else { throw BackendContractError.invalidValue }
        capture = intent.context.capture; original = intent.original
        intentFingerprint = BackgroundDownloadValue.fingerprint(intent); capturedAt = date
    }
    func validate() throws {
        guard capturedAt.timeIntervalSinceReferenceDate.isFinite, BackgroundDownloadValue.digest(intentFingerprint) else {
            throw BackendContractError.invalidValue
        }
    }
    func matches(_ intent: RecordingIntent) -> Bool {
        BackgroundDownloadValue.exact(intent.context.capture, capture) && BackgroundDownloadValue.exact(intent.original, original)
            && intent.capturedAt == capturedAt && BackgroundDownloadValue.fingerprint(intent) == intentFingerprint
    }
}

nonisolated struct BackgroundDownloadIssuedTicket: Equatable, Sendable, Codable {
    let command: MediaOperationID
    let planned: BackgroundDownloadPlannedIntentReference
    let begin: BackgroundDownloadBackendReference
    let lease: BackgroundDownloadLeaseReference
    let registration: DeviceRegistration
    let request: BackgroundDownloadReadTicketRequest
    let source: DistributionReceipt
    let ticket: DistributionReceipt
    let contentType: String
    let responseURLFingerprint: String
    let captureDate: BackgroundDownloadCaptureDateReference?
    func validate() throws {
        try BackgroundDownloadValue.text(command.rawValue); try planned.validate(); try begin.validate(); try lease.validate(); try request.validate()
        try captureDate?.validate()
        guard registration.isCommitted, source.isCommitted, ticket.isCommitted,
              BackgroundDownloadValue.exact(registration.server.registration, planned.context.registration),
              BackgroundDownloadValue.exact(request.context, planned.context), BackgroundDownloadValue.exact(request.rendition, planned.rendition),
              BackgroundDownloadValue.exact(source.operation, request.source), BackgroundDownloadValue.exact(ticket.operation, request.operation),
              BackgroundDownloadValue.exact(source.registration, planned.context.registration), BackgroundDownloadValue.exact(ticket.registration, planned.context.registration),
              BackgroundDownloadValue.exact(source.rendition, planned.rendition), BackgroundDownloadValue.exact(ticket.rendition, planned.rendition),
              BackgroundDownloadValue.exact(source.commit.key, BackendCommitKey.distribution(source.operation, source.rendition, source.registration)),
              BackgroundDownloadValue.exact(ticket.commit.key, BackendCommitKey.distribution(ticket.operation, ticket.rendition, ticket.registration)),
              ["video/mp4", "video/quicktime"].contains(contentType), BackgroundDownloadValue.digest(responseURLFingerprint),
              begin.storeIdentity == planned.context.storeIdentity,
              captureDate.map({ BackgroundDownloadValue.exact($0.capture, planned.rendition.original.capture) }) ?? true else {
            throw BackendContractError.identityMismatch
        }
    }
}

nonisolated struct BackgroundDownloadObservationReference: Equatable, Sendable, Codable {
    let storeIdentity: RegistrationStoreIdentity
    let command: MediaOperationID
    let stage: BackgroundDownloadObservationStage
    let taskID: BackgroundMediaTaskID
    let fingerprint: String
    let commit: BackendCommitReceipt
    init(_ saved: StoredBackgroundDownloadObservation) throws {
        guard saved.isCommitted else { throw BackendContractError.notCommitted }
        storeIdentity = saved.expectedStoreIdentity; command = saved.change.command; stage = saved.change.stage
        taskID = saved.change.taskID; fingerprint = saved.change.fingerprint; commit = saved.commit
    }
    var key: BackendCommitKey { .backgroundDownload(command, stage, taskID, fingerprint) }
    func validate() throws {
        try BackgroundDownloadValue.text(command.rawValue); try BackgroundDownloadValue.text(taskID.rawValue)
        guard BackgroundDownloadValue.digest(fingerprint), commit.matches(key, revision: commit.previousRevision),
              BackgroundDownloadValue.exact(commit.key, key) else { throw BackendContractError.notCommitted }
    }
    func matches(_ record: StoredBackgroundDownloadObservation) -> Bool {
        record.isCommitted && storeIdentity == record.expectedStoreIdentity && stage == record.change.stage
            && BackgroundDownloadValue.exact(taskID, record.change.taskID) && BackgroundDownloadValue.exact(command, record.change.command)
            && BackgroundDownloadValue.exact(commit, record.commit) && fingerprint == record.change.fingerprint
    }
}

/// Mirror of the SDK's ephemeral file stat. Does not relax OriginalFileFingerprint.
nonisolated struct BackgroundDownloadSourceFileFacts: Equatable, Sendable, Codable {
    let device: Int64; let inode: UInt64; let size: Int64
    let modifiedSeconds: Int64; let modifiedNanoseconds: Int64
    let changedSeconds: Int64; let changedNanoseconds: Int64; let linkCount: UInt64
    init(_ facts: BackgroundDownloadSourceFacts) {
        device = facts.device; inode = facts.inode; size = facts.size; modifiedSeconds = facts.modifiedSeconds
        modifiedNanoseconds = facts.modifiedNanoseconds; changedSeconds = facts.changedSeconds
        changedNanoseconds = facts.changedNanoseconds; linkCount = facts.linkCount
    }
    func sdkFacts() throws -> BackgroundDownloadSourceFacts {
        try .init(device: device, inode: inode, size: size, modifiedSeconds: modifiedSeconds,
            modifiedNanoseconds: modifiedNanoseconds, changedSeconds: changedSeconds, changedNanoseconds: changedNanoseconds, linkCount: linkCount)
    }
}

nonisolated struct BackgroundDownloadResponseObservation: Equatable, Sendable, Codable {
    let command: MediaOperationID
    let ticket: BackgroundDownloadObservationReference
    let prepared: BackgroundDownloadBackendReference
    let attached: BackgroundDownloadBackendReference
    let artifact: BackgroundDownloadArtifactReference
    let response: BackgroundDownloadResponseFacts
    let source: BackgroundDownloadSourceFileFacts
    let media: TemporaryMediaID
    let usage: MediaUsageID
    var taskID: BackgroundMediaTaskID { ticket.taskID }
    func validate() throws {
        try BackgroundDownloadValue.text(command.rawValue); try ticket.validate(); try prepared.validate(); try attached.validate()
        try response.validate(); _ = try source.sdkFacts()
        try BackgroundDownloadValue.text(media.rawValue); try BackgroundDownloadValue.text(usage.rawValue)
        guard ticket.stage == .issuedTicket, source.size > 0, UInt64(source.size) == response.contentLength,
              prepared.storeIdentity == ticket.storeIdentity, attached.storeIdentity == ticket.storeIdentity else { throw BackendContractError.identityMismatch }
    }
}

/// Created only from the owning ingress manager's actual close result. Journal
/// replay still joins the actual SDK terminal independently.
nonisolated enum BackgroundDownloadClosedSource: Equatable, Sendable, Codable {
    case artifact(BackgroundDownloadArtifactReference, initial: BackgroundDownloadSourceFileFacts,
                  final: BackgroundDownloadSourceFileFacts, content: ContentIdentity?)
    case unpinned(ownerGeneration: UUID, binding: BackgroundMediaTaskBinding)
    init(_ closure: BackgroundDownloadSourceClosure, initial: BackgroundDownloadSourceFacts,
         final: BackgroundDownloadSourceFacts, content: ContentIdentity?) throws {
        guard closure.workersJoined, closure.handlesClosed, initial.permitsSDKUnlinkTransition(to: final) else { throw BackendContractError.readersActive }
        self = .artifact(closure.reference, initial: .init(initial), final: .init(final), content: content)
    }
    init(_ closure: BackgroundDownloadUnpinnedClosure) throws {
        guard closure.pinsSealed, closure.workersJoined, closure.handlesClosed else { throw BackendContractError.readersActive }
        self = .unpinned(ownerGeneration: closure.ownerGeneration, binding: closure.binding)
    }
    var binding: BackgroundMediaTaskBinding {
        switch self { case .artifact(let ref, _, _, _): ref.binding; case .unpinned(_, let binding): binding }
    }
    func validate() throws {
        if case .artifact(_, let initial, let final, let content) = self {
            let a = try initial.sdkFacts(), b = try final.sdkFacts()
            guard a.permitsSDKUnlinkTransition(to: b) else { throw BackendContractError.identityMismatch }
            if let content { try DownloadIngressValueValidation.content(content); guard content.byteCount == UInt64(a.size) else { throw BackendContractError.identityMismatch } }
        }
    }
}

nonisolated struct BackgroundDownloadSourceClosedObservation: Equatable, Sendable, Codable {
    let command: MediaOperationID
    let ticket: BackgroundDownloadObservationReference
    let prepared: BackgroundDownloadBackendReference
    let attached: BackgroundDownloadBackendReference
    let terminal: BackgroundDownloadBackendReference
    let source: BackgroundDownloadClosedSource
    var taskID: BackgroundMediaTaskID { ticket.taskID }
    func validate() throws {
        try BackgroundDownloadValue.text(command.rawValue); try ticket.validate(); try prepared.validate(); try attached.validate(); try terminal.validate(); try source.validate()
        guard ticket.stage == .issuedTicket, prepared.storeIdentity == ticket.storeIdentity,
              attached.storeIdentity == ticket.storeIdentity, terminal.storeIdentity == ticket.storeIdentity else { throw BackendContractError.identityMismatch }
    }
}

/// Planned immutable import inputs. Actual temporary target facts are added by
/// its owner after independently hashing/closing the target's verification FD.
nonisolated struct BackgroundDownloadImportSelection: Equatable, Sendable, Codable {
    let response: BackgroundDownloadObservationReference
    let sourceClosed: BackgroundDownloadObservationReference
    let ownerClosed: BackgroundDownloadBackendReference
    let leaseReleased: BackgroundDownloadLeaseReference
    let captureDate: BackgroundDownloadCaptureDateReference
    let sourceContent: ContentIdentity
    func validate() throws {
        try response.validate(); try sourceClosed.validate(); try ownerClosed.validate(); try leaseReleased.validate(); try captureDate.validate()
        try DownloadIngressValueValidation.content(sourceContent)
        guard response.stage == .response, sourceClosed.stage == .sourceClosed,
              response.storeIdentity == sourceClosed.storeIdentity, response.storeIdentity == ownerClosed.storeIdentity,
              BackgroundDownloadValue.exact(response.taskID, sourceClosed.taskID) else { throw BackendContractError.identityMismatch }
    }
}

nonisolated struct BackgroundDownloadImportObservation: Equatable, Sendable, Codable {
    let command: MediaOperationID
    let selection: BackgroundDownloadImportSelection
    let media: TemporaryMediaID
    let use: TemporaryMediaUseRecord
    let leaf: String
    let contentType: String
    let directory: TemporaryFileIdentity
    let file: TemporaryFileIdentity
    let content: ContentIdentity
    let targetFile: ManagedUploadFileIdentity
    var taskID: BackgroundMediaTaskID { selection.response.taskID }
    func validate() throws {
        try BackgroundDownloadValue.text(command.rawValue); try selection.validate(); try TemporaryMediaLeaf.validate(leaf, contentType: contentType)
        try DownloadIngressValueValidation.content(content)
        guard BackgroundDownloadValue.exact(media, use.usage.media), directory.inode > 0, file.inode > 0,
              file.device == targetFile.device, file.inode == targetFile.inode, targetFile.size > 0,
              UInt64(targetFile.size) == content.byteCount, BackgroundDownloadValue.exact(content, selection.sourceContent),
              (0..<1_000_000_000).contains(targetFile.modifiedNanoseconds),
              (0..<1_000_000_000).contains(targetFile.changedNanoseconds) else { throw BackendContractError.identityMismatch }
    }
}

nonisolated indirect enum BackgroundDownloadStoreChange: Equatable, Sendable, Codable {
    case issuedTicket(BackgroundDownloadIssuedTicket)
    case response(BackgroundDownloadResponseObservation)
    case sourceClosed(BackgroundDownloadSourceClosedObservation)
    case imported(BackgroundDownloadImportObservation)
    var command: MediaOperationID {
        switch self { case .issuedTicket(let v): v.command; case .response(let v): v.command; case .sourceClosed(let v): v.command; case .imported(let v): v.command }
    }
    var stage: BackgroundDownloadObservationStage {
        switch self { case .issuedTicket: .issuedTicket; case .response: .response; case .sourceClosed: .sourceClosed; case .imported: .imported }
    }
    var taskID: BackgroundMediaTaskID {
        switch self { case .issuedTicket(let v): v.planned.taskID; case .response(let v): v.taskID; case .sourceClosed(let v): v.taskID; case .imported(let v): v.taskID }
    }
    var storeIdentity: RegistrationStoreIdentity {
        switch self { case .issuedTicket(let v): v.planned.context.storeIdentity; case .response(let v): v.ticket.storeIdentity; case .sourceClosed(let v): v.ticket.storeIdentity; case .imported(let v): v.selection.response.storeIdentity }
    }
    var fingerprint: String { BackgroundDownloadValue.fingerprint(self) }
    var key: BackendCommitKey { .backgroundDownload(command, stage, taskID, fingerprint) }
    func validate() throws {
        switch self { case .issuedTicket(let v): try v.validate(); case .response(let v): try v.validate(); case .sourceClosed(let v): try v.validate(); case .imported(let v): try v.validate() }
        guard BackgroundDownloadValue.digest(fingerprint) else { throw BackendContractError.invalidValue }
    }
}

nonisolated struct StoredBackgroundDownloadObservation: Equatable, Sendable, Codable {
    let change: BackgroundDownloadStoreChange
    let commit: BackendCommitReceipt
    let expectedStoreIdentity: RegistrationStoreIdentity
    var isCommitted: Bool {
        (try? change.validate()) != nil && change.storeIdentity == expectedStoreIdentity
            && commit.matches(change.key, revision: commit.previousRevision) && BackgroundDownloadValue.exact(commit.key, change.key)
    }
    var mutation: BackendStoreMutation { .init(expectedRevision: commit.previousRevision, change: .backgroundDownload(change), expectedStoreIdentity: expectedStoreIdentity) }
    var reference: BackgroundDownloadObservationReference { get throws { try .init(self) } }
}
