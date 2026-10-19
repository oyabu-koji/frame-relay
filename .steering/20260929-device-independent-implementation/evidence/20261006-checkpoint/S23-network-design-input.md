# S23 読取引渡し（2026-10-06）

network_map explorerのread-only調査をmainが受領。実装/試験/独立validationではない。既存単一writerを維持し別DBを作らない。

## 既存/不足

- MediaRequest.swiftは本人意思/複合待機/transport/遠隔結果を分離。BackendMediaPortsはrequestStopとobserveStopを分離。
- MediaStoreCommandsはowner/context媒体lease、OriginalStoreDocumentは全owner/accessGeneration/writer reconciliationEpochを要求。
- ProductLibraryFactoryの同store/accessへ両recovery observerを注入する。ProductCompositionのlocal player/探索capture背景停止に、一律transfer停止を足さない。
- 新規候補: Application/MediaIO/MediaGateCoordinator、Application/MediaOperations/MediaTransferCoordinator、Platform/Network/URLSessionMediaTransport・MediaReaderRecovery・NetworkConditionAdapter、単独所有CompositionとUIApplicationDelegate橋。
- 不足する永続対応: (session identifier, task identifier) → operation/attempt/target/registration/媒体lease/原本leaseまたは管理upload一時ファイル。taskDescriptionは正本でなく照合key。
- async継続消失後のrestore/OS callbackイベント受け口、upload用管理一時ファイル所有値、S49からREC/保存/異常終了の世代付き事実入力も不足。
- ManagedOriginalAccessはURL非公開/最大64KiB read。背景file uploadはOS領域へcopyするため、原本URL直渡しで全reader管理を迂回しない。管理lease→内容確認済みupload一時ファイル→SDK所有/解放を別追跡する。現TemporaryMediaReceiptはrendition専用。

## 停止/復旧

cancel要求→didCompleteWithError→callback派生I/O drain→SDK/handle解放→lease release commit。suspended/resume data/actor辞書空を解放証拠にしない。既知全背景sessionを同identifierで再生成しgetAllTasksと永続対応を照合、未知/重複はunknown。task不在は遠隔未実行や保存成功を意味しない。全owner観測とwriter epoch/latest accessGenerationを照合しreconcileMediaをcommit、観測中新leaseは世代/CAS競合で拒否。

UIApplication背景completion handlerはURLSession didFinishEventsだけで返さず、delegateからactorへ渡したstore commit/ファイルdrain完了を待つ。RECのgate失効/停止要求を先行するがMac ACK/hashをREC開始条件へ加えない。

## installed iOS27 SDK根拠

SDK root: /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/

Foundation.framework/Headers/NSURLSession.h: getAllTasks346、session内task ID693、cancel789/suspend806、背景upload copy891、同identifier復旧1287、didFinishEvents1662、task終端1781、download一時ファイル即時保全1858。UIKit/UIApplication.h:460が背景復帰入口。

## 強い保証の局所未成立

- NSURLSession.h:1352–1367、NSURLRequest.h:239–248はcellular/expensive/constrained/ultraConstrained許可設定で、Wi-Fi interface種別を拘束する公開APIは見つからない。allowsCellularAccess=falseは必須でも厳密Wi-Fi保証とは異なる。
- Network.swiftinterface:2502–2506のNWParameters.requiredInterface/requiredInterfaceTypeは存在するがURLSessionへの受渡しAPIは確認できない。NWPathMonitor(requiredInterfaceType:)は監視のみ。
- NSURLSession.h:1384: background sessionは常に接続待機しwaitsForConnectivityを無視。前景pathだけではOS停止中のVPN基礎回線変更を拘束できない。
- NSURLSession.h:1732–1733: background sessionはredirectを常に追従、willPerformHTTPRedirectionは呼ばれない。最終URL照合を送信前拒否の証拠にしない。
- NSURLSession.h:1517: backgroundではcustom URLProtocol不可。
- NSURLSession.h:2144–2154のcellular等metricsは事後観測で経路拘束ではない。

永続task/OS終端/callbackは実装可能。厳密なVPN基礎回線Wi-Fi拘束とbackground redirect送信前拒否の方式は未成立として局所保留。前景限定へ仕様を縮小しない。DV-12には実Wi-Fi/Tailscale/cellular切替/背景/ロック/REC・停止時間/ファイル保護を残す。方式未成立を単なる実機未確認に言い換えない。
