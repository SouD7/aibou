# 取得方法と根拠

AIBOU Monitorは、外部ライブラリを追加せず、macOSが提供するAPIと同梱コマンドを利用します。値には取得元、時刻、状態、必要な場合は計測区間を付け、実測、差分からの算出、OSによる推定を区別します。

## CPU計算と既存ツールとの関係

Appleはオープンソース版 `top` のCPU処理を公開しています。

- [Apple Open Source: top/cpu.c](https://github.com/apple-oss-distributions/top/blob/main/cpu.c)

この資料から、累積CPU時間は2時点の差分を実経過時間で割ること、初回値やカウンタの巻き戻りでは割合を作らないこと、プロセスCPUでは複数コア利用時に100%を超え得ることを確認しました。

AIBOUのコードは既存のAIBOU実装を基にこの計算を独立して実装しており、`top/cpu.c` のコードをコピーしていません。macOSのActivity Monitorは独自の製品実装であり、そのコードや非公開アルゴリズムも流用していません。

## 基本収集

| 対象 | 取得元 | 扱い |
|---|---|---|
| ホスト・論理コアCPU | Mach `host_processor_info` | CPU tickの前回値との差を割合へ変換 |
| プロセス | `libproc`、`proc_pidinfo`、`proc_pid_rusage` | CPU時間、スレッド、起動時刻、メモリ、I/Oを取得 |
| メモリ | Mach `host_statistics64`、`sysctl vm.swapusage` | 物理RAM内訳とスワップを分離 |
| 時計 | `mach_absolute_time`、`mach_continuous_time`、`Date` | 稼働時間、スリープを含む時間、壁時計を分離 |
| ネットワーク | `sysctl NET_RT_IFLIST2` / `if_msghdr2` / `if_data64` | 64bit IF別累積値と差分速度。物理集計は両時点に存在するIFから算出し、追加・消失・リセット時は部分取得 |
| ディスク | IOKit `IOBlockStorageDriver` statistics | IORegistry entry ID別の累積値と差分速度。集合変更・リセット・一部取得失敗は部分取得。エラーカウンタ欠損は0とせず取得失敗・部分取得 |
| 起動データ領域の容量 | `FileManager.attributesOfFileSystem` | `/System/Volumes/Data`（存在しない構成では `/`）の総容量と空き容量。APFSの共有容量や消去可能領域の扱いによりFinderの表示とは異なる。取得失敗はnil |
| バッテリー | IOPowerSources、IOKit `AppleSmartBattery` | 百分率、絶対容量、電圧、電流、算出電力を区別 |
| 画面 | CoreGraphics、IOKit `IODisplayConnect` | 画素とポイント、設定Hz、EDID検証概要を分離 |
| 外部機器・GPU情報 | IORegistry | USB、Thunderbolt、OSが公開するアクセラレータ情報 |
| 熱状態 | `ProcessInfo.thermalState` | OSの区分を表示。温度へ変換しない |

`libproc` の上流ヘッダにはprivate interfaceで変更され得る旨が記載されています。AIBOUは対象macOSで検証し、取得失敗を欠損として扱います。将来の互換性を公開APIと同程度には保証できません。

- [XNU libproc.h](https://github.com/apple-oss-distributions/xnu/blob/main/libsyscall/wrappers/libproc/libproc.h)
- [XNU VM statistics](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/vm_statistics.h)
- [Apple: ProcessInfo thermalState](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property)
- [Apple: CGDisplayMode](https://developer.apple.com/documentation/coregraphics/cgdisplaymode)
- [Apple: IOPowerSources](https://developer.apple.com/documentation/iokit/iopowersources_h)

## 条件付きの追加収集

`nettop` はユーザーが詳細取得を実行したときだけ、2サンプルを採取します。最後の1秒deltaからプロセス別の送受信量・速度、接続先、TCP RTT、再送、状態を表示します。最初のサンプルしかない場合は速度を作りません。CSVの反復ヘッダー、引用符、IPv6を処理しますが、短命な接続の完全捕捉はできません。

`powermetrics` は対応する場合にCPU周波数、GPU、熱関連のplistフィールドを追加表示します。通常実行で権限が足りない場合、ユーザーの明示操作からmacOSの管理者認証を起動できます。認証しても、要求したサンプラーやプロセス別GPU値がその機種で提供されるとは限りません。値は元のフィールド名と単位表記を保ち、意味が確認できない数値をGPU使用率、瞬時周波数、温度へ変換しません。

両コマンドの具体的なオプションと出力形式は、実行対象macOSに同梱される `nettop(1)` と `powermetrics(1)` のman pageを基準にします。これらはアプリ向けの安定した公開APIではなく、OS更新で形式や権限条件が変わる可能性があります。

## 現在取得できない、または完全ではない情報

- 全プロセスのワイヤード・圧縮・キャッシュ別メモリ内訳
- RAMの読み書き帯域とアクセスレイテンシ
- 全機種で安定して取得できるCPU/GPU温度、ファン最小・最大・現在RPM、VRM温度
- 信頼できるプロセス別GPU占有率
- 画面全体の実表示FPS
- 全プロトコル共通の遅延や、アプリ単位の「通信エラー」判定
- macOSの設定画面と完全一致する「システムデータ」分類
- 非公開の部品型番、アクセスを許可されていないファイルや短命プロセスの完全列挙

これらの欠損を別の数値で穴埋めしません。OS・機種・権限による非対応と、計測待ちや取得失敗を分けて表示します。

## 再レビュー後の状態・識別の扱い

- プロセス列挙は戻り値だけでなくerrnoも確認します。Appleの[libproc実装](https://github.com/apple-oss-distributions/xnu/blob/main/libsyscall/wrappers/libproc/libproc.c)では、proc_listpidsがsyscall失敗を0へ変換する経路があるため、呼び出し直前にerrnoをクリアして正常0件と区別します。
- プロセスのCPU・I/O速度には、最後に成功した列挙からの実経過時間をProcessSample.measurementIntervalとして保持し、数値画面とObservationSnapshotへ渡します。
- 外部機器の識別にはIORegistryEntryGetRegistryEntryIDを使用します。シリアル番号を使わず、USB/Thunderboltの属性欠損でも別entryを統合しません。完全な一覧のみ接続イベントの比較に使います。
- 電源種別はkIOPSInternalBatteryTypeで選択し、UPSを内蔵電池として表示しません。デバイス取得は正常な空集合・部分取得・API失敗を分離します。
- powermetricsの解析上限（12,000末端値・深さ15）で省略が生じた場合は、結果集合を部分取得と明示します。未読フィールドを非対応と断定しません。
