import Foundation
import Security
import Testing
@testable import FrameRelay

nonisolated struct RegistrationTestKeychain {
    let service = "FrameRelay.registration.tests." + UUID().uuidString.lowercased()
    let connection: RegistrationConnection
    init(endpoint: RegistrationEndpoint? = nil, destination: String = "9a3ba104-985f-4a2d-875d-d458258b9b6b") throws {
        connection = try .init(endpoint: endpoint ?? .init(httpsOrigin: "https://registration.invalid"),
                               destination: .init(rawValue: destination))
    }
    func vault() throws -> KeychainRegistrationVault {
        #if DEBUG && targetEnvironment(simulator)
        if connection.endpoint.origin.scheme == "http" {
            return try .init(isolatedTestService: service, probeEndpoint: connection.endpoint)
        }
        #endif
        return .init(service: service)
    }
    func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false,
         kSecUseDataProtectionKeychain as String: true]
    }
    /// Exact UUID namespace and just the two accounts this fixture can create.
    /// No product credentials, wildcard deletes or access-group changes.
    func cleanup() {
        precondition(service.hasPrefix("FrameRelay.registration.tests."))
        for account in ["connection", "initial." + connection.destination.rawValue] {
            let status = SecItemDelete(query(account) as CFDictionary)
            #expect(status == errSecSuccess || status == errSecItemNotFound)
        }
    }
}

actor RegistrationTestRemote: RegistrationRemotePort {
    var receipt: RegistrationServerReceipt?
    var hideNextReply = false
    var lookupResult: BackendOutcome<RegistrationServerReceipt>?
    var mismatchReceipt = false
    private(set) var posts = 0
    private(set) var lookups = 0
    private(set) var discoveries = 0
    func setHideReply() { hideNextReply = true }
    func setLookup(_ result: BackendOutcome<RegistrationServerReceipt>) { lookupResult = result }
    func setMismatch() { mismatchReceipt = true }
    func checkConnection(_ connection: RegistrationConnection, bearer: String) -> BackendOutcome<BackendCapabilities> {
        discoveries += 1
        return .succeeded(.init(destination: connection.destination, wireVersion: "1",
                                 operations: [.destinationIdentity, .registration, .registrationLookup]))
    }
    func discover(_ connection: RegistrationConnection) -> BackendOutcome<BackendCapabilities> {
        checkConnection(connection, bearer: "test")
    }
    func lookup(_ intent: RegistrationIntent, at connection: RegistrationConnection) -> BackendOutcome<RegistrationServerReceipt> {
        lookups += 1
        if let lookupResult { return lookupResult }
        return receipt.map { .succeeded($0) } ?? .notExecuted
    }
    func register(_ command: RegistrationCommand, at connection: RegistrationConnection) -> BackendOutcome<RegistrationServerReceipt> {
        guard command.isCommitted else { return .failed(.rejected) }
        posts += 1
        let received = RegistrationServerReceipt(intent: command.intent, registration: .init(destination: command.intent.destination,
            id: .init(rawValue: "21088ea6-c2bc-4c21-8329-63d05bdfefcb"), generation: .init(rawValue: 1)))
        receipt = received
        if hideNextReply { hideNextReply = false; return .unknown }
        if mismatchReceipt {
            return .succeeded(.init(intent: .init(operation: .init(rawValue: UUID().uuidString.lowercased()),
                destination: command.intent.destination), registration: received.registration))
        }
        return .succeeded(received)
    }
}

nonisolated func registrationIsCommitted(_ state: RegistrationState) -> Bool {
    if case .registered(_, let value) = state { return value.isCommitted }
    return false
}

nonisolated func registrationSnapshot(_ store: any MediaOperationStorePort) async throws -> BackendStoreSnapshot {
    guard case .loaded(let value) = await store.load() else { throw BackendContractError.unavailable }
    return value
}
