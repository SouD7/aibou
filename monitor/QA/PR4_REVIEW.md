# PR #4 追加機能の独立レビュー

レビュー日: 2026-09-14（JST）

対象: [PR #4 — feat(monitor): add Codex consultation and app usage hub](https://github.com/SouD7/aibou/pull/4)

- Base: `0981d840a812a1fbc04331a91e41226a4679ba67`
- Head: `7bcd45e0531f04d810d66dd378d596e0c6a20b27`
- 範囲: 変更52ファイル、すべて `monitor/` 内。相談機能、アプリランチャー、アプリ別使用量、既存収集への接続、テスト、文書、画像、同梱アプリ。
- レビュー対象はコミット済みの専用worktree。共有作業フォルダの未コミット変更や過去レビューの承認を、今回の正しさの根拠にはしていない。
- 終盤にGitHubのhead/baseを再取得し、対象コミットが変わっていないことを確認した。

## 結論

**COMMENT（改善推奨）**。CRITICAL/HIGH、設計上のBLOCKは確認していない。MEDIUM 2件、LOW 2件と、未再現の設計上の注意点2件を記録する。

| 独立担当 | 判定 | 担当内の指摘 |
| --- | --- | --- |
| `/root/r6_code_review` — コード・仕様・安全性 | COMMENT | MEDIUM: 認証取消と完了の競合。LOW: 実機アプリ一覧のQA画像。容量走査の制約を設計担当へ共有。 |
| `/root/r4_architecture_review` — 設計・反証 | WATCH | MEDIUM: MainActor上の帰属計算。LOW: 認証操作の重複。容量走査と再接続の所有範囲をWATCHとして記録。 |

2担当が独立に差分を確認した後、親担当が再現条件と重要度を検証して統合した。コード担当のCOMMENTと設計担当のWATCHから、最終判定をCOMMENTとする。レビューのみを実施し、製品コードの修正やGitHubへのレビュー投稿は行っていない。

## 1. MEDIUM — ログイン取消と認証完了が競合すると、画面の認証状態が更新されない

対象: [ConsultationModel.swift:124](https://github.com/SouD7/aibou/blob/7bcd45e0531f04d810d66dd378d596e0c6a20b27/monitor/Sources/ConsultationModel.swift#L124)、[通知処理:250](https://github.com/SouD7/aibou/blob/7bcd45e0531f04d810d66dd378d596e0c6a20b27/monitor/Sources/ConsultationModel.swift#L250)

**発生条件:** ブラウザでのChatGPT認証が完了するタイミングで「ログインを取消」を押す。

`cancelLogin()`はRPC応答を待つ前に`loginID`を消し、取消応答の内容を捨て、常に「ログインを取り消しました。」を表示する。CLI 0.145.0の生成schemaでは、取消応答の`status`は`canceled`または`notFound`。すでに認証処理が完了していた場合、`notFound`は取消成功を意味しない。

この間に成功通知が到着しても、消去済み`loginID`と一致せず無視される。さらに`account/updated(authMode: chatgpt)`も再取得を起こさないため、専用アカウントがログイン済みでもAIBOUは未ログイン表示を続ける。再接続で回復する。認証を迂回して送信する問題ではない。

**検証:** コード担当の模擬RPCに加え、親担当が「初期account=null → 取消中にChatGPT認証完了 → 成功通知・account更新通知 → cancel応答notFound」というfixtureで再確認した。実アカウントは使用していない。

```text
cancel-race serverSignedIn=true signedIn=false loginURL=false status=ログインを取り消しました。
```

- [再現用fixture](/Users/sodaiyamamoto/aibou/monitor/QA/pr4-login-cancel-probe.swift)
- [再現結果](/Users/sodaiyamamoto/aibou/monitor/QA/pr4-login-cancel-probe.log)

**修正案:** 取消応答を判定し、取消後、特に`notFound`時は`account/read`で状態を再確認する。ChatGPTへの`account/updated`も再確認につなげ、取得結果に応じた表示にする。取消と完了の競合、取消成功、失敗を回帰テストに追加する。現在の[ConsultationTests.swift:119](https://github.com/SouD7/aibou/blob/7bcd45e0531f04d810d66dd378d596e0c6a20b27/monitor/Tests/ConsultationTests.swift#L119)は通常の取消要求を中心に確認している。

確度: 高。

## 2. MEDIUM — アプリ詳細のプロセス帰属計算が画面処理を占有する

対象: [ApplicationDetailView.swift:56](https://github.com/SouD7/aibou/blob/7bcd45e0531f04d810d66dd378d596e0c6a20b27/monitor/Sources/ApplicationDetailView.swift#L56)、[ApplicationUsage.swift:9](https://github.com/SouD7/aibou/blob/7bcd45e0531f04d810d66dd378d596e0c6a20b27/monitor/Sources/ApplicationUsage.swift#L9)

**発生条件:** 多数のプロセス、特に深い親子関係が逆順に並ぶ入力で、アプリ詳細を表示する。

Viewは1秒周期の`TimelineView`内で`ApplicationProcessGroup.make`を同期実行する。処理は全プロセスのパスを解決し、子孫集合が確定するまで全リストを繰り返し走査するため、最悪O(P²)になる。Store更新によるView再評価でも計算され得る。

**検証:** 設計担当の計測を、親担当がPRの`make`実装本体を抽出した最適化Swiftプローブで追試した。実際の大量プロセス生成は行っていない。

| 合成入力 | 500プロセス | 1,000プロセス | 2,000プロセス |
| --- | ---: | ---: | ---: |
| 浅い構成、対象アプリ5プロセス | 0.006秒 | 0.011秒 | 0.021秒 |
| 逆順の深い親子鎖、全件が対象 | 0.056秒 | 0.216秒 | 0.838秒 |

このストレス条件では、毎回の計算がMainActorを長時間占有し、アプリ全体の操作が引っかかる。通常の浅い構成は軽く、一般的なMacで常時0.8秒停止すると主張するものではない。実機のプロセス数・順序・ファイルシステムによって結果は変わる。

- [再現用プローブ](/Users/sodaiyamamoto/aibou/monitor/QA/pr4-attribution-probe.swift)
- [親担当の計測結果](/Users/sodaiyamamoto/aibou/monitor/QA/pr4-attribution-probe.log)

**修正案:** 親PIDから子配列を作り、キューによるO(P+E)の走査へ変更する。プロセスサンプル更新時にバックグラウンドで帰属を一度計算し、画面は結果を参照する。時刻だけが変わる更新では、stale表示のみ再計算する。最適化の前後で帰属結果が同じことと、入力順序に依存しないことを確認する。

確度: 高。性能測定は合成入力での結果。

## 3. LOW — ログイン取消の応答前に、次の認証操作を開始できる

対象: [ConsultationModel.swift:124](https://github.com/SouD7/aibou/blob/7bcd45e0531f04d810d66dd378d596e0c6a20b27/monitor/Sources/ConsultationModel.swift#L124)、[ConsultationView.swift:39](https://github.com/SouD7/aibou/blob/7bcd45e0531f04d810d66dd378d596e0c6a20b27/monitor/Sources/ConsultationView.swift#L39)

**発生条件:** 「ログインを取消」を押した直後、取消RPC応答前に再ログインやログアウトを押す。

`cancelLogin()`は`loginURL/loginID`を消す一方、`connecting`を立てない。再ログインのボタンとmodelのguardが有効なため、旧cancelと新startを同時に進められる。旧cancelの完了表示が新しいログイン待機表示を上書きできる。CLI側の処理順序によって、さらにエラーとなる可能性がある。

**修正案:** 取消完了まで認証操作を処理中として所有し、他の認証操作を無効化する。最小変更では`connecting`を適切に管理する。認証状態を明示的なenumに整理する案もあるが、必須ではない。遅延cancel fixtureで重複要求と古い表示の上書きを検証する。

根拠は状態遷移の静的確認。実ブラウザでの連打試験は未実施。項目1とは同じ認証処理の修正で対応できるが、別の操作順序なので回帰条件を分ける。

## 4. LOW — QA画像に実機のアプリ一覧と起動状態が含まれている

対象: [LAUNCHER_RESULTS.md:15](https://github.com/SouD7/aibou/blob/7bcd45e0531f04d810d66dd378d596e0c6a20b27/monitor/QA/LAUNCHER_RESULTS.md#L15)、`monitor/QA/launcher-preview.png`

文書に「118個のアプリ」とあり、画像には実機のアプリ名と起動中表示が含まれることを目視確認した。リポジトリの閲覧者に実機環境が伝わる。

認証情報や個人パスは確認していない。ユーザー自身が元のアプリ一覧画像を提示し、変更のコミット・プッシュも依頼していることから、無許可の重大情報漏えいとは判定しない。

**改善案:** 公開用QA画像は合成データで描画したものへ置き換えるか、追跡対象から外す。履歴の書き換えは必須修正ではなく、公開範囲や削除要件がある場合に別途判断する。

## 設計上の注意点（未再現・非BLOCK）

### 容量走査の15秒制限は、ファイルシステム呼び出しを強制中断できない

[ApplicationStorage.swift:297](https://github.com/SouD7/aibou/blob/7bcd45e0531f04d810d66dd378d596e0c6a20b27/monitor/Sources/ApplicationStorage.swift#L297)の期限・取消判定は、同期のファイル列挙やメタデータ取得から制御が戻った時点で行われる。ネットワークボリューム等の呼び出しが停止した場合、[APPLICATIONS.md:28](https://github.com/SouD7/aibou/blob/7bcd45e0531f04d810d66dd378d596e0c6a20b27/monitor/APPLICATIONS.md#L28)の15秒を超える可能性がある。詳細を閉じてもその呼び出しは中断されず、再度開くと走査が重なり得る。

外部ファイルシステムの停止は安全な環境で再現していない。まず文書を「呼び出し間で確認する15秒の処理予算」と正確にし、走査の同時数を共有実行管理で制限する案がある。強制期限が必要なら子プロセス等の停止可能な境界を検討する。UIをバックグラウンド化している点は適切。

### 再接続時に旧App Serverの終了完了を待たない

[ConsultationModel.swift:63](https://github.com/SouD7/aibou/blob/7bcd45e0531f04d810d66dd378d596e0c6a20b27/monitor/Sources/ConsultationModel.swift#L63)は旧接続に停止要求を出した直後、同じ専用`CODEX_HOME`で新しい子プロセスを起動できる。終了完了の待機は主にアプリ終了時のcleanupに使われる。

旧プロセスの終了が遅い場合、短時間だけ同じ認証領域を複数プロセスで共有する。認証ファイルの破損等の実害は確認していない。必要なら終了確認またはタイムアウトまで再接続を処理中とする。

## 問題として数えなかった事項

- 関連ファイル容量は標準保存先から推定した候補で、全データ・専有量ではないことがUIと文書に明示されている。
- 外部ヘルパー、短命プロセス、共有サービスの帰属に制約があり、欠測を0に変換しない設計になっている。
- 選択したCLIを信頼する境界が明示され、任意の実行ファイル自体をAIBOUがOS sandboxで隔離するとは約束していない。
- 相談は許可した全体指標だけを添付し、確認画面の内容を送信する。プロセス名、ファイルパス、任意エラー文字列は自動添付しない。
- ChatGPT認証の強制、APIキー環境の除外、送信前account確認、ツール要求の拒否、thread/turn ID検証が実装されている。
- Launcherは選んだURLを`NSWorkspace`へ渡し、シェルコマンドへ展開しない。
- 追加ネットワーク収集は操作tokenで所有し、別操作を誤って取り消さない検証がある。
- 既存archive等の過去レビューの懸念を、このPRで新規導入された問題として再計上していない。

## 今回の検証

| 検証 | 結果・証拠 |
| --- | --- |
| PRのコミット固定 | GitHubのhead/baseと専用worktreeのHEADが一致。最後の確認でも更新なし。 |
| 全テスト | 全非Appソースと全Testsをwarnings-as-errorsで再コンパイルし、ALL TESTS PASSED。[ログ](/Users/sodaiyamamoto/aibou/monitor/QA/pr4-review-tests.log) |
| アプリ全体の型チェック | `Sources/*.swift`、App.swiftを含めwarnings-as-errorsで成功。終了コード0。[ログ](/Users/sodaiyamamoto/aibou/monitor/QA/pr4-review-typecheck.log) |
| 実CLI接続 | CLI 0.145.0、一時CODEX_HOMEでaccount=null、ChatGPT強制、shell/apps無効、model接続を確認。[ログ](/Users/sodaiyamamoto/aibou/monitor/QA/pr4-review-handshake.log) |
| 認証取消の競合 | 模擬RPCでserver側ログイン済み・UI未ログインを再現。上記fixture/log。 |
| 集計負荷 | 合成の浅い木・逆順の深い木で実装を計測。上記probe/log。 |
| 固定ソースのhash | PRに記録された37ファイルのSHA-256と一致。[ログ](/Users/sodaiyamamoto/aibou/monitor/QA/pr4-review-source-hashes.log) |
| 配布物・差分 | 同梱`.app`の`codesign --verify --strict`、`git diff --check`成功。対象worktreeはclean。 |

型チェック・テストは今回再実行した。同梱アプリの新規ビルドは今回行っておらず、署名検証とソースhashの一致を、新規ビルドの証明とは区別する。

実アカウントでのログイン・推論、GUIの全操作、すべてのインストール済みアプリの起動、停止した外部ボリュームの試験は未実施。CLI接続テストではログインや質問送信をしておらず、利用枠を消費していない。

## 再現コマンド

専用worktreeの`monitor`を作業ディレクトリにして、認証fixtureを実行する:

```bash
xcrun swiftc -parse-as-library -warnings-as-errors \
  -module-cache-path /tmp/aibou-consultation-module-cache \
  Sources/ConsultationModel.swift \
  /Users/sodaiyamamoto/aibou/monitor/QA/pr4-login-cancel-probe.swift \
  -o /tmp/aibou-pr4-login-cancel-probe
/tmp/aibou-pr4-login-cancel-probe
```

帰属計算のプローブ:

```bash
xcrun swift -O -module-cache-path /tmp/aibou-consultation-module-cache \
  -target arm64-apple-macosx13.0 \
  /Users/sodaiyamamoto/aibou/monitor/QA/pr4-attribution-probe.swift
```

帰属プローブはPRの`make`実装を抽出し、必要な型だけを定義したもの。認証プローブはPRの`ConsultationModel.swift`を直接コンパイルして模擬RPCを注入する。いずれも実アカウントやユーザーアプリを操作しない。
