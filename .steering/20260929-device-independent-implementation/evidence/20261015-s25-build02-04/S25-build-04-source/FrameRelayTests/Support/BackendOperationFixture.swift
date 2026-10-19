import Testing
@testable import FrameRelay

/// Synthetic contract inputs only. These receipts represent fake committed facts;
/// they do not establish disk durability, media quality, or a real backend result.
nonisolated struct BackendOperationFixture {
    let destination: DestinationIdentity
    let registrationIntent: RegistrationIntent
    let registration: RegistrationIdentity
    let deviceRegistration: DeviceRegistration
    let original: OriginalContent
    let secondOriginal: OriginalContent
    let current: RenditionIdentity
    let candidate: RenditionIdentity

    init() throws {
        let destination = DestinationIdentity(rawValue: "synthetic-destination")
        let registration = RegistrationIdentity(destination: destination,
                                                id: .init(rawValue: "synthetic-registration"),
                                                generation: .init(rawValue: 3))
        let intent = RegistrationIntent(operation: .init(rawValue: "synthetic-register"),
                                        destination: destination)
        self.destination = destination
        self.registration = registration
        registrationIntent = intent
        deviceRegistration = DeviceRegistration(
            server: .init(intent: intent, registration: registration),
            intentCommit: backendCommit(.registrationIntent(intent.operation, destination), revision: 10),
            commit: backendCommit(.registration(intent.operation, registration), revision: 11))
        let original = try Self.makeOriginal("A")
        self.original = original
        secondOriginal = try Self.makeOriginal("B")
        current = try Self.makeRendition(original: original, name: "V1", generation: 4)
        candidate = try Self.makeRendition(original: original, name: "V2", generation: 5)
    }

    static func makeOriginal(_ name: String, generation: UInt64 = 7) throws -> OriginalContent {
        OriginalContent(capture: .init(rawValue: "synthetic-capture-\(name)"),
                        generation: .init(rawValue: generation),
                        content: try .init(byteCount: 4096, algorithm: "synthetic-digest",
                                           digest: "synthetic-original-\(name)"))
    }

    static func makeRendition(original: OriginalContent, name: String,
                              generation: UInt64) throws -> RenditionIdentity {
        RenditionIdentity(original: original, inputLogIdentity: "synthetic-log",
                          transformAssetIdentity: "synthetic-transform", transformAssetVersion: "test-1",
                          outputConfigurationIdentity: "synthetic-output", conversionVersion: "test-1",
                          rendition: .init(rawValue: "synthetic-rendition-\(name)"),
                          deliveryContent: try .init(byteCount: 512, algorithm: "synthetic-digest",
                                                     digest: "synthetic-delivery-\(name)"),
                          publicationGeneration: .init(rawValue: generation))
    }

    func descriptor(original override: OriginalContent? = nil,
                    result: RecordingSaveResult = .saved,
                    presence: OriginalPresence = .present,
                    readiness: OriginalReadiness = .ready,
                    hasCommit: Bool = true) -> OriginalDescriptor {
        let original = override ?? self.original
        let context = CaptureContext(generation: .init(session: .init(rawValue: "synthetic-session"),
                                                       settings: 91), capture: original.capture)
        let token = CaptureCommandToken(context: context, operation: .init(rawValue: "synthetic-save"),
                                        ordinal: 6)
        let reference = CaptureOriginalReference(rawValue: "synthetic-original-reference")
        return OriginalDescriptor(original: original, reference: reference, saveResult: result,
                                  saveCommit: hasCommit ? .init(token: token, previousRevision: 20,
                                                                committedRevision: 21) : nil,
                                  savedReference: reference, savedContext: context,
                                  presence: presence, readiness: readiness)
    }

    func batch(originals: [OriginalDescriptor]? = nil,
               operations: [MediaOperationID]? = nil,
               onWiFi: Bool = true,
               registration override: DeviceRegistration? = nil) throws -> TransferBatch {
        let originals = originals ?? [descriptor(), descriptor(original: secondOriginal)]
        let operations = operations ?? originals.indices.map { MediaOperationID(rawValue: "synthetic-upload-\($0)") }
        return try TransferBatch(id: .init(rawValue: "synthetic-batch"), originals: originals,
                                 operations: operations, onWiFi: onWiFi,
                                 registration: override ?? deviceRegistration, expectedRevision: 30)
    }

    func request(purpose: MediaPurpose = .upload, target: MediaTarget? = nil,
                 operation: String = "synthetic-upload") -> MediaRequest {
        MediaRequest(operation: .init(rawValue: operation), target: target ?? .original(original),
                     purpose: purpose, registration: registration, expectedStartRevision: 30)
    }

    func readyRequest(purpose: MediaPurpose = .upload, target: MediaTarget? = nil) throws -> MediaRequest {
        var request = request(purpose: purpose, target: target)
        try request.acceptStartCommit(backendCommit(.request(request.operation, request.target, registration),
                                                     revision: request.expectedStartRevision))
        try request.reconcile(remoteResult(for: request, outcome: .notExecuted))
        return request
    }

    func remoteResult(for request: MediaRequest, outcome: BackendOutcome<EvidenceID>,
                      session: UploadSessionID? = nil, observation: UInt64? = nil) -> RemoteOperationResult {
        .init(context: .init(operation: request.operation, registration: request.registration,
                             target: request.target, session: session ?? request.session),
              observation: .init(rawValue: observation ?? ((request.lastObservation?.rawValue ?? 0) + 1)),
              result: outcome)
    }

    func ledger(current: RenditionIdentity? = nil) -> PublicationLedger {
        PublicationLedger(destination: destination, current: current ?? self.current,
                          generation: .init(rawValue: 8), revision: 40)
    }

    func replacement(previous: RenditionIdentity? = nil, candidate: RenditionIdentity? = nil,
                     generation: UInt64 = 9) -> PublicationIntent {
        PublicationIntent(operation: .init(rawValue: "synthetic-publish"), previous: previous ?? current,
                          candidate: candidate ?? self.candidate,
                          invalidationID: .init(rawValue: "synthetic-invalidation"),
                          invalidationGeneration: .init(rawValue: generation))
    }

    func distribution(rendition: RenditionIdentity? = nil,
                      registration override: RegistrationIdentity? = nil,
                      kind: MediaRetrievalKind = .full,
                      operation: String = "synthetic-distribute") -> DistributionIntent {
        DistributionIntent(operation: .init(rawValue: operation), rendition: rendition ?? current,
                           registration: override ?? registration, kind: kind)
    }

    func acknowledgement(for record: InvalidationRecord) -> InvalidationAcknowledgement {
        InvalidationAcknowledgement(record: record, commit: backendCommit(record.key, revision: 60))
    }
}

nonisolated func backendCommit(_ key: BackendCommitKey, revision: UInt64) -> BackendCommitReceipt {
    BackendCommitReceipt(key: key, previousRevision: revision, committedRevision: revision + 1)
}
