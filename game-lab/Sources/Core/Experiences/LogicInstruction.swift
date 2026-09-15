import Foundation

public struct LogicInstructionModel: ExperienceModel {
    public static let gameID = "instruction-atelier"
    public enum Instruction: String, CaseIterable, Codable, Equatable, Sendable {
        case read, store0, store1, add0, add1Memory, addOne, output, ifZero4, jump1, stop
        public var title: String {
            switch self {
            case .read: return "読む"
            case .store0: return "置く M0"
            case .store1: return "置く M1"
            case .add0: return "足す M0"
            case .add1Memory: return "足す M1"
            case .addOne: return "1を足す"
            case .output: return "出す"
            case .ifZero4: return "0なら4へ"
            case .jump1: return "1へ戻る"
            case .stop: return "止める"
            }
        }
        public var symbol: String {
            switch self {
            case .read: return "tray.and.arrow.down"
            case .store0, .store1: return "square.and.arrow.down"
            case .add0, .add1Memory, .addOne: return "plus.circle"
            case .output: return "tray.and.arrow.up"
            case .ifZero4: return "arrow.triangle.branch"
            case .jump1: return "arrow.uturn.backward"
            case .stop: return "stop.circle"
            }
        }
    }
    public enum Action { case append(Instruction), remove(Int), move(Int, Int), step, rewind, verify, selectCase(Int) }
    public struct Trace: Codable, Equatable {
        public let step: Int
        public let instruction: String
        public let accumulator: Int?
        public let memory: [Int?]
        public let output: [Int]
    }
    public struct CaseResult: Codable, Equatable {
        public let input: [Int]
        public let expected: [Int]
        public let actual: [Int]
        public let error: String?
        public var passed: Bool { expected == actual && error == nil }
    }
    public var stage: Int
    public private(set) var program: [Instruction] = []
    public private(set) var pc = 0
    public private(set) var accumulator: Int?
    public private(set) var memory: [Int?] = [nil, nil]
    public private(set) var input: [Int]
    public private(set) var inputIndex = 0
    public private(set) var output: [Int] = []
    public private(set) var steps = 0
    public private(set) var halted = false
    public private(set) var fault: String?
    public private(set) var trace: [Trace] = []
    public private(set) var results: [CaseResult] = []
    public private(set) var message = "命令を選んで、下のレールに並べよう。"
    public init(stage: Int) {
        self.stage = min(5, max(1, stage))
        input = Self.inputs(for: self.stage)[0]
    }
    public var stageTitle: String { ["受け取って渡す", "順番のある計算", "先に置いておく", "0だけ見送る", "くり返す手順"][stage - 1] }
    public var goal: String {
        ["2の札を受け取って、出力へ届けよう。", "3に1を足して、4の札を出そう。", "2と3を使って、5の札を作ろう。", "0だけは出さず、ほかの数はそのまま届けよう。", "0・2・4を、1・3・5にして順番に届けよう。"][stage - 1]
    }
    public var guide: String {
        if let fault { return fault }
        if isComplete { return "手順だけで、目標の札が出てきたね。入力と結果の流れを作品に残そう。" }
        if steps > 0 && !halted {
            return "手元は\(accumulator.map(String.init) ?? "空")、M0は\(memory[0].map(String.init) ?? "未設定")。次は\(program.indices.contains(pc) ? program[pc].title : "終了")だね。"
        }
        return message
    }
    public var hints: [String] {
        switch stage {
        case 1: return ["出す前に、手元に札が必要だね。", "入力から手元へ運ぶ命令を探そう。", "『読む』の次に『出す』を並べてみよう。"]
        case 2: return ["計算するのは、どの札かな？", "出す前に、手元の数を変えよう。", "読む → 1を足す → 出す、で一歩ずつ見よう。"]
        case 3: return ["次の数字を読むと、手元はどうなるかな？", "最初の数字を、別の置き場に残せそうだね。", "読む → 置くM0 → 読む → 足すM0 → 出す、を試そう。"]
        case 4: return ["0のときだけ、出す命令を飛ばせるかな？", "条件によって、次の命令を変えてみよう。", "読む → 0なら4へ → 出す → 止める、で3つの入力を試そう。"]
        default: return ["同じことを、次の札にも繰り返したいね。", "新しい札を読む命令まで戻ろう。", "読む → 1を足す → 出す → 1へ戻る。札がなくなったら止まるよ。"]
        }
    }
    public var available: [Instruction] {
        switch stage {
        case 1: return [.read, .output]
        case 2: return [.read, .addOne, .output]
        case 3: return [.read, .store0, .add0, .output]
        case 4: return [.read, .ifZero4, .output, .stop]
        default: return [.read, .addOne, .output, .jump1]
        }
    }
    public var expected: [Int] { Self.expected(for: input, stage: stage) }
    public var isComplete: Bool { !results.isEmpty && results.allSatisfy(\.passed) }
    public var metrics: [ExperienceMetric] { [.init("実行", "\(steps)命令"), .init("残りの入力", "\(input.count - inputIndex)枚"), .init("確認", "\(results.filter(\.passed).count) / \(Self.inputs(for: stage).count)")] }
    public var isValid: Bool {
        (1...5).contains(stage) && program.count <= 8 && memory.count == 2
        && inputIndex >= 0 && inputIndex <= input.count && input.count <= 8 && output.count <= 100
        && pc >= 0 && pc <= 8 && steps >= 0 && steps <= 100 && trace.count <= 100
        && input.allSatisfy { (-9...99).contains($0) }
        && output.allSatisfy { (-9...99).contains($0) }
        && memory.allSatisfy { $0 == nil || (-9...99).contains($0!) }
        && (accumulator == nil || (-9...99).contains(accumulator!))
    }
    public static func inputs(for stage: Int) -> [[Int]] {
        switch stage { case 1: return [[2]]; case 2: return [[3]]; case 3: return [[2, 3]]; case 4: return [[0], [3], [7]]; default: return [[0, 2, 4], [1, 5]] }
    }
    private static func expected(for input: [Int], stage: Int) -> [Int] {
        switch stage { case 1: return input; case 2, 5: return input.map { $0 + 1 }; case 3: return [input.reduce(0, +)]; default: return input.filter { $0 != 0 } }
    }
    private mutating func resetMachine(input newInput: [Int]? = nil) {
        if let newInput { input = newInput }
        pc = 0; accumulator = nil; memory = [nil, nil]; inputIndex = 0; output = []; steps = 0; halted = false; fault = nil; trace = []
    }
    public mutating func send(_ action: Action) {
        switch action {
        case .append(let instruction):
            guard available.contains(instruction), program.count < 8 else { message = "命令は8枚まで置けるよ。選んだ命令を外してから試そう。"; return }
            program.append(instruction); results = []; resetMachine(); message = "\(instruction.title)を置いたよ。1命令ずつ確かめよう。"
        case .remove(let index):
            guard program.indices.contains(index) else { return }; program.remove(at: index); results = []; resetMachine()
        case .move(let from, let to):
            guard program.indices.contains(from), program.indices.contains(to), from != to else { return }
            let item = program.remove(at: from); program.insert(item, at: to); results = []; resetMachine()
        case .rewind: resetMachine(); message = "同じ入力から、もう一度試そう。"
        case .selectCase(let index):
            let cases = Self.inputs(for: stage); guard cases.indices.contains(index) else { return }; resetMachine(input: cases[index])
        case .step:
            executeStep()
            if halted && fault == nil && Self.inputs(for: stage).count == 1 { results = [CaseResult(input: input, expected: expected, actual: output, error: inputIndex == input.count ? nil : "入力が残っているよ。")] }
        case .verify:
            guard !program.isEmpty else { message = "まず命令を並べよう。"; return }
            results = Self.inputs(for: stage).map { values in
                var trial = self; trial.resetMachine(input: values)
                for _ in 0..<101 { if trial.halted || trial.fault != nil { break }; trial.executeStep() }
                let error = trial.fault ?? (trial.inputIndex < values.count ? "入力が残っているよ。" : nil)
                return CaseResult(input: values, expected: trial.expected, actual: trial.output, error: error)
            }
            message = isComplete ? "どの入力でも、目標どおりになったね。" : "違いが出た入力を選んで、一歩ずつ見てみよう。"
        }
    }
    private mutating func executeStep() {
        guard !halted, fault == nil else { return }
        guard !program.isEmpty else { message = "まず命令を選んで、レールに並べよう。"; return }
        guard program.indices.contains(pc) else { halted = true; return }
        guard steps < 100 else { fault = "100命令続いているね。手順を直すか、最初へ戻って確かめよう。"; return }
        let instruction = program[pc]
        if [.store0, .store1, .add0, .add1Memory, .addOne, .output, .ifZero4].contains(instruction), accumulator == nil { fault = "いま手元が空だね。『読む』で値を持ってから使おう。"; return }
        if (instruction == .add0 && memory[0] == nil) || (instruction == .add1Memory && memory[1] == nil) { fault = "置き場が未設定だね。最初の値を置いてから足してみよう。"; return }
        var next = pc + 1
        switch instruction {
        case .read:
            if inputIndex == input.count { halted = true } else { accumulator = input[inputIndex]; inputIndex += 1 }
        case .store0: memory[0] = accumulator
        case .store1: memory[1] = accumulator
        case .add0, .add1Memory, .addOne:
            let value = instruction == .addOne ? 1 : memory[instruction == .add0 ? 0 : 1]!
            let sum = accumulator! + value
            guard (-9...99).contains(sum) else { fault = "この装置で扱える数は−9〜99だよ。値を確かめよう。"; return }
            accumulator = sum
        case .output: output.append(accumulator!); accumulator = nil
        case .ifZero4: if accumulator == 0 { next = 3 }
        case .jump1: next = 0
        case .stop: halted = true
        }
        steps += 1; pc = next
        trace.append(Trace(step: steps, instruction: instruction.title, accumulator: accumulator, memory: memory, output: output))
        if pc >= program.count { halted = true }
    }
}
