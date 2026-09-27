import Foundation
import Testing
@testable import FrameRelay

struct ManagedOriginalStoreTests {
    @Test func rejectsEscapeReferencesAndPersistentReservationReuse() async throws {
        try await withStorageRun { run in
            let originals = ManagedOriginalStore(run: run)
            for invalid in ["../outside", "/absolute", "a/b", "a\\b", ".", "", "a.mov"] {
                await #expect(throws: ExplorationStorageError.invalidReference) {
                    try await originals.reserve(original: .init(rawValue: invalid))
                }
            }
            let reference = CaptureOriginalReference(rawValue: "synthetic-original-A")
            let url = try await originals.reserve(original: reference)
            #expect(url.deletingLastPathComponent() == run.url)
            await #expect(throws: ExplorationStorageError.alreadyExists) {
                try await ManagedOriginalStore(run: run).reserve(original: reference)
            }
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test func rejectsSymlinksAndExistingMediaWithoutChangingThem() async throws {
        try await withStorageRun { run in
            let store = ManagedOriginalStore(run: run)
            let existing = CaptureOriginalReference(rawValue: "existing-synthetic")
            let existingURL = run.url.appendingPathComponent(existing.rawValue + ".mov")
            let bytes = Data("synthetic-only".utf8)
            try bytes.write(to: existingURL, options: .withoutOverwriting)
            await #expect(throws: ExplorationStorageError.alreadyExists) { try await store.reserve(original: existing) }
            #expect(try Data(contentsOf: existingURL) == bytes)
            let linked = CaptureOriginalReference(rawValue: "linked-synthetic")
            let link = try await store.reserve(original: linked)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: existingURL)
            await #expect(throws: ExplorationStorageError.unsafePath) { try await store.existingURL(for: linked) }
            await #expect(throws: ExplorationStorageError.unsafePath) { try await store.digest(for: linked) }
        }
    }

    @Test func boundedHashIdentifiesBytesAndRejectsInaccessibleOriginal() async throws {
        try await withStorageRun { run in
            let store = ManagedOriginalStore(run: run)
            let first = CaptureOriginalReference(rawValue: "synthetic-one")
            let second = CaptureOriginalReference(rawValue: "synthetic-two")
            let firstURL = try await store.reserve(original: first)
            let secondURL = try await store.reserve(original: second)
            try Data("abc".utf8).write(to: firstURL, options: .withoutOverwriting)
            try Data("abd".utf8).write(to: secondURL, options: .withoutOverwriting)
            let one = try await store.digest(for: first)
            let two = try await store.digest(for: second)
            #expect(one.byteCount == 3)
            #expect(one.sha256 == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
            #expect(one.sha256 != two.sha256)
            #expect(try await store.byteCount(for: first) == 3)
            let absent = CaptureOriginalReference(rawValue: "synthetic-absent")
            _ = try await store.reserve(original: absent)
            await #expect(throws: ExplorationStorageError.inaccessible) { try await store.digest(for: absent) }
        }
    }

    @Test func arbitraryBytesNeverBecomeVerifiedMedia() async throws {
        try await withStorageRun { run in
            let fixture = try CaptureFixture()
            let originals = ManagedOriginalStore(run: run)
            let url = try await originals.reserve(original: fixture.intent.original)
            try Data("not-a-media-file-synthetic".utf8).write(to: url, options: .withoutOverwriting)
            let inspector = AVOriginalInspectionAdapter(originals: originals)
            let result = await inspector.inspect(.init(token: fixture.token(4), original: fixture.intent.original))
            guard case .unavailable(let token, _) = result else {
                Issue.record("Arbitrary bytes must not be accepted as inspected media")
                return
            }
            #expect(token == fixture.token(4))
            #expect(await inspector.observation(for: fixture.intent.original) == nil)
        }
    }
}
