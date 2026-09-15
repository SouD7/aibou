# 女の子から授業へ：実装と検証記録

確認日：2026年9月15日。

## 実装した範囲

- ロビーの女の子の輪郭に沿うクリック範囲。ホバー時の案内と、全画面共通の「授業」入口。
- 5分野・20授業のノート。「見つける → 試してみる → 考える → つなげる」。
- 全20テーマの操作模型、条件を示した3択、誤答の説明、参考資料、自分のPCへの接続。
- 歓迎・説明・発見の女の子の静止差分3枚。授業内の身体の揺れ・口パクなし。ロビーの既存の瞬きを保持。
- 任意の日本語読み上げ。段階変更、別授業、画面を閉じる操作で停止。
- 実験操作と正答を経て発見済みにする独立した保存。再起動後は完了と前の授業を復元し、自動開始しない。
- 統合アプリでは分かりやすいラボへ移動する。数値一覧の開発者画面へは接続しない。

本編ゲームの提供状況は既存の回路のみ。ほか19テーマの授業と模型は利用でき、ミニゲーム本編は準備中と表示する。

## 合格した確認

| 確認 | 結果 |
|---|---|
| 単独ゲームアプリ、統合モニターアプリのビルド | 両方成功。Swift 5 / macOS 13対象、警告をエラーとして扱うビルド |
| 両アプリの署名検証 | `codesign --verify --deep --strict` 成功 |
| Coreテスト | 77件、失敗0。教材ID・出典・選択肢・保存・進行を含む。`lesson-core-tests.log` |
| 実際のLessonStoreの保存と復旧 | 43項目合格。破損/将来版原本の退避、保存不能時の継続、再試行を含む。`LESSON-STORE-VERIFICATION.md` |
| 生成した人物素材の切り抜き | 本番クロマキー処理を適用し、緑残りやシアン衣装の欠けを目視確認。`output/lessons-art/` |
| 画面操作での部分確認 | ロビーの女の子からノートを開く、5分野の選択、メモリ授業の導入までComputer Useで確認 |
| 全体画面の描画 | 本番Viewを1600×900で125枚描画。5ライブラリ＋20授業の各段階・正答/誤答。`captures/lessons-full/manifest.json` |

描画画像は画面から独立したImageRendererによるもの。実際のボタンクリックや音声再生を通したテストではない。長い台詞の髪への重なりは導入文の長さと人物位置を調整し、保存表示の背景色も改善した。

## 残る実画面の確認

Macがロックされたため、追加した3つのUIテストは実行開始前に自動操作モードの初期化がタイムアウトした。アプリ内のテスト失敗ではなく、3件とも未実行として扱う。ユーザーへロック解除を依頼済み。

- 女の子から開き、全20授業で実験→正答→発見を保存し、全件の入口へ戻れること。
- 誤答→答え直し、再起動での発見保持、準備中展示への正しい移動。
- 授業の開閉で、展示室と作業中の回路を保つこと。
- 追加の目視：小さいウィンドウ、ホバー範囲、任意音声と参考資料の開閉、統合先ラボへの移動。

実行ログ：`lesson-ui-tests.log`。
初期化タイムアウトの結果：`results/ui-20260915-041822-43886.xcresult`。

解除後の再開コマンド：

```sh
./game-lab/ui-test.sh test \
  -only-testing:AIBOUGameLabUITests/ExhibitionUITests/testGirlOpensLessonsAndAllTwentyExperimentsComplete \
  -only-testing:AIBOUGameLabUITests/ExhibitionUITests/testLessonWrongAnswerRetryPersistenceAndExhibitReturn \
  -only-testing:AIBOUGameLabUITests/ExhibitionUITests/testLessonsPreserveWorkingCircuitAndRoom
```

これらのUIテストは専用の一時保存先を使う。既存の回路・作品・授業の実データはテスト用fixtureにしない。

## 根拠と限界

教材の一次資料は `research/lessons/curriculum.md`、着想源からの選定理由は `research/lessons/experience-design.md`。説明・実験・確認問題の内容照合は実施済み。画面やプログラムの検証は、初心者の楽しさや学習効果を実証するものではない。

## 2026-09-15 自由な授業選択の修正

- 授業の右上に「授業一覧（全20テーマ）」を追加。段階や正答状況に関係なく一覧へ戻れる。
- 授業表示中もアプリ上部のナビゲーションを操作でき、「授業」を押すと必ず一覧を開く。
- 一覧に、任意順で選び、途中でも切り替えられることを明記。
- Computer Useの実アプリ操作で、E→D→C→B→Aを中心に全20テーマを開き、実験未操作・授業未完了の状態から別テーマへ選び直せることを確認。
- 単独・統合アプリを再ビルド済み。
- 追加したXCTest `testAllLessonsCanBeChosenInAnyOrderBeforeCompleting` は初回の授業入口クリック後に一覧を検出できず失敗したため、合格とは扱わない。上記20件はComputer Useでの確認結果。ログは `lesson-free-navigation-ui.log`。
