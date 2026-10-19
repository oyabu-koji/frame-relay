import AVFoundation
import CryptoKit
import Foundation
import Testing
@testable import FrameRelay

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["FR_S25_HTTP_FIXTURE"] == "1"))
@MainActor struct RenditionHTTPFixtureTests {
    @Test func authenticatedStreamingAdvancesBeforeFullFileAndActuallyTerminates() async throws {
        let configuration = try S25HTTPConfiguration()
        try await withStorageRun { run in
            let fixture = try await RenditionFixture.make(run: run, content: configuration.content, renditionID: configuration.id)
            let gate = FixtureRenditionAdmission(fixture.command.gate)
            let client = FixedRenditionHTTPClient(binding: configuration.binding(mode: "normal", scenario: "streaming"))
            let reader = try await FixedRenditionRangeReader.open(command: fixture.command, admission: gate,
                authorization: gate, leases: fixture.leases, client: client, scope: fixture.scope)
            let player = try await AVRenditionPlayback.open(leases: fixture.leases, temporary: fixture.temporary, scope: fixture.scope) { _ in
                .init(reader: reader, contentType: configuration.mime)
            }
            let session = PlaybackSessionID(rawValue: "http-streaming")
            let task = Task { await player.play(.init(source: .remote(fixture.command), session: session,
                invalidationGeneration: .init(rawValue: 0))) }
            let advanced = await renditionEventually(seconds: 30) { player.elapsedSeconds > 0.1 && player.decodedFrames > 0 }
            let bytesAtProgress = client.receivedBytes
            let beforeStop = await S25StreamingSnapshot(player: player, client: client, reader: reader)
            let sdk = player.player
            await player.end(session)
            let result = await task.value
            let afterStop = await S25StreamingSnapshot(player: player, client: client, reader: reader)
            let observation = S25StreamingObservation(reachedProgress: advanced,
                totalByteCount: configuration.content.byteCount, bytesAtProgressConditionCheck: bytesAtProgress,
                beforeStop: beforeStop, afterStop: afterStop)
            Attachment.record(String(decoding: try JSONEncoder().encode(observation), as: UTF8.self),
                named: "s25-streaming-diagnostics.json")
            #expect(advanced)
            #expect(bytesAtProgress > 0 && bytesAtProgress < configuration.content.byteCount)
            if case .succeeded(let token) = result { #expect(token.observation == .played) }
            else { Issue.record("HTTP fixture did not progress in the real AVPlayer") }
            #expect(player.audioTracks == 1 && sdk?.currentItem == nil && player.sdkDetached)
            #expect(client.invalidated && client.started == client.completed)
            #expect(afterStop.clientBufferedPayloadBytes == 0 && afterStop.reader.bufferedResultPayloadBytes == 0)
            #expect(afterStop.reader.activeReads == 0 && afterStop.activeResourceRequests == 0)
            let terminalBytes = client.receivedBytes
            try await Task.sleep(for: .milliseconds(200))
            #expect(client.receivedBytes == terminalBytes)
            #expect(try await mediaOriginalSnapshot(fixture.store).logicalOriginals.first?.mediaReaders.isEmpty == true)
            let scoped = try await fixture.scope.close()
            #expect(scoped.observations.contains { $0.owner == .transport && $0.terminal.handlesClosed })
            #expect(scoped.observations.contains { $0.owner == .renditionPlayer && $0.terminal.handlesClosed })
            Attachment.record("fixtureOnly=true bytesAtProgress=\(bytesAtProgress) total=\(configuration.content.byteCount) started=\(client.started) completed=\(client.completed) decoded=\(player.decodedFrames)", named: "s25-streaming-observation.txt")
        }
    }

    @Test(arguments: ["wrong-version", "wrong-digest", "wrong-size", "short", "oversize", "redirect"])
    func rejectsMalformedFixedRangeAndWaitsForTerminal(mode: String) async throws {
        let configuration = try S25HTTPConfiguration()
        try await withStorageRun { run in
            let fixture = try await RenditionFixture.make(run: run, content: configuration.content, renditionID: configuration.id)
            let gate = FixtureRenditionAdmission(fixture.command.gate)
            let client = FixedRenditionHTTPClient(binding: configuration.binding(mode: mode))
            let reader = try await FixedRenditionRangeReader.open(command: fixture.command, admission: gate,
                authorization: gate, leases: fixture.leases, client: client, scope: fixture.scope)
            do { _ = try await reader.read(offset: 0, length: 64); Issue.record("Accepted malformed response: \(mode)") }
            catch { }
            let terminal = try await reader.close()
            #expect(terminal.handlesClosed && terminal.started == terminal.completed)
            #expect(mode != "redirect" || client.refusedRedirects == 1)
            #expect(try await mediaOriginalSnapshot(fixture.store).logicalOriginals.first?.mediaReaders.isEmpty == true)
        }
    }

    @Test func exactRangeGateChangeAndStopDuringResponse() async throws {
        let configuration = try S25HTTPConfiguration()
        try await withStorageRun { run in
            let fixture = try await RenditionFixture.make(run: run, content: configuration.content, renditionID: configuration.id)
            let gate = FixtureRenditionAdmission(fixture.command.gate)
            let client = FixedRenditionHTTPClient(binding: configuration.binding(mode: "normal"))
            let reader = try await FixedRenditionRangeReader.open(command: fixture.command, admission: gate,
                authorization: gate, leases: fixture.leases, client: client, scope: fixture.scope)
            #expect(try await reader.read(offset: 17, length: 37).count == 37)
            let started = client.started
            await gate.setDenied(true)
            await #expect(throws: BackendContractError.notOnWiFi) { try await reader.read(offset: 54, length: 37) }
            #expect(client.started == started)
            _ = try await reader.close()
            await gate.setDenied(false)
            let slow = FixedRenditionHTTPClient(binding: configuration.binding(mode: "delayed"))
            let pendingReader = try await FixedRenditionRangeReader.open(command: fixture.command, admission: gate,
                authorization: gate, leases: fixture.leases, client: slow, scope: fixture.scope)
            let read = Task { try await pendingReader.read(offset: 0, length: 65_536) }
            #expect(await renditionEventually { slow.receivedBytes > 0 })
            let terminal = try await pendingReader.close()
            if case .success = await read.result { Issue.record("Stopped delayed response delivered bytes") }
            #expect(terminal.handlesClosed && terminal.started == terminal.completed)
            #expect(try await mediaOriginalSnapshot(fixture.store).logicalOriginals.first?.mediaReaders.isEmpty == true)
        }
    }

    @Test func authenticationFailureAndGateLossDuringResponseDoNotDeliverBytes() async throws {
        let configuration = try S25HTTPConfiguration()
        try await withStorageRun { run in
            let fixture = try await RenditionFixture.make(run: run, content: configuration.content, renditionID: configuration.id)
            let gate = FixtureRenditionAdmission(fixture.command.gate)
            let unauthorized = FixedRenditionHTTPClient(binding: configuration.binding(mode: "normal", authorized: false))
            let deniedReader = try await FixedRenditionRangeReader.open(command: fixture.command, admission: gate,
                authorization: gate, leases: fixture.leases, client: unauthorized, scope: fixture.scope)
            do { _ = try await deniedReader.read(offset: 0, length: 64); Issue.record("Missing bearer accepted") }
            catch { }
            _ = try await deniedReader.close()
            #expect(unauthorized.started == 1 && unauthorized.completed == 1)
            let delayed = FixedRenditionHTTPClient(binding: configuration.binding(mode: "delayed"))
            let reader = try await FixedRenditionRangeReader.open(command: fixture.command, admission: gate,
                authorization: gate, leases: fixture.leases, client: delayed, scope: fixture.scope)
            let read = Task { try await reader.read(offset: 0, length: 64) }
            #expect(await renditionEventually { delayed.receivedBytes > 0 })
            await gate.setDenied(true)
            if case .success = await read.result { Issue.record("Gate loss during response delivered bytes") }
            _ = try await reader.close()
            #expect(delayed.completed == 1 && delayed.invalidated)
            #expect(try await mediaOriginalSnapshot(fixture.store).logicalOriginals.first?.mediaReaders.isEmpty == true)
        }
    }

    @Test func httpRetrievalVerifiesWholeFileBeforePhotoUse() async throws {
        let configuration = try S25HTTPConfiguration()
        try await withStorageRun { run in
            let fixture = try await RenditionFixture.make(run: run, content: configuration.content, renditionID: configuration.id)
            let gate = FixtureRenditionAdmission(fixture.command.gate)
            let client = FixedRenditionHTTPClient(binding: configuration.binding(mode: "normal"))
            let reader = try await FixedRenditionRangeReader.open(command: fixture.command, admission: gate,
                authorization: gate, leases: fixture.leases, client: client, scope: fixture.scope)
            let created = try await fixture.create()
            let complete = try await RenditionTemporaryRetrieval(temporary: fixture.temporary).retrieve(reader: reader, usage: created.usage)
            #expect(complete.hasCompleteCoverage && complete.verifiedContent == configuration.content)
            guard case .succeeded(let usage) = await fixture.temporary.acquireUsage(complete.id,
                purpose: .photoHandoff, usageID: .init(rawValue: "http-photo")) else { Issue.record("No photo use"); return }
            let photo = try await fixture.temporary.resolvePhotoMedia(usage)
            #expect(photo.handoff.capturedAt == RenditionFixture.capturedAt)
            #expect(try renditionContent(Data(contentsOf: photo.url)) == configuration.content)
            try await fixture.temporary.finishPhotoMedia(usage)
            #expect(await fixture.temporary.releaseUsage(usage) == .succeeded(complete.id))
            #expect(await fixture.temporary.releaseUsage(complete.usage) == .succeeded(complete.id))
            #expect(client.invalidated && client.started == client.completed)
        }
    }
}

nonisolated private struct S25StreamingObservation: Encodable {
    let reachedProgress: Bool
    let totalByteCount: UInt64
    let bytesAtProgressConditionCheck: UInt64
    let beforeStop: S25StreamingSnapshot
    let afterStop: S25StreamingSnapshot
}

/// Fixed aggregate fields only. Payload counts describe this app's retained
/// Data, not allocation capacity or opaque URLSession/AVPlayer memory.
nonisolated private struct S25StreamingSnapshot: Encodable {
    let phase: String
    let setupStage: String
    let elapsedSeconds: Double
    let decodedFrames: Int
    let audioTracks: Int
    let playerPresent: Bool
    let itemStatus: Int?
    let timeControlStatus: Int?
    let activeResourceRequests: Int
    let cumulativeResourceDeliveredBytes: UInt64
    let cumulativeReceivedBytes: UInt64
    let clientBufferedPayloadBytes: UInt64
    let clientPeakBufferedPayloadBytes: UInt64
    let startedHTTP: Int
    let completedHTTP: Int
    let invalidated: Bool
    let sdkMemoryBytes = "unknown"
    let reader: RenditionReadDiagnostics

    @MainActor init(player: AVRenditionPlayback, client: FixedRenditionHTTPClient,
                    reader: FixedRenditionRangeReader) async {
        self.reader = await reader.diagnostics()
        phase = String(describing: player.phase); setupStage = player.setupStage.rawValue
        elapsedSeconds = player.elapsedSeconds; decodedFrames = player.decodedFrames; audioTracks = player.audioTracks
        playerPresent = player.player != nil; itemStatus = player.player?.currentItem?.status.rawValue
        timeControlStatus = player.player?.timeControlStatus.rawValue
        activeResourceRequests = player.activeResourceRequests; cumulativeResourceDeliveredBytes = player.resourceDeliveredBytes
        cumulativeReceivedBytes = client.receivedBytes; clientBufferedPayloadBytes = client.bufferedPayloadBytes
        clientPeakBufferedPayloadBytes = client.peakBufferedPayloadBytes
        startedHTTP = client.started; completedHTTP = client.completed; invalidated = client.invalidated
    }
}

nonisolated private struct S25HTTPConfiguration: Sendable {
    let base: URL
    let token: String
    let id: String
    let content: ContentIdentity
    let mime: String
    init() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let raw = environment["FR_S25_FIXTURE_URL"], let base = URL(string: raw),
              base.scheme == "http", base.host == "127.0.0.1", base.port != nil,
              base.user == nil, base.password == nil, base.query == nil, base.fragment == nil,
              let token = environment["FR_S25_FIXTURE_TOKEN"], !token.isEmpty,
              let id = environment["FR_S25_FIXTURE_ID"], !id.isEmpty,
              let digest = environment["FR_S25_FIXTURE_SHA256"], digest.count == 64,
              let rawCount = environment["FR_S25_FIXTURE_BYTE_COUNT"], let count = UInt64(rawCount), count > 65_536,
              let mime = environment["FR_S25_FIXTURE_MIME"], ["video/quicktime", "video/mp4"].contains(mime)
        else { throw BackendContractError.invalidValue }
        self.base = base; self.token = token; self.id = id; self.mime = mime
        content = try .init(byteCount: count, algorithm: "sha256", digest: digest)
    }
    func binding(mode: String, authorized: Bool = true, scenario: String? = nil) -> FixedRenditionHTTPBinding {
        .init(url: base.appendingPathComponent(mode), contentType: mime, headers: { _ in
            var headers = authorized ? ["Authorization": "Bearer " + token] : [:]
            if let scenario { headers["X-Fixture-Scenario"] = scenario }
            return headers
        }, validateIdentity: { response, command in
            guard command.distribution.rendition.rendition.rawValue == id,
                  response.value(forHTTPHeaderField: "X-Fixture-Rendition") == id,
                  response.value(forHTTPHeaderField: "X-Fixture-SHA256") == content.digest,
                  response.value(forHTTPHeaderField: "X-Fixture-Size") == String(content.byteCount) else {
                throw BackendContractError.identityMismatch
            }
        })
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["FR_S25_GENERATE_FIXTURE"] == "1"))
struct RenditionFixtureGenerationTests {
    @Test func generateDisposableMovieAndManifest() async throws {
        try await withStorageRun { run in
            let movie = run.url.appendingPathComponent("s25-fixture.mov")
            try await SyntheticMovieFixture.write(to: movie, withAudio: true, durationSeconds: 60)
            let content = try renditionContent(Data(contentsOf: movie))
            let manifest = "{\"fixtureOnly\":true,\"path\":\"\(movie.path)\",\"byteCount\":\(content.byteCount),\"sha256\":\"\(content.digest)\",\"mime\":\"video/quicktime\",\"duration\":60}"
            Attachment.record(manifest, named: "s25-generated-fixture.json")
            print("S25_GENERATED_FIXTURE \(manifest)")
        }
    }
}
