import Foundation
import Darwin

/// Read-only final validation under the normal document/writer lock. It grants
/// no receipt, journal event or media ownership; the live resolver already
/// owns the verified FD and the caller's action only registers PhotoKit work.
nonisolated enum PhotoSaveStartStoreBoundary {
    static func require(_ command: PhotoLibraryAddCommand, document: RecordingStoreDocument,
                        epoch: ReaderReconciliationEpoch) throws {
        try requireCommittedInput(command, document: document)
        let projection = try document.replayStore()
        try requireCurrentInput(command, projection: projection, epoch: epoch)
    }

    // Keep the large current-state values out of the journal replay's stack.
    // Both phases still execute synchronously under the same writer lock.
    @inline(never)
    private static func requireCommittedInput(_ command: PhotoLibraryAddCommand,
                                              document: RecordingStoreDocument) throws {
        let saved = command.registration, intent = saved.intent
        try intent.validate()
        guard saved.isCommitted, let identity = saved.expectedStoreIdentity, document.storeIdentity == identity,
              case .committed(let actual) = document.lookupBackend(saved.mutation),
              exact(actual, saved.commit), exact(command.media.handoff.usage, intent.usage),
              exact(command.media.handoff.rendition, intent.rendition), exact(command.media.handoff.media, intent.media),
              command.media.handoff.capturedAt == intent.capturedAt else { throw BackendContractError.notCommitted }
    }

    @inline(never)
    private static func requireCurrentInput(_ command: PhotoLibraryAddCommand, projection: MediaStoreProjection,
                                           epoch: ReaderReconciliationEpoch) throws {
        let saved = command.registration, intent = saved.intent
        guard let record = projection.photoRegistrations.last(where: { $0.registration.intent.key == intent.key }),
              same(record.registration, saved), record.results.isEmpty,
              record.usageTerminal == nil, record.usageRelease == nil, record.terminalUsageRelease == nil else {
            throw BackendContractError.wrongStage
        }
        guard let media = projection.temporaryMedia.first(where: { $0.id == intent.media }),
              exact(media.id, intent.media), exact(media.rendition, intent.rendition), media.capturedAt == intent.capturedAt,
              media.capturedAt.timeIntervalSinceReferenceDate.isFinite,
              media.complete, exact(media.verifiedContent, Optional(intent.rendition.deliveryContent)),
              !media.reclaiming, !media.reclaimed,
              media.directoryIdentity == saved.directoryIdentity, media.fileIdentity == saved.fileIdentity,
              let file = media.fileIdentity,
              exact(command.media.contentType, Optional(media.contentType)),
              media.usages.contains(where: { exact($0, saved.mediaUse) }),
              exact(saved.mediaUse.usage, intent.usage), saved.mediaUse.usage.purpose == .photoHandoff,
              exact(saved.mediaUse.lease.context, MediaReadContext.temporary(intent.media, intent.usage.id)),
              exact(saved.mediaUse.lease.target, MediaTarget.rendition(intent.rendition)),
              exact(saved.mediaUse.lease.registration, media.registration),
              saved.mediaUse.lease.epoch == epoch, intent.usage.epoch == epoch else {
            throw BackendContractError.ineligibleOriginal
        }
        guard let original = projection.originals.first(where: { exact($0.original, intent.rendition.original) }),
              !projection.originals.contains(where: { $0.original.capture == intent.rendition.original.capture
                  && !exact($0.original, intent.rendition.original) }),
              original.removal == nil, original.invalidation == nil,
              original.mediaReaders.contains(where: { exact($0, saved.mediaUse.lease) }) else {
            throw BackendContractError.ineligibleOriginal
        }
        // A valid independent cached rendition also works without a local
        // binding or after the original was physically organized/removed.
        guard let current = projection.registrations.last(where: {
            $0.server.registration.destination == media.registration.destination
        }), current.isCommitted, exact(current.server.registration, media.registration),
              let publication = projection.confirmationState(original: intent.rendition.original, registration: media.registration),
              exact(publication.registration, media.registration), exact(publication.current, intent.rendition),
              !publication.invalidatedRenditions.contains(intent.rendition.rendition) else { throw BackendContractError.invalidated }
        try projection.requireOriginalUploadRegistration(current)
        try requireNamedFile(command.media, leaf: media.leaf, directory: media.directoryIdentity,
                             file: file, bytes: intent.rendition.deliveryContent.byteCount)
    }

    private static func requireNamedFile(_ media: TemporaryLocalMedia, leaf: String, directory: TemporaryFileIdentity,
                                        file: TemporaryFileIdentity, bytes: UInt64) throws {
        let url = media.url
        guard url.isFileURL, exact(url.lastPathComponent, leaf), let witness = media.photoReadWitness, witness.isCurrent else {
            throw BackendContractError.identityMismatch
        }
        var root = stat(), value = stat(), openedRoot = stat(), opened = stat(), relative = stat()
        guard lstat(url.deletingLastPathComponent().path, &root) == 0,
              fstat(witness.directoryDescriptor, &openedRoot) == 0, openedRoot.st_mode & S_IFMT == S_IFDIR,
              root.st_mode & S_IFMT == S_IFDIR,
              Int64(root.st_dev) == directory.device, UInt64(root.st_ino) == directory.inode,
              openedRoot.st_dev == root.st_dev, openedRoot.st_ino == root.st_ino,
              lstat(url.path, &value) == 0, value.st_mode & S_IFMT == S_IFREG,
              fstat(witness.fileDescriptor, &opened) == 0,
              fstatat(witness.directoryDescriptor, leaf, &relative, AT_SYMLINK_NOFOLLOW) == 0,
              try OriginalFileFingerprint(info: value) == witness.fingerprint,
              try OriginalFileFingerprint(info: opened) == witness.fingerprint,
              try OriginalFileFingerprint(info: relative) == witness.fingerprint,
              Int64(value.st_dev) == file.device, UInt64(value.st_ino) == file.inode,
              value.st_size >= 0, UInt64(value.st_size) == bytes else { throw BackendContractError.identityMismatch }
    }

    static func same(_ left: CommittedPhotoRegistrationIntent, _ right: CommittedPhotoRegistrationIntent) -> Bool {
        exact(left.intent, right.intent) && exact(left.mediaUse, right.mediaUse) && exact(left.commit, right.commit)
            && left.expectedStoreIdentity == right.expectedStoreIdentity
            && left.directoryIdentity == right.directoryIdentity && left.fileIdentity == right.fileIdentity
    }

    /// Local termination authority only; the external addition may still be
    /// unknown. Every returned mutation/receipt must be looked up exactly.
    static func localStopProof(_ record: PhotoRegistrationRecord, identity: RegistrationStoreIdentity)
        -> [(BackendStoreMutation, BackendCommitReceipt)]? {
        let registration = record.registration
        guard registration.isCommitted, registration.expectedStoreIdentity == identity else { return nil }
        if let terminal = record.usageTerminal, let release = record.terminalUsageRelease,
           terminal.expectedStoreIdentity == identity, release.expectedStoreIdentity == identity,
           exact(terminal.terminal.intent, registration.intent), exact(terminal.terminal.mediaUse, registration.mediaUse),
           terminal.terminal.directoryIdentity == registration.directoryIdentity,
           terminal.terminal.fileIdentity == registration.fileIdentity,
           exact(release.release.terminal, terminal.terminal),
           exact(release.release.terminalCommand, terminal.command), exact(release.release.terminalCommit, terminal.commit) {
            return [(registration.mutation, registration.commit), (terminal.mutation, terminal.commit), (release.mutation, release.commit)]
        }
        // Preserve the old successful-SDK release authority. It is neither a
        // new fabricated terminal nor permission to release any other use.
        if let release = record.usageRelease, let success = record.results.last,
           case .succeeded = success.result.outcome,
           release.expectedStoreIdentity == identity, success.expectedStoreIdentity == identity,
           exact(release.release.intent, registration.intent), exact(release.release.mediaUse, registration.mediaUse),
           release.release.directoryIdentity == registration.directoryIdentity,
           release.release.fileIdentity == registration.fileIdentity,
           exact(release.release.successCommand, success.command), exact(release.release.successCommit, success.commit) {
            return [(registration.mutation, registration.commit), (success.mutation, success.commit), (release.mutation, release.commit)]
        }
        return nil
    }

    static func photoReadersStopped(backend: BackendStoreSnapshot, originals: OriginalStoreSnapshot) -> Bool {
        guard backend.revision == originals.revision, let identity = backend.storeIdentity,
              !backend.temporaryMedia.contains(where: { $0.usages.contains(where: { $0.usage.purpose == .photoHandoff }) }) else { return false }
        for record in backend.photoRegistrations {
            guard localStopProof(record, identity: identity) != nil,
                  let media = backend.temporaryMedia.first(where: { exact($0.id, record.registration.intent.media) }),
                  media.releasedUsages.contains(where: { exact($0, record.registration.mediaUse) }),
                  let original = originals.logicalOriginals.first(where: { exact($0.original, record.registration.intent.rendition.original) }),
                  !original.mediaReaders.contains(where: { exact($0, record.registration.mediaUse.lease) }) else { return false }
        }
        return true
    }

    private static func exact<T: Encodable>(_ left: T, _ right: T) -> Bool {
        PhotoSaveBatchValueValidation.exact(left, right)
    }
}
