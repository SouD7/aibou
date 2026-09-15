# Workshop UI 自動検証記録

2026-09-14、XCTest / XCUIAutomation、macOS 26.5.2。
旧自由実験7件＋新Workshop9件をコンパイルし、実機の公開UI操作で検証した。

**各シナリオの最終結果を集計すると、自動成功15件、未完遂1件。16件すべて自動成功とはしていない。**
全体実行後、原因を修正した範囲だけ再実行したため、成功証跡は複数の結果bundleに分かれる。

## 結果bundle

- **A**：[全16件の実行](results/ui-20260914-184252-15527.xcresult) — 12成功、4失敗。
- **B**：[起動手順等の修正後](results/ui-20260914-184651-15880.xcresult) — 旧未接続テストが成功。残り3件はデスクトップ/SpaceのAX取得で失敗。
- **C**：[最終3件の実行](results/ui-20260914-185200-16608.xcresult) — 予想・OR反例の2件成功。作品保持テスト1件は開始ボタン後のAX要素消失で未完遂。
- **D**：[作品保持の個別実行](results/ui-20260914-184843-16116.xcresult) — 完成→リセット→作品帳表示まで成功。その後、閉じるIDが親IDに上書きされている実装上の問題を検出。修正済み。

## シナリオ別の最終結果

| XCTest scenario | 結果 | 証跡 |
|---|---|---|
| GameLabUITests.testDisconnectedCircuitDoesNotPass | 成功 | B |
| GameLabUITests.testExportResetReplayRestoresCircuitAndLamp | 成功 | A |
| GameLabUITests.testIncorrectGateDoesNotPassThenANDPasses | 成功 | A |
| GameLabUITests.testIncorrectOptionalPredictionDoesNotBlockNextMission | 成功 | A |
| GameLabUITests.testNativeDragPlacesGateInSlot | 成功 | A |
| GameLabUITests.testResetAllowsFreshSolution | 成功 | A |
| GameLabUITests.testResetKeepsORMission | 成功 | A |
| WorkshopUITests.testCompanionSwitchChangesOnlyWhenRequested | 成功 | A |
| WorkshopUITests.testIntroductionRequiresStartAndUnknownOutputCannotBeTested | 成功 | A |
| WorkshopUITests.testNativeWireDragConnectsTheTwoATerminals | 成功 | A |
| WorkshopUITests.testRelaunchResumesSavedCircuitAndInputState | 成功 | A |
| WorkshopUITests.testStoppingVerificationAllowsEditingWithoutStaleSuccess | 成功 | A |
| WorkshopUITests.testUndoRestoresPreviousGateAndItsOutput | 成功 | A |
| WorkshopUITests.testWrongOptionalPredictionStillAllowsCompletedWork | 成功 | C |
| WorkshopUITests.testWrongORProducesCounterexampleAndCannotFinish | 成功 | C |
| WorkshopUITests.testRestartKeepsCompletedWorkAvailable | 未完遂 | C。作品表示までの動作はDで撮影済み |

任意予想の最終テストは、誤答の説明を見る→「回路で確かめる」→A1/B0/出力0を実際に確認→作品帳へ保存まで検証した。
OR反例の最終テストは、失敗を確認→「この条件で試す」→A0/B1/出力1まで検証した。
再開テストはテスト専用の保存先を指定し、プロセス終了・再起動後の入力と回路を確認した。

## 検出した問題と対応

- `accessibilityValue` の進行状態がXCTestから空になったため、読み上げ可能な日本語の状態をラベルにも含めた。
- 作品帳、反例、予想説明の親コンテナIDが子ボタンIDを上書きする問題を修正した。反例と予想の対象操作は修正後に成功。
- macOSは同じ確認ボタンをTouchBarとSheet双方に提供するため、テストの確認ボタンqueryをSheet配下へ絞った。
- シート表示の遷移中に背後のScrollViewを操作してしまうテストの問題を修正した。操作可能になるまで待ち、実際に操作できるScrollViewだけを対象にする。
- 起動時は終了完了・前面化・foreground状態を待ち、必要な場合に限りWindowメニューから当該ウィンドウを一度選ぶ。再起動リトライのループは追加していない。
- それでも共有デスクトップ上でAXのApplicationがDisabledとなりWindow/子要素が消える現象が残った。失敗時の録画は別アプリの全画面Spaceを映しており、通常のゲーム操作での不具合とは区別した。最終未完遂1件はこの状態で停止しており、合格扱いにしていない。

## 画像・診断

- [名前付き画像一覧](captures/workshop-final/README.md)
- [導入](captures/workshop-final/entrance.png)
- [接続した盤面](captures/workshop-final/connected-play.png)
- [作品完成](captures/workshop-final/completed.png)
- [予想の説明](captures/workshop-final/prediction-explained.png)
- [反例の実験](captures/workshop-final/counterexample.png)
- [作品保持・閉じるID修正前](captures/workshop-final/artifact-before-close-id-fix.png)
- [最終実行の診断と録画](captures/workshop-ui-final-check/manifest.json)

最終の作品帳操作、AIBOU Monitor統合、性能記録の確認は [WORKSHOP-VERIFICATION.md](WORKSHOP-VERIFICATION.md) を参照。

## 親エージェントによる補完確認

自動未完遂の作品保持は、修正後のmonitor統合ビルドでComputer Useにより補完確認した。ANDを4条件検証して作品帳へ保存し、やり直し確認を承認。新しい盤面が未接続・A0/B0になった後も作品帳に接続済みAND・A1/B1・4観察が残ることを確認。作品内Aを0へ変えてランプ消灯を確認し、`w.artifact.close`で正常に閉じた。作業盤面は未接続・A0/B0のまま保持された。

さらに最終の高さ調整後、monitor内の部品棚とundoが一画面に収まること、ANDの配置・配線・点灯、案内絵の拡大/縮小、CPUタブとの往復後の状態保持を実画面で確認した。自動成功件数は15件のままとし、この補完を自動合格には加算しない。
