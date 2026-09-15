# ネイティブゲームの操作・観測・実装QAに必要なツール

調査日：2026-09-14。この分冊は公式ドキュメント・公式リポジトリを確認した機能調査。現在のComputer Useによる既存Macアプリの限定的な実操作結果は[統合資料](../../AIBOU_GAME_TOOLING_RESEARCH.md)に記録した。追加ツールの導入・権限変更は行っていない。以下の「推奨」「設計案」はaibou向けの判断であり、ベンダーの保証とは区別する。

## 結論

品質を優先するなら、AIの画面操作だけに検証を任せず、次の役割をそろえる。

1. **既存ゲームを観察して遊ぶ：** 画面＋アクセシビリティを読めるcomputer useを主経路にする。macOS追加候補はPeekaboo。追加導入は現在使える操作ツールに不足がある場合でよい。
2. **体験を記録する：** OBS Studioによる映像・音声記録。操作ログと時刻を合わせ、どう操作したら何が起きたかを残す。
3. **自作Macアプリの操作を反復確認する：** XCTest + XCUIAutomation、Accessibility Inspector。
4. **自作ゲームの滑らかさ・負荷を測る：** Xcode Instruments、Metalを使用する場合はMetal Performance HUD。動画だけではフレーム時間や原因を確定しない。
5. **同じ状態を再現する：** ゲーム内にseed固定・reset・pause/step・状態/イベント出力を実装する。これは製品購入より優先度が高い設計上の準備。

現行の `monitor/README.md` では、監視アプリはSwiftUI/AppKit、基本観測は2秒間隔、詳細は1秒間隔。「ディスプレイの設定Hz」は実表示FPSではないと明記されている。このデータだけでミニゲームのフレーム落ちを検証する設計にはしない。現状はコマンドによるビルドのため、XCUIAutomationの採用にはUIテスト用targetなどを整える必要がある。

## macOS向けツールの比較

| ツール | 確認できた機能 | aibouでの用途・優先度 | 限界 |
|---|---|---|---|
| **Peekaboo** | macOSのCLI・メニューバーアプリ・MCP。画面撮影、AX階層と要素ID、クリック、ドラッグ、キー入力、ウィンドウ操作 | 既存Steam/Macゲームの観察・手動に近い操作の追加候補。現在のcomputer useで不足を確認後に採用 | macOS 15以降。ゲームが独自描画した盤面に意味付き要素があるとは限らない。物理ポインタのドラッグは前面操作。全ゲーム互換を保証しない |
| **XCTest + XCUIAutomation** | XCTestのアサーションとUI操作。クリック、キー入力、保持時間と速度を指定するドラッグ | 自作aibouの「開く→遊ぶ→結果→再挑戦」の回帰検証に高優先 | 実装・テストtargetの準備が必要。意味情報が公開されないゲーム盤面は座標操作や別の観測方法を要する |
| **Accessibility Inspector** | 階層内のアクセシビリティ情報を表示・問い合わせ・テスト | ボタン名、状態、フォーカス順序、ゲーム盤面の操作可能性の確認に高優先 | 画像に描かれただけの部品の意味を自動的に生成するものではない |
| **OBS Studio** | macOS ScreenCaptureKitにより画面・単独ウィンドウ・アプリをキャプチャ。macOS 13以降は音声も取得。WebSocketによる外部制御 | 既存作品の学習体験、aibouの視覚・音・動きのQA記録に高優先 | 入力ツールではない。録画負荷やキャプチャFPSが観察対象に影響する可能性を考慮する |
| **Xcode Instruments** | CPU、メモリ、I/O等のプロファイリング。Time Profiler、Allocations/Leaks等 | 遊び始め・演出・大量オブジェクト・画面切替での詰まりを特定する品質確認 | 全ての情報がAIに既存の専用ツールとして提供されているわけではない。計測と結果出力の手順を用意する |
| **Metal Performance HUD** | MetalアプリのFPS、フレーム間隔、GPU時間、メモリ等の可視化・ログ | Metal描画を使う実装の滑らかさと負荷を調べる追加経路 | あらゆる描画方式の万能計測器ではない。原因分析にはInstruments等を併用 |

根拠：[Peekaboo公式](https://github.com/openclaw/Peekaboo)、[XCTest](https://developer.apple.com/documentation/xctest)、[ドラッグAPI](https://developer.apple.com/documentation/xcuiautomation/xcuicoordinate/click%28forduration%3Athendragto%3Awithvelocity%3Athenholdforduration%3A%29)、[Accessibility Inspector](https://developer.apple.com/documentation/accessibility/accessibility-inspector)、[OBSのmacOSキャプチャ](https://obsproject.com/kb/macos-screen-capture-source)、[OBS外部制御](https://obsproject.com/kb/remote-control-guide)、[Appleの性能改善ガイド](https://developer.apple.com/documentation/xcode/improving-your-app-s-performance/)、[Metal HUD公式解説](https://developer.apple.com/videos/play/tech-talks/110339/)。

## Peekabooを採用する場合の確認事項

旧 `steipete/Peekaboo` URLは調査時点で `openclaw/Peekaboo` に転送される。公式README上の現行配布はmacOS 15以降、npm版はNode.js 22以降。Screen Recording・Accessibility、入力方式によってEvent Synthesizingの権限が必要である。[公式README](https://github.com/openclaw/Peekaboo)

機能の細部は、名前だけで判断せず次のように扱う。

- `press` はキーごとの `--hold`、キー間の `--delay`、キー列の反復を指定できる。公開されたchord構文は修飾キーと最後の通常キーであり、「WとDを同時に押し続ける」など任意の通常キーの同時入力やゲームパッド入力まで備えるとは確認していない。[press仕様](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/press.md)
- `drag` は始点・終点、時間、補間点数、左右ボタン、修飾キーを指定できる。経路を使う配線操作や部品配置の候補になる。ただし前面の物理カーソルを使うため、利用者が同時に別作業をすると干渉しうる。[drag仕様](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/drag.md)
- `capture live` は変化を検出してPNGを保持し、コンタクトシート・メタデータを作れる。**active FPSは最大15、ライブ収録の上限は180秒**。これは体験の節目の記録に向き、60/120 FPSの滑らかさを評価する証拠には不足する。必要な連続動画はOBS等で別途記録する。[capture仕様](https://github.com/openclaw/Peekaboo/blob/main/docs/commands/capture.md)
- スナップショットに紐づく要素IDや正確なウィンドウ指定を使う。画面変更後には再観測し、古い座標や「入力を送れた」という結果だけで成功扱いにしない。[Automation仕様](https://github.com/openclaw/Peekaboo/blob/main/docs/automation.md)

## 「画面が見える」と「ゲーム盤面を理解して操作できる」の違い

ネイティブゲームやCanvas相当の独自描画では、画面上に20個の部品があっても、AX階層上は大きな描画領域1個という場合がある。Appleは、単一のviewに複数の独立した要素を描く場合、それぞれを `NSAccessibilityElement` として公開する方法を案内している。したがって、computer useツールを増やすだけでは、自作ゲームに存在しない意味情報を補えない。[Appleのカスタム要素実装ガイド](https://developer.apple.com/documentation/accessibility/integrating-accessibility-into-your-app)

推奨する二重の確認経路：

- **人と同じ画面・入力での確認：** 見た目、操作のわかりやすさ、ドラッグしやすさ、フィードバック、成功/失敗の読み取りを見る。
- **内部状態を用いた確認：** 配線接続、メモリ割当、命令位置、待ち行列、勝敗条件を状態出力で検証する。UIだけでは見逃すルールの不整合を検出する。

自作ゲームには、部品や操作の名前・状態・座標、再挑戦、キーボード操作を用意すると、アクセシビリティと自動検証を同時に改善できる。内部状態を直接変更するテストだけでUI品質まで保証したことにはしない。

## 入力ツールに求める仕様

以下はaibouと参考ゲームの操作に必要な受入れ基準の提案。

| 要件 | なぜ必要か | 確認方法 |
|---|---|---|
| 画面・ウィンドウの正しい座標変換 | Retina倍率・ウィンドウ移動で配線端子を外さない | 縮尺や位置を変えて同じ端子を操作 |
| mouse down / move / upの分離または時間付きドラッグ | 配線・部品配置・経路作成 | 途中移動、キャンセル、領域外ドロップを試す |
| key down / key up・保持時間 | 移動・時間進行・連続操作 | 短押しと長押しを区別して結果を確認 |
| 複数キー・マウスを組み合わせる入力 | 修飾操作や同時移動 | 実際に必要になった組合せで受入試験 |
| 操作の停止・全入力の解放 | 中断後に押しっぱなしが残らない | 失敗・中断・対象ウィンドウ喪失を試す |
| 時刻付き操作ログ＋動画 | どの入力で状態が変わったか比較する | ログのマーカーと映像を突き合わせる |
| 入力後の観測と成功条件 | OSへの入力送信成功とゲーム内成功は別 | 出力・状態・進行を読み直す |

フレーム単位の正確さが必要な場合、AIが毎フレームを見て判断する方法には頼らず、短い入力列を実行するローカルの再生器と、ゲーム内の固定時間ステップを用意する。これは精度を得る設計案であり、今回調べた汎用GUIツールがリアルタイム制御を保証しているという意味ではない。

## Windows専用ゲームを調べる必要が出た場合

**品質重視の第一候補は、対象ゲームが動くWindows実機を別に用意し、その実機側で入力と録画を実行すること。** PC購入が必須という結論ではない。まず参考作品のMac版・ブラウザ版で十分かを確認し、Windows専用作品にしか得られない知見がある場合に拡張する。

Mac上のParallelsは利用可能な候補だが、2026-08-25更新の公式制約では、Apple Silicon上の3DアクセラレーションはDirectX 11.1・OpenGL 4.3で、一部のゲームやアプリは動作しない。VM内で測った性能を、Windows実機での本来の体験やaibouのMac性能と同一視しない。[Parallels公式制約](https://kb.parallels.com/en/129497)

追加の入力手段としてPyAutoGUIは `keyDown/keyUp`、`mouseDown/mouseUp`、時間付きドラッグを提供する。状態を見て判断するAI自体ではなく、入力の実行部品である。[PyAutoGUI公式API](https://pyautogui.readthedocs.io/en/latest/quickstart.html)

Windowsで通常の入力がゲームに届かない場合、PyDirectInputはDirectInputのscan codeとWin32 `SendInput` を用いる候補。ただし原作者のREADMEでは、drag・hotkey・scrollが未実装、マウスのduration等が無視されると明記されている。aibouの全操作を任せる標準基盤としては推さず、特定ゲームの入力が必要になったときの補助候補に留める。[PyDirectInput公式](https://github.com/learncodebygaming/pydirectinput)

遠隔デスクトップや映像配信を使う場合も、ネットワーク遅延と録画のフレーム落ちはゲーム自体の問題と分ける。性能計測は実行マシン内で記録する。

## Nintendo Switch 2のひみつ展

通常のMacのcomputer useだけで、Switch 2実機のJoy-Con入力や体験を操作できるとは確認していない。基本の調査経路は、**実機で人が操作し、録画・観察結果をAIと共有すること**。

本体のキャプチャボタンは一部のソフト/場面を除き、最大30秒前からの動画を保存する。短い操作の記録には使えるが、長い探索の記録には別途キャプチャ環境が必要。[任天堂公式サポート](https://support-jp.nintendo.com/app/answers/detail/a_id/35057)

ElgatoはSwitch 2の外部キャプチャ対応を案内しており、キャプチャカード＋PC＋OBSなどは映像取得の候補になる。ただし映像取得とコントローラー操作は別の経路。解像度・HDR・120 Hzを観察対象にするなら、カードと録画設定もその形式に対応している必要がある。[Elgato公式対応情報](https://help.elgato.com/hc/en-us/articles/34029957928465-Elgato-Capture-Cards-Can-Nintendo-Switch-2-be-captured-or-recorded)、[録画の公式ガイド](https://www.elgato.com/us/en/explorer/products/capture/How-to-Stream-or-Record-Nintendo-Switch-2-Gameplay/)

振動・実物の持ち心地・マウス操作感などは、映像だけでは評価できない。人の体験記録を併用する。フレームレート比較を低FPSの画像サンプルだけで判定しない。

## aibouに先に整備したい検証用機能

外部ツールの導入数より、次の機能が「AIが実装して試し、改善する」反復の品質を決める。

1. 指定ステージ・指定seedで起動できる。
2. 初期状態へのreset、pause、1ステップ進行ができる。
3. プレイヤーの操作を時刻/ステップ付きで記録し、同じ初期状態で再生できる。
4. ゲーム状態・学習上の重要イベント・勝敗理由を機械が読める形で出せる。
5. 表示と状態の対応を確認できる。例えば「配線したように見えるが未接続」「保存したように見えるがRAMにしかない」を検出できる。
6. リサイズ、拡大、音量、キーボード、動きを減らす設定で確認できる。
7. 通常・失敗・再挑戦・途中終了の代表シナリオを一つの手順で繰り返せる。

AIによるクリア確認は操作とルールの品質を支える。初心者が本当に理解するか、楽しいかは、対象ユーザーに「説明・予想・別の状況への適用」を試してもらう検証が必要である。
