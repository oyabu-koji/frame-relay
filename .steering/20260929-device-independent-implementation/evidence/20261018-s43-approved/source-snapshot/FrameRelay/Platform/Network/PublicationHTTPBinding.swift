import Foundation

/// One fixed source and its per-GET read tickets. The source receipt is never
/// reused as a read ticket, and URLSession retries cannot allocate new tickets.
actor PublicationHTTPBinding: RenditionRangeAuthorizationPort {
    nonisolated let command: RetrieveMediaCommand
    nonisolated let mediaType: String
    nonisolated let invalidationGeneration: InvalidationGeneration
    private let connection: RegistrationConnection
    private let remote: URLSessionPublicationRemote
    private let admission: any RenditionMediaAdmissionPort
    private let store: any MediaOperationStorePort
    private let identity: RegistrationStoreIdentity
    private init(command: RetrieveMediaCommand, mediaType: String, generation: InvalidationGeneration,
                 connection: RegistrationConnection, remote: URLSessionPublicationRemote,
                 admission: any RenditionMediaAdmissionPort, store: any MediaOperationStorePort, identity: RegistrationStoreIdentity) {
        self.command = command; self.mediaType = mediaType; invalidationGeneration = generation
        self.connection = connection; self.remote = remote; self.admission = admission; self.store = store; self.identity = identity
    }
    static func open(gate: MediaGateLease, sourceOperation: MediaOperationID, connection: RegistrationConnection,
                     remote: URLSessionPublicationRemote, admission: any RenditionMediaAdmissionPort,
                     store: any MediaOperationStorePort, identity: RegistrationStoreIdentity) async throws -> PublicationHTTPBinding {
        try await admission.check(gate)
        guard case .rendition(let rendition) = gate.target,
              case .succeeded(let manifest) = await remote.manifest(original: rendition.original, registration: gate.registration),
              let current = manifest.current, PublicationStoreBoundary.exact(current, rendition), let type = manifest.mediaType else { throw BackendContractError.unavailable }
        let initial = try await PublicationStoreBoundary.load(store, identity: identity)
        let prior = initial.publications.last { $0.observation.registration == gate.registration && $0.observation.rendition.original == rendition.original }
        if prior?.observation.rendition != rendition || prior?.observation.invalidationGeneration != manifest.invalidationGeneration {
            guard manifest.revision > (prior?.observation.observation.rawValue ?? 0) else { throw BackendContractError.staleGeneration }
            let observation = PublishedRenditionObservation(command: .init(rawValue: UUID().uuidString), registration: gate.registration,
                rendition: rendition, observation: .init(rawValue: manifest.revision), invalidationGeneration: manifest.invalidationGeneration)
            let mutation = BackendStoreMutation(expectedRevision: initial.revision, change: .publication(observation), expectedStoreIdentity: identity)
            guard case .committed(let proof) = await PublicationStoreBoundary.commit(mutation, store: store),
                  proof.matches(mutation.change.key, revision: mutation.expectedRevision) else { throw BackendContractError.unknownResult }
        }
        let request = PublicationDistributionRequest(operation: sourceOperation, gate: gate, rendition: rendition, purpose: .source, kind: .full, range: nil, source: nil)
        // Same complete request is used for reconciliation; never rebase a
        // server operation or turn a missing response into a new operation.
        var result = await remote.distribute(request)
        if result == .unknown { result = await remote.lookupDistribution(request) }
        guard case .succeeded(let source) = result, source.mediaType == type else { throw BackendContractError.unknownResult }
        let binding = PublicationHTTPBinding(command: .init(gate: gate, distribution: source.receipt, range: nil), mediaType: type,
            generation: manifest.invalidationGeneration, connection: connection, remote: remote, admission: admission, store: store, identity: identity)
        try await binding.checkCurrent()
        return binding
    }
    func authorize(_ proposed: RetrieveMediaCommand) async throws -> RetrieveMediaCommand {
        guard exactGate(proposed.gate), PublicationStoreBoundary.exact(proposed.distribution, command.distribution), let range = proposed.range else { throw BackendContractError.identityMismatch }
        try await checkCurrent()
        let request = PublicationDistributionRequest(operation: .init(rawValue: UUID().uuidString), gate: command.gate,
            rendition: command.distribution.rendition, purpose: .read, kind: .range, range: range, source: command.distribution.operation)
        var response = await remote.distribute(request)
        if response == .unknown { response = await remote.lookupDistribution(request) }
        guard case .succeeded(let accepted) = response, accepted.mediaType == mediaType else { throw BackendContractError.unknownResult }
        try await checkCurrent()
        return .init(gate: command.gate, distribution: accepted.receipt, range: range)
    }
    func binding() -> FixedRenditionHTTPBinding {
        var parts = URLComponents(url: connection.endpoint.url(path: "publication/media/" + command.distribution.rendition.rendition.rawValue), resolvingAgainstBaseURL: false)!
        let registration = command.distribution.registration
        parts.queryItems = [.init(name: "destination_id", value: registration.destination.rawValue),
            .init(name: "registration_id", value: registration.id.rawValue), .init(name: "registration_generation", value: String(registration.generation.rawValue))]
        return .init(url: parts.url!, contentType: mediaType, headers: { [self] value in
            guard value.identitiesMatch, await exactGate(value.gate), PublicationStoreBoundary.exact(value.distribution.rendition, command.distribution.rendition),
                  value.distribution.operation != command.distribution.operation else { throw BackendContractError.identityMismatch }
            try await checkCurrent()
            var headers = try await remote.authorizationHeaders(registration)
            headers["X-FrameRelay-Distribution-ID"] = try PublicationWire.headerID(value.distribution.operation.rawValue)
            headers["X-FrameRelay-Transport-ID"] = try PublicationWire.headerID(value.gate.operation.rawValue)
            headers["X-FrameRelay-Attempt-ID"] = try PublicationWire.headerID(value.gate.attempt.rawValue)
            headers["X-FrameRelay-Access-Generation"] = String(value.gate.generation)
            headers["Cache-Control"] = "no-store"
            try await checkCurrent()
            return headers
        }, validateIdentity: { response, value in
            let rendition = value.distribution.rendition
            let expected = ["X-FrameRelay-Wire-Version": PublicationWire.version,
                "X-FrameRelay-Distribution-ID": try PublicationWire.headerID(value.distribution.operation.rawValue),
                "X-FrameRelay-Rendition-ID": rendition.rendition.rawValue,
                "X-FrameRelay-Publication-Generation": String(rendition.publicationGeneration.rawValue),
                "X-FrameRelay-Content-SHA256": rendition.deliveryContent.digest,
                "X-FrameRelay-Content-Bytes": String(rendition.deliveryContent.byteCount), "Cache-Control": "no-store"]
            guard expected.allSatisfy({ response.value(forHTTPHeaderField: $0.key) == $0.value }) else { throw BackendContractError.identityMismatch }
        })
    }
    private func checkCurrent() async throws {
        try await admission.check(command.gate)
        let snapshot = try await PublicationStoreBoundary.load(store, identity: identity)
        let registration = command.distribution.registration
        guard snapshot.registrations.last(where: { $0.server.registration.destination == registration.destination })?.server.registration == registration,
              let state = snapshot.confirmationStates.first(where: { $0.registration == registration && $0.current.original == command.distribution.rendition.original }),
              PublicationStoreBoundary.exact(state.current, command.distribution.rendition),
              PublicationStoreBoundary.exact(state.registration, registration), state.generation == invalidationGeneration,
              !state.invalidatedRenditions.contains(state.current.rendition) else { throw BackendContractError.invalidated }
        try await admission.check(command.gate)
    }
    private func exactGate(_ value: MediaGateLease) -> Bool {
        value.operation.rawValue.utf8.elementsEqual(command.gate.operation.rawValue.utf8)
            && value.attempt.rawValue.utf8.elementsEqual(command.gate.attempt.rawValue.utf8)
            && PublicationStoreBoundary.exact(value.target, command.gate.target)
            && PublicationStoreBoundary.exact(value.registration, command.gate.registration)
            && value.generation == command.gate.generation
    }
}
