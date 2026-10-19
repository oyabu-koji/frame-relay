import Foundation

/// Metadata in the common recording writer. The leaf is allocated locally,
/// never copied from a server filename or treated as evidence of file contents.
nonisolated struct TemporaryMediaState: Equatable, Sendable, Codable {
    let id: TemporaryMediaID
    let rendition: RenditionIdentity
    let registration: RegistrationIdentity
    let capturedAt: Date
    let leaf: String
    let contentType: String
    let directoryIdentity: TemporaryFileIdentity
    var fileIdentity: TemporaryFileIdentity?
    var ranges: [MediaByteRange] = []
    var verifiedContent: ContentIdentity?
    var usages: [TemporaryMediaUseRecord] = []
    var releasedUsages: [TemporaryMediaUseRecord] = []
    var reclaiming = false
    var reclaimed = false

    var coveredByteCount: UInt64 {
        Self.merged(ranges).reduce(0) { $0 + $1.upperBound - $1.lowerBound }
    }
    var complete: Bool {
        let merged = Self.merged(ranges)
        return merged.count == 1 && merged[0].lowerBound == 0
            && merged[0].upperBound == rendition.deliveryContent.byteCount
    }
    func receipt(for usage: TemporaryMediaUsage) -> TemporaryMediaReceipt {
        .init(id: id, rendition: rendition, capturedAt: capturedAt, ranges: ranges,
              verifiedContent: verifiedContent, usage: usage,
              isReleased: reclaiming || reclaimed || !usages.contains(where: { $0.usage == usage }))
    }
    static func merged(_ ranges: [MediaByteRange]) -> [MediaByteRange] {
        var result: [MediaByteRange] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = result.last, range.lowerBound <= last.upperBound {
                result[result.count - 1] = MediaByteRange(uncheckedLower: last.lowerBound,
                    upper: max(last.upperBound, range.upperBound))
            } else { result.append(range) }
        }
        return result
    }
}

private extension MediaByteRange {
    nonisolated init(uncheckedLower: UInt64, upper: UInt64) {
        lowerBound = uncheckedLower; upperBound = upper
    }
}

nonisolated struct TemporaryMediaUseRecord: Equatable, Sendable, Codable {
    let usage: TemporaryMediaUsage
    let lease: MediaReadLease
    let owner: String
}

/// Filesystem identity only. Size/hash verification is an independent step.
nonisolated struct TemporaryFileIdentity: Equatable, Sendable, Codable {
    let device: Int64
    let inode: UInt64
}

nonisolated enum TemporaryMediaChange: Equatable, Sendable, Codable {
    case create(TemporaryMediaState)
    case fileCreated(TemporaryMediaID, TemporaryFileIdentity)
    case stored(TemporaryMediaID, MediaByteRange)
    case verified(TemporaryMediaID, ContentIdentity)
    case acquire(TemporaryMediaID, TemporaryMediaUseRecord)
    /// The adapter closes every file/SDK consumer before committing this event.
    case release(TemporaryMediaID, TemporaryMediaUseRecord)
    case reclaim(TemporaryMediaID)
    /// An absent file after the recorded reclaim intent is an idempotent result.
    case reclaimed(TemporaryMediaID)

    var id: TemporaryMediaID {
        switch self {
        case .create(let value): value.id
        case .fileCreated(let id, _), .stored(let id, _), .verified(let id, _), .acquire(let id, _), .release(let id, _),
             .reclaim(let id), .reclaimed(let id): id
        }
    }
}
