import SwiftUI

struct ProductCaptureSubjectsView: View {
    @Bindable var model: ProductCaptureCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("人物とピント").font(.headline)
            Picker("撮影意図", selection: Binding<CaptureShootingIntent?>(
                get: { model.preferences.shootingIntent },
                set: { value in if let value { Task { await model.chooseShootingIntent(value) } } })) {
                Text("選択してください").tag(Optional<CaptureShootingIntent>.none)
                Text("人物のみ").tag(Optional(CaptureShootingIntent.people))
                Text("人物＋背景").tag(Optional(CaptureShootingIntent.peopleAndBackground))
                Text("景色優先").tag(Optional(CaptureShootingIntent.scenery))
            }
            .disabled(!model.subjectControlsConfigured || !model.preferencesLoaded || model.isSavingShootingIntent || model.isPreparing)
            .accessibilityIdentifier("capture.subject.intent")
            Text(status).accessibilityIdentifier("capture.subject.state")
            if let snapshot = model.subjects {
                Toggle("主役の追跡", isOn: Binding(get: { snapshot.trackingEnabled }, set: { enabled in
                    Task { await model.changeSubjects(.tracking(enabled)) }
                }))
                .disabled(model.isUpdatingSubjects)
                .accessibilityIdentifier("capture.subject.tracking")
                Text("追跡OFFは人物を優先するAFです。ピント固定には切り替わりません。")
                    .font(.footnote)
                if snapshot.candidates.isEmpty, model.allowsSceneTap {
                    Text("人物がいないときは、プレビューの合わせたい位置をタップしてください。")
                        .font(.footnote)
                }
                ForEach(Array(snapshot.candidates.enumerated()), id: \.element.id) { index, person in
                    HStack {
                        Button(snapshot.protagonist == person.id ? "人物\(index + 1)・主役" : "人物\(index + 1)を主役に") {
                            Task { await model.changeSubjects(.selectProtagonist(person.id)) }
                        }
                        .accessibilityIdentifier("capture.subject.protagonist.\(index)")
                        Toggle("人物\(index + 1)を露出評価", isOn: Binding(
                            get: { snapshot.exposureTargets.contains(person.id) },
                            set: { _ in Task { await model.changeSubjects(.toggleExposure(person.id)) } }))
                        .accessibilityIdentifier("capture.subject.exposure.\(index)")
                    }
                    .disabled(model.isUpdatingSubjects)
                }
                Text(focusStatus(snapshot.focus)).font(.footnote)
                    .accessibilityIdentifier("capture.subject.focus")
            }
            if let issue = model.subjectIssue { Text(issue).font(.footnote) }
            Text("露出評価の対象は複数選べます。主役の指定とは別で、ISOやシャッターは自動変更しません。")
                .font(.footnote)
        }
    }

    private var status: String {
        guard let snapshot = model.subjects else { return "人物は未確認です。人物検出や撮影意図の選択を待たず、撮影条件が整えばRECできます。" }
        if snapshot.focus != .applied {
            switch snapshot.state {
            case .following: return "主役を選択済みです。AFの適用は未確認です。"
            case .lostHolding, .heldAwaitingSelection: return "主役を見失いました。ピント保持の適用は未確認です。タップで指定し直してください。"
            case .sceneAF: return "ピントを合わせる位置を指定済みです。AFの適用は未確認です。"
            case .personPriorityAF: return "人物優先AFの適用は未確認です。"
            default: break
            }
        }
        switch snapshot.state {
        case .detecting: return "人物を検出しています。"
        case .following: return "指定した主役へピントを追従しています。"
        case .lostHolding: return "主役を見失いました。ピントを保持して、同じ主役の復帰を待っています。"
        case .heldAwaitingSelection: return "ピントを保持しています。主役をタップして指定し直してください。"
        case .personPriorityAF: return snapshot.candidates.isEmpty ? "人物は未検出です。" : "人物を優先するAFを使用しています。"
        case .sceneAF: return "指定した画面位置へピントを合わせています。"
        case .unavailable: return "現在の人物情報を確認できません。"
        }
    }

    private func focusStatus(_ value: CaptureSubjectFocusAvailability) -> String {
        switch value {
        case .applied: return "AF設定を適用しました。実際の合焦をプレビューで確認してください。"
        case .unconfirmed: return "AF設定は未確認です。"
        case .unsupported: return "この撮影条件では必要なAF操作に対応していません。"
        case .failed: return "AF設定の適用を確認できません。"
        }
    }
}
