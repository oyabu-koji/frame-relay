import Foundation
import Testing
@testable import FrameRelay

struct BackgroundMediaRequestFingerprintTests {
    @Test func fixedOriginPathMethodRangeAndHeadersAreBoundWithoutCredentialValues() throws {
        var request = URLRequest(url: try #require(URL(string: "https://background-media.invalid/fixed/upload")))
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer disposable-secret-A", forHTTPHeaderField: "Authorization")
        let fingerprint = try BackgroundMediaRequestFingerprint.make(request: request)
        #expect(fingerprint.sha256.count == 64)
        var rotated = request
        rotated.setValue("Bearer disposable-secret-B", forHTTPHeaderField: "Authorization")
        #expect(try BackgroundMediaRequestFingerprint.make(request: rotated) == fingerprint)
        let encoded = String(decoding: try JSONEncoder().encode(fingerprint), as: UTF8.self)
        #expect(!encoded.contains("disposable-secret") && !encoded.contains("background-media.invalid"))
        for url in ["https://another-origin.invalid/fixed/upload", "https://background-media.invalid/other/upload",
                    "http://background-media.invalid/fixed/upload", "https://background-media.invalid:8443/fixed/upload"] {
            var changed = request
            changed.url = URL(string: url)
            #expect(try BackgroundMediaRequestFingerprint.make(request: changed) != fingerprint)
        }
        var changed = request
        changed.httpMethod = "PUT"
        #expect(try BackgroundMediaRequestFingerprint.make(request: changed) != fingerprint)
        changed = request
        changed.setValue("bytes=0-65535", forHTTPHeaderField: "Range")
        let range = try BackgroundMediaRequestFingerprint.make(request: changed)
        #expect(range != fingerprint)
        changed.setValue("bytes=65536-131071", forHTTPHeaderField: "Range")
        #expect(try BackgroundMediaRequestFingerprint.make(request: changed) != range)
        changed = request
        changed.setValue("video/quicktime", forHTTPHeaderField: "Content-Type")
        #expect(try BackgroundMediaRequestFingerprint.make(request: changed) != fingerprint)
    }

    @Test(arguments: ["https://user:password@background-media.invalid/fixed", "https://background-media.invalid/fixed?token=secret",
                     "https://background-media.invalid/fixed?", "https://background-media.invalid/fixed#fragment", "file:///tmp/fixed"])
    func rejectsUnadoptedURLInputs(url: String) throws {
        let request = URLRequest(url: try #require(URL(string: url)))
        #expect(throws: BackendContractError.invalidValue) { try BackgroundMediaRequestFingerprint.make(request: request) }
    }

    @Test func rejectsBodyStreamAndUnknownHeaders() throws {
        var request = URLRequest(url: try #require(URL(string: "https://background-media.invalid/fixed")))
        request.httpBody = Data([1, 2, 3])
        #expect(throws: BackendContractError.invalidValue) { try BackgroundMediaRequestFingerprint.make(request: request) }
        request.httpBody = nil
        request.httpBodyStream = InputStream(data: Data([1]))
        #expect(throws: BackendContractError.invalidValue) { try BackgroundMediaRequestFingerprint.make(request: request) }
        request.httpBodyStream = nil
        request.setValue("different-target", forHTTPHeaderField: "X-Unadopted-Media-Target")
        #expect(throws: BackendContractError.invalidValue) { try BackgroundMediaRequestFingerprint.make(request: request) }
    }
}

/// Opt-in uses only unique background identifiers and .invalid requests. No
/// URLSessionTask is ever resumed. SDK inability/timeouts fail these probes;
/// they are never replaced by a fake callback or a successful empty result.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["FR_BACKGROUND_SDK_TEST"] == "1"))
struct BackgroundMediaSessionTests {
    @Test(.timeLimit(.minutes(2))) func emptySessionEnumeratesAndBuffersActualInvalidationBeforeConsumerStarts() async throws {
        let identity = backgroundSDKIdentity()
        let session = try BackgroundMediaSession(identity: identity)
        #expect(throws: BackendContractError.readersActive) { try BackgroundMediaSession(identity: identity) }
        let otherGeneration = BackgroundMediaSessionIdentity(identifier: identity.identifier, generation: .init(rawValue: UUID()))
        #expect(throws: BackendContractError.readersActive) { try BackgroundMediaSession(identity: otherGeneration) }
        #expect(await session.enumerate() == .succeeded([]))
        await session.invalidate()
        try await backgroundSDKWait("actual empty session invalidation") { await session.enumerate() == .unknown }
        // The first consumer takes the already-finished stream, so its actual
        // invalidation event necessarily survived before consumer startup.
        let events = try await backgroundSDKDrain(session)
        #expect(events.last?.value == .sessionInvalidated(errorCode: nil))
        #expect(events.filter { if case .sessionInvalidated = $0.value { return true }; return false }.count == 1)
        backgroundSDKExpectSequences(events, identity: identity)
        await #expect(throws: BackendContractError.wrongStage) { try await session.events() }
        // Reuse becomes possible only after the real didBecomeInvalid callback.
        let replacement = try BackgroundMediaSession(identity: otherGeneration)
        #expect(await replacement.enumerate() == .succeeded([]))
        await replacement.invalidate()
        try await backgroundSDKWait("replacement session invalidation") { await replacement.enumerate() == .unknown }
        let replacementEvents = try await backgroundSDKDrain(replacement)
        #expect(replacementEvents.last?.value == .sessionInvalidated(errorCode: nil))
        Attachment.record("unique empty session enumerated; actual invalidation observed; late consumer retained all events; generation reuse after callback only",
            named: "s23-background-empty-session.txt")
    }

    @Test(.timeLimit(.minutes(2))) func suspendedUploadAndDownloadEnumerateCancelAndActuallyCompleteWithoutResume() async throws {
        try await withStorageRun { run in
            let fixture = try await BackgroundUploadFixture.make(run: run)
            let owner = try ManagedUploadSource(run: run, originals: fixture.access)
            let source = try await owner.create(from: fixture.lease, id: .init(rawValue: UUID().uuidString))
            let file = try await owner.uploadFile(for: source, lease: fixture.lease)
            let session = try BackgroundMediaSession(identity: backgroundSDKIdentity())
            var created: [BackgroundMediaTaskBinding] = []
            do {
                let uploadRequest = try backgroundSDKRequest(path: "/never-resumed-upload", method: "POST")
                let uploadIntent = try backgroundSDKUploadIntent(fixture, source: source, session: session.identity, request: uploadRequest)
                guard case .succeeded(let upload) = await session.createSuspended(uploadIntent, request: uploadRequest, upload: file) else {
                    throw BackgroundSDKProbeError.unavailable("suspended upload factory")
                }
                created.append(upload)
                try await owner.retain(source, lease: fixture.lease, for: upload)
                #expect(await session.createSuspended(uploadIntent, request: uploadRequest, upload: file) == .succeeded(upload))
                var changedRequest = uploadRequest
                changedRequest.url = URL(string: "https://background-media.invalid/different-target")
                #expect(await session.createSuspended(uploadIntent, request: changedRequest, upload: file) == .failed(.rejected))
                let downloadRequest = try backgroundSDKRequest(path: "/never-resumed-download", method: "GET", range: "bytes=0-65535")
                let downloadIntent = try backgroundSDKDownloadIntent(fixture, session: session.identity, request: downloadRequest)
                guard case .succeeded(let download) = await session.createSuspended(downloadIntent, request: downloadRequest, upload: nil) else {
                    throw BackgroundSDKProbeError.unavailable("suspended download factory")
                }
                created.append(download)
                guard case .succeeded(let tasks) = await session.enumerate() else {
                    throw BackgroundSDKProbeError.unavailable("current SDK task enumeration")
                }
                #expect(tasks.count == 2)
                for (binding, kind) in [(upload, BackgroundMediaTaskKind.upload), (download, .download)] {
                    let exact = tasks.filter { $0.session == binding.session && $0.taskIdentifier == binding.taskIdentifier
                        && $0.taskDescription == binding.taskDescription }
                    #expect(exact.count == 1 && exact.first?.kind == kind && exact.first?.state == .suspended)
                    #expect(exact.first?.bytesSent == 0 && exact.first?.bytesReceived == 0)
                    // Current presence and zero bytes are deliberately not SDK
                    // completion, remote non-execution, or owner closure.
                    #expect(await session.observeTerminal(binding) == .inProgress)
                }
                let fabricatedPermit = BackgroundMediaStrictPermit(context: uploadIntent.context,
                    evidence: .init(rawValue: "synthetic-not-a-strict-path-proof"))
                let capture = CaptureMediaAdmission()
                let idleAuthorization = try #require(capture.authorizeResume())
                #expect(await session.resume(upload, permit: fabricatedPermit, captureAuthorization: idleAuthorization) == .notExecuted)
                let beforeHold = try #require(capture.authorizeResume())
                let captureOwner = try captureBoundaryOwner()
                capture.begin(captureOwner, phases: [.recording])
                #expect(capture.authorizeResume() == nil)
                #expect(await session.resume(upload, permit: fabricatedPermit, captureAuthorization: beforeHold) == .notExecuted)
                capture.end(captureOwner)
                let unknown = BackgroundMediaTaskBinding(session: session.identity, taskIdentifier: Int.max,
                    taskDescription: UUID().uuidString)
                await session.requestStop(unknown)
                #expect(await session.observeTerminal(unknown) == .unknown)
                #expect(await session.observeTerminal(upload) == .inProgress)
                guard case .succeeded(let stillSuspended) = await session.enumerate() else {
                    throw BackgroundSDKProbeError.unavailable("post-rejection task enumeration")
                }
                #expect(stillSuspended.count == 2 && stillSuspended.allSatisfy { $0.state == .suspended && $0.bytesSent == 0 && $0.bytesReceived == 0 })
                await session.requestStop(upload)
                await session.requestStop(download)
                try await backgroundSDKWait("real upload and download didComplete callbacks") {
                    if case .succeeded = await session.observeTerminal(upload),
                       case .succeeded = await session.observeTerminal(download) { return true }
                    return false
                }
                guard case .succeeded(let uploadTerminal) = await session.observeTerminal(upload),
                      case .succeeded(let downloadTerminal) = await session.observeTerminal(download) else {
                    throw BackgroundSDKProbeError.unavailable("exact cached actual terminal")
                }
                #expect(uploadTerminal.outcome == .cancelled && downloadTerminal.outcome == .cancelled)
                await session.invalidate()
                try await backgroundSDKWait("actual nonempty session invalidation") { await session.enumerate() == .unknown }
                let closure = try await owner.finish(source, lease: fixture.lease, terminal: uploadTerminal)
                #expect(closure.tasksJoined && closure.handlesClosed && closure.uploadSource == source)
                // No download TemporaryMedia or download-owner success is
                // synthesized from cancellation or an SDK terminal.
                let events = try await backgroundSDKDrain(session)
                backgroundSDKExpectSequences(events, identity: session.identity)
                let actual = events.compactMap { event -> BackgroundMediaSDKTerminal? in
                    if case .taskTerminal(let terminal) = event.value { return terminal }; return nil
                }
                #expect(actual.count == 2 && actual.contains(uploadTerminal) && actual.contains(downloadTerminal))
                #expect(events.last?.value == .sessionInvalidated(errorCode: nil))
                #expect(!events.contains { if case .downloadArtifactUnavailable = $0.value { return true }; return false })
                #expect(!events.contains { if case .unknownTaskTerminal = $0.value { return true }; return false })
                #expect(try Data(contentsOf: fixture.url) == fixture.bytes)
                #expect(try Data(contentsOf: file.url) == fixture.bytes)
                #expect(try await mediaOriginalSnapshot(fixture.store).originals.first?.readers == [fixture.lease])
                #expect(await fixture.access.releaseRead(fixture.lease) == .succeeded(.init(lease: fixture.lease)))
                _ = try await owner.closeOwner()
                Attachment.record("neverResumed=true sdkTasks=2 suspended=2 enumeratedExact=2 actualCancelledCompletions=2 actualInvalidation=1 orderedEvents=\(events.count) copyBytes=\(fixture.bytes.count) sourceHandlesClosed=true inputLeaseReleasedByCaller=true",
                    named: "s23-background-suspended-tasks.txt")
            } catch {
                // Request cleanup without inventing completion/FD release if
                // this SDK/environment cannot deliver its actual callbacks.
                for binding in created { await session.requestStop(binding) }
                await session.invalidate()
                throw error
            }
        }
    }
}

private nonisolated enum BackgroundSDKProbeError: Error {
    case unavailable(String), timeout(String)
}

private nonisolated func backgroundSDKIdentity() -> BackgroundMediaSessionIdentity {
    .init(identifier: .init(rawValue: "FrameRelay.s23.sdk-test." + UUID().uuidString), generation: .init(rawValue: UUID()))
}

private nonisolated func backgroundSDKRequest(path: String, method: String, range: String? = nil) throws -> URLRequest {
    var request = URLRequest(url: try #require(URL(string: "https://background-media.invalid" + path)))
    request.httpMethod = method
    if let range { request.setValue(range, forHTTPHeaderField: "Range") }
    return request
}

/// Synthetic SDK-only intents are not claims of prepared journal commits or
/// accepted strict admission. The adapter never resumes these test tasks.
private nonisolated func backgroundSDKUploadIntent(_ fixture: BackgroundUploadFixture, source: ManagedUploadSourceIdentity,
    session: BackgroundMediaSessionIdentity, request: URLRequest) throws -> BackgroundMediaTaskIntent {
    let registration = RegistrationIdentity(destination: .init(rawValue: "s23-sdk-test-destination"),
        id: .init(rawValue: "s23-sdk-test-registration"), generation: .init(rawValue: 1))
    return .init(id: .init(rawValue: UUID().uuidString), context: .init(operation: fixture.lease.operation,
        attempt: .init(rawValue: UUID().uuidString), target: .original(fixture.binding.original), registration: registration,
        gateGeneration: 1, storeIdentity: .init(rawValue: UUID())), session: session, taskDescription: UUID().uuidString,
        requestFingerprint: try .make(request: request),
        source: .upload(session: .init(rawValue: "synthetic-Mac-session-distinct-from-OS-session"), lease: fixture.lease, source: source))
}

private nonisolated func backgroundSDKDownloadIntent(_ fixture: BackgroundUploadFixture,
    session: BackgroundMediaSessionIdentity, request: URLRequest) throws -> BackgroundMediaTaskIntent {
    let registration = RegistrationIdentity(destination: .init(rawValue: "s23-sdk-test-destination"),
        id: .init(rawValue: "s23-sdk-test-registration"), generation: .init(rawValue: 1))
    let rendition = RenditionIdentity(original: fixture.binding.original, inputLogIdentity: "synthetic-no-quality-claim",
        transformAssetIdentity: "synthetic-no-transform", transformAssetVersion: "test", outputConfigurationIdentity: "test",
        conversionVersion: "test", rendition: .init(rawValue: UUID().uuidString), deliveryContent: fixture.binding.original.content,
        publicationGeneration: .init(rawValue: 1))
    let operation = MediaOperationID(rawValue: UUID().uuidString), attempt = TransferAttemptID(rawValue: UUID().uuidString)
    let lease = MediaReadLease(id: .init(rawValue: UUID().uuidString), target: .rendition(rendition), operation: operation,
        registration: registration, context: .transport(attempt), epoch: .init(rawValue: UUID().uuidString), accessGeneration: .init(rawValue: 1))
    return .init(id: .init(rawValue: UUID().uuidString), context: .init(operation: operation, attempt: attempt,
        target: .rendition(rendition), registration: registration, gateGeneration: 1, storeIdentity: .init(rawValue: UUID())),
        session: session, taskDescription: UUID().uuidString, requestFingerprint: try .make(request: request),
        source: .download(rendition: rendition, range: try .init(lowerBound: 0, upperBound: 65_536), lease: lease))
}

/// Bounded waiting is test-only. No product timeout/retry/retention policy is
/// inferred from these limits and timeout is always an explicit probe failure.
private nonisolated func backgroundSDKWait(_ label: String, _ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(30))
    while !(await condition()) {
        guard ContinuousClock.now < deadline else { throw BackgroundSDKProbeError.timeout(label) }
        try await Task.sleep(for: .milliseconds(25))
    }
}

private nonisolated func backgroundSDKDrain(_ session: BackgroundMediaSession) async throws -> [BackgroundMediaSDKEvent] {
    let stream = try await session.events()
    var events: [BackgroundMediaSDKEvent] = []
    // Callers first observed actual invalidation, which finishes this stream.
    for await event in stream { events.append(event) }
    return events
}

private nonisolated func backgroundSDKExpectSequences(_ events: [BackgroundMediaSDKEvent], identity: BackgroundMediaSessionIdentity) {
    #expect(!events.isEmpty && events.allSatisfy { $0.session == identity && $0.stream == events.first?.stream })
    #expect(events.map(\.sequence) == events.indices.map { UInt64($0) + 1 })
}
