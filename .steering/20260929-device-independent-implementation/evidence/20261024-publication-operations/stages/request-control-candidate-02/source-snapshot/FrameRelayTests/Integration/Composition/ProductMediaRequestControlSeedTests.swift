import CryptoKit
import Darwin
import Foundation
import Testing
@testable import FrameRelay

/// One create-only technical fixture per dedicated Simulator. These are typed
/// pre-SDK inputs, not camera/Log, formal publication, external-result or actual
/// transport producer evidence. No Photos, Keychain, AV or network API is used.
@Suite(.serialized) @MainActor struct ProductMediaRequestControlSeedTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_MEDIA_REQUEST_CONTROL_SEED"] == "1"))
    func seedFivePreSDKRequestsOnceOnDedicatedEmptyProductRoot() async throws {
        let context = try requestControlSeedContext(mode: "SEED")
        try #require(context.phase == "seed")
        let input = try requestControlSourceInput()
        let content = try input.mediaContent()
        let sourceBytes = try Data(contentsOf: URL(fileURLWithPath: input.path))
        try #require(try requestControlFile(URL(fileURLWithPath: input.path)) == input)
        let services = try await ProductLibraryFactory.shared.open()
        try await requestControlRequireEmptyRoot(services, nonce: context.nonce)
        let sourceURL = services.run.url.appendingPathComponent("request-control-source-" + context.nonce + ".mov")
        try sourceBytes.write(to: sourceURL, options: .withoutOverwriting)
        let sourceCopy = try requestControlFile(sourceURL)
        try #require(sourceCopy.sameContents(input))

        let registration = try await inventoryRegister(services.store)
        let identity = try #require(try await mediaSnapshot(services.store).storeIdentity)
        let local = OriginalContent(capture: .init(rawValue: context.capture("local")),
            generation: .init(rawValue: 1), content: content)
        let binding = try await requestControlBindTechnicalSavedOriginal(local, bytes: sourceBytes, services: services)
        let bindingState = try #require(try await mediaOriginalSnapshot(services.store).originals.first)
        let originalFile = try requestControlFile(try await services.originals.existingURL(for: binding.reference))
        let reservation = try requestControlFile(services.run.url.appendingPathComponent(binding.reference.rawValue + ".reservation"))
        var targets: [RequestControlSeedTarget] = []
        var publications: [PublishedRenditionObservation] = []
        var remoteOriginals: [OriginalContent] = []
        for role in ["local", "waiting", "cancelled", "completed", "ended"] {
            let target: MediaTarget
            if role == "local" { target = .original(local) }
            else {
                let original = OriginalContent(capture: .init(rawValue: context.capture(role)),
                    generation: .init(rawValue: 1), content: content)
                let rendition = RenditionIdentity(original: original, inputLogIdentity: "synthetic-not-log",
                    transformAssetIdentity: "no-formal-proof", transformAssetVersion: "technical-controls-v1",
                    outputConfigurationIdentity: "unacquired-technical-movie", conversionVersion: "fixture-only",
                    rendition: .init(rawValue: UUID().uuidString.lowercased()), deliveryContent: content,
                    publicationGeneration: .init(rawValue: 1))
                let publication = mediaPublication(rendition, registration: registration.server.registration)
                _ = try await mediaCommit(services.store, .publication(publication))
                publications.append(publication)
                remoteOriginals.append(original)
                target = .rendition(rendition)
            }
            let revision = try await mediaSnapshot(services.store).revision
            let request = MediaRequest(operation: .init(rawValue: UUID().uuidString.lowercased()), target: target,
                purpose: role == "local" ? .upload : role == "ended" ? .playback : .download,
                registration: registration.server.registration, expectedStartRevision: revision)
            _ = try await mediaCommit(services.store, .request(command: request.operation, value: request))
            if role == "waiting" {
                for wait in [MediaWaitReason.wiFiUnavailable, .recording, .authentication] {
                    try await requestControlTechnicalTransition(request, .wait(wait, active: true), services: services)
                }
            } else if role == "cancelled" {
                try await requestControlTechnicalTransition(request, .cancel, services: services)
            } else if role == "completed" {
                // Explicit injected external observation; never a fake SDK terminal.
                let observation = RemoteOperationResult(context: .init(operation: request.operation,
                    registration: request.registration, target: request.target, session: nil),
                    observation: .init(rawValue: 1), result: .succeeded(.init(rawValue: "technical-external-result-" + context.nonce)))
                try await requestControlTechnicalTransition(request, .reconciled(observation), services: services)
            } else if role == "ended" {
                try await requestControlTechnicalTransition(request, .endPlayback, services: services)
            }
            let stored = try #require(try await mediaSnapshot(services.store).requests.first { $0.operation == request.operation })
            targets.append(.init(role: role, request: stored))
        }
        let catalog = inventoryObservation(identity, registration, originals: remoteOriginals)
        _ = try await inventoryCommit(services.store, catalog)
        let sentinelURL = requestControlSentinel(services, nonce: context.nonce)
        try sourceBytes.write(to: sentinelURL, options: .withoutOverwriting)
        let backend = try await mediaSnapshot(services.store)
        let manifest = RequestControlSeedManifest(schema: "fr-s28-media-request-control-seed-v1",
            nonce: context.nonce, simulator: context.simulator, variant: context.variant, identity: identity,
            registration: registration, rootIdentity: try requestControlIdentity(services.run.url, directory: true),
            sourceInput: input, sourceCopy: sourceCopy, binding: binding, bindingCommit: bindingState.bindingCommit,
            originalFile: originalFile, reservation: reservation, sentinel: try requestControlFile(sentinelURL),
            targets: targets, publications: publications, catalog: catalog, seedRevision: backend.revision)
        let file = services.run.url.appendingPathComponent(RequestControlSeedConstants.manifestLeaf)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: file, options: .withoutOverwriting)
        let manifestFile = try requestControlFile(file)
        try await requestControlVerify(services, manifest: manifest, expectedStage: 0)
        try #require(try requestControlFile(file) == manifestFile)
        try #require(try requestControlFile(URL(fileURLWithPath: input.path)) == input)
        print("S28_MEDIA_REQUEST_CONTROL_MANIFEST " + (try requestControlJSON(manifestFile.signature)))
        print("S28_MEDIA_REQUEST_CONTROL_EXPECTED " + (try requestControlJSON(requestControlUIExpected(manifest, manifestFile: manifestFile))))
        print("S28_MEDIA_REQUEST_CONTROL_SEED variant=\(context.variant) requests=5 localOriginals=1 remoteOriginals=4 parents=0 children=0 attempts=0 sessions=0 tasks=0 readers=0 fixtureDirectMediaActions=none nativeSDKInventory=notMeasured technicalFixtureOnly=true")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["FR_MEDIA_REQUEST_CONTROL_VERIFY"] == "1"))
    func verifyConsumedPersonControlPrefixFilesAndIndependentSQLiteReopen() async throws {
        let context = try requestControlSeedContext(mode: "VERIFY")
        let expectedRoot = try requestControlProductRoot()
        _ = try requestControlIdentity(expectedRoot, directory: true)
        _ = try requestControlIdentity(expectedRoot.appendingPathComponent(RequestControlSeedConstants.manifestLeaf))
        let services = try await ProductLibraryFactory.shared.open()
        let file = services.run.url.appendingPathComponent(RequestControlSeedConstants.manifestLeaf)
        let manifestFile = try requestControlFile(file)
        let expectedSignature = try requestControlExpectedManifestSignature()
        try #require(manifestFile.signature == expectedSignature)
        let manifest = try JSONDecoder().decode(RequestControlSeedManifest.self, from: Data(contentsOf: file))
        try #require(manifest.nonce == context.nonce && manifest.simulator == context.simulator && manifest.variant == context.variant)
        let backend = try await mediaSnapshot(services.store)
        let stage = context.phase == "observe" ? backend.personControls.count : try requestControlStage(context.phase)
        try await requestControlVerify(services, manifest: manifest, expectedStage: stage)
        let reopened = try SQLiteRecordingStore(run: services.run, mode: .openExisting,
            supportedVerificationSchemas: ["fr-final-read-v1"])
        try #require(try await mediaSnapshot(reopened) == backend)
        let before = try await mediaOriginalSnapshot(services.store), replay = try await mediaOriginalSnapshot(reopened)
        // The writer-instance epoch is ephemeral. Durable original projections
        // and every actual reader are compared independently of that epoch.
        try #require(before.revision == replay.revision && before.originals == replay.originals
            && before.logicalOriginals == replay.logicalOriginals && before.removalBatches == replay.removalBatches)
        let currentRecordings = await services.store.loadRecordings(), replayRecordings = await reopened.loadRecordings()
        let currentUnfinished = await services.store.loadUnfinished(), replayUnfinished = await reopened.loadUnfinished()
        try #require(currentRecordings == replayRecordings && currentUnfinished == replayUnfinished)
        for record in backend.personControls {
            try #require(await services.store.lookupCommit(record.mutation) == .committed(record.commit))
            try #require(await reopened.lookupCommit(record.mutation) == .committed(record.commit))
        }
        try #require(try requestControlFile(file) == manifestFile)
        let plans = backend.personControls.map { record in
            RequestControlVerifiedPlan(parent: record.plan.parent.rawValue, scope: record.plan.scope.rawValue,
                action: record.plan.action.rawValue, children: record.children.map { child in
                    .init(command: child.child.command.rawValue, operation: child.child.target.operation.rawValue,
                        decision: requestControlDecisionText(child.decision))
                })
        }
        let summary = RequestControlVerifySummary(schema: "fr-s28-media-request-control-verify-v1", nonce: context.nonce,
            simulator: context.simulator, variant: context.variant, requestedPhase: context.phase,
            actualPhase: RequestControlSeedConstants.phases[stage], parents: plans.count,
            children: plans.reduce(0) { $0 + $1.children.count }, plans: plans)
        print("S28_MEDIA_REQUEST_CONTROL_VERIFY " + (try requestControlJSON(summary)))
        print("S28_MEDIA_REQUEST_CONTROL_ACTUAL_PHASE " + RequestControlSeedConstants.phases[stage])
        print("S28_MEDIA_REQUEST_CONTROL_PRESERVED sourceInput=match sourceCopy=match original=match reservation=match sentinel=match manifest=match hashAndInode=match independentSQLite=equal attempts=0 sessions=0 tasks=0 logicalReaders=0 mediaReaders=0 fixtureDirectMediaActions=none nativeSDKInventory=notMeasured")
    }
}

nonisolated private enum RequestControlSeedConstants {
    static let manifestLeaf = "s28-media-request-control-seed.json"
    static let phases = ["seed", "localPause", "localResume", "remotePause", "remoteResume", "allPause", "localCancel"]
}
nonisolated private struct RequestControlSeedContext {
    let nonce: String
    let simulator: String
    let variant: String
    let phase: String
    func capture(_ role: String) -> String { "rc-" + String(nonce.prefix(8)) + "-" + role }
}
nonisolated private struct RequestControlFileSignature: Codable, Equatable {
    let sha256: String
    let bytes: UInt64
    let device: Int64
    let inode: UInt64
}
nonisolated private struct RequestControlFile: Codable, Equatable {
    let path: String
    let byteCount: UInt64
    let sha256: String
    let identity: TemporaryFileIdentity
    var signature: RequestControlFileSignature {
        .init(sha256: sha256, bytes: byteCount, device: identity.device, inode: identity.inode)
    }
    func mediaContent() throws -> ContentIdentity { try .init(byteCount: byteCount, algorithm: "sha256", digest: sha256) }
    func sameContents(_ other: Self) -> Bool { byteCount == other.byteCount && sha256 == other.sha256 }
}
nonisolated private struct RequestControlSeedTarget: Codable {
    let role: String
    let request: MediaRequest
}
nonisolated private struct RequestControlSeedManifest: Codable {
    let schema: String
    let nonce: String
    let simulator: String
    let variant: String
    let identity: RegistrationStoreIdentity
    let registration: DeviceRegistration
    let rootIdentity: TemporaryFileIdentity
    let sourceInput: RequestControlFile
    let sourceCopy: RequestControlFile
    let binding: OriginalBinding
    let bindingCommit: OriginalStoreCommitReceipt
    let originalFile: RequestControlFile
    let reservation: RequestControlFile
    let sentinel: RequestControlFile
    let targets: [RequestControlSeedTarget]
    let publications: [PublishedRenditionObservation]
    let catalog: RemoteInventoryObservation
    let seedRevision: UInt64
}
nonisolated private struct RequestControlUIExpected: Encodable {
    struct Target: Encodable {
        let role: String
        let capture: String
        let operation: String
        let requestToken: String
        let rendition: String?
        let remoteToken: String?
        let startRevision: UInt64
    }
    let schema: String
    let nonce: String
    let simulator: String
    let variant: String
    let storeUUID: String
    let manifest: RequestControlFileSignature
    let targets: [Target]
}
nonisolated private struct RequestControlVerifiedPlan: Encodable {
    struct Child: Encodable { let command: String; let operation: String; let decision: String }
    let parent: String
    let scope: String
    let action: String
    let children: [Child]
}
nonisolated private struct RequestControlVerifySummary: Encodable {
    let schema: String
    let nonce: String
    let simulator: String
    let variant: String
    let requestedPhase: String
    let actualPhase: String
    let parents: Int
    let children: Int
    let plans: [RequestControlVerifiedPlan]
}

nonisolated private func requestControlSeedContext(mode: String) throws -> RequestControlSeedContext {
    let env = ProcessInfo.processInfo.environment, prefix = "FR_MEDIA_REQUEST_CONTROL_"
    try #require(["SEED", "VERIFY", "UI"].filter { env[prefix + $0] == "1" } == [mode])
    let nonce = try #require(env[prefix + "NONCE"]), variant = try #require(env[prefix + "VARIANT"])
    let phase = try #require(env[prefix + "PHASE"])
    let requested = try #require(env[prefix + "SIMULATOR_UDID"].flatMap(UUID.init(uuidString:)))
    let actual = try #require(env["SIMULATOR_UDID"].flatMap(UUID.init(uuidString:)))
    #if targetEnvironment(simulator)
    try #require(requested == actual)
    try #require((actual.uuidString == "DF5792DA-974B-484E-AABE-CEB35BE81671" && variant == "normal" && nonce == "2a348f92-1908-4f90-b8ee-022db9af9292")
        || (actual.uuidString == "DB784948-3DA5-454A-9526-29C37B22AB84" && variant == "max" && nonce == "6debb933-100f-4327-835f-5415010a47e7"))
    try #require(RequestControlSeedConstants.phases.contains(phase) || ["all", "relaunch", "observe"].contains(phase))
    return .init(nonce: nonce, simulator: actual.uuidString, variant: variant, phase: phase)
    #else
    throw BackendContractError.unavailable
    #endif
}
nonisolated private func requestControlSourceInput() throws -> RequestControlFile {
    let env = ProcessInfo.processInfo.environment, prefix = "FR_MEDIA_REQUEST_CONTROL_SOURCE_"
    let path = try #require(env[prefix + "PATH"])
    try #require(path.hasPrefix("/") && path.utf8.count <= 4096)
    let file = try requestControlFile(URL(fileURLWithPath: path))
    let count = try #require(env[prefix + "BYTES"].flatMap(UInt64.init))
    let device = try #require(env[prefix + "DEVICE"].flatMap(Int64.init))
    let inode = try #require(env[prefix + "INODE"].flatMap(UInt64.init))
    try #require(count > 0 && file.path == path && file.byteCount == count && file.sha256 == env[prefix + "SHA256"]
        && file.identity == TemporaryFileIdentity(device: device, inode: inode))
    var info = stat()
    try #require(lstat(path, &info) == 0 && info.st_mode & 0o222 == 0)
    return file
}
nonisolated private func requestControlExpectedManifestSignature() throws -> RequestControlFileSignature {
    let env = ProcessInfo.processInfo.environment, prefix = "FR_MEDIA_REQUEST_CONTROL_MANIFEST_"
    return .init(sha256: try #require(env[prefix + "SHA256"]), bytes: try #require(env[prefix + "BYTES"].flatMap(UInt64.init)),
        device: try #require(env[prefix + "DEVICE"].flatMap(Int64.init)), inode: try #require(env[prefix + "INODE"].flatMap(UInt64.init)))
}
nonisolated private func requestControlIdentity(_ url: URL, directory: Bool = false) throws -> TemporaryFileIdentity {
    var info = stat()
    try #require(lstat(url.path, &info) == 0 && info.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG))
    return .init(device: Int64(info.st_dev), inode: UInt64(info.st_ino))
}
nonisolated private func requestControlFile(_ url: URL) throws -> RequestControlFile {
    let normalized = url.standardizedFileURL
    let identity = try requestControlIdentity(normalized)
    let size = try #require(try normalized.resourceValues(forKeys: [.fileSizeKey]).fileSize)
    try #require(size >= 0 && size <= 64 * 1_024 * 1_024)
    let bytes = try Data(contentsOf: normalized)
    let after = try requestControlIdentity(normalized)
    try #require(bytes.count == size && after == identity)
    let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    return .init(path: normalized.path, byteCount: UInt64(bytes.count), sha256: digest, identity: identity)
}
nonisolated private func requestControlJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}
nonisolated private func requestControlStage(_ phase: String) throws -> Int {
    if ["relaunch", "all"].contains(phase) { return 6 }
    return try #require(RequestControlSeedConstants.phases.firstIndex(of: phase))
}
nonisolated private func requestControlProductRoot() throws -> URL {
    let support = try #require(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
    return support.resolvingSymlinksInPath().appendingPathComponent("FrameRelayLibrary", isDirectory: true)
}
nonisolated private func requestControlSentinel(_ services: ProductLibraryServices, nonce: String) -> URL {
    services.run.url.deletingLastPathComponent().appendingPathComponent("s28-media-request-control-external-" + nonce + ".mov")
}

@MainActor private func requestControlRequireEmptyRoot(_ services: ProductLibraryServices, nonce: String) async throws {
    let expected = try requestControlProductRoot()
    try #require(services.run.url.standardizedFileURL == expected.standardizedFileURL)
    try #require(!FileManager.default.fileExists(atPath: requestControlSentinel(services, nonce: nonce).path))
    let leaves = Set(try FileManager.default.contentsOfDirectory(atPath: services.run.url.path))
    let allowed: Set<String> = ["run.marker", "recordings.sqlite", "recordings.sqlite-wal", "recordings.sqlite-shm",
        "recordings.sqlite-journal", "recordings-sqlite.lock", "originals.lock"]
    try #require(leaves.isSubset(of: allowed))
    let backend = try await mediaSnapshot(services.store), originals = try await mediaOriginalSnapshot(services.store)
    try #require(backend.revision == 0 && backend.storeIdentity == nil && backend.registrationIntents.isEmpty
        && backend.registrations.isEmpty && backend.batches.isEmpty && backend.requests.isEmpty && backend.verifications.isEmpty
        && backend.confirmations.isEmpty && backend.invalidations.isEmpty && backend.outbox.isEmpty && backend.publications.isEmpty
        && backend.confirmationStates.isEmpty && backend.deliveries.isEmpty && backend.distributionObservations.isEmpty
        && backend.temporaryMedia.isEmpty && backend.photoRegistrations.isEmpty && backend.photoSaveBatches.isEmpty
        && backend.backgroundTasks.isEmpty && backend.remoteInventory.isEmpty && backend.publicationManifests.isEmpty && backend.personControls.isEmpty)
    try #require(originals.revision == 0 && originals.originals.isEmpty && originals.logicalOriginals.isEmpty && originals.removalBatches.isEmpty)
    guard case .loaded(let records) = await services.store.loadRecordings(),
          case .loaded(let unfinished) = await services.store.loadUnfinished(),
          case .loaded(let library) = await services.reader.loadLibrary() else { throw BackendContractError.unavailable }
    try #require(records.revision == 0 && records.recordings.isEmpty && unfinished.isEmpty && library.items.isEmpty
        && library.remoteItems.isEmpty && library.history.isEmpty && library.mediaRequests.isEmpty && library.personControls.isEmpty)
}
@MainActor private func requestControlBindTechnicalSavedOriginal(_ original: OriginalContent, bytes: Data,
    services: ProductLibraryServices) async throws -> OriginalBinding {
    let fixture = try CaptureFixture(clip: original.capture.rawValue)
    guard case .committed(let intent) = await services.store.execute(.commitIntent(fixture.token(1), expectedRevision: 0, fixture.intent)) else {
        throw BackendContractError.notCommitted
    }
    let destination = try await services.originals.reserve(original: fixture.intent.original)
    try bytes.write(to: destination, options: .withoutOverwriting)
    var lifecycle = try RecordingSaveLifecycle(intent: fixture.intent, intentToken: fixture.token(1), revision: 0)
    try lifecycle.acceptIntentCommit(intent)
    try lifecycle.acceptRecordingEnd(context: fixture.context, evidence: fixture.end)
    try lifecycle.acceptFile(.init(context: fixture.context, original: fixture.intent.original,
        byteCount: UInt64(bytes.count), finalizedAt: fixture.time))
    // Typed synthetic classification only; this does not inspect or relabel the MOV as Log.
    _ = try lifecycle.acceptInspection(fixture.inspection(), resultToken: fixture.token(4))
    let result = try #require(lifecycle.resultRecord)
    try #require(result.result == .saved)
    guard case .committed(let receipt) = await services.store.execute(.commitResult(fixture.token(4), expectedRevision: 1, result)) else {
        throw BackendContractError.notCommitted
    }
    let binding = OriginalBinding(original: original, reference: fixture.intent.original, saveRecord: result, saveCommit: receipt)
    _ = try await mediaOriginalCommit(services.store, .bind(binding))
    return binding
}
@MainActor private func requestControlTechnicalTransition(_ request: MediaRequest, _ value: MediaRequestTransition,
    services: ProductLibraryServices) async throws {
    _ = try await mediaCommit(services.store, .requestTransition(command: .init(rawValue: UUID().uuidString.lowercased()),
        operation: request.operation, target: request.target, registration: request.registration, value: value))
}

@MainActor private func requestControlVerify(_ services: ProductLibraryServices, manifest: RequestControlSeedManifest,
    expectedStage stage: Int) async throws {
    try #require((0...6).contains(stage) && manifest.schema == "fr-s28-media-request-control-seed-v1")
    try #require(try requestControlIdentity(services.run.url, directory: true) == manifest.rootIdentity)
    let roles = ["local", "waiting", "cancelled", "completed", "ended"]
    try #require(manifest.targets.map(\.role) == roles && Set(manifest.targets.map { $0.request.operation }).count == 5)
    let backend = try await mediaSnapshot(services.store), originals = try await mediaOriginalSnapshot(services.store)
    try #require(backend.storeIdentity == manifest.identity && backend.registrations == [manifest.registration])
    try #require(backend.registrationIntents.count == 1 && backend.requests.count == 5 && backend.publications.count == 4
        && backend.confirmationStates.count == 4 && backend.remoteInventory.count == 1 && backend.personControls.count == stage)
    try #require(backend.revision == manifest.seedRevision + UInt64(stage))
    try #require(backend.batches.isEmpty && backend.verifications.isEmpty && backend.confirmations.isEmpty
        && backend.invalidations.isEmpty && backend.outbox.isEmpty && backend.deliveries.isEmpty
        && backend.distributionObservations.isEmpty && backend.temporaryMedia.isEmpty && backend.photoRegistrations.isEmpty
        && backend.photoSaveBatches.isEmpty && backend.backgroundTasks.isEmpty && backend.publicationManifests.isEmpty)
    try #require(backend.publications.map(\.observation) == manifest.publications
        && backend.remoteInventory.first?.observation == manifest.catalog && backend.remoteInventory.first?.isCommitted == true)
    try #require(backend.confirmationStates.allSatisfy { $0.validConfirmation == nil && $0.invalidatedRenditions.isEmpty })
    try #require(originals.originals.count == 1 && originals.originals.first?.binding == manifest.binding
        && originals.originals.first?.bindingCommit == manifest.bindingCommit && originals.logicalOriginals.count == 5
        && originals.removalBatches.isEmpty)
    try #require(originals.logicalOriginals.allSatisfy {
        $0.readers.isEmpty && $0.mediaReaders.isEmpty && $0.requiresMediaReconciliation == ($0.binding == nil) && $0.mediaReconciliation == nil
            && $0.removal == nil && $0.resolvedRemoval == nil && $0.removalResolution == nil && $0.invalidation == nil
    })
    var commandIDs = Set<MediaOperationID>()
    var expectedRequests = manifest.targets.map(\.request)
    let actions: [MediaPersonControlAction] = [.pause, .resumeIntent, .pause, .resumeIntent, .pause, .cancel]
    for (index, record) in backend.personControls.enumerated() {
        let all = index == 4, targetIndices = all ? Array(0..<5) : [index < 2 || index == 5 ? 0 : 1]
        try #require(record.isCommitted && record.plan.storeIdentity == manifest.identity && record.plan.action == actions[index]
            && record.plan.scope == (all ? .allPause : .single) && record.children.count == targetIndices.count)
        try #require(record.commit.previousRevision == manifest.seedRevision + UInt64(index)
            && record.commit.committedRevision == record.commit.previousRevision + 1)
        try #require(commandIDs.insert(record.plan.parent).inserted && RemoteInventoryValidation.canonicalID(record.plan.parent.rawValue))
        let fixedOperations = Set(record.plan.children.map { $0.target.operation })
        try #require(fixedOperations == Set(targetIndices.map { expectedRequests[$0].operation }))
        for child in record.children {
            try #require(commandIDs.insert(child.child.command).inserted && RemoteInventoryValidation.canonicalID(child.child.command.rawValue))
            let targetIndex = try #require(expectedRequests.firstIndex { child.child.target.matches($0) })
            try #require(targetIndices.contains(targetIndex) && child.child.target.attempt == nil)
            let expectedDecision: MediaPersonControlDecision = all && targetIndex >= 2
                ? .notProcessed(targetIndex == 2 ? .cancelled : targetIndex == 3 ? .completed : .playbackEnded) : .recorded
            try #require(child.decision == expectedDecision)
            if expectedDecision == .recorded { try expectedRequests[targetIndex].apply(actions[index].transition) }
        }
        try #require(await services.store.lookupCommit(record.mutation) == .committed(record.commit))
    }
    let childCount = backend.personControls.reduce(0) { $0 + $1.children.count }
    try #require(childCount == (stage <= 4 ? stage : stage + 4) && commandIDs.count == stage + childCount)
    try #require(commandIDs.isDisjoint(with: Set(backend.requests.map(\.operation))))
    for expected in expectedRequests {
        let actual = try #require(backend.requests.first { MediaPersonControlTarget(expected).matches($0) })
        try #require(LibraryMediaRequestProjection.samePresentation(actual, expected) && actual.attempt == nil && actual.session == nil
            && actual.transport == .queued && !actual.canRun)
    }
    guard case .loaded(let records) = await services.store.loadRecordings(),
          case .loaded(let unfinished) = await services.store.loadUnfinished(),
          case .loaded(let library) = await services.reader.loadLibrary() else { throw BackendContractError.unavailable }
    try #require(records.recordings.count == 1 && records.recordings.first?.result == manifest.binding.saveRecord
        && records.recordings.first?.resultCommit == manifest.binding.saveCommit && unfinished.isEmpty)
    try #require(library.items.count == 1 && library.history.isEmpty && library.remoteItems.count == 4
        && library.mediaRequests.count == 5 && library.personControls == backend.personControls && library.photoSaveBatches.isEmpty)
    let oldRoot = URL(fileURLWithPath: manifest.sourceCopy.path).deletingLastPathComponent().standardizedFileURL
    let currentRoot = services.run.url.standardizedFileURL
    let oldContainer = oldRoot.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let currentContainer = currentRoot.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    // Xcode may move this same directory to a new App container UUID. Only that
    // UUID component may differ; the immutable manifest's exact leaves remain.
    try #require(Array(oldRoot.pathComponents.suffix(3)) == ["Library", "Application Support", "FrameRelayLibrary"]
        && Array(currentRoot.pathComponents.suffix(3)) == ["Library", "Application Support", "FrameRelayLibrary"]
        && oldContainer.deletingLastPathComponent() == currentContainer.deletingLastPathComponent()
        && oldContainer.deletingLastPathComponent().lastPathComponent == "Application"
        && UUID(uuidString: oldContainer.lastPathComponent) != nil && UUID(uuidString: currentContainer.lastPathComponent) != nil)
    let sourceLeaf = "request-control-source-" + manifest.nonce + ".mov"
    let originalLeaf = manifest.binding.reference.rawValue + ".mov"
    let reservationLeaf = manifest.binding.reference.rawValue + ".reservation"
    let sentinelLeaf = "s28-media-request-control-external-" + manifest.nonce + ".mov"
    try #require(manifest.sourceCopy.path == oldRoot.appendingPathComponent(sourceLeaf).path
        && manifest.originalFile.path == oldRoot.appendingPathComponent(originalLeaf).path
        && manifest.reservation.path == oldRoot.appendingPathComponent(reservationLeaf).path
        && manifest.sentinel.path == oldRoot.deletingLastPathComponent().appendingPathComponent(sentinelLeaf).path)
    try #require(try requestControlFile(URL(fileURLWithPath: manifest.sourceInput.path)) == manifest.sourceInput)
    let currentFiles: [(RequestControlFile, URL)] = [
        (manifest.sourceCopy, currentRoot.appendingPathComponent(sourceLeaf)),
        (manifest.originalFile, currentRoot.appendingPathComponent(originalLeaf)),
        (manifest.reservation, currentRoot.appendingPathComponent(reservationLeaf)),
        (manifest.sentinel, currentRoot.deletingLastPathComponent().appendingPathComponent(sentinelLeaf))]
    for (expected, currentURL) in currentFiles {
        let actual = try requestControlFile(currentURL)
        try #require(actual.path == currentURL.path && actual.signature == expected.signature)
    }
    let originalContent = try manifest.originalFile.mediaContent()
    try #require(originalContent == manifest.binding.original.content && manifest.sourceInput.sameContents(manifest.sourceCopy)
        && manifest.sourceCopy.sameContents(manifest.originalFile) && manifest.sentinel.sameContents(manifest.originalFile)
        && manifest.reservation.byteCount == 0)
}
nonisolated private func requestControlDecisionText(_ decision: MediaPersonControlDecision) -> String {
    switch decision { case .recorded: "recorded"; case .notProcessed(let reason): "notProcessed." + reason.rawValue }
}
nonisolated private func requestControlUIExpected(_ manifest: RequestControlSeedManifest,
    manifestFile: RequestControlFile) -> RequestControlUIExpected {
    .init(schema: "fr-s28-media-request-control-ui-v1", nonce: manifest.nonce, simulator: manifest.simulator,
        variant: manifest.variant, storeUUID: manifest.identity.rawValue.uuidString, manifest: manifestFile.signature,
        targets: manifest.targets.map { seed in
            let request = seed.request
            let rendition: String?
            if case .rendition(let value) = request.target { rendition = value.rendition.rawValue } else { rendition = nil }
            return .init(role: seed.role, capture: request.target.original.capture.rawValue, operation: request.operation.rawValue,
                requestToken: MediaPersonControlTarget(request).accessibilityToken, rendition: rendition,
                remoteToken: seed.role == "local" ? nil : RemoteInventoryOriginalID(destination: request.registration.destination,
                    original: request.target.original).accessibilityToken, startRevision: request.expectedStartRevision)
        })
}
