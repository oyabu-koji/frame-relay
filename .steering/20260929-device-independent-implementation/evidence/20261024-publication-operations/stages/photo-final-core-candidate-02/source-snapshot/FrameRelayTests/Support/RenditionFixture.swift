import CryptoKit
import Foundation
import Testing
@testable import FrameRelay

/// All identities and receipts in this file are explicit disposable fixtures.
/// No legacy HTTP response is promoted to production distribution evidence.
nonisolated struct RenditionFixture: Sendable {
    let run: ExplorationRunDirectory
    let store: any MediaDiskStore
    let leases: RenditionReadLeases
    let scope: RenditionMediaScope
    let temporary: ManagedTemporaryMedia
    let faults: TemporaryMediaFaultStore?
    let command: RetrieveMediaCommand
    static let capturedAt = Date(timeIntervalSince1970: 1_600_000_123)

    static func make(run: ExplorationRunDirectory, content: ContentIdentity,
                     renditionID: String = "s25-fixture", candidate: StorageCandidate = .sqlite,
                     faultable: Bool = false) async throws -> Self {
        let base: any MediaDiskStore
        switch candidate {
        case .atomicFile: base = try AtomicFileRecordingStore(run: run, mode: .createNew)
        case .sqlite: base = try SQLiteRecordingStore(run: run, mode: .createNew)
        }
        let faults = faultable ? await TemporaryMediaFaultStore(base: base) : nil
        let store: any MediaDiskStore = faults.map { $0 as any MediaDiskStore } ?? base
        let registration = try await mediaRegister(store)
        let original = OriginalContent(capture: .init(rawValue: "s25-fixture-original"),
            generation: .init(rawValue: 1), content: content)
        let rendition = RenditionIdentity(original: original, inputLogIdentity: "synthetic-not-log",
            transformAssetIdentity: "no-quality-claim", transformAssetVersion: "fixture-v1",
            outputConfigurationIdentity: "fixture-movie", conversionVersion: "synthetic-writer",
            rendition: .init(rawValue: renditionID), deliveryContent: content, publicationGeneration: .init(rawValue: 1))
        _ = try await mediaCommit(store, .publication(mediaPublication(rendition, registration: registration)))
        let operation = MediaOperationID(rawValue: "explicit-fixture-distribution")
        let distribution = DistributionReceipt(operation: operation, rendition: rendition, registration: registration,
            commit: .init(key: .distribution(operation, rendition, registration), previousRevision: 0, committedRevision: 1))
        let command = RetrieveMediaCommand(gate: .init(operation: .init(rawValue: "fixture-read"),
            attempt: .init(rawValue: "fixture-attempt"), target: .rendition(rendition), registration: registration, generation: 1),
            distribution: distribution, range: nil)
        let leases = RenditionReadLeases(store: store)
        let scope = try await RenditionMediaScope.open(original: original, leases: leases)
        let temporary = try await ManagedTemporaryMedia.open(root: run.url.appendingPathComponent("temporary", isDirectory: true),
            leases: leases, scope: scope)
        return .init(run: run, store: store, leases: leases, scope: scope, temporary: temporary, faults: faults, command: command)
    }

    func create() async throws -> TemporaryMediaReceipt {
        try await temporary.create(command: command, id: .init(rawValue: UUID().uuidString),
            usageID: .init(rawValue: UUID().uuidString), capturedAt: Self.capturedAt, contentType: "video/quicktime")
    }
    func complete(_ bytes: Data) async throws -> TemporaryMediaReceipt {
        let receipt = try await create()
        for offset in stride(from: 0, to: bytes.count, by: 65_536) {
            let end = min(bytes.count, offset + 65_536)
            try await temporary.store(bytes.subdata(in: offset..<end),
                range: .init(lowerBound: UInt64(offset), upperBound: UInt64(end)), using: receipt.usage)
        }
        return try await temporary.verify(receipt.usage)
    }
}

nonisolated func renditionContent(_ data: Data) throws -> ContentIdentity {
    try .init(byteCount: UInt64(data.count), algorithm: "sha256",
              digest: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
}

actor FixtureRenditionAdmission: RenditionMediaAdmissionPort, RenditionRangeAuthorizationPort {
    private let gate: MediaGateLease
    var denied = false
    private(set) var checks = 0
    private(set) var authorizations = 0
    init(_ gate: MediaGateLease) { self.gate = gate }
    func setDenied(_ value: Bool) { denied = value }
    func check(_ value: MediaGateLease) throws {
        checks += 1
        guard value == gate, !denied else { throw BackendContractError.notOnWiFi }
    }
    func authorize(_ command: RetrieveMediaCommand) throws -> RetrieveMediaCommand {
        try check(command.gate)
        authorizations += 1
        let operation = MediaOperationID(rawValue: "explicit-range-fixture-\(authorizations)")
        let prior = command.distribution
        let proof = DistributionReceipt(operation: operation, rendition: prior.rendition, registration: prior.registration,
            commit: .init(key: .distribution(operation, prior.rendition, prior.registration), previousRevision: 0, committedRevision: 1))
        return .init(gate: command.gate, distribution: proof, range: command.range)
    }
}

@MainActor func renditionEventually(seconds: Double = 15, _ condition: @MainActor () async -> Bool) async -> Bool {
    let end = ContinuousClock.now.advanced(by: .seconds(seconds))
    while !(await condition()) {
        if ContinuousClock.now >= end { return false }
        do { try await Task.sleep(for: .milliseconds(25)) } catch { return false }
    }
    return true
}
