# 最新版の独立レビュー R4 — 2026-09-13

## 結論

**COMMENT（改善事項あり）。CRITICAL 0、HIGH 0、MEDIUM 1、LOW 1。** 新規指摘2件は両担当が一致し、親が固定コピーで再現した。前回R3で修正した経路の再発は確認されなかった。

| 独立担当 | 判定 |
|---|---|
| コード担当 | COMMENT。確定指摘2件 |
| 設計担当 | WATCH。新規BLOCKなし。追加検証が必要な懸念2件 |
| 統合 | **COMMENT** |

[コード担当の詳細](R4_CODE_REVIEW.md)・[設計担当の詳細](R4_ARCHITECTURE_REVIEW.md)。

## 対象の固定

新しいコンテキストのコード担当・設計担当が独立に確認した。ソースコードの修正は行っていない。

レビュー開始時は前回R3修正の最終検証対象22ファイルと一致していた。その後、別タスク「macOS不具合診断機能を追加」が同じ作業フォルダで診断機能を追加し、CoreSampler・MonitorStore・Appも変更した。このため、**22:14:37 JST時点のコピーへ対象を固定**し、追加分も静的レビュー、既存全テスト、ビルドの対象にした。以降の並行変更は今回の判定に含まれない。開発途中の診断機能を完成版とみなした承認ではない。

- 固定対象: Sources 12、Tests 8、scripts 3、plist/privacy 2、Markdown 4、計29ファイル。
- [対象時刻・SHA-256一覧](r4-latest-snapshot.json)
- [確認したソースの固定コピー（ZIP）](r4-reviewed-source.zip)
- 開始時の旧22ファイルとの照合は[開始時記録](r4-source-sha256.json)に分離して保存。

## 新規指摘

### MEDIUM / P2: キャッシュされた機器一覧に新しい取得時刻が付く

**場所:** [DeviceSampler.swift:63](/Users/sodaiyamamoto/aibou/monitor/Sources/DeviceSampler.swift:63)、[DeviceSampler.swift:267](/Users/sodaiyamamoto/aibou/monitor/Sources/DeviceSampler.swift:267)。

機器・ハードウェア一覧は30秒キャッシュされるが、再利用時も一覧status指標のrecordedAtとPanel.capturedAtを現在時刻で作り直す。一覧の行は元の取得時刻を保持しており、同じ一覧に異なる鮮度の情報が付く。観測APIでstatusやpanel時刻を参照するconsumerは、実際より最大約30秒新しい一覧と解釈し得る。

**再現:** USB列挙fixtureを注入し、20ミリ秒間隔で2回sample。USB取得は1回なのに、2回目のstatus/panel時刻が行の取得時刻より新しくなることを確認。

**最小修正:** cachedInventoryから取得日時も返し、一覧statusとpanelにその日時を使用する。必要なら「今回の投影時刻」を取得日時と別に持つ。TTL内は同じ取得日時、TTL更新後だけ日時が進む回帰テストを追加する。

設計担当は、TTL判定がDate差のため壁時計後退時にキャッシュ期限が延びる点も確認した。TTLには単調時計を使うことを推奨する。この時計変更の実機試験は未実施。

**確度: 高。実行再現済み。** 一覧再取得が30秒間隔という仕様自体への指摘ではない。

### LOW / P3: 保存索引の件数・合計・完了日時の矛盾を受理する

**場所:** [StorageScanner.swift:246](/Users/sodaiyamamoto/aibou/monitor/Sources/StorageScanner.swift:246)。

復元時のgraph検証は循環・親参照を拒否するが、完了日時の存在、scannedCountとnode数、totalLogicalBytesとroot値の一致は確認しない。破損・手動変更されたJSONが、完了した過去の走査結果として表示され得る。

**再現:** rootが1個、rootサイズ12B、完了日時なし、scannedCountと全体サイズが999,999のarchiveを用意。loadは例外を返さずsavedとして受理した。

**最小修正:** 通常writerが保証する完了日時・件数・合計の整合性を復元時にも検証する。可能な値はnodesから再計算する方法もある。正常な部分取得・権限不足の表現は排除しない。

**確度: 高。実行再現済み。** 通常scannerがこの矛盾を生成する不具合は確認していない。端末内の保存データが破損した場合の防御不足として低優先度とした。

## 追加検証が必要な懸念（WATCH）

- **スリープ復帰時の時計基準。** 世代失効後もqueue内の古い収集jobが実行され得る。wake後にそのjobが時計基準を進め、続くpreservingClock resetがその値を保持するとsleepGapが欠落する順序がある。コード上の経路を確認したが実スリープでの再現は未実施。収集開始前の世代検査を推奨する。
- **追加診断のMainActor負荷。** 固定対象では診断に必要な少数の指標を取り出すため、全process・追加計測行のObservationを1〜2秒ごとにMainActorで生成する。最大入力でのGUI遅延は未測定。必要な集計指標だけの診断入力を推奨する。開発途中の追加機能に対する設計上の指摘である。

管理者認証先の終了未検証、全件JSONの負荷、索引構築から保存登録までの終了窓、履歴復元のMainActor負荷、将来の複数consumerは既知WATCHとして維持する。

## 再現・検証

[再現コード](R4ReviewProbe.swift)と[出力](r4-findings-probe.log):

```text
cache_probe reads=1 cachedRowOlderThanStatus=true cachedRowOlderThanPanel=true
archive_probe status=saved completedAtMissing=true count=999999 nodes=1 total=999999 rootBytes=12
```

再現用archiveは専用一時フォルダへ生成し終了時に削除した。ユーザーの保存ファイル・起動中アプリは操作していない。

- 開始時22ファイル: 全テスト、最適化build、codesign strict、plist/privacy lint成功。[テスト](r4-tests.log)・[build](r4-build.log)・[bundle検証](r4-bundle-checks.log)
- 22:14固定対象: 既存全テスト成功（22:17:47 JST）。[テスト](r4-latest-tests.log)
- 22:14固定対象: 最適化warnings-as-errors build成功。[build](r4-latest-build.log)
- 同じ固定対象で生成したアプリ: codesign strict、元/バンドルplist/privacy全lint成功。[bundle検証](r4-latest-bundle-checks.log)

診断追加部分の専用テストはこの固定対象にまだ存在しない。既存全テスト成功を診断ルールの網羅検証として扱わない。管理者認証、実スリープ、外部機器の実着脱、巨大archiveの再測定、GUI操作は今回実施していない。
