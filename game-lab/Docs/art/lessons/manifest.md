# 授業用 aibou 差分素材

既存の `game-lab/Art/Exhibition/guide-notebook.png` を本人・衣装・画風の基準に、内蔵 `image_gen` で3枚の静止ポーズを制作した。CLI・外部 API キーは使用していない。歓迎ポーズを追加の参照として、続く2枚の頭の位置・頭身・カメラ距離を揃えた。

| ファイル | 役割 | 表現 | 実寸 |
| --- | --- | --- | --- |
| `game-lab/Art/Lessons/welcome.png` | 話しかけた時・授業選択 | 閉じたノートを両手で持つ（ユーザー採用ポーズ） | 1122×1402 |
| `game-lab/Art/Lessons/explaining.png` | 授業の説明 | ノートを持ち、画面右へ掌を差し出す | 1086×1448 |
| `game-lab/Art/Lessons/celebrating.png` | 理解の確認後・まとめ | 小さなグッドサインと控えめな笑顔 | 1086×1448 |

3枚とも3:4。画像自体は緑背景を含む。制作時は単色 `#00FF00` を指定したが、生成結果の画素値には微小な揺れがある。UIは既存の `ImageProcessing.removeGreenScreen` で背景を除去し、固定位置・固定サイズで静止差分を切り替えること。上半身の揺れ、顔の移動、口パク用アニメーションは含めていない。ロビーの既存の瞬きに変更はない。

## 生成元

- welcome: `/Users/fujishima/.codex/generated_images/01a0a0ef-8675-7390-94a5-b11585df590c/exec-448ae299-6b6b-475e-abb9-08779d73cf24.png`
- explaining: `/Users/fujishima/.codex/generated_images/01a0a0ef-8675-7390-94a5-b11585df590c/exec-f5d1046f-1e87-43a8-bd33-3e3bb7eca8ee.png`
- celebrating: `/Users/fujishima/.codex/generated_images/01a0a0ef-8675-7390-94a5-b11585df590c/exec-02144baf-f2dc-4fd1-aec2-a8e764e77d19.png`

全プロンプトと参照は `prompts.json` に保存。プロジェクト用ファイルへコピー済みであり、生成元フォルダーへの依存はない。

## 確認

- 3枚を目視確認：黒いボブ、前髪、青い目、白とシアンの髪飾り、ヘッドホン、白いハイネック、黒いシアンラインのパーカーが維持され、同じ本人に見える。
- 髪と手の欠け、余分な手足、不要な文字・装飾がないことを確認。説明ポーズは掌が右端寄りなので、UIでは画像全体を aspect-fit し、横方向を切り取らないこと。
- 本番で使用する `avatar-motion/Sources/ImageProcessing.swift` を直接コンパイルし、クリーム背景上に実描画した `chromakey-preview.png` を確認。背景の緑の残り、目立つ緑色の縁取り、シアンの衣装が抜ける問題は見られなかった。
- 解像度・SHA-256・四隅のRGB・緑背景比率は `asset-inspection.json` に記録。
- `preview.swift` は上記の本番クロマキー処理による確認用で、ゲームのUIコードは変更していない。

プレビュー再生成:

```sh
swiftc output/lessons-art/preview.swift avatar-motion/Sources/ImageProcessing.swift -o output/lessons-art/preview
output/lessons-art/preview
```

## 2026-09-15 歓迎ポーズの差し替え

ユーザー採用の `output/guide-pose-alternatives-v1/02-notebook.png` を基準に、内蔵画像生成で緑背景の表示用素材を制作し welcome.png を更新。説明・まとめのポーズは維持。学習導入と各ミニゲーム開始時は共通の welcome を参照するため一括反映。生成記録は `output/guide-pose-alternatives-v1/adoption.json`。
