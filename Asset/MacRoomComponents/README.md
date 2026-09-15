# Mac版の部屋コンポーネント

元画像: `source-room.png`（avatar-motion/Assets/RoomAnimation/frame-000.png のコピー）。
imagegenによる背景分離・隠れた部分の補完。元画像と完全なピクセル一致ではありません。
Mac/Windowsアプリの実装への組み込みはまだ行っていません。

## 基本素材

- background.png: 家具・機器を除去し、壁と床を補完した背景
- bed.png: ベッド・電池5目盛り点灯
- bookshelf.png: 現在の本の量の本棚
- desk.png: 通常のデスク（小物を含む）
- chair.png: 椅子
- display.png: モニター・壁の制御ボックス・配線
- fan-1.png / fan-2.png: 左右のファン
- clock.png: 時計
- network.png: 電波塔と台
- compute.png: 演算ユニット本体
- external.png: 外部接続ホースと床の接続部

## 状態差分（本体ごと置き換えるPNG）

- bookshelf-empty.png: ほぼ空の本棚
- bed-medium.png: 電池2目盛り点灯（青）
- bed-low.png: 電池1目盛り点灯（赤）
- desk-stacked.png: 書類が山積みのデスク

ベッドの残量はヘッドボードと側面の大きな残量ランプの両方で表現。低残量は1目盛りだけ赤く点灯し、アイコン全体を赤い枠で囲みません。その他の細い装飾灯は変更していません。
今回の通常素材・状態差分は背景を除いて透過PNGです。

## 配置とプレビュー

manifest.json の canvas は 1672×941。画像は余白を含むため、単純に全画面に重ねず、sourceRect（画像内の家具領域）をtargetRect（部屋内の配置領域）へ対応させて描画します。矩形は左上原点の [x,y,width,height]。
状態差分は同じ基本素材の変換を使い、書類などの領域がsourceRectをはみ出す場合もクリップしないでください。variantsは通常版と同時表示せず切り替えます。zの小さい順に描画します。
配置値は元画像を参考にした近似です。生成に伴う形状の変化があり、旧クリック領域や状態描画との接続には調整が必要です。

- contact-sheet.png: 全素材と状態差分の一覧
- preview-normal.png: 通常版の配置確認
- preview-states.png: ほぼ空の本棚・低残量・山積み書類の配置確認
- bed-perspective-v2-cutout.png: 先に作成した別画角のベッド切り抜き（この部屋のmanifestには未使用）
- generation-prompts.json / state-prompts.json: 内蔵imagegenに渡した生成指示
- prepare-preview.cjs: sharpによる透過検査・配置メタデータ・確認画像の生成。別環境ではSHARP_MODULEにsharpのモジュールパスを指定。

元ファイルは削除せず、このフォルダーに集約してコピーしています。起動画面素材や以前のWindows用素材は対象外です。

## 背景の電流アニメーション

BackgroundCurrent/ に新しい背景連番PNG、光だけの透過PNG、sequence.json、preview.htmlを保存しています。詳細は同フォルダーのREADME.md参照。
