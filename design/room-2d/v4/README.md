# AIBOU 固定カメラ用2D画面素材 v4

黒／白 × 俯瞰／水平の4画面。1672×941px、家具11点の透過PNG、クリックマスク、編集用ORA、アニメーション連番を収録。

## 修正

- **ベッド**：俯瞰のシングルベッドを造形の基準に、水平側を描き直し。幅広い足元フレームを細くし、長い側面を見せる向きに変更。ヘッドボードの傾き、バッテリー領域、寝姿の仮アンカーを更新。
- **電波塔**：両視点の共通床座標を基準に、デスクとCPUの間へ配置。俯瞰側の浮いた接地位置と過大な高さを補正。水平と同じ電子機器の台座を俯瞰にも追加。
- **ファン**：共通の筐体・7枚羽・4本の固定支持部から、両視点の部品を出力。壁上の位置と見かけの比率を調整。筐体・内枠・支持部・軸は固定、羽だけ12フレームで回転。
- **デスク／モニタ**：水平側の横幅を縮め、奥の作業位置へ寄せた。モニタ面、交換用画面、壁ケーブルを一緒に更新し、電波塔の台座を見えるようにした。
- **本棚**：旧ベッドの裏に隠れていた部分を、新しい原画から補修。
- **CPU／外部ケーブル／配線**：v3の脳の刻印、球の点滅、羽だけの回転、消灯ベースの断続的な流光を維持。

## 確認

- `previews/cross-camera-v4.jpg`：黒白・俯瞰水平の比較。
- `previews/horizontal-before-after.jpg`：水平の修正前後。
- `previews/*-motion.webp`：CPU・ファン・配線を合成した24フレームの見本。
- `previews/fan-blades-motion.webp`：4画面のファン拡大見本。
- `previews/*-layers.jpg`：透過境界の確認用。
- `index.html`：素材ビューア。家具クリックと視点・テーマの切替。
- `layout-contract.json`：共通配置、変更理由、投影座標、原画上の補正。
- `validation.json` / `alignment-validation.json`：再合成、マスク、部品、連番、配置の検証。

## 合成

全PNGを原点(0,0)に置き、`manifest.json`のz昇順でsource-over合成する。
背景 → 配線の流光 → 家具。CPU連番はCPU本体の直後、外部ケーブルより前。
ファンは静止合成PNGの代わりに `fixedHousing → bladeFrames[n] → fixedGrille → fixedHub` を描画する。
`effects/manifest.json`の画像パスは原則`effects/`基準。`source`はパッケージルート基準。
ORAは背景＋家具、ファン各4部品の計18レイヤー。

## 制作範囲

固定2D画面の素材です。ネイティブアプリ、バックエンド接続、アバター新規ポーズは含みません。
共通配置図は整合性確認用の基準であり、原画から正確な3Dモデルを復元したものではありません。ファンの中心位置は共通投影を使用し、俯瞰の壁高圧縮には見た目の補正を加えています。ベッド・デスクなどの立体家具は2D原画なので、細部までの厳密な3D再投影ではありません。
家具の裏や脚間には固定配置用の局所背景・陰影を含みます。任意移動やアバターの背後歩行には追加の隠れ面・遮蔽素材が必要です。
ブラウザでの実動作確認は、既存のローカルURL制約により未実施。画像・連番・参照・JavaScript構文を検証しています。

## 再生成

旧v3を保持する。通常の素材利用はこのv4のみで完結する。
生成原画は組み込みimagegenを使用。プロンプトは`repairs/generation-prompts.json`。
再生成は隣接v3を読み込むため、旧版も必要。

1. `scripts/extract_beds.py`（SAM vit_bと重みが必要）
2. `scripts/refine_bed_shelf.py`
3. `scripts/align_layout.py`
4. `scripts/finish_network.py`
5. `scripts/finish_beds.py`（非線形補正は一度だけ適用。再試行は手順2から）
6. `scripts/integrate_v4.py`
7. `scripts/export_previews.py`
8. `scripts/export_alignment_review.py`
9. `scripts/validate_assets.py`、`scripts/validate_alignment.py`
10. `scripts/package_assets.py`

主な依存: Pillow、NumPy、OpenCV。SAM抽出のみPyTorch / Segment Anything。
