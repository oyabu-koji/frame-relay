import Foundation
import Testing
@testable import FrameRelay

struct PhotoSaveCoordinatorTests {
    @Test(arguments: StorageCandidate.allCases)
    func sameWriterAndS25DiskMediaReachSuccessBeforeUsageRelease(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run, candidate: candidate)
            guard case .succeeded(let saved) = await f.coordinator.save(f.receipt, action: .init(rawValue: "explicit-save")) else {
                Issue.record("Local fixture save failed"); return
            }
            #expect(saved.outcome == .succeeded(localIdentifier: try .init(rawValue: "s31-fixture-asset")))
            #expect(saved.registration.intent.capturedAt == RenditionFixture.capturedAt)
            #expect(await f.library.requests == [.addOnly])
            #expect(await f.library.additions.count == 1)
            #expect(await f.library.completed == 1)
            #expect(try await f.library.fileBytes.map { try renditionContent($0) } == f.receipt.rendition.deliveryContent)
            #expect(await f.media.finishes == 1)
            #expect(await f.media.releases == 1)
            let released = try await f.rendition.temporary.stateFor(f.receipt.id)
            #expect(released.usages.isEmpty && released.reclaimed)
            #expect(try await f.rendition.temporary.usageSnapshot(f.receipt.id).openHandles == 0)
            let reopened: any MediaDiskStore = candidate == .sqlite
                ? try SQLiteRecordingStore(run: run, mode: .openExisting)
                : try AtomicFileRecordingStore(run: run, mode: .openExisting)
            let next = f.reopenedCoordinator(store: reopened)
            #expect(await next.restore() == .succeeded(try await mediaSnapshot(reopened).photoRegistrations))
            #expect(await next.save(f.receipt, action: .init(rawValue: "repeat-save")) == .failed(.rejected))
            #expect(await f.library.additions.count == 1)
            #expect(await f.library.requests == [.addOnly])
        }
    }

    @Test(arguments: [false, true])
    func uncertainIntentNeverBecomesPermissionToInvokePhotos(afterCommit: Bool) async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run)
            await f.faults.configure(.intent, afterCommit: afterCommit)
            #expect(await f.coordinator.save(f.receipt, action: .init(rawValue: "uncertain-intent")) == .unknown)
            #expect(await f.coordinator.save(f.receipt, action: .init(rawValue: "new-action")) == .unknown)
            #expect(await f.library.additions.isEmpty)
            #expect(await f.library.requests.isEmpty)
            #expect(await f.media.resolves == 0)
            #expect(await f.media.releases == 0)
            #expect(try await mediaSnapshot(f.rendition.store).photoRegistrations.count == (afterCommit ? 1 : 0))
            await f.faults.configure()
            if afterCommit {
                let reopened = try SQLiteRecordingStore(run: run, mode: .openExisting)
                let next = f.reopenedCoordinator(store: reopened)
                _ = await next.restore()
                #expect(await next.save(f.receipt, action: .init(rawValue: "after-reopen")) == .failed(.rejected))
            }
            #expect(await f.library.additions.isEmpty)
        }
    }

    @Test(arguments: [false, true])
    func interruptionAtResultCommitRetainsMediaAndNeverReadds(afterCommit: Bool) async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run)
            await f.faults.configure(.result, afterCommit: afterCommit)
            #expect(await f.coordinator.save(f.receipt, action: .init(rawValue: "sdk-finished")) == .unknown)
            #expect(await f.library.additions.count == 1)
            #expect(await f.library.completed == 1)
            #expect(await f.media.finishes == 1)
            #expect(await f.media.releases == 0)
            let held = try await f.rendition.temporary.usageSnapshot(f.receipt.id)
            #expect(held.uses == 1 && held.openHandles == 0 && held.fileBytes > 0)
            let original = try await f.latest()
            #expect((original.outcome != nil) == afterCommit)
            let reopened = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let next = f.reopenedCoordinator(store: reopened)
            _ = await next.restore()
            #expect(await next.save(f.receipt, action: .init(rawValue: "new-add-after-crash")) == .failed(.rejected))
            #expect(await f.library.additions.count == 1)
            // Restoration and result checking cannot fabricate a lost identifier.
            if !afterCommit {
                let reconciler = PhotoRegistrationReconciler(store: reopened, identity: f.identity, library: f.library)
                guard case .succeeded(let checked) = await reconciler.reconcile(original.registration.intent.key,
                    action: .init(rawValue: "check-intent-only")) else { Issue.record("No presence observation"); return }
                #expect(checked.currentPresence?.presence == .correspondenceUnknown)
                #expect(checked.outcome == nil)
                #expect(await f.library.requests == [.addOnly])
                #expect(await f.library.lookups.isEmpty)
            }
        }
    }

    @Test func deniedSaveRetainsProofOfNonStartAndOnlyExplicitLinkedRetryCanAdd() async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run)
            await f.library.configure(add: .denied)
            let first = MediaOperationID(rawValue: "denied-save")
            guard case .succeeded(let denied) = await f.coordinator.save(f.receipt, action: first) else { Issue.record("No denied result"); return }
            #expect(denied.outcome == .notAttempted(.authorizationRequired))
            #expect(await f.library.additions.isEmpty)
            #expect(await f.library.requests.isEmpty)
            #expect(await f.media.resolves == 0)
            #expect(await f.media.finishes == 0)
            #expect(await f.media.releases == 0)
            await f.library.configure(add: .authorized)
            #expect(await f.coordinator.save(f.receipt, action: .init(rawValue: "implicit-retry")) == .failed(.rejected))
            #expect(await f.coordinator.save(f.receipt, action: .init(rawValue: "wrong-retry"), retryOf: .init(rawValue: "other")) == .failed(.rejected))
            guard case .succeeded(let retried) = await f.coordinator.save(f.receipt,
                action: .init(rawValue: "explicit-retry"), retryOf: first) else { Issue.record("Explicit retry failed"); return }
            #expect(retried.registration.intent.retryOf == first)
            #expect(await f.library.additions.count == 1)
            #expect(try await mediaSnapshot(f.rendition.store).photoRegistrations.count == 2)
        }
    }

    @Test(arguments: [PhotoRegistrationOutcome.unknown(localIdentifier: nil),
                      .unknown(localIdentifier: try! .init(rawValue: "unknown-exact-id")),
                      .succeeded(localIdentifier: nil), .failed(.rejected), .notAttempted(.authorizationRequired)])
    func settledResultPreservesItsMeaningAndDoesNotRepeatTheSameOperation(outcome: PhotoRegistrationOutcome) async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run)
            await f.library.configure(outcome: outcome)
            let action = MediaOperationID(rawValue: "one-operation")
            guard case .succeeded(let saved) = await f.coordinator.save(f.receipt, action: action) else { Issue.record("No recorded result"); return }
            #expect(saved.outcome == outcome)
            #expect(await f.coordinator.save(f.receipt, action: action) == .succeeded(saved))
            #expect(await f.coordinator.save(f.receipt, action: .init(rawValue: "unlinked-operation")) == .failed(.rejected))
            #expect(await f.library.additions.count == 1)
            if case .succeeded = outcome {
                #expect(await f.media.releases == 1)
            } else { #expect(await f.media.releases == 0) }
            let reconciler = PhotoRegistrationReconciler(store: f.faults, identity: f.identity, library: f.library)
            guard case .succeeded(let checked) = await reconciler.reconcile(saved.registration.intent.key,
                action: .init(rawValue: "explicit-result-check")) else { Issue.record("No exact observation"); return }
            #expect(checked.outcome == outcome)
            if outcome.localIdentifier == nil {
                #expect(checked.currentPresence?.presence == .correspondenceUnknown)
                #expect(await f.library.requests == [.addOnly])
                #expect(await f.library.lookups.isEmpty)
            }
        }
    }

    @Test(arguments: [PhotoLibraryAuthorization.authorized, .limited, .denied, .restricted],
          [PhotoAssetPresence.present, .notFound])
    func exactPresenceNeverRewritesUnknownAsNotSavedOrPermitsReaddition(authorization: PhotoLibraryAuthorization,
                                                                       presence: PhotoAssetPresence) async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run)
            let sdkOutcome = PhotoRegistrationOutcome.unknown(localIdentifier: try .init(rawValue: "only-this-identifier"))
            await f.library.configure(read: authorization, outcome: sdkOutcome, presence: presence)
            guard case .succeeded(let saved) = await f.coordinator.save(f.receipt,
                action: .init(rawValue: "unknown-sdk-result")) else { Issue.record("No unknown result"); return }
            let reconciler = PhotoRegistrationReconciler(store: f.faults, identity: f.identity, library: f.library)
            guard case .succeeded(let checked) = await reconciler.reconcile(saved.registration.intent.key,
                action: .init(rawValue: "explicit-presence")) else { Issue.record("No presence"); return }
            #expect(checked.outcome == sdkOutcome)
            let readable = authorization == .authorized || authorization == .limited
            #expect(checked.currentPresence?.presence == (readable ? presence : .unavailable))
            #expect(checked.currentPresence?.authorization == authorization)
            #expect(await f.library.lookups.count == (readable ? 1 : 0))
            #expect(await f.library.requests == [.addOnly])
            #expect(await f.coordinator.save(f.receipt, action: .init(rawValue: "after-external-deletion"),
                retryOf: saved.registration.intent.operation) == .failed(.rejected))
            #expect(await f.library.additions.count == 1)
        }
    }

    @Test func delayedTerminalKeepsUsageAndCancellationDoesNotCancelOwnedSaveOrAllowDoubleTap() async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run)
            await f.library.configure(delayed: true)
            let caller = Task { await f.coordinator.save(f.receipt, action: .init(rawValue: "owned-save")) }
            #expect(await renditionEventually { await f.library.additions.count == 1 })
            caller.cancel()
            #expect(await f.coordinator.save(f.receipt, action: .init(rawValue: "double-tap")) == .inProgress)
            #expect(await f.coordinator.reconcile(.init(rendition: f.receipt.rendition), action: .init(rawValue: "too-early")) == .inProgress)
            let held = try await f.rendition.temporary.usageSnapshot(f.receipt.id)
            #expect(held.uses == 1 && held.openHandles == 1 && held.fileBytes > 0)
            #expect(await f.media.finishes == 0)
            #expect(await f.media.releases == 0)
            #expect(try await f.latest().outcome == nil)
            await f.library.complete()
            guard case .succeeded = await caller.value else { Issue.record("Cancellation discarded external completion"); return }
            #expect(await f.library.completed == 1)
            #expect(await f.media.finishes == 1)
            #expect(await f.media.releases == 1)
            #expect(try await f.rendition.temporary.usageSnapshot(f.receipt.id).fileBytes == 0)
        }
    }

    @Test(arguments: [false, true])
    func finishFailureOrMismatchedIntentStaysUnknownAndRetainsUsage(wrongIntent: Bool) async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run)
            await f.library.configure(wrongIntent: wrongIntent)
            await f.media.configure(finishFails: !wrongIntent)
            guard case .succeeded(let saved) = await f.coordinator.save(f.receipt,
                action: .init(rawValue: "unsafe-terminal")) else { Issue.record("No uncertain result"); return }
            guard case .unknown? = saved.outcome else { Issue.record("Unsafe terminal became success"); return }
            #expect(await f.media.releases == 0)
            #expect(try await f.rendition.temporary.usageSnapshot(f.receipt.id).uses == 1)
            #expect(await f.coordinator.save(f.receipt, action: .init(rawValue: "must-not-add-again")) == .failed(.rejected))
            if !wrongIntent {
                await f.media.configure()
                try await f.media.finishPhotoMedia(f.receipt.usage)
            } else { #expect(saved.localIdentifier == nil) }
        }
    }

    @Test func alteredReceiptAndIntentOnlyRestoreCannotEnterSDK() async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run)
            await f.faults.configure(badReceipt: true)
            #expect(await f.coordinator.save(f.receipt, action: .init(rawValue: "bad-receipt")) == .unknown)
            #expect(await f.library.additions.isEmpty)
            #expect(await f.library.requests.isEmpty)
            await f.faults.configure()
            let next = f.reopenedCoordinator()
            guard case .succeeded(let records) = await next.restore() else { Issue.record("No durable intent"); return }
            #expect(records.count == 1 && records[0].outcome == nil)
            #expect(await f.library.requests.isEmpty)
            #expect(await next.save(f.receipt, action: .init(rawValue: "retry-intent-only")) == .failed(.rejected))
        }
    }

    @Test func limitedAddOnlyIsNotAnAuthorizationForSaving() async throws {
        try await withStorageRun { run in
            let f = try await PhotoSaveFixture.make(run: run)
            await f.library.configure(add: .limited)
            guard case .succeeded(let record) = await f.coordinator.save(f.receipt,
                action: .init(rawValue: "unsupported-add-status")) else { Issue.record("No not-attempted record"); return }
            #expect(record.outcome == .notAttempted(.authorizationRequired))
            #expect(await f.library.additions.isEmpty)
            #expect(await f.media.resolves == 0)
        }
    }
}
