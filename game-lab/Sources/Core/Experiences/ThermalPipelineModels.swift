import Foundation

public struct CoolingSample: Codable, Equatable {
    public var tick: Int
    public var heat: Int
    public var work: Int
    public var noise: Int
    public var restricted: Bool
}
public struct CoolingRun: Codable, Equatable {
    public var cooler: Int
    public var fast: Bool
    public var warm: Bool
    public var length: Int
    public var sample: CoolingSample
}
public struct CoolingModel: ExperienceModel {
    public static let gameID = "cooling-workshop"
    public enum Action { case step, cooler(Int), fast(Bool), warm(Bool), length(Int), retry, inspect(Int) }
    public var stage: Int
    public var cooler = 3
    public var fast = false
    public var warm = false
    public var length = 4
    public var tick = 0
    public var heat = 0
    public var work = 0
    public var noise = 0
    public var restricted = false
    public var samples: [CoolingSample] = []
    public var runs: [CoolingRun] = []
    public var inspected: Int?
    public init(stage: Int) {
        self.stage = min(5, max(1, stage)); fast = stage != 1
        length = stage == 1 || stage == 5 ? 4 : (stage == 2 ? 12 : 16)
        if stage == 3 || stage == 4 { cooler = 5 }
        if stage == 4 { warm = true }
    }
    public var stageTitle: String { ["熱はあとからたまる", "速さを続ける", "静かな依頼", "暖かい場所へ", "次の依頼を予想"][stage-1] }
    public var goal: String {
        switch stage {
        case 1: return "ゆっくりと速く。各4刻み動かして、熱と完成数を比べよう。"
        case 2: return "12刻みで24個の作品を作り続けよう。"
        case 3: return "16刻みで26個以上。音は20ポイント以内に収めよう。"
        case 4: return "2つの周囲を比べ、16刻みで30個以上作れる場所を選ぼう。"
        default: return "4刻みで8個と、12刻みで24個。両方の依頼を満たそう。"
        }
    }
    public var cooling: Int { max(0, cooler - (warm ? 2 : 0)) }
    public var heatPerStep: Int { fast && !restricted ? 5 : 2 }
    public var canStep: Bool { tick < length }
    public var isComplete: Bool {
        guard tick == length else { return false }
        switch stage {
        case 1: return runs.contains { !$0.fast && $0.sample.tick == 4 } && runs.contains { $0.fast && $0.sample.tick == 4 }
        case 2: return work >= 24
        case 3: return work >= 26 && noise <= 20
        case 4: return work >= 30 && runs.contains { $0.warm } && runs.contains { !$0.warm }
        default: return runs.contains { $0.length == 4 && $0.sample.work >= 8 } && runs.contains { $0.length == 12 && $0.sample.work >= 24 }
        }
    }
    public var guide: String {
        if isComplete {
            if stage == 3 { return "\(work)個できたね。音も\(noise)で依頼の範囲に収まったよ。" }
            if heat == 0 { return "続けて作れたね。この条件なら、熱をためずに動かせたよ。" }
            return "\(work)個できたね。終わりには熱が\(heat)たまっているよ。"
        }
        if restricted { return "速くする設定だけど、今は1個ずつ。直前の熱を見てみよう。" }
        if tick == length { return stage == 3 && noise > 20 ? "作品はできたね。静かさの条件も比べてみよう。" : "今回の記録は残してあるよ。条件を変えて、同じ最初から比べよう。" }
        if heat >= 16 { return "熱が\(heat)になったね。次の刻みの作る速さを見てみよう。" }
        return tick == 0 ? "私は完成した数を数えるね。熱のたまり方を、一緒に見よう。" : "生まれる熱は\(heatPerStep)、逃がせる熱は\(cooling)。どちらが大きいかな？"
    }
    public var hints: [String] { ["始めた直後と、しばらく後。作る速さは同じかな？", "発熱と放熱の差が、熱のたまり方につながるよ。", stage == 3 ? "静音ファンで16刻み試して、完成数と音を一緒に見てみよう。" : stage == 1 ? "モードだけを切り替え、もう一度4刻み動かしてみよう。" : stage == 4 ? "周囲を通常へ戻すと、有効な放熱はどうなるかな？" : "放熱5の部品なら、速くの発熱5と釣り合うよ。"] }
    public var metrics: [ExperienceMetric] { [.init("刻み", "\(tick) / \(length)"), .init("完成", "\(work) 個"), .init("熱", "\(heat) ポイント"), .init("音の合計", "\(noise)"), .init("動作", restricted ? "保護中 · 1個ずつ" : (fast ? "速く · 2個ずつ" : "ゆっくり · 1個ずつ"))] }
    public var isValid: Bool { (1...5).contains(stage) && [1,3,5].contains(cooler) && [4,12,16].contains(length) && (0...length).contains(tick) && heat >= 0 && heat <= 160 && work >= 0 && work <= 64 && noise >= 0 && noise <= 96 && samples.count <= 32 && runs.count <= 10 }
    public mutating func send(_ action: Action) {
        switch action {
        case .step:
            guard canStep else { return }
            if heat >= 16 { restricted = true } else if restricted && heat <= 10 { restricted = false }
            let effectiveFast = fast && !restricted
            heat = max(0, heat + (effectiveFast ? 5 : 2) - cooling)
            work += effectiveFast ? 2 : 1; noise += cooler == 5 ? 3 : cooler == 3 ? 1 : 0
            tick += 1; inspected = nil
            let sample = CoolingSample(tick: tick, heat: heat, work: work, noise: noise, restricted: restricted)
            samples.append(sample)
            if tick == length { runs.append(CoolingRun(cooler: cooler, fast: fast, warm: warm, length: length, sample: sample)); runs = Array(runs.suffix(10)) }
        case .cooler(let value):
            guard [2,3,5].contains(stage), [1,3,5].contains(value), value != cooler, stage != 2 || value != 1 else { return }
            reset(); cooler = value
        case .fast(let value): guard stage == 1, value != fast else { return }; reset(); fast = value
        case .warm(let value): guard stage == 4, value != warm else { return }; reset(); warm = value
        case .length(let value): guard stage == 5, [4,12].contains(value), value != length else { return }; reset(); length = value
        case .retry: reset()
        case .inspect(let index): guard samples.indices.contains(index) else { return }; inspected = index
        }
    }
    private mutating func reset() { tick = 0; heat = 0; work = 0; noise = 0; restricted = false; samples = []; inspected = nil }
}

public struct PipelineSample: Codable, Equatable {
    public var tick: Int; public var unread: Int; public var q1: Int; public var q2: Int; public var done: Int
}
public struct PipelineConfig: Codable, Equatable, Hashable {
    public var read: Int; public var cpu: Int; public var write: Int; public var ram: Int
    public func differences(_ other: Self) -> Int { [read != other.read, cpu != other.cpu, write != other.write, ram != other.ram].filter { $0 }.count }
}
public struct PipelineRun: Codable, Equatable { public var config: PipelineConfig; public var ticks: Int; public var samples: [PipelineSample] }
public struct BottleneckModel: ExperienceModel {
    public static let gameID = "bottleneck-detective"
    public enum Action { case step, upgrade(String), retry, inspect(Int) }
    public var stage: Int
    public var config: PipelineConfig
    public var unread = 6; public var q1 = 0; public var q2 = 0; public var done = 0; public var tick = 0
    public var samples: [PipelineSample] = []
    public var runs: [PipelineRun] = []
    public var observedThird = false
    public var inspected: Int?
    public var notice = ""
    public init(stage: Int) { self.stage = min(5,max(1,stage)); config = Self.baseline(stage) }
    public static func baseline(_ stage: Int) -> PipelineConfig {
        switch stage {
        case 3: return .init(read: 2, cpu: 2, write: 2, ram: 2)
        case 4: return .init(read: 1, cpu: 3, write: 3, ram: 8)
        case 5: return .init(read: 2, cpu: 1, write: 1, ram: 8)
        default: return .init(read: 2, cpu: 1, write: 2, ram: 8)
        }
    }
    public var stageTitle: String { ["待っているのは誰", "一か所だけ改善", "置き場所が先", "別の仕事", "同じ速さの二か所"][stage-1] }
    public var goal: String { stage == 1 ? "6個を最後まで流し、3刻み目の待ち列を観察しよう。" : stage == 5 ? "一か所ずつ変えた3本の比較を残し、5刻み以内に届けよう。" : "一か所を変えて、同じ6個を5刻み以内に届けよう。" }
    public var canStep: Bool { done < 6 && tick < 32 }
    public var isComplete: Bool {
        guard done == 6 else { return false }
        if stage == 1 { return observedThird }
        guard tick <= 5 else { return false }
        if stage == 5 {
            return runs.indices.dropFirst(2).contains { i in
                runs[i-2].config == Self.baseline(5) && runs[i-1].config.differences(runs[i-2].config) == 1 && runs[i].config.differences(runs[i-1].config) == 1 && runs[i].config == config && runs[i].ticks <= 5
            }
        }
        return true
    }
    public var guide: String {
        if !notice.isEmpty { return notice }
        if isComplete { return stage == 1 ? "3刻み目は計算前に4個。この列が、手がかりになったね。" : "同じ仕事が5刻みで終わった！変えた場所と、列の変化を残そう。" }
        if stage == 5, done == 6, config.cpu == 2, config.write == 1 { return "計算は速くなったね。でも出口が1個ずつ待たせているみたい。" }
        if stage == 5, done == 6, config.cpu == 1, config.write == 2 { return "出口は空いているけど、計算は1個ずつ進んでいるね。" }
        if done == 6 { return stage == 1 ? "記録の3刻み目を選んで、列の中を見てみよう。" : "今回は\(tick)刻みだったね。変わらなかったことも手がかりだよ。" }
        if q1 + q2 >= config.ram && unread > 0 { return "読み込みが空き枠を待っているね。計算を速くすると変わるかな？" }
        if q1 > config.cpu { return "ここに順番待ちができたね。前と後は、いくつずつ進めているかな？" }
        return "私は完成までの刻みを数えるね。どの列が増えるか、見ていて。"
    }
    public var hints: [String] { [stage == 3 ? "読み込めないとき、RAMの空き枠を見てみよう。" : "長い待ち列の、次の装置を見てみよう。", stage == 4 ? "今回の読み込みは1、計算は3だね。" : "一度に進める数と、入ってくる数を比べよう。", stage == 1 ? "下の履歴から「3」を選ぶと、待ち列を観察できるよ。" : stage == 3 ? "RAMを2から4へ変えて、同じ6個を試してみよう。" : stage == 4 ? "読み込みを2へ変えてみよう。" : stage == 5 ? "計算と出口を、一回の試行で一か所ずつ2へ変えて比べよう。" : "CPUを1から2へ変えて、同じ6個を試してみよう。"] }
    public var metrics: [ExperienceMetric] { [.init("今回", "\(tick) 刻み"), .init("完成", "\(done) / 6"), .init("RAM使用", "\(q1+q2) / \(config.ram)"), .init("比較記録", "\(runs.count) 本"), .init("目標", stage == 1 ? "3刻み目を観察" : "5刻み以内")] }
    public var isValid: Bool { (1...5).contains(stage) && [unread,q1,q2,done].allSatisfy { (0...6).contains($0) } && unread+q1+q2+done == 6 && q1+q2 <= config.ram && (0...32).contains(tick) && (1...6).contains(config.read) && (1...6).contains(config.cpu) && (1...6).contains(config.write) && [2,4,8].contains(config.ram) && samples.count <= 32 && runs.count <= 10 }
    public mutating func send(_ action: Action) {
        notice = ""
        switch action {
        case .step:
            guard canStep else { return }
            let out = min(config.write,q2); let compute = min(config.cpu,q1)
            let read = min(config.read,unread,config.ram-(q1+q2-out))
            unread -= read; q1 += read-compute; q2 += compute-out; done += out; tick += 1; inspected = nil
            samples.append(.init(tick: tick, unread: unread, q1: q1, q2: q2, done: done))
            if done == 6 { runs.append(.init(config: config,ticks: tick,samples: samples)); runs = Array(runs.suffix(10)) }
        case .upgrade(let item):
            guard stage != 1 else { return }
            var next = stage == 5 ? config : Self.baseline(stage)
            switch (stage,item) {
            case (2,"read"): next.read = 3
            case (2,"cpu"): next.cpu = 2
            case (2,"write"): next.write = 3
            case (3,"cpu"): next.cpu = 4
            case (3,"ram"): next.ram = 4
            case (4,"read"): next.read = 2
            case (4,"cpu"): next.cpu = 6
            case (5,"cpu"): next.cpu = 2
            case (5,"write"): next.write = 2
            default: return
            }
            if stage == 5 {
                guard done == 6, let last = runs.last, last.config == config, next.differences(config) == 1 else { notice = "まず今の条件で最後まで流そう。その記録から一か所だけ変えるよ。"; return }
            }
            guard next != config else { return }; config = next; reset()
        case .retry: reset()
        case .inspect(let index):
            guard samples.indices.contains(index) else { return }
            inspected = index
            let s = samples[index]
            if stage == 1 && s.tick == 3 && s.q1 == 4 && s.q2 == 1 && s.done == 1 { observedThird = true }
        }
    }
    private mutating func reset() { tick = 0; unread = 6; q1 = 0; q2 = 0; done = 0; samples = []; inspected = nil }
}
