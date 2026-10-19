@testable import FrameRelay
import Foundation

/// Explicit wire schema. Swift enum Codable layouts never cross this boundary.
nonisolated enum PublicationWire {
    static let version = "fr-publication-v1"
    static let maximumBytes = 262_144
    typealias Value = PublicationJSON
    static func text(_ value: String) throws -> Value {
        guard !value.isEmpty, value.utf8.count <= 1024, !value.contains("\0") else { throw BackendContractError.invalidValue }
        return .string(value)
    }
    static func number(_ value: UInt64) -> Value { .string(String(value)) }
    static func registration(_ value: RegistrationIdentity) throws -> Value {
        guard value.generation.rawValue > 0 else { throw BackendContractError.invalidValue }
        return .object(["destination_id": try text(value.destination.rawValue), "registration_id": try text(value.id.rawValue), "generation": number(value.generation.rawValue)])
    }
    static func content(_ value: ContentIdentity) throws -> Value {
        guard value.byteCount > 0, value.algorithm == "sha256", value.digest.utf8.count == 64,
              value.digest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw BackendContractError.invalidValue }
        return .object(["algorithm": .string(value.algorithm), "digest": .string(value.digest), "byte_count": number(value.byteCount)])
    }
    static func original(_ value: OriginalContent) throws -> Value {
        .object(["capture_id": try text(value.capture.rawValue), "content_generation": number(value.generation.rawValue), "content": try content(value.content)])
    }
    static func rendition(_ value: RenditionIdentity) throws -> Value {
        guard RegistrationWireIdentity.isCanonical(value.rendition.rawValue), value.publicationGeneration.rawValue > 0 else { throw BackendContractError.invalidValue }
        return .object(["original": try original(value.original), "input_log_identity": try text(value.inputLogIdentity),
            "transform_asset_identity": try text(value.transformAssetIdentity), "transform_asset_version": try text(value.transformAssetVersion),
            "output_configuration_identity": try text(value.outputConfigurationIdentity), "conversion_version": try text(value.conversionVersion),
            "rendition_id": try text(value.rendition.rawValue), "delivery_content": try content(value.deliveryContent),
            "publication_generation": number(value.publicationGeneration.rawValue)])
    }
    static func localCommit(_ value: BackendCommitReceipt) throws -> Value {
        guard value.matches(value.key, revision: value.previousRevision) else { throw BackendContractError.notCommitted }
        return .object(["previous_revision": number(value.previousRevision), "committed_revision": number(value.committedRevision)])
    }
    static func distribution(_ value: DistributionReceipt) throws -> Value {
        guard value.isCommitted else { throw BackendContractError.notCommitted }
        return .object(["operation_id": try text(value.operation.rawValue), "rendition": try rendition(value.rendition),
            "registration": try registration(value.registration), "previous_revision": number(value.commit.previousRevision), "committed_revision": number(value.commit.committedRevision)])
    }
    static func invalidation(_ value: InvalidationRecord) throws -> Value {
        guard value.generation.rawValue > 0 else { throw BackendContractError.invalidValue }
        return .object(["invalidation_id": try text(value.id.rawValue), "rendition": try rendition(value.rendition),
            "registration": try registration(value.registration), "invalidation_generation": number(value.generation.rawValue)])
    }
    static func request(_ fields: [String: Value]) -> Value { .object(fields.merging(["schema_version": .string(version)]) { _, next in next }) }
    static func manifestRequest(_ original: OriginalContent, _ reg: RegistrationIdentity) throws -> Value {
        request(["original": try self.original(original), "registration": try registration(reg)])
    }
    static func distributionRequest(_ value: PublicationDistributionRequest) throws -> Value {
        guard value.gate.target == .rendition(value.rendition), value.gate.registration.generation.rawValue > 0 else { throw BackendContractError.identityMismatch }
        switch value.purpose {
        case .source: guard value.kind == .full, value.range == nil, value.source == nil else { throw BackendContractError.invalidValue }
        case .read:
            guard value.source != nil, (value.kind == .full) == (value.range == nil) else { throw BackendContractError.invalidValue }
        }
        let range: Value
        if let bounds = value.range {
            guard bounds.lowerBound < bounds.upperBound, bounds.upperBound <= value.rendition.deliveryContent.byteCount else { throw BackendContractError.invalidValue }
            range = .object(["lower_bound": number(bounds.lowerBound), "upper_bound": number(bounds.upperBound)])
        } else { range = .null }
        return request(["operation_id": try text(value.operation.rawValue), "registration": try registration(value.gate.registration), "rendition": try rendition(value.rendition),
            "gate": .object(["operation_id": try text(value.gate.operation.rawValue), "attempt_id": try text(value.gate.attempt.rawValue), "access_generation": number(value.gate.generation)]),
            "purpose": .string(value.purpose.rawValue), "kind": .string(value.kind.rawValue), "range": range, "source_operation_id": try value.source.map { try text($0.rawValue) } ?? .null])
    }
    static func syncRequest(_ entry: BackendSyncEntry) throws -> Value {
        switch entry {
        case .confirmation(let record):
            guard record.intent.playback.observation == .played, record.commit.key == record.intent.key else { throw BackendContractError.identityMismatch }
            let token = record.intent.playback
            return request(["registration": try registration(entry.registration), "confirmation": .object([
                "operation_id": try text(record.intent.operation.rawValue), "playback_session_id": try text(token.session.rawValue),
                "distribution": try distribution(token.distribution), "invalidation_generation": number(token.invalidationGeneration.rawValue),
                "observation": .string("played"), "local_commit": try localCommit(record.commit)])])
        case .invalidation(let ack):
            guard ack.isCommitted else { throw BackendContractError.notCommitted }
            return request(["registration": try registration(entry.registration), "acknowledgement": .object([
                "invalidation": try invalidation(ack.record), "local_commit": try localCommit(ack.commit)])])
        }
    }
    static func lookupRequest(registration reg: RegistrationIdentity, kind: String, operation: String) throws -> Value {
        request(["registration": try registration(reg), "kind": .string(kind), "operation_id": try text(operation)])
    }
    static func lookupRequest(_ entry: BackendSyncEntry) throws -> Value {
        switch entry {
        case .confirmation(let record): return try lookupRequest(registration: entry.registration, kind: "confirmation", operation: record.intent.operation.rawValue)
        case .invalidation(let ack): return try lookupRequest(registration: entry.registration, kind: "acknowledgement", operation: ack.record.id.rawValue)
        }
    }
    static func envelope(_ data: Data, request expected: Value) throws -> Value {
        let object = try parse(data).object(keys: ["schema_version", "request", "result"])
        guard object["schema_version"] == .string(version), object["request"] == expected else { throw BackendContractError.identityMismatch }
        return object["result"]!
    }
    static func lookupResult(_ data: Data, lookup: Value, original: Value) throws -> Value {
        let object = try envelope(data, request: lookup).object(keys: ["original_request", "original_result"])
        guard object["original_request"] == original else { throw BackendContractError.identityMismatch }
        return object["original_result"]!
    }
    static func decodeManifest(_ value: Value, original expected: OriginalContent) throws -> PublicationManifest {
        let object = try value.object(keys: ["current", "revision", "invalidation_generation", "replacement_pending", "media_type"])
        let current = object["current"] == .null ? nil : try decodeRendition(object["current"]!)
        guard current == nil || current?.original == expected else { throw BackendContractError.identityMismatch }
        let type = object["media_type"] == .null ? nil : try mediaType(object["media_type"]!)
        guard (current == nil) == (type == nil) else { throw BackendContractError.identityMismatch }
        return .init(current: current, revision: try object["revision"]!.uint(), invalidationGeneration: .init(rawValue: try object["invalidation_generation"]!.uint()),
                     replacementPending: try object["replacement_pending"]!.bool(), mediaType: type)
    }
    static func decodeDistribution(_ value: Value, expected: PublicationDistributionRequest) throws -> PublicationDistribution {
        let object = try value.object(keys: ["receipt", "media_type"])
        let receipt = try object["receipt"]!.object(keys: ["operation_id", "rendition", "registration", "previous_revision", "committed_revision"])
        guard receipt["operation_id"] == (try text(expected.operation.rawValue)), receipt["rendition"] == (try rendition(expected.rendition)),
              receipt["registration"] == (try registration(expected.gate.registration)) else { throw BackendContractError.identityMismatch }
        let proof = DistributionReceipt(operation: expected.operation, rendition: expected.rendition, registration: expected.gate.registration,
            commit: .init(key: .distribution(expected.operation, expected.rendition, expected.gate.registration),
                previousRevision: try receipt["previous_revision"]!.uint(), committedRevision: try receipt["committed_revision"]!.uint()))
        guard proof.isCommitted else { throw BackendContractError.notCommitted }
        return .init(receipt: proof, mediaType: try mediaType(object["media_type"]!))
    }
    static func decodeSync(_ value: Value, entry: BackendSyncEntry) throws -> BackendSyncResponse {
        switch entry {
        case .confirmation(let record):
            let object = try value.object(keys: ["operation_id", "accepted"])
            guard object["operation_id"] == (try text(record.intent.operation.rawValue)), object["accepted"] == .boolean(true) else { throw BackendContractError.identityMismatch }
            return .confirmation(record.intent.operation)
        case .invalidation(let ack):
            let object = try value.object(keys: ["invalidation_id", "accepted"])
            guard object["invalidation_id"] == (try text(ack.record.id.rawValue)), object["accepted"] == .boolean(true) else { throw BackendContractError.identityMismatch }
            return .invalidation(ack.record.id)
        }
    }
    static func decodeInvalidation(_ value: Value, registration expected: RegistrationIdentity) throws -> InvalidationRecord {
        let object = try value.object(keys: ["invalidation_id", "rendition", "registration", "invalidation_generation"])
        guard object["registration"] == (try registration(expected)) else { throw BackendContractError.identityMismatch }
        return .init(id: .init(rawValue: try object["invalidation_id"]!.opaque()), rendition: try decodeRendition(object["rendition"]!), registration: expected,
                     generation: .init(rawValue: try object["invalidation_generation"]!.uint(positive: true)))
    }
    static func decodeContent(_ value: Value) throws -> ContentIdentity {
        let object = try value.object(keys: ["algorithm", "digest", "byte_count"])
        let result = try ContentIdentity(byteCount: object["byte_count"]!.uint(positive: true), algorithm: object["algorithm"]!.opaque(), digest: object["digest"]!.opaque())
        _ = try content(result)
        return result
    }
    static func decodeOriginal(_ value: Value) throws -> OriginalContent {
        let object = try value.object(keys: ["capture_id", "content_generation", "content"])
        return .init(capture: .init(rawValue: try object["capture_id"]!.opaque()), generation: .init(rawValue: try object["content_generation"]!.uint()), content: try decodeContent(object["content"]!))
    }
    static func decodeRendition(_ value: Value) throws -> RenditionIdentity {
        let o = try value.object(keys: ["original", "input_log_identity", "transform_asset_identity", "transform_asset_version", "output_configuration_identity", "conversion_version", "rendition_id", "delivery_content", "publication_generation"])
        let id = try o["rendition_id"]!.opaque()
        guard RegistrationWireIdentity.isCanonical(id) else { throw BackendContractError.invalidValue }
        return .init(original: try decodeOriginal(o["original"]!), inputLogIdentity: try o["input_log_identity"]!.opaque(),
            transformAssetIdentity: try o["transform_asset_identity"]!.opaque(), transformAssetVersion: try o["transform_asset_version"]!.opaque(),
            outputConfigurationIdentity: try o["output_configuration_identity"]!.opaque(), conversionVersion: try o["conversion_version"]!.opaque(),
            rendition: .init(rawValue: id), deliveryContent: try decodeContent(o["delivery_content"]!), publicationGeneration: .init(rawValue: try o["publication_generation"]!.uint(positive: true)))
    }
    static func mediaType(_ value: Value) throws -> String {
        guard case .string(let type) = value, ["video/mp4", "video/quicktime"].contains(type) else { throw BackendContractError.unsupportedVersion }
        return type
    }
    static func isAbsent(_ data: Data) -> Bool {
        guard let object = try? parse(data).object(keys: ["schema_version", "code", "retryable"]) else { return false }
        return object["schema_version"] == .string(version) && object["code"] == .string("publication_operation_not_executed") && object["retryable"] == .boolean(false)
    }
    static func parse(_ data: Data) throws -> Value {
        guard !data.isEmpty, data.count <= maximumBytes, String(data: data, encoding: .utf8) != nil else { throw BackendContractError.unsupportedVersion }
        var parser = PublicationJSONParser(bytes: Array(data))
        let result = try parser.value(depth: 0)
        parser.space()
        guard parser.index == parser.bytes.count else { throw BackendContractError.unsupportedVersion }
        return result
    }
    static func body(_ value: Value) throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: value.foundation, options: [.sortedKeys, .fragmentsAllowed])
        guard data.count <= maximumBytes else { throw BackendContractError.invalidValue }
        return data
    }
    static func headerID(_ value: String) throws -> String {
        _ = try text(value)
        return Data(value.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

nonisolated indirect enum PublicationJSON: Equatable, Sendable {
    case object([String: PublicationJSON]), array([PublicationJSON]), string(String), boolean(Bool), null
    func object(keys: Set<String>) throws -> [String: Self] {
        guard case .object(let value) = self, Set(value.keys) == keys else { throw BackendContractError.unsupportedVersion }
        return value
    }
    func opaque() throws -> String {
        guard case .string(let value) = self else { throw BackendContractError.invalidValue }
        _ = try PublicationWire.text(value); return value
    }
    func uint(positive: Bool = false) throws -> UInt64 {
        guard case .string(let text) = self, !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }),
              text == "0" || text.first != "0", let value = UInt64(text), !positive || value > 0 else { throw BackendContractError.invalidValue }
        return value
    }
    func bool() throws -> Bool {
        guard case .boolean(let value) = self else { throw BackendContractError.invalidValue }; return value
    }
    var foundation: Any {
        switch self {
        case .object(let value): value.mapValues(\.foundation)
        case .array(let value): value.map(\.foundation)
        case .string(let value): value
        case .boolean(let value): value
        case .null: NSNull()
        }
    }
}

/// Detect duplicates before Foundation can collapse keys. The schema has no
/// JSON numeric values: counts are canonical decimal strings and bools are bools.
nonisolated private struct PublicationJSONParser {
    let bytes: [UInt8]
    var index = 0
    mutating func space() { while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
    mutating func take(_ byte: UInt8) throws {
        space(); guard index < bytes.count, bytes[index] == byte else { throw BackendContractError.unsupportedVersion }; index += 1
    }
    mutating func value(depth: Int) throws -> PublicationJSON {
        space(); guard depth <= 32, index < bytes.count else { throw BackendContractError.unsupportedVersion }
        switch bytes[index] {
        case 34: return .string(try string())
        case 123:
            index += 1; space(); var object: [String: PublicationJSON] = [:]
            if index < bytes.count, bytes[index] == 125 { index += 1; return .object(object) }
            while true {
                let key = try string(); guard object[key] == nil else { throw BackendContractError.unsupportedVersion }
                try take(58); object[key] = try value(depth: depth + 1); space()
                if index < bytes.count, bytes[index] == 125 { index += 1; return .object(object) }
                try take(44)
            }
        case 91:
            index += 1; space(); var array: [PublicationJSON] = []
            if index < bytes.count, bytes[index] == 93 { index += 1; return .array(array) }
            while true {
                array.append(try value(depth: depth + 1)); space()
                if index < bytes.count, bytes[index] == 93 { index += 1; return .array(array) }
                try take(44)
            }
        case 116: try literal("true"); return .boolean(true)
        case 102: try literal("false"); return .boolean(false)
        case 110: try literal("null"); return .null
        default: throw BackendContractError.unsupportedVersion
        }
    }
    mutating func literal(_ text: String) throws {
        let literal = Array(text.utf8)
        guard bytes.count - index >= literal.count, Array(bytes[index..<(index + literal.count)]) == literal else { throw BackendContractError.unsupportedVersion }
        index += literal.count
    }
    mutating func string() throws -> String {
        space(); let start = index; try take(34)
        while index < bytes.count {
            let byte = bytes[index]; index += 1
            if byte == 34 { return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) }
            if byte == 92 { guard index < bytes.count else { break }; index += 1 }
            else if byte < 32 { throw BackendContractError.unsupportedVersion }
        }
        throw BackendContractError.unsupportedVersion
    }
}
