import Foundation

/// A bounded observation of server storage metadata. It is not a local binding,
/// current-file observation, verification evidence, publication or confirmation.
nonisolated struct RemoteInventoryPage: Sendable, Codable, Equatable {
    let registration: RegistrationIdentity
    let requestCursor: String?
    let originals: [OriginalContent]
    let nextCursor: String?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.registration == rhs.registration
            && RemoteInventoryValidation.same(lhs.requestCursor, rhs.requestCursor)
            && lhs.originals.count == rhs.originals.count
            && zip(lhs.originals, rhs.originals).allSatisfy { RemoteInventoryValidation.same($0.0, $0.1) }
            && RemoteInventoryValidation.same(lhs.nextCursor, rhs.nextCursor)
    }
}

nonisolated struct RemoteInventoryObservation: Equatable, Sendable, Codable {
    let command: MediaOperationID
    let storeIdentity: RegistrationStoreIdentity
    let registration: RegistrationIdentity
    let requestCursor: String?
    let page: RemoteInventoryPage

    var key: BackendCommitKey { .remoteInventory(command, registration) }

    func validate() throws {
        guard RemoteInventoryValidation.canonicalID(command.rawValue) else { throw BackendContractError.invalidValue }
        try RemoteInventoryValidation.page(page)
        guard page.registration == registration,
              RemoteInventoryValidation.same(page.requestCursor, requestCursor) else {
            throw BackendContractError.identityMismatch
        }
    }
}

nonisolated struct StoredRemoteInventoryPage: Equatable, Sendable {
    let observation: RemoteInventoryObservation
    let commit: BackendCommitReceipt
    var isCommitted: Bool { commit.matches(observation.key, revision: commit.previousRevision) }
}

/// Byte identities preserve opaque capture IDs, including canonical Unicode aliases.
nonisolated struct RemoteInventoryOriginalID: Hashable, Sendable {
    let destination: Data
    let capture: Data
    let generation: UInt64
    let algorithm: Data
    let digest: Data
    let byteCount: UInt64

    init(destination: DestinationIdentity, original: OriginalContent) {
        self.destination = Data(destination.rawValue.utf8)
        capture = Data(original.capture.rawValue.utf8)
        generation = original.generation.rawValue
        algorithm = Data(original.content.algorithm.utf8)
        digest = Data(original.content.digest.utf8)
        byteCount = original.content.byteCount
    }
    var accessibilityToken: String {
        destination.base64EncodedString() + "." + capture.base64EncodedString()
            + ".\(generation)." + algorithm.base64EncodedString() + "." + digest.base64EncodedString() + ".\(byteCount)"
    }
}

nonisolated enum RemoteInventoryValidation {
    static let maximumItems = 32
    static let maximumCaptureBytes = 2048
    static let maximumCursorBytes = 640
    static let maximumResponseBytes = 262_144

    static func canonicalID(_ value: String) -> Bool {
        value.utf8.count == 36 && UUID(uuidString: value)?.uuidString.lowercased() == value
    }
    static func cursor(_ value: String?) throws {
        guard let value else { return }
        guard !value.isEmpty, value.utf8.count <= maximumCursorBytes,
              value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0)
                  || (97...122).contains($0) || $0 == 45 || $0 == 95 }) else {
            throw BackendContractError.invalidValue
        }
        let base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padded = base64 + String(repeating: "=", count: (4 - base64.utf8.count % 4) % 4)
        guard let decoded = Data(base64Encoded: padded), !decoded.isEmpty,
              decoded.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") == value else {
            throw BackendContractError.invalidValue
        }
    }
    static func original(_ value: OriginalContent) throws {
        guard !value.capture.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.capture.rawValue.utf8.count <= maximumCaptureBytes,
              value.generation.rawValue > 0, value.content.byteCount > 0,
              value.content.algorithm == "sha256", value.content.digest.utf8.count == 64,
              value.content.digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw BackendContractError.invalidValue
        }
    }
    static func page(_ value: RemoteInventoryPage) throws {
        let registration = value.registration
        guard canonicalID(registration.destination.rawValue), canonicalID(registration.id.rawValue),
              registration.generation.rawValue > 0, registration.generation.rawValue <= UInt64(Int64.max),
              value.originals.count <= maximumItems else { throw BackendContractError.invalidValue }
        try cursor(value.requestCursor); try cursor(value.nextCursor)
        if let next = value.nextCursor {
            guard !value.originals.isEmpty, !same(next, value.requestCursor) else { throw BackendContractError.invalidValue }
        }
        try value.originals.forEach(original)
    }
    static func same(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): true
        case (.some(let a), .some(let b)): a.utf8.elementsEqual(b.utf8)
        default: false
        }
    }
    static func same(_ lhs: OriginalContent, _ rhs: OriginalContent) -> Bool {
        lhs.capture.rawValue.utf8.elementsEqual(rhs.capture.rawValue.utf8)
            && lhs.generation == rhs.generation && lhs.content.byteCount == rhs.content.byteCount
            && lhs.content.algorithm.utf8.elementsEqual(rhs.content.algorithm.utf8)
            && lhs.content.digest.utf8.elementsEqual(rhs.content.digest.utf8)
    }
}
