import Foundation

public struct ParallelPixelModel: ExperienceModel {
    public static let gameID = "pixel-factory"
    public enum Action { case step, device(Bool), resident(Bool), reset }
    public private(set) var stage: Int
    public private(set) var useGPU = false
    public private(set) var resident = false
    public private(set) var tick = 0
    public private(set) var pass = 0
    public private(set) var processed = 0
    public private(set) var phase = "準備"
    public private(set) var remainingSetup = 0
    public private(set) var pixels: [Int] = []
    public private(set) var trials: [ParallelTrial] = []
    public var count: Int { stage == 1 ? 4 : stage == 3 ? 2 : 16 }
    public var source: [Int] { Array([0,1,1,0,1,2,2,1,1,2,2,1,0,1,1,0].prefix(count)) }
    public var stageTitle: String { ["4つの画素", "16画素をまとめよう", "小さな依頼", "前の画素の答え", "2回まとめて"][stage - 1] }
    public var goal: String { stage == 5 ? "2回の加工を、毎回戻す場合とまとめる場合で比べよう。" : "同じ原画をCPUとGPUで加工し、できた絵と総時間を比べよう。" }
    public var hints: [String] { ["塗る時間の前後にも注目しよう。", stage == 4 ? "この手順では、前の画素の答えが必要だよ。" : "GPUの準備は2手、読み戻しは1手。計算だけと分けて見よう。", stage == 5 ? "まとめると、2回目に準備と読み戻しを繰り返さずに進められるよ。" : "機械を切り替え、同じ原画からもう一度試してみよう。"] }
    public var guide: String {
        if isComplete { return "同じ絵でも、量や手順で得意な機械が変わるね。前後の時間も比べられたよ。" }
        if runFinished { return "\(tick)手で出力できたね。同じ原画でもう一方も試してみよう。" }
        if phase == "読み戻し" { return "画素はできたね。出力口へ戻すまで、もう1手かかるよ。" }
        if phase == "準備" { return "まとめて塗る前の準備だね。計算の時間とは別に数えよう。" }
        return "\(processed)画素できたね。\(stage == 4 ? "次は前の画素の答えを使うよ。" : useGPU ? "4画素ずつ進むよ。" : "1画素ずつ進むよ。")"
    }
    public var runFinished: Bool { phase == "完成" }
    public var isComplete: Bool {
        if stage == 5 { return trials.contains { $0.key == "gpu-split" && $0.ticks == 14 } && trials.contains { $0.key == "gpu-resident" && $0.ticks == 11 } }
        return trials.contains { $0.key == "cpu" } && trials.contains { $0.key == "gpu" }
    }
    public var metrics: [ExperienceMetric] { [.init("実行", "\(tick)手"), .init("加工済み", "\(processed) / \(count)"), .init("段階", phase), .init("加工", "\(pass + 1) / \(stage == 5 ? 2 : 1)回")] }
    public init(stage: Int) { self.stage = min(5,max(1,stage)); useGPU = self.stage == 5; rewind() }
    private mutating func rewind() { tick = 0; pass = 0; processed = 0; pixels = source; remainingSetup = useGPU ? 2 : 0; phase = useGPU ? "準備" : "計算" }
    private mutating func finish() {
        phase = "完成"
        let key = stage == 5 ? (resident ? "gpu-resident" : "gpu-split") : useGPU ? "gpu" : "cpu"
        let title = stage == 5 ? (resident ? "まとめる" : "毎回戻す") : useGPU ? "GPU" : "CPU"
        trials.removeAll { $0.key == key }; trials.append(ParallelTrial(key,title,tick,pixels))
    }
    public mutating func send(_ action: Action) {
        switch action {
        case .device(let gpu): guard stage != 5 || gpu else { return }; useGPU = gpu; rewind()
        case .resident(let b): guard stage == 5 else { return }; resident = b; rewind()
        case .reset: rewind()
        case .step:
            guard !runFinished, tick < 64 else { return }; tick += 1
            if phase == "準備" { remainingSetup -= 1; if remainingSetup == 0 { phase = "計算" }; return }
            if phase == "読み戻し" {
                if stage == 5 && pass == 0 { pass = 1; processed = 0; remainingSetup = 2; phase = "準備" } else { finish() }; return
            }
            let end = min(count, processed + (useGPU && stage != 4 ? 4 : 1))
            for i in processed..<end { pixels[i] = stage == 4 ? ((i > 0 ? pixels[i - 1] : 0) + source[i]) % 4 : min(3,pixels[i] + 1) }
            processed = end
            if processed == count {
                if stage == 5 && pass == 0 && (!useGPU || resident) { pass = 1; processed = 0 }
                else if useGPU { phase = "読み戻し" }
                else { finish() }
            }
        }
    }
}
