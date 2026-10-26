import Foundation
import Testing
@testable import FrameRelay

struct UploadMetadataTests {
    @Test func beginReceiptBindsTheWholeQueryAndOpaqueUTF8Source() throws {
        let f = try MetadataDomainFixture(capture: "  capture-\u{00e9}  ")
        let query = try f.query(.create, generation: 1)
        let encoded = try UploadMetadataValidation.canonicalBytes(query.query)
        let decoded = try JSONDecoder().decode(UploadMetadataQuery.self, from: encoded)
        #expect(UploadMetadataValidation.exact(decoded, query.query) && query.isCommitted)
        let aliasOriginal = OriginalContent(capture: .init(rawValue: "  capture-e\u{0301}  "),
            generation: f.source.original.generation, content: f.source.original.content)
        let aliasSource = try UploadMetadataRequest(storeIdentity: f.source.storeIdentity, registration: f.source.registration,
            operation: f.source.operation, original: aliasOriginal, expectedStartRevision: f.source.expectedStartRevision)
        let sources = [aliasSource, try UploadMetadataRequest(storeIdentity: .init(rawValue: UUID()), registration: f.source.registration,
            operation: f.source.operation, original: f.source.original, expectedStartRevision: f.source.expectedStartRevision)]
        for source in sources {
            let changed = try UploadMetadataQuery(id: query.query.id, observationCommand: query.query.observationCommand,
                request: source, kind: .create, generation: query.query.generation)
            #expect(changed.fingerprint != query.query.fingerprint)
            #expect(!CommittedUploadMetadataQuery(query: changed, commit: query.commit, expectedStoreIdentity: source.storeIdentity).isCommitted)
        }
        let changedKind = try UploadMetadataQuery(id: query.query.id, observationCommand: query.query.observationCommand,
            request: f.source, kind: .lookup(.init(rawValue: "session")), generation: query.query.generation)
        #expect(!CommittedUploadMetadataQuery(query: changedKind, commit: query.commit, expectedStoreIdentity: f.source.storeIdentity).isCommitted)
        var object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["generation"] = ["rawValue": 2]
        #expect(throws: BackendContractError.identityMismatch) {
            try JSONDecoder().decode(UploadMetadataQuery.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }

    @Test func allReservationsParticipateInGenerationAndMaximumNeverWraps() throws {
        #expect(try UploadMetadataGeneration.next(lastObservation: nil, reservations: []).rawValue == 1)
        #expect(try UploadMetadataGeneration.next(lastObservation: .init(rawValue: 5),
            reservations: [.init(rawValue: 9), .init(rawValue: 7)]).rawValue == 10)
        #expect(try UploadMetadataGeneration.next(lastObservation: .init(rawValue: 11), reservations: [.init(rawValue: 9)]).rawValue == 12)
        #expect(throws: BackendContractError.staleGeneration) {
            try UploadMetadataGeneration.next(lastObservation: .init(rawValue: UInt64.max), reservations: [])
        }
        #expect(throws: BackendContractError.staleGeneration) {
            try UploadMetadataGeneration.next(lastObservation: nil, reservations: [.init(rawValue: UInt64.max)])
        }
    }

    @Test(arguments: [false, true])
    func createdSessionNeverInfersStatusOrReversesAnInterveningPersonInstruction(cancel: Bool) throws {
        let f = try MetadataDomainFixture(), query = try f.query(.create, generation: 1)
        var request = f.media
        try request.markAwaitingUploadMetadata(query)
        request.setWait(.saving, active: true)
        if cancel { request.cancel() } else { request.pause() }
        let observation = try UploadMetadataObservation(command: query.query.observationCommand, query: query,
            response: .created(f.binding()))
        try request.applyUploadMetadata(observation)
        #expect(request.session == f.binding().session && request.remote == .unknown && !request.hasReconciled && !request.canRun)
        #expect(request.intent == (cancel ? .cancelled : .paused) && request.waits == [.saving])
        #expect(request.transport == .queued && request.attempt == nil && request.uploadMetadataPending == nil)
        #expect(try f.stored(observation).verification == nil)
    }

    @Test func awaitingQueryRevokesOldAttemptPermissionUntilTheLatestExactReply() throws {
        let f = try MetadataDomainFixture(), query = try f.query(.lookup(f.binding().session), generation: 2)
        var request = f.media
        try request.reconcile(.init(context: f.context, observation: .init(rawValue: 1), result: .inProgress))
        #expect(request.canRun)
        try request.markAwaitingUploadMetadata(query)
        #expect(!request.canRun && !request.hasReconciled && request.uploadMetadataPending == query.query.generation)
        #expect(throws: BackendContractError.wrongStage) { try request.beginAttempt(.init(rawValue: "premature")) }
        let latest = try UploadMetadataObservation(command: query.query.observationCommand, query: query,
            response: .status(f.status(.receiving)))
        try request.applyUploadMetadata(latest)
        #expect(request.canRun && request.uploadMetadataPending == nil)
        try request.beginAttempt(.init(rawValue: "after-exact-observation"))
        #expect(request.transport == .active)
        let newer = try f.query(.lookup(f.binding().session), generation: 3)
        try request.markAwaitingUploadMetadata(newer)
        #expect(request.transport == .active && request.attempt?.rawValue == "after-exact-observation")
        #expect(request.remote == .inProgress && !request.canRun)
    }

    @Test func aLegacyReconciliationCannotClearPendingOrExternalCancellationHolds() throws {
        let f = try MetadataDomainFixture(), query = try f.query(.lookup(f.binding().session), generation: 2)
        var request = f.media
        try request.reconcile(.init(context: f.context, observation: .init(rawValue: 1), result: .inProgress))
        try request.markAwaitingUploadMetadata(query)
        try request.reconcile(.init(context: f.context, observation: .init(rawValue: 2), result: .notExecuted))
        #expect(request.hasReconciled && request.uploadMetadataPending != nil && !request.canRun)
        let next = try f.query(.lookup(f.binding().session), generation: 3)
        try request.markAwaitingUploadMetadata(next)
        request.setWait(.wiFiUnavailable, active: true)
        let observation = try UploadMetadataObservation(command: next.query.observationCommand, query: next,
            response: .status(f.status(.cancelled)))
        try request.applyUploadMetadata(observation)
        #expect(request.uploadMetadataHold == .serverCancelled && request.remote == .unknown && request.intent == .running)
        #expect(request.waits == [.wiFiUnavailable] && request.transport == .queued && !request.canRun)
        request.setWait(.wiFiUnavailable, active: false)
        try request.reconcile(.init(context: f.context, observation: .init(rawValue: 4), result: .notExecuted))
        #expect(request.uploadMetadataHold == .serverCancelled && !request.canRun)
    }

    @Test func authenticObservationAuthorityBindsEvidenceAndEveryOtherResponseField() throws {
        let f = try MetadataDomainFixture(), query = try f.query(.lookup(f.binding().session), generation: 1)
        let observation = try UploadMetadataObservation(command: query.query.observationCommand, query: query,
            response: .status(f.status(.completed, evidence: f.proof())))
        let record = try f.stored(observation)
        let proof = try #require(record.verification)
        #expect(record.isCommitted && proof.isCommitted && proof.key == observation.key && proof.commit == record.commit)
        #expect(proof.key != .verification(proof.command, proof.evidence.id, proof.expected))
        #expect(proof.evidence.verifies(f.source.original, destination: f.source.registration.server.registration.destination,
            supportedSchemas: ["fr-final-read-v1"]))
        let altered = try UploadMetadataObservation(command: observation.command, query: query,
            response: .status(f.status(.completed, evidence: f.proof(), indexes: [0], failure: "opaque-server-detail")))
        let borrowed = StoredUploadMetadataObservation(observation: altered, commit: record.commit, expectedStoreIdentity: record.expectedStoreIdentity)
        #expect(observation.fingerprint != altered.fingerprint && !borrowed.isCommitted && borrowed.verification == nil)
        let injected = StoredVerificationEvidence(command: proof.command, expected: proof.expected, evidence: proof.evidence,
            commit: proof.commit, metadataProvenance: .observation(borrowed))
        #expect(!injected.isCommitted)
        let noSource = StoredVerificationEvidence(command: proof.command, expected: proof.expected, evidence: proof.evidence, commit: proof.commit)
        #expect(!noSource.isCommitted)
        let begin = CommittedUploadMetadataQuery(query: query.query,
            commit: .init(key: query.query.key, previousRevision: query.commit.previousRevision + 1,
                committedRevision: query.commit.committedRevision + 1), expectedStoreIdentity: query.expectedStoreIdentity)
        let changedBegin = try UploadMetadataObservation(command: observation.command, query: begin, response: observation.response)
        #expect(changedBegin.fingerprint != observation.fingerprint)
        #expect(!StoredUploadMetadataObservation(observation: changedBegin, commit: record.commit, expectedStoreIdentity: record.expectedStoreIdentity).isCommitted)
    }

    @Test func malformedCompletedEvidenceCannotBeAdoptedAndLegacyNilEncodingIsUnchanged() throws {
        let f = try MetadataDomainFixture(), query = try f.query(.lookup(f.binding().session), generation: 1)
        for field in ["schema", "method", "committed", "final-save", "hash", "bytes", "date"] {
            #expect(throws: BackendContractError.invalidValue) {
                try UploadMetadataObservation(command: query.query.observationCommand, query: query,
                    response: .status(f.status(.completed, evidence: f.proof(changing: field))))
            }
        }
        #expect(throws: BackendContractError.notCommitted) {
            try UploadMetadataObservation(command: query.query.observationCommand, query: query, response: .status(f.status(.completed)))
        }
        let evidence = VerificationEvidence(id: .init(rawValue: "legacy-proof"), context: f.context, finalSaveCompleted: true,
            verification: .finalDestinationReadBack(f.source.original.content), committed: true, schemaVersion: "fr-final-read-v1", observedAt: f.proof().observedAt)
        let command = MediaOperationID(rawValue: "legacy-verification")
        let receipt = BackendCommitReceipt(key: .verification(command, evidence.id, f.context), previousRevision: 8, committedRevision: 9)
        let current = StoredVerificationEvidence(command: command, expected: f.context, evidence: evidence, commit: receipt)
        let legacy = LegacyMetadataVerification(command: command, expected: f.context, evidence: evidence, commit: receipt)
        #expect(try UploadMetadataValidation.canonicalBytes(current) == UploadMetadataValidation.canonicalBytes(legacy))
        let decoded = try JSONDecoder().decode(StoredVerificationEvidence.self, from: UploadMetadataValidation.canonicalBytes(legacy))
        #expect(decoded.isCommitted && decoded.metadataProvenance == nil && decoded.key == receipt.key)
        let object = try #require(try JSONSerialization.jsonObject(with: UploadMetadataValidation.canonicalBytes(f.media)) as? [String: Any])
        #expect(object["uploadMetadataHold"] == nil && object["uploadMetadataPending"] == nil)
        #expect(try JSONDecoder().decode(MediaRequest.self, from: UploadMetadataValidation.canonicalBytes(f.media)) == f.media)
    }
}

nonisolated private struct LegacyMetadataVerification: Encodable {
    let command: MediaOperationID
    let expected: RemoteOperationContext
    let evidence: VerificationEvidence
    let commit: BackendCommitReceipt
}
nonisolated private struct MetadataDomainFixture {
    let source: UploadMetadataRequest
    let media: MediaRequest
    init(capture: String = "opaque-capture") throws {
        let registration = try BackendOperationFixture().deviceRegistration
        source = try .init(storeIdentity: .init(rawValue: UUID()), registration: registration,
            operation: .init(rawValue: "upload-operation"), original: inventoryOriginal(capture), expectedStartRevision: 30)
        var media = MediaRequest(operation: source.operation, target: .original(source.original), purpose: .upload,
            registration: registration.server.registration, expectedStartRevision: 30)
        try media.acceptStartCommit(.init(key: .request(media.operation, media.target, media.registration), previousRevision: 30, committedRevision: 31))
        self.media = media
    }
    var context: RemoteOperationContext { .init(operation: source.operation, registration: source.registration.server.registration,
        target: .original(source.original), session: binding().session) }
    func binding() -> UploadMetadataBinding { .init(registration: source.registration.server.registration, operation: source.operation,
        original: source.original, session: .init(rawValue: "metadata-session"), chunkSize: 1024) }
    func query(_ kind: UploadMetadataQueryKind, generation: UInt64) throws -> CommittedUploadMetadataQuery {
        let query = try UploadMetadataQuery(id: .init(rawValue: "query-" + String(generation)),
            observationCommand: .init(rawValue: "observation-" + String(generation)), request: source, kind: kind, generation: .init(rawValue: generation))
        return .init(query: query, commit: .init(key: query.key, previousRevision: 40, committedRevision: 41), expectedStoreIdentity: source.storeIdentity)
    }
    func status(_ state: UploadMetadataState, evidence: UploadFinalReadEvidence? = nil, indexes: [UInt64] = [], failure: String? = nil) -> UploadMetadataStatus {
        .init(binding: binding(), state: state, evidence: evidence, chunkIndexes: indexes, failureCode: failure)
    }
    func proof(changing field: String? = nil) -> UploadFinalReadEvidence {
        .init(id: .init(rawValue: "final-read-proof"), schemaVersion: field == "schema" ? "unsupported" : "fr-final-read-v1",
            method: field == "method" ? "assembly_only" : "final_destination_read_back", committed: field != "committed",
            finalSaveCompleted: field != "final-save", sha256: field == "hash" ? String(repeating: "b", count: 64) : source.original.content.digest,
            byteCount: source.original.content.byteCount + (field == "bytes" ? 1 : 0),
            observedAt: Date(timeIntervalSinceReferenceDate: field == "date" ? .infinity : 12345))
    }
    func stored(_ observation: UploadMetadataObservation) throws -> StoredUploadMetadataObservation {
        let value = StoredUploadMetadataObservation(observation: observation,
            commit: .init(key: observation.key, previousRevision: 45, committedRevision: 46), expectedStoreIdentity: source.storeIdentity)
        guard value.isCommitted else { throw BackendContractError.notCommitted }
        return value
    }
}
