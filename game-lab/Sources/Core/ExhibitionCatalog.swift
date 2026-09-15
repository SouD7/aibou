import Foundation

public enum ExhibitionAreaID: String, CaseIterable, Codable, Sendable, Identifiable {
    case a, b, c, d, e
    public var id: String { rawValue }
    public var letter: String { rawValue.uppercased() }
}

public struct ExhibitionArea: Identifiable, Equatable, Sendable {
    public let id: ExhibitionAreaID
    public let title: String
    public let subtitle: String
    public let colorName: String
    public let icon: String
    public let guideInvitation: String

    public var learningTopics: String {
        switch id {
        case .a: return "ビット・論理・記憶"
        case .b: return "命令・演算・並列処理"
        case .c: return "保存・容量・転送"
        case .d: return "映像・通信・接続"
        case .e: return "電力・冷却・性能"
        }
    }
}

public struct ExhibitionGame: Identifiable, Equatable, Sendable {
    public let id: String
    public let areaID: ExhibitionAreaID
    public let themeID: String
    public let title: String
    public let learningDescription: String
    public let guideInvitation: String
    public let icon: String
    public let isPlayable: Bool
}

/// The exhibition is an index of learning experiences, not a mandatory course order.
public enum ExhibitionCatalog {
    public static let circuitGameID = "circuit-atelier"

    public static let areas: [ExhibitionArea] = [
        .init(id: .a, title: "デジタル回路", subtitle: "小さな合図から、しくみが生まれる。",
              colorName: "cyan", icon: "point.3.connected.trianglepath.dotted",
              guideInvitation: "この小さなスイッチ、つなぐと何ができるかな。一緒に動かしてみよう。"),
        .init(id: .b, title: "CPU・GPUと処理方式", subtitle: "仕事を分けて、順番を工夫する。",
              colorName: "amber", icon: "cpu",
              guideInvitation: "順番にする仕事と、同時にできる仕事。机の上で比べてみよう。"),
        .init(id: .c, title: "メモリ・ストレージ", subtitle: "いま使う場所と、残しておく場所。",
              colorName: "lavender", icon: "memorychip",
              guideInvitation: "机と棚、どちらに置くと使いやすいかな。データの居場所を探してみよう。"),
        .init(id: .d, title: "映像表示・通信・接続", subtitle: "部品から画面へ、PCから外の世界へ。",
              colorName: "mint", icon: "cable.connector",
              guideInvitation: "画面も通信も、データが届いて動いているよ。その道をたどってみよう。"),
        .init(id: .e, title: "PC全体の動作・電力・冷却", subtitle: "ひとつのPCとして、つながって動く。",
              colorName: "coral", icon: "bolt.fill",
              guideInvitation: "ここではPC全体を眺めてみよう。ひとつ変えると、どこに違いが出るかな。")
    ]

    public static let games: [ExhibitionGame] = [
        .init(id: "bit-art", areaID: .a, themeID: "H02", title: "ビットとデータ表現",
              learningDescription: "0と1を組み合わせて絵を作る。使えるビットが増えると、表せる形がどう変わるかを発見する。",
              guideInvitation: "点ける、消す。それだけで、どんな絵が描けるかな？", icon: "square.grid.3x3.fill", isPlayable: true),
        .init(id: circuitGameID, areaID: .a, themeID: "H03", title: "論理回路",
              learningDescription: "スイッチと部品をつなぎ、ふたりの準備がそろったときだけ光るランプを作る。入力と出力の関係を4通りで確かめる。",
              guideInvitation: "ふたりのスイッチで、ランプをつけよう。片方だけのときは、どうなるかな？", icon: "lightbulb", isPlayable: true),
        .init(id: "memory-switch", areaID: .a, themeID: "H04", title: "記憶回路",
              learningDescription: "入力を戻しても合図が残る装置を作る。今の入力と、覚えている状態の違いを見つける。",
              guideInvitation: "手を離しても覚えているスイッチ。どんなしくみだと思う？", icon: "switch.2", isPlayable: true),
        .init(id: "tiny-switch-workshop", areaID: .a, themeID: "H19", title: "トランジスタとスイッチング",
              learningDescription: "別の信号で開閉するスイッチを組み合わせる。電気の通り道と、0・1の論理のつながりを探る。",
              guideInvitation: "ひとつの合図で、別の道を開けてみよう。", icon: "switch.2", isPlayable: true),
        .init(id: "instruction-atelier", areaID: .b, themeID: "H05", title: "CPUの命令実行",
              learningDescription: "読む・計算する・残す、という命令を並べる。順番や分岐を変えながら、CPUが命令を進めるしくみを追う。",
              guideInvitation: "この数字を目標の答えにしたいな。どの順番で命令を渡そう？", icon: "list.number", isPlayable: true),
        .init(id: "work-dispatch", areaID: .b, themeID: "H07", title: "CPUの時間配分とタスク管理",
              learningDescription: "計算の時間と作業場所を複数の仕事へ割り当てる。仕事によって必要な資源が違うことを比べる。",
              guideInvitation: "みんなの仕事が届いたよ。時間と作業場所を、どう分けようか。", icon: "rectangle.3.group", isPlayable: true),
        .init(id: "parallel-factory", areaID: .b, themeID: "H08", title: "並列処理",
              learningDescription: "独立した工程を同時に進め、前の結果が必要な工程は待つ。働き手を増やしたときの速さを比べる。",
              guideInvitation: "一緒にできる作業はどれかな？前の答えを待つ作業もありそう。", icon: "arrow.triangle.branch", isPlayable: true),
        .init(id: "pixel-factory", areaID: .b, themeID: "H12", title: "GPUと画像処理",
              learningDescription: "たくさんの画素に似た計算をまとめて行う。GPUが得意な並列の仕事と、その準備にかかる時間を知る。",
              guideInvitation: "この絵の色を一斉に変えてみよう。まとめてできると速いかな？", icon: "square.grid.3x3", isPlayable: true),
        .init(id: "memory-dock", areaID: .c, themeID: "H06", title: "メモリとデータ保存",
              learningDescription: "作業中のデータを置くメモリと、保存して残すストレージを使い分ける。保存することと作業場所を空けることを比べる。",
              guideInvitation: "保存はできたね。じゃあ、作業中の置き場所も空いたのかな？", icon: "memorychip", isPlayable: true),
        .init(id: "cache-delivery", areaID: .c, themeID: "H09", title: "キャッシュメモリ",
              learningDescription: "繰り返し使うデータを近い棚に置く。棚の広さや取り出す順番を変えて、データ待ちの時間を比べる。",
              guideInvitation: "また同じ本を使うみたい。手元に置いておいたらどうなるかな？", icon: "shippingbox", isPlayable: true),
        .init(id: "memory-rescue", areaID: .c, themeID: "H10", title: "メモリ圧縮とスワップ",
              learningDescription: "作業場所が混み合ったときに、データを圧縮したり一時的に移したりする。空間を作る効果と、処理や読み戻しの負担を比べる。",
              guideInvitation: "机がいっぱいだね。小さくまとめる？いったん棚へ移す？", icon: "arrow.down.right.and.arrow.up.left", isPlayable: true),
        .init(id: "storage-warehouse", areaID: .c, themeID: "H11", title: "ストレージの容量と転送速度",
              learningDescription: "倉庫の広さと、データを出し入れする速さを別々に変える。保存容量と読み書きの性能の違いを見つける。",
              guideInvitation: "棚には余裕があるのに、荷物が届かないね。どこを変えよう？", icon: "externaldrive", isPlayable: true),
        .init(id: "display-studio", areaID: .d, themeID: "H13", title: "ディスプレイと映像表示",
              learningDescription: "画素数、画像を作る頻度、画面を更新する頻度を別々に変える。解像度・FPS・Hzの違いを観察する。",
              guideInvitation: "絵を作る速さと、画面をめくる速さ。別々に変えて見てみよう。", icon: "display", isPlayable: true),
        .init(id: "packet-express", areaID: .d, themeID: "H14", title: "ネットワークの帯域と遅延",
              learningDescription: "届くまでの時間と、一度に運べるデータ量を変える。小さな往復と大きな転送で効く条件を比べる。",
              guideInvitation: "道を広げると、最初の便も早く着くのかな？", icon: "envelope", isPlayable: true),
        .init(id: "board-town", areaID: .d, themeID: "H17", title: "PCの構成とデータ経路",
              learningDescription: "CPU・GPU・メモリなどの役割と、それを結ぶ経路をたどる。同じチップにある機能や、共有する道の混み合いを知る。",
              guideInvitation: "部品の役割と、置かれている場所。データの道をたどって確かめよう。", icon: "cpu", isPlayable: true),
        .init(id: "connection-lab", areaID: .d, themeID: "H18", title: "接続端子と通信・給電",
              learningDescription: "機器・ケーブル・端子の条件を合わせる。挿さる形だけでなく、通信・映像・給電の対応を確かめる。",
              guideInvitation: "ぴったり挿さったね。映像も電気も、ちゃんと届く組み合わせかな？", icon: "cable.connector", isPlayable: true),
        .init(id: "pc-day", areaID: .e, themeID: "H01", title: "PC内部の処理の流れ",
              learningDescription: "写真を開き、編集し、保存する流れを部品でつなぐ。入力・計算・作業中の記憶・保存・表示の役割をたどる。",
              guideInvitation: "写真を一枚開いてみよう。PCの中では、誰がどんな仕事をしているかな？", icon: "desktopcomputer", isPlayable: true),
        .init(id: "battery-voyage", areaID: .e, themeID: "H15", title: "消費電力とバッテリー",
              learningDescription: "残っているエネルギーと、それを使う速さを区別する。仕事や給電の条件を変え、使い続けられる時間を比べる。",
              guideInvitation: "同じ残量から出発しても、どんな仕事をするかで航路が変わりそう。", icon: "battery.75", isPlayable: true),
        .init(id: "cooling-workshop", areaID: .e, themeID: "H16", title: "発熱と冷却",
              learningDescription: "仕事から生まれる熱と、外へ逃がす熱を比べる。冷却や周囲の温度を変えて、続けられる速さを探す。",
              guideInvitation: "しばらく動かすと温かくなったね。熱の逃げ道を工夫してみよう。", icon: "fanblades", isPlayable: true),
        .init(id: "bottleneck-detective", areaID: .e, themeID: "H20", title: "PC性能とボトルネック",
              learningDescription: "仕事の各段階を観察し、一か所ずつ条件を変える。待ち時間を制限している場所が、仕事によって変わることを見つける。",
              guideInvitation: "どこで待っているのかな。ひとつだけ変えて、予想を確かめよう。", icon: "magnifyingglass", isPlayable: true)
    ]

    public static func area(_ id: ExhibitionAreaID) -> ExhibitionArea {
        // CaseIterable IDs and the complete catalog are checked together in core tests.
        areas.first { $0.id == id }!
    }

    public static func game(_ id: String) -> ExhibitionGame? { games.first { $0.id == id } }
    public static func games(in areaID: ExhibitionAreaID) -> [ExhibitionGame] { games.filter { $0.areaID == areaID } }
}

public enum ExhibitionRoute: Equatable, Sendable {
    case lobby
    case area(ExhibitionAreaID)
    case entry(String)
    case playing(String)
}

public enum ExhibitionGameStatus: String, Equatable, Sendable {
    case preparing, unvisited, visited, inProgress, completed

    public var title: String {
        switch self {
        case .preparing: return "準備中"
        case .unvisited: return "あそべる"
        case .visited: return "見つけた"
        case .inProgress: return "つづきから"
        case .completed: return "作品あり"
        }
    }

    public static func resolve(game: ExhibitionGame, visited: Bool, workshop: WorkshopSnapshot) -> Self {
        guard game.isPlayable else { return .preparing }
        if game.id == ExhibitionCatalog.circuitGameID {
            if workshop.completedArtifact != nil { return .completed }
            if workshop.hasStarted { return .inProgress }
        }
        return visited ? .visited : .unvisited
    }
}

public enum ExhibitionSaveError: Error, Equatable {
    case unsupportedVersion(Int)
    case tooLarge
}

/// Only museum visits are stored here. Learning completion belongs to each game's own model.
public struct ExhibitionProgress: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let maximumBytes = 65_536
    public private(set) var visitedGameIDs: Set<String>
    public private(set) var lastAreaID: ExhibitionAreaID?

    public init(visitedGameIDs: Set<String> = [], lastAreaID: ExhibitionAreaID? = nil) {
        self.visitedGameIDs = visitedGameIDs.intersection(Set(ExhibitionCatalog.games.map(\.id)))
        self.lastAreaID = lastAreaID
    }

    public mutating func visit(_ gameID: String) {
        guard let game = ExhibitionCatalog.game(gameID) else { return }
        visitedGameIDs.insert(gameID)
        lastAreaID = game.areaID
    }

    public mutating func navigate(to areaID: ExhibitionAreaID?) { lastAreaID = areaID }

    private enum CodingKeys: String, CodingKey { case schemaVersion, visitedGameIDs, lastAreaID }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.schemaVersion else { throw ExhibitionSaveError.unsupportedVersion(version) }
        let identifiers = try container.decode([String].self, forKey: .visitedGameIDs)
        let area = try container.decodeIfPresent(String.self, forKey: .lastAreaID)
        self.init(visitedGameIDs: Set(identifiers), lastAreaID: area.flatMap(ExhibitionAreaID.init(rawValue:)))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaVersion, forKey: .schemaVersion)
        try container.encode(visitedGameIDs.sorted(), forKey: .visitedGameIDs)
        try container.encodeIfPresent(lastAreaID?.rawValue, forKey: .lastAreaID)
    }

    public static func load(from url: URL) throws -> ExhibitionProgress {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= maximumBytes else { throw ExhibitionSaveError.tooLarge }
        let data = try Data(contentsOf: url)
        guard data.count <= maximumBytes else { throw ExhibitionSaveError.tooLarge }
        return try JSONDecoder().decode(Self.self, from: data)
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw ExhibitionSaveError.tooLarge }
        try data.write(to: url, options: .atomic)
    }
}
