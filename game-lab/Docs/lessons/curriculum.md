# AIBOU：相棒から受ける20の小さな授業

調査・編集日：2026年9月15日。本文の正本は [LessonCatalog.swift](../../Sources/Core/LessonCatalog.swift)。展示のIDと所属は [ExhibitionCatalog.swift](../../Sources/Core/ExhibitionCatalog.swift) を維持する。

## 今回選んだ授業の形

女の子に話しかけ、知りたい問いを選び、机の上の模型を操作し、理由を確かめる。1授業は「問いと説明 → 小さな実験 → 条件を明記した3択 → 自分のPCとの接続」の4段階にする。女の子は答えを読むだけでなく、予想する対象、見るべき変化、そこから言えることを伝える。間違えたときも、何を分けて考えるとよいかを具体的に返す。

これは今回の製品設計上の選定であり、対象利用者で学習効果が実証されたという主張ではない。授業後に一問答えられることと、理解が定着して自分の状況へ応用できることも同一視しない。今後の利用観察では、時間を置いた再説明、条件を変えた予想、実際のラボ画面の読み取りを確認する。

全20授業を提供するが、20の本編ミニゲームが完成したという意味ではない。授業内実験は焦点を絞った独立した模型。本編へ進めるものは、現時点で実装されている論理回路のみ。授業の進捗と本編の完成作品は別に記録する。

## 授業の並べ方

展示館の5分野×4入口を維持する。興味のある授業へ直接入れるようにし、履修の強制ロックは設けない。基本語を各授業内で説明するため、上から順に受けなくても成立する。

初めての利用者に案内するなら、次の順が自然である。

- **PCの全体像から**：PC内部の処理の流れ → メモリとデータ保存 → CPUの時間配分とタスク管理 → PC性能とボトルネック。
- **回路のしくみから**：ビットとデータ表現 → 論理回路 → 記憶回路 → トランジスタとスイッチング。
- **身近な疑問から**：消費電力とバッテリー、接続端子と通信・給電、ディスプレイと映像表示など、利用者が今知りたいものを選ぶ。

この案内順は資料の講義順をそのまま転用せず、AIBOUの日常利用への接続を優先した設計判断である。

## 20授業の到達目標・実験・理解確認

問題は実験の現在値と独立している。計算に使う初期値・処理順・省略条件を問題文で明示し、可変UIを動かしたことで正解が変わる設計を避ける。

| 展示ID／授業 | 到達目標と実験の焦点 | 固定条件の理解確認 | 根拠となる一次資料 |
|---|---|---|---|
| H02 `bit-art`／0と1で、何を表せる？ | ビットの組み合わせを数へ対応づける。0/1を切り替え、位の重みと合計を見る。 | 独立した3ビットは8通り。 | [MIT 6.004：情報と符号化](https://ocw.mit.edu/courses/6-004-computation-structures-spring-2017/pages/c1/)。 |
| H03 `circuit-atelier`／条件を組み合わせる回路 | ANDで入力の4組を比較。成功した一回だけでなく、条件全体を確認する。 | A＝1・B＝0の二入力ANDは0。 | [MIT 6.004：組み合わせ論理](https://ocw.mit.edu/courses/6-004-computation-structures-spring-2017/pages/c4/c4s2/)。 |
| H04 `memory-switch`／前の合図を覚えるしくみ | 入力と記憶を分離し、取り込み・保持を切り替える。 | 通電したDラッチに1を取り込み保持した後、入力を0にしても記憶は1。 | [MIT 6.004：Digital StateとD Latch](https://ocw.mit.edu/courses/6-004-computation-structures-spring-2017/pages/c5/c5s2/)。 |
| H19 `tiny-switch-workshop`／電気で動く小さなスイッチ | 制御の合図が別の通り道を開くことを観察。 | 「制御ONで通す」という模型では、制御をONにする。 | [MIT 6.004：MOSFETとCMOS](https://ocw.mit.edu/courses/6-004-computation-structures-spring-2017/pages/c3/c3s2/)。 |
| H05 `instruction-atelier`／CPUと命令の順番 | 命令を入れ替え、途中値と答えを見る。周波数と性能も区別。 | 2に3を足した後2倍すると10。 | [MIT：命令セット](https://ocw.mit.edu/courses/6-004-computation-structures-spring-2017/pages/c9/)、[Intel：周期あたりの仕事と周波数](https://www.intel.com/content/www/us/en/gaming/resources/cpu-clock-speed.html)。 |
| H07 `work-dispatch`／CPUの時間を分ける | 一つのCPUで仕事を交代し、反応までと完了までを比較。 | 交代すれば両方が少しずつ進むが、能力が二倍になるわけではない。 | [OSTEP第7章：スケジューリング](https://pages.cs.wisc.edu/~remzi/OSTEP/cpu-sched.pdf)、[Apple：CPU使用状況](https://support.apple.com/ja-jp/guide/activity-monitor/actmntr43452/mac)。 |
| H08 `parallel-factory`／同時にできる仕事・待つ仕事 | 働き手と依存関係を変え、待つ工程を見つける。 | 1秒のAの結果を使う1秒のBは、受け渡しゼロでも最短2秒。 | [MIT 6.004：並列処理](https://ocw.mit.edu/courses/6-004-computation-structures-spring-2017/pages/c21/)。 |
| H12 `pixel-factory`／GPUが得意な仕事 | 多くの点に同じ計算を行い、処理レーンで比較。 | 各画素を独立に明るくする処理は並列化しやすい。 | [NVIDIA：GPUのスレッドとホストの役割](https://docs.nvidia.com/cuda/cuda-programming-guide/01-introduction/programming-model.html)、[Apple：GPU処理とデータ移動](https://developer.apple.com/videos/play/tech-talks/10580/)。 |
| H06 `memory-dock`／メモリと保存は別の役割 | 保存と解放の前後で机と棚を比較。 | 編集中の作品が机に残る模型では、保存だけで机の使用量は減らない。 | [MIT：記憶階層と不揮発保存](https://ocw.mit.edu/courses/6-004-computation-structures-spring-2017/pages/c14/c14s2/)、[Apple：メモリプレッシャーと使用量](https://support.apple.com/ja-jp/guide/activity-monitor/actmntr1004/mac)。 |
| H09 `cache-delivery`／よく使うデータを手元に置く | 同じ要求を再び出し、ヒットとミスを比較。 | 空の容量1キャッシュにAを残し、他要求なしにAを読むとヒット。 | [MIT：局所性とキャッシュ](https://ocw.mit.edu/courses/6-004-computation-structures-spring-2017/pages/c14/c14s2/)。 |
| H10 `memory-rescue`／メモリが混み合ったとき | 可逆圧縮と退避で、場所と読み戻しの負担を比較。 | ストレージへの一時退避はスワップ。 | [Apple：圧縮、キャッシュ、スワップの定義](https://support.apple.com/ja-jp/guide/activity-monitor/actmntr1004/mac)。 |
| H11 `storage-warehouse`／保存できる量と、運べる速さ | 転送量と速度を変え、時間を比較。容量との違いを確認。 | 同量を同速度で転送するなら、容量だけ二倍にしても転送時間は同じ。 | [MIT：記憶技術と階層](https://ocw.mit.edu/courses/6-004-computation-structures-spring-2017/pages/c14/c14s2/)、[OSTEP：入出力装置](https://pages.cs.wisc.edu/~remzi/OSTEP/file-devices.pdf)。 |
| H13 `display-studio`／解像度・FPS・Hz | フレーム生成と表示更新を別々に変更。 | 補間なしでアプリ30FPSのまま表示だけ120Hzにしても、新しい絵は毎秒30枚。 | [Apple：更新頻度の設定と映像のフレームレート](https://support.apple.com/ja-jp/102297)。 |
| H14 `packet-express`／通信の遅延と帯域 | 届き始めるまでと、全部届くまでを比較。 | 転送時間を無視する微小通信なら、帯域だけ二倍でも往復100msは変わらない。 | [Cloudflare：遅延、帯域、スループット](https://www.cloudflare.com/en-gb/learning/performance/glossary/what-is-latency/)。 |
| H17 `board-town`／部品を結ぶデータの道 | 部品の役割と共有経路を観察。配置と役割を区別。 | 共通経路が毎秒10個までなら、送り手が二つでも合計上限は10個。 | [Apple：CPUとGPUの統合メモリ](https://developer.apple.com/videos/play/tech-talks/10580/)、[OSTEP：入出力のシステム構成](https://pages.cs.wisc.edu/~remzi/OSTEP/file-devices.pdf)。 |
| H18 `connection-lab`／挿さる形と、できること | 機器とケーブルの対応条件を組み合わせる。 | 映像非対応ケーブルでは、形が合ってもその映像を送れない。 | [USB-IF：通信速度と給電能力の別表示](https://www.usb.org/cable_connector)、[Apple：Macのポートと対応](https://support.apple.com/ja-jp/109523)。 |
| H01 `pc-day`／写真一枚が動かすPCの仕事 | 開く・編集・保存に伴う、部品の役割を追う。 | 編集結果をファイルとして残すのはストレージへ保存する役割。 | [OSTEP：入出力装置](https://pages.cs.wisc.edu/~remzi/OSTEP/file-devices.pdf)、[MIT：作業メモリ・ストレージ](https://ocw.mit.edu/courses/6-004-computation-structures-spring-2017/pages/c14/c14s2/)。 |
| H15 `battery-voyage`／残っている量と、使う速さ | 残存エネルギーと一定の消費電力から時間を比較。 | 損失なし、40Whを一定10Wで使う模型なら4時間。 | [Apple：使用条件と電池の持続時間](https://www.apple.com/batteries/maximizing-performance/)。数値例は単位定義から作成した独自の計算問題。 |
| H16 `cooling-workshop`／生まれる熱と、逃がす熱 | 発熱と放熱を変え、温度の傾向を見る。 | 熱が逃げるより多く生まれる条件を続けると、最初は温度が上がる。 | [Apple：温度センサーと冷却](https://support.apple.com/ja-jp/102336)、[Intel：電力・温度による周波数の条件](https://www.intel.com/content/www/us/en/gaming/resources/how-intel-technologies-boost-cpu-performance.html)。 |
| H20 `bottleneck-detective`／待ち時間の原因を探す | 一工程だけ速め、同じ仕事で効果を比較。 | 直列8秒・2秒・2秒のいずれか一工程を半分にするなら、8秒の工程が最も短縮できる。 | [Intel：仕事によって変わる制限部分](https://www.intel.com/content/www/us/en/gaming/resources/what-is-bottlenecking-my-pc.html)。数値例はAIBOU独自。 |

## 誤解を防ぐために決めた境界

**メモリ使用量が多い＝異常、とは教えない。** Appleはメモリプレッシャーに空きメモリ、スワップ率、確保済みメモリ、ファイルキャッシュが関わると説明している。このため授業では空き容量の数値だけから不足を判断させず、保存・解放・圧縮・退避の役割と、PCの反応を分けて扱う。[Apple公式ガイド](https://support.apple.com/ja-jp/guide/activity-monitor/actmntr1004/mac)

**CPU使用率を性能の点数にしない。** 処理時間の配分と、完了までの時間は別の量。周波数も周期あたりの命令処理や仕事の性質に依存する。授業の模型は「同じ条件で比較する」ためのもので、実機への倍率予測には使わない。[OSTEPのスケジューリング指標](https://pages.cs.wisc.edu/~remzi/OSTEP/cpu-sched.pdf)、[Intelのクロック解説](https://www.intel.com/content/www/us/en/gaming/resources/cpu-clock-speed.html)

**GPUなら何でも速い、と教えない。** 並列化のしやすさと、仕事の準備・受け渡しを含めて説明する。NVIDIAのモデルをAppleの具体的なコア構造と同一視せず、CPU/GPUの役割の理解に限定する。統合メモリについてはApple自身の説明を参照する。[NVIDIA Programming Model](https://docs.nvidia.com/cuda/cuda-programming-guide/01-introduction/programming-model.html)、[Apple Metal Compute](https://developer.apple.com/videos/play/tech-talks/10580/)

**USB-Cという形だけで機能を断定しない。** 端子、ケーブル、接続先の対応を一緒に確認する。USB-IFの新旧ロゴや最新規格番号を暗記課題にはせず、能力が別々に存在することを学習対象にする。[USB-IFのケーブル表示](https://www.usb.org/cable_connector)

**模型の温度や電池残量を、ユーザーのPCの診断として見せない。** 実機から取れる値と取れない値を区別し、温度一つで故障や寿命を断定しない。残り時間は一定消費という条件つきの計算であり、電池劣化の予測モデルではない。[Appleの温度ガイド](https://support.apple.com/ja-jp/102336)、[Appleのバッテリーガイド](https://www.apple.com/batteries/maximizing-performance/)

## 女の子の台詞とフィードバック

本文はAIBOU用の新規日本語台詞。資料の文章や授業図を転載していない。基本は「一緒に比べる」「違いに気づく」語り口とする。正解だけを褒めて終わらず、条件と理由を一文で返す。誤答時には罰やランク低下を設けず、具体的な考え方へ戻す。

全授業に `analogyLimit` を持たせ、模型が省略した条件を短く示す。長い注意文を先に読ませるのではなく、実験の意味を解釈する位置で参照できる形を想定する。授業内の数値は「模型」「一定」「損失なし」などの条件を持ち、実測値として表示しない。

常時の女の子の動きは、ユーザー指定の瞬きのみ。場面の表情・ポーズ差分は授業の段階に応じた静止状態として切り替える。身体を揺らすことで反応を表現しない。

## 実装と検証

- 全20件のID・順序・所属を既存の展示カタログへ対応させた。
- `LessonDefinition` に問い、目標、導入、説明、比喩の限界、操作対象、3択と正誤の理由、まとめ、ラボへの接続、出典を保存する。
- 説明本文は89〜110文字で、図や操作領域と同居できる長さに抑えた。
- `LessonCatalogTests` は、欠けた授業・重複ID・活動種別の漏れ・不正な正答番号・出典の欠落・JSON往復の破損・数値問題の期待値を確認する。
- 実行：`cd game-lab && swift test --filter LessonCatalogTests`。2026-09-15、5件合格、0失敗。
- UIでの読みやすさ、操作内容と説明の一致、学習結果の永続化は、統合側の検証で別途確認する。

単元の内容は一次資料と整合するよう編集したが、学習者による有用性の検証は別工程である。公開後の授業改善では、正答率だけでなく、何を見てどのように説明したかを確認する。
