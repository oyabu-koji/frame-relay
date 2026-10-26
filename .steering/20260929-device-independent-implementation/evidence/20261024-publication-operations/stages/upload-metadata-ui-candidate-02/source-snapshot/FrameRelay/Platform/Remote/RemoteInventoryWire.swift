import Foundation

/// This metadata schema reuses the strict duplicate-key parser, not synthesized enum Codable.
nonisolated enum RemoteInventoryWire {
    static func url(connection: RegistrationConnection, registration: RegistrationIdentity, after: String?) throws -> URL {
        guard registration.destination == connection.destination,
              RegistrationWireIdentity.isCanonical(registration.destination.rawValue),
              RegistrationWireIdentity.isCanonical(registration.id.rawValue),
              registration.generation.rawValue > 0, registration.generation.rawValue <= UInt64(Int64.max) else {
            throw BackendContractError.identityMismatch
        }
        try RemoteInventoryValidation.cursor(after)
        var parts = URLComponents(url: connection.endpoint.url(path: "uploads/inventory"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [
            .init(name: "destination_id", value: registration.destination.rawValue),
            .init(name: "registration_id", value: registration.id.rawValue),
            .init(name: "registration_generation", value: String(registration.generation.rawValue)),
            .init(name: "limit", value: "32")
        ]
        if let after { parts.queryItems!.append(.init(name: "cursor", value: after)) }
        guard let result = parts.url else { throw BackendContractError.invalidValue }
        return result
    }
    static func page(_ data: Data, registration: RegistrationIdentity, after: String?) throws -> RemoteInventoryPage {
        let value = try PublicationWire.parse(data).object(keys: ["destination_id", "registration_id", "registration_generation", "request_cursor", "items", "next_cursor"])
        guard case .string(let destination) = value["destination_id"],
              case .string(let id) = value["registration_id"],
              destination.utf8.elementsEqual(registration.destination.rawValue.utf8),
              id.utf8.elementsEqual(registration.id.rawValue.utf8),
              try value["registration_generation"]!.uint(positive: true) == registration.generation.rawValue,
              case .array(let items) = value["items"], items.count <= RemoteInventoryValidation.maximumItems else {
            throw BackendContractError.identityMismatch
        }
        let requestCursor = try cursor(value["request_cursor"]!)
        let nextCursor = try cursor(value["next_cursor"]!)
        guard RemoteInventoryValidation.same(requestCursor, after) else { throw BackendContractError.identityMismatch }
        let page = RemoteInventoryPage(registration: registration, requestCursor: requestCursor,
            originals: try items.map(original), nextCursor: nextCursor)
        try RemoteInventoryValidation.page(page)
        return page
    }
    static func original(_ value: PublicationJSON) throws -> OriginalContent {
        let fields = try value.object(keys: ["capture_id", "content_generation", "sha256", "byte_count"])
        guard case .string(let capture) = fields["capture_id"], case .string(let digest) = fields["sha256"] else {
            throw BackendContractError.invalidValue
        }
        let original = OriginalContent(capture: .init(rawValue: capture),
            generation: .init(rawValue: try fields["content_generation"]!.uint(positive: true)),
            content: try .init(byteCount: fields["byte_count"]!.uint(positive: true), algorithm: "sha256", digest: digest))
        try RemoteInventoryValidation.original(original)
        return original
    }
    private static func cursor(_ value: PublicationJSON) throws -> String? {
        if value == .null { return nil }
        guard case .string(let text) = value else { throw BackendContractError.invalidValue }
        try RemoteInventoryValidation.cursor(text)
        return text
    }
}
