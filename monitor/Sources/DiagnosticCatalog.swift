import Foundation

enum DiagnosticCatalog {
    static let cases: [DiagnosticCase] = [
        // MARK: - 温度・冷却
        d("thermal-pressure", "温度・冷却", "OSの熱負荷上昇（性能抑制の可能性）", ["処理が急に遅くなる", "ファンが高回転になる"], ["吸排気口の閉塞", "冷却系の汚れや故障", "高温環境", "高い演算負荷"], ["平らで通気のよい場所へ移す", "負荷の高い処理を終了して温度が下がるまで待つ"], ["OSの熱状態とCPU使用率を同時に確認", "内部温度とファン回転数は機種依存で本アプリでは取得不可", "ケースやスタンドが吸排気口を塞いでいないか確認"], .thermalPressure, thermalSource),
        d("fan-always-fast", "温度・冷却", "ファンが常に高速", ["アイドル時にもファン音が大きい"], ["温度センサーや冷却ファンの異常", "内部のほこり"], ["高負荷アプリを終了する", "再起動後も続く場合はApple Diagnosticsを実行する"], ["CPU使用率と温度状態を確認", "周囲温度と設置面を確認"], .manual, thermalSource),
        d("fan-not-spinning", "温度・冷却", "高負荷でもファン音がしない", ["本体が熱いのに冷却音が変わらない", "突然終了する"], ["ファンやファン制御回路の故障"], ["負荷を止めて電源を切り、冷えるまで使用を控える", "Apple Diagnosticsまたは修理相談を利用する"], ["温度状態が高いか確認", "機種がファンレスか仕様を確認"], .manual, diagnosticsSource),
        d("localized-hotspot", "温度・冷却", "筐体の一部が異常に熱い", ["特定箇所だけ触れにくいほど熱い"], ["バッテリーや電源回路の局所発熱", "冷却部品の接触不良"], ["充電器と周辺機器を外し、電源を切る", "膨張や臭いがあれば使用を中止して修理相談する"], ["発熱位置と発生条件を記録", "外観の変形や異臭を確認"], .manual, thermalSource),
        d("thermal-shutdown", "温度・冷却", "高温時の突然の終了", ["高負荷中に電源が落ちる", "冷却後は起動する"], ["冷却能力不足", "温度センサーまたは電源系の異常"], ["負荷と周囲温度を下げる", "再発時はApple Diagnosticsを実行する"], ["終了前の温度状態とCPU使用率を記録", "同じ作業で再現するか安全な範囲で確認"], .manual, diagnosticsSource),
        d("cold-environment", "温度・冷却", "低温環境で動作が不安定", ["寒い場所で起動しない", "バッテリー駆動時間が短い"], ["動作温度範囲外", "結露"], ["電源を切ったまま室温になじませる", "結露が疑われる間は充電しない"], ["使用場所の温度と湿度を確認"], .manual, thermalSource),
        d("blocked-vent", "温度・冷却", "吸排気の妨げ", ["柔らかい面で使うと熱くなる", "ファン音が増える"], ["寝具やほこりによる通気阻害"], ["硬く平らな面で使う", "外側の吸排気口を乾いた柔らかいブラシで清掃する"], ["設置場所を変えたときの温度状態を比較"], .manual, thermalSource),

        // MARK: - CPU・性能
        d("cpu-sustained-busy", "CPU・性能", "CPU全体の高負荷が継続", ["全体が重い", "発熱や消費電力が増える"], ["CPUを使う処理の飽和", "冷却不足による性能低下の可能性"], ["不要な高負荷処理を終了する", "kernel_taskは温度管理を助ける場合があるため強制終了しない", "完了待ちの処理なら電源接続と放熱を確保する"], ["アクティビティモニタでCPU上位プロセスを確認", "kernel_taskが高い場合は熱状態と通気も確認"], .cpuBusy, cpuSource, "", [kernelTaskSource]),
        d("single-core-busy", "CPU・性能", "特定コアの高負荷が継続", ["一部の処理だけ遅い", "全体CPUが低くても反応が鈍い"], ["単一スレッドまたは直列処理の飽和", "アプリの待機・ループ"], ["該当処理を終了または再起動する", "再現するアプリを更新する"], ["コア別使用率と実行中プロセスを確認"], .coreBusy, cpuSource),
        d("general-slowness", "CPU・性能", "全般的な動作低下", ["アプリ起動や切替が遅い"], ["熱による抑制", "ストレージまたはメモリの不調"], ["再起動して再現を確認", "空き容量とCPU負荷を確認する"], ["温度、CPU、swap、空き容量をまとめて確認"], .manual, cpuSource),
        d("beachball", "CPU・性能", "待機カーソルが頻発", ["虹色カーソルが長く続く"], ["ストレージ応答遅延", "メモリ不足", "周辺機器の待ち"], ["反応しないアプリを終了する", "外付け機器を外して再現を確認する"], ["発生中のCPU、swap、空き容量を確認"], .manual, cpuSource),
        d("unexpected-restart", "CPU・性能", "予期しない再起動", ["操作中に再起動する", "問題が起きた旨の表示が出る"], ["メモリ、基板、電源、周辺機器の異常"], ["周辺機器を外して更新を適用する", "繰り返す場合はApple Diagnosticsを実行する"], ["再現条件と接続機器を記録", "解析にはパニックログが必要だが本アプリでは取得不可"], .manual, restartSource),
        d("freeze", "CPU・性能", "画面と入力が固まる", ["ポインタやキー入力に反応しない"], ["メモリやストレージの不調", "GPUまたは基板の異常"], ["しばらく待って復帰しなければ安全に再起動する", "再発時は周辺機器を減らす"], ["発生直前の負荷と温度を記録"], .manual, diagnosticsSource),
        d("performance-on-battery", "CPU・性能", "バッテリー時だけ遅い", ["電源を外すと処理速度が下がる"], ["バッテリーの劣化や電力供給能力低下"], ["低電力モード設定を確認する", "バッテリー状態をシステム設定で確認する"], ["外部電源の有無で同じ処理を比較"], .manual, batterySource),
        d("benchmark-drop", "CPU・性能", "長時間処理で性能が落ちる", ["開始直後より処理時間が延びる"], ["冷却飽和", "電源アダプタの供給不足"], ["純正または適合電力のアダプタを使う", "通気を確保して負荷を分散する"], ["温度状態と充電状態を時系列で確認"], .manual, thermalSource),

        // MARK: - メモリ
        d("swap-allocated", "メモリ", "swap領域が割り当て済み", ["ディスクアクセスを伴う遅延が起きることがある"], ["RAM容量不足の可能性", "メモリ部品の異常はこの値だけでは判断不可"], ["不要な大容量アプリやタブを閉じる", "再起動後の増え方を観察する"], ["アクティビティモニタのメモリプレッシャーも確認"], .swapAllocated, memorySource, "swapUsedは割り当て履歴を含み、現在のメモリ不足や故障を単独では示さない。本アプリはメモリプレッシャーを取得しない。"),
        d("memory-pressure", "メモリ", "メモリプレッシャー上昇", ["アプリ切替が遅い", "圧縮やswapが増える"], ["作業量に対するRAM容量不足", "特定アプリの過大なメモリ消費"], ["使用量の大きいアプリを終了する", "常駐項目を見直す"], ["アクティビティモニタでメモリプレッシャーを手動確認", "本アプリはメモリプレッシャーを取得不可"], .manual, memorySource),
        d("app-memory-errors", "メモリ", "複数アプリが不規則に終了", ["異なるアプリでクラッシュが続く"], ["RAMやメモリコントローラの異常"], ["macOSとアプリを更新する", "Apple Diagnosticsを実行する"], ["特定アプリだけか複数か確認", "本アプリはクラッシュログを取得しない"], .manual, diagnosticsSource),
        d("boot-memory-beeps", "メモリ", "起動時のビープ音・メモリエラー表示", ["起動せず音や記号が出る"], ["RAMの未認識または故障"], ["電源を切り、増設可能機種は装着状態を専門家に確認してもらう", "Appleサポートへ連絡する"], ["音の回数や画面表示を記録"], .manual, bootMemorySource),
        d("memory-after-upgrade", "メモリ", "メモリ交換後の不安定化", ["増設後から起動失敗やクラッシュが起きる"], ["非対応メモリ", "装着不良"], ["機種仕様に適合するか確認する", "作業者または修理窓口に装着確認を依頼する"], ["交換前後で症状を比較"], .manual, diagnosticsSource),

        // MARK: - ストレージ
        d("storage-low", "ストレージ", "起動ディスクの空き容量不足", ["保存や更新に失敗する", "動作が遅くなる"], ["SSD故障ではなく空き領域不足の可能性"], ["不要な大容量ファイルをバックアップ後に整理する", "macOSのストレージ管理を使う"], ["空き容量と総容量を確認"], .storageLow, storageSource, "10 GiB未満または総容量の10%未満をAIBOUの注意目安とする。Appleの故障判定基準ではない。"),
        d("storage-read-write-error", "ストレージ", "読み書きエラー", ["ファイルを開けない", "コピーが途中で失敗する"], ["SSD、ケーブル、外付けケースの異常"], ["重要データを直ちに別媒体へバックアップする", "ディスクユーティリティのFirst Aidを実行する"], ["内蔵と外付けのどちらで発生するか確認"], .manual, diskUtilitySource),
        d("storage-not-mounted", "ストレージ", "ディスクがマウントされない", ["Finderにボリュームが出ない"], ["ドライブ、ケーブル、ポート、電源の異常"], ["別のケーブルとポートで確認する", "ディスクユーティリティで認識状態を確認する"], ["システム情報に機器が見えるか確認"], .manual, diskUtilitySource),
        d("storage-slow", "ストレージ", "ストレージ応答が遅い", ["保存や起動に時間がかかる"], ["SSD劣化", "外付け接続速度やケーブルの問題"], ["バックアップを作成する", "別ポート・適合ケーブルで比較する"], ["空き容量を確認", "本アプリはI/O速度とSMARTを取得しない"], .manual, diskUtilitySource),
        d("smart-warning", "ストレージ", "SMART警告", ["ディスクユーティリティで致命的エラー表示"], ["ストレージ媒体の故障予兆"], ["書き込みを減らして直ちにバックアップする", "修理または交換を手配する"], ["ディスクユーティリティでSMART状態を手動確認", "本アプリはSMARTを取得不可"], .manual, smartSource),
        d("filesystem-errors", "ストレージ", "ファイルシステムエラー", ["フォルダが開けない", "起動ディスク検証に失敗する"], ["媒体エラー", "不意の電源断による論理破損"], ["バックアップ後に復旧環境からFirst Aidを実行する", "修復不能ならAppleサポートへ相談する"], ["First Aidの結果を保存"], .manual, diskUtilitySource),
        d("external-drive-disconnect", "ストレージ", "外付けドライブが切断される", ["使用中に取り外し通知が出る"], ["ケーブル、ハブ、ポート、電力不足"], ["Macへ直接接続する", "短い適合ケーブルと外部電源付きハブを試す"], ["接続経路を一つずつ変えて再現確認"], .manual, usbSource),
        d("storage-noise", "ストレージ", "ドライブから異音", ["クリック音や擦れる音が続く"], ["回転式外付けドライブの機械故障"], ["使用を止めて電源を切る", "再通電を繰り返さずデータ復旧業者へ相談する"], ["音がMac本体か外付けドライブか切り分け"], .manual, diskUtilitySource),

        // MARK: - バッテリー・電源
        d("battery-low", "バッテリー・電源", "バッテリー残量が少ない", ["まもなくスリープまたは終了する可能性"], ["通常の放電または充電機会不足", "接続しても充電できない場合は充電器やポートの不調候補"], ["適合する電源アダプタへ接続する", "充電が始まるか確認する"], ["残量、充電中、外部電源の表示を確認"], .batteryLow, batterySource),
        d("battery-critical", "バッテリー・電源", "バッテリー残量が重大", ["保存前に電源が切れる恐れ"], ["通常の放電または充電機会不足", "接続しても回復しない場合はバッテリーまたは充電系統の不調候補"], ["作業を保存して直ちに適合電源へ接続する", "充電できなければ電源を切る"], ["外部電源認識と充電状態を確認"], .batteryCritical, batterySource),
        d("charging-paused", "バッテリー・電源", "外部電源中だが充電していない", ["電源接続中に非充電と表示される"], ["満充電、最適化充電または充電上限", "高温やアダプタ・ケーブル・ポートの供給不足", "これらを除外して続く場合はバッテリー不調候補"], ["本体を冷まし接続を確認する", "適合する電力のアダプタを直接接続する"], ["最適化充電や充電上限の設定も確認"], .chargingPaused, chargingSource, "外部電源を認識しながら非充電である状態だけを示す。最適化充電、充電上限、温度管理など正常な理由があり、故障判定ではない。"),
        d("battery-service", "バッテリー・電源", "バッテリー修理推奨表示", ["バッテリー設定に修理サービス推奨が出る"], ["セル劣化や内部異常"], ["バックアップを取りAppleまたは正規サービスへ相談する"], ["システム設定のバッテリー状態を手動確認"], .manual, batterySource),
        d("battery-runtime-short", "バッテリー・電源", "駆動時間が短い", ["満充電から急速に減る"], ["バッテリー劣化", "温度や高負荷"], ["エネルギー使用量の大きいアプリを終了する", "バッテリー状態を確認する"], ["同じ負荷で減少量を比較", "設計容量・サイクル数・OSの最大容量比率は未取得。満充電容量は対応機種で条件付き取得"], .manual, batterySource),
        d("battery-sudden-drop", "バッテリー・電源", "残量表示が急減・突然終了", ["残量があるのに電源が落ちる"], ["セル不均衡", "バッテリーまたは電源回路の故障"], ["重要データを保存して電源接続で使う", "Apple Diagnosticsと修理相談を利用する"], ["発生時の残量と負荷を記録"], .manual, diagnosticsSource),
        d("battery-swelling", "バッテリー・電源", "バッテリー膨張の疑い", ["底面やトラックパッドが浮く", "筐体に隙間が出る"], ["バッテリーセルの膨張", "落下による筐体変形"], ["電源を切り、押し戻したり穴を開けたりせず使用を中止する", "Appleまたは正規サービスへ相談する"], ["平らな面で筐体の変形を目視確認"], .manual, safetySource),
        d("adapter-not-recognized", "バッテリー・電源", "電源アダプタを認識しない", ["接続しても外部電源表示にならない"], ["アダプタ、ケーブル、ポート、電源回路の故障"], ["コンセント、ケーブル、ポートを順に確認する", "適合する別のアダプタで比較する"], ["ポート内の異物や損傷を目視確認"], .manual, chargingSource),
        d("power-on-failure", "バッテリー・電源", "電源が入らない", ["電源ボタンに反応しない"], ["バッテリー、アダプタ、ロジックボードの故障"], ["電源接続を確認し周辺機器を外す", "Appleの起動手順に従い修理相談する"], ["別のコンセントと適合アダプタを確認"], .manual, powerOnSource),

        // MARK: - ネットワーク
        d("wifi-no-network", "ネットワーク", "Wi-Fiネットワークが見つからない", ["他端末には見えるSSIDが表示されない"], ["Wi-Fiアンテナや無線モジュールの異常"], ["Wi-Fiを入れ直しMacとルーターを再起動する", "別の場所やネットワークで比較する"], ["本アプリはRSSI、SNR、リンク速度を取得しない", "ワイヤレス診断を実行"], .manual, wifiSource),
        d("wifi-frequent-drop", "ネットワーク", "Wi-Fiが頻繁に切れる", ["接続と切断を繰り返す"], ["アンテナ接触不良", "電波干渉やルーター設定"], ["ルーターへ近づき干渉源を離す", "ワイヤレス診断を実行する"], ["別ネットワークでも再現するか確認"], .manual, wifiSource),
        d("wifi-slow", "ネットワーク", "Wi-Fi通信が遅い", ["転送速度や応答が不安定"], ["アンテナ性能低下", "距離・干渉・回線混雑"], ["ルーターに近づけて比較する", "推奨設定と更新を確認する"], ["有線接続と別端末で比較", "本アプリではリンク品質を測定不可"], .manual, wifiSource),
        d("ethernet-no-link", "ネットワーク", "Ethernetリンクが確立しない", ["有線接続が未接続になる"], ["ケーブル、変換アダプタ、ポートの異常"], ["別ケーブルとポートで試す", "ハブを外して直接接続する"], ["システム設定とシステム情報で認識を確認"], .manual, networkSource),
        d("bluetooth-unavailable", "ネットワーク", "Bluetoothが利用できない", ["Bluetoothをオンにできない", "機器が検出されない"], ["Bluetoothモジュールやアンテナの異常"], ["Macと機器を再起動する", "不要なUSB機器を外して再試行する"], ["複数のBluetooth機器で比較"], .manual, bluetoothSource),
        d("bluetooth-drop", "ネットワーク", "Bluetooth接続が途切れる", ["音声や入力が断続的に切れる"], ["電波干渉や機器側の電池不足", "これらを除外して複数機器で続く場合はアンテナ系統の不調候補"], ["距離を縮め、USB 3機器などの干渉源を離す", "機器を充電して再ペアリングする"], ["別のBluetooth機器で再現確認"], .manual, bluetoothDropSource),
        d("network-only-this-mac", "ネットワーク", "このMacだけ通信できない", ["同じ回線の他端末は正常"], ["無線・有線インターフェースの異常"], ["VPNやプロキシ設定を一時的に確認する", "別ネットワークで比較しワイヤレス診断を使う"], ["ハードウェア構成とネットワーク設定の両方を確認"], .manual, networkSource),

        // MARK: - 画面・GPU
        d("display-black", "画面・GPU", "内蔵画面が真っ暗", ["起動音や動作音はあるが表示されない"], ["バックライト、表示ケーブル、GPU、基板の異常"], ["明るさを上げ外部ディスプレイで確認する", "周辺機器を外して再起動する"], ["懐中電灯で薄い像が見えるか確認", "外部画面への出力有無を確認"], .manual, displaySource),
        d("display-flicker", "画面・GPU", "画面のちらつき", ["輝度や表示が周期的に揺れる"], ["表示ケーブル、パネル、GPUの異常"], ["可変リフレッシュや自動輝度設定を確認する", "外部画面とセーフモードで比較する"], ["角度を変えると再現するか確認"], .manual, displaySource),
        d("display-lines", "画面・GPU", "線・色むら・表示欠け", ["縦線、横線、変色が残る"], ["液晶パネル、表示ケーブル、GPUの故障"], ["スクリーンショットと外部画面で切り分ける", "物理損傷があれば修理相談する"], ["スクリーンショットにも写るか確認"], .manual, displaySource),
        d("external-display-not-detected", "画面・GPU", "外部ディスプレイを検出しない", ["接続しても画面設定に現れない"], ["ケーブル、変換器、ポート、ディスプレイの異常"], ["対応ケーブルで直接接続する", "ディスプレイの入力選択と電源を確認する"], ["別ポート・別画面で比較"], .manual, externalDisplaySource),
        d("external-display-artifacts", "画面・GPU", "外部画面のノイズ・瞬断", ["点滅、砂嵐、色化けが出る"], ["帯域不足やケーブル不良", "GPUまたはポート異常"], ["解像度とリフレッシュレートを下げる", "認証済みの短いケーブルで直接接続する"], ["別ケーブルと内蔵画面で比較"], .manual, externalDisplaySource),
        d("gpu-heavy-lag", "画面・GPU", "描画処理で著しく遅い", ["動画や3D表示だけ引っかかる"], ["GPUの熱・電源・基板異常"], ["高負荷アプリを終了し温度を下げる", "macOSとアプリを更新する"], ["外部画面を外して比較", "本アプリはGPU使用率とFPSを取得しない"], .manual, displaySource),
        d("camera-no-image", "画面・GPU", "内蔵カメラが映らない", ["カメラ映像が黒い", "認識されない"], ["カメラモジュールや接続ケーブルの異常"], ["カメラ使用中の他アプリを終了する", "再起動して複数アプリで試す"], ["プライバシー権限と緑の表示灯を確認"], .manual, cameraSource),

        // MARK: - 入力・周辺機器
        d("keyboard-keys", "入力・周辺機器", "キーが反応しない・連打される", ["特定キーの欠落や二重入力"], ["キー機構、ケーブル、液体侵入の異常"], ["電源を切って表面を適切に清掃する", "外付けキーボードで切り分ける"], ["入力ソースとキーリピート設定を確認"], .manual, keyboardSource),
        d("trackpad-failure", "入力・周辺機器", "トラックパッドが反応しない", ["クリックやポインタ移動ができない"], ["トラックパッド、ケーブル、膨張バッテリーの異常"], ["外付けポインティング機器を接続する", "浮きや変形があれば使用を中止する"], ["セーフモードと外付けマウスで比較"], .manual, trackpadSource),
        d("usb-not-recognized", "入力・周辺機器", "USB機器を認識しない", ["接続しても機器が現れない"], ["ポート、ケーブル、ハブ、機器の故障"], ["別ポートと別ケーブルで直接接続する", "必要な電力を供給できるハブを使う"], ["システム情報のUSB欄で認識を確認"], .manual, usbSource),
        d("usb-overcurrent", "入力・周辺機器", "USB電力消費の警告", ["アクセサリに電力が必要と表示される"], ["機器またはケーブルの短絡", "ポートの供給不足"], ["該当機器を外す", "外部電源付きハブまたは適合アダプタを使う"], ["機器を一台ずつ接続して原因を特定"], .manual, usbSource),
        d("port-intermittent", "入力・周辺機器", "ポート接続が不安定", ["ケーブルに触れると接続が切れる"], ["端子摩耗、異物、はんだ接合の異常"], ["使用を止めポート内を目視確認する", "無理に清掃せず修理相談する"], ["別ポートと別ケーブルで比較"], .manual, usbSource),
        d("audio-output-failure", "入力・周辺機器", "スピーカー・音声出力の異常", ["音が出ない", "片側だけ、音割れがある"], ["スピーカー、端子、オーディオ回路の異常"], ["出力先と音量を確認する", "ヘッドフォンや別ユーザーで比較する"], ["起動音や複数アプリで再現するか確認"], .manual, soundSource),
        d("microphone-failure", "入力・周辺機器", "マイク入力の異常", ["録音できない", "雑音や極端に小さい音"], ["マイク、ケーブル、音声回路の異常"], ["入力デバイスと入力音量を確認する", "ケースや異物が開口部を塞いでいないか確認する"], ["ボイスメモなど複数アプリで比較"], .manual, soundSource),

        // MARK: - 起動・スリープ
        d("startup-question-mark", "起動・スリープ", "疑問符フォルダで起動停止", ["点滅する疑問符フォルダが出る"], ["起動ディスク未認識", "SSDや基板の故障"], ["復旧環境で起動ディスクとFirst Aidを確認する", "見つからなければ修理相談する"], ["ディスクユーティリティで内蔵ディスクが見えるか確認"], .manual, questionMarkSource),
        d("startup-prohibited", "起動・スリープ", "禁止マークで起動停止", ["丸に斜線の記号が出る"], ["起動ディスク上のmacOSのバージョンまたはビルドがこのMacと互換しない"], ["Appleの手順に従って復旧環境からmacOSを再インストールする", "先にバックアップ可能性を確認する"], ["起動ディスクとインストールしたmacOSの対応を確認"], .manual, prohibitedSource),
        d("startup-loop", "起動・スリープ", "再起動を繰り返す", ["ログイン前後で何度も再起動する"], ["メモリ、ストレージ、電源、周辺機器の異常"], ["周辺機器を外しセーフモードを試す", "Apple Diagnosticsを実行する"], ["再起動する段階と表示を記録"], .manual, restartSource),
        d("sleep-wake-failure", "起動・スリープ", "スリープから復帰しない", ["画面や入力が戻らない"], ["スリープ設定、バックグラウンド処理、接続周辺機器", "これらを除外して続く場合は表示・電源管理系統の不調候補"], ["電源接続と外部画面を確認する", "周辺機器を外して再現を確認する"], ["設定、実行中処理、電源ランプ、外部画面の反応を確認"], .manual, sleepSource),
        d("unexpected-wake", "起動・スリープ", "勝手にスリープ解除する", ["閉じた状態や夜間に起動する"], ["共有サービス、ネットワークアクセス、バックグラウンド処理、周辺機器", "これらを除外して続く場合は電源管理系統の不調候補"], ["共有、ネットワーク起動、Bluetooth機器を確認する", "接続機器を外して比較する"], ["システム設定のスリープ関連項目を確認"], .manual, sleepSource),
        d("unexpected-sleep", "起動・スリープ", "使用中にスリープする", ["残量があるのに画面が消え休止する"], ["バッテリー・スリープ設定、バックグラウンド処理、周辺機器", "これらを除外して続く場合はバッテリーまたは電源管理系統の不調候補"], ["電源接続で再現を確認する", "設定と接続機器を確認する"], ["発生時の残量、外部電源、温度状態、実行中処理を記録"], .manual, sleepSource),
        d("lid-sensor", "起動・スリープ", "対応機種のふた角度センサー確認", ["ふたを閉じてもスリープしない"], ["対応モデルでのふた角度センサーの修理後の構成・較正不備"], ["修理歴と対応モデルを確認し、Appleまたは正規サービスへ相談する"], ["ふたを閉じたときのスリープ動作と直近のディスプレイ・センサー修理歴を確認"], .manual, lidSensorSource, "ふた角度センサーを備える対応モデルと修理後の確認に限る。"),

        // MARK: - 外観・物理損傷
        d("liquid-exposure", "外観・物理損傷", "液体に触れた", ["濡れた後に入力・充電・画面が不安定"], ["腐食、短絡、液体侵入"], ["直ちに電源を切り、すべてのケーブルを外す", "熱風や米を使わず修理相談する"], ["通電せず液体の種類と時刻を記録"], .manual, liquidSource),
        d("impact-damage", "外観・物理損傷", "落下・衝撃後の不具合", ["落下後に画面、起動、ポートが不安定"], ["筐体、基板、バッテリー、表示部の損傷"], ["変形や発熱があれば電源を切る", "バックアップ可能なら作成し点検を依頼する"], ["隙間、割れ、曲がり、異臭を目視確認"], .manual, diagnosticsSource),
        d("hinge-damage", "外観・物理損傷", "ヒンジの異音・緩み", ["開閉時に擦れる", "画面角度を保持できない"], ["ヒンジや表示ケーブルの損傷"], ["開閉回数を減らし無理に動かさない", "修理相談する"], ["画面角度で表示が乱れるか確認"], .manual, displaySource),
        d("enclosure-deformation", "外観・物理損傷", "筐体の変形・隙間", ["底面が浮く", "平面でがたつく"], ["バッテリー膨張", "衝撃による変形"], ["電源を切り充電と使用を中止する", "押し戻さず修理相談する"], ["熱や臭いを伴うか離れて目視確認"], .manual, safetySource),
        d("burning-smell", "外観・物理損傷", "焦げ臭・煙・火花", ["焦げた臭い、煙、火花、異常音"], ["バッテリー、電源回路、ケーブルの短絡"], ["安全に可能なら電源を切りコンセントから外す", "再通電せず、煙や発火時はその場を離れて緊急窓口へ連絡する"], ["触れずに発生箇所と接続機器を確認"], .manual, safetySource)
    ]

    private static func d(
        _ id: String, _ category: String, _ title: String,
        _ symptoms: [String], _ causes: [String], _ actions: [String], _ checks: [String],
        _ rule: DiagnosticRule, _ source: String,
        _ limitation: String = "", _ extraSources: [String] = []
    ) -> DiagnosticCase {
        let scope = "Apple資料は確認・対処手順の根拠であり、個別部品の故障を証明しない。部品レベルの原因はAIBOUの切り分け候補で、監視値だけでは確定できない。"
        return DiagnosticCase(id: id, category: category, title: title, symptoms: symptoms, causes: causes, actions: actions, checks: checks, limitation: limitation.isEmpty ? scope : "\(limitation) \(scope)", rule: rule, sources: [source] + extraSources)
    }

    private static let diagnosticsSource = "https://support.apple.com/ja-jp/102550"
    private static let thermalSource = "https://support.apple.com/ja-jp/102336"
    private static let cpuSource = "https://support.apple.com/ja-jp/guide/activity-monitor/actmntr43452/mac"
    private static let kernelTaskSource = "https://support.apple.com/ja-jp/102172"
    private static let memorySource = "https://support.apple.com/ja-jp/guide/activity-monitor/-actmntr1004/mac"
    private static let storageSource = "https://support.apple.com/ja-jp/102624"
    private static let diskUtilitySource = "https://support.apple.com/ja-jp/guide/disk-utility/dskutl1040/mac"
    private static let smartSource = "https://support.apple.com/ja-jp/guide/mac-help/mchlp2548/mac"
    private static let batterySource = "https://support.apple.com/ja-jp/guide/mac-help/mh20865/mac"
    private static let chargingSource = "https://support.apple.com/ja-jp/102588"
    private static let wifiSource = "https://support.apple.com/ja-jp/guide/mac-help/mchlf4de377f/mac"
    private static let networkSource = "https://support.apple.com/ja-jp/guide/activity-monitor/actmntr1006/mac"
    private static let bluetoothSource = "https://support.apple.com/ja-jp/guide/mac-help/blth1004/mac"
    private static let bluetoothDropSource = "https://support.apple.com/102319"
    private static let displaySource = "https://support.apple.com/ja-jp/guide/mac-help/mchl7c7ebe08/mac"
    private static let externalDisplaySource = "https://support.apple.com/ja-jp/guide/mac-help/mchl7c7ebe08/mac"
    private static let cameraSource = "https://support.apple.com/ja-jp/102437"
    private static let usbSource = "https://support.apple.com/ja-jp/102204"
    private static let keyboardSource = "https://support.apple.com/ja-jp/guide/mac-help/mchlp1240/mac"
    private static let trackpadSource = "https://support.apple.com/ja-jp/guide/mac-help/mchlp2857/mac"
    private static let soundSource = "https://support.apple.com/ja-jp/102411"
    private static let restartSource = "https://support.apple.com/ja-jp/102382"
    private static let startupSource = "https://support.apple.com/ja-jp/102675"
    private static let questionMarkSource = "https://support.apple.com/ja-jp/102601"
    private static let prohibitedSource = "https://support.apple.com/ja-jp/101666"
    private static let powerOnSource = "https://support.apple.com/ja-jp/102623"
    private static let bootMemorySource = "https://support.apple.com/ja-jp/102210"
    private static let sleepSource = "https://support.apple.com/ja-jp/guide/mac-help/mchlp2995/mac"
    private static let lidSensorSource = "https://support.apple.com/ja-jp/123126"
    private static let liquidSource = "https://support.apple.com/ja-jp/102249"
    private static let safetySource = "https://support.apple.com/ja-jp/guide/macbook-air/apd9b8f7aa11/mac"
}
