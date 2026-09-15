# aibou向け：ブラウザ操作・ゲームQAのツール調査

調査日：2026-09-14。対象はWebで遊ぶ参考作品と、Webで実装する場合のaibouゲーム部分。この分冊は公式文書に基づく機能調査。現在のComputer Useによる限定的な実操作結果は[統合資料](../../AIBOU_GAME_TOOLING_RESEARCH.md)に記録した。追加ツールは導入していない。推奨構成と品質判断はaibou向けの提案。

## 結論

Web実装を採る場合、**探索操作用のComputer Useと、再現可能なテスト用のPlaywright Testを組み合わせる**。Chrome DevTools MCPは、動きが重い、メモリが戻らない、素材が読み込めない等の問題を調べる補完ツールにする。

品質を左右するのは、操作ツールを増やすことより、**同じ場面を再現し、ゲーム内部の状態と実際の画面を照合できること**である。自作ゲームには、固定された初期条件、一時停止とステップ実行、入力記録、状態の読み取りを最初から設計する。

## ツール比較と導入優先順位

| 候補 | 推奨役割 | 確認できた機能 | 弱点・適用限界 | 優先順位 |
|---|---|---|---|---|
| Playwright Test / Library | 自作Webゲームの回帰テスト。起動→配置→実行→成功/失敗→再試行を、修正後も繰り返し検証 | マウス・キーボード操作、スクリーンショット比較、動画、trace、ブラウザ内JavaScriptの実行、時間制御、複数ブラウザ | テストシナリオと期待結果を設計する必要がある。画像差分だけでは学習内容や面白さは判断できない。macOSネイティブUI用ではない | **Webを選ぶならP0** |
| Playwright MCP | AIが参考ゲームや試作品を対話的に操作する入口。通常UIは意味を持つ要素、Canvasは画像と座標で扱う | 既定はアクセシビリティスナップショット。vision capabilityで座標クリック、ドラッグ等を追加 | Canvas内の意味やゲームルールは自動では得られない。任意のゲームの完走やリアルタイム反射操作を保証しない。既存Computer Useと用途が重複する場合は追加必須ではない | **P1・既存操作手段が不足したら** |
| Playwright CLI + Skills | AIがコード開発と並行して、短いコマンドでブラウザ操作を進める選択肢 | 公式MCP READMEで、コーディングエージェントにとってCLI + Skillsが適する場合があると案内 | Playwright Testそのもの、MCP、CLIは役割が異なる。全部を常設する根拠にはならない | **P1・MCPとの選択候補** |
| Chrome DevTools MCP | Chrome上の性能・通信・コンソール・メモリ診断 | performance trace、コンソールと通信の調査、JavaScript評価、画像取得、ヒープ調査等 | 公式サポートはChrome / Chrome for Testing。Webの性能指標が良好でも、ゲームの遊びやすさやネイティブアプリの性能が良いとは限らない | **P1・Web試作の性能を詰める段階** |

Playwrightの対応ブラウザはChromium / WebKit / Firefoxなど。WebKitはSafari本体とは異なるため、WKWebViewに組み込む場合やネイティブのSwiftUI / SpriteKitを採る場合は、最終的なmacOSアプリ上で別途確認する。ブラウザ上の試作が成功したことを、そのまま実アプリ品質の証拠にはしない。[対応ブラウザ](https://playwright.dev/docs/browsers)

Playwright MCPの公式案内は、MCPを継続的な状態・構造観察が役立つ探索用途、CLI + Skillsをコーディングエージェントの処理量・コンテキスト効率に合う選択肢として区別している。aibouでは実際に利用可能な操作手段を確認し、重複導入を避けて選ぶ。[Playwright MCP公式README](https://github.com/microsoft/playwright-mcp)

## Canvas / WebGLゲームで必要になること

HTML Canvasは描画された物体を意味を持つHTML要素として自動公開しない。画面にスイッチ、配線、メモリブロックが見えていても、アクセシビリティツリーから各物体を取得できるとは限らない。[MDN Canvas公式リファレンス](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/canvas#accessibility)

Playwright MCPにはvision capabilityがあり、公式文書はCanvas / WebGLでスクリーンショットと座標操作を用いる方法を示している。これにより操作の入口は作れるが、隠れた状態の把握や正しい解法の発見まで自動で保証されるわけではない。[Playwright MCP Vision Mode](https://playwright.dev/mcp/vision-mode)

自作ゲームへの設計提案：

- メニュー、開始、停止、再試行、解説、数値設定などは、可能ならラベルを持つ通常のUIとして実装する。
- 盤面にある物体には安定したIDを与え、「入力Aの値」「ゲートBの出力」「空きRAM」「待機キュー」などを読み取れるようにする。
- 外部への公開を必要としない開発用インターフェースで、状態をJSONとして取得できるようにする。画面表示と状態を照合するために使う。
- 反射速度を伴わない検証には、一時停止、1ステップ実行、速度変更を用意する。通常速度での体験検証も別に残す。
- 画面から操作する経路は必ず検証する。内部状態を書き換えて成功画面を出すだけでは、実際に遊べることの確認にならない。

## 記録・再現・見た目の検証

**Trace**は「どの操作で崩れたか」を追うために使う。Playwright Trace Viewerは操作、DOMスナップショット、画像の時系列、コンソール、通信などを確認できる。ただしDOMスナップショットはゲームエンジンの全内部状態を保存するものではない。Canvasでは画面記録と独自の状態記録を併用する。[Trace Viewer](https://playwright.dev/docs/trace-viewer)

**動画**はアニメーション、成功・失敗の伝わり方、遷移の唐突さを見直す材料になる。Playwright Testは失敗時のみ動画を残す設定も提供する。録画の解像度は既定値のままにせず、ゲーム内の細かな文字や信号が読める大きさに合わせる。[Videos](https://playwright.dev/docs/videos)

**画像差分**はレイアウト崩れ、描画抜け、配線の見え方などの回帰を検出する。基準画像を保存して比較できるが、OS、ブラウザ、フォント、ハードウェア等で描画が異なるため、比較環境をそろえる。差分がないことは、機能・意味・楽しさが正しい証明にはならない。[Visual comparisons](https://playwright.dev/docs/test-snapshots)

**時間制御**ではPlaywright ClockがDate、タイマー、requestAnimationFrameなどを扱える。これを使って経過時間に依存する処理を検証できる。ただし乱数、外部入力、ゲーム固有のシミュレーションまで自動的に決定的になるわけではないため、固定seedと明示的なシミュレーションtickをゲーム側に設けることを推奨する。[Clock](https://playwright.dev/docs/clock)

## 開発用インターフェースの最小構成案

以下は既存製品の機能一覧ではなく、aibouに追加する開発用設計案。

| 能力 | 具体例 | 品質への効果 |
|---|---|---|
| シナリオを選ぶ | メモリ容量8、仕事3件、固定seed17で開始 | 同じ問題を何度も確認できる |
| 状態を読み取る | メモリ領域、処理待ち、現在tick、成功条件、エラー | 画面とシミュレーションの食い違いを見つける |
| 時間を進める | 停止、1tick、10ticks、通常速度 | 因果関係を追いやすくする |
| 操作を記録・再生する | 初期条件＋tickごとの入力＋期待結果 | 以前直した不具合が戻っていないか確認できる |
| シーンを保存する | 状態JSON＋スクリーンショット＋バージョン | 不具合の報告と再現を容易にする |

ゲームを学ぶAIが人間に見えない情報を読む検証と、人間と同じ画面だけで遊ぶ検証は、結果を分けて記録する。前者は正しさと不具合診断、後者は説明・視認性・操作の確認に使う。面白さと学習効果の最終確認には、想定する初心者の実プレイが必要である。

## 最初に行うべき実証

最初の1ゲームで、以下を一巡できることを確認してから対象を増やす。

1. AIが画面を見て開始し、部品またはデータを操作する。
2. 正解と不正解を一度ずつ試し、何が起きたかを画像と状態で説明する。
3. 同じ操作を再実行し、同じ結果を得る。
4. ウィンドウの大きさを変えても主要操作ができる。
5. 修正前後の画像・操作記録・結果を比較する。
6. 通常速度でも、操作の反応・演出・音・説明のタイミングを人が確認する。

この実証が通れば「AIがこのゲームの主要経路を操作・検証できる」と言える。単にクリックAPIがあるだけで「任意のゲームをAIが実際に遊び切れる」とは言わない。

## Chrome DevTools MCPの使いどころ

画像や状態を確認して、動作の遅さ、読み込み失敗、繰り返しプレイ後のメモリ増加などが問題になったときに導入価値が高い。公式ツール一覧にはperformance trace、コンソール・ネットワーク、JavaScript評価、ヒープスナップショット等がある。ゲームの状態を読み取る入口にもできるが、状態を意味のある形で公開する設計は別途必要。[公式ツール一覧](https://github.com/ChromeDevTools/chrome-devtools-mcp/blob/main/docs/tool-reference.md)

導入時の条件として、公式READMEのChrome対応範囲、利用統計、CrUXへのアクセス設定を確認する。現時点の公式文書は利用統計の既定有効と無効化オプション、性能ツールのCrUX参照を明記している。今回それらの設定変更・導入は行っていない。[Chrome DevTools MCP公式README](https://github.com/ChromeDevTools/chrome-devtools-mcp)

## 補助となるAPIの一次資料

- [Playwright Mouse](https://playwright.dev/docs/api/class-mouse)：移動、クリック、押下・解放などの座標操作。
- [Playwright Evaluating JavaScript](https://playwright.dev/docs/evaluating)：ページ内状態の読み取り・開発用インターフェースとの接続。
- [Playwright MCP公式リポジトリ](https://github.com/microsoft/playwright-mcp)：現在のツール能力と設定。
- [Chrome DevTools MCP公式リポジトリ](https://github.com/ChromeDevTools/chrome-devtools-mcp)：対応範囲と必要環境。
