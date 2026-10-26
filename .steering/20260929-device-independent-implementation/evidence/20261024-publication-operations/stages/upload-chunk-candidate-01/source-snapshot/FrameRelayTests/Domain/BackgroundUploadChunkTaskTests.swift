import Foundation
import Testing
@testable import FrameRelay

/// Pure synthetic contract inputs. These receipts/closure flags are not SDK,
/// disk durability, source-copy or whole-original completion evidence.
struct BackgroundUploadChunkTaskTests {
    @Test(arguments: [false, true])
    func oldSourceJSONKeepsItsOriginalPayloadAndDigestInvariant(download: Bool) throws {
        let f = try ChunkTaskValueFixture(), original = f.intent.context.target.original
        let source: BackgroundMediaTaskSource, old: ChunkTaskLegacySource
        if download {
            let rendition = publicationRendition(original)
            let lease = MediaReadLease(id: .init(rawValue: "old-download-reader"), target: .rendition(rendition),
                operation: f.intent.context.operation, registration: f.intent.context.registration,
                context: .transport(f.intent.context.attempt), epoch: .init(rawValue: "media-epoch"), accessGeneration: .init(rawValue: 1))
            source = .download(rendition: rendition, range: nil, lease: lease)
            old = .download(rendition: rendition, range: nil, lease: lease)
        } else {
            let whole = chunkTaskSource(original.content)
            source = .upload(session: f.range.binding.session, lease: f.lease, source: whole)
            old = .upload(session: f.range.binding.session, lease: f.lease, source: whole)
            let valid = chunkTaskIntent(f.intent, source: source)
            try valid.validate()
            #expect(throws: BackendContractError.identityMismatch) {
                try chunkTaskIntent(f.intent, source: .upload(session: f.range.binding.session, lease: f.lease,
                    source: f.chunk.source)).validate()
            }
        }
        let bytes = try UploadMetadataValidation.canonicalBytes(source)
        let oldBytes = try UploadMetadataValidation.canonicalBytes(old)
        #expect(bytes == oldBytes)
        #expect(try JSONDecoder().decode(BackgroundMediaTaskSource.self, from: bytes) == source)
    }

    @Test func chunkSourceRoundTripsOnlyCompactMetadataAndKeepsItsIndependentContent() throws {
        let f = try ChunkTaskValueFixture()
        try f.intent.validate()
        let bytes = try UploadMetadataValidation.canonicalBytes(f.intent)
        let decoded = try JSONDecoder().decode(BackgroundMediaTaskIntent.self, from: bytes)
        #expect(UploadMetadataValidation.exact(decoded, f.intent))
        let owner = try #require(decoded.source.uploadOwnership)
        #expect(owner.macSession == f.range.binding.session && owner.originalLease == f.lease)
        #expect(owner.source == f.chunk.source && owner.descriptor == f.chunk.descriptor && owner.metadata == f.selection)
        #expect(owner.source.content != owner.originalLease.original.content)
        let object = try #require(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let source = try #require(object["source"] as? [String: Any])
        let chunk = try #require(source["uploadChunk"] as? [String: Any])
        let selection = try #require(chunk["metadata"] as? [String: Any])
        #expect(Set(selection.keys) == ["storeIdentity", "observationCommand", "queryID", "observationFingerprint",
            "observationGeneration", "previousRevision", "committedRevision"])
        #expect(selection["query"] == nil && selection["response"] == nil && selection["mutation"] == nil)
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(!text.contains("https://") && !text.contains("Authorization") && !text.contains("requestBody"))
    }

    @Test(arguments: ["operation", "registration", "target", "uuid"])
    func aChunkMustMatchTheOriginalLeaseAndWholeServerBinding(field: String) throws {
        let f = try ChunkTaskValueFixture(), old = f.intent.context
        let context = BackgroundMediaRequestContext(operation: field == "operation" ? .init(rawValue: UUID().uuidString) : old.operation,
            attempt: old.attempt, target: field == "target" ? .original(try inventoryOriginal("different-original")) : old.target,
            registration: field == "registration" ? .init(destination: old.registration.destination,
                id: .init(rawValue: UUID().uuidString.lowercased()), generation: .init(rawValue: 2)) : old.registration,
            gateGeneration: old.gateGeneration, storeIdentity: field == "uuid" ? .init(rawValue: UUID()) : old.storeIdentity)
        #expect(throws: BackendContractError.identityMismatch) { try chunkTaskIntent(f.intent, context: context).validate() }
    }

    @Test func actualSDKTerminalAndExactChunkOwnerClosureRemainSeparateFacts() throws {
        let f = try ChunkTaskValueFixture(), binding = chunkTaskBinding(f.intent)
        var state = BackgroundMediaTaskState(intent: f.intent)
        try state.apply(.attached(f.intent, binding))
        try state.apply(.stopRequested(f.intent))
        let closure = BackgroundMediaOwnerClosure(binding: binding, uploadSource: f.chunk.source, tasksJoined: true, handlesClosed: true)
        #expect(throws: BackendContractError.readersActive) { try state.apply(.ownerClosed(f.intent, closure)) }
        try state.apply(.terminal(f.intent, .init(binding: binding, outcome: .completed)))
        let wrong = BackgroundMediaOwnerClosure(binding: binding, uploadSource: chunkTaskSource(f.lease.original.content),
            tasksJoined: true, handlesClosed: true)
        #expect(throws: BackendContractError.identityMismatch) { try state.apply(.ownerClosed(f.intent, wrong)) }
        #expect(state.terminal?.outcome == .completed && state.ownerClosure == nil)
        try state.apply(.ownerClosed(f.intent, closure))
        #expect(state.ownerClosure == closure && state.stopRequested && !state.resumeRequested)
        // No MediaRequest, verification, Mac receipt or reader release is made.
        #expect(state.events.isEmpty)
    }

    @Test func aCanonicallyEqualTaskIDCannotReplaceThePreparedIntent() throws {
        let f = try ChunkTaskValueFixture()
        let prepared = chunkTaskIntent(f.intent, id: .init(rawValue: "task-\u{00e9}"))
        let alias = chunkTaskIntent(f.intent, id: .init(rawValue: "task-e\u{0301}"))
        #expect(prepared == alias) // Swift String equality is not this authority.
        var state = BackgroundMediaTaskState(intent: prepared)
        #expect(throws: BackendContractError.identityMismatch) { try state.apply(.attached(alias, chunkTaskBinding(prepared))) }
        #expect(state.binding == nil)
        try state.apply(.attached(prepared, chunkTaskBinding(prepared)))
        #expect(state.binding != nil)
    }

    @Test func opaqueOriginalSpellingIsValidatedWithoutCanonicalAliasBorrowing() throws {
        let f = try ChunkTaskValueFixture()
        let alias = OriginalContent(capture: .init(rawValue: "capture-e\u{0301}"), generation: f.lease.original.generation,
            content: f.lease.original.content)
        #expect(alias == f.lease.original)
        let lease = OriginalReadLease(id: f.lease.id, original: alias, operation: f.lease.operation,
            accessGeneration: f.lease.accessGeneration, epoch: f.lease.epoch)
        #expect(throws: BackendContractError.identityMismatch) {
            try chunkTaskIntent(f.intent, source: .uploadChunk(lease: lease, chunk: f.chunk, metadata: f.selection)).validate()
        }
    }
}

nonisolated private enum ChunkTaskLegacySource: Codable {
    case upload(session: UploadSessionID, lease: OriginalReadLease, source: ManagedUploadSourceIdentity)
    case download(rendition: RenditionIdentity, range: MediaByteRange?, lease: MediaReadLease)
}

nonisolated private struct ChunkTaskValueFixture {
    let range: UploadChunkRange
    let chunk: ManagedUploadChunkIdentity
    let selection: UploadChunkMetadataSelection
    let lease: OriginalReadLease
    let intent: BackgroundMediaTaskIntent

    init() throws {
        let registration = RegistrationIdentity(destination: .init(rawValue: "11111111-1111-4111-8111-111111111111"),
            id: .init(rawValue: "22222222-2222-4222-8222-222222222222"), generation: .init(rawValue: 1))
        let registrationIntent = RegistrationIntent(operation: .init(rawValue: "domain-registration"), destination: registration.destination)
        let device = DeviceRegistration(server: .init(intent: registrationIntent, registration: registration),
            intentCommit: backendCommit(.registrationIntent(registrationIntent.operation, registration.destination), revision: 10),
            commit: backendCommit(.registration(registrationIntent.operation, registration), revision: 11))
        let original = try OriginalContent(capture: .init(rawValue: "capture-\u{00e9}"), generation: .init(rawValue: 1),
            content: .init(byteCount: 21, algorithm: "sha256", digest: String(repeating: "a", count: 64)))
        let operation = MediaOperationID(rawValue: "33333333-3333-4333-8333-333333333333"), identity = RegistrationStoreIdentity(rawValue: UUID())
        let binding = UploadMetadataBinding(registration: registration, operation: operation, original: original,
            session: .init(rawValue: "44444444-4444-4444-8444-444444444444"), chunkSize: 8)
        range = try .init(binding: binding, index: 0)
        let descriptor = try UploadChunkDescriptor(range: range,
            content: .init(byteCount: 8, algorithm: "sha256", digest: String(repeating: "b", count: 64)))
        chunk = try .init(source: chunkTaskSource(descriptor.content), descriptor: descriptor)
        let source = try UploadMetadataRequest(storeIdentity: identity, registration: device, operation: operation,
            original: original, expectedStartRevision: 30)
        let query = try UploadMetadataQuery(id: .init(rawValue: "domain-query"), observationCommand: .init(rawValue: "domain-observe"),
            request: source, kind: .lookup(binding.session), generation: .init(rawValue: 1))
        let committed = CommittedUploadMetadataQuery(query: query, commit: backendCommit(query.key, revision: 40), expectedStoreIdentity: identity)
        let observation = try UploadMetadataObservation(command: query.observationCommand, query: committed,
            response: .status(.init(binding: binding, state: .receiving, evidence: nil, chunkIndexes: [], failureCode: nil)))
        selection = try .init(.init(observation: observation, commit: backendCommit(observation.key, revision: 42), expectedStoreIdentity: identity))
        lease = .init(id: .init(rawValue: "domain-lease"), original: original, operation: operation,
            accessGeneration: .init(rawValue: 1), epoch: .init(rawValue: "original-private-epoch"))
        intent = .init(id: .init(rawValue: "domain-task"), context: .init(operation: operation, attempt: .init(rawValue: "domain-attempt"),
            target: .original(original), registration: registration, gateGeneration: 8, storeIdentity: identity),
            session: .init(identifier: .init(rawValue: "com.framerelay.chunk-domain"), generation: .init(rawValue: UUID())),
            taskDescription: UUID().uuidString, requestFingerprint: .init(sha256: String(repeating: "c", count: 64)),
            source: .uploadChunk(lease: lease, chunk: chunk, metadata: selection))
    }
}

nonisolated private func chunkTaskSource(_ content: ContentIdentity) -> ManagedUploadSourceIdentity {
    .init(id: .init(rawValue: UUID().uuidString), directoryDevice: 1, directoryInode: 2,
        file: .init(device: 1, inode: 3, size: Int64(content.byteCount), modifiedSeconds: 1, modifiedNanoseconds: 0,
            changedSeconds: 1, changedNanoseconds: 0), content: content)
}
nonisolated private func chunkTaskBinding(_ intent: BackgroundMediaTaskIntent) -> BackgroundMediaTaskBinding {
    .init(session: intent.session, taskIdentifier: 17, taskDescription: intent.taskDescription)
}
nonisolated private func chunkTaskIntent(_ intent: BackgroundMediaTaskIntent, context: BackgroundMediaRequestContext? = nil,
    source: BackgroundMediaTaskSource? = nil, id: BackgroundMediaTaskID? = nil) -> BackgroundMediaTaskIntent {
    .init(id: id ?? intent.id, context: context ?? intent.context, session: intent.session, taskDescription: intent.taskDescription,
        requestFingerprint: intent.requestFingerprint, source: source ?? intent.source)
}
