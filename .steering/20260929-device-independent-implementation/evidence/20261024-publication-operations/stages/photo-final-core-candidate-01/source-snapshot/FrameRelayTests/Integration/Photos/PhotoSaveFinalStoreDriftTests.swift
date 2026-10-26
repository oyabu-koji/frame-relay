import Darwin
import Foundation
import Synchronization
import Testing
@testable import FrameRelay

/// Actual AtomicFile/SQLite final writer checks on new UUID-isolated roots.
/// The synchronous callback is a technical guard observation only. These tests
/// never call PhotoKit, an AV SDK, a native add, or a production media producer.
@Suite(.serialized) @MainActor struct PhotoSaveFinalStoreDriftTests {
    @Test(arguments: StorageCandidate.allCases)
    func aCommittedInvalidationAfterResolveRefusesTheOldCommand(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run, candidate: candidate)
            let command = try await photoDriftCommand(f), original = f.receipt.rendition.original
            try await photoDriftRequireCurrent(command, f: f)
            let record = statusInvalidation(f.receipt.rendition, registration: command.registration.mediaUse.lease.registration,
                id: "photo-final-invalidation-" + UUID().uuidString)
            _ = try await mediaOriginalCommit(f.rendition.store, .reserveInvalidation(.init(record)))
            let logical = try #require(try await mediaOriginalSnapshot(f.rendition.store).logicalOriginals.first)
            #expect(logical.invalidation?.record == record)
            let beforeGate = try await mediaSnapshot(f.rendition.store), count = PhotoDriftCounter()
            #expect(!(await f.rendition.store.performPhotoSaveIfCurrent(command) { count.increment() }))
            #expect(count.value == 0)
            #expect(try await mediaSnapshot(f.rendition.store) == beforeGate)
            let saved = try await f.latest()
            #expect(saved.results.isEmpty && saved.usageTerminal == nil && saved.terminalUsageRelease == nil)
            let state = try #require(try await mediaOriginalSnapshot(f.rendition.store).logicalOriginals.first { $0.original == original })
            #expect(state.mediaReaders.contains(command.registration.mediaUse.lease))
            #expect(try await f.rendition.temporary.usageSnapshot(f.receipt.id).openHandles == 1)
            let additions = await f.library.additions
            #expect(additions.isEmpty)
            try await photoDriftRetireNonStart(f, command: command)
        }
    }

    @Test(arguments: StorageCandidate.allCases, ["file", "directory", "symlink-leaf", "content-type"])
    func namedPathAndContentTypeAreRecheckedAfterTheFullHash(candidate: StorageCandidate, change: String) async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run, candidate: candidate)
            let actual = try await photoDriftCommand(f)
            try await photoDriftRequireCurrent(actual, f: f)
            let bytes = try Data(contentsOf: actual.media.url), content = try renditionContent(bytes)
            let witness = try #require(actual.media.photoReadWitness)
            var local = actual.media
            var retained: URL?
            if change == "directory" {
                let root = actual.media.url.deletingLastPathComponent()
                let moved = root.deletingLastPathComponent().appendingPathComponent("retained-photo-directory-" + UUID().uuidString)
                try FileManager.default.moveItem(at: root, to: moved)
                retained = moved.appendingPathComponent(actual.media.url.lastPathComponent)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
                try Data().write(to: root.appendingPathComponent("owner.lock"), options: .withoutOverwriting)
                try bytes.write(to: actual.media.url, options: .withoutOverwriting)
            } else if change == "content-type" {
                local = .init(url: local.url, handoff: local.handoff, contentType: "video/mp4", photoReadWitness: local.photoReadWitness)
            } else {
                let moved = actual.media.url.deletingLastPathComponent().appendingPathComponent("retained-photo-file-" + UUID().uuidString)
                try FileManager.default.moveItem(at: actual.media.url, to: moved); retained = moved
                if change == "symlink-leaf" { try FileManager.default.createSymbolicLink(at: actual.media.url, withDestinationURL: moved) }
                else { try bytes.write(to: actual.media.url, options: .withoutOverwriting) }
            }
            let command = try PhotoLibraryAddCommand(registration: actual.registration, media: local)
            let before = try await mediaSnapshot(f.rendition.store), count = PhotoDriftCounter()
            #expect(!(await f.rendition.store.performPhotoSaveIfCurrent(command) { count.increment() }))
            #expect(count.value == 0 && command.media.photoReadWitness == actual.media.photoReadWitness)
            #expect(try await mediaSnapshot(f.rendition.store) == before)
            let opened = try OriginalFileFingerprint(descriptor: witness.fileDescriptor)
            #expect(opened.device == witness.fingerprint.device && opened.inode == witness.fingerprint.inode
                && opened.size == witness.fingerprint.size)
            if let retained {
                #expect(try renditionContent(Data(contentsOf: retained)) == content)
                // The owner closes its original FD even when named integrity
                // fails. Neither replacement nor retained leaf is repaired.
                await #expect(throws: BackendContractError.identityMismatch) { try await f.media.finishPhotoMedia(f.receipt.usage) }
                #expect(try renditionContent(Data(contentsOf: retained)) == content)
                let record = try await f.latest()
                #expect(record.results.isEmpty && record.usageTerminal == nil && record.terminalUsageRelease == nil)
                #expect(try await mediaSnapshot(f.rendition.store).temporaryMedia[0].usages.count == 1)
            } else { try await photoDriftRetireNonStart(f, command: actual) }
            let additions = await f.library.additions
            #expect(additions.isEmpty)
        }
    }

    @Test(arguments: StorageCandidate.allCases, ["operation", "usage", "registration"])
    func normalizedEqualUTF8AliasesCannotJoinAnActualSavedIntentOrUse(candidate: StorageCandidate, field: String) async throws {
        try await withStorageRun { run in
            let f = try await photoDriftFixture(run, candidate: candidate, unicode: true)
            let actual = try await photoDriftCommand(f, operation: "photo-op-caf\u{00e9}")
            try await photoDriftRequireCurrent(actual, f: f)
            let saved = actual.registration
            var use = saved.mediaUse, usage = saved.intent.usage
            var operation = saved.intent.operation
            if field == "operation" { operation = .init(rawValue: operation.rawValue.decomposedStringWithCanonicalMapping) }
            if field == "usage" {
                usage = .init(id: .init(rawValue: usage.id.rawValue.decomposedStringWithCanonicalMapping),
                    purpose: usage.purpose, media: usage.media, epoch: usage.epoch)
            }
            var registration = use.lease.registration
            if field == "registration" {
                registration = .init(destination: registration.destination,
                    id: .init(rawValue: registration.id.rawValue.decomposedStringWithCanonicalMapping), generation: registration.generation)
            }
            use = .init(usage: usage, lease: photoDriftLease(use.lease, usage: usage, registration: registration), owner: use.owner)
            let intent = try PhotoRegistrationIntent(operation: operation,
                handoff: .init(media: saved.intent.media, rendition: saved.intent.rendition, capturedAt: saved.intent.capturedAt, usage: usage))
            let proposed = photoDriftRegistration(saved, intent: intent, use: use)
            let local = TemporaryLocalMedia(url: actual.media.url, handoff: intent.handoff,
                contentType: actual.media.contentType, photoReadWitness: actual.media.photoReadWitness)
            let alias = try PhotoLibraryAddCommand(registration: proposed, media: local)
            // Swift's normalization equality alone accepts all three aliases.
            // The final writer must compare the exact persisted UTF-8 input.
            #expect(alias == actual && alias.registration.isCommitted)
            let exactIntent = PhotoSaveBatchValueValidation.exact(alias.registration.intent, saved.intent)
            let exactUse = PhotoSaveBatchValueValidation.exact(alias.registration.mediaUse, saved.mediaUse)
            #expect(!exactIntent || !exactUse)
            let before = try await mediaSnapshot(f.rendition.store), count = PhotoDriftCounter()
            #expect(!(await f.rendition.store.performPhotoSaveIfCurrent(alias) { count.increment() }))
            #expect(count.value == 0)
            #expect(try await mediaSnapshot(f.rendition.store) == before)
            try await photoDriftRequireCurrent(actual, f: f)
            try await photoDriftRetireNonStart(f, command: actual)
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func immutableCoverageContentDateAndFileMetadataCannotReplaceTheActualFinalInput(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run, candidate: candidate), command = try await photoDriftCommand(f)
            let state = try await f.rendition.temporary.stateFor(f.receipt.id)
            let before = try await mediaSnapshot(f.rendition.store)
            let wrongContent = try renditionContent(Data(repeating: 0xee, count: 4096))
            let replacement = TemporaryMediaState(id: state.id, rendition: state.rendition, registration: state.registration,
                capturedAt: state.capturedAt.addingTimeInterval(1), leaf: state.leaf, contentType: state.contentType,
                directoryIdentity: .init(device: state.directoryIdentity.device, inode: state.directoryIdentity.inode + 1))
            // These immutable fields have no legal post-intent update API. Do
            // not fabricate successful drift by rewriting a journal/document.
            let changes: [TemporaryMediaChange] = [
                .stored(state.id, try .init(lowerBound: 1, upperBound: 2)),
                .verified(state.id, wrongContent),
                .fileCreated(state.id, .init(device: state.directoryIdentity.device, inode: state.directoryIdentity.inode + 1)),
                .create(replacement)]
            for change in changes {
                let mutation = BackendStoreMutation(expectedRevision: before.revision,
                    change: .temporary(command: .init(rawValue: UUID().uuidString), value: change))
                guard case .rejected = await f.rendition.store.commit(mutation) else {
                    Issue.record("An immutable temporary input was replaced"); throw BackendContractError.invalidValue
                }
                #expect(try await mediaSnapshot(f.rendition.store) == before)
            }
            try await photoDriftRequireCurrent(command, f: f)
            #expect(try await f.rendition.temporary.stateFor(f.receipt.id) == state)
            try await photoDriftRetireNonStart(f, command: command)
        }
    }

    @Test(arguments: StorageCandidate.allCases, ["date", "delivery-content"])
    func aDifferentHandoffCannotBorrowTheSamePhotoKeyAndActualReceipt(candidate: StorageCandidate, field: String) async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run, candidate: candidate), actual = try await photoDriftCommand(f)
            let saved = actual.registration
            let rendition = field == "delivery-content"
                ? photoDriftRendition(saved.intent.rendition, content: try renditionContent(Data(repeating: 0xcc, count: 4096))) : saved.intent.rendition
            let intent = try PhotoRegistrationIntent(operation: saved.intent.operation,
                handoff: .init(media: saved.intent.media, rendition: rendition,
                    capturedAt: field == "date" ? saved.intent.capturedAt.addingTimeInterval(1) : saved.intent.capturedAt, usage: saved.intent.usage))
            let use = TemporaryMediaUseRecord(usage: saved.mediaUse.usage,
                lease: photoDriftLease(saved.mediaUse.lease, rendition: rendition), owner: saved.mediaUse.owner)
            let local = TemporaryLocalMedia(url: actual.media.url, handoff: intent.handoff,
                contentType: actual.media.contentType, photoReadWitness: actual.media.photoReadWitness)
            let altered = try PhotoLibraryAddCommand(registration: photoDriftRegistration(saved, intent: intent, use: use), media: local)
            #expect(altered.registration.isCommitted && altered.registration.intent.key == saved.intent.key)
            let before = try await mediaSnapshot(f.rendition.store), count = PhotoDriftCounter()
            #expect(!(await f.rendition.store.performPhotoSaveIfCurrent(altered) { count.increment() }))
            #expect(count.value == 0)
            #expect(try await mediaSnapshot(f.rendition.store) == before)
            try await photoDriftRequireCurrent(actual, f: f)
            try await photoDriftRetireNonStart(f, command: actual)
        }
    }

    @Test(arguments: StorageCandidate.allCases, [false, true])
    func independentCachedMediaNeedsNeitherAPhysicalOriginalNorANotRemovedClassification(candidate: StorageCandidate, removed: Bool) async throws {
        try await withStorageRun { run in
            let f = try await photoDriftFixture(run, candidate: candidate, local: true, removed: removed)
            let logical = try #require(try await mediaOriginalSnapshot(f.rendition.store).logicalOriginals.first)
            let binding = try #require(logical.binding)
            let url = run.url.appendingPathComponent(binding.reference.rawValue + ".mov")
            try photoDriftAbsent(url)
            #expect(logical.removal == nil && logical.invalidation == nil && (logical.removalResolution == .removed) == removed)
            let command = try await photoDriftCommand(f)
            try await photoDriftRequireCurrent(command, f: f)
            try photoDriftAbsent(url)
            try await photoDriftRetireNonStart(f, command: command)
            let settled = try #require(try await mediaOriginalSnapshot(f.rendition.store).logicalOriginals.first)
            #expect(settled.binding == binding && settled.removalResolution == logical.removalResolution)
        }
    }

    @Test(arguments: StorageCandidate.allCases, ["removal", "publication"])
    func livePhotoOwnershipKeepsRemovalAndPublicationBehindTheirOrderingFences(candidate: StorageCandidate, boundary: String) async throws {
        try await withStorageRun { run in
            let f = try await photoDriftFixture(run, candidate: candidate, local: true), command = try await photoDriftCommand(f)
            let state = try #require(try await mediaOriginalSnapshot(f.rendition.store).logicalOriginals.first)
            let before = try await mediaSnapshot(f.rendition.store)
            if boundary == "removal" {
                let intent = RemovalIntent(operation: .init(rawValue: UUID().uuidString), original: state.original, purpose: .discard)
                let mutation = OriginalStoreMutation(operation: intent.operation, expectedRevision: before.revision,
                    change: .reserveRemoval(intent, expectedInvalidation: state.invalidationGeneration, expectedAccess: state.accessGeneration))
                #expect(await f.rendition.store.commitOriginal(mutation) == .rejected(.readersActive))
            } else {
                let next = photoDriftRendition(f.receipt.rendition, version: 2)
                let mutation = BackendStoreMutation(expectedRevision: before.revision, change: .publication(mediaPublication(next,
                    registration: command.registration.mediaUse.lease.registration, observation: 2, generation: 1)))
                #expect(await f.rendition.store.commit(mutation) == .rejected(.awaitingAcknowledgements))
            }
            #expect(try await mediaSnapshot(f.rendition.store) == before)
            // The existing fences prohibit these standalone live drifts. Do
            // not invent distribution/ACK facts to reach a later guard.
            try await photoDriftRequireCurrent(command, f: f)
            #expect(try await mediaOriginalSnapshot(f.rendition.store).logicalOriginals.first?.removal == nil)
            #expect(try await mediaSnapshot(f.rendition.store).confirmationStates.first?.current == f.receipt.rendition)
            try await photoDriftRetireNonStart(f, command: command)
        }
    }
}

private nonisolated final class PhotoDriftCounter: Sendable {
    private let count = Mutex(0)
    func increment() { count.withLock { $0 += 1 } }
    var value: Int { count.withLock { $0 } }
}
private nonisolated func photoDriftCommand(_ f: PhotoSaveFixture, operation: String = UUID().uuidString) async throws -> PhotoLibraryAddCommand {
    let saved = try await f.commitIntent(action: operation)
    let local = try await f.media.resolvePhotoMedia(f.receipt.usage)
    return try .init(registration: saved.registration, media: local)
}
private nonisolated func photoDriftRequireCurrent(_ command: PhotoLibraryAddCommand, f: PhotoSaveFixture) async throws {
    let before = try await mediaSnapshot(f.rendition.store), count = PhotoDriftCounter()
    let allowed = await f.rendition.store.performPhotoSaveIfCurrent(command) { count.increment() }
    try #require(allowed && count.value == 1)
    #expect(try await mediaSnapshot(f.rendition.store) == before)
    let additions = await f.library.additions
    #expect(additions.isEmpty)
}
private nonisolated func photoDriftRetireNonStart(_ f: PhotoSaveFixture, command: PhotoLibraryAddCommand) async throws {
    try await f.media.finishPhotoMedia(f.receipt.usage)
    _ = try await mediaCommit(f.rendition.store, .photo(command: .init(rawValue: UUID().uuidString),
        value: .result(.init(intent: command.registration.intent, outcome: .notAttempted(.rejected)))))
    let terminal = try await f.media.photoUsageTerminal(command.registration, termination: .notStarted)
    _ = try await mediaCommit(f.rendition.store, .photo(command: .init(rawValue: UUID().uuidString), value: .terminal(terminal)))
    #expect(await f.media.releaseUsage(f.receipt.usage) == .succeeded(f.receipt.id))
    #expect(try await f.rendition.temporary.usageSnapshot(f.receipt.id).openHandles == 0)
}
private nonisolated func photoDriftRegistration(_ saved: CommittedPhotoRegistrationIntent, intent: PhotoRegistrationIntent,
    use: TemporaryMediaUseRecord) -> CommittedPhotoRegistrationIntent {
    .init(intent: intent, mediaUse: use, commit: saved.commit, expectedStoreIdentity: saved.expectedStoreIdentity,
        directoryIdentity: saved.directoryIdentity, fileIdentity: saved.fileIdentity)
}
private nonisolated func photoDriftLease(_ value: MediaReadLease, usage: TemporaryMediaUsage? = nil,
    registration: RegistrationIdentity? = nil, rendition: RenditionIdentity? = nil) -> MediaReadLease {
    .init(id: value.id, target: rendition.map(MediaTarget.rendition) ?? value.target, operation: value.operation,
        registration: registration ?? value.registration, context: usage.map { .temporary($0.media, $0.id) } ?? value.context,
        epoch: value.epoch, accessGeneration: value.accessGeneration)
}
private nonisolated func photoDriftRendition(_ value: RenditionIdentity, content: ContentIdentity? = nil,
    version: UInt64? = nil) -> RenditionIdentity {
    .init(original: value.original, inputLogIdentity: value.inputLogIdentity, transformAssetIdentity: value.transformAssetIdentity,
        transformAssetVersion: value.transformAssetVersion, outputConfigurationIdentity: value.outputConfigurationIdentity,
        conversionVersion: value.conversionVersion, rendition: version.map { .init(rawValue: "photo-generation-\($0)") } ?? value.rendition,
        deliveryContent: content ?? value.deliveryContent, publicationGeneration: version.map { .init(rawValue: $0) } ?? value.publicationGeneration)
}
private nonisolated func photoDriftAbsent(_ url: URL) throws {
    var value = stat(); let result = lstat(url.path, &value), observed = errno
    try #require(result != 0 && observed == ENOENT)
}

/// Custom inputs stay in this file/new run. Unicode registration/use identities
/// exercise exact joins; historical removed is a synthetic persisted fixture
/// classification through real writer receipts, not a physical deletion proof.
@MainActor private func photoDriftFixture(_ run: ExplorationRunDirectory, candidate: StorageCandidate,
    unicode: Bool = false, local: Bool = false, removed: Bool = false) async throws -> PhotoSaveFixture {
    let bytes = Data((0..<4096).map { UInt8($0 % 251) }), content = try renditionContent(bytes)
    let rendition: RenditionFixture
    if unicode {
        let store: any MediaDiskStore
        switch candidate {
        case .atomicFile: store = try AtomicFileRecordingStore(run: run, mode: .createNew)
        case .sqlite: store = try SQLiteRecordingStore(run: run, mode: .createNew)
        }
        let registration = try await mediaRegister(store, registration: .init(destination: .init(rawValue: "photo-destination-caf\u{00e9}"),
            id: .init(rawValue: "photo-registration-caf\u{00e9}"), generation: .init(rawValue: 1)))
        let original = OriginalContent(capture: .init(rawValue: "photo-original-caf\u{00e9}"), generation: .init(rawValue: 1), content: content)
        let identity = RenditionIdentity(original: original, inputLogIdentity: "synthetic-not-log", transformAssetIdentity: "no-quality-claim",
            transformAssetVersion: "fixture-v1", outputConfigurationIdentity: "fixture-movie", conversionVersion: "synthetic-writer",
            rendition: .init(rawValue: "photo-rendition-caf\u{00e9}"), deliveryContent: content, publicationGeneration: .init(rawValue: 1))
        _ = try await mediaCommit(store, .publication(mediaPublication(identity, registration: registration)))
        let operation = MediaOperationID(rawValue: UUID().uuidString)
        let distribution = DistributionReceipt(operation: operation, rendition: identity, registration: registration,
            commit: .init(key: .distribution(operation, identity, registration), previousRevision: 0, committedRevision: 1))
        let retrieve = RetrieveMediaCommand(gate: .init(operation: .init(rawValue: UUID().uuidString), attempt: .init(rawValue: UUID().uuidString),
            target: .rendition(identity), registration: registration, generation: 1), distribution: distribution, range: nil)
        let leases = RenditionReadLeases(store: store), scope = try await RenditionMediaScope.open(original: original, leases: leases)
        let temporary = try await ManagedTemporaryMedia.open(root: run.url.appendingPathComponent("photo-drift-temporary", isDirectory: true),
            leases: leases, scope: scope)
        rendition = .init(run: run, store: store, leases: leases, scope: scope, temporary: temporary, faults: nil, command: retrieve)
    } else { rendition = try await RenditionFixture.make(run: run, content: content, candidate: candidate) }
    if local {
        let binding = try await statusKnownOriginal(rendition.command.distribution.rendition.original, store: rendition.store)
        try photoDriftAbsent(run.url.appendingPathComponent(binding.reference.rawValue + ".mov"))
        if removed {
            try await mediaReconcile(rendition.store, original: binding.original)
            let state = try #require(try await mediaOriginalSnapshot(rendition.store).logicalOriginals.first)
            let intent = RemovalIntent(operation: .init(rawValue: UUID().uuidString), original: binding.original, purpose: .discard)
            _ = try await mediaOriginalCommit(rendition.store, .reserveRemoval(intent,
                expectedInvalidation: state.invalidationGeneration, expectedAccess: state.accessGeneration))
            _ = try await mediaOriginalCommit(rendition.store, .resolveRemoval(intent, .removed))
        }
    }
    let complete = try await rendition.complete(bytes), before = try await mediaSnapshot(rendition.store)
    let identity = try await rendition.store.establishRegistrationIdentity(expectedRevision: before.revision, expectedIdentity: nil)
    guard case .succeeded(let usage) = await rendition.temporary.acquireUsage(complete.id, purpose: .photoHandoff,
        usageID: .init(rawValue: unicode ? "photo-use-caf\u{00e9}" : "photo-drift-use-" + UUID().uuidString)) else { throw BackendContractError.unavailable }
    let receipt = try await rendition.temporary.stateFor(complete.id).receipt(for: usage)
    guard await rendition.temporary.releaseUsage(complete.usage) == .succeeded(complete.id) else { throw BackendContractError.unavailable }
    let faults = PhotoSaveFaultStore(base: rendition.store), library = PhotoSaveLibrary(), media = PhotoSaveMedia(base: rendition.temporary)
    let coordinator = PhotoSaveCoordinator(store: faults, identity: identity, temporaryMedia: media, library: library)
    return .init(rendition: rendition, faults: faults, identity: identity, receipt: receipt, library: library, media: media, coordinator: coordinator)
}
