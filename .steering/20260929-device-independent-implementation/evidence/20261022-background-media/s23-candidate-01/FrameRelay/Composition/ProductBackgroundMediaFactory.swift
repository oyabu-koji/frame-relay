import Foundation

nonisolated enum ProductBackgroundPreparation: Equatable, Sendable {
    case prepared(knownSessions: Int)
    case held
}

/// Bound to one ProductLibraryFactory, not the first arbitrary test/product
/// store opened in this process. The normal App and background delegate share
/// the same instance and therefore the same writer and OS session owners.
actor ProductBackgroundMediaFactory {
    static let shared = ProductBackgroundMediaFactory(library: .shared)

    typealias OpenLibrary = @Sendable () async throws -> ProductLibraryServices
    typealias MakeSource = @Sendable (ProductLibraryServices) async throws -> any BackgroundMediaUploadSourcePort

    private let openLibrary: OpenLibrary
    private let admission: any BackgroundMediaStrictAdmissionPort
    private let sessionFactory: BackgroundMediaCoordinator.SessionFactory
    private let sourceFactory: MakeSource
    private var services: ProductLibraryServices?
    private var coordinator: BackgroundMediaCoordinator?
    private var boundIdentity: RegistrationStoreIdentity?
    private var sessions: [BackgroundMediaSessionID: (BackgroundMediaSessionIdentity, any BackgroundMediaSessionPort)] = [:]
    private var openingSessions: [BackgroundMediaSessionID: (BackgroundMediaSessionIdentity, Task<any BackgroundMediaSessionPort, Error>)] = [:]
    private var source: (any BackgroundMediaUploadSourcePort)?
    private var openingSource: Task<any BackgroundMediaUploadSourcePort, Error>?
    private var observers: [String: BackgroundMediaCoordinator.DidDrain] = [:]
    private var finished: [String: [BackgroundMediaDrainObservation]] = [:]

    init(library: ProductLibraryFactory = .shared,
         admission: any BackgroundMediaStrictAdmissionPort = UnavailableBackgroundMediaStrictAdmission(),
         sessionFactory: @escaping BackgroundMediaCoordinator.SessionFactory = { try BackgroundMediaSession(identity: $0) },
         sourceFactory: @escaping MakeSource = { try ManagedUploadSource(run: $0.run, originals: $0.access) },
         openLibrary: OpenLibrary? = nil) {
        self.openLibrary = openLibrary ?? { try await library.open() }
        self.admission = admission; self.sessionFactory = sessionFactory; self.sourceFactory = sourceFactory
    }

    /// Called both by normal composition and by the delegate itself. Empty
    /// roots open the real store without creating SDK sessions or media owners.
    func prepare() async -> ProductBackgroundPreparation {
        do {
            let services = try await library()
            guard case .loaded(let snapshot) = await services.store.load() else { return .held }
            let identifiers = Set(snapshot.backgroundTasks.map { $0.intent.session.identifier.rawValue })
            for identifier in identifiers {
                guard await restore(identifier: identifier) else { return .held }
            }
            return .prepared(knownSessions: identifiers.count)
        } catch { return .held }
    }

    /// Unknown identifiers never instantiate an OS session and never report
    /// delivery completion. A known, exact generation is recovered once.
    func restore(identifier: String, didDrain: BackgroundMediaCoordinator.DidDrain? = nil) async -> Bool {
        if let didDrain { observers[identifier] = didDrain }
        do {
            let services = try await library()
            guard case .loaded(let snapshot) = await services.store.load(), let identity = snapshot.storeIdentity else { return false }
            let candidates = Set(snapshot.backgroundTasks.filter {
                $0.intent.context.storeIdentity == identity && $0.intent.session.identifier.rawValue == identifier
            }.map { $0.intent.session })
            guard candidates.count == 1, let session = candidates.first else { return false }
            let coordinator = try self.coordinator(services: services, identity: identity)
            guard case .succeeded = await coordinator.recover(session) else { return false }
            await coordinator.retryHeldEvents()
            if let observer = observers[identifier] {
                for observation in finished[identifier] ?? [] { await observer(observation) }
            }
            return true
        } catch { return false }
    }

    func startUpload(_ plan: BackgroundMediaUploadPlan) async -> BackgroundMediaStartResult {
        do {
            let services = try await library()
            guard case .loaded(let snapshot) = await services.store.load(),
                  snapshot.storeIdentity == plan.context.storeIdentity else { return .refused(.identityMismatch) }
            let coordinator = try self.coordinator(services: services, identity: plan.context.storeIdentity)
            return await coordinator.startUpload(plan)
        } catch { return .unknown }
    }

    private func library() async throws -> ProductLibraryServices {
        if let services { return services }
        let opened = try await openLibrary()
        if let services {
            guard services.store === opened.store else { throw BackendContractError.identityMismatch }
            return services
        }
        services = opened
        return opened
    }

    private func coordinator(services: ProductLibraryServices,
                             identity: RegistrationStoreIdentity) throws -> BackgroundMediaCoordinator {
        if let coordinator {
            guard boundIdentity == identity else { throw BackendContractError.identityMismatch }
            return coordinator
        }
        let created = BackgroundMediaCoordinator(store: services.store, identity: identity, originals: services.access,
            admission: admission, sessionFactory: { [weak self] identity in
                guard let self else { throw BackendContractError.unavailable }
                return try await self.session(identity)
            }, sourceFactory: { [weak self] in
                guard let self else { throw BackendContractError.unavailable }
                return try await self.uploadSource()
            }, didDrain: { [weak self] observation in await self?.recordDrained(observation) })
        boundIdentity = identity
        coordinator = created
        return created
    }

    private func session(_ identity: BackgroundMediaSessionIdentity) async throws -> any BackgroundMediaSessionPort {
        if let existing = sessions[identity.identifier] {
            guard existing.0 == identity else { throw BackendContractError.identityMismatch }
            return existing.1
        }
        if let opening = openingSessions[identity.identifier] {
            guard opening.0 == identity else { throw BackendContractError.identityMismatch }
            return try await opening.1.value
        }
        let create = sessionFactory
        let task = Task { try await create(identity) }
        openingSessions[identity.identifier] = (identity, task)
        defer { openingSessions.removeValue(forKey: identity.identifier) }
        let result = try await task.value
        sessions[identity.identifier] = (identity, result)
        return result
    }

    private func uploadSource() async throws -> any BackgroundMediaUploadSourcePort {
        if let source { return source }
        if let openingSource { return try await openingSource.value }
        let services = try await library()
        if let source { return source }
        if let openingSource { return try await openingSource.value }
        let create = sourceFactory
        let task = Task { try await create(services) }
        openingSource = task
        defer { openingSource = nil }
        let result = try await task.value
        source = result
        return result
    }

    private func recordDrained(_ observation: BackgroundMediaDrainObservation) async {
        let identifier = observation.session.identifier.rawValue
        if !(finished[identifier] ?? []).contains(observation) { finished[identifier, default: []].append(observation) }
        await observers[identifier]?(observation)
    }
}
