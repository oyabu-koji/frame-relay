import Foundation
import Testing
@testable import FrameRelay

/// Explicit, test-target-only data for the dedicated removal Simulator. The
/// normal App has no fixture argument, success injection or seed branch.
@Suite(.serialized)
struct ProductRemovalSeedTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_REMOVAL_SEED"] == "1"))
    func seedDedicatedNormalRoot() async throws {
        let token = try removalSeedToken()
        let services = try await ProductLibraryFactory.shared.open()
        guard case .loaded(let before) = await services.reader.loadLibrary() else {
            Issue.record("Cannot read the normal product root"); return
        }
        // This refusal protects the existing CF/s16 seed and every other root.
        try #require(before.items.isEmpty)
        let file = services.run.url.appendingPathComponent("s34-removal-seed.json")
        try #require(!FileManager.default.fileExists(atPath: file.path))
        let fixture = OriginalRemovalFixture(run: services.run, store: services.store,
            files: services.originals, access: services.access)
        let prefix = "s34r-" + token
        let discard = try await fixture.original(prefix + "-discard", unknown: true)
        let cleanup = try await fixture.original(prefix + "-cleanup")
        let pending = try await fixture.original(prefix + "-pending", unknown: true)
        let keep = try await fixture.original(prefix + "-keep", unknown: true)
        // Only this Unit fixture supplies synthetic saved/remote/played facts.
        // The normal cleanup start remains unavailable; no real Log, remote
        // result, Photos action or accepted Rec.709 quality is claimed.
        _ = try await fixture.evidence(cleanup, schema: "fr-final-read-v1")
        let cleanupBatch = try fixture.batch([cleanup], name: "s34-seed-cleanup-" + token)
        guard case .succeeded(let cleaned) = await fixture.coordinator().start(cleanupBatch) else {
            Issue.record("S32 core must perform the actual fixture unlink"); return
        }
        try #require(cleaned.targets.first?.status == .resolved(.removed))
        let pendingBatch = try fixture.discardBatch(pending, name: "s34-seed-pending-" + token)
        let snapshot = try await mediaOriginalSnapshot(services.store)
        guard case .committed = await services.store.commitOriginal(.init(operation: pendingBatch.operation,
            expectedRevision: snapshot.revision, change: .removalBatch(pendingBatch))) else {
            throw BackendContractError.notCommitted
        }
        try await mediaReconcile(services.store, original: pending.original)
        _ = try await mediaOriginalCommit(services.store, .reserveRemoval(pendingBatch.intent(for: pendingBatch.targets[0]),
            expectedInvalidation: .init(rawValue: 0), expectedAccess: .init(rawValue: 0)))
        let sentinel = services.run.url.deletingLastPathComponent().appendingPathComponent("s34-external-" + token + ".mov")
        let discardBytes = try Data(contentsOf: await services.originals.existingURL(for: discard.reference))
        try discardBytes.write(to: sentinel, options: .withoutOverwriting)
        let manifest = RemovalSeedManifest(token: token, bindings: [discard, cleanup, pending, keep],
            cleanup: cleaned, pending: pendingBatch, externalContent: try renditionContent(discardBytes))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: file, options: .withoutOverwriting)
        guard case .loaded(let library) = await services.reader.loadLibrary() else { throw BackendContractError.unavailable }
        try #require(library.history.isEmpty)
        try #require(library.recordings.count == 4)
        try #require(library.recordings.contains(where: { $0.id == cleanup.original.capture && $0.removal == .removed(.cleanup) }))
        try #require(library.recordings.contains(where: { $0.id == pending.original.capture && $0.removal == .reconciliationRequired(.discard) }))
        print("S34_REMOVAL_SEED token=\(token) root=normal cleanup=actual-S32-unlink pending=reserved history=0")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_REMOVAL_VERIFY"] == "1"))
    func verifyDedicatedUIResultAndUntouchedData() async throws {
        let token = try removalSeedToken()
        let services = try await ProductLibraryFactory.shared.open()
        let file = services.run.url.appendingPathComponent("s34-removal-seed.json")
        let manifest = try JSONDecoder().decode(RemovalSeedManifest.self, from: Data(contentsOf: file))
        try #require(manifest.token == token)
        let state = try await mediaOriginalSnapshot(services.store)
        let byID = Dictionary(uniqueKeysWithValues: manifest.bindings.map { ($0.original.capture.rawValue, $0) })
        let prefix = "s34r-" + token
        let discard = try #require(byID[prefix + "-discard"])
        let cleanup = try #require(byID[prefix + "-cleanup"])
        let pending = try #require(byID[prefix + "-pending"])
        let keep = try #require(byID[prefix + "-keep"])
        try #require(state.originals.count == 4)
        for binding in manifest.bindings {
            try #require(state.originals.first(where: { $0.binding.original == binding.original })?.binding == binding)
        }
        try #require(await services.originals.observeFile(discard.reference) == .absent)
        try #require(await services.originals.observeFile(cleanup.reference) == .absent)
        try #require(state.originals.first(where: { $0.binding == discard })?.removalResolution == .removed)
        try #require(state.originals.first(where: { $0.binding == discard })?.resolvedRemoval?.purpose == .discard)
        try #require(state.removalBatches.contains(where: { $0.batch == manifest.pending
            && $0.targets.first?.status == .reserved(manifest.pending.intent(for: manifest.pending.targets[0])) }))
        try #require(state.removalBatches.contains(where: { $0.batch == manifest.cleanupBatch && $0.targets.first?.status == .resolved(.removed) }))
        for binding in [pending, keep] {
            let digest = try await services.originals.digest(for: binding.reference)
            try #require(digest.sha256 == binding.original.content.digest && digest.byteCount == binding.original.content.byteCount)
        }
        try #require(state.logicalOriginals.allSatisfy { $0.readers.isEmpty && $0.mediaReaders.isEmpty })
        let sentinel = services.run.url.deletingLastPathComponent().appendingPathComponent("s34-external-" + token + ".mov")
        try #require(try renditionContent(Data(contentsOf: sentinel)) == manifest.externalContent)
        guard case .loaded(let library) = await services.reader.loadLibrary() else { throw BackendContractError.unavailable }
        try #require(library.history.map(\.id) == [discard.original.capture])
        try #require(library.recordings.contains(where: { $0.id == cleanup.original.capture && $0.removal == .removed(.cleanup) }))
        try #require(library.recordings.contains(where: { $0.id == pending.original.capture && $0.removal == .reconciliationRequired(.discard) }))
        try #require(!library.recordings.contains(where: { $0.id == discard.original.capture }))
        print("S34_REMOVAL_VERIFY token=\(token) bindings=4 discard=UI-unlink cleanup=S32-unlink pending=unchanged keep=hash-match external=hash-match readers=0")
    }
}

nonisolated private struct RemovalSeedManifest: Codable {
    let token: String
    let bindings: [OriginalBinding]
    let cleanupBatch: OriginalRemovalBatch
    let pending: OriginalRemovalBatch
    let externalContent: ContentIdentity

    init(token: String, bindings: [OriginalBinding], cleanup: OriginalRemovalBatchRecord,
         pending: OriginalRemovalBatch, externalContent: ContentIdentity) {
        self.token = token; self.bindings = bindings; cleanupBatch = cleanup.batch
        self.pending = pending; self.externalContent = externalContent
    }
}

nonisolated private func removalSeedToken() throws -> String {
    let input = ProcessInfo.processInfo.environment["FR_REMOVAL_SEED_TOKEN"] ?? ""
    let uuid = try #require(UUID(uuidString: input))
    try #require(uuid.uuidString.lowercased() == input.lowercased())
    return uuid.uuidString.lowercased()
}
