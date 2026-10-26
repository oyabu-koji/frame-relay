import Foundation
import Darwin
import Testing
@testable import FrameRelay

struct OriginalRemovalIntegrationTests {
    @Test(arguments: StorageCandidate.allCases)
    func actualCleanupKeepsIndependentOriginalsReservationsAndExternalData(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let fixture = try OriginalRemovalFixture(run: run, candidate: candidate)
            let a = try await fixture.original("cleanup-a")
            let b = try await fixture.original("ineligible-b")
            let c = try await fixture.original("cleanup-c")
            _ = try await fixture.evidence(a); _ = try await fixture.evidence(c)
            let sentinel = run.url.deletingLastPathComponent().appendingPathComponent("external-sentinel-" + UUID().uuidString)
            let external = Data("external synthetic media untouched".utf8)
            try external.write(to: sentinel, options: .withoutOverwriting)
            let bURL = try await fixture.files.existingURL(for: b.reference)
            let bBytes = try Data(contentsOf: bURL)
            let batch = try fixture.batch([a, b, c])
            guard case .succeeded(let result) = await fixture.coordinator().start(batch) else {
                Issue.record("Expected per-target durable outcomes"); return
            }
            #expect(result.targets.map(\.status) == [.resolved(.removed), .notExecuted(.ineligible), .resolved(.removed)])
            #expect(await fixture.files.observeFile(a.reference) == .absent)
            #expect(await fixture.files.observeFile(c.reference) == .absent)
            #expect(try Data(contentsOf: bURL) == bBytes)
            #expect(try Data(contentsOf: sentinel) == external)
            for binding in [a, b, c] {
                try ExplorationRunDirectory.requireRegularFile(run.url.appendingPathComponent(binding.reference.rawValue + ".reservation"))
            }
            let reopened = try OriginalRemovalFixture.open(.openExisting(at: run.url), candidate: candidate)
            let snapshot = try await mediaOriginalSnapshot(reopened)
            #expect(snapshot.removalBatches == [result])
            #expect(snapshot.originals.count == 3)
            #expect(try await mediaSnapshot(reopened).verifications.count == 2)
            #expect(try await mediaSnapshot(reopened).photoRegistrations.isEmpty)
        }
    }

    @Test(arguments: ["content", "symlink", "hardlink"])
    func fileSpecificFailureKeepsReservationAndContinuesIndependentTarget(kind: String) async throws {
        try await withStorageRun { run in
            let fixture = try OriginalRemovalFixture(run: run)
            let a = try await fixture.original("tampered-a")
            let b = try await fixture.original("independent-b")
            _ = try await fixture.evidence(a); _ = try await fixture.evidence(b)
            let aURL = try await fixture.files.existingURL(for: a.reference)
            let sentinel = run.url.appendingPathComponent("untouched-external.mov")
            try Data("external target".utf8).write(to: sentinel, options: .withoutOverwriting)
            switch kind {
            case "content":
                let writer = try FileHandle(forWritingTo: aURL)
                try writer.write(contentsOf: Data([0x5a])); try writer.synchronize(); try writer.close()
            case "symlink":
                try FileManager.default.moveItem(at: aURL, to: run.url.appendingPathComponent("retained-a.mov"))
                try FileManager.default.createSymbolicLink(at: aURL, withDestinationURL: sentinel)
            default:
                try FileManager.default.linkItem(at: aURL, to: run.url.appendingPathComponent("second-hard-link.mov"))
            }
            let sentinelBefore = try Data(contentsOf: sentinel)
            let batch = try fixture.batch([a, b])
            guard case .succeeded(let result) = await fixture.coordinator().start(batch) else {
                Issue.record("A file-local failure must not stop an independent target"); return
            }
            #expect(result.targets[0].status == .reserved(batch.intent(for: batch.targets[0])))
            #expect(result.targets[1].status == .resolved(.removed))
            #expect(await fixture.files.observeFile(b.reference) == .absent)
            #expect(try Data(contentsOf: sentinel) == sentinelBefore)
            let before = try await mediaOriginalSnapshot(fixture.store)
            let recovery = OriginalRemovalReconciler(store: fixture.store, execution: fixture.access)
            _ = await recovery.reconcile()
            #expect(try await mediaOriginalSnapshot(fixture.store) == before)
        }
    }

    @Test func activeSDKAndUnknownPersistedReaderCannotBeDeclaredReleased() async throws {
        try await withStorageRun { run in
            let fixture = try OriginalRemovalFixture(run: run)
            let binding = try await fixture.original("active-reader")
            _ = try await fixture.evidence(binding)
            guard case .succeeded(let source) = await fixture.access.acquirePlayback(binding.original,
                operation: .init(rawValue: "player"), leaseID: .init(rawValue: "reader")) else {
                Issue.record("Expected real open descriptor"); return
            }
            let lease = source.lease
            guard case .succeeded(let attachment) = await fixture.access.attachReader(lease, id: .init(rawValue: "sdk")) else {
                Issue.record("Expected SDK attachment"); return
            }
            await fixture.access.requestReaderStop(lease)
            #expect(await fixture.access.releaseRead(lease) == .inProgress)
            let batch = try fixture.batch([binding])
            guard case .succeeded(let result) = await fixture.coordinator().start(batch) else {
                Issue.record("Expected unexecuted target"); return
            }
            #expect(result.targets.first?.status == .notExecuted(.terminationUnconfirmed))
            let reopened = try OriginalRemovalFixture.open(.openExisting(at: run.url), candidate: .sqlite)
            let recoveredAccess = ManagedOriginalAccess(store: reopened, originals: ManagedOriginalStore(run: run))
            #expect(await recoveredAccess.reconcileReaders(binding.original) == .inProgress)
            #expect(await recoveredAccess.recoverPersistedReaders(binding.original) == .unknown)
            #expect(await fixture.files.observeFile(binding.reference) == .present(byteCount: binding.original.content.byteCount))
            _ = await fixture.access.readerDidFinish(attachment)
            #expect(await fixture.access.releaseRead(lease) == .succeeded(.init(lease: lease)))
            // Reusing the old command is observation only, even after release.
            #expect(await fixture.coordinator().start(batch) == .succeeded(result))
            let fresh = try fixture.batch([binding], name: "new-user-action")
            guard case .succeeded(let removed) = await fixture.coordinator().start(fresh) else {
                Issue.record("Fresh explicit action should succeed after actual release"); return
            }
            #expect(removed.targets.first?.status == .resolved(.removed))
        }
    }

    @Test func oldZeroReaderReceiptCannotAuthorizeAfterAnotherReaderOpenedAndClosed() async throws {
        try await withStorageRun { run in
            let fixture = try OriginalRemovalFixture(run: run)
            let binding = try await fixture.original("stale-zero-reader")
            let (selection, _) = try await fixture.evidence(binding)
            let batch = try fixture.batch([binding])
            let target = batch.targets[0]
            try await mediaReconcile(fixture.store, original: binding.original)
            let snapshot = try await mediaOriginalSnapshot(fixture.store)
            guard case .committed = await fixture.store.commitOriginal(.init(operation: batch.operation,
                expectedRevision: snapshot.revision, change: .removalBatch(batch))),
                  case .succeeded(let stale) = await fixture.access.reconcileReaders(binding.original),
                  case .succeeded(let source) = await fixture.access.acquirePlayback(binding.original,
                    operation: .init(rawValue: "intervening-play"), leaseID: .init(rawValue: "intervening-reader")) else {
                Issue.record("Expected initial zero-reader observation and real intervening FD"); return
            }
            #expect(await fixture.access.releaseRead(source.lease) == .succeeded(.init(lease: source.lease)))
            // A real close does not manufacture the independent SDK/OS epoch
            // observation invalidated by the intervening acquisition.
            try await mediaReconcile(fixture.store, original: binding.original)
            guard case .succeeded(let fresh) = await fixture.access.reconcileReaders(binding.original) else {
                Issue.record("The intervening descriptor should actually be closed"); return
            }
            #expect(stale.accessGeneration != fresh.accessGeneration)
            let result = await fixture.access.removeOriginal(batch: batch, target: target, evidence: selection,
                quiescence: .init(target: target, transport: .neverStarted(.original(binding.original)), readers: stale))
            #expect(result == .notExecuted)
            let after = try await mediaOriginalSnapshot(fixture.store)
            #expect(after.removalBatches.first?.targets.first?.status == .unprocessed)
            #expect(after.originals.first?.removal == nil)
            #expect(await fixture.files.observeFile(binding.reference) == .present(byteCount: binding.original.content.byteCount))
        }
    }

    @Test(arguments: [OriginalRemovalFaultStore.Stage.batch, .reserve, .boundary, .result], [false, true])
    @MainActor func commitInterruptionRestoresFactsWithoutRetryingUnlink(stage: OriginalRemovalFaultStore.Stage, after: Bool) async throws {
        try await withStorageRun { run in
            let fixture = try OriginalRemovalFixture(run: run)
            let binding = try await fixture.original("interruption")
            _ = try await fixture.evidence(binding)
            let faulty = OriginalRemovalFaultStore(base: fixture.store)
            faulty.configure(stage, afterCommit: after)
            let access = ManagedOriginalAccess(store: faulty, originals: fixture.files)
            let batch = try fixture.batch([binding])
            #expect(await fixture.coordinator(store: faulty, access: access).start(batch) == .unknown)
            let before = try await mediaOriginalSnapshot(fixture.store)
            let wasUnlinked = stage == .result || (stage == .boundary && after)
            #expect(await fixture.files.observeFile(binding.reference) == (wasUnlinked ? .absent : .present(byteCount: binding.original.content.byteCount)))
            let reopened = try OriginalRemovalFixture.open(.openExisting(at: run.url), candidate: .sqlite)
            let recovered = ManagedOriginalAccess(store: reopened, originals: ManagedOriginalStore(run: run))
            let reconciler = OriginalRemovalReconciler(store: reopened, execution: recovered)
            guard case .succeeded(let records) = await reconciler.reconcile() else {
                Issue.record("Expected read-only fact recovery"); return
            }
            if stage == .batch && !after { #expect(records.isEmpty) }
            else {
                let status = try #require(records.first?.targets.first?.status)
                if wasUnlinked { #expect(status == .resolved(.removed)) }
                else if (stage == .reserve && after) || stage == .boundary { #expect(status == .resolved(.notRemoved)) }
                else { #expect(status == .unprocessed) }
            }
            // Reconciliation does not execute any accepted/unreserved target.
            #expect(await fixture.files.observeFile(binding.reference) == (wasUnlinked ? .absent : .present(byteCount: binding.original.content.byteCount)))
            if stage == .batch || (stage == .reserve && !after) {
                let afterRecovery = try await mediaOriginalSnapshot(reopened)
                #expect(afterRecovery.revision == before.revision)
                #expect(afterRecovery.originals == before.originals)
                #expect(afterRecovery.logicalOriginals == before.logicalOriginals)
                #expect(afterRecovery.removalBatches == before.removalBatches)
            }
        }
    }

    @Test(arguments: [OriginalRemovalFaultStore.Stage.batch, .reserve])
    @MainActor func lostIntentAndReserveRepliesWithExactLookupCanContinueOnce(stage: OriginalRemovalFaultStore.Stage) async throws {
        try await withStorageRun { run in
            let fixture = try OriginalRemovalFixture(run: run)
            let binding = try await fixture.original("lookup")
            _ = try await fixture.evidence(binding)
            let faulty = OriginalRemovalFaultStore(base: fixture.store)
            faulty.configure(stage, afterCommit: true, hideLookup: false)
            let access = ManagedOriginalAccess(store: faulty, originals: fixture.files)
            let batch = try fixture.batch([binding])
            let coordinator = fixture.coordinator(store: faulty, access: access)
            guard case .succeeded(let result) = await coordinator.start(batch) else {
                Issue.record("An exact committed mutation should allow the one live attempt"); return
            }
            #expect(result.targets.first?.status == .resolved(.removed))
            #expect(await coordinator.start(batch) == .succeeded(result))
        }
    }

    @Test(arguments: [false, true])
    func invalidationFirstRejectsCleanupAndRemovalFirstDefersInvalidation(removalFirst: Bool) async throws {
        try await withStorageRun { run in
            let fixture = try OriginalRemovalFixture(run: run)
            let binding = try await fixture.original("ordering")
            let (_, invalidation) = try await fixture.evidence(binding)
            let batch = try fixture.batch([binding])
            if !removalFirst {
                #expect(await fixture.access.reserveInvalidation(invalidation) == .succeeded(.init(record: invalidation)))
                guard case .succeeded(let result) = await fixture.coordinator().start(batch) else {
                    Issue.record("Invalidation-first should retain an unexecuted target"); return
                }
                #expect(result.targets.first?.status == .notExecuted(.ineligible))
                #expect(await fixture.files.observeFile(binding.reference) == .present(byteCount: binding.original.content.byteCount))
            } else {
                let barrier = OriginalRemovalDigestBarrier()
                let files = ManagedOriginalStore(run: run, digestCheckpoint: { _ in await barrier.checkpoint() })
                let access = ManagedOriginalAccess(store: fixture.store, originals: files)
                let coordinator = fixture.coordinator(access: access)
                let executing = Task { await coordinator.start(batch) }
                defer { Task { await barrier.resume() } }
                try await barrier.wait()
                #expect(await access.reserveInvalidation(invalidation) == .unknown)
                let reserved = try await mediaOriginalSnapshot(fixture.store)
                #expect(reserved.removalBatches.first?.targets.first?.status == .reserved(batch.intent(for: batch.targets[0])))
                await barrier.resume()
                guard case .succeeded(let result) = await executing.value else {
                    Issue.record("Deletion should resolve before invalidation can reserve"); return
                }
                #expect(result.targets.first?.status == .resolved(.removed))
                #expect(await access.reserveInvalidation(invalidation) == .succeeded(.init(record: invalidation)))
            }
        }
    }

    @Test(arguments: ["registration", "verification"])
    func latestCleanupConditionsAreRecheckedAfterFullRead(change: String) async throws {
        try await withStorageRun { run in
            let fixture = try OriginalRemovalFixture(run: run)
            let binding = try await fixture.original("latest-proof")
            let (selection, _) = try await fixture.evidence(binding)
            let batch = try fixture.batch([binding])
            let barrier = OriginalRemovalDigestBarrier()
            let files = ManagedOriginalStore(run: run, digestCheckpoint: { _ in await barrier.checkpoint() })
            let access = ManagedOriginalAccess(store: fixture.store, originals: files)
            let coordinator = fixture.coordinator(access: access)
            let executing = Task { await coordinator.start(batch) }
            defer { Task { await barrier.resume() } }
            try await barrier.wait()
            if change == "registration" {
                _ = try await mediaRegister(fixture.store, registration: .init(destination: selection.registration.destination,
                    id: .init(rawValue: "new-registration"), generation: .init(rawValue: 2)))
            } else {
                let old = try #require(try await mediaSnapshot(fixture.store).verifications.last)
                let proof = VerificationEvidence(id: .init(rawValue: "new-ineligible-proof"), context: old.expected,
                    finalSaveCompleted: true, verification: .assemblyOnly(binding.original.content), committed: true,
                    schemaVersion: "s32-contract", observedAt: Date(timeIntervalSince1970: 2))
                _ = try await mediaCommit(fixture.store, .verification(command: .init(rawValue: "new-proof-command"),
                    expected: old.expected, evidence: proof))
            }
            await barrier.resume()
            guard case .succeeded(let result) = await executing.value else {
                Issue.record("Changed cleanup evidence must resolve as not removed"); return
            }
            #expect(result.targets.first?.status == .resolved(.notRemoved))
            #expect(await files.observeFile(binding.reference) == .present(byteCount: binding.original.content.byteCount))
            #expect(try await mediaOriginalSnapshot(fixture.store).originals.first?.removal == nil)
        }
    }

    @Test(arguments: ["leaf", "lock", "root"])
    func pathReplacementDuringFullReadNeverDeletesReplacement(kind: String) async throws {
        try await withStorageRun { run in
            let fixture = try OriginalRemovalFixture(run: run, candidate: .atomicFile)
            let binding = try await fixture.original("path-swap")
            let movie = try await fixture.files.existingURL(for: binding.reference)
            let bytes = try Data(contentsOf: movie)
            let probe = OriginalRemovalCheckpointProbe()
            let files = ManagedOriginalStore(run: run, digestCheckpoint: { _ in
                await probe.record()
                switch kind {
                case "leaf":
                    try? FileManager.default.moveItem(at: movie, to: run.url.appendingPathComponent("held-original.mov"))
                    try? bytes.write(to: movie, options: .withoutOverwriting)
                case "lock":
                    try? FileManager.default.moveItem(at: run.url.appendingPathComponent("originals.lock"),
                        to: run.url.appendingPathComponent("held-originals.lock"))
                    try? Data().write(to: run.url.appendingPathComponent("originals.lock"), options: .withoutOverwriting)
                default:
                    let held = run.url.deletingLastPathComponent().appendingPathComponent("held-root-" + UUID().uuidString)
                    try? FileManager.default.moveItem(at: run.url, to: held)
                    _ = try? ExplorationRunDirectory.createNew(at: run.url)
                    try? bytes.write(to: movie, options: .withoutOverwriting)
                    try? Data().write(to: run.url.appendingPathComponent(binding.reference.rawValue + ".reservation"), options: .withoutOverwriting)
                }
            })
            do {
                let prepared = try await files.prepareOriginalRemoval(binding)
                defer { try? prepared.close() }
                #expect(throws: (any Error).self) { try prepared.unlink() }
            } catch {
                if !(await probe.reached) { Issue.record("Removal preparation failed before full-read checkpoint: \(error)") }
            }
            #expect(await probe.reached)
            #expect(try Data(contentsOf: movie) == bytes)
            if kind == "leaf" {
                #expect(try Data(contentsOf: run.url.appendingPathComponent("held-original.mov")) == bytes)
            }
        }
    }
}
