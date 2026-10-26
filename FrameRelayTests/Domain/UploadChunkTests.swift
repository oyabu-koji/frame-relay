import Foundation
import Testing
@testable import FrameRelay

struct UploadChunkTests {
    @Test(arguments: [UInt64(0), 1, 2])
    func firstMiddleAndShortLastRangesDoNotOverlap(index: UInt64) throws {
        let range = try UploadChunkRange(binding: chunkValueBinding(total: 21, size: 8), index: index)
        #expect(range.offset == index * 8 && range.length == [UInt64(8), 8, 5][Int(index)])
        #expect(range.upperBoundExclusive == range.offset + range.length && range.totalByteCount == 21 && range.chunkCount == 3)
        let decoded = try JSONDecoder().decode(UploadChunkRange.self, from: JSONEncoder().encode(range))
        #expect(decoded == range && decoded.binding.original.capture.rawValue.utf8.elementsEqual(range.binding.original.capture.rawValue.utf8))
    }

    @Test(arguments: [UInt64(1), 8, 16, UInt64.max])
    func singleAndExactBoundariesRemainUInt64WithoutRoundingOverflow(total: UInt64) throws {
        let size: UInt64 = total == UInt64.max ? UInt64.max : 8
        let last = (total - 1) / size, range = try UploadChunkRange(binding: chunkValueBinding(total: total, size: size), index: last)
        #expect(range.upperBoundExclusive == total && range.length > 0 && range.length <= size)
        if total <= size { #expect(range.offset == 0 && range.length == total && range.chunkCount == 1) }
        else { #expect(range.offset == 8 && range.length == 8 && range.chunkCount == 2) }
        #expect(throws: BackendContractError.invalidValue) {
            try UploadChunkRange(binding: range.binding, index: range.chunkCount)
        }
    }

    @Test func anOverflowingIndexNeverWrapsIntoAValidRange() throws {
        let binding = try chunkValueBinding(total: UInt64.max, size: 2)
        #expect(throws: BackendContractError.invalidValue) { try UploadChunkRange(binding: binding, index: UInt64.max) }
        let last = try UploadChunkRange(binding: binding, index: UInt64.max / 2)
        #expect(last.offset == UInt64.max - 1 && last.length == 1 && last.upperBoundExclusive == UInt64.max)
    }

    @Test(arguments: ["size", "bytes", "generation", "registration-generation", "digest", "algorithm", "destination", "registration", "operation", "session", "capture"])
    func decodingRevalidatesTheFullBindingInsteadOfTrustingSynthesizedValues(field: String) throws {
        let range = try UploadChunkRange(binding: chunkValueBinding(), index: 0)
        let changed = try chunkValueJSON(range) { object in
            var binding = object["binding"] as! [String: Any]
            switch field {
            case "size": binding["chunkSize"] = 0
            case "bytes", "generation", "digest", "algorithm", "capture":
                var original = binding["original"] as! [String: Any]
                if field == "generation" { original["generation"] = ["rawValue": 0] }
                else if field == "capture" { original["capture"] = ["rawValue": "\0"] }
                else {
                    var content = original["content"] as! [String: Any]
                    if field == "bytes" { content["byteCount"] = 0 }
                    if field == "digest" { content["digest"] = String(repeating: "A", count: 64) }
                    if field == "algorithm" { content["algorithm"] = "other" }
                    original["content"] = content
                }
                binding["original"] = original
            case "registration-generation", "destination", "registration":
                var registration = binding["registration"] as! [String: Any]
                if field == "registration-generation" { registration["generation"] = ["rawValue": 0] }
                else { registration[field == "destination" ? "destination" : "id"] = ["rawValue": "not-a-canonical-uuid"] }
                binding["registration"] = registration
            case "operation": binding["operation"] = ["rawValue": "AAAAAAAA-1111-4111-8111-111111111111"]
            case "session": binding["session"] = ["rawValue": "unknown-session"]
            default: Issue.record("Unknown corruption")
            }
            object["binding"] = binding
        }
        #expect(throws: BackendContractError.invalidValue) { try JSONDecoder().decode(UploadChunkRange.self, from: changed) }
    }

    @Test(arguments: ["offset", "length", "upperBoundExclusive", "totalByteCount", "chunkCount"])
    func independentDerivedRangeFieldsCannotBeInjected(field: String) throws {
        let range = try UploadChunkRange(binding: chunkValueBinding(), index: 0)
        let data = try chunkValueJSON(range) { $0[field] = 1 }
        #expect(throws: BackendContractError.invalidValue) { try JSONDecoder().decode(UploadChunkRange.self, from: data) }
    }

    @Test func opaqueCaptureIdentityUsesUTF8RatherThanCanonicalStringEquivalence() throws {
        let composed = try UploadChunkRange(binding: chunkValueBinding(capture: "  雪+\u{00e9}  "), index: 0)
        let decomposed = try UploadChunkRange(binding: chunkValueBinding(capture: "  雪+e\u{0301}  "), index: 0)
        #expect(composed.binding.original.capture == decomposed.binding.original.capture)
        #expect(composed != decomposed)
        let first = try UploadMetadataValidation.canonicalBytes(composed), second = try UploadMetadataValidation.canonicalBytes(decomposed)
        #expect(first != second)
    }

    @Test func descriptorRequiresItsOwnRangeSizedSHA256AndManagedFileIdentity() throws {
        let range = try UploadChunkRange(binding: chunkValueBinding(), index: 0)
        let content = try ContentIdentity(byteCount: range.length, algorithm: "sha256", digest: String(repeating: "b", count: 64))
        let descriptor = try UploadChunkDescriptor(range: range, content: content)
        #expect(descriptor.content != range.binding.original.content)
        #expect(throws: BackendContractError.identityMismatch) {
            try UploadChunkDescriptor(range: range, content: range.binding.original.content)
        }
        let source = chunkValueSource(content: content)
        let managed = try ManagedUploadChunkIdentity(source: source, descriptor: descriptor)
        #expect(try JSONDecoder().decode(ManagedUploadChunkIdentity.self, from: JSONEncoder().encode(managed)) == managed)
        let foreign = try ContentIdentity(byteCount: content.byteCount, algorithm: "sha256", digest: String(repeating: "c", count: 64))
        #expect(throws: BackendContractError.identityMismatch) {
            try ManagedUploadChunkIdentity(source: chunkValueSource(content: foreign), descriptor: descriptor)
        }
        let mismatched = try chunkValueJSON(managed) { object in
            var source = object["source"] as! [String: Any], file = source["file"] as! [String: Any]
            file["size"] = -1; source["file"] = file; object["source"] = source
        }
        #expect(throws: BackendContractError.invalidValue) { try JSONDecoder().decode(ManagedUploadChunkIdentity.self, from: mismatched) }
        let badDescriptor = try chunkValueJSON(descriptor) { $0["content"] = ["byteCount": range.length, "algorithm": "sha256", "digest": "wrong"] }
        #expect(throws: BackendContractError.invalidValue) { try JSONDecoder().decode(UploadChunkDescriptor.self, from: badDescriptor) }
    }

    @Test func selectionIsCompactAndMustRejoinTheWholeActualObservation() throws {
        // Pure synthetic receipt inputs; actual receipt durability belongs to
        // the same-writer integration boundary, never this value test.
        let saved = try chunkValueObservation(), selection = try UploadChunkMetadataSelection(saved)
        #expect(selection.matches(saved) && selection.expectedKey == saved.observation.key && selection.commit == saved.commit)
        let data = try JSONEncoder().encode(selection)
        let fields = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(fields.keys) == ["storeIdentity", "observationCommand", "queryID", "observationFingerprint", "observationGeneration", "previousRevision", "committedRevision"])
        #expect(data.count < 1024 && !String(decoding: data, as: UTF8.self).contains("original"))
        #expect(try JSONDecoder().decode(UploadChunkMetadataSelection.self, from: data) == selection)
        let unrelated = try chunkValueObservation()
        #expect(!selection.matches(unrelated))
        let borrowed = StoredUploadMetadataObservation(observation: unrelated.observation, commit: saved.commit, expectedStoreIdentity: saved.expectedStoreIdentity)
        #expect(throws: BackendContractError.notCommitted) { try UploadChunkMetadataSelection(borrowed) }
        let invalid = try chunkValueJSON(selection) { $0["committedRevision"] = selection.previousRevision }
        #expect(throws: BackendContractError.invalidValue) { try JSONDecoder().decode(UploadChunkMetadataSelection.self, from: invalid) }
        let wrongKey = try chunkValueJSON(selection) { $0["queryID"] = ["rawValue": selection.observationCommand.rawValue] }
        #expect(throws: BackendContractError.invalidValue) { try JSONDecoder().decode(UploadChunkMetadataSelection.self, from: wrongKey) }
        let changed = try chunkValueJSON(selection) { $0["observationGeneration"] = ["rawValue": 2] }
        #expect(!(try JSONDecoder().decode(UploadChunkMetadataSelection.self, from: changed)).matches(saved))
    }

    @Test(arguments: ["index", "bytes", "hash"])
    func aChunkReceiptCannotBorrowOtherChunkOrWholeContent(field: String) throws {
        let range = try UploadChunkRange(binding: chunkValueBinding(), index: 0)
        let descriptor = try UploadChunkDescriptor(range: range,
            content: .init(byteCount: range.length, algorithm: "sha256", digest: String(repeating: "b", count: 64)))
        let receipt = try UploadChunkReceipt(descriptor: descriptor, chunkIndex: range.index, byteCount: range.length, sha256: descriptor.content.digest)
        #expect(try JSONDecoder().decode(UploadChunkReceipt.self, from: JSONEncoder().encode(receipt)) == receipt)
        let invalid = try chunkValueJSON(receipt) { object in
            if field == "index" { object["chunkIndex"] = 1 }
            if field == "bytes" { object["byteCount"] = range.totalByteCount }
            if field == "hash" { object["sha256"] = range.binding.original.content.digest }
        }
        #expect(throws: BackendContractError.identityMismatch) { try JSONDecoder().decode(UploadChunkReceipt.self, from: invalid) }
    }
}

private nonisolated func chunkValueBinding(total: UInt64 = 21, size: UInt64 = 8, capture: String = "opaque+雪e\u{0301}") throws -> UploadMetadataBinding {
    try .init(registration: .init(destination: .init(rawValue: "11111111-1111-4111-8111-111111111111"),
        id: .init(rawValue: "22222222-2222-4222-8222-222222222222"), generation: .init(rawValue: 1)),
        operation: .init(rawValue: "33333333-3333-4333-8333-333333333333"),
        original: .init(capture: .init(rawValue: capture), generation: .init(rawValue: 1),
            content: .init(byteCount: total, algorithm: "sha256", digest: String(repeating: "a", count: 64))),
        session: .init(rawValue: "44444444-4444-4444-8444-444444444444"), chunkSize: size)
}
private nonisolated func chunkValueSource(content: ContentIdentity) -> ManagedUploadSourceIdentity {
    .init(id: .init(rawValue: UUID().uuidString), directoryDevice: 1, directoryInode: 2,
        file: .init(device: 1, inode: 3, size: Int64(content.byteCount), modifiedSeconds: 0, modifiedNanoseconds: 1,
            changedSeconds: 0, changedNanoseconds: 1), content: content)
}
private nonisolated func chunkValueJSON<T: Encodable>(_ value: T, change: (inout [String: Any]) throws -> Void) throws -> Data {
    let bytes = try JSONEncoder().encode(value)
    var object = try #require(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    try change(&object); return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
}
private nonisolated func chunkValueObservation() throws -> StoredUploadMetadataObservation {
    let registration = try BackendOperationFixture().deviceRegistration
    let source = try UploadMetadataRequest(storeIdentity: .init(rawValue: UUID()), registration: registration,
        operation: .init(rawValue: UUID().uuidString), original: chunkValueBinding().original, expectedStartRevision: 30)
    let session = UploadSessionID(rawValue: UUID().uuidString.lowercased())
    let query = try UploadMetadataQuery(id: .init(rawValue: UUID().uuidString), observationCommand: .init(rawValue: UUID().uuidString),
        request: source, kind: .lookup(session), generation: .init(rawValue: 1))
    let committed = CommittedUploadMetadataQuery(query: query, commit: .init(key: query.key, previousRevision: 40, committedRevision: 41), expectedStoreIdentity: source.storeIdentity)
    let binding = UploadMetadataBinding(registration: registration.server.registration, operation: source.operation, original: source.original, session: session, chunkSize: 8)
    let observation = try UploadMetadataObservation(command: query.observationCommand, query: committed,
        response: .status(.init(binding: binding, state: .receiving, evidence: nil, chunkIndexes: [], failureCode: nil)))
    return .init(observation: observation, commit: .init(key: observation.key, previousRevision: 45, committedRevision: 46), expectedStoreIdentity: source.storeIdentity)
}
