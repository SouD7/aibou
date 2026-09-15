import Foundation

public struct MemoryStorageTrial: Codable, Equatable {
    public var capacity: Int; public var rate: Int; public var latency: Int; public var sizes: [Int]; public var eighths: Int
}
public struct MemoryStorageModel: ExperienceModel {
    public static let gameID = "storage-warehouse"
    public enum Action { case step, capacity(Int), rate(Int), latency(Int), bundle(Bool), scenario(Int), restart }
    public private(set) var stage: Int
    public private(set) var capacityMB=32
    public private(set) var usedMB=16
    public private(set) var rate=4
    public private(set) var latency=8
    public private(set) var sizes=[4,4,4,4]
    public private(set) var scenario=0
    public private(set) var index=0
    public private(set) var phase="ready"
    public private(set) var phaseRemaining=0
    public private(set) var elapsed=0
    public private(set) var delivered=0
    public private(set) var finished=false
    public private(set) var trials: [MemoryStorageTrial]=[]
    public private(set) var message=""
    public var totalMB: Int { sizes.reduce(0,+) }
    public var isWriting: Bool { stage == 1 }
    public var secondsText: String { Self.time(elapsed) }
    public static func time(_ eighths: Int) -> String { eighths % 8 == 0 ? "\(eighths/8)" : String(format:"%.3f",Double(eighths)/8).replacingOccurrences(of:"0+$",with:"",options:.regularExpression) }
    public var stageTitle: String { ["棚が足りない","広いのに待つ","運ぶ速さ","小分けの荷物","どこを変える"][stage-1] }
    public var goal: String { ["8MBのデータを保存しよう。棚の広さと転送の速さ、どちらを変える？", "同じ4×4MBを、容量16MBと32MBで読み比べよう。", "同じ4×4MBを、4MB/sと8MB/sで読み比べよう。", "同じ16MBを、4回に分ける場合と1回にまとめる場合で比べよう。", "大きい1件と小さい8件。転送速度と準備待ち、どちらの改善が効くかな？"][stage-1] }
    public var hints: [String] {
        switch stage {
        case 1: return ["すでに8MB入っている棚へ、さらに8MB保存したいね。", "速く運べても、空き容量が4MBでは8MBの荷物は収まらないよ。", "棚容量を16MBにしてから進めよう。元の8MBと新しい8MBを両方保存できるよ。"]
        case 2: return ["棚の容量と、荷物を運ぶ速さを見比べよう。", "読み出す16MBと速度4MB/s、準備1秒が同じなら、広い棚でも運ぶ時間は変わらないよ。", "16MBの棚で全部読んだあと32MBに変えてもう一度。どちらも8秒だね。"]
        case 3: return ["待っている時間と、運んでいる時間を分けて見よう。", "速度を上げても、各荷物の前の準備1秒は残るよ。", "4MB/sで終えてから8MB/sへ変えてもう一度。8秒から6秒へ短くなるね。"]
        case 4: return ["総量はどちらも16MB。荷物の数が違うね。", "荷物を一つ始めるたびに準備1秒。まとめると、その回数が減るよ。", "4件×4MBを終えてから1件×16MBへ。準備が4回から1回になり、8秒から5秒になるね。"]
        default: return ["大きい1件と小さい8件、それぞれで待つ場所を比べよう。", "速度8MB/sは転送を、準備0.5秒は荷物ごとの待ちを減らすよ。", "大きい1件で速度8と準備0.5を比較。小さい8件でも両方を試すと、効果の大きい改善が逆になるね。"]
        }
    }
    public var metrics: [ExperienceMetric] { [.init("保存庫", "\(usedMB) / \(capacityMB) MB"), .init("転送", "\(rate) MB/s", detail:"準備 \(Self.time(latency)) 秒/件"), .init("到着", "\(delivered) / \(totalMB) MB"), .init("経過", "\(secondsText) 秒"), .init("いま", phase == "setup" ? "準備中" : phase == "transfer" ? "転送中" : finished ? "完了" : "待機")] }
    public var guide: String { isComplete ? "棚の広さ、道の速さ、始める前の待ち。それぞれの働きを比べられたね。" : message.isEmpty ? "同じ荷物で条件を変えてみよう。どこで待つのかな？" : message }
    public var isComplete: Bool {
        switch stage {
        case 1: return finished && usedMB == 16
        case 2: return trials.contains { $0.capacity == 16 && $0.eighths == 64 } && trials.contains { $0.capacity == 32 && $0.eighths == 64 }
        case 3: return trials.contains { $0.rate == 4 && $0.eighths == 64 } && trials.contains { $0.rate == 8 && $0.eighths == 48 }
        case 4: return trials.contains { $0.sizes.count == 4 && $0.eighths == 64 } && trials.contains { $0.sizes.count == 1 && $0.eighths == 40 }
        default: return trials.contains { $0.sizes == [16] && $0.rate == 8 && $0.latency == 8 && $0.eighths == 24 } && trials.contains { $0.sizes == [16] && $0.rate == 4 && $0.latency == 4 && $0.eighths == 36 } && trials.contains { $0.sizes.count == 8 && $0.rate == 8 && $0.latency == 8 && $0.eighths == 72 } && trials.contains { $0.sizes.count == 8 && $0.rate == 4 && $0.latency == 4 && $0.eighths == 48 }
        }
    }
    public var isValid: Bool {
        guard (1...5).contains(stage), [4,8].contains(rate), [4,8].contains(latency), [12,16,32].contains(capacityMB), usedMB>=0, usedMB<=capacityMB,
              (1...8).contains(sizes.count), sizes.allSatisfy({ $0>0 && $0<=16 }), (0...sizes.count).contains(index), elapsed>=0, elapsed<1000,
              ["ready","setup","transfer","done"].contains(phase), phaseRemaining>=0, phaseRemaining<=32,
              delivered==sizes.prefix(index).reduce(0,+), trials.count<=20 else { return false }
        if finished { return index==sizes.count && phase=="done" && phaseRemaining==0 }
        return index<sizes.count && phase != "done" && ((phase=="ready" && phaseRemaining==0) || (phase != "ready" && phaseRemaining>0))
    }
    public init(stage:Int) { self.stage=min(5,max(1,stage)); if self.stage==1 { capacityMB=12; usedMB=8; sizes=[8] }; if self.stage==2 { capacityMB=16 }; if self.stage==5 { sizes=[16] } }
    private mutating func resetRun() { index=0; phase="ready"; phaseRemaining=0; elapsed=0; delivered=0; finished=false; usedMB=stage==1 ? 8 : 16; message="同じ条件から、もう一度送れるよ。" }
    public mutating func send(_ action:Action) {
        switch action {
        case .restart: resetRun()
        case .capacity(let n): guard (stage==1 && [12,16].contains(n)) || (stage==2 && [16,32].contains(n)) else { return }; capacityMB=n; resetRun()
        case .rate(let n): guard [1,3,5].contains(stage), [4,8].contains(n) else { return }; rate=n; if stage==5 { latency=8 }; resetRun()
        case .latency(let n): guard stage==5, [4,8].contains(n) else { return }; latency=n; rate=4; resetRun()
        case .bundle(let yes): guard stage==4 else { return }; sizes=yes ? [16] : [4,4,4,4]; resetRun()
        case .scenario(let n): guard stage==5, [0,1].contains(n) else { return }; scenario=n; sizes=n==0 ? [16] : Array(repeating:1,count:8); resetRun()
        case .step:
            guard !finished else { return }
            guard !isWriting || usedMB+totalMB<=capacityMB else { message="棚にあと\(usedMB+totalMB-capacityMB)MB必要だね。転送を速くしても空きは増えないよ。"; return }
            for _ in 0..<8 {
                if finished { break }
                if phase=="ready" { phase="setup"; phaseRemaining=latency }
                elapsed += 1; phaseRemaining -= 1
                if phaseRemaining==0 {
                    if phase=="setup" { phase="transfer"; phaseRemaining=sizes[index]*8/rate }
                    else {
                        delivered += sizes[index]; index += 1
                        if index==sizes.count {
                            finished=true; phase="done"; if isWriting { usedMB += totalMB }
                            let t=MemoryStorageTrial(capacity:capacityMB,rate:rate,latency:latency,sizes:sizes,eighths:elapsed)
                            if !trials.contains(t) { trials.append(t); if trials.count>20 { trials.removeFirst() } }
                        } else { phase="ready" }
                    }
                }
            }
            if finished { message="\(totalMB)MBが\(secondsText)秒で届いたよ。条件を一つ変えて比べよう。" }
            else if phase=="ready" { message="\(delivered)MBが到着。次の荷物は待機中だよ。" }
            else { message="\(delivered)MBが到着。いまは\(phase=="setup" ? "準備の待ち時間" : "転送")だよ。" }
        }
    }
}
