import CryptoKit
import Foundation

/// Immutable request identity. Mutable intent/waits are deliberately excluded
/// from the payload; they are re-read before POST and never restored by a reply.
nonisolated struct UploadMetadataRequest: Equatable, Sendable, Codable {
    let storeIdentity: RegistrationStoreIdentity
    let registration: DeviceRegistration
    let operation: MediaOperationID
    let original: OriginalContent
    let expectedStartRevision: UInt64

    init(storeIdentity: RegistrationStoreIdentity, registration: DeviceRegistration, operation: MediaOperationID,
         original: OriginalContent, expectedStartRevision: UInt64) throws {
        self.storeIdentity = storeIdentity; self.registration = registration; self.operation = operation
        self.original = original; self.expectedStartRevision = expectedStartRevision
        try validate()
    }
    func validate() throws {
        try OriginalUploadAcceptanceValueValidation.registration(registration)
        try UploadMetadataValidation.text(operation.rawValue)
        try UploadMetadataValidation.original(original)
    }
    func matches(_ request: MediaRequest) -> Bool {
        request.purpose == .upload && request.startCommitted && request.expectedStartRevision == expectedStartRevision
            && UploadMetadataValidation.exact(request.operation, operation)
            && UploadMetadataValidation.exact(request.target, MediaTarget.original(original))
            && UploadMetadataValidation.exact(request.registration, registration.server.registration)
    }
}

nonisolated enum UploadMetadataQueryKind: Equatable, Sendable, Codable {
    case create
    case lookup(UploadSessionID)
}

nonisolated struct UploadMetadataQuery: Equatable, Sendable, Codable {
    let id: MediaOperationID
    let observationCommand: MediaOperationID
    let request: UploadMetadataRequest
    let kind: UploadMetadataQueryKind
    let generation: RemoteObservationGeneration
    let fingerprint: String

    init(id: MediaOperationID, observationCommand: MediaOperationID, request: UploadMetadataRequest,
         kind: UploadMetadataQueryKind, generation: RemoteObservationGeneration) throws {
        self.id = id; self.observationCommand = observationCommand; self.request = request
        self.kind = kind; self.generation = generation
        fingerprint = try UploadMetadataValidation.fingerprint(Payload(id: id, observationCommand: observationCommand,
            request: request, kind: kind, generation: generation))
        try validate()
    }
    var key: BackendCommitKey { .uploadMetadataQuery(id, fingerprint) }
    func validate() throws {
        try request.validate(); try UploadMetadataValidation.text(id.rawValue)
        try UploadMetadataValidation.text(observationCommand.rawValue)
        guard id != observationCommand, id != request.operation, observationCommand != request.operation,
              generation.rawValue > 0 else { throw BackendContractError.invalidValue }
        if case .lookup(let session) = kind { try UploadMetadataValidation.text(session.rawValue) }
        guard fingerprint == (try UploadMetadataValidation.fingerprint(Payload(id: id, observationCommand: observationCommand,
            request: request, kind: kind, generation: generation))) else { throw BackendContractError.identityMismatch }
    }
    private struct Payload: Encodable {
        let id: MediaOperationID
        let observationCommand: MediaOperationID
        let request: UploadMetadataRequest
        let kind: UploadMetadataQueryKind
        let generation: RemoteObservationGeneration
    }
    private enum CodingKeys: String, CodingKey { case id, observationCommand, request, kind, generation, fingerprint }
    init(from decoder: Decoder) throws {
        let value = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: value.decode(MediaOperationID.self, forKey: .id),
            observationCommand: value.decode(MediaOperationID.self, forKey: .observationCommand),
            request: value.decode(UploadMetadataRequest.self, forKey: .request),
            kind: value.decode(UploadMetadataQueryKind.self, forKey: .kind),
            generation: value.decode(RemoteObservationGeneration.self, forKey: .generation))
        guard try value.decode(String.self, forKey: .fingerprint) == fingerprint else { throw BackendContractError.identityMismatch }
    }
}

nonisolated struct CommittedUploadMetadataQuery: Equatable, Sendable, Codable {
    let query: UploadMetadataQuery
    let commit: BackendCommitReceipt
    let expectedStoreIdentity: RegistrationStoreIdentity
    var isCommitted: Bool {
        (try? query.validate()) != nil && expectedStoreIdentity == query.request.storeIdentity
            && commit.matches(query.key, revision: commit.previousRevision)
            && UploadMetadataValidation.exact(commit.key, query.key)
    }
    var mutation: BackendStoreMutation {
        .init(expectedRevision: commit.previousRevision, change: .uploadMetadata(.beginQuery(query)), expectedStoreIdentity: expectedStoreIdentity)
    }
}

/// The complete ten-field server binding, expressed with existing value types.
nonisolated struct UploadMetadataBinding: Equatable, Sendable, Codable {
    let registration: RegistrationIdentity
    let operation: MediaOperationID
    let original: OriginalContent
    let session: UploadSessionID
    let chunkSize: UInt64
    func validate(for request: UploadMetadataRequest) throws {
        try UploadMetadataValidation.text(session.rawValue)
        guard chunkSize > 0, UploadMetadataValidation.exact(registration, request.registration.server.registration),
              UploadMetadataValidation.exact(operation, request.operation), UploadMetadataValidation.exact(original, request.original) else {
            throw BackendContractError.identityMismatch
        }
    }
}

nonisolated enum UploadMetadataState: String, Equatable, Sendable, Codable {
    case receiving, finalizing, completed, failed, cancelled
}

/// All eight server fields, including the server's finite observation date.
/// A completed flag or an evidence ID alone cannot construct this authority.
nonisolated struct UploadFinalReadEvidence: Equatable, Sendable, Codable {
    let id: EvidenceID
    let schemaVersion: String
    let method: String
    let committed: Bool
    let finalSaveCompleted: Bool
    let sha256: String
    let byteCount: UInt64
    let observedAt: Date
    func validate(for original: OriginalContent) throws {
        try UploadMetadataValidation.text(id.rawValue)
        guard schemaVersion == "fr-final-read-v1", method == "final_destination_read_back", committed, finalSaveCompleted,
              sha256.utf8.elementsEqual(original.content.digest.utf8), byteCount == original.content.byteCount,
              observedAt.timeIntervalSinceReferenceDate.isFinite else { throw BackendContractError.invalidValue }
    }
}

nonisolated struct UploadMetadataStatus: Equatable, Sendable, Codable {
    let binding: UploadMetadataBinding
    let state: UploadMetadataState
    let evidence: UploadFinalReadEvidence?
    let chunkIndexes: [UInt64]
    let failureCode: String?
    func validate(for request: UploadMetadataRequest) throws {
        try binding.validate(for: request)
        let quotient = request.original.content.byteCount / binding.chunkSize
        let count = quotient.addingReportingOverflow(request.original.content.byteCount % binding.chunkSize == 0 ? 0 : 1)
        guard !count.overflow else { throw BackendContractError.invalidValue }
        var previous: UInt64?
        for index in chunkIndexes {
            guard index < count.partialValue, previous.map({ index > $0 }) ?? true else { throw BackendContractError.invalidValue }
            previous = index
        }
        if state == .completed {
            guard let evidence else { throw BackendContractError.notCommitted }
            try evidence.validate(for: request.original)
        } else if evidence != nil { throw BackendContractError.invalidValue }
    }
}

nonisolated enum UploadMetadataResponse: Equatable, Sendable, Codable {
    case created(UploadMetadataBinding)
    case status(UploadMetadataStatus)
    var binding: UploadMetadataBinding {
        switch self { case .created(let value): value; case .status(let value): value.binding }
    }
}

nonisolated struct UploadMetadataObservation: Equatable, Sendable, Codable {
    let command: MediaOperationID
    let query: CommittedUploadMetadataQuery
    let response: UploadMetadataResponse
    let fingerprint: String

    init(command: MediaOperationID, query: CommittedUploadMetadataQuery, response: UploadMetadataResponse) throws {
        self.command = command; self.query = query; self.response = response
        fingerprint = try UploadMetadataValidation.fingerprint(Payload(command: command, storeIdentity: query.expectedStoreIdentity,
            query: query, response: response))
        try validate()
    }
    var key: BackendCommitKey { .uploadMetadataObservation(command, query.query.id, fingerprint) }
    func validate() throws {
        guard query.isCommitted, UploadMetadataValidation.exact(command, query.query.observationCommand) else {
            throw BackendContractError.notCommitted
        }
        try response.binding.validate(for: query.query.request)
        switch (query.query.kind, response) {
        case (.create, .created): break
        case (.lookup(let session), .status(let value)):
            guard UploadMetadataValidation.exact(session, value.binding.session) else { throw BackendContractError.identityMismatch }
            try value.validate(for: query.query.request)
        default: throw BackendContractError.identityMismatch
        }
        guard fingerprint == (try UploadMetadataValidation.fingerprint(Payload(command: command, storeIdentity: query.expectedStoreIdentity,
            query: query, response: response))) else { throw BackendContractError.identityMismatch }
    }
    var verificationEvidence: VerificationEvidence? {
        guard (try? validate()) != nil, case .status(let status) = response,
              status.state == .completed, let proof = status.evidence else { return nil }
        let request = query.query.request
        return .init(id: proof.id, context: .init(operation: request.operation, registration: request.registration.server.registration,
            target: .original(request.original), session: status.binding.session), finalSaveCompleted: proof.finalSaveCompleted,
            verification: .finalDestinationReadBack(request.original.content), committed: proof.committed,
            schemaVersion: proof.schemaVersion, observedAt: proof.observedAt)
    }
    private struct Payload: Encodable {
        let command: MediaOperationID
        let storeIdentity: RegistrationStoreIdentity
        let query: CommittedUploadMetadataQuery
        let response: UploadMetadataResponse
    }
    private enum CodingKeys: String, CodingKey { case command, query, response, fingerprint }
    init(from decoder: Decoder) throws {
        let value = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(command: value.decode(MediaOperationID.self, forKey: .command),
            query: value.decode(CommittedUploadMetadataQuery.self, forKey: .query),
            response: value.decode(UploadMetadataResponse.self, forKey: .response))
        guard try value.decode(String.self, forKey: .fingerprint) == fingerprint else { throw BackendContractError.identityMismatch }
    }
}

nonisolated struct StoredUploadMetadataObservation: Equatable, Sendable, Codable {
    let observation: UploadMetadataObservation
    let commit: BackendCommitReceipt
    let expectedStoreIdentity: RegistrationStoreIdentity
    var isCommitted: Bool {
        (try? observation.validate()) != nil && expectedStoreIdentity == observation.query.expectedStoreIdentity
            && expectedStoreIdentity == observation.query.query.request.storeIdentity
            && observation.query.commit.committedRevision <= commit.previousRevision
            && commit.matches(observation.key, revision: commit.previousRevision)
            && UploadMetadataValidation.exact(commit.key, observation.key)
    }
    var mutation: BackendStoreMutation {
        .init(expectedRevision: commit.previousRevision, change: .uploadMetadata(.observe(observation)), expectedStoreIdentity: expectedStoreIdentity)
    }
    var verification: StoredVerificationEvidence? {
        guard isCommitted, let evidence = observation.verificationEvidence else { return nil }
        return .init(command: observation.command, expected: evidence.context, evidence: evidence, commit: commit,
            metadataProvenance: .observation(self))
    }
}

/// Box the full immutable provenance, keeping old verification values small.
/// The payload has no StoredVerificationEvidence back-reference or receipt self-hash.
nonisolated indirect enum UploadMetadataVerificationProvenance: Equatable, Sendable, Codable {
    case observation(StoredUploadMetadataObservation)
    var key: BackendCommitKey {
        switch self { case .observation(let value): value.observation.key }
    }
    func matches(_ value: StoredVerificationEvidence) -> Bool {
        switch self {
        case .observation(let source):
            guard source.isCommitted, let evidence = source.observation.verificationEvidence else { return false }
            return UploadMetadataValidation.exact(value.command, source.observation.command)
                && UploadMetadataValidation.exact(value.commit, source.commit)
                && UploadMetadataValidation.exact(value.expected, evidence.context)
                && UploadMetadataValidation.exact(value.evidence, evidence)
        }
    }
}

nonisolated indirect enum UploadMetadataChange: Equatable, Sendable, Codable {
    case beginQuery(UploadMetadataQuery)
    case observe(UploadMetadataObservation)
    var key: BackendCommitKey {
        switch self { case .beginQuery(let value): value.key; case .observe(let value): value.key }
    }
    var request: UploadMetadataRequest {
        switch self { case .beginQuery(let value): value.request; case .observe(let value): value.query.query.request }
    }
}

nonisolated enum UploadMetadataHold: String, Equatable, Sendable, Codable { case serverCancelled }

nonisolated enum UploadMetadataGeneration {
    static func next(lastObservation: RemoteObservationGeneration?, reservations: [RemoteObservationGeneration]) throws -> RemoteObservationGeneration {
        let maximum = reservations.map(\.rawValue).max().map { max($0, lastObservation?.rawValue ?? 0) } ?? (lastObservation?.rawValue ?? 0)
        guard maximum < UInt64.max else { throw BackendContractError.staleGeneration }
        return .init(rawValue: maximum + 1)
    }
}

nonisolated enum UploadMetadataValidation {
    static func text(_ value: String) throws {
        guard !value.isEmpty else { throw BackendContractError.invalidValue }
    }
    static func original(_ value: OriginalContent) throws {
        try text(value.capture.rawValue)
        guard value.generation.rawValue > 0, value.content.byteCount > 0, value.content.algorithm == "sha256",
              value.content.digest.utf8.count == 64,
              value.content.digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw BackendContractError.invalidValue
        }
    }
    static func canonicalBytes<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .deferredToDate
        do { return try encoder.encode(value) } catch { throw BackendContractError.invalidValue }
    }
    static func fingerprint<T: Encodable>(_ value: T) throws -> String {
        SHA256.hash(data: try canonicalBytes(value)).map { String(format: "%02x", $0) }.joined()
    }
    static func exact<T: Encodable>(_ left: T, _ right: T) -> Bool {
        guard let lhs = try? canonicalBytes(left), let rhs = try? canonicalBytes(right) else { return false }
        return lhs == rhs
    }
}
