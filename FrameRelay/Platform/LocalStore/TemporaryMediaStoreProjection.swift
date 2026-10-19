import Foundation

extension MediaStoreProjection {
    nonisolated mutating func applyTemporary(_ change: TemporaryMediaChange) throws {
        try MediaStoredValueValidation.text(change.id.rawValue)
        if case .create(let value) = change {
            try requireCurrentRegistration(value.registration)
            try MediaStoredValueValidation.rendition(value.rendition)
            guard !temporaryMedia.contains(where: { $0.id == value.id || $0.leaf == value.leaf }),
                  UUID(uuidString: value.leaf) != nil, value.capturedAt.timeIntervalSince1970.isFinite,
                  ["video/quicktime", "video/mp4"].contains(value.contentType),
                  value.ranges.isEmpty, value.verifiedContent == nil, value.usages.isEmpty,
                  value.releasedUsages.isEmpty, value.fileIdentity == nil,
                  !value.reclaiming, !value.reclaimed,
                  let current = confirmationState(original: value.rendition.original, registration: value.registration),
                  current.current == value.rendition,
                  !current.invalidatedRenditions.contains(value.rendition.rendition) else {
                throw BackendContractError.invalidValue
            }
            temporaryMedia.append(value)
            return
        }
        guard let index = temporaryMedia.firstIndex(where: { $0.id == change.id }) else {
            throw BackendContractError.identityMismatch
        }
        var value = temporaryMedia[index]
        guard !value.reclaimed else { throw BackendContractError.wrongStage }
        switch change {
        case .create: throw BackendContractError.wrongStage
        case .fileCreated(_, let identity):
            guard !value.reclaiming, value.fileIdentity == nil else { throw BackendContractError.wrongStage }
            value.fileIdentity = identity
        case .stored(_, let range):
            guard !value.reclaiming, value.verifiedContent == nil, range.lowerBound < range.upperBound,
                  range.upperBound <= value.rendition.deliveryContent.byteCount else {
                throw BackendContractError.invalidValue
            }
            value.ranges = TemporaryMediaState.merged(value.ranges + [range])
        case .verified(_, let content):
            guard !value.reclaiming, value.complete, content == value.rendition.deliveryContent else {
                throw BackendContractError.identityMismatch
            }
            value.verifiedContent = content
        case .acquire(_, let use):
            try requireCurrentRegistration(value.registration)
            try MediaStoredValueValidation.mediaLease(use.lease)
            try MediaStoredValueValidation.text(use.owner)
            guard let originalIndex = originals.firstIndex(where: { $0.original == value.rendition.original }),
                  originals[originalIndex].removal == nil, originals[originalIndex].invalidation == nil,
                  originals[originalIndex].accessGeneration.rawValue < UInt64.max,
                  use.lease.accessGeneration.rawValue == originals[originalIndex].accessGeneration.rawValue + 1,
                  !originals[originalIndex].mediaReaders.contains(where: { $0.id == use.lease.id }),
                  !originals[originalIndex].readers.contains(where: { $0.id == use.lease.id }),
                  let current = confirmationState(original: value.rendition.original, registration: value.registration),
                  current.current == value.rendition, !current.invalidatedRenditions.contains(value.rendition.rendition)
            else { throw BackendContractError.staleGeneration }
            guard !value.reclaiming, use.usage.media == value.id, use.usage.epoch == use.lease.epoch,
                  value.fileIdentity != nil,
                  use.lease.context == .temporary(value.id, use.usage.id),
                  use.lease.target == .rendition(value.rendition), use.lease.registration == value.registration,
                  !value.usages.contains(where: { $0.usage.id == use.usage.id }),
                  !value.releasedUsages.contains(where: { $0.usage.id == use.usage.id }),
                  use.usage.purpose != .photoHandoff || (value.complete && value.verifiedContent == value.rendition.deliveryContent)
            else { throw BackendContractError.ineligibleOriginal }
            originals[originalIndex].accessGeneration = use.lease.accessGeneration
            originals[originalIndex].requiresMediaReconciliation = true
            originals[originalIndex].mediaReconciliation = nil
            originals[originalIndex].mediaReaders.append(use.lease)
            mediaUses.append(use.lease)
            value.usages.append(use)
        case .release(_, let use):
            guard let position = value.usages.firstIndex(of: use),
                  let originalIndex = originals.firstIndex(where: { $0.original == value.rendition.original }),
                  let leaseIndex = originals[originalIndex].mediaReaders.firstIndex(of: use.lease) else {
                throw BackendContractError.identityMismatch
            }
            originals[originalIndex].mediaReaders.remove(at: leaseIndex)
            value.usages.remove(at: position)
            value.releasedUsages.append(use)
            if value.usages.isEmpty { value.reclaiming = true }
        case .reclaim:
            guard value.usages.isEmpty else { throw BackendContractError.readersActive }
            value.reclaiming = true
        case .reclaimed:
            guard value.reclaiming, value.usages.isEmpty else { throw BackendContractError.wrongStage }
            value.reclaimed = true
        }
        temporaryMedia[index] = value
    }
}
