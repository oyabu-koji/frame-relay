/// These describe post-commit requests only. Actual SDK terminal, owner closure
/// and reader release remain the existing background journal's separate facts.
nonisolated enum MediaPersonControlStopDisposition: Equatable, Sendable {
    case notRequired, notRequested, requested, unknown
}
nonisolated struct MediaPersonControlStopResult: Equatable, Sendable {
    let child: MediaOperationID
    let disposition: MediaPersonControlStopDisposition
}
nonisolated enum MediaPersonControlResult: Equatable, Sendable {
    case recorded(StoredMediaPersonControlPlan, stops: [MediaPersonControlStopResult])
    case rejected(BackendContractError)
    case unknown
}
nonisolated protocol MediaRequestControlPort: Sendable {
    func submitPersonControl(_ plan: MediaPersonControlPlan) async -> MediaPersonControlResult
    /// Resolves only this exact plan's retained mutation or its durable record.
    /// A reopened record never authorizes automatic SDK redispatch.
    func lookupPersonControl(_ plan: MediaPersonControlPlan) async -> MediaPersonControlResult
}
