# R5 設計担当の独立レビュー

担当: `r4_architecture_review`（R5対象で再レビュー）。返却本文から親が要約して保存。

**Architectural Status: WATCH。新規BLOCKなし。**

## 新規WATCH: 単独APIの継続性の説明

Observations.swift:156–160の既定stateはsnapshotで、MonitoringEngine.collectObservationsもこれを返す。Diagnostics.swift:64–70はrunning以外のingestで継続記録を消去する。README.md:15に、単独利用で必要なrunning入力、stable segmentの所有、snapshotでCPU継続判定が成立しないことが明記されていない。

新しいsnapshotを2秒ごとに20秒以上渡しても、瞬時判定6件は評価可能だがCPU系2件はobservingとなる。Storeはrunningとsegmentを供給するため**現行UIには影響しない**。既存テストもこのone-shot非連続を固定しており、確度は高。

まず文書でMonitorStore.diagnosticResultsを推奨し、snapshotの限界を明示する。独立consumerでも必要ならsessionがsegmentと開始停止を所有するAPIを追加する。snapshot自体の非連続guardを緩めない。

## 診断機能で整合している契約

- **鮮度と状態:** schema、収集状態、lastSampleAt、10秒以内、未来でないこと、指標のstatusと取得時刻を検証。Diagnostics.swift:129–165。
- **継続:** segment変更、6秒超の欠測、逆行、条件不成立・欠損でrunを作り直す。evaluateは経過を増やさず、採用された取得時刻で20秒を判定。Diagnostics.swift:66–119。
- **同一コア:** 各コアのrunを持ち、別コアへ移動した高負荷を合算しない。順位交代の回帰テストあり。Diagnostics.swift:71–106、DiagnosticTests.swift:63–73。
- **停止と再開:** pauseでrunをresetし、startは新segment、採用sampleだけがsampleSegmentを更新してingest。MonitorStore.swift:174–216。
- **画面の鮮度:** 2秒ごとに現在時刻で再評価するため、収集停滞時も古い値を現在の結果として保持し続けない。DiagnosticsView.swift:10–14。
- **手動確認:** manualは自動evidenceを持たず、症状と確認済みSetは診断入力と分離。チェック操作で原因の確度を上げない。Diagnostics.swift:93–100、MonitorStore.swift:59–60。
- **永続化:** 診断run・手動チェックはメモリ内だけ。終了保存groupへ新しい診断保存処理を追加していない。

## 維持する既知事項

R4の機器一覧cache時刻と保存summary整合性の2指摘は未修正。診断8件はdevices/hardware一覧を使用しないためcache時刻問題は自動診断へ直接波及しない。

次のWATCHを維持する。

- 失効したqueued sampleがwake後にclock baselineを更新する順序（実スリープ未再現）。
- 少数の診断指標のためにMainActorで全Observationを作り、表示中も2秒ごとに投影する負荷（最大入力性能未測定）。
- 管理者認証先powermetricsの終了未確認。
- 全件storage索引・JSON生成のメモリ負荷と、索引完成まで保存登録されない終了窓。
- MainActorでの履歴同期復元。
- 将来の複数consumerに対するstateful MonitoringEngineの所有境界。現行はprivate engine/serial queueの単一producer。

## 検証

親の独立module cacheでの全テスト成功を照合。診断TestsはTestMainへ接続済み。最終build・署名・lintは親が確認し[統合レビュー](CODE_REVIEW_R5_2026-09-13.md)へ記録。今回、GUI・実スリープ・管理者認証・巨大archive・ユーザーデータの操作は行っていない。
