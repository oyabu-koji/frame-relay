import Foundation
import AVFoundation
import Testing
@testable import FrameRelay

/// Opt-in, test-target-only preparation for a later, separate UI test process.
/// Uses the normal app host's one factory/writer, with no product fixture branch.
@Suite(.serialized)
struct ProductLibrarySeedTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_LIBRARY_SEED"] == "1"))
    func seedNormalAppContainer() async throws {
        let services = try await ProductLibraryFactory.shared.open()
        guard case .loaded(let before) = await services.reader.loadLibrary() else {
            Issue.record("Seed cannot read the normal product root"); return
        }
        let expected = Set(["s16v2-original", "s16v2-cleanup", "s16v2-discard", "s16v2-unfinished"])
        let existing = Set(before.items.map { $0.id.rawValue })
        let manifestURL = services.run.url.appendingPathComponent("s16v2-test-seed-evidence.json")
        let creating = existing.isDisjoint(with: expected)
        if creating {
            let playable = try await seedMovie("s16v2-original", services: services)
            try #require(playable.saveRecord.result == .unknown(.evidenceMissing))
            for (name, purpose) in [("s16v2-cleanup", RemovalPurpose.cleanup), ("s16v2-discard", .discard)] {
                let binding = try await seedMovie(name, services: services)
                try await seedRemovalProjection(binding, purpose: purpose, services: services)
            }
            let unfinished = try CaptureFixture(clip: "s16v2-unfinished")
            try await services.originals.reserveForRecording(unfinished.intent.original)
            guard case .committed = await services.store.execute(.commitIntent(unfinished.token(1), expectedRevision: 0, unfinished.intent)) else {
                Issue.record("Seed unfinished intent failed"); return
            }
        } else {
            // Never repair/reset a partially prepared or unexpectedly changed root.
            try #require(expected.isSubset(of: existing))
            try #require(FileManager.default.fileExists(atPath: manifestURL.path))
        }
        guard case .loaded(let result) = await services.reader.loadLibrary() else {
            Issue.record("Seed result unavailable"); return
        }
        try #require(expected.isSubset(of: Set(result.items.map { $0.id.rawValue })))
        try #require(result.history.contains { $0.id.rawValue == "s16v2-discard" })
        try #require(result.recordings.contains { $0.id.rawValue == "s16v2-cleanup" && $0.removal == .removed(.cleanup) })
        try #require(result.recordings.contains { $0.id.rawValue == "s16v2-unfinished" && $0.requiresReconciliation })
        guard case .succeeded(let state) = await services.store.loadOriginalState() else {
            Issue.record("Seed ledger unavailable"); return
        }
        try #require(state.originals.allSatisfy { $0.readers.isEmpty })
        let evidence = try await seedEvidence(services)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let bytes = try encoder.encode(evidence)
        if creating { try bytes.write(to: manifestURL, options: .withoutOverwriting) }
        else {
            let previous = try JSONDecoder().decode(SeedEvidence.self, from: Data(contentsOf: manifestURL))
            try #require(evidence.hasSameStableIdentity(as: previous))
        }
        print("S16_SEED_EVIDENCE " + String(decoding: bytes, as: UTF8.self))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_LIBRARY_VERIFY"] == "1"))
    func verifySeedIdentityAndReleasedReadersAfterUI() async throws {
        let services = try await ProductLibraryFactory.shared.open()
        let file = services.run.url.appendingPathComponent("s16v2-test-seed-evidence.json")
        let original = try JSONDecoder().decode(SeedEvidence.self, from: Data(contentsOf: file))
        let current = try await seedEvidence(services)
        try #require(current.hasSameStableIdentity(as: original))
        guard case .succeeded(let state) = await services.store.loadOriginalState() else {
            Issue.record("Post UI ledger unavailable"); return
        }
        try #require(state.originals.allSatisfy { $0.readers.isEmpty })
        print("S16_POST_UI_IDENTITY_MATCH previousRoot=\(original.root) previousContainer=\(original.container) currentRoot=\(current.root) currentContainer=\(current.container) bundle=\(Bundle.main.bundleIdentifier ?? "missing") readers=0 digest=\(current.digest)")
    }
}

nonisolated private struct SeedEvidence: Codable, Equatable {
    let root: String
    let container: String
    let bindings: [OriginalBinding]
    let digest: String
    let byteCount: UInt64
    let videoDuration: Double
    let audioDuration: Double
    let audioTracks: Int
    let removalEvidence: String

    /// Installation can move the data container while retaining its contents.
    /// Physical URLs remain observations; only the normal relative product root
    /// and exact persisted/media identities participate in the continuity check.
    func hasSameStableIdentity(as previous: Self) -> Bool {
        hasNormalProductRoot && previous.hasNormalProductRoot
            && bindings == previous.bindings && digest == previous.digest
            && byteCount == previous.byteCount && videoDuration == previous.videoDuration
            && audioDuration == previous.audioDuration && audioTracks == previous.audioTracks
            && removalEvidence == previous.removalEvidence
    }

    private var hasNormalProductRoot: Bool {
        let expected = URL(fileURLWithPath: container, isDirectory: true)
            .appendingPathComponent("Library/Application Support/FrameRelayLibrary", isDirectory: true)
        return URL(fileURLWithPath: root).standardizedFileURL.path == expected.standardizedFileURL.path
    }
}

nonisolated private func seedEvidence(_ services: ProductLibraryServices) async throws -> SeedEvidence {
    try #require(Bundle.main.bundleIdentifier == "com.oyabu.FrameRelay")
    guard case .succeeded(let state) = await services.store.loadOriginalState(),
          let playable = state.originals.first(where: { $0.binding.original.capture.rawValue == "s16v2-original" })?.binding else {
        throw BackendContractError.unavailable
    }
    let bindingIDs = Set(["s16v2-original", "s16v2-cleanup", "s16v2-discard"])
    let bindings = state.originals.map(\.binding).filter { bindingIDs.contains($0.original.capture.rawValue) }
        .sorted { $0.original.capture.rawValue < $1.original.capture.rawValue }
    try #require(Set(bindings.map { $0.original.capture.rawValue }) == bindingIDs)
    let digest = try await services.originals.digest(for: playable.reference)
    try #require(digest.sha256 == playable.original.content.digest)
    try #require(digest.byteCount == playable.original.content.byteCount)
    try #require(playable.saveRecord.result == .unknown(.evidenceMissing))
    let asset = AVURLAsset(url: try await services.originals.existingURL(for: playable.reference))
    let videos = try await asset.loadTracks(withMediaType: .video)
    let audios = try await asset.loadTracks(withMediaType: .audio)
    let video = try #require(videos.first)
    let audio = try #require(audios.first)
    let videoDuration = try await video.load(.timeRange).duration.seconds
    let audioDuration = try await audio.load(.timeRange).duration.seconds
    try #require(videoDuration == 30)
    try #require(audioDuration == 30)
    try #require(audios.count == 1)
    return .init(root: services.run.url.path, container: NSHomeDirectory(),
        bindings: bindings,
        digest: digest.sha256, byteCount: digest.byteCount, videoDuration: videoDuration,
        audioDuration: audioDuration, audioTracks: audios.count,
        removalEvidence: "test-only projection seed; not product cleanup/discard success")
}

nonisolated private func seedMovie(_ name: String, services: ProductLibraryServices) async throws -> OriginalBinding {
    let fixture = try CaptureFixture(clip: name)
    let coordinator = OriginalSaveCoordinator(store: services.store, originals: services.originals,
        inspection: AVOriginalInspectionAdapter(originals: services.originals))
    guard case .ready = await coordinator.begin(fixture.intent, token: fixture.token(1)) else {
        throw CaptureContractError.wrongStage
    }
    let url = try await services.originals.reservedURL(for: fixture.intent.original)
    print("S16_SEED_MOVIE_BEGIN capture=\(name) url=\(url.path) durationSeconds=30")
    try await SyntheticMovieFixture.write(to: url, withAudio: true, durationSeconds: 30)
    print("S16_SEED_MOVIE_COMPLETE capture=\(name)")
    _ = await coordinator.recordingEnded(context: fixture.context, evidence: fixture.end)
    let digest = try await services.originals.digest(for: fixture.intent.original)
    let file = CaptureFileEvidence(context: fixture.context, original: fixture.intent.original,
                                  byteCount: digest.byteCount, finalizedAt: fixture.time)
    guard case .committed(let result, _) = await coordinator.fileFinalized(file, resultToken: fixture.token(4)),
          case .unknown = result.result,
          case .succeeded(let binding) = await services.access.bind(fixture.intent.original,
              operation: .init(rawValue: "seed-bind-" + name)) else { throw CaptureContractError.evidenceMismatch }
    return binding
}

/// This bypasses product deletion to prepare projection cases. It is NOT proof
/// that cleanup eligibility, confirmation, or the product deletion flow works.
nonisolated private func seedRemovalProjection(_ binding: OriginalBinding, purpose: RemovalPurpose,
                                               services: ProductLibraryServices) async throws {
    guard case .succeeded(let before) = await services.store.loadOriginalState(),
          let state = before.originals.first(where: { $0.binding.original == binding.original }) else {
        throw BackendContractError.unavailable
    }
    let intent = RemovalIntent(operation: .init(rawValue: "seed-removal-" + binding.original.capture.rawValue),
                               original: binding.original, purpose: purpose)
    guard case .committed(let receipt) = await services.store.commitOriginal(.init(operation: intent.operation,
        expectedRevision: before.revision, change: .reserveRemoval(intent,
        expectedInvalidation: state.invalidationGeneration, expectedAccess: state.accessGeneration))) else {
        throw BackendContractError.notCommitted
    }
    let url = try await services.originals.existingURL(for: binding.reference)
    try FileManager.default.removeItem(at: url) // Only the synthetic Movie just created above.
    guard case .committed = await services.store.commitOriginal(.init(
        operation: .init(rawValue: "seed-resolution-" + binding.original.capture.rawValue),
        expectedRevision: receipt.committedRevision, change: .resolveRemoval(intent, .removed))) else {
        throw BackendContractError.notCommitted
    }
}
