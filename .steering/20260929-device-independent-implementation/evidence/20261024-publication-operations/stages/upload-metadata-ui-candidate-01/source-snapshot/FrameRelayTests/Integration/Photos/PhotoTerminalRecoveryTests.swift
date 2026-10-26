import Foundation
import Testing
@testable import FrameRelay

/// Real common-writer journals and S25 files with an explicit fake SDK boundary.
/// The terminal does not establish Photos success or rendition quality.
struct PhotoTerminalRecoveryTests {
    @MainActor @Test(arguments: StorageCandidate.allCases,
          [PhotoRegistrationOutcome.succeeded(localIdentifier: nil), .failed(.rejected),
           .unknown(localIdentifier: try! .init(rawValue: "closed-owner-unknown")),
           .notAttempted(.authorizationRequired)])
    func closedOwnerAcknowledgesOnlyItsExactCommittedPhotoReleaseWithoutAnyNewEffect(candidate: StorageCandidate,
                                                                                    outcome: PhotoRegistrationOutcome) async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run, candidate: candidate)
            await f.library.configure(outcome: outcome)
            if case .notAttempted = outcome { await f.library.configure(add: .denied) }
            guard case .succeeded(let saved) = await f.coordinator.save(f.receipt, action: .init(rawValue: "closed-owner-photo")) else {
                Issue.record("Expected a durable terminal before closing its real owner"); return
            }
            let closed = try await f.rendition.scope.close()
            let observed = try #require(closed.observations.first)
            #expect(observed.terminal.started == observed.terminal.completed && observed.terminal.handlesClosed)
            let before = try await mediaSnapshot(f.rendition.store)
            #expect(await f.rendition.temporary.recoverTerminalPhotoUsage(saved) == .succeeded(f.receipt.id))
            #expect(await f.rendition.temporary.releaseUsage(f.receipt.usage) == .succeeded(f.receipt.id))
            await #expect(throws: BackendContractError.identityMismatch) { _ = try await f.rendition.temporary.rootUsageSnapshot() }
            #expect(await f.rendition.temporary.inspect(f.receipt.id) == .failed(.contentMismatch))

            let registration = saved.registration
            let alteredUse = TemporaryMediaUseRecord(usage: registration.mediaUse.usage, lease: registration.mediaUse.lease,
                owner: "another-owner-must-not-join-or-reuse-this-proof")
            let altered = PhotoRegistrationRecord(registration: .init(intent: registration.intent, mediaUse: alteredUse,
                commit: registration.commit, expectedStoreIdentity: registration.expectedStoreIdentity,
                directoryIdentity: registration.directoryIdentity, fileIdentity: registration.fileIdentity),
                results: saved.results, presenceObservations: saved.presenceObservations, usageRelease: saved.usageRelease,
                usageTerminal: saved.usageTerminal, terminalUsageRelease: saved.terminalUsageRelease)
            #expect(await f.rendition.temporary.recoverTerminalPhotoUsage(altered) == .unknown)
            #expect(try await mediaSnapshot(f.rendition.store) == before)
            let expectedAdditions: Int
            if case .notAttempted = outcome { expectedAdditions = 0 } else { expectedAdditions = 1 }
            #expect(await f.library.additions.count == expectedAdditions)
            let state = try await f.rendition.temporary.stateFor(f.receipt.id)
            if case .succeeded = outcome { #expect(state.reclaimed) }
            else {
                #expect(!state.reclaimed && !state.reclaiming)
                let file = run.url.appendingPathComponent("temporary").appendingPathComponent(state.leaf)
                #expect(try renditionContent(Data(contentsOf: file)) == f.receipt.rendition.deliveryContent)
            }
        }
    }

    @MainActor @Test func closedOwnerStillRequiresExactReleaseLookupAndDoesNotWriteDuringRetry() async throws {
        try await withStorageRun { run in
            let seed = try await photoTerminalSeed(run)
            let base = try photoTerminalStore(run)
            let faults = PhotoSaveFaultStore(base: base)
            let leases = RenditionReadLeases(store: faults)
            let scope = try await RenditionMediaScope.open(original: seed.record.registration.intent.rendition.original, leases: leases)
            let owner = try await ManagedTemporaryMedia.open(root: run.url.appendingPathComponent("temporary"), leases: leases, scope: scope)
            #expect(await owner.recoverTerminalPhotoUsage(seed.record) == .succeeded(seed.record.registration.intent.media))
            _ = try await scope.close()
            let settled = try #require(try await mediaSnapshot(base).photoRegistrations.last)
            let before = try await mediaSnapshot(base)
            let writes = faults.photoCommits.count
            faults.configure(.releaseTerminalUsage)
            #expect(await owner.recoverTerminalPhotoUsage(settled) == .unknown)
            faults.configure()
            #expect(await owner.recoverTerminalPhotoUsage(settled) == .succeeded(seed.record.registration.intent.media))
            #expect(faults.photoCommits.count == writes)
            #expect(try await mediaSnapshot(base) == before)
        }
    }

    @MainActor @Test func concurrentExactTerminalRecoveriesShareOneMutationAndPreserveTheCopy() async throws {
        try await withStorageRun { run in
            let seed = try await photoTerminalSeed(run)
            let base = try photoTerminalStore(run)
            let gate = PhotoRecoveryJoinBarrier()
            let store = PhotoRecoveryJoinStore(base: base, intent: seed.record.registration.mutation, barrier: gate)
            let leases = RenditionReadLeases(store: store)
            let scope = try await RenditionMediaScope.open(original: seed.record.registration.intent.rendition.original, leases: leases)
            let owner = try await ManagedTemporaryMedia.open(root: run.url.appendingPathComponent("temporary"), leases: leases, scope: scope)
            let first = Task { await owner.recoverTerminalPhotoUsage(seed.record) }
            defer { Task { await gate.release() } }
            try #require(await renditionEventually { await gate.hasArrived() })
            let second = Task {
                await gate.markSecondCall()
                return await owner.recoverTerminalPhotoUsage(seed.record)
            }
            try #require(await renditionEventually { await gate.secondHasStarted() })
            // An actor request after the second call's scheduling point gives
            // the duplicate its chance to encounter the held exact recovery.
            _ = try await owner.stateFor(seed.record.registration.intent.media)
            await gate.release()
            #expect(await first.value == .succeeded(seed.record.registration.intent.media))
            #expect(await second.value == .succeeded(seed.record.registration.intent.media))
            #expect(await store.releaseCommitCount() == 1)
            let state = try await owner.stateFor(seed.record.registration.intent.media)
            #expect(state.usages.isEmpty && !state.reclaimed && !state.reclaiming)
            #expect(state.releasedUsages.filter { $0.usage == seed.record.registration.intent.usage } == [seed.record.registration.mediaUse])
            let file = run.url.appendingPathComponent("temporary").appendingPathComponent(state.leaf)
            #expect(try renditionContent(Data(contentsOf: file)) == state.rendition.deliveryContent)
            _ = try await scope.close()
        }
    }

    @Test(arguments: StorageCandidate.allCases,
          [PhotoRegistrationOutcome.succeeded(localIdentifier: nil), .failed(.rejected),
           .unknown(localIdentifier: try! .init(rawValue: "terminal-unknown-asset")),
           .notAttempted(.authorizationRequired)])
    func terminalReleasesItsReaderButOnlySuccessReclaimsTheCopy(candidate: StorageCandidate,
                                                               outcome: PhotoRegistrationOutcome) async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run, candidate: candidate)
            await f.library.configure(outcome: outcome)
            if case .notAttempted = outcome { await f.library.configure(add: .denied) }
            guard case .succeeded(let saved) = await f.coordinator.save(f.receipt, action: .init(rawValue: "terminal-save")) else {
                Issue.record("No terminal result"); return
            }
            #expect(saved.outcome == outcome)
            let terminal = try #require(saved.usageTerminal)
            let release = try #require(saved.terminalUsageRelease)
            #expect(await f.rendition.store.lookupCommit(terminal.mutation) == .committed(terminal.commit))
            #expect(await f.rendition.store.lookupCommit(release.mutation) == .committed(release.commit))
            #expect(terminal.terminal.mediaUse == saved.registration.mediaUse)
            let state = try await f.rendition.temporary.stateFor(f.receipt.id)
            let disk = try await f.rendition.temporary.usageSnapshot(state.id)
            #expect(state.usages.isEmpty && state.releasedUsages.contains(saved.registration.mediaUse))
            #expect(disk.uses == 0 && disk.openHandles == 0)
            let success: Bool
            if case .succeeded = outcome { success = true } else { success = false }
            #expect(state.reclaimed == success && state.reclaiming == success)
            #expect((disk.fileBytes == 0) == success)
            if !success {
                let file = run.url.appendingPathComponent("temporary").appendingPathComponent(state.leaf)
                #expect(try renditionContent(Data(contentsOf: file)) == f.receipt.rendition.deliveryContent)
                let before = try await mediaSnapshot(f.rendition.store)
                #expect(await f.rendition.store.commit(.init(expectedRevision: before.revision,
                    change: .temporary(command: .init(rawValue: "must-not-unlink-unknown-copy"), value: .reclaim(state.id)))) == .rejected(.readersActive))
            }
            #expect(try await mediaOriginalSnapshot(f.rendition.store).logicalOriginals.first?.mediaReaders.isEmpty == true)
            _ = try await f.rendition.scope.close()
            let reopened: any MediaDiskStore = candidate == .sqlite
                ? try SQLiteRecordingStore(run: run, mode: .openExisting)
                : try AtomicFileRecordingStore(run: run, mode: .openExisting)
            #expect(try await mediaSnapshot(reopened).photoRegistrations == [saved])
            #expect(try await mediaSnapshot(reopened).temporaryMedia.first?.reclaimed == success)
        }
    }

    @Test func terminalLeavesOtherLocalReadersAndCopiesUntouched() async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run, keepPlayback: true)
            let state = try await f.rendition.temporary.stateFor(f.receipt.id)
            let playback = try #require(state.usages.first { $0.usage.purpose == .playback })
            _ = try await f.rendition.temporary.read(playback.usage, offset: 0, length: 8)
            let other = try await f.rendition.create()
            let otherBefore = try await f.rendition.temporary.stateFor(other.id)
            await f.library.configure(outcome: .unknown(localIdentifier: nil))
            guard case .succeeded(let saved) = await f.coordinator.save(f.receipt, action: .init(rawValue: "one-photo-terminal")) else {
                Issue.record("Other reader blocked a safe photo terminal"); return
            }
            #expect(saved.terminalUsageRelease != nil)
            let after = try await f.rendition.temporary.stateFor(state.id)
            #expect(after.usages == [playback] && after.releasedUsages.contains(saved.registration.mediaUse))
            #expect(try await f.rendition.temporary.usageSnapshot(state.id).openHandles == 1)
            #expect(try await f.rendition.temporary.stateFor(other.id) == otherBefore)
            #expect(await f.rendition.temporary.releaseUsage(playback.usage) == .succeeded(state.id))
            #expect(try await f.rendition.temporary.usageSnapshot(state.id).fileBytes > 0)
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func reopenedTerminalUnknownRecoversOnlyExactOldUseAndRetainsResult(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let seed = try await photoTerminalSeed(run, candidate: candidate)
            let store = try photoTerminalStore(run, candidate: candidate)
            let leases = RenditionReadLeases(store: store)
            let scope = try await RenditionMediaScope.open(original: seed.record.registration.intent.rendition.original, leases: leases)
            let owner = try await ManagedTemporaryMedia.open(root: run.url.appendingPathComponent("temporary"), leases: leases, scope: scope)
            let library = PhotoSaveLibrary()
            let coordinator = PhotoSaveCoordinator(store: store, identity: seed.identity, temporaryMedia: owner, library: library)
            guard case .succeeded(let records) = await coordinator.restore() else { Issue.record("Terminal recovery failed"); return }
            let record = try #require(records.last)
            #expect(record.outcome == seed.record.outcome && record.localIdentifier == seed.record.localIdentifier)
            #expect(record.terminalUsageRelease != nil)
            let state = try await owner.stateFor(record.registration.intent.media)
            #expect(state.usages.isEmpty && !state.reclaimed && !state.reclaiming)
            #expect(state.releasedUsages.contains(record.registration.mediaUse))
            #expect(try await owner.usageSnapshot(state.id).fileBytes > 0)
            #expect(await library.additions.isEmpty)
            #expect(await library.requests.isEmpty)
            _ = try await scope.close()
        }
    }

    @Test(arguments: [false, true])
    func terminalCommitLossNeverBecomesAnUnconfirmedRelease(afterCommit: Bool) async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run)
            await f.library.configure(outcome: .unknown(localIdentifier: nil))
            await f.faults.configure(.terminal, afterCommit: afterCommit)
            #expect(await f.coordinator.save(f.receipt, action: .init(rawValue: "uncertain-terminal")) == .unknown)
            #expect(await f.media.releases == 0)
            #expect(try await f.rendition.temporary.stateFor(f.receipt.id).usages.count == 1)
            #expect((try await f.latest().usageTerminal != nil) == afterCommit)
            await f.faults.configure()
            guard case .succeeded = await f.reopenedCoordinator().restore() else { Issue.record("Restore failed"); return }
            #expect(try await f.rendition.temporary.stateFor(f.receipt.id).usages.isEmpty == afterCommit)
            #expect(try await f.rendition.temporary.usageSnapshot(f.receipt.id).fileBytes > 0)
            #expect(await f.library.additions.count == 1)
        }
    }

    @Test(arguments: [false, true])
    func terminalReleaseResponseLossRetainsOriginalMutationAcrossScopeClose(afterCommit: Bool) async throws {
        try await withStorageRun { run in
            let seed = try await photoTerminalSeed(run)
            let base = try photoTerminalStore(run)
            let faults = await PhotoSaveFaultStore(base: base)
            await faults.configure(.releaseTerminalUsage, afterCommit: afterCommit)
            let leases = RenditionReadLeases(store: faults)
            let scope = try await RenditionMediaScope.open(original: seed.record.registration.intent.rendition.original, leases: leases)
            let owner = try await ManagedTemporaryMedia.open(root: run.url.appendingPathComponent("temporary"), leases: leases, scope: scope)
            #expect(await owner.recoverTerminalPhotoUsage(seed.record) == .unknown)
            #expect(try await owner.stateFor(seed.record.registration.intent.media).usages.isEmpty == afterCommit)
            await faults.configure()
            if afterCommit {
                #expect(await owner.recoverTerminalPhotoUsage(seed.record) == .succeeded(seed.record.registration.intent.media))
                _ = try await scope.close()
            } else {
                await #expect(throws: BackendContractError.unknownResult) { try await scope.close() }
                #expect(await owner.recoverTerminalPhotoUsage(seed.record) == .unknown)
            }
            #expect(await faults.photoCommits.count == 1)
            let mutation = try #require(await faults.photoCommits.first)
            let exactLookups = await faults.lookups.filter { $0.change.key == mutation.change.key }
            #expect(!exactLookups.isEmpty && exactLookups.allSatisfy { $0 == mutation })
        }
    }

    @Test(arguments: ["command", "commit", "owner", "lease", "epoch", "directory", "file"])
    func writerRejectsTerminalReleaseWithAlteredProof(corruption: String) async throws {
        try await withStorageRun { run in
            let seed = try await photoTerminalSeed(run)
            let store = try photoTerminalStore(run)
            let release = try PhotoTerminalUsageRelease(record: seed.record)
            var value = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(release)) as? [String: Any])
            if corruption == "command" { value["terminalCommand"] = ["rawValue": "other-terminal-command"] }
            else if corruption == "commit" {
                var commit = try #require(value["terminalCommit"] as? [String: Any])
                commit["committedRevision"] = 9_999
                value["terminalCommit"] = commit
            } else {
                var terminal = try #require(value["terminal"] as? [String: Any])
                if corruption == "directory" || corruption == "file" {
                    terminal[corruption == "directory" ? "directoryIdentity" : "fileIdentity"] = ["device": 9_999, "inode": 9_999]
                } else {
                    var use = try #require(terminal["mediaUse"] as? [String: Any])
                    if corruption == "owner" { use["owner"] = "unrelated-owner" }
                    else {
                        var lease = try #require(use["lease"] as? [String: Any])
                        lease[corruption == "lease" ? "id" : "epoch"] = ["rawValue": "unrelated-lease-or-epoch"]
                        use["lease"] = lease
                    }
                    terminal["mediaUse"] = use
                }
                value["terminal"] = terminal
            }
            let altered = try JSONDecoder().decode(PhotoTerminalUsageRelease.self, from: JSONSerialization.data(withJSONObject: value))
            let before = try await mediaSnapshot(store)
            #expect(await store.commit(.init(expectedRevision: before.revision,
                change: .photo(command: .init(rawValue: "altered-terminal-release"), value: .releaseTerminalUsage(altered)),
                expectedStoreIdentity: seed.identity)) == .rejected(.identityMismatch))
            #expect(try await mediaSnapshot(store) == before)
        }
    }

    @Test func laterSuccessOfSameUnknownRequestReclaimsRetainedCopyWithoutAddingAgain() async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run)
            await f.library.configure(outcome: .unknown(localIdentifier: nil))
            guard case .succeeded(let unknown) = await f.coordinator.save(f.receipt, action: .init(rawValue: "unknown-then-success")) else {
                Issue.record("No unknown result"); return
            }
            #expect(try await f.rendition.temporary.stateFor(f.receipt.id).usages.isEmpty)
            #expect(try await f.rendition.temporary.usageSnapshot(f.receipt.id).fileBytes > 0)
            _ = try await mediaCommit(f.rendition.store, .photo(command: .init(rawValue: "same-sdk-late-success"),
                value: .result(.init(intent: unknown.registration.intent, outcome: .succeeded(localIdentifier: nil)))))
            guard case .succeeded = await f.coordinator.restore() else { Issue.record("Late terminal success not restored"); return }
            #expect(try await f.rendition.temporary.stateFor(f.receipt.id).reclaimed)
            #expect(try await f.rendition.temporary.usageSnapshot(f.receipt.id).fileBytes == 0)
            #expect(await f.library.additions.count == 1)
        }
    }

    @Test func linkedRetryCannotSwitchMediaOrReuseTheRetiredPhotoUsage() async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run)
            await f.library.configure(add: .denied)
            let action = MediaOperationID(rawValue: "denied-original-copy")
            guard case .succeeded(let denied) = await f.coordinator.save(f.receipt, action: action) else {
                Issue.record("No denied original"); return
            }
            let bytes = Data((0..<4096).map { UInt8($0 % 251) })
            let other = try await f.rendition.complete(bytes)
            guard case .succeeded(let use) = await f.rendition.temporary.acquireUsage(other.id, purpose: .photoHandoff,
                usageID: .init(rawValue: "different-copy-use")) else { throw BackendContractError.unavailable }
            let otherReceipt = try await f.rendition.temporary.stateFor(other.id).receipt(for: use)
            await f.library.configure(add: .authorized)
            #expect(await f.coordinator.save(otherReceipt, action: .init(rawValue: "wrong-copy-retry"), retryOf: action) == .failed(.rejected))
            guard case .succeeded(let retried) = await f.coordinator.save(f.receipt,
                action: .init(rawValue: "right-copy-retry"), retryOf: action) else { Issue.record("No fresh retry"); return }
            #expect(retried.registration.intent.media == denied.registration.intent.media)
            #expect(retried.registration.intent.rendition == denied.registration.intent.rendition)
            #expect(retried.registration.intent.capturedAt == denied.registration.intent.capturedAt)
            #expect(retried.registration.mediaUse != denied.registration.mediaUse)
            #expect(await f.library.additions.count == 1)
        }
    }

    @Test func definiteRetryIntentRejectionRetiresItsUnusedNewLeaseWithoutDroppingTheCopy() async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run)
            await f.library.configure(add: .denied)
            let original = MediaOperationID(rawValue: "denied-before-rejected-retry")
            guard case .succeeded = await f.coordinator.save(f.receipt, action: original) else {
                Issue.record("No original denial"); return
            }
            await f.library.configure(add: .authorized)
            await f.faults.configure(.intent, rejected: true)
            #expect(await f.coordinator.save(f.receipt, action: .init(rawValue: "definitely-rejected-retry"), retryOf: original) == .failed(.rejected))
            let state = try await f.rendition.temporary.stateFor(f.receipt.id)
            #expect(state.usages.isEmpty && !state.reclaimed && !state.reclaiming)
            #expect(state.releasedUsages.filter { $0.usage.purpose == .photoHandoff }.count == 2)
            #expect(try await mediaOriginalSnapshot(f.rendition.store).logicalOriginals.first?.mediaReaders.isEmpty == true)
            #expect(try await mediaSnapshot(f.rendition.store).photoRegistrations.count == 1)
            #expect(try await f.rendition.temporary.usageSnapshot(state.id).fileBytes > 0)
            #expect(await f.library.additions.isEmpty)
            _ = try await f.rendition.scope.close()
        }
    }

    @Test(arguments: [false, true])
    func uncertainRetryIntentKeepsItsFreshLeaseUntilExactLiveNonStartReconciliation(afterCommit: Bool) async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run)
            await f.library.configure(add: .denied)
            let original = MediaOperationID(rawValue: "denied-before-uncertain-retry")
            guard case .succeeded = await f.coordinator.save(f.receipt, action: original) else {
                Issue.record("No original denial"); return
            }
            await f.library.configure(add: .authorized)
            await f.faults.configure(.intent, afterCommit: afterCommit)
            let retry = MediaOperationID(rawValue: "uncertain-fresh-retry")
            #expect(await f.coordinator.save(f.receipt, action: retry, retryOf: original) == .unknown)
            let before = try await f.rendition.temporary.stateFor(f.receipt.id)
            let fresh = try #require(before.usages.first)
            #expect(before.usages.count == 1 && fresh.usage != f.receipt.usage)
            await f.faults.configure()
            guard case .succeeded = await f.coordinator.restore() else { Issue.record("Restore unavailable"); return }
            let after = try await f.rendition.temporary.stateFor(f.receipt.id)
            #expect(after.usages.isEmpty == afterCommit)
            #expect(!after.reclaiming && !after.reclaimed)
            if afterCommit {
                let record = try await f.latest()
                #expect(record.registration.intent.operation == retry && record.registration.intent.usage == fresh.usage)
                #expect(record.outcome == nil && record.usageTerminal?.terminal.termination == .notStarted)
                #expect(record.terminalUsageRelease != nil)
                _ = try await f.rendition.scope.close()
            } else {
                #expect(after.usages == [fresh])
                #expect(await f.coordinator.save(f.receipt, action: retry, retryOf: original) == .unknown)
                #expect(try await f.rendition.temporary.stateFor(f.receipt.id).usages == [fresh])
            }
            #expect(await f.library.additions.isEmpty)
        }
    }
}

private actor PhotoRecoveryJoinBarrier {
    private var arrived = false
    private var resumed = false
    private var second = false
    private var continuation: CheckedContinuation<Void, Never>?
    func hasArrived() -> Bool { arrived }
    func secondHasStarted() -> Bool { second }
    func markSecondCall() { second = true }
    func hold() async {
        arrived = true
        if !resumed { await withCheckedContinuation { continuation = $0 } }
    }
    func release() { resumed = true; continuation?.resume(); continuation = nil }
}

private actor PhotoRecoveryJoinStore {
    private let base: any MediaDiskStore
    private let intent: BackendStoreMutation
    private let barrier: PhotoRecoveryJoinBarrier
    private var held = false
    private var releaseCommits = 0
    init(base: any MediaDiskStore, intent: BackendStoreMutation, barrier: PhotoRecoveryJoinBarrier) {
        self.base = base; self.intent = intent; self.barrier = barrier
    }
    func releaseCommitCount() -> Int { releaseCommits }
    func load() async -> BackendStoreLoadResult { await base.load() }
    func commit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        if case .photo(_, .releaseTerminalUsage) = mutation.change { releaseCommits += 1 }
        return await base.commit(mutation)
    }
    func lookupCommit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        if mutation == intent, !held { held = true; await barrier.hold() }
        return await base.lookupCommit(mutation)
    }
    func loadOriginalState() async -> BackendOutcome<OriginalStoreSnapshot> { await base.loadOriginalState() }
    func commitOriginal(_ mutation: OriginalStoreMutation) async -> OriginalStoreCommitResult { await base.commitOriginal(mutation) }
    func lookupOriginalCommit(_ mutation: OriginalStoreMutation) async -> BackendOutcome<OriginalStoreCommitReceipt> {
        await base.lookupOriginalCommit(mutation)
    }
}
extension PhotoRecoveryJoinStore: OriginalStorePort, MediaOperationStorePort {}

private nonisolated struct PhotoTerminalSeed: Sendable {
    let record: PhotoRegistrationRecord
    let identity: RegistrationStoreIdentity
}

private nonisolated func photoTerminalSeed(_ run: ExplorationRunDirectory,
                                           candidate: StorageCandidate = .sqlite) async throws -> PhotoTerminalSeed {
    let f = try await PhotoSaveFixture.make(run: run, candidate: candidate)
    await f.media.configure(releaseBlocked: true)
    await f.library.configure(outcome: .unknown(localIdentifier: try .init(rawValue: "same-unknown-asset")))
    #expect(await f.coordinator.save(f.receipt, action: .init(rawValue: "terminal-before-old-owner-ended")) == .unknown)
    let record = try await f.latest()
    try #require(record.usageTerminal != nil && record.terminalUsageRelease == nil)
    return .init(record: record, identity: f.identity)
}

private nonisolated func photoTerminalStore(_ run: ExplorationRunDirectory,
                                            candidate: StorageCandidate = .sqlite) throws -> any MediaDiskStore {
    candidate == .sqlite ? try SQLiteRecordingStore(run: run, mode: .openExisting)
        : try AtomicFileRecordingStore(run: run, mode: .openExisting)
}
