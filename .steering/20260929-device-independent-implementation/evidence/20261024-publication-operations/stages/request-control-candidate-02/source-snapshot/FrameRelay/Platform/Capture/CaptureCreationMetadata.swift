import AVFoundation
import Foundation

/// Both recording candidates receive the same independently observed calendar date.
/// A nil legacy/exploration date does not become the time of encoding or inspection.
nonisolated enum CaptureCreationMetadata {
    static func items(capturedAt: Date?) -> [AVMetadataItem] {
        guard let capturedAt, capturedAt.timeIntervalSince1970.isFinite else { return [] }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let item = AVMutableMetadataItem()
        item.identifier = .quickTimeMetadataCreationDate
        item.value = formatter.string(from: capturedAt) as NSString
        item.dataType = kCMMetadataBaseDataType_UTF8 as String
        return [item]
    }
}
