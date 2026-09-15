import Foundation

public struct MemoryRescueData: Codable, Equatable, Identifiable {
    public var id: String
    public var raw: Int
    public var packed: Int
    public var location: String
    public var compressed = false
    public var version = 2
    public var footprint: Int { compressed ? packed : raw }
}
public struct MemoryRescueTrial: Codable, Equatable { public var capacity: Int; public var method: String; public var ticks: Int }
public struct MemoryRescueModel: ExperienceModel {
    public static let gameID = "memory-rescue"
    public enum Action { case select(String), compress, evict, admit, close, step, capacity(Int), restart, power, restore }
    public private(set) var stage: Int
    public private(set) var ramCapacity=6
    public private(set) var data: [MemoryRescueData]
    public private(set) var selectedID="B"
    public private(set) var requests: [String]
    public private(set) var index=0
    public private(set) var ticks=0
    public private(set) var cpuTicks=0
    public private(set) var ioTicks=0
    public private(set) var method=""
    public private(set) var powered=true
    public private(set) var restored=false
    public private(set) var trials: [MemoryRescueTrial]=[]
    public private(set) var log: [String]=[]
    public private(set) var message=""
    public var usedRAM: Int { data.filter { $0.location == "ram" }.reduce(0) { $0+$1.footprint } }
    public var usedScratch: Int { data.filter { $0.location == "scratch" }.reduce(0) { $0+$1.raw } }
    public var selected: MemoryRescueData? { data.first { $0.id == selectedID } }
    public var next: String? { index < requests.count ? requests[index] : nil }
    public var stageTitle: String { ["いっぱいでも動く","小さくする費用","また使うなら","行ったり来たり","退避は保存？"][stage-1] }
    public var goal: String { ["RAMが満杯のままA B A Bを使ってみよう。", "Bを残してCを入れよう。圧縮と退避の2つの方法で比べよう。", "Cを使ったあと、Bをもう一度使おう。広げる場所はあるかな？", "同じA B A Bを、RAM3枠と6枠で読み比べよう。", "教材の電源を切って入れ直し、保存庫の元データを読み込もう。"][stage-1] }
    public var hints: [String] {
        switch stage {
        case 1: return ["使いたいAとBは、どちらもRAMに置いてあるね。", "空きを作らなくても、すでにあるデータは1拍で読めるよ。", "『次の要求を読む』を4回押してみよう。満杯でも4拍で終わるね。"]
        case 2: return ["次に必要なCは2枠。しばらく使わないBをどうしよう？", "Bは3→1枠へ圧縮できるよ。圧縮には2拍、退避には3拍かかる。", "Bを圧縮→Cを入れる→4回読む。その後『もう一度』でBを退避する方法も試そう。"]
        case 3: return ["Bは小さく畳まれているけれど、使うときは3枠に戻るよ。", "Cを読み終えたら閉じられるね。Bを広げる2枠を作ろう。", "Cを1回読む→Cを選んで閉じる→次のBを読む。広げる2拍と読む1拍が加わるよ。"]
        case 4: return ["RAM3枠では、一度にAとBの片方しか置けないね。", "読み終えた品を選んで一時退避すると、次の品を読み込めるよ。", "Aを読む→A退避→Bを読む→B退避→Aを読む→A退避→Bを読む。その後RAM6枠で比べよう。"]
        default: return ["RAMと一時退避には作業版v2、保存庫には元のv1があるよ。", "この教材の電源を切ったあと、作業版がどこに残るか確かめよう。", "電源OFF→ON→『保存庫のv1をひらく』。戻るのは保存されたv1で、未保存のv2ではないよ。"]
        }
    }
    public var metrics: [ExperienceMetric] { [.init("RAM", "\(usedRAM) / \(ramCapacity) 枠"), .init("一時退避", "\(usedScratch) / 12 枠"), .init("経過", "\(ticks) 拍"), .init("CPUの仕事", "\(cpuTicks) 拍"), .init("移動の待ち", "\(ioTicks) 拍")] }
    public var guide: String {
        if isComplete { return ["RAMがいっぱいでも、置いてあるデータはそのまま使えたね。", "圧縮はCPU、退避は移動の仕事が増えたね。空きと時間の両方で比べよう。", "小さくできても、使うときは広げる空きと時間が必要なんだね。", "退避した量だけでなく、行き来の回数で待ち時間が変わったね。", "退避は保存の代わりではなかったね。未保存の作業版v2は戻らなかったよ。"][stage-1] }
        return message.isEmpty ? goal : message
    }
    public var isComplete: Bool {
        switch stage {
        case 1: return index == 4 && ticks == 4
        case 2: return trials.contains { $0.method == "圧縮" && $0.ticks == 6 } && trials.contains { $0.method == "退避" && $0.ticks == 7 }
        case 3: return index == 2 && ticks == 4
        case 4: return trials.contains { $0.capacity == 3 && $0.ticks == 22 } && trials.contains { $0.capacity == 6 && $0.ticks == 7 }
        default: return restored && powered && data.allSatisfy { $0.location == "ram" && $0.version == 1 }
        }
    }
    public var isValid: Bool {
        (1...5).contains(stage) && [3,6].contains(ramCapacity)
        && (1...3).contains(data.count) && requests.count <= 4 && (0...requests.count).contains(index) && ticks >= 0 && ticks < 1000
        && Set(data.map(\.id)).count == data.count && data.contains { $0.id == selectedID }
        && data.allSatisfy { ["A","B","C"].contains($0.id) && (1...3).contains($0.raw) && $0.packed > 0 && $0.packed <= $0.raw && ["ram","scratch","waiting","gone","closed"].contains($0.location) && [1,2].contains($0.version) && (!$0.compressed || $0.location == "ram") }
        && usedRAM <= ramCapacity && usedScratch <= 12 && (powered || usedRAM + usedScratch == 0)
        && requests.allSatisfy { id in data.contains { $0.id == id } } && trials.count <= 20
    }
    public init(stage: Int) {
        self.stage=min(5,max(1,stage)); data=[.init(id:"A",raw:3,packed:3,location:"ram"), .init(id:"B",raw:3,packed:1,location:"ram")]; requests=["A","B","A","B"]
        if self.stage == 2 { data.append(.init(id:"C",raw:2,packed:2,location:"waiting")); requests=["A","C","A","C"] }
        if self.stage == 3 { data[1].compressed=true; data.append(.init(id:"C",raw:2,packed:2,location:"ram")); requests=["C","B"]; selectedID="C" }
        if self.stage == 4 { ramCapacity=3; data[1].packed=3; data[1].location="scratch"; selectedID="A" }
        if self.stage == 5 { data[1].location="scratch"; requests=[] }
    }
    private mutating func note(_ text: String) { message=text; log.append(text); if log.count>30 { log.removeFirst() } }
    private mutating func restartRun(capacity: Int? = nil) {
        let keep=trials; let cap=capacity ?? ramCapacity; self=Self(stage:stage); if stage == 4 { ramCapacity=cap }; trials=keep
    }
    public mutating func send(_ action: Action) {
        switch action {
        case .select(let id): guard data.contains(where: { $0.id==id }) else { return }; selectedID=id; return
        case .restart: restartRun(); return
        case .capacity(let n): guard stage == 4 && [3,6].contains(n) else { return }; restartRun(capacity:n); return
        case .power:
            guard stage == 5 else { return }; powered.toggle()
            if !powered { data.indices.forEach { data[$0].location="gone" }; note("作業中のデータはRAMからも一時退避からも消えたね。保存の代わりにはならないよ。") } else { note("保存庫には元データv1が残っているよ。読み込んでみよう。") }; return
        case .restore:
            guard stage == 5 && powered && data.allSatisfy({ $0.location == "gone" }) else { return }; data.indices.forEach { data[$0].location="ram";data[$0].version=1 }; restored=true; note("保存された元データv1が戻ったよ。未保存のv2は戻っていないね。"); return
        default: break
        }
        guard powered, let i=data.firstIndex(where: { $0.id==selectedID }) else { return }
        switch action {
        case .compress:
            guard stage == 2, data[i].location == "ram", data[i].packed < data[i].raw, !data[i].compressed else { note("このデータは今は圧縮できないよ。"); return }
            data[i].compressed=true; ticks += 2; cpuTicks += 2; method="圧縮"; note("Bを3→1枠にしたよ。CPUも2拍働いたね。")
        case .evict:
            guard [2,4].contains(stage), data[i].location == "ram", !data[i].compressed, usedScratch+data[i].raw <= 12 else { note("非圧縮の作業データを選ぶと、一時退避できるよ。"); return }
            data[i].location="scratch"; ticks += data[i].raw; ioTicks += data[i].raw; if stage == 2 { method="退避" }; note("\(selectedID)を一時退避したよ。移動に\(data[i].raw)拍かかったね。")
        case .admit:
            guard stage == 2, let c=data.firstIndex(where: { $0.id=="C" }), data[c].location == "waiting" else { return }
            guard usedRAM+2 <= ramCapacity else { note("Cには2枠の空きが必要だよ。"); return }; data[c].location="ram"; note("Cが入ったね。次の要求を進めてみよう。")
        case .close:
            guard stage == 3, selectedID == "C", index > 0, data[i].location == "ram" else { note("この先に必要なデータは閉じずに残そう。"); return }; data[i].location="closed"; note("Cを閉じて2枠空いたね。Bを広げられるかな？")
        case .step:
            guard let item=next, let n=data.firstIndex(where: { $0.id==item }) else { return }
            if data[n].location == "waiting" { note("\(item)がまだ作業場に入っていないよ。"); return }
            if data[n].location == "scratch" {
                guard usedRAM+data[n].raw <= ramCapacity else { note("\(item)を読むには\(data[n].raw)枠の空きが必要。いま使ったデータを退避できるかな？"); return }
                data[n].location="ram"; ticks += data[n].raw; ioTicks += data[n].raw
            }
            guard data[n].location == "ram" else { return }
            if data[n].compressed {
                let extra=data[n].raw-data[n].packed
                guard usedRAM+extra <= ramCapacity else { note("Bを広げるには、あと\(usedRAM+extra-ramCapacity)枠必要だね。"); return }
                data[n].compressed=false; ticks += 2; cpuTicks += 2
            }
            ticks += 1; index += 1; note("\(item)を読んだよ。経過\(ticks)拍、RAMは\(usedRAM)/\(ramCapacity)枠。")
            if index == requests.count {
                let t=MemoryRescueTrial(capacity:ramCapacity,method:method,ticks:ticks)
                if !trials.contains(t) { trials.append(t); if trials.count>20 { trials.removeFirst() } }
            }
        default: break
        }
    }
}
