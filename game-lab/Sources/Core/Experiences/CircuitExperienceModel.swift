import Foundation

/// Five checkpoints of the existing two-person AND workshop. The legacy workshop
/// journal is embedded, replayed on decode, and never read from or written to its old save.
public struct CircuitExperienceModel: ExperienceModel {
    public static let gameID = "circuit-atelier"
    public enum Port: String, Codable, CaseIterable {
        case aOut, bOut, gateA, gateB, gateOut, lampIn
        public var link: CircuitLink {
            switch self { case .aOut, .gateA: return .inputA; case .bOut, .gateB: return .inputB; case .gateOut, .lampIn: return .output }
        }
        public var source: Bool { self == .aOut || self == .bOut || self == .gateOut }
        public var title: String {
            switch self { case .aOut: return "A 出力"; case .bOut: return "B 出力"; case .gateA: return "部品 入力1"; case .gateB: return "部品 入力2"; case .gateOut: return "部品 出力"; case .lampIn: return "ランプ 入力" }
        }
    }
    public enum Action {
        case begin, selectGate(GateKind), toggleInput(CircuitInput), setInputs(InputPair)
        case connect(Port, Port), toggleLink(CircuitLink), askCompanion, observe, step, replayRow(InputPair)
        case predict(Bool), skipPrediction
    }
    public private(set) var stage: Int
    private var session: WorkshopSession
    public private(set) var skippedPrediction = false
    public private(set) var message = ""
    public var workshop: WorkshopSnapshot { session.state }
    public var circuit: CircuitSnapshot { workshop.circuit }
    public var observations: [TruthTableCheck] { workshop.observations }
    public var revision: String { "\(circuit.selectedGate?.rawValue ?? "none"):\(CircuitLink.allCases.filter(circuit.links.contains).map(\.rawValue).joined(separator: ","))" }
    public var started: Bool { workshop.hasStarted }
    public var canObserve: Bool { workshop.canObserve }
    public var named: Bool { stage == 5 || circuit.verification == .passed }
    public var isComplete: Bool {
        switch stage {
        case 1: return started
        case 2: return circuit.isConnected
        case 3: return observations.count == 4 && circuit.isConnected
        case 4: return circuit.verification == .passed
        case 5: return circuit.verification == .passed && (circuit.prediction.answer != nil || skippedPrediction)
        default: return false
        }
    }
    public var stageTitle: String { ["一緒に作る", "合図をつなぐ", "片方と両方", "直して確かめる", "名前と作品"][stage - 1] }
    public var goal: String {
        ["ふたりの準備ができたときだけ光るランプを、一緒に作ろう。",
         "部品を置き、A・B・ランプへ3本の線をつなごう。",
         "スイッチの4通りを試して、今の回路の結果を比べよう。",
         "片方だけでは消え、ふたりとも準備できたときだけ光るように直そう。",
         "完成したANDを別の場面で試し、ふたりの準備ランプを作品にしよう。"][stage - 1]
    }
    public var guide: String {
        if !message.isEmpty { return message }
        if !started { return "0は消灯、1は点灯。今の「？」はまだ道がつながっていない合図だよ。始めてみよう。" }
        if stage == 5 && circuit.prediction.answer == nil && !skippedPrediction {
            return "これがANDだよ。Aを準備完了、Bを開始許可と呼び替えたら、同じ条件で光るかな？ 予想は見送っても大丈夫。"
        }
        if isComplete {
            switch stage {
            case 1: return "一緒に作ろう！ まだ「？」だから、暗くても出力0とは決まっていないんだ。"
            case 2: return "3本つながったね。今は道が完成したところ。次は4通りの光り方を観察しよう。"
            case 3: return "4通り見られたね。光る条件と依頼の条件は同じかな？ 食い違う行があれば、押して再現できるよ。"
            case 4: return "できた！ ふたりとも準備できたときだけ光ったね。これがANDの働きだよ。"
            default: return circuit.prediction.answer == nil ? "予想は見送っても、作った回路は完成だよ。「作品を残す」で保存できるよ。" : workshop.feedbackText
            }
        }
        return workshop.feedbackText
    }
    public var hints: [String] { ["光ってほしいのは、ふたりとも準備できたときだけだね。未接続の「？」と、消灯の0を分けて見よう。", "部品と3本の線がそろったら、Aだけ・Bだけ・両方・どちらも0を比べてみよう。", "Aが0、Bが1なら消えてほしいね。パーツ01の「&」をつなぎ、4通り全部を確かめよう。"] }
    public var metrics: [ExperienceMetric] { [
        ExperienceMetric("入力 A / B", "\(circuit.inputs.a ? 1 : 0) / \(circuit.inputs.b ? 1 : 0)"),
        ExperienceMetric("出力", circuit.output.label, detail: circuit.output == .unknown ? "未接続は0ではなく未確定" : circuit.output == .high ? "ランプ点灯" : "ランプ消灯"),
        ExperienceMetric("つながった道", "\(circuit.links.count) / 3"),
        ExperienceMetric("同じ回路の観察", "\(observations.count) / 4", detail: "部品・配線を変えると観察を取り直す"),
        ExperienceMetric("目標との一致", "\(observations.filter(\.passed).count) / 4", detail: "目標: 両方が1のときだけ1")
    ] }
    public init(stage: Int) {
        self.stage = min(5, max(1, stage)); session = WorkshopSession(seed: 17)
        if self.stage >= 2 { try? session.apply(.begin) }
        if self.stage >= 3 {
            try? session.apply(.circuit(.selectGate(self.stage == 4 ? .or : .and)))
            for link in CircuitLink.allCases { try? session.apply(.circuit(.toggleLink(link))) }
        }
        if self.stage == 4 || self.stage == 5 { try? session.apply(.circuit(.verify)) }
        if self.stage == 4 { try? session.apply(.selectCounterexample(InputPair(a: false, b: true))) }
        if self.stage == 5 { try? session.apply(.circuit(.setInputs(InputPair(a: true, b: false)))) }
    }
    public mutating func send(_ action: Action) {
        message = ""
        do {
            switch action {
            case .begin:
                if !started { try session.apply(.begin) }
            case .selectGate(let gate): try session.apply(.circuit(.selectGate(gate)))
            case .toggleInput(let input): try session.apply(.circuit(.toggleInput(input)))
            case .setInputs(let inputs): try session.apply(.circuit(.setInputs(inputs)))
            case .toggleLink(let link): try session.apply(.circuit(.toggleLink(link)))
            case .connect(let from, let to):
                guard from.source != to.source && from.link == to.link else { message = "出力の端子と、対応する入力の端子をつないでね。Aは入力1、Bは入力2につながるよ。"; return }
                if !circuit.links.contains(from.link) { try session.apply(.circuit(.toggleLink(from.link))) }
                else { message = "ここはもうつながっているよ。線のボタンで外すこともできるよ。" }
            case .askCompanion: try session.apply(.askCompanion)
            case .observe:
                try session.apply(.observe)
                // The legacy observation action is separate from verification. Only
                // after the player has actually observed all rows do we validate them.
                if observations.count == 4 { try session.apply(.circuit(.verify)) }
            case .step: try session.apply(.circuit(.step))
            case .replayRow(let inputs):
                guard observations.contains(where: { $0.inputs == inputs }) else { message = "まだ記録していない条件だよ。スイッチで試して「今を記録」を押してね。"; return }
                if circuit.checks.contains(where: { $0.inputs == inputs && !$0.passed }) { try session.apply(.selectCounterexample(inputs)) }
                else { try session.apply(.circuit(.setInputs(inputs))) }
            case .predict(let answer):
                guard circuit.verification == .passed else { message = "先に4通りの光り方を目標と比べよう。"; return }
                try session.apply(.circuit(.setInputs(circuit.prediction.inputs)))
                try session.apply(.circuit(.predict(answer))); skippedPrediction = false
            case .skipPrediction:
                guard circuit.verification == .passed else { message = "先に4通りの光り方を目標と比べよう。"; return }
                skippedPrediction = true
            }
            if circuit.verification != .passed { skippedPrediction = false }
        } catch { message = (error as? LocalizedError)?.errorDescription ?? "この操作は今はできないよ。" }
    }
    public var isValid: Bool {
        (1...5).contains(stage) && session.initialSeed == 17 && circuit.mission == .and
        && !session.actions.contains(.finish) && !session.actions.contains(.reset)
        && session.actions.count <= WorkshopSession.maximumReplayActions
        && (!skippedPrediction || circuit.verification == .passed)
    }
    private enum CodingKeys: String, CodingKey { case stage, journal, skippedPrediction, message }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stage = try c.decode(Int.self, forKey: .stage)
        session = try WorkshopSession.replay(c.decode(WorkshopReplay.self, forKey: .journal))
        skippedPrediction = try c.decode(Bool.self, forKey: .skippedPrediction)
        message = try c.decode(String.self, forKey: .message)
        guard isValid else { throw DecodingError.dataCorruptedError(forKey: .journal, in: c, debugDescription: "Invalid circuit checkpoint") }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(stage, forKey: .stage); try c.encode(session.replayDocument(), forKey: .journal)
        try c.encode(skippedPrediction, forKey: .skippedPrediction); try c.encode(message, forKey: .message)
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.stage == rhs.stage && lhs.skippedPrediction == rhs.skippedPrediction
        && lhs.message == rhs.message && lhs.session.replayDocument() == rhs.session.replayDocument()
    }
}
