import Foundation
import Network

/// Metadata only. This adapter advertises no upload, playback, confirmation or ACK capability.
actor URLSessionRegistrationRemote: RegistrationRemotePort {
    private let credentials: any RegistrationAuthorizationPort
    private let store: any MediaOperationStorePort
    init(credentials: any RegistrationAuthorizationPort, store: any MediaOperationStorePort) {
        self.credentials = credentials
        self.store = store
    }

    func checkConnection(_ connection: RegistrationConnection, bearer: String) async -> BackendOutcome<BackendCapabilities> {
        guard !bearer.isEmpty, bearer.utf8.count <= 4096,
              bearer.utf8.allSatisfy({ (33...126).contains($0) }) else { return .failed(.authenticationRequired) }
        return await discovery(connection, initialBearer: bearer, storeIdentity: nil)
    }
    func discover(_ connection: RegistrationConnection, storeIdentity: RegistrationStoreIdentity) async -> BackendOutcome<BackendCapabilities> {
        await discovery(connection, initialBearer: nil, storeIdentity: storeIdentity)
    }
    private func discovery(_ connection: RegistrationConnection, initialBearer: String?, storeIdentity: RegistrationStoreIdentity?) async -> BackendOutcome<BackendCapabilities> {
        do {
            let response = try await request(connection, path: "capabilities", intent: nil, post: false, initialBearer: initialBearer, storeIdentity: storeIdentity)
            guard response.status == 200 else { return .failed(failure(response.status)) }
            return .succeeded(try RegistrationWire.capabilities(response.data, connection: connection))
        } catch let error as RegistrationAccessError { return .failed(accessFailure(error)) }
        catch is BackendContractError { return .failed(.unknownSchema) }
        catch { return .failed(.connectionUnavailable) }
    }

    func register(_ command: RegistrationCommand, at connection: RegistrationConnection, storeIdentity: RegistrationStoreIdentity) async -> BackendOutcome<RegistrationServerReceipt> {
        guard command.isCommitted, command.intent.destination == connection.destination else { return .failed(.rejected) }
        return await receipt(command.intent, connection: connection, post: true, storeIdentity: storeIdentity)
    }

    func lookup(_ intent: RegistrationIntent, at connection: RegistrationConnection, storeIdentity: RegistrationStoreIdentity) async -> BackendOutcome<RegistrationServerReceipt> {
        guard intent.destination == connection.destination else { return .failed(.rejected) }
        return await receipt(intent, connection: connection, post: false, storeIdentity: storeIdentity)
    }

    private func receipt(_ intent: RegistrationIntent, connection: RegistrationConnection, post: Bool, storeIdentity: RegistrationStoreIdentity) async -> BackendOutcome<RegistrationServerReceipt> {
        do {
            let response = try await request(connection,
                path: post ? "registrations" : "registration-intents/" + intent.operation.rawValue,
                intent: intent, post: post, storeIdentity: storeIdentity)
            if response.status == 200 { return .succeeded(try RegistrationWire.receipt(response.data, intent: intent)) }
            if !post, response.status == 404, RegistrationWire.isKnownAbsent(response.data, intent: intent) { return .notExecuted }
            return .failed(failure(response.status))
        } catch let error as RegistrationAccessError { return .failed(accessFailure(error)) }
        catch is BackendContractError { return .failed(.unknownSchema) }
        catch { return .unknown }
    }

    private func request(_ connection: RegistrationConnection, path: String,
                         intent: RegistrationIntent?, post: Bool, initialBearer: String? = nil, storeIdentity: RegistrationStoreIdentity?) async throws -> RegistrationHTTPResponse {
        if let intent {
            guard RegistrationWireIdentity.isCanonical(intent.operation.rawValue), intent.destination == connection.destination else {
                throw BackendContractError.identityMismatch
            }
        }
        let material: RegistrationAuthorization
        if let initialBearer { material = .init(bearer: initialBearer, secret: nil) }
        else {
            guard let storeIdentity else { throw RegistrationAccessError.credentialConflict }
            try await requireStore(storeIdentity)
            material = try await credentials.authorization(for: connection, intent: intent, storeIdentity: storeIdentity)
            try await requireStore(storeIdentity)
        }
        let url = connection.endpoint.url(path: path, destination: !post && intent != nil ? connection.destination : nil)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15)
        request.httpMethod = post ? "POST" : "GET"
        request.httpShouldHandleCookies = false
        request.setValue("Bearer " + material.bearer, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let intent {
            guard let secret = material.secret else { throw RegistrationAccessError.credentialMissing }
            request.setValue(secret, forHTTPHeaderField: "X-FrameRelay-Registration-Secret")
            if post {
                request.httpBody = try RegistrationWire.body(intent)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
        }
        return try await RegistrationURLSessionRequest.perform(request)
    }

    private func requireStore(_ identity: RegistrationStoreIdentity) async throws {
        guard case .loaded(let snapshot) = await store.load() else { throw RegistrationAccessError.credentialUnavailable }
        guard snapshot.storeIdentity == identity else { throw RegistrationAccessError.credentialConflict }
    }

    private func failure(_ status: Int) -> BackendFailure {
        switch status {
        case 401, 403: .authenticationRequired
        case 409, 422: .rejected
        case 503: .connectionUnavailable
        default: .unknownSchema
        }
    }
    private func accessFailure(_ error: RegistrationAccessError) -> BackendFailure {
        switch error {
        case .credentialUnavailable: .inaccessible
        case .invalidConfiguration, .credentialConflict, .corruptCredential: .rejected
        case .credentialMissing: .authenticationRequired
        }
    }
}

nonisolated struct RegistrationHTTPResponse: Sendable {
    let status: Int
    let data: Data
}
nonisolated enum RegistrationHTTPError: Error { case refusedResponse, transport, cancelled }

nonisolated struct RegistrationHTTPSnapshot: Equatable, Sendable {
    var responseReceived = false
    var maximumRetainedBytes = 0
    var redirectsRefused = 0
    var taskCompletions = 0
    var sessionInvalidations = 0
    var continuationResumes = 0
}
/// Optional test observation contains counts only, never network material.
@MainActor final class RegistrationHTTPObservation {
    fileprivate(set) var snapshot = RegistrationHTTPSnapshot()
}

/// Each bounded request owns a session and awaits both task completion and session invalidation.
/// No URL, header, response body or underlying NSError is emitted as diagnostics.
@MainActor final class RegistrationURLSessionRequest: NSObject, @preconcurrency URLSessionDataDelegate {
    private let request: URLRequest
    private let observation: RegistrationHTTPObservation?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var deadline: Task<Void, Never>?
    private var continuation: CheckedContinuation<RegistrationHTTPResponse, Error>?
    private var response: HTTPURLResponse?
    private var data = Data()
    private var failure: RegistrationHTTPError?
    private var completed = false

    private init(request: URLRequest, observation: RegistrationHTTPObservation?) {
        self.request = request
        self.observation = observation
    }
    static func perform(_ request: URLRequest, observation: RegistrationHTTPObservation? = nil) async throws -> RegistrationHTTPResponse {
        let operation = RegistrationURLSessionRequest(request: request, observation: observation)
        return try await withTaskCancellationHandler {
            try await operation.run()
        } onCancel: {
            Task { @MainActor in operation.cancel() }
        }
    }
    private func run() async throws -> RegistrationHTTPResponse {
        if Task.isCancelled { throw RegistrationHTTPError.cancelled }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.urlCredentialStorage = nil
            configuration.connectionProxyDictionary = [:]
            configuration.proxyConfigurations = []
            configuration.waitsForConnectivity = false
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 20
            configuration.httpMaximumConnectionsPerHost = 1
            configuration.httpAdditionalHeaders = [:]
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
            self.session = session
            let task = session.dataTask(with: request)
            self.task = task
            deadline = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(21)) } catch { return }
                self?.cancel()
            }
            task.resume()
        }
    }
    private func cancel() {
        guard !completed else { return }
        failure = failure ?? .cancelled
        task?.cancel()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        failure = .refusedResponse
        observation?.snapshot.redirectsRefused += 1
        completionHandler(nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else { completionHandler(.cancelAuthenticationChallenge, nil) }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        observation?.snapshot.responseReceived = true
        guard let http = response as? HTTPURLResponse, http.url == request.url,
              http.mimeType?.lowercased() == "application/json",
              http.expectedContentLength <= Int64(RegistrationWire.maximumResponseBytes) else {
            failure = .refusedResponse
            completionHandler(.cancel)
            return
        }
        self.response = http
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard failure == nil, data.count <= RegistrationWire.maximumResponseBytes - self.data.count else {
            failure = .refusedResponse
            dataTask.cancel()
            return
        }
        self.data.append(data)
        observation?.snapshot.maximumRetainedBytes = max(observation?.snapshot.maximumRetainedBytes ?? 0, self.data.count)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        observation?.snapshot.taskCompletions += 1
        completed = true
        if error != nil { failure = failure ?? .transport }
        deadline?.cancel()
        deadline = nil
        self.task = nil
        session.finishTasksAndInvalidate()
    }
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        observation?.snapshot.sessionInvalidations += 1
        self.session = nil
        guard let continuation else { return }
        self.continuation = nil
        observation?.snapshot.continuationResumes += 1
        if let failure { continuation.resume(throwing: failure) }
        else if error != nil || !completed { continuation.resume(throwing: RegistrationHTTPError.transport) }
        else if let response { continuation.resume(returning: .init(status: response.statusCode, data: data)) }
        else { continuation.resume(throwing: RegistrationHTTPError.refusedResponse) }
    }
}
