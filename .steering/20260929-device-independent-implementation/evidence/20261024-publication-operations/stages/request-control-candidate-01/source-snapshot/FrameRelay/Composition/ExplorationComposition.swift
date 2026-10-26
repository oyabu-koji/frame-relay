import AVFoundation
import Foundation

@MainActor
enum ExplorationComposition {
    static func makeModel() -> ExplorationCoordinator {
        let reader = ExplorationTicketReader()
        return ExplorationCoordinator(factory: LiveExplorationFactory(), ticketLoader: { try await reader.read($0) })
    }
}

actor LiveExplorationFactory: ExplorationFactoryPort {
    func runtime() throws -> ExplorationRuntime {
        #if targetEnvironment(simulator)
        return .simulator
        #else
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let os = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        let home = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath()
        let values = try home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values.volumeAvailableCapacityForImportantUsage, available > 0 else {
            throw ExplorationIssue.deviceFactsMissing
        }
        return .physicalDevice(osVersion: os, availableBytes: UInt64(available))
        #endif
    }

    func makeServices(ticket: ExplorationTicket, output: ExplorationOutputCandidate,
                      store: ExplorationStoreCandidate) async throws -> ExplorationServices {
        let issues = ExplorationGate.issues(ticket: ticket, output: output, store: store, runtime: try runtime())
        if let issue = issues.first { throw issue }
        guard await permission(for: .video), await permission(for: .audio) else { throw ExplorationIssue.permissionDenied }
        let recheck = ExplorationGate.issues(ticket: ticket, output: output, store: store, runtime: try runtime())
        if let issue = recheck.first { throw issue }
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ExplorationIssue.storageUnavailable
        }
        // All paths are application-owned. The imported ticket contains references only.
        let parent = support.appendingPathComponent("CaptureExploration", isDirectory: true).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let sessionID = UUID().uuidString
        let run = try ExplorationRunDirectory.createNew(at: parent.appendingPathComponent(sessionID, isDirectory: true))
        let originals = ManagedOriginalStore(run: run)
        let recordingStore: any RecordingStorePort
        switch store {
        case .atomicFile: recordingStore = try AtomicFileRecordingStore(run: run, mode: .createNew)
        case .sqlite: recordingStore = try SQLiteRecordingStore(run: run, mode: .createNew)
        }
        return ExplorationServices(generation: .init(session: .init(rawValue: sessionID), settings: 1),
                                   device: NativeExplorationCapture(candidate: output, originals: originals),
                                   store: recordingStore, inspection: AVOriginalInspectionAdapter(originals: originals),
                                   diagnostics: try ExplorationDiagnosticsStore(run: run, mode: .createNew))
    }

    private func permission(for media: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: media) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: media)
        default: return false
        }
    }

    func nextCaptureIdentity(generation: CaptureGeneration) -> (CaptureContext, CaptureOperationID, CaptureOriginalReference) {
        let id = UUID().uuidString
        return (.init(generation: generation, capture: .init(rawValue: id)),
                .init(rawValue: "rec-\(id)"), .init(rawValue: "original-\(id)"))
    }

    func currentTime() -> CaptureTimeObservation { ExplorationCaptureValues.now() }
}

actor ExplorationTicketReader {
    func read(_ selectedURL: URL) throws -> Data {
        let accessing = selectedURL.startAccessingSecurityScopedResource()
        defer { if accessing { selectedURL.stopAccessingSecurityScopedResource() } }
        let values = try selectedURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        // An import transport bound, not a recording/quality parameter.
        guard values.isRegularFile == true, let size = values.fileSize, (1...65_536).contains(size) else {
            throw ExplorationIssue.ticketReadFailed
        }
        let bytes = try Data(contentsOf: selectedURL)
        guard bytes.count <= 65_536 else { throw ExplorationIssue.ticketReadFailed }
        return bytes
    }
}
