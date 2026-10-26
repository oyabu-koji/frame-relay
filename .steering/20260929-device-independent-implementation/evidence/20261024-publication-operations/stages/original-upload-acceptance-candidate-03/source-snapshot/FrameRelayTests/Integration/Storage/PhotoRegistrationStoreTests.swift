import Foundation
import Testing
@testable import FrameRelay

/// Explicit synthetic media and terminal values exercise the real common disk
/// writer. They do not claim PhotoKit success or production Rec.709 provenance.
struct PhotoRegistrationStoreTests {
    @Test(arguments: StorageCandidate.allCases, [false, true])
    func intentFaultKeepsExactMutationAndSourceUseAcrossReopen(candidate: StorageCandidate, afterCommit: Bool) async throws {
        try await withStorageRun { run in
            let operation = MediaOperationID(rawValue: "photo-intent")
            let fault: RecordingStoreFault = afterCommit
                ? .afterBackendCommitBeforeReply(.photo(operation)) : .beforeBackendCommit(.photo(operation))
            let fixture = try await PhotoStoreFixture.make(run: run, candidate: candidate, fault: fault)
            let mutation = try await photoMutation(fixture.store,
                command: operation, change: .intent(fixture.intent))
            #expect(await fixture.store.commit(mutation) == (afterCommit ? .unknown : .unavailable(.inaccessible)))
            let reopened = try photoDisk(candidate, run: run, mode: .openExisting)
            let snapshot = try await mediaSnapshot(reopened)
            #expect(snapshot.photoRegistrations.count == (afterCommit ? 1 : 0))
            if afterCommit {
                let registration = try #require(snapshot.photoRegistrations.first?.registration)
                #expect(registration.mutation == mutation)
                #expect(await reopened.lookupCommit(mutation) == .committed(registration.commit))
                #expect(await reopened.commit(mutation) == .committed(registration.commit))
                #expect(registration.mediaUse.usage == fixture.intent.usage)
                #expect(snapshot.temporaryMedia.first?.usages == [registration.mediaUse])
                let changedRevision = BackendStoreMutation(expectedRevision: mutation.expectedRevision + 1,
                    change: mutation.change, expectedStoreIdentity: mutation.expectedStoreIdentity)
                #expect(await reopened.lookupCommit(changedRevision) == .rejected(.identityMismatch))
            } else {
                #expect(await reopened.lookupCommit(mutation) == .unknown)
            }
        }
    }

    @Test(arguments: StorageCandidate.allCases, [false, true])
    func resultFaultDoesNotTurnIntentIntoPermissionToAddAgain(candidate: StorageCandidate, afterCommit: Bool) async throws {
        try await withStorageRun { run in
            let command = MediaOperationID(rawValue: "photo-result")
            let fault: RecordingStoreFault = afterCommit
                ? .afterBackendCommitBeforeReply(.photo(command)) : .beforeBackendCommit(.photo(command))
            let fixture = try await PhotoStoreFixture.make(run: run, candidate: candidate, fault: fault)
            _ = try await mediaCommit(fixture.store, .photo(command: fixture.intent.operation, value: .intent(fixture.intent)))
            let result = PhotoRegistrationResult(intent: fixture.intent, outcome: .succeeded(localIdentifier: nil))
            let mutation = try await photoMutation(fixture.store, command: command, change: .result(result))
            #expect(await fixture.store.commit(mutation) == (afterCommit ? .unknown : .unavailable(.inaccessible)))
            let reopened = try photoDisk(candidate, run: run, mode: .openExisting)
            let record = try #require(try await mediaSnapshot(reopened).photoRegistrations.first)
            #expect(record.outcome == (afterCommit ? .succeeded(localIdentifier: nil) : nil))
            if afterCommit {
                #expect(await reopened.lookupCommit(mutation) == .committed(try #require(record.results.last).commit))
            } else { #expect(await reopened.lookupCommit(mutation) == .unknown) }
            // A new process cannot use its fresh epoch as a new-add permit for
            // either an intent-only or a success-without-identifier history.
            let intent = try PhotoRegistrationIntent(operation: .init(rawValue: "unconditional-readd"),
                handoff: fixture.intent.handoff)
            let retry = try await photoMutation(reopened, command: intent.operation, change: .intent(intent))
            #expect(await reopened.commit(retry) == .rejected(.staleGeneration))
            // The duplicate rule is independently replayed under the original writer.
            let sameEpochRetry = try await photoMutation(fixture.store, command: intent.operation, change: .intent(intent))
            #expect(await fixture.store.commit(sameEpochRetry) == .rejected(.duplicateTarget))
        }
    }

    @Test func unknownCanReceiveDelayedExactTerminalButCannotBeReaddedOrRewritten() async throws {
        try await withStorageRun { run in
            let fixture = try await PhotoStoreFixture.make(run: run)
            let intentMutation = try await photoMutation(fixture.store,
                command: fixture.intent.operation, change: .intent(fixture.intent))
            _ = try await photoCommit(fixture.store, intentMutation)
            let identifier = try PhotoAssetIdentifier(rawValue: "exact-local-identifier")
            _ = try await photoWrite(fixture.store, "unknown", .result(.init(intent: fixture.intent,
                outcome: .unknown(localIdentifier: identifier))))
            let reopened = try SQLiteRecordingStore(run: run, mode: .openExisting)
            #expect(try await mediaSnapshot(reopened).photoRegistrations.first?.outcome == .unknown(localIdentifier: identifier))
            let duplicate = try PhotoRegistrationIntent(operation: .init(rawValue: "duplicate"), handoff: fixture.intent.handoff)
            #expect(await fixture.store.commit(try await photoMutation(fixture.store,
                command: duplicate.operation, change: .intent(duplicate))) == .rejected(.duplicateTarget))
            let differentIdentifier = try PhotoAssetIdentifier(rawValue: "unrelated-asset")
            #expect(await fixture.store.commit(try await photoMutation(fixture.store, command: .init(rawValue: "wrong-asset"),
                change: .result(.init(intent: fixture.intent, outcome: .succeeded(localIdentifier: differentIdentifier)))))
                == .rejected(.identityMismatch))
            _ = try await photoWrite(fixture.store, "delayed-terminal", .result(.init(intent: fixture.intent,
                outcome: .succeeded(localIdentifier: identifier))))
            #expect(await fixture.store.commit(try await photoMutation(fixture.store, command: .init(rawValue: "late-unknown"),
                change: .result(.init(intent: fixture.intent, outcome: .unknown(localIdentifier: identifier)))))
                == .rejected(.wrongStage))
            let changedPayload = BackendStoreMutation(expectedRevision: intentMutation.expectedRevision,
                change: .photo(command: fixture.intent.operation,
                    value: .result(.init(intent: fixture.intent, outcome: .unknown(localIdentifier: nil)))))
            #expect(await reopened.lookupCommit(changedPayload) == .rejected(.identityMismatch))
            #expect(await reopened.lookupCommit(intentMutation) == .committed(
                try #require(try await mediaSnapshot(reopened).photoRegistrations.first?.registration.commit)))
        }
    }

    @Test func currentNotFoundAndRestrictedScopePreserveSuccessfulRegistration() async throws {
        try await withStorageRun { run in
            let fixture = try await PhotoStoreFixture.make(run: run)
            _ = try await photoWrite(fixture.store, fixture.intent.operation.rawValue, .intent(fixture.intent))
            let identifier = try PhotoAssetIdentifier(rawValue: "subsequently-deleted-photo")
            _ = try await photoWrite(fixture.store, "success", .result(.init(intent: fixture.intent,
                outcome: .succeeded(localIdentifier: identifier))))
            let first = try PhotoPresenceObservation(intent: fixture.intent, generation: 1, identifier: identifier,
                authorization: .limited, presence: .notFound)
            _ = try await photoWrite(fixture.store, "limited-lookup", .presence(first))
            let second = try PhotoPresenceObservation(intent: fixture.intent, generation: 2, identifier: identifier,
                authorization: .authorized, presence: .notFound)
            _ = try await photoWrite(fixture.store, "full-lookup", .presence(second))
            #expect(await fixture.store.commit(try await photoMutation(fixture.store,
                command: .init(rawValue: "late-old-lookup"), change: .presence(first))) == .rejected(.staleGeneration))
            let retry = try PhotoRegistrationIntent(operation: .init(rawValue: "do-not-resurrect"),
                handoff: fixture.intent.handoff, retryOf: fixture.intent.operation)
            #expect(await fixture.store.commit(try await photoMutation(fixture.store,
                command: retry.operation, change: .intent(retry))) == .rejected(.duplicateTarget))
            let reopened = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let record = try #require(try await mediaSnapshot(reopened).photoRegistrations.first)
            #expect(record.outcome == .succeeded(localIdentifier: identifier))
            #expect(record.currentPresence == second)
            #expect(record.presenceObservations.count == 2)
        }
    }

    @Test(arguments: [false, true])
    func explicitRetryRequiresProvenNonAdditionAndPreviousOperation(notAttempted: Bool) async throws {
        try await withStorageRun { run in
            let fixture = try await PhotoStoreFixture.make(run: run)
            _ = try await photoWrite(fixture.store, fixture.intent.operation.rawValue, .intent(fixture.intent))
            let outcome: PhotoRegistrationOutcome = notAttempted ? .notAttempted(.authorizationRequired) : .failed(.invalidMedia)
            _ = try await photoWrite(fixture.store, "non-addition", .result(.init(intent: fixture.intent, outcome: outcome)))
            let noRetryReference = try PhotoRegistrationIntent(operation: .init(rawValue: "blind-retry"),
                handoff: fixture.intent.handoff)
            #expect(await fixture.store.commit(try await photoMutation(fixture.store,
                command: noRetryReference.operation, change: .intent(noRetryReference))) == .rejected(.duplicateTarget))
            let explicit = try PhotoRegistrationIntent(operation: .init(rawValue: "explicit-retry"),
                handoff: fixture.intent.handoff, retryOf: fixture.intent.operation)
            _ = try await photoWrite(fixture.store, explicit.operation.rawValue, .intent(explicit))
            #expect(try await mediaSnapshot(fixture.store).photoRegistrations.map { $0.registration.intent } == [fixture.intent, explicit])
            #expect(await fixture.store.commit(try await photoMutation(fixture.store,
                command: .init(rawValue: "contradictory-old-terminal"),
                change: .result(.init(intent: fixture.intent, outcome: .succeeded(localIdentifier: nil))))) == .rejected(.wrongStage))
        }
    }

    @Test func intentRejectsDifferentSourceDateAndObsoleteUsageEpoch() async throws {
        try await withStorageRun { run in
            let fixture = try await PhotoStoreFixture.make(run: run)
            let revision = try await mediaSnapshot(fixture.store).revision
            #expect(await fixture.store.commit(.init(expectedRevision: revision - 1,
                change: .photo(command: fixture.intent.operation, value: .intent(fixture.intent)))) == .rejected(.revisionConflict))
            let source = fixture.intent.handoff
            let dateMismatch = try PhotoRegistrationIntent(operation: .init(rawValue: "wrong-date"), handoff: .init(
                media: source.media, rendition: source.rendition, capturedAt: source.capturedAt.addingTimeInterval(1), usage: source.usage))
            #expect(await fixture.store.commit(try await photoMutation(fixture.store,
                command: dateMismatch.operation, change: .intent(dateMismatch))) == .rejected(.ineligibleOriginal))
            let obsoleteUsage = TemporaryMediaUsage(id: source.usage.id, purpose: .photoHandoff, media: source.media,
                epoch: .init(rawValue: "obsolete-process"))
            let stale = try PhotoRegistrationIntent(operation: .init(rawValue: "stale-use"), handoff: .init(
                media: source.media, rendition: source.rendition, capturedAt: source.capturedAt, usage: obsoleteUsage))
            #expect(await fixture.store.commit(try await photoMutation(fixture.store,
                command: stale.operation, change: .intent(stale))) == .rejected(.staleGeneration))
            #expect(try await mediaSnapshot(fixture.store).photoRegistrations.isEmpty)
        }
    }

    @Test func fabricatedCompleteHandoffCannotReplacePersistedAcquisitionAndHashVerification() async throws {
        try await withStorageRun { run in
            let bytes = Data(repeating: 3, count: 128)
            let fixture = try await RenditionFixture.make(run: run, content: renditionContent(bytes))
            let partial = try await fixture.create()
            let pretendUse = TemporaryMediaUsage(id: partial.usage.id, purpose: .photoHandoff,
                media: partial.id, epoch: partial.usage.epoch)
            let fabricated = TemporaryMediaReceipt(id: partial.id, rendition: partial.rendition,
                capturedAt: partial.capturedAt, ranges: [try .init(lowerBound: 0, upperBound: UInt64(bytes.count))],
                verifiedContent: partial.rendition.deliveryContent, usage: pretendUse, isReleased: false)
            let intent = try PhotoRegistrationIntent(operation: .init(rawValue: "fabricated-photo-intent"),
                handoff: fabricated.photoHandoff(expected: partial.rendition))
            #expect(await fixture.store.commit(try await photoMutation(fixture.store,
                command: intent.operation, change: .intent(intent))) == .rejected(.ineligibleOriginal))
            #expect(try await mediaSnapshot(fixture.store).photoRegistrations.isEmpty)
            #expect(await fixture.temporary.releaseUsage(partial.usage) == .succeeded(partial.id))
            _ = try await fixture.scope.close()
        }
    }

    @Test func successfulRecoveryReleasesOnlyExactOldPhotoUsageAndRetainsOtherReaders() async throws {
        try await withStorageRun { run in
            let fixture = try await PhotoStoreFixture.make(run: run)
            guard case .succeeded(let other) = await fixture.temporary.acquireUsage(fixture.intent.media,
                purpose: .playback, usageID: .init(rawValue: "independent-playback")) else {
                Issue.record("Could not acquire independent fixture usage"); return
            }
            _ = try await photoWrite(fixture.store, fixture.intent.operation.rawValue, .intent(fixture.intent))
            _ = try await photoWrite(fixture.store, "terminal-success", .result(.init(intent: fixture.intent,
                outcome: .succeeded(localIdentifier: try PhotoAssetIdentifier(rawValue: "saved-asset")))))
            let reopened = try SQLiteRecordingStore(run: run, mode: .openExisting)
            let record = try #require(try await mediaSnapshot(reopened).photoRegistrations.first)
            let release = try PhotoUsageRelease(record: record)
            let ordinary = BackendStoreChange.temporary(command: .init(rawValue: "ordinary-old-release"),
                value: .release(fixture.intent.media, record.registration.mediaUse))
            #expect(await reopened.commit(.init(expectedRevision: try await mediaSnapshot(reopened).revision,
                change: ordinary)) == .rejected(.staleGeneration))
            let mutation = try await photoMutation(reopened, command: .init(rawValue: "successful-photo-recovery"),
                change: .releaseUsage(release))
            let receipt = try await photoCommit(reopened, mutation)
            #expect(await reopened.lookupCommit(mutation) == .committed(receipt))
            #expect(await reopened.commit(mutation) == .committed(receipt))
            let snapshot = try await mediaSnapshot(reopened)
            let media = try #require(snapshot.temporaryMedia.first)
            #expect(media.usages.map(\.usage) == [other])
            #expect(media.releasedUsages.contains(record.registration.mediaUse))
            #expect(!media.reclaiming && !media.reclaimed)
            #expect(snapshot.photoRegistrations.first?.usageRelease?.commit == receipt)
            let original = try #require(try await mediaOriginalSnapshot(reopened).logicalOriginals.first)
            #expect(original.mediaReaders == media.usages.map(\.lease))
            #expect(try Data(contentsOf: run.url.appendingPathComponent("temporary").appendingPathComponent(media.leaf)) == fixture.bytes)
            #expect(await reopened.commit(try await photoMutation(reopened,
                command: .init(rawValue: "second-release-identity"), change: .releaseUsage(release))) == .rejected(.wrongStage))
        }
    }

    @Test(arguments: ["unknown", "failed", "root", "usage"])
    func recoveryRejectsForgedSuccessOrDifferentSource(corruption: String) async throws {
        try await withStorageRun { run in
            let fixture = try await PhotoStoreFixture.make(run: run)
            _ = try await photoWrite(fixture.store, fixture.intent.operation.rawValue, .intent(fixture.intent))
            let outcome: PhotoRegistrationOutcome = corruption == "unknown" ? .unknown(localIdentifier: nil)
                : corruption == "failed" ? .failed(.rejected) : .succeeded(localIdentifier: nil)
            _ = try await photoWrite(fixture.store, "actual-terminal", .result(.init(intent: fixture.intent, outcome: outcome)))
            var record = try #require(try await mediaSnapshot(fixture.store).photoRegistrations.first)
            if corruption == "unknown" || corruption == "failed" {
                #expect(throws: BackendContractError.notCommitted) { try PhotoUsageRelease(record: record) }
                let actual = try #require(record.results.last)
                record.results = [.init(command: actual.command,
                    result: .init(intent: fixture.intent, outcome: .succeeded(localIdentifier: nil)), commit: actual.commit)]
            }
            var release = try PhotoUsageRelease(record: record)
            if corruption == "root" || corruption == "usage" {
                var value = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(release)) as? [String: Any])
                if corruption == "root" { value["directoryIdentity"] = ["device": 999, "inode": 999] }
                else {
                    var use = try #require(value["mediaUse"] as? [String: Any])
                    use["owner"] = "unrelated-owner"
                    value["mediaUse"] = use
                }
                release = try JSONDecoder().decode(PhotoUsageRelease.self, from: JSONSerialization.data(withJSONObject: value))
            }
            #expect(await fixture.store.commit(try await photoMutation(fixture.store,
                command: .init(rawValue: "forged-recovery"), change: .releaseUsage(release))) == .rejected(.identityMismatch))
            #expect(try await mediaSnapshot(fixture.store).temporaryMedia.first?.usages.count == 1)
        }
    }

    @Test(arguments: Array(1...7))
    func legacyDocumentReadKeepsDiskBytesAndEmptyPhotosProjection(schema: Int) async throws {
        try await withStorageRun { run in
            var value = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(RecordingStoreDocument())) as? [String: Any])
            value["schema"] = schema
            let bytes = try JSONSerialization.data(withJSONObject: value, options: .sortedKeys)
            let file = run.url.appendingPathComponent("recordings.json")
            try bytes.write(to: file, options: .withoutOverwriting)
            let store = try AtomicFileRecordingStore(run: run, mode: .openExisting)
            let snapshot = try await mediaSnapshot(store)
            #expect(snapshot.photoRegistrations.isEmpty && snapshot.revision == 0)
            #expect(try Data(contentsOf: file) == bytes)
            #expect(RecordingStoreDocument.currentSchema == 7)
        }
    }

    @Test(arguments: ["operation", "purpose", "receipt"])
    func corruptPhotoJournalIsRejectedWithoutRepairOrWrite(corruption: String) async throws {
        try await withStorageRun { run in
            let fixture = try await PhotoStoreFixture.make(run: run, candidate: .atomicFile)
            _ = try await photoWrite(fixture.store, fixture.intent.operation.rawValue, .intent(fixture.intent))
            let file = run.url.appendingPathComponent("recordings.json")
            let valid = try Data(contentsOf: file)
            let damaged: Data
            if corruption == "receipt" {
                var value = try #require(JSONSerialization.jsonObject(with: valid) as? [String: Any])
                var journal = try #require(value["backendJournal"] as? [[String: Any]])
                var entry = try #require(journal.last)
                var receipt = try #require(entry["receipt"] as? [String: Any])
                receipt["committedRevision"] = 0
                entry["receipt"] = receipt
                journal[journal.count - 1] = entry
                value["backendJournal"] = journal
                damaged = try JSONSerialization.data(withJSONObject: value)
            } else {
                let string = try #require(String(data: valid, encoding: .utf8))
                let changed = corruption == "operation"
                    ? string.replacingOccurrences(of: fixture.intent.operation.rawValue, with: "  ")
                    : string.replacingOccurrences(of: "\"photoHandoff\":{}", with: "\"playback\":{}")
                #expect(changed != string)
                damaged = Data(changed.utf8)
            }
            try damaged.write(to: file, options: .atomic)
            #expect(throws: ExplorationStorageError.corruptStore) { try AtomicFileRecordingStore(run: run, mode: .openExisting) }
            #expect(await fixture.store.load() == .unavailable(.corruptStore))
            #expect(try Data(contentsOf: file) == damaged)
        }
    }
}

nonisolated private struct PhotoStoreFixture: Sendable {
    let store: any MediaDiskStore
    let temporary: ManagedTemporaryMedia
    let scope: RenditionMediaScope
    let intent: PhotoRegistrationIntent
    let bytes: Data

    static func make(run: ExplorationRunDirectory, candidate: StorageCandidate = .sqlite,
                     fault: RecordingStoreFault? = nil) async throws -> Self {
        let store = try photoDisk(candidate, run: run, mode: .createNew, fault: fault)
        let registration = try await mediaRegister(store)
        let bytes = Data(repeating: 7, count: 1024)
        let content = try renditionContent(bytes)
        let original = OriginalContent(capture: .init(rawValue: "s31-storage-fixture"), generation: .init(rawValue: 1), content: content)
        let rendition = RenditionIdentity(original: original, inputLogIdentity: "synthetic-not-log",
            transformAssetIdentity: "no-quality-claim", transformAssetVersion: "fixture-v1",
            outputConfigurationIdentity: "fixture-movie", conversionVersion: "synthetic-writer",
            rendition: .init(rawValue: "s31-storage-rendition"), deliveryContent: content, publicationGeneration: .init(rawValue: 1))
        _ = try await mediaCommit(store, .publication(mediaPublication(rendition, registration: registration)))
        let distributionOperation = MediaOperationID(rawValue: "explicit-s31-fixture-distribution")
        let distribution = DistributionReceipt(operation: distributionOperation, rendition: rendition, registration: registration,
            commit: .init(key: .distribution(distributionOperation, rendition, registration), previousRevision: 0, committedRevision: 1))
        let retrieve = RetrieveMediaCommand(gate: .init(operation: .init(rawValue: "fixture-read"), attempt: .init(rawValue: "fixture-attempt"),
            target: .rendition(rendition), registration: registration, generation: 1), distribution: distribution, range: nil)
        let leases = RenditionReadLeases(store: store)
        let scope = try await RenditionMediaScope.open(original: original, leases: leases)
        let temporary = try await ManagedTemporaryMedia.open(root: run.url.appendingPathComponent("temporary"), leases: leases, scope: scope)
        let created = try await temporary.create(command: retrieve, id: .init(rawValue: "s31-temporary"),
            usageID: .init(rawValue: "s31-download-use"), capturedAt: RenditionFixture.capturedAt, contentType: "video/quicktime")
        try await temporary.store(bytes, range: .init(lowerBound: 0, upperBound: UInt64(bytes.count)), using: created.usage)
        _ = try await temporary.verify(created.usage)
        guard case .succeeded(let photo) = await temporary.acquireUsage(created.id, purpose: .photoHandoff,
            usageID: .init(rawValue: "s31-photo-use")) else { throw BackendContractError.ineligibleOriginal }
        #expect(await temporary.releaseUsage(created.usage) == .succeeded(created.id))
        let state = try await temporary.stateFor(created.id)
        let handoff = try state.receipt(for: photo).photoHandoff(expected: rendition)
        let intent = try PhotoRegistrationIntent(operation: .init(rawValue: "photo-intent"), handoff: handoff)
        return .init(store: store, temporary: temporary, scope: scope, intent: intent, bytes: bytes)
    }
}

nonisolated private func photoDisk(_ candidate: StorageCandidate, run: ExplorationRunDirectory,
    mode: ExplorationStoreOpenMode, fault: RecordingStoreFault? = nil) throws -> any MediaDiskStore {
    switch candidate {
    case .atomicFile: try AtomicFileRecordingStore(run: run, mode: mode, fault: fault)
    case .sqlite: try SQLiteRecordingStore(run: run, mode: mode, fault: fault)
    }
}

nonisolated private func photoMutation(_ store: any MediaOperationStorePort, command: MediaOperationID,
                                     change: PhotoRegistrationChange) async throws -> BackendStoreMutation {
    let snapshot = try await mediaSnapshot(store)
    return .init(expectedRevision: snapshot.revision, change: .photo(command: command, value: change),
        expectedStoreIdentity: snapshot.storeIdentity)
}

nonisolated private func photoCommit(_ store: any MediaOperationStorePort, _ mutation: BackendStoreMutation) async throws -> BackendCommitReceipt {
    guard case .committed(let receipt) = await store.commit(mutation) else { throw BackendContractError.notCommitted }
    #expect(await store.lookupCommit(mutation) == .committed(receipt))
    return receipt
}

nonisolated private func photoWrite(_ store: any MediaOperationStorePort, _ command: String,
                                  _ change: PhotoRegistrationChange) async throws -> BackendCommitReceipt {
    try await photoCommit(store, photoMutation(store, command: .init(rawValue: command), change: change))
}
