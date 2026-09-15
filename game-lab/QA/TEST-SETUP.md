# Game Lab のネイティブ UI テスト

この構成は、`swiftc` でビルドする Game Lab と、Xcode がビルドする UI テストを分離します。アプリ本体を Xcode プロジェクトに移行する必要はありません。

## 構成

- `AIBOUGameLabUITests.xcodeproj`：UI testing bundle だけを含む共有スキーム。
- `UITests/GameLabUITests.swift`：実際のアクセシビリティ要素をクリックする XCTest。
- `ui-test.sh`：テスト runner のビルド、指定アプリの登録、UI テスト実行、結果保存。
- アプリの bundle ID：`local.aibou.gamelab`。
- runner の bundle ID：`local.aibou.gamelab.uitests.xctrunner`。

`XCUIApplication(bundleIdentifier:)` でビルド済みアプリを起動します。生成された `.xctestrun` では `UseUITargetAppProvidedByTests = true` を確認済みです。`TEST_HOST` や架空のアプリターゲットは指定していません。

## 実行

リポジトリのルートから、画面を操作せずテストコードをコンパイルするには：

```sh
./game-lab/ui-test.sh build
```

Game Lab をビルドした後、現在のデスクトップ上で UI テストを実行するには：

```sh
./game-lab/ui-test.sh test
```

アプリが既定の `game-lab/AIBOUGameLab.app` と異なる場所にある場合：

```sh
AIBOU_GAME_LAB_APP="/absolute/path/AIBOUGameLab.app" ./game-lab/ui-test.sh test
```

特定のシナリオだけ実行する例：

```sh
./game-lab/ui-test.sh test -only-testing:AIBOUGameLabUITests/GameLabUITests/testIncorrectGateDoesNotPassThenANDPasses
```

UI テストはアプリを起動・終了し、マウスを動かします。Computer Use による手動検証と同時には実行せず、デスクトップの操作を一方にまとめます。macOS がテスト runner の操作権限を求めた場合は、許可後に同じコマンドを再実行します。

## 検証すること

1. AND 課題を OR で組んだ場合、検証後に失敗が表示される。リセットして AND に組み直すと成功する。
2. 配線していない回路では全条件チェックと一手実行が無効で、成功扱いにもならない。
3. 入力変更・一手実行の後でも、リセットして正常な回路を作り直せる。
4. OR パーツをネイティブのドラッグ操作でスロットに配置できる。
5. OR 課題でリセットしても、AND 課題に戻らず OR のまま回路だけを作り直せる。
6. 任意の応用予想に誤答しても、説明を見て閉じ、次の実験へ進める。
7. 正解した回路と点灯状態を書き出し、リセット後に保存ファイルを再生すると成功状態とランプが復元される。開発パネル表示中もヘッダーとフッターの操作が見える。

`game.check` はアプリの通常の操作として四つの入力条件を検証します。テストコードから内部の正解判定や状態変更を呼び出す処理はありません。テスト終了時と、予想誤答・書き出し直後には、アプリウインドウのスクリーンショットを保存します。

## 結果と制約

- Xcode 26.6 で `build-for-testing` 成功、runner と `.xctestrun` の生成を確認済み。
- **2026-09-14、最終コードでネイティブ UI テスト 7 件すべて合格。実行 69.85 秒、失敗・スキップともに 0 件。** 実行結果は `QA/results/ui-20260914-180441-11557.xcresult`、ログは `QA/results/ui-final-layout-run.log`。
- 確認済みの画像 10 枚と manifest、集計 JSON は `QA/captures/ui-final-layout/`。予想誤答の説明全文、開発パネルの自動スクロール表示、開発パネル表示中もヘッダーとフッターが固定表示されることを目視確認済み。
- [開発パネルの自動表示](captures/ui-final-layout/developer-auto-scroll.png) / [予想誤答の説明](captures/ui-final-layout/prediction-wrong-answer.png) / [ファイル書き出し](captures/ui-final-layout/export-file-created.png) / [ドラッグ配置](captures/ui-final-layout/native-drag-or.png) / [保存ファイルから復元](captures/ui-final-layout/replay-restored.png)。
- 最終の全件合格 run は Xcode が動画を保持せず、画像のみを出力しました。調整中のドラッグ操作の録画は `QA/captures/ui-initial/3F3AE802-3D90-4815-9005-9676EA6E1FA1.mp4` にあります。この操作自体は成功し、当時のテストが macOS AX の `label` と `value` を取り違えたため失敗扱いになった記録です。
- macOS の SwiftUI 要素では、表示内容が AX の `label` と `value` のどちらに現れるかが異なります。成功・失敗は専用 identifier、ランプ・配置結果は両属性から期待する状態の文字列を検証します。空の文字列を成功扱いにはしません。
- Xcode 26.6 付属 XCTest / XCUIAutomation は macOS 14 以降向けのため、**UI runner の最低 OS は macOS 14**。アプリ本体の macOS 13 対応とは別です。
- Apple が署名した XCTest 同梱 framework を strip しない旨のビルド警告が出る場合があります。
- XCTest のスクリーンショットは状態確認用です。アニメーションの自然さ、色・余白・説明の伝わりやすさ、楽しさ、初見ユーザーの理解を単独で判定するものではありません。

## 公式資料

- [Apple — XCUIApplication.init(bundleIdentifier:)](https://developer.apple.com/documentation/xcuiautomation/xcuiapplication/init%28bundleidentifier%3A%29)：bundle ID を指定した起動。
- [Apple — Adding tests to your Xcode project](https://developer.apple.com/documentation/xcode/adding-tests-to-your-xcode-project)：UI テストターゲットと XCTest。
- [Apple — Technical Note TN2339](https://developer.apple.com/library/archive/technotes/tn2339/_index.html)：`build-for-testing` と `test-without-building`。
- [Apple — click(forDuration:thenDragTo:)](https://developer.apple.com/documentation/xcuiautomation/xcuielement/click%28forduration%3Athendragto%3A%29)：押し続けてから別の要素へドラッグする操作。
