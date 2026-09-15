import Foundation

/// The first exhibition: construct and investigate a two-person ready lamp.
/// UI animation and the companion's speech never change this model by themselves.
public enum WorkshopPhase: String, Codable, Sendable {
    case welcome, building, observing, verified, finished
}

public enum WorkshopFeedback: String, Codable, Sendable {
    case welcome, began, gateChanged, connectionChanged, inputChanged, companionChangedInput
    case observationAdded, checkProgress, verificationFailed, verificationPassed
    case hint, counterexampleSelected, predictionAnswered, finished, reset
}

public struct WorkshopArtifact: Codable, Equatable, Sendable {
    public let circuit: CircuitSnapshot
    public let observations: [TruthTableCheck]
    /// Position in the deterministic journal, not a clock time or learning score.
    public let completedActionIndex: Int
}

public struct WorkshopSnapshot: Codable, Equatable, Sendable {
    public let circuit: CircuitSnapshot
    public let phase: WorkshopPhase
    public let hasStarted: Bool
    public let hintLevel: Int
    public let observations: [TruthTableCheck]
    public let selectedCounterexample: InputPair?
    public let feedback: WorkshopFeedback
    public let completedArtifact: WorkshopArtifact?
    public let canUndo: Bool

    public var observedInputs: [InputPair] { observations.map(\.inputs) }
    public var canObserve: Bool { hasStarted && circuit.isConnected }
    public var canFinish: Bool { circuit.verification == .passed && phase != .finished }

    /// A factual fallback script. The view can animate or voice it without driving progress.
    public var feedbackText: String {
        switch feedback {
        case .welcome:
            return "ふたりの準備ができたときだけ、このランプがつくようにしたいんだ。一緒に作ってみよう？"
        case .began:
            return "まずは部品をひとつ置こう。それから、ふたつのスイッチとランプをつないでみてね。"
        case .gateChanged:
            return "部品が変わったね。つないだら、スイッチを変えて動きを比べてみよう。"
        case .connectionChanged:
            return circuit.isConnected
                ? "道がつながったね。私のスイッチも動かせるよ。条件を変えて、光り方を観察しよう。"
                : "まだつながっていない道があるね。ランプの「？」は、出力が決まっていない合図だよ。"
        case .inputChanged:
            return "今はAが\(circuit.inputs.a ? 1 : 0)、Bが\(circuit.inputs.b ? 1 : 0)だね。ランプがどう変わるか見てみよう。"
        case .companionChangedInput:
            return "私のスイッチを\(circuit.inputs.b ? "入れた" : "切った")よ。そっちのスイッチと合わせると、どうなるかな？"
        case .observationAdded:
            return "\(Self.conditionText(circuit.inputs))は、\(Self.outputText(circuit.output))ね。観察ノートに残したよ。"
        case .checkProgress:
            return "\(circuit.checks.count)通り目を確かめたよ。ひとつずつ、光り方を比べよう。"
        case .verificationFailed:
            guard let check = circuit.checks.first(where: { !$0.passed }) else { return "目標と違う条件を、もう一度試してみよう。" }
            return "\(Self.conditionText(check.inputs))は、\(Self.outputText(check.actual))ね。目標では\(check.expected ? "光る" : "消える")はず。部品を変えて比べてみよう。"
        case .verificationPassed:
            return "できたね！4通りすべて、目標どおり。ふたつの条件が両方そろったときに合図を出す。これがANDの働きだよ。"
        case .hint:
            if hintLevel == 1 {
                return circuit.isConnected
                    ? "ふたりとも準備できたときと、ひとりだけのときを比べてみよう。"
                    : "スイッチA、スイッチB、ランプ。それぞれの端子が部品につながっているかな？"
            }
            if hintLevel == 2 { return "Aだけが1のとき、Bだけが1のとき、両方が1のとき。この3通りの違いを見てみよう。" }
            return "「&」の部品を試してみよう。ひとりだけでは光らず、ふたりがそろうと光るか確かめてみてね。"
        case .counterexampleSelected:
            return "目標と違った条件に戻したよ。この状態で部品を入れ替えると、違いが見つかるかも。"
        case .predictionAnswered:
            return circuit.prediction.isCorrect == true
                ? "予想どおり！\(circuit.predictionExplanation ?? "")"
                : "この条件ではどうなるか、一緒に見てみよう。\(circuit.predictionExplanation ?? "")"
        case .finished:
            return "ふたりの準備完了ランプができたね。作品帳に残したよ。いつでも、また試せるよ。"
        case .reset:
            return "作業台を片づけたよ。もう一度、好きな順番で試してみよう。"
        }
    }

    private static func conditionText(_ inputs: InputPair) -> String {
        switch (inputs.a, inputs.b) {
        case (false, false): return "ふたりとも準備していないとき"
        case (false, true): return "Bだけ準備できたとき"
        case (true, false): return "Aだけ準備できたとき"
        case (true, true): return "ふたりとも準備できたとき"
        }
    }
    private static func outputText(_ output: LogicSignal) -> String {
        switch output {
        case .low: return "ランプは消えた"
        case .high: return "ランプが光った"
        case .unknown: return "まだ出力が決まっていない"
        }
    }
}

public enum WorkshopAction: Codable, Equatable, Sendable {
    case begin
    case circuit(CircuitAction)
    /// The only autonomous-looking input action: it occurs on the player's explicit request.
    case askCompanion
    case observe
    case hint
    case selectCounterexample(InputPair)
    case undo
    case finish
    /// Start a clean attempt, preserving the last completed work and the initial seed.
    /// This boundary compacts the journal and cannot be crossed with undo.
    case reset
}

/// Persistence stores only an input journal. Loading reconstructs and validates all game state.
public struct WorkshopReplay: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let currentModelVersion = "workshop-2"
    public let schemaVersion: Int
    public let modelVersion: String
    public let circuitModelVersion: String
    public let initialSeed: UInt64
    public let actions: [WorkshopAction]

    public init(initialSeed: UInt64, actions: [WorkshopAction]) {
        self.schemaVersion = Self.currentSchemaVersion
        self.modelVersion = Self.currentModelVersion
        self.circuitModelVersion = CircuitReplay.modelVersion
        self.initialSeed = initialSeed
        self.actions = actions
    }
}

public enum WorkshopError: Error, Equatable, LocalizedError {
    case notStarted
    case alreadyStarted
    case unsupportedCircuitAction
    case connectionRequired
    case verificationRequired
    case invalidCounterexample
    case nothingToUndo
    case unsupportedSchema(Int)
    case unsupportedModel(String)
    case unsupportedCircuitModel(String)
    case tooManyActions(Int)
    case documentTooLarge(Int)

    public var errorDescription: String? {
        switch self {
        case .notStarted: return "「一緒に作る」から始めてください。"
        case .alreadyStarted: return "すでに作業を始めています。"
        case .unsupportedCircuitAction: return "この展示では、ふたりの準備完了ランプを作ります。"
        case .connectionRequired: return "部品と3本の線をつないでから確かめてください。"
        case .verificationRequired: return "4通りの動きを確かめてから作品を残してください。"
        case .invalidCounterexample: return "この条件は、今の回路で見つかった食い違いではありません。"
        case .nothingToUndo: return "戻せる操作がありません。"
        case .unsupportedSchema: return "この保存データの形式には対応していません。"
        case .unsupportedModel, .unsupportedCircuitModel: return "この保存データは、別のバージョンの展示で作られています。"
        case .tooManyActions: return "この作業記録は保存できる操作数を超えています。"
        case .documentTooLarge: return "この保存データは大きすぎるため読み込めません。"
        }
    }
}

public struct WorkshopSession: Sendable {
    public static let maximumReplayActions = 8_192
    public static let maximumReplayBytes = 1_048_576
    public static let maximumUndoDepth = 64
    public let initialSeed: UInt64
    public private(set) var actions: [WorkshopAction] = []

    private struct Frame: Sendable {
        var circuit: CircuitSession
        var hasStarted = false
        var hintLevel = 0
        var observations: [TruthTableCheck] = []
        var selectedCounterexample: InputPair?
        var feedback = WorkshopFeedback.welcome
        var completedArtifact: WorkshopArtifact?
        var finished = false
    }
    private var frame: Frame
    private var history: [Frame] = []

    public init(seed: UInt64 = 17) {
        self.initialSeed = seed
        self.frame = Frame(circuit: CircuitSession(seed: seed))
    }

    public var state: WorkshopSnapshot {
        let phase: WorkshopPhase
        if !frame.hasStarted { phase = .welcome }
        else if frame.finished { phase = .finished }
        else if frame.circuit.state.verification == .passed { phase = .verified }
        else if frame.circuit.state.isConnected { phase = .observing }
        else { phase = .building }
        return WorkshopSnapshot(circuit: frame.circuit.state, phase: phase,
            hasStarted: frame.hasStarted, hintLevel: frame.hintLevel,
            observations: frame.observations, selectedCounterexample: frame.selectedCounterexample,
            feedback: frame.feedback, completedArtifact: frame.completedArtifact, canUndo: !history.isEmpty)
    }
    public var snapshot: WorkshopSnapshot { state }
    public func replayDocument() -> WorkshopReplay { WorkshopReplay(initialSeed: initialSeed, actions: actions) }

    public static func replay(_ document: WorkshopReplay) throws -> WorkshopSession {
        guard document.schemaVersion == WorkshopReplay.currentSchemaVersion else {
            throw WorkshopError.unsupportedSchema(document.schemaVersion)
        }
        guard document.modelVersion == WorkshopReplay.currentModelVersion else {
            throw WorkshopError.unsupportedModel(document.modelVersion)
        }
        guard document.circuitModelVersion == CircuitReplay.modelVersion else {
            throw WorkshopError.unsupportedCircuitModel(document.circuitModelVersion)
        }
        guard document.actions.count <= maximumReplayActions else {
            throw WorkshopError.tooManyActions(document.actions.count)
        }
        var session = WorkshopSession(seed: document.initialSeed)
        for action in document.actions { try session.apply(action) }
        return session
    }

    public static func replay(data: Data) throws -> WorkshopSession {
        guard data.count <= maximumReplayBytes else { throw WorkshopError.documentTooLarge(data.count) }
        return try replay(JSONDecoder().decode(WorkshopReplay.self, from: data))
    }

    public mutating func apply(_ action: WorkshopAction) throws {
        // Reset must remain available even when a long-lived attempt fills its journal.
        // A compact checkpoint is still an ordinary, validated action sequence: persisted
        // snapshots never become authoritative inputs to the model.
        if action == .reset {
            try resetWithCompactCheckpoint()
            return
        }
        try commit(action)
    }

    private mutating func commit(_ action: WorkshopAction) throws {
        guard actions.count < Self.maximumReplayActions else {
            throw WorkshopError.tooManyActions(actions.count + 1)
        }
        if action == .undo {
            guard let previous = history.popLast() else { throw WorkshopError.nothingToUndo }
            frame = previous
            actions.append(action)
            return
        }
        // Mutations are transactional: a rejected action cannot damage the live or saved attempt.
        var next = frame
        try execute(action, in: &next)
        if action == .finish || action == .reset {
            // Saving work is a checkpoint, not an edit. Later edits can be undone,
            // but undo can never remove the completed artifact from the work collection.
            history.removeAll()
        } else {
            history.append(frame)
            if history.count > Self.maximumUndoDepth { history.removeFirst() }
        }
        frame = next
        actions.append(action)
    }

    private mutating func resetWithCompactCheckpoint() throws {
        var compact = WorkshopSession(seed: initialSeed)
        if let work = frame.completedArtifact {
            try compact.apply(.begin)
            guard let gate = work.circuit.selectedGate else { throw WorkshopError.verificationRequired }
            try compact.apply(.circuit(.selectGate(gate)))
            for link in CircuitLink.allCases where work.circuit.links.contains(link) {
                try compact.apply(.circuit(.toggleLink(link)))
            }
            try compact.apply(.circuit(.verify))
            // Preserve the saved work's next test condition as well as its visible circuit.
            for _ in 0..<work.circuit.nextCheckIndex { try compact.apply(.circuit(.step)) }
            if let answer = work.circuit.prediction.answer {
                try compact.apply(.circuit(.predict(answer)))
            }
            if compact.state.circuit.inputs != work.circuit.inputs {
                try compact.apply(.circuit(.setInputs(work.circuit.inputs)))
            }
            try compact.apply(.finish)
        } else if frame.hasStarted {
            try compact.apply(.begin)
        }
        // The artifact's bookkeeping tick and completedActionIndex now refer to the
        // compact journal. Its board, observations, prediction, and verification remain.
        try compact.commit(.reset)
        self = compact
    }

    private func execute(_ action: WorkshopAction, in next: inout Frame) throws {
        switch action {
        case .begin:
            guard !next.hasStarted else { throw WorkshopError.alreadyStarted }
            next.hasStarted = true
            next.feedback = .began
        case .reset:
            let savedWork = next.completedArtifact
            let wasStarted = next.hasStarted
            next = Frame(circuit: CircuitSession(seed: initialSeed))
            next.hasStarted = wasStarted
            next.completedArtifact = savedWork
            next.feedback = wasStarted ? .reset : .welcome
        case .undo:
            // Handled before constructing a transaction.
            throw WorkshopError.nothingToUndo
        default:
            guard next.hasStarted else { throw WorkshopError.notStarted }
            try executeStarted(action, in: &next)
        }
    }

    private func executeStarted(_ action: WorkshopAction, in next: inout Frame) throws {
        switch action {
        case .circuit(let circuitAction):
            try executeCircuit(circuitAction, in: &next)
        case .askCompanion:
            try next.circuit.apply(.toggleInput(.b))
            next.finished = false
            next.feedback = .companionChangedInput
        case .observe:
            guard next.circuit.state.isConnected else { throw WorkshopError.connectionRequired }
            Self.recordCurrentObservation(in: &next)
            next.feedback = .observationAdded
        case .hint:
            next.hintLevel = min(3, next.hintLevel + 1)
            next.feedback = .hint
        case .selectCounterexample(let inputs):
            guard next.circuit.state.checks.contains(where: { $0.inputs == inputs && !$0.passed }) else {
                throw WorkshopError.invalidCounterexample
            }
            try next.circuit.apply(.setInputs(inputs))
            next.selectedCounterexample = inputs
            next.feedback = .counterexampleSelected
        case .finish:
            guard next.circuit.state.verification == .passed else { throw WorkshopError.verificationRequired }
            next.completedArtifact = WorkshopArtifact(circuit: next.circuit.state,
                observations: next.observations, completedActionIndex: actions.count + 1)
            next.finished = true
            next.feedback = .finished
        case .begin, .undo, .reset:
            throw WorkshopError.unsupportedCircuitAction
        }
    }

    private func executeCircuit(_ action: CircuitAction, in next: inout Frame) throws {
        switch action {
        case .selectMission, .nextMission, .reset:
            throw WorkshopError.unsupportedCircuitAction
        case .step, .verify:
            guard next.circuit.state.isConnected else { throw WorkshopError.connectionRequired }
        default: break
        }
        let previous = next.circuit.state
        try next.circuit.apply(action)
        next.finished = false
        let current = next.circuit.state
        if previous.selectedGate != current.selectedGate || previous.links != current.links {
            next.observations = []
            next.selectedCounterexample = nil
            next.hintLevel = 0
        }
        switch action {
        case .selectGate:
            next.feedback = .gateChanged
        case .toggleLink:
            next.feedback = .connectionChanged
        case .toggleInput, .setInputs:
            next.selectedCounterexample = nil
            next.feedback = .inputChanged
        case .step, .verify:
            if action == .step { Self.recordCurrentObservation(in: &next) }
            else { next.observations = current.checks }
            if current.verification == .passed { next.feedback = .verificationPassed }
            else if current.verification == .failed { next.feedback = .verificationFailed }
            else { next.feedback = .checkProgress }
        case .predict:
            next.feedback = .predictionAnswered
        case .selectMission, .nextMission, .reset:
            break
        }
    }

    private static func recordCurrentObservation(in next: inout Frame) {
        let state = next.circuit.state
        let row = TruthTableCheck(inputs: state.inputs, expected: state.mission.evaluate(state.inputs), actual: state.output)
        next.observations.removeAll { $0.inputs == row.inputs }
        next.observations.append(row)
        next.observations.sort { rowIndex($0.inputs) < rowIndex($1.inputs) }
    }
    private static func rowIndex(_ inputs: InputPair) -> Int { (inputs.a ? 2 : 0) + (inputs.b ? 1 : 0) }
}
