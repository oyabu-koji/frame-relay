import CryptoKit
import Darwin
import Foundation

extension BackgroundMediaRequestFingerprint {
    /// A conservative request boundary for the independent background basis.
    /// No URL, credential value, or request body is written to the journal.
    /// Query/custom-header wire formats need a separately adopted safe mapping.
    nonisolated static func make(request: URLRequest) throws -> Self {
        guard let url = request.url, let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.percentEncodedQuery == nil, components.percentEncodedFragment == nil,
              request.httpBody == nil, request.httpBodyStream == nil else {
            throw BackendContractError.invalidValue
        }
        if let port = components.port, !(1...65_535).contains(port) { throw BackendContractError.invalidValue }
        let method = request.httpMethod ?? "GET"
        guard !method.isEmpty, method.utf8.allSatisfy({ (65...90).contains($0) }) else {
            throw BackendContractError.invalidValue
        }
        let fixed: Set<String> = ["accept", "accept-encoding", "content-type", "content-length", "content-encoding",
            "range", "if-match", "if-none-match", "if-range", "if-modified-since", "if-unmodified-since"]
        let credentials: Set<String> = ["authorization", "proxy-authorization", "cookie"]
        var headers: [(String, String)] = [], seen: Set<String> = []
        for (rawName, value) in request.allHTTPHeaderFields ?? [:] {
            let name = rawName.lowercased()
            guard seen.insert(name).inserted, fixed.contains(name) || credentials.contains(name),
                  !value.contains("\r"), !value.contains("\n") else { throw BackendContractError.invalidValue }
            // Credential rotation is authorized by registration/credential
            // owners. A fingerprint grants no credential authority.
            headers.append((name, credentials.contains(name) ? "present" : value))
        }
        headers.sort { $0.0 < $1.0 }
        var safe = Data()
        func append(_ value: String) {
            let bytes = Data(value.utf8)
            safe.append(contentsOf: String(bytes.count).utf8)
            safe.append(58)
            safe.append(bytes)
        }
        append("FrameRelay-background-request-v1")
        append(method)
        append(url.absoluteURL.absoluteString)
        for (name, value) in headers { append(name); append(value) }
        return .init(sha256: SHA256.hash(data: safe).map { String(format: "%02x", $0) }.joined())
    }
}

/// A real background URLSession whose tasks are created suspended. There is no
/// positive resume path until strict VPN-underlay/redirect admission is solved.
/// Every mutable field is confined to the serial delegate queue; only immutable
/// values cross the one unbounded, single-consumer event stream.
nonisolated final class BackgroundMediaSession: NSObject, BackgroundMediaSessionPort,
    URLSessionDownloadDelegate, @unchecked Sendable {
    let identity: BackgroundMediaSessionIdentity
    private let delegateDispatch: DispatchQueue
    private let delegateOperations: OperationQueue
    private let streamID = UUID()
    private let eventStream: AsyncStream<BackgroundMediaSDKEvent>
    private let eventContinuation: AsyncStream<BackgroundMediaSDKEvent>.Continuation
    private var session: URLSession!
    private var streamTaken = false
    private var sequence: UInt64 = 0
    private var invalidationRequested = false
    private var invalidated = false
    private var pendingCreations: [BackgroundMediaTaskID: BackgroundMediaTaskIntent] = [:]
    private var creations: [BackgroundMediaTaskID: (BackgroundMediaTaskIntent, BackgroundMediaTaskBinding)] = [:]
    private var terminals: [BackgroundMediaSDKTerminal] = []

    init(identity: BackgroundMediaSessionIdentity) throws {
        try BackgroundMediaSessionRegistry.claim(identity)
        self.identity = identity
        let dispatch = DispatchQueue(label: "FrameRelay.background-media." + UUID().uuidString)
        delegateDispatch = dispatch
        let operations = OperationQueue()
        operations.name = "FrameRelay.background-media.delegate"
        operations.maxConcurrentOperationCount = 1
        operations.underlyingQueue = dispatch
        delegateOperations = operations
        let events = AsyncStream<BackgroundMediaSDKEvent>.makeStream(bufferingPolicy: .unbounded)
        eventStream = events.stream
        eventContinuation = events.continuation
        super.init()
        // Session creation and delegate callbacks share this dispatch queue, so
        // a reconnect callback cannot race the session field's initialization.
        dispatch.sync {
            let settings = URLSessionConfiguration.background(withIdentifier: identity.identifier.rawValue)
            settings.allowsCellularAccess = false
            settings.urlCache = nil
            settings.urlCredentialStorage = nil
            settings.httpCookieStorage = nil
            settings.httpShouldSetCookies = false
            settings.requestCachePolicy = .reloadIgnoringLocalCacheData
            settings.sessionSendsLaunchEvents = true
            session = URLSession(configuration: settings, delegate: self, delegateQueue: operations)
        }
    }

    func events() async throws -> AsyncStream<BackgroundMediaSDKEvent> {
        try await withCheckedThrowingContinuation { continuation in
            delegateOperations.addOperation { [self] in
                guard !streamTaken else { continuation.resume(throwing: BackendContractError.wrongStage); return }
                streamTaken = true
                continuation.resume(returning: eventStream)
            }
        }
    }

    func createSuspended(_ intent: BackgroundMediaTaskIntent, request: URLRequest,
                         upload: BackgroundMediaUploadFile?) async -> BackendOutcome<BackgroundMediaTaskBinding> {
        await withCheckedContinuation { continuation in
            delegateOperations.addOperation { [self] in
                do {
                    try intent.validate()
                    guard intent.session == identity,
                          try BackgroundMediaRequestFingerprint.make(request: request) == intent.requestFingerprint else {
                        throw BackendContractError.identityMismatch
                    }
                    try validateSource(intent, request: request, upload: upload)
                } catch { continuation.resume(returning: .failed(.rejected)); return }
                guard !invalidationRequested, !invalidated else { continuation.resume(returning: .notExecuted); return }
                if let old = creations[intent.id] {
                    continuation.resume(returning: old.0 == intent ? .succeeded(old.1) : .failed(.contentMismatch))
                    return
                }
                if let pending = pendingCreations[intent.id] {
                    continuation.resume(returning: pending == intent ? .inProgress : .failed(.contentMismatch))
                    return
                }
                guard !pendingCreations.values.contains(where: { $0.taskDescription == intent.taskDescription }),
                      !creations.values.contains(where: { $0.0.taskDescription == intent.taskDescription }) else {
                    continuation.resume(returning: .unknown); return
                }
                pendingCreations[intent.id] = intent
                session.getAllTasks { [self] tasks in
                    pendingCreations.removeValue(forKey: intent.id)
                    guard !invalidationRequested, !invalidated else { continuation.resume(returning: .notExecuted); return }
                    // A matching description after an interrupted create/attach
                    // is ambiguous. Never adopt it or create another task.
                    guard !tasks.contains(where: { $0.taskDescription == intent.taskDescription }) else {
                        continuation.resume(returning: .unknown); return
                    }
                    do { try validateSource(intent, request: request, upload: upload) }
                    catch { continuation.resume(returning: .failed(.rejected)); return }
                    let task: URLSessionTask
                    switch intent.source {
                    case .upload:
                        guard let upload else { continuation.resume(returning: .failed(.rejected)); return }
                        task = session.uploadTask(with: request, fromFile: upload.url)
                    case .download:
                        task = session.downloadTask(with: request)
                    }
                    task.taskDescription = intent.taskDescription
                    let binding = BackgroundMediaTaskBinding(session: identity, taskIdentifier: task.taskIdentifier,
                        taskDescription: intent.taskDescription)
                    creations[intent.id] = (intent, binding)
                    // The SDK specifies initial suspension. Do not repair an
                    // unexpected SDK state by resuming, stopping, or recreating.
                    guard task.state == .suspended else { continuation.resume(returning: .unknown); return }
                    continuation.resume(returning: .succeeded(binding))
                }
            }
        }
    }

    func enumerate() async -> BackendOutcome<[BackgroundMediaTaskObservation]> {
        await withCheckedContinuation { continuation in
            delegateOperations.addOperation { [self] in
                guard !invalidated else { continuation.resume(returning: .unknown); return }
                session.getAllTasks { [self] tasks in
                    // No sorting, deduplication, task adoption, or absent-task
                    // terminal is produced from this current SDK list.
                    continuation.resume(returning: .succeeded(tasks.map(observation)))
                }
            }
        }
    }

    func resume(_ binding: BackgroundMediaTaskBinding,
                permit: BackgroundMediaStrictPermit) async -> BackendOutcome<BackgroundMediaTaskBinding> {
        // No valid strict permit producer exists. Even a caller-made permit
        // cannot turn path observation/cellular policy into an underlay proof.
        .notExecuted
    }

    func requestStop(_ binding: BackgroundMediaTaskBinding) async {
        await withCheckedContinuation { continuation in
            delegateOperations.addOperation { [self] in
                guard binding.session == identity, !invalidated else { continuation.resume(); return }
                session.getAllTasks { [self] tasks in
                    let matches = tasks.filter { $0.taskIdentifier == binding.taskIdentifier
                        && $0.taskDescription == binding.taskDescription }
                    if matches.count == 1 { matches[0].cancel() }
                    // This only acknowledges delivery of the cancel request.
                    // Neither absence nor cancel acceptance caches a terminal.
                    continuation.resume()
                }
            }
        }
    }

    func observeTerminal(_ binding: BackgroundMediaTaskBinding) async -> BackendOutcome<BackgroundMediaSDKTerminal> {
        await withCheckedContinuation { continuation in
            delegateOperations.addOperation { [self] in
                guard binding.session == identity else { continuation.resume(returning: .unknown); return }
                let exact = terminals.filter { $0.binding == binding }
                if let first = exact.first, exact.allSatisfy({ $0 == first }) {
                    continuation.resume(returning: .succeeded(first))
                } else if !exact.isEmpty { continuation.resume(returning: .unknown) }
                else {
                    let known = creations.values.contains { $0.1 == binding }
                    continuation.resume(returning: known && !invalidated ? .inProgress : .unknown)
                }
            }
        }
    }

    func invalidate() async {
        await withCheckedContinuation { continuation in
            delegateOperations.addOperation { [self] in
                if !invalidationRequested, !invalidated {
                    invalidationRequested = true
                    // Known callers cancel their exact tasks separately. Unknown
                    // enumerated tasks are not implicitly swept by this method.
                    session.finishTasksAndInvalidate()
                }
                continuation.resume()
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        dispatchPrecondition(condition: .onQueue(delegateDispatch))
        guard owns(session), !invalidated else { return }
        let outcome: BackgroundMediaSDKOutcome
        if let error {
            let failure = error as NSError
            outcome = failure.domain == NSURLErrorDomain && failure.code == NSURLErrorCancelled
                ? .cancelled : .failed(code: failure.code)
        } else { outcome = .completed }
        if let description = task.taskDescription, let uuid = UUID(uuidString: description),
           uuid.uuidString.caseInsensitiveCompare(description) == .orderedSame {
            let terminal = BackgroundMediaSDKTerminal(binding: .init(session: identity,
                taskIdentifier: task.taskIdentifier, taskDescription: description), outcome: outcome)
            terminals.append(terminal)
            emit(.taskTerminal(terminal))
        } else { emit(.unknownTaskTerminal(observation(task), outcome: outcome)) }
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        dispatchPrecondition(condition: .onQueue(delegateDispatch))
        guard owns(session), !invalidated else { return }
        invalidated = true
        BackgroundMediaSessionRegistry.release(identity)
        emit(.sessionInvalidated(errorCode: error.map { ($0 as NSError).code }))
        // This SDK callback is the session's last message. All earlier events,
        // including finish-events barriers, remain in the unbounded buffer.
        eventContinuation.finish()
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        dispatchPrecondition(condition: .onQueue(delegateDispatch))
        guard owns(session), !invalidated else { return }
        emit(.finishedEvents)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        dispatchPrecondition(condition: .onQueue(delegateDispatch))
        guard owns(session), !invalidated else { return }
        // Foundation deletes this URL when the delegate returns. A safe,
        // synchronous managed ingress has not been adopted for S23. Never pass
        // the ephemeral URL to a Task/stream or manufacture TemporaryMedia.
        emit(.downloadArtifactUnavailable(observation(downloadTask)))
    }

    private func owns(_ candidate: URLSession) -> Bool { candidate === session }
    private func emit(_ value: BackgroundMediaSDKEventValue) {
        let next = sequence.addingReportingOverflow(1)
        precondition(!next.overflow, "Background event sequence exhausted")
        sequence = next.partialValue
        eventContinuation.yield(.init(session: identity, stream: streamID, sequence: sequence, value: value))
    }
    private func observation(_ task: URLSessionTask) -> BackgroundMediaTaskObservation {
        let kind: BackgroundMediaTaskKind = task is URLSessionUploadTask ? .upload
            : task is URLSessionDownloadTask ? .download : .other
        let state: BackgroundMediaSDKTaskState
        switch task.state {
        case .running: state = .running
        case .suspended: state = .suspended
        case .canceling: state = .canceling
        case .completed: state = .completed
        @unknown default: state = .unknown
        }
        return .init(session: identity, taskIdentifier: task.taskIdentifier, taskDescription: task.taskDescription,
            kind: kind, state: state, bytesSent: task.countOfBytesSent, bytesReceived: task.countOfBytesReceived)
    }

    private func validateSource(_ intent: BackgroundMediaTaskIntent, request: URLRequest,
                                upload: BackgroundMediaUploadFile?) throws {
        switch intent.source {
        case .upload(_, _, let source):
            guard let upload, upload.identity == source,
                  request.httpMethod == "PUT" || request.httpMethod == "POST",
                  request.value(forHTTPHeaderField: "Range") == nil else { throw BackendContractError.identityMismatch }
            try Self.validateUpload(upload)
        case .download(_, let range, _):
            guard upload == nil, request.httpMethod == "GET" else { throw BackendContractError.identityMismatch }
            let expected = range.map { "bytes=\($0.lowerBound)-\($0.upperBound - 1)" }
            guard request.value(forHTTPHeaderField: "Range") == expected else { throw BackendContractError.identityMismatch }
        }
    }

    private static func validateUpload(_ upload: BackgroundMediaUploadFile) throws {
        let url = upload.url.standardizedFileURL, source = upload.identity
        guard UUID(uuidString: source.id.rawValue) != nil, url.isFileURL,
              url.path == url.resolvingSymlinksInPath().path,
              url.lastPathComponent == source.id.rawValue + ".upload" else { throw BackendContractError.identityMismatch }
        let root = url.deletingLastPathComponent()
        guard root.lastPathComponent == "background-upload-sources" else { throw BackendContractError.identityMismatch }
        _ = try ExplorationRunDirectory.openExisting(at: root.deletingLastPathComponent())
        let rootFD = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard rootFD >= 0 else { throw BackendContractError.identityMismatch }
        defer { Darwin.close(rootFD) }
        var info = stat(), named = stat()
        guard fstat(rootFD, &info) == 0, info.st_mode & S_IFMT == S_IFDIR,
              Int64(info.st_dev) == source.directoryDevice, UInt64(info.st_ino) == source.directoryInode,
              fstatat(rootFD, url.lastPathComponent, &named, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw BackendContractError.identityMismatch
        }
        let fingerprint = try OriginalFileFingerprint(info: named)
        guard fingerprint.device == source.file.device, fingerprint.inode == source.file.inode,
              fingerprint.size == source.file.size, fingerprint.modifiedSeconds == source.file.modifiedSeconds,
              fingerprint.modifiedNanoseconds == source.file.modifiedNanoseconds,
              fingerprint.changedSeconds == source.file.changedSeconds,
              fingerprint.changedNanoseconds == source.file.changedNanoseconds else {
            throw BackendContractError.identityMismatch
        }
    }
}

/// Foundation forbids reuse of a background identifier before actual session
/// invalidation. A generation change or ARC/deinit is not that callback.
private nonisolated enum BackgroundMediaSessionRegistry {
    private static let lock = NSLock()
    private static var owners: [BackgroundMediaSessionID: BackgroundMediaSessionGeneration] = [:]
    static func claim(_ identity: BackgroundMediaSessionIdentity) throws {
        let name = identity.identifier.rawValue
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        guard !name.isEmpty, name.utf8.count <= 255,
              name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { throw BackendContractError.invalidValue }
        lock.lock(); defer { lock.unlock() }
        guard owners[identity.identifier] == nil else { throw BackendContractError.readersActive }
        owners[identity.identifier] = identity.generation
    }
    static func release(_ identity: BackgroundMediaSessionIdentity) {
        lock.lock(); defer { lock.unlock() }
        guard owners[identity.identifier] == identity.generation else { return }
        owners.removeValue(forKey: identity.identifier)
    }
}
