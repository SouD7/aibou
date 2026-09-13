# 最新版の独立再レビュー R6 — 2026-09-13

## 結論

**COMMENT（改善事項あり）。新規MEDIUM 2件、CRITICAL/HIGH/LOWは0件。** 前回修正した3件は再確認できた。今回の2件は、その修正の再発とは別の入力検証の不足。

| 独立担当 | 判定 |
|---|---|
| [コード担当](R6_CODE_REVIEW.md) | COMMENT。小さな入力fixtureで新規MEDIUM 2件を再現 |
| [設計担当](R6_ARCHITECTURE_REVIEW.md) | WATCH。前回修正3件CLEAR、設計BLOCKなし |
| 統合 | **COMMENT**。新規2件と既知WATCHを残す |

## 新規の確定指摘

### 1. MEDIUM / P2: ファイルを親に持つ保存索引を受け入れる

場所: [StorageScanner.swift:279](/Users/sodaiyamamoto/aibou/monitor/Sources/StorageScanner.swift:279)。

`validTree`は親IDが存在することと全ノードがrootへ到達することを検証するが、参照先の親がdirectoryかは検証しない。directoryのroot → file → fileという、通常のファイルシステムでは成立しない階層を含む保存データでも、件数・合計・完了日時などが整合していれば復元される。

コード担当がローカルの不正archive fixtureを読み込み、`archive_parent_kind=ACCEPTED status=saved nodes=3`を確認した。通常の走査がこの構造を生成するという指摘ではなく、破損・編集された保存入力を受け入れる検証不足。権限境界を越える問題ではない。

最小修正案: 親ID解決時に参照先の`kind == .directory`も必須とし、fileを親にしたfixtureを拒否する回帰テストを追加する。前回追加したroot種別・summary検証は正常に機能しており、今回はroot以外の親種別という別の条件。

### 2. MEDIUM / P2: PID不明のnettop行に直前の帰属が残る

場所: [AdditionalCollectors.swift:215](/Users/sodaiyamamoto/aibou/monitor/Sources/AdditionalCollectors.swift:215)、[AdditionalCollectors.swift:240](/Users/sodaiyamamoto/aibou/monitor/Sources/AdditionalCollectors.swift:240)。

`owner`と`processLabel`はPIDを解析できた時だけ更新される。このため、正常な`good.42`行の次に、接続行ではないが末尾の`.PID`を持たない`malformed-process`行が来ると、前のプロセスの親元を引き継ぎ、説明もそのプロセスの接続として表示する。

コード担当が数値列は正常なCSVで再現し、`nettop_malformed_owner=OWNER-42 note=good.42 の接続。計測区間の観測結果`を確認した。不完全な出力やOS依存の形式変更時に誤った帰属を表示する経路であり、現在の通常nettop出力で常時発生するという指摘ではない。

最小修正案: 接続行とプロセス行を分け、非接続行では必ず帰属状態を更新する。PID解析失敗時は`未特定`へ戻し、接続という説明を付けない。正常行の直後にPID欠落・不正行を置く回帰テストを追加する。

## 対象と方法

2026-09-13 23:38:46 JSTの最新版を固定した。Sources 12、Tests 9、scripts 3、plist/privacy 2、Markdown 5の計31ファイル。前回修正検証時からの内容変更はない。[取得時刻・SHA-256](r6-snapshot.json)、[確認したソースZIP](r6-reviewed-source.zip)。Gitの差分も確認したうえで、今回も固定した全体を再レビューした。

コード担当は新しいコンテキストの `r6_code_review`。設計担当は新規エージェント数の上限により、前回の独立担当 `r4_architecture_review` を再利用し、固定対象を読み直した。いずれも今回の統括・前回修正の実装担当とは別。コードと設計を独立して評価する。

## 検証

- 固定snapshotで実際の `bash test.sh` を実行し、全8 suiteが成功（23:41:12 JST）。[全テストログ](r6-tests.log)
- 同じsnapshotで実際の `bash run.sh --build` が成功。[ビルドログ](r6-build.log)
- 生成した隔離bundleの `codesign --verify --strict --verbose=2` が成功。元とbundle内のInfo.plist・PrivacyInfo.xcprivacyのlint、3スクリプトの構文検査も成功。[検証ログ](r6-bundle-checks.log)
- 診断catalogは70件、ID一意、文書に全IDあり。[catalog照合](r6-catalog-check.json)
- [対象ファイルの最終照合](r6-final-scope-check.json)で変更・未確認の追加Sources/Testsなし。

全テスト成功は既存テスト範囲の結果であり、未検証条件での不具合不存在を保証しない。独立担当の追加再現結果は最終判定に別途反映する。

コード担当は固定snapshotのCommon.swift・StorageScanner.swift・AdditionalCollectors.swiftと一時的な`@main` fixtureだけを最適化・warnings-as-errorsでcompileし、上記2出力を確認した。一時source・binary・archiveは担当が削除済みで、再現入力と結果は[コード報告](R6_CODE_REVIEW.md)に記録した。

## 設計評価と制約

[独立設計レビュー](R6_ARCHITECTURE_REVIEW.md): WATCH。前回修正3件はCLEAR、新規の確定不具合・BLOCKなし。

既知の検討事項は、スリープ前に予約した収集によるclock基準の更新、MainActor上の診断全量投影と履歴復元、最大50万件の全量JSON・索引、保存登録前の終了窓、管理者認証先の終了未確認、将来の複数consumerの収集所有。詳細ではMainActorの2経路を分け、計7項目として記録する。

本レビューではGUI再起動、実スリープ、管理者認証、巨大archiveの再測定を行っていない。製品のソース・テスト、起動中のアプリ、実ユーザー保存ファイルは変更せず、QA成果物だけを追加・更新した。
