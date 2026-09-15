import Foundation

public struct ParallelConnection: Codable, Equatable, Identifiable {
    public var id: Int
    public var device: String
    public var port: String
    public var cable: String
}
public struct ParallelConnectionCheck: Codable, Equatable, Identifiable {
    public var id: String { label }
    public var label: String
    public var status: Int // -1 unknown, 0 insufficient, 1 passes
    public var detail: String
}
public struct ParallelConnectionModel: ExperienceModel {
    public static let gameID = "connection-lab"
    public enum Action { case cable(Int,String), port(Int,String), connect(Int), disconnect(Int), inspect, reveal, reset }
    public private(set) var stage: Int
    public private(set) var connections: [ParallelConnection] = []
    public private(set) var connectedIDs: Set<Int> = []
    public private(set) var checks: [ParallelConnectionCheck] = []
    public private(set) var revealed = false
    public private(set) var observations: Set<String> = []
    public private(set) var notice = ""
    public var stageTitle: String { ["つないで届ける", "挿さったのに映らない", "電気も足りる？", "みんなで同じ口", "書いていない条件"][stage - 1] }
    public var goal: String { ["カメラをつないで、形・通信・給電を確かめよう。", "αの接続を調べてから、映像を送れるケーブルを見つけよう。", "γで映像と給電を調べてから、画面の必要条件をそろえよう。", "ハブの入口は容量8。3台を2つのポートに分けて届けよう。", "未記載は非対応とは別。条件カードを調べてから確かめよう。"][stage - 1] }
    public var hints: [String] { ["形、映像、通信、電気は別々の条件だよ。", stage == 4 ? "子ポートが増えても、入口の容量8はみんなで使うよ。" : "機器の必要条件と、ケーブルの条件カードを比べてみよう。", stage == 4 ? "カメラ3と倉庫5を一つの入口へ、画面6をもう一方へ分けよう。" : stage == 5 ? "『仕様を見る』で未記載の条件を確かめ、もう一度検査しよう。" : "βは映像あり・容量8・給電60W。この架空の画面は6と30Wが必要だよ。"] }
    public var guide: String {
        if !notice.isEmpty { return notice }
        if isComplete { return "条件をひと続きで確かめられたね。挿さる形だけで、できることは決まらないね。" }
        if checks.contains(where: { $0.status == -1 }) { return "まだ確認できない条件があるね。書いていないことと、非対応は違うよ。" }
        if let failure = checks.first(where: { $0.status == 0 }) { return "\(failure.label)：\(failure.detail)。どの条件を替えるとよさそうかな？" }
        if !checks.isEmpty { return "今の接続は条件を満たしたね。最初の組み合わせとの違いも確かめよう。" }
        return "この機器を動かしたいな。機器もケーブルも、できることを見てみよう。"
    }
    public var isComplete: Bool {
        guard !checks.isEmpty, checks.allSatisfy({ $0.status == 1 }) else { return false }
        switch stage { case 2: return observations.contains("alpha-failed"); case 3: return observations.contains("gamma-failed"); case 4: return observations.contains("hub-overloaded"); case 5: return observations.contains("unknown") && revealed; default: return true }
    }
    public var metrics: [ExperienceMetric] {
        if checks.isEmpty { return [.init("接続", "\(connectedIDs.count) / \(connections.count)"),.init("検査","未検査"),.init("条件", "架空の機器")] }
        let ordered = checks.filter { $0.status != 1 } + checks.filter { $0.status == 1 }
        return ordered.prefix(5).map { .init($0.label, $0.status < 0 ? "? 未確認" : $0.status == 0 ? "× 不足" : "✓",detail:$0.detail) }
    }
    public var availableCables: [String] { stage == 5 ? ["δ"] : ["α","β","γ"] }
    public var availablePorts: [String] { stage == 4 ? ["ハブ","B1","B2"] : ["A","B"] }
    public init(stage: Int) {
        self.stage = min(5,max(1,stage))
        if self.stage == 4 { connections = [ParallelConnection(id:0,device:"カメラ",port:"ハブ",cable:"β"),ParallelConnection(id:1,device:"ストレージ",port:"ハブ",cable:"β"),ParallelConnection(id:2,device:"画面",port:"ハブ",cable:"β")]; connectedIDs = [0,1,2] }
        else { connections = [ParallelConnection(id:0,device:self.stage == 1 ? "カメラ" : "画面",port:self.stage == 1 ? "A" : "B",cable:self.stage == 3 ? "γ" : self.stage == 5 ? "δ" : "α")]; connectedIDs = self.stage == 1 ? [] : [0] }
    }
    public func requirement(_ device: String) -> (capacity: Int,power: Int,video: Bool) { device == "画面" ? (6,30,true) : device == "カメラ" ? (3,5,false) : (5,10,false) }
    public func cableValues(_ cable: String) -> (capacity: Int,power: Int?,video: Bool?) { switch cable { case "α": return (4,60,false); case "γ": return (8,15,true); case "δ" where !revealed: return (8,nil,nil); default: return (8,60,true) } }
    public func cableDescription(_ cable: String) -> String { let c = cableValues(cable); return "映像 \(c.video.map { $0 ? "あり" : "なし" } ?? "未記載")\n容量 \(c.capacity) / 給電 \(c.power.map { "\($0)W" } ?? "未記載")" }
    private mutating func invalidate() { checks = []; notice = "接続を替えたね。今の条件で、もう一度確かめよう。" }
    public mutating func send(_ action: Action) {
        notice = ""
        switch action {
        case .cable(let id,let cable): guard availableCables.contains(cable),let i = connections.firstIndex(where: { $0.id == id }) else { return }; connections[i].cable = cable; invalidate()
        case .port(let id,let port): guard availablePorts.contains(port), let i = connections.firstIndex(where: { $0.id == id }) else { return }; connections[i].port = port; invalidate()
        case .connect(let id): guard connections.contains(where: { $0.id == id }) else { return }; connectedIDs.insert(id); invalidate()
        case .disconnect(let id): connectedIDs.remove(id); invalidate()
        case .reveal: guard stage == 5 else { return }; if !revealed { observations.insert("unknown") }; revealed = true; invalidate()
        case .reset: let saved = observations; self = .init(stage:stage); observations = saved
        case .inspect:
            checks = []
            var totalByPort: [String:Int] = [:]; var powerByPort: [String:Int] = [:]
            for con in connections {
                let prefix = connections.count > 1 ? con.device + "・" : ""
                guard connectedIDs.contains(con.id) else { checks.append(.init(label:prefix + "経路",status:0,detail:"両端をつないでみよう")); continue }
                let req = requirement(con.device); let cable = cableValues(con.cable)
                let cap = min(con.port == "A" ? 4 : 8,cable.capacity)
                let availablePower = cable.power.map { min(con.port == "A" ? 15 : 60,$0) }
                checks.append(.init(label:prefix + "形",status:1,detail:"架空C形・適合"))
                if req.video { checks.append(.init(label:prefix + "映像",status:con.port == "A" || cable.video == false ? 0 : cable.video == nil ? -1 : 1,detail:con.port == "A" || cable.video == false ? "映像の対応なし" : cable.video == nil ? "ケーブルの対応が未記載" : "経路全体が対応")) }
                checks.append(.init(label:prefix + "容量",status:cap >= req.capacity ? 1 : 0,detail:"\(cap) / 必要\(req.capacity)"))
                checks.append(.init(label:prefix + "給電",status:availablePower.map { $0 >= req.power ? 1 : 0 } ?? -1,detail:"\(availablePower.map { "\($0)W" } ?? "未記載") / 必要\(req.power)W"))
                let port = con.port == "ハブ" ? "B1" : con.port
                totalByPort[port,default:0] += req.capacity; powerByPort[port,default:0] += req.power
            }
            if stage == 4 {
                let active = connections.filter { connectedIDs.contains($0.id) }
                for port in ["B1","B2"] {
                    let direct = active.filter { $0.port == port }.count
                    let hubUsesPort = port == "B1" && active.contains { $0.port == "ハブ" }
                    if direct > 1 || (direct > 0 && hubUsesPort) {
                        checks.append(.init(label:port + "物理接続",status:0,detail:"一つの口に複数の直接接続はできない。ハブへまとめよう"))
                    }
                }
                for port in ["B1","B2"] where totalByPort[port,default:0] > 0 {
                    checks.append(.init(label:port + "共有容量",status:totalByPort[port,default:0] <= 8 ? 1 : 0,detail:"\(totalByPort[port,default:0]) / 8"))
                    checks.append(.init(label:port + "共有給電",status:powerByPort[port,default:0] <= 60 ? 1 : 0,detail:"\(powerByPort[port,default:0]) / 60W"))
                }
                if totalByPort["B1",default:0] > 8 { observations.insert("hub-overloaded") }
            }
            if stage == 2 && connections[0].cable == "α" && checks.contains(where: { $0.status == 0 }) { observations.insert("alpha-failed") }
            if stage == 3 && connections[0].cable == "γ" && checks.contains(where: { $0.label == "給電" && $0.status == 0 }) { observations.insert("gamma-failed") }
            if stage == 5 && checks.contains(where: { $0.status == -1 }) { observations.insert("unknown") }
        }
    }
}
