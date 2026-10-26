import AVFoundation
import Foundation
import UniformTypeIdentifiers

@MainActor final class RenditionResourceLoader: NSObject, @preconcurrency AVAssetResourceLoaderDelegate {
    private let resourceURL: URL
    private let byteCount: UInt64
    private let contentType: UTType
    private let reader: any RenditionByteReadingPort
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var requests: [ObjectIdentifier: AVAssetResourceLoadingRequest] = [:]
    private(set) var closed = false
    private(set) var deliveredBytes: UInt64 = 0
    private(set) var maximumReadLength = 0
    var pending: Int { tasks.count }

    init(resourceURL: URL, byteCount: UInt64, mimeType: String, reader: any RenditionByteReadingPort) throws {
        guard let type = UTType(mimeType: mimeType), type == .quickTimeMovie || type == .mpeg4Movie,
              byteCount > 0, byteCount <= UInt64(Int64.max) else { throw BackendContractError.invalidValue }
        self.resourceURL = resourceURL; self.byteCount = byteCount; contentType = type; self.reader = reader
    }

    func resourceLoader(_ loader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        guard request.request.url == resourceURL else { return false }
        guard !closed else { request.finishLoading(with: CancellationError()); return true }
        let id = ObjectIdentifier(request)
        requests[id] = request
        tasks[id] = Task { @MainActor in
            defer { tasks.removeValue(forKey: id); requests.removeValue(forKey: id) }
            do {
                if let info = request.contentInformationRequest {
                    if let allowed = info.allowedContentTypes, !allowed.isEmpty,
                       !allowed.contains(where: { UTType($0).map { contentType.conforms(to: $0) } ?? false }) {
                        throw BackendContractError.invalidValue
                    }
                    info.contentType = contentType.identifier
                    info.contentLength = Int64(byteCount); info.isByteRangeAccessSupported = true
                    info.isEntireLengthAvailableOnDemand = true
                }
                if let data = request.dataRequest {
                    guard data.requestedOffset >= 0, data.currentOffset >= 0, data.requestedLength >= 0 else {
                        throw BackendContractError.invalidValue
                    }
                    var offset = UInt64(max(data.currentOffset, data.requestedOffset))
                    let requestedEnd = UInt64(data.requestedOffset).addingReportingOverflow(UInt64(data.requestedLength))
                    guard !requestedEnd.overflow, offset <= byteCount else { throw BackendContractError.invalidValue }
                    let end = data.requestsAllDataToEndOfResource ? byteCount : min(byteCount, requestedEnd.partialValue)
                    while offset < end {
                        try Task.checkCancellation()
                        guard !closed, !request.isCancelled else { throw CancellationError() }
                        let length = Int(min(65_536, end - offset))
                        maximumReadLength = max(maximumReadLength, length)
                        let bytes = try await reader.read(offset: offset, length: length)
                        try Task.checkCancellation()
                        guard !closed, !request.isCancelled, bytes.count == length else { throw CancellationError() }
                        data.respond(with: bytes)
                        offset += UInt64(bytes.count); deliveredBytes += UInt64(bytes.count)
                    }
                }
                if !request.isCancelled, !request.isFinished { request.finishLoading() }
            } catch {
                if !request.isCancelled, !request.isFinished { request.finishLoading(with: error) }
            }
        }
        return true
    }
    func resourceLoader(_ loader: AVAssetResourceLoader, didCancel request: AVAssetResourceLoadingRequest) {
        tasks[ObjectIdentifier(request)]?.cancel()
    }
    func closeAdmission() {
        closed = true
        for task in tasks.values { task.cancel() }
        for request in requests.values where !request.isCancelled && !request.isFinished {
            request.finishLoading(with: CancellationError())
        }
    }
    func drain() async {
        closeAdmission()
        for task in Array(tasks.values) { await task.value }
    }
}
