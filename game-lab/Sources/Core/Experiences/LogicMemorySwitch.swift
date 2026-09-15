import Foundation

public struct LogicMemorySwitchModel: ExperienceModel {
    public static let gameID = "memory-switch"
    public enum Action { case toggle(Int), write, power, saveCopy, restoreCopy, record }
    public struct Event: Codable, Equatable { public var title: String; public var input: [Int]; public var stored: [Int?] }
    public var stage: Int
    public private(set) var input: [Int]
    public private(set) var stored: [Int?]
    public private(set) var powered = true
    public private(set) var copy: [Int]?
    public private(set) var events: [Event] = []
    public private(set) var evidence: Set<String> = []
    public private(set) var message = "入力を変えて、覚えている値と見比べよう。"
    public init(stage: Int) {
        self.stage = min(5, max(1, stage)); let count = self.stage >= 4 ? 4 : 1
        input = Array(repeating: 0, count: count); stored = Array(repeating: 0, count: count)
        if self.stage == 3 { stored = [1] }
        if self.stage == 5 { stored = [1,0,1,0] }
        if self.stage == 1 { message = "今は記憶する箱がないよ。入力を0と1にして、光り方を記録しよう。" }
        if self.stage == 5 { message = "まずコピーを作らずに電源を切り、何が残るか記録しよう。そのあと、保存した場合と比べてみよう。" }
        events = [Event(title: "初期", input: input, stored: stored)]
    }
    public var stageTitle: String { ["いまの合図", "合図を残す", "入力と記憶", "4つを一度に", "電源を切ったら"][stage - 1] }
    public var goal: String { ["入力0と1の光り方を比べて記録しよう。", "1を書いてから入力を0へ戻し、1を残そう。", "入力0・記憶1から、書く前と後を比べよう。", "1010を書き、入力0101に変えて保持と書込みを比べよう。", "保存せず切ったときと、保存して復元したときを比べよう。"][stage - 1] }
    public var output: [Int?] { !powered ? Array(repeating: nil, count: input.count) : stage == 1 ? input.map(Optional.some) : stored }
    public var inputText: String { input.map(String.init).joined() }
    public var storedText: String { stored.map { $0.map(String.init) ?? "?" }.joined() }
    public var guide: String {
        guard isComplete else { return message }
        if stage == 1 { return "入力を変えると、そのまま光り方が変わったね。次は合図を残す箱を試してみよう。" }
        if stage == 5 { return "電源を切ると記憶は失われたね。別に保存していたコピーからは戻せることも確かめられたよ。" }
        return "今の入力と、残している値は別だったね。書くタイミングで変えられたよ。"
    }
    public var hints: [String] {
        if stage == 1 { return ["入力と出力の数字を見比べてみよう。", "入力を変えたら、ほかの操作なしで出力も変わるかな？", "入力0で記録してから1に変え、もう一度記録しよう。"] }
        if stage == 5 { return ["まずコピーなしで電源を切り、未設定の記憶を記録しよう。", "次は電源を入れ、1010を書いてコピーを保存してから切ってみよう。", "保存したあと電源を切って入れ直したら『コピーを戻す』で2つの場合を比べよう。"] }
        return ["入力と、覚えている値を別々に見よう。", "箱が変わったのは、どの操作の直後だったかな？", stage == 4 ? "1010を書き、入力だけ0101へ。それを記録してからもう一度書こう。" : "入力を1にして『書く』、入力だけ0に戻してみよう。"]
    }
    public var isComplete: Bool {
        switch stage {
        case 1: return evidence.isSuperset(of: ["direct0", "direct1"])
        case 2: return evidence.contains("hold1")
        case 3: return evidence.isSuperset(of: ["before", "after"])
        case 4: return evidence.isSuperset(of: ["hold4", "write4"])
        default: return evidence.isSuperset(of: ["lost", "restored"])
        }
    }
    public var metrics: [ExperienceMetric] { [.init("入力 D", powered ? inputText : "電源OFF"), .init("記憶 Q", stage == 1 ? "記憶なし" : storedText), .init("保存コピー", copy?.map(String.init).joined() ?? "なし"), .init("比較記録", "\(evidence.count) 件")] }
    public var isValid: Bool { (1...5).contains(stage) && input.count == (stage >= 4 ? 4 : 1) && input.count == stored.count && input.allSatisfy { $0 == 0 || $0 == 1 } && stored.allSatisfy { $0 == nil || $0 == 0 || $0 == 1 } && events.count <= 64 && (copy == nil || (copy!.count == input.count && copy!.allSatisfy { $0 == 0 || $0 == 1 })) && events.allSatisfy { $0.input.count == input.count && $0.stored.count == stored.count } }
    public mutating func send(_ action: Action) {
        var title = ""
        switch action {
        case .toggle(let bit):
            guard powered, input.indices.contains(bit) else { message = "電源を入れてから入力を変えよう。"; return }
            input[bit] = 1-input[bit]; title = "入力"
            message = stage == 1 ? "入力は\(inputText)。出力も\(inputText)に変わったね。今の光り方を記録してみよう。" : "入力は\(inputText)になったね。記憶Qは\(storedText)のままだよ。『書く』前後で比べてみよう。"
        case .write:
            guard powered, stage > 1 else { message = "電源を入れてから書いてみよう。"; return }
            stored = input.map(Optional.some); title = "書く"; message = "今の入力を書いたよ。入力だけ変えると、どうなるかな？"
        case .power:
            guard stage == 5 else { return }; powered.toggle(); stored = Array(repeating: nil, count: input.count); title = powered ? "電源ON" : "電源OFF"
            if !powered && copy == [1,0,1,0] { evidence.insert("savedPowerOff") }
            message = powered ? "電源を入れたけれど、記憶は未設定だね。書くか、保存コピーを戻そう。" : "電源が切れたね。記憶は?になったけれど、コピーは残っているかな？"
        case .saveCopy:
            guard stage == 5, powered, stored.allSatisfy({ $0 != nil }) else { message = "値を書いてから、保存コピーを作ろう。"; return }; copy = stored.compactMap { $0 }; evidence.remove("savedPowerOff"); title = "コピー保存"
        case .restoreCopy:
            guard stage == 5, powered, let copy else { message = "保存したコピーと電源が必要だね。"; return }; stored = copy.map(Optional.some); title = "復元"
            if evidence.contains("lost") && evidence.contains("savedPowerOff") && copy == [1,0,1,0] { evidence.insert("restored") }
        case .record:
            if stage == 1 { evidence.insert("direct\(inputText)") }
            if powered && input == [0] && stored == [1] { evidence.insert("hold1"); if stage == 3 { evidence.insert("before") } }
            if stage == 3 && powered && input == [0] && stored == [0] && evidence.contains("before") { evidence.insert("after") }
            if stage == 4 && powered && input == [0,1,0,1] && stored == [1,0,1,0] { evidence.insert("hold4") }
            if stage == 4 && powered && input == [0,1,0,1] && stored == [0,1,0,1] && evidence.contains("hold4") { evidence.insert("write4") }
            if stage == 5 && copy == nil && stored.allSatisfy({ $0 == nil }) { evidence.insert("lost") }
            title = "記録"; message = stage == 1 ? "今の入力と出力を記録したよ。もう一方の合図でも比べてみよう。" : "今の入力と記憶を記録したよ。条件を変えて比べよう。"
        }
        if stage == 1 { stored = input.map(Optional.some) }
        events.append(Event(title: title, input: input, stored: stored)); if events.count > 64 { events.removeFirst() }
    }
}
