# S25 test-only 固定版HTTP/AVPlayer fixture

この支援は合成60秒H264/PCM Movieを、新しい隔離runtimeから認証付きHTTP Rangeで配信する技術試験用である。製品server API、DistributionReceipt、変換・配布証拠を作らない。既存backend、guard、runner、登録listener、旧snapshot/runtimeは変更しない。

## 準備

mainが現sourceを凍結して実Xcode構成を確認し、`RenditionFixtureGenerationTests/generateDisposableMovieAndManifest()` を明示opt-in実行する。生成manifestの `fixtureOnly=true/path/byteCount/sha256/mime/duration=60` と実Movie全hash/sizeが一致しなければprepareは拒否する。欠落した旧Movieや架空manifestは代用しない。

同じ版で `RenditionHTTPFixtureTests` の5宣言をSDKに列挙させる。通常4宣言と6parameterのmalformed宣言、計10実行が対象である。列挙の識別子には `()` / `(mode:)` を含める。prepareには列挙JSON、実project/scheme列挙、destination観測も渡す。

```sh
python3 -I -B -S .steering/20260929-device-independent-implementation/support/server-isolation/prepare_rendition_fixture.py --revision 001 --fixture-manifest <生成manifest.json> --enumeration <SDK列挙.json> --xcode-list <xcode-list-verified.txt> --destinations <destinations.txt> --destination-udid DFE46693-E8DD-4814-8957-4F327699F719 --derived-data /private/tmp/fr-di-20261014-s25/DerivedData
```

入力不足時は停止する。このplaceholder command自体は実行しない。出力は新 `/private/tmp/fr-di-20261014-s25/S25/preparation-NNN`。8支援file（新5件＋既存guard/lifecycle/runner）と依存provenance、具体config、SDK観測、App/Test/projectの全source hashを凍結する。`runtime-fixture-NNN` は未作成のまま残す。

依存の正本はrepo内 `evidence/20261014-s26j-complete/` のprovenance/checkpoint/archive manifest。既存Python 3.12実体、entry symlink、site-packages全file、pyvenv.cfg、.pthをread-only照合し、.pthは実行しない。backend snapshotはimportしない。既存tmpに依存provenanceが残っていることを仮定しない。

## 実行と証拠

`preparation-NNN/commands.json` の `dry_run` はsource/config/fixture hashと具体child commandの確認だけを行う。`execute` はmainの具体レビュー後だけ使い、親supervisorがlistener→実ready→Simulator wrapperを起動する。新runtime・result bundleを上書きしない。

listener自身がguarded bootstrapを持ち、既存 `run_pytest.py` の設定/FD helperと `listener_lifecycle.serve_observed` をread-only再利用する。guardの書込root、SQLite authorizer、外向通信禁止、1processにつき1回の `127.0.0.1:0` bind、subprocess禁止を維持する。22設定は従来helperから明示し、HOMEは値を変えず継承する。backend Settingsをimportしていないため「製品設定load成功」とは呼ばない。

guard後にだけ既存site-packagesをsys.pathへ追加し、Uvicorn/asyncio/h11、wsなし、proxy/access logなし、reload/worker childなしで起動する。外部Movieを新runtime/mediaへcopyし、開始前・終了後に両Movie全hash/sizeを照合する。source Movieと外部依存は変更しない。

wrapperは確定run/PID/URL/期限と0600秘密fileを照合し、許可した7環境値だけを `TEST_RUNNER_` 付きenvへ渡す。tokenはCLIに載せず、Xcode stdoutの同文字列は保存前に伏字にする。内部xcresult等が使い捨て環境を保持する可能性は残るため、恒久秘密は使わずlistener終了で失効させる。metadata取得には秘密envを渡さない。

実Xcode commandはFrameRelay project/scheme/test plan、Debug、確認済destination、独立DerivedData、package自動解決なし、並列testなし、診断自動収集なしを明示する。SDK metadataから5宣言/10実行の完全一致、6parameter全値、失敗/skip/expected failure各0を要求し、Xcode exit 0や0実行だけでは成功にしない。App/Test/project sourceは実行前後で再照合する。

Xcode実終了後はnonzero/timeoutでもsummary・全test tree・build-resultsを各10秒上限で個別回収し、どれかの抽出失敗で他の回収を省略しない。全test treeの複数assertion issueを保持し、metadataに使い捨てtokenが現れた場合も保存前に伏字にする。全体summaryの5宣言とdevice別summaryの10実行を区別する。wrapperはXcode exit、試験失敗数、build診断、各metadata抽出状態を分け、親もchild結果と欠落artifact一覧を独立保存する。metadata欠落で元のXcode/試験失敗を隠さず、欠落を成功へ変更しない。
各metadata toolのstderrも、timeout時の取得済分を含めて記録する。秘密envは渡さず、使い捨てtokenを伏字にした後の先頭8 KiBだけを保存し、切詰めの有無と表示を付ける。これによりTestReport保存権限拒否などの抽出理由を、単なるnonzero exitへ縮約しない。

listenerは各requestの到着・header/最初のbody送信時刻、要求Range、Content-Length、実file読取byte、ASGI send受理byte、disconnect/完了、file close・handler実終端を保存する。ASGI send受理byteをclient受信byteとは同一視しない。`X-Fixture-Scenario: streaming` はstreaming試験だけの識別子で、実送出範囲のunion（重複Rangeを除いたcoverage）を全取得caseから分離する。clientの進行時受信byte/decoded frameと別に、streaming停止までに全Movieを送出していないことを照合する。

## HTTP契約

GET `/media/<mode>`、Bearer必須、1つの `bytes=start-end` Range、最大64 KiB。正常応答は206とexact Content-Range/Length/Type、X-Fixture-Rendition/SHA256/Size。headerにはno-storeを付け、別originへ接続しない。

| mode | 実動作と確認範囲 |
| --- | --- |
| normal | 固定Movieの指定範囲を配信。4 KiBごと10msの試験専用throttle |
| wrong-version / wrong-digest / wrong-size | 1つのidentity headerだけ不一致。body原本は変更しない |
| short / oversize | 実要求Rangeの長さNに対してbody/正直なContent-LengthをN−1/N＋1 byteにする。HTTP framingは正しく、Content-Rangeとの不一致をheader段階で拒否する試験 |
| redirect | 302→同listenerの未公開 `/media/redirect-target`。追従が0件であることを観測 |
| delayed | 206 headerと最初の1 byteを送信し、2秒待機。その間の停止によるdisconnect、またはgate loss後の残body送信と端末非deliverを分離して確認 |

short/oversize成功は、正常Content-Lengthを受理した後の実body不足・上限超過を検出した証拠ではない。その種類の途中切断/不正framingを同modeへ混在させない。端末側のbody count guard、正常header後切断の検証範囲は別に評価する。
clientがheader不一致を直ちに拒否すればbody送出が0 byteでも正しい。親は全206応答のRange値を整数として照合し、`N=end-start+1`、`0<N<=65536`、原本全長とのtotal一致、`0<=start<=end<total`を要求する。cacheのread-aheadで呼出元の64 byte要求がHTTPでは最大64 KiBへ拡張されるため、固定64 byteではなく実要求Rangeを使う。short/oversizeは各1件、N−1/N＋1の宣言長、header実送出、実送出量が宣言長以内、file closeと実終端を照合し、全body送出は必須にしない。観測した送出量は省略せず保存する。

delayedは厳密に2件とし、停止側は1 byteだけ送出した未完のRangeと実disconnect、gate loss側は実Range長Nの全byte送出と最初のbodyから実終端まで2秒以上を各1件要求する。全206応答のheader/最初のbody/実終端時刻は有限値・順序を照合する。全byte送出後のclient disconnectも実終端として扱い、端末非deliverはSDK側の試験結果と合わせる。HTTP003の旧固定長判定による親失敗は保持し、修正版は新preparation/runtimeで再実行する。

throttle・2秒delay・64 KiB上限・listener1200秒・wrapper最大1100秒は合成検証の条件であり、製品timeoutや速度基準として採用しない。gate拒否、認証拒否、停止は実client/SDK terminalとserver側観測を合わせて評価する。SDKの音声track存在は聴取品質の証拠ではない。

## 終了条件

通常停止fileもrun identityと実listener PIDへ束縛する。Uvicorn server task/connection、response handler、file FD、生成threadを全終端/joinし、guard拒否0、媒体FD残存0、SQLite接続0、許可外import0、原本/依存/source不変を要求する。

親はlistener/wrapperの `Popen.wait()` とwrapperのXcode実終了を別に観測する。停止要求の受付だけを実停止としない。中断時は自分のPopen childとwrapperが作ったXcode process groupだけを停止する。強制signal/timeout/未終了/未close/未joinは失敗である。0600秘密fileはlistener finallyで削除し、異常時に残れば親が全child実終了を確認してから削除するが、通常成功へ変更しない。秘密値や秘密file hashをpublic evidenceへ保存しない。

準備・静的compile・dry-runはHTTP/AVPlayer成功ではない。合成fixtureの再生技術証拠を、製品配布wire、実Log/標準変換、TLS/Wi-Fi/Tailscale、実機/背景/ロック、PhotoKit書込、撮影原本の受入へ拡大しない。
