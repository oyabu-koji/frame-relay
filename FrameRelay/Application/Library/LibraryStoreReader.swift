import Foundation

/// All read contracts belong to the same writer. No Library database or recovery writes.
actor LibraryStoreReader: LibraryReadPort {
    private let store: any RecordingStorePort & OriginalStorePort & MediaOperationStorePort
    private let files: any RecordingOriginalFilePort

    init(store: any RecordingStorePort & OriginalStorePort & MediaOperationStorePort,
         files: any RecordingOriginalFilePort) {
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
            let backendResult = await store.load()
            guard case .loaded(let backend) = backendResult else {
                switch backendResult {
                case .unavailable(.unknownSchema): return .unavailable(.unknownSchema)
                case .unavailable(.corruptStore): return .unavailable(.corruptStore)
                case .unavailable(.contentMismatch): return .unavailable(.identityMismatch)
                default: return .unavailable(.inaccessible)
                }
            }
            guard backend.revision == saved.revision else { continue }
            guard Set(saved.recordings.map { $0.intent.context.capture }).count == saved.recordings.count,
                  Set(saved.recordings.map { $0.intent.original }).count == saved.recordings.count,
                  Set(originals.originals.map { $0.binding.original.capture }).count == originals.originals.count else {
                return .unavailable(.identityMismatch)
            }
            let requests = LibraryMediaRequestProjection.rows(backend: backend, originals: originals)
            var items: [LibraryItem] = []
            for recording in saved.recordings {
                let state = originals.originals.first { $0.binding.original.capture == recording.intent.context.capture }
                let file = await files.observeFile(recording.intent.original)
                let photos = backend.photoRegistrations.filter {
                    $0.registration.intent.key.capture == recording.intent.context.capture
                }
                var item = LibraryProjection.item(recording, file: file, state: state, photoRegistrations: photos, backend: backend)
                item.uploadCandidateBinding = OriginalUploadAcceptanceBoundary.candidate(recording, state: state)
                item.originalUploadAcceptances = backend.originalUploadAcceptances.filter { record in
                    record.isCommitted && record.plan.request.targets.contains {
                        OriginalUploadAcceptanceValueValidation.exact($0.binding.original.capture, item.id)
                    }
                }
                if let original = item.original {
                    item.mediaRequests = LibraryMediaRequestProjection.matching(requests, original: original)
                }
                if let original = item.original,
                   (try? LocalRenditionSelection.select(backend: backend, originals: originals,
                    target: .init(original: original, destination: nil))) != nil {
                    item.localRenditionUnavailableReason = nil
                }
                if let original = item.original {
                    item.photoSaveSource = LibraryPhotoSaveProjection.source(backend: backend, originals: originals,
                        target: .init(original: original, destination: nil))
                    item.photoSaveUnavailableReason = LibraryPhotoSaveProjection.unavailable(item.photoSaveSource, backend: backend)
                    item.photoRegistrations = LibraryPhotoSaveProjection.registrations(backend.photoRegistrations,
                        original: original, destination: nil)
                }
                let operations = originals.removalBatches.flatMap { batch in
                    batch.targets.filter { $0.target.original.capture == item.id }.map { row in
                        LibraryRemovalOperation(batch: batch.batch.operation, purpose: batch.batch.purpose,
                            target: row.target, status: row.status, failure: row.failure)
                    }
                }
                item.removalOperations = operations
                item.operationResults = operations.map { operation in
                    let outcome: LibraryRecordedOutcome
                    switch operation.status {
                    case .unprocessed: outcome = .notProcessed
                    case .reserved: outcome = .unknown
                    case .notExecuted(let reason):
                        outcome = .failed(reason == .terminationUnconfirmed ? "原本の使用終了を確認できないため、削除していません。" : "前回は削除を実行していません。")
                    case .resolved(let resolution):
                        let latest = state?.resolvedRemoval?.operation == operation.id
                        let expected: LibraryRemoval = resolution == .removed ? .removed(operation.purpose) : .notRemoved(operation.purpose)
                        if latest && item.removal != expected { outcome = .unknown }
                        else { outcome = resolution == .removed ? .succeeded : .failed("原本は削除していません。") }
                    }
                    return .init(id: operation.batch, action: operation.action, outcome: outcome)
                }
                if state?.removal != nil { item.removalUnavailableReason = "前の削除結果を照合してください。" }
                else if state?.invalidation != nil { item.removalUnavailableReason = "確認の失効を照合中です。完了後に操作してください。" }
                else if let original = item.original,
                        !OriginalRemovalTransportHistory.neverStartedForRemoval(original, backend: backend),
                        OriginalRemovalTransportHistory.stoppedTasks(original, backend: backend) == nil {
                    item.removalUnavailableReason = "以前の通信の終了を確認できません。原本を保持しています。"
                }
                let bytes = item.original?.content.byteCount ?? recording.result?.file.byteCount
                let size = bytes.map { ByteCountFormatter.string(fromByteCount: Int64(clamping: $0), countStyle: .file) } ?? "不明"
                let verification = item.original.flatMap { original in
                    backend.verifications.last(where: { $0.expected.target == .original(original) })
                }
                let valid = verification.flatMap { proof -> StoredVerificationEvidence? in
                    guard let original = item.original, proof.isCommitted,
                          let registration = backend.registrations.last(where: {
                              $0.server.registration.destination == proof.expected.registration.destination
                          }), registration.isCommitted, registration.server.registration == proof.expected.registration,
                          proof.evidence.verifies(original, destination: proof.expected.registration.destination,
                            supportedSchemas: ["fr-final-read-v1"]) else { return nil }
                    return proof
                }
                let verifiedAt = valid.map { $0.evidence.observedAt.formatted(date: .abbreviated, time: .standard) } ?? "記録なし"
                let cleanupEvidence = item.original.map { original in
                    recording.result?.result == .saved && backend.confirmationStates.contains { confirmation in
                        guard confirmation.current.original == original, confirmation.validConfirmation != nil,
                              let registration = backend.registrations.last(where: {
                                  $0.server.registration.destination == confirmation.registration.destination
                              }), registration.isCommitted, registration.server.registration == confirmation.registration,
                              let proof = backend.verifications.last(where: {
                                  $0.expected.target == .original(original)
                                      && $0.expected.registration.destination == confirmation.registration.destination
                              }) else { return false }
                        return proof.isCommitted && proof.evidence.verifies(original,
                            destination: confirmation.registration.destination, supportedSchemas: ["fr-final-read-v1"])
                    }
                } ?? false
                item.cleanupUnavailableReason = item.removalUnavailableReason
                    ?? (cleanupEvidence ? nil : "同じ原本の有効な保存検証と軽量版の明示確認がありません。")
                item.removalReviewInformation = "対象：\(item.title)。\(item.captureDateDescription)。原本のサイズ：\(size)。最後の有効な保存検証：\(verifiedAt)。"
                    + "容量整理の条件：\(item.cleanupUnavailableReason ?? "最後の保存検証と有効な明示確認あり。削除直前にも照合します。")"
                items.append(item)
            }
            // A deletion or capture commit during the file scan invalidates this mixed snapshot.
            let after = await store.loadRecordings()
            guard case .loaded(let latest) = after else { return .unavailable(failure(after)) }
            guard latest.revision == saved.revision else { continue }
            guard case .succeeded(let latestOriginals) = await store.loadOriginalState(),
                  case .loaded(let latestBackend) = await store.load() else { return .unavailable(.inaccessible) }
            guard latestOriginals.revision == saved.revision, latestBackend.revision == saved.revision else { continue }
            guard latestBackend.storeIdentity == backend.storeIdentity,
                  OriginalUploadAcceptanceValueValidation.exact(
                    OriginalUploadAcceptanceBoundary.currentRegistration(latestBackend),
                    OriginalUploadAcceptanceBoundary.currentRegistration(backend)) else { return .unavailable(.identityMismatch) }
            for item in items {
                guard let recording = latest.recordings.first(where: {
                    OriginalUploadAcceptanceValueValidation.exact($0.intent.context.capture, item.id)
                }) else { return .unavailable(.identityMismatch) }
                let state = latestOriginals.originals.first {
                    OriginalUploadAcceptanceValueValidation.exact($0.binding.original.capture, item.id)
                }
                guard OriginalUploadAcceptanceValueValidation.exact(item.uploadCandidateBinding,
                    OriginalUploadAcceptanceBoundary.candidate(recording, state: state)) else { return .unavailable(.identityMismatch) }
            }
            return .loaded(.init(revision: saved.revision, items: items.sorted { $0.id.rawValue < $1.id.rawValue },
                remoteItems: remoteItems(backend: backend, originals: originals, local: items, requests: requests),
                photoSaveBatches: backend.photoSaveBatches, storeIdentity: backend.storeIdentity,
                mediaRequests: requests, personControls: backend.personControls,
                uploadRegistration: OriginalUploadAcceptanceBoundary.currentRegistration(backend),
                originalUploadAcceptances: backend.originalUploadAcceptances.filter(\.isCommitted)))
        }
        return .unavailable(.changing)
    }

    private func remoteItems(backend: BackendStoreSnapshot, originals: OriginalStoreSnapshot, local: [LibraryItem],
        requests: [LibraryMediaRequest]) -> [LibraryRemoteItem] {
        var known: [(DestinationIdentity, OriginalContent)] = []
        var keys = Set<RemoteInventoryOriginalID>()
        for page in backend.remoteInventory where page.isCommitted {
            let observation = page.observation
            guard observation.storeIdentity == backend.storeIdentity,
                  let current = backend.registrations.last(where: {
                      $0.server.registration.destination == observation.registration.destination
                  }), current.isCommitted,
                  PublicationStoreBoundary.exact(current.server.registration, observation.registration) else { continue }
            for original in observation.page.originals {
                let key = RemoteInventoryOriginalID(destination: observation.registration.destination, original: original)
                if keys.insert(key).inserted { known.append((observation.registration.destination, original)) }
            }
        }
        return known.compactMap { destination, original -> LibraryRemoteItem? in
            if local.contains(where: { $0.original.map { RemoteInventoryValidation.same($0, original) } == true }) { return nil }
            let remoteConflict = known.contains { otherDestination, other in
                otherDestination == destination && other.capture.rawValue.utf8.elementsEqual(original.capture.rawValue.utf8)
                    && !RemoteInventoryValidation.same(other, original)
            }
            let localConflict = local.contains { $0.id.rawValue.utf8.elementsEqual(original.capture.rawValue.utf8) }
            let registration = backend.registrations.last(where: {
                PublicationStoreBoundary.exact($0.server.registration.destination, destination)
            })?.server.registration
            let media = registration.map { LibraryPublicationProjection.statuses(original: original,
                registration: $0, backend: backend) }
            let source = LibraryPhotoSaveProjection.source(backend: backend, originals: originals,
                target: .init(original: original, destination: destination))
            return .init(destination: destination, original: original, hasIdentityConflict: remoteConflict || localConflict,
                publicationDescription: media?.publication ?? "公開版の保存記録なし（未照合を含む）",
                retrievalDescription: media?.retrieval ?? "端末内の軽量版の取得記録なし・オフライン再生不可",
                localRenditionUnavailableReason: (try? LocalRenditionSelection.select(backend: backend, originals: originals,
                    target: .init(original: original, destination: destination))) == nil ? LocalRenditionSelection.unavailableReason : nil,
                photoSaveSource: source, photoSaveUnavailableReason: LibraryPhotoSaveProjection.unavailable(source, backend: backend),
                photoRegistrations: LibraryPhotoSaveProjection.registrations(backend.photoRegistrations,
                    original: original, destination: destination),
                mediaRequests: LibraryMediaRequestProjection.matching(requests, original: original, destination: destination))
        }.sorted { $0.id.accessibilityToken.utf8.lexicographicallyPrecedes($1.id.accessibilityToken.utf8) }
    }

    private func failure(_ result: RecordingStoreLoadResult) -> LibraryReadFailure {
        switch result {
        case .unrecognizedSchema: .unknownSchema
        case .corruptStore: .corruptStore
        default: .inaccessible
        }
    }
}
