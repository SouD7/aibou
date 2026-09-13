# R5修正後・独立設計レビュー

2026-09-13。独立担当 `r4_architecture_review` の返答を統括担当が要約・保存したもの。実装担当とは別の担当が今回の変更を確認した。

**今回の修正範囲: CLEAR。製品全体: WATCH。設計BLOCKなし。**

## 修正の評価

1. 単独APIの説明が実装契約と一致した。継続診断は既存Storeが収集・監視区間・停止・ingestを所有する。snapshotを偽ってrunningにする変更はなく、確度は高い。
2. Cacheの実取得Dateと単調時刻による有効期限を分離した。`instant < expiresAt`で30秒境界から再取得し、行・一覧status・panelの日時も一致する。壁時計変更と失敗キャッシュのテストがある。R4のキャッシュ日時MEDIUMと壁時計TTLのWATCHは解消。
3. 保存データ検証は通常scannerが生成する完了状態と整合する。errorCount省略、部分集計、allocatedBytes不明を受け入れ、矛盾するデータを拒否する。loadがファイルを変更しないテストもある。

## 採用したトレードオフ

- 独立した継続診断セッションAPIは提供せず、継続CPU判定には監視中Storeを用いる。
- 取得失敗も30秒キャッシュするため、機器取得の回復反映が最大30秒遅れる。
- 不正な保存データの自動修復は行わず、元ファイルを保持して拒否する。再走査が必要になる。

## 継続するWATCH

- スリープ前に予約された基本sampleが復帰後に動き、clock基準のreset前にCoreSampler.previousClockを更新する可能性。実スリープで未検証。
- 診断の全行・全プロセス投影と履歴復元がMainActorで動く。最大規模のGUI負荷は未測定。
- 管理者認証先のpowermetrics子孫プロセスの終了は未確認。
- 最大50万ノードの全量JSON・索引・Dataによるメモリ負荷。
- 最終索引の構築から保存group登録までの終了時の空白期間。
- 状態を持つunchecked Sendableなengineを将来複数consumerで使う場合の所有境界。現行はprivate engineと直列queueによる単一producer。

今回の3修正について追加変更は不要という判断。上記WATCHを製品全体の評価に残し、[統合結果](R5_FIX_RESULTS.md)はCOMMENTとする。
