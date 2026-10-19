/// Both read contracts belong to the same writer. No Library database or recovery writes.
actor LibraryStoreReader: LibraryReadPort {
    private let store: any RecordingStorePort & OriginalStorePort
    private let files: any RecordingOriginalFilePort

    init(store: any RecordingStorePort & OriginalStorePort, files: any RecordingOriginalFilePort) {
        self.store = store
        self.files = files
    }

    func loadLibrary() async -> LibraryLoadResult {
        // Bound retries prevent a busy capture writer from indefinitely blocking the UI.
        for _ in 0..<3 {
            let recordings = await store.loadRecordings()
            guard case .loaded(let saved) = recordings else { return .unavailable(failure(recordings)) }
            let originalResult = await store.loadOriginalState()
            guard case .succeeded(let originals) = originalResult else {
                switch originalResult {
                case .failed(.unknownSchema): return .unavailable(.unknownSchema)
                case .failed(.corruptStore): return .unavailable(.corruptStore)
                case .failed(.contentMismatch): return .unavailable(.identityMismatch)
                default: return .unavailable(.inaccessible)
                }
            }
            guard saved.revision == originals.revision else { continue }
            guard Set(saved.recordings.map { $0.intent.context.capture }).count == saved.recordings.count,
                  Set(originals.originals.map { $0.binding.original.capture }).count == originals.originals.count else {
                return .unavailable(.identityMismatch)
            }
            var items: [LibraryItem] = []
            for recording in saved.recordings {
                let state = originals.originals.first { $0.binding.original.capture == recording.intent.context.capture }
                let file = await files.observeFile(recording.intent.original)
                items.append(LibraryProjection.item(recording, file: file, state: state))
            }
            // A deletion or capture commit during the file scan invalidates this mixed snapshot.
            let after = await store.loadRecordings()
            guard case .loaded(let latest) = after else { return .unavailable(failure(after)) }
            guard latest.revision == saved.revision else { continue }
            return .loaded(.init(revision: saved.revision, items: items.sorted { $0.id.rawValue < $1.id.rawValue }))
        }
        return .unavailable(.changing)
    }

    private func failure(_ result: RecordingStoreLoadResult) -> LibraryReadFailure {
        switch result {
        case .unrecognizedSchema: .unknownSchema
        case .corruptStore: .corruptStore
        default: .inaccessible
        }
    }
}
