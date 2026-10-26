import Darwin
import Foundation
import Testing
@testable import FrameRelay

#if DEBUG && targetEnvironment(simulator)
/// Opt-in technical probe on a new disposable root/unique OS identifier. The
/// real native upload is never resumed; .invalid is never contacted. Injected
/// policy permits local preparation only, not strict VPN/media authorization.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["FR_UPLOAD_CHUNK_SDK_TEST"] == "1"))
struct BackgroundUploadChunkSessionTests {
    @Test(.timeLimit(.minutes(2))) func suspendedTypedChunkActuallyCancelsAndDrainsItsOwnedFDAndLeaseBeforeStopped() async throws {
            let context = try chunkNativeRun(), run = context.run
            defer { chunkNativeRecord(context, stage: "root-retained") }
            let f = try await BackgroundUploadChunkStoreFixture.make(run)
            _ = try await f.createSession(); let selected = try await f.get(), plan = try chunkCoordinatorPlan(f, selected: selected)
            let before = try chunkNativeFingerprint(f.url), managed = try ManagedUploadSource(run: run, originals: f.access)
            let gate = BackgroundCheckpoint(), releaseGate = BackgroundCheckpoint(), native = try BackgroundMediaSession(identity: plan.session)
            let sdk = ChunkNativeSessionProbe(base: native, creationGate: gate), requests = ChunkCoordinatorRequests()
            let access = BackgroundAccessProbe(base: f.access, releaseBarrier: releaseGate)
            let owner = chunkCoordinator(f, sdk: sdk, source: managed, access: access)
            let work = Task { await owner.startUploadChunk(plan, requests: requests) }
            do {
                try await gate.waitForArrival()
                let binding = try #require(await sdk.createdBinding)
                guard case .succeeded(let observed) = await native.enumerate() else { throw BackendContractError.unavailable }
                #expect(observed.count == 1 && observed[0].kind == .upload && observed[0].state == .suspended)
                #expect(observed[0].bytesSent == 0 && observed[0].bytesReceived == 0)
                #expect(await native.observeTerminal(binding) == .inProgress)
                #expect(await managed.resources().openHandles == 1)
                #expect(try await mediaOriginalSnapshot(f.store).logicalOriginals[0].readers.count == 1)
                chunkNativeRecord(context, stage: "actual-suspended", binding: binding, openHandles: 1, readers: 1)
                #expect(await sdk.rejectedAlteredRequest)
                let capture = CaptureMediaAdmission(), authorization = try #require(capture.authorizeResume())
                let fabricated = BackgroundMediaStrictPermit(context: plan.context, evidence: .init(rawValue: "synthetic-not-a-strict-path-proof"))
                #expect(await native.resume(binding, permit: fabricated, captureAuthorization: authorization) == .notExecuted)
                guard case .succeeded(let unchanged) = await native.enumerate() else { throw BackendContractError.unavailable }
                #expect(unchanged.count == 1 && unchanged[0].state == .suspended && unchanged[0].bytesSent == 0 && unchanged[0].bytesReceived == 0)
                await gate.release()
                #expect(await work.value == .refused(.sdkResumeUnavailable))
                try await releaseGate.waitForArrival()
                guard case .succeeded(let actualTerminal) = await native.observeTerminal(binding) else { throw BackendContractError.unknownResult }
                let beforeRelease = try await mediaSnapshot(f.store), closedTask = try #require(beforeRelease.backgroundTasks.first)
                let closure = try #require(closedTask.events.last { if case .ownerClosed = $0.change { return true }; return false })
                let sdkEvent = try #require(closedTask.events.last { if case .terminal = $0.change { return true }; return false })
                #expect(actualTerminal.outcome == .cancelled && closedTask.ownerClosure?.handlesClosed == true)
                #expect(sdkEvent.commit.committedRevision < closure.commit.committedRevision)
                #expect(await managed.resources().openHandles == 0)
                #expect(try await mediaOriginalSnapshot(f.store).logicalOriginals[0].readers.count == 1)
                #expect(beforeRelease.requests[0].transport != .stopped)
                chunkNativeRecord(context, stage: "owner-closed-before-lease-release", binding: binding, terminal: actualTerminal,
                    openHandles: 0, readers: 1, ownerClosedRevision: closure.commit.committedRevision)
                await releaseGate.release()
                try await chunkCoordinatorWaitForStop(f)
                guard case .succeeded(let terminal) = await native.observeTerminal(binding) else { throw BackendContractError.unknownResult }
                #expect(terminal.binding == binding && terminal.outcome == .cancelled)
                let final = try await mediaSnapshot(f.store), task = try #require(final.backgroundTasks.first)
                #expect(task.terminal == terminal && task.ownerClosure?.uploadSource == task.intent.source.uploadOwnership?.source)
                #expect(task.ownerClosure?.handlesClosed == true && task.ownerClosure?.tasksJoined == true)
                #expect(final.requests[0].transport == .stopped && !final.requests[0].hasReconciled && final.requests[0].remote == .inProgress)
                #expect(final.verifications.isEmpty && final.outbox.isEmpty && final.confirmations.isEmpty)
                #expect(final.originalUploadAcceptances.count == 1 && final.uploadMetadataObservations.count == 2)
                #expect(await managed.resources().openHandles == 0)
                try await chunkCoordinatorRequireProofs(f, task: task)
                guard case .succeeded(let inventory) = await f.store.loadRemovalTransportInventory(f.source.original) else { throw BackendContractError.unavailable }
                let stopped = try BackgroundUploadChunkAdmission.stoppedRevision(task, journal: inventory.journal, through: final.revision)
                #expect(stopped > closure.commit.committedRevision)
                chunkNativeRecord(context, stage: "actual-stopped", binding: binding, terminal: terminal, openHandles: 0, readers: 0,
                    ownerClosedRevision: closure.commit.committedRevision, stoppedRevision: stopped)
                let after = try chunkNativeFingerprint(f.url), originalBytes = try Data(contentsOf: f.url)
                #expect(after == before && originalBytes == f.bytes)
                let source = try #require(task.intent.source.uploadOwnership?.source)
                let file = run.url.appendingPathComponent("background-upload-sources").appendingPathComponent(source.id.rawValue + ".upload")
                let bytes = try Data(contentsOf: file), content = try renditionContent(bytes)
                #expect(content == source.content && bytes == f.bytes.prefix(Int(source.content.byteCount)))
                let persisted = String(decoding: try JSONEncoder().encode(task.intent), as: UTF8.self)
                #expect(!persisted.contains("synthetic-disposable-") && !persisted.contains("chunk-upload.invalid"))
                await native.invalidate()
                try await backgroundEventually { await native.enumerate() == .unknown }
                _ = try await managed.closeOwner()
                Attachment.record("neverResumed=true typedChunkTasks=1 actualSuspendedBytesSent=0 actualCancelledTerminal=1 sourceOwnHandles=0 originalReaders=0 stoppedAfterOwnerClose=true wholeVerification=0 finalize=0",
                    named: "s23-upload-chunk-suspended-native.txt")
            } catch {
                await gate.release(); await releaseGate.release()
                if let binding = await sdk.createdBinding { await native.requestStop(binding) }
                await native.invalidate()
                _ = await work.value
                chunkNativeRecord(context, stage: "failed-root-retained", binding: await sdk.createdBinding)
                // Unknown SDK/file closure is retained, never fabricated as cleanup.
                throw error
            }
    }
}

private nonisolated struct ChunkNativeRun: Sendable {
    let run: ExplorationRunDirectory
    let simulator: String
    let nonce: String
}
private nonisolated struct ChunkNativeSummary: Encodable {
    let schema = "fr-upload-chunk-native-retained-v1"
    let root: String; let simulator: String; let nonce: String; let stage: String
    let binding: BackgroundMediaTaskBinding?; let terminal: BackgroundMediaSDKTerminal?
    let ownOpenHandles: Int?; let originalReaders: Int?
    let ownerClosedRevision: UInt64?; let stoppedRevision: UInt64?
    let actualResumeEnabled = false
}
private nonisolated func chunkNativeRun() throws -> ChunkNativeRun {
    let env = ProcessInfo.processInfo.environment
    guard env["FR_UPLOAD_CHUNK_SDK_TEST"] == "1",
          let simulator = env["FR_UPLOAD_CHUNK_SIMULATOR_ID"], let requested = UUID(uuidString: simulator),
          let actual = env["SIMULATOR_UDID"], UUID(uuidString: actual) == requested,
          let nonce = env["FR_UPLOAD_CHUNK_NONCE"], let id = UUID(uuidString: nonce), id.uuidString.lowercased() == nonce else {
        throw BackendContractError.invalidValue
    }
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent("FrameRelay-upload-chunk-sdk-" + nonce, isDirectory: true)
    var existing = stat()
    guard lstat(root.path, &existing) != 0, errno == ENOENT else { throw BackendContractError.identityMismatch }
    let context = ChunkNativeRun(run: try ExplorationRunDirectory.createNew(at: root), simulator: requested.uuidString, nonce: nonce)
    chunkNativeRecord(context, stage: "created-once")
    return context
}
private nonisolated func chunkNativeRecord(_ context: ChunkNativeRun, stage: String,
    binding: BackgroundMediaTaskBinding? = nil, terminal: BackgroundMediaSDKTerminal? = nil,
    openHandles: Int? = nil, readers: Int? = nil, ownerClosedRevision: UInt64? = nil, stoppedRevision: UInt64? = nil) {
    let value = ChunkNativeSummary(root: context.run.url.path, simulator: context.simulator, nonce: context.nonce, stage: stage,
        binding: binding, terminal: terminal, ownOpenHandles: openHandles, originalReaders: readers,
        ownerClosedRevision: ownerClosedRevision, stoppedRevision: stoppedRevision)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    if let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) {
        Attachment.record(text, named: "upload-chunk-native-" + stage + ".json")
        print("FR_UPLOAD_CHUNK_NATIVE " + text)
    }
}

private actor ChunkNativeSessionProbe: BackgroundMediaSessionPort {
    let base: BackgroundMediaSession
    let creationGate: BackgroundCheckpoint
    private(set) var createdBinding: BackgroundMediaTaskBinding?
    private(set) var rejectedAlteredRequest = false
    init(base: BackgroundMediaSession, creationGate: BackgroundCheckpoint) { self.base = base; self.creationGate = creationGate }
    func events() async throws -> AsyncStream<BackgroundMediaSDKEvent> { try await base.events() }
    func createSuspended(_ intent: BackgroundMediaTaskIntent, request: URLRequest, upload: BackgroundMediaUploadFile?) async -> BackendOutcome<BackgroundMediaTaskBinding> {
        var wrong = request; wrong.setValue("0", forHTTPHeaderField: "Content-Length")
        rejectedAlteredRequest = await base.createSuspended(intent, request: wrong, upload: upload) == .failed(.rejected)
        let result = await base.createSuspended(intent, request: request, upload: upload)
        if case .succeeded(let binding) = result {
            createdBinding = binding
            guard await base.createSuspended(intent, request: request, upload: upload) == .succeeded(binding) else { return .unknown }
            await creationGate.checkpoint()
        }
        return result
    }
    func enumerate() async -> BackendOutcome<[BackgroundMediaTaskObservation]> { await base.enumerate() }
    func resume(_ binding: BackgroundMediaTaskBinding, permit: BackgroundMediaStrictPermit,
        captureAuthorization: CaptureMediaResumeAuthorization) async -> BackendOutcome<BackgroundMediaTaskBinding> {
        await base.resume(binding, permit: permit, captureAuthorization: captureAuthorization)
    }
    func requestStop(_ binding: BackgroundMediaTaskBinding) async { await base.requestStop(binding) }
    func observeTerminal(_ binding: BackgroundMediaTaskBinding) async -> BackendOutcome<BackgroundMediaSDKTerminal> { await base.observeTerminal(binding) }
    func invalidate() async { await base.invalidate() }
}
private nonisolated func chunkNativeFingerprint(_ url: URL) throws -> OriginalFileFingerprint {
    var value = stat()
    guard lstat(url.path, &value) == 0 else { throw BackendContractError.unavailable }
    return try .init(info: value)
}
#endif
