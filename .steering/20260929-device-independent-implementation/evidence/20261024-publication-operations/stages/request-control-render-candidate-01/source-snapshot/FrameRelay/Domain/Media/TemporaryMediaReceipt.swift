import Foundation

nonisolated struct MediaByteRange: Hashable, Sendable, Codable {
    let lowerBound: UInt64
    let upperBound: UInt64

    init(lowerBound: UInt64, upperBound: UInt64) throws {
        guard lowerBound < upperBound else { throw BackendContractError.invalidValue }
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }

    private enum CodingKeys: String, CodingKey { case lowerBound, upperBound }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(lowerBound: values.decode(UInt64.self, forKey: .lowerBound),
                      upperBound: values.decode(UInt64.self, forKey: .upperBound))
    }
}

nonisolated enum TemporaryMediaPurpose: Equatable, Sendable, Codable { case playback, photoHandoff }

nonisolated struct TemporaryMediaUsage: Equatable, Sendable, Codable {
    let id: MediaUsageID
    let purpose: TemporaryMediaPurpose
    let media: TemporaryMediaID
    var epoch: ReaderReconciliationEpoch? = nil
}

nonisolated struct TemporaryMediaReceipt: Equatable, Sendable {
    let id: TemporaryMediaID
    let rendition: RenditionIdentity
    let capturedAt: Date
    let ranges: [MediaByteRange]
    let verifiedContent: ContentIdentity?
    let usage: TemporaryMediaUsage
    let isReleased: Bool

    var hasCompleteCoverage: Bool {
        var end: UInt64 = 0
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            guard range.lowerBound <= end, range.upperBound <= rendition.deliveryContent.byteCount else { return false }
            end = max(end, range.upperBound)
        }
        return end == rendition.deliveryContent.byteCount
    }

    func photoHandoff(expected: RenditionIdentity) throws -> PhotoMediaHandoff {
        guard rendition == expected, hasCompleteCoverage, verifiedContent == rendition.deliveryContent,
              usage.media == id, usage.purpose == .photoHandoff, !isReleased else {
            throw BackendContractError.ineligibleOriginal
        }
        return PhotoMediaHandoff(media: id, rendition: rendition, capturedAt: capturedAt, usage: usage)
    }
}

/// This grants use of complete media only; it is not a Photos registration receipt.
nonisolated struct PhotoMediaHandoff: Equatable, Sendable {
    let media: TemporaryMediaID
    let rendition: RenditionIdentity
    let capturedAt: Date
    let usage: TemporaryMediaUsage
}
