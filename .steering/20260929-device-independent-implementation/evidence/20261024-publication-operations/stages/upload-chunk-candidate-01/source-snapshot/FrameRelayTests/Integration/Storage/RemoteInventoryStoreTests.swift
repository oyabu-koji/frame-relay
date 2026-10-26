import Foundation
import Testing
@testable import FrameRelay

@Suite(.serialized) @MainActor struct RemoteInventoryStoreTests {
    @Test(arguments: StorageCandidate.allCases)
    func boundedPagesDuplicatesAndEmptyObservationSurviveDiskReopenWithoutCreatingOriginals(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let store = try inventoryDisk(candidate, run: run, mode: .createNew)
            let registration = try await inventoryRegister(store)
            let identity = try #require(try await mediaSnapshot(store).storeIdentity)
            let originals = [try inventoryOriginal("remote-a"), try inventoryOriginal("remote-b")]
            let a = inventoryObservation(identity, registration, originals: originals, next: inventoryCursor("page-1"))
            let first = try await inventoryCommit(store, a)
            _ = try await inventoryCommit(store, inventoryObservation(identity, registration, originals: [originals[0]],
                after: a.page.nextCursor))
            _ = try await inventoryCommit(store, inventoryObservation(identity, registration, originals: []))
            let reopened = try inventoryDisk(candidate, run: run, mode: .openExisting)
            let snapshot = try await mediaSnapshot(reopened)
            #expect(snapshot.remoteInventory.count == 3 && snapshot.remoteInventory[0].commit == first)
            #expect(try await mediaOriginalSnapshot(reopened).logicalOriginals.isEmpty)
            #expect(snapshot.verifications.isEmpty && snapshot.publications.isEmpty && snapshot.confirmations.isEmpty
                && snapshot.invalidations.isEmpty && snapshot.outbox.isEmpty && snapshot.requests.isEmpty)
            let reader = LibraryStoreReader(store: reopened, files: StatusSynchronizationAbsentFiles())
            guard case .loaded(let library) = await reader.loadLibrary() else { throw BackendContractError.unavailable }
            #expect(library.items.isEmpty && library.history.isEmpty && library.remoteItems.count == 2)
            #expect(library.remoteItems.allSatisfy { $0.captureDateDescription == "撮影日時不明" && !$0.hasIdentityConflict })
            #expect(try await mediaSnapshot(reopened) == snapshot)
        }
    }

    @Test(arguments: StorageCandidate.allCases, [RecordingStoreFault.beforeDiskCommit, .afterDiskCommitBeforeReply])
    func realCommitFaultAndExactLookupNeverRebaseOrInventAPage(candidate: StorageCandidate, fault: RecordingStoreFault) async throws {
        try await withStorageRun { run in
            let base = try inventoryDisk(candidate, run: run, mode: .createNew)
            let registration = try await inventoryRegister(base)
            let before = try await mediaSnapshot(base)
            let identity = try #require(before.storeIdentity)
            let observation = inventoryObservation(identity, registration, originals: [try inventoryOriginal("fault")])
            let mutation = BackendStoreMutation(expectedRevision: before.revision, change: .remoteInventory(observation), expectedStoreIdentity: identity)
            let faulty = try inventoryDisk(candidate, run: run, mode: .openExisting, fault: fault)
            let result = await faulty.commit(mutation)
            #expect(result == (fault == .afterDiskCommitBeforeReply ? .unknown : .unavailable(.inaccessible)))
            let reopened = try inventoryDisk(candidate, run: run, mode: .openExisting)
            let after = try await mediaSnapshot(reopened)
            if fault == .afterDiskCommitBeforeReply {
                let receipt = try #require(after.remoteInventory.first?.commit)
                #expect(await reopened.lookupCommit(mutation) == .committed(receipt))
                #expect(await reopened.lookupCommit(.init(expectedRevision: mutation.expectedRevision + 1,
                    change: mutation.change, expectedStoreIdentity: identity)) == .rejected(.identityMismatch))
            } else {
                #expect(after.remoteInventory.isEmpty && after.revision == before.revision)
                #expect(await reopened.lookupCommit(mutation) == .unknown)
            }
            #expect(try await mediaOriginalSnapshot(reopened).logicalOriginals.isEmpty)
            #expect(after.confirmations.isEmpty && after.outbox.isEmpty)
        }
    }

    @Test(arguments: StorageCandidate.allCases)
    func byteDistinctUnicodePayloadCannotUseAnotherMutationReceipt(candidate: StorageCandidate) async throws {
        try await withStorageRun { run in
            let store = try inventoryDisk(candidate, run: run, mode: .createNew)
            let registration = try await inventoryRegister(store)
            let identity = try #require(try await mediaSnapshot(store).storeIdentity)
            let a = try inventoryOriginal("\u{e9}"), b = try inventoryOriginal("e\u{301}")
            #expect(a == b && !RemoteInventoryValidation.same(a, b))
            let original = inventoryObservation(identity, registration, originals: [a])
            let before = try await mediaSnapshot(store)
            let mutation = BackendStoreMutation(expectedRevision: before.revision, change: .remoteInventory(original), expectedStoreIdentity: identity)
            guard case .committed = await store.commit(mutation) else { throw BackendContractError.notCommitted }
            let alias = RemoteInventoryObservation(command: original.command, storeIdentity: identity,
                registration: registration.server.registration, requestCursor: nil,
                page: .init(registration: registration.server.registration, requestCursor: nil, originals: [b], nextCursor: nil))
            let changed = BackendStoreMutation(expectedRevision: before.revision, change: .remoteInventory(alias), expectedStoreIdentity: identity)
            #expect(mutation != changed)
            #expect(await store.lookupCommit(changed) == .rejected(.identityMismatch))
            #expect(await store.commit(changed) == .rejected(.identityMismatch))
            _ = try await inventoryCommit(store, inventoryObservation(identity, registration, originals: [b]))
            let reader = LibraryStoreReader(store: store, files: StatusSynchronizationAbsentFiles())
            guard case .loaded(let library) = await reader.loadLibrary() else { throw BackendContractError.unavailable }
            #expect(library.remoteItems.count == 2 && Set(library.remoteItems.map(\.id)).count == 2)
            #expect(library.remoteItems.allSatisfy { !$0.hasIdentityConflict })
        }
    }

    @Test func remoteConflictsKeepTheRealLocalMovieAndExternalSentinelUnchanged() async throws {
        try await withStorageRun { run in
            let binding = try await makeBindingMovie(run: run)
            let store = try SQLiteRecordingStore(run: run, mode: .openExisting)
            _ = try await mediaOriginalCommit(store, .bind(binding))
            let files = ManagedOriginalStore(run: run)
            let localBefore = try await files.digest(for: binding.reference)
            let sentinel = run.url.appendingPathComponent("inventory-external-sentinel.bin")
            let sentinelBytes = Data("separate-external-evidence".utf8)
            try sentinelBytes.write(to: sentinel, options: .withoutOverwriting)
            let registration = try await inventoryRegister(store)
            let identity = try #require(try await mediaSnapshot(store).storeIdentity)
            let conflict = OriginalContent(capture: binding.original.capture, generation: binding.original.generation,
                content: try .init(byteCount: binding.original.content.byteCount, algorithm: "sha256", digest: String(repeating: "f", count: 64)))
            let remote = try inventoryOriginal("remote-only")
            _ = try await inventoryCommit(store, inventoryObservation(identity, registration, originals: [binding.original, conflict, remote]))
            let reader = LibraryStoreReader(store: store, files: files)
            guard case .loaded(let library) = await reader.loadLibrary() else { throw BackendContractError.unavailable }
            #expect(library.items.count == 1 && library.items[0].original == binding.original)
            #expect(library.remoteItems.count == 2)
            #expect(library.remoteItems.first(where: { RemoteInventoryValidation.same($0.original, conflict) })?.hasIdentityConflict == true)
            #expect(library.history.isEmpty && library.remoteItems.allSatisfy { $0.captureDateDescription == "撮影日時不明" })
            #expect(try await files.digest(for: binding.reference) == localBefore)
            #expect(try Data(contentsOf: sentinel) == sentinelBytes)
            let backend = try await mediaSnapshot(store)
            #expect(backend.confirmations.isEmpty && backend.outbox.isEmpty && backend.verifications.isEmpty)
        }
    }

    @Test(arguments: [1, 2, 3, 4])
    func legacyHistoryIsReadWithoutRewriteBeforeExplicitIdentityAndInventory(schema: Int) async throws {
        try await withStorageRun { run in
            let envelopes = [
                #"{"schema":1,"entries":[]}"#,
                #"{"schema":2,"entries":[],"transactionRevision":0}"#,
                #"{"schema":3,"entries":[],"transactionRevision":0,"originalJournal":[]}"#,
                #"{"schema":4,"entries":[],"transactionRevision":0,"originalJournal":[],"backendJournal":[],"legacyRevision":0}"#
            ]
            let bytes = Data(envelopes[schema - 1].utf8)
            let path = run.url.appendingPathComponent("recordings.json")
            try bytes.write(to: path, options: .withoutOverwriting)
            let store = try AtomicFileRecordingStore(run: run, mode: .openExisting)
            #expect(try await mediaSnapshot(store).remoteInventory.isEmpty)
            #expect(try Data(contentsOf: path) == bytes)
            let registration = try await inventoryRegister(store)
            let identity = try #require(try await mediaSnapshot(store).storeIdentity)
            _ = try await inventoryCommit(store, inventoryObservation(identity, registration, originals: [try inventoryOriginal("legacy")]))
            let reopened = try AtomicFileRecordingStore(run: run, mode: .openExisting)
            #expect(try await mediaSnapshot(reopened).remoteInventory.count == 1)
            #expect(try await mediaOriginalSnapshot(reopened).logicalOriginals.isEmpty)
            #expect(try RecordingStoreDocument.decode(Data(contentsOf: path)).schema == 7)
        }
    }

    @Test(arguments: ["missing-uuid", "other-uuid", "registration", "cursor-echo", "too-many", "same-next"])
    func unboundMalformedAndWrongContextObservationCannotBecomeDurable(reason: String) async throws {
        try await withStorageRun { run in
            let store = try SQLiteRecordingStore(run: run, mode: .createNew)
            let registration = try await inventoryRegister(store)
            let before = try await mediaSnapshot(store)
            let identity = try #require(before.storeIdentity)
            let current = registration.server.registration
            let original = try inventoryOriginal("guarded")
            let wrong = RegistrationIdentity(destination: current.destination, id: .init(rawValue: UUID().uuidString.lowercased()), generation: current.generation)
            let observed = reason == "registration" ? wrong : current
            let cursor = inventoryCursor("cursor")
            let page = RemoteInventoryPage(registration: observed, requestCursor: ["cursor-echo", "same-next"].contains(reason) ? cursor : nil,
                originals: reason == "too-many" ? Array(repeating: original, count: 33) : [original],
                nextCursor: reason == "same-next" ? cursor : nil)
            let observation = RemoteInventoryObservation(command: .init(rawValue: UUID().uuidString.lowercased()),
                storeIdentity: identity, registration: observed, requestCursor: reason == "same-next" ? cursor : nil, page: page)
            let expected: RegistrationStoreIdentity? = reason == "missing-uuid" ? nil
                : reason == "other-uuid" ? .init(rawValue: UUID()) : identity
            let result = await store.commit(.init(expectedRevision: before.revision, change: .remoteInventory(observation), expectedStoreIdentity: expected))
            guard case .rejected = result else { Issue.record("Invalid inventory context became durable"); return }
            #expect(try await mediaSnapshot(store) == before)
        }
    }
}

nonisolated func inventoryDisk(_ candidate: StorageCandidate, run: ExplorationRunDirectory,
    mode: ExplorationStoreOpenMode, fault: RecordingStoreFault? = nil) throws -> any MediaDiskStore {
    switch candidate {
    case .atomicFile: try AtomicFileRecordingStore(run: run, mode: mode, fault: fault)
    case .sqlite: try SQLiteRecordingStore(run: run, mode: mode, fault: fault)
    }
}
nonisolated func inventoryRegister(_ store: any MediaOperationStorePort) async throws -> DeviceRegistration {
    _ = try await establishRegistrationIdentity(store)
    let registration = RegistrationIdentity(destination: .init(rawValue: "9a3ba104-985f-4a2d-875d-d458258b9b6b"),
        id: .init(rawValue: UUID().uuidString.lowercased()), generation: .init(rawValue: 1))
    _ = try await mediaRegister(store, registration: registration)
    let snapshot = try await mediaSnapshot(store)
    return try #require(snapshot.registrations.last)
}
nonisolated func inventoryOriginal(_ capture: String, digit: String = "a") throws -> OriginalContent {
    .init(capture: .init(rawValue: capture), generation: .init(rawValue: 1),
        content: try .init(byteCount: 4096, algorithm: "sha256", digest: String(repeating: digit, count: 64)))
}
nonisolated func inventoryCursor(_ value: String) -> String {
    Data(value.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}
nonisolated func inventoryObservation(_ identity: RegistrationStoreIdentity, _ registration: DeviceRegistration,
    originals: [OriginalContent], after: String? = nil, next: String? = nil) -> RemoteInventoryObservation {
    .init(command: .init(rawValue: UUID().uuidString.lowercased()), storeIdentity: identity,
        registration: registration.server.registration, requestCursor: after,
        page: .init(registration: registration.server.registration, requestCursor: after, originals: originals, nextCursor: next))
}
nonisolated func inventoryCommit(_ store: any MediaOperationStorePort, _ observation: RemoteInventoryObservation) async throws -> BackendCommitReceipt {
    let before = try await mediaSnapshot(store)
    guard case .committed(let receipt) = await store.commit(.init(expectedRevision: before.revision,
        change: .remoteInventory(observation), expectedStoreIdentity: observation.storeIdentity)) else { throw BackendContractError.notCommitted }
    return receipt
}
