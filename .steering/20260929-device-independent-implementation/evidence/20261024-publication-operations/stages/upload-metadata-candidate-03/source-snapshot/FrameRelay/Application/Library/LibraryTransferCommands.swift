/// Retains the complete first request while an App owner is uncertain. A tap
/// after uncertainty only looks up that request, never creates another parent.
@MainActor final class LibraryTransferCommands: OriginalUploadAcceptancePort {
    private let acceptance: any OriginalUploadAcceptancePort
    private let network: any OriginalUploadStartNetworkPort
    private var pending: OriginalUploadAcceptanceRequest?
    private var inFlight = false

    init(acceptance: any OriginalUploadAcceptancePort, network: any OriginalUploadStartNetworkPort) {
        self.acceptance = acceptance; self.network = network
    }

    func availability(items: [LibraryItem], snapshot: LibrarySnapshot) -> LibraryActionAvailability {
        guard !inFlight, pending == nil else { return .unavailable("先の転送要求の受付結果を照合してください。") }
        guard !items.isEmpty else { return .unavailable("対象の動画を選択してください。") }
        guard snapshot.storeIdentity != nil, snapshot.uploadRegistration != nil else {
            return .unavailable("転送先の現在の登録を一つに特定できません。Macとの接続と登録を確認してください。")
        }
        guard items.allSatisfy({ $0.uploadCandidateBinding != nil }) else {
            return .unavailable("選んだすべての動画の原本と保存記録の対応が必要です。選択を保持して再読み込みしてください。")
        }
        guard network.currentCondition() == .wiFi else { return .unavailable(Self.wifiReason) }
        return .available
    }

    @MainActor func accept(_ request: OriginalUploadAcceptanceRequest) async -> OriginalUploadAcceptanceResult {
        guard !inFlight else { return .unknown }
        if let pending {
            guard OriginalUploadAcceptanceValueValidation.exact(pending, request) else { return .rejected(.wrongStage) }
            return await lookupAcceptance(request)
        }
        pending = request; inFlight = true
        let result = await acceptance.accept(request)
        inFlight = false
        return finish(result, request: request)
    }

    @MainActor func lookupAcceptance(_ request: OriginalUploadAcceptanceRequest) async -> OriginalUploadAcceptanceResult {
        guard !inFlight else { return .unknown }
        if let pending, !OriginalUploadAcceptanceValueValidation.exact(pending, request) { return .rejected(.wrongStage) }
        pending = request; inFlight = true
        let result = await acceptance.lookupAcceptance(request)
        inFlight = false
        return finish(result, request: request)
    }

    private func finish(_ result: OriginalUploadAcceptanceResult,
        request: OriginalUploadAcceptanceRequest) -> OriginalUploadAcceptanceResult {
        if case .recorded(let record) = result {
            guard record.isCommitted, OriginalUploadAcceptanceValueValidation.exact(record.plan.request, request) else { return .unknown }
        }
        switch result {
        case .recorded, .rejected: pending = nil
        case .unknown: break
        }
        return result
    }

    static let wifiReason = "新しい転送要求は、現在のWi-Fi経路を確認できるときに受け付けます。Wi-Fiに接続してから操作してください。"
}

nonisolated enum LibraryTransferProjection {
    static func currentRequest(_ child: OriginalUploadAcceptanceChild, record: StoredOriginalUploadAcceptance,
        rows: [LibraryMediaRequest]) -> LibraryMediaRequest? {
        guard child.decision == .accepted, let initial = child.initialRequest else { return nil }
        let matches = rows.filter {
            OriginalUploadAcceptanceValueValidation.exact($0.request.operation, child.target.operation)
                && OriginalUploadAcceptanceValueValidation.exact($0.request.target, initial.target)
                && OriginalUploadAcceptanceValueValidation.exact($0.request.registration, record.plan.request.registration.server.registration)
                && $0.request.expectedStartRevision == initial.expectedStartRevision
                && $0.request.purpose == .upload && $0.request.startCommitted
        }
        return matches.count == 1 ? matches[0] : nil
    }

    static func decision(_ child: OriginalUploadAcceptanceChild) -> String {
        switch child.decision {
        case .accepted: return "受付時の記録：転送要求を受け付けました。受付時には通信を開始していません。"
        case .notProcessed(let reason):
            let explanation: String
            switch reason {
            case .bindingUnavailable: explanation = "原本と保存記録の対応を確認できません。"
            case .bindingChanged: explanation = "選択時の原本と現在の保存記録が一致しません。"
            case .saveNotCompleted: explanation = "原本の正常保存を確認できません。"
            case .removalReserved: explanation = "原本の削除結果を照合中です。"
            case .invalidated: explanation = "確認の失効を照合中です。"
            case .removed: explanation = "iPhoneの原本は削除済みです。"
            case .fileMissing: explanation = "iPhoneの原本が見つかりません。"
            case .fileInaccessible: explanation = "iPhoneの原本にアクセスできません。"
            case .fileUnknown: explanation = "iPhoneの原本の存在を確認できません。"
            case .byteCountMismatch: explanation = "原本のサイズと保存記録が一致しません。"
            case .alreadyRequested: explanation = "同じ原本と転送先への転送要求が既にあります。"
            }
            return "未処理：" + explanation
        }
    }
}
