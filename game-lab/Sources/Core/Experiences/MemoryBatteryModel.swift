import Foundation

public enum MemoryPowerMode:String,Codable,CaseIterable,Identifiable {
    case standard,fast,idle
    public var id:String { rawValue }
    public var title:String { self == .standard ? "標準" : self == .fast ? "高速" : "待機" }
    public var watts:Int { self == .standard ? 12 : self == .fast ? 30 : 6 }
    public var work:Int { self == .standard ? 1 : self == .fast ? 2 : 0 }
}
public struct MemoryBatteryInterval:Codable,Equatable { public var mode:MemoryPowerMode; public var supply:Int }
public struct MemoryBatteryTrial:Codable,Equatable { public var modes:[MemoryPowerMode];public var supplies:[Int];public var endingSixths:Int;public var work:Int }
public struct MemoryBatteryModel:ExperienceModel {
    public static let gameID="battery-voyage"
    public enum Action { case mode(Int,MemoryPowerMode), supply(Int), step, restart, all(MemoryPowerMode), select(Int) }
    public private(set) var stage:Int
    public private(set) var energy=180
    public private(set) var intervals:[MemoryBatteryInterval]
    public private(set) var index=0
    public private(set) var selectedIndex=0
    public private(set) var work=0
    public private(set) var lastDelta=0
    public private(set) var spilled=0
    public private(set) var trials:[MemoryBatteryTrial]=[]
    public private(set) var levels:[Int]=[]
    public private(set) var message=""
    public var current:MemoryBatteryInterval { intervals[min(index,5)] }
    public var finished:Bool { index==6 }
    public var energyText:String { Self.wh(energy) }
    public var workText:String { stage==2 ? "\(work) 単位" : "\(work) / \(stage>=4 ? 9 : stage==3 ? 12 : 6)" }
    public static func wh(_ sixths:Int)->String { sixths%6==0 ? "\(sixths/6)" : String(format:"%.1f",Double(sixths)/6) }
    public var stageTitle:String { ["量と速さ","同じ残量で","つないでも減る","給電のある時間","満充電の上限"][stage-1] }
    public var goal:String { ["30Whから標準12Wで60分動かし、残量を観察しよう。", "標準と高速で同じ60分を過ごし、残量と仕事を比べよう。", "18W給電で12の仕事を終え、15Wh以上残そう。", "前半だけ給電できる60分。仕事9以上、残量10Wh以上の航路を作ろう。", "59Whから出発。高速と標準を3回ずつ、二つの順番で比べよう。"][stage-1] }
    public var hints:[String] {
        switch stage {
        case 1: return ["30Whは残っている量、12Wは使う速さだよ。", "10分は1/6時間。12Wなら10分ごとに2Wh使うね。", "『10分進める』を6回。60分で12Wh使って、18Wh残るよ。"]
        case 2: return ["出発時の30Whと60分は同じにして比べよう。", "高速は多く仕事ができるけれど、電力も大きくなるね。", "標準だけで60分試す→全区間高速にして60分。標準は18Wh・仕事6、高速は0Wh・仕事12になるよ。"]
        case 3: return ["給電中でも、使う電力のほうが大きいと残量は減るよ。", "給電18Wと高速30Wの差は12W。10分で電池から2Wh補うね。", "18W給電のまま全6区間を高速にして進めると、仕事12・残量18Whになるよ。"]
        case 4: return ["給電できるのは前半の30分だけ。各区間の仕事量も見よう。", "高速3回と標準3回で仕事9。満充電に届かなければ、順番を入れ替えても最後の残量は同じだよ。", "前半の3区間を高速、後半を標準にして6回進めると仕事9・残量17Whになるよ。"]
        default: return ["出発時に59Wh。電池は60Whを超えて蓄えられないね。", "給電中に満充電になると、受け取れない分が出るよ。どの時間に仕事をしよう？", "高速3回→標準3回を試してから『もう一度』。標準3回→高速3回に変え、54Whと45Whを比べよう。"]
        }
    }
    public var metrics:[ExperienceMetric] { [.init("残量","\(energyText) Wh"),.init("消費 / 給電","\(current.mode.watts) / \(current.supply) W"),.init("経過","\(index*10) 分"),.init("仕事",workText),.init("この区間","\(lastDelta>0 ? "+" : "")\(Self.wh(lastDelta)) Wh",detail:spilled>0 ? "受け取らなかった余剰 \(Self.wh(spilled)) Wh" : "") ] }
    public var guide:String { isComplete ? "仕事と残量、両方を見ながら航路を選べたね。量と使う速さは別なんだね。" : message.isEmpty ? "出発前のエネルギーを見て、どんな仕事をするか選ぼう。" : message }
    public var isComplete:Bool {
        switch stage {
        case 1:return finished && energy==108 && work==6
        case 2:return trials.contains { $0.endingSixths==108 && $0.work==6 } && trials.contains { $0.endingSixths==0 && $0.work==12 }
        case 3:return finished && energy>=90 && work==12 && intervals.allSatisfy { $0.supply==18 }
        case 4:return finished && work>=9 && energy>=60
        default:return trials.contains { $0.endingSixths==324 && $0.work==9 } && trials.contains { $0.endingSixths==270 && $0.work==9 }
        }
    }
    public var isValid:Bool {
        (1...5).contains(stage) && intervals.count==6 && intervals.allSatisfy { [0,18,36].contains($0.supply) }
        && (0...6).contains(index) && (0..<6).contains(selectedIndex) && (0...360).contains(energy)
        && work==intervals.prefix(index).reduce(0) { $0+$1.mode.work } && levels.count==index
        && levels.allSatisfy { (0...360).contains($0) } && (levels.last==nil || levels.last==energy) && spilled>=0 && trials.count<=20
    }
    public init(stage:Int) {
        self.stage=min(5,max(1,stage)); intervals=Array(repeating:.init(mode:.standard,supply:0),count:6)
        if self.stage==3 { intervals=Array(repeating:.init(mode:.fast,supply:18),count:6) }
        if self.stage>=4 { energy=self.stage==4 ? 120 : 354; intervals=(0..<6).map { .init(mode:.standard,supply:$0<3 ? 36 : 0) } }
    }
    private mutating func resetRun() { index=0;selectedIndex=0;energy=stage>=4 ? (stage==4 ? 120 : 354) : 180;work=0;lastDelta=0;spilled=0;levels=[];message="同じ出発残量から、もう一度比べよう。" }
    public mutating func send(_ action:Action) {
        switch action {
        case .select(let n):guard (0..<6).contains(n) else { return };selectedIndex=n
        case .restart:resetRun()
        case .mode(let n,let mode):guard stage>1,(0..<6).contains(n),n>=index else { return };intervals[n].mode=mode
        case .all(let mode):guard stage>1 else { return };resetRun();for i in intervals.indices { intervals[i].mode=mode }
        case .supply(let w):guard stage==3,[0,18,36].contains(w) else { return };resetRun();for i in intervals.indices { intervals[i].supply=w }
        case .step:
            guard !finished else { return }
            let item=intervals[index],delta=item.supply-item.mode.watts,raw=energy+delta
            guard raw>=0 else { message="この10分を終えるエネルギーが足りないよ。巻き戻して航路を見直そう。";return }
            spilled += max(0,raw-360);let next=min(360,raw);lastDelta=next-energy;energy=next;work += item.mode.work;index += 1;levels.append(energy);selectedIndex=min(5,index)
            message="10分で\(lastDelta>0 ? "+" : "")\(Self.wh(lastDelta))Wh。\(item.supply>0 && lastDelta<0 ? "つながっていても、使う速さのほうが大きいみたい。" : "仕事は\(work)になったね。")"
            if finished { let t=MemoryBatteryTrial(modes:intervals.map(\.mode),supplies:intervals.map(\.supply),endingSixths:energy,work:work);if !trials.contains(t) { trials.append(t);if trials.count>20 { trials.removeFirst() } } }
        }
    }
}
