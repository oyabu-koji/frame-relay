import Foundation
import Testing
@testable import FrameRelay

struct UploadChunkWireTests {
    @Test(arguments: ["a+b", "a b", "a&b=c/d?e#f%g", "  雪e\u{0301}+  "])
    func putUsesEightExactFormDecodedFieldsAndRangeHeaders(capture: String) throws {
        let descriptor = try chunkWireDescriptor(capture: capture), request = try chunkWireRequest(descriptor)
        let url = try #require(request.url), parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = try #require(parts.percentEncodedQuery)
        let fields = try query.split(separator: "&").map { item -> (String, String) in
            let values = item.split(separator: "=", omittingEmptySubsequences: false)
            try #require(values.count == 2)
            let key = try #require(String(values[0]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding)
            let value = try #require(String(values[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding)
            return (key, value)
        }
        try #require(fields.count == 8 && Set(fields.map { $0.0 }).count == 8)
        let actual = Dictionary(uniqueKeysWithValues: fields), binding = descriptor.range.binding
        #expect(actual.count == 8 && fields.count == 8)
        #expect(actual["capture_id"]?.utf8.elementsEqual(capture.utf8) == true)
        #expect(actual["destination_id"] == binding.registration.destination.rawValue && actual["registration_id"] == binding.registration.id.rawValue)
        #expect(actual["registration_generation"] == "2" && actual["operation_id"] == binding.operation.rawValue)
        #expect(actual["content_generation"] == "3" && actual["sha256"] == binding.original.content.digest && actual["byte_count"] == "5000")
        #expect(!query.contains("+") && parts.path == "/frame-relay/v1/uploads/" + binding.session.rawValue + "/chunks/1")
        #expect(request.httpMethod == "PUT" && request.httpBody == nil && request.httpBodyStream == nil && !request.httpShouldHandleCookies)
        #expect(request.value(forHTTPHeaderField: "Content-Range") == "bytes 2048-4095/5000")
        #expect(request.value(forHTTPHeaderField: "Content-Length") == "2048" && request.value(forHTTPHeaderField: "X-Chunk-SHA256") == descriptor.content.digest)
    }

    @Test func fingerprintHasItsOwnVersionAndMasksBothRotatingCredentials() throws {
        let descriptor = try chunkWireDescriptor(), request = try chunkWireRequest(descriptor)
        let fingerprint = try BackgroundMediaRequestFingerprint.makeUploadChunk(request: request, descriptor: descriptor)
        var changed = request
        changed.setValue("Bearer synthetic-rotated-bearer", forHTTPHeaderField: "Authorization")
        changed.setValue("synthetic-rotated-secret", forHTTPHeaderField: "X-FrameRelay-Registration-Secret")
        #expect(try BackgroundMediaRequestFingerprint.makeUploadChunk(request: changed, descriptor: descriptor) == fingerprint)
        changed.url = URL(string: request.url!.absoluteString.replacingOccurrences(of: "chunk-upload.invalid", with: "other-chunk.invalid"))
        #expect(try BackgroundMediaRequestFingerprint.makeUploadChunk(request: changed, descriptor: descriptor) != fingerprint)
        let persisted = String(decoding: try JSONEncoder().encode(fingerprint), as: UTF8.self)
        #expect(fingerprint.sha256.count == 64 && !persisted.contains("synthetic-") && !persisted.contains("chunk-upload.invalid"))
        #expect(throws: BackendContractError.invalidValue) { try BackgroundMediaRequestFingerprint.make(request: request) }
    }

    @Test(arguments: ["method", "index", "session", "query", "duplicate", "body", "stream", "length", "range", "hash", "cookie", "proxy", "extra", "auth", "secret"])
    func fingerprintRejectsEveryUnboundRequestComponent(field: String) throws {
        let descriptor = try chunkWireDescriptor()
        var request = try chunkWireRequest(descriptor)
        switch field {
        case "method": request.httpMethod = "POST"
        case "index": request.url = URL(string: request.url!.absoluteString.replacingOccurrences(of: "/chunks/1?", with: "/chunks/0?"))
        case "session": request.url = URL(string: request.url!.absoluteString.replacingOccurrences(of: descriptor.range.binding.session.rawValue, with: UUID().uuidString.lowercased()))
        case "query": request.url = URL(string: request.url!.absoluteString + "&foreign=value")
        case "duplicate": request.url = URL(string: request.url!.absoluteString + "&capture_id=another")
        case "body": request.httpBody = Data([1])
        case "stream": request.httpBodyStream = InputStream(data: Data([1]))
        case "length": request.setValue("02048", forHTTPHeaderField: "Content-Length")
        case "range": request.setValue("bytes 0-2047/5000", forHTTPHeaderField: "Content-Range")
        case "hash": request.setValue(descriptor.range.binding.original.content.digest, forHTTPHeaderField: "X-Chunk-SHA256")
        case "cookie": request.setValue("foreign-cookie=value", forHTTPHeaderField: "Cookie")
        case "proxy": request.setValue("Bearer foreign", forHTTPHeaderField: "Proxy-Authorization")
        case "extra": request.setValue("foreign", forHTTPHeaderField: "X-Unadopted")
        case "auth": request.setValue(nil, forHTTPHeaderField: "Authorization")
        case "secret": request.setValue(nil, forHTTPHeaderField: "X-FrameRelay-Registration-Secret")
        default: throw BackendContractError.invalidValue
        }
        #expect(throws: BackendContractError.self) { try BackgroundMediaRequestFingerprint.makeUploadChunk(request: request, descriptor: descriptor) }
    }

    @Test func receiptBindsOnlyTheChunkAndAcceptsTheExactSizeLimit() throws {
        let descriptor = try chunkWireDescriptor(), data = chunkWireReceipt(descriptor)
        let receipt = try UploadChunkWire.receipt(data, descriptor: descriptor)
        #expect(receipt.descriptor == descriptor && receipt.chunkIndex == 1 && receipt.byteCount == 2048 && receipt.sha256 == descriptor.content.digest)
        var boundary = data; boundary.append(Data(repeating: 32, count: 4096 - data.count))
        #expect(try UploadChunkWire.receipt(boundary, descriptor: descriptor) == receipt)
        boundary.append(32)
        #expect(throws: BackendContractError.unsupportedVersion) { try UploadChunkWire.receipt(boundary, descriptor: descriptor) }
    }

    @Test(arguments: ["true", "1.0", "1e0", "-0", "-1", "18446744073709551616", "\"1\""])
    func receiptIndexesRequireCanonicalJSONUnsignedInteger(token: String) throws {
        let descriptor = try chunkWireDescriptor()
        let invalid = Data("{\"chunk_index\":\(token),\"byte_count\":\"2048\",\"sha256\":\"\(descriptor.content.digest)\"}".utf8)
        #expect(throws: BackendContractError.self) { try UploadChunkWire.receipt(invalid, descriptor: descriptor) }
    }

    @Test(arguments: ["duplicate", "extra", "empty", "invalid-utf8", "wrong-hash", "wrong-index", "wrong-bytes", "leading-zero", "numeric-bytes", "nested", "trailing"])
    func malformedReceiptsCannotCreateTypedAuthority(field: String) throws {
        let descriptor = try chunkWireDescriptor(), valid = String(decoding: chunkWireReceipt(descriptor), as: UTF8.self)
        let data: Data
        switch field {
        case "duplicate": data = Data(valid.dropLast().utf8) + Data(",\"chunk_index\":1}".utf8)
        case "extra": data = Data(valid.dropLast().utf8) + Data(",\"final_save_completed\":true}".utf8)
        case "empty": data = Data()
        case "invalid-utf8": data = Data([123, 34, 255, 34, 58, 48, 125])
        case "wrong-hash": data = Data(valid.replacingOccurrences(of: descriptor.content.digest, with: descriptor.range.binding.original.content.digest).utf8)
        case "wrong-index": data = Data(valid.replacingOccurrences(of: "\"chunk_index\":1", with: "\"chunk_index\":0").utf8)
        case "wrong-bytes": data = Data(valid.replacingOccurrences(of: "\"2048\"", with: "\"5000\"").utf8)
        case "leading-zero": data = Data(valid.replacingOccurrences(of: "\"2048\"", with: "\"02048\"").utf8)
        case "numeric-bytes": data = Data(valid.replacingOccurrences(of: "\"2048\"", with: "2048").utf8)
        case "nested": data = Data(valid.replacingOccurrences(of: "\"chunk_index\":1", with: "\"chunk_index\":[1]").utf8)
        case "trailing": data = Data((valid + "true").utf8)
        default: throw BackendContractError.invalidValue
        }
        #expect(throws: BackendContractError.self) { try UploadChunkWire.receipt(data, descriptor: descriptor) }
    }
}

nonisolated func chunkWireDescriptor(capture: String = "opaque+雪e\u{0301}") throws -> UploadChunkDescriptor {
    let original = OriginalContent(capture: .init(rawValue: capture), generation: .init(rawValue: 3),
        content: try .init(byteCount: 5000, algorithm: "sha256", digest: String(repeating: "a", count: 64)))
    let binding = UploadMetadataBinding(registration: .init(destination: .init(rawValue: "11111111-1111-4111-8111-111111111111"),
        id: .init(rawValue: "22222222-2222-4222-8222-222222222222"), generation: .init(rawValue: 2)),
        operation: .init(rawValue: "33333333-3333-4333-8333-333333333333"), original: original,
        session: .init(rawValue: "44444444-4444-4444-8444-444444444444"), chunkSize: 2048)
    return try .init(range: .init(binding: binding, index: 1), content: .init(byteCount: 2048, algorithm: "sha256", digest: String(repeating: "b", count: 64)))
}
nonisolated func chunkWireRequest(_ descriptor: UploadChunkDescriptor) throws -> URLRequest {
    try UploadChunkWire.request(descriptor: descriptor,
        connection: .init(endpoint: .init(httpsOrigin: "https://chunk-upload.invalid"), destination: descriptor.range.binding.registration.destination),
        authorization: .init(bearer: "synthetic-disposable-bearer", secret: "synthetic-disposable-secret"))
}
private nonisolated func chunkWireReceipt(_ descriptor: UploadChunkDescriptor) -> Data {
    Data("{\"chunk_index\":\(descriptor.range.index),\"byte_count\":\"\(descriptor.range.length)\",\"sha256\":\"\(descriptor.content.digest)\"}".utf8)
}
