import Foundation

public struct ParallelFrame: Codable, Equatable, Identifiable {
    public var id: Int { quantum }
    public var quantum: Int
    public var frameID: Int
    public var sourceQuantum: Int
    public var position: Double { Double(sourceQuantum) / 120 }
}

public struct ParallelDisplayModel: ExperienceModel {
    public static let gameID = "display-studio"
    public enum Action { case step, fps(Int), hz(Int), resolution(Bool), capacity(Bool), inspect(Int), window(Int), reset }
    public private(set) var stage: Int
    public private(set) var requestedFPS = 15
    public private(set) var hz = 60
    public private(set) var highResolution = false
    public private(set) var boosted = false
    public private(set) var quantum = 0
    public private(set) var generated: [ParallelFrame] = []
    public private(set) var displayed: [ParallelFrame] = []
    public private(set) var trials: [ParallelTrial] = []
    public private(set) var inspected: Int?
    public private(set) var windowStart = 0
    public var fps: Int { stage >= 4 ? min(requestedFPS, (highResolution ? 30 : 120) * (boosted ? 2 : 1)) : requestedFPS }
    public var pixelCount: Int { highResolution ? 9216 : 2304 }
    public var runFinished: Bool { quantum >= 120 }
    public var distinct: Int { Set(displayed.map(\.frameID)).count }
    public var stageTitle: String { ["コマを作る", "作る回数とめくる回数", "作った絵が全部出ない", "細かく描く", "何を優先する？"][stage - 1] }
    public var goal: String { ["生成15と30FPSを、同じ60Hzで1秒ずつ比べよう。", "生成30FPSのまま、表示30・60・120Hzを比べよう。", "生成60FPSの絵を、30Hzと60Hzで表示して比べよう。", "描画能力は同じ。縦横2倍にすると何が変わるかな。", "細かさと生成60FPSを両立するには？解像度と描画能力を比べよう。"][stage - 1] }
    public var guide: String {
        if isComplete { return "作る回数とめくる回数を分けて見られたね。実画面の能力以上は、コマ列で確かめよう。" }
        if let i = inspected, displayed.indices.contains(i) { let f = displayed[i]; return "この更新はF\(f.frameID)。\(String(format: "%.1f", Double(f.quantum) * 1000 / 120))msに表示された絵だよ。" }
        if runFinished { return "1秒で\(generated.count)枚作り、画面は\(displayed.count)回更新したね。異なる絵は\(distinct)枚だよ。" }
        return "絵を作る係と、画面をめくる係。下のコマの番号も見ながら進めよう。"
    }
    public var hints: [String] { ["上の列は作った絵、下の列は画面に出た絵だよ。", stage >= 4 ? "縦横2倍なら画素は4倍。この条件では同じ能力で作れる頻度が減るよ。" : "同じ番号が続くコマは、新しく作り直した絵ではないよ。", stage == 5 ? "細かい128×72のまま、描画能力を2倍にして比べてみよう。" : "一つの条件だけ変えて、同じ1秒を最初から再生しよう。"] }
    public var metrics: [ExperienceMetric] { [.init("生成", "\(fps) FPS"), .init("更新", "\(hz) Hz"), .init("作った絵", "\(generated.count)枚"), .init("画面更新", "\(displayed.count)回"), .init("異なる絵", "\(distinct)枚")] }
    public var isComplete: Bool {
        switch stage {
        case 1: return has(15,60,false,false) && has(30,60,false,false)
        case 2: return [30,60,120].allSatisfy { has(30,$0,false,false) }
        case 3: return has(60,30,false,false) && has(60,60,false,false)
        case 4: return has(120,120,false,false) && has(30,120,true,false)
        default: return has(120,120,false,false) && has(30,120,true,false) && has(60,120,true,true)
        }
    }
    public init(stage: Int) { self.stage = min(5,max(1,stage)); requestedFPS = self.stage == 1 ? 15 : self.stage == 2 ? 30 : self.stage == 3 ? 60 : 120; hz = self.stage >= 4 ? 120 : self.stage == 3 ? 30 : 60 }
    private func has(_ f: Int, _ h: Int, _ high: Bool, _ boost: Bool) -> Bool { trials.contains { $0.values == [f,h,high ? 1 : 0,boost ? 1 : 0] } }
    private mutating func rewind() { quantum = 0; generated = []; displayed = []; inspected = nil; windowStart = 0 }
    public mutating func send(_ action: Action) {
        switch action {
        case .fps(let n): guard stage == 1, [15,30].contains(n) else { return }; requestedFPS = n; rewind()
        case .hz(let n): guard (stage == 2 && [30,60,120].contains(n)) || (stage == 3 && [30,60].contains(n)) else { return }; hz = n; rewind()
        case .resolution(let high): guard stage >= 4 else { return }; highResolution = high; rewind()
        case .capacity(let boost): guard stage == 5 else { return }; boosted = boost; rewind()
        case .inspect(let i): guard displayed.indices.contains(i) else { return }; inspected = i
        case .window(let start): windowStart = max(0,min(max(0,displayed.count - 6),start))
        case .reset: rewind()
        case .step:
            guard !runFinished else { return }
            let next = min(120,quantum + 120 / hz)
            while quantum < next {
                if quantum % (120 / fps) == 0 { generated.append(ParallelFrame(quantum: quantum,frameID: generated.count,sourceQuantum: quantum)) }
                if quantum % (120 / hz) == 0, let latest = generated.last { displayed.append(ParallelFrame(quantum: quantum,frameID: latest.frameID,sourceQuantum: latest.quantum)) }
                quantum += 1
            }
            windowStart = max(0,displayed.count - 6)
            if runFinished {
                let key = "\(fps)-\(hz)-\(highResolution)-\(boosted)"
                trials.removeAll { $0.key == key }
                trials.append(ParallelTrial(key,"\(fps)FPS / \(hz)Hz・\(highResolution ? "128×72" : "64×36")",120,[fps,hz,highResolution ? 1 : 0,boosted ? 1 : 0]))
            }
        }
    }
}
