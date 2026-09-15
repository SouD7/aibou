# アバター遷移間隔・メモリ閾値の変更と検証

- ブランチ: `codex/avatar-timing-memory-threshold`
- 作業開始時のmain: `19951f7d691f07e6ee687017ebeaed50d7871833`（PR #11マージ後）
- アバターの自動選択を30秒から10秒へ変更。起動時、通常の繰り返し、相談・デモ終了後に適用。
- メモリは80%未満が通常、80%以上99%未満が書類の山、99%以上が書類があふれる。警告文と「書く」姿勢の優先選択も99%の判定に従う。

## 検証結果

- `./integrated/test.sh`: 全4スイート成功（[ログ](timing-memory-tests.log)）。
- [RoomSessionTests.swift](../Tests/RoomSessionTests.swift): 9.999秒では未選択、10秒で選択、19.999秒では未選択、20秒で再選択。相談・デモ中の停止と終了後10秒の再開も確認。
- [HardwareRoomPolicyTests.swift](../Tests/HardwareRoomPolicyTests.swift): 79.999%、80%、95%、98.999%、99%、100%、98.999%への回復を検証。警告とアバター候補も確認。
- `./integrated/run.sh --build`: 成功（[ログ](timing-memory-build.log)）。
- `codesign --verify --deep --strict integrated/AIBOU.app`: 成功。
- Swiftソース45件がビルド時の複製と一致。素材・設定・付随ファイル143件がアプリ同梱先と一致。

今回の変更は自動テストとビルドで検証。実画面での10秒間隔の観察は未実施。
