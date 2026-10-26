# Upload chunk のローカル生成部分

DI-SOURCE-20261025-20（503入力、398code）で、固定binding/indexからoverflowを避けて範囲を決め、同じ原本lease/FDから64KiB以内の単位でcopyしchunkを独立hash・実preadで全読戻しする部分を実装した。unknown leafは上書き/採用/削除せず、失敗時もcaller leaseを解放しない。旧whole処理・namespaceは指定mode1箇所以外byte同一。

関連177は4suite32宣言69展開成功、skip/失敗/診断0、398code前後一致。新Domain9宣言30展開、Storage10宣言22展開は実partial write/EINTR/差替・取消/duplicate/unknown/reopenとwhole分離を含む。入力の保存検査と媒体bytesは技術合成fixtureで、正式producerやSDK送信成功の証拠ではない。

[main差分確認](main-review.json)。同feature UnitBの最新GET・全prior stop履歴の同writer guard、typedwire/SDK接続は続行中。strict正開始・全媒体停止・全steeringは未完、独立validationは開始していない。
