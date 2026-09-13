# AIBOU 固定カメラ用2D素材 v5

黒／白 × 俯瞰／水平の4画面。ベッドの配置を修正した版です。

- ベッドの**長辺を左の高い壁へ付け、壁に沿う向き**に変更。枕・ヘッドボードは本棚側、足元は左手前です。
- 幅を広めに戻し、アバターを寝かせる寝面を確保。目安は幅1.4m × 長さ2.1m。寸法は原画制作上の目安であり、3D実測値ではありません。
- 黒白・両視点のベッド透過PNG、クリックマスク、バッテリー表示、寝姿の仮アンカーと寝面の四隅を更新。
- 他の家具・背景・ファン部品・CPU点滅・配線の流光はv4を継承。

## 確認用

- `previews/cross-camera-v5.jpg`：4画面比較。
- `previews/horizontal-before-after.jpg`：v4との水平比較。
- `previews/*-motion.webp`：24フレームの動作見本。
- `previews/*-layers.jpg`：透過レイヤー一覧。
- `manifest.json`：PNG、描画順、クリック領域、アバター仮アンカー。
- `layout-contract.json`：ベッドの向き・幅の方針と寝面の四隅。
- `validation.json` / `alignment-validation.json` / `bed-validation.json`：素材・登録座標・壁沿いの向きを確認した記録。

## 合成方法

1672×941の全レイヤーを原点(0,0)にsource-over合成します。
背景 → 配線の流光 → 家具をz昇順。CPU連番はCPU本体の直後、外部ケーブルより前。
ファンの動画は `fixedHousing → bladeFrames[n] → fixedGrille → fixedHub` の4部品を使用。
`effects/manifest.json`の画像パスは`effects/`基準、`source`のみルート基準。
ORAは背景と家具、ファン各4部品を含む18レイヤーです。

## 範囲

画面素材のみ。アプリ・バックエンド連携・新しいアバターポーズは含みません。
寝姿のアンカーは仮で、実際の寝姿素材に合わせた枕・布団・フレームの遮蔽制作が必要です。
固定配置用なので、家具の脚間などには局所背景・陰影を含みます。任意移動用の完全な隠れ面は未制作です。
2D原画からの編集で、厳密な3D再投影ではありません。ブラウザ実動作検証は既存のローカルURL制約により未実施です。

## 再生成

v4からコピーした状態で実行：

1. `scripts/build_wall_beds.py`（Pillow / NumPy / OpenCV / PyTorch / Segment Anything vit_bと重み）
2. `scripts/refine_wall_beds.py` → `scripts/integrate_v5.py`
3. `scripts/export_previews.py`
4. `scripts/export_alignment_review.py`
5. `scripts/validate_assets.py`、`scripts/validate_alignment.py`、`scripts/validate_beds.py`
6. `scripts/package_assets.py`

ベッド原画は組み込みimagegenで制作。`repairs/*-wall-bed-source.png`と`repairs/wall-bed-prompts.json`に保存。
通常の素材利用はv5フォルダのみで完結します。
