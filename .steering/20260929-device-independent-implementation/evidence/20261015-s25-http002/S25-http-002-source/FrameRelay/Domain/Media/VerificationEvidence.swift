import Foundation

nonisolated enum OriginalVerificationMethod: Equatable, Sendable, Codable {
    case finalDestinationReadBack(ContentIdentity)
    case assemblyOnly(ContentIdentity)
}

/// The server's proof and the device's durable adoption are separate facts.
nonisolated struct StoredVerificationEvidence: Equatable, Sendable, Codable {
    let command: MediaOperationID
    let expected: RemoteOperationContext
    let evidence: VerificationEvidence
    let commit: BackendCommitReceipt

    var key: BackendCommitKey { .verification(command, evidence.id, expected) }
    var isCommitted: Bool {
        expected == evidence.context && commit.matches(key, revision: commit.previousRevision)
    }
}

/// Committed server proof; upload completion and legacy flags cannot construct this proof implicitly.
nonisolated struct VerificationEvidence: Equatable, Sendable, Codable {
    let id: EvidenceID
    let context: RemoteOperationContext
    let finalSaveCompleted: Bool
    let verification: OriginalVerificationMethod
    let committed: Bool
    let schemaVersion: String
    let observedAt: Date

    func verifies(_ original: OriginalContent, destination: DestinationIdentity,
                  supportedSchemas: Set<String>) -> Bool {
        guard context.registration.destination == destination, context.target == .original(original),
              context.session != nil, finalSaveCompleted, committed,
              supportedSchemas.contains(schemaVersion),
              case .finalDestinationReadBack(let content) = verification else { return false }
        return content == original.content
    }
}

nonisolated enum CleanupIneligibility: Equatable, Sendable {
    case originalUnavailable, verificationMissing, confirmationMissing
}

nonisolated enum CleanupEligibility: Equatable, Sendable {
    case eligible(OriginalContent, InvalidationGeneration)
    case ineligible(CleanupIneligibility)
}

nonisolated enum CleanupRules {
    /// No current-network, current-Mac-existence or Photos-saved condition is added here.
    static func evaluate(original: OriginalDescriptor, lastVerification: StoredVerificationEvidence?,
                         confirmation: ConfirmationState, supportedSchemas: Set<String>) -> CleanupEligibility {
        guard original.isTransferEligible else { return .ineligible(.originalUnavailable) }
        guard let lastVerification, lastVerification.isCommitted,
              lastVerification.evidence.verifies(original.original, destination: confirmation.registration.destination,
                                                 supportedSchemas: supportedSchemas) else {
            return .ineligible(.verificationMissing)
        }
        guard let record = confirmation.validConfirmation,
              record.intent.playback.distribution.rendition.original == original.original else {
            return .ineligible(.confirmationMissing)
        }
        return .eligible(original.original, confirmation.generation)
    }
}
