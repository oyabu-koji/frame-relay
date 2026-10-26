import Foundation
import Testing
@testable import FrameRelay

struct RegistrationWireTests {
    private let destination = DestinationIdentity(rawValue: "9a3ba104-985f-4a2d-875d-d458258b9b6b")
    private var intent: RegistrationIntent {
        .init(operation: .init(rawValue: "995a3657-30a8-44b4-84c1-fc3cbe7a6041"), destination: destination)
    }
    private var receipt: [String: Any] {
        ["destination_id": destination.rawValue, "operation_id": intent.operation.rawValue,
         "registration_id": "21088ea6-c2bc-4c21-8329-63d05bdfefcb", "generation": "9223372036854775807",
         "created_at": "2026-10-06T19:43:31.123456+00:00"]
    }
    @Test func productEndpointRejectsAmbiguousOrUnprotectedOrigins() throws {
        for value in ["http://127.0.0.1:8989", "http://example.com", "https://example.com/", "https://user:secret@example.com",
                      "https://example.com?token=secret", "https://example.com#fragment", "https://example.com/a",
                      "https://example.com:0", "https://example.com:65536", "https://example.com\\evil", "https://example.com ",
                      "https://%65xample.com"] {
            #expect(throws: (any Error).self) { try RegistrationEndpoint(httpsOrigin: value) }
        }
        let endpoint = try RegistrationEndpoint(httpsOrigin: "https://example.com:8443")
        #expect(endpoint.url(path: "registrations").path == "/frame-relay/v1/registrations")
    }
    @Test func exactReceiptPreserves63BitGenerationAndTarget() throws {
        let value = try RegistrationWire.receipt(JSONSerialization.data(withJSONObject: receipt), intent: intent)
        #expect(value.intent == intent)
        #expect(value.registration.generation.rawValue == UInt64(Int64.max))
    }
    @Test func rejectsChangedIdentityUnknownFieldsAndNonCanonicalGenerations() throws {
        let changes: [(String, Any)] = [("destination_id", UUID().uuidString.lowercased()),
            ("operation_id", intent.operation.rawValue.uppercased()), ("registration_id", "not-an-id"),
            ("generation", 1), ("generation", true), ("generation", "01"), ("generation", "0"),
            ("generation", "9223372036854775808"), ("generation", "+1"), ("extra", "unexpected")]
        for (key, value) in changes {
            var changed = receipt; changed[key] = value
            let data = try JSONSerialization.data(withJSONObject: changed)
            #expect(throws: (any Error).self) { try RegistrationWire.receipt(data, intent: intent) }
        }
    }
    @Test func timestampsMustBeRealCanonicalUTCInstants() throws {
        for value in ["2026-02-29T00:00:00.123456+00:00", "2026-10-06T24:00:00.123456+00:00",
                      "2026-10-06T19:43:60.123456+00:00", "2026-10-06T19:43:31.123Z", "0000-01-01T00:00:00.000000+00:00",
                      "2026-10-06T19:43:31.123456+00:00\n"] {
            var changed = receipt; changed["created_at"] = value
            let data = try JSONSerialization.data(withJSONObject: changed)
            #expect(throws: (any Error).self) { try RegistrationWire.receipt(data, intent: intent) }
        }
    }
    @Test func onlyExactAuthenticatedAbsenceCanAuthorizeSameIntentRetry() throws {
        let absent: [String: Any] = ["code": "registration_not_executed", "destination_id": destination.rawValue,
                                   "operation_id": intent.operation.rawValue, "retryable": false]
        #expect(RegistrationWire.isKnownAbsent(try JSONSerialization.data(withJSONObject: absent), intent: intent))
        for (key, value) in [("retryable", 0 as Any), ("code", "not_found" as Any),
                             ("operation_id", "different" as Any), ("extra", "field" as Any)] {
            var changed = absent; changed[key] = value
            #expect(!RegistrationWire.isKnownAbsent(try JSONSerialization.data(withJSONObject: changed), intent: intent))
        }
    }
    @Test func capabilityDiscoveryDoesNotAdvertiseUnimplementedMediaOperations() throws {
        let connection = try RegistrationConnection(endpoint: .init(httpsOrigin: "https://example.com"), destination: destination)
        let data = try JSONSerialization.data(withJSONObject: ["protocol_version": 1, "destination_id": destination.rawValue,
                                                             "capabilities": ["registration-intent-v1"]])
        let value = try RegistrationWire.capabilities(data, connection: connection)
        #expect(value.operations == [.destinationIdentity, .registration, .registrationLookup])
        let unknown = try JSONSerialization.data(withJSONObject: ["protocol_version": 1, "destination_id": destination.rawValue,
                                                                "capabilities": ["registration-intent-v1", "media"]])
        #expect(throws: (any Error).self) { try RegistrationWire.capabilities(unknown, connection: connection) }
        let floatVersion = Data("{\"protocol_version\":1.0,\"destination_id\":\"\(destination.rawValue)\",\"capabilities\":[\"registration-intent-v1\"]}".utf8)
        #expect(throws: (any Error).self) { try RegistrationWire.capabilities(floatVersion, connection: connection) }
    }
    @Test func descriptionsRedactOriginAndCredentials() throws {
        let endpoint = try RegistrationEndpoint(httpsOrigin: "https://private.invalid")
        let authorization = RegistrationAuthorization(bearer: "private-token", secret: "private-secret")
        #expect(!String(reflecting: endpoint).contains("private"))
        #expect(!String(reflecting: authorization).contains("private"))
    }
}
