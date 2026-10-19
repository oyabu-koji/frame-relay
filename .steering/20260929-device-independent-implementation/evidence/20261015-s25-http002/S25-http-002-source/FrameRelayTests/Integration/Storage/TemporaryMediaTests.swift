import Foundation
import Testing
@testable import FrameRelay

struct TemporaryMediaTests {
    @Test(arguments: StorageCandidate.allCases)
    func completeFileMultipleUsesRetainUntilPhotoCallbackAndFinalClose(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let bytes = Data((0..<131_079).map { UInt8($0 % 251) })
            let fixture = try await RenditionFixture.make(run: run, content: renditionContent(bytes), candidate: candidate)
            let complete = try await fixture.complete(bytes)
            #expect(complete.hasCompleteCoverage)
            #expect(complete.verifiedContent == fixture.command.distribution.rendition.deliveryContent)
            guard case .succeeded(let photo) = await fixture.temporary.acquireUsage(complete.id, purpose: .photoHandoff,
                usageID: .init(rawValue: "photo")) else { Issue.record("Complete file denied photo use"); return }
            let local = try await fixture.temporary.resolvePhotoMedia(photo)
            #expect(local.handoff.capturedAt == RenditionFixture.capturedAt)
            #expect(try Data(contentsOf: local.url) == bytes)
            #expect(await fixture.temporary.releaseUsage(photo) == .inProgress)
            #expect(try await fixture.temporary.read(complete.usage, offset: 65_530, length: 32) == bytes.subdata(in: 65_530..<65_562))
            #expect(await fixture.temporary.releaseUsage(complete.usage) == .succeeded(complete.id))
            let retained = try await fixture.temporary.usageSnapshot(complete.id)
            #expect(retained.uses == 1 && retained.openHandles == 1 && retained.fileBytes == UInt64(bytes.count))
            try await fixture.temporary.finishPhotoMedia(photo)
            #expect(await fixture.temporary.releaseUsage(photo) == .succeeded(complete.id))
            let released = try await fixture.temporary.usageSnapshot(complete.id)
            #expect(released.uses == 0 && released.openHandles == 0 && released.fileBytes == 0 && released.closedHandles > 0)
            #expect(!FileManager.default.fileExists(atPath: local.url.path))
            #expect(try await mediaOriginalSnapshot(fixture.store).logicalOriginals.first?.mediaReaders.isEmpty == true)
            let reopened: any MediaDiskStore = candidate == .sqlite
                ? try SQLiteRecordingStore(run: run, mode: .openExisting)
                : try AtomicFileRecordingStore(run: run, mode: .openExisting)
            let durable = try #require(try await mediaSnapshot(reopened).temporaryMedia.first)
            #expect(durable.reclaimed && durable.capturedAt == RenditionFixture.capturedAt)
        }
    }

    @Test func rangeHoleAndWholeHashMismatchNeverProducePhotoHandoff() async throws {
        try await withStorageRun { run in
            let bytes = Data(repeating: 8, count: 1024)
            let fixture = try await RenditionFixture.make(run: run, content: renditionContent(bytes))
            let receipt = try await fixture.create()
            try await fixture.temporary.store(bytes.prefix(512), range: .init(lowerBound: 0, upperBound: 512), using: receipt.usage)
            try await fixture.temporary.store(bytes.suffix(511), range: .init(lowerBound: 513, upperBound: 1024), using: receipt.usage)
            await #expect(throws: BackendContractError.ineligibleOriginal) { try await fixture.temporary.verify(receipt.usage) }
            #expect(await fixture.temporary.acquireUsage(receipt.id, purpose: .photoHandoff, usageID: .init(rawValue: "hole")) == .failed(.rejected))
            try await fixture.temporary.store(Data([9]), range: .init(lowerBound: 512, upperBound: 513), using: receipt.usage)
            await #expect(throws: BackendContractError.identityMismatch) { try await fixture.temporary.verify(receipt.usage) }
            #expect(await fixture.temporary.acquireUsage(receipt.id, purpose: .photoHandoff, usageID: .init(rawValue: "hash")) == .failed(.rejected))
            #expect(await fixture.temporary.releaseUsage(receipt.usage) == .succeeded(receipt.id))
        }
    }

    @Test func reopenPreservesOldUsageAndRejectsOldEpochReleaseAndSameLengthTamper() async throws {
        try await withStorageRun { run in
            let bytes = Data(repeating: 5, count: 2048)
            let fixture = try await RenditionFixture.make(run: run, content: renditionContent(bytes))
            let receipt = try await fixture.complete(bytes)
            let reopened = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let newLeases = RenditionReadLeases(store: reopened)
            let newScope = try await RenditionMediaScope.open(original: fixture.command.distribution.rendition.original, leases: newLeases)
            await #expect(throws: BackendContractError.readersActive) {
                try await ManagedTemporaryMedia.open(root: run.url.appendingPathComponent("temporary"), leases: newLeases, scope: newScope)
            }
            let owner = fixture.temporary
            guard case .succeeded(let inspected) = await owner.inspect(receipt.id) else { Issue.record("Reopen lost file"); return }
            #expect(inspected.verifiedContent == receipt.verifiedContent)
            let record = try #require(try await owner.stateFor(receipt.id).usages.first)
            await #expect(throws: BackendContractError.staleGeneration) {
                try await newLeases.check(record.lease)
            }
            let before = try await mediaSnapshot(reopened)
            #expect(await reopened.commit(.init(expectedRevision: before.revision,
                change: .temporary(command: .init(rawValue: "wrong-epoch"), value: .release(receipt.id, record)))) == .rejected(.staleGeneration))
            let state = try await owner.stateFor(receipt.id)
            let file = run.url.appendingPathComponent("temporary").appendingPathComponent(state.leaf)
            let handle = try FileHandle(forWritingTo: file)
            try handle.write(contentsOf: Data([1])); try handle.close()
            #expect(await owner.inspect(receipt.id) == .failed(.contentMismatch))
            #expect(try await mediaOriginalSnapshot(reopened).logicalOriginals.first?.mediaReaders.count == 1)
            #expect(FileManager.default.fileExists(atPath: file.path))
        }
    }

    @Test func partialReadAndReusedUsageIDAreRejectedWithoutRemovingFirstUse() async throws {
        try await withStorageRun { run in
            let fixture = try await RenditionFixture.make(run: run, content: renditionContent(Data(repeating: 1, count: 32)))
            let receipt = try await fixture.create()
            await #expect(throws: BackendContractError.ineligibleOriginal) {
                try await fixture.temporary.read(receipt.usage, offset: 0, length: 1)
            }
            #expect(await fixture.temporary.acquireUsage(receipt.id, purpose: .playback, usageID: receipt.usage.id) == .succeeded(receipt.usage))
            #expect(try await fixture.temporary.usageSnapshot(receipt.id).uses == 1)
        }
    }
}
