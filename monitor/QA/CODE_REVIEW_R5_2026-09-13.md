# 機能追加後の独立レビュー R5 — 2026-09-13

> このレビュー後、確定3指摘を修正した。[修正・独立再レビュー・検証結果](R5_FIX_RESULTS.md)。以下は修正前の記録を保持している。

## 結論

**COMMENT（改善事項あり）。新規MEDIUM 1件。新規CRITICAL/HIGH/LOWは0件。** 現行UI/MonitorStore経由の追加診断に、新たな確定不具合・設計BLOCKは確認されなかった。新規指摘は単独API利用の説明不足であり、前回未修正のMEDIUM 1・LOW 1とは別に数える。

| 独立担当 | 判定 |
|---|---|
| コード担当 | COMMENT。単独利用の案内にMEDIUM 1件 |
| 設計担当 | WATCH。現行UIの契約は整合、単独利用の説明と既知の設計制約を残す |
| 統合 | **COMMENT** |

[コード担当の詳細](R5_CODE_REVIEW.md)・[設計担当の詳細](R5_ARCHITECTURE_REVIEW.md)。

## 対象

2026-09-13 22:42:42 JST時点の最新版。Sources 12、Tests 9、scripts 3、plist/privacy 2、Markdown 5、計31ファイルを固定した。[対象時刻・SHA-256](r5-snapshot.json)・[確認したソースZIP](r5-reviewed-source.zip)。

R4以降の主な変更は、診断70ケース・8自動判定の完成、同一コアごとの継続追跡、単発snapshotと継続監視の分離、評価不能理由の表示、画面の症状・確認済み状態保持、診断専用テストと利用文書。

最終照合でも現在の作業フォルダは固定した31ファイルと一致し、追加の未確認Sources/Testsはなかった。[最終照合](r5-final-scope-check.json)。R4時のようなレビュー途中のソース変更は今回検出していない。

コード担当は新しいコンテキストの`r5_code_review`。設計担当はエージェント数の上限により前回の独立設計担当`r4_architecture_review`を再利用し、新しい固定対象を再確認した。いずれも今回の実装担当ではない。ソースの修正・アプリ再起動・ユーザー保存データの変更は行っていない。

## 新規指摘

### MEDIUM / P2: 単独APIの利用案内ではCPU継続判定の前提が不足する

**場所:** [README.md:15](/Users/sodaiyamamoto/aibou/monitor/README.md:15)、[MonitorStore.swift:14](/Users/sodaiyamamoto/aibou/monitor/Sources/MonitorStore.swift:14)、[Observations.swift:156](/Users/sodaiyamamoto/aibou/monitor/Sources/Observations.swift:156)、[Diagnostics.swift:66](/Users/sodaiyamamoto/aibou/monitor/Sources/Diagnostics.swift:66)。

READMEは単独利用で新しいObservationSnapshotを順番にingestし、evaluateする方法を案内する。しかし用意されているUI非依存のMonitoringEngine.collectObservationsは、監視区間を持たないstate=snapshotを返す。DiagnosticEngine.ingestはrunning以外で継続記録をリセットするため、そのproducerを利用した単独呼出しでは20秒以上CPUが高負荷でもcpuBusy/coreBusyはobservingのままとなる。

**影響範囲:** アバターなどから単独APIを組み合わせる場合の案内・契約不足。MonitorStore経由ではrunningと監視区間が付与されるため、**現在のアプリ画面のCPU継続判定にこの問題はない**。単発snapshotだけでは連続監視を証明できないという実装方針自体は正しい。

**根拠:** DiagnosticTests.swiftの同一区間20秒のrunning fixtureはmatched、snapshotを20秒間繰り返すfixtureはobservingを期待し、今回も全テストが通った。実装の挙動は意図通りであり、利用説明がこの違いを十分に伝えていない。

**最小修正:** 文書でMonitorStore.diagnosticResultsを推奨経路とし、単発snapshotではCPUの持続判定が成立しないことを明示する。単独の継続利用も正式に提供するなら、安定したsegmentと停止・再開を管理するsession APIを用意する。snapshotを無条件にrunningへ読み替える修正は行わない。

**確度:** 高（コード契約・既存の動的テスト）。現行GUIへの影響と単独APIへの影響は分けて評価した。

## 前回から残る確定指摘

| 優先度 | 項目 | R5での状況 |
|---|---|---|
| MEDIUM / P2 | 機器一覧cacheのstatus/panel取得時刻が毎回新しくなる | DeviceSamplerはR4と同じ。未修正 |
| LOW / P3 | 保存索引の完了日時・件数・合計の矛盾を受理 | StorageScannerはR4と同じ。未修正 |

この2件をR5で新しく見つけた問題とは数えない。[R4の再現・根拠・修正案](CODE_REVIEW_R4_2026-09-13.md)を引き継ぐ。今回の追加機能による再発でもない。

## 維持する設計上の懸念

スリープ復帰時のqueued sampleとclock baselineの競合、診断のMainActor上の全量Observation投影、管理者認証先の終了未確認、全件JSONの大規模負荷、索引作成後まで保存登録されない終了窓、MainActor履歴復元、将来の複数consumerの所有境界をWATCHとして維持する。実機未再現・性能未測定のものを確定バグ件数へ加えてはいない。

## 検証

- ソースを変更せず、独立したmodule cacheで全テスト成功（2026-09-13 22:47:12 JST）。[ログ](r5-tests.log)
- カタログ70 IDがすべて一意で、DIAGNOSTICS.mdの70 ID集合と一致。[記録](r5-catalog-check.json)
- 最初の共有cacheを使った試行では既存MonitorStoreのFoundation参照がコンパイルに失敗した。[初回ログ](r5-shared-cache-attempt.log)。独立cacheでは同一ソースが成功したため、アプリのコード不具合には数えていない。cache内部の原因までは特定していない。
- 同じ固定対象でmacOS 13ターゲット・最適化warnings-as-errors build成功。[buildログ](r5-build.log)
- 生成アプリのcodesign strict、元/バンドルのInfo.plist・PrivacyInfo.xcprivacy全lint成功。[検証ログ](r5-bundle-checks.log)

診断テストは、初回と20秒継続、同一コアの順位交代、欠測・重複・再開区間、単発snapshot、停止・古い値・未来時刻・未取得/部分取得/推定・非有限値、復旧、手動ケースの非推論、結果のCodableを確認する。GUI操作、実スリープ、管理者認証、巨大archive負荷、物理故障の再現は今回行っていない。カタログの全Appleページの内容は今回再調査していない。
