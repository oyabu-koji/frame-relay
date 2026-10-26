import Darwin
import Foundation
import Testing
@testable import FrameRelay

#if DEBUG && targetEnvironment(simulator)
/// One guarded new Simulator/nonce root, retained on success and failure. This
/// real SDK test never resumes download and never receives an artifact. Positive
/// synthetic callback tests live in the storage suite and are not inherited.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["FR_DOWNLOAD_INGRESS_SDK_TEST"] == "1"))
struct BackgroundDownloadIngressSessionTests {
    @Test(.timeLimit(.minutes(2))) func nativeSuspendedDownloadCancelsWithoutPinImportOrLeaseRelease() async throws {
        let context = try downloadIngressNativeRun()
        defer { downloadIngressNativeRecord(context, stage: "root-retained") }
        let f = try await DownloadIngressFixture.make(context.run, callbackFile: false)
        let original = try downloadIngressFileFacts(f.base.url), ingress = ManagedDownloadIngress()
        let sink = try await ingress.registerExpected(f.proposal, prepared: f.prepared, store: f.store)
        let session = try BackgroundMediaSession(identity: f.intent.session, downloadIngress: sink)
        let stream = try await session.events()
        let events = Task { () -> [BackgroundMediaSDKEvent] in
            var result: [BackgroundMediaSDKEvent] = []; for await event in stream { result.append(event) }; return result
        }
        var actual: BackgroundMediaTaskBinding?
        do {
            guard case .succeeded(let binding) = await session.createSuspended(f.intent, request: f.request, upload: nil) else { throw BackendContractError.unavailable }
            actual = binding
            #expect(await session.createSuspended(f.intent, request: f.request, upload: nil) == .succeeded(binding))
            guard case .succeeded(let tasks) = await session.enumerate() else { throw BackendContractError.unavailable }
            #expect(tasks.count == 1 && tasks[0].kind == .download && tasks[0].state == .suspended)
            #expect(tasks[0].bytesSent == 0 && tasks[0].bytesReceived == 0)
            #expect(await session.observeTerminal(binding) == .inProgress)
            var earlyClosure = false
            do { _ = try await ingress.closeUnpinnedCreation(binding: binding); earlyClosure = true } catch {}
            #expect(!earlyClosure)
            let admission = CaptureMediaAdmission(), permit = BackgroundMediaStrictPermit(context: f.intent.context,
                evidence: .init(rawValue: "synthetic-not-a-strict-path-proof"))
            let authorization = try #require(admission.authorizeResume())
            #expect(await session.resume(binding, permit: permit, captureAuthorization: authorization) == .notExecuted)
            guard case .succeeded(let unchanged) = await session.enumerate() else { throw BackendContractError.unavailable }
            #expect(unchanged.count == 1 && unchanged[0].state == .suspended && unchanged[0].bytesReceived == 0 && unchanged[0].bytesSent == 0)
            let suspendedResources = await ingress.resources()
            downloadIngressNativeRecord(context, stage: "actual-suspended-never-resumed", binding: binding, pinnedArtifacts: suspendedResources.pinnedArtifacts)
            await session.requestStop(binding)
            try await backgroundEventually {
                if case .succeeded = await session.observeTerminal(binding) { return true }; return false
            }
            guard case .succeeded(let terminal) = await session.observeTerminal(binding) else { throw BackendContractError.unknownResult }
            #expect(terminal.binding == binding && terminal.outcome == .cancelled)
            let closure = try await ingress.closeUnpinnedCreation(binding: binding), resources = await ingress.resources()
            #expect(closure.binding == binding && closure.ownerGeneration == ingress.ownerGeneration && closure.handlesClosed && closure.workersJoined && closure.pinsSealed)
            #expect(resources.pinnedArtifacts == 0 && resources.openHandles == 0 && resources.activeWorkers == 0 && resources.readBytes == 0)
            try await f.requireNoImportOrRelease()
            #expect(!FileManager.default.fileExists(atPath: f.location.path))
            #expect(try downloadIngressFileFacts(f.base.url) == original)
            await session.invalidate()
            try await backgroundEventually { await session.enumerate() == .unknown }
            let observed = await events.value
            #expect(observed.filter { if case .taskTerminal(let value) = $0.value { return value == terminal }; return false }.count == 1)
            #expect(!observed.contains { if case .downloadArtifact = $0.value { return true }; return false })
            #expect(!observed.contains { if case .downloadArtifactUnavailable = $0.value { return true }; return false })
            #expect(observed.last?.value == .sessionInvalidated(errorCode: nil))
            #expect(observed.map(\.sequence) == (1...UInt64(observed.count)).map { $0 })
            let final = try await mediaSnapshot(f.store)
            downloadIngressNativeRecord(context, stage: "actual-terminal-unpinned-closed", binding: binding, terminal: terminal, closure: closure,
                pinnedArtifacts: resources.pinnedArtifacts, verifiedTemporary: final.temporaryMedia.filter { $0.verifiedContent != nil }.count)
        } catch {
            if let actual { await session.requestStop(actual) }
            await session.invalidate()
            downloadIngressNativeRecord(context, stage: "failed-root-retained", binding: actual)
            // Retain unknown resources/lease; no fabricated close/terminal/import.
            throw error
        }
    }
}

private nonisolated struct DownloadIngressNativeRun: Sendable {
    let run: ExplorationRunDirectory; let nonce: String; let simulator: String
}
private nonisolated struct DownloadIngressNativeSummary: Encodable {
    let schema = "fr-download-ingress-native-retained-v1"
    let root: String; let nonce: String; let simulator: String; let stage: String
    let binding: BackgroundMediaTaskBinding?; let terminal: BackgroundMediaSDKTerminal?
    let unpinnedClosed: Bool
    let nativeResumeEnabled = false
    let pinnedArtifacts: Int?
    let verifiedTemporary: Int?
}
private nonisolated func downloadIngressNativeRun() throws -> DownloadIngressNativeRun {
    let env = ProcessInfo.processInfo.environment
    guard env["FR_DOWNLOAD_INGRESS_SDK_TEST"] == "1", let expected = env["FR_DOWNLOAD_INGRESS_SIMULATOR_ID"],
          let simulator = UUID(uuidString: expected), let observed = env["SIMULATOR_UDID"], UUID(uuidString: observed) == simulator,
          let nonce = env["FR_DOWNLOAD_INGRESS_NONCE"], let id = UUID(uuidString: nonce), id.uuidString.lowercased() == nonce else {
        throw BackendContractError.invalidValue
    }
    let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("FrameRelay-download-ingress-sdk-" + nonce, isDirectory: true)
    var info = stat(); guard lstat(root.path, &info) != 0, errno == ENOENT else { throw BackendContractError.identityMismatch }
    let value = DownloadIngressNativeRun(run: try ExplorationRunDirectory.createNew(at: root), nonce: nonce, simulator: simulator.uuidString)
    downloadIngressNativeRecord(value, stage: "created-once"); return value
}
private nonisolated func downloadIngressNativeRecord(_ context: DownloadIngressNativeRun, stage: String,
    binding: BackgroundMediaTaskBinding? = nil, terminal: BackgroundMediaSDKTerminal? = nil, closure: BackgroundDownloadUnpinnedClosure? = nil,
    pinnedArtifacts: Int? = nil, verifiedTemporary: Int? = nil) {
    let value = DownloadIngressNativeSummary(root: context.run.url.path, nonce: context.nonce, simulator: context.simulator, stage: stage,
        binding: binding, terminal: terminal, unpinnedClosed: closure?.handlesClosed == true && closure?.workersJoined == true && closure?.pinsSealed == true,
        pinnedArtifacts: pinnedArtifacts, verifiedTemporary: verifiedTemporary)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    if let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) {
        Attachment.record(text, named: "download-ingress-native-" + stage + ".json")
        print("FR_DOWNLOAD_INGRESS_NATIVE " + text)
    }
}
#endif
