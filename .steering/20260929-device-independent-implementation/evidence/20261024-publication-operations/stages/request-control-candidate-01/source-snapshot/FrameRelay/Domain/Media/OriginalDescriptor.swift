nonisolated struct ContentIdentity: Hashable, Sendable, Codable {
    let byteCount: UInt64
    let algorithm: String
    let digest: String

    init(byteCount: UInt64, algorithm: String, digest: String) throws {
        guard byteCount > 0, !algorithm.isEmpty, !digest.isEmpty else {
            throw BackendContractError.invalidValue
        }
        self.byteCount = byteCount
        self.algorithm = algorithm
        self.digest = digest
    }
}

nonisolated struct OriginalContent: Hashable, Sendable, Codable {
    let capture: CaptureID
    let generation: ContentGeneration
    let content: ContentIdentity
}

nonisolated enum OriginalPresence: Equatable, Sendable { case present, absent, unknown }
nonisolated enum OriginalReadiness: Equatable, Sendable { case ready, inaccessible, recovering, writing }

/// T11 binds content identity to the capture store's existing committed save fact.
/// This value neither creates an original nor reclassifies capture's save result.
nonisolated struct OriginalDescriptor: Equatable, Sendable {
    let original: OriginalContent
    let reference: CaptureOriginalReference
    let saveResult: RecordingSaveResult
    let saveCommit: RecordingCommitReceipt?
    /// Identity from the capture save record, not reconstructed from this descriptor.
    let savedReference: CaptureOriginalReference
    let savedContext: CaptureContext
    let presence: OriginalPresence
    let readiness: OriginalReadiness

    var isTransferEligible: Bool {
        guard saveResult == .saved, presence == .present, readiness == .ready,
              let receipt = saveCommit, receipt.token.context == savedContext,
              savedContext.capture == original.capture, savedReference == reference else { return false }
        return receipt.matches(receipt.token, revision: receipt.previousRevision)
    }
}

nonisolated struct RenditionIdentity: Hashable, Sendable, Codable {
    let original: OriginalContent
    let inputLogIdentity: String
    let transformAssetIdentity: String
    let transformAssetVersion: String
    let outputConfigurationIdentity: String
    let conversionVersion: String
    let rendition: RenditionID
    let deliveryContent: ContentIdentity
    let publicationGeneration: PublicationGeneration
}

nonisolated enum MediaTarget: Hashable, Sendable, Codable {
    case original(OriginalContent)
    case rendition(RenditionIdentity)

    var original: OriginalContent {
        switch self {
        case .original(let original): original
        case .rendition(let rendition): rendition.original
        }
    }
}
