# 追加アバター状態の検証

この文書は初回追加時の履歴です。書く・突っ伏すの原画と顔アップの時間・表情は後から変更されています。現行の検証結果は [状態調整の検証](../state-refinements/VERIFICATION.md) を参照してください。

2026-09-15 / macOS / AIBOUAvatarMotion

## 結果

「書く」「突っ伏す」「ノイズ」「顔アップ」を追加。主状態は7種類、立ち姿差分を含む原画設定は9種類です。

- `./test.sh`: **All 13 tests passed**。既存機能、全方向の状態遷移、約2秒周期のノイズ間隔・継続時間のばらつき、停止・低減・離脱時の解除、顔アップのフェード・上昇・行き過ぎ・跳ね返り・着地を確認。
- `./run.sh --build`: Swift 5 / macOS 13ターゲット、`-warnings-as-errors`で成功。
- `codesign --verify --deep --strict AIBOUAvatarMotion.app`: 成功。
- `git diff --check -- avatar-motion`: 成功。
- 独立したコードレビューで、追加状態に関する具体的な不具合の指摘なし。
- 実アプリを更新版に再起動し、CUAで7つのボタンと「書く」「突っ伏す」「顔アップ」の選択・描画を確認。音声操作は別の行に配置し、状態ボタンが隠れないことを確認。

## 実描画

`close-up/` は読む状態からの遷移を20fpsで1.1秒、`glitch/` は通常の立ち姿に加える周期ノイズを10fpsで6秒取得したSpriteKitの実描画です。各ディレクトリの `metadata.json` が時刻を記録しています。

- [顔アップ到着前・フェード](close-up/close-up-t0.25.png)
- [顔アップの行き過ぎ付近](close-up/close-up-t0.40.png)
- [跳ね返り](close-up/close-up-t0.60.png)
- [着地後](close-up/close-up-t1.00.png)
- [ノイズあり](glitch/glitch-t0.80.png)
- [ノイズ解除](glitch/glitch-t1.20.png)
- [次のノイズ](glitch/glitch-t2.80.png)

`first/` は初回の全原画確認用です。この後、書く位置を机面に合わせて8px下げ、CPU姿勢の接地影を調整し、顔アップを肩の入らない画角へ拡大しました。最終の書く・CPU姿勢はアプリ操作で確認しています。

## 素材と変更範囲

- `Assets/writing.png`: 専用の座り・書きもの原画（透過PNG）。
- `Assets/cpu-rest.png`: 両膝を床につけてCPU上の腕に顔を伏せた専用原画（透過PNG）。
- いずれも内蔵image_genで生成。プロンプトは `artwork/additional-states-prompts.json`。
- `Manifest.swift` / `Assets/rig.json`: 新4状態のID、表示名、配置、顔の画角。
- `AvatarStateMotion.swift` / `ElectricTransition.swift` / `AvatarScene.swift` / `Motion.swift`: 周期ノイズ、飛び込み、光、手元・呼吸の動き。
- `App.swift` / `Capture.swift`: 7状態の操作、顔が動く状態の撮影。
- 新規の外部依存はなし。既存の部屋表示状態・コンポーネント機能の作業を保持。

## 制限

既存方式と同じく1枚の原画の格子変形です。書く動きは手元の反復で、文字を実際に書き進めるものではありません。顔アップは既存の立ち原画と閉眼パッチを拡大しているため、高解像度の専用顔原画に比べると輪郭が柔らかくなります。停止・動きを抑える・キャラクターのみでは、既存の方針に合わせて遷移と周期ノイズを抑制します。

ソースとビルドの識別用ハッシュは `source-sha256.txt`。
