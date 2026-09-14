# PR #6 独立レビュー

レビュー日: 2026-09-14（JST）

対象: [PR #6 — feat(monitor): separate diagnostic symptoms from cause candidates](https://github.com/SouD7/aibou/pull/6)

- Base: `8b3906234a2670d4ff10e627a2189ebb290dd3ba`
- Head: `03f3f9331f319239033edeeff59e6a701c9a4a02`
- 変更31ファイル、すべてmonitor内。専用worktreeのコミット済み差分をレビュー。
- 終盤にGitHubのhead/baseが変わっていないことを再確認。

## 判定

**COMMENT（改善推奨）**。CRITICAL/HIGHは0件、MEDIUM 1件、LOW 2件。設計上のBLOCKはない。

| 独立担当 | 最終判定 | 結果 |
| --- | --- | --- |
| `/root/r6_code_review` — コード・仕様・安全性 | COMMENT | 症状名からの原因検索漏れ、同名原因の識別、QAの絶対パスを指摘。 |
| `/root/r4_architecture_review` — 設計・反証 | WATCH | 症状・原因・観測・手動指定の境界は成立。同名原因の文脈と確認作業の共有範囲に改善点。検索の逆参照不足も確認。 |

2担当の報告を受領後、親担当が再現結果を照合して統合した。コード担当のCOMMENT、設計担当のWATCHから最終COMMENTとする。過去のPR #4の指摘はこのPRに再計上していない。

## 1. MEDIUM — 原因タブで新しい症状名を検索しても関連原因が出ない

対象: [DiagnosticSelection.swift:65](https://github.com/SouD7/aibou/blob/03f3f9331f319239033edeeff59e6a701c9a4a02/monitor/Sources/DiagnosticSelection.swift#L65)、[DiagnosticsView.swift:39](https://github.com/SouD7/aibou/blob/03f3f9331f319239033edeeff59e6a701c9a4a02/monitor/Sources/DiagnosticsView.swift#L39)

**発生条件:** 「自動判定」または「手動判定」で、症状カードに表示される新しい症状名を検索する。

原因検索は、原因名・分類・対処法と旧`DiagnosticCase.symptoms`だけを参照する。独立して定義した`DiagnosticSymptom.title/examples`を検索しない。一方、検索欄は全タブ共通で「症状・原因・対処法を検索」と案内している。

コード担当の固定headプローブを親担当も再実行し、次を確認した。searchは自動・手動両タブの検索結果を合わせた件数。

| 症状名 | 紐付いている原因 | 検索結果 |
| --- | ---: | ---: |
| Mac全体の操作が遅い | 16 | 0 |
| ファイルを保存できない・更新に失敗する | 3 | 0 |
| 本体が異常に熱くなる | 8 | 0 |

**影響:** 詳細からは原因へ到達できるが、原因タブで同じ症状名を探すと空になる。診断結果やチェック状態そのものを変更する問題ではない。

**最小修正:** 原因IDから関連症状への逆引きを作り、原因の検索文字列に新しい症状名と例文を含める。静的カタログなので事前に索引を生成できる。既存テストは原因名→症状の方向だけを確認しているため、症状名→原因の回帰テストを追加する。

- [再現プローブ](/Users/sodaiyamamoto/aibou/monitor/QA/pr6-search-probe.swift)
- [親担当の再現ログ](/Users/sodaiyamamoto/aibou/monitor/QA/pr6-search-probe.log)

確度: 高。実装に対する模擬入力で再現済み。

## 2. LOW — 同じ名前の原因候補を区別できない

対象: [DiagnosticSelection.swift:82](https://github.com/SouD7/aibou/blob/03f3f9331f319239033edeeff59e6a701c9a4a02/monitor/Sources/DiagnosticSelection.swift#L82)、[DiagnosticsView.swift:152](https://github.com/SouD7/aibou/blob/03f3f9331f319239033edeeff59e6a701c9a4a02/monitor/Sources/DiagnosticsView.swift#L152)

**発生条件:** 「手動判定」または「バッテリーの減りが早い・残量警告が出る」の詳細を開く。

元カタログの`battery-low`と`battery-critical`は、どちらも「通常の放電または充電機会不足」という原因を持つ。このPRはそれぞれを別IDのチェック付きカードへ展開するが、折り畳み時の表示とVoiceOverラベルには原因名と手動判定種別しかない。

**影響:** 見た目と読み上げが同じカードが2つ並び、チェック状態は独立する。どの条件に属する候補を操作しているのか分かりにくい。

**最小修正:** 元の条件名`cause.context.title`を副題とアクセシビリティラベルに併記する。意味上同じ原因を共有IDへ統合する選択肢もあるが、選択状態の意味を変えるため、表示だけを直す方が小さい。重複タイトルでも区別できる表示を確認する。

確度: 高。両担当がカタログと新しいカード生成・表示処理を照合して確認。

## 3. LOW — QA文書のアプリパスが特定のローカル環境に固定されている

対象: [DIAGNOSTICS_SELECTION_RESULTS.md:50](https://github.com/SouD7/aibou/blob/03f3f9331f319239033edeeff59e6a701c9a4a02/monitor/QA/DIAGNOSTICS_SELECTION_RESULTS.md#L50)、[SYMPTOMS_ONLY_FIX_RESULTS.md:25](https://github.com/SouD7/aibou/blob/03f3f9331f319239033edeeff59e6a701c9a4a02/monitor/QA/SYMPTOMS_ONLY_FIX_RESULTS.md#L25)

アプリの場所がローカルアカウント名を含む絶対パスで記載されており、別メンバーのcheckoutでは利用できない。認証情報の漏えいではない。

**修正案:** リポジトリにコミットする文書では`monitor/AIBOUMonitor.app`等の相対パスを使う。チャット上で現在のローカル成果物を開くリンクとは用途を分ける。

## 設計上の注意点 — 確認作業は原因ごとではなく元ケースで共有される

対象: [DiagnosticsView.swift:188](https://github.com/SouD7/aibou/blob/03f3f9331f319239033edeeff59e6a701c9a4a02/monitor/Sources/DiagnosticsView.swift#L188)

確認作業のチェックは`context.id + index`で保存される。そのため、同じ元ケースから作った複数の原因カードでは、1か所を変更すると同じ確認項目がすべて更新される。

同じ作業を一度だけ記録する設計として合理的で、状態破損や誤判定ではない。ただし原因カード内に配置されているので、原因ごとの独立記録にも見える。

**改善案:** 「このケースに共通する確認項目」と明示する。原因ごとにIDを変えるだけでは確認作業が重複するため推奨しない。判定はWATCH、非BLOCK。

## 問題がないことを確認した主な仕様

- 「すべて」は独立して定義した60症状。原因IDと症状IDは分離され、内部観測を症状カードへ自動変換しない。
- 113原因すべてに症状の詳細からアクセスできる。
- 5タブは症状3集合・原因2集合に分離される。
- 「今の候補」は原因チェック、「選択した症状」は症状の手動選択だけで抽出する。
- 自動チェックは観測可能な8条件のmatchedだけ。unknown/observingや古い値から自動でチェックしない。
- 手動true/falseと自動追従が別状態で保持され、「自動に戻す」とリセットが機能する。
- 同一IDの選択状態はMonitorStoreを介して一覧・詳細で共有される。
- 新規の外部I/O、権限要求、永続保存はなく、追加QA画像は合成fixture。
- 現行の60症状・113原因は静的かつ有界で、規模に起因する実用上の性能問題は確認していない。

## 今回の検証

| 検証 | 結果 |
| --- | --- |
| 全テスト | 固定headの非Appソースと全Testsをwarnings-as-errorsで新規コンパイル。ALL TESTS PASSED。[ログ](/Users/sodaiyamamoto/aibou/monitor/QA/pr6-review-tests.log) |
| 検索の再現 | 固定headの実装に対する独立プローブを親担当も再実行。上記3例すべて0件。 |
| 同梱アプリ | `codesign --verify --strict`成功。今回新しくアプリ全体をビルドしたという意味ではない。 |
| 対象照合 | 症状モデル・テストの記録SHA-256一致、差分のwhitespace検査成功、専用worktreeはclean。 |
| GitHub | 終盤にhead/baseを再取得し、変更なし。 |

実GUIの全クリック操作、VoiceOverでの操作試験、実アカウントでの認証や推論は未実施。読み上げ名の重複はソースのaccessibilityLabelから確認した。

この依頼ではレビューとローカルの報告書作成のみを実施した。製品コードの修正、コミット、プッシュ、GitHubへのレビュー投稿は行っていない。
