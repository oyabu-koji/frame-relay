import Foundation

/// Dedicated chunk wire contract. It does not send HTTP, adopt a receipt into
/// the journal, finalize a job or create whole-original verification evidence.
nonisolated enum UploadChunkWire {
    static let maximumReceiptBytes = 4096
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func request(descriptor: UploadChunkDescriptor, connection: RegistrationConnection,
                        authorization: RegistrationAuthorization) throws -> URLRequest {
        try descriptor.validate()
        guard UploadMetadataValidation.exact(connection.destination, descriptor.range.binding.registration.destination),
              validHeaderSecret(authorization.bearer), let secret = authorization.secret, validHeaderSecret(secret) else {
            throw BackendContractError.identityMismatch
        }
        let range = descriptor.range
        var parts = URLComponents(url: connection.endpoint.url(path: path(range)), resolvingAgainstBaseURL: false)!
        parts.percentEncodedQuery = try query(range.binding)
        guard let url = parts.url else { throw BackendContractError.invalidValue }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 60)
        request.httpMethod = "PUT"; request.httpShouldHandleCookies = false
        for (name, value) in fixedHeaders(descriptor) { request.setValue(value, forHTTPHeaderField: name) }
        request.setValue("Bearer " + authorization.bearer, forHTTPHeaderField: "Authorization")
        request.setValue(secret, forHTTPHeaderField: "X-FrameRelay-Registration-Secret")
        _ = try validate(request: request, descriptor: descriptor)
        return request
    }

    /// Exact typed endpoint/query/header comparison, repeated on the native
    /// executor before suspended creation. No credential values are returned.
    static func validate(request: URLRequest, descriptor: UploadChunkDescriptor) throws -> URLComponents {
        try descriptor.validate()
        let range = descriptor.range
        guard request.httpMethod == "PUT", request.httpBody == nil, request.httpBodyStream == nil,
              !request.httpShouldHandleCookies, let url = request.url,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = parts.host, !host.isEmpty, allowedOrigin(parts),
              parts.user == nil, parts.password == nil, parts.percentEncodedFragment == nil,
              parts.percentEncodedPath == "/frame-relay/v1/" + path(range),
              parts.percentEncodedQuery?.utf8.elementsEqual(try query(range.binding).utf8) == true,
              parts.port.map({ (1...65_535).contains($0) }) ?? true else { throw BackendContractError.invalidValue }
        var headers: [String: String] = [:]
        for (raw, value) in request.allHTTPHeaderFields ?? [:] {
            let name = raw.lowercased()
            guard headers[name] == nil, !value.contains("\r"), !value.contains("\n"), !value.contains("\0") else {
                throw BackendContractError.invalidValue
            }
            headers[name] = value
        }
        let expected = fixedHeaders(descriptor)
        guard Set(headers.keys) == Set(expected.keys).union(["authorization", "x-framerelay-registration-secret"]) else {
            throw BackendContractError.invalidValue
        }
        for (name, value) in expected {
            guard headers[name]?.utf8.elementsEqual(value.utf8) == true else { throw BackendContractError.identityMismatch }
        }
        guard let bearer = headers["authorization"], bearer.hasPrefix("Bearer "), validHeaderSecret(String(bearer.dropFirst(7))),
              let secret = headers["x-framerelay-registration-secret"], validHeaderSecret(secret) else { throw BackendContractError.invalidValue }
        return parts
    }

    static func receipt(_ data: Data, descriptor: UploadChunkDescriptor) throws -> UploadChunkReceipt {
        guard !data.isEmpty, data.count <= maximumReceiptBytes else { throw BackendContractError.unsupportedVersion }
        try requireFlatReceipt(data)
        let fields = try UploadMetadataJSON.parse(data).object(["chunk_index", "byte_count", "sha256"])
        return try .init(descriptor: descriptor, chunkIndex: fields["chunk_index"]!.uint(numericToken: true),
            byteCount: fields["byte_count"]!.uint(positive: true), sha256: fields["sha256"]!.text())
    }

    /// All three fields are scalars. Reject nested containers before the
    /// shared strict parser, without changing its metadata-number policy.
    private static func requireFlatReceipt(_ data: Data) throws {
        var quoted = false, escaped = false, depth = 0
        for byte in data {
            if quoted {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { quoted = false }
                continue
            }
            if byte == 34 { quoted = true }
            else if byte == 123 { depth += 1; guard depth == 1 else { throw BackendContractError.unsupportedVersion } }
            else if byte == 125 { depth -= 1; guard depth >= 0 else { throw BackendContractError.unsupportedVersion } }
            else if byte == 91 || byte == 93 { throw BackendContractError.unsupportedVersion }
        }
    }

    private static func path(_ range: UploadChunkRange) -> String {
        "uploads/" + range.binding.session.rawValue + "/chunks/" + String(range.index)
    }
    private static func query(_ binding: UploadMetadataBinding) throws -> String {
        let registration = binding.registration, original = binding.original
        let fields = ["destination_id": registration.destination.rawValue, "registration_id": registration.id.rawValue,
            "registration_generation": String(registration.generation.rawValue), "operation_id": binding.operation.rawValue,
            "capture_id": original.capture.rawValue, "content_generation": String(original.generation.rawValue),
            "sha256": original.content.digest, "byte_count": String(original.content.byteCount)]
        return try fields.keys.sorted().map { key in
            guard let name = key.addingPercentEncoding(withAllowedCharacters: unreserved),
                  let value = fields[key]!.addingPercentEncoding(withAllowedCharacters: unreserved) else { throw BackendContractError.invalidValue }
            return name + "=" + value
        }.joined(separator: "&")
    }
    private static func fixedHeaders(_ descriptor: UploadChunkDescriptor) -> [String: String] {
        let range = descriptor.range
        return ["accept": "application/json", "content-type": "application/octet-stream", "content-length": String(range.length),
            "content-range": "bytes \(range.offset)-\(range.upperBoundExclusive - 1)/\(range.totalByteCount)", "x-chunk-sha256": descriptor.content.digest]
    }
    private static func validHeaderSecret(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 8192 && value.utf8.allSatisfy { (33...126).contains($0) }
    }
    private static func allowedOrigin(_ parts: URLComponents) -> Bool {
        if parts.scheme == "https" { return true }
        #if DEBUG && targetEnvironment(simulator)
        return parts.scheme == "http" && parts.host == "127.0.0.1"
        #else
        return false
        #endif
    }
}
