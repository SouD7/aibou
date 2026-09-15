# 学習・ゲーム単独パッケージの切り出し検証

検証日: 2026-09-15。環境: Apple Silicon / macOS 26.5.2 / Apple Swift 6.3.3。

## 対象と変更範囲

切り出し前の作業フォルダは、2026-09-15 13:00:30 JST のバックアップとして全53,021ファイルをSHA-256照合済み。学習専用ブランチは GitHub の main `a2e2a8b` を基点にし、追加対象を `game-lab/` に限定した。

- 学習・ゲームの内容、操作、保存形式・保存先、素材、音生成処理、アプリ識別子は維持。
- ラボのボタン・コールバック・引数転送だけを削除。教材本文にある「ラボ」への言及は、内容を変えないため保持。
- 以前利用していたアバター5ソース・5素材を変更せず `Vendor/AvatarMotion/` に同梱し、ビルド・描画スクリプトの参照先を変更。
- 説明書の単独起動手順とパッケージ内リンクを更新。
- UIテストに20体験の一時保存先を指定し、ユーザーの進捗から分離。全20ゲームの開始・退出確認を追加。授業テストはmacOSの公開する要素種別・識別子に合わせて検索条件だけを調整し、同じ操作と検証を維持。

`Sources/` 全75ファイルのうち56ファイルはバイト単位で一致。変更した19ファイルの全差分を別担当が確認し、ラボ接続の削除以外にゲーム動作を変える編集がないことを確認した。`Core` 27ファイル、`Art` 22ファイル、CoreTests 11ファイル、StoreChecks 2ファイル、`Info.plist`、`Package.swift`、音生成スクリプトは一致している。

- [切り出し前後のSHA-256](standalone-source-hashes.json)
- [製品ソースの変更差分](standalone-source-diff.patch)
- [同梱アバターのSHA-256](../Vendor/AvatarMotion/SHA256SUMS)

## 自動検証

| 検証 | 結果 |
|---|---|
| `./test.sh` | Core 163テスト成功 |
| `./scripts/verify-experience-stores.sh` | 保存・再開・作品保持・破損保存保全など17チェック成功 |
| `./run.sh --build` | 兄弟フォルダが存在しない隔離場所で最適化ビルド成功。Swift警告はエラーとして扱う |
| `codesign --verify --deep --strict AIBOUGameLab.app` | 成功 |
| `./scripts/render-experiences.sh <出力先> --stages 1` | 全20体験で課題1成功→保存→再読込→作品コピーの独立性を確認。80画面・4一覧画像を生成 |

ビルドは `game-lab/` だけをコピーした別ディレクトリで実行した。元の `avatar-motion/`、`monitor/`、`integrated/` はその場所には存在しない。

新しいアプリに含まれる画像・音など23リソースは、バックアップ中のアプリ内の同名ファイルと全て一致した。以前のアプリ内に残っていた未使用の3ファイル（`LobbyMotion/talking.png` と案内画像の原画・アルファ試作）は、元から現行ビルドスクリプトがコピーしないためクリーンビルドには含まれない。製品コードからこれらへの参照がないことを確認した。素材フォルダにある原画は保持している。

- [Coreテストログ](core-tests.log)
- [Storeチェックログ](store-checks.log)
- [単独ビルドログ](standalone-build.log)
- [アプリ内リソースの比較](resource-comparison.json)
- [20体験の保存・描画結果](standalone-render-manifest.json)
- [20体験の代表画面](standalone-twenty-experiences.png)

描画検証は非表示ウィンドウで本番のSwiftUI画面とモデルを使用し、一時保存先で実Storeを検証する。音声の聞こえ方やマウス操作の確認とは区別する。代表画面一覧を目視し、素材の欠落や全体レイアウトの崩れがないことを確認した。

## 検証範囲の注意

旧UIテストには、19体験を準備中と期待するものや、新20体験の入口から旧回路画面へ進むことを期待するものが残っている。これは切り出し前からの不一致であり、それに合わせてゲームを変更していない。今回の実画面テストでは、全20ゲームの起動・ラボ導線の不在・元の展示室への退出、縮小ウィンドウでの入口操作、ロビーの瞬き、音声停止、旧回路工房の保存からの再開が成功した。

授業テストの初回実行は、入口がButtonではなくOtherとして公開されていることと、活動内のボタンに親の `lesson.activity` 識別子が付くことにより停止した。結果バンドルのアクセシビリティ情報で確認し、同じ操作を要素識別子または表示ラベルで選択するテストへ修正した。製品ソースは変更していない。

この検証は本環境におけるソフトウェアの確認であり、全OS版での動作や初心者の学習効果の実証ではない。ビルドは従来通りローカル用のad-hoc署名を使用する。


## 実画面テストの最終結果

対象6件は最終実行で全て成功（最初の実行で5件成功、授業テストの検索条件修正後に残る1件を再実行して成功）。製品の再修正は行っていない。

| 対象 | 結果 |
|---|---|
| 全20ゲームを起動し、ラボ導線がないことを確認して正しい展示室へ戻る | 成功 |
| 小さいウィンドウで全展示室・マップの入口を操作する | 成功 |
| 女の子から授業を開き、全20テーマの実験・問い・発見保存を実行する | 成功。保存JSONの完了IDも全20件一致 |
| ロビーの停止・再生・瞬きと画面遷移 | 成功 |
| マップを開くと案内音声が停止する | 成功 |
| 従来の回路工房を終了・再起動し、回路と入力・点灯状態を復元する | 成功 |

- [各テストの最終結果と実行履歴](standalone-ui-results.json)
- [最初の選択6件のログ（授業の要素検索1件失敗を含む）](standalone-ui-initial.log)
- [授業テスト再実行の成功ログ](standalone-ui-lessons.log)

同じ対象を再実行する場合は、`game-lab/` 内でビルド後に実行する。macOSがUIテスト用の認証を求める場合は、Macの利用者が対応する。

```sh
./run.sh --build
./ui-test.sh test \
  -only-testing:AIBOUGameLabUITests/ExhibitionUITests/testAllTwentyGamesStartAndReturnToTheirRoomWithoutLabControls \
  -only-testing:AIBOUGameLabUITests/ExhibitionUITests/testCompactWindowKeepsAllDoorsAndMapEntrancesOperable \
  -only-testing:AIBOUGameLabUITests/ExhibitionUITests/testGirlOpensLessonsAndAllTwentyExperimentsComplete \
  -only-testing:AIBOUGameLabUITests/ExhibitionUITests/testLobbyAnimationPauseAndNavigation \
  -only-testing:AIBOUGameLabUITests/ExhibitionUITests/testLobbyNarrationEndsWhenOpeningMap \
  -only-testing:AIBOUGameLabUITests/WorkshopUITests/testRelaunchResumesSavedCircuitAndInputState
```
