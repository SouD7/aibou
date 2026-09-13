# R3修正 独立設計レビュー

2026-09-13。担当: `r3_fresh_architecture`。担当のread-only制約により、返却されたレビューを親エージェントが要約して保存した。

## 判定

**修正範囲はCLEAR、製品全体はWATCH。新規BLOCK・現行欠陥は確認されなかった。** 管理者認証先の終了確認は、今回の部分改善で解決したとは扱わない。

## 修正範囲の根拠

- Observationは基本監視状態、現在区間、保持値の取得区間、最終基本計測時刻を分離する。単独Engine取得もsnapshotとして区別する。[Observations.swift:136](/Users/sodaiyamamoto/aibou/monitor/Sources/Observations.swift:136)、[MonitorStore.swift:87](/Users/sodaiyamamoto/aibou/monitor/Sources/MonitorStore.swift:87)。状態遷移・追加値・Codableのテストと整合する。
- CPUは未取得をunavailable、取得済みで基準不足ならwaiting、差分成立ならderivedとし、失敗後はbaselineをクリアする。[CoreSampler.swift:159](/Users/sodaiyamamoto/aibou/monitor/Sources/CoreSampler.swift:159)、[CoreSampler.swift:472](/Users/sodaiyamamoto/aibou/monitor/Sources/CoreSampler.swift:472)。初回・成功・失敗・回復・空配列のfixtureで確認する。
- 保存treeはroot唯一性、ID一意性、path一致、親存在、全nodeのroot到達性を反復走査で検証する。[StorageScanner.swift:255](/Users/sodaiyamamoto/aibou/monitor/Sources/StorageScanner.swift:255)。期待計算量O(n)、再帰stackなし。循環・自己参照・追加root・欠損親・path不一致・2万段逆順chainのテストがある。
- 履歴復元もappendと同じ許可判定を使い、未知キーを排除し、許可されたコア/GPUキーを保持する。[History.swift:27](/Users/sodaiyamamoto/aibou/monitor/Sources/History.swift:27)。
- CommandRunnerはshutdownとlaunchを同じlock境界で調停し、受理済みrunを終了待機へ登録する。cancelのwakeを終了と誤認せず、猶予内で生存確認してSIGKILLへ進む。[AdditionalCollectors.swift:82](/Users/sodaiyamamoto/aibou/monitor/Sources/AdditionalCollectors.swift:82)、[AdditionalCollectors.swift:100](/Users/sodaiyamamoto/aibou/monitor/Sources/AdditionalCollectors.swift:100)。
- 直接task cleanupと保存は共通の最大2秒deadlineを使用し、MainActorを塞がない。[MonitorStore.swift:365](/Users/sodaiyamamoto/aibou/monitor/Sources/MonitorStore.swift:365)。SIGTERM無視・timeout/cancel競合・保存待機のfixtureと整合する。

## 維持するWATCH

1. 管理者認証先powermetricsの終了: osascript終了と別の境界であり、子の残留有無は不明。実機で認証成功・取消・timeout・アプリ終了を検証する必要がある。残留が実証され、終了保証が必要な場合に権限helper等を設計する。
2. 全件JSONと大規模RSS: nodes、索引、encode用Dataを全件保持する。既存の50万件測定は最大RSS約948.75 MB。今回の再測定ではない。上限拡張前にオンディスク索引や分割保存を検討する。
3. 索引構築中の保存登録前終了: UI用索引完成後に保存登録するため、その間の終了では新結果が保存されない。UIはまだ完了表示しておらず、旧atomic archiveが残る既知のbest-effort契約。強化時は保存登録をUI索引構築から分離する。
4. 複数consumerの収集所有: 現行Storeの専用queueは直列だが、直接Engine APIの非並行要件はコメント規約。独立した複数consumerを追加する前に単一producerの所有を強制する。

## 検証の範囲

[全テスト成功ログ](r3-fix-tests.log)と[22ファイルの指紋](r3-fix-source-sha256.json)を照合。最適化warnings-as-errors build、codesign strict、plist/privacy lintは親の実行結果を根拠とする。管理者認証、GUI再起動、実スリープ、巨大archiveの再測定は今回実施していない。
