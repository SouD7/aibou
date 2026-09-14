# Codex相談機能 検証結果

実施日: 2026-09-14。変更対象は `monitor/` のみ。他タスクの `avatar-motion/` と `design/` の変更は対象外。

## 実装

- 「相談」画面、ChatGPT認証、送信内容の確認、集計情報の添付、ストリーム回答、追加質問、中断、新規相談、切断・ログアウト。
- 公式Codex CLIのApp Serverをstdioで利用。専用CODEX_HOMEを使用し、既存の認証ファイルやAPIキーを取り込まない。
- 添付は許可した全体指標の投影。ファイル・プロセス・接続先の一覧を自動送信しない。
- 自動修復やツールの操作要求は提供しない。送信失敗時は再送せず状態を表示する。

## 検証済み

| 検証 | 結果・根拠 |
| --- | --- |
| Swiftコンパイルと全回帰テスト | warnings-as-errorsで成功。`consultation-tests.log`にALL TESTS PASSED。最終実行は04:41 JST。 |
| アプリビルド | 全Sourcesを最適化・warnings-as-errorsでビルド成功。アプリへPrivacyInfoをコピーし、adhoc署名のstrict検証とplist lintが成功。`consultation-build.log`。配布用の公証は実施していない。 |
| 送信データ | 許可項目、機密マーカーの除外、欠測と非有限値の扱いをfixtureで確認。 |
| RPC・会話 | UTF-8の分割、双方向通信、操作要求拒否、完了通知の順序、重複回避、中断、切断、送信未確認の表示、接続ごとの会話回数を検証。 |
| 子プロセス終了 | SIGTERMを無視するfixtureでも、強制終了後に終了待機が完了。 |
| 実CLIとの接続 | codex-cli 0.145.0。認証空の一時CODEX_HOMEでinitialize/account/read/config/read、相談モデルの接続に成功。認証種別設定と主要ツール無効設定を照合。`consultation-handshake.log`。 |
| 画面 | fixtureによる相談本文・送信状態・接続操作・入力欄のオフスクリーン描画を目視確認。`consultation-preview.png`。ログインや送信の実操作E2Eではない。 |
| コードレビュー | 独立エージェントの最終判定APPROVE。残存指摘0。`CONSULTATION_CODE_REVIEW.md`。 |
| アーキテクチャレビュー | 独立エージェントの最終判定CLEAR。`CONSULTATION_ARCHITECTURE_REVIEW.md`。 |
| 検証対象の固定 | `consultation-source-sha256.txt`で全Sources/Testsとplist・ビルドスクリプトを記録し、ビルド後に一致を確認。git diff --checkも成功。 |

## 未実施・範囲

- 実アカウントでのブラウザ認証、推論、利用枠超過を含むサービス側のE2E。検証では質問をOpenAIへ送信せず、利用枠を消費していない。
- 実際のアカウントでの初回ログインはアプリの「相談」から行う。
- 稼働中のモニタの再起動、ユーザーの監視アーカイブへの検証書き込み、コミット・プッシュは行っていない。
- App Serverの将来の互換性、任意CLI実行ファイルの安全性、切断後のリモート処理停止は保証しない。詳細は `../CONSULTATION.md`。
