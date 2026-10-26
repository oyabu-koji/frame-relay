import Foundation
import CoreFoundation

nonisolated enum RegistrationWire {
    static let maximumResponseBytes = 16_384

    static func capabilities(_ data: Data, connection: RegistrationConnection) throws -> BackendCapabilities {
        let object = try object(data, keys: ["protocol_version", "destination_id", "capabilities"])
        guard let version = object["protocol_version"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(),
              ["c", "s", "i", "l", "q"].contains(String(cString: version.objCType)), version == 1,
              object["destination_id"] as? String == connection.destination.rawValue,
              let capabilities = object["capabilities"] as? [String], capabilities == ["registration-intent-v1"] else {
            throw BackendContractError.unsupportedVersion
        }
        return .init(destination: connection.destination, wireVersion: "1",
                     operations: [.destinationIdentity, .registration, .registrationLookup])
    }

    static func receipt(_ data: Data, intent: RegistrationIntent) throws -> RegistrationServerReceipt {
        let object = try object(data, keys: ["destination_id", "operation_id", "registration_id", "generation", "created_at"])
        guard object["destination_id"] as? String == intent.destination.rawValue,
              object["operation_id"] as? String == intent.operation.rawValue,
              RegistrationWireIdentity.isCanonical(intent.destination.rawValue),
              RegistrationWireIdentity.isCanonical(intent.operation.rawValue),
              let id = object["registration_id"] as? String, RegistrationWireIdentity.isCanonical(id),
              let generation = object["generation"] as? String,
              generation.range(of: "^[1-9][0-9]{0,18}$", options: .regularExpression) != nil,
              let number = UInt64(generation), number <= UInt64(Int64.max),
              let timestamp = object["created_at"] as? String, validTimestamp(timestamp) else {
            throw BackendContractError.identityMismatch
        }
        return .init(intent: intent, registration: .init(destination: intent.destination,
            id: .init(rawValue: id), generation: .init(rawValue: number)))
    }

    static func isKnownAbsent(_ data: Data, intent: RegistrationIntent) -> Bool {
        guard let object = try? object(data, keys: ["code", "destination_id", "operation_id", "retryable"]),
              object["code"] as? String == "registration_not_executed",
              object["destination_id"] as? String == intent.destination.rawValue,
              object["operation_id"] as? String == intent.operation.rawValue,
              let retryable = object["retryable"] as? NSNumber,
              CFGetTypeID(retryable) == CFBooleanGetTypeID(), retryable == false else { return false }
        return true
    }

    static func body(_ intent: RegistrationIntent) throws -> Data {
        guard RegistrationWireIdentity.isCanonical(intent.destination.rawValue),
              RegistrationWireIdentity.isCanonical(intent.operation.rawValue) else { throw BackendContractError.invalidValue }
        return try JSONSerialization.data(withJSONObject: ["destination_id": intent.destination.rawValue,
            "operation_id": intent.operation.rawValue], options: [.sortedKeys])
    }

    private static func object(_ data: Data, keys: Set<String>) throws -> [String: Any] {
        guard !data.isEmpty, data.count <= maximumResponseBytes,
              let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(value.keys) == keys else { throw BackendContractError.unsupportedVersion }
        return value
    }
    private static func validTimestamp(_ value: String) -> Bool {
        guard value.utf8.count == 32,
              value.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{6}\\+00:00$",
                          options: .regularExpression) != nil else { return false }
        let parts = value.prefix(19).split(whereSeparator: { "-T:".contains($0) }).compactMap { Int($0) }
        guard parts.count == 6, parts[0] > 0 else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let expected = DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: parts[3], minute: parts[4], second: parts[5])
        guard let date = calendar.date(from: expected) else { return false }
        let actual = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return [actual.year, actual.month, actual.day, actual.hour, actual.minute, actual.second] == parts.map(Optional.some)
    }
}
