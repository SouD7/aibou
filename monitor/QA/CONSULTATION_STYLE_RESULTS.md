# 相談の返答スタイル設定 検証結果

2026-09-14

## 変更

- `ConsultationModel.swift`: 相談専用のdeveloperInstructionsに、親しみのある落ち着いたです・ます調、結論から説明、次に試すこと1〜2個、明示的な詳細要求への応答を追加。回答の長さをアプリのUserDefaultsに保存し、初期値・未知値は標準。
- `ConsultationPayload.swift`: 短め（100字・2〜3文）、標準（200字・3〜5文）、詳しめ（400字・5〜8文）の目安を定義。各送信の長さ指定をdraftに固定し、確認した本文に含めて送信。
- `ConsultationView.swift`: 質問欄に3段階の選択、送信確認画面に選択した長さを表示。
- `ConsultationTests.swift`: 保存・復元、未知値、3種の送信内容、確認後の変更からの保護、同じ会話での変更、新しい会話、専用指示の送信を検証。
- `CONSULTATION.md`: 設定と適用範囲を説明。

## 検証

- `bash monitor/test.sh`: warnings-as-errorsでコンパイル成功、全回帰テスト成功（`consultation-style-tests.log`）。
- `bash monitor/run.sh --build`: 同梱アプリのビルド成功（`consultation-style-build.log`）。
- `codesign --verify --strict monitor/AIBOUMonitor.app`: 成功。
- テスト用相談画面を1000×950で描画し、標準選択と3つのラベル、質問欄、説明の配置を目視確認（`consultation-style-preview.png`）。

実アカウントでの推論は実行していない。検証は指示・設定・送信経路・表示を対象とし、生成回答の実際の文字数や口調を保証するものではない。文字数は目安で、生成後の切り詰めは行わない。
