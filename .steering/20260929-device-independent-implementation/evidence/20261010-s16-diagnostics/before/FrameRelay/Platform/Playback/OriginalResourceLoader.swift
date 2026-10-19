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
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var requests: [ObjectIdentifier: AVAssetResourceLoadingRequest] = [:]
    private(set) var isClosed = false
    private(set) var deliveredBytes: UInt64 = 0
    private(set) var maximumReadLength = 0
    var pendingCount: Int { tasks.count }

    init(resourceURL: URL, byteCount: UInt64, read: @escaping Read) {
        self.resourceURL = resourceURL; self.byteCount = byteCount; self.read = read
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        guard request.request.url == resourceURL else { return false }
        guard !isClosed, byteCount <= UInt64(Int64.max) else {
            request.finishLoading(with: CancellationError())
            return true
        }
        let id = ObjectIdentifier(request)
        requests[id] = request
        tasks[id] = Task { @MainActor in
            defer { tasks.removeValue(forKey: id); requests.removeValue(forKey: id) }
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
                        let bytes = try await read(offset, length)
                        // Cancellation can happen during an actual read that ignores Task cancellation.
                        try Task.checkCancellation()
                        guard !isClosed, !request.isCancelled else { throw CancellationError() }
                        guard !bytes.isEmpty, bytes.count <= length else { throw BackendContractError.unavailable }
                        data.respond(with: bytes)
                        offset += UInt64(bytes.count)
                        deliveredBytes += UInt64(bytes.count)
                    }
                }
                if !request.isCancelled, !request.isFinished { request.finishLoading() }
            } catch {
                if !request.isCancelled, !request.isFinished { request.finishLoading(with: error) }
            }
        }
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel request: AVAssetResourceLoadingRequest) {
        // Keep the task tracked until its underlying await actually returns.
        tasks[ObjectIdentifier(request)]?.cancel()
    }

    func closeAdmission() {
        isClosed = true
        for task in tasks.values { task.cancel() }
        for request in requests.values where !request.isCancelled && !request.isFinished {
            request.finishLoading(with: CancellationError())
        }
    }

    func drain() async {
        closeAdmission()
        let outstanding = Array(tasks.values)
        for task in outstanding { await task.value }
        // A closed delegate remains attached until the asset is dropped. Any late
        // SDK callback is rejected above and cannot acquire another original read.
    }
}
