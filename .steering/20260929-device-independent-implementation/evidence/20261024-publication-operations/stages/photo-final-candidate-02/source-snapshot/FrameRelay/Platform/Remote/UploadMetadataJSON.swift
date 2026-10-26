import Foundation

/// Separate from PublicationJSON: only this schema admits numeric tokens, and
/// the wire decoder permits them solely as canonical unsigned chunk indexes.
nonisolated indirect enum UploadMetadataJSON: Equatable, Sendable {
    case object([String: Self]), array([Self]), string(String), number(String), boolean(Bool), null

    static func parse(_ data: Data) throws -> Self {
        guard !data.isEmpty, data.count <= 262_144, String(data: data, encoding: .utf8) != nil else {
            throw BackendContractError.unsupportedVersion
        }
        var parser = UploadMetadataJSONParser(bytes: Array(data))
        let result = try parser.value(depth: 0)
        parser.space()
        guard parser.index == parser.bytes.count else { throw BackendContractError.unsupportedVersion }
        return result
    }
    func object(_ keys: Set<String>) throws -> [String: Self] {
        guard case .object(let fields) = self, Set(fields.keys) == keys else { throw BackendContractError.unsupportedVersion }
        return fields
    }
    func text() throws -> String {
        guard case .string(let text) = self, !text.isEmpty, text.utf8.count <= 4096,
              !text.contains("\0") else { throw BackendContractError.invalidValue }
        return text
    }
    func uint(positive: Bool = false, numericToken: Bool = false) throws -> UInt64 {
        let text: String
        switch self {
        case .string(let value) where !numericToken: text = value
        case .number(let value) where numericToken: text = value
        default: throw BackendContractError.invalidValue
        }
        guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }),
              text == "0" || text.first != "0", let value = UInt64(text), !positive || value > 0 else {
            throw BackendContractError.invalidValue
        }
        return value
    }
    func bool() throws -> Bool {
        guard case .boolean(let value) = self else { throw BackendContractError.invalidValue }; return value
    }
}

nonisolated private struct UploadMetadataJSONParser {
    let bytes: [UInt8]
    var index = 0
    mutating func space() { while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 } }
    mutating func take(_ byte: UInt8) throws {
        space(); guard index < bytes.count, bytes[index] == byte else { throw BackendContractError.unsupportedVersion }; index += 1
    }
    mutating func value(depth: Int) throws -> UploadMetadataJSON {
        space(); guard depth <= 32, index < bytes.count else { throw BackendContractError.unsupportedVersion }
        switch bytes[index] {
        case 34: return .string(try string())
        case 123:
            index += 1; space(); var fields: [String: UploadMetadataJSON] = [:]
            if index < bytes.count, bytes[index] == 125 { index += 1; return .object(fields) }
            while true {
                let key = try string()
                // Also refuses canonically equivalent duplicate keys before
                // Swift Dictionary could collapse their different UTF-8 bytes.
                guard fields[key] == nil else { throw BackendContractError.unsupportedVersion }
                try take(58); fields[key] = try value(depth: depth + 1); space()
                if index < bytes.count, bytes[index] == 125 { index += 1; return .object(fields) }
                try take(44)
            }
        case 91:
            index += 1; space(); var items: [UploadMetadataJSON] = []
            if index < bytes.count, bytes[index] == 93 { index += 1; return .array(items) }
            while true {
                items.append(try value(depth: depth + 1)); space()
                if index < bytes.count, bytes[index] == 93 { index += 1; return .array(items) }
                try take(44)
            }
        case 116: try literal("true"); return .boolean(true)
        case 102: try literal("false"); return .boolean(false)
        case 110: try literal("null"); return .null
        case 45, 48...57:
            let start = index
            while index < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) { index += 1 }
            let token = String(decoding: bytes[start..<index], as: UTF8.self)
            guard token.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil else {
                throw BackendContractError.unsupportedVersion
            }
            return .number(token)
        default: throw BackendContractError.unsupportedVersion
        }
    }
    mutating func literal(_ value: String) throws {
        let token = Array(value.utf8)
        guard bytes.count - index >= token.count, Array(bytes[index..<(index + token.count)]) == token else {
            throw BackendContractError.unsupportedVersion
        }
        index += token.count
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
