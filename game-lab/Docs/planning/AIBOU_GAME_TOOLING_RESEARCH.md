# aibou：ゲームを実際に操作し、品質を高めるためのツール調査

調査日：2026-09-14  
対象：参考ゲームの体験調査から、自作ミニゲームの実装・プレイ・改善まで。  
方法：公式資料、現在のツール仕様、ローカル開発環境を確認し、ブラウザと既存Macアプリで小さな操作試験を実施した。推奨はaibou向けの判断であり、ツール間の成功率・速度の比較実験は行っていない。

## 推奨する構成

**現在のSwift製aibouを基準にすると、Computer Use ＋ Xcodeのテスト・性能計測 ＋ 録画 ＋ ゲーム自身の再現機能が第一候補になる。** Web実装を選ぶ場合は、Playwright Testを検証の中心にする。

「AIが画面を見て遊べること」と「同じ条件で正しさを確かめられること」を両方用意する。aibouは遊びを通してハードウェアを理解するアプリなので、操作・見た目・性能に加え、ゲーム内の因果関係と学習結果まで確認する必要がある。

| 役割 | 現行Macアプリを伸ばす場合 | Webでゲームを作る場合 |
|---|---|---|
| AIが画面を見て遊ぶ | 現在のComputer Use | 現在の内蔵Browser / Computer Use |
| 正解・失敗・再挑戦を繰り返し検証する | Swiftのロジックテスト＋XCTest / XCUIAutomation | モデルのテスト＋Playwright Test |
| 同じ問題を再現し、値を確かめる | 自作のreset・状態取得・step・replay | 同左。必要ならWebMCP等で接続 |
| 映像・音・演出を見返す | OBS Studio＋FFmpeg | Playwrightの動画＋必要に応じてOBS |
| 滑らかさ・負荷の原因を調べる | Instruments。Metal描画ならMetal HUDも候補 | Chrome DevTools。AIからの調査にはDevTools MCPも候補 |
| 初心者が学べて楽しいか確かめる | 初見プレイの観察＋説明・予想の課題 | 同左 |

まず整えるべきものは、**ゲームを作って、私が操作し、不具合を再現し、修正結果を比較できる一巡の開発環境**である。

## 現在の環境で確認できたこと

### 小さな実操作試験

| 対象 | 実施した操作 | 確認できた範囲 |
|---|---|---|
| NandGame / 内蔵ブラウザ | 説明を閉じる→リレーをツールボックスから盤面へドラッグ→再観測 | ボタン操作、盤面の画像取得、部品配置が成功。チュートリアルが配線操作の段階へ進んだ |
| 既存AIBOU Monitor / macOS | アプリ取得→CPUからメモリへ切替→画像・UI情報取得→CPUへ戻す | 現在のComputer Useで、実際のSwiftUIアプリを操作・観測できた |

これは限定的な接続・入力確認である。NandGameの配線・クリア、任意のSteamゲームの操作、素早い同時入力、連続録画、音の評価まで成功したという結果ではない。NandGameの調査用タブは閉じた。

### 開発ツールの確認

- Xcode **26.6**、`xcodebuild`、`swift`、`xctrace`の存在を確認した。
- Node.js / npmの実行パスを確認した。
- FFmpeg **8.1.2**を確認した。
- `peekaboo`は現在のPATHには見つからなかった。
- Playwright Test、専用MCP、OBSの導入・接続試験は実施していない。
- 現在のmonitorはSwiftUI/AppKitとシェルによるビルド。ゲーム用のUIテストtargetや検証窓口は、これから整備する対象である。[既存実装の説明](https://github.com/SouD7/aibou/blob/0981d84/monitor/README.md)

したがって、**Computer Useを新たに探して導入する作業から始める必要はない**。この環境では、ブラウザ・Macアプリ双方の基本操作を実測できている。

## ツール候補の比較

### 1. 現在のComputer Use / 内蔵Browser：最初に使う

参考作品を遊び、試作品の「何を押すかわかるか」「配線をつかめるか」「失敗の理由が見えるか」を確認する入口。公式にもブラウザのクリック・入力・画面確認と、MacアプリのGUI検証が案内されている。[Browser公式](https://learn.chatgpt.com/docs/browser)、[Computer Use公式](https://learn.chatgpt.com/docs/computer-use)

このセッションのAPIでは、画像、アクセシビリティ情報、クリック、キー入力、始点と終点を指定したドラッグを利用できる。ブラウザには要素名による操作やDOMの観測もある。ただし、**公開されているAPIに長押し時間・任意のkeyDown/keyUp・ゲームパッド・フレーム同期入力は確認できない**。リアルタイムの反射操作が必要なゲームは、対象ごとの入力試験が必要になる。

また、現在のブラウザ操作APIにPlaywright形式の操作が含まれることと、Playwright Testの画像比較・trace・動画・時計制御が一式使えることは別である。

### 2. XCTest / XCUIAutomation ＋ Accessibility Inspector：Mac版の反復検証

自作aibouの開始、部品操作、成功、失敗、再挑戦を、変更のたびに繰り返し確認する。XCTestはアサーションと性能テストを持ち、XCUIAutomationでUIを操作できる。画像をテスト結果に添付することもできる。[XCTest](https://developer.apple.com/documentation/xctest)、[XCUIScreenshot](https://developer.apple.com/documentation/xcuiautomation/xcuiscreenshot)

Accessibility Inspectorでは、ボタン名や状態が適切に公開されているかを確認する。SpriteKit等で独自に描いた部品は、必要な意味情報・キーボード操作をアプリ側で補う。これはAI操作だけでなく、利用者の操作可能性にも関わる。[Accessibility Inspector](https://developer.apple.com/documentation/accessibility/accessibility-inspector)

**採用判断：現行Mac構成を続けるなら優先。** 現在のビルドにテストtargetを整える作業が必要。XCTestの画像取得だけで画像差分の運用まで完成するわけではなく、基準画像と比較方法は別途決める。

### 3. Instruments / Metal Performance HUD：滑らかさと負荷の検証

InstrumentsでCPU時間、メモリの増加、処理が詰まる場面を調べる。Metalを使う描画では、Metal HUDもFPS・フレーム間隔等を調べる候補になる。[Appleの性能改善ガイド](https://developer.apple.com/documentation/xcode/improving-your-app-s-performance/)、[Metal HUD公式解説](https://developer.apple.com/videos/play/tech-talks/110339/)

**採用判断：Mac版では優先。** aibouのアクティビティモニタ部分は基本2秒・詳細1秒間隔の観測なので、それだけでは一瞬のフレーム落ちを説明できない。設定上のディスプレイHzと、ゲームが実際に描画するFPSも分けて扱う。[現在の観測仕様](https://github.com/SouD7/aibou/blob/0981d84/monitor/README.md)

平均FPSだけでなく、操作直後の遅れ、重いフレーム、繰り返しプレイ後のメモリ、ゲームを閉じた後の負荷を確認する。録画あり・なしの条件も記録する。

### 4. OBS Studio ＋ FFmpeg：体験を記録して比較する

OBSはMacの対象ウィンドウやアプリを映像として記録でき、macOS 13以降の該当キャプチャ方式では音声も扱える。FFmpegは、録画の切り出しや比較用画像の作成に使う。[OBS公式](https://obsproject.com/kb/macos-screen-capture-source)、[FFmpeg公式](https://ffmpeg.org/ffmpeg.html)

**採用判断：演出と音を作り込む段階で優先。** 参考ゲームについては「操作前→入力→反応→次の気づき」を短いクリップとして残す。自作ゲームでは修正前後を同じ場面で比較する。録画はAIが音や操作感を人と同じように評価できる保証ではないため、人の体験レビューにも使う。

### 5. Playwright Test：Web実装を選ぶなら優先

同じ操作列の再実行、基準画像との比較、失敗時のtrace・動画、時間経過の制御が揃う。小さなWebゲームを継続的に磨くための有力な検証基盤。[画像比較](https://playwright.dev/docs/test-snapshots)、[Trace Viewer](https://playwright.dev/docs/trace-viewer)、[動画](https://playwright.dev/docs/videos)、[時計制御](https://playwright.dev/docs/clock)

Canvasに描かれた部品は、それだけでは意味のあるHTML要素にならない。ゲーム状態の取得と、画面に対する座標・キー操作を組み合わせる。[Canvasのアクセシビリティ](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/canvas#accessibility)

**採用判断：Webで作る場合に採用。** SwiftUI / SpriteKitアプリを直接検証するツールではない。PlaywrightのWebKitもSafari本体ではないので、最終的にWKWebViewに組み込むなら、実アプリ上の確認を残す。[対応ブラウザ](https://playwright.dev/docs/browsers)

### 6. Playwright MCP / CLI：ブラウザ操作の追加候補

Playwright MCPはAIの対話的なブラウザ操作に使える。vision機能ではCanvas / WebGL等を画像と座標で操作できる。公式はCLI＋Skillsという選択肢も案内している。[Vision Mode](https://playwright.dev/mcp/vision-mode)、[公式リポジトリ](https://github.com/microsoft/playwright-mcp)

**採用判断：現在のBrowserで足りない操作が判明した場合。** この環境では基本操作がすでに成功しているため、まず追加したいのは操作窓口の重複より、Playwright Testによる反復確認である。

### 7. Chrome DevTools MCP：Web版の原因調査を補う

通信、コンソール、性能trace、ヒープ等の調査をAIから行う候補。たとえば「何度も再挑戦すると重くなる」「素材が読み込まれない」を調べる用途に合う。[公式ツール一覧](https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/tool-reference.md)

**採用判断：Web試作の性能や不具合を詰める段階。** Chromeの診断結果をMacネイティブ版やWKWebViewの実測結果としては扱わない。

### 8. Peekaboo：Macの入力機能が不足した場合の候補

Macの画面・アクセシビリティ情報・クリック等をCLI/MCPで扱える。`press`の保持時間、`drag`の時間指定があり、現在の操作APIでは足りない入力への候補になる。[公式](https://github.com/openclaw/Peekaboo)、[キー入力](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/press.md)、[ドラッグ](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/drag.md)

**採用判断：対象ゲームで不足を確認してから。** 任意の同時キー入力、ゲームパッド、フレーム同期を万能に扱えるとは確認していない。ライブ撮影も公式上最大15 FPSであり、滑らかさの検証用録画とは用途が異なる。[撮影仕様](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/capture.md)

### 9. WebMCP / 独自MCP：自作ゲームの検証窓口を接続する候補

WebMCPはページがAI向けの操作を公開する仕組み。ブラウザ内で同じ画面を見ながら、定義済みの操作を呼ぶ用途に合う。ただし公式上、対応モデル・配布状況・ワークスペースによる条件があり、今回aibouとの接続は実証していない。[Site tools公式](https://learn.chatgpt.com/docs/webmcp)

**採用判断：最初はテスト用関数や開発画面でよい。** 複数ゲームを共通操作したくなったら、WebならWebMCP、ネイティブならローカルの検証窓口をMCP化する案を検討する。MCPを導入するだけでゲーム状態が見えるわけではなく、aibou側の実装が必要になる。

### 10. Record & Replay：人の操作手順をAIへ伝える補助

Macで実演したワークフローから再利用可能なskillを作る機能。参考ゲームの調査手順や、エディタの定型作業を示す用途が考えられる。[公式](https://learn.chatgpt.com/docs/extend/record-and-replay)

**採用判断：手順を実演したい場合の補助。** ここでのReplayはskillに基づいて手順を行う仕組みであり、ゲームの入力を同じtickで厳密再生する機能とは区別する。今回この機能の録画試験は行っていない。

## 最も重要な自作機能：ゲームの状態を再現・観測できるようにする

以下は既製ツールの機能ではなく、aibouの開発用に実装する提案である。

| 機能 | 具体例 | 何を確かめられるか |
|---|---|---|
| 同じ条件でやり直す | 問題ID・seed・初期データを指定してreset | 修正前後の差が、問題条件の違いに起因していないか |
| 内部状態を読む | 配線、論理値、RAM配置、命令位置、待ち行列、成否理由をJSON出力 | 見た目と実際の計算が一致するか |
| 一手ずつ進める | 1命令、1クロック、1tickのstep | どの操作が何を変えたか |
| 操作を記録・再生する | 初期状態＋tick付き入力列＋モデル版 | 不具合を同じ手順で再現できるか |
| 証拠をまとめる | 同じ試行IDの状態・画像・動画・エラー・性能ログ | 不具合の原因と修正結果を追えるか |

固定seedだけでは完全な再現性は得られない。時間刻み、イベント順、保存状態、外部入力、モデルの版も揃える。仮想PCの「RAMを減らす」「電源を切る」は教育用モデルの操作として実装する。

検証は二つの経路で行う。

1. **人と同じ画面で遊ぶ経路**：実際にクリック・ドラッグして、開始から失敗・成功・再挑戦まで確認する。
2. **モデルの正しさを調べる経路**：条件を固定し、全入力や境界条件を試す。真理値表や手計算で作った期待値と照合する。

内部の値を直接変えて成功画面に到達した試験は、UIを操作してクリアした試験とは分けて記録する。

## ゲームごとに何を確認するか

| 体験の例 | 私が画面で行うこと | 自動検証すること | 初心者に確かめてもらうこと |
|---|---|---|---|
| 回路をつないでランプを点ける | 部品配置、配線、切断、入力切替 | 全入力と真理値表の一致。表示上の配線と接続状態の一致 | 初めての入力で出力を予想できるか |
| RAMと保存場所を使い分ける | データを置く、保存する、仮想電源を切る | 保存済み・未保存の違いが定義したモデル通りか | なぜ残った／消えたのか説明できるか |
| CPUに仕事を割り振る | 命令配置、一手実行、コア数変更 | 依存関係、処理順、完了時間 | コアを増やしても速くならない例を見分けられるか |
| PC内の詰まりを解消する | 一箇所の能力を変えて再実行 | 同じ仕事量での待ち時間・律速の変化 | 未経験の条件で改善箇所を理由付きで選べるか |

楽しさについては「迷わず開始できるか」「失敗から次の手を考えられるか」「条件を変えてもう一度試したくなるか」を観察する。AIのクリアや画像一致は、初心者の理解・楽しさの証明にはならない。少人数の試作評価は改善点を見つけるために使う。

## 操作精度が必要な場面への方針

回路や配置パズルでは、画像とUI情報を再取得しながら一手ずつ操作する。小さな端子については、ウィンドウ移動・Retina倍率・リサイズ後も狙えるかを確認する。

長押しや同時入力が必要なら、そのゲームで「押す→一定時間保持→離す」「ドラッグ途中でキャンセル」「中断後に入力が残らない」を受入試験にする。必要に応じて短い入力列をローカルで再生する仕組みを用意する。LLMが毎フレーム判断することは前提にしない。

検証用のpause / stepがあっても、通常速度でのプレイは別に確認する。私が操作しやすいことだけを理由に、ゲームのテンポや楽しさを削らない。

## 実装方式と参考ゲームの実行環境

現行aibouにはSwiftUI/AppKitの資産がある。2Dゲーム描画にはSpriteKitが候補になるが、ゲームエンジンは未決定。WebやGodotを選ぶ場合も、必要な演出・制作手順・配布形態から判断する。操作ツールの都合だけで移行する根拠はない。[SpriteKit](https://developer.apple.com/documentation/spritekit)、[Godotのデバッグ機能](https://docs.godotengine.org/en/stable/tutorials/scripting/debug/overview_of_debugging_tools.html)

参考作品の実行環境は別途必要である。

- **Web / Mac作品**：現在のツールから着手しやすい。ゲームごとに入力方式を確認する。
- **Windows専用作品**：必要な作品が決まった時点でWindows環境を用意する。Parallelsは候補だが、公式にグラフィックスAPI・ゲーム互換性の制約があり、Mac上で全作品が動くとは仮定しない。[Parallels公式](https://kb.parallels.com/en/129497)
- **Nintendo Switch 2 のひみつ展**：実機での人の操作と録画が現実的な調査経路。キャプチャカードは映像取得の手段で、Joy-Con操作の手段ではない。振動や持ち心地も映像だけでは評価できない。[ElgatoのSwitch 2対応案内](https://help.elgato.com/hc/en-us/articles/34029957928465-Elgato-Capture-Cards-Can-Nintendo-Switch-2-be-captured-or-recorded)

## 整備する順番

1. **代表ゲームを1本選ぶ。** 例えば「2入力の回路をつなぎ、出力を予想する」短い体験。部品操作、因果関係、失敗、再挑戦を一度に確認できる。
2. **描画から分離した学習モデルと、reset・状態取得・stepを作る。** 何を教え、何を省略するモデルかも記述する。
3. **Computer Useで主要な操作を一巡する。** 開始、誤操作、修正、成功、再挑戦を実際の画面で確認する。
4. **採用方式の回帰テストを整える。** MacならXCTest / XCUIAutomation、WebならPlaywright Test。版と画面条件を固定して証拠を残す。
5. **録画・性能計測・初心者プレイで磨く。** 見やすさ、反応、演出、音、学習上の誤解を改善する。
6. **不足が実証された時にツールを追加する。** 時間付き入力ならPeekaboo等、Web診断ならDevTools MCP、複数ゲームの共通操作なら独自MCPを検討する。

この一巡が安定してから、ほかのハードウェア理解のゲームへ展開する。今回の推奨は、追加ツールをすべて導入する指示ではなく、品質を確かめながら構成を選ぶための判断材料である。

## 詳細資料

- [ブラウザ操作・Playwright・DevToolsの調査](research/tooling/browser-qa.md)
- [Mac / Windows / Switchの操作・録画・性能計測](research/tooling/native-qa.md)
- [自作ゲームの再現機能と学習内容の検証設計](research/tooling/quality-harness.md)
- [学習対象の整理](AIBOU_GAME_LEARNING_SCOPE.md)
- [参考ゲームの調査](AIBOU_GAME_REFERENCE_RESEARCH.md)
