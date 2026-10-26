# S31 使用権解放とowner閉鎖の競合（2026-10-23）

S34の全Unit回帰で、既存Photos/取消し/失効試験の1枝が不明応答になった。元fixtureの実SQLiteには結果・SDK終端・使用権解放・失効ACKが残っていた。元の返値分岐は未確定のまま保持し、別途barrierでSDK結果/終端commit→実invalidation/使用権解放/root閉鎖/ACK→遅延caller releaseを強制した。`photo-owner-red-12`では閉鎖済みFileHandleのdescriptor参照によるApp crashを確定した。

同exact登録/結果/終端/modeの回収を単一Taskへ合流し、既完了useは元intent/terminal/releaseのexact commitと同use・dir/file/store identityを照合する。閉鎖後は自ownerの実FD終端も確認し、読み取りだけで既完了を返す。部分閉鎖・証拠不足はunknownを保ち、閉鎖FileHandle参照をSwift guardで拒否する。root再open・再回収・unlink・Photos再追加をせず、unknown/failed/notAttemptedのコピーを保持する。`succeeded(record)`は記録確定であり、写真保存成功への昇格ではない。

| 検証 | 結果 |
| --- | --- |
| 決定的red | `photo-owner-red-12` 旧8枝成功、新1枝crash。初回のmethod filter `red-11`は0実行で受入証拠にしない |
| 関連4suite | `photo-owner-green-13` 36宣言86展開成功、失敗/skip0。元8枝・新barrierと、両store/4結果/閉鎖後exact・別owner拒否・lookup不明・同exact並行回収の1commitを確認 |
| 全Unit | `photo-owner-unit-all-14` 604宣言中573成功/31条件付きskip、952展開成功（空templateを除く951）、失敗0 |
| 実PhotoKit | 新専用Simulatorで追加/読取をgrantした`authorized-15`とrevokeした`denied-16`が各2成功/各2skip。実追加のbytes/日時/音声/再生、coordinatorの終端/use解放/コピー回収・拒否時保持を確認。既存Photos資産の削除なし |
| build | `photo-owner-ios-build-17` generic iOS/Debug/署名なし成功 |

全必要runは292入力が前後一致し、compiler/analyzer診断・xcresult runtimeWarnings 0。raw stdoutには既存のFig等の出力も保持する。構成はFrameRelay.xcodeproj/scheme・test plan FrameRelay、Debug、Xcode27.0(27A266a)/Swift compiler6.4、Swift5/iOS27.0を維持。各command/result/実行版は[runs](runs/)、raw xcresult/DerivedData/開始copyは `/var/folders/8g/jlksky052tn269bzjt7lbgyr0000gn/T/fr-implementation-20261023-_coslmwo/`。

mainは製品1file/test2fileの全差分と元8枝不変を確認。[ソース](implementation-source/)と[文書レビュー](documentation-review.json)を保存した。実SDK試験のOS権限は新専用Simulatorで明示設定し、初回dialog・限定選択・実機を証明しない。正式媒体/通常Photos開始・複数保存/全S31・実機品質受入は未完了。独立validationは開始していない。
