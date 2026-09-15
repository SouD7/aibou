import Foundation

public struct LogicTinySwitchModel: ExperienceModel {
    public static let gameID = "tiny-switch-workshop"
    public enum Layout: String, Codable, CaseIterable { case series, parallel; public var title: String { self == .series ? "直列" : "並列" } }
    public enum Action { case toggle(Int), place(Int), connect(Int), changeLayout(Layout), invert(Int), power, record, test, replay(Int) }
    public struct Observation: Codable, Equatable { public var a: Int; public var b: Int; public var actual: Int?; public var expected: Int; public var matches: Bool { actual == expected } }
    public var stage: Int
    public private(set) var inputs = [0,0]
    public private(set) var placed = [false,false]
    public private(set) var connected = [false,false]
    public private(set) var activeOn = [1,1]
    public private(set) var layout = Layout.series
    public private(set) var powered = true
    public private(set) var observations: [Observation] = []
    public private(set) var message = "部品を置いて、開閉の合図をつなごう。"
    public init(stage: Int) { self.stage = min(5,max(1,stage)) }
    public var switchCount: Int { [1,4].contains(stage) ? 1 : 2 }
    public var stageTitle: String { ["合図で道を開く", "ふたりの許可", "別々の入口", "合図を反対に", "条件を読み替える"][stage-1] }
    public var goal: String { ["Aが1のときだけ、道を通してランプをつけよう。", "AとBの両方が1のときだけ、ランプをつけよう。", "AかB、少なくとも片方が1ならランプをつけよう。", "Aが0のときに点灯し、1のときは消える装置にしよう。", "どちらの呼び出しでも点灯。両方押したときも確かめよう。"][stage-1] }
    public func isClosed(_ index: Int) -> Bool { placed[index] && connected[index] && inputs[index] == activeOn[index] }
    public var output: Int? {
        guard powered, (0..<switchCount).allSatisfy({ placed[$0] && connected[$0] }) else { return nil }
        let pass = switchCount == 1 ? isClosed(0) : layout == .series ? isClosed(0) && isClosed(1) : isClosed(0) || isClosed(1)
        return pass ? 1 : 0
    }
    public var guide: String {
        if isComplete { return "つなぎ方と開閉の条件で、光り方を作れたね。道をたどって作品に残そう。" }
        return message
    }
    public var hints: [String] {
        switch stage {
        case 2: return ["両方の許可がないと、届かない道を作ろう。", "二つを順番に通る必要がある形はどちらかな？", "直列にして、両方を『1で通る』にして試そう。"]
        case 3,5: return ["ランプまで、通れる道が一つでもあるかな？", "二つのスイッチを順番に通る必要があるか見よう。", "入口で道を二つに分ける『並列』を試そう。"]
        case 4: return ["合図と反対の光り方を作りたいね。", "スイッチの『通る条件』も変えられるよ。", "部品を『0で通る』に切り替えて、A0とA1を比べよう。"]
        default: return ["信号用と通り道の端子は別だね。", "部品を置いて、紫の制御端子につなごう。", "Aを切り替えて、通る・止まるを記録しよう。"]
        }
    }
    public var isComplete: Bool { observations.count == (switchCount == 1 ? 2 : 4) && observations.allSatisfy(\.matches) && output != nil }
    public var metrics: [ExperienceMetric] { [.init("つなぎ方", switchCount == 1 ? "1つのスイッチ" : layout.title), .init("入力", switchCount == 1 ? "A \(inputs[0])" : "A \(inputs[0]) · B \(inputs[1])"), .init("ランプ", powered ? output.map(String.init) ?? "? 未接続" : "電源OFF"), .init("一致した条件", "\(observations.filter(\.matches).count) / \(switchCount == 1 ? 2 : 4)")] }
    public var isValid: Bool { (1...5).contains(stage) && inputs.count == 2 && placed.count == 2 && connected.count == 2 && activeOn.count == 2 && inputs.allSatisfy { (0...1).contains($0) } && activeOn.allSatisfy { (0...1).contains($0) } && observations.count <= 4 }
    private func expected(a: Int,b: Int) -> Int {
        switch stage { case 1: return a; case 2: return a == 1 && b == 1 ? 1 : 0; case 4: return 1-a; default: return a == 1 || b == 1 ? 1 : 0 }
    }
    private mutating func addObservation() {
        guard let output else { message = powered ? "部品を置いて、紫の制御線をつないでね。" : "電源を入れてから確かめよう。"; return }
        let currentA = inputs[0], currentB = inputs[1], single = switchCount == 1
        observations.removeAll { $0.a == currentA && (single || $0.b == currentB) }
        let row = Observation(a: inputs[0], b: inputs[1], actual: output, expected: expected(a: inputs[0],b: inputs[1])); observations.append(row)
        message = row.matches ? "この入力では目標どおりだね。他の条件も見よう。" : "この入力では\(row.expected)にしたいけれど、実際は\(output)だね。止まった道を見よう。"
    }
    public mutating func send(_ action: Action) {
        switch action {
        case .toggle(let i): guard (0..<switchCount).contains(i) else { return }; inputs[i] = 1-inputs[i]; message = "\(i == 0 ? "A" : "B")を\(inputs[i])にしたよ。通り道はどうなったかな？"
        case .place(let i): guard (0..<switchCount).contains(i) else { return }; placed[i].toggle(); if !placed[i] { connected[i] = false }; observations = []
        case .connect(let i): guard (0..<switchCount).contains(i), placed[i] else { message = "先に部品を置こう。"; return }; connected[i].toggle(); observations = []
        case .changeLayout(let new): guard switchCount == 2 else { return }; layout = new; observations = []; message = "\(new.title)の道になったね。同じ入力でもう一度比べよう。"
        case .invert(let i): guard (0..<switchCount).contains(i), placed[i] else { return }; activeOn[i] = 1-activeOn[i]; observations = []
        case .power: powered.toggle(); observations = []
        case .record: addObservation()
        case .test:
            guard output != nil else { addObservation(); return }; observations = []
            for a in 0...1 { for b in 0..<(switchCount == 1 ? 1 : 2) { inputs = [a,b]; addObservation() } }
        case .replay(let index): guard observations.indices.contains(index) else { return }; inputs = [observations[index].a, observations[index].b]
        }
    }
}
