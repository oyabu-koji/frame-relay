import Foundation
import AVFoundation
import Testing
@testable import FrameRelay

@Suite(.serialized)
struct ProductCompositionTests {
    @Test func thirtySecondMovieCompletesBothTracksAndFullReaderInspection() async throws {
        try await withStorageRun { run in
            let fixture = try CaptureFixture(clip: "composition-long-movie")
            let originals = ManagedOriginalStore(run: run)
            let url = try await originals.reserve(original: fixture.intent.original)
            print("S16_LONG_MOVIE_BEGIN url=\(url.path) durationSeconds=30")
            try await SyntheticMovieFixture.write(to: url, withAudio: true, durationSeconds: 30)
            print("S16_LONG_MOVIE_GENERATION_COMPLETE url=\(url.path)")
            let asset = AVURLAsset(url: url)
            let videos = try await asset.loadTracks(withMediaType: .video)
            let audios = try await asset.loadTracks(withMediaType: .audio)
            #expect(videos.count == 1)
            #expect(audios.count == 1)
            let video = try #require(videos.first)
            let audio = try #require(audios.first)
            let videoDuration = try await video.load(.timeRange).duration.seconds
            let audioDuration = try await audio.load(.timeRange).duration.seconds
            #expect(videoDuration == 30)
            #expect(audioDuration == 30)
            let inspector = AVOriginalInspectionAdapter(originals: originals)
            guard case .inspected(_, let inspection) = await inspector.inspect(
                .init(token: fixture.token(4), original: fixture.intent.original)) else {
                Issue.record("The complete thirty-second Movie must finish actual AVAssetReader inspection"); return
            }
            #expect(inspection.video.hasSamples)
            #expect(inspection.audio.hasSamples)
            #expect(inspection.playback == .unavailable(.notMeasured))
            #expect(inspection.completeness == .unknown(.evidenceMissing))
            let observation = try #require(await inspector.observation(for: fixture.intent.original))
            #expect(observation.videoTrackCount == 1)
            #expect(observation.audioTrackCount == 1)
            #expect(observation.digest.byteCount > 0)
            print("S16_LONG_MOVIE_READER_COMPLETE videoSeconds=\(videoDuration) audioSeconds=\(audioDuration) audioTracks=\(audios.count) digest=\(observation.digest.sha256)")
        }
    }

    @Test func factoryReturnsOneWriterAndReopensFixedProductDirectory() async throws {
        let parent = try compositionTestParent()
        let factory = ProductLibraryFactory(supportDirectory: parent)
        let first = try await factory.open()
        let second = try await factory.open()
        #expect(first.store === second.store)
        #expect(first.access === second.access)
        #expect(first.run.url.lastPathComponent == "FrameRelayLibrary")
        let fixture = try CaptureFixture(clip: "composition-retained")
        try await first.originals.reserveForRecording(fixture.intent.original)
        guard case .committed = await first.store.execute(.commitIntent(fixture.token(1), expectedRevision: 0, fixture.intent)) else {
            Issue.record("Real product writer did not commit"); return
        }
        let reopened = try await ProductLibraryFactory(supportDirectory: parent).open()
        guard case .loaded(let snapshot) = await reopened.reader.loadLibrary() else {
            Issue.record("Fixed root did not reopen"); return
        }
        #expect(snapshot.items.map(\.id) == [fixture.context.capture])
        #expect(snapshot.items[0].recording.result == nil)
    }

    @Test(arguments: ["missing-marker", "missing-database", "corrupt-database", "symlink"])
    func invalidExistingRootIsPreserved(kind: String) async throws {
        let parent = try compositionTestParent()
        let root = parent.appendingPathComponent("FrameRelayLibrary")
        if kind == "symlink" {
            let target = parent.appendingPathComponent("other")
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            try FileManager.default.createSymbolicLink(at: root, withDestinationURL: target)
        } else if kind == "missing-marker" {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        } else {
            _ = try ExplorationRunDirectory.createNew(at: root)
            if kind == "corrupt-database" {
                try Data("invalid-db-preserved".utf8).write(to: root.appendingPathComponent("recordings.sqlite"))
            }
        }
        let sentinel = parent.appendingPathComponent("do-not-reset")
        try Data("preserve".utf8).write(to: sentinel)
        let before = try directoryBytes(parent)
        let factory = ProductLibraryFactory(supportDirectory: parent)
        for _ in 0..<2 {
            do { _ = try await factory.open(); Issue.record("Invalid existing root was accepted: \(kind)") }
            catch { }
        }
        let after = try directoryBytes(parent)
        for (path, bytes) in before { #expect(after[path] == bytes) }
        let added = Set(after.keys).subtracting(before.keys)
        #expect(added.isSubset(of: [root.appendingPathComponent("recordings-sqlite.lock").path]))
        if kind == "missing-database" {
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("recordings.sqlite").path))
        }
    }

    @MainActor @Test func compositionKeepsModelsAndDoesNotAutoResumeAfterBackground() async throws {
        let factory = ProductLibraryFactory(supportDirectory: try compositionTestParent())
        let composition = ProductComposition(factory: factory)
        await composition.open()
        let library = try #require(composition.library)
        let playback = try #require(composition.playback)
        #expect(library.snapshot?.items.isEmpty == true)
        await composition.enteredBackground()
        await composition.open()
        #expect(composition.library === library)
        #expect(composition.playback === playback)
        #expect(playback.target == nil)
        #expect(!playback.playback.isBusy)
        #expect(composition.openingIssue == nil)
    }
}

nonisolated private func compositionTestParent() throws -> URL {
    let parent = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent("FrameRelay-composition-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
    return parent // Retain evidence until process/container teardown; no live SQLite unlink.
}

nonisolated private func directoryBytes(_ directory: URL) throws -> [String: Data] {
    let enumerator = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]))
    var files: [String: Data] = [:]
    for case let url as URL in enumerator {
        if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            files[url.path] = try Data(contentsOf: url)
        }
    }
    return files
}
