import Foundation
import Testing
@testable import FrameRelay

struct PhotoRegistrationTests {
    @Test func intentRoundTripPreservesCaptureDateAndExactMediaUse() throws {
        let intent = try photoDomainIntent()
        let decoded = try JSONDecoder().decode(PhotoRegistrationIntent.self, from: JSONEncoder().encode(intent))
        #expect(decoded == intent)
        #expect(decoded.capturedAt == Date(timeIntervalSince1970: 1_600_000_123))
        #expect(decoded.key.capture == intent.rendition.original.capture)
        #expect(decoded.key.rendition == intent.rendition.rendition)
        let otherPublication = RenditionIdentity(original: intent.rendition.original,
            inputLogIdentity: intent.rendition.inputLogIdentity,
            transformAssetIdentity: intent.rendition.transformAssetIdentity,
            transformAssetVersion: intent.rendition.transformAssetVersion,
            outputConfigurationIdentity: intent.rendition.outputConfigurationIdentity,
            conversionVersion: intent.rendition.conversionVersion,
            rendition: intent.rendition.rendition, deliveryContent: intent.rendition.deliveryContent,
            publicationGeneration: .init(rawValue: 2))
        #expect(PhotoRegistrationKey(rendition: otherPublication) == intent.key)
    }

    @Test(arguments: ["purpose", "media", "epoch", "digest", "operation", "capture", "retry"])
    func decoderRejectsInvalidNestedIntentValues(corruption: String) throws {
        let intent = try photoDomainIntent()
        var value = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(intent)) as? [String: Any])
        switch corruption {
        case "purpose":
            var usage = try #require(value["usage"] as? [String: Any])
            usage["purpose"] = ["playback": [:]]
            value["usage"] = usage
        case "media": value["media"] = ["rawValue": "different-media"]
        case "epoch":
            var usage = try #require(value["usage"] as? [String: Any])
            usage.removeValue(forKey: "epoch")
            value["usage"] = usage
        case "digest":
            var rendition = try #require(value["rendition"] as? [String: Any])
            var content = try #require(rendition["deliveryContent"] as? [String: Any])
            content["digest"] = "not-a-hash"
            rendition["deliveryContent"] = content
            value["rendition"] = rendition
        case "capture":
            var rendition = try #require(value["rendition"] as? [String: Any])
            var original = try #require(rendition["original"] as? [String: Any])
            original["capture"] = ["rawValue": "  "]
            rendition["original"] = original
            value["rendition"] = rendition
        case "retry": value["retryOf"] = ["rawValue": intent.operation.rawValue]
        default: value["operation"] = ["rawValue": "  "]
        }
        let data = try JSONSerialization.data(withJSONObject: value)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(PhotoRegistrationIntent.self, from: data) }
    }

    @Test func handoffRequiresFiniteDateAndCurrentPhotoUse() throws {
        let intent = try photoDomainIntent()
        let handoff = PhotoMediaHandoff(media: intent.media, rendition: intent.rendition,
            capturedAt: Date(timeIntervalSinceReferenceDate: .infinity), usage: intent.usage)
        #expect(throws: BackendContractError.invalidValue) {
            try PhotoRegistrationIntent(operation: intent.operation, handoff: handoff)
        }
        let invalidIdentifier = Data("{\"rawValue\":\"   \"}".utf8)
        #expect(throws: BackendContractError.invalidValue) {
            try JSONDecoder().decode(PhotoAssetIdentifier.self, from: invalidIdentifier)
        }
        let invalidKey = Data("{\"capture\":{\"rawValue\":\"\"},\"rendition\":{\"rawValue\":\"v1\"}}".utf8)
        #expect(throws: BackendContractError.invalidValue) {
            try JSONDecoder().decode(PhotoRegistrationKey.self, from: invalidKey)
        }
    }

    @Test func addCommandBindsReceiptAndResolvedHandoff() throws {
        let intent = try photoDomainIntent()
        let use = photoDomainUse(intent)
        let receipt = BackendCommitReceipt(key: .photo(intent.operation, intent.key),
            previousRevision: 7, committedRevision: 8)
        let registration = CommittedPhotoRegistrationIntent(intent: intent, mediaUse: use, commit: receipt)
        let file = URL(fileURLWithPath: "/explicit-disposable-fixture.mov")
        let command = try PhotoLibraryAddCommand(registration: registration,
            media: .init(url: file, handoff: intent.handoff))
        #expect(command.registration.intent == intent)
        #expect(registration.mutation.expectedRevision == 7)
        #expect(registration.mutation.change == .photo(command: intent.operation, value: .intent(intent)))
        let invalid = CommittedPhotoRegistrationIntent(intent: intent, mediaUse: use,
            commit: .init(key: receipt.key, previousRevision: 7, committedRevision: 9))
        #expect(throws: BackendContractError.identityMismatch) {
            try PhotoLibraryAddCommand(registration: invalid, media: .init(url: file, handoff: intent.handoff))
        }
        let changed = PhotoMediaHandoff(media: intent.media, rendition: intent.rendition,
            capturedAt: intent.capturedAt.addingTimeInterval(1), usage: intent.usage)
        #expect(throws: BackendContractError.identityMismatch) {
            try PhotoLibraryAddCommand(registration: registration, media: .init(url: file, handoff: changed))
        }
        #expect(throws: BackendContractError.identityMismatch) {
            try PhotoLibraryAddCommand(registration: registration,
                media: .init(url: URL(string: "https://example.invalid/video.mov")!, handoff: intent.handoff))
        }
    }

    @Test func authorizationLimitsAndNotFoundDoNotChangeHistoricalSuccess() throws {
        let intent = try photoDomainIntent()
        let identifier = try PhotoAssetIdentifier(rawValue: "exact-photo-asset")
        let receipt = BackendCommitReceipt(key: .photo(intent.operation, intent.key), previousRevision: 1, committedRevision: 2)
        var record = PhotoRegistrationRecord(registration: .init(intent: intent,
            mediaUse: photoDomainUse(intent), commit: receipt))
        record.results.append(.init(command: .init(rawValue: "result"),
            result: .init(intent: intent, outcome: .succeeded(localIdentifier: identifier)), commit: receipt))
        let notFound = try PhotoPresenceObservation(intent: intent, generation: 1, identifier: identifier,
            authorization: .limited, presence: .notFound)
        record.presenceObservations.append(.init(command: .init(rawValue: "lookup"), observation: notFound, commit: receipt))
        #expect(record.outcome == .succeeded(localIdentifier: identifier))
        #expect(record.currentPresence?.presence == .notFound)
        #expect(record.outcome?.permitsExplicitRetry == false)
        #expect(throws: BackendContractError.invalidValue) {
            try PhotoPresenceObservation(intent: intent, generation: 2, identifier: identifier,
                authorization: .denied, presence: .present)
        }
        #expect(throws: BackendContractError.invalidValue) {
            try PhotoPresenceObservation(intent: intent, generation: 0, identifier: nil,
                authorization: .notDetermined, presence: .correspondenceUnknown)
        }
        #expect(PhotoRegistrationOutcome.succeeded(localIdentifier: nil).permitsExplicitRetry == false)
        #expect(PhotoRegistrationOutcome.unknown(localIdentifier: nil).permitsExplicitRetry == false)
        #expect(PhotoRegistrationOutcome.notAttempted(.authorizationRequired).permitsExplicitRetry)
        #expect(PhotoRegistrationOutcome.failed(.invalidMedia).permitsExplicitRetry)
    }
}

nonisolated private func photoDomainIntent() throws -> PhotoRegistrationIntent {
    let content = try ContentIdentity(byteCount: 32, algorithm: "sha256", digest: String(repeating: "a", count: 64))
    let rendition = RenditionIdentity(original: .init(capture: .init(rawValue: "photo-capture"),
        generation: .init(rawValue: 1), content: content), inputLogIdentity: "explicit-fixture-input",
        transformAssetIdentity: "no-quality-claim", transformAssetVersion: "fixture-v1",
        outputConfigurationIdentity: "fixture", conversionVersion: "fixture-v1",
        rendition: .init(rawValue: "photo-rendition-v1"), deliveryContent: content, publicationGeneration: .init(rawValue: 1))
    let media = TemporaryMediaID(rawValue: "photo-media")
    let usage = TemporaryMediaUsage(id: .init(rawValue: "photo-usage"), purpose: .photoHandoff,
        media: media, epoch: .init(rawValue: "photo-epoch"))
    return try .init(operation: .init(rawValue: "photo-operation"), handoff: .init(media: media,
        rendition: rendition, capturedAt: Date(timeIntervalSince1970: 1_600_000_123), usage: usage))
}

nonisolated private func photoDomainUse(_ intent: PhotoRegistrationIntent) -> TemporaryMediaUseRecord {
    .init(usage: intent.usage, lease: .init(id: .init(rawValue: "photo-lease"), target: .rendition(intent.rendition),
        operation: intent.operation, registration: .init(destination: .init(rawValue: "fixture-destination"),
            id: .init(rawValue: "fixture-registration"), generation: .init(rawValue: 1)),
        context: .temporary(intent.media, intent.usage.id), epoch: intent.usage.epoch!, accessGeneration: .init(rawValue: 1)),
        owner: "fixture-owner")
}
