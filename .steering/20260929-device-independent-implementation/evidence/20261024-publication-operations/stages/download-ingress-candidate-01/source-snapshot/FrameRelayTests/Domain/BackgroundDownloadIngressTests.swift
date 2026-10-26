import Foundation
import Testing
@testable import FrameRelay

struct BackgroundDownloadIngressTests {
    @Test func expectationsRetainMissingDateAndTicketWithoutCreatingMediaAuthority() throws {
        let proposal = try downloadDomainProposal()
        #expect(proposal.capturedAt == nil && proposal.captureRecord == nil && proposal.readTicket == nil)
        #expect(proposal.rendition.deliveryContent != proposal.rendition.original.content)
        #expect(throws: BackendContractError.invalidValue) {
            try downloadDomainProposal(range: .init(lowerBound: 0, upperBound: 1024))
        }
        #expect(throws: BackendContractError.invalidValue) {
            try BackgroundDownloadExpectedProposal(intent: proposal.intent, responseURL: proposal.responseURL,
                contentType: proposal.contentType, capturedAt: Date(timeIntervalSinceReferenceDate: .infinity), captureRecord: nil,
                distributionOperation: proposal.distributionOperation)
        }
    }

    @Test func existingPreparedReferenceIsCompactAndRevalidatesItsExactKey() throws {
        let proposal = try downloadDomainProposal(), event = downloadDomainPrepared(proposal.intent)
        let reference = try KnownPreparedDownloadReference(event), mutation = try reference.mutation(for: proposal.intent)
        #expect(UploadMetadataValidation.exact(mutation.change.key, event.commit.key))
        #expect(mutation.expectedRevision == event.commit.previousRevision && mutation.expectedStoreIdentity == event.storeIdentity)
        let bytes = try JSONEncoder().encode(reference)
        var object = try #require(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(Set(object.keys) == ["storeIdentity", "command", "taskID", "commit"])
        #expect(!String(decoding: bytes, as: UTF8.self).contains("https"))
        #expect(try JSONDecoder().decode(KnownPreparedDownloadReference.self, from: bytes) == reference)
        object["taskID"] = ["rawValue": "another-task"]
        let changed = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: BackendContractError.notCommitted) { try JSONDecoder().decode(KnownPreparedDownloadReference.self, from: changed) }
        let wrong = StoredBackgroundMediaTaskEvent(command: event.command, change: .stopRequested(proposal.intent), commit: event.commit, storeIdentity: event.storeIdentity)
        #expect(throws: BackendContractError.invalidValue) { try KnownPreparedDownloadReference(wrong) }
        // These are pure synthetic facts. Only the owner's real store lookup
        // can establish that this key/payload was actually prepared.
    }

    @Test func artifactEventHasOnlyAnOpaqueOwnerScopedReference() throws {
        let proposal = try downloadDomainProposal(), binding = BackgroundMediaTaskBinding(session: proposal.intent.session,
            taskIdentifier: 1, taskDescription: proposal.intent.taskDescription)
        let reference = BackgroundDownloadArtifactReference(id: UUID(), ownerGeneration: UUID(), binding: binding)
        let data = try JSONEncoder().encode(reference)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["id", "ownerGeneration", "binding"])
        #expect(try JSONDecoder().decode(BackgroundDownloadArtifactReference.self, from: data) == reference)
        #expect(reference != .init(id: reference.id, ownerGeneration: UUID(), binding: binding))
        let foreign = BackgroundMediaTaskBinding(session: .init(identifier: binding.session.identifier, generation: .init(rawValue: UUID())),
            taskIdentifier: 1, taskDescription: binding.taskDescription)
        #expect(reference != .init(id: reference.id, ownerGeneration: reference.ownerGeneration, binding: foreign))
    }

    @Test func opaqueExpectedMetadataUsesUTF8AndNoCurrentDateFallback() throws {
        let first = try downloadDomainProposal(capture: "caf\u{00e9}"), second = try downloadDomainProposal(capture: "cafe\u{0301}", basedOn: first)
        #expect(first.rendition.original.capture == second.rendition.original.capture)
        #expect(first != second && first.capturedAt == nil && second.capturedAt == nil)
        #expect(first.distributionHeader == Data(first.distributionOperation.rawValue.utf8).base64EncodedString().replacingOccurrences(of: "=", with: ""))
    }

    @Test func theSDKUnlinkTransitionPreservesSizeMtimeAndThenSealsCtime() throws {
        let linked = try downloadDomainFacts(), unlinked = try downloadDomainFacts(links: 0, changed: 11)
        #expect(linked.permitsSDKUnlinkTransition(to: linked))
        #expect(linked.permitsSDKUnlinkTransition(to: unlinked))
        #expect(unlinked.permitsSDKUnlinkTransition(to: unlinked))
        #expect(!unlinked.permitsSDKUnlinkTransition(to: linked))
        let later = try downloadDomainFacts(links: 0, changed: 12)
        #expect(!unlinked.permitsSDKUnlinkTransition(to: later))
        #expect(throws: BackendContractError.invalidValue) { try downloadDomainFacts(links: 2) }
    }

    @Test(arguments: ["inode", "size", "mtime", "linked-ctime", "backward-unlink-ctime"])
    func anUnrelatedFileChangeCannotBorrowTheSDKUnlinkException(field: String) throws {
        let first = try downloadDomainFacts(), changed = try downloadDomainFacts(inode: field == "inode" ? 5 : 4,
            size: field == "size" ? 4095 : 4096, modified: field == "mtime" ? 11 : 10,
            links: field == "backward-unlink-ctime" ? 0 : 1, changed: field == "backward-unlink-ctime" ? 9 : 11)
        #expect(!first.permitsSDKUnlinkTransition(to: changed))
    }

    @Test(arguments: ["status", "range", "encoding", "length", "missing-range"])
    func normalizedResponseFactsCannotDecodePartialOrAssumedMissingHeaders(field: String) throws {
        let p = try downloadDomainProposal(), facts = try BackgroundDownloadResponseFacts(urlFingerprint: p.responseURLFingerprint,
            status: 200, contentType: p.contentType, contentLength: p.rendition.deliveryContent.byteCount,
            wireVersion: "fr-publication-v1", distributionHeader: p.distributionHeader, renditionID: p.rendition.rendition,
            publicationGeneration: p.rendition.publicationGeneration, content: p.rendition.deliveryContent, cacheControl: "no-store",
            contentRangeAbsent: true, contentEncoding: .absent, transferEncodingAbsent: true)
        let bytes = try JSONEncoder().encode(facts)
        #expect(try JSONDecoder().decode(BackgroundDownloadResponseFacts.self, from: bytes) == facts)
        var object = try #require(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        if field == "status" { object["status"] = 206 }
        if field == "range" { object["contentRangeAbsent"] = false }
        if field == "encoding" { object["contentEncoding"] = "gzip" }
        if field == "length" { object["contentLength"] = 1 }
        if field == "missing-range" { object.removeValue(forKey: "contentRangeAbsent") }
        let changed = try JSONSerialization.data(withJSONObject: object)
        var refused = false
        do { _ = try JSONDecoder().decode(BackgroundDownloadResponseFacts.self, from: changed) } catch { refused = true }
        #expect(refused)
    }
}

private nonisolated func downloadDomainProposal(capture: String = "expected-caf\u{00e9}", range: MediaByteRange? = nil,
    basedOn old: BackgroundDownloadExpectedProposal? = nil) throws -> BackgroundDownloadExpectedProposal {
    let registration = old?.intent.context.registration ?? .init(destination: .init(rawValue: "download-destination"),
        id: .init(rawValue: "download-registration"), generation: .init(rawValue: 1))
    let original = OriginalContent(capture: .init(rawValue: capture), generation: .init(rawValue: 1),
        content: try .init(byteCount: 4096, algorithm: "sha256", digest: String(repeating: "a", count: 64)))
    let rendition = RenditionIdentity(original: original, inputLogIdentity: "synthetic-not-log", transformAssetIdentity: "not-formal",
        transformAssetVersion: "fixture", outputConfigurationIdentity: "raw", conversionVersion: "test",
        rendition: old?.rendition.rendition ?? .init(rawValue: "download-rendition"),
        deliveryContent: try .init(byteCount: 131_111, algorithm: "sha256", digest: String(repeating: "b", count: 64)), publicationGeneration: .init(rawValue: 1))
    let operation = old?.intent.context.operation ?? .init(rawValue: "download-op"), attempt = old?.intent.context.attempt ?? .init(rawValue: "download-attempt")
    let lease = MediaReadLease(id: .init(rawValue: "download-reader"), target: .rendition(rendition), operation: operation,
        registration: registration, context: .transport(attempt), epoch: .init(rawValue: "synthetic-media-epoch"), accessGeneration: .init(rawValue: 1))
    let intent = BackgroundMediaTaskIntent(id: old?.intent.id ?? .init(rawValue: "download-task"),
        context: .init(operation: operation, attempt: attempt, target: .rendition(rendition), registration: registration,
            gateGeneration: 1, storeIdentity: old?.intent.context.storeIdentity ?? .init(rawValue: UUID())),
        session: old?.intent.session ?? .init(identifier: .init(rawValue: "FrameRelay.download-domain"), generation: .init(rawValue: UUID())),
        taskDescription: old?.intent.taskDescription ?? UUID().uuidString, requestFingerprint: .init(sha256: String(repeating: "d", count: 64)),
        source: .download(rendition: rendition, range: range, lease: lease))
    return try .init(intent: intent, responseURL: URL(string: "https://download-ingress.invalid/full")!, contentType: "video/mp4",
        capturedAt: nil, captureRecord: nil, distributionOperation: .init(rawValue: "read-ticket"))
}
private nonisolated func downloadDomainPrepared(_ intent: BackgroundMediaTaskIntent) -> StoredBackgroundMediaTaskEvent {
    let command = MediaOperationID(rawValue: "prepared-download")
    return .init(command: command, change: .prepared(intent), commit: .init(key: .backgroundTask(command, intent.id), previousRevision: 10, committedRevision: 11),
        storeIdentity: intent.context.storeIdentity)
}
private nonisolated func downloadDomainFacts(inode: UInt64 = 4, size: Int64 = 4096, modified: Int64 = 10,
    links: UInt64 = 1, changed: Int64 = 10) throws -> BackgroundDownloadSourceFacts {
    try .init(device: 1, inode: inode, size: size, modifiedSeconds: modified, modifiedNanoseconds: 1,
        changedSeconds: changed, changedNanoseconds: 1, linkCount: links)
}
