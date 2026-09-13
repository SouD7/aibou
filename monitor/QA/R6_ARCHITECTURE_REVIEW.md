# R6 独立設計レビュー

2026-09-13。独立設計担当 `r4_architecture_review` の最終回答を統括担当が要約して保存した。新規担当の起動がエージェント数上限に達したため、前回の独立担当を再利用し、固定した最新版を読み直した。

**Architectural Status: WATCH。新規の確定不具合なし、BLOCKなし。前回の修正3件はCLEAR。**

## 対象と証拠

23:38:46 JSTの31ファイルを固定し、担当がSHA-256一致を確認した。[対象manifest](r6-snapshot.json)。前回修正検証時から内容の変更はない。

| 前回修正 | 再確認した根拠 | 結論 |
|---|---|---|
| 診断API契約 | MonitorStore.swift:14–18、175–217、Diagnostics.swift:64–89、README.md:15–17。one-shotは継続runをresetし、監視中Storeが区間とingestを所有。DiagnosticTests.swift:31–96で継続・停止・gap・重複・snapshotを検証 | CLEAR、追加修正不要 |
| 機器cache時刻とTTL | DeviceSampler.swift:45–97、274–285。実取得DateとContinuousClock期限を分離。DeviceTests.swift:17–70で29/30秒境界、壁時計補正、失敗時刻保持を検証 | CLEAR、追加修正不要 |
| 保存summary検証 | StorageScanner.swift:246–268、458–470。正常完了scannerと復元検証が整合。StorageTests.swift:115–150で矛盾拒否・ファイル不変・部分結果と旧errorCount省略受理 | CLEAR、追加修正不要 |

現行Storeはprivate engineを専用serial queueから利用し、MainActorのgeneration検証で古い結果のUI・履歴・診断への採用を拒否する。直接command終了確認と登録済み保存も共通の最大2秒deadlineで待ち、MainActorを塞がない。

## 継続する既知WATCH

以下は今回発見した新規の確定不具合とは別の検討事項。コード上の経路と、実機での再現・負荷測定を区別する。

| 懸念・根拠 | 発生条件・影響・確度 | 最小対応案 |
|---|---|---|
| 復帰後の予約済みsample。[MonitorStore.swift:200](/Users/sodaiyamamoto/aibou/monitor/Sources/MonitorStore.swift:200)、[CoreSampler.swift:144](/Users/sodaiyamamoto/aibou/monitor/Sources/CoreSampler.swift:144) | sleep前のjobがwake後に走ると、結果破棄前にclock基準を更新し、その後のpreservingClock resetがsleep区間を失う可能性。順序の存在は高確度、実スリープで未再現 | collect開始前に検査できるthread-safe世代取消token |
| MainActorでの診断全量投影。[MonitorStore.swift:91](/Users/sodaiyamamoto/aibou/monitor/Sources/MonitorStore.swift:91)、[Observations.swift:156](/Users/sodaiyamamoto/aibou/monitor/Sources/Observations.swift:156)、[DiagnosticsView.swift:10](/Users/sodaiyamamoto/aibou/monitor/Sources/DiagnosticsView.swift:10) | sample採用時と診断表示時に全row/processを投影。電力結果は最大12,000 leaf。経路は確定、最大UI遅延は未測定 | 8ルールに必要な指標だけの軽量入力 |
| MainActorでの履歴復元。[MonitorStore.swift:110](/Users/sodaiyamamoto/aibou/monitor/Sources/MonitorStore.swift:110)、[History.swift:120](/Users/sodaiyamamoto/aibou/monitor/Sources/History.swift:120) | 最大32 MBの履歴を初期化中に同期read/decode/sanitize。経路は確定、停止時間は未測定 | archive queueで復元し検証済み結果を反映 |
| 最大50万nodeの全量JSONと索引。[StorageScanner.swift:82](/Users/sodaiyamamoto/aibou/monitor/Sources/StorageScanner.swift:82)、[StorageScanner.swift:231](/Users/sodaiyamamoto/aibou/monitor/Sources/StorageScanner.swift:231) | 上限近傍でobject graph、Data、索引を保持。全量保持は確定、今回は巨大archiveを再測定せず | 分割形式またはページ単位で読める索引への移行を検討 |
| 索引完成から保存登録までの終了窓。[MonitorStore.swift:142](/Users/sodaiyamamoto/aibou/monitor/Sources/MonitorStore.swift:142)、[MonitorStore.swift:293](/Users/sodaiyamamoto/aibou/monitor/Sources/MonitorStore.swift:293) | terminal索引構築中に終了すると最新完了scanが保存登録されない。以前のatomic archiveは残る。順序は確定、頻度は未測定 | 索引構築より先に保存またはpipeline全体をpending登録 |
| 管理者認証先の子孫終了。[AdditionalCollectors.swift:248](/Users/sodaiyamamoto/aibou/monitor/Sources/AdditionalCollectors.swift:248) | 直接Processはosascript。認証先powermetricsの終了までは未検証。取消・timeout・終了後に単発計測が完了する可能性 | 実機統合試験後、必要に応じて追跡できる権限境界を設計 |
| 将来の複数consumer。[MonitorStore.swift:5](/Users/sodaiyamamoto/aibou/monitor/Sources/MonitorStore.swift:5)、[CoreSampler.swift:113](/Users/sodaiyamamoto/aibou/monitor/Sources/CoreSampler.swift:113) | unchecked Sendableなengineの可変baselineは並行呼出し禁止がコメント契約。現行単一Storeでは未発生 | 拡張前にactor所有または単一producerからのsnapshot配信 |

## トレードオフ

失敗inventoryの30秒cacheは回復反映を最大30秒遅らせる代わりに反復取得を抑える。不正archiveは自動修復せず元ファイルを保持する。単独継続session APIは提供せず既存Storeを利用する。いずれも前回修正に伴う明示的な設計判断で、追加修正は不要。

既知WATCHを解消する場合は、収集開始取消、軽量診断入力と非同期履歴復元、保存登録順序を先に検討する。actor化や保存形式移行は改修範囲と移行・障害復旧の複雑さを伴うため、本レビューでは実装しない。

## 検証と限界

担当は固定snapshotの全test.sh成功と診断catalogテストを確認した。[全テスト](r6-tests.log)。担当回答時点のbuildは未算入で、統括担当がその後の成功と署名・plist検証を[統合報告](CODE_REVIEW_R6_2026-09-13.md)に記録する。

GUI、実スリープ、管理者認証、巨大archive、実ユーザー保存データは操作していない。
