import Foundation

nonisolated struct RecordingStoreDocument: Codable {
    static let currentSchema = 5
    var schema = currentSchema
    /// Nil for stores which have not explicitly established registration identity.
    /// Reading or migrating a legacy document never generates one.
    var storeIdentity: RegistrationStoreIdentity? = nil
    var entries: [Entry] = []
    /// Store transaction order, independent of capture/settings/content generations.
    var transactionRevision: UInt64 = 0
    var originalJournal: [OriginalStoreJournalEntry] = []
    var backendJournal: [BackendStoreJournalEntry] = []
    /// Original entries at/before this revision retain schema-3 acceptance rules.
    /// Never advances after migration; current guards do not invalidate old facts.
    var legacyRevision: UInt64 = 0

    struct Entry: Codable {
        let intentToken: CaptureCommandToken
        let intent: RecordingIntent
        var revision: UInt64 = 1
        var resultToken: CaptureCommandToken?
        var result: RecordingResultRecord?
    }

    static func decode(_ data: Data) throws -> Self {
        struct Header: Decodable { let schema: Int }
        let decoder = JSONDecoder()
        let header: Header
        do { header = try decoder.decode(Header.self, from: data) }
        catch { throw ExplorationStorageError.corruptStore }
        guard (1...currentSchema).contains(header.schema) else { throw ExplorationStorageError.unknownSchema }
        do {
            let document: Self
            if header.schema == 1 {
                struct LegacyDocument: Decodable { let entries: [Entry] }
                let legacy = try decoder.decode(LegacyDocument.self, from: data)
                var migrated = Self()
                migrated.entries = legacy.entries
                for entry in legacy.entries {
                    let next = migrated.transactionRevision.addingReportingOverflow(entry.revision)
                    guard !next.overflow else { throw ExplorationStorageError.corruptStore }
                    migrated.transactionRevision = next.partialValue
                }
                migrated.legacyRevision = migrated.transactionRevision
                document = migrated
            } else if header.schema == 2 {
                struct PreviousDocument: Decodable {
                    let entries: [Entry]
                    let transactionRevision: UInt64
                }
                let previous = try decoder.decode(PreviousDocument.self, from: data)
                var migrated = Self()
                migrated.entries = previous.entries
                migrated.transactionRevision = previous.transactionRevision
                migrated.legacyRevision = previous.transactionRevision
                document = migrated
            } else if header.schema == 3 {
                struct PreviousDocument: Decodable {
                    let entries: [Entry]
                    let transactionRevision: UInt64
                    let originalJournal: [OriginalStoreJournalEntry]
                }
                let previous = try decoder.decode(PreviousDocument.self, from: data)
                var migrated = Self()
                migrated.entries = previous.entries
                migrated.transactionRevision = previous.transactionRevision
                migrated.originalJournal = previous.originalJournal
                migrated.legacyRevision = previous.transactionRevision
                document = migrated
            } else if header.schema == 4 {
                var migrated = try decoder.decode(Self.self, from: data)
                guard migrated.storeIdentity == nil else { throw ExplorationStorageError.corruptStore }
                migrated.schema = currentSchema
                document = migrated
            } else {
                document = try decoder.decode(Self.self, from: data)
            }
            try document.validate()
            return document
        } catch { throw ExplorationStorageError.corruptStore }
    }

    func validate() throws {
        guard schema == Self.currentSchema else { throw ExplorationStorageError.unknownSchema }
        var captures = Set<CaptureID>()
        var operations = Set<CaptureOperationID>()
        var originals = Set<CaptureOriginalReference>()
        var recordingRevisions: UInt64 = 0
        for entry in entries {
            let next = recordingRevisions.addingReportingOverflow(entry.revision)
            guard !next.overflow else { throw CaptureContractError.invalidValue }
            recordingRevisions = next.partialValue
            try RecordingStoredValueValidation.intent(entry.intent)
            guard captures.insert(entry.intent.context.capture).inserted,
                  operations.insert(entry.intent.operation).inserted,
                  originals.insert(entry.intent.original).inserted else {
                throw CaptureContractError.evidenceMismatch
            }
            var lifecycle = try RecordingSaveLifecycle(intent: entry.intent, intentToken: entry.intentToken, revision: 0)
            try lifecycle.acceptIntentCommit(.init(token: entry.intentToken, previousRevision: 0, committedRevision: 1))
            switch (entry.resultToken, entry.result) {
            case (nil, nil):
                guard entry.revision == 1 else { throw CaptureContractError.revisionConflict }
            case (.some(let token), .some(let result)):
                guard entry.revision == 2, result.intent == entry.intent else {
                    throw CaptureContractError.evidenceMismatch
                }
                try Self.validateResult(result, token: token, lifecycle: &lifecycle)
            default: throw CaptureContractError.evidenceMismatch
            }
        }
        let recordingAndOriginalRevisionCount = recordingRevisions.addingReportingOverflow(UInt64(originalJournal.count))
        let total = recordingAndOriginalRevisionCount.partialValue.addingReportingOverflow(UInt64(backendJournal.count))
        guard !recordingAndOriginalRevisionCount.overflow, !total.overflow, transactionRevision == total.partialValue,
              legacyRevision <= transactionRevision else { throw CaptureContractError.revisionConflict }
        _ = try replayStore()
    }

    mutating func apply(_ command: RecordingStoreCommand) throws -> RecordingCommitReceipt {
        let token: CaptureCommandToken
        let expected: UInt64
        switch command {
        case .commitIntent(let incoming, let revision, let intent):
            token = incoming; expected = revision
            try RecordingStoredValueValidation.intent(intent)
            guard token.context == intent.context, token.operation == intent.operation else {
                throw CaptureContractError.wrongContext
            }
            guard expected == 0 else { throw CaptureContractError.revisionConflict }
            guard !entries.contains(where: { $0.intent.context.capture == intent.context.capture
                || $0.intent.operation == intent.operation || $0.intent.original == intent.original }) else {
                throw CaptureContractError.duplicateOrOutOfOrder
            }
            entries.append(Entry(intentToken: token, intent: intent))
        case .commitResult(let incoming, let revision, let record):
            token = incoming; expected = revision
            guard token.context == record.intent.context, token.operation == record.intent.operation else {
                throw CaptureContractError.wrongContext
            }
            guard let index = entries.firstIndex(where: { $0.intent.context == token.context }) else {
                throw CaptureContractError.wrongContext
            }
            let old = entries[index]
            guard old.revision == expected else { throw CaptureContractError.revisionConflict }
            guard old.result == nil else { throw CaptureContractError.duplicateOrOutOfOrder }
            guard record.intent == old.intent, token.operation == old.intent.operation else {
                throw CaptureContractError.evidenceMismatch
            }
            var lifecycle = try RecordingSaveLifecycle(intent: old.intent, intentToken: old.intentToken, revision: 0)
            try lifecycle.acceptIntentCommit(.init(token: old.intentToken, previousRevision: 0, committedRevision: 1))
            try Self.validateResult(record, token: token, lifecycle: &lifecycle)
            entries[index].resultToken = token
            entries[index].result = record
            entries[index].revision = 2
        }
        let next = transactionRevision.addingReportingOverflow(1)
        guard !next.overflow else { throw CaptureContractError.revisionConflict }
        transactionRevision = next.partialValue
        try validate()
        return RecordingCommitReceipt(token: token, previousRevision: expected, committedRevision: expected + 1)
    }

    private static func validateResult(_ record: RecordingResultRecord, token: CaptureCommandToken,
                                       lifecycle: inout RecordingSaveLifecycle) throws {
        try RecordingStoredValueValidation.result(record)
        try lifecycle.acceptRecordingEnd(context: record.intent.context, evidence: record.end)
        try lifecycle.acceptFile(record.file)
        _ = try lifecycle.acceptInspection(record.inspection, resultToken: token)
        guard lifecycle.resultRecord == record else { throw CaptureContractError.evidenceMismatch }
    }

    var unfinished: [UnfinishedRecording] {
        entries.compactMap { entry in
            if entry.result?.result == .saved { return nil }
            return UnfinishedRecording(intent: entry.intent, revision: entry.revision, lastResult: entry.result?.result)
        }
    }
}

/// Codable synthesis bypasses validating initializers. Revalidate every persisted
/// input and every typed observation before it is used or admitted to the store.
nonisolated enum RecordingStoredValueValidation {
    static func text(_ value: String) throws {
        guard !value.isEmpty, value.utf8.count <= 1024, !value.unicodeScalars.contains(where: { $0.value < 32 }) else {
            throw CaptureContractError.invalidValue
        }
    }

    static func reason(_ reason: CaptureUnavailableReason) throws {
        if case .adapterFailure(let code) = reason { try text(code) }
    }

    static func time(_ observation: CaptureTimeObservation) throws {
        switch observation {
        case .unavailable(let why): try reason(why)
        case .observed(let stamp, let method):
            guard stamp.value.timescale > 0, stamp.resolution.timescale > 0,
                  stamp.resolution.ticks > 0,
                  stamp.uncertainty.map({ $0.timescale > 0 && $0.ticks >= 0 }) ?? true else {
                throw CaptureContractError.invalidValue
            }
            switch stamp.clock {
            case .mediaPTS(let value), .captureDevice(let value), .monotonic(let value), .wallClock(let value):
                try text(value)
            case .captureSession(let session): try text(session.rawValue)
            }
            try observationMethod(method)
        }
    }

    static func observationMethod(_ method: CaptureObservationMethod) throws {
        switch method {
        case .direct(let source): try text(source)
        case .inferred(let method, let evidence):
            try text(method)
            guard !evidence.isEmpty else { throw CaptureContractError.invalidValue }
            for item in evidence { try text(item.rawValue) }
        }
    }

    static func settings(_ configuration: CaptureConfiguration, _ exposure: CaptureManualExposure, _ zoom: Double) throws {
        _ = try CaptureConfiguration(camera: configuration.camera, width: configuration.width,
                                     height: configuration.height, framesPerSecond: configuration.framesPerSecond,
                                     codec: configuration.codec, logEncoding: configuration.logEncoding,
                                     stabilizationMode: configuration.stabilizationMode)
        try text(configuration.camera); try text(configuration.stabilizationMode)
        guard exposure.shutter.timescale > 0, zoom.isFinite, zoom > 0 else { throw CaptureContractError.invalidValue }
        _ = try CaptureManualExposure(shutter: exposure.shutter, iso: exposure.iso, aperture: exposure.aperture)
    }

    static func intent(_ intent: RecordingIntent) throws {
        try text(intent.context.capture.rawValue); try text(intent.context.generation.session.rawValue)
        try text(intent.operation.rawValue); try text(intent.applied.operation.rawValue); try text(intent.trialReference)
        do { try ExplorationRunDirectory.validateReference(intent.original) }
        catch { throw CaptureContractError.invalidValue }
        try settings(intent.desired.configuration, intent.desired.exposure, intent.desired.zoom)
        try time(intent.acceptedAt)
        guard intent.context.generation == intent.applied.generation,
              case .observed(let values, let at, let method) = intent.applied.values,
              values.matches(intent.desired) else { throw CaptureContractError.evidenceMismatch }
        try settings(values.configuration, values.exposure, values.zoom)
        try time(at); try observationMethod(method)
    }

    static func track(_ track: CaptureTrackInspection) throws {
        switch track {
        case .verified(let span):
            guard span.count > 0 else { throw CaptureContractError.invalidValue }
            try time(span.first); try time(span.last)
        case .unavailable(let why): try reason(why)
        case .missing: break
        }
    }

    static func result(_ record: RecordingResultRecord) throws {
        try intent(record.intent)
        try time(record.end.ceasedAt); try time(record.end.lastVideo); try time(record.end.lastAudio)
        if case .interrupted(let why) = record.end.writer { try reason(why) }
        if case .failed(let why) = record.end.writer { try reason(why) }
        try time(record.file.finalizedAt)
        try track(record.inspection.video); try track(record.inspection.audio)
        switch record.inspection.format {
        case .observed(let format, let at, let method):
            guard format.width > 0, format.height > 0, format.nominalFramesPerSecond.isFinite,
                  format.nominalFramesPerSecond > 0 else { throw CaptureContractError.invalidValue }
            try time(at); try observationMethod(method)
        case .unavailable(let why): try reason(why)
        }
        switch record.inspection.playback {
        case .failed(let why), .unavailable(let why): try reason(why)
        case .verified: break
        }
        switch record.inspection.completeness {
        case .partial(let why), .unknown(let why): try reason(why)
        case .complete: break
        }
        switch record.result {
        case .partial(let why), .unknown(let why), .failed(let why): try reason(why)
        case .saved: break
        }
    }
}
