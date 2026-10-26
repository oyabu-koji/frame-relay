import Foundation

/// Range-by-range acquisition is also usable by a resumable transport owner.
/// This does not select S23's OS background scheduling or manufacture a receipt.
actor RenditionTemporaryRetrieval {
    private let temporary: any TemporaryMediaWritingPort
    init(temporary: any TemporaryMediaWritingPort) { self.temporary = temporary }

    func retrieve(reader: any RenditionByteReadingPort, usage: TemporaryMediaUsage) async throws -> TemporaryMediaReceipt {
        let result: Result<TemporaryMediaReceipt, Error>
        do {
            let state = try await temporary.stateFor(usage.media)
            var offset: UInt64 = 0
            let coverage = TemporaryMediaState.merged(state.ranges)
            while offset < state.rendition.deliveryContent.byteCount {
                try Task.checkCancellation()
                if let present = coverage.first(where: { $0.lowerBound <= offset && offset < $0.upperBound }) {
                    offset = present.upperBound; continue
                }
                let nextCovered = coverage.first(where: { $0.lowerBound > offset })?.lowerBound
                    ?? state.rendition.deliveryContent.byteCount
                let length = Int(min(65_536, nextCovered - offset))
                let data = try await reader.read(offset: offset, length: length)
                let range = try MediaByteRange(lowerBound: offset, upperBound: offset + UInt64(length))
                try await temporary.store(data, range: range, using: usage)
                offset = range.upperBound
            }
            result = .success(try await temporary.verify(usage))
        } catch { result = .failure(error) }
        _ = try await reader.close()
        return try result.get()
    }
}
