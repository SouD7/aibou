# Codexに相談

サイドバーの「相談」から、このMacについてCodexに質問できます。ChatGPTログインによるCodex利用枠を使います。APIキーによる別課金はこの機能では受け付けません。

## 使い方

1. 公式のCodex CLIをインストールする。AIBOUは一般的な配置を自動探索し、見つからない場合は「実行ファイルを選択」で信頼できるcodex本体を指定する。選択した実行ファイルはユーザー権限で起動するため、無関係なプログラムを選ばない。[公式導入ガイド](https://developers.openai.com/codex/cli)
2. 「Codexと接続」→「ChatGPTでログイン」→「ブラウザでログイン」。AIBOU専用の認証なので、普段のCodexアプリとは別に初回ログインする。
3. 質問を書き、「今回のモニタ集計情報を添付」を選択する。
4. 「送信内容を確認」で実際に送る質問とJSONを確認し、「この内容で相談」を押す。
5. 回答の続きは追加質問で送る。「回答を停止」で中断、「新しい相談」で会話を分ける。

通信失敗や3分の回答期限超過時は切断する。自動再送は行わず、利用枠の重複消費を避ける。接続が切れた場合、すでに受理されたリモート処理の即時停止は保証しない。再接続すると新しいthreadになる。画面に残る過去の発言は、その新しいthreadには送られない。

質問には「送信確認中」「Codexが受理」「送信未確認・自動再送なし」の状態を表示する。受理を確認する前に接続が切れた場合、送信されなかったとは断定できない。会話20往復の制限は、その接続の現在のthreadで受理された質問を数える。

## 送信情報

自動添付はCPU全体、RAM・swap、起動データ領域の容量、デバイスI/O速度、サーマル状態、充電状態、ネットワークの全体速度、計測間隔の許可した指標のみ。各値には取得時刻、状態、単位、計測間隔を付ける。停止・再開区間と最後の基本計測日時も保持する。生成元はAIBOUの基本収集カテゴリと指標IDとして表す。

ファイル内容・階層・パス、プロセス名・PID・親元、接続先、機器シリアル、任意の取得エラー文字列、rawの追加電力データは自動添付しない。コア個別の全量データや履歴、既存の診断結果一覧も初期版の添付対象外。プレビュー生成後にモニタ値が更新されても、確認した同じ添付を送る。添付をoffにしても質問に手入力した情報は送信する。

「情報なし」は0や正常へ置き換えない。Codexには取得済みの情報で説明するよう指示するが、回答は原因の確定やハードウェア故障の証明ではない。

## 認証・保存・操作範囲

- ローカルApp Serverとstdio JSONLで接続。HTTP待受ポートをAIBOU独自には開かない（ログインcallbackはCodexが管理）。
- `~/Library/Application Support/AIBOU Monitor/Consultation/codex-home`にCodexが認証を保存・更新する。AIBOUはアクセストークンを読んだりコピーしたりせず、公式account APIを使う。「ログアウト」はこの専用環境に適用する。
- 既存の`~/.codex`設定・認証やAPIキー環境変数は引き継がない。ChatGPT認証を強制し、質問前にもaccount種別を確認する。
- 新しい会話はephemeral thread。AIBOUは会話のファイル保存や再起動後の復元を実装しない。認証やCodexの内部動作ファイルは専用環境に残る場合がある。OpenAI側の保持条件まで「保存しない」と保証するものではなく、アカウントの適用条件に従う。
- 専用workspace、read-only sandbox、ネットワークを許可しない実行sandbox、shell・ブラウザ・アプリ・plugins・hooks・multi-agent等を無効化する起動設定。推論サービスへの接続はApp Serverが行う。これらは正規のCodex CLIが設定を適用する前提であり、選択した任意の実行ファイル自体をAIBOUがOS sandboxへ閉じ込める保証ではない。専用workspaceは再利用し、その中にユーザーが置いたファイルを自動削除しない。
- サーバーからのツール・権限・入力要求は拒否する。相談UIからコマンド実行、ファイル変更、削除、設定変更、外部アプリ操作は提供しない。
- 質問8,000 UTF-8 bytes、添付込32,000 bytes、1回答65,536 bytes、会話20往復、RPC期限30秒、ログイン待機5分、回答期限3分。制限到達時は理由を表示する。
- 利用枠超過等はCodexのエラーを画面へ表示する。課金の自動切替・利用枠リセットの自動購入はしない。

PrivacyInfo.xcprivacyには、ユーザーが送信を選ぶ質問と診断情報をApp Functionality目的として追加した。アカウントへ紐付く通信で、広告追跡には使わない。

## 実装と検証

`CodexRPC.swift`（子プロセスとJSONL）、`ConsultationModel.swift`（認証・会話・中断）、`ConsultationPayload.swift`（許可した集計値の投影）、`ConsultationView.swift`（相談画面）。

`Tests/ConsultationTests.swift`は実アカウントを使わないfixtureで、送信範囲、JSONL分割、ストリームの重複、前会話の遅延通知、開始応答前の完了、中断、通信失敗、API認証拒否、Processによる双方向通信を確認する。

テスト実行ファイルの `--codex-handshake /absolute/path/to/codex` は一時的な認証空のCODEX_HOMEでinitialize/account/read/config/readと相談モデルの接続を検証する。ログイン・質問送信・利用枠消費は行わない。

確認した基準CLIは `codex-cli 0.145.0`。App Serverは実験的な接続口のため、CLI更新時はschemaとhandshakeを再検証する。[App Server仕様](https://learn.chatgpt.com/docs/app-server)、[認証](https://learn.chatgpt.com/docs/auth)、[設定](https://learn.chatgpt.com/docs/config-file/config-reference)。
