import Foundation

/// Only metadata requests belong here. Per-query tasks coalesce, including a
/// completed unknown result: the same reservation never starts a second HTTP.
actor URLSessionUploadMetadataRemote: UploadMetadataRemotePort {
    private struct Exchange {
        let query: CommittedUploadMetadataQuery
        let task: Task<BackendOutcome<UploadMetadataResponse>, Never>
    }
    private let connection: RegistrationConnection
    private let credentials: any RegistrationAuthorizationPort
    private let store: any MediaOperationStorePort
    private let observation: UploadMetadataHTTPObservation?
    private var exchanges: [String: Exchange] = [:]

    init(connection: RegistrationConnection, credentials: any RegistrationAuthorizationPort,
         store: any MediaOperationStorePort, observation: UploadMetadataHTTPObservation? = nil) {
        self.connection = connection; self.credentials = credentials; self.store = store; self.observation = observation
    }
    func create(_ query: CommittedUploadMetadataQuery) async -> BackendOutcome<UploadMetadataResponse> {
        guard case .create = query.query.kind else { return .failed(.rejected) }
        return await exchange(query)
    }
    func lookup(_ query: CommittedUploadMetadataQuery) async -> BackendOutcome<UploadMetadataResponse> {
        guard case .lookup = query.query.kind else { return .failed(.rejected) }
        return await exchange(query)
    }
    private func exchange(_ query: CommittedUploadMetadataQuery) async -> BackendOutcome<UploadMetadataResponse> {
        guard query.isCommitted, let key = try? UploadMetadataValidation.fingerprint(query) else { return .failed(.rejected) }
        if let old = exchanges[key] {
            guard UploadMetadataValidation.exact(old.query, query) else { return .failed(.rejected) }
            return await old.task.value
        }
        let task = Task { await self.perform(query) }
        exchanges[key] = .init(query: query, task: task)
        return await task.value
    }
    private func perform(_ query: CommittedUploadMetadataQuery) async -> BackendOutcome<UploadMetadataResponse> {
        do {
            _ = try await UploadMetadataScope.dispatch(store, query: query)
            var request = try UploadMetadataWire.http(query, connection: connection)
            let headers = try await authorization(query.query.request)
            for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
            _ = try await UploadMetadataScope.dispatch(store, query: query)
            guard !Task.isCancelled else { return .unknown }
            let response = try await GuardedUploadMetadataHTTP.perform(request, query: query, store: store, observation: observation)
            let currentHeaders = try await authorization(query.query.request)
            guard currentHeaders == headers, !Task.isCancelled else { return .unknown }
            _ = try await UploadMetadataScope.current(store, request: query.query.request)
            guard response.status == 200 else {
                return response.status == 401 || response.status == 403 ? .failed(.authenticationRequired) : .unknown
            }
            return .succeeded(try UploadMetadataWire.response(response.data, query: query))
        } catch UploadMetadataHTTPError.scopeRefused { return .notExecuted }
        catch is RegistrationAccessError { return .failed(.authenticationRequired) }
        catch { return .unknown }
    }
    private func authorization(_ request: UploadMetadataRequest) async throws -> [String: String] {
        _ = try await UploadMetadataScope.current(store, request: request)
        guard UploadMetadataValidation.exact(connection.destination, request.registration.server.registration.destination) else {
            throw RegistrationAccessError.credentialConflict
        }
        let material = try await credentials.authorization(for: connection, intent: request.registration.server.intent,
            storeIdentity: request.storeIdentity)
        _ = try await UploadMetadataScope.current(store, request: request)
        guard let secret = material.secret, !secret.isEmpty, secret.utf8.count <= 4096,
              secret.utf8.allSatisfy({ (33...126).contains($0) }),
              !material.bearer.isEmpty, material.bearer.utf8.count <= 4096,
              material.bearer.utf8.allSatisfy({ (33...126).contains($0) }) else { throw RegistrationAccessError.credentialConflict }
        return ["Authorization": "Bearer " + material.bearer, "X-FrameRelay-Registration-Secret": secret]
    }
}

nonisolated enum UploadMetadataHTTPError: Error { case scopeRefused, responseRefused, transport, cancelled }
nonisolated struct UploadMetadataHTTPSnapshot: Equatable, Sendable {
    var tasksCreated = 0
    var resumePermits = 0
    var taskCompletions = 0
    var sessionInvalidations = 0
    var continuationResumes = 0
    var redirectsRefused = 0
    var maximumRetainedBytes = 0
}
/// Counts only; no URL, credentials, response body or underlying error leaks.
@MainActor final class UploadMetadataHTTPObservation {
    fileprivate(set) var snapshot = UploadMetadataHTTPSnapshot()
}

/// Session, request and suspended task are constructed outside the writer lock.
/// Only the direct resume is inside its synchronous last-scope gate. Returning
/// waits for both native task completion and session invalidation, even refusal.
@MainActor final class GuardedUploadMetadataHTTP: NSObject, @preconcurrency URLSessionDataDelegate {
    private let request: URLRequest
    private let query: CommittedUploadMetadataQuery
    private let store: any MediaOperationStorePort
    private let observation: UploadMetadataHTTPObservation?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var dispatchWork: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var continuation: CheckedContinuation<PublicationHTTPResponse, Error>?
    private var response: HTTPURLResponse?
    private var data = Data()
    private var failure: UploadMetadataHTTPError?
    private var taskCompleted = false
    private var sessionInvalidated = false
    private var dispatchFinished = false
    private var invalidationRequested = false

    private init(request: URLRequest, query: CommittedUploadMetadataQuery, store: any MediaOperationStorePort,
                 observation: UploadMetadataHTTPObservation?) {
        self.request = request; self.query = query; self.store = store; self.observation = observation
    }
    static func perform(_ request: URLRequest, query: CommittedUploadMetadataQuery, store: any MediaOperationStorePort,
                        observation: UploadMetadataHTTPObservation? = nil) async throws -> PublicationHTTPResponse {
        let owner = GuardedUploadMetadataHTTP(request: request, query: query, store: store, observation: observation)
        return try await withTaskCancellationHandler { try await owner.run() } onCancel: {
            Task { @MainActor in owner.cancel() }
        }
    }
    private func run() async throws -> PublicationHTTPResponse {
        guard !Task.isCancelled else { throw UploadMetadataHTTPError.cancelled }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil; configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
            configuration.urlCredentialStorage = nil; configuration.connectionProxyDictionary = [:]; configuration.proxyConfigurations = []
            configuration.waitsForConnectivity = false; configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 20; configuration.httpMaximumConnectionsPerHost = 1
            configuration.httpAdditionalHeaders = [:]
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
            self.session = session
            let prepared = session.dataTask(with: request)
            task = prepared; observation?.snapshot.tasksCreated += 1
            deadline = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(21)) } catch { return }
                self?.cancel()
            }
            dispatchWork = Task { [self] in
                // No actor state, task construction, await or redispatch is
                // captured by this writer action: resume executes right here.
                let allowed = await store.performUploadMetadataIfCurrent(query) { prepared.resume() }
                dispatchFinished = true
                if allowed { observation?.snapshot.resumePermits += 1 }
                else {
                    failure = failure ?? .scopeRefused
                    prepared.cancel()
                    if !invalidationRequested { invalidationRequested = true; session.invalidateAndCancel() }
                }
                dispatchWork = nil
                finishIfTerminal()
            }
        }
    }
    private func cancel() {
        guard continuation != nil else { return }
        failure = failure ?? .cancelled
        task?.cancel()
        if !invalidationRequested { invalidationRequested = true; session?.invalidateAndCancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        failure = .responseRefused; observation?.snapshot.redirectsRefused += 1; completionHandler(nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
            ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, http.url == request.url, http.mimeType?.lowercased() == "application/json",
              http.expectedContentLength <= Int64(UploadMetadataWire.maximumBytes) else {
            failure = .responseRefused; completionHandler(.cancel); return
        }
        self.response = http; completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard failure == nil, data.count <= UploadMetadataWire.maximumBytes - self.data.count else {
            failure = .responseRefused; dataTask.cancel(); return
        }
        self.data.append(data)
        observation?.snapshot.maximumRetainedBytes = max(observation?.snapshot.maximumRetainedBytes ?? 0, self.data.count)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        observation?.snapshot.taskCompletions += 1; taskCompleted = true
        if error != nil { failure = failure ?? .transport }
        self.task = nil
        if !invalidationRequested { invalidationRequested = true; session.finishTasksAndInvalidate() }
        finishIfTerminal()
    }
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        observation?.snapshot.sessionInvalidations += 1; sessionInvalidated = true; self.session = nil
        if error != nil { failure = failure ?? .transport }
        finishIfTerminal()
    }
    private func finishIfTerminal() {
        guard dispatchFinished, taskCompleted, sessionInvalidated, let continuation else { return }
        self.continuation = nil; deadline?.cancel(); deadline = nil
        observation?.snapshot.continuationResumes += 1
        if let failure { continuation.resume(throwing: failure) }
        else if let response { continuation.resume(returning: .init(status: response.statusCode, data: data)) }
        else { continuation.resume(throwing: UploadMetadataHTTPError.responseRefused) }
    }
}
