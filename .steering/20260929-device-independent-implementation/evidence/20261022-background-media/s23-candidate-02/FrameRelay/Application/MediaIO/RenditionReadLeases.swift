import Foundation

/// Uses the existing recording writer and its current process epoch. No lease
/// is removed merely because this instance has no corresponding SDK object.
actor RenditionReadLeases {
    let store: any OriginalStorePort
    let mediaStore: any MediaOperationStorePort

    init(store: any OriginalStorePort & MediaOperationStorePort) {
        self.store = store; mediaStore = store
    }

    func currentEpoch() async throws -> ReaderReconciliationEpoch {
        guard case .succeeded(let snapshot) = await store.loadOriginalState(),
              let epoch = snapshot.reconciliationEpoch else { throw BackendContractError.unavailable }
        return epoch
    }

    /// Usage and its ordering lease enter the same writer transaction.
    func acquireTemporary(_ state: TemporaryMediaState, purpose: TemporaryMediaPurpose,
                          usageID: MediaUsageID, owner: String) async throws -> TemporaryMediaUseRecord {
        let leaseID = ReadLeaseID(rawValue: UUID().uuidString)
        while true {
            try Task.checkCancellation()
            guard case .succeeded(let snapshot) = await store.loadOriginalState(),
                  let epoch = snapshot.reconciliationEpoch,
                  let original = snapshot.logicalOriginals.first(where: { $0.original == state.rendition.original }),
                  original.accessGeneration.rawValue < UInt64.max else { throw BackendContractError.unavailable }
            let lease = MediaReadLease(id: leaseID, target: .rendition(state.rendition),
                operation: .init(rawValue: UUID().uuidString), registration: state.registration,
                context: .temporary(state.id, usageID), epoch: epoch,
                accessGeneration: .init(rawValue: original.accessGeneration.rawValue + 1))
            let use = TemporaryMediaUseRecord(usage: .init(id: usageID, purpose: purpose, media: state.id, epoch: epoch),
                lease: lease, owner: owner)
            let mutation = BackendStoreMutation(expectedRevision: snapshot.revision,
                change: .temporary(command: .init(rawValue: UUID().uuidString), value: .acquire(state.id, use)))
            switch await mediaStore.commit(mutation) {
            case .committed: return use
            case .rejected(.revisionConflict): continue
            case .rejected(let error): throw error
            case .unavailable, .unknown:
                guard case .committed = await mediaStore.lookupCommit(mutation) else { throw BackendContractError.unknownResult }
                return use
            }
        }
    }

    func acquire(rendition: RenditionIdentity, registration: RegistrationIdentity,
                 operation: MediaOperationID, context: MediaReadContext) async throws -> MediaReadLease {
        let id = ReadLeaseID(rawValue: UUID().uuidString)
        while true {
            try Task.checkCancellation()
            guard case .succeeded(let snapshot) = await store.loadOriginalState(),
                  let epoch = snapshot.reconciliationEpoch,
                  let state = snapshot.logicalOriginals.first(where: { $0.original == rendition.original }),
                  state.accessGeneration.rawValue < UInt64.max else { throw BackendContractError.unavailable }
            let lease = MediaReadLease(id: id, target: .rendition(rendition), operation: operation,
                registration: registration, context: context, epoch: epoch,
                accessGeneration: .init(rawValue: state.accessGeneration.rawValue + 1))
            let mutation = OriginalStoreMutation(operation: .init(rawValue: UUID().uuidString),
                expectedRevision: snapshot.revision, change: .acquireMedia(lease))
            switch await store.commitOriginal(mutation) {
            case .committed: return lease
            case .rejected(.revisionConflict): continue
            case .rejected(let failure): throw failure
            case .unavailable: throw BackendContractError.unknownResult
            }
        }
    }

    func check(_ lease: MediaReadLease) async throws {
        guard case .succeeded(let snapshot) = await store.loadOriginalState(),
              snapshot.reconciliationEpoch == lease.epoch,
              let state = snapshot.logicalOriginals.first(where: { $0.original == lease.target.original }),
              state.mediaReaders.contains(lease), state.removal == nil, state.invalidation == nil,
              case .rendition(let rendition) = lease.target,
              case .loaded(let media) = await mediaStore.load(),
              media.registrations.last(where: { $0.server.registration.destination == lease.registration.destination })?
                .server.registration == lease.registration,
              let current = media.confirmationStates.first(where: {
                  $0.registration == lease.registration && $0.current.original == rendition.original
              }), current.current == rendition, !current.invalidatedRenditions.contains(rendition.rendition)
        else { throw BackendContractError.staleGeneration }
    }

    /// The caller is the owner which has observed actual task/SDK/file closure.
    func release(_ lease: MediaReadLease) async throws {
        while true {
            guard case .succeeded(let snapshot) = await store.loadOriginalState(),
                  snapshot.reconciliationEpoch == lease.epoch,
                  snapshot.logicalOriginals.contains(where: { $0.mediaReaders.contains(lease) })
            else { throw BackendContractError.staleGeneration }
            let mutation = OriginalStoreMutation(operation: .init(rawValue: UUID().uuidString),
                expectedRevision: snapshot.revision, change: .releaseMedia(lease))
            switch await store.commitOriginal(mutation) {
            case .committed: return
            case .rejected(.revisionConflict): continue
            case .rejected(let failure): throw failure
            case .unavailable: throw BackendContractError.unknownResult
            }
        }
    }

    func commit(_ change: BackendStoreChange) async throws {
        while true {
            guard case .loaded(let snapshot) = await mediaStore.load() else { throw BackendContractError.unavailable }
            let mutation = BackendStoreMutation(expectedRevision: snapshot.revision, change: change)
            switch await mediaStore.commit(mutation) {
            case .committed: return
            case .rejected(.revisionConflict): continue
            case .rejected(let error): throw error
            case .unavailable, .unknown:
                guard case .committed = await mediaStore.lookupCommit(mutation) else {
                    throw BackendContractError.unknownResult
                }
                return
            }
        }
    }
}
