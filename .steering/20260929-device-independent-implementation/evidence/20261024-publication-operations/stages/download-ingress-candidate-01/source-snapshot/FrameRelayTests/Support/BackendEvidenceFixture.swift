import Foundation
@testable import FrameRelay

/// Synthetic identities and versions only. No product schema, digest or media settings are selected.
nonisolated struct BackendEvidenceFixture {
    let capture: CaptureFixture
    let original: OriginalContent
    let descriptor: OriginalDescriptor
    let registration: RegistrationIdentity
    let rendition: RenditionIdentity
    let distribution: DistributionReceipt

    init() throws {
        capture = try CaptureFixture()
        original = OriginalContent(capture: capture.context.capture, generation: .init(rawValue: 2),
                                   content: try .init(byteCount: 100, algorithm: "fixture-digest", digest: "original"))
        descriptor = OriginalDescriptor(original: original, reference: capture.intent.original,
                                        saveResult: .saved, saveCommit: capture.receipt(capture.token(1)),
                                        savedReference: capture.intent.original, savedContext: capture.context,
                                        presence: .present, readiness: .ready)
        registration = RegistrationIdentity(destination: .init(rawValue: "fixture-destination"),
                                            id: .init(rawValue: "fixture-device"), generation: .init(rawValue: 1))
        rendition = RenditionIdentity(original: original, inputLogIdentity: "fixture-log",
                                      transformAssetIdentity: "fixture-transform", transformAssetVersion: "fixture-v",
                                      outputConfigurationIdentity: "fixture-output", conversionVersion: "fixture-v",
                                      rendition: .init(rawValue: "fixture-rendition-1"),
                                      deliveryContent: try .init(byteCount: 10, algorithm: "fixture-digest", digest: "rendition"),
                                      publicationGeneration: .init(rawValue: 1))
        let operation = MediaOperationID(rawValue: "fixture-distribution")
        distribution = DistributionReceipt(operation: operation, rendition: rendition, registration: registration,
                                           commit: Self.commit(.distribution(operation, rendition, registration)))
    }

    static func commit(_ key: BackendCommitKey, revision: UInt64 = 0) -> BackendCommitReceipt {
        BackendCommitReceipt(key: key, previousRevision: revision, committedRevision: revision + 1)
    }

    func playback(generation: UInt64 = 0) throws -> PlaybackToken {
        try PlaybackToken(distribution: distribution, session: .init(rawValue: "fixture-playback"),
                          invalidationGeneration: .init(rawValue: generation), observation: .played)
    }

    func confirmed() throws -> ConfirmationState {
        var state = ConfirmationState(registration: registration, current: rendition,
                                      generation: .init(rawValue: 0), revision: 0)
        let intent = try state.prepareConfirmation(operation: .init(rawValue: "fixture-confirm"), playback: playback())
        try state.commitConfirmation(intent, receipt: Self.commit(intent.key))
        return state
    }

    var invalidation: InvalidationRecord {
        InvalidationRecord(id: .init(rawValue: "fixture-invalidation"), rendition: rendition,
                           registration: registration, generation: .init(rawValue: 1))
    }

    func verification(method: OriginalVerificationMethod? = nil, committed: Bool = true) -> VerificationEvidence {
        VerificationEvidence(id: .init(rawValue: "fixture-proof"),
                             context: .init(operation: .init(rawValue: "fixture-upload"), registration: registration,
                                            target: .original(original), session: .init(rawValue: "fixture-upload-session")),
                             finalSaveCompleted: true, verification: method ?? .finalDestinationReadBack(original.content),
                             committed: committed, schemaVersion: "fixture-schema", observedAt: Date(timeIntervalSince1970: 0))
    }

    func storedVerification(method: OriginalVerificationMethod? = nil, committed: Bool = true) -> StoredVerificationEvidence {
        let evidence = verification(method: method, committed: committed)
        let command = MediaOperationID(rawValue: "fixture-store-proof")
        return StoredVerificationEvidence(command: command, expected: evidence.context, evidence: evidence,
                                          commit: Self.commit(.verification(command, evidence.id, evidence.context)))
    }

    func readers(epoch: String = "fixture-epoch") throws -> OriginalReadersState {
        var state = OriginalReadersState(original: original, epoch: .init(rawValue: epoch), generation: .init(rawValue: 0))
        try state.reconcile([])
        return state
    }

    var removal: RemovalIntent {
        RemovalIntent(operation: .init(rawValue: "fixture-removal"), original: original, purpose: .cleanup)
    }

    func temporary(ranges: [MediaByteRange], verified: Bool = true, released: Bool = false,
                   purpose: TemporaryMediaPurpose = .photoHandoff) -> TemporaryMediaReceipt {
        let id = TemporaryMediaID(rawValue: "fixture-temporary")
        return TemporaryMediaReceipt(id: id, rendition: rendition, capturedAt: Date(timeIntervalSince1970: 0),
                                     ranges: ranges, verifiedContent: verified ? rendition.deliveryContent : nil,
                                     usage: .init(id: .init(rawValue: "fixture-use"), purpose: purpose, media: id),
                                     isReleased: released)
    }
}
