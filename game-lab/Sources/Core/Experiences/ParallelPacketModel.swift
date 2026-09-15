import Foundation

public struct ParallelPacket: Codable, Equatable, Identifiable {
    public var id: Int
    public var sentAt: Int?
    public var arrival: Int?
    public var delivered = false
    public var lost = false
    public var retryAt: Int?
    public var attempts = 0
}

public struct ParallelPacketModel: ExperienceModel {
    public static let gameID = "packet-express"
    public enum Action { case step, bandwidth(Int), latency(Int), connection(Bool), retry(Bool), reset }
    public private(set) var stage: Int
    public private(set) var tick = 0
    public private(set) var bandwidth = 1
    public private(set) var latency = 1
    public private(set) var connected = false
    public private(set) var retryEnabled = false
    public private(set) var packets: [ParallelPacket] = []
    public private(set) var trials: [ParallelTrial] = []
    public private(set) var firstArrival: Int?
    public var count: Int { stage == 1 || stage == 5 ? 4 : stage == 4 ? 6 : 8 }
    public var deliveredCount: Int { packets.filter(\.delivered).count }
    public var runFinished: Bool { deliveredCount == count }
    public var stalled: Bool { stage == 5 && !retryEnabled && deliveredCount == 3 && packets.filter({ !$0.delivered }).allSatisfy(\.lost) }
    public var stageTitle: String { ["届く道", "道を広げると", "道を短くすると", "小さな往復", "一通だけ迷子"][stage - 1] }
    public var goal: String { ["切れた道をつないで4通届けよう。最初と全部の到着を見よう。", "幅1と4で同じ8通を配送し、初便と全便を比べよう。", "幅4のまま、移動3手と1手で同じ8通を比べよう。", "3往復の返事待ち。幅を広げる場合と移動を減らす場合を比べよう。", "2番だけ初回に失われる条件。再送なしとありを比べよう。"][stage - 1] }
    public var hints: [String] { ["待っているのは出発前？道の上？返事が必要かな？", stage == 5 ? "2番の初回だけ届かない条件だよ。番号をそろえるには同じ便りを再送しよう。" : "幅は毎手に出発できる数。移動にかかる手数とは別だよ。", stage == 4 ? "幅4でも返事を待つ回数は同じ。移動を1手にして比べてみよう。" : "同じ便りを最初から流し、最初の到着と全便の到着を残そう。"] }
    public var guide: String {
        if !connected { return "道が一か所、切れているね。つなぐと便りが届くかな？" }
        if isComplete { return "同じ便りで比べられたね。道幅と移動時間は、効くところが違うね。" }
        if stalled { return "3通届いたけど、2番が足りないね。再送するとどうなるかな？" }
        if runFinished { return "最初は\(firstArrival ?? 0)手、全部は\(tick)手で届いたよ。条件を一つ変えて比べよう。" }
        if stage == 4 { return "今は\(deliveredCount / 2)往復。返事が届いてから次の便りを送るよ。" }
        return "\(deliveredCount)通届いたね。道の上の便りは、あと何手で着くかな？"
    }
    public var metrics: [ExperienceMetric] { [.init("いま", "\(tick)手"), .init("到着", "\(deliveredCount) / \(count)"), .init("初便", firstArrival.map { "\($0)手" } ?? "未到着"), .init("全便", runFinished ? "\(tick)手" : "未完了")] }
    public var isComplete: Bool {
        switch stage {
        case 1: return trials.contains { $0.ticks == 5 }
        case 2: return has(1,3,false) && has(4,3,false)
        case 3: return has(4,3,false) && has(4,1,false)
        case 4: return has(1,3,false) && has(4,3,false) && trials.contains { $0.values[1] == 1 && $0.ticks == 12 }
        default: return has(2,1,false) && has(2,1,true)
        }
    }
    public init(stage: Int) { self.stage = min(5,max(1,stage)); latency = [2,3,4].contains(self.stage) ? 3 : 1; bandwidth = self.stage == 3 ? 4 : self.stage == 5 ? 2 : 1; connected = self.stage != 1; rewind() }
    private func has(_ b: Int, _ l: Int, _ retry: Bool) -> Bool { trials.contains { $0.values.prefix(3).elementsEqual([b,l,retry ? 1 : 0]) } }
    private mutating func rewind() { tick = 0; firstArrival = nil; packets = (1...count).map { ParallelPacket(id:$0) } }
    private mutating func record() {
        let key = "\(bandwidth)-\(latency)-\(retryEnabled)"
        trials.removeAll { $0.key == key }
        trials.append(ParallelTrial(key,"幅\(bandwidth)・移動\(latency)\(stage == 5 ? (retryEnabled ? "・再送あり" : "・再送なし") : "")",tick,[bandwidth,latency,retryEnabled ? 1 : 0,firstArrival ?? 0,deliveredCount]))
    }
    public mutating func send(_ action: Action) {
        switch action {
        case .bandwidth(let b): guard [2,4].contains(stage), [1,4].contains(b) else { return }; bandwidth = b; rewind()
        case .latency(let l): guard [3,4].contains(stage), [1,3].contains(l) else { return }; latency = l; rewind()
        case .connection(let c): guard stage == 1 else { return }; connected = c; rewind()
        case .retry(let r): guard stage == 5 else { return }; retryEnabled = r; rewind()
        case .reset: rewind()
        case .step:
            guard connected, !runFinished, !stalled, tick < 64 else { return }
            var candidates = packets.indices.filter { packets[$0].sentAt == nil || (retryEnabled && packets[$0].lost && (packets[$0].retryAt ?? Int.max) <= tick) }
            if stage == 4 { candidates = candidates.filter { $0 == 0 || packets[$0 - 1].delivered } }
            for i in candidates.prefix(bandwidth) {
                packets[i].sentAt = tick; packets[i].attempts += 1
                let lost = stage == 5 && packets[i].id == 2 && packets[i].attempts == 1
                packets[i].lost = lost; packets[i].arrival = lost ? nil : tick + 1 + latency
                packets[i].retryAt = lost ? tick + 1 + 2 * (latency + 1) : nil
            }
            tick += 1
            for i in packets.indices where packets[i].arrival == tick { packets[i].delivered = true; if firstArrival == nil { firstArrival = tick } }
            if runFinished || stalled { record() }
        }
    }
}
