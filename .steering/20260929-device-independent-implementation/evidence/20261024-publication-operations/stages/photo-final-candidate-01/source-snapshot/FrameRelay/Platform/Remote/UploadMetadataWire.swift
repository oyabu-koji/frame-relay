import Foundation

nonisolated enum UploadMetadataWire {
    static let maximumBytes = 262_144
    static let bindingKeys: Set<String> = ["destination_id", "registration_id", "registration_generation", "operation_id",
        "capture_id", "content_generation", "sha256", "byte_count", "session_id", "chunk_size"]

    static func fields(_ request: UploadMetadataRequest) throws -> [String: String] {
        try request.validate()
        let registration = request.registration.server.registration, original = request.original
        for text in [registration.destination.rawValue, registration.id.rawValue, request.operation.rawValue] {
            guard RegistrationWireIdentity.isCanonical(text) else { throw BackendContractError.invalidValue }
        }
        guard registration.generation.rawValue > 0, registration.generation.rawValue <= UInt64(Int64.max),
              !original.capture.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !original.capture.rawValue.contains("\0"), original.capture.rawValue.utf8.count <= 4096 else {
            throw BackendContractError.invalidValue
        }
        return ["destination_id": registration.destination.rawValue, "registration_id": registration.id.rawValue,
            "registration_generation": String(registration.generation.rawValue), "operation_id": request.operation.rawValue,
            "capture_id": original.capture.rawValue, "content_generation": String(original.generation.rawValue),
            "sha256": original.content.digest, "byte_count": String(original.content.byteCount)]
    }

    static func http(_ query: CommittedUploadMetadataQuery, connection: RegistrationConnection) throws -> URLRequest {
        guard query.isCommitted,
              UploadMetadataValidation.exact(connection.destination, query.query.request.registration.server.registration.destination) else {
            throw BackendContractError.notCommitted
        }
        let fields = try fields(query.query.request)
        let url: URL, method: String, body: Data?
        switch query.query.kind {
        case .create:
            url = connection.endpoint.url(path: "uploads"); method = "POST"
            body = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes])
        case .lookup(let session):
            guard RegistrationWireIdentity.isCanonical(session.rawValue) else { throw BackendContractError.invalidValue }
            var parts = URLComponents(url: connection.endpoint.url(path: "uploads/" + session.rawValue), resolvingAgainstBaseURL: false)!
            let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
            parts.percentEncodedQuery = try fields.keys.sorted().map { key in
                guard let name = key.addingPercentEncoding(withAllowedCharacters: unreserved),
                      let value = fields[key]!.addingPercentEncoding(withAllowedCharacters: unreserved) else {
                    throw BackendContractError.invalidValue
                }
                return name + "=" + value
            }.joined(separator: "&")
            guard let value = parts.url else { throw BackendContractError.invalidValue }
            url = value; method = "GET"; body = nil
        }
        guard body.map({ $0.count <= maximumBytes }) ?? true else { throw BackendContractError.invalidValue }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15)
        request.httpMethod = method; request.httpBody = body; request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }

    static func response(_ data: Data, query: CommittedUploadMetadataQuery) throws -> UploadMetadataResponse {
        guard query.isCommitted else { throw BackendContractError.notCommitted }
        let value = try UploadMetadataJSON.parse(data)
        let expected = query.query.request
        switch query.query.kind {
        case .create:
            let top = try value.object(["binding"])
            return .created(try binding(top["binding"]!, request: expected))
        case .lookup(let session):
            let top = try value.object(["binding", "status", "evidence", "chunk_indexes", "failure_code"])
            let binding = try binding(top["binding"]!, request: expected)
            guard UploadMetadataValidation.exact(binding.session, session),
                  let state = UploadMetadataState(rawValue: try top["status"]!.text()),
                  case .array(let indexes) = top["chunk_indexes"] else { throw BackendContractError.identityMismatch }
            let evidence = top["evidence"] == .null ? nil : try evidence(top["evidence"]!, original: expected.original)
            let failure = top["failure_code"] == .null ? nil : try top["failure_code"]!.text()
            let result = UploadMetadataStatus(binding: binding, state: state, evidence: evidence,
                chunkIndexes: try indexes.map { try $0.uint(numericToken: true) }, failureCode: failure)
            try result.validate(for: expected)
            return .status(result)
        }
    }

    private static func binding(_ value: UploadMetadataJSON, request: UploadMetadataRequest) throws -> UploadMetadataBinding {
        let fields = try value.object(bindingKeys), expected = try self.fields(request)
        for (key, text) in expected {
            guard case .string(let actual) = fields[key], actual.utf8.elementsEqual(text.utf8) else {
                throw BackendContractError.identityMismatch
            }
        }
        let session = try fields["session_id"]!.text()
        guard RegistrationWireIdentity.isCanonical(session) else { throw BackendContractError.invalidValue }
        let result = UploadMetadataBinding(registration: request.registration.server.registration, operation: request.operation,
            original: request.original, session: .init(rawValue: session), chunkSize: try fields["chunk_size"]!.uint(positive: true))
        try result.validate(for: request)
        return result
    }

    private static func evidence(_ value: UploadMetadataJSON, original: OriginalContent) throws -> UploadFinalReadEvidence {
        let fields = try value.object(["evidence_id", "schema_version", "method", "committed", "final_save_completed", "sha256", "byte_count", "observed_at"])
        let id = try fields["evidence_id"]!.text(), observed = try fields["observed_at"]!.text()
        // repository.now_text emits UTC ISO8601 with exactly six fractional
        // digits. Numeric timestamps and partially parsed date strings refuse.
        guard RegistrationWireIdentity.isCanonical(id), observed.range(of:
            #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{6}\+00:00$"#,
            options: .regularExpression) != nil else { throw BackendContractError.invalidValue }
        let seconds = String(observed.prefix(19)) + "+00:00"
        let micros = String(observed.dropFirst(20).prefix(6))
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        guard !observed.hasPrefix("0000-"), let base = formatter.date(from: seconds),
              formatter.string(from: base).replacingOccurrences(of: "Z", with: "+00:00") == seconds,
              let fraction = Double(micros) else { throw BackendContractError.invalidValue }
        let date = base.addingTimeInterval(fraction / 1_000_000)
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw BackendContractError.invalidValue
        }
        let result = UploadFinalReadEvidence(id: .init(rawValue: id), schemaVersion: try fields["schema_version"]!.text(),
            method: try fields["method"]!.text(), committed: try fields["committed"]!.bool(),
            finalSaveCompleted: try fields["final_save_completed"]!.bool(), sha256: try fields["sha256"]!.text(),
            byteCount: try fields["byte_count"]!.uint(positive: true), observedAt: date)
        try result.validate(for: original)
        return result
    }
}
