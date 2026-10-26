import Foundation
import Darwin

/// Per-run control-event evidence. It is separate from recording commit state,
/// media durability, quality acceptance, and the UI's bounded display history.
/// These adapters coordinate through the same lock and read the latest snapshot
/// for each append. No truncation, reset, migration, or media operation is exposed.
actor ExplorationDiagnosticsStore: ExplorationDiagnosticsPort {
    private let run: ExplorationRunDirectory
    private let file: URL
    private static let lockName = "diagnostics.lock"

    init(run: ExplorationRunDirectory, mode: ExplorationStoreOpenMode) throws {
        self.run = run
        let file = run.url.appendingPathComponent("diagnostics.json")
        self.file = file
        try ExplorationFileLock.withLock(run: run, name: Self.lockName) {
            var info = stat()
            let exists = lstat(file.path, &info) == 0
            guard exists || errno == ENOENT else { throw ExplorationStorageError.inaccessible }
            switch mode {
            case .createNew:
                guard !exists else { throw ExplorationStorageError.alreadyExists }
                try JSONEncoder().encode(ExplorationDiagnosticsDocument()).write(to: file, options: .withoutOverwriting)
            case .openExisting:
                guard exists else { throw ExplorationStorageError.inaccessible }
            }
            try ExplorationRunDirectory.requireRegularFile(file)
            _ = try ExplorationDiagnosticsDocument.decode(Data(contentsOf: file))
        }
    }

    func append(_ event: ExplorationDeviceEvent) throws -> ExplorationDiagnosticRecord {
        try ExplorationDiagnosticValidation.event(event)
        return try ExplorationFileLock.withLock(run: run, name: Self.lockName) {
            try ExplorationRunDirectory.requireRegularFile(file)
            var document = try ExplorationDiagnosticsDocument.decode(Data(contentsOf: file))
            let previous = document.events.last?.sequence ?? 0
            let next = previous.addingReportingOverflow(1)
            guard !next.overflow else { throw CaptureContractError.invalidValue }
            let record = ExplorationDiagnosticRecord(sequence: next.partialValue, event: event)
            document.events.append(record)
            try JSONEncoder().encode(document).write(to: file, options: .atomic)
            return record
        }
    }

    func load() throws -> [ExplorationDiagnosticRecord] {
        try ExplorationFileLock.withLock(run: run, name: Self.lockName) {
            try ExplorationRunDirectory.requireRegularFile(file)
            return try ExplorationDiagnosticsDocument.decode(Data(contentsOf: file)).events
        }
    }
}

nonisolated private struct ExplorationDiagnosticsDocument: Codable {
    var schema = 1
    var events: [ExplorationDiagnosticRecord] = []

    static func decode(_ data: Data) throws -> Self {
        struct Header: Decodable { let schema: Int }
        let decoder = JSONDecoder()
        let schema: Int
        do { schema = try decoder.decode(Header.self, from: data).schema }
        catch { throw ExplorationStorageError.corruptStore }
        guard schema == 1 else { throw ExplorationStorageError.unknownSchema }
        do {
            let document = try decoder.decode(Self.self, from: data)
            for (index, entry) in document.events.enumerated() {
                guard entry.sequence == UInt64(index) + 1 else { throw CaptureContractError.invalidValue }
                try ExplorationDiagnosticValidation.event(entry.event)
            }
            return document
        } catch { throw ExplorationStorageError.corruptStore }
    }
}

nonisolated private enum ExplorationDiagnosticValidation {
    static func event(_ event: ExplorationDeviceEvent) throws {
        // Control-event producers supply stable codes and opaque IDs, never error
        // descriptions or user names. Reject path-shaped values at this boundary
        // as well; this is not a general-purpose private-text anonymizer.
        let encoded = try JSONEncoder().encode(event)
        try validateStrings(JSONSerialization.jsonObject(with: encoded))
        switch event {
        case .capture(let capture): try captureEvent(capture)
        case .fileFinalized(let evidence): try RecordingStoredValueValidation.time(evidence.finalizedAt)
        case .observation(let observation): try RecordingStoredValueValidation.time(observation.time)
        }
    }

    private static func validateStrings(_ value: Any) throws {
        if let string = value as? String {
            try RecordingStoredValueValidation.text(string)
            guard !string.contains("/"), !string.contains("\\") else { throw CaptureContractError.invalidValue }
        } else if let object = value as? [String: Any] {
            for value in object.values { try validateStrings(value) }
        } else if let array = value as? [Any] {
            for value in array { try validateStrings(value) }
        }
    }

    private static func captureEvent(_ event: CaptureIOEvent) throws {
        switch event {
        case .whiteBalanceLocked(_, let lock):
            _ = try CaptureWhiteBalanceGains(red: lock.gains.red, green: lock.gains.green, blue: lock.gains.blue)
            try RecordingStoredValueValidation.time(lock.measuredAt)
            try RecordingStoredValueValidation.time(lock.appliedAt)
        case .automaticWhiteBalanceRestored(_, let time), .recordingStarted(_, let time):
            try RecordingStoredValueValidation.time(time)
        case .recordingEnded(_, let evidence):
            try RecordingStoredValueValidation.time(evidence.ceasedAt)
            try RecordingStoredValueValidation.time(evidence.lastVideo)
            try RecordingStoredValueValidation.time(evidence.lastAudio)
        case .commandFailed: break
        case .audioObserved(_, _, let state):
            switch state.level {
            case .observed(let level, let at, let method):
                _ = try CaptureAudioLevel(linearAmplitude: level.linearAmplitude, isClipping: level.isClipping)
                try RecordingStoredValueValidation.time(at)
                try RecordingStoredValueValidation.observationMethod(method)
            case .unavailable: break
            }
            if case .recovering(let attempt) = state.input, attempt < 0 { throw CaptureContractError.invalidValue }
            if case .received(let span) = state.arrival { try RecordingStoredValueValidation.track(.verified(span)) }
            switch state.writing {
            case .accepted(let span), .completed(let span): try RecordingStoredValueValidation.track(.verified(span))
            default: break
            }
        }
    }
}
