import Darwin
import Foundation

nonisolated struct ProductLibraryServices: Sendable {
    let run: ExplorationRunDirectory
    let store: SQLiteRecordingStore
    let originals: ManagedOriginalStore
    let access: ManagedOriginalAccess
    let reader: LibraryStoreReader
    let photoReconciliation: LibraryPhotoReconciliation
}

/// App-lifetime owner of the one writer. The directory validator is shared with
/// exploration, but the fixed product root has no ticket or per-run dependency.
actor ProductLibraryFactory {
    static let shared = ProductLibraryFactory()
    private let supportDirectory: URL?
    private let photoLibrary: any PhotoLibraryPort
    private var services: ProductLibraryServices?

    init(supportDirectory: URL? = nil, photoLibrary: any PhotoLibraryPort = NativePhotoLibrary()) {
        self.supportDirectory = supportDirectory
        self.photoLibrary = photoLibrary
    }

    func open() throws -> ProductLibraryServices {
        if let services { return services }
        let support: URL
        if let supportDirectory {
            support = supportDirectory.standardizedFileURL
            try ExplorationRunDirectory.requireDirectory(support)
        } else {
            guard let location = FileManager.default.urls(for: .applicationSupportDirectory,
                                                         in: .userDomainMask).first else {
                throw ExplorationStorageError.inaccessible
            }
            // Resolve the OS-owned container prefix only, before app-owned paths.
            support = location.resolvingSymlinksInPath().standardizedFileURL
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            try ExplorationRunDirectory.requireDirectory(support)
        }
        let root = support.appendingPathComponent("FrameRelayLibrary", isDirectory: true)
        var info = stat()
        let exists = lstat(root.path, &info) == 0
        if !exists, errno != ENOENT { throw ExplorationStorageError.inaccessible }
        let mode: ExplorationStoreOpenMode = exists ? .openExisting : .createNew
        let run = try exists ? ExplorationRunDirectory.openExisting(at: root)
                            : ExplorationRunDirectory.createNew(at: root)
        // Never turn an invalid/missing existing database into an empty library.
        let store = try SQLiteRecordingStore(run: run, mode: mode, supportedVerificationSchemas: ["fr-final-read-v1"])
        let originals = ManagedOriginalStore(run: run)
        let access = ManagedOriginalAccess(store: store, originals: originals)
        let result = ProductLibraryServices(run: run, store: store, originals: originals, access: access,
            reader: LibraryStoreReader(store: store, files: originals),
            photoReconciliation: LibraryPhotoReconciliation(store: store, library: photoLibrary))
        services = result
        return result
    }
}
