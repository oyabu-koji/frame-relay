@testable import FrameRelay
import Foundation
import Darwin

/// One composition-owned access/ordering boundary. Every product SDK reader must
/// register an attachment. Exploration inspection before binding remains separate.
actor ManagedOriginalAccess: OriginalAccessPort, OriginalPlaybackAccessPort, OriginalOperationOrderingPort {
    private struct Reader {
        let lease: OriginalReadLease
        var handle: ManagedOriginalReadHandle?
        var opening = true
        var attachments: Set<MediaUsageID> = []
        var stopping = false
        var releasing = false
        var releaseRequested = false
        var releaseMutation: OriginalStoreMutation?
    }
    private let store: any RecordingStorePort & OriginalStorePort
    private let originals: ManagedOriginalStore
    private let opener: any ManagedOriginalReadOpeningPort
    private let recoveryObserver: (any OriginalReaderRecoveryPort)?
    private let mediaRecoveryObserver: (any MediaReaderRecoveryPort)?
    private let epoch = ReaderReconciliationEpoch(rawValue: UUID().uuidString)
    private var readers: [ReadLeaseID: Reader] = [:]

    init(store: any RecordingStorePort & OriginalStorePort, originals: ManagedOriginalStore,
         recoveryObserver: (any OriginalReaderRecoveryPort)? = nil,
         opener: (any ManagedOriginalReadOpeningPort)? = nil,
         mediaRecoveryObserver: (any MediaReaderRecoveryPort)? = nil) {
        self.store = store; self.originals = originals; self.recoveryObserver = recoveryObserver
        self.mediaRecoveryObserver = mediaRecoveryObserver
        self.opener = opener ?? originals
    }

    func bind(_ reference: CaptureOriginalReference, operation: MediaOperationID) async -> BackendOutcome<OriginalBinding> {
        guard case .loaded(let recordings) = await store.loadRecordings(),
              let entry = recordings.recordings.first(where: { $0.intent.original == reference }),
              let record = entry.result, let receipt = entry.resultCommit,
              record.end.writer != .notStarted else { return .notExecuted }
        do {
            let digest = try await originals.digest(for: reference)
            guard digest.byteCount == record.file.byteCount else { return .failed(.contentMismatch) }
            guard case .succeeded(let snapshot) = await store.loadOriginalState() else { return .unknown }
            let content = try ContentIdentity(byteCount: digest.byteCount, algorithm: "sha256", digest: digest.sha256)
            if let old = snapshot.originals.first(where: { $0.binding.reference == reference }) {
                guard old.binding.original.content == content, old.binding.saveRecord == record,
                      old.binding.saveCommit == receipt else { return .failed(.contentMismatch) }
                return .succeeded(old.binding)
            }
            // A remote-only identity is authoritative too: attaching a local
            // binding must retain its content generation, reservations and leases.
            let known = snapshot.logicalOriginals.first { $0.original.capture == entry.intent.context.capture }?.original
            guard known == nil || known?.content == content else { return .failed(.contentMismatch) }
            let original = known ?? .init(capture: entry.intent.context.capture, generation: .init(rawValue: 1), content: content)
            let binding = OriginalBinding(original: original, reference: reference, saveRecord: record, saveCommit: receipt)
            let mutation = OriginalStoreMutation(operation: operation, expectedRevision: snapshot.revision, change: .bind(binding))
            switch await store.commitOriginal(mutation) {
            case .committed: return .succeeded(binding)
            case .rejected: return .failed(.rejected)
            case .unavailable: return .unknown
            }
        } catch { return .failed(.inaccessible) }
    }

    func describe(_ reference: CaptureOriginalReference) async -> OriginalDescriptionResult {
        guard case .succeeded(let snapshot) = await store.loadOriginalState(),
              let state = snapshot.originals.first(where: { $0.binding.reference == reference }) else {
            return .unavailable(.inaccessible)
        }
        let binding = state.binding
        let presence: OriginalPresence
        var readiness: OriginalReadiness = state.removal == nil && state.invalidation == nil ? .ready : .recovering
        switch await originals.observeFile(reference) {
        case .absent: presence = .absent
        case .unavailable: presence = .unknown; readiness = .inaccessible
        case .present:
            presence = .present
            do {
                let digest = try await originals.digest(for: reference)
                if digest.sha256 != binding.original.content.digest || digest.byteCount != binding.original.content.byteCount {
                    return .unavailable(.contentMismatch)
                }
            } catch { readiness = .inaccessible }
        }
        return .described(.init(original: binding.original, reference: reference, saveResult: binding.saveRecord.result,
            saveCommit: binding.saveCommit, savedReference: binding.saveRecord.intent.original,
            savedContext: binding.saveRecord.intent.context, presence: presence, readiness: readiness))
    }

    func acquireRead(_ original: OriginalContent, operation: MediaOperationID,
                     leaseID: ReadLeaseID) async -> BackendOutcome<OriginalReadLease> {
        await acquire(original, operation: operation, leaseID: leaseID, playback: false)
    }

    func acquirePlayback(_ original: OriginalContent, operation: MediaOperationID,
                         leaseID: ReadLeaseID) async -> BackendOutcome<OriginalPlaybackSource> {
        switch await acquire(original, operation: operation, leaseID: leaseID, playback: true) {
        case .succeeded(let lease): return .succeeded(.init(lease: lease))
        case .failed(let failure): return .failed(failure)
        case .notExecuted: return .notExecuted
        default: return .unknown
        }
    }

    private func acquire(_ original: OriginalContent, operation: MediaOperationID,
                         leaseID: ReadLeaseID, playback: Bool) async -> BackendOutcome<OriginalReadLease> {
        guard readers[leaseID] == nil, case .succeeded(let snapshot) = await store.loadOriginalState(),
              let state = snapshot.originals.first(where: { $0.binding.original == original }),
              state.removal == nil, state.invalidation == nil, state.removalResolution != .removed,
              state.accessGeneration.rawValue < UInt64.max else { return .notExecuted }
        guard playback || state.binding.saveRecord.result == .saved else { return .notExecuted }
        let lease = OriginalReadLease(id: leaseID, original: original, operation: operation,
            accessGeneration: .init(rawValue: state.accessGeneration.rawValue + 1), epoch: epoch)
        let mutation = OriginalStoreMutation(operation: freshOperation("reader-acquire"),
                                             expectedRevision: snapshot.revision, change: .acquire(lease))
        // Persist reader ownership BEFORE opening. Removal can never pass through
        // a gap between the file opening and registration of that reader.
        guard case .committed = await store.commitOriginal(mutation) else { return .unknown }
        readers[leaseID] = Reader(lease: lease)
        do {
            let handle = try await opener.openBoundRead(state.binding)
            readers[leaseID]?.handle = handle
            readers[leaseID]?.opening = false
            // Opening is an actual outstanding reader operation. Cancellation or
            // invalidation during its await cannot turn nil handle into release.
            let pending = readers[leaseID]
            guard !Task.isCancelled, pending?.stopping == false, pending?.releaseRequested == false,
                  case .succeeded(let latest) = await store.loadOriginalState(),
                  let current = latest.originals.first(where: { $0.binding.original == original }),
                  current.removal == nil, current.invalidation == nil, current.readers.contains(lease),
                  readers[leaseID]?.stopping == false, readers[leaseID]?.handle != nil else {
                if case .succeeded = await releaseRead(lease) { return .notExecuted }
                return .unknown
            }
            return .succeeded(lease)
        } catch {
            readers[leaseID]?.opening = false
            if case .succeeded = await releaseRead(lease) {
                if error is CancellationError { return .notExecuted }
                if let mismatch = error as? CaptureContractError, mismatch == .evidenceMismatch {
                    return .failed(.contentMismatch)
                }
                return .failed(.inaccessible)
            }
            return .unknown
        }
    }

    func attachReader(_ lease: OriginalReadLease, id: MediaUsageID) -> BackendOutcome<OriginalReaderAttachment> {
        guard var reader = readers[lease.id], reader.lease == lease, reader.handle != nil,
              !reader.stopping, !reader.releasing, !reader.attachments.contains(id), !id.rawValue.isEmpty else {
            return .notExecuted
        }
        reader.attachments.insert(id)
        readers[lease.id] = reader
        return .succeeded(.init(lease: lease, id: id))
    }

    /// SDK resource loaders consume bounded bytes from this very descriptor; they
    /// never receive a file URL that could create an untracked SDK file handle.
    /// S15 drains loader tasks/queues before readerDidFinish, including on error.
    func readBytes(_ attachment: OriginalReaderAttachment, offset: UInt64, maximumLength: Int) throws -> Data {
        guard let reader = readers[attachment.lease.id], reader.lease == attachment.lease,
              reader.attachments.contains(attachment.id), !reader.stopping, !reader.releasing,
              let handle = reader.handle else { throw BackendContractError.wrongStage }
        guard offset <= UInt64(Int64.max), offset <= reader.lease.original.content.byteCount,
              (1...65_536).contains(maximumLength) else { throw BackendContractError.invalidValue }
        guard try OriginalFileFingerprint(descriptor: handle.handle.fileDescriptor) == handle.fingerprint else {
            throw BackendContractError.identityMismatch
        }
        let count = min(maximumLength, Int(min(UInt64(maximumLength), reader.lease.original.content.byteCount - offset)))
        if count == 0 { return Data() }
        var bytes = [UInt8](repeating: 0, count: count)
        var received: Int
        repeat { received = pread(handle.handle.fileDescriptor, &bytes, count, off_t(offset)) } while received < 0 && errno == EINTR
        guard received > 0 else { throw BackendContractError.unavailable }
        guard try OriginalFileFingerprint(descriptor: handle.handle.fileDescriptor) == handle.fingerprint else {
            throw BackendContractError.identityMismatch
        }
        return Data(bytes.prefix(received))
    }

    func readerDidFinish(_ attachment: OriginalReaderAttachment) -> BackendOutcome<ReadLeaseID> {
        guard var reader = readers[attachment.lease.id], reader.lease == attachment.lease,
              reader.attachments.remove(attachment.id) != nil else { return .notExecuted }
        readers[attachment.lease.id] = reader
        return .succeeded(attachment.lease.id)
    }

    func requestReaderStop(_ lease: OriginalReadLease) {
        guard readers[lease.id]?.lease == lease else { return }
        readers[lease.id]?.stopping = true
    }

    func isReaderStopRequested(_ lease: OriginalReadLease) -> Bool {
        guard let reader = readers[lease.id], reader.lease == lease else { return true }
        return reader.stopping
    }

    func releaseRead(_ lease: OriginalReadLease) async -> BackendOutcome<ReadReleaseReceipt> {
        guard var reader = readers[lease.id], reader.lease == lease else { return .notExecuted }
        if reader.opening {
            reader.stopping = true; reader.releaseRequested = true
            readers[lease.id] = reader
            return .inProgress
        }
        guard reader.attachments.isEmpty, !reader.releasing else { return .inProgress }
        do { try reader.handle?.handle.close(); reader.handle = nil }
        catch { return .unknown }
        reader.releasing = true
        readers[lease.id] = reader
        guard case .succeeded(let snapshot) = await store.loadOriginalState() else {
            readers[lease.id]?.releasing = false; return .unknown
        }
        let mutation = reader.releaseMutation ?? OriginalStoreMutation(operation: freshOperation("reader-release"),
            expectedRevision: snapshot.revision, change: .release(lease))
        readers[lease.id]?.releaseMutation = mutation
        switch await store.commitOriginal(mutation) {
        case .committed:
            readers.removeValue(forKey: lease.id)
            return .succeeded(.init(lease: lease))
        case .rejected(.revisionConflict):
            readers[lease.id]?.releaseMutation = nil
            readers[lease.id]?.releasing = false
            return .unknown
        default:
            readers[lease.id]?.releasing = false
            return .unknown
        }
    }

    func reconcileReaders(_ original: OriginalContent) async -> BackendOutcome<AllReadersReleasedReceipt> {
        guard case .succeeded(let snapshot) = await store.loadOriginalState(),
              let state = snapshot.logicalOriginals.first(where: { $0.original == original }) else { return .unknown }
        guard state.readersReleased(in: snapshot.reconciliationEpoch),
              !readers.values.contains(where: { $0.lease.original == original }) else { return .inProgress }
        return .succeeded(.init(original: original, accessGeneration: state.accessGeneration, epoch: epoch))
    }

    func recoverPersistedReaders(_ original: OriginalContent) async -> BackendOutcome<AllReadersReleasedReceipt> {
        guard let recoveryObserver, case .succeeded(let snapshot) = await store.loadOriginalState(),
              let state = snapshot.originals.first(where: { $0.binding.original == original }) else { return .unknown }
        for lease in state.readers {
            // Current handles must go through normal SDK teardown + actual close.
            guard readers[lease.id] == nil, lease.epoch != epoch else { return .inProgress }
            guard case .succeeded(let release) = await recoveryObserver.observeRecoveredRelease(lease),
                  release.lease == lease,
                  case .succeeded(let latest) = await store.loadOriginalState() else { return .unknown }
            guard case .committed = await store.commitOriginal(.init(operation: freshOperation("reader-recovered"),
                expectedRevision: latest.revision, change: .release(lease))) else { return .unknown }
        }
        return await reconcileReaders(original)
    }

    func reserveRemoval(_ request: RemovalBoundaryRequest) async -> BackendOutcome<RemovalIntent> {
        // Cleanup authority needs S21's actual verification/confirmation records
        // and S32's last-moment evaluation. A caller-made .eligible is not enough.
        guard request.intent.purpose == .discard else { return .notExecuted }
        guard request.stopped == .neverStarted(.original(request.intent.original)),
              request.stopped == request.expectedTransport else { return .unknown }
        guard case .succeeded(let snapshot) = await store.loadOriginalState(),
              let state = snapshot.originals.first(where: { $0.binding.original == request.intent.original }),
              let logical = snapshot.logicalOriginals.first(where: { $0.original == request.intent.original }),
              logical.readersReleased(in: snapshot.reconciliationEpoch),
              !readers.values.contains(where: { $0.lease.original == request.intent.original }),
              request.released == .init(original: request.intent.original, accessGeneration: state.accessGeneration, epoch: epoch),
              request.readers.validates(request.released) else { return .notExecuted }
        let mutation = OriginalStoreMutation(operation: freshOperation("removal-reserve"), expectedRevision: snapshot.revision,
            change: .reserveRemoval(request.intent, expectedInvalidation: state.invalidationGeneration,
                                    expectedAccess: state.accessGeneration))
        guard case .committed = await store.commitOriginal(mutation) else { return .unknown }
        return .succeeded(request.intent)
    }

    func recoverPersistedMediaReaders(_ original: OriginalContent) async -> BackendOutcome<AllReadersReleasedReceipt> {
        guard let mediaRecoveryObserver, case .succeeded(let initial) = await store.loadOriginalState(),
              let state = initial.logicalOriginals.first(where: { $0.original == original }) else { return .unknown }
        guard state.readers.isEmpty, !readers.values.contains(where: { $0.lease.original == original }) else { return .inProgress }
        for lease in state.mediaReaders {
            guard case .succeeded(let released) = await mediaRecoveryObserver.observeReleased(lease), released == lease,
                  case .succeeded(let current) = await store.loadOriginalState(),
                  case .committed = await store.commitOriginal(.init(operation: freshOperation("media-reader-recovered"),
                    expectedRevision: current.revision, change: .releaseMedia(lease))) else { return .unknown }
        }
        guard case .succeeded(let current) = await store.loadOriginalState(),
              let latest = current.logicalOriginals.first(where: { $0.original == original }),
              let epoch = current.reconciliationEpoch,
              case .succeeded(let observed) = await mediaRecoveryObserver.observeQuiescence(original: original,
                    accessGeneration: latest.accessGeneration, epoch: epoch),
              observed.original == original, observed.accessGeneration == latest.accessGeneration, observed.epoch == epoch,
              case .committed = await store.commitOriginal(.init(operation: freshOperation("media-readers-reconciled"),
                expectedRevision: current.revision, change: .reconcileMedia(observed))) else { return .unknown }
        return await reconcileReaders(original)
    }

    func reconcileRemoval(_ intent: RemovalIntent,
                          result: BackendOutcome<RemovalResolutionReceipt>) async -> BackendOutcome<RemovalIntent> {
        guard case .succeeded(let receipt) = result, receipt.intent == intent,
              case .succeeded(let snapshot) = await store.loadOriginalState(),
              let state = snapshot.originals.first(where: { $0.binding.original == intent.original }),
              state.removal == intent else { return .unknown }
        // Reconcile existing facts only. This operation never performs unlink.
        switch (receipt.resolution, await originals.observeFile(state.binding.reference)) {
        case (.removed, .absent): break
        case (.notRemoved, .present):
            do {
                let handle = try await originals.openBoundRead(state.binding)
                try handle.handle.close()
            } catch { return .unknown }
        default: return .unknown
        }
        guard case .committed = await store.commitOriginal(.init(operation: freshOperation("removal-resolve"),
            expectedRevision: snapshot.revision, change: .resolveRemoval(intent, receipt.resolution))) else { return .unknown }
        return .succeeded(intent)
    }

    func reserveInvalidation(_ record: InvalidationRecord) async -> BackendOutcome<InvalidationPermit> {
        guard case .succeeded(let snapshot) = await store.loadOriginalState() else { return .unknown }
        // Resume only the exact durable reservation. A new registration or
        // different invalidation can never take over its ownership.
        if let reservation = snapshot.logicalOriginals.first(where: { $0.original == record.rendition.original })?.invalidation {
            guard reservation.record == record else { return .unknown }
            for id in Array(readers.keys) where readers[id]?.lease.original == record.rendition.original { readers[id]?.stopping = true }
            return .succeeded(.init(record: record))
        }
        guard case .committed = await store.commitOriginal(.init(operation: freshOperation("invalidation-reserve"),
            expectedRevision: snapshot.revision, change: .reserveInvalidation(.init(record)))) else { return .unknown }
        for id in Array(readers.keys) where readers[id]?.lease.original == record.rendition.original { readers[id]?.stopping = true }
        return .succeeded(.init(record: record))
    }

    func finishInvalidation(_ acknowledgement: InvalidationAcknowledgement) async -> BackendOutcome<InvalidationID> {
        // The commit already checked all durable readers and atomically resolved
        // ordering. A lost reply is reconciled against that exact durable ACK,
        // including after outbox delivery; no new release fact is manufactured.
        guard !readers.values.contains(where: { $0.lease.original == acknowledgement.record.rendition.original }) else {
            return .inProgress
        }
        return await store.lookupInvalidation(acknowledgement)
    }

    private func freshOperation(_ prefix: String) -> MediaOperationID { .init(rawValue: prefix + "-" + UUID().uuidString) }
}
