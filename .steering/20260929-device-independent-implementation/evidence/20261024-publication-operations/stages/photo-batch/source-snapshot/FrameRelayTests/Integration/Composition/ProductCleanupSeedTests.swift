import Foundation
import Testing
@testable import FrameRelay

/// Opt-in, test-target-only setup of a fresh dedicated Simulator's real product
/// root. The product App receives no fixture flag, command or success injection.
@Suite(.serialized) @MainActor struct ProductCleanupSeedTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_CLEANUP_SEED"] == "1"))
    func seedFreshDedicatedNormalRoot() async throws {
        let token = try cleanupSeedToken()
        let services = try await ProductLibraryFactory.shared.open()
        guard case .loaded(let initial) = await services.reader.loadLibrary() else { throw BackendContractError.unavailable }
        try #require(initial.items.isEmpty)
        let file = services.run.url.appendingPathComponent("s34-cleanup-seed.json")
        try #require(!FileManager.default.fileExists(atPath: file.path))
        let fixture = try await CleanupCompositionFixture.make(library: .shared)
        let prefix = "s34c-" + token
        let a = try await fixture.add(prefix + "-a")
        let b = try await fixture.add(prefix + "-b")
        let missing = try await fixture.add(prefix + "-missing", evidence: false)
        let keep = try await fixture.originals.original(prefix + "-keep", unknown: true)
        let external = cleanupSentinel(services, token: token)
        let data = try Data(contentsOf: await services.originals.existingURL(for: keep.reference))
        try data.write(to: external, options: .withoutOverwriting)
        let backend = try await mediaSnapshot(services.store)
        try #require(backend.photoRegistrations.isEmpty)
        let encoder = cleanupSeedEncoder()
        let manifest = CleanupSeedManifest(token: token, bindings: [a.binding, b.binding, missing.binding, keep],
            externalContent: try renditionContent(data), verification: try encoder.encode(backend.verifications),
            confirmation: try encoder.encode(backend.confirmations), photoRegistrationCount: backend.photoRegistrations.count,
            requests: try encoder.encode(backend.requests))
        try encoder.encode(manifest).write(to: file, options: .withoutOverwriting)
        let before = try await mediaOriginalSnapshot(services.store)
        try #require(before.originals.count == 4 && before.removalBatches.isEmpty)
        try #require(before.logicalOriginals.allSatisfy { $0.readers.isEmpty && $0.mediaReaders.isEmpty })
        guard case .loaded(let library) = await services.reader.loadLibrary() else { throw BackendContractError.unavailable }
        try #require(library.history.isEmpty && library.recordings.count == 4)
        try #require(library.items.filter { $0.cleanupUnavailableReason == nil }.count == 2)
        try await fixture.close()
        print("S34_CLEANUP_SEED token=\(token) bindings=4 eligible=2 missing=1 keep=1 root=normal synthetic-proof-and-SDK real-MOV-and-own-FD-closure no-network")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_CLEANUP_VERIFY"] == "1"))
    func verifyUIBatchRealFilesAndUntouchedEvidenceAfterReopen() async throws {
        let token = try cleanupSeedToken()
        let services = try await ProductLibraryFactory.shared.open()
        let file = services.run.url.appendingPathComponent("s34-cleanup-seed.json")
        let initialBytes = try Data(contentsOf: file)
        let manifest = try JSONDecoder().decode(CleanupSeedManifest.self, from: initialBytes)
        try #require(manifest.token == token)
        let state = try await mediaOriginalSnapshot(services.store)
        let backend = try await mediaSnapshot(services.store)
        let prefix = "s34c-" + token
        let bindings = Dictionary(uniqueKeysWithValues: manifest.bindings.map { ($0.original.capture.rawValue, $0) })
        let a = try #require(bindings[prefix + "-a"])
        let b = try #require(bindings[prefix + "-b"])
        let missing = try #require(bindings[prefix + "-missing"])
        let keep = try #require(bindings[prefix + "-keep"])
        try #require(state.originals.count == 4 && state.removalBatches.count == 1)
        let batch = try #require(state.removalBatches.first)
        try #require(batch.batch.purpose == .cleanup && batch.batch.authorization == .cleanup)
        try #require(batch.batch.targets.map(\.original.capture) == [a.original.capture, b.original.capture, missing.original.capture])
        try #require(Set(batch.batch.targets.map(\.operation)).count == 3)
        for binding in manifest.bindings {
            try #require(state.originals.first(where: { $0.binding.original == binding.original })?.binding == binding)
        }
        for binding in [a, b] {
            try #require(await services.originals.observeFile(binding.reference) == .absent)
            try #require(state.originals.first(where: { $0.binding == binding })?.removalResolution == .removed)
            try #require(batch.targets.first(where: { $0.target.original == binding.original })?.status == .resolved(.removed))
        }
        try #require(batch.targets.first(where: { $0.target.original == missing.original })?.status == .notExecuted(.ineligible))
        for binding in [missing, keep] {
            let digest = try await services.originals.digest(for: binding.reference)
            try #require(digest.sha256 == binding.original.content.digest && digest.byteCount == binding.original.content.byteCount)
        }
        let encoder = cleanupSeedEncoder()
        try #require(encoder.encode(backend.verifications) == manifest.verification)
        try #require(encoder.encode(backend.confirmations) == manifest.confirmation)
        try #require(manifest.photoRegistrationCount == 0 && backend.photoRegistrations.isEmpty)
        try #require(encoder.encode(backend.requests) == manifest.requests)
        try #require(renditionContent(Data(contentsOf: cleanupSentinel(services, token: token))) == manifest.externalContent)
        try #require(state.logicalOriginals.allSatisfy { $0.readers.isEmpty && $0.mediaReaders.isEmpty })
        guard case .loaded(let library) = await services.reader.loadLibrary() else { throw BackendContractError.unavailable }
        try #require(library.recordings.count == 4 && library.history.isEmpty)
        try #require(library.items.filter { $0.removal == .removed(.cleanup) }.map(\.id) == [a.original.capture, b.original.capture])
        try #require(Data(contentsOf: file) == initialBytes)
        print("S34_CLEANUP_VERIFY token=\(token) bindings=4 batch=\(batch.batch.operation.rawValue) fixedTargets=3 removed=2 ineligible=1 keep=hash-match originalReaders=0 mediaReaders=0 external=hash-match evidence=unchanged manifest=unchanged history=0")
    }
}

nonisolated private struct CleanupSeedManifest: Codable {
    let token: String
    let bindings: [OriginalBinding]
    let externalContent: ContentIdentity
    let verification: Data
    let confirmation: Data
    let photoRegistrationCount: Int
    let requests: Data
}

nonisolated private func cleanupSeedToken() throws -> String {
    let input = ProcessInfo.processInfo.environment["FR_CLEANUP_SEED_TOKEN"] ?? ""
    let uuid = try #require(UUID(uuidString: input))
    try #require(uuid.uuidString.lowercased() == input.lowercased())
    return uuid.uuidString.lowercased()
}

nonisolated private func cleanupSeedEncoder() -> JSONEncoder {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    return encoder
}

nonisolated private func cleanupSentinel(_ services: ProductLibraryServices, token: String) -> URL {
    services.run.url.deletingLastPathComponent().appendingPathComponent("s34-cleanup-external-" + token + ".mov")
}
