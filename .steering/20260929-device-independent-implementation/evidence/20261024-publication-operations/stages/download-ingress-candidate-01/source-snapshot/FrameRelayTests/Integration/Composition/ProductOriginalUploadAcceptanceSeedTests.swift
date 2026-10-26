import CryptoKit
import Darwin
import Foundation
import Testing
@testable import FrameRelay

/// Create-only technical fixture on the two explicitly assigned Simulators.
/// Saved classifications are typed synthetic inputs; the missing original is
/// never created. These tests use no Photos, Keychain, AV or network API.
@Suite(.serialized) @MainActor struct ProductOriginalUploadAcceptanceSeedTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_ORIGINAL_UPLOAD_SEED"] == "1"))
    func seedThreeSavedBindingsOnceWithoutAcceptingARequest() async throws {
        let context = try uploadSeedContext(mode: "SEED")
        try #require(context.phase == "seed")
        let input = try uploadSeedSource(), sourceBytes = try Data(contentsOf: URL(fileURLWithPath: input.path))
        try #require(try uploadSeedFile(URL(fileURLWithPath: input.path)) == input)
        let services = try await ProductLibraryFactory.shared.open()
        try await uploadSeedRequireEmpty(services, context: context)
        let sourceURL = services.run.url.appendingPathComponent("original-upload-source-" + context.nonce + ".mov")
        try sourceBytes.write(to: sourceURL, options: .withoutOverwriting)
        let sourceCopy = try uploadSeedFile(sourceURL)
        try #require(sourceCopy.sameContents(input))
        let registration = try await inventoryRegister(services.store)
        let identity = try #require(try await mediaSnapshot(services.store).storeIdentity)
        var targets: [UploadSeedTarget] = []
        for role in UploadSeedConstants.roles {
            let original = OriginalContent(capture: .init(rawValue: context.capture(role)), generation: .init(rawValue: 1),
                content: try input.content())
            let binding = try await uploadSeedBind(original, bytes: sourceBytes, present: role != "missing", services: services)
            let state = try #require(try await mediaOriginalSnapshot(services.store).originals.first {
                OriginalUploadAcceptanceValueValidation.exact($0.binding, binding)
            })
            let url = services.run.url.appendingPathComponent(binding.reference.rawValue + ".mov")
            let file: UploadSeedFile?
            if role == "missing" { try uploadSeedRequireAbsent(url); file = nil }
            else { file = try uploadSeedFile(url); try #require(file?.sameContents(input) == true) }
            targets.append(.init(role: role, binding: binding, bindingCommit: state.bindingCommit, file: file,
                reservation: try uploadSeedFile(services.run.url.appendingPathComponent(binding.reference.rawValue + ".reservation"))))
        }
        let sentinelURL = uploadSeedSentinel(services.run.url, nonce: context.nonce)
        try sourceBytes.write(to: sentinelURL, options: .withoutOverwriting)
        let backend = try await mediaSnapshot(services.store)
        let manifest = UploadSeedManifest(schema: "fr-original-upload-seed-v1", nonce: context.nonce,
            simulator: context.simulator, variant: context.variant, identity: identity, registration: registration,
            rootIdentity: try uploadSeedIdentity(services.run.url, directory: true), sourceInput: input, sourceCopy: sourceCopy,
            sentinel: try uploadSeedFile(sentinelURL), targets: targets, seedRevision: backend.revision)
        let file = services.run.url.appendingPathComponent(UploadSeedConstants.manifestLeaf)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: file, options: .withoutOverwriting)
        let manifestFile = try uploadSeedFile(file)
        try await uploadSeedVerify(services, manifest: manifest, stage: 0)
        try #require(try uploadSeedFile(file) == manifestFile)
        try #require(try uploadSeedFile(URL(fileURLWithPath: input.path)) == input)
        print("ORIGINAL_UPLOAD_SEED_MANIFEST " + (try uploadSeedJSON(manifestFile.signature)))
        print("ORIGINAL_UPLOAD_UI_EXPECTED " + (try uploadSeedJSON(uploadSeedExpected(manifest, file: manifestFile))))
        print("ORIGINAL_UPLOAD_SEED variant=\(context.variant) savedBindings=3 presentOriginals=2 initiallyMissingOriginals=1 parents=0 children=0 requests=0 attempts=0 sessions=0 tasks=0 readers=0 directPhotosKeychainNetworkSDK=none nativeWiFi=notObserved technicalClassificationOnly=true")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_ORIGINAL_UPLOAD_VERIFY"] == "1"))
    func verifyConsumedPrefixImmutableReceiptsEveryFileAndIndependentWriterReopen() async throws {
        let context = try uploadSeedContext(mode: "VERIFY"), root = try uploadSeedProductRoot()
        _ = try uploadSeedIdentity(root, directory: true)
        _ = try uploadSeedIdentity(root.appendingPathComponent(UploadSeedConstants.manifestLeaf))
        let services = try await ProductLibraryFactory.shared.open()
        let file = services.run.url.appendingPathComponent(UploadSeedConstants.manifestLeaf)
        let manifestFile = try uploadSeedFile(file)
        let expectedSignature = try uploadSeedExpectedSignature()
        try #require(manifestFile.signature == expectedSignature)
        let manifest = try JSONDecoder().decode(UploadSeedManifest.self, from: Data(contentsOf: file))
        try #require(manifest.nonce == context.nonce && manifest.simulator == context.simulator && manifest.variant == context.variant)
        let backend = try await mediaSnapshot(services.store)
        let stage = context.phase == "observe" ? backend.originalUploadAcceptances.count : try uploadSeedStage(context.phase)
        try await uploadSeedVerify(services, manifest: manifest, stage: stage)
        let reopened = try SQLiteRecordingStore(run: services.run, mode: .openExisting,
            supportedVerificationSchemas: ["fr-final-read-v1"])
        try #require(try await mediaSnapshot(reopened) == backend)
        let before = try await mediaOriginalSnapshot(services.store), after = try await mediaOriginalSnapshot(reopened)
        // A writer-instance epoch is ephemeral; every durable reader and binding
        // is compared without treating a new empty epoch as an SDK observation.
        try #require(before.revision == after.revision && before.originals == after.originals
            && before.logicalOriginals == after.logicalOriginals && before.removalBatches == after.removalBatches)
        let saved = await services.store.loadRecordings(), replay = await reopened.loadRecordings()
        let unfinished = await services.store.loadUnfinished(), replayUnfinished = await reopened.loadUnfinished()
        try #require(saved == replay && unfinished == replayUnfinished)
        for record in backend.originalUploadAcceptances {
            try #require(await services.store.lookupCommit(record.mutation) == .committed(record.commit))
            try #require(await reopened.lookupCommit(record.mutation) == .committed(record.commit))
        }
        try #require(try uploadSeedFile(file) == manifestFile)
        let summary = UploadSeedVerifySummary(schema: "fr-original-upload-verify-v1", nonce: context.nonce,
            simulator: context.simulator, variant: context.variant, requestedPhase: context.phase,
            actualPhase: UploadSeedConstants.stages[stage], storeUUID: manifest.identity.rawValue.uuidString,
            parents: backend.originalUploadAcceptances.map { record in
                .init(parent: record.plan.request.parent.rawValue, scope: record.plan.request.scope.rawValue,
                    previousRevision: record.commit.previousRevision, committedRevision: record.commit.committedRevision,
                    children: record.children.map { child in
                        .init(operation: child.target.operation.rawValue, capture: child.target.binding.original.capture.rawValue,
                            decision: uploadSeedDecision(child.decision))
                    })
            }, currentRequests: backend.requests.map { $0.operation.rawValue })
        print("ORIGINAL_UPLOAD_VERIFY " + (try uploadSeedJSON(summary)))
        print("ORIGINAL_UPLOAD_ACTUAL_PHASE " + UploadSeedConstants.stages[stage])
        print("ORIGINAL_UPLOAD_PRESERVED sourceInput=match sourceCopy=match originals2=match missingOriginal=neverCreated reservations3=match sentinel=match manifest=match rootAndFileInodes=match independentSQLite=equal attempts=0 sessions=0 tasks=0 logicalReaders=0 mediaReaders=0 directPhotosKeychainNetworkSDK=none nativeSDKInventory=notMeasured captureWaitExercise=none")
    }
}

nonisolated private enum UploadSeedConstants {
    static let manifestLeaf = "original-upload-acceptance-seed.json"
    static let stages = ["seed", "single", "multiple"]
    static let roles = ["a", "b", "missing"]
    static let sourceSuffix = "/fr-implementation-20261024-l0p333tn/request-control-synthetic-source.mov"
    static let sourceHash = "153d236030c76488aa11dfc797a107b7474999bae44f16bb81eaafad364e15c7"
    static let sourceBytes: UInt64 = 2_907_110
    static let sourceInode: UInt64 = 33_015_426
}
nonisolated private struct UploadSeedContext {
    let nonce: String; let simulator: String; let variant: String; let phase: String
    func capture(_ role: String) -> String { "ou-" + String(nonce.prefix(8)) + "-" + role }
}
nonisolated private struct UploadSeedSignature: Codable, Equatable {
    let sha256: String; let bytes: UInt64; let device: Int64; let inode: UInt64
}
nonisolated private struct UploadSeedFile: Codable, Equatable {
    let path: String; let bytes: UInt64; let sha256: String; let identity: TemporaryFileIdentity
    var signature: UploadSeedSignature { .init(sha256: sha256, bytes: bytes, device: identity.device, inode: identity.inode) }
    func content() throws -> ContentIdentity { try .init(byteCount: bytes, algorithm: "sha256", digest: sha256) }
    func sameContents(_ other: Self) -> Bool { bytes == other.bytes && sha256 == other.sha256 }
}
nonisolated private struct UploadSeedTarget: Codable {
    let role: String; let binding: OriginalBinding; let bindingCommit: OriginalStoreCommitReceipt
    let file: UploadSeedFile?; let reservation: UploadSeedFile
}
nonisolated private struct UploadSeedManifest: Codable {
    let schema: String; let nonce: String; let simulator: String; let variant: String
    let identity: RegistrationStoreIdentity; let registration: DeviceRegistration; let rootIdentity: TemporaryFileIdentity
    let sourceInput: UploadSeedFile; let sourceCopy: UploadSeedFile; let sentinel: UploadSeedFile
    let targets: [UploadSeedTarget]; let seedRevision: UInt64
}
nonisolated private struct UploadSeedUIExpected: Encodable {
    struct Target: Encodable { let role: String; let capture: String; let present: Bool }
    let schema: String; let nonce: String; let simulator: String; let variant: String; let storeUUID: String
    let manifest: UploadSeedSignature; let targets: [Target]
}
nonisolated private struct UploadSeedVerifySummary: Encodable {
    struct Parent: Encodable {
        struct Child: Encodable { let operation: String; let capture: String; let decision: String }
        let parent: String; let scope: String; let previousRevision: UInt64; let committedRevision: UInt64; let children: [Child]
    }
    let schema: String; let nonce: String; let simulator: String; let variant: String; let requestedPhase: String
    let actualPhase: String; let storeUUID: String; let parents: [Parent]; let currentRequests: [String]
}

nonisolated private func uploadSeedContext(mode: String) throws -> UploadSeedContext {
    let env = ProcessInfo.processInfo.environment, prefix = "FR_ORIGINAL_UPLOAD_"
    try #require(["SEED", "VERIFY", "UI"].filter { env[prefix + $0] == "1" } == [mode])
    let nonce = try #require(env[prefix + "NONCE"]), variant = try #require(env[prefix + "VARIANT"])
    let phase = try #require(env[prefix + "PHASE"])
    let requested = try #require(env[prefix + "SIMULATOR_UDID"].flatMap(UUID.init(uuidString:)))
    let actual = try #require(env["SIMULATOR_UDID"].flatMap(UUID.init(uuidString:)))
    #if targetEnvironment(simulator)
    try #require(requested == actual)
    try #require((actual.uuidString == "0B25C6C1-874F-469C-9E64-5147ECD8B0E3" && variant == "normal" && nonce == "fbfcf429-af96-4e4d-a4a5-bc91d5c42f90")
        || (actual.uuidString == "D2A95760-9D74-41FF-AF73-4C7CF94E0385" && variant == "max" && nonce == "6ad6cdcb-598f-4e30-b41c-68e0fbcc37b5"))
    try #require(UploadSeedConstants.stages.contains(phase) || ["all", "relaunch", "observe"].contains(phase))
    return .init(nonce: nonce, simulator: actual.uuidString, variant: variant, phase: phase)
    #else
    throw BackendContractError.unavailable
    #endif
}
nonisolated private func uploadSeedSource() throws -> UploadSeedFile {
    let env = ProcessInfo.processInfo.environment, prefix = "FR_ORIGINAL_UPLOAD_SOURCE_"
    let path = try #require(env[prefix + "PATH"])
    try #require(path.hasPrefix("/") && path.utf8.count <= 4096 && path.hasSuffix(UploadSeedConstants.sourceSuffix)
        && URL(fileURLWithPath: path).standardizedFileURL.path == path)
    let file = try uploadSeedFile(URL(fileURLWithPath: path))
    let bytes = try #require(env[prefix + "BYTES"].flatMap(UInt64.init))
    let inode = try #require(env[prefix + "INODE"].flatMap(UInt64.init))
    let device = try #require(env[prefix + "DEVICE"].flatMap(Int64.init))
    try #require(file.path == path && file.bytes == bytes && bytes == UploadSeedConstants.sourceBytes
        && file.sha256 == env[prefix + "SHA256"] && file.sha256 == UploadSeedConstants.sourceHash
        && inode == UploadSeedConstants.sourceInode && file.identity == TemporaryFileIdentity(device: device, inode: inode))
    var info = stat(); try #require(lstat(path, &info) == 0 && info.st_mode & 0o222 == 0)
    return file
}
nonisolated private func uploadSeedExpectedSignature() throws -> UploadSeedSignature {
    let env = ProcessInfo.processInfo.environment, prefix = "FR_ORIGINAL_UPLOAD_MANIFEST_"
    return .init(sha256: try #require(env[prefix + "SHA256"]), bytes: try #require(env[prefix + "BYTES"].flatMap(UInt64.init)),
        device: try #require(env[prefix + "DEVICE"].flatMap(Int64.init)), inode: try #require(env[prefix + "INODE"].flatMap(UInt64.init)))
}
nonisolated private func uploadSeedIdentity(_ url: URL, directory: Bool = false) throws -> TemporaryFileIdentity {
    var info = stat()
    try #require(lstat(url.path, &info) == 0 && info.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG))
    if !directory { try #require(info.st_nlink == 1) }
    return .init(device: Int64(info.st_dev), inode: UInt64(info.st_ino))
}
nonisolated private func uploadSeedFile(_ url: URL) throws -> UploadSeedFile {
    let url = url.standardizedFileURL, before = try uploadSeedIdentity(url)
    let size = try #require(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
    try #require(size >= 0 && size <= 64 * 1_024 * 1_024)
    let bytes = try Data(contentsOf: url)
    let after = try uploadSeedIdentity(url)
    try #require(bytes.count == size && after == before)
    return .init(path: url.path, bytes: UInt64(bytes.count),
        sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), identity: before)
}
nonisolated private func uploadSeedRequireAbsent(_ url: URL) throws {
    var info = stat(); let result = lstat(url.path, &info), observedError = errno
    try #require(result != 0 && observedError == ENOENT)
}
nonisolated private func uploadSeedJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}
nonisolated private func uploadSeedStage(_ phase: String) throws -> Int {
    if ["all", "relaunch"].contains(phase) { return 2 }
    return try #require(UploadSeedConstants.stages.firstIndex(of: phase))
}
nonisolated private func uploadSeedProductRoot() throws -> URL {
    let support = try #require(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
    return support.resolvingSymlinksInPath().appendingPathComponent("FrameRelayLibrary", isDirectory: true)
}
nonisolated private func uploadSeedSentinel(_ root: URL, nonce: String) -> URL {
    root.deletingLastPathComponent().appendingPathComponent("original-upload-external-" + nonce + ".mov")
}

@MainActor private func uploadSeedRequireEmpty(_ services: ProductLibraryServices, context: UploadSeedContext) async throws {
    let root = try uploadSeedProductRoot()
    try #require(services.run.url.standardizedFileURL == root.standardizedFileURL)
    try uploadSeedRequireAbsent(root.appendingPathComponent(UploadSeedConstants.manifestLeaf))
    try uploadSeedRequireAbsent(uploadSeedSentinel(root, nonce: context.nonce))
    let allowed: Set<String> = ["run.marker", "recordings.sqlite", "recordings.sqlite-wal", "recordings.sqlite-shm",
        "recordings.sqlite-journal", "recordings-sqlite.lock", "originals.lock"]
    try #require(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)).isSubset(of: allowed))
    let backend = try await mediaSnapshot(services.store), originals = try await mediaOriginalSnapshot(services.store)
    try #require(backend.revision == 0 && backend.storeIdentity == nil && backend.registrationIntents.isEmpty
        && backend.registrations.isEmpty && backend.requests.isEmpty && backend.originalUploadAcceptances.isEmpty)
    try uploadSeedRequireNoOtherOperations(backend)
    try #require(originals.revision == 0 && originals.originals.isEmpty && originals.logicalOriginals.isEmpty && originals.removalBatches.isEmpty)
    guard case .loaded(let saved) = await services.store.loadRecordings(),
          case .loaded(let unfinished) = await services.store.loadUnfinished(),
          case .loaded(let library) = await services.reader.loadLibrary() else { throw BackendContractError.unavailable }
    try #require(saved.revision == 0 && saved.recordings.isEmpty && unfinished.isEmpty && library.items.isEmpty
        && library.remoteItems.isEmpty && library.history.isEmpty && library.originalUploadAcceptances.isEmpty)
}

@MainActor private func uploadSeedBind(_ original: OriginalContent, bytes: Data, present: Bool,
    services: ProductLibraryServices) async throws -> OriginalBinding {
    let fixture = try CaptureFixture(clip: original.capture.rawValue)
    guard case .committed(let intent) = await services.store.execute(.commitIntent(fixture.token(1), expectedRevision: 0, fixture.intent)) else {
        throw BackendContractError.notCommitted
    }
    let destination = try await services.originals.reserve(original: fixture.intent.original)
    if present { try bytes.write(to: destination, options: .withoutOverwriting) }
    else { try uploadSeedRequireAbsent(destination) }
    var lifecycle = try RecordingSaveLifecycle(intent: fixture.intent, intentToken: fixture.token(1), revision: 0)
    try lifecycle.acceptIntentCommit(intent)
    try lifecycle.acceptRecordingEnd(context: fixture.context, evidence: fixture.end)
    try lifecycle.acceptFile(.init(context: fixture.context, original: fixture.intent.original,
        byteCount: original.content.byteCount, finalizedAt: fixture.time))
    // A synthetic saved classification is deliberately separate from the real
    // existence observation. No file is written or removed for the missing row.
    _ = try lifecycle.acceptInspection(fixture.inspection(), resultToken: fixture.token(4))
    let record = try #require(lifecycle.resultRecord); try #require(record.result == .saved)
    guard case .committed(let commit) = await services.store.execute(.commitResult(fixture.token(4), expectedRevision: 1, record)) else {
        throw BackendContractError.notCommitted
    }
    let binding = OriginalBinding(original: original, reference: fixture.intent.original, saveRecord: record, saveCommit: commit)
    _ = try await mediaOriginalCommit(services.store, .bind(binding))
    return binding
}

@MainActor private func uploadSeedVerify(_ services: ProductLibraryServices, manifest: UploadSeedManifest, stage: Int) async throws {
    try #require((0...2).contains(stage) && manifest.schema == "fr-original-upload-seed-v1")
    try #require(manifest.targets.map(\.role) == UploadSeedConstants.roles)
    try #require(try uploadSeedIdentity(services.run.url, directory: true) == manifest.rootIdentity)
    let backend = try await mediaSnapshot(services.store), originals = try await mediaOriginalSnapshot(services.store)
    try #require(backend.storeIdentity == manifest.identity && backend.registrations == [manifest.registration]
        && backend.registrationIntents.count == 1 && backend.originalUploadAcceptances.count == stage
        && backend.requests.count == min(stage, 2) && backend.revision == manifest.seedRevision + UInt64(stage))
    try #require(OriginalUploadAcceptanceValueValidation.exact(OriginalUploadAcceptanceBoundary.currentRegistration(backend), Optional(manifest.registration)))
    try uploadSeedRequireNoOtherOperations(backend)
    try #require(originals.originals.count == 3 && originals.logicalOriginals.count == 3 && originals.removalBatches.isEmpty)
    try #require(originals.logicalOriginals.allSatisfy {
        $0.readers.isEmpty && $0.mediaReaders.isEmpty && !$0.requiresMediaReconciliation && $0.mediaReconciliation == nil
            && $0.removal == nil && $0.resolvedRemoval == nil && $0.removalResolution == nil && $0.invalidation == nil
    })
    for target in manifest.targets {
        let state = try #require(originals.originals.first { OriginalUploadAcceptanceValueValidation.exact($0.binding, target.binding) })
        try #require(state.bindingCommit == target.bindingCommit && OriginalUploadAcceptanceValueValidation.savedBinding(target.binding))
    }
    var commands = Set<MediaOperationID>(), initialRequests: [MediaRequest] = []
    for (index, record) in backend.originalUploadAcceptances.enumerated() {
        let targets = index == 0 ? [manifest.targets[0]] : manifest.targets
        let expected: [OriginalUploadAcceptanceDecision] = index == 0 ? [.accepted]
            : [.notProcessed(.alreadyRequested), .accepted, .notProcessed(.fileMissing)]
        try #require(record.isCommitted && record.expectedStoreIdentity == manifest.identity
            && record.plan.request.storeIdentity == manifest.identity && record.plan.request.scope == (index == 0 ? .single : .multiple)
            && OriginalUploadAcceptanceValueValidation.exact(record.plan.request.registration, manifest.registration)
            && record.children.count == targets.count && record.children.map(\.decision) == expected
            && record.commit.previousRevision == manifest.seedRevision + UInt64(index)
            && record.commit.committedRevision == record.commit.previousRevision + 1)
        try #require(commands.insert(record.plan.request.parent).inserted && RemoteInventoryValidation.canonicalID(record.plan.request.parent.rawValue))
        for (child, target) in zip(record.children, targets) {
            try #require(OriginalUploadAcceptanceValueValidation.exact(child.target.binding, target.binding)
                && commands.insert(child.target.operation).inserted && RemoteInventoryValidation.canonicalID(child.target.operation.rawValue))
            try #require(child.presence == (target.role == "missing" ? .missing : .present(byteCount: target.binding.original.content.byteCount)))
            if let initial = child.initialRequest { initialRequests.append(initial) }
        }
        try #require(await services.store.lookupCommit(record.mutation) == .committed(record.commit))
    }
    try #require(commands.count == (stage == 2 ? 6 : stage * 2) && initialRequests.count == backend.requests.count)
    for expected in initialRequests {
        let current = try #require(backend.requests.first { MediaPersonControlTarget(expected).matches($0) })
        try #require(LibraryMediaRequestProjection.samePresentation(current, expected) && current.startCommitted
            && current.transport == .queued && current.intent == .running && current.waits.isEmpty && current.attempt == nil
            && current.session == nil && current.remote == .unknown && !current.hasReconciled && !current.canRun)
    }
    guard case .loaded(let saved) = await services.store.loadRecordings(),
          case .loaded(let unfinished) = await services.store.loadUnfinished(),
          case .loaded(let library) = await services.reader.loadLibrary() else { throw BackendContractError.unavailable }
    try #require(saved.revision == backend.revision && originals.revision == backend.revision && library.revision == backend.revision
        && saved.recordings.count == 3 && unfinished.isEmpty && library.items.count == 3 && library.history.isEmpty
        && library.remoteItems.isEmpty && library.mediaRequests.count == backend.requests.count && library.personControls.isEmpty
        && library.originalUploadAcceptances == backend.originalUploadAcceptances)
    for target in manifest.targets {
        let row = try #require(saved.recordings.first { $0.intent.context.capture == target.binding.original.capture })
        let item = try #require(library.items.first { $0.id == target.binding.original.capture })
        try #require(row.result == target.binding.saveRecord && row.resultCommit == target.binding.saveCommit
            && item.uploadCandidateBinding == target.binding && item.operationResults.isEmpty && !item.isDiscardHistory)
        try #require(item.file == (target.role == "missing" ? .absent : .present(byteCount: target.binding.original.content.byteCount)))
        try #require(item.originalUploadAcceptances.count == (target.role == "a" ? stage : stage == 2 ? 1 : 0))
    }
    try uploadSeedVerifyFiles(services.run.url, manifest: manifest)
}

nonisolated private func uploadSeedRequireNoOtherOperations(_ backend: BackendStoreSnapshot) throws {
    try #require(backend.batches.isEmpty && backend.verifications.isEmpty && backend.confirmations.isEmpty
        && backend.invalidations.isEmpty && backend.outbox.isEmpty && backend.publications.isEmpty && backend.confirmationStates.isEmpty
        && backend.deliveries.isEmpty && backend.distributionObservations.isEmpty && backend.temporaryMedia.isEmpty
        && backend.photoRegistrations.isEmpty && backend.photoSaveBatches.isEmpty && backend.backgroundTasks.isEmpty
        && backend.remoteInventory.isEmpty && backend.publicationManifests.isEmpty && backend.personControls.isEmpty)
}
nonisolated private func uploadSeedVerifyFiles(_ root: URL, manifest: UploadSeedManifest) throws {
    let oldRoot = URL(fileURLWithPath: manifest.sourceCopy.path).deletingLastPathComponent().standardizedFileURL
    let root = root.standardizedFileURL
    let oldContainer = oldRoot.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let container = root.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    // Follow only an App container UUID relocation, retaining root and every
    // file inode. Never rewrite paths in the immutable manifest or reseed it.
    try #require(Array(oldRoot.pathComponents.suffix(3)) == ["Library", "Application Support", "FrameRelayLibrary"]
        && Array(root.pathComponents.suffix(3)) == ["Library", "Application Support", "FrameRelayLibrary"]
        && oldContainer.deletingLastPathComponent() == container.deletingLastPathComponent()
        && container.deletingLastPathComponent().lastPathComponent == "Application"
        && UUID(uuidString: oldContainer.lastPathComponent) != nil && UUID(uuidString: container.lastPathComponent) != nil)
    try #require(try uploadSeedFile(URL(fileURLWithPath: manifest.sourceInput.path)) == manifest.sourceInput)
    try #require(manifest.sourceInput.path.hasSuffix(UploadSeedConstants.sourceSuffix) && manifest.sourceInput.sha256 == UploadSeedConstants.sourceHash
        && manifest.sourceInput.bytes == UploadSeedConstants.sourceBytes && manifest.sourceInput.identity.inode == UploadSeedConstants.sourceInode)
    var inputInfo = stat()
    try #require(lstat(manifest.sourceInput.path, &inputInfo) == 0 && inputInfo.st_mode & 0o222 == 0)
    let sourceLeaf = "original-upload-source-" + manifest.nonce + ".mov"
    try #require(manifest.sourceCopy.path == oldRoot.appendingPathComponent(sourceLeaf).path
        && manifest.sentinel.path == uploadSeedSentinel(oldRoot, nonce: manifest.nonce).path)
    var files: [(UploadSeedFile, URL)] = [(manifest.sourceCopy, root.appendingPathComponent(sourceLeaf)),
        (manifest.sentinel, uploadSeedSentinel(root, nonce: manifest.nonce))]
    for target in manifest.targets {
        let leaf = target.binding.reference.rawValue
        try #require(target.reservation.path == oldRoot.appendingPathComponent(leaf + ".reservation").path && target.reservation.bytes == 0)
        files.append((target.reservation, root.appendingPathComponent(leaf + ".reservation")))
        if let file = target.file {
            let content = try file.content()
            try #require(target.role != "missing" && file.path == oldRoot.appendingPathComponent(leaf + ".mov").path
                && file.sameContents(manifest.sourceInput) && content == target.binding.original.content)
            files.append((file, root.appendingPathComponent(leaf + ".mov")))
        } else { try #require(target.role == "missing"); try uploadSeedRequireAbsent(root.appendingPathComponent(leaf + ".mov")) }
    }
    for (expected, currentURL) in files {
        let actual = try uploadSeedFile(currentURL)
        try #require(actual.path == currentURL.path && actual.signature == expected.signature)
    }
    try #require(manifest.sourceCopy.sameContents(manifest.sourceInput) && manifest.sentinel.sameContents(manifest.sourceInput))
}
nonisolated private func uploadSeedDecision(_ decision: OriginalUploadAcceptanceDecision) -> String {
    switch decision { case .accepted: "accepted"; case .notProcessed(let reason): "notProcessed." + reason.rawValue }
}
nonisolated private func uploadSeedExpected(_ manifest: UploadSeedManifest, file: UploadSeedFile) -> UploadSeedUIExpected {
    .init(schema: "fr-original-upload-ui-v1", nonce: manifest.nonce, simulator: manifest.simulator, variant: manifest.variant,
        storeUUID: manifest.identity.rawValue.uuidString, manifest: file.signature,
        targets: manifest.targets.map { .init(role: $0.role, capture: $0.binding.original.capture.rawValue, present: $0.file != nil) })
}
