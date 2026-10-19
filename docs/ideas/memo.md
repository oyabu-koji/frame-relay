# バックエンド連携：別セッションへの依頼メモ

新しいセッションでは「実装依頼（次のセッション用）」のコードブロックをコピーして使用する。確定仕様の正本は `20260928-backend-integration.md`。このメモの保存自体は、次のWorkflowの開始を意味しない。

## 計画作成依頼（実施済みの履歴）

```text
$prepare-steering

/Users/oyabu/dev/rep/FrameRelay/docs/ideas/20260928-backend-integration.md
を入力に、実装用steeringを作成してください。

1つのsteering内で段階化し、既存撮影steeringとの依存、
早期の通信成立性確認、品質試験前の合意条件を明記してください。

Git状態を確認し、未コミット変更と未追跡README.mdを保持してください。
今回は計画作成までとし、実装・試験・稼働環境・実データの操作は開始しないでください。
```

## 実装依頼（次のセッション用）

```text
$implement-steering

/Users/oyabu/dev/rep/FrameRelay/.steering/20260928-backend-integration/
に従って実装してください。

確定仕様は docs/ideas/20260928-backend-integration.md です。
steeringは再レビュー済みで、追加指摘はありません。

まずGit状態を確認し、既存の未コミット変更と未追跡README.mdを保持してください。
T01から依存条件を確認し、実行可能なタスクを進めてください。

撮影側のG2A／G2B引渡し、早期通信確認、品質試験前のG3合意を守ってください。
撮影側の引渡し待ちでも、独立して進められる作業は進めてください。
稼働環境変更・実DB移行・旧データ操作は開始せず、試験範囲と隔離条件を確認してください。

進捗・検証証跡・未確認事項をtasklistへ随時反映してください。
```
