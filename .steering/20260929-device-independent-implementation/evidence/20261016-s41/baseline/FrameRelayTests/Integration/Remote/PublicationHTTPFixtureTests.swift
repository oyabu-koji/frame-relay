import Foundation
import Testing
@testable import FrameRelay

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["FR_S27_HTTP_FIXTURE"] == "1"))
@MainActor struct PublicationHTTPFixtureTests {
    @Test func canonicalPlaybackConfirmationInvalidationAndReplacement() async throws {
        let config = try PublicationHTTPConfiguration()
        try await withStorageRun { run in
            let store = try SQLiteRecordingStore(run: run, mode: .createNew)
            let identity = try await establishRegistrationIdentity(store)
            _ = try await mediaCommit(store, .registrationIntent(config.receipt.intent))
            _ = try await mediaCommit(store, .registration(config.receipt))
            let registered = try #require(try await mediaSnapshot(store).registrations.first)
            let credentials = PublicationCredentialsFixture(registration: registered, identity: identity,
                material: .init(bearer: config.bearer, secret: config.registrationSecret))
            let remote = URLSessionPublicationRemote(connection: config.connection, credentials: credentials, store: store, identity: identity)
            let gate = MediaGateLease(operation: .init(rawValue: UUID().uuidString), attempt: .init(rawValue: UUID().uuidString),
                target: .rendition(config.v1), registration: registered.server.registration, generation: 1)
            let admission = FixtureRenditionAdmission(gate)
            let binding = try await PublicationHTTPBinding.open(gate: gate, sourceOperation: .init(rawValue: UUID().uuidString),
                connection: config.connection, remote: remote, admission: admission, store: store, identity: identity)
            let wire = await binding.binding()
            let leases = RenditionReadLeases(store: store)
            let registry = RenditionScopeRegistry(leases: leases)
            let scope = try await registry.open(original: config.v1.original)
            let temporary = try await ManagedTemporaryMedia.open(root: run.url.appendingPathComponent("temporary", isDirectory: true), leases: leases, scope: scope)
            let client = FixedRenditionHTTPClient(binding: wire)
            let reader = try await FixedRenditionRangeReader.open(command: binding.command, admission: admission,
                authorization: binding, leases: leases, client: client, scope: scope)
            let player = try await AVRenditionPlayback.open(leases: leases, temporary: temporary, scope: scope) { _ in reader }
            let session = PlaybackSessionID(rawValue: "s27-wire-player")
            do {
                // A separately owned successful GET establishes a consumed
                // ticket while V1 is still current. Negative probes use the
                // JSON-only bounded client and never become playback evidence.
                let ticket = try await binding.authorize(.init(gate: gate, distribution: binding.command.distribution,
                    range: .init(lowerBound: 0, upperBound: 37)))
                let probe = FixedRenditionHTTPClient(binding: wire)
                let probeLease = try await leases.acquire(rendition: config.v1, registration: gate.registration,
                    operation: gate.operation, context: .transport(gate.attempt))
                try await leases.commit(.distribution(.init(command: .init(rawValue: UUID().uuidString), lease: probeLease,
                    observation: .init(rawValue: 1), result: .succeeded(ticket.distribution))))
                let owned = PublicationProbeOwner(client: probe, lease: probeLease, leases: leases)
                _ = try await scope.register(owner: .transport) { try await owned.close() }
                #expect(try await probe.read(ticket).count == 37)
                let replay = try await config.mediaRequest(ticket, binding: wire)
                #expect(try await PublicationURLSessionRequest.perform(replay).status == 409)
                _ = try await owned.close()
                let unused = try await binding.authorize(.init(gate: gate, distribution: binding.command.distribution,
                    range: .init(lowerBound: 37, upperBound: 74)))
                let staleRequest = try await config.mediaRequest(unused, binding: wire)
                let playing = Task { await player.play(.init(source: .remote(binding.command), session: session,
                    invalidationGeneration: binding.invalidationGeneration)) }
                let advanced = await renditionEventually(seconds: 30) { player.elapsedSeconds > 0.1 && player.decodedFrames > 0 }
                let bytesAtProgress = client.receivedBytes
                #expect(advanced && bytesAtProgress > 0 && bytesAtProgress < config.v1.deliveryContent.byteCount)
                guard case .succeeded(let token) = await playing.value else { throw BackendContractError.unavailable }
                #expect(try await mediaSnapshot(store).confirmations.isEmpty)
                let confirmations = MediaConfirmationCoordinator(store: store, identity: identity)
                guard case .succeeded(let record) = await confirmations.confirm(token, action: .init(rawValue: "explicit-http-confirmation")) else { throw BackendContractError.notCommitted }
                _ = try await config.control("arm-confirmation-response-loss")
                let outbox = BackendOutboxCoordinator(store: store, identity: identity, remote: remote)
                #expect(await outbox.synchronize() == .succeeded(1))
                #expect(try await mediaSnapshot(store).confirmations == [record])
                let replacement = try await config.control("begin-replacement")
                let next = try PublicationWire.decodeRendition(try replacement.object(keys: ["replacement_id", "rendition", "media_type", "invalidation_id", "invalidation_generation"])["rendition"]!)
                #expect(next.original == config.v1.original && next.rendition != config.v1.rendition)
                #expect(try await config.controlStatus("publish-replacement") == 409)
                let external = PublicationExternalFixture() // Explicit tests-only owner inventory.
                let invalidator = MediaInvalidationCoordinator(store: store, identity: identity,
                    ordering: ManagedOriginalAccess(store: store, originals: ManagedOriginalStore(run: run)), scopes: registry, external: external)
                var after: InvalidationID?
                var acknowledgements: [InvalidationAcknowledgement] = []
                repeat {
                    guard case .succeeded(let page) = await remote.invalidations(registration: gate.registration, after: after) else { throw BackendContractError.unknownResult }
                    for invalidation in page.records {
                        guard case .succeeded(let ack) = await invalidator.invalidate(invalidation) else { throw BackendContractError.unknownResult }
                        acknowledgements.append(ack)
                    }
                    after = page.nextAfter
                } while after != nil
                #expect(acknowledgements.count == 1)
                #expect(player.player == nil && player.sdkDetached)
                #expect(client.started == client.completed && client.invalidated)
                #expect(await outbox.synchronize() == .succeeded(1))
                let published = try await config.control("publish-replacement")
                let output = try published.object(keys: ["rendition", "media_type", "previous_revision", "committed_revision"])
                #expect(try PublicationWire.decodeRendition(output["rendition"]!) == next)
                guard case .succeeded(let manifest) = await remote.manifest(original: config.v1.original, registration: gate.registration) else { throw BackendContractError.unknownResult }
                #expect(manifest.current == next)
                #expect(try await PublicationURLSessionRequest.perform(staleRequest).status == 409)
                #expect(try await mediaSnapshot(store).confirmationStates.first?.validConfirmation == nil)
                let state = await reader.diagnostics()
                #expect(state.cachePayloadBytes == 0 && state.pendingResponsePayloadBytes == 0 && state.bufferedResultPayloadBytes == 0)
                Attachment.record("fixtureOnly=true bytesAtProgress=\(bytesAtProgress) total=\(config.v1.deliveryContent.byteCount) decoded=\(player.decodedFrames) httpStarted=\(client.started) httpCompleted=\(client.completed) cacheAfter=\(state.cachePayloadBytes) acknowledgements=\(acknowledgements.count)", named: "s27-wire-observation.txt")
            } catch {
                await player.end(session); await client.close(); _ = try? await scope.close()
                throw error
            }
        }
    }
}

@MainActor private final class PublicationProbeOwner {
    let client: FixedRenditionHTTPClient
    let lease: MediaReadLease
    let leases: RenditionReadLeases
    var terminal: RenditionReadTerminal?
    init(client: FixedRenditionHTTPClient, lease: MediaReadLease, leases: RenditionReadLeases) { self.client = client; self.lease = lease; self.leases = leases }
    func close() async throws -> RenditionReadTerminal {
        if let terminal { return terminal }
        await client.close()
        guard client.started == client.completed, client.invalidated else { throw BackendContractError.readersActive }
        try await leases.release(lease)
        let value = RenditionReadTerminal(epoch: lease.epoch, started: client.started, completed: client.completed, bytes: client.receivedBytes, handlesClosed: true)
        terminal = value; return value
    }
}

@MainActor private struct PublicationHTTPConfiguration {
    let connection: RegistrationConnection
    let receipt: RegistrationServerReceipt
    let v1: RenditionIdentity
    let bearer: String
    let registrationSecret: String
    let fixtureSecret: String
    let runIdentity: String
    init() throws {
        let env = ProcessInfo.processInfo.environment
        guard let origin = env["FR_S27_ORIGIN"], let bearer = env["FR_S27_BEARER"], let secret = env["FR_S27_REGISTRATION_SECRET"],
              let fixtureSecret = env["FR_S27_FIXTURE_SECRET"], let json = env["FR_S27_FIXTURE_JSON"], json.utf8.count <= 16_384 else { throw BackendContractError.invalidValue }
        let object = try PublicationWire.parse(Data(json.utf8)).object(keys: ["schema_version", "run_identity", "fixture_only", "wire_sha256", "source_sha256", "media_type", "registration_receipt", "original", "v1", "v2", "provenance"])
        guard object["schema_version"] == .string("fr-publication-fixture-v1"), object["fixture_only"] == .boolean(true),
              object["wire_sha256"] == .string("455868ebe8d057ad32471a169396333c03cd1bcf2b4a4986f3147935f2617e0a"), object["v2"] == .null else { throw BackendContractError.unsupportedVersion }
        let registration = try object["registration_receipt"]!.object(keys: ["destination_id", "operation_id", "registration_id", "generation", "created_at"])
        let intent = RegistrationIntent(operation: .init(rawValue: try registration["operation_id"]!.opaque()), destination: .init(rawValue: try registration["destination_id"]!.opaque()))
        receipt = try RegistrationWire.receipt(PublicationWire.body(object["registration_receipt"]!), intent: intent)
        #if DEBUG && targetEnvironment(simulator)
        connection = try .init(endpoint: .isolatedLoopbackProbe(origin), destination: intent.destination)
        #else
        throw BackendContractError.unavailable
        #endif
        v1 = try PublicationWire.decodeRendition(object["v1"]!)
        guard try PublicationWire.original(v1.original) == object["original"], object["media_type"] == .string("video/quicktime") else { throw BackendContractError.identityMismatch }
        self.bearer = bearer; registrationSecret = secret; self.fixtureSecret = fixtureSecret
        runIdentity = try object["run_identity"]!.opaque()
    }
    func mediaRequest(_ command: RetrieveMediaCommand, binding: FixedRenditionHTTPBinding) async throws -> URLRequest {
        let range = try #require(command.range)
        var request = URLRequest(url: binding.url)
        for (name, value) in try await binding.headers(command) { request.setValue(value, forHTTPHeaderField: name) }
        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        return request
    }
    func controlStatus(_ action: String) async throws -> Int { try await controlResponse(action).status }
    func control(_ action: String) async throws -> PublicationJSON {
        let response = try await controlResponse(action)
        guard response.status == 200 else { throw BackendContractError.unknownResult }
        let object = try PublicationWire.parse(response.data).object(keys: ["run_identity", "action", "result"])
        guard object["run_identity"] == .string(runIdentity), object["action"] == .string(action) else { throw BackendContractError.identityMismatch }
        return object["result"]!
    }
    private func controlResponse(_ action: String) async throws -> PublicationHTTPResponse {
        var parts = URLComponents(url: connection.endpoint.origin, resolvingAgainstBaseURL: false)!
        parts.path = "/__s27_fixture__/control"
        var request = URLRequest(url: parts.url!); request.httpMethod = "POST"
        request.setValue(fixtureSecret, forHTTPHeaderField: "X-FrameRelay-Fixture-Secret")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try PublicationWire.body(.object(["run_identity": .string(runIdentity), "action": .string(action)]))
        return try await PublicationURLSessionRequest.perform(request)
    }
}
