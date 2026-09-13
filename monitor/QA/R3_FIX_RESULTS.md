# R3レビューへの改善結果

対象: [R3レビュー](CODE_REVIEW_R3_2026-09-13.md)。2026-09-13。

## 改善内容

| 指摘 | 対応 | 状態 |
|---|---|---|
| MEDIUM: Observationで基本監視の停止を判別できない | schema 2にcollection.state、現在の監視区間、保持値の取得区間、最終基本計測時刻を追加。追加計測の時刻・取得元statusは維持 | 修正済み |
| MEDIUM: CPU取得失敗が初回差分待ちになる | tick取得失敗・空配列をunavailable、初回・回復直後の基準不足をwaitingとして区別。tick readerを注入可能にした | 修正済み |
| MEDIUM: 管理者計測の子プロセス停止が未検証 | cancelでも直接taskの終了を待ち、必要なら1秒後にSIGKILL。取消要求、時間切れ、直接task終了確認を分離。アプリの最大2秒終了待機に直接task cleanupを含めた | 部分改善。管理者認証先の終了は未検証 |
| LOW: 保存ストレージに循環があると不完全なtreeを受理 | 唯一のroot、ID一意性、path/ID一致、親参照、全nodeのroot到達性を検証。反復処理で各nodeの訪問は最大2回 | 修正済み |
| WATCH: 履歴復元時に未知キーを保持 | 保存時と同じ集計項目の許可リストを復元時にも適用 | 修正済み |

主な変更: `Sources/Observations.swift`、`MonitorStore.swift`、`CoreSampler.swift`、`StorageScanner.swift`、`History.swift`、`AdditionalCollectors.swift`、`App.swift`、対応するTests、README。依存ライブラリ追加なし。

## 回帰検証

- 修正前の循環fixtureで `invalid graph accepted: disconnected cycle` を再現: [ログ](r3-fix-red.log)。
- CPU初回→正常差分→取得失敗→回復→正常差分、空tickを検証。
- Observationのrunning/paused/resume/stopped、停止中の単発追加値、単独snapshot、Codableを検証。
- ストレージの循環、自己参照、追加root、欠損親、path不一致、root親参照を拒否。逆順に並べた2万段の合成親子chainは復元成功。
- 履歴の未知キーを排除し、コア別キー・ドットを含む既存GPUキーを保持。
- テストバイナリ自身をSIGTERM無視fixtureとして起動し、120秒timeoutを待たず直接taskを終了。cancelledとdirectProcessExited、終了待機の登録・解除を確認。fixtureは5秒alarmで自己終了も確保。
- timeout猶予中にcancelが同じsemaphoreを起こしても、process終了と誤認せず強制終了へ進むことを検証。
- 管理者timeoutの表示が、直接認証コマンドの終了と認証先powermetricsの終了未確認を区別することを検証。

最終候補で次を確認した。

- `./monitor/test.sh`: **ALL TESTS PASSED**（2026-09-13 22:02:06 JST）。[ログ](r3-fix-tests.log)
- `./monitor/run.sh --build`: **成功**。macOS 13ターゲット、最適化、warnings-as-errors。[ログ](r3-fix-build.log)
- `codesign --verify --strict --verbose=2`: **成功**。
- 元ファイルとアプリ内のInfo.plist・PrivacyInfo.xcprivacy: **全lint成功**。
- 検証対象22ファイルの[SHA-256](r3-fix-source-sha256.json)を保存。

## 独立再レビュー

| 担当 | 判定 | 内容 |
|---|---|---|
| コード担当 | APPROVE | 新規指摘0件。管理者認証先の終了は未検証境界として残す |
| 設計担当 | WATCH | 今回の修正範囲はCLEAR、新規BLOCKなし。製品全体の既知制約を維持 |
| 統合判定 | **COMMENT** | 設計WATCHがあるため、無条件の全体承認とはしない |

[コードレビュー](R3_FIX_CODE_REVIEW.md)・[設計レビュー](R3_FIX_ARCHITECTURE_REVIEW.md)。前回の担当laneを再利用し、実装担当と分けて現行コードを再確認した。

## 残る制約

管理者権限の実機統合試験は行っていない。通常権限で確認したのは直接taskの停止だけであり、認証を越えた子プロセス終了の証明ではない。rootプロセスの残留自体も未確認。子孫すべての終了を保証するには、認証成功・取消・timeout・アプリ終了の実機検証を行い、必要に応じて権限helper等を別途設計する。

全件JSONの大規模メモリ負荷、ストレージ索引構築中の終了で保存登録に至らない窓、履歴復元のMainActor負荷、将来の複数consumerの収集所有境界は前回のWATCHを維持する。今回、巨大archiveの負荷測定やGUI再起動は行わない。起動中アプリの未保存走査とユーザーの既存保存索引は操作していない。

Observation schema 1の状態欠損をrunningと推定する互換復元は設けていない。新しいconsumerはschema 2を使用する。履歴・ストレージの保存schemaは変更していない。
