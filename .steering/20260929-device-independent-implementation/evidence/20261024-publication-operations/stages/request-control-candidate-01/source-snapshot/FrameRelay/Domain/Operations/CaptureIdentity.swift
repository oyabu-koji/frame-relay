// Values cross adapter execution domains; they contain no SDK objects or I/O.
nonisolated struct CaptureSessionID: Hashable, Sendable, Codable {
    let rawValue: String
}

nonisolated struct CaptureID: Hashable, Sendable, Codable {
    let rawValue: String
}

nonisolated struct CaptureOperationID: Hashable, Sendable, Codable {
    let rawValue: String
}

nonisolated struct CaptureEvidenceID: Hashable, Sendable, Codable {
    let rawValue: String
}

nonisolated struct CaptureGeneration: Equatable, Hashable, Sendable, Codable {
    let session: CaptureSessionID
    let settings: UInt64
}

nonisolated struct CaptureContext: Equatable, Hashable, Sendable, Codable {
    let generation: CaptureGeneration
    let capture: CaptureID
}

/// The owner assigns a new ordinal for each command, within one capture.
/// A matching ID alone never makes a callback current: its stage must also match.
nonisolated struct CaptureCommandToken: Equatable, Hashable, Sendable, Codable {
    let context: CaptureContext
    let operation: CaptureOperationID
    let ordinal: UInt64
}

nonisolated enum CaptureContractError: Error, Equatable, Sendable, Codable {
    case invalidValue
    case wrongContext
    case duplicateOrOutOfOrder
    case wrongStage
    case evidenceMismatch
    case revisionConflict
}

/// A receipt means the persistent store committed, not that an in-memory child saved.
nonisolated struct RecordingCommitReceipt: Equatable, Sendable, Codable {
    let token: CaptureCommandToken
    let previousRevision: UInt64
    let committedRevision: UInt64

    func matches(_ expectedToken: CaptureCommandToken, revision: UInt64) -> Bool {
        let successor = revision.addingReportingOverflow(1)
        return !successor.overflow && token == expectedToken
            && previousRevision == revision && committedRevision == successor.partialValue
    }
}
