import Foundation
import Observation

@MainActor @Observable final class ProductComposition {
    private let factory: ProductLibraryFactory
    private let backgroundFactory: ProductBackgroundMediaFactory
    private let registrationFactory: @Sendable (any MediaOperationStorePort) -> RegistrationCoordinator
    private(set) var library: LibraryModel?
    private(set) var playback: OriginalPlaybackModel?
    private(set) var connection: ConnectionModel?
    private(set) var capture: ProductCaptureCoordinator?
    private(set) var mediaTermination: ProductMediaTermination?
    private(set) var isOpening = false
    private(set) var openingIssue: String?
    let exploration = ExplorationComposition.makeModel()

    init(factory: ProductLibraryFactory = .shared,
         backgroundFactory: ProductBackgroundMediaFactory? = nil,
         registrationFactory: @escaping @Sendable (any MediaOperationStorePort) -> RegistrationCoordinator = { store in
             let vault = KeychainRegistrationVault()
             return RegistrationCoordinator(store: store, vault: vault, remote: URLSessionRegistrationRemote(credentials: vault, store: store))
         }) {
        self.factory = factory
        self.backgroundFactory = backgroundFactory ?? (factory === ProductLibraryFactory.shared
            ? .shared : ProductBackgroundMediaFactory(library: factory))
        self.registrationFactory = registrationFactory
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
            let capture = ProductCaptureFactory.make(services: services,
                mediaBoundary: ProductCaptureMediaBoundary(background: backgroundFactory), didSave: { [weak self] in
                await self?.library?.refresh()
            })
            self.capture = capture
            let admission: @MainActor @Sendable () -> Bool = { [weak capture] in
                guard let capture, !capture.isStarting, !capture.isSaving else { return false }
                if let phase = capture.capture?.phase, [.starting, .recording, .stopping].contains(phase) { return false }
                return true
            }
            let termination = ProductRemovalTermination(store: services.store, access: services.access, player: adapter,
                scopes: media.scopes, admission: admission)
            let execution = ProductRemovalExecution(access: services.access, admission: admission)
            let commands = LibraryRemovalCommands(base: PhotoAwareLibraryCommands(base: OriginalPlaybackLibraryCommands(model: player)),
                reader: services.reader, store: services.store,
                discard: DiscardCoordinator(store: services.store, termination: termination, execution: execution),
                execution: execution, termination: termination, admission: admission)
            library = LibraryModel(reader: services.reader, commands: commands, photos: services.photoReconciliation, removals: commands)
            connection = ConnectionModel(coordinator: registrationFactory(services.store))
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
        await exploration.stop()
    }

    func presentationEnded() async { await library?.refresh() }
}
