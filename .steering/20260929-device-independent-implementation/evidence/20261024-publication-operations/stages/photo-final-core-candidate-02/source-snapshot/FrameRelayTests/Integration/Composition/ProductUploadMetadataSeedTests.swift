import CryptoKit
import Darwin
import Foundation
import Security
import Testing
@testable import FrameRelay

/// One create-only fixture per assigned new Simulator. Saved classification,
/// registration and queued acceptance are synthetic typed inputs. No remote
/// registration, native Wi-Fi, camera, Photos or media transfer is claimed.
@Suite(.serialized) @MainActor struct ProductUploadMetadataSeedTests {
    @Test(.enabled(if: metadataSeedFlag("FR_UPLOAD_METADATA_SEED")))
    func seedOneSavedOriginalQueuedRequestAndCurrentNamespaceCredentialsOnce() async throws {
        let context = try metadataSeedContext(mode: "SEED")
        try #require(context.phase == "seed")
        let input = try metadataSeedSource(), bytes = try Data(contentsOf: URL(fileURLWithPath: input.path))
        try #require(try metadataSeedFile(URL(fileURLWithPath: input.path)) == input)
        let services = try await ProductLibraryFactory.shared.open()
        try await metadataSeedRequireEmpty(services, context: context)
        _ = try await services.store.establishRegistrationIdentity(expectedRevision: 0, expectedIdentity: nil)
        let identity = try #require(try await mediaSnapshot(services.store).storeIdentity)
        let destination = DestinationIdentity(rawValue: UUID().uuidString.lowercased())
        let intent = RegistrationIntent(operation: .init(rawValue: UUID().uuidString.lowercased()), destination: destination)
        let connection = try RegistrationConnection(endpoint: .init(httpsOrigin: context.origin), destination: destination)
        let credentials = try await metadataSeedCreateCredentials(identity, intent: intent, connection: connection)
        _ = try await mediaCommit(services.store, .registrationIntent(intent))
        // Technical server-result input only; no server or registration POST.
        _ = try await mediaCommit(services.store, .registration(.init(intent: intent, registration: .init(
            destination: destination, id: .init(rawValue: UUID().uuidString.lowercased()), generation: .init(rawValue: 1)))))
        let registration = try #require(try await mediaSnapshot(services.store).registrations.last)
        let sourceURL = services.run.url.appendingPathComponent("upload-metadata-source-" + context.nonce + ".mov")
        try bytes.write(to: sourceURL, options: .withoutOverwriting)
        let original = OriginalContent(capture: .init(rawValue: context.capture), generation: .init(rawValue: 1),
            content: try .init(byteCount: input.bytes, algorithm: "sha256", digest: input.sha256))
        let binding = try await metadataSeedBind(original, bytes: bytes, services: services)
        let state = try #require(try await mediaOriginalSnapshot(services.store).originals.first)
        let before = try await mediaSnapshot(services.store)
        let request = try OriginalUploadAcceptanceRequest(parent: .init(rawValue: UUID().uuidString.lowercased()),
            storeIdentity: identity, registration: registration, scope: .single,
            targets: [.init(operation: .init(rawValue: UUID().uuidString.lowercased()), binding: binding)])
        // This direct typed fixture journal is not a product native-Wi-Fi
        // acceptance. The genuine writer generates its new receipt and child.
        let plan = try OriginalUploadAcceptancePlan(request: request, presences: [.present(byteCount: input.bytes)])
        let mutation = BackendStoreMutation(expectedRevision: before.revision, change: .originalUploadAcceptance(plan),
            expectedStoreIdentity: identity)
        guard case .committed(let accepted) = await services.store.commit(mutation) else { throw BackendContractError.notCommitted }
        let backend = try await mediaSnapshot(services.store)
        let current = try #require(backend.requests.first)
        let sentinelURL = metadataSeedSentinel(services.run.url, nonce: context.nonce)
        try bytes.write(to: sentinelURL, options: .withoutOverwriting)
        let manifest = MetadataSeedManifest(schema: "fr-upload-metadata-seed-v1", nonce: context.nonce,
            simulator: context.simulator, variant: context.variant, origin: context.origin,
            portKeeperID: MetadataSeedConstants.portKeeperID, portKeeperPID: MetadataSeedConstants.portKeeperPID,
            identity: identity, registration: registration, credentials: credentials,
            rootIdentity: try metadataSeedIdentity(services.run.url, directory: true), sourceInput: input,
            sourceCopy: try metadataSeedFile(sourceURL), binding: binding, bindingCommit: state.bindingCommit,
            originalFile: try metadataSeedFile(services.run.url.appendingPathComponent(binding.reference.rawValue + ".mov")),
            reservation: try metadataSeedFile(services.run.url.appendingPathComponent(binding.reference.rawValue + ".reservation")),
            sentinel: try metadataSeedFile(sentinelURL), acceptancePlan: plan, acceptanceCommit: accepted,
            initialRequest: current, seedRevision: backend.revision)
        let file = services.run.url.appendingPathComponent(MetadataSeedConstants.manifestLeaf)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: file, options: .withoutOverwriting)
        let signature = try metadataSeedFile(file).signature
        try await metadataSeedVerify(services, manifest: manifest, stage: 0)
        try #require(try metadataSeedFile(file).signature == signature)
        let expected = MetadataSeedUIExpected(schema: "fr-upload-metadata-ui-v1", nonce: context.nonce,
            simulator: context.simulator, variant: context.variant, storeUUID: identity.rawValue.uuidString,
            capture: context.capture, operation: current.operation.rawValue,
            requestToken: MediaPersonControlTarget(current).accessibilityToken, acceptanceParent: request.parent.rawValue,
            manifest: signature, credentialBundleSHA256: credentials.bundleSHA256, origin: context.origin,
            portKeeperID: MetadataSeedConstants.portKeeperID, portKeeperPID: MetadataSeedConstants.portKeeperPID)
        print("UPLOAD_METADATA_SEED_MANIFEST " + (try metadataSeedJSON(signature)))
        print("UPLOAD_METADATA_UI_EXPECTED " + (try metadataSeedJSON(expected)))
        print("UPLOAD_METADATA_SEED variant=\(context.variant) savedBindings=1 originalAcceptanceParents=1 children=1 queuedRequests=1 queries=0 observations=0 currentNamespaceItems=2 syntheticRegistration=true serverRegistration=notExercised nativeWiFi=notObserved attempts=0 sessions=0 readers=0 mediaSDKInventory=notMeasured")
    }

    @Test(.enabled(if: metadataSeedFlag("FR_UPLOAD_METADATA_VERIFY")))
    func verifyConsumedPrefixExactReceiptsCredentialsFilesAndIndependentWriterReopen() async throws {
        let context = try metadataSeedContext(mode: "VERIFY"), root = try metadataSeedProductRoot()
        _ = try metadataSeedIdentity(root, directory: true)
        _ = try metadataSeedIdentity(root.appendingPathComponent(MetadataSeedConstants.manifestLeaf))
        let services = try await ProductLibraryFactory.shared.open()
        let file = services.run.url.appendingPathComponent(MetadataSeedConstants.manifestLeaf)
        let manifestFile = try metadataSeedFile(file), signature = try metadataSeedExpectedSignature()
        try #require(manifestFile.signature == signature)
        let manifest = try JSONDecoder().decode(MetadataSeedManifest.self, from: Data(contentsOf: file))
        try #require(manifest.nonce == context.nonce && manifest.simulator == context.simulator
            && manifest.variant == context.variant && manifest.origin == context.origin)
        let backend = try await mediaSnapshot(services.store)
        let actual = backend.uploadMetadataQueries.isEmpty ? 0 : backend.personControls.count + 1
        let stage = context.phase == "observe" ? actual : try metadataSeedStage(context.phase)
        try await metadataSeedVerify(services, manifest: manifest, stage: stage)
        let reopened = try SQLiteRecordingStore(run: services.run, mode: .openExisting, supportedVerificationSchemas: ["fr-final-read-v1"])
        try #require(try await mediaSnapshot(reopened) == backend)
        let original = try await mediaOriginalSnapshot(services.store), replay = try await mediaOriginalSnapshot(reopened)
        try #require(original.revision == replay.revision && original.originals == replay.originals
            && original.logicalOriginals == replay.logicalOriginals && original.removalBatches == replay.removalBatches)
        let saved = await services.store.loadRecordings(), savedReplay = await reopened.loadRecordings()
        let unfinished = await services.store.loadUnfinished(), unfinishedReplay = await reopened.loadUnfinished()
        try #require(saved == savedReplay && unfinished == unfinishedReplay)
        for record in backend.originalUploadAcceptances {
            try #require(await reopened.lookupCommit(record.mutation) == .committed(record.commit))
        }
        for query in backend.uploadMetadataQueries {
            try #require(await reopened.lookupCommit(query.mutation) == .committed(query.commit))
        }
        for record in backend.personControls {
            try #require(await reopened.lookupCommit(record.mutation) == .committed(record.commit))
        }
        try metadataSeedVerifyFiles(services.run.url, manifest: manifest)
        try await metadataSeedVerifyCredentials(manifest)
        try #require(try metadataSeedFile(file) == manifestFile)
        let summary = MetadataSeedVerifySummary(schema: "fr-upload-metadata-verify-v1", nonce: context.nonce,
            simulator: context.simulator, variant: context.variant, requestedPhase: context.phase,
            actualPhase: MetadataSeedConstants.stages[stage], storeUUID: manifest.identity.rawValue.uuidString,
            queryIDs: backend.uploadMetadataQueries.map { $0.query.id.rawValue },
            queryCommits: backend.uploadMetadataQueries.map(\.commit),
            personParents: backend.personControls.map { $0.plan.parent.rawValue },
            personChildren: backend.personControls.flatMap { $0.children.map { $0.child.command.rawValue } },
            currentRequest: backend.requests[0].operation.rawValue, credentialBundleSHA256: manifest.credentials.bundleSHA256)
        print("UPLOAD_METADATA_VERIFY " + (try metadataSeedJSON(summary)))
        print("UPLOAD_METADATA_ACTUAL_PHASE " + MetadataSeedConstants.stages[stage])
        print("UPLOAD_METADATA_PRESERVED sourceInput=match sourceCopy=match original=match reservation=match sentinel=match immutableManifest=match rootAndFileInodes=match currentNamespaceBundle=match independentSQLite=equal originalAcceptance=unchanged observations=0 attempts=0 sessions=0 logicalReaders=0 mediaReaders=0 captureWaitExercise=none nativeHTTPGlobalCounts=notMeasured nativeMediaSDKInventory=notMeasured lookupContract=localOnly closedHTTPSOnly=true")
    }
}

nonisolated private enum MetadataSeedConstants {
    static let manifestLeaf = "upload-metadata-seed.json"
    static let stages = ["seed", "requestUnknown", "paused", "cancelled"]
    static let origin = "https://127.0.0.1:51875"
    static let portKeeperID = "12667470-2db3-4f9d-bc26-b3b919e691ae"
    static let portKeeperPID = 37193
    static let sourceSuffix = "/fr-implementation-20261024-l0p333tn/request-control-synthetic-source.mov"
    static let sourceHash = "153d236030c76488aa11dfc797a107b7474999bae44f16bb81eaafad364e15c7"
    static let sourceBytes: UInt64 = 2_907_110
    static let sourceDevice: Int64 = 16_777_234
    static let sourceInode: UInt64 = 33_015_426
}
nonisolated private struct MetadataSeedContext {
    let nonce: String; let simulator: String; let variant: String; let phase: String; let origin: String
    var capture: String { "um-" + String(nonce.prefix(8)) + "-saved" }
}
nonisolated private struct MetadataSeedSignature: Codable, Equatable {
    let sha256: String; let bytes: UInt64; let device: Int64; let inode: UInt64
}
nonisolated private struct MetadataSeedFile: Codable, Equatable {
    let path: String; let bytes: UInt64; let sha256: String; let identity: TemporaryFileIdentity
    var signature: MetadataSeedSignature { .init(sha256: sha256, bytes: bytes, device: identity.device, inode: identity.inode) }
}
nonisolated private struct MetadataSeedCredentialHashes: Codable {
    let connectionAccount: String; let credentialAccount: String
    let connectionSHA256: String; let credentialSHA256: String; let bundleSHA256: String
}
nonisolated private struct MetadataSeedManifest: Codable {
    let schema: String; let nonce: String; let simulator: String; let variant: String; let origin: String
    let portKeeperID: String; let portKeeperPID: Int
    let identity: RegistrationStoreIdentity; let registration: DeviceRegistration; let credentials: MetadataSeedCredentialHashes
    let rootIdentity: TemporaryFileIdentity; let sourceInput: MetadataSeedFile; let sourceCopy: MetadataSeedFile
    let binding: OriginalBinding; let bindingCommit: OriginalStoreCommitReceipt
    let originalFile: MetadataSeedFile; let reservation: MetadataSeedFile; let sentinel: MetadataSeedFile
    let acceptancePlan: OriginalUploadAcceptancePlan; let acceptanceCommit: BackendCommitReceipt
    let initialRequest: MediaRequest; let seedRevision: UInt64
}
nonisolated private struct MetadataSeedUIExpected: Encodable {
    let schema: String; let nonce: String; let simulator: String; let variant: String; let storeUUID: String
    let capture: String; let operation: String; let requestToken: String; let acceptanceParent: String
    let manifest: MetadataSeedSignature; let credentialBundleSHA256: String; let origin: String
    let portKeeperID: String; let portKeeperPID: Int
}
nonisolated private struct MetadataSeedVerifySummary: Encodable {
    let schema: String; let nonce: String; let simulator: String; let variant: String; let requestedPhase: String
    let actualPhase: String; let storeUUID: String; let queryIDs: [String]; let queryCommits: [BackendCommitReceipt]
    let personParents: [String]; let personChildren: [String]; let currentRequest: String; let credentialBundleSHA256: String
}

nonisolated private func metadataSeedFlag(_ key: String) -> Bool { ProcessInfo.processInfo.environment[key] == "1" }
nonisolated private func metadataSeedValue(_ key: String) throws -> String {
    guard let value = ProcessInfo.processInfo.environment[key], !value.isEmpty else { throw BackendContractError.invalidValue }
    return value
}
nonisolated private func metadataSeedContext(mode: String) throws -> MetadataSeedContext {
    let prefix = "FR_UPLOAD_METADATA_"
    try #require(["SEED", "VERIFY", "UI"].filter { metadataSeedFlag(prefix + $0) } == [mode])
    let nonce = try metadataSeedValue(prefix + "NONCE"), variant = try metadataSeedValue(prefix + "VARIANT")
    let phase = try metadataSeedValue(prefix + "PHASE"), origin = try metadataSeedValue(prefix + "CLOSED_HTTPS_ORIGIN")
    let requested = try metadataSeedValue(prefix + "SIMULATOR_UDID"), actual = try metadataSeedValue("SIMULATOR_UDID")
    #if targetEnvironment(simulator)
    try #require(requested == actual && ((actual == "7AD9895F-23EB-4FB2-B2A0-A92F4D7E431F"
        && variant == "normal" && nonce == "6c947a54-5a1a-438b-8080-96db9ef62f80")
        || (actual == "52CDA9DC-D57C-4DA7-89BB-33F15C5B9169" && variant == "max" && nonce == "76416ee5-f016-4720-9f78-46f697a2719c")))
    let keeperID = try metadataSeedValue(prefix + "PORT_KEEPER_ID"), keeperPID = try metadataSeedValue(prefix + "PORT_KEEPER_PID")
    try #require(origin == MetadataSeedConstants.origin && metadataSeedFlag(prefix + "CLOSED_HTTPS_HELD")
        && keeperID == MetadataSeedConstants.portKeeperID && keeperPID == String(MetadataSeedConstants.portKeeperPID))
    try #require(MetadataSeedConstants.stages.contains(phase) || ["observe", "all", "relaunch"].contains(phase))
    return .init(nonce: nonce, simulator: actual, variant: variant, phase: phase, origin: origin)
    #else
    throw BackendContractError.unavailable
    #endif
}
nonisolated private func metadataSeedSource() throws -> MetadataSeedFile {
    let prefix = "FR_UPLOAD_METADATA_SOURCE_", path = try metadataSeedValue(prefix + "PATH")
    try #require(path.hasPrefix("/") && path.hasSuffix(MetadataSeedConstants.sourceSuffix)
        && URL(fileURLWithPath: path).standardizedFileURL.path == path)
    let file = try metadataSeedFile(URL(fileURLWithPath: path))
    let hash = try metadataSeedValue(prefix + "SHA256"), bytes = try metadataSeedValue(prefix + "BYTES")
    let device = try metadataSeedValue(prefix + "DEVICE"), inode = try metadataSeedValue(prefix + "INODE")
    try #require(file.sha256 == hash && hash == MetadataSeedConstants.sourceHash
        && String(file.bytes) == bytes && file.bytes == MetadataSeedConstants.sourceBytes
        && String(file.identity.device) == device && file.identity.device == MetadataSeedConstants.sourceDevice
        && String(file.identity.inode) == inode && file.identity.inode == MetadataSeedConstants.sourceInode)
    var info = stat(); try #require(lstat(path, &info) == 0 && info.st_mode & 0o222 == 0)
    return file
}
nonisolated private func metadataSeedExpectedSignature() throws -> MetadataSeedSignature {
    let prefix = "FR_UPLOAD_METADATA_MANIFEST_"
    let hash = try metadataSeedValue(prefix + "SHA256"), bytesText = try metadataSeedValue(prefix + "BYTES")
    let deviceText = try metadataSeedValue(prefix + "DEVICE"), inodeText = try metadataSeedValue(prefix + "INODE")
    return .init(sha256: hash, bytes: try #require(UInt64(bytesText)),
        device: try #require(Int64(deviceText)), inode: try #require(UInt64(inodeText)))
}
nonisolated private func metadataSeedIdentity(_ url: URL, directory: Bool = false) throws -> TemporaryFileIdentity {
    var info = stat()
    try #require(lstat(url.path, &info) == 0 && info.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG))
    if !directory { try #require(info.st_nlink == 1) }
    return .init(device: Int64(info.st_dev), inode: UInt64(info.st_ino))
}
nonisolated private func metadataSeedFile(_ url: URL) throws -> MetadataSeedFile {
    let before = try metadataSeedIdentity(url)
    let size = try #require(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
    try #require(size >= 0 && size <= 64 * 1_024 * 1_024)
    let data = try Data(contentsOf: url), after = try metadataSeedIdentity(url)
    try #require(before == after && size == data.count)
    return .init(path: url.standardizedFileURL.path, bytes: UInt64(data.count), sha256: metadataSeedDigest(data), identity: before)
}
nonisolated private func metadataSeedDigest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
nonisolated private func metadataSeedJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}
nonisolated private func metadataSeedAbsent(_ url: URL) throws {
    var info = stat(); let result = lstat(url.path, &info), observed = errno
    try #require(result != 0 && observed == ENOENT)
}
nonisolated private func metadataSeedStage(_ phase: String) throws -> Int {
    if ["all", "relaunch"].contains(phase) { return 3 }
    return try #require(MetadataSeedConstants.stages.firstIndex(of: phase))
}
nonisolated private func metadataSeedProductRoot() throws -> URL {
    let support = try #require(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
    return support.resolvingSymlinksInPath().appendingPathComponent("FrameRelayLibrary", isDirectory: true)
}
nonisolated private func metadataSeedSentinel(_ root: URL, nonce: String) -> URL {
    root.deletingLastPathComponent().appendingPathComponent("upload-metadata-external-" + nonce + ".mov")
}

// Only the exact two current-UUID accounts are addressed. No service/global
// enumeration, fallback, update, repair or deletion exists in this fixture.
nonisolated private struct MetadataSeedConnection: Codable {
    let version: Int; let storeIdentity: RegistrationStoreIdentity; let origin: String; let destination: String; let bearer: String
}
nonisolated private struct MetadataSeedCredential: Codable {
    let version: Int; let storeIdentity: RegistrationStoreIdentity; let destination: String; let operation: String; let secret: String
}
nonisolated private func metadataSeedKeychainQuery(_ account: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: KeychainRegistrationVault.productService,
        kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false, kSecUseDataProtectionKeychain as String: true]
}
nonisolated private func metadataSeedKeychainBytes(_ account: String) throws -> Data? {
    var query = metadataSeedKeychainQuery(account)
    query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?; let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let bytes = item as? Data, !bytes.isEmpty, bytes.count <= 16_384 else {
        throw RegistrationAccessError.credentialUnavailable
    }
    return bytes
}
nonisolated private func metadataSeedKeychainCreate(_ account: String, data: Data) throws {
    guard try metadataSeedKeychainBytes(account) == nil else { throw RegistrationAccessError.credentialConflict }
    var query = metadataSeedKeychainQuery(account)
    query[kSecValueData as String] = data; query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw RegistrationAccessError.credentialConflict }
}
nonisolated private func metadataSeedRandom() throws -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw RegistrationAccessError.credentialUnavailable }
    return bytes.map { String(format: "%02x", $0) }.joined()
}
@MainActor private func metadataSeedCreateCredentials(_ identity: RegistrationStoreIdentity, intent: RegistrationIntent,
    connection: RegistrationConnection) async throws -> MetadataSeedCredentialHashes {
    let connectionAccount = "store." + identity.rawValue.uuidString.lowercased() + ".connection"
    let credentialAccount = "store." + identity.rawValue.uuidString.lowercased() + ".initial." + intent.destination.rawValue
    guard try metadataSeedKeychainBytes(connectionAccount) == nil, try metadataSeedKeychainBytes(credentialAccount) == nil else {
        throw RegistrationAccessError.credentialConflict
    }
    let encoder = JSONEncoder()
    let connectionBytes = try encoder.encode(MetadataSeedConnection(version: 2, storeIdentity: identity,
        origin: connection.endpoint.origin.absoluteString, destination: connection.destination.rawValue, bearer: metadataSeedRandom()))
    let credentialBytes = try encoder.encode(MetadataSeedCredential(version: 2, storeIdentity: identity,
        destination: intent.destination.rawValue, operation: intent.operation.rawValue, secret: metadataSeedRandom()))
    try metadataSeedKeychainCreate(connectionAccount, data: connectionBytes)
    try metadataSeedKeychainCreate(credentialAccount, data: credentialBytes)
    return .init(connectionAccount: connectionAccount, credentialAccount: credentialAccount,
        connectionSHA256: metadataSeedDigest(connectionBytes), credentialSHA256: metadataSeedDigest(credentialBytes),
        bundleSHA256: metadataSeedDigest(connectionBytes + Data([0]) + credentialBytes))
}
@MainActor private func metadataSeedVerifyCredentials(_ manifest: MetadataSeedManifest) async throws {
    let expected = manifest.credentials, identity = manifest.identity, intent = manifest.registration.server.intent
    guard expected.connectionAccount == "store." + identity.rawValue.uuidString.lowercased() + ".connection",
          expected.credentialAccount == "store." + identity.rawValue.uuidString.lowercased() + ".initial." + intent.destination.rawValue,
          let connectionBytes = try metadataSeedKeychainBytes(expected.connectionAccount),
          let credentialBytes = try metadataSeedKeychainBytes(expected.credentialAccount),
          metadataSeedDigest(connectionBytes) == expected.connectionSHA256,
          metadataSeedDigest(credentialBytes) == expected.credentialSHA256,
          metadataSeedDigest(connectionBytes + Data([0]) + credentialBytes) == expected.bundleSHA256 else {
        throw RegistrationAccessError.credentialConflict
    }
    // No assertion macro ever receives these decoded values or auth headers.
    let connection: MetadataSeedConnection, credential: MetadataSeedCredential
    do {
        connection = try JSONDecoder().decode(MetadataSeedConnection.self, from: connectionBytes)
        credential = try JSONDecoder().decode(MetadataSeedCredential.self, from: credentialBytes)
    } catch { throw RegistrationAccessError.credentialConflict }
    let hex: (String) -> Bool = { $0.utf8.count == 64 && $0.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
    guard connection.version == 2, credential.version == 2, connection.storeIdentity == identity, credential.storeIdentity == identity,
          connection.origin == manifest.origin, connection.destination == intent.destination.rawValue,
          credential.destination == intent.destination.rawValue, credential.operation == intent.operation.rawValue,
          hex(connection.bearer), hex(credential.secret), connection.bearer != credential.secret else {
        throw RegistrationAccessError.credentialConflict
    }
    let vault = KeychainRegistrationVault()
    let saved = try await vault.connection(storeIdentity: identity)
    let expectedConnection = try RegistrationConnection(endpoint: .init(httpsOrigin: manifest.origin), destination: intent.destination)
    guard saved == expectedConnection else { throw RegistrationAccessError.credentialConflict }
    let authorization = try await vault.authorization(for: expectedConnection, intent: intent, storeIdentity: identity)
    guard authorization.bearer.utf8.elementsEqual(connection.bearer.utf8),
          authorization.secret?.utf8.elementsEqual(credential.secret.utf8) == true,
          try metadataSeedKeychainBytes(expected.connectionAccount) == connectionBytes,
          try metadataSeedKeychainBytes(expected.credentialAccount) == credentialBytes else { throw RegistrationAccessError.credentialConflict }
}

@MainActor private func metadataSeedRequireEmpty(_ services: ProductLibraryServices, context: MetadataSeedContext) async throws {
    let root = try metadataSeedProductRoot()
    try #require(services.run.url == root)
    try metadataSeedAbsent(root.appendingPathComponent(MetadataSeedConstants.manifestLeaf))
    try metadataSeedAbsent(metadataSeedSentinel(root, nonce: context.nonce))
    let allowed: Set<String> = ["run.marker", "recordings.sqlite", "recordings.sqlite-wal", "recordings.sqlite-shm",
        "recordings.sqlite-journal", "recordings-sqlite.lock", "originals.lock"]
    try #require(Set(try FileManager.default.contentsOfDirectory(atPath: root.path)).isSubset(of: allowed))
    let backend = try await mediaSnapshot(services.store), originals = try await mediaOriginalSnapshot(services.store)
    try #require(backend.revision == 0 && backend.storeIdentity == nil && backend.registrations.isEmpty
        && backend.registrationIntents.isEmpty && backend.requests.isEmpty && backend.originalUploadAcceptances.isEmpty
        && backend.uploadMetadataQueries.isEmpty && backend.uploadMetadataObservations.isEmpty && backend.personControls.isEmpty)
    try metadataSeedNoOtherOperations(backend)
    try #require(originals.revision == 0 && originals.originals.isEmpty && originals.logicalOriginals.isEmpty && originals.removalBatches.isEmpty)
    guard case .loaded(let saved) = await services.store.loadRecordings(), case .loaded(let unfinished) = await services.store.loadUnfinished(),
          case .loaded(let library) = await services.reader.loadLibrary() else { throw BackendContractError.unavailable }
    try #require(saved.revision == 0 && saved.recordings.isEmpty && unfinished.isEmpty && library.items.isEmpty
        && library.remoteItems.isEmpty && library.history.isEmpty)
}
@MainActor private func metadataSeedBind(_ original: OriginalContent, bytes: Data, services: ProductLibraryServices) async throws -> OriginalBinding {
    let fixture = try CaptureFixture(clip: original.capture.rawValue)
    guard case .committed(let intent) = await services.store.execute(.commitIntent(fixture.token(1), expectedRevision: 0, fixture.intent)) else {
        throw BackendContractError.notCommitted
    }
    let destination = try await services.originals.reserve(original: fixture.intent.original)
    try bytes.write(to: destination, options: .withoutOverwriting)
    var lifecycle = try RecordingSaveLifecycle(intent: fixture.intent, intentToken: fixture.token(1), revision: 0)
    try lifecycle.acceptIntentCommit(intent); try lifecycle.acceptRecordingEnd(context: fixture.context, evidence: fixture.end)
    try lifecycle.acceptFile(.init(context: fixture.context, original: fixture.intent.original, byteCount: original.content.byteCount, finalizedAt: fixture.time))
    _ = try lifecycle.acceptInspection(fixture.inspection(), resultToken: fixture.token(4))
    let record = try #require(lifecycle.resultRecord)
    guard case .committed(let saved) = await services.store.execute(.commitResult(fixture.token(4), expectedRevision: 1, record)) else {
        throw BackendContractError.notCommitted
    }
    let binding = OriginalBinding(original: original, reference: fixture.intent.original, saveRecord: record, saveCommit: saved)
    _ = try await mediaOriginalCommit(services.store, .bind(binding)); return binding
}
@MainActor private func metadataSeedVerify(_ services: ProductLibraryServices, manifest: MetadataSeedManifest, stage: Int) async throws {
    try #require((0...3).contains(stage) && manifest.schema == "fr-upload-metadata-seed-v1"
        && manifest.origin == MetadataSeedConstants.origin && manifest.portKeeperID == MetadataSeedConstants.portKeeperID
        && manifest.portKeeperPID == MetadataSeedConstants.portKeeperPID)
    try #require(try metadataSeedIdentity(services.run.url, directory: true) == manifest.rootIdentity)
    let backend = try await mediaSnapshot(services.store), originals = try await mediaOriginalSnapshot(services.store)
    let queryCount = stage == 0 ? 0 : 1, personCount = max(0, stage - 1)
    try #require(backend.storeIdentity == manifest.identity && backend.registrations == [manifest.registration]
        && backend.registrationIntents.count == 1 && backend.originalUploadAcceptances.count == 1
        && backend.requests.count == 1 && backend.uploadMetadataQueries.count == queryCount
        && backend.uploadMetadataObservations.isEmpty && backend.personControls.count == personCount
        && backend.revision == manifest.seedRevision + UInt64(stage))
    try metadataSeedNoOtherOperations(backend)
    try #require(originals.originals.count == 1 && originals.logicalOriginals.count == 1 && originals.removalBatches.isEmpty)
    let state = try #require(originals.originals.first), logical = try #require(originals.logicalOriginals.first)
    try #require(state.binding == manifest.binding && state.bindingCommit == manifest.bindingCommit
        && OriginalUploadAcceptanceValueValidation.savedBinding(state.binding) && logical.readers.isEmpty && logical.mediaReaders.isEmpty
        && !logical.requiresMediaReconciliation && logical.mediaReconciliation == nil && logical.removal == nil
        && logical.resolvedRemoval == nil && logical.removalResolution == nil && logical.invalidation == nil)
    let accepted = backend.originalUploadAcceptances[0]
    try #require(accepted.children.count == 1)
    let acceptedInitial = try #require(accepted.children[0].initialRequest)
    try #require(accepted.isCommitted && accepted.expectedStoreIdentity == manifest.identity
        && UploadMetadataValidation.exact(accepted.plan, manifest.acceptancePlan) && accepted.commit == manifest.acceptanceCommit
        && accepted.children.count == 1 && accepted.children[0].decision == .accepted
        && accepted.children[0].presence == .present(byteCount: manifest.sourceInput.bytes)
        && LibraryMediaRequestProjection.samePresentation(acceptedInitial, manifest.initialRequest))
    try #require(await services.store.lookupCommit(accepted.mutation) == .committed(accepted.commit))
    let current = backend.requests[0]
    let expectedPending: RemoteObservationGeneration? = stage == 0 ? nil : .init(rawValue: 1)
    try #require(MediaPersonControlTarget(manifest.initialRequest).matches(current) && current.startCommitted
        && current.intent == (stage < 2 ? .running : stage == 2 ? .paused : .cancelled)
        && current.waits == manifest.initialRequest.waits && current.waits.isEmpty && current.transport == .queued
        && current.attempt == nil && current.session == nil && current.remote == .unknown && !current.canRun
        && !current.hasReconciled && current.lastObservation == nil && current.uploadMetadataHold == nil
        && current.uploadMetadataPending == expectedPending)
    for query in backend.uploadMetadataQueries {
        let expected = try UploadMetadataRequest(storeIdentity: manifest.identity, registration: manifest.registration,
            operation: current.operation, original: manifest.binding.original, expectedStartRevision: current.expectedStartRevision)
        try #require(query.isCommitted && query.expectedStoreIdentity == manifest.identity && query.query.kind == .create
            && query.query.generation.rawValue == 1 && UploadMetadataValidation.exact(query.query.request, expected)
            && RegistrationWireIdentity.isCanonical(query.query.id.rawValue)
            && RegistrationWireIdentity.isCanonical(query.query.observationCommand.rawValue)
            && query.query.id != query.query.observationCommand && query.commit.previousRevision == manifest.seedRevision
            && query.commit.committedRevision == manifest.seedRevision + 1)
        try #require(await services.store.lookupCommit(query.mutation) == .committed(query.commit))
    }
    var commands: Set<MediaOperationID> = [accepted.plan.request.parent, current.operation]
    for query in backend.uploadMetadataQueries {
        try #require(commands.insert(query.query.id).inserted && commands.insert(query.query.observationCommand).inserted)
    }
    for (index, record) in backend.personControls.enumerated() {
        try #require(record.isCommitted && record.plan.storeIdentity == manifest.identity && record.plan.scope == .single
            && record.plan.action == (index == 0 ? .pause : .cancel) && record.children.count == 1
            && record.children[0].decision == .recorded && record.children[0].child.target.matches(manifest.initialRequest)
            && record.commit.previousRevision == manifest.seedRevision + UInt64(index) + 1
            && record.commit.committedRevision == record.commit.previousRevision + 1)
        try #require(commands.insert(record.plan.parent).inserted && commands.insert(record.children[0].child.command).inserted
            && RegistrationWireIdentity.isCanonical(record.plan.parent.rawValue)
            && RegistrationWireIdentity.isCanonical(record.children[0].child.command.rawValue))
        try #require(await services.store.lookupCommit(record.mutation) == .committed(record.commit))
    }
    guard case .loaded(let saved) = await services.store.loadRecordings(), case .loaded(let unfinished) = await services.store.loadUnfinished(),
          case .loaded(let library) = await services.reader.loadLibrary() else { throw BackendContractError.unavailable }
    try #require(saved.revision == backend.revision && originals.revision == backend.revision && library.revision == backend.revision
        && saved.recordings.count == 1 && saved.recordings[0].result == manifest.binding.saveRecord
        && saved.recordings[0].resultCommit == manifest.binding.saveCommit && unfinished.isEmpty
        && library.items.count == 1 && library.history.isEmpty && library.remoteItems.isEmpty && library.mediaRequests.count == 1
        && library.originalUploadAcceptances == backend.originalUploadAcceptances && library.personControls == backend.personControls)
    try #require(library.items[0].uploadCandidateBinding == manifest.binding && library.items[0].operationResults.isEmpty
        && library.items[0].file == .present(byteCount: manifest.sourceInput.bytes) && !library.items[0].isDiscardHistory)
    try metadataSeedVerifyFiles(services.run.url, manifest: manifest)
    try await metadataSeedVerifyCredentials(manifest)
}
nonisolated private func metadataSeedNoOtherOperations(_ backend: BackendStoreSnapshot) throws {
    try #require(backend.batches.isEmpty && backend.verifications.isEmpty && backend.confirmations.isEmpty
        && backend.invalidations.isEmpty && backend.outbox.isEmpty && backend.publications.isEmpty && backend.confirmationStates.isEmpty
        && backend.deliveries.isEmpty && backend.distributionObservations.isEmpty && backend.temporaryMedia.isEmpty
        && backend.photoRegistrations.isEmpty && backend.photoSaveBatches.isEmpty && backend.backgroundTasks.isEmpty
        && backend.remoteInventory.isEmpty && backend.publicationManifests.isEmpty)
}
nonisolated private func metadataSeedVerifyFiles(_ root: URL, manifest: MetadataSeedManifest) throws {
    let oldRoot = URL(fileURLWithPath: manifest.sourceCopy.path).deletingLastPathComponent().standardizedFileURL
    let root = root.standardizedFileURL
    let oldContainer = oldRoot.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let container = root.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    try #require(Array(oldRoot.pathComponents.suffix(3)) == ["Library", "Application Support", "FrameRelayLibrary"]
        && Array(root.pathComponents.suffix(3)) == ["Library", "Application Support", "FrameRelayLibrary"]
        && oldContainer.deletingLastPathComponent() == container.deletingLastPathComponent()
        && container.deletingLastPathComponent().lastPathComponent == "Application"
        && UUID(uuidString: oldContainer.lastPathComponent) != nil && UUID(uuidString: container.lastPathComponent) != nil)
    try #require(try metadataSeedFile(URL(fileURLWithPath: manifest.sourceInput.path)) == manifest.sourceInput)
    try #require(manifest.sourceInput.path.hasSuffix(MetadataSeedConstants.sourceSuffix)
        && manifest.sourceInput.sha256 == MetadataSeedConstants.sourceHash && manifest.sourceInput.bytes == MetadataSeedConstants.sourceBytes
        && manifest.sourceInput.identity == .init(device: MetadataSeedConstants.sourceDevice, inode: MetadataSeedConstants.sourceInode))
    var info = stat(); try #require(lstat(manifest.sourceInput.path, &info) == 0 && info.st_mode & 0o222 == 0)
    let sourceLeaf = "upload-metadata-source-" + manifest.nonce + ".mov", originalLeaf = manifest.binding.reference.rawValue
    let files: [(MetadataSeedFile, URL, URL)] = [
        (manifest.sourceCopy, oldRoot.appendingPathComponent(sourceLeaf), root.appendingPathComponent(sourceLeaf)),
        (manifest.originalFile, oldRoot.appendingPathComponent(originalLeaf + ".mov"), root.appendingPathComponent(originalLeaf + ".mov")),
        (manifest.reservation, oldRoot.appendingPathComponent(originalLeaf + ".reservation"), root.appendingPathComponent(originalLeaf + ".reservation")),
        (manifest.sentinel, metadataSeedSentinel(oldRoot, nonce: manifest.nonce), metadataSeedSentinel(root, nonce: manifest.nonce))]
    for (expected, originalURL, currentURL) in files {
        let actual = try metadataSeedFile(currentURL)
        try #require(expected.path == originalURL.path && actual.signature == expected.signature)
    }
    try #require(manifest.reservation.bytes == 0 && [manifest.sourceCopy, manifest.originalFile, manifest.sentinel].allSatisfy {
        $0.sha256 == manifest.sourceInput.sha256 && $0.bytes == manifest.sourceInput.bytes
    })
}
