import CryptoKit
import Foundation

/// S20 test-only wire observations. These values never create a product receipt.
nonisolated struct LegacyProbeConfiguration: Sendable {
    let url: URL
    let resultID: String
    let sha256: String
    let byteCount: UInt64
    let prefixSHA256: String
    let token: String

    init(environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        guard environment["FR_LEGACY_PLAYBACK_PROBE"] == "1" else {
            throw LegacyProbeError.invalidConfiguration("opt-in")
        }
        func required(_ key: String) throws -> String {
            guard let value = environment[key], !value.isEmpty else {
                throw LegacyProbeError.invalidConfiguration(key)
            }
            return value
        }
        resultID = try required("FR_LEGACY_PROBE_RESULT_ID")
        sha256 = try required("FR_LEGACY_PROBE_SHA256")
        prefixSHA256 = try required("FR_LEGACY_PROBE_PREFIX_SHA256")
        let rawURL = try required("FR_LEGACY_PROBE_URL")
        guard let parts = URLComponents(string: rawURL), parts.scheme == "http",
              parts.host == "127.0.0.1", let port = parts.port, (1...65_535).contains(port),
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              let url = parts.url, url.absoluteString == rawURL else {
            throw LegacyProbeError.invalidConfiguration("IPv4 loopback HTTP URL")
        }
        let components = parts.path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 5, components[0].isEmpty, components[1] == "assets",
              let assetID = UInt64(components[2]), assetID > 0,
              components[3] == "results", components[4] == Substring(resultID),
              !resultID.isEmpty, resultID.count <= 128,
              resultID.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0)
                  || (97...122).contains($0) || $0 == 45 || $0 == 95 }),
              Self.isDigest(sha256), Self.isDigest(prefixSHA256),
              let count = UInt64(try required("FR_LEGACY_PROBE_BYTE_COUNT")),
              (64...8_388_608).contains(count) else {
            throw LegacyProbeError.invalidConfiguration("fixed result identity / test media size")
        }
        self.url = url
        byteCount = count
        token = try required("FR_LEGACY_PROBE_TOKEN")
        guard token.count <= 4_096, token.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw LegacyProbeError.invalidConfiguration("Bearer token shape")
        }
    }

    private static func isDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    var publicIdentity: [String: String] {
        ["url": url.absoluteString, "resultID": resultID, "sha256": sha256,
         "byteCount": String(byteCount), "prefix64SHA256": prefixSHA256]
    }
}

nonisolated enum LegacyProbeError: Error {
    case invalidConfiguration(String)
    case rejected(String)
    case transport(domain: String, code: Int)
    case timeout(String)
}

/// Never serialize NSError.userInfo, requests, environment, or an error's description.
nonisolated func legacyProbeErrorCode(_ error: Error) -> String {
    if let error = error as? LegacyProbeError { return String(describing: error) }
    let value = error as NSError
    return "\(value.domain):\(value.code)"
}

nonisolated func legacyProbeSHA256(_ bytes: Data) -> String {
    SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
}

nonisolated struct LegacyProbeHTTPObservation: Codable, Equatable, Sendable {
    let offset: UInt64
    let requestedLength: Int
    let authenticated: Bool
    var status: Int?
    var identityHeadersMatched = false
    var bodyBytes = 0
    var terminal = false
    var errorCode: String?
}

nonisolated struct LegacyProbeNetworkSnapshot: Codable, Equatable, Sendable {
    let startedTasks: Int
    let completedTasks: Int
    let activeTasks: Int
    let receivedBytes: UInt64
    let maximumRequestLength: Int
    let admissionClosed: Bool
    let invalidationRequested: Bool
    let invalidationCallback: Bool
    let invalidationError: String?
    let refusedRedirects: Int
    let observations: [LegacyProbeHTTPObservation]
}

/// Main-queue delegate callbacks and all state share the MainActor. The session
/// performs network I/O; no unchecked mutable state crosses the actor boundary.
@MainActor final class LegacyProbeRangeClient: NSObject, @preconcurrency URLSessionDataDelegate {
    private let configuration: LegacyProbeConfiguration
    private var session: URLSession!
    private var entries: [Int: Entry] = [:]
    private var observations: [LegacyProbeHTTPObservation] = []
    private var closed = false
    private var invalidating = false
    private var invalidated = false
    private var invalidationError: String?
    private var receivedBytes: UInt64 = 0
    private var refusedRedirects = 0

    init(configuration: LegacyProbeConfiguration) {
        self.configuration = configuration
        super.init()
        let settings = URLSessionConfiguration.ephemeral
        settings.urlCache = nil
        settings.urlCredentialStorage = nil
        settings.httpCookieStorage = nil
        settings.httpShouldSetCookies = false
        settings.requestCachePolicy = .reloadIgnoringLocalCacheData
        settings.connectionProxyDictionary = [:]
        // Probe bounds only, not accepted product latency / throughput values.
        settings.timeoutIntervalForRequest = 10
        settings.timeoutIntervalForResource = 20
        session = URLSession(configuration: settings, delegate: self, delegateQueue: .main)
    }

    func read(offset: UInt64, length: Int, authenticated: Bool = true) async throws -> Data {
        try Task.checkCancellation()
        guard !closed, length > 0, length <= 65_536, offset < configuration.byteCount,
              UInt64(length) <= configuration.byteCount - offset else {
            throw LegacyProbeError.rejected("closed or invalid bounded range")
        }
        // Finite technical-probe budgets, not production policy.
        guard observations.count < 512, entries.count < 8, receivedBytes < 8_388_608 else {
            throw LegacyProbeError.rejected("probe request / concurrency / byte budget")
        }
        let id = UUID()
        var request = URLRequest(url: configuration.url)
        request.httpMethod = "GET"
        request.setValue("bytes=\(offset)-\(offset + UInt64(length) - 1)", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if authenticated { request.setValue("Bearer " + configuration.token, forHTTPHeaderField: "Authorization") }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request)
                let index = observations.count
                observations.append(.init(offset: offset, requestedLength: length, authenticated: authenticated))
                entries[task.taskIdentifier] = Entry(id: id, task: task, index: index, continuation: continuation)
                task.resume()
            }
        } onCancel: {
            Task { @MainActor in self.entries.values.first(where: { $0.id == id })?.task.cancel() }
        }
    }

    var snapshot: LegacyProbeNetworkSnapshot {
        .init(startedTasks: observations.count, completedTasks: observations.filter(\.terminal).count,
              activeTasks: entries.count, receivedBytes: receivedBytes,
              maximumRequestLength: observations.map(\.requestedLength).max() ?? 0,
              admissionClosed: closed, invalidationRequested: invalidating,
              invalidationCallback: invalidated, invalidationError: invalidationError,
              refusedRedirects: refusedRedirects, observations: observations)
    }

    func invalidateAndCancel() {
        closed = true
        guard !invalidating else { return }
        invalidating = true
        session.invalidateAndCancel()
    }

    func stopAndObserveTerminal() async -> Bool {
        invalidateAndCancel()
        return await legacyProbeEventually(seconds: 5) { self.invalidated && self.entries.isEmpty }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        refusedRedirects += 1
        entries[task.taskIdentifier]?.failure = .rejected("redirect")
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let entry = entries[dataTask.taskIdentifier], let response = response as? HTTPURLResponse else {
            completionHandler(.cancel); return
        }
        let observation = observations[entry.index]
        observations[entry.index].status = response.statusCode
        guard response.url == configuration.url, entry.failure == nil else {
            entry.failure = .rejected("response endpoint / redirect")
            completionHandler(.cancel); return
        }
        if !observation.authenticated {
            guard response.statusCode == 401 else {
                entry.failure = .rejected("missing Bearer token was not rejected with 401")
                completionHandler(.cancel); return
            }
            // Header observation is sufficient for 401. Discard its body, but wait
            // for didCompleteWithError before returning the observation.
            entry.observedUnauthorized = true
            completionHandler(.cancel); return
        }
        let end = observation.offset + UInt64(observation.requestedLength) - 1
        let expected = [
            "Content-Range": "bytes \(observation.offset)-\(end)/\(configuration.byteCount)",
            "Content-Length": String(observation.requestedLength), "Accept-Ranges": "bytes",
            "ETag": "\"\(configuration.sha256)\"", "X-Processed-Result-Id": configuration.resultID,
            "X-Processed-Result-SHA256": configuration.sha256,
            "X-Processed-Result-Size": String(configuration.byteCount)
        ]
        let encoding = response.value(forHTTPHeaderField: "Content-Encoding")
        guard response.statusCode == 206,
              expected.allSatisfy({ response.value(forHTTPHeaderField: $0.key) == $0.value }),
              encoding == nil || encoding == "identity" else {
            entry.failure = .rejected("206 / fixed identity / exact range headers")
            completionHandler(.cancel); return
        }
        observations[entry.index].identityHeadersMatched = true
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let entry = entries[dataTask.taskIdentifier] else { return }
        receivedBytes += UInt64(data.count)
        let expected = observations[entry.index].requestedLength
        guard entry.failure == nil, observations[entry.index].identityHeadersMatched,
              data.count <= expected - entry.bytes.count, receivedBytes <= 8_388_608 else {
            entry.failure = .rejected("unverified or oversized body / probe byte budget")
            dataTask.cancel(); return
        }
        entry.bytes.append(data)
        observations[entry.index].bodyBytes = entry.bytes.count
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let entry = entries.removeValue(forKey: task.taskIdentifier) else { return }
        observations[entry.index].terminal = true
        observations[entry.index].errorCode = error.map(legacyProbeErrorCode)
        if let failure = entry.failure {
            observations[entry.index].errorCode = legacyProbeErrorCode(failure)
            entry.continuation.resume(throwing: failure); return
        }
        if entry.observedUnauthorized {
            entry.continuation.resume(returning: Data()); return
        }
        if let error {
            let value = error as NSError
            entry.continuation.resume(throwing: LegacyProbeError.transport(domain: value.domain, code: value.code))
            return
        }
        guard observations[entry.index].identityHeadersMatched,
              entry.bytes.count == observations[entry.index].requestedLength else {
            entry.continuation.resume(throwing: LegacyProbeError.rejected("incomplete range body")); return
        }
        entry.continuation.resume(returning: entry.bytes)
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        invalidated = true
        invalidationError = error.map(legacyProbeErrorCode)
    }

    @MainActor private final class Entry {
        let id: UUID
        let task: URLSessionDataTask
        let index: Int
        let continuation: CheckedContinuation<Data, Error>
        var bytes = Data()
        var failure: LegacyProbeError?
        var observedUnauthorized = false

        init(id: UUID, task: URLSessionDataTask, index: Int, continuation: CheckedContinuation<Data, Error>) {
            self.id = id; self.task = task; self.index = index; self.continuation = continuation
        }
    }
}

@MainActor func legacyProbeEventually(seconds: Double, condition: @MainActor () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
    while !condition() {
        if ContinuousClock.now >= deadline || Task.isCancelled { return false }
        do { try await Task.sleep(for: .milliseconds(20)) } catch { return false }
    }
    return true
}

/// A separate file per phase preserves pre-stop timeout diagnostics and terminal
/// observations even when Swift Testing stdout is absent from an xcresult.
@MainActor final class LegacyProbeEvidence {
    let directory: URL
    private let identity: [String: String]
    private var ordinal = 0

    init(configuration: LegacyProbeConfiguration, name: String) throws {
        identity = configuration.publicIdentity
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "fr-s20-legacy-probe-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        print("S20_LEGACY_PROBE_EVIDENCE " + directory.path)
    }

    func record(_ phase: String, client: LegacyProbeRangeClient,
                values: [String: String] = [:]) throws {
        ordinal += 1
        let value = Event(phase: phase, identity: identity, network: client.snapshot, values: values,
                          scope: "S20 technical probe only; no distribution, verification, or confirmation receipt")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(value).write(to: directory.appendingPathComponent("\(ordinal)-\(phase).json"),
                                        options: .withoutOverwriting)
    }

    nonisolated private struct Event: Codable {
        let phase: String
        let identity: [String: String]
        let network: LegacyProbeNetworkSnapshot
        let values: [String: String]
        let scope: String
    }
}
