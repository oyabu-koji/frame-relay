nonisolated enum OriginalUploadAcceptanceResult: Equatable, Sendable {
    case recorded(StoredOriginalUploadAcceptance)
    case rejected(BackendContractError)
    case unknown
}

/// A consumer fixes the whole request before its first await. Its implementation
/// observes stat only and commits one plan; uncertain commits retain the exact
/// original mutation/revision for lookup rather than restatting or rebasing.
nonisolated protocol OriginalUploadAcceptancePort: Sendable {
    func accept(_ request: OriginalUploadAcceptanceRequest) async -> OriginalUploadAcceptanceResult
    func lookupAcceptance(_ request: OriginalUploadAcceptanceRequest) async -> OriginalUploadAcceptanceResult
}

/// Initial native default-route observation only, never a strict media permit.
nonisolated protocol OriginalUploadStartNetworkPort: Sendable {
    func currentCondition() -> NetworkCondition
}
