import Foundation

public struct MemoryCacheTrial: Codable, Equatable {
    public var capacity: Int; public var order: String; public var ticks: Int; public var hits: Int
}
public struct MemoryCacheModel: ExperienceModel {
    public static let gameID = "cache-delivery"
    public enum Action { case step, replace(String?), configure(Int), order(Int), restart }
    public private(set) var stage: Int
    public private(set) var capacity: Int
    public private(set) var requests: [String]
    public private(set) var cache: [String] = []
    public private(set) var index = 0
    public private(set) var ticks = 0
    public private(set) var hits = 0
    public private(set) var remaining = 0
    public private(set) var currentHit = false
    public private(set) var pending: String?
    public private(set) var log: [String] = []
    public private(set) var trials: [MemoryCacheTrial] = []
    public private(set) var message = ""
    public var next: String? { index < requests.count ? requests[index] : nil }
    public var finished: Bool { index == requests.count && pending == nil }
    public var stageTitle: String { ["近くから届く", "2つの置き場", "残すものを選ぶ", "順番が変わる", "全部はじめて"][stage-1] }
    public var goal: String { ["Aを2回届けて、はじめてと2回目の時間を比べよう。", "同じA B A Bを、近い棚1口と2口で届けよう。", "A B A C A Bを18拍以内で届けよう。次に使うものを手元へ残そう。", "同じ個数の注文を、二つの順番で届けて比べよう。", "全部違う6個の注文を、近い棚なしと3口で比べよう。"][stage-1] }
    public var hints: [String] {
        switch stage {
        case 1: return ["次も同じAだね。最初のAを手元へ置いておこう。", "遠い棚からは4拍、手元にあれば1拍で届くよ。", "1拍ずつ進めて2個とも届けよう。原本を遠い棚に残したまま、合計5拍で届くね。"]
        case 2: return ["AとBを交互に頼まれているね。手元は何口あるとよさそう？", "1口では、次のBを置くとAを手放すことになるよ。", "棚1口で全部届けたら棚2口に変えてもう一度。16拍と10拍を比べよう。"]
        case 3: return ["届いた品だけでなく、その次の要求を見よう。", "Cの次にはAが来るね。Aを手元へ残せるかな？", "Cが来たらBを選んで入れ替えよう。次のAが1拍で届くと全体18拍になるよ。"]
        case 4: return ["頼まれる個数は同じ。でも順番は違うね。", "同じ品が続くと、入れ替える前に手元の品を何回も使えるよ。", "A B A C A Bを終えてからA A A B B Cへ切り替え、18拍と15拍を比べよう。"]
        default: return ["今日は全部違う品。このあと同じ品をまた使うかな？", "手元の棚を広げても、初めての品は遠い棚へ取りに行くよ。", "棚なしで全部届けたら3口でも試そう。どちらも6個×4拍で24拍になるね。"]
        }
    }
    public var metrics: [ExperienceMetric] { [.init("経過", "\(ticks) 拍"), .init("届いた注文", "\(index) / \(requests.count)"), .init("近い棚", "\(cache.count) / \(capacity)"), .init("手元から", "\(hits) 回"), .init("次の便", pending.map { "\($0)の置換待ち" } ?? next ?? "完了")] }
    public var guide: String { if isComplete { return "同じ条件で比べると、再利用と置き場の違いが見えたね。" }; if !message.isEmpty { return message }; return "今日の注文を運ぼう。手元にも置いておくと、次はどうなるかな？" }
    public var isComplete: Bool {
        switch stage {
        case 1: return finished && ticks == 5
        case 2: return trials.contains { $0.capacity == 1 && $0.ticks == 16 } && trials.contains { $0.capacity == 2 && $0.ticks == 10 }
        case 3: return finished && ticks <= 18
        case 4: return trials.contains { $0.order == "ABACAB" && $0.ticks == 18 } && trials.contains { $0.order == "AAABBC" && $0.ticks == 15 }
        default: return trials.contains { $0.capacity == 0 && $0.ticks == 24 } && trials.contains { $0.capacity == 3 && $0.ticks == 24 }
        }
    }
    public var isValid: Bool {
        (1...5).contains(stage) && (0...3).contains(capacity) && cache.count <= capacity && Set(cache).count == cache.count
        && (0...requests.count).contains(index) && (1...8).contains(requests.count) && requests.allSatisfy { ["A","B","C","D","E","F"].contains($0) }
        && cache.allSatisfy { requests.contains($0) } && (0...4).contains(remaining)
        && (remaining == 0 || (index < requests.count && pending == nil))
        && (pending == nil || (index > 0 && pending == requests[index-1] && remaining == 0 && cache.count == capacity && !cache.contains(pending!)))
        && ticks >= 0 && ticks <= 100 && hits >= 0 && hits <= index && log.count == index && trials.count <= 20
    }
    public init(stage: Int) {
        self.stage = min(5,max(1,stage)); capacity = 2; requests = ["A","B","A","C","A","B"]
        switch self.stage { case 1: capacity = 1; requests = ["A","A"]; case 2: capacity = 1; requests = ["A","B","A","B"]; case 5: capacity = 0; requests = ["A","B","C","D","E","F"]; default: break }
    }
    private mutating func clearRun() { cache=[]; index=0; ticks=0; hits=0; remaining=0; pending=nil; log=[]; message="同じ注文を、空の棚からもう一度比べよう。" }
    private mutating func record() {
        guard finished else { return }
        let t = MemoryCacheTrial(capacity: capacity, order: requests.joined(), ticks: ticks, hits: hits)
        if !trials.contains(t) { trials.append(t); if trials.count > 20 { trials.removeFirst() } }
        message = "\(requests.count)個が\(ticks)拍で届いたよ。手元からは\(hits)回だったね。"
    }
    public mutating func send(_ action: Action) {
        switch action {
        case .configure(let value):
            let allowed = stage == 2 ? [1,2] : stage == 5 ? [0,3] : [capacity]
            guard allowed.contains(value) else { return }; capacity=value; clearRun()
        case .order(let value):
            guard stage == 4 && (0...1).contains(value) else { return }; requests = value == 0 ? ["A","B","A","C","A","B"] : ["A","A","A","B","B","C"]; clearRun()
        case .restart: clearRun()
        case .replace(let old):
            guard let arriving = pending else { return }
            if let old { guard let slot = cache.firstIndex(of: old) else { return }; cache[slot] = arriving }
            pending=nil; message = old.map { "\($0)を外して\(arriving)を残したね。元データは遠い棚にあるよ。" } ?? "\(arriving)は手元に残さず届けたよ。"
            record()
        case .step:
            guard pending == nil else { message="届いた品をどれと入れ替えるか選ぼう。今回の品を残さなくてもいいよ。"; return }
            guard let item=next else { record(); return }
            if remaining == 0 { currentHit=cache.contains(item); remaining=currentHit ? 1 : 4 }
            ticks += 1; remaining -= 1
            message = "\(item)を\(currentHit ? "手元" : "遠い棚")から運んでいるよ。あと\(remaining)拍。"
            if remaining == 0 {
                if currentHit { hits += 1 }
                log.append("\(item) · \(currentHit ? "手元 1拍" : "遠い棚 4拍")")
                index += 1
                if !currentHit && capacity > 0 { if cache.count < capacity { cache.append(item) } else { pending=item } }
                message = pending == nil ? "\(item)が届いたよ。次の注文は何かな？" : "\(item)が届いたよ。何を手元に残そうか？"
                record()
            }
        }
    }
}
