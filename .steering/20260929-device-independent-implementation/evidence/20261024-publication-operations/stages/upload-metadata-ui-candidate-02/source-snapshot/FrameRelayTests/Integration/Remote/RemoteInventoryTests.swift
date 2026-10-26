import Foundation
import Testing
@testable import FrameRelay

@Suite(.serialized) @MainActor struct RemoteInventoryTests {
    @Test func strictWireKeepsOpaqueBytesAndFullUnsignedContentValues() throws {
        let registration = inventoryTestRegistration()
        let opaque = OriginalContent(capture: .init(rawValue: " /e\u{301}\0../ "), generation: .init(rawValue: UInt64.max),
            content: try .init(byteCount: UInt64.max, algorithm: "sha256", digest: String(repeating: "a", count: 64)))
        let data = try inventoryWireData(registration, originals: [opaque], next: inventoryCursor("page"))
        let page = try RemoteInventoryWire.page(data, registration: registration, after: nil)
        #expect(page.originals.count == 1 && RemoteInventoryValidation.same(page.originals[0], opaque))
        #expect(page.originals[0].capture.rawValue.utf8.elementsEqual(opaque.capture.rawValue.utf8))
        let connection = try inventoryConnection(registration.destination)
        let url = try RemoteInventoryWire.url(connection: connection, registration: registration, after: page.nextCursor)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/frame-relay/v1/uploads/inventory")
        #expect(components.queryItems?.first(where: { $0.name == "limit" })?.value == "32")
        #expect(components.queryItems?.first(where: { $0.name == "cursor" })?.value == page.nextCursor)
    }

    @Test(arguments: ["duplicate-key", "identity", "numeric", "leading-zero", "overflow", "capture-large", "items-large", "unknown-field", "bad-cursor", "wrong-echo", "response-large"])
    func malformedOrUnboundWirePageIsRejectedBeforeJournalUse(reason: String) throws {
        let registration = inventoryTestRegistration()
        let normal = try inventoryWireData(registration, originals: [try inventoryOriginal("opaque")])
        var object = try #require(JSONSerialization.jsonObject(with: normal) as? [String: Any])
        var item = try #require((object["items"] as? [[String: Any]])?.first)
        var data: Data
        switch reason {
        case "duplicate-key":
            let text = try #require(String(data: normal, encoding: .utf8))
            data = Data(("{\"items\":[]," + text.dropFirst()).utf8)
        case "identity": object["registration_id"] = UUID().uuidString.lowercased(); data = try JSONSerialization.data(withJSONObject: object)
        case "numeric": item["content_generation"] = 1; object["items"] = [item]; data = try JSONSerialization.data(withJSONObject: object)
        case "leading-zero": item["byte_count"] = "04096"; object["items"] = [item]; data = try JSONSerialization.data(withJSONObject: object)
        case "overflow": item["byte_count"] = "18446744073709551616"; object["items"] = [item]; data = try JSONSerialization.data(withJSONObject: object)
        case "capture-large": item["capture_id"] = String(repeating: "x", count: 2049); object["items"] = [item]; data = try JSONSerialization.data(withJSONObject: object)
        case "items-large": object["items"] = Array(repeating: item, count: 33); data = try JSONSerialization.data(withJSONObject: object)
        case "unknown-field": object["media_url"] = "must-not-be-consumed"; data = try JSONSerialization.data(withJSONObject: object)
        case "bad-cursor": object["next_cursor"] = inventoryCursor("page") + "="; data = try JSONSerialization.data(withJSONObject: object)
        case "wrong-echo": object["request_cursor"] = inventoryCursor("unrequested"); data = try JSONSerialization.data(withJSONObject: object)
        default: data = Data(repeating: 32, count: RemoteInventoryValidation.maximumResponseBytes + 1) + normal
        }
        do { _ = try RemoteInventoryWire.page(data, registration: registration, after: nil); Issue.record("Malformed inventory response accepted") }
        catch { }
    }

    @Test func explicitPageContinuationRejectsCursorCyclesAndRetainsPreviouslySeenItemsOnEmptyPage() async throws {
        try await withStorageRun { run in
            let store = try SQLiteRecordingStore(run: run, mode: .createNew)
            let registration = try await inventoryRegister(store)
            let connection = try inventoryConnection(registration.server.registration.destination)
            let remote = InventoryRemoteFixture()
            let a = try inventoryOriginal("one"), b = try inventoryOriginal("two")
            let first = inventoryCursor("first"), second = inventoryCursor("second")
            remote.pages = [
                .succeeded(.init(registration: registration.server.registration, requestCursor: nil, originals: [a], nextCursor: first)),
                .succeeded(.init(registration: registration.server.registration, requestCursor: first, originals: [a, b], nextCursor: second)),
                .succeeded(.init(registration: registration.server.registration, requestCursor: second, originals: [b], nextCursor: first)),
                .succeeded(.init(registration: registration.server.registration, requestCursor: second, originals: [], nextCursor: nil))
            ]
            let coordinator = RemoteInventoryCoordinator(store: store, remoteFactory: { _, _, _ in remote })
            #expect(remote.afters.isEmpty)
            #expect(await coordinator.discover(connection: connection, registration: registration) == .init(phase: .recorded, receivedCount: 1, hasMore: true))
            #expect(remote.afters.count == 1)
            #expect(await coordinator.discover(connection: connection, registration: registration).receivedCount == 2)
            let beforeCycle = try await mediaSnapshot(store)
            #expect(await coordinator.discover(connection: connection, registration: registration).phase == .unavailable)
            #expect(try await mediaSnapshot(store) == beforeCycle)
            #expect(await coordinator.discover(connection: connection, registration: registration) == .init(phase: .recorded, receivedCount: 0, hasMore: false))
            #expect(remote.afters == [nil, first, second, second])
            let reader = LibraryStoreReader(store: store, files: StatusSynchronizationAbsentFiles())
            guard case .loaded(let library) = await reader.loadLibrary() else { throw BackendContractError.unavailable }
            #expect(library.remoteItems.count == 2 && library.items.isEmpty)
            let reopened = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let nextRemote = InventoryRemoteFixture()
            nextRemote.pages = [.succeeded(.init(registration: registration.server.registration, requestCursor: nil, originals: [], nextCursor: nil))]
            let next = RemoteInventoryCoordinator(store: reopened, remoteFactory: { _, _, _ in nextRemote })
            _ = await next.discover(connection: connection, registration: registration)
            #expect(nextRemote.afters.count == 1 && nextRemote.afters[0] == nil)
            #expect(try await mediaSnapshot(reopened).remoteInventory.count == 4)
        }
    }

    @Test func unknownCommitKeepsItsExactMutationAndStopsNetworkUntilLookupConfirmsIt() async throws {
        try await withStorageRun { run in
            let base = try SQLiteRecordingStore(run: run, mode: .createNew)
            let registration = try await inventoryRegister(base)
            let store = InventoryFaultStore(base: base)
            store.hideReply = true; store.hideLookup = true
            let remote = InventoryRemoteFixture()
            let cursor = inventoryCursor("next")
            remote.pages = [
                .succeeded(.init(registration: registration.server.registration, requestCursor: nil, originals: [try inventoryOriginal("lost-reply")], nextCursor: cursor)),
                .succeeded(.init(registration: registration.server.registration, requestCursor: cursor, originals: [], nextCursor: nil))
            ]
            let coordinator = RemoteInventoryCoordinator(store: store, remoteFactory: { _, _, _ in remote })
            let connection = try inventoryConnection(registration.server.registration.destination)
            #expect(await coordinator.discover(connection: connection, registration: registration).phase == .reconciliationRequired)
            let first = try #require(store.mutations.first)
            #expect(await coordinator.discover(connection: connection, registration: registration).phase == .reconciliationRequired)
            #expect(store.mutations == [first] && remote.afters == [nil])
            store.hideLookup = false
            #expect(await coordinator.discover(connection: connection, registration: registration).phase == .recorded)
            #expect(store.lookups == [first, first] && store.mutations == [first] && remote.afters == [nil])
            store.hideReply = false
            #expect(await coordinator.discover(connection: connection, registration: registration).phase == .recorded)
            #expect(remote.afters == [nil, cursor])
            #expect(try await mediaSnapshot(base).remoteInventory.count == 2)
        }
    }

    @Test(arguments: ["store", "registration"])
    func replacementDuringRemoteAwaitCannotCommitAnOldPage(replacement: String) async throws {
        try await withStorageRun { run in
            let base = try SQLiteRecordingStore(run: run, mode: .createNew)
            let registration = try await inventoryRegister(base)
            let store = InventoryFaultStore(base: base)
            let remote = InventoryRemoteFixture()
            remote.pages = [.succeeded(.init(registration: registration.server.registration, requestCursor: nil,
                originals: [try inventoryOriginal("late-page")], nextCursor: nil))]
            remote.onPage = {
                if replacement == "store" { store.observedIdentity = .init(rawValue: UUID()) }
                else {
                    _ = try await mediaRegister(base, registration: .init(destination: registration.server.registration.destination,
                        id: .init(rawValue: UUID().uuidString.lowercased()), generation: .init(rawValue: 2)))
                }
            }
            let coordinator = RemoteInventoryCoordinator(store: store, remoteFactory: { _, _, _ in remote })
            #expect(await coordinator.discover(connection: try inventoryConnection(registration.server.registration.destination), registration: registration).phase == .unavailable)
            #expect(store.mutations.isEmpty && remote.afters.count == 1)
            #expect(try await mediaSnapshot(base).remoteInventory.isEmpty)
        }
    }

    @Test func concurrentCallsAreSinglePageAndCaptureAdmissionDoesNotBecomeAMediaPermit() async throws {
        try await withStorageRun { run in
            let store = try SQLiteRecordingStore(run: run, mode: .createNew)
            let registration = try await inventoryRegister(store)
            let remote = InventoryRemoteFixture()
            remote.pages = [.succeeded(.init(registration: registration.server.registration, requestCursor: nil,
                originals: [try inventoryOriginal("single-page")], nextCursor: nil))]
            let gate = InventoryRemoteGate()
            remote.onPage = { await gate.checkpoint() }
            let admission = InventoryAdmission()
            let coordinator = RemoteInventoryCoordinator(store: store, admission: { admission.allowed }, remoteFactory: { _, _, _ in remote })
            let connection = try inventoryConnection(registration.server.registration.destination)
            let first = Task { await coordinator.discover(connection: connection, registration: registration) }
            defer { Task { await gate.release() } }
            try await backgroundEventually { await gate.hasArrived() }
            #expect(await coordinator.discover(connection: connection, registration: registration).phase == .busy)
            await gate.release()
            #expect(await first.value.phase == .recorded && remote.afters.count == 1)
            admission.allowed = false
            #expect(await coordinator.discover(connection: connection, registration: registration).phase == .waitingForCapture)
            #expect(remote.afters.count == 1)
            #expect(try await mediaSnapshot(store).requests.isEmpty)
        }
    }

    @Test func nativeRemoteRefusesUnboundStoreAndUnavailableCredentialsBeforeAnySDKRequest() async throws {
        try await withStorageRun { run in
            let store = try SQLiteRecordingStore(run: run, mode: .createNew)
            let registration = try await inventoryRegister(store)
            let identity = try #require(try await mediaSnapshot(store).storeIdentity)
            let credentials = InventoryUnavailableCredentials()
            let connection = try inventoryConnection(registration.server.registration.destination)
            let wrong = URLSessionRemoteInventoryRemote(connection: connection, credentials: credentials, store: store,
                identity: .init(rawValue: UUID()), registration: registration)
            #expect(await wrong.page(registration: registration.server.registration, after: nil) == .unknown)
            #expect(credentials.calls == 0)
            let current = URLSessionRemoteInventoryRemote(connection: connection, credentials: credentials, store: store,
                identity: identity, registration: registration)
            let port: any RemoteInventoryRemotePort = current
            #expect(await current.page(registration: registration.server.registration, after: nil) == .failed(.authenticationRequired))
            #expect(await port.page(registration: registration.server.registration, after: nil) == .failed(.authenticationRequired))
            #expect(credentials.calls == 2)
            #expect(try await mediaSnapshot(store).remoteInventory.isEmpty)
        }
    }

    @Test func normalCompositionUsesOneWriterRefreshesCatalogAndDoesNotGrantCustomRegistrationProductCredentials() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("FrameRelay-inventory-composition-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        let factory = ProductLibraryFactory(supportDirectory: parent)
        let services = try await factory.open()
        let keychain = try RegistrationTestKeychain(); defer { keychain.cleanup() }
        let vault = try keychain.vault(), registrationRemote = RegistrationTestRemote()
        let registrationCoordinator = RegistrationCoordinator(store: services.store, vault: vault, remote: registrationRemote)
        guard case .registered = await registrationCoordinator.register(connection: keychain.connection, bearer: "inventory-test-bootstrap") else {
            throw BackendContractError.notCommitted
        }
        let registration = try #require(try await mediaSnapshot(services.store).registrations.last)
        let remote = InventoryRemoteFixture()
        remote.pages = [.succeeded(.init(registration: registration.server.registration, requestCursor: nil,
            originals: [try inventoryOriginal("normal-composition-catalog")], nextCursor: nil))]
        let first = ProductComposition(factory: factory, registrationFactory: { store in
            RegistrationCoordinator(store: store, vault: vault, remote: registrationRemote)
        })
        await first.open()
        #expect(first.remoteInventory == nil && first.connection?.supportsRemoteInventory == false)
        let composition = ProductComposition(factory: factory, registrationFactory: { store in
            RegistrationCoordinator(store: store, vault: vault, remote: registrationRemote)
        }, remoteInventoryFactory: { opened in
            RemoteInventoryCoordinator(store: opened.store, remoteFactory: { _, _, _ in remote })
        })
        await composition.open()
        let model = try #require(composition.connection)
        #expect(model.canDiscoverRemoteInventory && remote.afters.isEmpty)
        await model.discoverRemoteInventory()
        #expect(model.remoteInventoryReport?.phase == .recorded)
        #expect(composition.library?.snapshot?.remoteItems.count == 1 && composition.library?.snapshot?.items.isEmpty == true)
        #expect(composition.library?.snapshot?.revision == (try await mediaSnapshot(services.store).revision))
        await composition.open()
        #expect(composition.connection === model && remote.afters.count == 1)
        #expect(try await mediaOriginalSnapshot(services.store).logicalOriginals.isEmpty)
        #expect(try await mediaSnapshot(services.store).outbox.isEmpty)
    }
}

nonisolated func inventoryTestRegistration() -> RegistrationIdentity {
    .init(destination: .init(rawValue: "9a3ba104-985f-4a2d-875d-d458258b9b6b"),
        id: .init(rawValue: "21088ea6-c2bc-4c21-8329-63d05bdfefcb"), generation: .init(rawValue: 1))
}
nonisolated func inventoryConnection(_ destination: DestinationIdentity) throws -> RegistrationConnection {
    try .init(endpoint: .init(httpsOrigin: "https://inventory.invalid"), destination: destination)
}
nonisolated func inventoryWireData(_ registration: RegistrationIdentity, after: String? = nil,
    originals: [OriginalContent], next: String? = nil) throws -> Data {
    let object: [String: Any] = [
        "destination_id": registration.destination.rawValue, "registration_id": registration.id.rawValue,
        "registration_generation": String(registration.generation.rawValue), "request_cursor": after as Any? ?? NSNull(),
        "items": originals.map { ["capture_id": $0.capture.rawValue, "content_generation": String($0.generation.rawValue),
            "sha256": $0.content.digest, "byte_count": String($0.content.byteCount)] }, "next_cursor": next as Any? ?? NSNull()
    ]
    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

@MainActor final class InventoryRemoteFixture {
    var pages: [BackendOutcome<RemoteInventoryPage>] = []
    var onPage: (@MainActor @Sendable () async throws -> Void)?
    private(set) var afters: [String?] = []
    func page(registration: RegistrationIdentity, after: String?) async -> BackendOutcome<RemoteInventoryPage> {
        afters.append(after)
        do { try await onPage?() } catch { return .unknown }
        return pages.isEmpty ? .unknown : pages.removeFirst()
    }
}
extension InventoryRemoteFixture: RemoteInventoryRemotePort {}

@MainActor final class InventoryFaultStore {
    let base: any MediaDiskStore
    var hideReply = false
    var hideLookup = false
    var observedIdentity: RegistrationStoreIdentity?
    private(set) var mutations: [BackendStoreMutation] = []
    private(set) var lookups: [BackendStoreMutation] = []
    init(base: any MediaDiskStore) { self.base = base }
    func load() async -> BackendStoreLoadResult {
        guard case .loaded(var snapshot) = await base.load() else { return .unavailable(.inaccessible) }
        if let observedIdentity { snapshot.storeIdentity = observedIdentity }
        return .loaded(snapshot)
    }
    func commit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        mutations.append(mutation)
        let result = await base.commit(mutation)
        return hideReply ? .unknown : result
    }
    func lookupCommit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        lookups.append(mutation)
        return hideLookup ? .unknown : await base.lookupCommit(mutation)
    }
}
extension InventoryFaultStore: MediaOperationStorePort {}

private actor InventoryRemoteGate {
    private var arrived = false
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    func hasArrived() -> Bool { arrived }
    func checkpoint() async { arrived = true; if !released { await withCheckedContinuation { continuation = $0 } } }
    func release() { released = true; continuation?.resume(); continuation = nil }
}
@MainActor private final class InventoryAdmission { var allowed = true }
@MainActor private final class InventoryUnavailableCredentials {
    private(set) var calls = 0
    func authorization(for connection: RegistrationConnection, intent: RegistrationIntent?, storeIdentity: RegistrationStoreIdentity) async throws -> RegistrationAuthorization {
        calls += 1; throw RegistrationAccessError.credentialUnavailable
    }
}
extension InventoryUnavailableCredentials: RegistrationAuthorizationPort {}
