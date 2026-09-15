# 20体験 実装契約（2026-09-15）

> 20体験の制作・検証時の記録です。下記のラボ統合・復帰コールバック・外部出力フォルダの記述は切り出し前の履歴です。単独版では接続を除去し、[現在の検証結果](QA/STANDALONE-VERIFICATION.md) に範囲を記録しています。


共通部分の編集担当はroot。授業Lesson*と既存回路・ラボ・展示UIを保持する。

## Core
`ExperienceModel: Codable, Equatable`
- `associatedtype Action`（Codable不要）
- `static var gameID: String { get }`
- `init(stage: Int)` 1...5
- `var stage: Int { get }`
- `var stageTitle: String { get }`
- `var goal: String { get }`
- `var guide: String { get }` 現在の状態に即した相棒の言葉
- `var hints: [String] { get }` 段階的3件
- `var isComplete: Bool { get }`
- `var metrics: [ExperienceMetric] { get }` 観察ノート用 3〜5行
- `mutating func send(_ action: Action)` 不正な操作は安全に拒否。モデル内でフィードバック
- `var isValid: Bool { get }` 保存読込検証。defaultはstage範囲だけ、固有状態の整合を追加可

`ExperienceMetric(_ label: String, _ value: String, detail: String = "")` Codable/Equatable/Identifiable。

## UI
`@StateObject private var store = ExperienceStore(MyModel(stage: 1))`
Viewの引数は `var onExit: () -> Void` と `var onLab: (() -> Void)? = nil`。

```
ExperienceScreen(store: store, onExit: onExit, onLab: onLab) { model, send in
    MyApparatus(model: model, send: send)
}
```

`ExperienceStore<M>` はmodelをPublished、操作undo/reset/再開/保存/作品/比較を担当。
`send(_ action: M.Action)` により変更時のみ保存。
各担当は共通header/goal/guide/観察ノート/作品/段階選択を作らない。
contentの領域は **幅1160×高さ550**、ダークな装置盤。内部のパディング16〜24。
contentはモデルとsendだけで描画し、Storeの状態に依存しない（作品の独立再生に再利用）。
主要な固有ボタン/部品トレイをこの盤の中に置く。文字18〜24、ラベル14〜17。
共通の背景は白い机、作業盤はグラファイト、物理装置は白い厚い面取りパネル。
女の子は右下365×426、観察ノートは右上356×292、字幕と共通操作は盤面の下。

共通UI部品（root所有、実装済み）：
- `ExperienceDevice(title: String, subtitle: String = "", active: Bool = false, @ViewBuilder content: () -> Content)` 白い装置、ネジ、厚み。サイズは外でframe指定。
- `ExperienceButtonStyle(primary: Bool = false)` 共通の物理ボタン
- `ExperienceChip(label: String, symbol: String = "square", color: Color = .cyan, selected: Bool = false)` データ/部品のカートリッジ（Buttonではない）
- `ExperienceSignal(active: Bool, vertical: Bool = false)` 状態に沿った信号経路
- `ExperienceStyle` ink/muted/cyan/dark/paper/purple/amber/coral
- 既存WorkshopChamfer/WorkshopPlateも使用可

独自の装置絵はSwiftUI Path/Shape/Canvas等で描画。適切な暗色背景上で白文字を使う。選択はシアン縁、無効は薄く、unknownは?。
操作はクリックとキーボードで可能にし、配置型はドラッグでも同じActionを送る。
rootが全体の初回統合ビルドを実施。担当は独自の全体ビルドを重複実行しない。

## 担当
root: Core共通/Store/Screen/素材/統合/19冷却・20ボトルネック/既存回路共通化
logic: Logic*.swift（01/03/04/05/06）
memory: Memory*.swift（09/10/11/12/17/18）
parallel: Parallel*.swift（07/08/13/14/15/16）

## 画面・保存の具体値

共通画面は1600×900。盤面は x28/y169、1160×550。見出しは x28/y16、1544×62。課題は x28/y94、1544×56。観察ノートは x1216/y169、356×292。女の子は x1210/y462、365×426。字幕は x28/y739、1160×82。共通操作は x28/y839、1160×54。

色・面取り・影・文字・選択・無効状態は `ExperienceChrome.swift`。女の子は `LessonArt` の welcome / explaining / celebrating を使用。背景は既存の作業机素材を再利用。各ゲームの装置はモデルから描画し、素材に固定された数値や不可視ボタンは使用しない。

保存は `ExperienceModel.swift` の共通Recordと `ExperienceStore.swift`。体験ごとに独立したJSON。作品はモデルのスナップショットで、再操作はコピー。旧workshop保存は保持し、旧回路入口を残す。予想・理由・発見、比較、ヒント利用、完了課題も保存する。

## 統合進捗（完成）

全20体験を展示館へ統合済み。全課題、保存・再開、モデルの成功・失敗条件を確認済み。代表20画面と9つの追加状態の目視確認、最終最適化ビルドを完了。

|番号|体験ID|状態|確認済み|残作業|
|---|---|---|---|---|
|01|bit-art|完成|5課題・代表/失敗条件・保存再開・画面|なし|
|02|circuit-atelier|完成|5課題・代表/失敗条件・保存再開・画面|なし|
|03|memory-switch|完成|5課題・代表/失敗条件・保存再開・画面|なし|
|04|tiny-switch-workshop|完成|5課題・代表/失敗条件・保存再開・画面|なし|
|05|instruction-atelier|完成|5課題・代表/失敗条件・保存再開・画面|なし|
|06|work-dispatch|完成|5課題・代表/失敗条件・保存再開・画面|なし|
|07|parallel-factory|完成|5課題・代表/失敗条件・保存再開・画面|なし|
|08|pixel-factory|完成|5課題・代表/失敗条件・保存再開・画面|なし|
|09|memory-dock|完成|5課題・代表/失敗条件・保存再開・画面|なし|
|10|cache-delivery|完成|5課題・代表/失敗条件・保存再開・画面|なし|
|11|memory-rescue|完成|5課題・代表/失敗条件・保存再開・画面|なし|
|12|storage-warehouse|完成|5課題・代表/失敗条件・保存再開・画面|なし|
|13|display-studio|完成|5課題・代表/失敗条件・保存再開・画面|なし|
|14|packet-express|完成|5課題・代表/失敗条件・保存再開・画面|なし|
|15|board-town|完成|5課題・代表/失敗条件・保存再開・画面|なし|
|16|connection-lab|完成|5課題・代表/失敗条件・保存再開・画面|なし|
|17|pc-day|完成|5課題・代表/失敗条件・保存再開・画面|なし|
|18|battery-voyage|完成|5課題・代表/失敗条件・保存再開・画面|なし|
|19|cooling-workshop|完成|5課題・代表/失敗条件・保存再開・画面|なし|
|20|bottleneck-detective|完成|5課題・代表/失敗条件・保存再開・画面|なし|

共通保存17確認成功。Core全163テスト成功。全20体験の課題1成功→保存→再読込→作品コピーの独立性を実Storeで確認。全20×5課題の初期と成功・再開の140画面を保存済み。

**完成20、実装中0、依存待ち0、未着手0。**

検証記録: `QA/Experiences/`。全課題画面: `../output/minigame-experiences-qa-native-v2/`。最終代表: `../output/minigame-experiences-qa-final-v3/`。納品ページ: `../output/minigame-experiences-delivery/index.html`。

ラボ側の開発は別担当へ移管。こちらは展示館・20体験・ゲーム側の復帰コールバックを担当し、ラボ内部の追加変更は行わない。

## 最終確認

- 01〜06：Logic担当が代表6枚、05の初期/3出力、06のI/O待ちを目視。rootが共通枠・統合を確認。
- 07/08/13〜16：Parallel担当が代表6枚、長い依存説明・4人・1100幅を目視。rootが新造形と小窓を確認。
- 09〜12/17/18：Memory担当が代表6枚を目視。09の文字、12の待機台詞の修正後も再確認。
- 19/20：rootが熱16・長い待ち列・課題5の全条件ボタンを目視。固有9テストと全体保存検証済み。
- `game-lab/AIBOUGameLab.app` を最後の札のコントラスト変更まで含め最適化ビルド・署名。
- ラボ統合ビルドは成功。その後のラボ作業は別担当へ移管し、共通ゲームUIの最後の1ファイルはソースから取り込める形で納品。

元の生成画像との相違と検証範囲は納品書に明記。画面の画像化だけではなく、全体験がモデルと共通の保存・操作へ接続されている。
