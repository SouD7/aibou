# R5レビュー修正結果

対象: [R5レビュー](CODE_REVIEW_R5_2026-09-13.md)の新規1件と、R4から引き継いだ確定2件。2026-09-13。

## 修正内容

| 指摘 | 修正 |
|---|---|
| 単独API利用時にCPU継続判定の前提が不明 | READMEとAPIコメントで、継続2種類を含む8判定には監視中の既存MonitorStore.diagnosticResultsを使用すると明記。単発snapshotは6種類の瞬時判定のみで、CPUの継続時間を蓄積しないことを説明 |
| 機器一覧のキャッシュに新しい取得日時が付く | Cacheの実取得Dateを一覧status・panelにも伝播。TTLをContinuousClockの30秒で管理し、壁時計の前進/後退から分離 |
| 保存索引のsummaryが矛盾しても復元できる | rootがdirectory、完了日時あり、件数とnodes数一致、全体合計とroot集計一致、報告エラー件数が保持詳細数以上であることを検証。矛盾するファイルは変更せず拒否 |

Sourcesの変更はDeviceSampler.swift、StorageScanner.swift、MonitorStore.swift（コメント）、Diagnostics.swift（コメント）。TestsはDeviceTests.swiftとStorageTests.swift。README、QAの計画・再現harness・報告を更新した。依存追加・保存schema変更なし。

単発snapshotを継続監視へ読み替える処理は追加していない。完了した走査に権限不足・部分集計・allocatedBytes未取得が含まれる場合や、旧schema 1で任意のerrorCountが省略される場合は引き続き復元できる。日時の前後関係はシステム時計補正で逆転し得るため、それだけで拒否しない。

## 回帰・検証

- 新規テストで修正前の2件を再現: [cacheの失敗](r5-fix-red-device.log)、[保存検証の失敗](r5-fix-red-storage.log)。
- 修正後の対象テスト成功: [Device](r5-fix-device.log)、[Storage](r5-fix-storage.log)。
- Cache: 一覧再利用中の行/status/panel日時一致、29秒では再利用・30秒では更新、壁時計+1時間/-1時間、取得失敗の日時/status保持を検証。
- Storage: 完了日時欠落、件数・logical/allocated合計の矛盾、root種別不正、負のerrorCount・詳細数未満を拒否。正常な部分取得、容量不明、errorCount省略、詳細上限を超えるエラー総数を受理。loadがファイルを変更しないことも検証。
- 既存の循環graph、2万段の合成tree、通常scannerの保存復元、CPU/診断/Store/command等の全テストが成功（23:11:37 JST）。[全テストログ](r5-fix-tests.log)
- テストはtest.shと同じソース・フラグを使い、キャッシュだけを独立した `.build/r5-fix-module-cache` に指定した。

- 最新アプリの最適化buildとad-hoc署名が成功。[ビルドログ](r5-fix-build.log)
- `codesign --verify --strict --verbose=2`が成功。元ファイルとbundle内のInfo.plist・PrivacyInfo.xcprivacyも`plutil -lint`で正常。[署名・設定ファイル検証](r5-fix-bundle-checks.log)
- [最終ソースSHA-256とR5からの変更一覧](r5-fix-source-sha256.json)を保存。R5対象のうち、変更は上記Sources 4、Tests 2、READMEのみ。

## 独立再レビュー

| 担当 | 判定 |
|---|---|
| [コード担当](R5_FIX_CODE_REVIEW.md) | APPROVE。新規指摘0件 |
| [設計担当](R5_FIX_ARCHITECTURE_REVIEW.md) | 修正範囲CLEAR、製品全体WATCH。BLOCKなし |
| 統合 | COMMENT。確定3指摘は解消、既知の設計WATCHを継続 |

両担当は今回の実装担当とは別で、コード・テスト・API契約を独立して確認した。以下の未検証事項を含め、製品全体の問題がすべて解消したという判定ではない。

## 残る制約

今回の確定3指摘とは別のWATCHとして、スリープ時のqueued sampleとclock基準、診断全量投影・履歴復元のMainActor負荷、全件JSONの大規模負荷、索引構築後まで保存登録されない終了窓、管理者認証先の終了未確認、将来の複数consumerの収集所有境界を維持する。

GUI再起動、実スリープ、管理者認証、巨大archiveの再測定は行っていない。起動中のアプリとユーザーの保存ファイルは操作していない。新しいコードはアプリを次に起動した際に反映される。
