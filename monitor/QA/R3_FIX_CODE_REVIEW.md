# R3修正 コードレビュー

実施日: 2026-09-13  
判定: **APPROVE**

## 集計

- CRITICAL: 0
- HIGH: 0
- MEDIUM: 0
- LOW: 0
- 未検証境界: 1（管理者認証先の子プロセス終了）

## 仕様・旧R3指摘との照合

旧R3の状態表現2件・保存検証1件と履歴復元WATCHは修正されている。管理者計測の停止は計画どおり部分改善であり、認証先の終了は引き続き未検証である。

- Observation schema 2は状態、現在区間、保持値の取得区間、最終基本計測時刻を持つ（`/Users/sodaiyamamoto/aibou/monitor/Sources/Observations.swift:136`、同`:149`）。Storeはrunning／paused／stoppedを投影し、採用した基本値にだけsample segmentを付ける（`/Users/sodaiyamamoto/aibou/monitor/Sources/MonitorStore.swift:88`、同`:198`）。停止中に完了した追加計測は個別のrecordedAt/statusを保持する。READMEのschema 2契約とも一致する（`/Users/sodaiyamamoto/aibou/monitor/README.md:79`）。
- CPU tickのnil・空配列はunavailable、成功後の基準不足はwaiting、差分成立後はderivedとなる。失敗時に基準をnilへ戻すため回復直後も正しくwaitingになる（`/Users/sodaiyamamoto/aibou/monitor/Sources/CoreSampler.swift:159`、同`:177`、同`:472`）。注入fixtureは初回、成功、失敗、回復、空配列を検証する（`/Users/sodaiyamamoto/aibou/monitor/Tests/CoreTests.swift:27`）。
- 保存ストレージは唯一のroot、ID一意性、path/ID一致、親存在、全nodeのroot到達性とcycle不在を反復処理で確認する（`/Users/sodaiyamamoto/aibou/monitor/Sources/StorageScanner.swift:255`、同`:265`）。cycle、自己参照、追加root、欠損親、path不一致、2万段逆順chainのfixtureがある（`/Users/sodaiyamamoto/aibou/monitor/Tests/StorageTests.swift:115`）。各nodeは定数回しか訪問せずO(n)。
- 履歴復元は完全修飾keyを分割し、appendと同じmetric allowlistを適用する（`/Users/sodaiyamamoto/aibou/monitor/Sources/History.swift:28`、同`:92`）。未知key、余分なdot、許可済みcore/GPU keyの回帰fixtureを確認した（`/Users/sodaiyamamoto/aibou/monitor/Tests/HistoryTests.swift:30`）。

## キャンセル・終了競合

`CommandRunner`は予約受理とprocess起動の境界をlockで直列化し、受理済みrunだけを`activeRuns`へ登録する（`/Users/sodaiyamamoto/aibou/monitor/Sources/AdditionalCollectors.swift:72`）。cancelのwakeとtermination handlerが同じsemaphoreをsignalしても、猶予中は`Process.isRunning`を再確認し、生存時はSIGKILLへ進む（同`:100`）。timeout猶予中の同時cancelをSIGTERM無視fixtureで再現するテストもあり、直接task終了を確認している（`/Users/sodaiyamamoto/aibou/monitor/Tests/AdditionalTests.swift:191`）。Storeの終了待機はshutdown後、network/powerの直接task cleanupと保存に同じ最大2秒deadlineを使う（`/Users/sodaiyamamoto/aibou/monitor/Sources/MonitorStore.swift:353`、同`:365`）。新規runがwait後に登録される窓は、shutdownによるpending無効化と同じlock境界で閉じている。

## 未検証境界

**管理者認証先の終了 — 実機未検証、既知制約。** 通常権限fixtureが証明するのは直接起動したtaskの停止だけで、管理者経路の直接taskは`osascript`、認証先の`powermetrics`は別である（`/Users/sodaiyamamoto/aibou/monitor/Sources/AdditionalCollectors.swift:248`、同`:268`）。コードと画面向けnoteは`directProcessExited`と認証先終了を明確に分け（同`:276`）、READMEと結果文書も終了保証をしていない（`/Users/sodaiyamamoto/aibou/monitor/README.md:51`、`/Users/sodaiyamamoto/aibou/monitor/QA/R3_FIX_RESULTS.md:29`）。root子プロセス残留は実証されていない。将来保証が必要なら、認証成功・取消・timeout・アプリ終了を管理者実機統合試験で確認する。

## 検証

- `/Users/sodaiyamamoto/aibou/monitor/QA/r3-fix-tests.log`: 2026-09-13 22:02:06 JST、`AIBOU Monitor: ALL TESTS PASSED`。
- 親検証で最適化・warnings-as-errors build、codesign strict、Info.plist／PrivacyInfo.xcprivacy lintに成功。対象22ファイルの指紋は`QA/r3-fix-source-sha256.json`。
- 専用LSP diagnostics toolはこのレビュー環境に提供されていないため、全Sourcesを対象にしたwarnings-as-errorsコンパイル結果を型・警告診断の根拠とした。
- 管理者認証、GUI再起動、ユーザー保存archiveの変更は実施していない。

旧R3の確定不具合に回帰はなく、R3_FIX_PLANの要求を満たす。管理者認証先の終了は明示された未検証境界であり、今回の「部分改善」契約に対する承認を妨げない。
