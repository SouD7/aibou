# 再レビュー修正結果 — 2026-09-13

> この文書は7件の修正確認です。その後の全体レビューは[現状レビュー（R3）](CODE_REVIEW_R3_2026-09-13.md)を参照してください。

対象：[2026-09-13再レビュー](CODE_REVIEW_2026-09-13.md)のHIGH 1件・MEDIUM 6件。

## 結果

**7件を修正し、最終の全テスト・最適化ビルドに成功。**

- コード担当の独立再レビュー：**APPROVE**。7件すべて解消、新たな指摘0件。担当側でも全テストとwarnings-as-errors型検査を独立実行して成功。
- 設計担当の独立再レビュー：修正対象7件はCLEAR、新規BLOCKなし。製品全体は既知の性能・拡張課題が残るためWATCH。
- 統合判定：**COMMENT**（修正対象は解消。製品全体の既知WATCHを継続追跡）。
- ソースは最終テスト後から変更していない。[SHA-256](r2-source-sha256.json)
- 既存の保存結果を変更する操作・外部送信・新しい外部依存の追加は行っていない。

## 7件の対応

| 指摘 | 変更 | 回帰テスト |
|---|---|---|
| 1. ディスク集合変更による偽I/O速度 | IORegistry entry ID別にカウンタと取得の完全性を保持。前後に共通するデバイスだけを差分化。追加・削除・一時欠損・リセットは部分取得。継続して読めないentryも完全取得と見せない | 追加・削除・全欠損・再出現・個別リセット・安定した不完全集合・初回。新規デバイスの累積値を速度へ混ぜないことを確認 |
| 2. プロセス列挙失敗を実測0件にする | 正常空集合・失敗・個別PIDの部分取得を分離。失敗時は件数・スレッド数をnil／取得失敗とする | 負値、件数見積もりと本取得の0＋errno、古いerrno、正常0件、個別PID失敗 |
| 3. 観測APIの計測区間欠落 | ProcessSample.measurementIntervalを追加し、数値画面とObservationへ実経過時間を伝播。失敗時は最後の成功基準を維持するため、回復後はその長い時間窓を示す | 初回、2.375秒fixture、直接Observation、Store経由、成功→失敗→成功。プロセスの時間窓とホストの直近区間を混同しないことを確認 |
| 4. 外部機器IDの衝突 | 表示属性から作るIDを廃止し、IORegistryEntryGetRegistryEntryIDの値を保持。シリアル番号は使わない | 全属性が欠損した2台が別IDのまま残る。完全な一覧でのみ接続・切断イベントを生成 |
| 5. UPSを内蔵電池に分類 | 電源種をkIOPSInternalBatteryTypeで厳密に選択 | UPSのみ、UPSが先・内蔵電池が後の一覧、表示残量の確認 |
| 6. powermetrics解析上限を隠す | 12,000末端値・深さ15で未読部分ができたことを保持。全タブに部分取得と理由を表示。取得済みraw値は保つ | 上限ちょうど、1件超過、対象値が上限の前／後、深い対象key。未読を非対応と断定しない |
| 7. 機器なしとAPI失敗の混同 | DeviceSampler.Acquisitionでsuccess／partial／failureを保持。電源・外部機器・熱センサー・ディスプレイのレジストリ・ハードウェア取得に反映 | 正常空集合、API失敗、利用可能な部分値、失敗のキャッシュ。失敗・部分一覧を挟んでも偽の接続／切断を出さない |

プロセス列挙については、Appleの[libproc実装](https://github.com/apple-oss-distributions/xnu/blob/main/libsyscall/wrappers/libproc/libproc.c)に、内部の失敗を0へ変換してerrnoを保持する経路があることを確認した。このため負の戻り値だけでは判定せず、各呼び出し直前にerrnoをクリアして結果と組み合わせて判定する。コードのコピーは行っていない。

## 主な変更ファイル

- [CoreSampler.swift](../Sources/CoreSampler.swift)：ディスク識別・差分、列挙結果、成功基準と実計測区間。
- [DeviceSampler.swift](../Sources/DeviceSampler.swift)：機器固有ID、電源種別、取得状態と注入可能な取得元。
- [Common.swift](../Sources/Common.swift)、[Observations.swift](../Sources/Observations.swift)：プロセスの時間窓を保持・公開。
- [AdditionalCollectors.swift](../Sources/AdditionalCollectors.swift)：解析上限の明示。
- [MonitorStore.swift](../Sources/MonitorStore.swift)：完全な機器一覧だけでイベント基準を更新。
- [App.swift](../Sources/App.swift)、README：停止操作を「基本監視を停止」と明示。開始済みの単発電力計測は完了し得ることを説明。
- TestsのCore・Device・Observation・Additional・Store：上記の回帰fixture。
- [Probe.swift](Probe.swift)：実プロセス速度に正の計測区間があることを検証。[ArchiveScaleProbe.swift](ArchiveScaleProbe.swift)：保存・復元・索引を通す再現可能な合成負荷測定。

## 検証

- 最終 `./monitor/test.sh`：**ALL TESTS PASSED**（16:24:09 JST）。[ログ](r2-tests.log)
- 最終 `./monitor/run.sh --build`：**成功**。最適化・warnings-as-errors・macOS 13ターゲット。[ログ](r2-build.log)
- `codesign --verify --strict`、Info.plist／PrivacyInfo.xcprivacyのlint：成功。
- powermetrics上限テストは修正前に失敗し、修正後に成功することを確認。[修正前ログ](r2-regression-red.log)
- 実機プローブ：Apple M1 MacBook Air／macOS 26.6.2。340〜342プロセス。初回395ms、その後59〜70msで収集。2回目以降、1,014〜1,026個のCPU・I/O速度すべてに正の実計測区間があった。単発nettopは188行取得。[個人名・パス・接続先を記録しない出力](r2-live-probe.json)

実ディスクの着脱、UPS実機、OS障害の発生、管理者認証成功、他機種の動作は今回未試験。該当分岐は注入fixtureと静的レビューで検証した。

現在開いている旧版モニタは、利用者の未保存の中断スキャン結果を保持していたため終了していない。新しいアプリ本体はビルド済みだが、実行中の画面への反映には再起動が必要。今回の修正版GUIの新規操作確認は行っていない。

## 保存・復元まで含む負荷測定

[測定コード](ArchiveScaleProbe.swift)と[結果](r2-archive-scale.log)。一時ディレクトリ内だけで実行し、終了後にfixtureを削除。実際の保存関数、StorageScanner.load、StorageTreeIndexを使用した。元のスナップショットも保持した状態で復元する一連のプロセスを測定している。

| ノード数 | JSON容量 | 保存 | 復元・検証 | 索引構築 | プローブ最大RSS |
|---:|---:|---:|---:|---:|---:|
| 100,000 | 22.47 MB | 1.08秒 | 1.70秒 | 0.19秒 | 258.98 MB |
| 500,000 | 113.67 MB | 4.26秒 | 9.16秒 | 1.19秒 | 948.75 MB |

MBは10進表記。単一Mac・各1回の測定で、ほかの処理も動いている。GUI全体のRAMや最悪値を保証するものではない。ノード上限付近の検証であり、256 MiBのファイル容量上限そのものや、長いパス・大量タグの最悪条件を網羅してはいない。直接fixtureを作っているため、通常スキャンの128 MiBメタデータ見積もり制限は経由しない。

再現（monitorディレクトリ、bash）：

```bash
sources=()
for source in Sources/*.swift; do
  if [[ "$source" != "Sources/App.swift" ]]; then sources+=("$source"); fi
done
xcrun swiftc -O -warnings-as-errors -parse-as-library -swift-version 5 \
  -module-cache-path "$PWD/.build/module-cache" -target "$(uname -m)-apple-macosx13.0" \
  "${sources[@]}" QA/ArchiveScaleProbe.swift -o .build/ArchiveScaleProbe
.build/ArchiveScaleProbe 100000
.build/ArchiveScaleProbe 500000
```

## 残るWATCH

- **大規模アーカイブは軽量とは言えない。** 50万件の保存・復元で約949 MBのピークを観測。既存上限を維持する。全件JSON方式を拡張する前にディスク上でページ単位に扱う索引などが必要。
- **履歴復元・グラフ系列のMainActor処理**と、**将来の複数consumerへの配信境界**は今回変更していない。現行の直列監視を前提とし、拡張前に非同期復元・キャッシュ・単一producerの所有を検討する。
- **停止と保存**は既存方針を維持。ファイルI/Oの停止は協調的、終了時の保存待機は最大2秒。大きい保存が間に合わない場合は以前のatomic保存結果が残る。

これらは修正した7件とは分けて追跡する。修正対象に新たな設計BLOCKはないが、製品全体の性能や全機種対応を保証する判定ではない。
