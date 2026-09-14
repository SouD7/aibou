# AIBOU — SpriteKit animation prototype

採用したアバター01（黒髪ボブ・短パン・タイツ）を、指定の白い電脳部屋に配置するmacOS試作です。SwiftUI・SpriteKit・AVFoundationを使用し、外部パッケージやAPIキーは不要です。

背景は指定された `design/room-2d/v3/previews/white-horizontal-motion.webp` の動作版です。配線の流光・ファン回転・CPU点滅を、元と同じ24フレーム／2.4秒で繰り返し、アバターはその上で連続的に動きます。

合成した見本は `previews/white-room-avatar-motion.webp`、今回の検証記録は `QA/animated-room/VERIFICATION.md` です。

2026-09-14の立ち姿更新：中央・手前へ約2倍に拡大し、通常／後ろ手／前手の3種類を追加しました。現在の見本は `QA/standing-variants/standing-t1.00.png`、`standing-back-hands-t1.00.png`、`standing-front-hands-t1.00.png`。上記WebPは拡大前の記録です。

## 起動

`AIBOUAvatarMotion.app` を開きます。ソースから作る場合は、このフォルダで `./run.sh`。ビルドだけなら `./run.sh --build`。

macOS 13以降、ソースからのビルドにはXcode Command Line Toolsが必要です。同梱する実行ファイルはこのMac向けのローカル試作で、配布用の公証はしていません。

## 操作

- 部屋の部品にポインタを合わせるとシアンの輪郭と名称が表示されます。クリックすると右上に詳細パネルを開き、選択中の部品をラベンダーで示します。
- ヘッダーの「コンポーネント」一覧からも10個の部品を選べます。アバターに隠れた部品も一覧から開けます。
- 詳細は×、Esc、または部屋の何もない場所をクリックすると閉じます。詳細データは準備中表示です。
- 「警告デモ」から各部品の警告マークを表示・解除できます。「すべてに表示（デモ）」と「すべて解除」もあります。起動時は警告なしで、実際の異常検知は行いません。
- 黄色い「!」の吹き出しをクリックすると、その部品の詳細と警告文を開きます。詳細を閉じても警告状態は維持します。
- 「立つ」「眠る」「読む」「書く」「突っ伏す」「ノイズ」「顔アップ」で状態を切り替えます。
- 「立つ」の下の「立ち姿」で通常／後ろで組む／前で組むを選べます。別のモーションから戻った場合も選択を保持し、音声再生中にも切り替えられます。
- 一時停止、動きの強さ、モーション低減を変更できます。
- 一時停止は部屋とアバターの両方に効きます。「動きを抑える」は部屋を静止させ、アバターの変形を弱めます。強さのスライダーはアバターに作用します。
- 「キャラクターのみ」で背景を隠して全身を確認できます。立ち姿は部屋表示で大きく、脚の下部が画面外に出る配置です。
- 「サンプル音声」でmacOSのKyoko音声を再生し、音量に同期して口を動かします。
- 「音声を選ぶ…」でローカル音声を再生できます。音声の処理は端末内です。

## この版の動き

立ち姿は足元を保ちつつ、頭・髪・胸・衣服付近を異なる周期で変形させます。瞬きは間隔を変えた周期、リップシンクは再生位置に対応する音声の振幅に基づきます。

寝姿はベッドに合う専用原画を使い、閉眼・閉口のまま胸付近を中心に呼吸の動きを付けます。読書は専用の背面原画で、頭・肩の微動とページの変形を付けます。本の配色と背表紙ラインは部屋の本棚の黒／シアンの本を参照しています。見えない表紙・本文は補完案です。

現在は**1姿勢1枚の原画を部位ごとの重みで格子変形する試作**です。髪・袖・指が完全に独立した骨格や描画レイヤーになっているわけではありません。口は音量による開閉で、母音ごとの口形判定は含みません。姿勢間は下記の電気テレポートで切り替えます。

## 素材と座標

- `Assets/room.png`：今回ユーザーが指定した部屋画像（1672×941）。
- `Assets/RoomAnimation/`：指定WebPを画素とフレーム時間を保って展開した背景。`manifest.json` に元ファイルとSHA-256を記録しています。動作背景がある場合はこちらを優先し、`room.png` は静止背景の予備です。
- `Assets/standing.png`、`sleeping.png`、`reading.png`：姿勢ごとの原画。
- `Assets/standing-back-hands.png`、`standing-front-hands.png`：後ろ手／前手の立ち姿差分。元の顔・衣装・画角を保って内蔵image_genで制作し、顔の位置が揃っているため閉眼原画の目のパッチを共有します。
- `Assets/standing-blink.png`：閉眼原画。アプリ側で目の領域だけを取り出し、境界をぼかして瞬きに使用します。
- `Assets/rig.json`：部屋内の位置と表示サイズ、画像内の顔・胸・腰・目口・本の位置。部屋も画像内のランドマークも左上を原点とします。
- `Assets/sample.aiff`：macOS `say` のKyokoで生成したテスト音声。
- `artwork/generation-prompts.json`：内蔵image_genの参照画像とプロンプト。
- `artwork/standing-variants-prompts.json`：追加2姿勢の最終プロンプト、参照画像、生成元ファイル。

原画PNGは緑の単色背景で保存し、アプリの読み込み時に一度だけ背景を除去します。衣装のシアンを残すよう緑成分の優勢を判定し、キャッシュした透過テクスチャを再生に使います。原画の見た目を変える場合は、元のデザイン資料を参照して差し替えてください。

## 検証と再現

`./test.sh` で座標・動き・音声・透過処理の検証を実行します。`./run.sh --qa QA/captures` は実際のSpriteKitレンダリングから比較用PNGとメタデータを出力します。検証結果と残る制限は `QA/VERIFICATION.md` に記録します。

部屋の新しいレイヤー版やバックエンドへの接続は、この試作のシーンと音声制御を既存アプリへ移す次の段階です。

## 動作背景の再現

`scripts/import_room_animation.py` は指定WebPをPNG連番へ展開します。素材の再展開時のみPythonとPillowが必要で、アプリ実行時には不要です。背景は合成済みの動作見本を再生する方式で、家具ごとの制御は含みません。

`./run.sh --capture-dir QA/animated-room/sequence --pose standing --sequence 4.8` で部屋とアバターを一緒に描画した連番を10fpsで取得できます。`--sequence` の値は秒数です。背景は24枚を読み込んで保持するため、背景テクスチャだけで約150MB（展開後）を使用します。

動画書き出し用の `QA/animated-room/sequence/*.png` は生成物としてGit対象外です。確認用WebPと撮影メタデータ、各姿勢の代表PNGを収録しています。旧WebPは拡大前の記録で、現在のソースから連番を再生成すると更新後の中央・拡大表示になります。

## 部屋コンポーネントの選択

`Assets/room-components.json` はv3白・水平の `hitPolygons` と描画順を取り込んだ選択カタログです。本棚、電波塔、時計、ファン2基、ベッド、デスク、演算ユニット、モニター、外部接続、チェアに対応します。複数の輪郭と家具間の重なりを考慮し、拡大縮小時はSKViewからシーン座標へ変換して判定します。キャラクターのみ表示では部屋の選択を無効化します。

`AvatarScene.onComponentSelection` が `RoomComponent?` を通知し、`AvatarStore.selectedComponent` 経由で `RoomComponentDetail` を表示します。後でモニター側の取得処理を `RoomComponent.id` に対応付けて接続できます。現在はデータ取得・OS計測・架空の測定値を含みません。アバターは部屋のクリックを遮らず、重なる場所も背後の部品を選択できます。

検証記録は `QA/component-selection/VERIFICATION.md`。

## 警告表示の接続口

`ComponentWarning` は表示する `message` だけを持つCodableデータです。検知・回復判定はモニター側で行い、メインスレッドで `AvatarStore` または `AvatarScene` の下記APIを呼びます。

```swift
// 部品単位の追加・更新
store.setComponentWarning(ComponentWarning(message: "バックエンドから受け取った警告内容"), for: "compute")
// その部品だけを解除
store.setComponentWarning(nil, for: "compute")
// 全状態のスナップショット。含まれない部品は解除する。
store.replaceComponentWarnings(["fan-1": ComponentWarning(message: "警告内容")])
```

対象IDは `room-components.json` の11個。未知のIDは無視します。同じ状態の再送では吹き出しを作り直さず、メッセージ変更は開いている詳細にも反映します。「キャラクターのみ」表示中はマークを隠し、警告状態を保持します。モーション低減・一時停止中は出現アニメーションを省きます。ポップは短い出現動作だけで、点滅や音はありません。

デモはメモリ内の表示テストです。再起動で解除されます。実データ接続時はデモメニューを外し、上記APIをモニターから更新します。OS通知や検知ロジック、データ取得は含みません。検証記録は `QA/component-warnings/VERIFICATION.md`。

## モーション間の電気テレポート

部屋表示で状態を切り替えると、通常は合計0.5秒で次の順に切り替わります（顔アップは1秒の待機と飛び込みを含め1.62秒）。

1. 0.00–0.10秒：アバターが消え、元位置から短い火花が散る。
2. 0.10–0.20秒：始点から終点までの直線全体が一瞬光る。
3. 0.20–0.50秒：移動先に即座に現れ、横方向のずれ・薄い水色の信号ノイズが短く入る。

色は薄い水色 `#B8EAFF` と白 `#F0FBFF`。火花と直線光はSpriteKitのパス、出現ノイズは元テクスチャを共有する32本の横スライスで描画します。影と背景にはノイズを掛けません。胸の位置を移動経路の始点・終点に使います。

連続操作では進行中の移動を終えた後、最後に指定した姿勢へ移動します。同じ姿勢の再選択では再生をやり直しません。位置が同じ立ち姿差分同士は即時切り替えです。「動きを抑える」「キャラクターのみ」または停止中は演出を省略し、途中でこれらを有効にした場合もノイズを解除して目的の姿勢を表示します。動きの強さスライダーは通常の体の揺れだけに作用します。

実装は `Sources/ElectricTransition.swift` と `AvatarScene.selectPose(_:animated:)`。`animated: false` で演出なしの初期配置ができます。今回の記録・動作見本は `QA/electric-transition-v2/`（`QA/electric-transition/` は旧版）。撮影の `--fps` は1〜60、省略時10です。

```bash
./run.sh --capture-dir QA/electric-transition-v2/reading-to-standing --transition-from reading --pose standing --sequence 0.7 --fps 30
```

## コンポーネントの表示状態

部屋の部品をクリックするか「コンポーネント」メニューから選び、詳細の「表示状態」で切り替えます。「初期値」でその部品だけを戻せます。ファンは2基のオブジェクト・当たり判定を残し、選択・詳細・警告デモでは「ファン」に統合しています。

| 対象ID | 表示状態 | 初期値 |
| --- | --- | --- |
| `bed` | `0` / `1` / `2` / `3` / `4` 灯 | `4` |
| `bookshelf` | `sparse`（スカスカ）/ `normal`（中くらい）/ `overflow` | `normal` |
| `desk` | `normal` / `stacked`（書類の山）/ `overflow`（床にも書類）| `normal` |
| `display` | `normal` / `staticNoise`（砂嵐）| `normal` |
| `fans` | `stopped` / `slow` / `fast` | `slow` |
| `network` | `cyan` / `yellow` / `red` | `cyan` |
| `compute`（CPU）| `cyan` / `yellow` / `red` | `cyan` |

ベッドは枕上・側面とも4灯です。本棚の通常状態とデスクの通常状態は元画像を使い、本の差分は通常画像から切り出した原寸の本を使い、背表紙・厚さ・質感を統一しています。書類とランプはコードで生成したキャッシュ済みテクスチャを重ねます。ファンとCPUはv3で分離済みの素材を小さく切り出して再利用します。高速ファンは5回転／秒（300RPM、12フレーム／回転を毎秒60フレームで再生）で、羽根のブラーを重ねています。状態は互いに独立し、再起動すると初期値に戻ります。

バックエンド未接続で、観測値から状態への閾値判定は行いません。後でモニターからメインスレッドで下記を呼び出せます。

```swift
// 部品単位。未知の部品・状態や範囲外の灯数にはfalseを返し、既存状態を保持します。
scene.setComponentVisualState("2", for: "bed")
scene.setComponentVisualState("fast", for: "fans")
scene.setComponentVisualState("red", for: "compute")

// 全体のスナップショット。型付きCodableデータとして受け取れます。
let state = try JSONDecoder().decode(RoomVisualState.self, from: data)
scene.setRoomVisualState(state)
// onVisualStateChangeでUIに反映。同一状態の再送では通知を繰り返しません。
```

`fan-1` / `fan-2` も状態指定の別名として受け付け、両方のファンをまとめて変更します。警告は引き続き実オブジェクト単位で保持でき、`fans` を指定すると両方へ設定・解除します。詳細には両者の警告を集約します。

「動きを抑える」ではファン・CPU・砂嵐の時間変化も停止します。一時停止中でも手動の状態変更はでき、「キャラクターのみ」では状態を保持したまま部屋を隠します。

実装：`RoomVisualState.swift`（データ）、`RoomStateRenderer.swift`（描画）、`RoomStateArtwork.swift`（冊数・書類・ランプ・砂嵐）。素材の再切り出しは `scripts/import_room_state_assets.py`。確認画像は `QA/room-states/` にあります。

```bash
./run.sh --capture-dir QA/room-states/captures --room-states-qa
```

## 追加のアバター状態

- **書く**（`writing`）：チェアに座り、デスクの紙にペンを走らせます。椅子に座ったキャラクターを一緒に描いた専用原画と、手元の細かな往復・呼吸を使います。書く間は元の背景の椅子を隠し、椅子の座面・背もたれ・脚は変形させません。
- **突っ伏す**（`cpu-rest`）：両膝を床につき、顔だけをCPUに伏せ、両腕は下へ脱力して垂らします。添付の膝立ち／突っ伏し参考画像を体勢の参考にし、既存衣装を維持した専用原画です。前版より縦横20%縮小し、顔と膝の接地点を保って胴体と腕が小さく呼吸に合わせて揺れます。
- **ノイズ**（`glitch`）：通常の立ち姿に、遷移と同じ横スライスの信号ノイズが約2秒に1回入ります。4秒ごとに2回、間隔と長さが変わり、継続時間は約0.20〜0.42秒です。再現可能な時間関数を使っています。
- **顔アップ**（`close-up`）：通常の立ち原画の顔を画面いっぱいに拡大します。元位置から消えて1秒待ち、下からフェードインして目標を少し通り過ぎ、1回跳ね返って1.62秒で収まります。登場からバウンド終了までは口を開けた笑顔の原画を使い、その後に通常表情へ戻ります。待機中も光とノイズの内部時間は進み、表示時には到着ノイズが終了しています。顔を基準に拡縮し、「キャラクターのみ」でも顔の画角を維持します。

追加状態への出入りにも既存の火花・直線光・到着ノイズを使います。通常の立つ状態とノイズ状態の間も演出します。一時停止・「動きを抑える」・「キャラクターのみ」では既存の方針に合わせて遷移を省略し、途中の演出を解除します。周期ノイズもこれらの設定で止まります。立ち姿3種の選択は独立して保持します。

現行原画は `Assets/writing-seated.png`、`Assets/cpu-rest-relaxed.png`、`Assets/standing-smile-crescent.png`（緑背景を既存の処理で透過）。顔アップの登場・バウンドには、口を開けて三日月目で笑う差分を使います。従来の目を開けた笑顔 `Assets/standing-smile.png` も保持しています。内蔵image_genの修正プロンプトは `artwork/state-refinements-prompts.json`、三日月目差分は `artwork/crescent-smile-prompt.json`。初版プロンプトは `artwork/additional-states-prompts.json`。顔アップはバウンド終了後、通常の立ち原画・閉眼パッチへ戻ります。顔アップは既存原画を拡大するため、新規の高解像度顔原画ではありません。

再現例（状態IDは上記の括弧内）：

```bash
./run.sh --capture-dir QA/additional-states/close-up --transition-from reading --pose close-up --sequence 2 --fps 20
./run.sh --capture-dir QA/additional-states/glitch --pose glitch --sequence 6 --fps 10
```

検証結果は `QA/additional-states/VERIFICATION.md`。

書く間の椅子消去は `Assets/WritingBackdrop/` の24フレームの局所背景を使います。既存の部屋レイヤーを椅子なしで再合成し、部屋と同じ2.4秒周期で追従します。再生成は `scripts/export_writing_backdrop.py`。座り姿の椅子はアバター原画の一部で、別レイヤーの椅子を体の上へ重ねていません。2026-09-15の修正検証は `QA/state-refinements/VERIFICATION.md`。
