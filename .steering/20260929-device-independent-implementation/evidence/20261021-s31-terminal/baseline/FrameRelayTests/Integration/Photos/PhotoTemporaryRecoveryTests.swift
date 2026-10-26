import Darwin
import Foundation
import Testing
@testable import FrameRelay

struct PhotoTemporaryRecoveryTests {
    @Test func newLocalNamesUseOnlyTheDeclaredContainerSuffix() async throws {
        for (mime, suffix) in [("video/quicktime", "mov"), ("video/mp4", "mp4")] {
            let leaf = try TemporaryMediaLeaf.make(contentType: mime)
            try TemporaryMediaLeaf.validate(leaf, contentType: mime)
            #expect(URL(fileURLWithPath: leaf).pathExtension == suffix)
            #expect(UUID(uuidString: String(leaf.dropLast(suffix.count + 1)))?.uuidString == String(leaf.dropLast(suffix.count + 1)))
        }
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run)
            let state = try await f.rendition.temporary.stateFor(f.receipt.id)
            #expect(state.leaf.hasSuffix(".mov") && state.contentType == "video/quicktime")
            let local = try await f.rendition.temporary.resolvePhotoMedia(f.receipt.usage)
            #expect(local.url.lastPathComponent == state.leaf && local.contentType == state.contentType)
            try await f.rendition.temporary.finishPhotoMedia(f.receipt.usage)
        }
    }

    @Test func legacyUUIDOnlyFileReopensAndReadsWithoutRenameOrContentChange() async throws {
        try await withStorageRun { run in
            let seed = try await photoLegacyTemporarySeed(run)
            let store = try photoRecoveryStore(run)
            let leases = RenditionReadLeases(store: store)
            let scope = try await RenditionMediaScope.open(original: seed.state.rendition.original, leases: leases)
            let owner = try await ManagedTemporaryMedia.open(root: run.url.appendingPathComponent("temporary"), leases: leases, scope: scope)
            guard case .succeeded(let inspected) = await owner.inspect(seed.state.id) else { Issue.record("Legacy media unreadable"); return }
            #expect(inspected.verifiedContent == seed.state.rendition.deliveryContent)
            guard case .succeeded(let usage) = await owner.acquireUsage(seed.state.id, purpose: .playback,
                usageID: .init(rawValue: "new-process-legacy-read")) else { Issue.record("Legacy read use denied"); return }
            #expect(try await owner.read(usage, offset: 0, length: seed.bytes.count) == seed.bytes)
            #expect(await owner.releaseUsage(usage) == .succeeded(seed.state.id))
            let state = try await owner.stateFor(seed.state.id)
            #expect(state.leaf == seed.state.leaf && state.fileIdentity == seed.state.fileIdentity)
            #expect(state.usages.count == 1 && state.usages[0].usage.purpose == .photoHandoff)
            let url = run.url.appendingPathComponent("temporary").appendingPathComponent(state.leaf)
            #expect(try Data(contentsOf: url) == seed.bytes)
            #expect(!FileManager.default.fileExists(atPath: url.appendingPathExtension("mov").path))
        }
    }

    @Test func unsafeOrAmbiguousLeafAndMimeAreRejectedByTheCommonWriter() async throws {
        let uuid = "12345678-1234-ABCD-ABCD-123456789ABC"
        let invalid = ["../\(uuid).mov", "/\(uuid).mov", "\(uuid)/child.mov", "\(uuid).MOV",
            "\(uuid.lowercased()).mov", "\(uuid).mp4", "\(uuid).mov/", "\(uuid).mov.mov",
            "\(uuid).mov ", "\(uuid).mov\0", ".\(uuid).mov", "\(uuid).mOv"]
        try TemporaryMediaLeaf.validate(uuid, contentType: "video/quicktime")
        try TemporaryMediaLeaf.validate(uuid.lowercased(), contentType: "video/quicktime")
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run)
            let model = try await f.rendition.temporary.stateFor(f.receipt.id)
            let cases = invalid.map { ($0, "video/quicktime") }
                + ["Video/quicktime", "video/QuickTime", "video/mp4;codecs=avc1", "application/octet-stream"].map { (uuid, $0) }
            for (index, item) in cases.enumerated() {
                #expect(throws: BackendContractError.invalidValue) { try TemporaryMediaLeaf.validate(item.0, contentType: item.1) }
                let state = TemporaryMediaState(id: .init(rawValue: "rejected-leaf-\(index)"), rendition: model.rendition,
                    registration: model.registration, capturedAt: model.capturedAt, leaf: item.0,
                    contentType: item.1, directoryIdentity: model.directoryIdentity)
                let snapshot = try await mediaSnapshot(f.rendition.store)
                let mutation = BackendStoreMutation(expectedRevision: snapshot.revision,
                    change: .temporary(command: .init(rawValue: "rejected-create-\(index)"), value: .create(state)))
                #expect(await f.rendition.store.commit(mutation) == .rejected(.invalidValue))
                #expect(try await mediaSnapshot(f.rendition.store).revision == snapshot.revision)
            }
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func reopenedSuccessfulRegistrationReclaimsOnlyItsPersistedUsage(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let seed = try await photoRecoverySeed(run: run, candidate: candidate)
            let store = try photoRecoveryStore(run, candidate: candidate)
            let current = try #require(try await mediaSnapshot(store).photoRegistrations.last)
            let leases = RenditionReadLeases(store: store)
            let scope = try await RenditionMediaScope.open(original: seed.record.registration.intent.rendition.original, leases: leases)
            let owner = try await ManagedTemporaryMedia.open(root: run.url.appendingPathComponent("temporary"), leases: leases, scope: scope)
            let library = PhotoSaveLibrary()
            let coordinator = PhotoSaveCoordinator(store: store, identity: seed.identity, temporaryMedia: owner, library: library)
            guard case .succeeded(let records) = await coordinator.restore() else { Issue.record("Success was not recovered"); return }
            #expect(records.count == 1 && records[0].usageRelease != nil)
            let state = try await owner.stateFor(current.registration.intent.media)
            #expect(state.usages.isEmpty && state.releasedUsages.contains(current.registration.mediaUse) && state.reclaimed)
            #expect(try await owner.usageSnapshot(state.id).fileBytes == 0)
            #expect(try await mediaOriginalSnapshot(store).logicalOriginals.first?.mediaReaders.isEmpty == true)
            #expect(await owner.recoverSuccessfulPhotoUsage(current) == .succeeded(state.id))
            #expect(await library.requests.isEmpty)
            #expect(await library.additions.isEmpty)
            _ = try await scope.close()
        }
    }

    @Test func successfulPhotoRecoveryPreservesOtherOldEpochPlaybackUsage() async throws {
        try await withStorageRun { run in
            let seed = try await photoRecoverySeed(run: run, keepPlayback: true)
            let store = try photoRecoveryStore(run)
            let leases = RenditionReadLeases(store: store)
            let scope = try await RenditionMediaScope.open(original: seed.record.registration.intent.rendition.original, leases: leases)
            let owner = try await ManagedTemporaryMedia.open(root: run.url.appendingPathComponent("temporary"), leases: leases, scope: scope)
            #expect(await owner.recoverSuccessfulPhotoUsage(seed.record) == .succeeded(seed.record.registration.intent.media))
            let state = try await owner.stateFor(seed.record.registration.intent.media)
            let other = try #require(state.usages.first)
            #expect(state.usages.count == 1 && other.usage.purpose == .playback)
            #expect(state.releasedUsages.contains(seed.record.registration.mediaUse))
            #expect(!state.reclaiming && !state.reclaimed)
            #expect(try await owner.usageSnapshot(state.id).fileBytes > 0)
            #expect(await owner.releaseUsage(other.usage) == .unknown)
            #expect(try await mediaOriginalSnapshot(store).logicalOriginals.first?.mediaReaders == [other.lease])
        }
    }

    @Test(arguments: [PhotoRegistrationOutcome.unknown(localIdentifier: nil), .failed(.rejected), .notAttempted(.authorizationRequired)])
    func nonSuccessIsNeverAnOldOwnerReleasePermit(outcome: PhotoRegistrationOutcome) async throws {
        try await withStorageRun { run in
            let seed = try await photoRecoverySeed(run: run, outcome: outcome)
            let store = try photoRecoveryStore(run)
            let leases = RenditionReadLeases(store: store)
            let scope = try await RenditionMediaScope.open(original: seed.record.registration.intent.rendition.original, leases: leases)
            let owner = try await ManagedTemporaryMedia.open(root: run.url.appendingPathComponent("temporary"), leases: leases, scope: scope)
            #expect(await owner.recoverSuccessfulPhotoUsage(seed.record) == .unknown)
            let state = try await owner.stateFor(seed.record.registration.intent.media)
            #expect(state.usages.contains(seed.record.registration.mediaUse) && !state.reclaiming)
            #expect(try await owner.usageSnapshot(state.id).fileBytes > 0)
        }
    }

    @Test(arguments: [false, true])
    func releaseCommitResponseLossRetainsExactMutationAndDefersUnlink(afterCommit: Bool) async throws {
        try await withStorageRun { run in
            let seed = try await photoRecoverySeed(run: run)
            let base = try photoRecoveryStore(run)
            let faults = await PhotoSaveFaultStore(base: base)
            await faults.configure(.releaseUsage, afterCommit: afterCommit)
            let leases = RenditionReadLeases(store: faults)
            let scope = try await RenditionMediaScope.open(original: seed.record.registration.intent.rendition.original, leases: leases)
            let owner = try await ManagedTemporaryMedia.open(root: run.url.appendingPathComponent("temporary"), leases: leases, scope: scope)
            #expect(await owner.recoverSuccessfulPhotoUsage(seed.record) == .unknown)
            let state = try await owner.stateFor(seed.record.registration.intent.media)
            #expect(FileManager.default.fileExists(atPath: run.url.appendingPathComponent("temporary").appendingPathComponent(state.leaf).path))
            #expect(state.usages.isEmpty == afterCommit)
            #expect((try await mediaSnapshot(base).photoRegistrations.last?.usageRelease != nil) == afterCommit)
            await faults.configure()
            if afterCommit {
                #expect(await owner.recoverSuccessfulPhotoUsage(seed.record) == .succeeded(state.id))
                #expect(try await owner.usageSnapshot(state.id).fileBytes == 0)
            } else {
                // No new revision or command is submitted for an uncertain
                // in-memory mutation, even though the file remains intact.
                #expect(await owner.recoverSuccessfulPhotoUsage(seed.record) == .unknown)
                #expect(await faults.photoCommits.count == 1)
            }
        }
    }

    @Test func openPhotoConsumerAndForgedSuccessCannotReleaseTheActualUse() async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run)
            let intentOnly = try await f.commitIntent()
            _ = try await f.rendition.temporary.resolvePhotoMedia(f.receipt.usage)
            // Deliberately hostile caller bypasses the coordinator's producer
            // contract; the local owner still knows its SDK handle is open.
            let result = PhotoRegistrationResult(intent: intentOnly.registration.intent,
                outcome: .succeeded(localIdentifier: try .init(rawValue: "forged-terminal")))
            let snapshot = try await mediaSnapshot(f.rendition.store)
            let mutation = BackendStoreMutation(expectedRevision: snapshot.revision,
                change: .photo(command: .init(rawValue: "hostile-result"), value: .result(result)), expectedStoreIdentity: f.identity)
            guard case .committed = await f.rendition.store.commit(mutation) else { Issue.record("Fixture result not committed"); return }
            let current = try await f.latest()
            #expect(await f.rendition.temporary.recoverSuccessfulPhotoUsage(current) == .unknown)
            #expect(try await f.rendition.temporary.usageSnapshot(f.receipt.id).openHandles == 1)
            var altered = current
            altered.results.removeAll()
            #expect(await f.rendition.temporary.recoverSuccessfulPhotoUsage(altered) == .unknown)
            #expect(try await f.rendition.temporary.stateFor(f.receipt.id).usages.contains(current.registration.mediaUse))
            try await f.rendition.temporary.finishPhotoMedia(f.receipt.usage)
        }
    }

    @Test func globalRestoreSkipsAnotherOriginalWhileRecoveringItsOwnSuccess() async throws {
        try await withStorageRun { run in
            let seed = try await photoRecoverySeed(run: run, secondOriginal: true)
            let store = try photoRecoveryStore(run)
            let leases = RenditionReadLeases(store: store)
            let scope = try await RenditionMediaScope.open(original: seed.record.registration.intent.rendition.original, leases: leases)
            let owner = try await ManagedTemporaryMedia.open(root: run.url.appendingPathComponent("temporary"), leases: leases, scope: scope)
            let library = PhotoSaveLibrary()
            let coordinator = PhotoSaveCoordinator(store: store, identity: seed.identity, temporaryMedia: owner, library: library)
            guard case .succeeded(let records) = await coordinator.restore() else { Issue.record("Unrelated success blocked recovery"); return }
            #expect(records.count == 2)
            let mine = try #require(records.first { $0.registration.intent == seed.record.registration.intent })
            let other = try #require(records.first { $0.registration.intent != seed.record.registration.intent })
            #expect(mine.usageRelease != nil && other.usageRelease == nil)
            #expect(await owner.recoverSuccessfulPhotoUsage(other) == .notExecuted)
            let otherState = try #require(try await mediaSnapshot(store).temporaryMedia.first { $0.id == other.registration.intent.media })
            #expect(otherState.usages.contains(other.registration.mediaUse) && !otherState.reclaimed)
            #expect(await library.requests.isEmpty)
            #expect(await library.additions.isEmpty)
        }
    }
}

private nonisolated struct PhotoLegacyTemporarySeed: Sendable {
    let state: TemporaryMediaState
    let bytes: Data
}

/// Explicitly constructs a disposable old-format cache record and file. It
/// never migrates an existing file and asserts no actual movie/Rec.709 format.
private nonisolated func photoLegacyTemporarySeed(_ run: ExplorationRunDirectory) async throws -> PhotoLegacyTemporarySeed {
    let bytes = Data(repeating: 9, count: 64)
    let f = try await RenditionFixture.make(run: run, content: renditionContent(bytes))
    let root = run.url.appendingPathComponent("temporary")
    var rootInfo = stat()
    guard lstat(root.path, &rootInfo) == 0 else { throw BackendContractError.unavailable }
    let state = TemporaryMediaState(id: .init(rawValue: "legacy-uuid-only"), rendition: f.command.distribution.rendition,
        registration: f.command.distribution.registration, capturedAt: RenditionFixture.capturedAt,
        leaf: UUID().uuidString.lowercased(), contentType: "video/quicktime",
        directoryIdentity: .init(device: Int64(rootInfo.st_dev), inode: UInt64(rootInfo.st_ino)))
    _ = try await mediaCommit(f.store, .temporary(command: .init(rawValue: "legacy-cache-create"), value: .create(state)))
    let url = root.appendingPathComponent(state.leaf)
    try Data().write(to: url, options: .withoutOverwriting)
    var fileInfo = stat()
    guard lstat(url.path, &fileInfo) == 0 else { throw BackendContractError.unavailable }
    _ = try await mediaCommit(f.store, .temporary(command: .init(rawValue: "legacy-file-created"),
        value: .fileCreated(state.id, .init(device: Int64(fileInfo.st_dev), inode: UInt64(fileInfo.st_ino)))))
    guard case .succeeded(let writer) = await f.temporary.acquireUsage(state.id, purpose: .playback,
        usageID: .init(rawValue: "legacy-writer")) else { throw BackendContractError.unavailable }
    try await f.temporary.store(bytes, range: .init(lowerBound: 0, upperBound: UInt64(bytes.count)), using: writer)
    _ = try await f.temporary.verify(writer)
    guard case .succeeded = await f.temporary.acquireUsage(state.id, purpose: .photoHandoff,
        usageID: .init(rawValue: "legacy-unresolved-photo")) else { throw BackendContractError.unavailable }
    guard await f.temporary.releaseUsage(writer) == .succeeded(state.id) else { throw BackendContractError.unavailable }
    return .init(state: try await f.temporary.stateFor(state.id), bytes: bytes)
}

private nonisolated struct PhotoRecoverySeed: Sendable {
    let record: PhotoRegistrationRecord
    let identity: RegistrationStoreIdentity
}

/// Returning values releases the old object graph. Opening the next owner must
/// actually acquire the kernel root lock; absence is not inferred from a list.
private nonisolated func photoRecoverySeed(run: ExplorationRunDirectory, candidate: StorageCandidate = .sqlite,
                                           keepPlayback: Bool = false,
                                           outcome: PhotoRegistrationOutcome = .succeeded(localIdentifier: nil),
                                           secondOriginal: Bool = false) async throws -> PhotoRecoverySeed {
    let f = try await PhotoSaveFixture.make(run: run, candidate: candidate, keepPlayback: keepPlayback)
    await f.media.configure(releaseBlocked: true)
    await f.library.configure(outcome: outcome)
    _ = await f.coordinator.save(f.receipt, action: .init(rawValue: "committed-before-process-ended"))
    let record = try await f.latest()
    if secondOriginal { try await photoOtherOriginal(run: run, store: f.rendition.store, identity: f.identity) }
    return .init(record: record, identity: f.identity)
}

private nonisolated func photoRecoveryStore(_ run: ExplorationRunDirectory,
                                            candidate: StorageCandidate = .sqlite) throws -> any MediaDiskStore {
    candidate == .sqlite ? try SQLiteRecordingStore(run: run, mode: .openExisting)
        : try AtomicFileRecordingStore(run: run, mode: .openExisting)
}

private nonisolated func photoOtherOriginal(run: ExplorationRunDirectory, store: any MediaDiskStore,
                                           identity: RegistrationStoreIdentity) async throws {
    let bytes = Data(repeating: 7, count: 64)
    let content = try renditionContent(bytes)
    let original = OriginalContent(capture: .init(rawValue: "s31-other-original"), generation: .init(rawValue: 1), content: content)
    let rendition = RenditionIdentity(original: original, inputLogIdentity: "technical-fixture",
        transformAssetIdentity: "not-quality-proof", transformAssetVersion: "fixture",
        outputConfigurationIdentity: "fixture", conversionVersion: "fixture",
        rendition: .init(rawValue: "s31-other-rendition"), deliveryContent: content, publicationGeneration: .init(rawValue: 1))
    let registration = try #require(try await mediaSnapshot(store).registrations.last?.server.registration)
    _ = try await mediaCommit(store, .publication(mediaPublication(rendition, registration: registration)))
    let operation = MediaOperationID(rawValue: "s31-other-fixture-distribution")
    let command = RetrieveMediaCommand(gate: .init(operation: operation, attempt: .init(rawValue: "fixture"),
        target: .rendition(rendition), registration: registration, generation: 1),
        distribution: .init(operation: operation, rendition: rendition, registration: registration,
            commit: .init(key: .distribution(operation, rendition, registration), previousRevision: 0, committedRevision: 1)), range: nil)
    let leases = RenditionReadLeases(store: store)
    let scope = try await RenditionMediaScope.open(original: original, leases: leases)
    let owner = try await ManagedTemporaryMedia.open(root: run.url.appendingPathComponent("temporary-other"), leases: leases, scope: scope)
    let created = try await owner.create(command: command, id: .init(rawValue: "s31-other-media"),
        usageID: .init(rawValue: "other-playback"), capturedAt: RenditionFixture.capturedAt, contentType: "video/quicktime")
    try await owner.store(bytes, range: .init(lowerBound: 0, upperBound: 64), using: created.usage)
    _ = try await owner.verify(created.usage)
    guard case .succeeded(let use) = await owner.acquireUsage(created.id, purpose: .photoHandoff,
        usageID: .init(rawValue: "other-photo")) else { throw BackendContractError.unavailable }
    _ = await owner.releaseUsage(created.usage)
    let receipt = try await owner.stateFor(created.id).receipt(for: use)
    let media = PhotoSaveMedia(base: owner)
    await media.configure(releaseBlocked: true)
    let coordinator = PhotoSaveCoordinator(store: store, identity: identity, temporaryMedia: media, library: PhotoSaveLibrary())
    _ = await coordinator.save(receipt, action: .init(rawValue: "other-explicit-save"))
}
