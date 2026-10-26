import CryptoKit
import Foundation

/// In-memory expectations only. Neither a prepared task nor a pre-GET read
/// ticket proves that GET was admitted, metadata is current, or bytes verified.
/// Missing date/ticket is retained for the later import boundary to reject.
nonisolated struct BackgroundDownloadExpectedProposal: Equatable, Sendable {
    let intent: BackgroundMediaTaskIntent
    let responseURL: URL
    let contentType: String
    let capturedAt: Date?
    let captureRecord: CaptureOriginalReference?
    let distributionOperation: MediaOperationID
    let readTicket: DistributionReceipt?

    init(intent: BackgroundMediaTaskIntent, responseURL: URL, contentType: String, capturedAt: Date?,
         captureRecord: CaptureOriginalReference?, distributionOperation: MediaOperationID, readTicket: DistributionReceipt? = nil) throws {
        self.intent = intent; self.responseURL = responseURL; self.contentType = contentType
        self.capturedAt = capturedAt; self.captureRecord = captureRecord
        self.distributionOperation = distributionOperation; self.readTicket = readTicket
        try validate()
    }
    var rendition: RenditionIdentity {
        // Only full download values can be constructed by the public initializer.
        if case .download(let value, _, _) = intent.source { return value }
        preconditionFailure("Validated full download proposal required")
    }
    var responseURLFingerprint: String {
        SHA256.hash(data: Data(responseURL.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    var distributionHeader: String {
        Data(distributionOperation.rawValue.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    func validate() throws {
        try intent.validate()
        guard case .download(let rendition, nil, let lease) = intent.source,
              UploadMetadataValidation.exact(intent.context.target, MediaTarget.rendition(rendition)),
              UploadMetadataValidation.exact(lease.target, intent.context.target),
              UploadMetadataValidation.exact(lease.operation, intent.context.operation),
              UploadMetadataValidation.exact(lease.registration, intent.context.registration),
              UploadMetadataValidation.exact(lease.context, MediaReadContext.transport(intent.context.attempt)),
              ["video/mp4", "video/quicktime"].contains(contentType),
              ["https", "http"].contains(responseURL.scheme ?? ""),
              let parts = URLComponents(url: responseURL, resolvingAgainstBaseURL: false),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil, parts.fragment == nil,
              responseURL.absoluteString.utf8.count <= 8192,
              !distributionOperation.rawValue.isEmpty, distributionOperation.rawValue.utf8.count <= 4096,
              !distributionOperation.rawValue.contains("\0"),
              capturedAt.map({ $0.timeIntervalSinceReferenceDate.isFinite }) ?? true,
              captureRecord.map({ !$0.rawValue.isEmpty }) ?? true else { throw BackendContractError.invalidValue }
        try UploadMetadataValidation.original(rendition.original)
        try DownloadIngressValueValidation.content(rendition.deliveryContent)
        guard rendition.deliveryContent.byteCount <= UInt64(Int64.max), rendition.publicationGeneration.rawValue > 0,
              !rendition.rendition.rawValue.isEmpty, rendition.rendition.rawValue.utf8.count <= 4096,
              !rendition.rendition.rawValue.contains("\r"), !rendition.rendition.rawValue.contains("\n"),
              !rendition.rendition.rawValue.contains("\0") else { throw BackendContractError.invalidValue }
        if let ticket = readTicket {
            guard ticket.isCommitted, UploadMetadataValidation.exact(ticket.operation, distributionOperation),
                  UploadMetadataValidation.exact(ticket.rendition, rendition),
                  UploadMetadataValidation.exact(ticket.registration, intent.context.registration),
                  UploadMetadataValidation.exact(ticket.commit.key, BackendCommitKey.distribution(ticket.operation, rendition, ticket.registration)) else {
                throw BackendContractError.identityMismatch
            }
        }
    }
    static func == (lhs: Self, rhs: Self) -> Bool {
        UploadMetadataValidation.exact(lhs.intent, rhs.intent)
            && lhs.responseURL.absoluteString.utf8.elementsEqual(rhs.responseURL.absoluteString.utf8)
            && lhs.contentType.utf8.elementsEqual(rhs.contentType.utf8) && lhs.capturedAt == rhs.capturedAt
            && UploadMetadataValidation.exact(lhs.captureRecord, rhs.captureRecord)
            && UploadMetadataValidation.exact(lhs.distributionOperation, rhs.distributionOperation)
            && UploadMetadataValidation.exact(lhs.readTicket, rhs.readTicket)
    }
}

/// Compact reference to an EXISTING prepared background event. The owner still
/// performs exact load/lookup; decoding this value grants no metadata authority.
nonisolated struct KnownPreparedDownloadReference: Equatable, Sendable, Codable {
    let storeIdentity: RegistrationStoreIdentity
    let command: MediaOperationID
    let taskID: BackgroundMediaTaskID
    let commit: BackendCommitReceipt
    init(_ event: StoredBackgroundMediaTaskEvent) throws {
        guard case .prepared(let intent) = event.change, case .download(_, nil, _) = intent.source else { throw BackendContractError.invalidValue }
        storeIdentity = event.storeIdentity; command = event.command; taskID = intent.id; commit = event.commit
        try validate(for: intent)
    }
    func validate(for intent: BackgroundMediaTaskIntent) throws {
        try intent.validate(); try validate()
        guard case .download(_, nil, _) = intent.source, storeIdentity == intent.context.storeIdentity,
              UploadMetadataValidation.exact(taskID, intent.id) else { throw BackendContractError.identityMismatch }
    }
    func mutation(for intent: BackgroundMediaTaskIntent) throws -> BackendStoreMutation {
        try validate(for: intent)
        return .init(expectedRevision: commit.previousRevision, change: .backgroundTask(command: command, value: .prepared(intent)), expectedStoreIdentity: storeIdentity)
    }
    private func validate() throws {
        let key = BackendCommitKey.backgroundTask(command, taskID)
        guard !command.rawValue.isEmpty, !taskID.rawValue.isEmpty, commit.matches(key, revision: commit.previousRevision),
              UploadMetadataValidation.exact(commit.key, key) else { throw BackendContractError.notCommitted }
    }
    private enum CodingKeys: String, CodingKey { case storeIdentity, command, taskID, commit }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        storeIdentity = try values.decode(RegistrationStoreIdentity.self, forKey: .storeIdentity)
        command = try values.decode(MediaOperationID.self, forKey: .command)
        taskID = try values.decode(BackgroundMediaTaskID.self, forKey: .taskID)
        commit = try values.decode(BackendCommitReceipt.self, forKey: .commit)
        try validate()
    }
}

/// The only artifact event payload. It carries no URL, FD, numeric FD authority,
/// response object, expected metadata or closure. It cannot adopt another owner.
nonisolated struct BackgroundDownloadArtifactReference: Equatable, Sendable, Codable {
    let id: UUID
    let ownerGeneration: UUID
    let binding: BackgroundMediaTaskBinding
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.ownerGeneration == rhs.ownerGeneration && UploadMetadataValidation.exact(lhs.binding, rhs.binding)
    }
}

/// Normalized local response witness only. The remote URL is represented by
/// a fingerprint; this is not a new server commit or GET-admission receipt.
nonisolated struct BackgroundDownloadResponseFacts: Equatable, Sendable, Codable {
    let urlFingerprint: String
    let status: Int
    let contentType: String
    let contentLength: UInt64
    let wireVersion: String
    let distributionHeader: String
    let renditionID: RenditionID
    let publicationGeneration: PublicationGeneration
    let content: ContentIdentity
    let cacheControl: String
    let contentRangeAbsent: Bool
    let contentEncoding: BackgroundDownloadContentEncoding
    let transferEncodingAbsent: Bool
    init(urlFingerprint: String, status: Int, contentType: String, contentLength: UInt64, wireVersion: String,
         distributionHeader: String, renditionID: RenditionID, publicationGeneration: PublicationGeneration,
         content: ContentIdentity, cacheControl: String, contentRangeAbsent: Bool,
         contentEncoding: BackgroundDownloadContentEncoding, transferEncodingAbsent: Bool) throws {
        self.urlFingerprint = urlFingerprint; self.status = status; self.contentType = contentType; self.contentLength = contentLength
        self.wireVersion = wireVersion; self.distributionHeader = distributionHeader; self.renditionID = renditionID
        self.publicationGeneration = publicationGeneration; self.content = content; self.cacheControl = cacheControl
        self.contentRangeAbsent = contentRangeAbsent; self.contentEncoding = contentEncoding; self.transferEncodingAbsent = transferEncodingAbsent
        try validate()
    }
    func validate() throws {
        try DownloadIngressValueValidation.content(content)
        guard status == 200, ["video/mp4", "video/quicktime"].contains(contentType), contentLength == content.byteCount,
              wireVersion == "fr-publication-v1", cacheControl == "no-store", contentRangeAbsent, transferEncodingAbsent,
              !distributionHeader.isEmpty, !renditionID.rawValue.isEmpty, publicationGeneration.rawValue > 0,
              urlFingerprint.utf8.count == 64, urlFingerprint.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw BackendContractError.invalidValue
        }
    }
    static func == (lhs: Self, rhs: Self) -> Bool { UploadMetadataValidation.exact(lhs, rhs) }
    private enum CodingKeys: String, CodingKey {
        case urlFingerprint, status, contentType, contentLength, wireVersion, distributionHeader, renditionID,
             publicationGeneration, content, cacheControl, contentRangeAbsent, contentEncoding, transferEncodingAbsent
    }
    init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(urlFingerprint: v.decode(String.self, forKey: .urlFingerprint), status: v.decode(Int.self, forKey: .status),
            contentType: v.decode(String.self, forKey: .contentType), contentLength: v.decode(UInt64.self, forKey: .contentLength),
            wireVersion: v.decode(String.self, forKey: .wireVersion), distributionHeader: v.decode(String.self, forKey: .distributionHeader),
            renditionID: v.decode(RenditionID.self, forKey: .renditionID), publicationGeneration: v.decode(PublicationGeneration.self, forKey: .publicationGeneration),
            content: v.decode(ContentIdentity.self, forKey: .content), cacheControl: v.decode(String.self, forKey: .cacheControl),
            contentRangeAbsent: v.decode(Bool.self, forKey: .contentRangeAbsent), contentEncoding: v.decode(BackgroundDownloadContentEncoding.self, forKey: .contentEncoding),
            transferEncodingAbsent: v.decode(Bool.self, forKey: .transferEncodingAbsent))
    }
}

nonisolated enum BackgroundDownloadContentEncoding: String, Equatable, Sendable, Codable { case absent, identity }

/// SDK ephemeral-file facts only. OriginalFileFingerprint continues to require
/// a linked original. A single SDK unlink may change nlink/ctime, never identity,
/// size or mtime; later ctime changes or relinking are refused.
nonisolated struct BackgroundDownloadSourceFacts: Equatable, Sendable {
    let device: Int64
    let inode: UInt64
    let size: Int64
    let modifiedSeconds: Int64
    let modifiedNanoseconds: Int64
    let changedSeconds: Int64
    let changedNanoseconds: Int64
    let linkCount: UInt64
    init(device: Int64, inode: UInt64, size: Int64, modifiedSeconds: Int64, modifiedNanoseconds: Int64,
         changedSeconds: Int64, changedNanoseconds: Int64, linkCount: UInt64) throws {
        guard inode > 0, size > 0, linkCount <= 1, (0..<1_000_000_000).contains(modifiedNanoseconds),
              (0..<1_000_000_000).contains(changedNanoseconds) else { throw BackendContractError.invalidValue }
        self.device = device; self.inode = inode; self.size = size; self.modifiedSeconds = modifiedSeconds
        self.modifiedNanoseconds = modifiedNanoseconds; self.changedSeconds = changedSeconds
        self.changedNanoseconds = changedNanoseconds; self.linkCount = linkCount
    }
    func permitsSDKUnlinkTransition(to next: Self) -> Bool {
        guard device == next.device, inode == next.inode, size == next.size,
              modifiedSeconds == next.modifiedSeconds, modifiedNanoseconds == next.modifiedNanoseconds else { return false }
        if linkCount == next.linkCount {
            return (linkCount == 0 || linkCount == 1) && changedSeconds == next.changedSeconds && changedNanoseconds == next.changedNanoseconds
        }
        return linkCount == 1 && next.linkCount == 0
            && (next.changedSeconds > changedSeconds || (next.changedSeconds == changedSeconds && next.changedNanoseconds >= changedNanoseconds))
    }
}

/// Actual same-owner worker join and FD close, independent of SDK terminal.
/// Future import must join the owner's observation and its own local receipt.
nonisolated struct BackgroundDownloadSourceClosure: Equatable, Sendable {
    let reference: BackgroundDownloadArtifactReference
    let workersJoined: Bool
    let handlesClosed: Bool
}

/// No-artifact closure of this process's registered/bound slot after its actual
/// known SDK terminal and pin join. An empty/reopened registry cannot issue it.
nonisolated struct BackgroundDownloadUnpinnedClosure: Equatable, Sendable {
    let ownerGeneration: UUID
    let binding: BackgroundMediaTaskBinding
    let pinsSealed: Bool
    let workersJoined: Bool
    let handlesClosed: Bool
}

private nonisolated enum DownloadIngressValueValidation {
    static func content(_ value: ContentIdentity) throws {
        guard value.byteCount > 0, value.algorithm == "sha256", value.digest.utf8.count == 64,
              value.digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw BackendContractError.invalidValue }
    }
}
