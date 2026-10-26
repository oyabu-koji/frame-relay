import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// SDK requests stay on the delegate's main queue. Only Sendable offsets/Data
/// cross to the original actor; no SDK object or file URL crosses that boundary.
@MainActor final class OriginalResourceLoader: NSObject, @preconcurrency AVAssetResourceLoaderDelegate {
    typealias Read = @Sendable (UInt64, Int) async throws -> Data
    private let resourceURL: URL
    private let byteCount: UInt64
    private let read: Read
    private let diagnostics: OriginalPlaybackDiagnostics?
    private var observed = OriginalLoaderDiagnostic()
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var requests: [ObjectIdentifier: AVAssetResourceLoadingRequest] = [:]
    private(set) var isClosed = false
    private(set) var deliveredBytes: UInt64 = 0
    private(set) var maximumReadLength = 0
    var pendingCount: Int { tasks.count }
    var diagnosticSnapshot: OriginalLoaderDiagnostic {
        var value = observed
        value.pending = tasks.count
        value.bytes = deliveredBytes
        value.maximumRead = maximumReadLength
        return value
    }

    init(resourceURL: URL, byteCount: UInt64, diagnostics: OriginalPlaybackDiagnostics? = nil,
         read: @escaping Read) {
        self.resourceURL = resourceURL; self.byteCount = byteCount; self.read = read
        self.diagnostics = diagnostics
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        observed.requests += 1
        diagnostics?.record(.loaderRequest, loader: diagnosticSnapshot)
        guard request.request.url == resourceURL else {
            observed.rejected += 1
            diagnostics?.record(.loaderRejected, loader: diagnosticSnapshot)
            return false
        }
        guard !isClosed, byteCount <= UInt64(Int64.max) else {
            observed.rejected += 1
            request.finishLoading(with: CancellationError())
            observed.finishes += 1; observed.errorFinishes += 1
            diagnostics?.record(.loaderRejected, loader: diagnosticSnapshot)
            return true
        }
        let id = ObjectIdentifier(request)
        requests[id] = request
        tasks[id] = Task { @MainActor in
            defer {
                tasks.removeValue(forKey: id); requests.removeValue(forKey: id)
                diagnostics?.record(.loaderTaskEnded, loader: diagnosticSnapshot)
            }
            do {
                guard !isClosed, !request.isCancelled else { throw CancellationError() }
                if let information = request.contentInformationRequest {
                    let contentType = UTType.quickTimeMovie.identifier
                    if let allowed = information.allowedContentTypes, !allowed.isEmpty,
                       !allowed.contains(where: { UTType($0).map { UTType.quickTimeMovie.conforms(to: $0) } ?? false }) {
                        throw BackendContractError.invalidValue
                    }
                    information.contentType = contentType
                    information.contentLength = Int64(byteCount)
                    information.isByteRangeAccessSupported = true
                    information.isEntireLengthAvailableOnDemand = true
                }
                if let data = request.dataRequest {
                    guard data.requestedOffset >= 0, data.currentOffset >= 0, data.requestedLength >= 0 else {
                        throw BackendContractError.invalidValue
                    }
                    var offset = UInt64(max(data.currentOffset, data.requestedOffset))
                    let end: UInt64
                    if data.requestsAllDataToEndOfResource { end = byteCount }
                    else {
                        let limit = UInt64(data.requestedOffset).addingReportingOverflow(UInt64(data.requestedLength))
                        guard !limit.overflow else { throw BackendContractError.invalidValue }
                        end = min(byteCount, limit.partialValue)
                    }
                    guard offset <= byteCount else { throw BackendContractError.invalidValue }
                    while offset < end {
                        try Task.checkCancellation()
                        guard !isClosed, !request.isCancelled else { throw CancellationError() }
                        let length = Int(min(65_536, end - offset))
                        maximumReadLength = max(maximumReadLength, length)
                        observed.reads += 1
                        diagnostics?.record(.loaderReadBegin, loader: diagnosticSnapshot)
                        let bytes: Data
                        do {
                            bytes = try await read(offset, length)
                            observed.readReturns += 1
                            diagnostics?.record(.loaderReadEnd, loader: diagnosticSnapshot)
                        } catch {
                            observed.readFailures += 1
                            diagnostics?.record(.loaderReadFailed, loader: diagnosticSnapshot, error: error)
                            throw error
                        }
                        // Cancellation can happen during an actual read that ignores Task cancellation.
                        try Task.checkCancellation()
                        guard !isClosed, !request.isCancelled else { throw CancellationError() }
                        guard !bytes.isEmpty, bytes.count <= length else { throw BackendContractError.unavailable }
                        data.respond(with: bytes)
                        offset += UInt64(bytes.count)
                        deliveredBytes += UInt64(bytes.count)
                    }
                }
                if !request.isCancelled, !request.isFinished {
                    request.finishLoading()
                    observed.finishes += 1
                    diagnostics?.record(.loaderFinished, loader: diagnosticSnapshot)
                }
            } catch {
                if !request.isCancelled, !request.isFinished {
                    request.finishLoading(with: error)
                    observed.finishes += 1; observed.errorFinishes += 1
                    diagnostics?.record(.loaderFinished, loader: diagnosticSnapshot, error: error)
                }
            }
        }
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel request: AVAssetResourceLoadingRequest) {
        observed.cancellations += 1
        diagnostics?.record(.loaderCancelled, loader: diagnosticSnapshot)
        // Keep the task tracked until its underlying await actually returns.
        tasks[ObjectIdentifier(request)]?.cancel()
    }

    func closeAdmission() {
        isClosed = true
        observed.closeCalls += 1
        for task in tasks.values { task.cancel() }
        for request in requests.values where !request.isCancelled && !request.isFinished {
            request.finishLoading(with: CancellationError())
            observed.finishes += 1; observed.errorFinishes += 1
        }
        diagnostics?.record(.loaderClosed, loader: diagnosticSnapshot)
    }

    func drain() async {
        closeAdmission()
        let outstanding = Array(tasks.values)
        for task in outstanding { await task.value }
        // A closed delegate remains attached until the asset is dropped. Any late
        // SDK callback is rejected above and cannot acquire another original read.
    }
}

nonisolated struct OriginalLoaderDiagnostic: Codable, Sendable {
    var requests = 0
    var rejected = 0
    var reads = 0
    var readReturns = 0
    var readFailures = 0
    var cancellations = 0
    var finishes = 0
    var errorFinishes = 0
    var closeCalls = 0
    var pending = 0
    var bytes: UInt64 = 0
    var maximumRead = 0
}
