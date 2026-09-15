import Foundation

public struct ParallelBoardModel: ExperienceModel {
    public static let gameID = "board-town"
    public enum Action { case step, connect(Bool), soc(Bool), shared(Bool), capacity(Int), position(Bool), reset }
    public private(set) var stage: Int
    public private(set) var tick = 0
    public private(set) var connected = false
    public private(set) var soc = false
    public private(set) var shared = false
    public private(set) var capacity = 1
    public private(set) var shifted = false
    public private(set) var deliveredUnits: [String] = []
    public private(set) var trials: [ParallelTrial] = []
    public var unitOrder: [String] { ["CPU1","GPU1","CPU2","GPU2"] }
    public var waitingUnits: [String] { unitOrder.filter { !deliveredUnits.contains($0) } }
    public var cpuReceived: Int { deliveredUnits.filter { $0.hasPrefix("CPU") }.count }
    public var gpuReceived: Int { deliveredUnits.filter { $0.hasPrefix("GPU") }.count }
    public var totalSteps: Int { stage <= 2 ? 6 : stage == 3 ? (shared ? 2 : 3) : (4 + capacity - 1) / capacity }
    public var runFinished: Bool { tick >= totalSteps }
    public var processLabels: [String] { stage == 3 ? (shared ? ["CPUが作る","GPUが使う"] : ["CPUが作る","別領域へコピー","GPUが使う"]) : ["SSD→RAM","CPUが読む","CPUが計算","GPUが読む","GPUが計算","画面へ出力"] }
    public var stageTitle: String { ["役割をつなぐ", "同じ役割、違うまとまり", "同じ置き場所を使う", "同じ道を使う", "置き方を変えたら"][stage - 1] }
    public var goal: String { ["切れたRAM→GPUをつないで、写真を画面まで届けよう。", "役割は同じ。別パッケージとSoCのまとまりを比べよう。", "CPUの成果をGPUへ。別メモリと共有メモリで比べよう。", "CPUとGPUへ2個ずつ。同じ道の幅1と2を比べよう。", "見た目の配置を変えて、同じデータの到着を比べよう。"][stage - 1] }
    public var hints: [String] { ["止まった機能から、必要なデータをたどろう。", stage >= 4 ? "CPUとGPUの線は、同じ道を使っているよ。" : "機能を囲む枠と、実際に通る道は別のものだよ。", stage == 4 ? "共有路を2個ずつ通れる部品に替えて、同じ4個を流そう。" : "条件を一つ変え、同じ始まりからもう一度試そう。"] }
    public var guide: String {
        if stage == 1 && !connected && tick >= 3 { return "CPUまで進んだね。GPUが読むための、メモリへの線が切れているよ。" }
        if isComplete { return "役割と置き方、道の条件を分けて見られたね。枠にまとめるだけで速くなるわけではないんだね。" }
        if stage >= 4 { return "CPUに\(cpuReceived)個、GPUに\(gpuReceived)個届いたよ。共有の道で残り\(waitingUnits.count)個を待っているね。" }
        if runFinished { return "\(tick)手で届いたね。まとまりや置き場所を替えて、同じ仕事を比べよう。" }
        return "\(processLabels[min(tick,processLabels.count - 1)])の番だね。必要なデータがどこから来るか見てみよう。"
    }
    public var metrics: [ExperienceMetric] {
        if stage >= 4 { return [.init("いま","\(tick)手"),.init("CPU","\(cpuReceived) / 2"),.init("GPU","\(gpuReceived) / 2"),.init("待ち","\(waitingUnits.count)個")] }
        return [.init("いま","\(tick)手"),.init("工程","\(tick) / \(totalSteps)"),.init("配置",soc ? "SoC" : "別パッケージ"),.init("メモリ",shared ? "共有" : "条件カード")]
    }
    public var isComplete: Bool {
        switch stage {
        case 1: return trials.contains { $0.ticks == 6 }
        case 2: return trials.contains { $0.key == "separate" } && trials.contains { $0.key == "soc" }
        case 3: return trials.contains { $0.key == "copy" } && trials.contains { $0.key == "shared" }
        case 4: return trials.contains { $0.key == "capacity1" } && trials.contains { $0.key == "capacity2" }
        default: return trials.contains { $0.key == "position0" } && trials.contains { $0.key == "position1" }
        }
    }
    public init(stage: Int) { self.stage = min(5,max(1,stage)); connected = self.stage != 1; soc = self.stage >= 3; shared = self.stage >= 4 }
    private mutating func rewind() { tick = 0; deliveredUnits = [] }
    public mutating func send(_ action: Action) {
        switch action {
        case .connect(let b): guard stage == 1 else { return }; connected = b; rewind()
        case .soc(let b): guard stage == 2 || stage == 4 else { return }; soc = b; rewind()
        case .shared(let b): guard stage == 3 else { return }; shared = b; rewind()
        case .capacity(let n): guard stage == 4, [1,2].contains(n) else { return }; capacity = n; rewind()
        case .position(let b): guard stage == 5 else { return }; shifted = b; rewind()
        case .reset: rewind()
        case .step:
            guard !runFinished, !(stage == 1 && !connected && tick >= 3) else { return }
            if stage >= 4 { deliveredUnits.append(contentsOf: waitingUnits.prefix(capacity)) }
            tick += 1
            if runFinished {
                let key: String
                switch stage { case 1: key = "connected"; case 2: key = soc ? "soc" : "separate"; case 3: key = shared ? "shared" : "copy"; case 4: key = "capacity\(capacity)"; default: key = "position\(shifted ? 1 : 0)" }
                let label = stage == 2 ? (soc ? "SoC" : "別パッケージ") : stage == 3 ? (shared ? "共有メモリ" : "別メモリ") : stage == 4 ? "道幅\(capacity)" : stage == 5 ? (shifted ? "位置を変更" : "元の位置") : "接続済み"
                trials.removeAll { $0.key == key }; trials.append(ParallelTrial(key,label,tick))
            }
        }
    }
}
