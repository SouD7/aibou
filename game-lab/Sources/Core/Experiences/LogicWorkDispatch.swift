import Foundation

public struct LogicWorkDispatchModel: ExperienceModel {
    public static let gameID = "work-dispatch"
    public enum Action { case admit(Int), select(Int), step, close(Int), pause(Int), capacity(Int), rewind, recordComparison }
    public enum Status: String, Codable { case pending, ready, paused, waiting, completed }
    public struct Job: Codable, Equatable {
        public var name: String
        public var symbol: String
        public var ram: Int
        public var work: Int
        public var done = 0
        public var status = Status.pending
        public var ioLength = 0
        public var ioRemaining = 0
        public var ioTriggered = false
        public var firstService: Int?
        public var completedAt: Int?
    }
    public struct Comparison: Codable, Equatable { public var capacity: Int; public var timeline: [Int?]; public var first: [Int?]; public var completed: [Int?] }
    public var stage: Int
    public private(set) var capacity: Int
    public private(set) var jobs: [Job]
    public private(set) var selected: Int?
    public private(set) var tick = 0
    public private(set) var timeline: [Int?] = []
    public private(set) var comparisons: [Comparison] = []
    public private(set) var sawLoadedWithoutWork = false
    public private(set) var message = "仕事を作業場所に載せて、CPUの1コマを渡そう。"
    public init(stage: Int) {
        self.stage = min(5,max(1,stage)); capacity = [3,5].contains(self.stage) ? 6 : 4
        jobs = Self.makeJobs(stage: self.stage)
    }
    private static func makeJobs(stage: Int) -> [Job] {
        if stage == 4 { return [Job(name: "通信", symbol: "envelope", ram: 1, work: 2, ioLength: 2), Job(name: "計算", symbol: "cpu", ram: 3, work: 3)] }
        let photo = Job(name: "写真", symbol: "photo", ram: 3, work: stage == 1 ? 3 : 4)
        return stage == 1 ? [photo] : [photo, Job(name: "音楽", symbol: "music.note", ram: 2, work: 2)]
    }
    public var stageTitle: String { ["場所と時間", "机が足りない", "少しずつ応える", "待ちを使う", "条件を一つ変える"][stage-1] }
    public var goal: String { ["仕事を載せただけの状態と、3コマ計算した状態を比べよう。", "4枠の机を使って、写真と音楽を両方終えよう。", "最初の2コマで両方へ1回ずつ応え、6コマで全部終えよう。", "通信を待つ間にも計算し、5コマで両方終えよう。", "机の広さだけ、配分だけを変えた2つの比較を残そう。"][stage-1] }
    public var used: Int { jobs.filter { [.ready,.paused,.waiting].contains($0.status) }.reduce(0) { $0 + $1.ram } }
    public var allDone: Bool { jobs.allSatisfy { $0.status == .completed } }
    public var guide: String { isComplete ? "場所と計算の時間を分けて工夫できたね。応答と全体の時間も比べられたよ。" : message }
    public var hints: [String] {
        switch stage {
        case 1: return ["載せただけで計算は進むかな？", "CPUに渡す仕事を選ぼう。", "写真を載せて選び、1コマずつ3回進めよう。"]
        case 2: return ["必要な枠と空き枠を見比べよう。", "終わった仕事の場所は空くよ。", "音楽を先に2コマで終え、写真を載せて4コマ進めよう。"]
        case 4: return ["待ち時間のあいだ、CPUは使えるかな？", "通信の返事を待ちながら計算を進めよう。", "通信 → 計算 → 計算 → 通信 → 計算、を試そう。"]
        case 5: return ["一度に変える条件を一つにしよう。", "同じ配分で机6枠と8枠を比べよう。", "6枠の同じ仕事で配分を変えた記録も加えると、違いを分けて見られるよ。"]
        default: return ["両方から早く返事がほしいね。", "最初の2コマを同じ仕事だけに渡す必要はあるかな？", "写真 → 音楽 → 写真 → 音楽 → 写真 → 写真、を試してみよう。"]
        }
    }
    public var isComplete: Bool {
        switch stage {
        case 1: return sawLoadedWithoutWork && allDone
        case 2: return allDone
        case 3: return allDone && tick <= 6 && jobs.allSatisfy { ($0.firstService ?? 99) <= 2 }
        case 4: return allDone && tick <= 5
        default:
            let capacityPair = comparisons.contains { a in comparisons.contains { b in a.capacity != b.capacity && a.timeline == b.timeline } }
            let orderPair = comparisons.contains { a in comparisons.contains { b in a.capacity == b.capacity && a.timeline != b.timeline } }
            return capacityPair && orderPair
        }
    }
    public var metrics: [ExperienceMetric] { [.init("作業場所", "\(used) / \(capacity) 枠"), .init("CPU", "1台 · \(tick) コマ"), .init("最初の応答", jobs.map { "\($0.name): \($0.firstService.map(String.init) ?? "まだ")" }.joined(separator: " / ")), .init("完了", "\(jobs.filter { $0.status == .completed }.count) / \(jobs.count)"), .init("比較", "\(comparisons.count)試行")] }
    public var isValid: Bool { (1...5).contains(stage) && [4,6,8].contains(capacity) && jobs.count == (stage == 1 ? 1 : 2) && jobs.allSatisfy { (1...8).contains($0.ram) && (1...60).contains($0.work) && $0.done >= 0 && $0.done <= $0.work && (0...2).contains($0.ioRemaining) } && used <= capacity && timeline.count == tick && (0...60).contains(tick) && comparisons.count <= 10 && (selected == nil || jobs.indices.contains(selected!)) && timeline.allSatisfy { $0 == nil || jobs.indices.contains($0!) } }
    public mutating func send(_ action: Action) {
        switch action {
        case .admit(let i):
            guard jobs.indices.contains(i), jobs[i].status == .pending else { return }
            guard used + jobs[i].ram <= capacity else { message = "必要なのは\(jobs[i].ram)枠、空いているのは\(capacity-used)枠だね。"; return }
            jobs[i].status = .ready; selected = i
            if stage == 1 && jobs[i].done == 0 { sawLoadedWithoutWork = true }
            message = "机に載ったね。計算はまだ\(jobs[i].done)/\(jobs[i].work)。次のコマを渡そう。"
        case .select(let i): guard jobs.indices.contains(i) else { return }; selected = i
        case .pause(let i): guard jobs.indices.contains(i) else { return }; if jobs[i].status == .ready { jobs[i].status = .paused } else if jobs[i].status == .paused { jobs[i].status = .ready }; message = "一時停止しても、作業場所は使ったままだよ。"
        case .close(let i): guard jobs.indices.contains(i), jobs[i].status != .completed else { return }; let original = Self.makeJobs(stage: stage)[i]; jobs[i] = original; message = "仕事を閉じて、場所を空けたよ。途中の計算は最初からになるね。"
        case .capacity(let size): guard stage == 5, [4,6,8].contains(size) else { return }; capacity = size; restart(); message = "机だけを\(size)枠に変えたよ。同じ仕事と配分で比べよう。"
        case .rewind: restart(); message = "仕事を同じ初期条件に戻したよ。比較の記録は残っているよ。"
        case .recordComparison:
            guard allDone else { message = "全ての仕事を終えてから、この試行を比較に残そう。"; return }
            let value = Comparison(capacity: capacity,timeline: timeline,first: jobs.map(\.firstService),completed: jobs.map(\.completedAt))
            if !comparisons.contains(value) { comparisons.append(value); if comparisons.count > 10 { comparisons.removeFirst() } }
            message = "机\(capacity)枠・\(tick)コマの試行を残したよ。条件を一つ変えて比べよう。"
        case .step: advance()
        }
    }
    private mutating func restart() { jobs = Self.makeJobs(stage: stage); tick = 0; timeline = []; selected = nil }
    private mutating func advance() {
        guard !allDone, tick < 60 else { return }
        let waiting = jobs.indices.filter { jobs[$0].status == .waiting }
        let ready = jobs.indices.filter { jobs[$0].status == .ready }
        var worker: Int?
        if let selected, ready.contains(selected) { worker = selected }
        else if !ready.isEmpty { message = "CPUを渡す、準備できた仕事を選ぼう。待っている仕事は時計で見分けられるよ。"; return }
        else if waiting.isEmpty { message = "まず仕事を載せるか、一時停止した仕事を再開しよう。"; return }
        if let worker { jobs[worker].done += 1; if jobs[worker].firstService == nil { jobs[worker].firstService = tick+1 } }
        for i in waiting { jobs[i].ioRemaining -= 1; if jobs[i].ioRemaining == 0 { jobs[i].status = .ready } }
        if let worker, jobs[worker].ioLength > 0 && !jobs[worker].ioTriggered && jobs[worker].done == 1 { jobs[worker].ioTriggered = true; jobs[worker].ioRemaining = jobs[worker].ioLength; jobs[worker].status = .waiting }
        tick += 1; timeline.append(worker)
        for i in jobs.indices where jobs[i].completedAt == nil && jobs[i].done == jobs[i].work && jobs[i].ioRemaining == 0 { jobs[i].status = .completed; jobs[i].completedAt = tick }
        message = worker.map { "\(jobs[$0].name)に1コマ渡したよ。場所は\(used)/\(capacity)枠だね。" } ?? "CPUは待ちながら、通信の時間が1コマ進んだよ。"
        if allDone && !isComplete { message = "全部終わったね。最初に応えた時点と、目標のコマ数を比べよう。" }
    }
}
