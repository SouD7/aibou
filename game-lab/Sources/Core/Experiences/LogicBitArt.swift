import Foundation

public struct LogicBitArtModel: ExperienceModel {
    public static let gameID = "bit-art"
    public enum Action { case select(Int), toggle(Int), chooseValue(Int), assignColor(Int), addBit, removeBit, switchMapping, record, beginComparison, expandComparison }
    public var stage: Int
    public private(set) var bits: Int
    public private(set) var pixels: [Int]
    public private(set) var palette: [Int]
    public private(set) var selected = 0
    public private(set) var mappingB = false
    public private(set) var observedValues: Set<Int> = []
    public private(set) var mappingObservations: Set<Bool> = []
    public private(set) var comparisons: [Int: [Int]] = [:]
    public private(set) var originalPixels: [Int]?
    public private(set) var originalPalette: [Int]?
    public private(set) var comparisonMode = false
    public private(set) var message = "点を選んで、0と1を切り替えてみよう。"
    public static let colorNames = ["白", "灰", "青", "緑", "黄", "シアン", "紫", "赤", "橙"]
    public static let target = [0, 1, 2, 3, 4, 5, 6, 7, 8, 0, 1, 2, 3, 4, 5, 8]
    public init(stage: Int) {
        self.stage = min(5, max(1, stage)); bits = self.stage == 1 ? 1 : 3
        pixels = Array(repeating: 0, count: self.stage < 3 ? 1 : 16)
        palette = Array(0..<(1 << bits))
        if self.stage == 3 { pixels = [0,5,2,3,4,0,5,7,2,3,4,5,7,6,0,2]; selected = 6 }
    }
    public var stageTitle: String { ["ひとつの合図", "8枚の絵札", "色の約束", "9色目", "小さな作品"][stage - 1] }
    public var goal: String { ["0と1、両方の光り方を記録しよう。", "3本のスイッチで、異なる8通りを見つけよう。", "101の数字を変えず、色の約束AとBを比べよう。", "9色の目標絵を作ろう。合図は何本必要かな？", "自分の絵を描き、同じ2色の絵を1bitと3bitで比べよう。"][stage - 1] }
    public var value: Int { pixels[selected] }
    public var binary: String { String(repeating: "0", count: max(0, bits - String(value, radix: 2).count)) + String(value, radix: 2) }
    public var colors: [Int] { pixels.map { palette[$0] } }
    public var totalBits: Int { pixels.count * bits }
    public var guide: String { isComplete ? "組み合わせと、読み方の約束を確かめられたね。絵を作品に残そう。" : message }
    public var hints: [String] {
        if stage == 3 { return ["数字と色、どちらが変わるかな？", "101の点を選んだまま、約束を変えてみよう。", "約束Aで記録してからBに切り替え、もう一度記録しよう。"] }
        if stage == 4 { return ["3本で何色まで区別できたかな？", "9色目は今の8通りに入りきらないね。", "1本足して1000を作り、色を橙に割り当ててみよう。"] }
        if stage == 5 { return ["同じ絵で、情報の入れ物だけを変えよう。", "『2色で比べる』は元の作品を残して別の絵を作るよ。", "1bitの絵を記録し、3bitの入れ物にしてもう一度記録しよう。"] }
        return ["一つのスイッチを変えると、どうなるかな？", "まだ記録していない数字を探そう。", "000から111までを一つずつ作って『記録』してみよう。"]
    }
    public var isComplete: Bool {
        switch stage {
        case 1: return observedValues == [0,1]
        case 2: return observedValues.count == 8
        case 3: return mappingObservations.count == 2
        case 4: return bits == 4 && colors == Self.target
        default: return comparisons[1] != nil && comparisons[1] == comparisons[3]
        }
    }
    public var metrics: [ExperienceMetric] { [.init("選んだ点", "\(binary) = \(value)"), .init("色", Self.colorNames[palette[value]]), .init("画素データ", "\(pixels.count) × \(bits) = \(totalBits) bit", detail: "圧縮や見出しを含まない教材内の量"), .init("観察", stage == 3 ? "\(mappingObservations.count) / 2" : "\(observedValues.count) 通り")] }
    public var isValid: Bool { (1...5).contains(stage) && (1...4).contains(bits) && [1,16].contains(pixels.count) && pixels.indices.contains(selected) && palette.count == 1 << bits && palette.allSatisfy { (0..<9).contains($0) } && pixels.allSatisfy { palette.indices.contains($0) } }
    public mutating func send(_ action: Action) {
        switch action {
        case .select(let index): guard pixels.indices.contains(index) else { return }; selected = index
        case .toggle(let bit): guard (0..<bits).contains(bit) else { return }; pixels[selected] ^= 1 << bit; message = "\(binary)は\(value)。この約束では\(Self.colorNames[palette[value]])になるね。"
        case .chooseValue(let value): guard palette.indices.contains(value) else { return }; pixels[selected] = value
        case .assignColor(let color):
            guard [4,5].contains(stage), Self.colorNames.indices.contains(color) else { return }
            palette[value] = color; message = "\(binary)を\(Self.colorNames[color])と読む約束にしたよ。同じ数字の点も変わるね。"
        case .addBit:
            guard bits < 4, stage >= 4, !comparisonMode else { return }; palette += Array(repeating: 0, count: 1 << bits); bits += 1; message = "4本になったね。16通りから色を割り当てられるよ。"
        case .removeBit:
            guard stage >= 4, bits > 1, !comparisonMode else { return }
            guard pixels.allSatisfy({ $0 < 1 << (bits - 1) }) else { message = "今の数字は少ない本数に収まらないよ。作品を残して別の絵で比べよう。"; return }
            bits -= 1; palette = Array(palette.prefix(1 << bits))
        case .switchMapping:
            guard stage == 3 else { return }; mappingB.toggle(); palette.swapAt(5,6); message = "同じ101でも、約束\(mappingB ? "B" : "A")では\(mappingB ? "紫" : "シアン")になるね。"
        case .record:
            observedValues.insert(value)
            if stage == 3 && value == 5 { mappingObservations.insert(mappingB) }
            if stage == 5 && comparisonMode { comparisons[bits] = colors }
            message = "今の数字と色、条件を記録したよ。"
        case .beginComparison:
            guard stage == 5 else { return }
            if originalPixels == nil { originalPixels = pixels; originalPalette = palette }
            pixels = Array(repeating: 0, count: 16); bits = 1; palette = [0,1]; selected = 0; comparisonMode = true; comparisons = [:]
            message = "元の作品は残してあるよ。この白と灰の絵を同じ条件で比べよう。"
        case .expandComparison:
            guard stage == 5 && comparisonMode && bits == 1 else { return }
            guard comparisons[1] != nil else { message = "まず1bitの絵を記録しよう。"; return }
            bits = 3; palette = [0,1,0,0,0,0,0,0]; message = "絵は同じまま、入れ物は3bitになったよ。量を記録して比べよう。"
        }
    }
}
