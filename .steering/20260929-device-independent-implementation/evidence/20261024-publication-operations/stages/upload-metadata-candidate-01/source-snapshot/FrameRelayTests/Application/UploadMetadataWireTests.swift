import Foundation
import Testing
@testable import FrameRelay

struct UploadMetadataWireTests {
    @Test func postHasExactlyEightStringFieldsAndGetUsesTheSameOpaqueUTF8Binding() async throws {
        let (f, query) = try await metadataWireQuery(lookup: false)
        let connection = try metadataHTTPSConnection(f)
        let http = try UploadMetadataWire.http(query, connection: connection)
        let data = try #require(http.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: String])
        let expected = try UploadMetadataWire.fields(f.request)
        #expect(http.httpMethod == "POST" && body.count == 8 && body == expected)
        #expect(body["capture_id"]?.utf8.elementsEqual(f.request.original.capture.rawValue.utf8) == true)
        #expect(http.value(forHTTPHeaderField: "Authorization") == nil && http.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let decoded = try UploadMetadataWire.response(metadataWireData(query), query: query)
        #expect(UploadMetadataValidation.exact(decoded.binding.original, f.request.original))
        try await f.assertBytesAndNoMedia()
    }

    @Test(arguments: ["extra", "missing", "alias", "generation-number", "generation-zero", "leading-zero", "wrong-bytes", "upper-session", "zero-chunk"])
    func strictPostEchoRejectsEveryIdentityOrSchemaChange(fault: String) async throws {
        let (_, query) = try await metadataWireQuery(lookup: false)
        var body = try metadataWireObject(query)
        var binding = try #require(body["binding"] as? [String: Any])
        switch fault {
        case "extra": binding["final_path"] = "not-a-device-path"
        case "missing": binding.removeValue(forKey: "operation_id")
        case "alias": binding["capture_id"] = query.query.request.original.capture.rawValue.decomposedStringWithCanonicalMapping
        case "generation-number": binding["content_generation"] = 1
        case "generation-zero": binding["registration_generation"] = "0"
        case "leading-zero": binding["byte_count"] = "04096"
        case "wrong-bytes": binding["byte_count"] = "4095"
        case "upper-session": binding["session_id"] = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"
        default: binding["chunk_size"] = "0"
        }
        body["binding"] = binding
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        #expect(throws: (any Error).self) { try UploadMetadataWire.response(data, query: query) }
    }

    @Test func knownSessionGETRetainsNumericChunkIndexesAndFullEightFieldProof() async throws {
        let (f, query) = try await metadataWireQuery(lookup: true)
        let http = try UploadMetadataWire.http(query, connection: metadataHTTPSConnection(f))
        #expect(http.httpMethod == "GET" && http.httpBody == nil)
        let queryItems = try #require(URLComponents(url: try #require(http.url), resolvingAgainstBaseURL: false)?.queryItems)
        #expect(queryItems.count == 8 && Set(queryItems.map(\.name)).count == 8)
        #expect(queryItems.first { $0.name == "capture_id" }?.value?.utf8.elementsEqual(f.request.original.capture.rawValue.utf8) == true)
        let response = try UploadMetadataWire.response(metadataWireData(query, state: "completed"), query: query)
        guard case .status(let value) = response else { throw BackendContractError.invalidValue }
        #expect(value.chunkIndexes == [0, 1] && value.state == .completed && value.evidence?.committed == true)
        #expect(value.evidence?.sha256 == f.request.original.content.digest && value.evidence?.byteCount == 4096)
        #expect(value.evidence?.observedAt.timeIntervalSinceReferenceDate.isFinite == true)
        #expect(abs((value.evidence?.observedAt.timeIntervalSince1970 ?? 0) - 1_792_861_200.123456) < 0.000001)
    }

    @Test(arguments: ["a+b", "a b", "a&b=c/d?e#f%g", "literal%2B+space 雪e\u{0301}"])
    func getQuerySurvivesServerFormDecodingWithoutChangingAnyOpaqueUTF8(capture: String) async throws {
        let f = try await MetadataAppFixture.make(capture: capture)
        _ = try metadataRecorded(await UploadMetadataCoordinator(store: f.services.store, remote: MetadataTestRemote()).refresh(f.request))
        let session = try #require(try await mediaSnapshot(f.services.store).requests.first?.session)
        let query = try await metadataBegin(f, kind: .lookup(session))
        let http = try UploadMetadataWire.http(query, connection: metadataHTTPSConnection(f))
        let encoded = try #require(URLComponents(url: try #require(http.url), resolvingAgainstBaseURL: false)?.percentEncodedQuery)
        #expect(!encoded.contains("+"))
        let pairs = try encoded.split(separator: "&").map { item -> (String, String) in
            let pieces = item.split(separator: "=", omittingEmptySubsequences: false)
            try #require(pieces.count == 2)
            let name = try #require(String(pieces[0]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding)
            let value = try #require(String(pieces[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding)
            return (name, value)
        }
        try #require(Set(pairs.map(\.0)).count == pairs.count)
        let form = Dictionary(uniqueKeysWithValues: pairs), expected = try UploadMetadataWire.fields(f.request)
        #expect(form.count == 8 && form == expected)
        #expect(form["capture_id"]?.utf8.elementsEqual(capture.utf8) == true)
        try await f.assertBytesAndNoMedia()
    }

    @Test(arguments: ["float", "exponent", "negative", "negative-zero", "bool", "string", "overflow", "duplicate", "reverse", "range",
        "extra", "unknown-status", "missing-evidence", "unexpected-evidence", "proof-extra", "method", "committed", "save", "sha", "bytes", "numeric-date", "invalid-date"])
    func getRefusesMalformedIndexesPartialProofAndUnboundState(fault: String) async throws {
        let (_, query) = try await metadataWireQuery(lookup: true)
        var body = try metadataWireObject(query, state: "completed")
        switch fault {
        case "float": body["chunk_indexes"] = [0, 1.5]
        case "exponent":
            let data = try metadataWireData(query, state: "completed")
            let text = try #require(String(data: data, encoding: .utf8)).replacingOccurrences(of: "[0,1]", with: "[0,1e0]")
            #expect(throws: (any Error).self) { try UploadMetadataWire.response(Data(text.utf8), query: query) }; return
        case "negative": body["chunk_indexes"] = [-1]
        case "negative-zero":
            let data = try metadataWireData(query, state: "completed")
            let text = try #require(String(data: data, encoding: .utf8)).replacingOccurrences(of: "[0,1]", with: "[-0,1]")
            #expect(throws: (any Error).self) { try UploadMetadataWire.response(Data(text.utf8), query: query) }; return
        case "bool": body["chunk_indexes"] = [false]
        case "string": body["chunk_indexes"] = ["0"]
        case "overflow":
            let data = try metadataWireData(query, state: "completed")
            let text = try #require(String(data: data, encoding: .utf8)).replacingOccurrences(of: "[0,1]", with: "[18446744073709551616]")
            #expect(throws: (any Error).self) { try UploadMetadataWire.response(Data(text.utf8), query: query) }; return
        case "duplicate": body["chunk_indexes"] = [0, 0]
        case "reverse": body["chunk_indexes"] = [1, 0]
        case "range": body["chunk_indexes"] = [4]
        case "extra": body["unexpected"] = false
        case "unknown-status": body["status"] = "sent"
        case "missing-evidence": body["evidence"] = NSNull()
        case "unexpected-evidence": body["status"] = "receiving"
        default:
            var proof = try #require(body["evidence"] as? [String: Any])
            switch fault {
            case "proof-extra": proof["extra"] = "not allowed"
            case "method": proof["method"] = "assembly_only"
            case "committed": proof["committed"] = false
            case "save": proof["final_save_completed"] = false
            case "sha": proof["sha256"] = String(repeating: "f", count: 64)
            case "bytes": proof["byte_count"] = "4095"
            case "numeric-date": proof["observed_at"] = 1_792_861_200
            default: proof["observed_at"] = "2026-02-31T17:00:00.123456+00:00"
            }
            body["evidence"] = proof
        }
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        #expect(throws: (any Error).self) { try UploadMetadataWire.response(data, query: query) }
    }

    @Test func parserRefusesDuplicateKeysInvalidUTF8OversizeAndOldPublicationStillRefusesNumbers() async throws {
        let (_, query) = try await metadataWireQuery(lookup: false)
        let body = String(decoding: try metadataWireData(query), as: UTF8.self)
        let duplicate = "{\"binding\":null," + body.dropFirst()
        for data in [Data(duplicate.utf8), Data([0xff]), Data(repeating: 32, count: 262_145),
                     Data((String(repeating: "[", count: 34) + "0" + String(repeating: "]", count: 34)).utf8)] {
            #expect(throws: (any Error).self) { try UploadMetadataJSON.parse(data) }
        }
        for text in ["0", "[1]", "{\"number\":1}"] {
            #expect(throws: (any Error).self) { try PublicationWire.parse(Data(text.utf8)) }
        }
    }
}

nonisolated func metadataHTTPSConnection(_ f: MetadataAppFixture) throws -> RegistrationConnection {
    try .init(endpoint: .init(httpsOrigin: "https://example.invalid"), destination: f.request.registration.server.registration.destination)
}
nonisolated func metadataWireQuery(lookup: Bool) async throws -> (MetadataAppFixture, CommittedUploadMetadataQuery) {
    let f = try await MetadataAppFixture.make()
    if lookup {
        _ = try metadataRecorded(await UploadMetadataCoordinator(store: f.services.store, remote: MetadataTestRemote()).refresh(f.request))
        let session = try #require(try await mediaSnapshot(f.services.store).requests.first?.session)
        return (f, try await metadataBegin(f, kind: .lookup(session)))
    }
    return (f, try await metadataBegin(f))
}
nonisolated func metadataWireObject(_ query: CommittedUploadMetadataQuery, state: String? = nil) throws -> [String: Any] {
    var binding: [String: Any] = try UploadMetadataWire.fields(query.query.request).mapValues { $0 as Any }
    let session: String
    if case .lookup(let known) = query.query.kind { session = known.rawValue }
    else { session = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" }
    binding["session_id"] = session; binding["chunk_size"] = "1024"
    guard let state else { return ["binding": binding] }
    var result: [String: Any] = ["binding": binding, "status": state, "chunk_indexes": [0, 1], "failure_code": NSNull(), "evidence": NSNull()]
    if state == "completed" {
        result["evidence"] = ["evidence_id": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", "schema_version": "fr-final-read-v1",
            "method": "final_destination_read_back", "committed": true, "final_save_completed": true,
            "sha256": query.query.request.original.content.digest, "byte_count": String(query.query.request.original.content.byteCount),
            "observed_at": "2026-10-24T17:00:00.123456+00:00"] as [String: Any]
    }
    return result
}
nonisolated func metadataWireData(_ query: CommittedUploadMetadataQuery, state: String? = nil) throws -> Data {
    try JSONSerialization.data(withJSONObject: metadataWireObject(query, state: state), options: [.sortedKeys, .withoutEscapingSlashes])
}
