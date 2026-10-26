import Foundation
import Testing
@testable import FrameRelay

struct BackgroundMediaTaskTests {
    @Test func immutableContextRoundTripsWithoutConfusingOSAndMacSessions() throws {
        let intent = try backgroundDomainIntent()
        try intent.validate()
        let bytes = try JSONEncoder().encode(intent)
        let restored = try JSONDecoder().decode(BackgroundMediaTaskIntent.self, from: bytes)
        #expect(restored == intent)
        #expect(restored.context.gateGeneration == 37)
        if case .upload(let session, let lease, let source) = restored.source {
            #expect(session.rawValue == "synthetic-mac-session")
            #expect(restored.session.identifier.rawValue != session.rawValue)
            #expect(lease.accessGeneration.rawValue == 2)
            #expect(lease.epoch.rawValue == "original-reader-epoch")
            #expect(source.file.size == 32)
        } else { Issue.record("The upload source must survive Codable") }
        #expect(!String(decoding: bytes, as: UTF8.self).contains("https://"))
        #expect(!String(decoding: bytes, as: UTF8.self).contains("Authorization"))
    }

    @Test func stopRequestDoesNotProveSDKOrOwnerTermination() throws {
        let intent = try backgroundDomainIntent()
        let binding = backgroundDomainBinding(intent)
        let terminal = BackgroundMediaSDKTerminal(binding: binding, outcome: .cancelled)
        var state = BackgroundMediaTaskState(intent: intent)
        try state.apply(.stopRequested(intent))
        #expect(state.binding == nil && state.terminal == nil && state.ownerClosure == nil)
        #expect(throws: BackendContractError.identityMismatch) { try state.apply(.terminal(intent, terminal)) }
        try state.apply(.attached(intent, binding))
        #expect(throws: BackendContractError.wrongStage) { try state.apply(.resumeRequested(intent, binding)) }
        let closure = backgroundDomainClosure(intent, binding: binding)
        #expect(throws: BackendContractError.readersActive) { try state.apply(.ownerClosed(intent, closure)) }
        try state.apply(.terminal(intent, terminal))
        #expect(state.terminal == terminal && state.ownerClosure == nil)
        let pending = BackgroundMediaOwnerClosure(binding: binding, uploadSource: closure.uploadSource,
            tasksJoined: true, handlesClosed: false)
        #expect(throws: BackendContractError.readersActive) { try state.apply(.ownerClosed(intent, pending)) }
        try state.apply(.ownerClosed(intent, closure))
        #expect(state.stopRequested && !state.resumeRequested)
        #expect(state.ownerClosure == closure)
        #expect(state.intent.source == intent.source)
    }

    @Test(arguments: ["session-generation", "description", "numeric-id", "source"])
    func delayedFactCannotChangeItsExactBindingOrSource(field: String) throws {
        let intent = try backgroundDomainIntent()
        let binding = backgroundDomainBinding(intent)
        var state = BackgroundMediaTaskState(intent: intent)
        try state.apply(.attached(intent, binding))
        try state.apply(.resumeRequested(intent, binding))
        if field == "source" {
            try state.apply(.terminal(intent, .init(binding: binding, outcome: .completed)))
            let wrong = BackgroundMediaOwnerClosure(binding: binding, uploadSource: nil, tasksJoined: true, handlesClosed: true)
            #expect(throws: BackendContractError.identityMismatch) { try state.apply(.ownerClosed(intent, wrong)) }
        } else {
            let other = BackgroundMediaTaskBinding(session: field == "session-generation"
                ? .init(identifier: binding.session.identifier, generation: .init(rawValue: UUID())) : binding.session,
                taskIdentifier: field == "numeric-id" ? binding.taskIdentifier + 1 : binding.taskIdentifier,
                taskDescription: field == "description" ? UUID().uuidString : binding.taskDescription)
            #expect(throws: BackendContractError.identityMismatch) {
                try state.apply(.terminal(intent, .init(binding: other, outcome: .completed)))
            }
        }
        #expect(state.ownerClosure == nil)
    }

    @Test(arguments: ["nonce", "fingerprint", "source-id", "source-size", "gate"])
    func decodedValuesStillRequireBoundaryValidation(field: String) throws {
        let intent = try backgroundDomainIntent()
        var value = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(intent)) as? [String: Any])
        switch field {
        case "nonce": value["taskDescription"] = "https://invalid.example/secret"
        case "fingerprint": value["requestFingerprint"] = ["sha256": "Bearer do-not-persist"]
        case "gate":
            var context = try #require(value["context"] as? [String: Any]); context["gateGeneration"] = 0; value["context"] = context
        default:
            var source = try #require(value["source"] as? [String: Any])
            var upload = try #require(source["upload"] as? [String: Any])
            var file = try #require(upload["source"] as? [String: Any])
            if field == "source-id" { file["id"] = ["rawValue": "../original.mov"] }
            else {
                var identity = try #require(file["file"] as? [String: Any]); identity["size"] = 31; file["file"] = identity
            }
            upload["source"] = file; source["upload"] = upload; value["source"] = source
        }
        let decoded = try JSONDecoder().decode(BackgroundMediaTaskIntent.self, from: JSONSerialization.data(withJSONObject: value))
        #expect(throws: (any Error).self) { try decoded.validate() }
    }

    @Test func fixedDownloadRangeAndMediaLeaseAreIndependentOfUploadIdentity() throws {
        let upload = try backgroundDomainIntent()
        let rendition = publicationRendition(upload.context.target.original)
        let context = BackgroundMediaRequestContext(operation: upload.context.operation, attempt: upload.context.attempt,
            target: .rendition(rendition), registration: upload.context.registration, gateGeneration: upload.context.gateGeneration,
            storeIdentity: upload.context.storeIdentity)
        let lease = MediaReadLease(id: .init(rawValue: "download-reader"), target: .rendition(rendition), operation: context.operation,
            registration: context.registration, context: .transport(context.attempt), epoch: .init(rawValue: "common-writer-epoch"),
            accessGeneration: .init(rawValue: 99))
        let intent = BackgroundMediaTaskIntent(id: upload.id, context: context, session: upload.session,
            taskDescription: upload.taskDescription, requestFingerprint: upload.requestFingerprint,
            source: .download(rendition: rendition, range: try .init(lowerBound: 0, upperBound: 16), lease: lease))
        try intent.validate()
        let invalid = BackgroundMediaTaskIntent(id: intent.id, context: context, session: intent.session,
            taskDescription: intent.taskDescription, requestFingerprint: intent.requestFingerprint,
            source: .download(rendition: rendition, range: try .init(lowerBound: 0, upperBound: 33), lease: lease))
        #expect(throws: BackendContractError.identityMismatch) { try invalid.validate() }
    }
}

nonisolated private func backgroundDomainIntent() throws -> BackgroundMediaTaskIntent {
    let original = OriginalContent(capture: .init(rawValue: "background-domain-original"), generation: .init(rawValue: 1),
        content: try .init(byteCount: 32, algorithm: "sha256", digest: String(repeating: "a", count: 64)))
    let operation = MediaOperationID(rawValue: "background-domain-request")
    let lease = OriginalReadLease(id: .init(rawValue: "background-domain-reader"), original: original, operation: operation,
        accessGeneration: .init(rawValue: 2), epoch: .init(rawValue: "original-reader-epoch"))
    return .init(id: .init(rawValue: UUID().uuidString), context: .init(operation: operation, attempt: .init(rawValue: "background-domain-attempt"),
        target: .original(original), registration: .init(destination: .init(rawValue: "fixture-destination"), id: .init(rawValue: "fixture-registration"),
            generation: .init(rawValue: 1)), gateGeneration: 37, storeIdentity: .init(rawValue: UUID())),
        session: .init(identifier: .init(rawValue: "com.framerelay.synthetic-background"), generation: .init(rawValue: UUID())),
        taskDescription: UUID().uuidString, requestFingerprint: .init(sha256: String(repeating: "b", count: 64)),
        source: .upload(session: .init(rawValue: "synthetic-mac-session"), lease: lease,
            source: .init(id: .init(rawValue: UUID().uuidString), directoryDevice: 1, directoryInode: 2,
                file: .init(device: 1, inode: 3, size: 32, modifiedSeconds: 1, modifiedNanoseconds: 0,
                    changedSeconds: 1, changedNanoseconds: 0), content: original.content)))
}
nonisolated private func backgroundDomainBinding(_ intent: BackgroundMediaTaskIntent) -> BackgroundMediaTaskBinding {
    .init(session: intent.session, taskIdentifier: 7, taskDescription: intent.taskDescription)
}
nonisolated private func backgroundDomainClosure(_ intent: BackgroundMediaTaskIntent,
    binding: BackgroundMediaTaskBinding) -> BackgroundMediaOwnerClosure {
    let source: ManagedUploadSourceIdentity?
    if case .upload(_, _, let value) = intent.source { source = value } else { source = nil }
    return .init(binding: binding, uploadSource: source, tasksJoined: true, handlesClosed: true)
}
