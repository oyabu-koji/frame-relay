import Foundation
import Network

actor URLSessionPublicationRemote: PublicationRemotePort {
    private let connection: RegistrationConnection
    private let credentials: any RegistrationAuthorizationPort
    private let store: any MediaOperationStorePort
    private let identity: RegistrationStoreIdentity
    init(connection: RegistrationConnection, credentials: any RegistrationAuthorizationPort,
         store: any MediaOperationStorePort, identity: RegistrationStoreIdentity) {
        self.connection = connection; self.credentials = credentials; self.store = store; self.identity = identity
    }
    func manifest(original: OriginalContent, registration: RegistrationIdentity) async -> BackendOutcome<PublicationManifest> {
        do {
            let request = try PublicationWire.manifestRequest(original, registration)
            let value = try await exchange(path: "manifest", request: request, registration: registration)
            return .succeeded(try PublicationWire.decodeManifest(value, original: original))
        } catch { return outcome(error) }
    }
    func distribute(_ request: PublicationDistributionRequest) async -> BackendOutcome<PublicationDistribution> {
        await distribution(request, lookup: false)
    }
    func lookupDistribution(_ request: PublicationDistributionRequest) async -> BackendOutcome<PublicationDistribution> {
        await distribution(request, lookup: true)
    }
    private func distribution(_ request: PublicationDistributionRequest, lookup: Bool) async -> BackendOutcome<PublicationDistribution> {
        do {
            let original = try PublicationWire.distributionRequest(request)
            let query = try lookup ? PublicationWire.lookupRequest(registration: request.gate.registration, kind: "distribution", operation: request.operation.rawValue) : original
            let value = try await exchange(path: lookup ? "operations/lookup" : "distributions", request: query, registration: request.gate.registration, original: lookup ? original : nil)
            return .succeeded(try PublicationWire.decodeDistribution(value, expected: request))
        } catch { return outcome(error) }
    }
    func invalidations(registration: RegistrationIdentity, after: InvalidationID?) async -> BackendOutcome<PublicationInvalidationPage> {
        do {
            let request = PublicationWire.request(["registration": try PublicationWire.registration(registration),
                "after_invalidation_id": try after.map { try PublicationWire.text($0.rawValue) } ?? .null, "limit": .string("8")])
            let value = try await exchange(path: "invalidations", request: request, registration: registration)
            let object = try value.object(keys: ["invalidations", "next_after"])
            guard case .array(let items) = object["invalidations"], items.count <= 8 else { throw BackendContractError.unsupportedVersion }
            let records = try items.map { try PublicationWire.decodeInvalidation($0, registration: registration) }
            let next = object["next_after"] == .null ? nil : InvalidationID(rawValue: try object["next_after"]!.opaque())
            let ids = records.map { $0.id.rawValue }
            guard Set(ids).count == ids.count, zip(ids, ids.dropFirst()).allSatisfy({ $0.utf8.lexicographicallyPrecedes($1.utf8) }),
                  after == nil || ids.allSatisfy({ after!.rawValue.utf8.lexicographicallyPrecedes($0.utf8) }),
                  next == nil || (!records.isEmpty && next == records.last?.id) else { throw BackendContractError.identityMismatch }
            return .succeeded(.init(records: records, nextAfter: next))
        } catch { return outcome(error) }
    }
    func send(_ entry: BackendSyncEntry) async -> BackendOutcome<BackendSyncResponse> { await sync(entry, lookup: false) }
    func lookup(_ entry: BackendSyncEntry) async -> BackendOutcome<BackendSyncResponse> { await sync(entry, lookup: true) }
    private func sync(_ entry: BackendSyncEntry, lookup: Bool) async -> BackendOutcome<BackendSyncResponse> {
        do {
            // A caller cannot turn a fabricated record into a wire confirmation.
            let snapshot = try await PublicationStoreBoundary.load(store, identity: identity)
            switch entry {
            case .confirmation(let record): guard snapshot.confirmations.contains(record) else { throw BackendContractError.notCommitted }
            case .invalidation(let ack): guard snapshot.invalidations.contains(ack) else { throw BackendContractError.notCommitted }
            }
            let original = try PublicationWire.syncRequest(entry)
            let request = try lookup ? PublicationWire.lookupRequest(entry) : original
            let path: String
            switch entry { case .confirmation: path = "confirmations"; case .invalidation: path = "acknowledgements" }
            let value = try await exchange(path: lookup ? "operations/lookup" : path, request: request,
                registration: entry.registration, original: lookup ? original : nil)
            return .succeeded(try PublicationWire.decodeSync(value, entry: entry))
        } catch { return outcome(error) }
    }
    private func exchange(path: String, request: PublicationJSON, registration: RegistrationIdentity,
                          original: PublicationJSON? = nil) async throws -> PublicationJSON {
        let headers = try await authorizationHeaders(registration)
        var http = URLRequest(url: connection.endpoint.url(path: "publication/" + path), cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 15)
        http.httpMethod = "POST"; http.httpShouldHandleCookies = false
        http.httpBody = try PublicationWire.body(request)
        for (name, value) in headers { http.setValue(value, forHTTPHeaderField: name) }
        http.setValue("application/json", forHTTPHeaderField: "Content-Type")
        http.setValue("application/json", forHTTPHeaderField: "Accept")
        http.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let response = try await PublicationURLSessionRequest.perform(http)
        _ = try await PublicationStoreBoundary.load(store, identity: identity)
        guard response.status == 200 else {
            if original != nil, response.status == 404, PublicationWire.isAbsent(response.data) { throw PublicationRemoteError.absent }
            if response.status == 401 || response.status == 403 { throw PublicationRemoteError.authentication }
            // 409 can follow a lost earlier response. It is never known absence.
            throw PublicationRemoteError.unresolved
        }
        return try original.map { try PublicationWire.lookupResult(response.data, lookup: request, original: $0) }
            ?? PublicationWire.envelope(response.data, request: request)
    }
    func authorizationHeaders(_ registration: RegistrationIdentity) async throws -> [String: String] {
        let before = try await PublicationStoreBoundary.load(store, identity: identity)
        guard PublicationStoreBoundary.exact(registration.destination, connection.destination),
              let historical = before.registrations.first(where: { $0.server.registration == registration }), historical.isCommitted,
              PublicationStoreBoundary.exact(historical.server.registration, registration) else { throw RegistrationAccessError.credentialMissing }
        let material = try await credentials.authorization(for: connection, intent: historical.server.intent, storeIdentity: identity)
        let after = try await PublicationStoreBoundary.load(store, identity: identity)
        guard after.registrations.contains(historical), let secret = material.secret,
              !material.bearer.isEmpty, material.bearer.utf8.count <= 4096,
              material.bearer.utf8.allSatisfy({ (33...126).contains($0) }), !secret.isEmpty,
              secret.utf8.count <= 4096, secret.utf8.allSatisfy({ (33...126).contains($0) }) else { throw RegistrationAccessError.credentialConflict }
        return ["Authorization": "Bearer " + material.bearer, "X-FrameRelay-Registration-Secret": secret]
    }
    private func outcome<T>(_ error: Error) -> BackendOutcome<T> {
        if let error = error as? PublicationRemoteError {
            switch error { case .absent: return .notExecuted; case .authentication: return .failed(.authenticationRequired); case .unresolved: return .unknown }
        }
        if error is RegistrationAccessError { return .failed(.authenticationRequired) }
        return .unknown
    }
}
nonisolated private enum PublicationRemoteError: Error { case absent, authentication, unresolved }

nonisolated struct PublicationHTTPResponse: Sendable {
    let status: Int
    let data: Data
}
nonisolated enum PublicationHTTPError: Error { case refusedResponse, transport, cancelled }

nonisolated struct PublicationHTTPSnapshot: Equatable, Sendable {
    var responseReceived = false
    var maximumRetainedBytes = 0
    var redirectsRefused = 0
    var taskCompletions = 0
    var sessionInvalidations = 0
    var continuationResumes = 0
}
/// Optional test observation contains counts only, never network material.
@MainActor final class PublicationHTTPObservation {
    fileprivate(set) var snapshot = PublicationHTTPSnapshot()
}

/// Each bounded request owns a session and awaits both task completion and session invalidation.
/// No URL, header, response body or underlying NSError is emitted as diagnostics.
@MainActor final class PublicationURLSessionRequest: NSObject, @preconcurrency URLSessionDataDelegate {
    private let request: URLRequest
    private let observation: PublicationHTTPObservation?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var deadline: Task<Void, Never>?
    private var continuation: CheckedContinuation<PublicationHTTPResponse, Error>?
    private var response: HTTPURLResponse?
    private var data = Data()
    private var failure: PublicationHTTPError?
    private var completed = false

    private init(request: URLRequest, observation: PublicationHTTPObservation?) {
        self.request = request
        self.observation = observation
    }
    static func perform(_ request: URLRequest, observation: PublicationHTTPObservation? = nil) async throws -> PublicationHTTPResponse {
        let operation = PublicationURLSessionRequest(request: request, observation: observation)
        return try await withTaskCancellationHandler {
            try await operation.run()
        } onCancel: {
            Task { @MainActor in operation.cancel() }
        }
    }
    private func run() async throws -> PublicationHTTPResponse {
        if Task.isCancelled { throw PublicationHTTPError.cancelled }
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
              http.expectedContentLength <= Int64(PublicationWire.maximumBytes) else {
            failure = .refusedResponse
            completionHandler(.cancel)
            return
        }
        self.response = http
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard failure == nil, data.count <= PublicationWire.maximumBytes - self.data.count else {
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
        else if error != nil || !completed { continuation.resume(throwing: PublicationHTTPError.transport) }
        else if let response { continuation.resume(returning: .init(status: response.statusCode, data: data)) }
        else { continuation.resume(throwing: PublicationHTTPError.refusedResponse) }
    }
}
