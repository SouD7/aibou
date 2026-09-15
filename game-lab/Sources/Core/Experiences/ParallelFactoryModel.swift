import Foundation

public struct ParallelTrial: Codable, Equatable, Identifiable {
    public var id: String { key }
    public var key: String
    public var label: String
    public var ticks: Int
    public var values: [Int]
    public init(_ key: String, _ label: String, _ ticks: Int, _ values: [Int] = []) {
        self.key = key; self.label = label; self.ticks = ticks; self.values = values
    }
}

public struct ParallelFactoryTask: Codable, Equatable, Identifiable {
    public var id: Int
    public var title: String
    public var duration: Int
    public var prerequisites: [Int]
    public var remaining: Int
    public var lane: Int
    public var isDone: Bool { remaining == 0 }
}

public struct ParallelFactoryModel: ExperienceModel {
    public static let gameID = "parallel-factory"
    public enum Action { case step, workers(Int), assign(Int, Int), moveEarlier(Int), inspect(Int), reset }
    public private(set) var stage: Int
    public private(set) var workers = 1
    public private(set) var tick = 0
    public private(set) var tasks: [ParallelFactoryTask] = []
    public private(set) var queueOrder: [Int] = []
    public private(set) var trials: [ParallelTrial] = []
    public private(set) var activeTasks: [Int] = []
    public private(set) var inspectedTask: Int?
    public private(set) var observedDependency = false
    public private(set) var notice = ""
    public var stageTitle: String { ["並べて同時に", "先の答えを待つ", "一列につながる", "分ける準備", "条件が変わったら"][stage - 1] }
    public var goal: String { ["同じ4枚を、1人と2人で完成させて比べよう。", "1人の記録と比べて、2人で8手以内に。組立の待ちも調べよう。", "つながる4工程を、1人と4人で比べよう。", "配布と集約も含めて、1人と2人で比べよう。", "準備が4手に増えたよ。2人で10手以内に完成させよう。"][stage - 1] }
    public var hints: [String] { ["同時に始めても困らない札を探そう。", stage == 3 ? "次の札は、前の札が終わるまで待つよ。" : "準備ができれば、色の札はお互いを待たずに進められるよ。", "札を選んで別のレーンを押すと分担できるよ。先に必要な札は前へ置こう。"] }
    public var guide: String {
        if !notice.isEmpty { return notice }
        if isComplete { return "同じ仕事で比べられたね。人数と、前の答えを待つ時間は別々なんだね。" }
        if let id = inspectedTask, let task = tasks.first(where: { $0.id == id }), !task.prerequisites.isEmpty {
            let names = tasks.filter { task.prerequisites.contains($0.id) }.map(\.title).joined(separator: "・")
            return "「\(task.title)」は「\(names)」が終わると動けるよ。"
        }
        if runFinished { return "\(tick)手でできたね。条件を変えて、同じ仕事を比べてみよう。" }
        if tick > 0 && activeTasks.isEmpty { return "進める札が待っているね。レーンの順番と、必要な先の札を見てみよう。" }
        return tick == 0 ? "この仕事を仕上げたいな。一緒にできる札はどれかな？" : "\(completedCount)枚できたね。次に始められる札を見てみよう。"
    }
    public var completedCount: Int { tasks.filter(\.isDone).count }
    public var runFinished: Bool { !tasks.isEmpty && completedCount == tasks.count }
    public var isComplete: Bool {
        switch stage {
        case 1: return has(1, 8) && has(2, 4)
        case 2: return has(1, 12) && has(2, 8) && observedDependency
        case 3: return has(1, 8) && has(4, 8)
        case 4: return has(1, 4) && has(2, 4)
        default: return has(2, 10)
        }
    }
    public var metrics: [ExperienceMetric] {
        [.init("働き手", "\(workers)人"), .init("いま", "\(tick)手"), .init("完了", "\(completedCount) / \(tasks.count)"), .init("比べた条件", "\(trials.count)")]
    }
    public init(stage: Int) { self.stage = min(5, max(1, stage)); if self.stage == 5 { workers = 2 }; configure() }
    private func has(_ count: Int, _ limit: Int) -> Bool { trials.contains { $0.key == "w\(count)" && $0.ticks <= limit } }
    private mutating func configure() {
        tick = 0; activeTasks = []; inspectedTask = nil; notice = ""
        let definitions: [(String, Int, [Int])]
        switch stage {
        case 1: definitions = (0..<4).map { ("色\(["A","B","C","D"][$0])", 2, []) }
        case 2, 5: definitions = [("準備", stage == 5 ? 4 : 2, []), ("色A",2,[0]), ("色B",2,[0]), ("色C",2,[0]), ("色D",2,[0]), ("組立",2,[1,2,3,4])]
        case 3: definitions = (0..<4).map { ("工程\($0 + 1)",2,$0 == 0 ? [] : [$0 - 1]) }
        default: definitions = workers == 1 ? [("色A",2,[]),("色B",2,[])] : [("配布",1,[]),("色A",2,[0]),("色B",2,[0]),("集約",1,[1,2])]
        }
        tasks = definitions.enumerated().map { ParallelFactoryTask(id: $0.offset, title: $0.element.0, duration: $0.element.1, prerequisites: $0.element.2, remaining: $0.element.1, lane: 0) }
        queueOrder = tasks.map(\.id)
    }
    private mutating func rewind() { tick = 0; activeTasks = []; for i in tasks.indices { tasks[i].remaining = tasks[i].duration }; notice = "" }
    public func laneTasks(_ lane: Int) -> [ParallelFactoryTask] { queueOrder.compactMap { id in tasks.first { $0.id == id && $0.lane == lane } } }
    public func waitingFor(_ task: ParallelFactoryTask) -> String {
        if task.isDone { return "完了" }
        if activeTasks.contains(task.id) { return "作業中" }
        let missing = task.prerequisites.compactMap { id in tasks.first { $0.id == id && !$0.isDone }?.title }
        return missing.isEmpty ? "始められる" : missing.joined(separator: "・") + "待ち"
    }
    public mutating func send(_ action: Action) {
        notice = ""
        switch action {
        case .workers(let n):
            guard [1,2,4].contains(n), stage != 5 || n == 2 else { return }
            workers = n; configure()
        case .assign(let id, let lane):
            guard (0..<workers).contains(lane), let i = tasks.firstIndex(where: { $0.id == id }) else { return }
            rewind(); tasks[i].lane = lane
        case .moveEarlier(let id):
            guard let at = queueOrder.firstIndex(of: id), let task = tasks.first(where: { $0.id == id }),
                  let previous = queueOrder[..<at].lastIndex(where: { prior in tasks.contains { $0.id == prior && $0.lane == task.lane } }) else { return }
            rewind(); queueOrder.swapAt(at, previous)
        case .inspect(let id):
            guard let t = tasks.first(where: { $0.id == id }) else { return }; inspectedTask = id
            if !t.prerequisites.isEmpty { observedDependency = true }
        case .reset: rewind()
        case .step:
            guard !runFinished, tick < 40 else { return }
            let done = Set(tasks.filter(\.isDone).map(\.id))
            var ids: [Int] = []
            for lane in 0..<workers {
                if let next = laneTasks(lane).first(where: { !$0.isDone }), next.prerequisites.allSatisfy(done.contains) { ids.append(next.id) }
            }
            activeTasks = ids
            for id in ids { if let i = tasks.firstIndex(where: { $0.id == id }) { tasks[i].remaining -= 1 } }
            tick += 1
            if runFinished {
                let record = ParallelTrial("w\(workers)", "\(workers)人", tick)
                if let i = trials.firstIndex(where: { $0.key == record.key }) { if tick < trials[i].ticks { trials[i] = record } } else { trials.append(record) }
            }
        }
    }
}
