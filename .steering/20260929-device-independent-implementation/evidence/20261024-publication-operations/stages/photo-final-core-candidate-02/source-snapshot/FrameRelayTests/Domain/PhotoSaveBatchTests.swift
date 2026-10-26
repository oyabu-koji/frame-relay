import Foundation
import Testing
@testable import FrameRelay

struct PhotoSaveBatchTests {
    @Test func fixedTargetsRoundTripWithoutNormalizingOpaqueCaptureBytes() throws {
        let left = try photoBatchDomainSource(capture: "\u{e9}")
        let right = try photoBatchDomainSource(capture: "e\u{301}")
        #expect(left == right)
        #expect(!PhotoSaveBatchValueValidation.exact(left, right))
        let a = try PhotoSaveBatchTarget(source: left, operation: .init(rawValue: "child-a"))
        let b = try PhotoSaveBatchTarget(source: right, operation: .init(rawValue: "child-b"))
        let batch = try PhotoSaveBatch(operation: .init(rawValue: "batch"), storeIdentity: left.storeIdentity, targets: [a, b])
        let decoded = try JSONDecoder().decode(PhotoSaveBatch.self, from: JSONEncoder().encode(batch))
        #expect(PhotoSaveBatchValueValidation.exact(decoded, batch))
        #expect(decoded.targets[0].source.rendition.original.capture.rawValue.utf8.elementsEqual("\u{e9}".utf8))
        #expect(decoded.targets[1].source.rendition.original.capture.rawValue.utf8.elementsEqual("e\u{301}".utf8))
    }

    @Test(arguments: ["empty", "key", "child", "parent", "store", "self-retry"])
    func fixedBatchRejectsAmbiguousOwnership(mode: String) throws {
        let source = try photoBatchDomainSource()
        let target = try PhotoSaveBatchTarget(source: source, operation: .init(rawValue: "child"))
        let other = try PhotoSaveBatchTarget(source: photoBatchDomainSource(capture: "other"), operation: target.operation)
        switch mode {
        case "empty":
            #expect(throws: BackendContractError.invalidValue) {
                try PhotoSaveBatch(operation: .init(rawValue: "batch"), storeIdentity: source.storeIdentity, targets: [])
            }
        case "key":
            let duplicate = try PhotoSaveBatchTarget(source: source, operation: .init(rawValue: "other-child"))
            #expect(throws: BackendContractError.duplicateTarget) {
                try PhotoSaveBatch(operation: .init(rawValue: "batch"), storeIdentity: source.storeIdentity, targets: [target, duplicate])
            }
        case "child":
            #expect(throws: BackendContractError.duplicateTarget) {
                try PhotoSaveBatch(operation: .init(rawValue: "batch"), storeIdentity: source.storeIdentity, targets: [target, other])
            }
        case "parent":
            #expect(throws: BackendContractError.duplicateTarget) {
                try PhotoSaveBatch(operation: target.operation, storeIdentity: source.storeIdentity, targets: [target])
            }
        case "store":
            #expect(throws: BackendContractError.duplicateTarget) {
                try PhotoSaveBatch(operation: .init(rawValue: "batch"), storeIdentity: .init(rawValue: UUID()), targets: [target])
            }
        default:
            #expect(throws: BackendContractError.invalidValue) {
                try PhotoSaveBatchTarget(source: source, operation: target.operation, retryOf: target.operation)
            }
        }
    }

    @Test func decoderRejectsInvalidSourceEvenWhenItWasEncodedWithoutAThrowingInitializer() throws {
        let good = try photoBatchDomainSource()
        let invalid = PhotoSaveSource(storeIdentity: good.storeIdentity, registration: good.registration,
            rendition: good.rendition, media: .init(rawValue: ""), capturedAt: good.capturedAt,
            directoryIdentity: good.directoryIdentity, fileIdentity: good.fileIdentity, leaf: good.leaf, contentType: good.contentType)
        let data = try JSONEncoder().encode(invalid)
        let source = try JSONDecoder().decode(PhotoSaveSource.self, from: data)
        #expect(throws: BackendContractError.invalidValue) { try source.validate() }
        #expect(throws: BackendContractError.invalidValue) {
            try PhotoSaveBatchTarget(source: source, operation: .init(rawValue: "child"))
        }
        let target = try PhotoSaveBatchTarget(source: good, operation: .init(rawValue: "child"))
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(target)) as? [String: Any])
        object["source"] = try JSONSerialization.jsonObject(with: data)
        let targetData = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(PhotoSaveBatchTarget.self, from: targetData) }
    }

    @Test func committedChildCannotBorrowCanonicallyEqualCommandOrBatchReceipt() throws {
        let source = try photoBatchDomainSource()
        let target = try PhotoSaveBatchTarget(source: source, operation: .init(rawValue: "child"))
        let batch = MediaOperationID(rawValue: "\u{e9}")
        let alias = MediaOperationID(rawValue: "e\u{301}")
        let receipt = BackendCommitReceipt(key: .photoBatch(target.operation, batch), previousRevision: 5, committedRevision: 6)
        let valid = CommittedPhotoSaveBatchChild(batch: batch, target: target, command: target.operation,
            commit: receipt, expectedStoreIdentity: source.storeIdentity)
        #expect(valid.isCommitted)
        #expect(valid.mutation.expectedRevision == 5 && valid.mutation.expectedStoreIdentity == source.storeIdentity)
        let changed = CommittedPhotoSaveBatchChild(batch: alias, target: target, command: target.operation,
            commit: receipt, expectedStoreIdentity: source.storeIdentity)
        #expect(batch == alias && !changed.isCommitted)
        let foreign = CommittedPhotoSaveBatchChild(batch: batch, target: target, command: target.operation,
            commit: receipt, expectedStoreIdentity: .init(rawValue: UUID()))
        #expect(!foreign.isCommitted)
    }
}

nonisolated private func photoBatchDomainSource(capture: String = "fixture") throws -> PhotoSaveSource {
    let identity = RegistrationStoreIdentity(rawValue: UUID(uuidString: "62caef5e-4965-49ef-a626-df42ad4152db")!)
    let registration = RegistrationIdentity(destination: .init(rawValue: "fixture-destination"), id: .init(rawValue: "registration"),
        generation: .init(rawValue: 1))
    let original = try publicationOriginal(capture)
    return .init(storeIdentity: identity, registration: registration, rendition: publicationRendition(original),
        media: .init(rawValue: "fixture-media"), capturedAt: RenditionFixture.capturedAt,
        directoryIdentity: .init(device: 1, inode: 2), fileIdentity: .init(device: 1, inode: 3),
        leaf: "A7D287A2-3A7E-48FE-B377-5DA19413F8D4.mov", contentType: "video/quicktime")
}
