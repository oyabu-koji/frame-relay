/// An app-managed identifier, never an arbitrary file URL or a deletion authority.
nonisolated struct CaptureOriginalReference: Equatable, Hashable, Sendable, Codable {
    let rawValue: String
}

nonisolated struct RecordingIntent: Equatable, Sendable, Codable {
    let context: CaptureContext
    let operation: CaptureOperationID
    let original: CaptureOriginalReference
    let trialReference: String
    let desired: DesiredCaptureSettings
    let applied: AppliedCaptureSettings
    let acceptedAt: CaptureTimeObservation
}

nonisolated enum CaptureWriterTermination: Equatable, Sendable, Codable {
    case completed
    case interrupted(CaptureUnavailableReason)
    case failed(CaptureUnavailableReason)
    case notStarted
}

/// The adapter emits this only after no more frames can be recorded.
/// "first buffer" is not substituted for first video or first audio PTS.
nonisolated struct RecordingEndEvidence: Equatable, Sendable, Codable {
    let writer: CaptureWriterTermination
    let ceasedAt: CaptureTimeObservation
    let lastVideo: CaptureTimeObservation
    let lastAudio: CaptureTimeObservation
}

nonisolated struct CaptureFileEvidence: Equatable, Sendable, Codable {
    let context: CaptureContext
    let original: CaptureOriginalReference
    let byteCount: UInt64
    let finalizedAt: CaptureTimeObservation
}

nonisolated enum CaptureTrackInspection: Equatable, Sendable, Codable {
    case verified(CaptureSampleSpan)
    case missing
    case unavailable(CaptureUnavailableReason)

    var hasSamples: Bool {
        if case .verified(let span) = self { return span.count > 0 }
        return false
    }

    var isUnknown: Bool {
        if case .unavailable = self { return true }
        return false
    }
}

nonisolated enum CaptureInspectionCheck: Equatable, Sendable, Codable {
    case verified
    case failed(CaptureUnavailableReason)
    case unavailable(CaptureUnavailableReason)
}

nonisolated enum CaptureMediaCompleteness: Equatable, Sendable, Codable {
    case complete
    case partial(CaptureUnavailableReason)
    case unknown(CaptureUnavailableReason)
}

/// File-readable format only. Camera identity and stabilization belong to the
/// intent/application trace and must not be fabricated as inspected metadata.
nonisolated struct RecordedMediaFormat: Equatable, Sendable, Codable {
    let width: Int
    let height: Int
    let nominalFramesPerSecond: Double
    let codec: CaptureCodec
    let logEncoding: CaptureLogEncoding

    func matches(_ configuration: CaptureConfiguration) -> Bool {
        width == configuration.width && height == configuration.height
            && nominalFramesPerSecond == Double(configuration.framesPerSecond)
            && codec == configuration.codec && logEncoding == configuration.logEncoding
    }
}

nonisolated struct CaptureMediaInspection: Equatable, Sendable, Codable {
    let context: CaptureContext
    let original: CaptureOriginalReference
    let video: CaptureTrackInspection
    let audio: CaptureTrackInspection
    let format: CaptureObservation<RecordedMediaFormat>
    let playback: CaptureInspectionCheck
    let completeness: CaptureMediaCompleteness
}

nonisolated enum RecordingSaveResult: Equatable, Sendable, Codable {
    case saved
    case partial(CaptureUnavailableReason)
    case unknown(CaptureUnavailableReason)
    case failed(CaptureUnavailableReason)
}

/// A technical file result only; no quality or PRD acceptance is encoded here.
nonisolated struct RecordingResultRecord: Equatable, Sendable, Codable {
    let intent: RecordingIntent
    let end: RecordingEndEvidence
    let file: CaptureFileEvidence
    let inspection: CaptureMediaInspection
    let result: RecordingSaveResult
}
