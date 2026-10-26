import AVFoundation
import Foundation
import Testing
@testable import FrameRelay

@Suite(.serialized) @MainActor struct RenditionPlaybackTests {
    @Test func completeTemporaryFilePlaysOfflineThenDetachesAndClosesItsUse() async throws {
        try await withStorageRun { run in
            let movie = run.url.appendingPathComponent("source.mov")
            try await SyntheticMovieFixture.write(to: movie, withAudio: true, durationSeconds: 8)
            let bytes = try Data(contentsOf: movie)
            let fixture = try await RenditionFixture.make(run: run, content: renditionContent(bytes))
            let complete = try await fixture.complete(bytes)
            let player = try await AVRenditionPlayback.open(leases: fixture.leases, temporary: fixture.temporary, scope: fixture.scope) { _ in
                Issue.record("Complete local playback must not request network admission")
                throw BackendContractError.notOnWiFi
            }
            let session = PlaybackSessionID(rawValue: "offline-local")
            let task = Task { await player.play(.init(source: .local(complete, fixture.command.distribution),
                session: session, invalidationGeneration: .init(rawValue: 0))) }
            let advanced = await renditionEventually { player.elapsedSeconds > 0.1 && player.decodedFrames > 0 }
            let sdk = player.player
            await player.end(session)
            let outcome = await task.value
            #expect(advanced)
            if case .succeeded(let token) = outcome {
                #expect(token.distribution == fixture.command.distribution && token.observation == .played)
            } else { Issue.record("Local real AVPlayer did not produce observed progress") }
            #expect(player.audioTracks == 1 && player.sdkDetached && player.phase == .stopped)
            #expect(player.startedMonitors == 1 && player.completedMonitors == 1)
            #expect(sdk?.currentItem == nil && player.player == nil)
            #expect(player.lastTerminal?.handlesClosed == true)
            #expect(try await fixture.temporary.usageSnapshot(complete.id).uses == 1)
            #expect(await fixture.temporary.releaseUsage(complete.usage) == .succeeded(complete.id))
            #expect(try await mediaOriginalSnapshot(fixture.store).logicalOriginals.first?.mediaReaders.isEmpty == true)
            let terminal = try await fixture.scope.close()
            #expect(terminal.observations.contains { $0.owner == .renditionPlayer && $0.terminal.started == $0.terminal.completed })
        }
    }

    @Test(arguments: [false, true])
    func invalidationStopsAlreadyBufferedLocalPlayerAndKeepsOriginalCaptureTime(concurrentEnd: Bool) async throws {
        try await withStorageRun { run in
            let movie = run.url.appendingPathComponent("invalidation.mov")
            try await SyntheticMovieFixture.write(to: movie, withAudio: true, durationSeconds: 8)
            let bytes = try Data(contentsOf: movie)
            let fixture = try await RenditionFixture.make(run: run, content: renditionContent(bytes))
            let complete = try await fixture.complete(bytes)
            let player = try await AVRenditionPlayback.open(leases: fixture.leases, temporary: fixture.temporary, scope: fixture.scope) { _ in
                throw BackendContractError.notOnWiFi
            }
            let session = PlaybackSessionID(rawValue: "invalidated-local")
            let task = Task { await player.play(.init(source: .local(complete, fixture.command.distribution),
                session: session, invalidationGeneration: .init(rawValue: 0))) }
            #expect(await renditionEventually { player.elapsedSeconds > 0.1 })
            let invalidation = InvalidationRecord(id: .init(rawValue: "invalidate-fixture"),
                rendition: complete.rendition, registration: fixture.command.distribution.registration,
                generation: .init(rawValue: 1))
            _ = try await mediaOriginalCommit(fixture.store, .reserveInvalidation(.init(invalidation)))
            let ending = concurrentEnd ? Task { await player.end(session) } : nil
            #expect(await renditionEventually { player.phase == .failed || (concurrentEnd && player.phase == .stopped) })
            await ending?.value
            await player.end(session); _ = await task.value
            #expect(player.sdkDetached && player.lastTerminal?.handlesClosed == true)
            #expect(player.startedMonitors == 1 && player.completedMonitors == 1)
            #expect(try await fixture.temporary.stateFor(complete.id).capturedAt == RenditionFixture.capturedAt)
            #expect(await fixture.temporary.releaseUsage(complete.usage) == .succeeded(complete.id))
            _ = try await fixture.scope.close()
        }
    }

    @Test func setupFailureJoinsMonitorBeforeScopeReportsTerminal() async throws {
        try await withStorageRun { run in
            let fixture = try await RenditionFixture.make(run: run, content: renditionContent(Data(repeating: 1, count: 128)))
            let player = try await AVRenditionPlayback.open(leases: fixture.leases, temporary: fixture.temporary,
                scope: fixture.scope) { _ in throw BackendContractError.unavailable }
            let session = PlaybackSessionID(rawValue: "failed-setup")
            let task = Task { await player.play(.init(source: .remote(fixture.command), session: session,
                invalidationGeneration: .init(rawValue: 0))) }
            #expect(await renditionEventually { player.phase == .failed })
            await player.end(session)
            #expect(await task.value == .failed(.inaccessible))
            #expect(player.startedMonitors == 1 && player.completedMonitors == 1)
            #expect(player.player == nil && player.sdkDetached)
            let terminal = try await fixture.scope.close()
            #expect(terminal.observations.contains {
                $0.owner == .renditionPlayer && $0.terminal.started == 1 && $0.terminal.completed == 1
            })
            #expect(try await mediaOriginalSnapshot(fixture.store).logicalOriginals.first?.mediaReaders.isEmpty == true)
        }
    }
}
