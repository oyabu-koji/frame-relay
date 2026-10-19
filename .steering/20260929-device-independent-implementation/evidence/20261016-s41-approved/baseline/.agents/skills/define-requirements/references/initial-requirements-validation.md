# Initial requirements validation

`define-requirements`と`setup-project`は、この定義を変更せず共通利用する。

## 必須領域

| 領域 | `valid`に必要な内容 |
| --- | --- |
| Project Overview | Project name、One-sentence summary、Problem to solveが具体的である |
| Users | Primary users、Usage contextが具体的である |
| Product Goals | プロジェクト固有の目標が1件以上ある |
| In Scope | MVPに含める具体的な機能が1件以上ある |
| Out of Scope | MVPに含めない具体的な対象が1件以上ある |
| Acceptance Criteria | 検証可能な条件が1件以上ある |

`Open Questions`は未決事項の記録欄であり、残っていることだけでは停止しない。永続文書の内容を大きく変える質問が残る場合は、main agentがユーザーへ確認する。

## 判定

- `missing`: ファイル、いずれかの必須セクション、または必須領域の表で要求したフィールド・項目が存在しない。
- `blank`: 必須セクションと必須フィールド・項目は存在するが、空欄、説明文だけ、プレースホルダー、またはプロジェクト固有性・検証可能性のない曖昧な一般論が残る。
- `valid`: すべての必須領域がプロジェクト固有の具体的内容で満たされる。

内容判定とは別に、対象ファイルが`absent`か`present`かを先に記録する。`missing`でも`absent`と`present`では更新方法が異なる。

- `absent + missing`: テンプレートassetから新規作成する。
- `present + missing`: 既存内容を正本として保持し、不足セクションだけを追加・補完する。テンプレートassetでファイル全体を置換しない。
- `present + blank`: 既存の構成と入力済み内容を保持し、空欄またはプレースホルダーだけを更新する。

上記の保持・補完規則は、不足情報を補う場合に適用する。`define-requirements`でユーザーが既存要件の変更を指定した場合は、合意した変更と整合に必要な関連箇所を更新できる。それ以外の既存内容は保持し、更新後の文書を同じ基準で再判定する。`setup-project`はこの判定を読み取り専用で利用し、初期要件を変更しない。

以下を`blank`として扱う。

- 見出しだけで本文がない。
- コロンの後ろが空である。
- `Project name:`、`Goal 1:`、`Core feature 1:`、`Non-goal 1:`、`Criterion 1:`などのラベルだけが残る。
- テンプレートの説明や例を言い換えただけで、プロジェクト固有の値がない。
- 「使いやすくする」「一般ユーザー向け」など、対象または検証可能な結果を特定できない一般論だけである。

ファイルの存在状態、必須フィールド・項目ごとの判定結果、不足内容を列挙する。状態が混在する場合も`missing`、`blank`、`valid`の順に優先し、1件でも`missing`なら全体を`missing`、`missing`がなく1件でも`blank`なら全体を`blank`、それ以外だけを`valid`とする。
