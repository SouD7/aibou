# AIBOU Monitor 再レビュー — 2026-09-13

> 以下は修正前の指摘です。同日、7件を修正し全テスト・ビルド・独立再レビューが完了しました。[最新の修正結果](REREVIEW_FIX_RESULTS.md)を参照してください。

## 結論

**REQUEST CHANGES（修正が必要）**。前回の修正確認とは別に、新しいコンテキストの2名のサブエージェントが現行コード全体をレビューした。

| 独立担当 | 判定 | 指摘 |
|---|---|---|
| fresh_code_review（code-reviewer） | REQUEST CHANGES | CRITICAL 0、HIGH 1、MEDIUM 6、LOW 0 |
| fresh_architecture_review（architect） | WATCH | 計測区間欠落を独立確認。大規模データ・UI負荷・将来の並行利用に継続課題 |

統合判定はコード担当のREQUEST CHANGESを採用。設計担当のWATCHは、コード上の誤計測を許容する判定ではない。

**今回はレビューのみで、ソースコードを修正していない。** テスト・ビルドは成功したが、以下の異常系や機器構成変更は既存テストで網羅されていない。実害を伴う静的なコード経路と、未測定の設計上の懸念を分けて記録する。

## 対象と検証

- `monitor/Sources/*.swift` 9ファイル、`Tests/*.swift` 8ファイル、ビルド・テスト・プローブスクリプト3件、Info.plist・PrivacyInfo.xcprivacy：計22件。
- AIBOU_BACKEND_SPEC.md、README.md、CAPABILITIES.mdと照合。過去QAは独立した判断の後に確認。
- Git管理なしのため差分ではなく全体レビュー。[開始時SHA-256](rereview-source-sha256.json)と終了時の22ファイルは一致。
- `./monitor/test.sh`：2026-09-13 15:47:48 JST、ALL TESTS PASSED。[ログ](rereview-tests.log)
- `./monitor/run.sh --build`：最適化・warnings-as-errors・macOS 13ターゲットで成功。[ログ](rereview-build.log)
- `codesign --verify --strict`、Info.plistとPrivacyInfo.xcprivacyの`plutil -lint`：成功。
- 今回はホットプラグ、UPS接続、API失敗注入、管理者認証、長時間GUI負荷の新規実機試験を実施していない。利用者の保存アーカイブは変更していない。

## HIGH — 優先して修正

### 1. ディスクの取得対象が変わると、累積値を区間I/Oへ誤計上する

**場所：** [CoreSampler.swift:545](/Users/sodaiyamamoto/aibou/monitor/Sources/CoreSampler.swift:545)、[累積値の収集:717](/Users/sodaiyamamoto/aibou/monitor/Sources/CoreSampler.swift:717)。

全IOBlockStorageDriverの累積読み書き量を先に合算し、その合計を前回の合計と差分化している。前後のデバイスID・取得集合は保持していない。

**発生条件：** 外部ディスクの追加・削除、あるデバイスの統計が一時的に取得できず次回に再び取得できるなど、累積値を持つデバイスが集計に加わる場合。例えば継続デバイスの増加が1 GBで、新たに取得対象へ入るデバイスに1 TBの累積値があれば、1.001 TBをその計測区間のI/Oとして扱う。これは条件を説明する算術例であり、実機で1 TBの値を観測したという意味ではない。

**影響：** 偽のI/O速度を表示し、[History.swift:78](/Users/sodaiyamamoto/aibou/monitor/Sources/History.swift:78)から集計履歴にも保存する。除去時に合計が減少すれば値は欠損になるが、集合変更自体は判別できない。

**修正案：** IORegistry entry ID等によるデバイス別カウンタを保持し、両時点に存在するデバイスだけ差分化する。追加・削除・リセット区間は部分取得と表示。最小対応として集合変更時に基準を破棄し、次の計測を待つ方法もある。

**必要なテスト：** デバイス追加・削除・一時欠損からの復帰・個別リセット。ネットワーク側に導入済みの集合別差分テストと同じ考え方を適用できる。

**確度：高。** 静的経路と算術で確認。実ディスク着脱は未試験。

## MEDIUM — 6件

### 2. プロセス列挙の失敗を「実測0件」にする

**場所：** [CoreSampler.swift:612](/Users/sodaiyamamoto/aibou/monitor/Sources/CoreSampler.swift:612)、[表示用集計:382](/Users/sodaiyamamoto/aibou/monitor/Sources/CoreSampler.swift:382)。

`proc_listallpids`の件数見積もり・本取得が失敗すると空配列を返す。上位処理はこれを正常な空集合として扱い、プロセス数と総スレッド数を0・実測と表示する。

**影響：** 一時的な列挙失敗と「プロセスが存在しない」を区別できず、欠損を0で埋めない共通契約に反する。

**修正案：** Result等で列挙成功・失敗理由を返し、失敗時の件数はnil／取得失敗にする。個別PIDの読み取り失敗による部分取得とは分ける。列挙失敗を注入するテストが必要。

**確度：高。** 静的確認。実libproc失敗は未注入。

### 3. 観測値APIでプロセス速度の計測区間が失われる

**場所：** [Observations.swift:145](/Users/sodaiyamamoto/aibou/monitor/Sources/Observations.swift:145)、[interval既定値:86](/Users/sodaiyamamoto/aibou/monitor/Sources/Observations.swift:86)。両担当が独立確認。

ObservationProcessはCPU・ディスク速度へintervalを設定できるが、ObservationSnapshotからの呼び出しでは省略され常にnilになる。画面用の指標には実経過時間がある一方、ProcessSample/CoreReadingはそれを観測APIへ伝える情報を持たない。

**影響：** アバター側で速度の時間窓を判断できない。仕様の「各指標は計測区間を持つ」を満たさない。カテゴリ内の指標にintervalが存在しても、このprocess一覧の欠落は補えない。

**修正案：** 一次収集結果へ実経過時間を保持し、Store経由・直接収集の両経路で渡す。設定上の1秒・2秒を代用しない。processのCPU・I/O速度のinterval値を直接検証する回帰テストを追加する。

**確度：高。** 呼び出し経路を親も照合。既存テストはJSON全体にintervalキーがあることしか検証していない。

### 4. 識別属性が同じ・不足した外部機器を1台にまとめる

**場所：** [DeviceSampler.swift:201](/Users/sodaiyamamoto/aibou/monitor/Sources/DeviceSampler.swift:201)、[MonitorStore.swift:199](/Users/sodaiyamamoto/aibou/monitor/Sources/MonitorStore.swift:199)。

機器IDを接続方式・vendorID・productID・locationだけで作り、同じIDを除外する。欠損値は0や「—」となるため、例えば3属性を持たない複数Thunderbolt entryが同じIDへまとまる。IORegistry entry自体の識別子は収集時に捨てている。

**影響：** 一覧から機器が消え、同じIDを使う接続・切断検出も変化を見落とす。

**修正案：** シリアル番号ではないIORegistryEntryGetRegistryEntryID等を保持して行・接続イベントのIDに使う。属性欠損の複数entry、片方の切断をfixtureで検証する。

**確度：高。** 衝突するコード条件を静的確認。該当する複数の実機接続は未試験。

### 5. 名前付きUPSを内蔵バッテリーとして選択する

**場所：** [DeviceSampler.swift:255](/Users/sodaiyamamoto/aibou/monitor/Sources/DeviceSampler.swift:255)、[バッテリー表示:85](/Users/sodaiyamamoto/aibou/monitor/Sources/DeviceSampler.swift:85)。

電源種がInternalBatteryである条件に加え、Nameが存在するだけでも電源を選択する。IOPowerSourcesにはUPSも含まれるため、名前付きUPSが先に列挙された場合やUPSのみのMacで、バッテリー表示へ採用され得る。

**影響：** UPSと内蔵バッテリーの情報を混同する。

**修正案：** 内蔵バッテリーの選択を`kIOPSInternalBatteryType`に限定する。UPSも扱うなら種類を明示した別の指標とする。内蔵＋UPS、UPSのみのselectorテストを追加する。

**確度：高。** 分岐とローカルmacOS SDKのIOPowerSources.h（41行付近）、IOPSKeys.h（501–511、736–747行付近）を照合。UPS実機は未接続。SDK場所：`/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/IOKit.framework/Headers/ps/`。

### 6. powermetrics解析の打ち切りを部分取得として報告しない

**場所：** [AdditionalCollectors.swift:269](/Users/sodaiyamamoto/aibou/monitor/Sources/AdditionalCollectors.swift:269)、[結果分類:286](/Users/sodaiyamamoto/aibou/monitor/Sources/AdditionalCollectors.swift:286)。

深さ15または12,000個の末端値に達すると走査を打ち切るが、その事実を結果へ渡さない。対象フィールドが打ち切り後にあれば「非対応」と判断し、前にあった結果にも取得範囲が不完全なことを示さない。

**影響：** 自分のパーサの上限を機種非対応と誤認する。取得済み個別値が実値であっても、結果集合の完全性は保証できない。

**修正案：** 件数・深さ上限への到達を保持し、パネル等へ部分取得と理由を表示する。対象0件でも非対応と断定しない。12,001 leafおよび深い対象keyを持つplistで回帰テストする。

**確度：高。** 静的分岐確認。実powermetricsでの上限到達は未確認。

### 7. 機器が存在しない状態とAPI取得失敗を区別しない

**場所：** [DeviceSampler.swift:255](/Users/sodaiyamamoto/aibou/monitor/Sources/DeviceSampler.swift:255)、[IORegistry列挙:265](/Users/sodaiyamamoto/aibou/monitor/Sources/DeviceSampler.swift:265)。

IOPSCopy系APIの失敗と内蔵バッテリー非搭載をともにnil、IOServiceMatching／IOServiceGetMatchingServicesの失敗と正常0件をともに空配列へ変換する。呼び出し側は一部を「非対応・内蔵バッテリーが見つからない」と扱い、外部機器一覧には失敗状態が残らない。

**影響：** 一時障害やアクセス失敗を非搭載・非対応として見せる。指摘2はlibproc、この指摘はデバイス収集での別の状態消失。

**修正案：** 成功0件・取得失敗・確認できる権限エラーをResult等で分離し、パネルにも状態を伝える。失敗原因が分からない場合に権限不足と推測せず、取得失敗として扱う。API失敗と正常空集合の別テストを追加する。

**確度：高。** 静的確認。IOKit障害は未注入。

## 設計担当の継続課題（WATCH）

以下は上記7件へ重複加算していない。現行条件で実証されたクラッシュや停止ではなく、設計上の制約・測定不足である。

| 課題 | 根拠と現在の制約 | 推奨する確認・変更 |
|---|---|---|
| 大規模保存・復元のピークメモリ | [StorageScanner.swift:246](/Users/sodaiyamamoto/aibou/monitor/Sources/StorageScanner.swift:246)で全JSON decode、ID検証、全件索引。保存も[MonitorStore.swift:372](/Users/sodaiyamamoto/aibou/monitor/Sources/MonitorStore.swift:372)で全エンコード後に容量判定。500件ページングは主に表示を制限する | 合法上限付近でdecode・索引・encodeを含むピークRSSを測定。上限拡張時はディスク上の索引を検討 |
| 履歴復元・グラフ準備のMainActor負荷 | [MonitorStore.swift:101](/Users/sodaiyamamoto/aibou/monitor/Sources/MonitorStore.swift:101)の履歴復元は同期。[App.swift:213](/Users/sodaiyamamoto/aibou/monitor/Sources/App.swift:213)では履歴の指標存在確認とseries生成が残る。最大8,641フレームで有界だがGUI負荷は今回未測定 | 復元を背景処理へ移し、履歴が変わった時にだけグラフ系列を生成・キャッシュ |
| 停止操作の意味 | [MonitorStore.swift:169](/Users/sodaiyamamoto/aibou/monitor/Sources/MonitorStore.swift:169)のpause後も単発電力計測は完了し得る。[既知制約](VERIFICATION.md)に記載済み。終了時の保存待機は背景処理で最大2秒 | 基本監視停止であることをUI・READMEで明確にするか、全計測停止へ統一。現行の既知制約だけを理由に新規バグとは数えない |
| 将来の複数consumer | [MonitorStore.swift:5](/Users/sodaiyamamoto/aibou/monitor/Sources/MonitorStore.swift:5)の状態を持つengineは非並行呼び出しをコメントで要求。現行UIは専用直列キューなので、この競合は未発生。snapshot投影はMainActorで全量変換 | 複数アバターや高頻度利用を導入する前に、単一producerのactorと変更不要な最新snapshotの配信を設計 |

旧556 MB・約91万件のストレージアーカイブは容量判定で読み込み前に拒否され、今回も変更していない。上限で保護されていることと、上限内のピークRAMを実測済みであることは別である。前回の合成負荷試験は保存エンコードやGUI全体を測ったものではない。

## 修正優先順位

1. ディスクをデバイス別に差分化し、集合変更の偽速度を防ぐ。
2. プロセス・デバイス収集の失敗状態と、powermetricsの部分取得を保持する。
3. 外部機器の固有IDと電源種別選択を修正する。
4. 観測APIへ実計測区間を引き渡す。
5. 上記の異常系・複数機器fixtureを追加後、保存・復元・履歴表示の負荷を測定する。

固定コマンド・管理者AppleScript・出力上限・タイムアウト・保存権限について、新たなセキュリティ問題は確認されなかった。ただし、これは全OS・全権限条件での安全性保証ではない。
