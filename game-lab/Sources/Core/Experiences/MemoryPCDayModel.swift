import Foundation

public enum MemoryPCCommand: String, Codable, CaseIterable, Identifiable {
    case open, edit, display, save, saveAs
    public var id:String { rawValue }
    public var title:String { switch self { case .open:return "開く"; case .edit:return "編集"; case .display:return "表示"; case .save:return "保存"; case .saveAs:return "別名保存" } }
    public var icon:String { switch self { case .open:return "folder.fill"; case .edit:return "pencil"; case .display:return "display"; case .save,.saveAs:return "externaldrive.fill" } }
    public var duration:Int { self == .display ? 1 : 2 }
}
public struct MemoryPCDayModel: ExperienceModel {
    public static let gameID="pc-day"
    public enum Action { case append(MemoryPCCommand), remove(Int), move(Int,Int), clear, step, power, source(String), observe }
    public private(set) var stage:Int
    public private(set) var storage:[String:Int]=["original":1]
    public private(set) var ram:Int?
    public private(set) var display:Int?
    public private(set) var program:[MemoryPCCommand]=[]
    public private(set) var pc=0
    public private(set) var remaining=0
    public private(set) var ticks=0
    public private(set) var powered=true
    public private(set) var rebooted=false
    public private(set) var bootVersion:Int?
    public private(set) var selectedSource="original"
    public private(set) var sawInvalidOrder=false
    public private(set) var observedDifference=false
    public private(set) var message=""
    public var current:MemoryPCCommand? { pc<program.count ? program[pc] : nil }
    public var stageTitle:String { ["写真をひらく","明るくして見る","画面と保存","順番を直す","新しい依頼"][stage-1] }
    public var goal:String { ["写真をひらいて、画面に表示する手順を作ろう。", "写真を明るくして表示し、保存版との違いを観察しよう。", "編集版を保存し、電源を入れ直してひらき、画面で確かめよう。", "先に編集しようとする手順を試してから、順番を直そう。", "元写真v1を残し、編集版v2を別名で保存して表示しよう。"][stage-1] }
    public var hints:[String] {
        switch stage {
        case 1: return ["写真はまだSSDにあるね。まず作業台へひらこう。", "作業台にある写真を画面へ出すには、表示の操作が必要だよ。", "『開く』『表示』の札を並べて、1拍実行を3回押そう。"]
        case 2: return ["作業中の写真と、保存された写真を見比べよう。", "編集して表示しても、保存庫の元写真は変わらないよ。", "開く→編集→表示を5拍で実行。そのあと『観察を記録』で作業v2と保存v1を比べよう。"]
        case 3: return ["いまの編集版v2は、まだRAMと画面にしかないね。", "電源を切る前に保存すれば、入れ直したあとSSDからひらけるよ。", "保存を2拍実行→電源OFF→ON→『開く』『表示』を並べて3拍実行。"]
        case 4: return ["最初の札を1拍実行してみよう。写真がない場所で編集できるかな？", "札を選んで矢印を押すと、実行前の順番を入れ替えられるよ。", "失敗を確かめたら『開く』を左へ動かし、開く→編集→表示→保存を実行しよう。"]
        default: return ["元写真を残すには、どこへ編集版を保存すればいいかな？", "『保存』は選んだ元のファイルを書き換える。『別名保存』なら二つ残せるよ。", "開く→編集→表示→別名保存。元写真v1と別名v2の両方があることを確かめよう。"]
        }
    }
    public var metrics:[ExperienceMetric] { [.init("経過","\(ticks) 拍"),.init("作業版",ram.map { "v\($0)" } ?? "なし"),.init("表示",display.map { "v\($0)" } ?? "なし"),.init("元の保存版","v\(storage["original"] ?? 0)"),.init("別名の保存版",storage["edited"].map { "v\($0)" } ?? "なし")] }
    public var guide:String { isComplete ? "写真をひらく、変える、見せる、残す。部品の働きがつながったね。" : message.isEmpty ? "一枚の写真で、PCの中を旅してみよう。操作札を並べてね。" : message }
    public var isComplete:Bool { switch stage { case 1:return ram==1 && display==1; case 2:return ram==2 && display==2 && storage["original"]==1 && observedDifference; case 3:return rebooted && bootVersion==2 && display==2 && storage["original"]==2; case 4:return sawInvalidOrder && display==2 && storage["original"]==2; default:return display==2 && storage["original"]==1 && storage["edited"]==2 } }
    public var isValid:Bool {
        (1...5).contains(stage) && program.count<=6 && (0...program.count).contains(pc) && (0...2).contains(remaining)
        && (remaining==0 || (pc<program.count && powered)) && ticks>=0 && ticks<1000
        && (1...2).contains(storage.count) && storage.keys.allSatisfy { ["original","edited"].contains($0) }
        && storage.values.allSatisfy { [1,2].contains($0) } && storage[selectedSource] != nil
        && (ram==nil || [1,2].contains(ram!)) && (display==nil || [1,2].contains(display!))
        && (bootVersion==nil || [1,2].contains(bootVersion!))
        && (powered || (ram==nil && display==nil))
    }
    public init(stage:Int) { self.stage=min(5,max(1,stage)); if self.stage==3 { ram=2; display=2; ticks=5; program=[.save] }; if self.stage==4 { program=[.edit,.open,.display,.save] } }
    public mutating func send(_ action:Action) {
        switch action {
        case .power:
            guard stage==3 else { return }; powered.toggle(); remaining=0; pc=0; program=[]
            if !powered { ram=nil; display=nil; bootVersion=nil; message="作業場と画面は消えたね。保存庫には何が残ったかな？" } else { rebooted=true; bootVersion=storage["original"]; message="電源が入ったよ。保存庫からひらいて表示しよう。" }; return
        case .source(let id): guard storage[id] != nil, remaining==0 else { return }; selectedSource=id; return
        case .observe: observedDifference = observedDifference || (ram==2 && display==2 && storage["original"]==1); message="観察：作業\(ram.map { "v\($0)" } ?? "なし")、画面\(display.map { "v\($0)" } ?? "なし")、保存v\(storage["original"] ?? 0)。"; return
        default: break
        }
        guard powered else { message="まず教材の電源を入れてみよう。"; return }
        switch action {
        case .append(let command):
            guard program.count<6, remaining==0, command != .saveAs || stage==5 else { return }; program.append(command)
        case .remove(let n): guard remaining==0, program.indices.contains(n), n>=pc else { return }; program.remove(at:n)
        case .move(let n,let delta): guard remaining==0,(-5...5).contains(delta),program.indices.contains(n),program.indices.contains(n+delta),n>=pc,n+delta>=pc else { return }; program.swapAt(n,n+delta)
        case .clear: guard remaining==0 else { return }; program=[]; pc=0
        case .step:
            guard let command=current else { message="次にしたい操作札を、下のレールに置いてみよう。"; return }
            if remaining==0 {
                guard command == .open || ram != nil else { sawInvalidOrder=true; message="作業台に写真がないよ。『開く』を先に置いてみよう。"; return }
                remaining=command.duration
            }
            ticks += 1; remaining -= 1
            if remaining==0 {
                switch command { case .open:ram=storage[selectedSource]; case .edit:ram=2; case .display:display=ram; case .save:storage[selectedSource]=ram; case .saveAs:storage["edited"]=ram }
                pc += 1; message="『\(command.title)』が終わったよ。作業台・保存庫・画面のどこが変わったかな？"
            } else { message="CPUが『\(command.title)』を指示しているよ。あと\(remaining)拍。" }
        default: break
        }
    }
}
