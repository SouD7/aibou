# 授業画面のオフスクリーン描画確認

2026-09-15。制作版の `LessonExperienceView` を SwiftUI `ImageRenderer` で1600×900の論理サイズへ描画した。これは画面レイアウトの確認であり、クリック・キーボード・音声・ネイティブpopoverの操作試験ではない。

## 対象と結果

- 全20授業の導入・実験・未回答の問い・振り返り：80枚。
- 全20授業の誤答後・正答後のフィードバック：40枚。
- 5分野の授業ライブラリ：5枚。
- 計125枚を実際のCore/UIから描画。制作素材の歓迎・説明・喜びの3ポーズを読込確認。
- 7枚の一覧画像で125画面すべての配置を確認。導入、実験、問い、正誤フィードバック、振り返り、5分野の項目で、本文・装置・下部操作の衝突や欠落を認めなかった。
- 長いキャッシュの説明、メモリ圧縮の導入、Dラッチの問い、GPUの誤答フィードバック、最長クラスのboard-town/coolingのラボ接続文、bottleneckの実験台詞は原寸でも確認。吹き出しは髪と重ならず、実験の模型注記はフッター操作より上に収まる。
- 常時アニメーションの検証はこの静止画確認に含まない。

## 指摘と反映

初回確認で、最下部の保存案内が茶色の机帯に灰色文字で載り、読みにくかった。Rootが紙色カプセル背景と濃い文字へ変更した。

その共通表示の変更後は、全125枚の再描画を繰り返さず、以下の3代表画面を最新コードで再描画して視認性と周囲への影響を確認した。その他122枚と一覧画像は共通保存案内のみ変更前である。

- [ライブラリC](captures/lessons-full/library-c.png)
- [メモリの実験](captures/lessons-full/memory-dock-2-experiment.png)
- [メモリの振り返り](captures/lessons-full/memory-dock-4-reflection.png)

## 証跡と再現

画像一覧は [manifest.json](captures/lessons-full/manifest.json)、最終3画面は [manifest-latest.json](captures/lessons-full/manifest-latest.json)。描画ツールは [RenderLessons.swift](../Tools/RenderLessons.swift)。本番のアプリ起動コードを含めず、Core/UIとアバター関連ソースから別の描画実行ファイルをビルドする。

```sh
xcrun swiftc -O -warnings-as-errors -parse-as-library -swift-version 5 \
  -module-cache-path game-lab/.build/module-cache -target arm64-apple-macosx13.0 \
  game-lab/Sources/Core/*.swift game-lab/Sources/UI/*.swift \
  avatar-motion/Sources/{Manifest,Motion,ImageProcessing,AvatarScene,RoomAnimation}.swift \
  game-lab/Tools/RenderLessons.swift \
  -o game-lab/.build/LessonPreview.app/Contents/MacOS/RenderLessons

game-lab/.build/LessonPreview.app/Contents/MacOS/RenderLessons \
  "$PWD/game-lab/QA/captures/lessons-full"
```

`LessonPreview.app/Contents/Resources` は本番GameLabのResourcesへのシンボリックリンク。全授業の状態は専用一時ディレクトリの `LessonStore(saveURL:)` で作り、処理後に削除する。使用者本人の進捗ファイルは読み書きしない。

特定画面だけ更新する場合は、第2引数に画像名をカンマ区切りで渡す。この場合、全体manifestと一覧画像は保持され、部分更新のmanifestを別に残す。

```sh
game-lab/.build/LessonPreview.app/Contents/MacOS/RenderLessons \
  "$PWD/game-lab/QA/captures/lessons-full" \
  library-c,memory-dock-2-experiment,memory-dock-4-reflection
```

## 未検証の範囲

この確認は、ロック中のMacでも実施できる描画確認として行った。実画面の入力、hover、フォーカス、画面サイズ変更、実験部品の全状態、参照資料popover、読み上げは別途実機検証で扱う。
