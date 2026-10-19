import Foundation

/// Endpoint/wire interpretation is injected. S25 does not adopt the legacy
/// server's result headers as the product distribution protocol.
nonisolated struct FixedRenditionHTTPBinding: Sendable {
    let url: URL
    let contentType: String
    let headers: @Sendable (RetrieveMediaCommand) async throws -> [String: String]
    let validateIdentity: @Sendable (HTTPURLResponse, RetrieveMediaCommand) throws -> Void
}

/// URLSession does the network work; delegate state stays on its main queue.
/// Only bounded Data crosses to the reader actor, never an SDK task.
@MainActor final class FixedRenditionHTTPClient: NSObject, @preconcurrency URLSessionDataDelegate {
    private let binding: FixedRenditionHTTPBinding
    private var session: URLSession!
    private var entries: [Int: Entry] = [:]
    private var invalidationWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var closed = false
    private(set) var invalidated = false
    private(set) var started = 0
    private(set) var completed = 0
    private(set) var receivedBytes: UInt64 = 0
    /// Logical Data payload held by this adapter, not URLSession/SDK heap use.
    var bufferedPayloadBytes: UInt64 { entries.values.reduce(0) { $0 + UInt64($1.bytes.count) } }
    private(set) var peakBufferedPayloadBytes: UInt64 = 0
    private(set) var refusedRedirects = 0

    init(binding: FixedRenditionHTTPBinding) {
        self.binding = binding
        super.init()
        let settings = URLSessionConfiguration.ephemeral
        settings.urlCache = nil; settings.urlCredentialStorage = nil
        settings.httpCookieStorage = nil; settings.httpShouldSetCookies = false
        settings.requestCachePolicy = .reloadIgnoringLocalCacheData
        // Public transport prohibition, not a guarantee about VPN underlying
        // paths or OS background continuation (those remain S23 obligations).
        settings.allowsCellularAccess = false
        session = URLSession(configuration: settings, delegate: self, delegateQueue: .main)
    }

    func read(_ command: RetrieveMediaCommand) async throws -> Data {
        guard command.identitiesMatch, let range = command.range,
              range.lowerBound < range.upperBound, range.upperBound - range.lowerBound <= 65_536,
              !closed else { throw BackendContractError.invalidValue }
        var request = URLRequest(url: binding.url)
        for (name, value) in try await binding.headers(command) { request.setValue(value, forHTTPHeaderField: name) }
        try Task.checkCancellation()
        guard !closed else { throw CancellationError() }
        request.httpMethod = "GET"
        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request)
                entries[task.taskIdentifier] = Entry(id: id, task: task, command: command, continuation: continuation)
                started += 1
                task.resume()
            }
        } onCancel: {
            Task { @MainActor in self.entries.values.first(where: { $0.id == id })?.task.cancel() }
        }
    }

    func close() async {
        if !closed { closed = true; session.invalidateAndCancel() }
        if invalidated { return }
        await withCheckedContinuation { invalidationWaiters.append($0) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        refusedRedirects += 1
        entries[task.taskIdentifier]?.error = BackendContractError.identityMismatch
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let entry = entries[dataTask.taskIdentifier] else { completionHandler(.cancel); return }
        do {
            guard let response = response as? HTTPURLResponse, response.url == binding.url,
                  response.statusCode == 206, entry.error == nil, let range = entry.command.range,
                  response.value(forHTTPHeaderField: "Content-Range") == "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(entry.command.distribution.rendition.deliveryContent.byteCount)",
                  response.value(forHTTPHeaderField: "Content-Length") == String(range.upperBound - range.lowerBound),
                  response.value(forHTTPHeaderField: "Content-Type")?.lowercased() == binding.contentType,
                  response.value(forHTTPHeaderField: "Content-Encoding") == nil
                    || response.value(forHTTPHeaderField: "Content-Encoding") == "identity"
            else { throw BackendContractError.identityMismatch }
            try binding.validateIdentity(response, entry.command)
            entry.validated = true
            completionHandler(.allow)
        } catch { entry.error = error; completionHandler(.cancel) }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let entry = entries[dataTask.taskIdentifier], let range = entry.command.range else { return }
        receivedBytes += UInt64(data.count)
        let expected = Int(range.upperBound - range.lowerBound)
        guard entry.validated, entry.error == nil, data.count <= expected - entry.bytes.count else {
            entry.error = BackendContractError.identityMismatch
            dataTask.cancel(); return
        }
        entry.bytes.append(data)
        peakBufferedPayloadBytes = max(peakBufferedPayloadBytes, bufferedPayloadBytes)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let entry = entries.removeValue(forKey: task.taskIdentifier) else { return }
        completed += 1
        if let error = entry.error ?? error { entry.continuation.resume(throwing: error); return }
        guard entry.validated, let range = entry.command.range,
              UInt64(entry.bytes.count) == range.upperBound - range.lowerBound else {
            entry.continuation.resume(throwing: BackendContractError.identityMismatch); return
        }
        entry.continuation.resume(returning: entry.bytes)
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        invalidated = true
        let waiters = invalidationWaiters; invalidationWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    @MainActor private final class Entry {
        let id: UUID
        let task: URLSessionDataTask
        let command: RetrieveMediaCommand
        let continuation: CheckedContinuation<Data, Error>
        var bytes = Data()
        var validated = false
        var error: Error?
        init(id: UUID, task: URLSessionDataTask, command: RetrieveMediaCommand,
             continuation: CheckedContinuation<Data, Error>) {
            self.id = id; self.task = task; self.command = command; self.continuation = continuation
        }
    }
}
