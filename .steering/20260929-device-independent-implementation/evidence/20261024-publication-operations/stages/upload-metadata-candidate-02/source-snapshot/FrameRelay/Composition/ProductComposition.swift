import Foundation
import Observation

@MainActor @Observable final class ProductComposition {
    private let factory: ProductLibraryFactory
    private let backgroundFactory: ProductBackgroundMediaFactory
    private let registrationFactory: (@Sendable (any MediaOperationStorePort) -> RegistrationCoordinator)?
    private let statusSynchronizationFactory: (@Sendable (ProductLibraryServices, ProductMediaTermination) -> any StatusSynchronizationPort)?
    private let remoteInventoryFactory: (@Sendable (ProductLibraryServices) -> any RemoteInventoryPort)?
    private let uploadMetadataFactory: (@Sendable (ProductLibraryServices) -> any UploadMetadataPort)?
    private let injectedPhotoNetwork: (any PhotoSaveStartNetworkPort)?
    private let injectedUploadNetwork: (any OriginalUploadStartNetworkPort)?
    private(set) var library: LibraryModel?
    private(set) var playback: OriginalPlaybackModel?
    private(set) var renditionPlayback: RenditionPlaybackModel?
    private(set) var renditionFactory: ProductRenditionFactory?
    private(set) var photoSaveBatches: PhotoSaveBatchCoordinator?
    private(set) var mediaRequestCommands: LibraryMediaRequestCommands?
    private(set) var originalUploadAcceptance: OriginalUploadAcceptanceCoordinator?
    private(set) var transferCommands: LibraryTransferCommands?
    private(set) var uploadMetadata: (any UploadMetadataPort)?
    private(set) var connection: ConnectionModel?
    private(set) var capture: ProductCaptureCoordinator?
    private(set) var mediaTermination: ProductMediaTermination?
    private(set) var statusSynchronization: (any StatusSynchronizationPort)?
    private(set) var remoteInventory: (any RemoteInventoryPort)?
    private(set) var isOpening = false
    private(set) var openingIssue: String?
    let exploration = ExplorationComposition.makeModel()

    init(factory: ProductLibraryFactory = .shared,
         backgroundFactory: ProductBackgroundMediaFactory? = nil,
         registrationFactory: (@Sendable (any MediaOperationStorePort) -> RegistrationCoordinator)? = nil,
         statusSynchronizationFactory: (@Sendable (ProductLibraryServices, ProductMediaTermination) -> any StatusSynchronizationPort)? = nil,
         remoteInventoryFactory: (@Sendable (ProductLibraryServices) -> any RemoteInventoryPort)? = nil,
         uploadMetadataFactory: (@Sendable (ProductLibraryServices) -> any UploadMetadataPort)? = nil,
         photoStartNetwork: (any PhotoSaveStartNetworkPort)? = nil,
         uploadStartNetwork: (any OriginalUploadStartNetworkPort)? = nil) {
        self.factory = factory
        self.backgroundFactory = backgroundFactory ?? (factory === ProductLibraryFactory.shared
            ? .shared : ProductBackgroundMediaFactory(library: factory))
        self.registrationFactory = registrationFactory
        self.statusSynchronizationFactory = statusSynchronizationFactory
        self.remoteInventoryFactory = remoteInventoryFactory
        self.uploadMetadataFactory = uploadMetadataFactory
        injectedPhotoNetwork = photoStartNetwork
        injectedUploadNetwork = uploadStartNetwork
    }

    func open() async {
        guard library == nil, !isOpening else { return }
        isOpening = true
        defer { isOpening = false }
        do {
            let services = try await factory.open()
            _ = await backgroundFactory.prepare()
            let adapter = AVOriginalPlayback(access: services.access)
            let player = OriginalPlaybackModel(playback: adapter)
            let media = ProductMediaTermination(store: services.store, access: services.access, player: adapter)
            mediaTermination = media
            playback = player
            let renditionFactory = ProductRenditionFactory(services: services, scopes: media.scopes)
            self.renditionFactory = renditionFactory
            let rendition = RenditionPlaybackModel(factory: renditionFactory, didChange: { [weak self] in
                await self?.library?.refresh()
            })
            renditionPlayback = rendition
            let playbackCommands = RenditionPlaybackLibraryCommands(base: OriginalPlaybackLibraryCommands(model: player),
                original: player, rendition: rendition)
            let photoNetwork = injectedPhotoNetwork ?? NativePhotoStartNetwork { [weak self] in
                Task { @MainActor in await self?.library?.refresh() }
            }
            let photoExecution = ProductPhotoSaveBatch(services: services, factory: renditionFactory,
                capture: backgroundFactory.captureAdmission)
            let photoBatches = PhotoSaveBatchCoordinator(store: services.store, execution: photoExecution,
                network: photoNetwork, capture: backgroundFactory.captureAdmission, didChange: { [weak self] in
                    await self?.library?.refresh()
                })
            photoSaveBatches = photoBatches
            let photoCommands = LibraryPhotoSaveCommands(coordinator: photoBatches, network: photoNetwork)
            let uploadNetwork = injectedUploadNetwork ?? NativeUploadStartNetwork(observation: photoNetwork)
            let uploadAcceptance = ProductOriginalUploadAcceptance.make(services: services, network: uploadNetwork,
                background: backgroundFactory)
            originalUploadAcceptance = uploadAcceptance
            let transferCommands = LibraryTransferCommands(acceptance: uploadAcceptance, network: uploadNetwork)
            self.transferCommands = transferCommands
            let capture = ProductCaptureFactory.make(services: services,
                mediaBoundary: ProductCaptureMediaBoundary(background: backgroundFactory, didChange: {
                    Task { await photoBatches.captureDidChange() }
                }), didSave: { [weak self] in
                await self?.library?.refresh()
            })
            self.capture = capture
            let admission: @MainActor @Sendable () -> Bool = { [weak capture] in
                guard let capture, !capture.isStarting, !capture.isSaving else { return false }
                if let phase = capture.capture?.phase, [.starting, .recording, .stopping].contains(phase) { return false }
                return true
            }
            let termination = ProductRemovalTermination(store: services.store, access: services.access, player: adapter,
                scopes: media.scopes, admission: admission, background: backgroundFactory)
            let execution = ProductRemovalExecution(access: services.access, admission: admission)
            let commands = LibraryRemovalCommands(base: PhotoAwareLibraryCommands(base: playbackCommands),
                reader: services.reader, store: services.store,
                discard: DiscardCoordinator(store: services.store, termination: termination, execution: execution),
                cleanup: CleanupCoordinator(store: services.store, termination: termination, execution: execution),
                execution: execution, termination: termination, admission: admission)
            let mediaRequestCommands = LibraryMediaRequestCommands(controls: backgroundFactory)
            self.mediaRequestCommands = mediaRequestCommands
            let registration: RegistrationCoordinator
            if let registrationFactory {
                registration = registrationFactory(services.store)
                // Preserve dependency-injected registration tests. A custom
                // registration never silently gains product Keychain access.
                statusSynchronization = statusSynchronizationFactory?(services, media)
                remoteInventory = remoteInventoryFactory?(services)
                uploadMetadata = uploadMetadataFactory?(services)
            } else {
                let vault = KeychainRegistrationVault()
                registration = RegistrationCoordinator(store: services.store, vault: vault,
                    remote: URLSessionRegistrationRemote(credentials: vault, store: services.store))
                let metadata = uploadMetadataFactory?(services) ?? ProductUploadMetadata(store: services.store,
                    credentials: vault, connection: { try await vault.connection(storeIdentity: $0) }, admission: admission,
                    didChange: { [weak self] in await self?.library?.refresh() })
                uploadMetadata = metadata
                statusSynchronization = statusSynchronizationFactory?(services, media)
                    ?? ProductStatusSynchronization(store: services.store, access: services.access, media: media,
                        credentials: vault, admission: admission, background: backgroundFactory, uploadMetadata: metadata)
                remoteInventory = remoteInventoryFactory?(services)
                    ?? RemoteInventoryCoordinator(store: services.store, admission: admission, remoteFactory: { connection, registration, identity in
                        URLSessionRemoteInventoryRemote(connection: connection, credentials: vault, store: services.store,
                            identity: identity, registration: registration)
                    })
            }
            let metadataCommands: LibraryUploadMetadataCommands?
            if let uploadMetadata { metadataCommands = LibraryUploadMetadataCommands(metadata: uploadMetadata) }
            else { metadataCommands = nil }
            library = LibraryModel(reader: services.reader, commands: commands, photos: services.photoReconciliation,
                removals: commands, remoteRenditions: playbackCommands, photoSaves: photoCommands,
                requestControls: mediaRequestCommands, transfers: transferCommands,
                uploadMetadata: metadataCommands)
            connection = ConnectionModel(coordinator: registration, statusSynchronization: statusSynchronization,
                remoteInventory: remoteInventory,
                didSynchronize: { [weak self] in await self?.library?.refresh() },
                synchronizationTargetDescription: { [weak self] original in
                    guard let item = self?.library?.snapshot?.items.first(where: {
                        $0.original.map { PublicationStoreBoundary.exact($0, original) } == true
                    }) else { return "撮影日時不明（この原本に対応する保存記録を確認できません）" }
                    return item.capturedAt == nil ? "撮影日時不明（撮影時の日時が記録されていません）" : item.captureDateDescription
                })
            openingIssue = nil
            await library?.refresh()
            await connection?.restore()
        } catch {
            openingIssue = "保存記録を開けません。既存の記録と原本は保持しています。再試行しても開けない場合は、保存領域の状態を確認してください。"
        }
    }

    func enteredBackground() async {
        await capture?.leaveCapture()
        await playback?.stop()
        await renditionPlayback?.stop()
        await exploration.stop()
    }

    func presentationEnded() async { await library?.refresh() }
}
