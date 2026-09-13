# 現状レビュー — 2026-09-13（R3）

> このレビューへの後続改善: [R3修正内容・検証・残る制約](R3_FIX_RESULTS.md)。以下は修正前の指摘を保存した記録。

## 結論

**COMMENT（改善事項あり）**。新しいコンテキストの2名のサブエージェントが、前回の承認を前提にせず現行全体をレビューした。

| 担当 | 独立判定 | 結果 |
|---|---|---|
| r3_fresh_code_review / code-reviewer | COMMENT | CRITICAL 0、HIGH 0、MEDIUM 3、LOW 1 |
| r3_fresh_architecture / architect | WATCH | 現行の単一UI・直列監視・既存上限の範囲で新規設計BLOCKなし |

中優先度3件のうち、2件はコード経路で確認した状態表現の不足、1件は管理者実行の停止保証に関する未検証事項。低優先度1件は不正なローカル保存データに対する検証不足である。全件を実機で再現した不具合として扱わない。

前回修正した7件を再発と判断する指摘はなかった。今回はコードを変更していない。

## 対象と検証証拠

- Sources 9、Tests 8、scripts 3、Info.plist／PrivacyInfo.xcprivacy 2：計22ファイル。仕様・README・CAPABILITIES・SOURCESと照合。
- Git管理なしのため全体レビュー。開始時と終了時の22ファイルのSHA-256は一致し、前回の最終検証時点とも一致。[指紋](r3-source-sha256.json)
- `./monitor/test.sh`：2026-09-13 16:54:30 JST、**ALL TESTS PASSED**。[ログ](r3-tests.log)
- `./monitor/run.sh --build`：最適化・warnings-as-errors・macOS 13ターゲットで成功。[ログ](r3-build.log)
- `codesign --verify --strict`、Info.plist・PrivacyInfo.xcprivacyのlint：成功。
- 新規GUI操作、実スリープ、ディスク着脱、UPS接続、管理者認証、大規模アーカイブの再測定は実施していない。実行中アプリの未保存スキャン結果を保持するため再起動していない。

## 中優先度 — 3件

### 1. 観測APIに停止状態の表現がない

**根拠：** [MonitorStore.swift:87](/Users/sodaiyamamoto/aibou/monitor/Sources/MonitorStore.swift:87)、[Observations.swift:136](/Users/sodaiyamamoto/aibou/monitor/Sources/Observations.swift:136)、[画面側の停止表示:74](/Users/sodaiyamamoto/aibou/monitor/Sources/App.swift:74)。

1回以上計測した後に基本監視を停止・スリープし、`observationSnapshot()`を取得すると、保持済みの指標を元のmeasured／derived状態で返す。画面ではバナーで停止を示すが、Snapshot自体にはrunning／pausedの情報がない。

**影響：** 将来のアバター等のconsumerは、意図的に停止中なのか、収集が遅延しているのかをこのAPIだけでは明示的に区別できない。計測日時は保持されており、日時を偽装しているわけではない。

**最小修正：** Snapshot全体に監視状態を追加し、必要なら観測区間の識別子も持たせる。元の計測方法を維持したい場合、個別指標のderivedをstaleに置き換えるより、監視状態と鮮度を別フィールドにする方法が適している。

**必要なテスト：** running→paused→resumedのSnapshot状態、停止中に完了した単発電力結果と基本監視の区別。

**確度：高。** コード担当・設計担当・親が静的経路を照合。専用実行テストは今回未実施。

### 2. CPU取得失敗を「計測待ち」と表示する

**根拠：** [CoreSampler.swift:471](/Users/sodaiyamamoto/aibou/monitor/Sources/CoreSampler.swift:471)。

`host_processor_info`の失敗で現在のCPU tickがnilになると、ユーザー利用・システム利用・アイドルは、値がnilという理由だけでwaitingになる。一方、コア別項目はunavailableと表示する。

**影響：** 同じ取得失敗について、全体の3指標は初回差分待ち、コア別は取得失敗となり、状態の意味が一致しない。

**最小修正：** 現在tickが未取得ならunavailable、現在値は取得できたが前回基準がないならwaitingと分ける。カウンタ巻き戻りも別の理由を付けると判断しやすい。

**必要なテスト：** tick取得を注入可能にし、初回成功、API失敗、失敗後の基準再取得を検証する。

**確度：高。** 分岐を静的確認。実機でMach API失敗は発生させていない。

### 3. 管理者計測の子プロセス停止を検証していない

**根拠：** [AdditionalCollectors.swift:49](/Users/sodaiyamamoto/aibou/monitor/Sources/AdditionalCollectors.swift:49)、[管理者経路:244](/Users/sodaiyamamoto/aibou/monitor/Sources/AdditionalCollectors.swift:244)。

管理者版powermetricsはosascript経由で実行する。現在のterminate／killの対象は直接起動したosascriptのPIDであり、認証経由のshellやpowermetricsまで停止したかは確認していない。コード担当はローカルSDKのNSTask.hで、terminateが対象taskへSIGTERMを送る契約であることを確認した。

**発生条件として確認が必要な場面：** 管理者計測中のアプリ終了、または120秒のタイムアウト。

**評価：** 孤児プロセスの発生は未証明。現在のpowermetricsは`-n 1 -i 1000`の単発実行であり、通常は計測後に終了する。READMEも終了時に停止を要求する方針であるため、常駐し続けることが確認された不具合とは記載しない。

**最初の対応：** 管理者経路の統合試験で、終了・タイムアウト後の実行プロセスを確認する。残留が実証された場合に、実行識別子やPIDの追跡、適切な権限を持つ管理方法を検討する。OSの認証経由で起動したプロセスまで通常のプロセスグループ操作で停止できるとは仮定しない。

**確度：停止対象のコード構造は高、子プロセス残留の発生は未確認。** この項目は停止保証の検証不足として扱う。

## 低優先度 — 1件

### 4. 保存索引に親子関係の循環があっても復元する

**根拠：** [StorageScanner.swift:246](/Users/sodaiyamamoto/aibou/monitor/Sources/StorageScanner.swift:246)。

復元時はIDの一意性と親IDの存在を検証するが、rootからの到達性や循環を検証しない。root以外の2ノードが互いを親にする不正JSONもsavedとして受理する。

**再現証拠：** コード担当が小さなfixtureで `status=saved nodes=3 rootChildren=0` を確認。ノードはあるのにrootから閲覧できない。

**影響範囲：** 破損・手動変更されたローカル保存ファイル。通常のscannerが生成する正常なアーカイブでこの構造が発生することは確認されていない。外部からの攻撃や新たな情報漏えいとして扱わない。

**最小修正：** rootが唯一の親なしノードであること、全ノードの到達性、循環がないことを検証する。現在のpathをIDとするモデルに合わせ、`path == id`などの整合性も確認する。

**確度：高。** fixture実証あり。cycle、孤立ノード、path不整合の回帰テストが有効。

## 設計担当のWATCH

下記は上の4件へ重複加算しない。現行仕様の制約や、将来の拡張前に扱う課題である。

| 課題 | 根拠・影響 | 次の対応 |
|---|---|---|
| 全件JSONの負荷 | [StorageScanner.swift:82](/Users/sodaiyamamoto/aibou/monitor/Sources/StorageScanner.swift:82)、[MonitorStore.swift:383](/Users/sodaiyamamoto/aibou/monitor/Sources/MonitorStore.swift:383)。配列・索引・JSONを全件保持。前回50万件測定の最大RSS約949MBは既知の実測値で、今回の再測定ではない | 上限拡張前にディスク上の索引やページ単位decodeを検討 |
| 完了から保存登録までの窓 | [MonitorStore.swift:129](/Users/sodaiyamamoto/aibou/monitor/Sources/MonitorStore.swift:129)、[同:278](/Users/sodaiyamamoto/aibou/monitor/Sources/MonitorStore.swift:278)。内部走査完了後、UI用索引の構築中に終了すると未登録の結果を保存しない | 保存登録を索引構築から分離すると改善。ただしこの時点ではUIに完了・保存済みと表示しておらず、既知の最大2秒のbest-effort終了の範囲として評価 |
| 履歴復元の許可リスト | [History.swift:27](/Users/sodaiyamamoto/aibou/monitor/Sources/History.swift:27)。新規appendは許可リストを使うが、復元は未知キーを除去しない。旧版・手動変更したローカル履歴のキーが再保存され得る | 復元時にも現在の完全修飾metric IDの許可リストを適用する。現行appendからの機微情報生成・外部送信ではない |
| 将来consumerの所有境界 | [MonitorStore.swift:5](/Users/sodaiyamamoto/aibou/monitor/Sources/MonitorStore.swift:5)。現行UIは直列で動くが、engineの直接APIはコメントによる非並行規約。停止状態の不足は指摘1と重複 | 複数consumer導入前に単一producerのactor／明示的な直列所有と状態付きSnapshotを設計 |

履歴復元・グラフ準備のMainActor負荷も前回からの継続課題であり、今回新規のGUI停止を実証したものではない。

## 推奨順序

1. CPUのAPI失敗と初回待ちを区別する。
2. 観測APIに基本監視の状態を持たせる。
3. 管理者実行の終了・タイムアウト経路を統合検証する。
4. 保存索引の到達性・循環と、履歴復元の許可リストを検証する。
5. 規模・consumer数を増やす段階で、永続化形式と収集所有を見直す。

テスト・ビルドの成功は、上記の未網羅条件や全機種での動作を保証しない。今回はレビュー結果の記録までとし、修正は行っていない。
