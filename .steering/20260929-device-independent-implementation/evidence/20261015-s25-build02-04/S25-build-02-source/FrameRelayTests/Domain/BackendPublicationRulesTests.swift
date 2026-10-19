import Testing
@testable import FrameRelay

struct BackendPublicationRulesTests {
    @Test func publicationBeforeDistributionRejectsEveryDelayedOldVersionEntry() throws {
        let fixture = try BackendOperationFixture()
        var ledger = fixture.ledger()
        let manifestOnly = ledger.manifest
        #expect(ledger.recipients.isEmpty)
        let replacement = fixture.replacement()
        try ledger.beginReplacement(replacement)
        #expect(ledger.current == fixture.current)
        #expect(ledger.requiredInvalidations.isEmpty)
        try ledger.commitPublication(backendCommit(.publication(replacement.operation, replacement.candidate),
                                                    revision: ledger.revision))
        #expect(ledger.current == fixture.candidate)
        let published = ledger
        for kind: MediaRetrievalKind in [.full, .range, .resume] {
            let late = fixture.distribution(rendition: manifestOnly, kind: kind)
            // Without a distribution receipt a conforming transport has no byte grant.
            // Actual HTTP byte-zero rejection belongs to the adapter integration tests.
            #expect(throws: BackendContractError.identityMismatch) {
                try ledger.commitDistribution(late, receipt: backendCommit(late.key, revision: ledger.revision))
            }
            #expect(ledger == published)
        }
    }

    @Test func distributionBeforePublicationRequiresInvalidationEvenWithoutConfirmationSync() throws {
        let fixture = try BackendOperationFixture()
        var ledger = fixture.ledger()
        let distribution = fixture.distribution(kind: .range)
        let receipt = try ledger.commitDistribution(distribution,
                                                    receipt: backendCommit(distribution.key, revision: ledger.revision))
        #expect(receipt.isCommitted)
        let replacement = fixture.replacement()
        try ledger.beginReplacement(replacement)
        let required = try #require(ledger.requiredInvalidations.first)
        #expect(required.registration == fixture.registration)
        #expect(required.rendition == fixture.current)
        #expect(required.generation == replacement.invalidationGeneration)
        #expect(throws: BackendContractError.awaitingAcknowledgements) {
            try ledger.commitPublication(backendCommit(.publication(replacement.operation, replacement.candidate),
                                                        revision: ledger.revision))
        }
        #expect(ledger.current == fixture.current)
        try ledger.acceptAcknowledgement(fixture.acknowledgement(for: required))
        try ledger.commitPublication(backendCommit(.publication(replacement.operation, replacement.candidate),
                                                    revision: ledger.revision))
        #expect(ledger.current == fixture.candidate)
        #expect(ledger.recipients.isEmpty)
        #expect(ledger.replacement == nil)

        // Prior acceptance protects the in-flight response, never another old-version request.
        for kind: MediaRetrievalKind in [.full, .range, .resume] {
            let again = fixture.distribution(rendition: receipt.rendition, kind: kind, operation: "old-after-publish")
            #expect(throws: BackendContractError.identityMismatch) {
                try ledger.commitDistribution(again, receipt: backendCommit(again.key, revision: ledger.revision))
            }
        }
    }

    @Test func recipientAddedWhileWaitingMustAcknowledgeBeforePublicationCanCommit() throws {
        let fixture = try BackendOperationFixture()
        var ledger = fixture.ledger()
        let first = fixture.distribution()
        _ = try ledger.commitDistribution(first, receipt: backendCommit(first.key, revision: ledger.revision))
        let replacement = fixture.replacement()
        try ledger.beginReplacement(replacement)
        let initialInvalidation = try #require(ledger.requiredInvalidations.first)
        try ledger.acceptAcknowledgement(fixture.acknowledgement(for: initialInvalidation))
        let stalePublication = backendCommit(.publication(replacement.operation, replacement.candidate),
                                             revision: ledger.revision)

        let newRegistration = RegistrationIdentity(destination: fixture.destination,
                                                   id: .init(rawValue: "new-device-registration"),
                                                   generation: .init(rawValue: 1))
        let arriving = fixture.distribution(registration: newRegistration, kind: .range, operation: "new-device-range")
        _ = try ledger.commitDistribution(arriving, receipt: backendCommit(arriving.key, revision: ledger.revision))
        #expect(ledger.requiredInvalidations.count == 2)
        #expect(ledger.acknowledgements == [fixture.registration])
        #expect(throws: BackendContractError.awaitingAcknowledgements) {
            try ledger.commitPublication(backendCommit(.publication(replacement.operation, replacement.candidate),
                                                        revision: ledger.revision))
        }
        let newlyRequired = try #require(ledger.requiredInvalidations.first { $0.registration == newRegistration })
        try ledger.acceptAcknowledgement(fixture.acknowledgement(for: newlyRequired))
        #expect(throws: BackendContractError.revisionConflict) { try ledger.commitPublication(stalePublication) }
        #expect(ledger.current == fixture.current)
        try ledger.commitPublication(backendCommit(.publication(replacement.operation, replacement.candidate),
                                                    revision: ledger.revision))
        #expect(ledger.current == fixture.candidate)
    }

    @Test func receivedButUncommittedStaleAndForeignAcknowledgementsDoNotAuthorizePublication() throws {
        let fixture = try BackendOperationFixture()
        var ledger = fixture.ledger()
        let distribution = fixture.distribution()
        _ = try ledger.commitDistribution(distribution, receipt: backendCommit(distribution.key, revision: ledger.revision))
        let replacement = fixture.replacement()
        try ledger.beginReplacement(replacement)
        let record = try #require(ledger.requiredInvalidations.first)
        let newRegistration = RegistrationIdentity(destination: fixture.destination, id: fixture.registration.id,
                                                   generation: .init(rawValue: fixture.registration.generation.rawValue + 1))
        let foreignRegistration = RegistrationIdentity(destination: .init(rawValue: "foreign-destination"),
                                                       id: fixture.registration.id, generation: fixture.registration.generation)
        let wrongRecords = [
            InvalidationRecord(id: .init(rawValue: "other-invalidation"), rendition: record.rendition,
                               registration: record.registration, generation: record.generation),
            InvalidationRecord(id: record.id, rendition: fixture.candidate,
                               registration: record.registration, generation: record.generation),
            InvalidationRecord(id: record.id, rendition: record.rendition,
                               registration: newRegistration, generation: record.generation),
            InvalidationRecord(id: record.id, rendition: record.rendition,
                               registration: foreignRegistration, generation: record.generation),
            InvalidationRecord(id: record.id, rendition: record.rendition,
                               registration: record.registration, generation: .init(rawValue: 8))
        ]
        let pending = ledger
        for wrong in wrongRecords {
            #expect(throws: BackendContractError.identityMismatch) {
                try ledger.acceptAcknowledgement(fixture.acknowledgement(for: wrong))
            }
            #expect(ledger == pending)
        }
        let uncommitted = InvalidationAcknowledgement(
            record: record, commit: .init(key: record.key, previousRevision: 60, committedRevision: 60))
        #expect(!uncommitted.isCommitted)
        #expect(throws: BackendContractError.identityMismatch) { try ledger.acceptAcknowledgement(uncommitted) }
        #expect(ledger.acknowledgements.isEmpty)
        #expect(throws: BackendContractError.awaitingAcknowledgements) {
            try ledger.commitPublication(backendCommit(.publication(replacement.operation, replacement.candidate),
                                                        revision: ledger.revision))
        }
        let valid = fixture.acknowledgement(for: record)
        try ledger.acceptAcknowledgement(valid)
        try ledger.acceptAcknowledgement(valid)
        #expect(ledger.acknowledgements.count == 1)
    }

    @Test func missingOldRegistrationAcknowledgementBlocksOnlyItsReplacement() throws {
        let fixture = try BackendOperationFixture()
        var blocked = fixture.ledger()
        let oldDistribution = fixture.distribution()
        _ = try blocked.commitDistribution(oldDistribution,
                                            receipt: backendCommit(oldDistribution.key, revision: blocked.revision))
        let replacement = fixture.replacement()
        try blocked.beginReplacement(replacement)

        // A newly registered device can still receive the current version; its ACK cannot
        // stand in for the unreachable old registration. No expiry substitutes for that ACK.
        let newRegistration = RegistrationIdentity(destination: fixture.destination,
                                                   id: .init(rawValue: "replacement-device"), generation: .init(rawValue: 1))
        let newDistribution = fixture.distribution(registration: newRegistration, operation: "new-device-current")
        let ordinaryUse = try blocked.commitDistribution(newDistribution,
                                                          receipt: backendCommit(newDistribution.key, revision: blocked.revision))
        #expect(ordinaryUse.isCommitted)
        #expect(ordinaryUse.rendition == fixture.current)
        let newInvalidation = try #require(blocked.requiredInvalidations.first { $0.registration == newRegistration })
        try blocked.acceptAcknowledgement(fixture.acknowledgement(for: newInvalidation))
        #expect(blocked.requiredInvalidations.contains { $0.registration == fixture.registration })
        #expect(throws: BackendContractError.awaitingAcknowledgements) {
            try blocked.commitPublication(backendCommit(.publication(replacement.operation, replacement.candidate),
                                                         revision: blocked.revision))
        }
        #expect(blocked.current == fixture.current)
        #expect(blocked.replacement == replacement)

        let otherCurrent = try BackendOperationFixture.makeRendition(original: fixture.secondOriginal,
                                                                     name: "other-V1", generation: 4)
        let otherCandidate = try BackendOperationFixture.makeRendition(original: fixture.secondOriginal,
                                                                       name: "other-V2", generation: 5)
        var independent = fixture.ledger(current: otherCurrent)
        let independentReplacement = fixture.replacement(previous: otherCurrent, candidate: otherCandidate)
        try independent.beginReplacement(independentReplacement)
        try independent.commitPublication(backendCommit(.publication(independentReplacement.operation, otherCandidate),
                                                          revision: independent.revision))
        #expect(independent.current == otherCandidate)
        #expect(blocked.current == fixture.current)
    }

    @Test func stalePublicationGenerationAndDifferentOriginalCannotBeginReplacement() throws {
        let fixture = try BackendOperationFixture()
        var ledger = fixture.ledger()
        let original = ledger
        let sameGeneration = try BackendOperationFixture.makeRendition(original: fixture.original,
                                                                       name: "different-output", generation: 4)
        #expect(throws: BackendContractError.staleGeneration) {
            try ledger.beginReplacement(fixture.replacement(candidate: sameGeneration))
        }
        #expect(throws: BackendContractError.staleGeneration) {
            try ledger.beginReplacement(fixture.replacement(generation: 8))
        }
        let differentOriginal = try BackendOperationFixture.makeRendition(original: fixture.secondOriginal,
                                                                          name: "wrong-original", generation: 5)
        #expect(throws: BackendContractError.identityMismatch) {
            try ledger.beginReplacement(fixture.replacement(candidate: differentOriginal))
        }
        #expect(throws: BackendContractError.identityMismatch) {
            try ledger.beginReplacement(fixture.replacement(previous: fixture.candidate))
        }
        #expect(ledger == original)
    }

    @Test func mismatchedDistributionCommitCannotAddRecipientOrConsumeRevision() throws {
        let fixture = try BackendOperationFixture()
        var ledger = fixture.ledger()
        let intent = fixture.distribution()
        let before = ledger
        let wrongCommit = backendCommit(.distribution(intent.operation, fixture.candidate, intent.registration),
                                         revision: ledger.revision)
        #expect(throws: BackendContractError.revisionConflict) {
            try ledger.commitDistribution(intent, receipt: wrongCommit)
        }
        #expect(throws: BackendContractError.revisionConflict) {
            try ledger.commitDistribution(intent, receipt: backendCommit(intent.key, revision: ledger.revision - 1))
        }
        #expect(ledger == before)
        let otherDestination = RegistrationIdentity(destination: .init(rawValue: "other-destination"),
                                                     id: fixture.registration.id, generation: fixture.registration.generation)
        let foreign = fixture.distribution(registration: otherDestination)
        #expect(throws: BackendContractError.identityMismatch) {
            try ledger.commitDistribution(foreign, receipt: backendCommit(foreign.key, revision: ledger.revision))
        }
        #expect(ledger == before)
    }
}
