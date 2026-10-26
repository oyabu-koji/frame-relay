/// Product wiring has only the common writer, stat observer and initial path
/// observation. No credential, source, remote or SDK factory belongs here.
nonisolated enum ProductOriginalUploadAcceptance {
    static func make(services: ProductLibraryServices, network: any OriginalUploadStartNetworkPort,
        background: ProductBackgroundMediaFactory) -> OriginalUploadAcceptanceCoordinator {
        OriginalUploadAcceptanceCoordinator(store: services.store, files: services.originals, network: network,
            didRecord: { await background.synchronizeCapture() })
    }
}
