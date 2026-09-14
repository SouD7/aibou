# Codex相談機能 実装計画

- macOS 13 / Swift標準ライブラリと既存SwiftUI構成を維持。変更はmonitor内。
- App Serverのstdio JSONLでinitialize、ChatGPTログイン、account/read、thread/start、turn/start、stream、interruptを扱う。SDKやAPIキーは追加しない。
- AIBOU専用CODEX_HOME、空の作業ディレクトリ、ChatGPT認証限定、read-only sandbox、shell/外部ツール無効化、サーバーからの操作要求拒否。アカウント情報・認証URLをログへ出さない。
- 相談は送信時のみ。質問と許可した全体指標・時刻・欠測状態をプレビューし、その同じ内容を送信。ファイル階層・プロセス名・パス・接続先・シリアル番号を自動添付しない。
- 会話は起動中だけ保持し、同じthreadで追加質問。中止・新規相談・切断・終了・通信失敗でbusy状態を解放する。RPCと出力に上限・期限を設ける。
- fixtureでJSONL分割、失敗・中断・通知順序、送信情報の範囲、認証モードを検証。実CLIとの認証不要handshake、全テスト、ビルド、署名を確認。アカウントログイン操作と実質問はユーザー操作を要するため、未実施なら明記する。

根拠: https://learn.chatgpt.com/docs/app-server と https://learn.chatgpt.com/docs/config-file/config-reference 。ローカルcodex-cli 0.145.0のgenerate-json-schemaも照合。App Serverは実験的APIのためCLI更新時に再検証する。
