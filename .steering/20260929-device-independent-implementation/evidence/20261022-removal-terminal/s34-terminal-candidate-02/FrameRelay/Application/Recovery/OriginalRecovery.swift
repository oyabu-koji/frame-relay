nonisolated struct RecoveredOriginal: Equatable, Sendable {
    let recording: RecordingStoreEntry
    let file: OriginalFileObservation

    /// Historical save classification and current availability are separate facts.
    /// Equal byte counts do not prove content identity; S13 supplies that binding.
    var requiresReconciliation: Bool {
        guard let result = recording.result else { return true }
        if case .unknown = result.result { return true }
        guard case .present(let byteCount) = file, byteCount == result.file.byteCount else { return true }
        return false
    }
}

nonisolated enum OriginalRecoveryResult: Equatable, Sendable {
    case loaded(revision: UInt64, originals: [RecoveredOriginal])
    case storeUnavailable(RecordingStoreLoadResult)
}

/// Read-only startup reconciliation. It neither changes the saved classification
/// nor executes unfinished capture, Photos, transfer, or removal operations.
actor OriginalRecovery {
    private let store: any RecordingStorePort
    private let originals: any RecordingOriginalFilePort

    init(store: any RecordingStorePort, originals: any RecordingOriginalFilePort) {
        self.store = store; self.originals = originals
    }

    func reconcile() async -> OriginalRecoveryResult {
        let result = await store.loadRecordings()
        guard case .loaded(let snapshot) = result else { return .storeUnavailable(result) }
        var recovered: [RecoveredOriginal] = []
        for recording in snapshot.recordings {
            let observation = await originals.observeFile(recording.intent.original)
            recovered.append(.init(recording: recording, file: observation))
        }
        return .loaded(revision: snapshot.revision, originals: recovered)
    }
}
