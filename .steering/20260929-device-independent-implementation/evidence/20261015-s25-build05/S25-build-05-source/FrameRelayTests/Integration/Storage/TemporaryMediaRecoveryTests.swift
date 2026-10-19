import Foundation
import Testing
@testable import FrameRelay

struct TemporaryMediaRecoveryTests {
    @Test(arguments: [false, true])
    func acquireAndReleaseFailuresCannotSplitUsageFromLease(afterCommit: Bool) async throws {
        try await withStorageRun { run in
            let bytes = Data(repeating: 1, count: 1024)
            let fixture = try await RenditionFixture.make(run: run, content: renditionContent(bytes), faultable: true)
            let receipt = try await fixture.complete(bytes)
            let faults = try #require(fixture.faults)
            await faults.configure(.acquire, afterCommit: afterCommit)
            let photoID = MediaUsageID(rawValue: "interrupted-photo-acquire")
            #expect(await fixture.temporary.acquireUsage(receipt.id, purpose: .photoHandoff, usageID: photoID) == .unknown)
            var state = try await fixture.temporary.stateFor(receipt.id)
            var original = try #require(try await mediaOriginalSnapshot(fixture.store).logicalOriginals.first)
            #expect(state.usages.count == (afterCommit ? 2 : 1))
            #expect(original.mediaReaders.count == state.usages.count)
            await faults.configure(nil)
            guard case .succeeded(let photo) = await fixture.temporary.acquireUsage(receipt.id, purpose: .photoHandoff, usageID: photoID)
            else { Issue.record("Exact acquire did not reconcile"); return }
            #expect(await fixture.temporary.releaseUsage(photo) == .succeeded(receipt.id))
            await faults.configure(.release, afterCommit: afterCommit)
            #expect(await fixture.temporary.releaseUsage(receipt.usage) == .unknown)
            state = try await fixture.temporary.stateFor(receipt.id)
            original = try #require(try await mediaOriginalSnapshot(fixture.store).logicalOriginals.first)
            #expect(state.usages.count == (afterCommit ? 0 : 1))
            #expect(original.mediaReaders.count == state.usages.count)
            #expect(state.reclaiming == afterCommit)
            await faults.configure(nil)
            #expect(await fixture.temporary.releaseUsage(receipt.usage) == .succeeded(receipt.id))
            #expect(await fixture.temporary.releaseUsage(receipt.usage) == .succeeded(receipt.id))
            #expect(try await fixture.temporary.stateFor(receipt.id).reclaimed)
            _ = try await fixture.scope.close()
        }
    }

    @Test func reopensAndFinishesCommittedReclamationAfterUnlinkWithoutReleasingOldActiveUses() async throws {
        try await withStorageRun { run in
            let interrupted = try await leaveInterruptedReclamation(run)
            let store = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let leases = RenditionReadLeases(store: store)
            let scope = try await RenditionMediaScope.open(original: interrupted.original, leases: leases)
            // Reacquiring the kernel lock is the real owner-lifetime boundary.
            let owner = try await ManagedTemporaryMedia.open(root: run.url.appendingPathComponent("temporary"), leases: leases, scope: scope)
            let before = try await owner.stateFor(interrupted.id)
            #expect(before.reclaiming && !before.reclaimed && before.usages.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: run.url.appendingPathComponent("temporary").appendingPathComponent(before.leaf).path))
            try await owner.recoverReclamation(interrupted.id)
            #expect(try await owner.stateFor(interrupted.id).reclaimed)
            #expect(try await mediaOriginalSnapshot(store).logicalOriginals.first?.mediaReaders.isEmpty == true)
            _ = try await scope.close()
        }
    }

    @Test func scopeClosesAdmissionButWaitsForPhotoCallbackAndReleasesRootOnlyAfterAllOwnersTerminate() async throws {
        try await withStorageRun { run in
            let bytes = Data(repeating: 7, count: 1024)
            let fixture = try await RenditionFixture.make(run: run, content: renditionContent(bytes))
            let receipt = try await fixture.complete(bytes)
            guard case .succeeded(let photo) = await fixture.temporary.acquireUsage(receipt.id, purpose: .photoHandoff,
                usageID: .init(rawValue: "active-photo")) else { Issue.record("No photo use"); return }
            let local = try await fixture.temporary.resolvePhotoMedia(photo)
            await #expect(throws: BackendContractError.readersActive) { try await fixture.scope.close() }
            #expect(FileManager.default.fileExists(atPath: local.url.path))
            #expect(await fixture.temporary.acquireUsage(receipt.id, purpose: .playback, usageID: .init(rawValue: "late")) == .failed(.rejected))
            let nextScope = try await RenditionMediaScope.open(original: receipt.rendition.original, leases: fixture.leases)
            await #expect(throws: BackendContractError.readersActive) {
                try await ManagedTemporaryMedia.open(root: run.url.appendingPathComponent("temporary"), leases: fixture.leases, scope: nextScope)
            }
            try await fixture.temporary.finishPhotoMedia(photo)
            await #expect(throws: BackendContractError.readersActive) { try await fixture.scope.close() }
            #expect(FileManager.default.fileExists(atPath: local.url.path))
            #expect(try await fixture.temporary.stateFor(receipt.id).usages.map(\.usage) == [photo])
            // Explicit S31-success boundary; a callback by itself is insufficient.
            #expect(await fixture.temporary.releaseUsage(photo) == .succeeded(receipt.id))
            let terminal = try await fixture.scope.close()
            #expect(terminal.factoryAdmissionClosed && terminal.registeredOwners == terminal.observations.count)
            #expect(terminal.observations.allSatisfy { $0.terminal.started == $0.terminal.completed && $0.terminal.handlesClosed })
            #expect(try await mediaOriginalSnapshot(fixture.store).logicalOriginals.first?.mediaReconciliation == nil)
            await #expect(throws: BackendContractError.unknownResult) {
                try await fixture.scope.reconcile(external: UnobservedExternalOwners())
            }
            let reopened = try await ManagedTemporaryMedia.open(root: run.url.appendingPathComponent("temporary"), leases: fixture.leases, scope: nextScope)
            #expect(try await reopened.stateFor(receipt.id).reclaimed)
            _ = try await nextScope.close()
        }
    }

    @Test func heldReaderRejectsLeafReplacementAndDoesNotUnlinkReplacement() async throws {
        try await withStorageRun { run in
            let bytes = Data(repeating: 2, count: 1024)
            let fixture = try await RenditionFixture.make(run: run, content: renditionContent(bytes))
            let receipt = try await fixture.complete(bytes)
            _ = try await fixture.temporary.read(receipt.usage, offset: 0, length: 16)
            let state = try await fixture.temporary.stateFor(receipt.id)
            let file = run.url.appendingPathComponent("temporary").appendingPathComponent(state.leaf)
            let moved = run.url.appendingPathComponent("held-original-bytes")
            try FileManager.default.moveItem(at: file, to: moved)
            try bytes.write(to: file, options: .withoutOverwriting)
            await #expect(throws: BackendContractError.identityMismatch) {
                try await fixture.temporary.read(receipt.usage, offset: 0, length: 16)
            }
            #expect(await fixture.temporary.releaseUsage(receipt.usage) == .unknown)
            #expect(try Data(contentsOf: file) == bytes && Data(contentsOf: moved) == bytes)
            #expect(try await fixture.temporary.stateFor(receipt.id).usages.count == 1)
        }
    }

    @Test func photoTerminalDetectsTruncationAndRetainsOtherUsageAndReconciliationState() async throws {
        try await withStorageRun { run in
            let bytes = Data(repeating: 3, count: 1024)
            let fixture = try await RenditionFixture.make(run: run, content: renditionContent(bytes))
            let receipt = try await fixture.complete(bytes)
            guard case .succeeded(let photo) = await fixture.temporary.acquireUsage(receipt.id, purpose: .photoHandoff,
                usageID: .init(rawValue: "photo-truncated")) else { Issue.record("No photo use"); return }
            let local = try await fixture.temporary.resolvePhotoMedia(photo)
            let handle = try FileHandle(forWritingTo: local.url)
            try handle.truncate(atOffset: 512); try handle.close()
            await #expect(throws: BackendContractError.identityMismatch) { try await fixture.temporary.finishPhotoMedia(photo) }
            #expect(await fixture.temporary.releaseUsage(photo) == .unknown)
            #expect(try await fixture.temporary.stateFor(receipt.id).usages.count == 2)
            #expect(try await fixture.temporary.usageSnapshot(receipt.id).openHandles == 0)
            #expect(try await mediaOriginalSnapshot(fixture.store).logicalOriginals.first?.mediaReaders.count == 2)
        }
    }
}

nonisolated private func leaveInterruptedReclamation(_ run: ExplorationRunDirectory) async throws -> (id: TemporaryMediaID, original: OriginalContent) {
    let bytes = Data(repeating: 4, count: 1024)
    let fixture = try await RenditionFixture.make(run: run, content: renditionContent(bytes), faultable: true)
    let receipt = try await fixture.complete(bytes)
    await fixture.faults?.configure(.reclaimed)
    #expect(await fixture.temporary.releaseUsage(receipt.usage) == .unknown)
    let state = try await fixture.temporary.stateFor(receipt.id)
    #expect(state.usages.isEmpty && state.reclaiming && !state.reclaimed)
    return (receipt.id, receipt.rendition.original)
}

private struct UnobservedExternalOwners: RenditionExternalOwnersPort {
    nonisolated func observeTerminal(original: OriginalContent, epoch: ReaderReconciliationEpoch) async throws -> EvidenceID {
        throw BackendContractError.unknownResult
    }
}
