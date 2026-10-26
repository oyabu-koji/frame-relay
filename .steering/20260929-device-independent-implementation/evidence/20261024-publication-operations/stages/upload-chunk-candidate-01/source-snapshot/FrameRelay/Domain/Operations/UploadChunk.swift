import Foundation

/// A computable server range, before any local file or chunk hash exists.
/// Only binding/index are encoded; all arithmetic is revalidated on decode.
nonisolated struct UploadChunkRange: Equatable, Sendable, Codable {
    let binding: UploadMetadataBinding
    let index: UInt64
    let offset: UInt64
    let length: UInt64
    let upperBoundExclusive: UInt64
    let totalByteCount: UInt64
    let chunkCount: UInt64

    init(binding: UploadMetadataBinding, index: UInt64) throws {
        try UploadChunkValueValidation.binding(binding)
        let total = binding.original.content.byteCount, size = binding.chunkSize
        let count = (total / size).addingReportingOverflow(total % size == 0 ? 0 : 1)
        let start = index.multipliedReportingOverflow(by: size)
        guard !count.overflow, index < count.partialValue, !start.overflow, start.partialValue < total else {
            throw BackendContractError.invalidValue
        }
        let length = min(size, total - start.partialValue)
        let end = start.partialValue.addingReportingOverflow(length)
        guard length > 0, !end.overflow, end.partialValue <= total else { throw BackendContractError.invalidValue }
        self.binding = binding; self.index = index; offset = start.partialValue
        self.length = length; upperBoundExclusive = end.partialValue; totalByteCount = total; chunkCount = count.partialValue
    }

    func validate() throws { _ = try Self(binding: binding, index: index) }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.index == rhs.index && UploadMetadataValidation.exact(lhs.binding, rhs.binding)
    }
    private enum CodingKeys: String, CodingKey { case binding, index }
    init(from decoder: Decoder) throws {
        try UploadChunkValueValidation.keys(decoder, ["binding", "index"])
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(binding: values.decode(UploadMetadataBinding.self, forKey: .binding),
            index: values.decode(UInt64.self, forKey: .index))
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(binding, forKey: .binding); try values.encode(index, forKey: .index)
    }
}

/// The hash is produced from this range's bytes, never borrowed from the whole
/// original. A one-chunk original may legitimately have the same content hash.
nonisolated struct UploadChunkDescriptor: Equatable, Sendable, Codable {
    let range: UploadChunkRange
    let content: ContentIdentity
    init(range: UploadChunkRange, content: ContentIdentity) throws {
        try range.validate(); try UploadChunkValueValidation.content(content)
        guard content.byteCount == range.length else { throw BackendContractError.identityMismatch }
        self.range = range; self.content = content
    }
    func validate() throws { _ = try Self(range: range, content: content) }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.range == rhs.range && UploadMetadataValidation.exact(lhs.content, rhs.content)
    }
    private enum CodingKeys: String, CodingKey { case range, content }
    init(from decoder: Decoder) throws {
        try UploadChunkValueValidation.keys(decoder, ["range", "content"])
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(range: values.decode(UploadChunkRange.self, forKey: .range),
            content: values.decode(ContentIdentity.self, forKey: .content))
    }
}

/// A local copy identity, separate from the full-original lease. Decoding this
/// value cannot adopt a previous process's file or close a current owner's FD.
nonisolated struct ManagedUploadChunkIdentity: Equatable, Sendable, Codable {
    let source: ManagedUploadSourceIdentity
    let descriptor: UploadChunkDescriptor
    init(source: ManagedUploadSourceIdentity, descriptor: UploadChunkDescriptor) throws {
        try descriptor.validate()
        try UploadChunkValueValidation.source(source)
        guard UploadMetadataValidation.exact(source.content, descriptor.content),
              UInt64(source.file.size) == descriptor.range.length else { throw BackendContractError.identityMismatch }
        self.source = source; self.descriptor = descriptor
    }
    func validate() throws { _ = try Self(source: source, descriptor: descriptor) }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.descriptor == rhs.descriptor && UploadMetadataValidation.exact(lhs.source, rhs.source)
    }
    private enum CodingKeys: String, CodingKey { case source, descriptor }
    init(from decoder: Decoder) throws {
        try UploadChunkValueValidation.keys(decoder, ["source", "descriptor"])
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(source: values.decode(ManagedUploadSourceIdentity.self, forKey: .source),
            descriptor: values.decode(UploadChunkDescriptor.self, forKey: .descriptor))
    }
}

/// Compact reference only. The prepared writer must join the full persisted
/// observation and its genuine receipt, then check latest GET/receiving/index
/// and serial-attempt rules. This value alone grants no dispatch authority.
nonisolated struct UploadChunkMetadataSelection: Equatable, Sendable, Codable {
    let storeIdentity: RegistrationStoreIdentity
    let observationCommand: MediaOperationID
    let queryID: MediaOperationID
    let observationFingerprint: String
    let observationGeneration: RemoteObservationGeneration
    let previousRevision: UInt64
    let committedRevision: UInt64

    init(_ saved: StoredUploadMetadataObservation) throws {
        guard saved.isCommitted else { throw BackendContractError.notCommitted }
        storeIdentity = saved.expectedStoreIdentity; observationCommand = saved.observation.command
        queryID = saved.observation.query.query.id; observationFingerprint = saved.observation.fingerprint
        observationGeneration = saved.observation.query.query.generation
        previousRevision = saved.commit.previousRevision; committedRevision = saved.commit.committedRevision
        try validate()
    }
    var expectedKey: BackendCommitKey { .uploadMetadataObservation(observationCommand, queryID, observationFingerprint) }
    var commit: BackendCommitReceipt {
        .init(key: expectedKey, previousRevision: previousRevision, committedRevision: committedRevision)
    }
    func validate() throws {
        let next = previousRevision.addingReportingOverflow(1)
        guard !observationCommand.rawValue.isEmpty, !queryID.rawValue.isEmpty, observationCommand != queryID,
              observationGeneration.rawValue > 0, !next.overflow, next.partialValue == committedRevision,
              UploadChunkValueValidation.isSHA256(observationFingerprint) else { throw BackendContractError.invalidValue }
    }
    func matches(_ saved: StoredUploadMetadataObservation) -> Bool {
        guard let expected = try? Self(saved) else { return false }; return self == expected
    }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.storeIdentity == rhs.storeIdentity && lhs.observationGeneration == rhs.observationGeneration
            && lhs.previousRevision == rhs.previousRevision && lhs.committedRevision == rhs.committedRevision
            && lhs.observationCommand.rawValue.utf8.elementsEqual(rhs.observationCommand.rawValue.utf8)
            && lhs.queryID.rawValue.utf8.elementsEqual(rhs.queryID.rawValue.utf8)
            && lhs.observationFingerprint.utf8.elementsEqual(rhs.observationFingerprint.utf8)
    }
    private enum CodingKeys: String, CodingKey {
        case storeIdentity, observationCommand, queryID, observationFingerprint, observationGeneration, previousRevision, committedRevision
    }
    init(from decoder: Decoder) throws {
        try UploadChunkValueValidation.keys(decoder, ["storeIdentity", "observationCommand", "queryID", "observationFingerprint",
            "observationGeneration", "previousRevision", "committedRevision"])
        let values = try decoder.container(keyedBy: CodingKeys.self)
        storeIdentity = try values.decode(RegistrationStoreIdentity.self, forKey: .storeIdentity)
        observationCommand = try values.decode(MediaOperationID.self, forKey: .observationCommand)
        queryID = try values.decode(MediaOperationID.self, forKey: .queryID)
        observationFingerprint = try values.decode(String.self, forKey: .observationFingerprint)
        observationGeneration = try values.decode(RemoteObservationGeneration.self, forKey: .observationGeneration)
        previousRevision = try values.decode(UInt64.self, forKey: .previousRevision)
        committedRevision = try values.decode(UInt64.self, forKey: .committedRevision)
        try validate()
    }
}

/// Exact chunk receipt only. It is not an SDK terminal, whole-original
/// verification, final-save evidence, or authority to finalize a job.
nonisolated struct UploadChunkReceipt: Equatable, Sendable, Codable {
    let descriptor: UploadChunkDescriptor
    let chunkIndex: UInt64
    let byteCount: UInt64
    let sha256: String
    init(descriptor: UploadChunkDescriptor, chunkIndex: UInt64, byteCount: UInt64, sha256: String) throws {
        try descriptor.validate()
        guard chunkIndex == descriptor.range.index, byteCount == descriptor.range.length,
              sha256.utf8.elementsEqual(descriptor.content.digest.utf8) else { throw BackendContractError.identityMismatch }
        self.descriptor = descriptor; self.chunkIndex = chunkIndex; self.byteCount = byteCount; self.sha256 = sha256
    }
    func validate() throws { _ = try Self(descriptor: descriptor, chunkIndex: chunkIndex, byteCount: byteCount, sha256: sha256) }
    private enum CodingKeys: String, CodingKey { case descriptor, chunkIndex, byteCount, sha256 }
    init(from decoder: Decoder) throws {
        try UploadChunkValueValidation.keys(decoder, ["descriptor", "chunkIndex", "byteCount", "sha256"])
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(descriptor: values.decode(UploadChunkDescriptor.self, forKey: .descriptor),
            chunkIndex: values.decode(UInt64.self, forKey: .chunkIndex), byteCount: values.decode(UInt64.self, forKey: .byteCount),
            sha256: values.decode(String.self, forKey: .sha256))
    }
}

private nonisolated enum UploadChunkValueValidation {
    static func binding(_ value: UploadMetadataBinding) throws {
        for text in [value.registration.destination.rawValue, value.registration.id.rawValue, value.operation.rawValue, value.session.rawValue] {
            guard let uuid = UUID(uuidString: text), uuid.uuidString.lowercased() == text else { throw BackendContractError.invalidValue }
        }
        try UploadMetadataValidation.original(value.original)
        let capture = value.original.capture.rawValue
        guard value.registration.generation.rawValue > 0, value.chunkSize > 0,
              !capture.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !capture.contains("\0"), capture.utf8.count <= 4096 else {
            throw BackendContractError.invalidValue
        }
    }
    static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    static func content(_ value: ContentIdentity) throws {
        guard value.byteCount > 0, value.algorithm == "sha256", isSHA256(value.digest) else { throw BackendContractError.invalidValue }
    }
    static func source(_ value: ManagedUploadSourceIdentity) throws {
        try content(value.content)
        guard let id = UUID(uuidString: value.id.rawValue), id.uuidString.lowercased() == value.id.rawValue.lowercased(),
              value.directoryInode > 0, value.file.inode > 0, value.file.size > 0,
              UInt64(value.file.size) == value.content.byteCount,
              (0..<1_000_000_000).contains(value.file.modifiedNanoseconds),
              (0..<1_000_000_000).contains(value.file.changedNanoseconds) else { throw BackendContractError.invalidValue }
    }
    private struct Key: CodingKey {
        let stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { return nil }
    }
    static func keys(_ decoder: Decoder, _ expected: Set<String>) throws {
        let values = try decoder.container(keyedBy: Key.self)
        guard Set(values.allKeys.map(\.stringValue)) == expected else { throw BackendContractError.invalidValue }
    }
}
