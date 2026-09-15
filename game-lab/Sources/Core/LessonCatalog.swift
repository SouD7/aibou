import Foundation

/// Each activity is a bounded teaching model, not a measurement or a hardware emulator.
public enum LessonActivityKind: String, CaseIterable, Codable, Equatable, Sendable {
    case bits, logic, latch, transistor, instructions, schedule, parallel, pixels
    case memory, cache, compression, storage, frames, network, bus, ports
    case flow, battery, cooling, bottleneck
}

public struct LessonSource: Codable, Equatable, Sendable {
    public let title: String
    public let url: String
}

public struct LessonChallenge: Codable, Equatable, Sendable {
    public let prompt: String
    public let options: [String]
    public let correctIndex: Int
    public let correctFeedback: String
    public let incorrectFeedback: String
}

public struct LessonDefinition: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let question: String
    public let goal: String
    public let intro: String
    public let explanation: String
    public let analogyLimit: String
    public let activity: LessonActivityKind
    public let activityPrompt: String
    public let challenge: LessonChallenge
    public let takeaway: String
    public let labConnection: String
    public let sources: [LessonSource]
}

/// Original Japanese teaching text. Source material supports the concepts, not the
/// invented workshop examples or their deliberately simplified numerical values.
/// Quiz conditions are self-contained and never depend on mutable activity state.
public enum LessonCatalog {
    private static let information = LessonSource(title: "MIT · 情報とビット", url: "https://ocw.mit.edu/courses/6-004-computation-structures-spring-2017/pages/c1/")
    private static let logic = LessonSource(title: "MIT · 組み合わせ回路", url: "https://ocw.mit.edu/courses/6-004-computation-structures-spring-2017/pages/c4/c4s2/")
    private static let state = LessonSource(title: "MIT · 状態を記憶する回路", url: "https://ocw.mit.edu/courses/6-004-computation-structures-spring-2017/pages/c5/c5s2/")
    private static let transistor = LessonSource(title: "MIT · MOSFETとCMOS", url: "https://ocw.mit.edu/courses/6-004-computation-structures-spring-2017/pages/c3/c3s2/")
    private static let instructions = LessonSource(title: "MIT · 命令セットの設計", url: "https://ocw.mit.edu/courses/6-004-computation-structures-spring-2017/pages/c9/")
    private static let memoryHierarchy = LessonSource(title: "MIT · キャッシュと記憶階層", url: "https://ocw.mit.edu/courses/6-004-computation-structures-spring-2017/pages/c14/c14s2/")
    private static let parallel = LessonSource(title: "MIT · 並列処理", url: "https://ocw.mit.edu/courses/6-004-computation-structures-spring-2017/pages/c21/")
    private static let scheduling = LessonSource(title: "OSTEP · CPUの仕事を配分する", url: "https://pages.cs.wisc.edu/~remzi/OSTEP/cpu-sched.pdf")
    private static let inputOutput = LessonSource(title: "OSTEP · 入出力装置", url: "https://pages.cs.wisc.edu/~remzi/OSTEP/file-devices.pdf")
    private static let memory = LessonSource(title: "Apple · メモリ使用状況の読み方", url: "https://support.apple.com/ja-jp/guide/activity-monitor/actmntr1004/mac")
    private static let cpu = LessonSource(title: "Apple · CPUの動作状況", url: "https://support.apple.com/ja-jp/guide/activity-monitor/actmntr43452/mac")
    private static let clock = LessonSource(title: "Intel · クロック周波数と性能", url: "https://www.intel.com/content/www/us/en/gaming/resources/cpu-clock-speed.html")
    private static let gpu = LessonSource(title: "NVIDIA · GPUの並列処理モデル", url: "https://docs.nvidia.com/cuda/cuda-programming-guide/01-introduction/programming-model.html")
    private static let unifiedMemory = LessonSource(title: "Apple · CPUとGPUの共有メモリ", url: "https://developer.apple.com/videos/play/tech-talks/10580/")
    private static let refresh = LessonSource(title: "Apple · ディスプレイの更新頻度", url: "https://support.apple.com/ja-jp/102297")
    private static let latency = LessonSource(title: "Cloudflare · 遅延と帯域の違い", url: "https://www.cloudflare.com/en-gb/learning/performance/glossary/what-is-latency/")
    private static let usb = LessonSource(title: "USB-IF · ケーブルの通信・給電能力", url: "https://www.usb.org/cable_connector")
    private static let ports = LessonSource(title: "Apple · Macのポートを識別する", url: "https://support.apple.com/ja-jp/109523")
    private static let battery = LessonSource(title: "Apple · バッテリーの使い方と持続時間", url: "https://www.apple.com/batteries/maximizing-performance/")
    private static let thermal = LessonSource(title: "Apple · Macの動作温度", url: "https://support.apple.com/ja-jp/102336")
    private static let thermalPerformance = LessonSource(title: "Intel · 電力・温度と動作周波数", url: "https://www.intel.com/content/www/us/en/gaming/resources/how-intel-technologies-boost-cpu-performance.html")
    private static let bottleneck = LessonSource(title: "Intel · PCのボトルネック", url: "https://www.intel.com/content/www/us/en/gaming/resources/what-is-bottlenecking-my-pc.html")

    public static let lessons: [LessonDefinition] = [
        .init(id: "bit-art", title: "0と1で、何を表せる？", question: "小さな合図だけで、数を表せるの？",
              goal: "ビットの組み合わせと、表せる状態の数を結びつける。",
              intro: "この小さな合図は、消えると0、点くと1。ひとつだと二通りだけど、並べるといろいろな数を表せるよ。右から1・2・4と重みを決め、1になった場所を足す約束で、数を作ってみよう。",
              explanation: "ビットは0か1を表す単位。三つなら000から111まで八通り。右から1・2・4の重みを決めると、101は4＋1＝5と読める。並びと読み方の約束を変えれば、数だけでなく色や文字などの情報も表せるんだ。",
              analogyLimit: "灯りは合図のたとえ。PCでは電圧などの物理的な状態を使い、実際の画像は色や形式の情報も持つよ。",
              activity: .bits, activityPrompt: "0と1を切り替えて、1になった場所の重みと、合計した数を見比べよう。",
              challenge: .init(prompt: "0か1を独立に選べるビットが三つ。並び方は全部で何通り？", options: ["3通り", "6通り", "8通り"], correctIndex: 2,
                               correctFeedback: "そう。2×2×2で8通り。ビットを一つ増やすと、選べる並びは二倍になるよ。",
                               incorrectFeedback: "それぞれに0と1の二つの選択があるね。2×2×2で、8通りになるよ。"),
              takeaway: "ビットは合図。組み合わせと読み方の約束で、絵も数字も表せる。",
              labConnection: "ラボのメモリや保存容量に出てくるBはバイトの単位。1バイトは8ビットだよ。",
              sources: [information]),
        .init(id: "circuit-atelier", title: "条件を組み合わせる回路", question: "ふたりとも準備できたときだけ、光らせられる？",
              goal: "入力の全組み合わせを試して、ANDの働きを説明する。",
              intro: "あなたのスイッチがA、私のスイッチがB。両方が1のときだけランプを点けたいんだ。片方だけのときも試せば、部品がどんな約束で働くのか見えてくるよ。",
              explanation: "ANDは、すべての入力が1のときだけ1を出す論理回路。二入力なら00・01・10・11の四通りを調べると働きを確かめられる。ORは少なくとも片方が1、XORは片方だけが1のときに1になるよ。",
              analogyLimit: "ここでは信号が安定した後の結果を見るよ。実物では伝わる時間があり、部品の切り替わりは瞬間的ではないんだ。",
              activity: .logic, activityPrompt: "AとBを切り替えて、どの組み合わせでランプが点くか比べよう。",
              challenge: .init(prompt: "二入力ANDで、A＝1、B＝0。信号が落ち着いた後の出力は？", options: ["0", "1", "前の値のまま"], correctIndex: 0,
                               correctFeedback: "その通り。両方はそろっていないから0。ANDは今の入力の組み合わせで決まるよ。",
                               incorrectFeedback: "ANDは両方が1のときだけ1。今回はBが0だから、出力も0になるよ。"),
              takeaway: "回路の約束は、うまくいった一回だけでなく、入力の全組み合わせで確かめる。",
              labConnection: "ラボに見えるCPUの中でも、小さな論理回路が組み合わされて計算や判断を支えているよ。",
              sources: [logic]),
        .init(id: "memory-switch", title: "前の合図を覚えるしくみ", question: "入力を戻したのに、どうして合図が残るの？",
              goal: "今の入力と、記憶されている状態を区別する。",
              intro: "今度の装置は、入力を見るだけでは答えがわからないよ。一度覚えた合図を、そのまま持っていられるんだ。入力を変える前と後で、覚えている値を比べてみよう。",
              explanation: "記憶を持つ回路では、過去の状態も結果に関わる。たとえばDラッチは、取り込みを許可している間は入力を反映し、許可を閉じると値を保持する。新しい入力と、保持した値が違うこともあるよ。",
              analogyLimit: "取り込みと保持を単純化した模型だよ。ここで扱う電子回路の記憶は、電源を切っても残る保存とは別なんだ。",
              activity: .latch, activityPrompt: "値を記憶した後に入力を変えて、入力と記憶が同じかどうか確かめよう。",
              challenge: .init(prompt: "電源が入ったDラッチに1を取り込み、保持に切り替えた。その後、入力だけを0にすると記憶は？", options: ["0に変わる", "1のまま", "値が二つになる"], correctIndex: 1,
                               correctFeedback: "そう。保持している間は、新しい入力ではなく、取り込んだ1を覚えているよ。",
                               incorrectFeedback: "入力と記憶を分けて考えよう。保持に切り替えた後なので、覚えている値は1のままだよ。"),
              takeaway: "記憶があると、今の入力だけでなく、それまでの出来事も扱える。",
              labConnection: "作業中の状態を持つメモリにつながる考え方だよ。メモリの使用量から個々の記憶回路の値は読めないんだ。",
              sources: [state, memoryHierarchy]),
        .init(id: "tiny-switch-workshop", title: "電気で動く小さなスイッチ", question: "ひとつの合図で、別の電気の道を開けられる？",
              goal: "制御する信号と、制御される通り道の役割を区別する。",
              intro: "指で押す代わりに、電気の合図で道を開けるスイッチを見てみよう。合図を送る場所と、電気が通る道は役割が違うよ。小さな部品を組み合わせると、さっきの論理回路につながるんだ。",
              explanation: "MOSFETというトランジスタは、ゲートとソースの間の電圧で、ソースとドレインの間の流れを制御する。デジタル回路では、これを主に通す・通さないスイッチとして組み合わせ、0と1の計算を作っているよ。",
              analogyLimit: "この模型は一種類のスイッチだけ。実物には種類や電圧の条件があり、完全な断線や抵抗ゼロになるわけではないよ。",
              activity: .transistor, activityPrompt: "制御の合図を切り替えて、別の通り道が開くところを観察しよう。",
              challenge: .init(prompt: "この模型は「制御ONなら通す、OFFなら遮る」スイッチ。通り道を開く操作は？", options: ["出口の名前を変える", "保存容量を増やす", "制御をONにする"], correctIndex: 2,
                               correctFeedback: "そう。制御する合図が、別の道の通し方を変える。それが電気のスイッチの入口だよ。",
                               incorrectFeedback: "道を開く条件は制御ONだったね。保存容量や名前ではなく、制御の合図を変えよう。"),
              takeaway: "電気の合図で別の流れを制御する小さな部品が、回路の土台になる。",
              labConnection: "CPUやGPUの部品数や製造技術を見るときの基礎になるよ。トランジスタの数だけで速さは決まらないんだ。",
              sources: [transistor]),
        .init(id: "instruction-atelier", title: "CPUと命令の順番", question: "同じ命令なのに、順番で答えが変わる？",
              goal: "CPUが命令を実行することと、周波数だけでは性能が決まらないことを知る。",
              intro: "CPUは、してほしいことを命令として受け取るよ。まずは数字を読み、計算し、結果を残す小さな仕事を追ってみよう。順番を入れ替えると、同じ命令でも答えは変わるかな。",
              explanation: "CPUは命令を読み取り、計算やデータの移動を進める。クロックは動作の周期を表すけれど、一周期にできる仕事や待ち時間も違う。だからGHzが大きいという理由だけで、別のCPUより速いとは決められないよ。",
              analogyLimit: "模型では命令を一つずつ進めるよ。実際のCPUは複数の段階を重ねたり、結果が矛盾しない範囲で実行順を工夫したりするんだ。",
              activity: .instructions, activityPrompt: "命令の順番を変えて、途中の数字と最後の結果を比べよう。",
              challenge: .init(prompt: "最初の値は2。「3を足す」→「2倍する」の順に一回ずつ実行した結果は？", options: ["10", "7", "12"], correctIndex: 0,
                               correctFeedback: "そう。2＋3＝5、その後に2倍して10。命令の順番が答えを決めたね。",
                               incorrectFeedback: "最初に足し算をするよ。2＋3＝5、それを2倍するから、答えは10だね。"),
              takeaway: "CPUは命令を実行する。速さを比べるときは、周波数と実際の仕事の両方を見る。",
              labConnection: "ラボのクロックは動作周期、CPU使用率は忙しさの手がかり。どちらも単独では処理性能の点数にならないよ。",
              sources: [instructions, clock, cpu]),
        .init(id: "work-dispatch", title: "CPUの時間を分ける", question: "ひとつの作業台で、いくつものアプリが動くのはなぜ？",
              goal: "同時に進んで見えることと、本当に同時に計算することを区別する。",
              intro: "音楽を聴きながら、文章を書いて、ファイルも開く。PCにはいくつもの仕事が届くね。一つの作業台でも、短い時間ごとに交代すれば、みんなが少しずつ進められるよ。",
              explanation: "OSは実行できる仕事にCPUの時間を割り当てる。通信や読み込みを待つ仕事があれば、別の仕事を進められる。CPU使用率は使われた時間の手がかりで、同じ割合でも完了する仕事量は同じとは限らないよ。",
              analogyLimit: "この模型は一度に一つの仕事を進める一台のCPU。実機には複数コアがあり、優先度や待ち状態なども配分に関わるよ。",
              activity: .schedule, activityPrompt: "仕事の配分を変えて、最初に反応するまでの待ち時間と、全部終わるまでを比べよう。",
              challenge: .init(prompt: "一つのCPUでAとBに交代で時間を渡す模型。交代することで起きることは？", options: ["必ず二倍速く終わる", "両方が少しずつ進む", "メモリが不要になる"], correctIndex: 1,
                               correctFeedback: "そう。両方を少しずつ進められるよ。でも仕事の総量が半分になるわけではないんだ。",
                               incorrectFeedback: "交代すると両方に進む機会が生まれるよ。一台の処理能力が二倍になったり、メモリが消えたりはしないんだ。"),
              takeaway: "忙しさ、反応までの時間、完了までの時間は、それぞれ違う見方。",
              labConnection: "ラボではCPUの忙しさと、実際に待っている操作を組み合わせて見よう。使用率の高さだけで不調とは決めないよ。",
              sources: [scheduling, cpu]),
        .init(id: "parallel-factory", title: "同時にできる仕事・待つ仕事", question: "働き手を増やせば、何でも二倍速くなる？",
              goal: "独立した仕事と、前の結果が必要な仕事を見分ける。",
              intro: "カードを別々に塗るなら、手分けできそう。でも前の答えを使って次を計算する仕事は、答えが届くまで待つ必要があるね。何人で働くかだけでなく、仕事同士の関係を見てみよう。",
              explanation: "並列処理は、同時に進められる仕事を複数の処理役に分けること。前の結果が必要な部分は、そのままでは分けられない。分配や結果を集める時間もあるため、コア数を増やしても全体が同じ比率で速くなるとは限らないよ。",
              analogyLimit: "模型の処理役は同じ速さで、受け渡し時間を単純化しているよ。実機ではコアの種類やメモリ待ちでも結果が変わるんだ。",
              activity: .parallel, activityPrompt: "働き手の数と仕事のつながりを変えて、同時に進む部分と待つ部分を探そう。",
              challenge: .init(prompt: "作業Aは1秒、その結果を使うBも1秒。受け渡し時間ゼロでも、処理役を二人にすると最短何秒？", options: ["0.5秒", "1秒", "2秒"], correctIndex: 2,
                               correctFeedback: "その通り。BはAを待つので1＋1＝2秒。独立しているかどうかが大事なんだ。",
                               incorrectFeedback: "BはAの結果が出るまで始められないよ。処理役が余っていても、最短は1＋1＝2秒だね。"),
              takeaway: "コアを増やす効果は、その仕事をどれだけ同時に進められるかで変わる。",
              labConnection: "ラボのCPU全体に余裕があっても、一つの処理が待ち時間を決めることがあるよ。仕事の分け方も考えてみよう。",
              sources: [parallel]),
        .init(id: "pixel-factory", title: "GPUが得意な仕事", question: "たくさんの点に、同じ計算をしたいときは？",
              goal: "GPUの並列処理の利点と、準備やデータ移動の負担を説明する。",
              intro: "絵のすべての点を少し明るくしたいな。それぞれの点を同じ決まりで計算できるなら、大勢でまとめて進められそう。少しの点と、たくさんの点で、仕事の分け方を比べてみよう。",
              explanation: "GPUは、多くのデータへ似た計算を並列に行うのが得意。画像以外の計算にも使えるよ。ただし仕事の準備、データの受け渡し、結果待ちにも時間がかかるので、小さな仕事や順番への依存が強い仕事では有利とは限らないんだ。",
              analogyLimit: "模型のレーンは実物のコア数ではないよ。CPUも並列処理ができ、GPUにも得意・不得意があるんだ。",
              activity: .pixels, activityPrompt: "処理する点と同時に働くレーンを変えて、まとめて進められる仕事を見つけよう。",
              challenge: .init(prompt: "準備時間は同じとする。GPUへまとめて渡す仕事として、並列化しやすいのは？", options: ["各画素を独立に明るくする", "必ず前の答えを待つ計算", "人が次の文字を入力するのを待つ"], correctIndex: 0,
                               correctFeedback: "そう。各画素が別々に計算できるので、同じ処理をたくさん並べやすいね。",
                               incorrectFeedback: "前の答えや人の操作を待つ仕事は、処理役を増やすだけでは進まないよ。各画素の独立した計算が向いているね。"),
              takeaway: "GPUは、たくさんの似た計算を同時に進めると力を発揮しやすい。",
              labConnection: "ラボのGPU使用状況と、動画・描画・計算など今している仕事を対応づけてみよう。GPU使用率だけでアプリの速さは決まらないよ。",
              sources: [gpu, unifiedMemory]),
        .init(id: "memory-dock", title: "メモリと保存は別の役割", question: "保存したのに、どうして机が空かないの？",
              goal: "保存と、作業中のメモリを解放することを区別する。",
              intro: "編集中の作品を机に広げて、完成した内容を棚にも残しておく。棚へ保存しても、続けて編集するなら机の上の作品は必要だね。二つの置き場所が、どんな役割なのか見てみよう。",
              explanation: "メモリは処理中のデータを置く場所で、ストレージはデータを保存する場所。保存は内容を残す操作で、使っているメモリを解放する操作とは別。メモリの空きが少なくても、再利用できるキャッシュなどがあれば、すぐ不足とは限らないよ。",
              analogyLimit: "机の枠は容量の模型。実際のメモリ管理はOSやアプリが行い、使わなくなった領域をいつ再利用するかも状況によって変わるよ。",
              activity: .memory, activityPrompt: "作品を保存したときと、使い終えたデータを解放したときで、机と棚を見比べよう。",
              challenge: .init(prompt: "この模型では編集中の作品が机に残る。棚へ保存した直後、机の使用量はどうなる？", options: ["必ず0になる", "保存だけでは変わらない", "必ず二倍になる"], correctIndex: 1,
                               correctFeedback: "そう。棚に記録を残しても、編集中の作品は机で使っているね。保存と解放は別だよ。",
                               incorrectFeedback: "保存は棚へ内容を残す操作だね。この模型では編集中なので、机の使用量はそのままだよ。"),
              takeaway: "保存することと、作業場所を空けることを分けて考える。",
              labConnection: "ラボでは使用量だけでなくメモリプレッシャーも見よう。空き容量だけで、PCが困っているかどうかは決められないよ。",
              sources: [memory, memoryHierarchy]),
        .init(id: "cache-delivery", title: "よく使うデータを手元に置く", question: "同じものを取りに行くなら、近くに置いておける？",
              goal: "キャッシュが役立つ条件と、容量だけでは効果が決まらないことを知る。",
              intro: "何度も使うカードを、遠い倉庫まで毎回取りに行くのは大変だね。小さな手元の棚に残しておけば、次は早く取り出せそう。ただ、棚がいっぱいになったら何を残すか考える必要があるよ。",
              explanation: "キャッシュは、また使いそうなデータを取り出しやすい場所に置くしくみ。欲しいデータがあればヒット、なければ元の場所へ取りに行く。繰り返しや近い場所へのアクセスが多いほど役立ちやすく、初めてのデータばかりでは効果が小さいよ。",
              analogyLimit: "ここでは一段の棚で比べるよ。CPUのキャッシュと、OSのファイルキャッシュは対象や仕組みが異なるけれど、再利用という考え方は共通なんだ。",
              activity: .cache, activityPrompt: "同じデータをもう一度要求して、手元の棚にあるときとないときの待ち方を比べよう。",
              challenge: .init(prompt: "容量1の空のキャッシュに、Aを読み込んで残した。他の要求を挟まず、もう一度Aを読むと？", options: ["必ず倉庫へ戻る", "保存データが消える", "キャッシュにヒットする"], correctIndex: 2,
                               correctFeedback: "そう。Aが手元に残っているので、次はそこから使えるね。繰り返す仕事に効く仕組みだよ。",
                               incorrectFeedback: "最初の要求でAを手元に残したね。他の要求もないから、次のAはキャッシュに見つかるよ。"),
              takeaway: "キャッシュの効果は、広さに加えて、同じデータをまた使うかどうかで変わる。",
              labConnection: "ラボのメモリにキャッシュが多くても、直ちに無駄とは言えないよ。再利用や必要時の回収に役立つ場合があるんだ。",
              sources: [memoryHierarchy, memory]),
        .init(id: "memory-rescue", title: "メモリが混み合ったとき", question: "データを小さくする？いったん別の場所へ移す？",
              goal: "圧縮とスワップの違い、空間と処理時間の交換を説明する。",
              intro: "机が混んできたら、同じ内容を小さくまとめる方法と、今使わないものを別の場所へ移す方法があるよ。どちらも置ける余地は増えるけれど、また使うときの手間はどうなるかな。",
              explanation: "メモリ圧縮はデータを元に戻せる形で小さくし、スワップは一部をストレージへ退避するしくみ。どちらもメモリをやりくりする助けになるけれど、圧縮・展開や読み戻しには仕事が増える。値があるだけで故障とは言えないよ。",
              analogyLimit: "模型の圧縮率や所要時間は比較用。実物ではデータによって縮み方が違い、OSが自動的に判断するよ。",
              activity: .compression, activityPrompt: "圧縮と退避を比べて、空いた場所と、元のデータを使うための手間を見よう。",
              challenge: .init(prompt: "メモリ内のデータをストレージへ一時退避する仕組みを、この授業では何と呼ぶ？", options: ["スワップ", "クロック", "解像度"], correctIndex: 0,
                               correctFeedback: "そう、スワップだよ。保存用ファイルを作る操作とは別で、OSが作業中のメモリをやりくりする仕組みなんだ。",
                               incorrectFeedback: "一時的な退避はスワップ。圧縮はデータを小さくする工夫、クロックや解像度は別の性質だね。"),
              takeaway: "メモリのやりくりには、空間を作る効果と、処理や読み戻しの負担がある。",
              labConnection: "ラボでは圧縮量やスワップの有無だけでなく、メモリプレッシャーと実際の待ち時間の変化を一緒に見よう。",
              sources: [memory]),
        .init(id: "storage-warehouse", title: "保存できる量と、運べる速さ", question: "大きな倉庫なら、荷物も速く届く？",
              goal: "ストレージ容量と、読み書きの速さを別々に考える。",
              intro: "棚にたくさん置けることと、すぐに取り出せることは別だね。倉庫を広くしても、出入り口で一つずつ待っていたら転送は速くならないかもしれない。どこを変えると何が変わるか比べてみよう。",
              explanation: "容量は保存できるデータの量。転送速度は単位時間に読み書きできる量で、応答までの遅れとも区別するよ。大きな連続データか、小さなデータをあちこち読むかでも速さは変わる。容量だけでは読み書きの性能を判断できないんだ。",
              analogyLimit: "模型では一定速度で運ぶよ。実機ではキャッシュ、空き領域、接続、アクセスの順番などでも時間が変わるんだ。",
              activity: .storage, activityPrompt: "データ量と転送速度を別々に変えて、全部届くまでの時間を比べよう。保存容量とは分けて考えてね。",
              challenge: .init(prompt: "倉庫の容量だけを二倍にした。転送速度とデータ量が同じなら、この定速模型の転送時間は？", options: ["必ず半分", "変わらない", "必ず二倍"], correctIndex: 1,
                               correctFeedback: "その通り。置ける量は増えるけれど、同じ量を同じ速さで運ぶ時間は変わらないね。",
                               incorrectFeedback: "変えたのは保存できる量だけだね。運ぶ量と速さが同じなら、転送時間も同じだよ。"),
              takeaway: "容量・転送速度・応答までの遅れを、それぞれ別の性質として見る。",
              labConnection: "ラボのストレージ空き容量と読み書きの量を見分けよう。転送量が少なくても、小さな読み込みを待っている場合があるよ。",
              sources: [memoryHierarchy, inputOutput]),
        .init(id: "display-studio", title: "解像度・FPS・Hz", question: "絵を作る速さと、画面を更新する速さは同じ？",
              goal: "画素数、フレーム生成頻度、表示更新頻度を区別する。",
              intro: "動画は、一枚ずつの絵を次々に見せているよ。絵の細かさ、次の絵ができる頻度、画面が更新される頻度。それぞれ別のつまみだと考えると、動きの見え方を読み解きやすくなるね。",
              explanation: "解像度は画面の画素数、FPSは一秒あたりに作る・送る画像の枚数、Hzは画面の更新頻度。画面だけを高Hzにしても、アプリが作る新しい絵は自動では増えない。なめらかさには、フレームが等間隔に届くことも関わるよ。",
              analogyLimit: "ここでは一回の更新で一枚を表示する模型。実際には可変更新や同期、補間などがあり、表示方法でも見え方が変わるよ。",
              activity: .frames, activityPrompt: "絵を作る頻度と画面を更新する頻度を変えて、同じ絵が繰り返し表示される条件を探そう。",
              challenge: .init(prompt: "アプリは毎秒30枚の新しい絵を作り、補間はしない。表示だけ60Hzから120Hzにすると、新しい絵は毎秒何枚？", options: ["120枚", "60枚", "30枚"], correctIndex: 2,
                               correctFeedback: "そう。新しく作る絵は30枚のまま。更新する機会と、絵を作る頻度は別なんだ。",
                               incorrectFeedback: "アプリの生成頻度は変えていないね。補間もしない条件なので、新しい絵は毎秒30枚のままだよ。"),
              takeaway: "細かさ・絵を作る頻度・表示を更新する頻度を、別々に考える。",
              labConnection: "ラボのディスプレイのHzと、ゲーム側のFPSを対応づけよう。Hzの表示だけでは、アプリが毎秒何枚作れたかはわからないよ。",
              sources: [refresh, gpu]),
        .init(id: "packet-express", title: "通信の遅延と帯域", question: "道を広げると、最初の返事も早く届く？",
              goal: "少量の往復と大量の転送で、効く条件が異なることを説明する。",
              intro: "遠くの相手に小さな返事をもらうときと、大きな荷物を全部届けるとき。どちらも通信だけど、待つ理由は同じとは限らないね。道の広さと、届くまでの遅れを別々に変えてみよう。",
              explanation: "帯域は一秒あたりに運べる量の上限、遅延はデータが届くまでの時間。大きな転送では帯域、小さなやりとりを何度もする仕事では遅延が効きやすい。実際に届く量は、混雑や再送などで帯域の上限より少なくなることもあるよ。",
              analogyLimit: "模型では経路が一つで、損失や再送を省略するよ。距離だけでなく機器の処理や混雑、相手の返答時間も待ち時間に関わるんだ。",
              activity: .network, activityPrompt: "道の広さと遅延を別々に変えて、届き始めるまでと全部届くまでを見比べよう。",
              challenge: .init(prompt: "転送にかかる時間を無視できる小さな通信。往復遅延が100msのまま帯域だけ二倍にすると、この模型の待ち時間は？", options: ["約100msのまま", "必ず50ms", "0msになる"], correctIndex: 0,
                               correctFeedback: "そう。ここではデータを送り出す時間を無視しているので、待ち時間を決める往復遅延は変わらないよ。",
                               incorrectFeedback: "今回は小さな通信で、転送時間は無視する条件だね。往復の遅延を変えていないので、約100msのままだよ。"),
              takeaway: "通信の速さには、運べる量と、返事が届くまでの時間という別の側面がある。",
              labConnection: "ラボの送受信量が少なくても、通信待ちは起きるよ。通信量だけから回線の応答の速さを決めつけないようにしよう。",
              sources: [latency]),
        .init(id: "board-town", title: "部品を結ぶデータの道", question: "同じPCの中でも、データの道が混むの？",
              goal: "部品の役割と配置、共有する経路の違いを知る。",
              intro: "CPU、GPU、メモリ、ストレージ。それぞれに役割があって、仕事の途中でデータを渡し合っているよ。部品の名前だけでなく、どの道を使って届けるのかも一緒に見てみよう。",
              explanation: "部品はメモリや接続経路を通してデータをやりとりする。共通の道を同時に使うと、通せる量を分け合うことがあるよ。AppleシリコンのようにCPUとGPUが同じメモリを利用する構成もあり、役割の違いと物理的な分離は別なんだ。",
              analogyLimit: "図は役割を示す地図で、基板の正確な配線図ではないよ。すべてのPCが一本の共通バスにつながっているわけではないんだ。",
              activity: .bus, activityPrompt: "データを送る部品と通り道を見て、同じ道を分け合うときの届き方を比べよう。",
              challenge: .init(prompt: "共通の道が毎秒10個まで運べる模型。二つの部品が同時に各10個を送りたいとき、合計で毎秒いくつまで？", options: ["20個", "10個", "100個"], correctIndex: 1,
                               correctFeedback: "その通り。送り手が増えても、共通の道の上限は10個のまま。道の能力も全体の仕事に関わるね。",
                               incorrectFeedback: "二つの部品が同じ道を使う条件だね。送りたい量は20個でも、道が運べる合計は毎秒10個までだよ。"),
              takeaway: "部品の性能だけでなく、データの居場所と、渡す経路も見る。",
              labConnection: "ラボのCPU・GPU・メモリは、別々の数字でも一つの仕事でつながっているよ。共有メモリでは単純に使用量を足せない場合もあるんだ。",
              sources: [unifiedMemory, inputOutput]),
        .init(id: "connection-lab", title: "挿さる形と、できること", question: "同じUSB-Cなら、どれでも映像を出せる？",
              goal: "機器・端子・ケーブルの対応がそろう必要があると説明する。",
              intro: "ケーブルはぴったり挿さった。でも充電できることと、映像を映せることは同じじゃないんだ。形が合ったら、その先でどんな仕事に対応しているか、組み合わせ全体を確かめよう。",
              explanation: "USB-Cは端子の形を表す名前で、通信速度・映像出力・給電の能力は製品によって違う。したいことに機器、接続先、ケーブルが対応している必要があるよ。一つだけ高性能でも、組み合わせ全体の能力は上がらないんだ。",
              analogyLimit: "ここでは通信・映像・給電の対応を絞って比べるよ。実際の接続は規格、設定、アダプターなども確認する必要があるんだ。",
              activity: .ports, activityPrompt: "機器とケーブルの対応を見比べて、同じ形でもできることが変わる組み合わせを探そう。",
              challenge: .init(prompt: "映像対応のPCと画面を、映像非対応のUSB-Cケーブルで直結した。この条件で言えることは？", options: ["形が同じなので必ず映る", "給電できれば必ず映る", "このケーブルでは映像を送れない"], correctIndex: 2,
                               correctFeedback: "そう。映像を通せる組み合わせが必要だね。形や給電への対応だけでは決められないよ。",
                               incorrectFeedback: "形が合っても、ケーブルは映像非対応という条件だね。映像を送るための対応を、全体でそろえる必要があるよ。"),
              takeaway: "端子の形だけで選ばず、やりたいことに全員が対応しているかを見る。",
              labConnection: "ラボの外部機器を見るときは、機器名に加えて接続方法や対応仕様も確認しよう。認識されることと全機能が使えることは別だよ。",
              sources: [usb, ports]),
        .init(id: "pc-day", title: "写真一枚が動かすPCの仕事", question: "写真を開いて保存するまで、誰が働くの？",
              goal: "読み出し・計算・作業中の記憶・保存・表示の役割をつなげる。",
              intro: "一枚の写真を開いて、少し明るくして、保存してみよう。画面では簡単な操作だけど、PCの中では複数の部品が協力しているよ。作品がどこにあって、今どんな仕事をしているか追ってみよう。",
              explanation: "保存先から読んだデータをメモリで使い、CPUやGPUがアプリの処理を進め、画面に結果を表示する。保存では結果をストレージへ残すよ。実際の作業は重なって進むので、一つの操作で複数の部品が同時に働くこともあるんだ。",
              analogyLimit: "模型は代表的な役割を一つずつ追うよ。写真が常に同じ経路を通るわけではなく、キャッシュやアプリの作りでも変わるんだ。",
              activity: .flow, activityPrompt: "作品を開く・編集する・保存する流れを進めて、そのたびに働く場所をたどろう。",
              challenge: .init(prompt: "写真の編集結果を、アプリを終了した後もファイルとして残したい。担当する役割は？", options: ["ストレージへ保存する", "画面を明るくする", "CPUの使用率を読む"], correctIndex: 0,
                               correctFeedback: "そう。ファイルとして残すのは保存の役割だね。表示されていることだけでは、保存済みとは限らないよ。",
                               incorrectFeedback: "画面に見えることと、後から使えるファイルを残すことは別だね。ストレージへ保存する役割が必要だよ。"),
              takeaway: "一つの操作を、データの居場所と部品の仕事に分けて考えられる。",
              labConnection: "ラボでアプリを開く前後を見比べよう。CPU・メモリ・ストレージの変化を、今行った操作とつなげて考えてみてね。",
              sources: [inputOutput, memoryHierarchy, unifiedMemory]),
        .init(id: "battery-voyage", title: "残っている量と、使う速さ", question: "同じ50％なのに、使える時間が違うのはなぜ？",
              goal: "エネルギー量と消費電力を分けて、持続時間を見積もる。",
              intro: "同じだけ電気が残っていても、軽い作業と重い作業では使う速さが違うね。残量を水の量、消費電力を減る速さとして眺めると、あとどれくらい使えそうか考えやすくなるよ。",
              explanation: "Whはエネルギーの量、Wはエネルギーを使う速さ。一定の10Wで使う模型なら、残り40Whで約4時間になるよ。実物では仕事、画面、通信、温度などで消費が変わるため、残り時間は固定の約束ではないんだ。",
              analogyLimit: "この模型は消費が一定で、変換損失などを省いた見積もりだよ。実機の残量％からWhへ直すには、その時点の利用できる容量も必要なんだ。",
              activity: .battery, activityPrompt: "残っている量と消費する速さを別々に変えて、使い続けられる時間を比べよう。",
              challenge: .init(prompt: "残り40Wh、消費は一定の10W、損失を考えない模型。何時間使える？", options: ["0.25時間", "4時間", "400時間"], correctIndex: 1,
                               correctFeedback: "そう。40Wh÷10W＝4時間。残りの量を、使う速さで割ると時間になるね。",
                               incorrectFeedback: "使える時間は残りの量÷使う速さ。40Wh÷10Wで4時間になるよ。"),
              takeaway: "残量は蓄え、消費電力は減る速さ。両方から持続時間を考える。",
              labConnection: "ラボでは残量だけでなく、今している作業や給電の状態も見よう。利用できる電力の測定値がない場合、正確な残り時間は断定できないよ。",
              sources: [battery]),
        .init(id: "cooling-workshop", title: "生まれる熱と、逃がす熱", question: "動かし続けると、なぜ速さが変わることがあるの？",
              goal: "温度の変化を、発熱と放熱の差から考える。",
              intro: "仕事を続けると、部品が温かくなるね。外へ逃がす熱より生まれる熱が多い間は、温度が上がりやすいよ。冷却の強さと仕事量を変えて、熱の出入りがどう釣り合うか見てみよう。",
              explanation: "部品が使う電力の多くは熱になり、冷却はその熱を外へ運ぶ。高い温度などの制限に近づくと、PCは動作を調整することがあるよ。速さは仕事量だけでなく、冷却、周囲の温度、電力の条件にも左右されるんだ。",
              analogyLimit: "模型の温度や限界値は実機の診断値ではないよ。ファンのない機種もあり、適切な温度や制御方法は機種によって違うんだ。",
              activity: .cooling, activityPrompt: "仕事から生まれる熱と逃がす熱を変えて、温度が上がる・落ち着く条件を見つけよう。",
              challenge: .init(prompt: "ほかの条件が同じ模型で、生まれる熱が逃げる熱より多い状態を続けると、最初はどうなる？", options: ["必ず温度が下がる", "熱が消える", "温度が上がる"], correctIndex: 2,
                               correctFeedback: "そう。入ってくる熱のほうが多い間は、熱がたまって温度が上がるよ。逃がす量との釣り合いが大切だね。",
                               incorrectFeedback: "生まれる量から逃げる量を引いて考えよう。熱がたまる条件なので、最初は温度が上がるよ。"),
              takeaway: "温度は仕事と冷却の両方の結果。温度の数字一つで故障とは判断しない。",
              labConnection: "ラボで温度・ファン・クロックが見えるときは、作業を始めてからの変化を一緒に見よう。数値が取れない機種では推測と測定を分けるよ。",
              sources: [thermal, thermalPerformance]),
        .init(id: "bottleneck-detective", title: "待ち時間の原因を探す", question: "どこを速くすると、いちばん待たずに済む？",
              goal: "条件を一つずつ変え、仕事を制限している段階を探す。",
              intro: "読み込み、計算、保存。全部が速いほどよさそうだけど、長く待っている場所を変えるほうが効果が大きいこともあるね。まず予想して、一か所だけ変え、同じ仕事で確かめてみよう。",
              explanation: "ボトルネックは、その仕事の進み方を強く制限している部分。別の場所を速くしても効果は小さいことがあり、条件を変えると制限する場所も移るよ。使用率の一枚の画面だけで決めず、同じ作業で条件をそろえて比べるんだ。",
              analogyLimit: "実験は仕事を流し続けるときの流量、次の問いは一回の仕事の所要時間だよ。実機では工程が重なるため、時間を足すだけでは予測できないこともあるんだ。",
              activity: .bottleneck, activityPrompt: "各工程の能力を変えて、単位時間に流せる量を比べよう。次の問いでは、一つの仕事にかかる時間を考えるよ。",
              challenge: .init(prompt: "直列の3工程は、読む8秒・計算2秒・保存2秒。どれか一つの時間を半分にできるなら、最も短縮できるのは？", options: ["読む工程", "計算する工程", "保存する工程"], correctIndex: 0,
                               correctFeedback: "そう。読む工程は8→4秒で4秒短縮。他は2→1秒で1秒ずつだから、今回は読む工程が最も効くね。",
                               incorrectFeedback: "半分にして減る時間を比べよう。読む工程は4秒、計算と保存は各1秒減るので、今回は読む工程が最も効くよ。"),
              takeaway: "同じ仕事で、一つだけ条件を変えて比べる。速くすべき場所は仕事ごとに違う。",
              labConnection: "ラボの記録と、何をして何秒待ったかを組み合わせよう。CPUだけでなくメモリ、保存、通信などにも手がかりがあるよ。",
              sources: [bottleneck, cpu, memory])
    ]

    public static func lesson(_ id: String) -> LessonDefinition? {
        lessons.first { $0.id == id }
    }

    public static func lessons(in area: ExhibitionAreaID) -> [LessonDefinition] {
        ExhibitionCatalog.games(in: area).compactMap { lesson($0.id) }
    }
}
