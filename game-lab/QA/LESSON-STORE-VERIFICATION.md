# LessonStore 保存・復旧の確認

`Sources/Core/*.swift` と実装中の `Sources/UI/LessonStore.swift` を、`Tools/CheckLessonStore.swift` と一緒に Swift 5・warnings-as-errors でコンパイルして実行した。モックのStoreや保存処理への差し替えは行っていない。

結果：**43項目合格**。実行ログは `lesson-store-checks.log`。

## 確認内容

- 壊れたJSONと将来のversion 2の記録を別々に使用。初期化時にエラーを表示し、元のファイルを書き換えず、完了状態を捏造しない。
- `open("memory-dock")` の保存時に `lessons-unreadable-UUID.json` が1つ作られ、元の全バイトを保持する。その後の新規記録は現行versionで読み込める。
- 開いただけでは完了を保存しない。実験・正答・まとめまで進めると完了が保存され、新しいStoreでも保持される。
- 追加保存・再保存で退避ファイルが増えず、元の退避データが変わらない。
- 親ディレクトリの位置に普通のファイルがある、確実に保存できない状態でも、`saveError` が表示され授業セッションは進められる。実験と正答で獲得した完了はメモリ上に残る。
- 保存先を修復して `retrySave()` するとエラーが消え、メモリ上の完了と最後の授業が保存・再読込できる。
- 再読込では途中セッションや自動開始を作らない。

全保存先は、一意な `aibou-lesson-store-check-UUID` 一時ディレクトリだけを使用し、実行後に削除した。アプリの実データ、UserDefaults、実画面は操作していない。Core・Store・UIの実装修正は不要だった。

再実行（`game-lab` から）:

```sh
swiftc -swift-version 5 -warnings-as-errors Sources/Core/*.swift Sources/UI/LessonStore.swift Tools/CheckLessonStore.swift -o /tmp/aibou-check-lesson-store
/tmp/aibou-check-lesson-store
```

これは保存・復旧の非UIチェックであり、エラー文の画面表示やボタンの配置を目視検証したものではない。
