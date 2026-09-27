# Tasklist — 撮影基盤の技術検証

## 現在の状態・実行規則

- 2026-09-26: `$prepare-steering` による計画作成。成果物はこのディレクトリの3文書だけ。実装・build/test・Simulator／実機起動・実機照会・実データ操作は開始していない。
- 2026-09-27: `$prepare-steering` による現行入力への再確認。既存の要求・設計・ケース・タスク・未決事項を保持し、再確認履歴と現在の計画状態だけを更新した。今回の再確認分はmain最終確認済み／計画再確認完了。実装・試験は全て未着手、実機容量・実iOS・空き容量は未確認のまま。
- 入力は[confirmed仕様](../../docs/ideas/20260926-capture-foundation-feasibility.md)、要求正本は[現行PRD](../../docs/product-requirements.md)。[requirements.md](requirements.md)の全P0表と禁止動作、[design.md](design.md)のケース・ゲートを維持する。
- 2026-09-27: ユーザーの明示 `$implement-steering .steering/20260926-capture-foundation-feasibility/` によりP01へ着手。進捗更新はmainが本ファイルを所有し、既存コードの読取調査はexplorer `p01_code_context`へ委任。未追跡README.mdを保持する。実機操作の対象・範囲、品質条件の合意は別に扱う。
- 2026-09-27・実機なしの先行: 本人の「iPhone繋がないとダメ？一旦それなしで進められない？」を受け、P02の開発側確認とP03の静的schema準備を後続の静的作業の前提として分離する。P04資料比較→P05純粋契約・単体試験→P06の実装／Simulator確認まで先行可能とする。P02/P03全体、P06の実機起動、P07の実録画比較は未完了のまま保持する。G01/G02の実機・媒体実施前提、G03の方式選定、G04品質事前合意、全P0と受入条件は緩和しない。別Workflowの開始ではなく、継続中implementの実行順調整。
- 各タスクの現在状態は以下に記録する。Ownerは担当役割の予定であり、実行開始時にmainが具体担当と所有ファイルを割り当てる。同じコードベースの他者の変更を戻さず、同じファイルを複数の書込担当へ同時に割り当てない。
- `pending → in-progress → done / blocked / cancelled`。書込タスクは原則一件ずつin-progressにし、依存タスクのDoneと必要ゲートを確認する。blockedは理由・影響・次の確認／必要判断を記録する。cancelledは合意された方針変更の理由が必要で、失敗ケースを消す用途にしない。
- 実装タスクのDone、検証ケース実施、AC-CF工程完了、PRD受入達成は別に記録する。観測可能性を妨げる未実装・不具合・検証手段未整備を、失敗の記録だけでDoneにしない。確認済み非対応は根拠と依存ケースを残す。
- 実機・媒体操作は明示WorkflowとG01の範囲を確認してから行う。既存データの移動／削除／上書き、容量確保、アプリ削除によるリセット、試験データ整理をこの計画の承認から開始しない。
- 証跡は下記台帳へ都度同期。3文書内には匿名参照・非機微の結果を記し、媒体・私的対応表はG01で決めるrepo外保管先へ置く。設計判断が変わった場合だけrequirements/designを更新する。

## Tasks

### P01 正本・差分・実行範囲を引き継ぐ

- [x] Status: done
  - Depends on: 明示された `$implement-steering`。本計画だけでは開始しない。
  - Owner: main。
  - Files: このsteeringの3文書（更新担当）。AGENTS、PROJECT_CONTEXT、仕様、永続6文書、関連コードは読取。
  - Done when: 正本の版と未commit差分、今回の実装範囲、禁止・未合意・後続必須、担当範囲を再確認し、外部操作の既存許可と不足を特定できる。
  - Verify: `git status --short`、対象diffと入力照合。開始時のREADME/docsの既存差分を他者作業として保護する。
  - Stop if: 仕様が変更／不整合、所有範囲不明、実装開始の明示がない。必要な変更仕様はmainから別Workflowを案内する。
  - Result (2026-09-27, main): AGENTS、PROJECT_CONTEXT、入力仕様、永続6文書、steering全文を確認。confirmed仕様とPRD補足R3を正本とし、全21要求・79AC、禁止動作、後続必須を維持。HEADとローカルのorigin/main参照はともに`acf4ec9f46d2f8f7332ce8ffe8c480bf9cac9257`。追跡済み／stage済み差分なし、未追跡はREADME.mdだけ（E-P01-01）。リモートの再取得は未実施。
  - Scope: 既存App内の撮影基盤検証を計画順に実装する権限を確認。現在の書込所有はmainのtasklistだけ。コードはP05以降でworkerへ個別割当。explorerの静的調査では初期表示と空の単体／起動UI雛形のみで、計画の現状と一致。製品UI・数値・方式、G04品質合意は未確定。実機の容量／実iOS／空き容量、署名成立、G01対象・操作・証跡保管先は未確認で、インストール・撮影・媒体複製・権限変更等は未実施。

### P02 開発・実機環境と実行構成を確認する

- [ ] Status: blocked
  - Depends on: P01。
  - Owner: main、実機情報・署名確認は本人と連携。
  - Files: tasklistの環境／実行証跡。project設定は読取。出力は許可したrepo外一時領域。
  - Done when: Xcode・Swiftコンパイラ・SDK、実在project・schemeのBuild/Test action・configuration・対象test、Simulator／実機destination・署名、実機の機種・容量・実iOS・空き容量を実値で記録し、build/test/実機の実行可否を区別できる。
  - Verify: 開発ガイドラインの順に`xcode-select -p`、`xcodebuild -version`、`xcrun swift --version`、確認済projectの`-list`、確認済schemeの`-showdestinations`等。各コマンド・出力先・終了結果を記録し、この計画では実行しない。
  - Stop if: 構成・SDK・runtime・実機・権限／署名が不足。OS・言語モード・Teamを回避目的で変えず、阻害される試験を未実施とする。
  - Result (2026-09-27, main): E-P02-01〜06で開発環境・scheme・Build/Test対象・Simulator destinationを確認。Appと2 test targetはiOS 27.0／Swift言語モード5.0、Automatic署名・Team設定あり。証明書・profileと実機署名の成立は未確認。Build/Test設定照会はビルド／テスト実行ではない。
  - Blocker: 実機接続を本人指示で後回しにする。実容量／実iOS／空き容量・実機署名準備は未確認（E-P02-07）で、P02全体は未完了。開発側の構成確認は完了し、P04/P05とP06の実機非依存部分は先行可能。実機・実データ依存の実施前に残件を解消する。環境不足を端末非対応と判定しない。
  - Resume (2026-09-27, main): 本人の「なんて答えたら良いのかわからないけど 進めていいよ」を受けて継続。提示済みの新規検証動画に限定する操作範囲への了承として記録する。未回答の実機情報は取得済みとせず、まずMac側から読取照会できる範囲を確認する。端末への接続・本人操作が必要な箇所は具体的な手順で案内する。

### P03 試験プロトコル・証跡・データ範囲を用意する

- [ ] Status: blocked
  - Depends on: P01、実機実施の前にP02。
  - Owner: main（品質・データ範囲の合意は本人）。
  - Files: このsteeringの条件版・判断台帳、合意したrepo外証跡台帳。実媒体操作はこのタスクでは行わない。
  - Done when: G01の対象・必要操作・保管先を確認し、G02の実行票schema、探索用の有限反復／シーン／初期試験値／障害手段／時刻対応を準備する。G04の品質評価項目・方法・許容範囲の合意済み／未合意を明示する。未合意の探索は観測のみとする。
  - Verify: designのケース共通規則と必要フィールドに欠落がないこと。実能力依存値はP07で束縛する期限を記録し、実施時に空欄を許さない。repo外媒体参照を匿名化できること。
  - Stop if: 試験に必要な操作範囲や保管先が不明、実容量埋め／既存データ削除等が必要という前提になった。品質未合意は品質合格試験を止めるが、条件を束縛した探索観測は分けて進められる。
  - Progress (2026-09-27, main): 下記「P03静的準備」に実行票schema、探索条件案、対象・操作範囲、品質未合意項目を準備。提示済みの新規媒体に限定した対象・必要操作は本人の継続指示で了承済み。実機実施・媒体保管先作成は未実施。実環境に依存する値は未束縛で、実行可能な試験票として扱わない。
  - Blocker: 既存FrameRelay内データ有無・実機探索の環境依存値・repo外媒体保管先は未確認で、P03全体は未完了。静的schemaと探索条件の束縛期限は準備済み。本人指示によりP04/P05とP06の実機非依存部分だけ先行する。実媒体を生成しない単体／Simulator試験はfake値と作業用一時領域で区別する。対象・操作範囲全体の再承認は不要。品質事前合意は品質合格試験の別ゲートとして保持。

### P04 標準API・出力・表示・保存候補の比較を設計する

- [x] Status: done
  - Depends on: P02の開発側構成確認、P03の静的schema・探索条件束縛期限（いずれも準備済み）。実機側の未完了はP06実機起動／P07実施前に解消する。
  - Owner: main／調査担当（read-only）。
  - Files: designのD01〜D05比較と判断台帳。使用SDK・公式契約は読取対象。
  - Done when: 候補ごとの必要能力、フレーム／音声書込の観測可能性、対応組合せ、隔離、保存commit、非焼込みと比較手順を列挙し、実録画を要する未確認事項をP06/P07の探索へ渡せる。候補を採用済みにしない。
  - Verify: 現行SDKと根拠の版を記録。外部依存なし、既存targetで実装可能な限定探索範囲と再現手順を差分として確認する。
  - Stop if: 契約不明のまま必要能力を仮定する、外部依存・OS変更・MediaVault追加調査が必要。mainが範囲・代案を整理する。
  - Progress (2026-09-27, main): 実機なしの先行指示に基づき着手。mainがdesign/tasklist、explorer `p01_code_context`がD01〜D03、explorer `p04_store_observation`がD04/D05をread-only調査。SDK/公式資料の契約と実機未確認事項を分離し、方式を採用済みにしない。
  - Result: E-P04-01。designの資料比較へ候補・API契約・根拠版・有限探索と未確認事項を反映。SDK型をP05へ漏らさない値境界を確認。実Log別の標準変換由来は未確定、実能力・録画・保存・負荷はP06/P07へ残す。G03の方式選定は未実施。

### P05 値・状態所有・I/O契約と試験窓口を作る

- [x] Status: done
  - Depends on: P04。
  - Owner: worker（開始時に具体ファイルをmainが指定）。
  - Files: `FrameRelay/Domain/{Capture,Media,Operations}/`の必要値、`Application/{Capture,Recovery,Ports}/`、対応する`FrameRelayTests/Domain/`・`Application/`・`Support/`。このタスクに必要なファイルだけ。
  - Done when: 希望／能力／実値、撮影／WB／音声4軸／保存、ID・世代・時刻・直接／推定／取得不能を表せ、SDKの具象を契約へ漏らさない。REC条件・二重REC・古いevent拒否を試験できる。
  - Verify: U01とU02の順序／不正／未知・重複の単体試験。確認済み構成で必要なbuild/testと隔離診断を記録する。
  - Stop if: WB安定・ND／人物検出待ちをREC条件に追加、設定無断代替、音量と音声有効性の混同、巨大な共有状態へ集約する設計が必要になった。
  - Progress (2026-09-27): worker `p05_contracts`へ本task記載のDomain/Applicationと対応単体testだけを割当。mainはdesign/tasklistとbuild/test実行証跡を所有。syntheticな値・fakeによる規則検証であり、実能力・品質を判定しない。
  - Result: E-P05-01〜04。純粋値・撮影／保存／音声復旧の独立reducer・型付きPortを新規14ファイルに実装。U01/U02の新規19宣言・引数展開22実行が成功（既存exampleは別扱い）。希望／能力scope／実値、WB・STOP・二本・古いevent、音声4軸、意図／file／検査／結果commitを区別。mainが全差分・所有範囲・test時source hash一致を確認。SDK隔離実行・実時刻／フレーム・disk永続性は後続へ残す。

### P06 方式比較用の最小探索実装を用意する

- [ ] Status: blocked
  - Depends on: P05。実装／単体・Simulator確認はP02の開発側構成とP03静的schemaで先行可能。実機起動・録画・媒体操作はP02/P03全体とG01/G02の探索実施前提を満たしてから行う。
  - Owner: worker。mainが候補ごとの所有ファイルと有限の比較範囲を指定。
  - Files: `Platform/{Capture,Render,OriginalStore,LocalStore,Diagnostics}/`の探索に必要なadapter、最小`Features/Capture/`、`Composition/`と既存入口、`project.pbxproj`のcamera/microphone用途説明、対応test。
  - Done when: D01〜D05を比較できる限定adapterと操作／観測窓口があり、候補ごとに希望・実値・記録開始／終端・音声・保存参照を残せる。記録・表示を分離し、探索版の保存先と原本を識別する。
  - Verify: 対象差分、同期group／target所属、生成Info.plist、既存設定維持。必要なbuild・診断・test・Simulatorで可能な表示と実機起動を行い、P07の試験開始条件を確認する。実録画の成立判定はP07。
  - Stop if: 起動不可、音声省略、無通知代替、ログに媒体／秘密混入、必要観測が取れないまま成功扱い。候補固有の不成立は比較事実としてP07へ渡す。
  - Progress (2026-09-27): 実機なしで実装・単体／使い捨てfixture・Simulator確認を先行。worker `p05_contracts`をcapture／探索表示・組み立て・project用途説明担当へ再割当、worker `p06_storage`を保存／原本検査候補・そのtest担当へ割当。保存のserializationに必要なDomain値のCodable対応はstorage担当だけが所有。mainは境界調整・build/testとsteeringを所有。実機起動・録画・G03比較は未実施のまま残す。
  - Result (2026-09-27): E-P06-01〜11。Movie出力／sample writer、設定読戻し、clip別WB順序、探索票と独立状態表示、両store・原本保護／Reader・連番付き診断保存を実装。WB測定・時計対応の値をUI履歴と別に保持する。厳密な有理数同値（丸め許容なし）、早期STOP／遅いcommit、診断保存失敗、未知schema・破損・競合を試験。最終の有意味な単体／統合64実行＋UI1実行が成功し、実機用署名なしbuild・Simulator起動／画面も確認。mainが最終差分・source hash・所有範囲を確認した。
  - Blocker / next: 本人指示により実機接続・起動・録画を未実施。P02/P03の実環境・既存Appデータ・媒体保管先・実能力依存値を確認してからG01/G02を束縛する。D02の公式変換資材・由来／版／利用条件が未取得のため、固定Rec.709表示は未実装・表示併用ケースはblocked。記録単独の探索窓口をもってD02を完了にしない。これらが残るためP06全体はdoneにせず、P07/G03以降へ進まない。
  - Limits: 保存実Logの判定・全編再生・完全性はinspectorがunknown／未測定を保持。Movieのstream別書込／最終sample、実WB適用と保存フレーム対応、音声入力／書込の実障害、容量・熱・実耐久性は未評価。WB再測定区間、音量レベル計測、録画中ズーム／切替、原本再生・本格復旧は計画のP09以降に残す。試験票の参照記載だけで実施前提全体の成立としない。探索UI・fixture数値・候補は製品採用や品質合格ではない。

### P07 限定探索・能力列挙から方式と実行票を束縛する

- [ ] Status: pending
  - Depends on: P06、G01/G02。
  - Owner: main／実機操作者、観測補助worker。新規修正はP06の所有者へ戻す。
  - Files: C01/C02とD01〜D05の証跡、designの採用候補・制約、tasklistの母集団／判断台帳。媒体は合意したアプリ領域・repo外保管先。
  - Done when: 実能力を列挙し、必要な限定録画で候補を比較してG03を判断できる。全セル・B/B0/E・依存ケースを展開し、各実行票の手動値・倍率・反復・場面・障害／中断手段・時刻対応を実施前に束縛する。品質合意と探索値を分ける。
  - Verify: 実Log、LT/422/Proxy、4K24/30、実補正、絞りとフレーム／音声観測の証拠。未確認・非対応・適用失敗の列、母集団の欠落、別方式比較、保存ファイル対応を照合。
  - Stop if: 環境不足、実施手段未整備、採用比較に必要な証拠不足。有限の追加探索は目的・条件版を更新してP06/P07へ戻す。標準不成立は未達を残し、要求縮小を先取りしない。

### P08 最小検証画面・組み立て・原本確認を整える

- [ ] Status: pending
  - Depends on: P07（G03）。
  - Owner: worker。
  - Files: `Features/Capture/`、必要な`Features/Playback/`、`Composition/`、既存入口、対応Presentation/UI test。
  - Done when: CF-01の操作・独立状態・不可理由・ケース／動画対応と1件の原本再生が可能。実録画／保存結果を受付表示から区別し、音声障害を色以外でも識別できる。仮操作を製品UIへ昇格しない。
  - Verify: U04/U05、C01/C19の表示・操作手順。再生で明示確認を作らないこと、I/OをViewから直接実行しないこと。
  - Stop if: 未合意の製品UIや製品ライブラリ完成が必要、表示値を成功の正本として扱う必要が生じた。

### P09 記録・手動設定・保存と復旧の基礎を実装する

- [ ] Status: pending
  - Depends on: P07、P08。
  - Owner: worker。
  - Files: `Application/{Capture,Recovery,Ports}/`、`Domain/{Capture,Media,Operations}/`、選定した`Platform/{Capture,LocalStore,OriginalStore}/`と対応test。
  - Done when: 選定方式で希望／能力／実値を照合して記録し、通常手動値・設定復元を維持。意図保存、終端、ファイル確定、映像／音声検査、結果commit、再起動照合を独立させ、正常／部分／不明／失敗を扱える。
  - Verify: U01/U03、C03/C04/C13に対応する契約・disk試験。必要音声未確認で正常保存にせず、原本非写真追加、非対応絞り操作なし。
  - Stop if: 無通知代替、診断ログだけの復旧、未確認store保証、媒体とDBの一括原子性を仮定する実装が必要。

### P10 WBを記録フレーム境界へ対応させる

- [ ] Status: pending
  - Depends on: P09。
  - Owner: worker。
  - Files: `Domain/Capture/`、`Application/Capture/`、`Platform/Capture/`、必要な検証表示と対応test。
  - Done when: 待機Auto、REC時取得値固定・安定待ちなし、本人合わせ直し・再固定、記録終端後Autoと次クリップ新規測定を実装し、直接観測／推定／取得不能を残せる。
  - Verify: U02の順序・STOP競合・二本・旧callback。C05の時刻／媒体照合窓口、他手動値維持を確認する。実機成立はP17/P18。
  - Stop if: 最終フレーム証拠をSTOP受付で代用、WB持越し、露出無断変更。取得不能は隠さずD01/D05へ戻す。

### P11 音声の独立観測・障害停止・有限復旧を実装する

- [ ] Status: pending
  - Depends on: P09、P10。
  - Owner: worker。
  - Files: 撮影Domain/Application/Ports、`Platform/Capture/`、音声表示、対応test。
  - Done when: レベル・入力有効性・到着・書込を区別し、静寂と音割れを入力障害から分離。確認済み障害で開始抑止／停止・部分確定、保存結果と復旧を分け、復旧後手動RECを守る。
  - Verify: U02/U04、C06/C07の注入経路。有限の探索猶予／試行上限／再構成範囲を条件版で管理。音声省略・無限再試行・全体再起動なし。
  - Stop if: 必要試験パラメータ未束縛、実入力／書込の観測不足をメーターで代用、製品復旧値の未合意採用。

### P12 固定Rec.709表示を実装する

- [ ] Status: pending
  - Depends on: P09、P11、D02の判断。
  - Owner: worker。
  - Files: `Platform/Render/`、必要な撮影Port／表示面、対応test。
  - Done when: 対象実Logと色特性に対応する固定標準変換を待機・録画中に使え、記録へ混ぜず描画と記録の時刻／負荷を観測できる。
  - Verify: U04とC08の検査手順、変換由来・Log適合・二重変換なし、記録経路へ非焼込み、LUT選択UIなし。品質評価はG04とP17/P18。
  - Stop if: 変換由来不明、未変換表示のみ、記録へ変換が混入、外部依存の導入が必要。

### P13 補正選択・対応条件付き復元を実装する

- [ ] Status: pending
  - Depends on: P09、P12。
  - Owner: worker。
  - Files: 撮影設定Domain/Application、`Platform/Capture/`、必要な検証表示と対応test。
  - Done when: OFF＋発見した補正候補、実適用、初回標準相当候補と対応条件付き前回復元、非対応時の理由と本人選択を扱える。画角変化・手動値・継続性を観測できる。
  - Verify: U01/U04とC09/C10の票。OFFのみ／モード名だけでは複数補正達成にせず、アプリ判断で補正・形式・制御方針を変えない。
  - Stop if: 複数モード不成立を架空名や無断代替で回避、製品名／数／強さの新規採用が必要。制約・代替はP20へ。

### P14 ズーム・レンズ切替と実適用観測を実装する

- [ ] Status: pending
  - Depends on: P10、P11、P13。
  - Owner: worker。
  - Files: 撮影Domain/Application、`Platform/Capture/`、必要な検証操作と対応test。
  - Done when: 試験票に従う寄る／引く・目標／途中停止、対応有向経路の切替、実カメラ・倍率・限定ISOと切替後保持を観測できる。手動値・WB・補正方針を維持し、不能な切替は無通知で実行しない。
  - Verify: U01/U04とC11/C12の手順、設定世代・実値・非対応経路拒否。停止精度・連続性はG04と実機試験で評価する。
  - Stop if: ISO上限／戻り基準／速度等が未束縛、常時Auto ISO・形式変更が必要、録画を失敗させて切替を優先する。製品停止支援・構図予告を追加しない。

### P15 規則・順序・永続性・表示の境界試験を完成させる

- [ ] Status: pending
  - Depends on: P08〜P14。
  - Owner: worker（テスト所有範囲）、修正は元ファイル所有者へ。
  - Files: `FrameRelayTests/{Domain,Application,Presentation,Platform,Integration,Support}/`、`FrameRelayUITests/{Flows,Support}/`。必要な本体修正はmainが再割当。
  - Done when: U01〜U05を実装し、遅延・逆順・重複、REC/STOP競合、音声静寂／不達／書込、B1〜B7の使い捨てdisk／プロセス中断、表示・再生分離を必要な層で検証できる。
  - Verify: 確認済scheme/test destinationで対象試験を実行、件数・skip・失敗と結果bundleを記録。実装を写すだけの試験や空雛形を証拠にしない。
  - Stop if: データ保護範囲を越える、永続性をin-memoryだけで合格にする、実機必須をfakeで閉じる。必要な失敗は修正／原因分類して残す。

### P16 統合版のbuild・診断・Simulator／実機起動を確認する

- [ ] Status: pending
  - Depends on: P15、P02の構成が現在も有効。
  - Owner: main／検証実行担当。
  - Files: tasklistの実行証跡。build/result bundleは許可したrepo外一時領域。
  - Done when: 変更に必要なbuild・診断・test、Simulatorで確認可能な操作、実機起動・権限・検証操作を確認し、P17開始に必要な観測と保存が機能する。
  - Verify: 実コマンド、project、scheme/action、configuration、destination、対象test／件数、終了結果、診断、証跡参照を記録。同期group／target所属、生成Info、既存iOS/Swift設定維持、秘密・媒体混入なしを確認。
  - Stop if: 必須build/test/起動未実施、0件／skipのみ、新規診断未解消、構成不足。品質・形式成立はこのタスクの成功から推定しない。

### P17 実機で単独条件を確認する

- [ ] Status: pending
  - Depends on: P16、C01/C02・母集団実行票の確定、G01/G02。品質判定はG04。
  - Owner: main／本人（実機操作・品質評価）。
  - Files: C03〜C13の実行票と証拠、tasklist結果台帳。媒体は合意領域のみ。
  - Done when: 実行可能な全C03セル、B0/B/Eの展開に従う手動・WB二本・音声・表示・補正3場面・ズーム／切替・通常保存を実施し、設定・動画・音声・時刻・管理記録を照合する。非対応／実施不能は根拠と依存を明示する。
  - Verify: C03〜C13の必須証拠、全セル数と結果、OFF→候補→OFF等の比較、反復失敗を含む全結果。G04未合意は観測だけと記録。
  - Stop if: 環境／手段不足、無音継続や保存不整合等で後続の安全な前提がない。修正・C18切り分け後に影響ケースを再実施し旧結果も残す。

### P18 標準条件の同時成立・応答性を確認する

- [ ] Status: pending
  - Depends on: P17、統合の必要前提が成立するセル。G01/G02、品質判定はG04。
  - Owner: main／本人。
  - Files: C16/C17の実行票と証拠、tasklist結果台帳。
  - Done when: B全セルで標準形式＋手動＋WB＋音声＋Rec.709＋補正＋録画中ズーム／対応Eを組み合わせ、約30秒・2〜3分の選定長と連続撮影を比較。初回権限／通常起動／復帰、REC開始・次REC、熱／容量／負荷の観測を区別する。
  - Verify: 単独との差、各24/30fps・カメラ・Log・補正、映像音声の連続性・実適用、時刻始終点と反復。2〜3秒を目標とし音声非省略。後続AF/ND/予告/通信は未検証。
  - Stop if: 実行可能な必須セルが未実施、統合前提が未確認、未合意値を品質合格に使う。標準不成立を代替形式の成功で閉じない。

### P19 障害・保存境界の中断／復帰／再起動を確認する

- [ ] Status: pending
  - Depends on: P17、P18の実行可能な範囲、P15の注入手段、G01/G02。
  - Owner: main／本人、必要に応じ試験担当。
  - Files: C07/C14/C15の実行票・証跡、tasklist結果台帳。新規試験媒体だけを対象。
  - Done when: 計画した権限／入力／書込障害、B1〜B7の中断・復帰・再起動を実施して実停止・WB終端・媒体／記録／表示を照合。通常・部分・不明・失敗、保存と復旧、復旧後手動RECを区別できる。P17等で取得済みのC07等は実装・条件の変更影響と証拠の十分性を確認して参照し、未実施境界・統合差分・新たな懸念に必要な追加試験を行う。
  - Verify: Port注入・使い捨てdisk・実OS事例を別集計し、各境界への到達証拠と未再現を記録。実容量埋め、既存媒体削除、アプリ削除を行わない。実機未実施を代替成功にしない。
  - Stop if: 必須実機障害の手段未整備、対象外データへ影響する操作が必要。該当必須は未実施／blockedで残す。救済失敗そのものを正常保存へ変更しない。

### P20 不成立・証拠不足を再現比較で切り分ける

- [ ] Status: pending
  - Depends on: P17〜P19の結果。阻害発生時には依存試験を止め、この手順を先行適用して記録する。
  - Owner: main／調査担当。コード修正は所有者へ戻す。
  - Files: C18の比較・根拠、designの制約・方式判断、tasklist未達台帳。
  - Done when: 失敗・不一致・未観測について同条件再現、一要因比較、別候補または適用されるSDK／プラットフォーム制約を確認し、原因分類・限界・影響AC・代替・次調査／相談事項を残す。観測を妨げる実装不備は修正後の再試験へ戻す。
  - Verify: 一回／一方式の失敗だけで非対応にしていないこと、原因未確認を保持すること、旧失敗を消していないこと。追加調査が必要な必須未実施はblockedのまま。
  - Stop if: 失敗の記録だけを調査完了にしようとする、要求変更や外部実データ調査が必要。mainが根拠・具体案を示して必要な判断へ戻す。

### P21 全P0・工程条件・永続文書影響を照合して引き継ぐ

- [ ] Status: pending
  - Depends on: P17〜P20。G06はP21内で評価する出口条件であり、P21の開始前提にはしない。
  - Owner: main。安定docsの必要な同期は対象を明示したdocument_authorへ別に割当。
  - Files: このsteeringの3文書。後続実装Workflowで必要なdocs同期は、影響と所有ファイルを確定してから行い、今回の計画作成では変更しない。
  - Done when: C19により全21要求・79ACとAC-CF-01〜11を照合し、証拠／部分観測／未達・未評価／後続必須を記録する。実行可能必須の未実施、環境不足・検証手段未整備があれば工程未完了として継続。根拠ある実施不能は依存ケース付きで報告する。安定した決定は必要なdocsへ同期し、要求変更は別合意を確認する。
  - Verify: 要求表79行の欠落・重複、ケース母集団と結果件数、品質事前合意、禁止動作、R3確定部分、コードと進捗の一致、最終diffと所有範囲。失敗・原因未確認は未達／未評価のまま影響・代案・次確認を示す。
  - Stop if: 資料のみ／失敗記録のみ／全ケース未実施、必須検証欠落、未達を達成へ昇格、関連安定文書の必要同期未完了。工程完了と基本撮影全体／初期版完成を混同しない。
  - Handoff: 同じsteeringパスを明示入力にして `$validate-implementation` を案内する。別Workflowは暗黙開始しない。専門`implementation_validator`はread-onlyで検証し、必要なdocsレビューは`doc_reviewer`を別に使う。

## ゲート・未決事項台帳

| ID | 現状 | 解決期限・担当 | 影響・扱い |
| --- | --- | --- | --- |
| G01 | 実装Workflow開始済み（P01）。新規媒体の対象・必要操作は本人了承済み。実機接続は後回しの指示あり。容量／実iOS／空き容量・実機署名・既存Appデータ・媒体保管先は未確認 | P01〜P03、実機実施前にmain／本人 | P04/P05・P06の実機非依存部分を先行。実機・実データ依存の実施は止める |
| G02 | 展開規則・ケース群はdesignに計画済み。P03の実行票schemaと有限探索条件案を下記に準備。実能力に依存する値・障害手段は未束縛 | 初期探索前P03、全実行票P07、main | 未束縛のケースは実施不可。試験値を製品値にしない |
| G03 | D01〜D05資料比較とP06の端末非依存実装／試験済み。実機比較・方式／実Logの選定は未実施。D02の公式変換資材・版／利用条件は未取得 | P04〜P07、main | P06全体はblocked。実機前提とD02残件を解消して比較へ。候補名は採用証拠ではない |
| G04 | 品質条件・方法・許容範囲未合意 | 品質合格に使う試験前、main／本人 | 探索観測のみ可。適合／PRD達成にしない |
| G05 | 製品UI、ズーム値、ISO基準、補正詳細、音声復旧、熱／容量等は未合意 | 製品採用が必要になる前、main／本人 | 本工程の探索条件と分離。要求見直しが必要なら別の明示Workflow |
| G06 | AC-CF全て未完了（P05/P06の端末非依存部分に証跡あり）、PRD79条件全て未評価 | P21、main | 工程／要求達成／初期版完成を別判定 |

## 環境・母集団台帳

| 項目 | 現在値 | 更新条件 |
| --- | --- | --- |
| 実装版／差分識別 | 開始HEAD `acf4ec9f46d2f8f7332ce8ffe8c480bf9cac9257`＋未commit実装。最終P06は`offline-vault-01/P06-test-05-sources.json`（Swift46＋project1）。過去checkpointを保持 | 各build・探索・試験でsource hashと差分を記録 |
| 実機 | iPhone 18 Pro（本人申告） | P02で実値・観測方法を確認 |
| 容量／実iOS／空き容量 | 未確認 | 試験開始前と必要な前後で記録 |
| Xcode／Swiftコンパイラ／SDK／署名 | macOS 26.6.2（25G83）、Xcode 27.0（27A266a）、Apple Swift 6.4（swiftlang-6.4.0.34.1）、iOS／Simulator SDK 27.0。Automatic署名・Team設定あり、実機署名成立は未確認 | E-P02-01〜05。言語モード5.0を維持、コンパイラと区別 |
| scheme／configuration／Build/Test action／対象test／destination | 入口FrameRelay.xcodeproj、scheme FrameRelay。既定Build/TestはDebug、Build対象App、Test対象FrameRelayTests／FrameRelayUITests（App依存）、関連test plan名FrameRelay。専用Simulator（iPhone 18 Pro／iOS 27.0／arm64）を新規作成し実行先に確認。接続実機なし | E-P02-02〜08。testメソッドの選択／除外・実行件数・起動は後続証跡で確認 |
| ケース母集団版／全セル数／実行可セル数／実施不能セル数／未確認セル数 | 未作成・件数未確定 | P07。C02全セルを保持しB/B0/Eとケース展開数を記録 |
| 実行票版／反復条件／品質合意ID | schema `CF-RUN-v0.1-draft`、探索条件案 `EXP-v0.1-draft`。実行票は未束縛、品質合意IDなし | P03/P07、条件変更時に版更新。draftでは実施不可 |
| 証跡保管先vaultID／参照方法 | 未確認 | P03。完全な私的パスはrepoに置かない |

## P03静的準備（操作範囲了承済み・条件未確定・未実行）

P02がblockedでもP01から独立して用意できる準備だけを記す。条件版はdraftで、G01/G02を通過した実行票ではない。仕様・方式・製品UIの変更はない。

### 対象・操作範囲（G01）

- 了承記録（2026-09-27）: 本人の「なんて答えたら良いのかわからないけど 進めていいよ」を、提示済みの下記対象・必要操作範囲への了承として記録。未回答の端末情報、未指定の保管先、探索条件案や品質許容範囲が確定したとは扱わない。
- 対象: 本人申告の実機1台の既存FrameRelay Appと、この検証で新規撮影する媒体・検証管理記録だけ。インストール／更新前に既存FrameRelayのインストール・保存データ有無を確認し、既存媒体や記録の初期化・移行を前提にしない。
- 必要操作: 合意済み実機への開発版インストール／起動、カメラ・マイク権限の本人操作、能力照会、束縛済み票での本人REC／STOP・設定操作・原本再生、対象クリップの検査。背景／ロック／本人による終了・再起動、権限拒否、障害注入は、別票に具体対象・境界・方法を記し、その操作範囲を確認してから行う。
- 証跡案: 新規原本はアプリ管理領域に保持。必要な証跡複製は、本人が指定するrepo外ローカル保管先に未使用のrunディレクトリを作り、対象clip IDを固定して行う。保管先の作成・複製もまだ実施しない。`vaultID/runID/caseID/repetitionID/clipID`で対応させ、私的パスとの対応表と媒体はrepo外だけに置く。内容同一性の確認方法はD05比較後に束縛する。
- 承認範囲に含めない操作: 既存実データの削除・移動・上書き、容量確保、アプリ削除／再インストールによるリセット、試験媒体の整理、写真追加、外部転送。保管期限・削除は別の本人判断とする。
- 確認の残件: 実機情報・接続／署名準備（P02で接続待ち）、既存FrameRelay内データの有無、repo外ローカル保管先。本人への直近の依頼はUSB接続・ロック解除・必要時の信頼操作だけとし、接続後にMacからの読取照会を優先する。品質合格試験は下記G04の別合意が必要。

### 実行票schema `CF-RUN-v0.1-draft`（G02）

| 区分 | 必須フィールド・検査 |
| --- | --- |
| 識別・追跡 | 環境ID、実装commit＋差分hash、条件版、母集団版、組合せID、群／ケースID、反復ID、撮影ID、保存操作ID、証拠ID。CF／AC-CF／PRD AC、依存セル、旧試行と再試験の対応。C05の二本は別撮影ID |
| 実施環境 | 日時・実施者、観測方法付き機種／実iOS／総容量／空き容量（前後）、Xcode／Swiftコンパイラ／SDK、scheme／action／configuration／destination参照、署名・権限、音声経路、熱状態 |
| 条件 | camera IDと物理／論理対応、実解像度、fps、codec、実Log、補正、出力候補。希望／能力／実適用と世代を別欄、非対応／未取得／取得不能の理由、前回復元条件 |
| 手順・有限量 | シーンID（照明・被写体・距離・動き・向き）、手動値、音源、開始／目標倍率、速度、途中停止時点、クリップ長、比較順、反復数、再準備／冷却条件、容量使用範囲、停止条件。期待観測と判定方法を記す |
| 境界・時計 | REC受付、WB取得／固定要求／適用／再固定／Auto、最初／最後の記録映像・音声、音声到着／書込、STOP受付、記録終端、ファイル確定、検査、結果commit、表示。媒体PTS・単調時計・実施日時の対応、分解能／誤差、直接／callback推定／取得不能 |
| 障害・中断 | B1〜B7の対象境界、到達hook／event、注入箇所、本人操作、有限回数、復旧手順、原本・store・表示の照合。Port注入／使い捨てdisk・プロセス／実OSを別票にし、未到達境界を成功にしない |
| 証拠 | 原本の不透明参照とvault相対キー、映像／音声track・codec・サイズ・長さ・色特性・日時／向き・再生検査、適用値時系列、ログ、永続管理記録、表示の照合。複製時の同一性、証拠欠損と影響 |
| 判定・残件 | 実施状況、動作観測、原因分類と根拠／反証、品質合意IDと項目別観測・適合、PRD全条件／部分観測、AC-CF工程判断、未達・未評価、依存未実施、制約・代案・次の確認を独立に記録 |

### 探索条件案 `EXP-v0.1-draft` と束縛期限

- 初期D01等の限定録画比較案は同じ条件を独立に再準備して2反復、1クリップ10秒。これは観測窓口の探索値で、品質合格に十分な回数・製品録画上限・P17以降の代表長ではない。実環境・容量確認後、初期探索実施前に実装候補と全撮影本数・見積使用量・安全に使える容量範囲を票へ明記し、不足なら録画しない。
- 基準と比較でシーン・音源・手動値・実装版を固定する。補正はOFF→候補→OFF、表示は記録単独→表示併用→記録単独、ズーム／切替は静止→操作あり→静止。失敗・中断も残し、目的と条件版を更新せず反復を増やさない。
- 実能力依存の手動値・Log・補正・倍率・速度・ISO限定補正範囲／戻り基準は未束縛。P04のSDK契約比較とP07の能力照会で決め、依存する各録画の**前**に票を埋める。初期比較に必要な値も探索後へ先送りしない。品質合意と製品採用は別欄とする。
- C05は二本を一試行とする。C16/C17は約30秒と2〜3分内で選ぶ実長、二本以上の連続撮影、B/B0/E全体の本数をP07で束縛する。端末の空き容量・安全な使用範囲なしで本数や長さを確定しない。
- 権限試験は対象AppのOS設定による本人操作を候補とし、初回権限の機会がなければ未実施を残す。容量相当／音声書込／store障害はPort注入と隔離した使い捨て領域を候補にし、実容量を埋めない。B1〜B7のhookと実OS中断の方法、音声の探索用猶予・復旧上限はP04〜P07で各票に束縛し、未束縛の障害試験は実施しない。
- 時刻対応の候補は媒体PTSと撮影経路の時計、単調時刻、実施日時の組を採取する方法。API契約・対応点・観測誤差はD05で確認して束縛する。callback時刻を保存フレーム時刻と同一にしない。

### 品質合意（G04）

| 評価対象 | 事前に提示・合意する評価条件／方法 | 許容範囲・現状 |
| --- | --- | --- |
| Rec.709・WB・色の連続 | 実Log別の標準変換由来と基準、同一照明・被写体、WB操作・フレーム境界との比較 | 未合意・未測定 |
| 補正効果・画角／構図 | 静止手持ち・歩き・パンの条件、OFF対比、構図基準物・保存映像の比較 | 未合意・未測定 |
| 音声同期・記録／描画の継続 | 既知の視聴覚イベント、track／時刻と再生の対応、落ち・途切れの測定条件と観測分解能 | 未合意・未測定 |
| ズーム・停止・レンズ移行 | 始終倍率と速度、操作時刻・実倍率、超過／遅延、明るさ・色・ピント・位置・切替時間の比較 | 未合意・未測定 |
| 起動・次REC・負荷 | 初回権限／通常／復帰を分離、入力から実記録までの起終点、代表長と反復 | 起動2〜3秒はPRD目標。追加許容範囲・品質反復数は未合意 |

各項目の具体シーン・測定方法・許容範囲・反復数を品質試験前に本人と合意して条件版と日時を固定する。それまでは探索観測のみで、後付けの閾値による既存結果の合格化は行わない。

### 実機なしの規則試験 `OFFLINE-v1`

2026-09-27の本人指示に基づくP05/P06先行では、Swift TestingのsyntheticなID・時刻・能力・eventと、必要時に新規作成する使い捨てfixtureだけを使う。数値は当該テストの入力であり、撮影パラメータ・品質閾値・製品既定値ではない。P05はU01/U02の規則・拒否・順序、P06はadapter境界・失敗・隔離・Simulatorの表示を確認する。再現性のため通常の一回実行を基本に、実装修正または環境失敗の後だけ理由を記して再試験する。正常系だけの反復成功を品質合格に使わない。実機能力・実フレームWB・録音・色・補正・ズーム・性能・実データ耐久性は未評価。

作業用のrepo外一時領域を`offline-vault-01`とし、開始snapshot・ログ・DerivedData・result bundleを置く。実媒体vaultとは別。既存Simulatorデータを保護するため検証専用端末を新規作成し、既存SimulatorへのApp更新・初期化・削除は行わない。端末の削除や実媒体整理はこの実行に含めない。

P06ではこの範囲で、両store候補の再open・競合・破損保持、原本参照の逸脱拒否と逐次hash、新規合成媒体のtrack／encoded sample読取を有限ケースで確認する。障害注入先は当該testが作った新規領域・bytesだけとし、既存実媒体へ適用しない。合成媒体は実Log・音声収録・再生品質の証拠ではない。`#if targetEnvironment(simulator)`の外側もcompileするため、列挙済みAny iOS Deviceに対する署名なしbuildを別途実行する。`CODE_SIGNING_ALLOWED=NO`は当該compileコマンド限定で、projectの署名／Teamを変更せず、実機署名・インストール・起動が成立したとは扱わない。

## 検証証跡

### 計画の静的検証

2026-09-26の行は既存計画に記録されていた過去の証跡として保持する。今回の実施結果は2026-09-27の行で区別し、過去の確認結果を今回の確認実績として流用しない。

| 日付 | 検証 | 結果 | 備考 |
| --- | --- | --- | --- |
| 2026-09-26 | AGENTS・PROJECT_CONTEXT・confirmed仕様・永続6文書・関連コードの読取調査 | 計画へ反映 | explorer調査と正本照合。実機／API成立を保証しない |
| 2026-09-26 | 3文書のID・参照・相互対応・差分範囲 | main最終確認済み／計画作成完了 | PRD79行に欠落・余分・重複なし、CF10・AC-CF11・C19・U5・P21を照合。未定義ID・task循環なし、相対リンク有効、全taskはpending。出力3ファイルのみ、既存75ファイルのhash不変・範囲外追加なし、追加diffに空白エラーなし。計画作成の検証であり、下記の実装検証とは別 |
| 2026-09-27 | 現行入力・関連コードの読取調査に基づく既存計画の再確認と履歴更新 | feature_planner確認済み | confirmed仕様、現行PRD、永続6文書、PROJECT_CONTEXTとexplorer調査を根拠に、既存計画と追跡IDを保持。全P0・禁止・R3・後続必須、工程とPRD判定の分離、未合意値の判断ゲートを維持。実装・試験・実機照会・実データ操作は未実施。更新後のmain確認結果は次行に記録 |
| 2026-09-27 | 更新後の全文diff・所有範囲・静的整合のmain最終確認 | main最終確認済み／計画再確認完了 | 差分は3文書の再確認履歴・状態のみ。mainの作業前81ファイルのsnapshotとの照合で所有範囲外78ファイルのSHA-256不変、追加・削除0。PRD79ACは欠落・余分・重複なく一致し全未評価、AC-CF11件は全未実施、P21件は全pending。ID・依存の実質変更なし、未定義ID・依存循環・リンク切れ0。`git diff --no-index --check`は空白エラー出力なし（差分ありの終了コード1）。今回の計画静的確認であり、実装・試験の完了やPRD達成を示さない |

### 実行記録

環境調査用の一時証跡を`env-vault-01`とし、repo外の`/private/tmp`内に作成した。対応先は作業セッションで保持し、repoには相対キーだけを記す。これはG01の実媒体保管先の合意ではなく、原本・音声・顔画像を保存しない。端末識別子や個人情報を含む生出力はrepoへ転記しない。

| 証拠ID | task／ケース／反復 | 環境・実装版・条件版 | 実コマンド／操作・構成 | 結果・件数・skip・診断 | 匿名参照・未確認範囲 |
| --- | --- | --- | --- | --- | --- |
| E-P01-01 | P01／開始状態 | 2026-09-27、HEAD `acf4ec9` | `git status --short --branch`、`git rev-parse HEAD`、`git rev-parse origin/main`、`git diff --stat`、`git diff --cached --stat`、追跡全ファイル＋READMEのSHA-256 snapshot | 全コマンド終了0。追跡差分0、未追跡READMEのみ、78ファイル記録 | `env-vault-01/initial-git.json`、`initial-files.json`。README SHA-256 `12a667aa2ed22c6211fdac7f033fd97f0f0836d5768c548855fbd00e3b26ca5f`。fetch／実機操作なし |
| E-P02-01 | P02／ツール環境 | 2026-09-27、HEAD `acf4ec9`、コード差分0 | `sw_vers`、`xcode-select -p`、`xcodebuild -version`、`xcrun swift --version`、`xcodebuild -showsdks` | 全て終了0。上記環境台帳の実値。選択先はXcode.app。sandbox内のSDK照会にFSEvents／cache診断あり | 実行セッション出力、`env-vault-01/sdk-list.txt`。コンパイル・機能成立未確認 |
| E-P02-02 | P02／project・scheme | 同上 | `xcodebuild -list -project FrameRelay.xcodeproj -disableAutomaticPackageResolution` | 終了0、3 target・Debug/Release・scheme FrameRelay。sandbox内はCoreSimulator接続拒否／log書込拒否あり。許可されたsandbox外で同コマンド再実行し終了0、当該診断なし | セッション出力、`env-vault-01/project-list-sandbox-start.txt`・`project-list-sandbox-end.txt`。sandbox内のruntime未発見を未導入とはしない |
| E-P02-03 | P02／destination | 同上、sandbox外の一覧照会許可後 | `xcodebuild -project FrameRelay.xcodeproj -scheme FrameRelay -showdestinations -disableAutomaticPackageResolution` | 終了0、iOS 27.0 Simulator 11件とgeneric 2件、接続実機0。My Macはplatform／iOS Support Version 26.6の条件不適合。`Supported platforms for the buildables in the current scheme is empty`診断あり | セッション出力。確認済みSimulator候補はiPhone 18 Pro、arm64、iOS 27.0（実機と区別）。Macの条件を理由にdeployment target変更なし |
| E-P02-04 | P02／Build action | 同上、Simulator候補 | `xcodebuild -project FrameRelay.xcodeproj -scheme FrameRelay -configuration Debug -destination 'platform=iOS Simulator,id=EF0AAC9B-A617-4479-9A7B-77ECDE42843A' -showBuildSettings -json -disableAutomaticPackageResolution`。既定構成は同destinationで`build -showBuildSettings`（configuration指定なし）でも確認 | 終了0、Build対象FrameRelay、既定Debug、設定維持。設定照会のみ、ビルド未実行。上記Supported platforms診断を保持 | `env-vault-01/build-settings.json`・`.stderr`、`build-settings-summary.json`、`build-action.txt`。署名は設定の存在だけで成立未確認 |
| E-P02-05 | P02／Test action | 同上、Simulator候補 | `xcodebuild -project FrameRelay.xcodeproj -scheme FrameRelay -destination 'platform=iOS Simulator,id=EF0AAC9B-A617-4479-9A7B-77ECDE42843A' test -showBuildSettings -json -disableAutomaticPackageResolution` | 終了0、既定Debug、FrameRelayTests／FrameRelayUITests／App。単体TEST_HOSTあり、UIのTEST_TARGET_NAMEはFrameRelay。全target iOS27.0／Swift5.0。testメソッド実行0（未実行） | `env-vault-01/test-settings.json`・`.stderr`、`test-settings-summary.json`。`-showBuildSettings`は同梱manの契約どおりaction設定照会、test実行ではない。上記Supported platforms診断あり |
| E-P02-06 | P02／test plan | 同上 | `xcodebuild -project FrameRelay.xcodeproj -scheme FrameRelay -showTestPlans -disableAutomaticPackageResolution` | 終了0、関連plan名FrameRelay。静的列挙では.xctestplan実ファイルなし。個別testの有効／除外・実行件数は未確認 | `env-vault-01/test-plans.txt`。plan一覧を試験合格にしない。上記Supported platforms診断あり |
| E-P02-07 | P02／継続時の接続確認 | 2026-09-27、本人の継続指示後、コード差分0 | `xcrun devicectl list devices --timeout 15 --quiet --json-output <repo外出力>`。sandbox内のtimeout後、許可されたsandbox外でtimeout 20秒にして再照会 | 初回終了2（15秒timeout）、再照会終了0。一覧1件はhardware realityがsimulated、visibilityClassがsimulators、providerがCoreSimulatorの端末。実機0件。初回timeoutを実機不在の根拠にはしない | `env-vault-01/devices-resume-01.json`・`devices-resume-02.json`とセッション出力。Simulatorの機種名・iOS・容量を実機値に転用しない。接続手順を本人へ案内済み |
| E-P02-08 | P02／実機なしの実行先準備 | 2026-09-27、OFFLINE-v1、既存設定維持 | `xcrun simctl list --json`／`list runtimes --json`でdevice typeとruntime確認。許可されたsandbox外で`xcrun simctl create 'FrameRelay CF 20260927 tmi2p8vs' com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro com.apple.CoreSimulator.SimRuntime.iOS-27-0`、既存project/schemeの`-showdestinations`で再確認 | 全て終了0。新規端末ID `DFE46693-E8DD-4814-8957-4F327699F719`、iOS27.0／arm64、実行先として列挙。既存Simulatorを初期化せず保持。Supported platforms診断は従前どおり。実機情報は未取得 | `offline-vault-01/destinations.txt`、開始状態`start-files.json`・`start-status.txt`、セッション出力。simctl helpのsandbox内接続拒否は許可されたsandbox外の再実行で解消。新規Simulator作成はApp起動・test成功ではない |
| E-P03-01 | P03／静的準備・main差分確認 | 2026-09-27、条件版draft | designのG01/G02/G04・実行票共通規則とschemaを照合。`git diff --check`、全文`git diff`、開始snapshotとのSHA-256比較、PRD／requirementsのAC集合・task状態・リンク確認 | 空白エラーなし。PRD79ACと追跡表79行が重複なく一致、リンク欠落0。開始時78ファイルのうちtasklistだけ変更、他77ファイル（README含む）不変。アプリ・project・要求・設計の変更なし | `env-vault-01/static-check.json`とセッション出力。実行票は未束縛、P02/P03 blocked、P04〜21 pending。全ケース未実施、品質未合意、PRD未評価 |
| E-P03-02 | P03／継続指示反映・main差分確認 | 2026-09-27、新規媒体の操作範囲了承後 | 操作範囲の了承と未確認の実機情報を分離してG01／Blockerを同期。`git diff --check`、全文`git diff`、開始snapshotとのSHA-256比較、AC集合・task状態・リンク確認 | tasklistだけ変更、READMEを含む他77ファイル不変。空白エラー・リンク欠落なし、PRD79ACと追跡表79行は一致。P01 done、P02/P03 blocked、P04〜21 pending | `env-vault-01/resume-static-check.json`とセッション出力。コード実装・build/test・実機操作・品質判定・PRD達成は未実施 |
| E-P04-01 | P04／D01〜D05資料比較 | 2026-09-27、Xcode27.0／iPhoneOS27.0 SDK | explorer 2件のread-only SDK調査とApple公式API／TN3104照合、mainによるdesignへの統合と差分確認 | 候補・必要能力・観測限界・隔離・保存境界・非焼込み・後続の比較手順を記録。実機未接続でもP05の値／Port準備が可能。外部依存・project設定変更なし | design「P04資料比較」、agent／web実行記録。Reader Provider／Writer ReceiverはP06でcompile確認、方式選定・実機成立・標準Rec.709変換・品質は未確認 |
| E-P05-01 | P05／App compile・link | 2026-09-27、OFFLINE-v1、Swift5／既定MainActor維持 | `xcodebuild -project FrameRelay.xcodeproj -scheme FrameRelay -configuration Debug -destination 'platform=iOS Simulator,id=DFE46693-E8DD-4814-8957-4F327699F719' -derivedDataPath <offline-vault-01/DerivedData> -resultBundlePath <offline-vault-01/P05-build-01.xcresult> -disableAutomaticPackageResolution build` | 終了0、BUILD SUCCEEDED。追加Domain/Applicationのcompile・link成功、Swift警告なし。未使用AppIntentsのmetadata extraction skippedというツール警告あり。起動・テスト実行とは別 | `offline-vault-01/P05-build-01.log`・`.xcresult`。P05作成途中のApp build、後続testの最終差分確認で更新する |
| E-P05-02 | P05／単体test初回 | 同上、`P05-test-01-sources.json`の18 Swiftファイル | 上記project/scheme/configuration/destination/DerivedDataに`-resultBundlePath <offline-vault-01/P05-test-01.xcresult> -disableAutomaticPackageResolution -only-testing:FrameRelayTests -parallel-testing-enabled NO test` | 終了65、test compile失敗・実行0。`CaptureAudioRecoveryTests.swift:11`の`#require`にmutating呼出しを渡したmacro展開でimmutable `$0`エラー。派生の不要try警告あり。workerへ修正を戻した | `offline-vault-01/P05-test-01.log`・`.xcresult`。App compile成功をtest成功にしない。修正後に同構成で再実行する |
| E-P05-03 | P05／U01/U02再試験 | 同上、`P05-test-02-sources.json` | E-P05-02と同構成、result bundleを`P05-test-02.xcresult`として`-quiet test`。mutating呼出しをmacro外へ分離後実施 | 終了0。20宣言（新規19＋既存example1）、引数展開23実行（新規22＋example1）。失敗0、skip0、runtime warning0。Swift compile警告なし。既存exampleは撮影検証数へ算入しない | `offline-vault-01/P05-test-02.log`・`.xcresult`・`P05-test-02-summary.json`・`P05-test-02-tests.json`。xcresulttool解析のsandbox内権限エラーは許可されたsandbox外で再取得し解消。実機・品質・PRD達成は未評価 |
| E-P05-04 | P05／main差分・所有確認 | 2026-09-27、test-02後 | 新規14 Swiftファイルの全文確認、Domain/ApplicationのSDK非依存・禁止経路の有無、開始snapshot・test source SHA-256照合、`git diff --check` | test時の全18 Swiftファイルhash一致。新規はDomain5／Application4／Tests5で割当範囲内。既存ファイルの変更はdesign/tasklistだけ、README保持。空白エラー0 | `offline-vault-01/P05-main-check.json`。独立したvalidate Workflowは未実施 |
| E-P06-D02 | P06／表示の資料残件 | 2026-09-27、実機未接続 | explorerによるApple公式資料の有限追加調査 | Log別のApple製3D LUTの存在は公式FCP資料に記載。Developer Downloads検索は取得不能、LUT／White Paper本文・版・利用条件は未取得。ログイン必須やAPI不存在とは断定しない | designのD02追加確認とagent記録。標準変換を独自係数で代用せず、表示併用ケース・CF-05を未確認に残す |
| E-P06-01 | P06／初回Simulator compile | 2026-09-27、OFFLINE-v1、UI組込前checkpoint | E-P05と同project/scheme/Debug/destination/DerivedData、`-resultBundlePath <offline-vault-01/P06-build-01.xcresult> -disableAutomaticPackageResolution -quiet build` | 終了65。AVCaptureDevice.clock不存在、iOS27非推奨expectsMediaDataInRealTime警告。入力portのnative clock使用・appendImmediately契約へ修正を戻した | `offline-vault-01/P06-build-01.log`・`.xcresult`・`-sources.json`。初回失敗を保持し、後続で再検証 |
| E-P06-02 | P06／実機用compile・link | 2026-09-27、OFFLINE-v1、E-P06-01修正後checkpoint | 同project/scheme/Debug/DerivedData、`-destination 'generic/platform=iOS' -resultBundlePath <offline-vault-01/P06-ios-build-01.xcresult> -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO -quiet build` | 終了0、Swift診断なし。Simulator分岐で除外される実機の設定／能力コードを含めcompile・link成功 | `offline-vault-01/P06-ios-build-01.log`・`.xcresult`・`-sources.json`。署名・実機起動・録画とは別。後続のUI／状態調整は最終構成で再確認 |
| E-P06-03 | P06／保存・Readerを含む単体／disk試験 | 2026-09-27、OFFLINE-v1、UI組込前 | E-P05-testと同構成、`-resultBundlePath <offline-vault-01/P06-test-01.xcresult> -only-testing:FrameRelayTests -parallel-testing-enabled NO -quiet test` | 終了0。36宣言・45実行（P05の23＋保存側22）、失敗0・skip0。合成Movie生成fixtureのvideo appendに優先度逆転runtime warning1件。fixtureをutility実行領域へ移す修正を戻し、再確認予定 | `offline-vault-01/P06-test-01.log`・`.xcresult`・`-sources.json`・`-summary.json`・`-tests.json`。xcresulttool同一bundleの同時解析はDBErrorとなり、順次再取得で解消。既存example1は有意味試験数へ含めない。実Log・再生・品質・電源断耐久性は未評価 |
| E-P06-04 | P06／探索UI組込後のiOS compile | 2026-09-27、`P06-final-sources.json`の45ファイルcheckpoint | E-P06-02と同構成、result bundleを`P06-ios-build-02.xcresult`へ変更 | 終了0、Swift診断なし。実行後source hash不一致0 | `offline-vault-01/P06-ios-build-02.log`・`.xcresult`。この後に観測event永続化／最初のappend成功通知へ更新するため、最終差分の証拠とは別 |
| E-P06-05 | P06／探索UI＋単体compile | 同上、OFFLINE-v1 | E-P06-03に`-only-testing:FrameRelayUITests/ExplorationFlowTests`追加、result bundle `P06-test-02.xcresult` | 終了65、test実行0。test actorの合成initializerに不正なnonisolated推論診断。設定を変えず明示initializerへ修正を戻した | `offline-vault-01/P06-test-02.log`・`.xcresult`。App／UI testのcompileをテスト実行成功にしない |
| E-P06-06 | P06／診断保存追加後のtest compile | OFFLINE-v1、`P06-test-03-sources.json` | E-P06-05と同構成、result bundle `P06-test-03.xcresult` | 終了65、実行0。明示initだけではactor診断未解消。fake factoryのstore生成をproperty既定値からinit本文へ移して修正 | `offline-vault-01/P06-test-03.log`・`.xcresult` |
| E-P06-07 | P06／test compile再試験 | OFFLINE-v1、`P06-test-04-sources.json` | 同構成、result bundle `P06-test-04.xcresult` | 終了65、実行0。actor診断は解消。WB順序testのmutating呼出しを#expectへ直接渡したmacro展開エラー16箇所。letへ先に評価する形へ修正 | `offline-vault-01/P06-test-04.log`（セッション出力上の省略あり）・`.xcresult`（診断正本） |
| E-P06-08 | P06／最終App iOS compile・link | OFFLINE-v1、App/projectは最終sourceと一致 | E-P06-02と同構成、result bundle `P06-ios-build-03.xcresult` | 終了0、Swift診断なし。診断保存・UI・最初のappend成功後の開始通知を含む。署名なしで実機用コードを確認 | `offline-vault-01/P06-ios-build-03.log`・`.xcresult`。以降の変更はWB testのmacro呼出しだけ。実機署名／起動は未確認 |
| E-P06-09 | P06／最終単体・disk・探索UI試験 | OFFLINE-v1、`P06-test-05-sources.json` | E-P06-05と同project/scheme/Debug/具体Simulator/DerivedData、`-resultBundlePath <offline-vault-01/P06-test-05.xcresult> -disableAutomaticPackageResolution -only-testing:FrameRelayTests -only-testing:FrameRelayUITests/ExplorationFlowTests -parallel-testing-enabled NO -quiet test` | 終了0。55宣言・引数展開66実行、失敗0・skip0・runtime warning0。内訳は有意味なunit/integration64、UI1、既存空example1。fixture優先度警告は解消。起動時未照会・REC/STOP不可・未束縛prepare拒否・権限alertなしをUIで確認 | `offline-vault-01/P06-test-05.log`・`.xcresult`・`-summary.json`・`-tests.json`。XcodeのSupported platforms／debugger version lookupのツール診断は残るが、Swift／runtime警告と区別。既存起動性能雛形は実施対象外 |
| E-P06-10 | P06／mainによるSimulator画面確認 | 専用Simulator、2026-09-27 | `simctl launch <専用ID> com.oyabu.FrameRelay`、`simctl io <専用ID> screenshot <offline-vault-01/P06-simulator-03.png>`、画像読取 | 起動・表示確認。探索専用／Simulator未確認／票未束縛／候補未選択／D02未実装の表示を確認。実機操作なし | test後Shutdownだったため初回launch149・screenshot timeout60。その専用端末だけboot後launch0、起動遷移中画像02を採用せず画像03で確認。`P06-simulator-03.png`。既存Simulatorの初期化・削除なし |
| E-P06-11 | P06／main最終差分・構成・所有確認 | 最終test後 | source SHA-256・開始snapshot、全新規Swiftの空白診断、project全文diff／生成Info.plist・target境界、PRD AC照合 | 新規Swift42（App/test割当内）、既存変更はdesign/tasklist・ContentView・project用途説明のみ。README不変、所有範囲外変更0、source不一致0、空白エラー0。iOS27／Swift5／並行処理／Team維持、用途説明を生成plistでも確認。PRD79ACの追跡維持 | `offline-vault-01/P06-main-check.json`・`P06-static-details.json`・`P06-final-check.json`。commit/push・別Workflow・独立validationは未実施 |
| E-P05／E-P06（部分） | C01〜C19、U01〜U05 | OFFLINE-v1 | U01/U02の規則、U03の新規disk／合成媒体、探索画面のU04/U05に相当する一部を実施 | C01〜C19実機ケース、後続の本実装・実I/O統合・品質は未実施 | 全U項目やAC-CF工程の完了へ昇格しない。媒体生成は新規synthetic fixtureのみ、実媒体・実機ログなし |

実行時はproject/workspace、scheme、configuration、destination、Build/Test action、対象testと件数、実装版、終了コード、診断、result bundle／ログの匿名参照を残す。手動実施は実施者・日時・操作を記す。品質は合意ID・項目別の観測／適合結果を分ける。必須の未実行を対象外や0件成功にせず、理由と影響を明示する。

P02の補足: `xcodebuild -project FrameRelay.xcodeproj -scheme FrameRelay build -showBuildSettings -json -disableAutomaticPackageResolution`も終了0で実行した。destination未指定では複数候補の先頭を選ぶ警告が出たため、E-P02-04では確認済みSimulatorを明示して再照会した。Test actionの初回セッション出力は表示上省略されたため、同コマンドを再照会しE-P02-05のJSON全体を一時領域へ保存・解析した。これらの再照会もbuild/testの実行ではない。証跡は一時保管であり、消失時には同じ構成照会とsnapshot確認を再実施する。

### ケース結果・残件の記録形式

| ケースID・条件版 | 対応AC-CF／PRD AC | 実施状況 | 動作観測・直接／推定 | 原因分類と根拠 | 品質合意／結果 | 証拠ID・次の確認 |
| --- | --- | --- | --- | --- | --- | --- |
| 未展開（designのC01〜C19をP07で実値展開） | requirementsの対応表 | 未実施 | 判定保留 | 原因未確認 | 許容範囲未合意／未測定 | 未取得 |

実施不能では前提の根拠と依存する未実施ケースを別列または同じ行に明示する。環境不足・手段未整備は非対応に置き換えない。実装問題を直した場合は旧試行を残して再試験IDを対応付ける。実ファイル・適用値・ログ・管理記録の欠けた証拠と影響ACを記す。

### 完了判定台帳

| 対象 | 現状 | 判定条件 |
| --- | --- | --- |
| 計画成果物 | 2026-09-26作成済み。2026-09-27はmain最終確認済み／計画再確認完了 | 今回の更新後にID・リンク・依存・正本整合・出力3ファイル限定を確認済み。過去の確認済み記録と区別する |
| 実装タスクP01〜P21 | P01/P04/P05 done、P02/P03 blocked（実機側残件）、P06 blocked（実機起動／比較前提・D02残件）、P07〜P21 pending | 各DoneとVerifyの証拠。P06の端末非依存検証成功は全体doneではない |
| AC-CF-01〜11 | 全て未完了。P05/P06の端末非依存検証は部分証跡として保持 | 実行可能必須の実施と観測・照合・切り分け・引継ぎ。環境／手段不足の必須未実施があれば未完了 |
| PRD全21要求・79AC | 全て未評価 | requirementsの個別行へ全条件・事前品質合意・適合証拠を照合 |
| 基本撮影全体・初期版完成 | 今回の完了対象外 | 後続必須を含む全P0の別受入 |

## 永続6文書に対する実装範囲（2026-09-27）

本人の「できれば実機確認は最後までやらない」「実装できるところを全てやり切りたい」を継続方針として記録する。実機接続は要求せず、実機なしで確定できる規則・実装・試験を優先する。ただし、現行計画はP07/G03の方式比較をP08以降の前提としている。後続の先行実装には、方式に依存しない部分／交換可能な探索候補と、実機比較後の選定・統合部分の依存を切り分ける必要がある。この方針記録だけでP07/G03を通過済みにせず、タスク状態・Done条件は変更しない。実能力・品質は最後の実機確認で判断し、候補の修正が必要になる可能性を残す。

以下は現在のコードと既存証跡の対応整理であり、独立したvalidationやPRD受入判定ではない。6文書は同じ初期版を異なる観点で定義しているため、文書の件数を実装率へ換算しない。

| 永続文書 | 現在コードへ反映した範囲 | 主な残り |
| --- | --- | --- |
| [product-requirements.md](../../docs/product-requirements.md) | FR-01/03/04/09、NFR-02に関係する希望・能力・実値、REC/STOP・WB、音声4軸、原本保存・検査・commitの基礎と探索adapter | 上記機能の本実装・実機成立、Rec.709、人物AF・ND、ズーム／レンズ切替、FR-10〜17の全管理フロー、非機能受入。全21要求・79ACは未評価 |
| [functional-design.md](../../docs/functional-design.md) | F1撮影フローの一部、撮影・音声・保存の独立状態と探索画面 | 完成した撮影操作・設定復元・再起動復旧、原本再生、F2〜F5の転送・確認・写真保存・破棄。探索画面は製品UIではない |
| [architecture.md](../../docs/architecture.md) | Domain/Application/Port/Platform/Compositionの分離、撮影出力2候補・保存2候補、SDK隔離、原本識別と世代付きcommit | 表示変換・解析・通信・Mac mini・Photos・削除の実装、方式選定とアプリ全体の復旧・競合制御 |
| [repository-structure.md](../../docs/repository-structure.md) | 撮影・保存に必要なDomain/Application/Platform、Features/Capture、Compositionと対応test配置 | Library/Playback/Connection、MediaOperations/MediaIO等の後続機能。空ディレクトリ作成を機能実装と数えない |
| [development-guidelines.md](../../docs/development-guidelines.md) | 既存Xcode設定・外部依存なしを維持、差分保護、関連build/test・Simulator確認と証跡管理 | 実機・品質・実通信／実データ・独立validation・初期版全体のDone条件。現在の検証成功を全体合格にしない |
| [glossary.md](../../docs/glossary.md) | 希望／能力／実値、操作ID・世代、WB、音声4軸、保存の正常／部分／不明／失敗を値と状態へ反映 | 軽量版の版・明示確認／失効・容量整理／破棄・写真登録・通信再開等の未実装領域 |

- 実装済みの範囲: 撮影・保存基盤の一部と方式比較用の探索実装。残件は実機試験だけではなく、製品機能の未実装も多い。
- 検証済みの範囲: E-P06-08〜11の有意味な単体／統合64実行＋UI1実行、実機用SDKの署名なしbuild、Simulator起動・表示。今回の対応整理ではコード変更・再試験は行っていない。
- 先行対象を検討できる範囲: 現steering内の原本再生、設定・保存／復旧、WB・音声・補正・ズーム／切替のうち方式非依存の規則・試験窓口。実APIへの統合、未合意の操作・数値、D02の標準変換資材、G03の方式選定を完了済みにはできない。
- 計画の範囲: このsteeringは撮影基盤の技術検証に限定する。人物AF・NDやライブラリ・転送・Mac mini変換・写真保存・容量整理・破棄等は後続必須として保持し、今回のsteering完了を6文書に記載した初期版全体の完成としない。別Workflowは開始していない。

## 振り返り・後続への残課題

- 実装完了日: 未完了。検証工程完了日: 未完了。
- 計画との差分: 本人の実機なし先行指示に基づき、P02/P03の開発側／静的前提を切り出してP04/P05・P06の実機非依存部分の依存を調整。全体のDone条件・全P0・追跡ID・G01〜G04の実機／品質ゲートは維持する。
- 直近の残課題: P02/P03の実環境・既存データ・媒体保管先・実能力依存値、P06の実機起動とD02公式変換資材の確認。実機接続は本人指示で後回しを維持し、未確認を非対応へ置換しない。G03は方式採用前、G04は品質判定前に解消する。P09以降の残機能と全PRD評価は未完了。
- 後続必須: FR-01のND再評価、FR-03の構図予告／停止支援反映、人物AF・ND、FR-07の予告・画質根拠の停止支援、製品操作、ライブラリ・通信・Mac mini・軽量版・写真・容量整理・破棄、NFRの残統合と実データ検証／合意済み整理。現行PRDを要求正本とし、requirementsの79行を追跡表として引き継ぐ。
- 安定docs更新候補: 実機対応・方式決定・保存／WB／音声境界・設定復元・後続統合制約・安定した証跡手順。要求変更がない限りPRDを縮小しない。未合意の数値や探索UIを永続製品仕様へ移さない。
- 継続中のWorkflow: `$implement-steering .steering/20260926-capture-foundation-feasibility/`。別Workflowは未開始。
