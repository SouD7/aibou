# AIBOU統合版の作成に用いたファイル一覧

記録日時: 2026-09-15T10:52:30+09:00。ブランチ: `codex/integrated-aibou-app`。基点: `19202d55e91efb3f3131442f7adb4653a26c54a2`。

ボタンを約1.5倍に拡大し、PR11の初回・再レビュー指摘を修正し、部屋上部の選択ボックスを削除した版までを対象とする。過去のQAログは、それぞれの検証時点の記録として保持する。ファイル名はリポジトリルートからの相対パス。新規作成・既存変更・既存再利用は記録時点のGit差分に基づく。

## 集計

| 分類 | ファイル数 |
| --- | --- |
| Swiftソース（新規6 + AvatarMotion 17 + Monitor 22） | 45 |
| 同梱する画像・音声・素材定義 | 140 |
| 素材フォルダに付随してコピーされるmacOS管理ファイル | 1 |
| 同梱するアプリ設定・プライバシー宣言 | 2 |
| ビルド入力・コピー対象 合計 | 188 |
| ビルド・テストスクリプト | 4 |
| テスト用Swiftソース | 24 |
| 設計・利用説明 | 2 |
| 検証記録・ログ・ソースハッシュ | 14 |
| 本一覧に記録したファイル総数 | 232 |

## ビルドへの取り込み方

`integrated/run.sh` は3ディレクトリの `Sources/*.swift` を全件コンパイルする。既存の2つのApp.swiftを含め、`AIBOU_INTEGRATED` 条件で統合用のエントリーポイントだけを有効にする。素材は `avatar-motion/Assets/` をディレクトリごとコピーする。「コンパイル・同梱される」ことと「通常起動時に必ず実行・表示される」ことは区別する。

既存の2つの `.app` を読み込んだり結合したりする方式ではない。共有ソースから `integrated/AIBOU.app` を生成する。

## 新規作成した統合用ソース

| ファイル | 扱い | 用途 |
| --- | --- | --- |
| [integrated/Sources/HardwareRoomPolicy.swift](Sources/HardwareRoomPolicy.swift) | 新規作成 | 実測値の閾値判定、家具の表示状態、警告、アバター候補、概要指標の対応 |
| [integrated/Sources/IntegratedApp.swift](Sources/IntegratedApp.swift) | 新規作成 | 統合アプリの起動・終了、全画面ウィンドウ、終了時の監視停止と保存待ち |
| [integrated/Sources/IntegratedStore.swift](Sources/IntegratedStore.swift) | 新規作成 | Avatar・Monitor・相談の接続、実測更新、30秒タイマー、各モードの切替 |
| [integrated/Sources/IntegratedWindow.swift](Sources/IntegratedWindow.swift) | 新規作成 | 部屋の統合UI、拡大したメニュー・相談ボタン、概要・詳細・接続案内、macOSメニューバーの家具選択、モニター表示中の相談ビュー切替 |
| [integrated/Sources/RoomConsultationView.swift](Sources/RoomConsultationView.swift) | 新規作成 | 部屋下部の質問・回答表示、送信確認、追加質問、下書き復元、モニター往復時の表示再生成、エラー回復 |
| [integrated/Sources/RoomSession.swift](Sources/RoomSession.swift) | 新規作成 | デモ／相談のセッション状態、次回の姿勢選択時刻、警告の解除履歴 |

## AvatarMotionから共有したソース

| ファイル | 扱い | 用途 |
| --- | --- | --- |
| [avatar-motion/Sources/App.swift](../avatar-motion/Sources/App.swift) | 既存を変更 | 既存の状態管理とデモ操作UIを共有。統合時のエントリーポイント切替、操作枠の表示切替、ウィンドウ通知を修正 |
| [avatar-motion/Sources/Audio.swift](../avatar-motion/Sources/Audio.swift) | 既存を再利用 | 音声の再生と音量からの口の動き |
| [avatar-motion/Sources/AvatarScene.swift](../avatar-motion/Sources/AvatarScene.swift) | 既存を変更 | 部屋とアバターのSpriteKit描画、姿勢遷移、家具選択。警告クリックのコールバックを追加 |
| [avatar-motion/Sources/AvatarStateMotion.swift](../avatar-motion/Sources/AvatarStateMotion.swift) | 既存を再利用 | ノイズや顔アップなど姿勢別の動作タイミング |
| [avatar-motion/Sources/Capture.swift](../avatar-motion/Sources/Capture.swift) | 既存を再利用 | 既存のキャプチャ・QA補助（ビルド対象。通常起動でキャプチャは実行しない） |
| [avatar-motion/Sources/ElectricTransition.swift](../avatar-motion/Sources/ElectricTransition.swift) | 既存を再利用 | 姿勢切替時の電気エフェクト |
| [avatar-motion/Sources/ImageProcessing.swift](../avatar-motion/Sources/ImageProcessing.swift) | 既存を再利用 | 透過処理、画像の切り出しと境界処理 |
| [avatar-motion/Sources/InteractiveRoomView.swift](../avatar-motion/Sources/InteractiveRoomView.swift) | 既存を再利用 | SwiftUIとSKViewの接続、マウス・ホバー・クリック入力 |
| [avatar-motion/Sources/Manifest.swift](../avatar-motion/Sources/Manifest.swift) | 既存を再利用 | 姿勢ID、画像・位置・サイズなどのリグ定義の読込 |
| [avatar-motion/Sources/Motion.swift](../avatar-motion/Sources/Motion.swift) | 既存を再利用 | アバターの基本的な動きの計算 |
| [avatar-motion/Sources/RoomAnimation.swift](../avatar-motion/Sources/RoomAnimation.swift) | 既存を再利用 | 部屋の連番アニメーションの読込と再生 |
| [avatar-motion/Sources/RoomComponentDetail.swift](../avatar-motion/Sources/RoomComponentDetail.swift) | 既存を再利用 | デモで使用する家具説明と表示状態の編集UI |
| [avatar-motion/Sources/RoomComponents.swift](../avatar-motion/Sources/RoomComponents.swift) | 既存を再利用 | 家具のカタログ、クリック領域、選択・ホバーの表示 |
| [avatar-motion/Sources/RoomStateArtwork.swift](../avatar-motion/Sources/RoomStateArtwork.swift) | 既存を再利用 | 点灯数など、家具の状態を示す追加描画 |
| [avatar-motion/Sources/RoomStateRenderer.swift](../avatar-motion/Sources/RoomStateRenderer.swift) | 既存を再利用 | 家具の状態別画像とエフェクトの描画 |
| [avatar-motion/Sources/RoomVisualState.swift](../avatar-motion/Sources/RoomVisualState.swift) | 既存を再利用 | 本棚・メモリ・ファン・バッテリーなどの表示状態と選択肢 |
| [avatar-motion/Sources/RoomWarnings.swift](../avatar-motion/Sources/RoomWarnings.swift) | 既存を再利用 | 警告データと家具上の警告マークの描画・判定 |

## Monitorから共有したソース

| ファイル | 扱い | 用途 |
| --- | --- | --- |
| [monitor/Sources/AdditionalCollectors.swift](../monitor/Sources/AdditionalCollectors.swift) | 既存を再利用 | 追加のネットワーク・電力等の計測 |
| [monitor/Sources/App.swift](../monitor/Sources/App.swift) | 既存を変更 | 既存Monitorのカード・表・グラフと全タブUI。統合時のエントリーポイント切替、サイドバーなしの固定表示を追加 |
| [monitor/Sources/ApplicationDetailView.swift](../monitor/Sources/ApplicationDetailView.swift) | 既存を再利用 | アプリ詳細画面 |
| [monitor/Sources/ApplicationLauncher.swift](../monitor/Sources/ApplicationLauncher.swift) | 既存を再利用 | アプリの列挙と起動処理 |
| [monitor/Sources/ApplicationLauncherView.swift](../monitor/Sources/ApplicationLauncherView.swift) | 既存を再利用 | アプリ一覧・検索・起動UI |
| [monitor/Sources/ApplicationStorage.swift](../monitor/Sources/ApplicationStorage.swift) | 既存を再利用 | アプリに関連するストレージ情報 |
| [monitor/Sources/ApplicationUsage.swift](../monitor/Sources/ApplicationUsage.swift) | 既存を再利用 | アプリ単位の使用量の集計 |
| [monitor/Sources/CodexRPC.swift](../monitor/Sources/CodexRPC.swift) | 既存を再利用 | 相談用Codex CLIプロセスとRPC通信、接続環境 |
| [monitor/Sources/Common.swift](../monitor/Sources/Common.swift) | 既存を再利用 | MonitorTab、Metric、PanelReadingなどの共通データ型 |
| [monitor/Sources/ConsultationModel.swift](../monitor/Sources/ConsultationModel.swift) | 既存を再利用 | ChatGPT認証状態、会話、送受信、停止・再接続の管理 |
| [monitor/Sources/ConsultationPayload.swift](../monitor/Sources/ConsultationPayload.swift) | 既存を再利用 | 送信内容と回答長、添付する観測情報の組立 |
| [monitor/Sources/ConsultationView.swift](../monitor/Sources/ConsultationView.swift) | 既存を再利用 | モニター内の相談タブ、接続と回答長の設定UI |
| [monitor/Sources/CoreSampler.swift](../monitor/Sources/CoreSampler.swift) | 既存を再利用 | CPU・メモリ・クロック・ストレージ・ネットワーク等の基本計測 |
| [monitor/Sources/DeviceSampler.swift](../monitor/Sources/DeviceSampler.swift) | 既存を再利用 | バッテリー・熱状態・ディスプレイ・外部機器等の列挙 |
| [monitor/Sources/DiagnosticCatalog.swift](../monitor/Sources/DiagnosticCatalog.swift) | 既存を再利用 | 状態チェックの項目・説明データ |
| [monitor/Sources/DiagnosticSelection.swift](../monitor/Sources/DiagnosticSelection.swift) | 既存を再利用 | 症状・原因候補の選択と表示状態 |
| [monitor/Sources/Diagnostics.swift](../monitor/Sources/Diagnostics.swift) | 既存を再利用 | 観測値に基づく状態チェックの判定 |
| [monitor/Sources/DiagnosticsView.swift](../monitor/Sources/DiagnosticsView.swift) | 既存を再利用 | 状態チェックUI（メンテナンスで再利用） |
| [monitor/Sources/History.swift](../monitor/Sources/History.swift) | 既存を再利用 | 監視履歴の蓄積・保存・読込 |
| [monitor/Sources/MonitorStore.swift](../monitor/Sources/MonitorStore.swift) | 既存を再利用 | 監視の実行、計測結果・履歴・スキャン等の状態管理 |
| [monitor/Sources/Observations.swift](../monitor/Sources/Observations.swift) | 既存を再利用 | 観測結果の共通スナップショット定義 |
| [monitor/Sources/StorageScanner.swift](../monitor/Sources/StorageScanner.swift) | 既存を再利用 | ストレージのスキャンとファイルツリーの処理 |

## アプリ設定とビルド・テスト手順

| ファイル | 扱い | 用途 |
| --- | --- | --- |
| [integrated/Info.plist](Info.plist) | 新規作成 | 統合アプリの名前・識別子・実行ファイル・OS要件・利用目的 |
| [monitor/PrivacyInfo.xcprivacy](../monitor/PrivacyInfo.xcprivacy) | 既存を再利用 | 既存Monitorから共有するプライバシー宣言 |
| [integrated/run.sh](run.sh) | 新規作成 | 統合アプリのコンパイル・素材コピー・署名・起動 |
| [integrated/test.sh](test.sh) | 新規作成 | 統合版の4テストスイートの実行 |
| [avatar-motion/test.sh](../avatar-motion/test.sh) | 既存を再利用 | 既存AvatarMotionの回帰テスト実行 |
| [monitor/test.sh](../monitor/test.sh) | 既存を再利用 | 既存Monitorの回帰テスト実行 |

## 再利用した素材の全一覧

以下の全素材は既存の `avatar-motion/Assets/` を再利用している。統合用に新しく画像・音声を生成していない。各パスの `avatar-motion/Assets/` 以降が、そのまま `integrated/AIBOU.app/Contents/Resources/Assets/` 以下の同梱先になる。

### ルート（17ファイル）

| ファイル | 用途 |
| --- | --- |
| [avatar-motion/Assets/.DS_Store](../avatar-motion/Assets/.DS_Store) | macOSのフォルダ管理メタデータ。素材と一緒にコピーされるがアプリ処理には未使用 |
| [avatar-motion/Assets/cpu-rest-relaxed.png](../avatar-motion/Assets/cpu-rest-relaxed.png) | アバターの姿勢・表情画像 |
| [avatar-motion/Assets/cpu-rest.png](../avatar-motion/Assets/cpu-rest.png) | アバターの姿勢・表情画像 |
| [avatar-motion/Assets/reading.png](../avatar-motion/Assets/reading.png) | アバターの姿勢・表情画像 |
| [avatar-motion/Assets/rig.json](../avatar-motion/Assets/rig.json) | アバターの画像・配置・顔パーツなどの定義 |
| [avatar-motion/Assets/room-components.json](../avatar-motion/Assets/room-components.json) | 家具の説明とクリック領域の定義 |
| [avatar-motion/Assets/room.png](../avatar-motion/Assets/room.png) | 部屋の静止背景 |
| [avatar-motion/Assets/sample.aiff](../avatar-motion/Assets/sample.aiff) | デモのサンプル音声 |
| [avatar-motion/Assets/sleeping.png](../avatar-motion/Assets/sleeping.png) | アバターの姿勢・表情画像 |
| [avatar-motion/Assets/standing-back-hands.png](../avatar-motion/Assets/standing-back-hands.png) | アバターの姿勢・表情画像 |
| [avatar-motion/Assets/standing-blink.png](../avatar-motion/Assets/standing-blink.png) | アバターの姿勢・表情画像 |
| [avatar-motion/Assets/standing-front-hands.png](../avatar-motion/Assets/standing-front-hands.png) | アバターの姿勢・表情画像 |
| [avatar-motion/Assets/standing-smile-crescent.png](../avatar-motion/Assets/standing-smile-crescent.png) | アバターの姿勢・表情画像 |
| [avatar-motion/Assets/standing-smile.png](../avatar-motion/Assets/standing-smile.png) | アバターの姿勢・表情画像 |
| [avatar-motion/Assets/standing.png](../avatar-motion/Assets/standing.png) | アバターの姿勢・表情画像 |
| [avatar-motion/Assets/writing-seated.png](../avatar-motion/Assets/writing-seated.png) | アバターの姿勢・表情画像 |
| [avatar-motion/Assets/writing.png](../avatar-motion/Assets/writing.png) | アバターの姿勢・表情画像 |

### RoomAnimation（25ファイル）

| ファイル | 用途 |
| --- | --- |
| [avatar-motion/Assets/RoomAnimation/frame-000.png](../avatar-motion/Assets/RoomAnimation/frame-000.png) | 部屋背景の連番フレーム・再生定義 |
| [avatar-motion/Assets/RoomAnimation/frame-001.png](../avatar-motion/Assets/RoomAnimation/frame-001.png) | 部屋背景の連番フレーム・再生定義 |
| [avatar-motion/Assets/RoomAnimation/frame-002.png](../avatar-motion/Assets/RoomAnimation/frame-002.png) | 部屋背景の連番フレーム・再生定義 |
| [avatar-motion/Assets/RoomAnimation/frame-003.png](../avatar-motion/Assets/RoomAnimation/frame-003.png) | 部屋背景の連番フレーム・再生定義 |
| [avatar-motion/Assets/RoomAnimation/frame-004.png](../avatar-motion/Assets/RoomAnimation/frame-004.png) | 部屋背景の連番フレーム・再生定義 |
| [avatar-motion/Assets/RoomAnimation/frame-005.png](../avatar-motion/Assets/RoomAnimation/frame-005.png) | 部屋背景の連番フレーム・再生定義 |
| [avatar-motion/Assets/RoomAnimation/frame-006.png](../avatar-motion/Assets/RoomAnimation/frame-006.png) | 部屋背景の連番フレーム・再生定義 |
| [avatar-motion/Assets/RoomAnimation/frame-007.png](../avatar-motion/Assets/RoomAnimation/frame-007.png) | 部屋背景の連番フレーム・再生定義 |
| [avatar-motion/Assets/RoomAnimation/frame-008.png](../avatar-motion/Assets/RoomAnimation/frame-008.png) | 部屋背景の連番フレーム・再生定義 |
| [avatar-motion/Assets/RoomAnimation/frame-009.png](../avatar-motion/Assets/RoomAnimation/frame-009.png) | 部屋背景の連番フレーム・再生定義 |
| [avatar-motion/Assets/RoomAnimation/frame-010.png](../avatar-motion/Assets/RoomAnimation/frame-010.png) | 部屋背景の連番フレーム・再生定義 |
| [avatar-motion/Assets/RoomAnimation/frame-011.png](../avatar-motion/Assets/RoomAnimation/frame-011.png) | 部屋背景の連番フレーム・再生定義 |
| [avatar-motion/Assets/RoomAnimation/frame-012.png](../avatar-motion/Assets/RoomAnimation/frame-012.png) | 部屋背景の連番フレーム・再生定義 |
| [avatar-motion/Assets/RoomAnimation/frame-013.png](../avatar-motion/Assets/RoomAnimation/frame-013.png) | 部屋背景の連番フレーム・再生定義 |
| [avatar-motion/Assets/RoomAnimation/frame-014.png](../avatar-motion/Assets/RoomAnimation/frame-014.png) | 部屋背景の連番フレーム・再生定義 |
| [avatar-motion/Assets/RoomAnimation/frame-015.png](../avatar-motion/Assets/RoomAnimation/frame-015.png) | 部屋背景の連番フレーム・再生定義 |
| [avatar-motion/Assets/RoomAnimation/frame-016.png](../avatar-motion/Assets/RoomAnimation/frame-016.png) | 部屋背景の連番フレーム・再生定義 |
| [avatar-motion/Assets/RoomAnimation/frame-017.png](../avatar-motion/Assets/RoomAnimation/frame-017.png) | 部屋背景の連番フレーム・再生定義 |
| [avatar-motion/Assets/RoomAnimation/frame-018.png](../avatar-motion/Assets/RoomAnimation/frame-018.png) | 部屋背景の連番フレーム・再生定義 |
| [avatar-motion/Assets/RoomAnimation/frame-019.png](../avatar-motion/Assets/RoomAnimation/frame-019.png) | 部屋背景の連番フレーム・再生定義 |
| [avatar-motion/Assets/RoomAnimation/frame-020.png](../avatar-motion/Assets/RoomAnimation/frame-020.png) | 部屋背景の連番フレーム・再生定義 |
| [avatar-motion/Assets/RoomAnimation/frame-021.png](../avatar-motion/Assets/RoomAnimation/frame-021.png) | 部屋背景の連番フレーム・再生定義 |
| [avatar-motion/Assets/RoomAnimation/frame-022.png](../avatar-motion/Assets/RoomAnimation/frame-022.png) | 部屋背景の連番フレーム・再生定義 |
| [avatar-motion/Assets/RoomAnimation/frame-023.png](../avatar-motion/Assets/RoomAnimation/frame-023.png) | 部屋背景の連番フレーム・再生定義 |
| [avatar-motion/Assets/RoomAnimation/manifest.json](../avatar-motion/Assets/RoomAnimation/manifest.json) | 部屋背景の連番フレーム・再生定義 |

### RoomStates（74ファイル）

| ファイル | 用途 |
| --- | --- |
| [avatar-motion/Assets/RoomStates/book-horizontal.png](../avatar-motion/Assets/RoomStates/book-horizontal.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/book-lower-right.png](../avatar-motion/Assets/RoomStates/book-lower-right.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/book-lower-white.png](../avatar-motion/Assets/RoomStates/book-lower-white.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/book-lower.png](../avatar-motion/Assets/RoomStates/book-lower.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/book-middle-short.png](../avatar-motion/Assets/RoomStates/book-middle-short.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/book-middle-white.png](../avatar-motion/Assets/RoomStates/book-middle-white.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/book-middle.png](../avatar-motion/Assets/RoomStates/book-middle.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/book-short.png](../avatar-motion/Assets/RoomStates/book-short.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/book-small.png](../avatar-motion/Assets/RoomStates/book-small.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/book-tall.png](../avatar-motion/Assets/RoomStates/book-tall.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/book-white.png](../avatar-motion/Assets/RoomStates/book-white.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/chair.png](../avatar-motion/Assets/RoomStates/chair.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/compute-00.png](../avatar-motion/Assets/RoomStates/compute-00.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/compute-01.png](../avatar-motion/Assets/RoomStates/compute-01.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/compute-02.png](../avatar-motion/Assets/RoomStates/compute-02.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/compute-03.png](../avatar-motion/Assets/RoomStates/compute-03.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/compute-04.png](../avatar-motion/Assets/RoomStates/compute-04.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/compute-05.png](../avatar-motion/Assets/RoomStates/compute-05.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/compute-06.png](../avatar-motion/Assets/RoomStates/compute-06.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/compute-07.png](../avatar-motion/Assets/RoomStates/compute-07.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/compute-08.png](../avatar-motion/Assets/RoomStates/compute-08.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/compute-09.png](../avatar-motion/Assets/RoomStates/compute-09.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/compute-10.png](../avatar-motion/Assets/RoomStates/compute-10.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/compute-11.png](../avatar-motion/Assets/RoomStates/compute-11.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-1-00.png](../avatar-motion/Assets/RoomStates/fan-1-00.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-1-01.png](../avatar-motion/Assets/RoomStates/fan-1-01.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-1-02.png](../avatar-motion/Assets/RoomStates/fan-1-02.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-1-03.png](../avatar-motion/Assets/RoomStates/fan-1-03.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-1-04.png](../avatar-motion/Assets/RoomStates/fan-1-04.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-1-05.png](../avatar-motion/Assets/RoomStates/fan-1-05.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-1-06.png](../avatar-motion/Assets/RoomStates/fan-1-06.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-1-07.png](../avatar-motion/Assets/RoomStates/fan-1-07.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-1-08.png](../avatar-motion/Assets/RoomStates/fan-1-08.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-1-09.png](../avatar-motion/Assets/RoomStates/fan-1-09.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-1-10.png](../avatar-motion/Assets/RoomStates/fan-1-10.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-1-11.png](../avatar-motion/Assets/RoomStates/fan-1-11.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-1-fast-00.png](../avatar-motion/Assets/RoomStates/fan-1-fast-00.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-1-fast-01.png](../avatar-motion/Assets/RoomStates/fan-1-fast-01.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-1-fast-02.png](../avatar-motion/Assets/RoomStates/fan-1-fast-02.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-1-fast-03.png](../avatar-motion/Assets/RoomStates/fan-1-fast-03.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-1-fast-04.png](../avatar-motion/Assets/RoomStates/fan-1-fast-04.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-1-fast-05.png](../avatar-motion/Assets/RoomStates/fan-1-fast-05.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-1-fast-06.png](../avatar-motion/Assets/RoomStates/fan-1-fast-06.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-1-fast-07.png](../avatar-motion/Assets/RoomStates/fan-1-fast-07.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-1-fast-08.png](../avatar-motion/Assets/RoomStates/fan-1-fast-08.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-1-fast-09.png](../avatar-motion/Assets/RoomStates/fan-1-fast-09.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-1-fast-10.png](../avatar-motion/Assets/RoomStates/fan-1-fast-10.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-1-fast-11.png](../avatar-motion/Assets/RoomStates/fan-1-fast-11.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-2-00.png](../avatar-motion/Assets/RoomStates/fan-2-00.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-2-01.png](../avatar-motion/Assets/RoomStates/fan-2-01.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-2-02.png](../avatar-motion/Assets/RoomStates/fan-2-02.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-2-03.png](../avatar-motion/Assets/RoomStates/fan-2-03.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-2-04.png](../avatar-motion/Assets/RoomStates/fan-2-04.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-2-05.png](../avatar-motion/Assets/RoomStates/fan-2-05.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-2-06.png](../avatar-motion/Assets/RoomStates/fan-2-06.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-2-07.png](../avatar-motion/Assets/RoomStates/fan-2-07.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-2-08.png](../avatar-motion/Assets/RoomStates/fan-2-08.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-2-09.png](../avatar-motion/Assets/RoomStates/fan-2-09.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-2-10.png](../avatar-motion/Assets/RoomStates/fan-2-10.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-2-11.png](../avatar-motion/Assets/RoomStates/fan-2-11.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-2-fast-00.png](../avatar-motion/Assets/RoomStates/fan-2-fast-00.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-2-fast-01.png](../avatar-motion/Assets/RoomStates/fan-2-fast-01.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-2-fast-02.png](../avatar-motion/Assets/RoomStates/fan-2-fast-02.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-2-fast-03.png](../avatar-motion/Assets/RoomStates/fan-2-fast-03.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-2-fast-04.png](../avatar-motion/Assets/RoomStates/fan-2-fast-04.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-2-fast-05.png](../avatar-motion/Assets/RoomStates/fan-2-fast-05.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-2-fast-06.png](../avatar-motion/Assets/RoomStates/fan-2-fast-06.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-2-fast-07.png](../avatar-motion/Assets/RoomStates/fan-2-fast-07.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-2-fast-08.png](../avatar-motion/Assets/RoomStates/fan-2-fast-08.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-2-fast-09.png](../avatar-motion/Assets/RoomStates/fan-2-fast-09.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-2-fast-10.png](../avatar-motion/Assets/RoomStates/fan-2-fast-10.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/fan-2-fast-11.png](../avatar-motion/Assets/RoomStates/fan-2-fast-11.png) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/manifest.json](../avatar-motion/Assets/RoomStates/manifest.json) | 家具の状態別素材・配置定義 |
| [avatar-motion/Assets/RoomStates/network-lamp.png](../avatar-motion/Assets/RoomStates/network-lamp.png) | 家具の状態別素材・配置定義 |

### WritingBackdrop（25ファイル）

| ファイル | 用途 |
| --- | --- |
| [avatar-motion/Assets/WritingBackdrop/frame-000.png](../avatar-motion/Assets/WritingBackdrop/frame-000.png) | 書く姿勢の背面・前景合成用フレームと定義 |
| [avatar-motion/Assets/WritingBackdrop/frame-001.png](../avatar-motion/Assets/WritingBackdrop/frame-001.png) | 書く姿勢の背面・前景合成用フレームと定義 |
| [avatar-motion/Assets/WritingBackdrop/frame-002.png](../avatar-motion/Assets/WritingBackdrop/frame-002.png) | 書く姿勢の背面・前景合成用フレームと定義 |
| [avatar-motion/Assets/WritingBackdrop/frame-003.png](../avatar-motion/Assets/WritingBackdrop/frame-003.png) | 書く姿勢の背面・前景合成用フレームと定義 |
| [avatar-motion/Assets/WritingBackdrop/frame-004.png](../avatar-motion/Assets/WritingBackdrop/frame-004.png) | 書く姿勢の背面・前景合成用フレームと定義 |
| [avatar-motion/Assets/WritingBackdrop/frame-005.png](../avatar-motion/Assets/WritingBackdrop/frame-005.png) | 書く姿勢の背面・前景合成用フレームと定義 |
| [avatar-motion/Assets/WritingBackdrop/frame-006.png](../avatar-motion/Assets/WritingBackdrop/frame-006.png) | 書く姿勢の背面・前景合成用フレームと定義 |
| [avatar-motion/Assets/WritingBackdrop/frame-007.png](../avatar-motion/Assets/WritingBackdrop/frame-007.png) | 書く姿勢の背面・前景合成用フレームと定義 |
| [avatar-motion/Assets/WritingBackdrop/frame-008.png](../avatar-motion/Assets/WritingBackdrop/frame-008.png) | 書く姿勢の背面・前景合成用フレームと定義 |
| [avatar-motion/Assets/WritingBackdrop/frame-009.png](../avatar-motion/Assets/WritingBackdrop/frame-009.png) | 書く姿勢の背面・前景合成用フレームと定義 |
| [avatar-motion/Assets/WritingBackdrop/frame-010.png](../avatar-motion/Assets/WritingBackdrop/frame-010.png) | 書く姿勢の背面・前景合成用フレームと定義 |
| [avatar-motion/Assets/WritingBackdrop/frame-011.png](../avatar-motion/Assets/WritingBackdrop/frame-011.png) | 書く姿勢の背面・前景合成用フレームと定義 |
| [avatar-motion/Assets/WritingBackdrop/frame-012.png](../avatar-motion/Assets/WritingBackdrop/frame-012.png) | 書く姿勢の背面・前景合成用フレームと定義 |
| [avatar-motion/Assets/WritingBackdrop/frame-013.png](../avatar-motion/Assets/WritingBackdrop/frame-013.png) | 書く姿勢の背面・前景合成用フレームと定義 |
| [avatar-motion/Assets/WritingBackdrop/frame-014.png](../avatar-motion/Assets/WritingBackdrop/frame-014.png) | 書く姿勢の背面・前景合成用フレームと定義 |
| [avatar-motion/Assets/WritingBackdrop/frame-015.png](../avatar-motion/Assets/WritingBackdrop/frame-015.png) | 書く姿勢の背面・前景合成用フレームと定義 |
| [avatar-motion/Assets/WritingBackdrop/frame-016.png](../avatar-motion/Assets/WritingBackdrop/frame-016.png) | 書く姿勢の背面・前景合成用フレームと定義 |
| [avatar-motion/Assets/WritingBackdrop/frame-017.png](../avatar-motion/Assets/WritingBackdrop/frame-017.png) | 書く姿勢の背面・前景合成用フレームと定義 |
| [avatar-motion/Assets/WritingBackdrop/frame-018.png](../avatar-motion/Assets/WritingBackdrop/frame-018.png) | 書く姿勢の背面・前景合成用フレームと定義 |
| [avatar-motion/Assets/WritingBackdrop/frame-019.png](../avatar-motion/Assets/WritingBackdrop/frame-019.png) | 書く姿勢の背面・前景合成用フレームと定義 |
| [avatar-motion/Assets/WritingBackdrop/frame-020.png](../avatar-motion/Assets/WritingBackdrop/frame-020.png) | 書く姿勢の背面・前景合成用フレームと定義 |
| [avatar-motion/Assets/WritingBackdrop/frame-021.png](../avatar-motion/Assets/WritingBackdrop/frame-021.png) | 書く姿勢の背面・前景合成用フレームと定義 |
| [avatar-motion/Assets/WritingBackdrop/frame-022.png](../avatar-motion/Assets/WritingBackdrop/frame-022.png) | 書く姿勢の背面・前景合成用フレームと定義 |
| [avatar-motion/Assets/WritingBackdrop/frame-023.png](../avatar-motion/Assets/WritingBackdrop/frame-023.png) | 書く姿勢の背面・前景合成用フレームと定義 |
| [avatar-motion/Assets/WritingBackdrop/manifest.json](../avatar-motion/Assets/WritingBackdrop/manifest.json) | 書く姿勢の背面・前景合成用フレームと定義 |

## 検証に使用したテストソース

| ファイル | 扱い | 用途 |
| --- | --- | --- |
| [integrated/Tests/AvatarWindowEventTests.swift](Tests/AvatarWindowEventTests.swift) | 新規作成 | 統合機能のテスト |
| [integrated/Tests/ConsultationIntegrationTests.swift](Tests/ConsultationIntegrationTests.swift) | 新規作成 | 統合機能のテスト |
| [integrated/Tests/HardwareRoomPolicyTests.swift](Tests/HardwareRoomPolicyTests.swift) | 新規作成 | 統合機能のテスト |
| [integrated/Tests/RoomSessionTests.swift](Tests/RoomSessionTests.swift) | 新規作成 | 統合機能のテスト |
| [avatar-motion/Tests/AvatarStateTests.swift](../avatar-motion/Tests/AvatarStateTests.swift) | 既存を再利用 | 既存アバター・部屋機能の回帰テスト |
| [avatar-motion/Tests/ElectricTransitionTests.swift](../avatar-motion/Tests/ElectricTransitionTests.swift) | 既存を再利用 | 既存アバター・部屋機能の回帰テスト |
| [avatar-motion/Tests/RoomComponentTests.swift](../avatar-motion/Tests/RoomComponentTests.swift) | 既存を再利用 | 既存アバター・部屋機能の回帰テスト |
| [avatar-motion/Tests/RoomVisualStateTests.swift](../avatar-motion/Tests/RoomVisualStateTests.swift) | 既存を再利用 | 既存アバター・部屋機能の回帰テスト |
| [avatar-motion/Tests/RoomWarningTests.swift](../avatar-motion/Tests/RoomWarningTests.swift) | 既存を再利用 | 既存アバター・部屋機能の回帰テスト |
| [avatar-motion/Tests/TestMain.swift](../avatar-motion/Tests/TestMain.swift) | 既存を再利用 | 既存アバター・部屋機能の回帰テスト |
| [monitor/Tests/AdditionalTests.swift](../monitor/Tests/AdditionalTests.swift) | 既存を再利用 | 既存監視・相談・診断・アプリ機能の回帰テスト |
| [monitor/Tests/ApplicationLauncherTests.swift](../monitor/Tests/ApplicationLauncherTests.swift) | 既存を再利用 | 既存監視・相談・診断・アプリ機能の回帰テスト |
| [monitor/Tests/ApplicationStorageTests.swift](../monitor/Tests/ApplicationStorageTests.swift) | 既存を再利用 | 既存監視・相談・診断・アプリ機能の回帰テスト |
| [monitor/Tests/ApplicationUsageTests.swift](../monitor/Tests/ApplicationUsageTests.swift) | 既存を再利用 | 既存監視・相談・診断・アプリ機能の回帰テスト |
| [monitor/Tests/ConsultationTests.swift](../monitor/Tests/ConsultationTests.swift) | 既存を再利用 | 既存監視・相談・診断・アプリ機能の回帰テスト |
| [monitor/Tests/CoreTests.swift](../monitor/Tests/CoreTests.swift) | 既存を再利用 | 既存監視・相談・診断・アプリ機能の回帰テスト |
| [monitor/Tests/DeviceTests.swift](../monitor/Tests/DeviceTests.swift) | 既存を再利用 | 既存監視・相談・診断・アプリ機能の回帰テスト |
| [monitor/Tests/DiagnosticSelectionTests.swift](../monitor/Tests/DiagnosticSelectionTests.swift) | 既存を再利用 | 既存監視・相談・診断・アプリ機能の回帰テスト |
| [monitor/Tests/DiagnosticTests.swift](../monitor/Tests/DiagnosticTests.swift) | 既存を再利用 | 既存監視・相談・診断・アプリ機能の回帰テスト |
| [monitor/Tests/HistoryTests.swift](../monitor/Tests/HistoryTests.swift) | 既存を再利用 | 既存監視・相談・診断・アプリ機能の回帰テスト |
| [monitor/Tests/ObservationTests.swift](../monitor/Tests/ObservationTests.swift) | 既存を再利用 | 既存監視・相談・診断・アプリ機能の回帰テスト |
| [monitor/Tests/StorageTests.swift](../monitor/Tests/StorageTests.swift) | 既存を再利用 | 既存監視・相談・診断・アプリ機能の回帰テスト |
| [monitor/Tests/StoreTests.swift](../monitor/Tests/StoreTests.swift) | 既存を再利用 | 既存監視・相談・診断・アプリ機能の回帰テスト |
| [monitor/Tests/TestMain.swift](../monitor/Tests/TestMain.swift) | 既存を再利用 | 既存監視・相談・診断・アプリ機能の回帰テスト |

## 設計・利用説明と検証記録

| ファイル | 扱い | 用途 |
| --- | --- | --- |
| [DESIGN.md](../DESIGN.md) | 既存を変更 | 既存の設計資料に統合画面とボタン拡大の仕様を追記 |
| [integrated/README.md](README.md) | 新規作成 | 起動方法、操作、状態の対応、検証手順 |
| [integrated/QA/BUTTON_SIZE_RESULTS.md](QA/BUTTON_SIZE_RESULTS.md) | 新規作成 | 実装・ボタン拡大の検証結果、ログ、または最終Swiftソースのハッシュ |
| [integrated/QA/RESULTS.md](QA/RESULTS.md) | 新規作成 | 実装・ボタン拡大の検証結果、ログ、または最終Swiftソースのハッシュ |
| [integrated/QA/avatar-tests.log](QA/avatar-tests.log) | 新規作成 | 実装・ボタン拡大の検証結果、ログ、または最終Swiftソースのハッシュ |
| [integrated/QA/avatar-typecheck.log](QA/avatar-typecheck.log) | 新規作成 | 実装・ボタン拡大の検証結果、ログ、または最終Swiftソースのハッシュ |
| [integrated/QA/build.log](QA/build.log) | 新規作成 | 実装・ボタン拡大の検証結果、ログ、または最終Swiftソースのハッシュ |
| [integrated/QA/button-size-build.log](QA/button-size-build.log) | 新規作成 | 実装・ボタン拡大の検証結果、ログ、または最終Swiftソースのハッシュ |
| [integrated/QA/integration-tests.log](QA/integration-tests.log) | 新規作成 | 実装・ボタン拡大の検証結果、ログ、または最終Swiftソースのハッシュ |
| [integrated/QA/monitor-tests.log](QA/monitor-tests.log) | 新規作成 | 実装・ボタン拡大の検証結果、ログ、または最終Swiftソースのハッシュ |
| [integrated/QA/policy-session-tests.log](QA/policy-session-tests.log) | 新規作成 | 実装・ボタン拡大の検証結果、ログ、または最終Swiftソースのハッシュ |
| [integrated/QA/source-sha256.txt](QA/source-sha256.txt) | 新規作成 | 実装・ボタン拡大の検証結果、ログ、または最終Swiftソースのハッシュ |
| [integrated/QA/PR11_REVIEW.md](QA/PR11_REVIEW.md) | 新規作成 | PR11の独立レビュー結果（修正前のコミットに対する記録） |
| [integrated/QA/PR11_FIXES.md](QA/PR11_FIXES.md) | 新規作成 | PR11レビュー指摘の修正内容、回帰テスト、実機キーボード確認 |
| [integrated/QA/pr11-fix-build.log](QA/pr11-fix-build.log) | 新規作成 | PR11修正後の統合ビルド結果 |
| [integrated/QA/pr11-fix-tests.log](QA/pr11-fix-tests.log) | 新規作成 | PR11修正後の全4統合テスト結果 |

## 生成物と完全性の確認

- 出力アプリ: `integrated/AIBOU.app`。実行ファイルは `Contents/MacOS/AIBOU`。
- `.build/sources/` はビルド時のソースの複製。元ファイルと重複するため別の入力ファイルとして数えない。コンパイラキャッシュや署名も一覧の集計対象外。
- 記録時にSwift 45件とビルド用複製、素材・設定・付随ファイル 143件と同梱先のSHA-256一致を全件確認した。
- 機械可読の一覧、各ファイルのサイズ・SHA-256・区分・同梱先は [QA/file-inventory.json](QA/file-inventory.json) に保存。
- この一覧文書とJSON自身は自己参照を避けて集計・ハッシュの対象外。内容の変更後は記録時点の一覧として扱う。
