import Foundation

nonisolated enum ExplorationOutputCandidate: String, CaseIterable, Codable, Sendable {
    case movieFile
    case sampleWriter
}

nonisolated enum ExplorationStoreCandidate: String, CaseIterable, Codable, Sendable {
    case atomicFile
    case sqlite
}

nonisolated enum ExplorationDisplayCondition: String, Codable, Sendable {
    case recordingOnly
    case standardRec709AlongsideRecording
}

/// An operator-supplied, versioned exploration ticket. No product defaults or paths.
nonisolated struct ExplorationTicket: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let environmentReference: String
    let authorizationRecordReference: String
    let existingDataScopeReference: String
    let evidenceVaultReference: String
    let caseID: String
    let repetitionID: String
    let conditionVersion: String
    let reportedDeviceModel: String
    let actualOSVersion: String
    let totalCapacityBytes: UInt64
    let availableCapacityBytes: UInt64
    let formatID: String
    let desired: DesiredCaptureSettings
    let display: ExplorationDisplayCondition
    let maximumDuration: CaptureRationalTime
    let maximumFileBytes: UInt64
    let minimumRemainingBytes: UInt64

    var validationIssues: [ExplorationIssue] {
        var issues: [ExplorationIssue] = []
        if schemaVersion != 1 { issues.append(.unknownTicketSchema) }
        let identifiers = [environmentReference, authorizationRecordReference, existingDataScopeReference,
                           evidenceVaultReference, caseID, repetitionID, conditionVersion, formatID]
        if identifiers.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            issues.append(.ticketReferencesMissing)
        }
        if identifiers.contains(where: { $0.contains("/") || $0.contains("\\") || $0.contains(":") }) {
            issues.append(.ticketReferencesMissing)
        }
        if reportedDeviceModel.isEmpty || actualOSVersion.isEmpty || totalCapacityBytes == 0
            || availableCapacityBytes == 0 || availableCapacityBytes > totalCapacityBytes {
            issues.append(.deviceFactsMissing)
        }
        if maximumDuration.timescale <= 0 || maximumDuration.ticks <= 0 || maximumFileBytes == 0
            || !maximumDuration.seconds.isFinite || maximumDuration.seconds >= Double(UInt64.max) / 1_000_000_000
            || maximumFileBytes > UInt64(Int64.max) || minimumRemainingBytes > UInt64(Int64.max)
            || minimumRemainingBytes == 0 || maximumFileBytes >= availableCapacityBytes
            || minimumRemainingBytes > availableCapacityBytes - min(maximumFileBytes, availableCapacityBytes) {
            issues.append(.trialLimitsInvalid)
        }
        let settings = desired
        if settings.configuration.camera.isEmpty || settings.configuration.width <= 0
            || settings.configuration.height <= 0 || settings.configuration.framesPerSecond <= 0
            || settings.configuration.framesPerSecond > Int(Int32.max)
            || settings.configuration.stabilizationMode.isEmpty || settings.exposure.shutter.timescale <= 0
            || settings.exposure.shutter.ticks <= 0 || !settings.exposure.iso.isFinite || settings.exposure.iso <= 0
            || !settings.zoom.isFinite || settings.zoom <= 0
            || settings.exposure.aperture.map({ !$0.isFinite || $0 <= 0 }) == true {
            issues.append(.settingsInvalid)
        }
        return issues
    }
}

nonisolated enum ExplorationRuntime: Equatable, Sendable {
    case simulator
    case physicalDevice(osVersion: String, availableBytes: UInt64)
}

nonisolated enum ExplorationIssue: Error, Equatable, Sendable {
    case ticketMissing
    case unknownTicketSchema
    case ticketReferencesMissing
    case deviceFactsMissing
    case trialLimitsInvalid
    case settingsInvalid
    case candidateMissing
    case simulatorHasNoVerifiedCamera
    case osVersionDiffers
    case capacityInsufficient
    case rec709TransformUnverified
    case permissionDenied
    case capabilityUnconfirmed(String)
    case appliedValuesDiffer
    case operationInProgress
    case storageUnavailable
    case ticketReadFailed
    case adapterFailure(String)

    var message: String {
        switch self {
        case .ticketMissing: return "試験票が未束縛です。実機情報と探索条件を記したJSONを選んでください。"
        case .unknownTicketSchema: return "この試験票のschema版は未対応です。"
        case .ticketReferencesMissing: return "環境・対象操作・既存データ範囲・媒体保管先・ケースの確認参照が不足しています。"
        case .deviceFactsMissing: return "実機の機種・実iOS・容量・空き容量の確認値が不足しています。"
        case .trialLimitsInvalid: return "有限の探索時間・出力上限・空き容量の条件が未確定または不正です。"
        case .settingsInvalid: return "希望する撮影設定が未確定または不正です。"
        case .candidateMissing: return "記録出力と保存方式の比較候補を選択してください。"
        case .simulatorHasNoVerifiedCamera: return "Simulatorでは実カメラ・音声付き録画の能力は未確認です。実機探索は実行できません。"
        case .osVersionDiffers: return "試験票の実iOSとこの端末が一致しません。"
        case .capacityInsufficient: return "この探索票に必要な空き容量を確認できません。自動の容量確保は行いません。"
        case .rec709TransformUnverified: return "固定Rec.709変換の由来・実Logとの適合が未確認のため、この表示併用ケースは実行できません。"
        case .permissionDenied: return "カメラまたはマイクの権限を確認できません。"
        case .capabilityUnconfirmed(let code): return "希望条件の能力を確認できません（\(code)）。"
        case .appliedValuesDiffer: return "読戻した実適用値が希望値と一致しません。別設定へ代替せず停止しました。"
        case .operationInProgress: return "現在の操作・保存が終了してから次の探索を準備してください。"
        case .storageUnavailable: return "探索用の保存領域または保存記録を準備できません。"
        case .ticketReadFailed: return "選択した試験票を読み取れません。"
        case .adapterFailure(let code): return "探索処理を完了できません（\(code)）。"
        }
    }
}

nonisolated enum ExplorationGate {
    static func issues(ticket: ExplorationTicket?, output: ExplorationOutputCandidate?,
                       store: ExplorationStoreCandidate?, runtime: ExplorationRuntime) -> [ExplorationIssue] {
        var issues: [ExplorationIssue] = []
        if runtime == .simulator { issues.append(.simulatorHasNoVerifiedCamera) }
        guard let ticket else { return issues + [.ticketMissing] }
        issues += ticket.validationIssues
        if output == nil || store == nil { issues.append(.candidateMissing) }
        if ticket.display == .standardRec709AlongsideRecording { issues.append(.rec709TransformUnverified) }
        if case .physicalDevice(let os, let free) = runtime {
            if os != ticket.actualOSVersion { issues.append(.osVersionDiffers) }
            if free < ticket.maximumFileBytes || free - min(ticket.maximumFileBytes, free) < ticket.minimumRemainingBytes {
                issues.append(.capacityInsufficient)
            }
        }
        return issues
    }
}
