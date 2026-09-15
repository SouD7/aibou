import Foundation

public enum GateKind: String, Codable, CaseIterable, Sendable {
    case and, or, xor

    public var title: String { rawValue.uppercased() }
    public var symbol: String {
        switch self { case .and: return "&"; case .or: return "≥1"; case .xor: return "=1" }
    }
    public var missionTitle: String {
        switch self {
        case .and: return "ふたりで点灯"
        case .or: return "どちらかで点灯"
        case .xor: return "ひとりだけで点灯"
        }
    }
    public var objective: String {
        switch self {
        case .and: return "AとBが両方1のときだけ、ランプを点けよう。"
        case .or: return "AとBの少なくとも一方が1なら、ランプを点けよう。"
        case .xor: return "AとBのどちらか一方だけが1のとき、ランプを点けよう。"
        }
    }
    public var explanation: String {
        switch self {
        case .and: return "ANDは、両方の入力が1のときだけ1を出力する。"
        case .or: return "ORは、少なくとも一方の入力が1なら1を出力する。"
        case .xor: return "XORは、ふたつの入力が異なるときだけ1を出力する。"
        }
    }
    public func evaluate(_ inputs: InputPair) -> Bool {
        switch self {
        case .and: return inputs.a && inputs.b
        case .or: return inputs.a || inputs.b
        case .xor: return inputs.a != inputs.b
        }
    }
}

public struct InputPair: Codable, Equatable, Hashable, Sendable {
    public var a: Bool
    public var b: Bool
    public init(a: Bool, b: Bool) { self.a = a; self.b = b }
    public static let truthTable = [
        InputPair(a: false, b: false), InputPair(a: false, b: true),
        InputPair(a: true, b: false), InputPair(a: true, b: true)
    ]
}

public enum CircuitInput: String, Codable, Sendable { case a, b }
public enum CircuitLink: String, Codable, CaseIterable, Sendable {
    case inputA, inputB, output
}
public enum LogicSignal: String, Codable, Sendable {
    case low, high, unknown
    public var bit: Bool? {
        switch self { case .low: return false; case .high: return true; case .unknown: return nil }
    }
    public var label: String {
        switch self { case .low: return "0"; case .high: return "1"; case .unknown: return "?" }
    }
    public init(_ value: Bool) { self = value ? .high : .low }
}
public enum VerificationStatus: String, Codable, Sendable { case untested, failed, passed }
public enum CircuitStage: String, Codable, Sendable { case building, readyToPredict, complete }

public struct TruthTableCheck: Codable, Equatable, Sendable {
    public let inputs: InputPair
    public let expected: Bool
    public let actual: LogicSignal
    public var passed: Bool { actual.bit == expected }
}

public struct PredictionState: Codable, Equatable, Sendable {
    public let inputs: InputPair
    public fileprivate(set) var answer: Bool?
    public fileprivate(set) var isCorrect: Bool?
}

public struct CircuitSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let modelVersion: String
    public fileprivate(set) var seed: UInt64
    public fileprivate(set) var tick: Int
    public fileprivate(set) var mission: GateKind
    public fileprivate(set) var selectedGate: GateKind?
    public fileprivate(set) var links: Set<CircuitLink>
    public fileprivate(set) var inputs: InputPair
    public fileprivate(set) var output: LogicSignal
    public fileprivate(set) var checks: [TruthTableCheck]
    public fileprivate(set) var nextCheckIndex: Int
    public fileprivate(set) var verification: VerificationStatus
    public fileprivate(set) var prediction: PredictionState
    public fileprivate(set) var completedMissions: [GateKind]

    public var isConnected: Bool { selectedGate != nil && links.count == CircuitLink.allCases.count }
    public var stage: CircuitStage {
        if verification != .passed { return .building }
        return prediction.answer != nil ? .complete : .readyToPredict
    }
    public var predictionExplanation: String? {
        guard prediction.answer != nil else { return nil }
        let answer = mission.evaluate(prediction.inputs) ? "1" : "0"
        return "A=\(prediction.inputs.a ? 1 : 0)、B=\(prediction.inputs.b ? 1 : 0)なら出力は\(answer)。\(mission.explanation)"
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, modelVersion, seed, tick, mission, selectedGate, links, inputs, output,
             checks, nextCheckIndex, verification, prediction, completedMissions
    }
    // A sorted link list makes exported snapshots byte-stable, as well as semantically deterministic.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(modelVersion, forKey: .modelVersion)
        try c.encode(seed, forKey: .seed)
        try c.encode(tick, forKey: .tick)
        try c.encode(mission, forKey: .mission)
        try c.encodeIfPresent(selectedGate, forKey: .selectedGate)
        try c.encode(CircuitLink.allCases.filter(links.contains), forKey: .links)
        try c.encode(inputs, forKey: .inputs)
        try c.encode(output, forKey: .output)
        try c.encode(checks, forKey: .checks)
        try c.encode(nextCheckIndex, forKey: .nextCheckIndex)
        try c.encode(verification, forKey: .verification)
        try c.encode(prediction, forKey: .prediction)
        try c.encode(completedMissions, forKey: .completedMissions)
    }
}

public enum CircuitAction: Codable, Equatable, Sendable {
    case selectGate(GateKind)
    case toggleLink(CircuitLink)
    case toggleInput(CircuitInput)
    case setInputs(InputPair)
    case step
    case verify
    case predict(Bool)
    case selectMission(GateKind)
    case nextMission
    case reset(seed: UInt64)
}

public struct CircuitReplay: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let modelVersion = "circuit-2"
    public let schemaVersion: Int
    public let modelVersion: String
    public let initialSeed: UInt64
    public let actions: [CircuitAction]

    public init(initialSeed: UInt64, actions: [CircuitAction]) {
        self.schemaVersion = Self.schemaVersion
        self.modelVersion = Self.modelVersion
        self.initialSeed = initialSeed
        self.actions = actions
    }
}

public enum CircuitError: Error, Equatable, LocalizedError {
    case unsupportedSchema(Int)
    case unsupportedModel(String)
    case tooManyActions(Int)
    case predictionRequiresVerification
    case nextMissionRequiresVerification
    case noNextMission

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version): return "Unsupported replay schema: \(version)"
        case .unsupportedModel(let version): return "Unsupported circuit model: \(version)"
        case .tooManyActions(let count): return "Replay has too many actions: \(count)"
        case .predictionRequiresVerification: return "4条件の検証に成功してから予想に進んでください。"
        case .nextMissionRequiresVerification: return "4条件の検証に成功してから次に進んでください。"
        case .noNextMission: return "すべてのミッションが完了しました。"
        }
    }
}

public struct CircuitSession: Sendable {
    public static let maximumReplayActions = 10_000
    public private(set) var state: CircuitSnapshot
    public private(set) var actions: [CircuitAction] = []
    public let initialSeed: UInt64

    public init(seed: UInt64 = 1) {
        self.initialSeed = seed
        self.state = Self.initialState(seed: seed, mission: .and, completed: [])
    }

    public var snapshot: CircuitSnapshot { state }
    public func replayDocument() -> CircuitReplay { CircuitReplay(initialSeed: initialSeed, actions: actions) }

    public static func replay(_ document: CircuitReplay) throws -> CircuitSession {
        guard document.schemaVersion == CircuitReplay.schemaVersion else {
            throw CircuitError.unsupportedSchema(document.schemaVersion)
        }
        guard document.modelVersion == CircuitReplay.modelVersion else {
            throw CircuitError.unsupportedModel(document.modelVersion)
        }
        guard document.actions.count <= maximumReplayActions else {
            throw CircuitError.tooManyActions(document.actions.count)
        }
        var session = CircuitSession(seed: document.initialSeed)
        for action in document.actions { try session.apply(action) }
        return session
    }

    public static func replay(data: Data) throws -> CircuitSession {
        try replay(JSONDecoder().decode(CircuitReplay.self, from: data))
    }

    public mutating func apply(_ action: CircuitAction) throws {
        guard actions.count < Self.maximumReplayActions else {
            throw CircuitError.tooManyActions(actions.count + 1)
        }
        let previousTick = state.tick
        switch action {
        case .selectGate(let gate):
            if state.selectedGate != gate { state.selectedGate = gate; invalidateVerification() }
        case .toggleLink(let link):
            if state.links.contains(link) { state.links.remove(link) } else { state.links.insert(link) }
            invalidateVerification()
        case .toggleInput(let input):
            if input == .a { state.inputs.a.toggle() } else { state.inputs.b.toggle() }
        case .setInputs(let inputs): state.inputs = inputs
        case .step:
            let inputs = InputPair.truthTable[state.nextCheckIndex]
            state.inputs = inputs
            let check = makeCheck(inputs)
            state.checks.removeAll { $0.inputs == inputs }
            state.checks.append(check)
            state.checks.sort { Self.rowIndex($0.inputs) < Self.rowIndex($1.inputs) }
            state.nextCheckIndex = (state.nextCheckIndex + 1) % 4
            updateVerification()
        case .verify:
            state.checks = InputPair.truthTable.map { makeCheck($0) }
            state.nextCheckIndex = 0
            updateVerification()
        case .predict(let answer):
            guard state.verification == .passed else { throw CircuitError.predictionRequiresVerification }
            state.prediction.answer = answer
            state.prediction.isCorrect = answer == state.mission.evaluate(state.prediction.inputs)
        case .selectMission(let mission):
            state = Self.initialState(seed: state.seed, mission: mission,
                                      completed: state.completedMissions.filter { $0 != mission })
        case .nextMission:
            guard state.verification == .passed else { throw CircuitError.nextMissionRequiresVerification }
            let index = Self.missionIndex(state.mission)
            guard index + 1 < GateKind.allCases.count else { throw CircuitError.noNextMission }
            state = Self.initialState(seed: state.seed, mission: GateKind.allCases[index + 1],
                                      completed: state.completedMissions)
        case .reset(let seed):
            state = Self.initialState(seed: seed, mission: .and, completed: [])
        }
        if case .reset = action { state.tick = 0 } else { state.tick = previousTick + 1 }
        state.output = observedOutput(state.inputs)
        actions.append(action)
    }

    private static func initialState(seed: UInt64, mission: GateKind, completed: [GateKind]) -> CircuitSnapshot {
        // Explicit wrapping arithmetic handles every UInt64 seed without a crash.
        let mixed = seed &* 6_364_136_223_846_793_005 &+ 1
        let seedRow = Int((mixed >> 32) & 3)
        // OR and XOR share a condition so their different rules can be compared.
        // At the app's seed 17 this gives AND:10, OR:11, XOR:11.
        let missionOffset = mission == .and ? 0 : 1
        let question = InputPair.truthTable[(seedRow + missionOffset) % 4]
        return CircuitSnapshot(schemaVersion: CircuitReplay.schemaVersion,
            modelVersion: CircuitReplay.modelVersion, seed: seed, tick: 0, mission: mission,
            selectedGate: nil, links: [], inputs: InputPair(a: false, b: false), output: .unknown,
            checks: [], nextCheckIndex: 0, verification: .untested,
            prediction: PredictionState(inputs: question, answer: nil, isCorrect: nil),
            completedMissions: completed)
    }

    private static func rowIndex(_ inputs: InputPair) -> Int { (inputs.a ? 2 : 0) + (inputs.b ? 1 : 0) }
    private static func missionIndex(_ mission: GateKind) -> Int { GateKind.allCases.firstIndex(of: mission)! }
    private func observedOutput(_ inputs: InputPair) -> LogicSignal {
        guard state.links.count == CircuitLink.allCases.count, let gate = state.selectedGate else { return .unknown }
        return LogicSignal(gate.evaluate(inputs))
    }
    private func makeCheck(_ inputs: InputPair) -> TruthTableCheck {
        TruthTableCheck(inputs: inputs, expected: state.mission.evaluate(inputs), actual: observedOutput(inputs))
    }
    private mutating func invalidateVerification() {
        state.checks = []
        state.nextCheckIndex = 0
        state.verification = .untested
        state.prediction.answer = nil
        state.prediction.isCorrect = nil
        state.completedMissions.removeAll { $0 == state.mission }
    }
    private mutating func updateVerification() {
        if state.checks.contains(where: { !$0.passed }) { state.verification = .failed }
        else if state.checks.count == 4 { state.verification = .passed }
        else { state.verification = .untested }
        if state.verification == .passed && !state.completedMissions.contains(state.mission) {
            state.completedMissions.append(state.mission)
            state.completedMissions.sort { Self.missionIndex($0) < Self.missionIndex($1) }
        }
    }
}
