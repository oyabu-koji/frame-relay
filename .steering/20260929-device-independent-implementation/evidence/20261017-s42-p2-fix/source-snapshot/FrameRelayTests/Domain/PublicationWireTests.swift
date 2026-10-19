import Foundation
import Testing
@testable import FrameRelay

@MainActor struct PublicationWireTests {
    @Test func opaqueIdentityComparesDecodedUTF8WithoutUnicodeNormalization() throws {
        let nfc = "\u{e9}", nfd = "e\u{301}"
        #expect(nfc == nfd) // Demonstrates why native String equality is insufficient.
        #expect(PublicationJSON.string(nfc) != .string(nfd))
        #expect(try PublicationWire.parse(Data("\"\\u00e9\"".utf8)) == .string(nfc))
        #expect(try PublicationWire.parse(Data("\"e\\u0301\"".utf8)) == .string(nfd))
        #expect(!PublicationStoreBoundary.exact(MediaOperationID(rawValue: nfc), MediaOperationID(rawValue: nfd)))
        let request = PublicationJSON.object(["id": .string(nfc)])
        let changed = PublicationJSON.object(["schema_version": .string(PublicationWire.version), "request": .object(["id": .string(nfd)]), "result": .null])
        #expect(throws: BackendContractError.identityMismatch) { try PublicationWire.envelope(PublicationWire.body(changed), request: request) }
    }
    @Test(arguments: ["{\"x\":\"1\",\"x\":\"2\"}", "{\"x\":{\"y\":true,\"y\":false}}", "{\"x\":1}", "{\"x\":NaN}", "{\"x\":\"\\uD800\"}", "[true,]", "{\"x\":true}false"])
    func duplicateKeysNumbersAndMalformedJSONAreRejected(text: String) {
        #expect(throws: (any Error).self) { try PublicationWire.parse(Data(text.utf8)) }
    }
    @Test func canonicalDecimalAndOpaqueIdentityDoNotNormalize() throws {
        for invalid in ["00", "01", "+1", "-1", " 1", "1.0", "18446744073709551616"] {
            #expect(throws: BackendContractError.invalidValue) { try PublicationJSON.string(invalid).uint() }
        }
        #expect(try PublicationJSON.string("18446744073709551615").uint() == UInt64.max)
        let id = "opaque/本人=?\r\n"
        let encoded = try PublicationWire.headerID(id)
        #expect(!encoded.contains("\r") && !encoded.contains("\n") && !encoded.contains("="))
        #expect(try PublicationWire.parse(PublicationWire.body(.string(id))) == .string(id))
        #expect(throws: BackendContractError.invalidValue) { try PublicationWire.text(String(repeating: "a", count: 1025)) }
    }
    @Test func distributionLookupMustMatchCompleteOriginalRequestAndCommit() async throws {
        try await withStorageRun { run in
            let f = try await PublicationFixture.make(run: run)
            let gate = MediaGateLease(operation: .init(rawValue: "transport"), attempt: .init(rawValue: "attempt"), target: .rendition(f.rendition), registration: f.registration, generation: 1)
            let request = PublicationDistributionRequest(operation: .init(rawValue: "distribution"), gate: gate, rendition: f.rendition,
                purpose: .read, kind: .range, range: try .init(lowerBound: 4, upperBound: 8), source: .init(rawValue: "source"))
            let original = try PublicationWire.distributionRequest(request)
            let lookup = try PublicationWire.lookupRequest(registration: f.registration, kind: "distribution", operation: request.operation.rawValue)
            let receipt = DistributionReceipt(operation: request.operation, rendition: f.rendition, registration: f.registration,
                commit: .init(key: .distribution(request.operation, f.rendition, f.registration), previousRevision: 7, committedRevision: 8))
            let result = PublicationJSON.object(["receipt": try PublicationWire.distribution(receipt), "media_type": .string("video/quicktime")])
            let envelope = PublicationJSON.object(["schema_version": .string(PublicationWire.version), "request": lookup,
                "result": .object(["original_request": original, "original_result": result])])
            let decoded = try PublicationWire.lookupResult(PublicationWire.body(envelope), lookup: lookup, original: original)
            #expect(try PublicationWire.decodeDistribution(decoded, expected: request).receipt == receipt)
            let changed = PublicationDistributionRequest(operation: request.operation, gate: gate, rendition: f.rendition,
                purpose: .read, kind: .range, range: try .init(lowerBound: 5, upperBound: 8), source: request.source)
            #expect(throws: BackendContractError.identityMismatch) {
                try PublicationWire.lookupResult(PublicationWire.body(envelope), lookup: lookup, original: PublicationWire.distributionRequest(changed))
            }
            let extra = PublicationJSON.object(["receipt": try PublicationWire.distribution(receipt), "media_type": .string("video/quicktime"), "legacy": .boolean(true)])
            #expect(throws: BackendContractError.unsupportedVersion) { try PublicationWire.decodeDistribution(extra, expected: request) }
        }
    }
    @Test func sha256CanonicalUUIDAndNullInitialPublicationAreExact() throws {
        let initial = PublicationJSON.object(["current": .null, "revision": .string("0"), "invalidation_generation": .string("0"), "replacement_pending": .boolean(false), "media_type": .null])
        let original = try publicationOriginal("initial")
        #expect(try PublicationWire.decodeManifest(initial, original: original).current == nil)
        #expect(throws: BackendContractError.invalidValue) {
            try PublicationWire.decodeContent(.object(["algorithm": .string("sha256"), "digest": .string(String(repeating: "A", count: 64)), "byte_count": .string("1")]))
        }
        var bytes = Data([0xff]); bytes.append(Data("{}".utf8))
        #expect(throws: BackendContractError.unsupportedVersion) { try PublicationWire.parse(bytes) }
    }
}
