import Darwin
import Foundation
import Synchronization
import Testing
@testable import FrameRelay

/// Actual dedicated writer/prepared receipts and raw synthetic callbacks. These
/// are local FD tests, not native receive, GET-admit, formal metadata or import.
@Suite(.serialized) struct ManagedDownloadIngressTests {
    @Test(arguments: [false, true])
    func pinReadsNothingAndTheSameFDOutlivesSDKUnlinkAndNameReplacement(unlink: Bool) async throws {
        try await withStorageRun { run in
            let f = try await DownloadIngressFixture.make(run), owner = ManagedDownloadIngress()
            let original = try downloadIngressFileFacts(f.base.url), observer = try FileHandle(forReadingFrom: f.location)
            let sink = try await owner.registerExpected(f.proposal, prepared: f.prepared, store: f.store)
            try #require(sink.bindKnownCreation(f.intent, binding: f.binding)) // Synthetic SDK input only.
            let reference = try downloadIngressPinned(sink.pinKnownCallback(binding: f.binding, location: f.location, response: f.response()))
            let pinned = await owner.resources()
            #expect(pinned.openHandles == 1 && pinned.activeWorkers == 0 && pinned.readBytes == 0 && pinned.pinnedArtifacts == 1)
            if unlink {
                #expect(Darwin.unlink(f.location.path) == 0)
                try f.sentinel.write(to: f.location, options: .withoutOverwriting)
                #expect(throws: ExplorationStorageError.self) { try OriginalFileFingerprint(descriptor: observer.fileDescriptor) }
            }
            try observer.close()
            let source = try await owner.take(reference)
            await downloadIngressExpect(.identityMismatch) { _ = try await owner.take(reference) }
            #expect(source.proposal.capturedAt == nil && source.proposal.readTicket == nil)
            #expect(source.response.contentRangeAbsent && source.response.contentEncoding == .absent)
            for length in [0, 65_537] {
                await downloadIngressExpect(.invalidValue) { _ = try await source.read(offset: 0, maximumLength: length) }
            }
            let bytes = try await source.read(offset: 0, maximumLength: 65_536)
            #expect(bytes == f.body.prefix(65_536))
            #expect(try await source.hashFull() == f.proposal.rendition.deliveryContent)
            let closed = try await source.finishAndClose(), after = await owner.resources()
            #expect(closed.reference == reference && closed.workersJoined && closed.handlesClosed)
            #expect(after.openHandles == 0 && after.closedHandles == 1 && after.activeWorkers == 0 && after.largestRead == 65_536)
            #expect(try await source.finishAndClose() == closed)
            await downloadIngressExpect(.wrongStage) { _ = try await source.read(offset: 0, maximumLength: 1) }
            let foreign = try FileHandle(forReadingFrom: f.sentinelURL)
            #expect(try await source.finishAndClose() == closed)
            #expect(fcntl(foreign.fileDescriptor, F_GETFD) >= 0); try foreign.close()
            #expect(try downloadIngressFileFacts(f.base.url) == original)
            try await f.requireNoImportOrRelease()
        }
    }

    @Test(arguments: ["status", "url", "mime", "length", "range", "encoding", "wire", "distribution", "rendition", "generation", "hash", "bytes", "cache"])
    func actualResponseMismatchRefusesBeforeOpeningAnyPayload(field: String) async throws {
        try await withStorageRun { run in
            let f = try await DownloadIngressFixture.make(run), owner = ManagedDownloadIngress()
            let sink = try await owner.registerExpected(f.proposal, prepared: f.prepared, store: f.store)
            try #require(sink.bindKnownCreation(f.intent, binding: f.binding))
            #expect(sink.pinKnownCallback(binding: f.binding, location: f.location, response: try f.response(changing: field)) == .refused)
            let state = await owner.resources()
            #expect(state.openHandles == 0 && state.pinnedArtifacts == 0 && state.readBytes == 0)
            #expect(sink.pinKnownCallback(binding: f.binding, location: f.location, response: try f.response()) == .refused)
            // Explicit test terminal input, not a real SDK callback.
            sink.observeKnownTerminal(.init(binding: f.binding, outcome: .cancelled))
            #expect(try await owner.closeUnpinnedCreation(binding: f.binding).handlesClosed)
            try await f.requireNoImportOrRelease()
        }
    }

    @Test(arguments: ["symlink", "hardlink", "directory", "size", "fifo"])
    func nonregularAliasedOrIncompleteSourcesAreNeverFollowedOrImported(kind: String) async throws {
        try await withStorageRun { run in
            let f = try await DownloadIngressFixture.make(run), owner = ManagedDownloadIngress()
            let sink = try await owner.registerExpected(f.proposal, prepared: f.prepared, store: f.store)
            try #require(sink.bindKnownCreation(f.intent, binding: f.binding))
            let retained = run.url.appendingPathComponent("retained-synthetic-sdk-bytes")
            try FileManager.default.moveItem(at: f.location, to: retained)
            switch kind {
            case "symlink": try FileManager.default.createSymbolicLink(at: f.location, withDestinationURL: retained)
            case "hardlink": try #require(link(retained.path, f.location.path) == 0)
            case "directory": try FileManager.default.createDirectory(at: f.location, withIntermediateDirectories: false)
            case "size": try Data(f.body.prefix(16)).write(to: f.location, options: .withoutOverwriting)
            case "fifo": try #require(mkfifo(f.location.path, 0o600) == 0)
            default: throw BackendContractError.invalidValue
            }
            #expect(sink.pinKnownCallback(binding: f.binding, location: f.location, response: try f.response()) == .refused)
            #expect(await owner.resources().openHandles == 0)
            #expect(try Data(contentsOf: retained) == f.body)
            sink.observeKnownTerminal(.init(binding: f.binding, outcome: .cancelled))
            #expect(try await owner.closeUnpinnedCreation(binding: f.binding).handlesClosed)
            try await f.requireNoImportOrRelease()
        }
    }

    @Test func unknownReopenedDuplicateAndForeignCapabilitiesCannotBorrowThisOwner() async throws {
        try await withStorageRun { run in
            let f = try await DownloadIngressFixture.make(run), owner = ManagedDownloadIngress()
            let sink = try await owner.registerExpected(f.proposal, prepared: f.prepared, store: f.store)
            let foreign = BackgroundMediaTaskBinding(session: .init(identifier: f.binding.session.identifier, generation: .init(rawValue: UUID())),
                taskIdentifier: f.binding.taskIdentifier, taskDescription: f.binding.taskDescription)
            #expect(!sink.bindKnownCreation(f.intent, binding: foreign))
            #expect(sink.pinKnownCallback(binding: f.binding, location: f.location, response: try f.response()) == .refused)
            try #require(sink.bindKnownCreation(f.intent, binding: f.binding))
            #expect(!sink.bindKnownCreation(f.intent, binding: f.binding))
            await downloadIngressExpect(.readersActive) { _ = try await owner.closeUnpinnedCreation(binding: f.binding) }
            let reference = try downloadIngressPinned(sink.pinKnownCallback(binding: f.binding, location: f.location, response: f.response()))
            #expect(sink.pinKnownCallback(binding: f.binding, location: f.location, response: try f.response()) == .refused)
            let unknown = BackgroundDownloadArtifactReference(id: UUID(), ownerGeneration: reference.ownerGeneration, binding: f.binding)
            await downloadIngressExpect(.identityMismatch) { _ = try await owner.take(unknown) }
            let reopened = ManagedDownloadIngress()
            await downloadIngressExpect(.identityMismatch) { _ = try await reopened.take(reference) }
            await downloadIngressExpect(.identityMismatch) { _ = try await reopened.closeUnpinnedCreation(binding: f.binding) }
            #expect(await reopened.resources().openHandles == 0)
            let source = try await owner.take(reference)
            sink.observeKnownTerminal(.init(binding: f.binding, outcome: .completed))
            #expect(!source.stop.isStopped) // Completed SDK does not abort a pinned reader.
            #expect(try await source.hashFull() == f.proposal.rendition.deliveryContent)
            await downloadIngressExpect(.readersActive) { _ = try await owner.closeUnpinnedCreation(binding: f.binding) }
            _ = try await owner.stopAndClose(reference)
            try await f.requireNoImportOrRelease()
        }
    }

    @Test(arguments: ["UUID", "payload"])
    func registrationRequiresTheActualPreparedPayloadAndCurrentObservedUUID(change: String) async throws {
        try await withStorageRun { run in
            let f = try await DownloadIngressFixture.make(run), owner = ManagedDownloadIngress()
            let store = DownloadIngressStoreObservation(base: f.store, rotateAfterLookup: change == "UUID")
            let proposal: BackgroundDownloadExpectedProposal
            if change == "payload" {
                let intent = BackgroundMediaTaskIntent(id: f.intent.id, context: f.intent.context, session: f.intent.session,
                    taskDescription: f.intent.taskDescription, requestFingerprint: .init(sha256: String(repeating: "c", count: 64)), source: f.intent.source)
                proposal = try .init(intent: intent, responseURL: f.proposal.responseURL, contentType: f.proposal.contentType,
                    capturedAt: nil, captureRecord: nil, distributionOperation: f.proposal.distributionOperation)
            } else { proposal = f.proposal }
            await downloadIngressExpect(.notCommitted) { _ = try await owner.registerExpected(proposal, prepared: f.prepared, store: store) }
            #expect(await owner.resources().registeredSlots == 0)
            #expect(try await mediaSnapshot(f.store).storeIdentity == f.base.source.storeIdentity)
            try await f.requireNoImportOrRelease()
        }
    }

    @Test(arguments: ["same-inode", "truncated", "unlink-modified", "hash"])
    func metadataPinDoesNotHideByteOrFileDrift(change: String) async throws {
        try await withStorageRun { run in
            let f = try await DownloadIngressFixture.make(run), owner = ManagedDownloadIngress()
            if change == "hash" { try downloadIngressChangeByte(f.location, expected: f.body[0]) }
            let sink = try await owner.registerExpected(f.proposal, prepared: f.prepared, store: f.store)
            try #require(sink.bindKnownCreation(f.intent, binding: f.binding))
            let reference = try downloadIngressPinned(sink.pinKnownCallback(binding: f.binding, location: f.location, response: f.response()))
            let source = try await owner.take(reference)
            if change == "same-inode" { try downloadIngressChangeByte(f.location, expected: f.body[0]) }
            if change == "truncated" {
                let handle = try FileHandle(forWritingTo: f.location)
                do { try handle.truncate(atOffset: 1024); try handle.synchronize(); try handle.close() } catch { try? handle.close(); throw error }
            }
            if change == "unlink-modified" {
                let handle = try FileHandle(forWritingTo: f.location)
                do {
                    try #require(Darwin.unlink(f.location.path) == 0)
                    try handle.write(contentsOf: Data([f.body[0] ^ 0xff])); try handle.synchronize(); try handle.close()
                } catch { try? handle.close(); throw error }
            }
            await downloadIngressExpect(.identityMismatch) { _ = try await source.hashFull() }
            _ = try await source.finishAndClose()
            #expect(await owner.resources().openHandles == 0)
            try await f.requireNoImportOrRelease()
        }
    }

    @Test(arguments: [false, true])
    func stopRevokesImmediatelyButCloseJoinsTheActualBlockedWorker(hash: Bool) async throws {
        try await withStorageRun { run in
            let f = try await DownloadIngressFixture.make(run), gate = BackgroundCheckpoint()
            let owner = ManagedDownloadIngress(readCheckpoint: { count in if count == 65_536 { await gate.checkpoint() } })
            let sink = try await owner.registerExpected(f.proposal, prepared: f.prepared, store: f.store)
            try #require(sink.bindKnownCreation(f.intent, binding: f.binding))
            let reference = try downloadIngressPinned(sink.pinKnownCallback(binding: f.binding, location: f.location, response: f.response()))
            let source = try await owner.take(reference)
            let worker = Task { if hash { _ = try await source.hashFull() } else { _ = try await source.read(offset: 0, maximumLength: 65_536) } }
            try await gate.waitForArrival()
            sink.requestStop(f.binding)
            #expect(source.stop.isStopped)
            let result = DownloadIngressCloseResult()
            let close = Task { let value = try await owner.stopAndClose(reference); await result.set(value); return value }
            for _ in 0..<12 { await Task.yield() }
            #expect(await result.value == nil)
            let waiting = await owner.resources()
            #expect(waiting.activeWorkers == 1 && waiting.openHandles == 1 && waiting.closedHandles == 0)
            await gate.release()
            do { try await worker.value; Issue.record("Stopped artifact worker returned bytes/hash") }
            catch is CancellationError {} catch { Issue.record("Unexpected worker error \(error)") }
            let closed = try await close.value, final = await owner.resources()
            #expect(closed.workersJoined && closed.handlesClosed && final.activeWorkers == 0 && final.openHandles == 0 && final.closedHandles == 1)
            await downloadIngressExpect(.wrongStage) { _ = try await source.read(offset: 0, maximumLength: 1) }
            try await f.requireNoImportOrRelease()
        }
    }

    @Test(arguments: [false, true])
    func aKnownTerminalCanCloseOnlyItsUnpinnedSlotAndSealsLateCallbacks(completed: Bool) async throws {
        try await withStorageRun { run in
            let f = try await DownloadIngressFixture.make(run), owner = ManagedDownloadIngress()
            let sink = try await owner.registerExpected(f.proposal, prepared: f.prepared, store: f.store)
            try #require(sink.bindKnownCreation(f.intent, binding: f.binding))
            await downloadIngressExpect(.readersActive) { _ = try await owner.closeUnpinnedCreation(binding: f.binding) }
            sink.observeKnownTerminal(.init(binding: f.binding, outcome: completed ? .completed : .cancelled))
            let closure = try await owner.closeUnpinnedCreation(binding: f.binding)
            #expect(closure.ownerGeneration == owner.ownerGeneration && closure.binding == f.binding && closure.pinsSealed && closure.handlesClosed && closure.workersJoined)
            #expect(try await owner.closeUnpinnedCreation(binding: f.binding) == closure)
            #expect(sink.pinKnownCallback(binding: f.binding, location: f.location, response: try f.response()) == .refused)
            #expect(await owner.resources().pinnedArtifacts == 0)
            try await f.requireNoImportOrRelease()
        }
    }

    @Test func failedPinCloseRetainsUnknownHandleAndCannotIssueAnUnpinnedFDZeroProof() async throws {
        try await withStorageRun { run in
            let f = try await DownloadIngressFixture.make(run), counter = DownloadIngressCloseCalls()
            let owner = ManagedDownloadIngress(pinClose: { counter.hit(); throw BackendContractError.unknownResult })
            let sink = try await owner.registerExpected(f.proposal, prepared: f.prepared, store: f.store)
            try #require(sink.bindKnownCreation(f.intent, binding: f.binding))
            let short = run.url.appendingPathComponent("synthetic-incomplete-callback")
            try Data([1, 2, 3]).write(to: short, options: .withoutOverwriting)
            #expect(sink.pinKnownCallback(binding: f.binding, location: short, response: try f.response()) == .refused)
            sink.observeKnownTerminal(.init(binding: f.binding, outcome: .cancelled))
            await downloadIngressExpect(.readersActive) { _ = try await owner.closeUnpinnedCreation(binding: f.binding) }
            await downloadIngressExpect(.readersActive) { _ = try await owner.closeUnpinnedCreation(binding: f.binding) }
            let resources = await owner.resources()
            #expect(resources.openHandles == 1 && resources.closedHandles == 0 && resources.pinnedArtifacts == 0 && counter.count == 1)
            // Unknown handle is retained/sealed; no blind numeric-FD reclose.
            try await f.requireNoImportOrRelease()
        }
    }

    @Test func retainingAnArtifactDoesNotBlockTheFollowingSerialTerminalOrClaimResourceDrain() async throws {
        try await withStorageRun { run in
            let f = try await DownloadIngressFixture.make(run), ingress = ManagedDownloadIngress()
            let sink = try await ingress.registerExpected(f.proposal, prepared: f.prepared, store: f.store)
            try #require(sink.bindKnownCreation(f.intent, binding: f.binding))
            let reference = try downloadIngressPinned(sink.pinKnownCallback(binding: f.binding, location: f.location, response: f.response()))
            _ = try await f.base.backend(.backgroundTask(command: .init(rawValue: UUID().uuidString), value: .attached(f.intent, f.binding)))
            let session = DownloadIngressDrainSession(binding: f.binding), drained = BackgroundDrainProbe()
            let owner = BackgroundMediaCoordinator(store: f.store, identity: f.base.source.storeIdentity, originals: f.base.access,
                sessionFactory: { _ in session }, sourceFactory: { throw BackendContractError.unavailable }, didDrain: { await drained.record($0) })
            guard case .succeeded = await owner.recover(f.intent.session) else { throw BackendContractError.unavailable }
            await session.sendArtifactAndTerminal(reference)
            try await backgroundEventually { await drained.count() == 1 }
            #expect(await owner.retainedEvents.contains { if case .downloadArtifact(let actual) = $0.value { return actual == reference }; return false })
            #expect(try await mediaSnapshot(f.store).backgroundTasks[0].terminal != nil)
            #expect(try await mediaSnapshot(f.store).backgroundTasks[0].ownerClosure == nil)
            #expect(await ingress.resources().openHandles == 1)
            try await f.requireNoImportOrRelease(allowTerminal: true)
            _ = try await ingress.stopAndClose(reference); await session.finish()
        }
    }
}

/// Shared by these new A suites only. Raw synthetic data, genuine writer
/// registration/publication/request/transport lease/prepared receipts, no ticket.
nonisolated struct DownloadIngressFixture: Sendable {
    let base: BackgroundUploadChunkStoreFixture
    let intent: BackgroundMediaTaskIntent
    let prepared: KnownPreparedDownloadReference
    let proposal: BackgroundDownloadExpectedProposal
    let lease: MediaReadLease
    let request: URLRequest
    let body: Data
    let location: URL
    let sentinel: Data
    let sentinelURL: URL
    var store: any MediaDiskStore { base.store }
    var binding: BackgroundMediaTaskBinding { .init(session: intent.session, taskIdentifier: 1, taskDescription: intent.taskDescription) }

    static func make(_ run: ExplorationRunDirectory, callbackFile: Bool = true) async throws -> Self {
        let base = try await BackgroundUploadChunkStoreFixture.make(run), registration = base.source.registration.server.registration
        let body = Data((0..<131_111).map { UInt8(truncatingIfNeeded: ($0 &* 23) ^ ($0 >> 11)) })
        let rendition = RenditionIdentity(original: base.source.original, inputLogIdentity: "synthetic-not-log", transformAssetIdentity: "not-formal",
            transformAssetVersion: "ingress-fixture", outputConfigurationIdentity: "raw-test", conversionVersion: "technical",
            rendition: .init(rawValue: UUID().uuidString.lowercased()), deliveryContent: try renditionContent(body), publicationGeneration: .init(rawValue: 1))
        _ = try await base.backend(.publication(mediaPublication(rendition, registration: registration)))
        let operation = MediaOperationID(rawValue: UUID().uuidString), attempt = TransferAttemptID(rawValue: UUID().uuidString)
        let initial = MediaRequest(operation: operation, target: .rendition(rendition), purpose: .download, registration: registration,
            expectedStartRevision: try await mediaSnapshot(base.store).revision)
        _ = try await base.backend(.request(command: operation, value: initial))
        _ = try await base.backend(.requestTransition(command: .init(rawValue: UUID().uuidString), operation: operation,
            target: initial.target, registration: registration, value: .reconciled(.init(context: .init(operation: operation,
                registration: registration, target: initial.target, session: nil), observation: .init(rawValue: 1), result: .notExecuted))))
        _ = try await base.backend(.requestTransition(command: .init(rawValue: UUID().uuidString), operation: operation,
            target: initial.target, registration: registration, value: .beginAttempt(attempt)))
        let leases = RenditionReadLeases(store: base.store)
        let lease = try await leases.acquire(rendition: rendition, registration: registration, operation: operation, context: .transport(attempt))
        let remoteURL = URL(string: "https://download-ingress.invalid/full/" + rendition.rendition.rawValue)!
        var request = URLRequest(url: remoteURL); request.httpMethod = "GET"
        let intent = BackgroundMediaTaskIntent(id: .init(rawValue: UUID().uuidString), context: .init(operation: operation, attempt: attempt,
            target: initial.target, registration: registration, gateGeneration: 1, storeIdentity: base.source.storeIdentity),
            session: .init(identifier: .init(rawValue: "FrameRelay.download-ingress.test." + UUID().uuidString), generation: .init(rawValue: UUID())),
            taskDescription: UUID().uuidString, requestFingerprint: try .make(request: request), source: .download(rendition: rendition, range: nil, lease: lease))
        _ = try await base.backend(.backgroundTask(command: .init(rawValue: UUID().uuidString), value: .prepared(intent)))
        let event = try #require(try await mediaSnapshot(base.store).backgroundTasks[0].events.first)
        let prepared = try KnownPreparedDownloadReference(event)
        let proposal = try BackgroundDownloadExpectedProposal(intent: intent, responseURL: remoteURL, contentType: "video/mp4",
            capturedAt: nil, captureRecord: nil, distributionOperation: .init(rawValue: UUID().uuidString))
        let location = run.url.appendingPathComponent("synthetic-sdk-callback.bin"), sentinelURL = run.url.appendingPathComponent("ingress-sentinel.bin")
        let sentinel = Data([41, 42, 43, 44]); try sentinel.write(to: sentinelURL, options: .withoutOverwriting)
        if callbackFile { try body.write(to: location, options: .withoutOverwriting) }
        return .init(base: base, intent: intent, prepared: prepared, proposal: proposal, lease: lease, request: request,
            body: body, location: location, sentinel: sentinel, sentinelURL: sentinelURL)
    }
    func response(changing field: String? = nil) throws -> HTTPURLResponse {
        var headers = ["Content-Type": proposal.contentType, "Content-Length": String(body.count),
            "X-FrameRelay-Wire-Version": "fr-publication-v1", "X-FrameRelay-Distribution-ID": proposal.distributionHeader,
            "X-FrameRelay-Rendition-ID": proposal.rendition.rendition.rawValue, "X-FrameRelay-Publication-Generation": "1",
            "X-FrameRelay-Content-SHA256": proposal.rendition.deliveryContent.digest, "X-FrameRelay-Content-Bytes": String(body.count), "Cache-Control": "no-store"]
        let keys = ["mime": "Content-Type", "length": "Content-Length", "wire": "X-FrameRelay-Wire-Version", "distribution": "X-FrameRelay-Distribution-ID",
            "rendition": "X-FrameRelay-Rendition-ID", "generation": "X-FrameRelay-Publication-Generation", "hash": "X-FrameRelay-Content-SHA256", "bytes": "X-FrameRelay-Content-Bytes", "cache": "Cache-Control"]
        if let field, let key = keys[field] { headers[key] = "mismatch" }
        if field == "range" { headers["Content-Range"] = "bytes 0-1023/\(body.count)" }
        if field == "encoding" { headers["Content-Encoding"] = "gzip" }
        let url = field == "url" ? URL(string: "https://foreign.invalid/full")! : proposal.responseURL
        return try #require(HTTPURLResponse(url: url, statusCode: field == "status" ? 206 : 200, httpVersion: "HTTP/1.1", headerFields: headers))
    }
    func requireNoImportOrRelease(allowTerminal: Bool = false) async throws {
        let backend = try await mediaSnapshot(store), originals = try await mediaOriginalSnapshot(store)
        #expect(backend.temporaryMedia.isEmpty && backend.verifications.isEmpty && backend.photoRegistrations.isEmpty)
        #expect(originals.logicalOriginals[0].mediaReaders.contains(lease))
        #expect(backend.backgroundTasks[0].ownerClosure == nil)
        if !allowTerminal { #expect(backend.backgroundTasks[0].terminal == nil) }
        #expect(try Data(contentsOf: base.url) == base.bytes)
        #expect(try Data(contentsOf: sentinelURL) == sentinel)
    }
}

nonisolated func downloadIngressPinned(_ result: BackgroundDownloadPinResult) throws -> BackgroundDownloadArtifactReference {
    guard case .pinned(let reference) = result else { throw BackendContractError.unavailable }; return reference
}
nonisolated func downloadIngressFileFacts(_ url: URL) throws -> OriginalFileFingerprint {
    var info = stat(); guard lstat(url.path, &info) == 0 else { throw BackendContractError.unavailable }; return try .init(info: info)
}
private nonisolated func downloadIngressChangeByte(_ url: URL, expected: UInt8) throws {
    let handle = try FileHandle(forWritingTo: url)
    do { try handle.write(contentsOf: Data([expected ^ 0xff])); try handle.synchronize(); try handle.close() } catch { try? handle.close(); throw error }
}
private nonisolated func downloadIngressExpect(_ expected: BackendContractError, _ operation: () async throws -> Void) async {
    do { try await operation(); Issue.record("Expected ingress rejection \(expected)") }
    catch let error as BackendContractError { #expect(error == expected) }
    catch { Issue.record("Unexpected ingress error \(error)") }
}
private actor DownloadIngressCloseResult {
    private(set) var value: BackgroundDownloadSourceClosure?
    func set(_ value: BackgroundDownloadSourceClosure) { self.value = value }
}
private nonisolated final class DownloadIngressCloseCalls: Sendable {
    private let state = Mutex(0)
    func hit() { state.withLock { $0 += 1 } }
    var count: Int { state.withLock { $0 } }
}
private actor DownloadIngressStoreObservation: MediaOperationStorePort {
    let base: any MediaOperationStorePort
    let rotateAfterLookup: Bool
    private var changed = false
    init(base: any MediaOperationStorePort, rotateAfterLookup: Bool) { self.base = base; self.rotateAfterLookup = rotateAfterLookup }
    func load() async -> BackendStoreLoadResult {
        let result = await base.load()
        guard changed, case .loaded(var snapshot) = result else { return result }
        snapshot.storeIdentity = .init(rawValue: UUID()); return .loaded(snapshot)
    }
    func commit(_ mutation: BackendStoreMutation) async -> BackendCommitResult { await base.commit(mutation) }
    func lookupCommit(_ mutation: BackendStoreMutation) async -> BackendCommitResult {
        let result = await base.lookupCommit(mutation); if rotateAfterLookup { changed = true }; return result
    }
}
private actor DownloadIngressDrainSession: BackgroundMediaSessionPort {
    let binding: BackgroundMediaTaskBinding
    private let stream: AsyncStream<BackgroundMediaSDKEvent>, continuation: AsyncStream<BackgroundMediaSDKEvent>.Continuation
    private let streamID = UUID()
    private var taken = false, terminal = false
    init(binding: BackgroundMediaTaskBinding) {
        self.binding = binding; let pair = AsyncStream<BackgroundMediaSDKEvent>.makeStream(); stream = pair.stream; continuation = pair.continuation
    }
    func events() throws -> AsyncStream<BackgroundMediaSDKEvent> { guard !taken else { throw BackendContractError.wrongStage }; taken = true; return stream }
    func createSuspended(_ intent: BackgroundMediaTaskIntent, request: URLRequest, upload: BackgroundMediaUploadFile?) -> BackendOutcome<BackgroundMediaTaskBinding> { .notExecuted }
    func enumerate() -> BackendOutcome<[BackgroundMediaTaskObservation]> {
        .succeeded(terminal ? [] : [.init(session: binding.session, taskIdentifier: binding.taskIdentifier, taskDescription: binding.taskDescription,
            kind: .download, state: .suspended, bytesSent: 0, bytesReceived: 0)])
    }
    func resume(_ binding: BackgroundMediaTaskBinding, permit: BackgroundMediaStrictPermit,
        captureAuthorization: CaptureMediaResumeAuthorization) -> BackendOutcome<BackgroundMediaTaskBinding> { .notExecuted }
    func requestStop(_ binding: BackgroundMediaTaskBinding) {}
    func observeTerminal(_ binding: BackgroundMediaTaskBinding) -> BackendOutcome<BackgroundMediaSDKTerminal> {
        terminal ? .succeeded(.init(binding: binding, outcome: .cancelled)) : .inProgress
    }
    func invalidate() { continuation.finish() }
    func finish() { continuation.finish() }
    func sendArtifactAndTerminal(_ reference: BackgroundDownloadArtifactReference) {
        let values: [BackgroundMediaSDKEventValue] = [.downloadArtifact(reference), .taskTerminal(.init(binding: binding, outcome: .cancelled)), .finishedEvents]
        terminal = true
        for (index, value) in values.enumerated() { continuation.yield(.init(session: binding.session, stream: streamID, sequence: UInt64(index + 1), value: value)) }
    }
}
