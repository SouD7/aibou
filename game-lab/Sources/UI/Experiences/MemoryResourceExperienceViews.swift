import SwiftUI
import AppKit

struct MemoryCacheExperienceView: View {
    @StateObject private var store=ExperienceStore(MemoryCacheModel(stage:1))
    var onExit:()->Void
    var body:some View { ExperienceScreen(store:store,onExit:onExit) { model,send in MemoryCacheApparatus(model:model,send:send) } }
}
struct MemoryCacheApparatus:View {
    let model:MemoryCacheModel;let send:(MemoryCacheModel.Action)->Void
    @State private var playing=false
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.scenePhase) private var scenePhase
    private let clock=Timer.publish(every:0.55,on:.main,in:.common).autoconnect()
    var body:some View {
        ZStack(alignment:.topLeading) {
            ExperienceDevice(title:"遠い棚",subtitle:"原本は残ります") {
                VStack(spacing:8) { ForEach(Array(Set(model.requests)).sorted(),id:\.self) { id in
                    HStack(spacing:12) {
                        Image(systemName:id=="A" ? "photo" : id=="B" ? "music.note" : "doc.fill").font(.system(size:20,weight:.semibold))
                        Text(id).font(.system(size:22,weight:.bold))
                    }.frame(maxWidth:.infinity).frame(height:34)
                        .foregroundStyle(ExperienceStyle.ink).background(memoryColor(id).gradient,in:WorkshopChamfer(corner:6))
                        .overlay(WorkshopChamfer(corner:6).strokeBorder(ExperienceStyle.ink,lineWidth:1.5))
                } }
            }.frame(width:180,height:355).offset(x:20,y:25)
            MemoryOrderStrip(items:model.requests,index:model.index).frame(width:880,height:78).offset(x:240,y:20)

            VStack(spacing:12) {
                ZStack {
                    RoundedRectangle(cornerRadius:20).fill(.black.opacity(0.3)).frame(height:22)
                    ExperienceSignal(active:model.remaining>0).frame(height:8)
                    Image(systemName:"shippingbox.fill").font(.system(size:35)).foregroundStyle(ExperienceStyle.amber)
                        .padding(12).background(ExperienceStyle.paper,in:RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(ExperienceStyle.ink,lineWidth:2))
                        .offset(x:model.remaining>0 ? CGFloat(4-model.remaining)/4*220-100 : -130)
                        .animation(reducedMotion ? nil : .easeInOut(duration:0.3),value:model.remaining)
                }.frame(height:130)
                Text(model.pending.map { "\($0)が到着 · 置き換える品を選ぼう" } ?? (model.finished ? "すべて到着" : "\(model.next ?? "")便 · \(model.remaining>0 ? "あと\(model.remaining)拍" : "発車前")"))
                    .font(.system(size:18,weight:.bold)).foregroundStyle(.white)
                HStack { Text("遠い棚 4拍");Spacer();Text("手元 1拍") }.font(.system(size:15,weight:.medium)).foregroundStyle(.white.opacity(0.7))
            }.frame(width:440,height:220).offset(x:230,y:135)

            ExperienceDevice(title:"近い棚",subtitle:"\(model.cache.count) / \(model.capacity) 口",active:model.currentHit && model.remaining>0) {
                HStack(spacing:12) {
                    ForEach(0..<max(1,model.capacity),id:\.self) { slot in
                        if slot<model.cache.count {
                            let id=model.cache[slot]
                            Button { if model.pending != nil { send(.replace(id)) } } label: { ExperienceChip(label:id,symbol:"shippingbox.fill",color:memoryColor(id),selected:model.pending != nil).frame(height:110) }.buttonStyle(.plain)
                                .accessibilityLabel("手元の\(id)\(model.pending != nil ? "を入れ替える" : "")")
                        } else {
                            RoundedRectangle(cornerRadius:7).fill(ExperienceStyle.dark).overlay(Text(model.capacity==0 ? "保持なし" : "空き").font(.system(size:17,weight:.bold)).foregroundStyle(.white.opacity(0.6))).frame(height:110)
                        }
                    }
                }
                if model.pending != nil { Button("今回の品を残さない") { send(.replace(nil)) }.buttonStyle(ExperienceButtonStyle()) }
            }.frame(width:415,height:290).offset(x:710,y:105)

            HStack(spacing:10) {
                Button("1拍進める") { playing=false;send(.step) }.buttonStyle(ExperienceButtonStyle(primary:true)).keyboardShortcut(.space,modifiers:[])
                Button(playing ? "一時停止" : "再生") { playing.toggle() }.buttonStyle(ExperienceButtonStyle())
                Button("もう一度") { playing=false;send(.restart) }.buttonStyle(ExperienceButtonStyle())
                if model.stage==2 || model.stage==5 {
                    ForEach(model.stage==2 ? [1,2] : [0,3],id:\.self) { n in Button("棚 \(n)口") { playing=false;send(.configure(n)) }.buttonStyle(ExperienceButtonStyle(primary:model.capacity==n)) }
                }
                if model.stage==4 {
                    Button("A B A C A B") { playing=false;send(.order(0)) }.buttonStyle(ExperienceButtonStyle())
                    Button("A A A B B C") { playing=false;send(.order(1)) }.buttonStyle(ExperienceButtonStyle())
                }
            }.offset(x:230,y:413)
            MemoryObservationLine(title:"配達の記録",lines:model.log.suffix(6).map { $0 }).frame(width:890,height:30).offset(x:230,y:477)
            MemoryObservationLine(title:"比べた結果",lines:model.trials.suffix(3).map { "\($0.capacity)口 / \($0.order) / \($0.ticks)拍" }).frame(width:1090,height:30).offset(x:30,y:511)
        }.frame(width:1160,height:550,alignment:.topLeading)
        .onReceive(clock) { _ in if playing { if model.pending != nil || model.finished { playing=false } else { send(.step) } } }
        .onChange(of:scenePhase) { if $0 != .active { playing=false } }
        .onChange(of:model.stage) { _ in playing=false }
        .onDisappear { playing=false }
    }
}

struct MemoryRescueExperienceView:View {
    @StateObject private var store=ExperienceStore(MemoryRescueModel(stage:1))
    var onExit:()->Void
    var body:some View { ExperienceScreen(store:store,onExit:onExit) { model,send in MemoryRescueApparatus(model:model,send:send) } }
}
struct MemoryRescueApparatus:View {
    let model:MemoryRescueModel;let send:(MemoryRescueModel.Action)->Void
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    private var compressed:Bool { model.data.contains { $0.id=="B" && $0.compressed } }
    var body:some View {
        ZStack(alignment:.topLeading) {
            ExperienceDevice(title:"圧縮",subtitle:"CPUの仕事 2拍") {
                VStack(spacing:5) {
                    MemoryCompressionMechanism(compressed:compressed)
                        .animation(reducedMotion ? nil : .easeInOut(duration:0.5),value:compressed)
                    Text(compressed ? "出口 · B 1枠" : "入口 · B 3枠").font(.system(size:12,weight:.bold)).foregroundStyle(ExperienceStyle.muted)
                    Button("圧縮する") { send(.compress) }.buttonStyle(ExperienceButtonStyle()).disabled(model.stage != 2 || compressed)
                }
            }.frame(width:205,height:290).offset(x:15,y:25)
            ExperienceDevice(title:"RAM",subtitle:"\(model.usedRAM) / \(model.ramCapacity) 枠",active:model.powered) {
                HStack(spacing:5) {
                    ForEach(model.data.filter { $0.location=="ram" }) { item in
                        Button { send(.select(item.id)) } label: {
                            VStack(spacing:10) {
                                Text(item.id).font(.system(size:36,weight:.bold))
                                Text(item.compressed ? "\(item.raw)→\(item.packed)" : "\(item.raw)枠").font(.system(size:19,weight:.bold))
                                if model.stage==5 { Text("\(model.restored ? "保存版" : "作業版") v\(item.version)").font(.system(size:12)) }
                            }.frame(width:CGFloat(item.footprint)/CGFloat(model.ramCapacity)*525-5,height:165)
                                .foregroundStyle(ExperienceStyle.ink)
                                .background(MemoryCartridgeShell(color:memoryColor(item.id),units:item.footprint,selected:model.selectedID==item.id,compressed:item.compressed))
                        }.buttonStyle(.plain).onDrag { NSItemProvider(object:item.id as NSString) }
                    }
                    ForEach(0..<max(0,model.ramCapacity-model.usedRAM),id:\.self) { _ in RoundedRectangle(cornerRadius:4).fill(ExperienceStyle.dark).frame(width:525/CGFloat(model.ramCapacity)-5,height:165) }
                }.frame(width:535,height:175).animation(reducedMotion ? nil : .easeInOut(duration:0.5),value:model.usedRAM)
            }.frame(width:580,height:290).offset(x:245,y:25)
            ExperienceDevice(title:"一時退避",subtitle:"\(model.usedScratch) / 12 枠") {
                VStack(spacing:12) {
                    ForEach(model.data.filter { $0.location=="scratch" }) { item in
                        Button { send(.select(item.id)) } label: { ExperienceChip(label:"\(item.id) · \(item.raw)枠",symbol:"shippingbox",color:memoryColor(item.id),selected:model.selectedID==item.id).frame(height:100) }.buttonStyle(.plain)
                    }
                    if model.usedScratch==0 { Image(systemName:"tray").font(.system(size:55)).foregroundStyle(ExperienceStyle.muted).frame(height:100) }
                    Text("保存の代わりではありません").font(.system(size:12,weight:.medium)).foregroundStyle(ExperienceStyle.muted)
                }
            }.frame(width:285,height:290).offset(x:850,y:25)
                .memoryDrop { id in send(.select(id));send(.evict) }
            if !model.requests.isEmpty { MemoryOrderStrip(items:model.requests,index:model.index).frame(width:580,height:75).offset(x:245,y:333) }
            if model.stage==2 {
                Button { send(.admit) } label: { ExperienceChip(label:"Cを入れる · 2枠",symbol:"plus",color:ExperienceStyle.amber).frame(width:185,height:78) }.buttonStyle(.plain).offset(x:20,y:335)
            }
            HStack(spacing:10) {
                if model.stage==5 {
                    Button(model.powered ? "電源OFF（実験内）" : "電源ON") { send(.power) }.buttonStyle(ExperienceButtonStyle())
                    Button("保存庫のv1をひらく") { send(.restore) }.buttonStyle(ExperienceButtonStyle(primary:true))
                } else {
                    Button("次の要求を読む") { send(.step) }.buttonStyle(ExperienceButtonStyle(primary:true)).keyboardShortcut(.space,modifiers:[])
                    if model.stage==2 || model.stage==4 { Button("選んだ品を一時退避") { send(.evict) }.buttonStyle(ExperienceButtonStyle()) }
                    if model.stage==3 { Button("選んだ品を閉じる") { send(.close) }.buttonStyle(ExperienceButtonStyle()) }
                }
                Button("もう一度") { send(.restart) }.buttonStyle(ExperienceButtonStyle())
                if model.stage==4 { ForEach([3,6],id:\.self) { n in Button("RAM \(n)枠") { send(.capacity(n)) }.buttonStyle(ExperienceButtonStyle(primary:model.ramCapacity==n)) } }
            }.offset(x:245,y:428)
            MemoryObservationLine(title:"比較",lines:model.trials.suffix(3).map { "RAM\($0.capacity) / \($0.method) / \($0.ticks)拍" }).frame(width:1090,height:40).offset(x:25,y:500)
        }.frame(width:1160,height:550,alignment:.topLeading)
    }
}

struct MemoryStorageExperienceView:View {
    @StateObject private var store=ExperienceStore(MemoryStorageModel(stage:1))
    var onExit:()->Void
    var body:some View { ExperienceScreen(store:store,onExit:onExit) { model,send in MemoryStorageApparatus(model:model,send:send) } }
}
struct MemoryStorageApparatus:View {
    let model:MemoryStorageModel;let send:(MemoryStorageModel.Action)->Void
    @State private var playing=false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    private let clock=Timer.publish(every:0.6,on:.main,in:.common).autoconnect()
    private var parcelLabel:String { model.index<model.sizes.count ? "\(model.sizes[model.index])MB" : "完了" }
    private var parcelColor:Color { [ExperienceStyle.cyan,ExperienceStyle.purple,ExperienceStyle.amber,ExperienceStyle.cyan][model.index%4] }
    private var transferProgress:Double { guard model.phase=="transfer",model.index<model.sizes.count else { return 0 };return 1-Double(model.phaseRemaining)/Double(model.sizes[model.index]*8/model.rate) }
    var body:some View {
        ZStack(alignment:.topLeading) {
            ExperienceDevice(title:"保存庫",subtitle:"\(model.usedMB) / \(model.capacityMB) MB") {
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12) {
                    ForEach(0..<(model.stage==1 ? model.capacityMB/4:4),id:\.self) { i in MemoryParcel(label: model.stage==1 && i>1 && !model.finished ? "空き4MB" : "4MB",symbol:["photo","music.note","play.rectangle","doc.text"][i],color:[ExperienceStyle.cyan,ExperienceStyle.purple,ExperienceStyle.amber,ExperienceStyle.cyan][i]).frame(height:88).opacity(model.stage==1 && i>1 && !model.finished ? 0.35:1) }
                }
            }.frame(width:310,height:300).offset(x:20,y:25)
            ExperienceDevice(title: model.phase=="setup" ? "準備中" : "搬送口",subtitle:"準備 \(MemoryStorageModel.time(model.latency))秒 / 件",active:model.phase=="setup") {
                VStack(spacing:9) {
                    MemoryLoadingPort(label:parcelLabel,preparing:model.phase=="setup",hasParcel:!model.finished && model.phase != "transfer",color:parcelColor)
                    HStack(spacing:7) { ForEach(0..<model.sizes.count,id:\.self) { i in Circle().fill(i<model.index ? ExperienceStyle.cyan : ExperienceStyle.ink.opacity(0.15)).frame(width:11,height:11) } }
                }
            }.frame(width:260,height:235).offset(x:360,y:25)
            VStack(spacing:2) {
                MemoryConveyor(phase:model.phase,parcel:parcelLabel,progress:transferProgress,color:parcelColor)
                    .animation(reducedMotion ? nil : .linear(duration:0.45),value:transferProgress)
                Text("\(model.rate) MB/s").font(.system(size:20,weight:.bold)).foregroundStyle(.white)
            }.frame(width:195,height:130).offset(x:630,y:83)
            ExperienceDevice(title:"受取台",subtitle:"\(model.delivered) / \(model.totalMB) MB",active:model.delivered>0) {
                VStack(spacing:8) {
                    ZStack {
                        RoundedRectangle(cornerRadius:7).fill(ExperienceStyle.dark).overlay(RoundedRectangle(cornerRadius:7).stroke(.gray,lineWidth:3))
                        if model.index>0 {
                            HStack(spacing:6) { ForEach(max(0,model.index-3)..<model.index,id:\.self) { i in
                                MemoryParcel(label:"\(model.sizes[i])MB",symbol:["photo","music.note","play.rectangle","doc.text"][i%4],color:[ExperienceStyle.cyan,ExperienceStyle.purple,ExperienceStyle.amber,ExperienceStyle.cyan][i%4]).frame(width:60,height:75)
                            } }
                        } else { Image(systemName:"tray.and.arrow.down").font(.system(size:35)).foregroundStyle(.white.opacity(0.35)) }
                    }.frame(height:97)
                    HStack { Text("\(model.secondsText) 秒").font(.system(size:21,weight:.bold));Spacer();Text("\(model.index) / \(model.sizes.count) 件").font(.system(size:14,weight:.bold)) }.foregroundStyle(ExperienceStyle.ink)
                    ProgressView(value:Double(model.delivered),total:Double(max(1,model.totalMB))).tint(ExperienceStyle.cyan).frame(height:6)
                }
            }.frame(width:280,height:260).offset(x:850,y:25)
            HStack(spacing:10) {
                if model.stage<=2 { ForEach(model.stage==1 ? [12,16] : [16,32],id:\.self) { n in Button("棚 \(n)MB") { playing=false;send(.capacity(n)) }.buttonStyle(ExperienceButtonStyle(primary:model.capacityMB==n)) } }
                if [1,3,5].contains(model.stage) { ForEach([4,8],id:\.self) { n in Button("\(n)MB/s") { playing=false;send(.rate(n)) }.buttonStyle(ExperienceButtonStyle(primary:model.rate==n)) } }
                if model.stage==4 {
                    Button("4件 × 4MB") { playing=false;send(.bundle(false)) }.buttonStyle(ExperienceButtonStyle(primary:model.sizes.count==4))
                    Button("1件 × 16MB") { playing=false;send(.bundle(true)) }.buttonStyle(ExperienceButtonStyle(primary:model.sizes.count==1))
                }
                if model.stage==5 {
                    Button("準備 0.5秒") { playing=false;send(.latency(4)) }.buttonStyle(ExperienceButtonStyle(primary:model.latency==4))
                    Button("大きい1件") { playing=false;send(.scenario(0)) }.buttonStyle(ExperienceButtonStyle(primary:model.scenario==0))
                    Button("小さい8件") { playing=false;send(.scenario(1)) }.buttonStyle(ExperienceButtonStyle(primary:model.scenario==1))
                }
            }.offset(x:model.stage==5 ? 250:360,y:325)
            HStack(spacing:12) {
                Button("1秒進める") { playing=false;send(.step) }.buttonStyle(ExperienceButtonStyle(primary:true)).keyboardShortcut(.space,modifiers:[])
                Button(playing ? "一時停止" : "再生") { playing.toggle() }.buttonStyle(ExperienceButtonStyle())
                Button("同じ条件でもう一度") { playing=false;send(.restart) }.buttonStyle(ExperienceButtonStyle())
            }.offset(x:360,y:407)
            MemoryObservationLine(title:"比べた結果",lines:model.trials.suffix(3).map { "\($0.sizes.count)件 / \($0.rate)MB/s / 準備\(MemoryStorageModel.time($0.latency))秒 → \(MemoryStorageModel.time($0.eighths))秒" }).frame(width:1090,height:50).offset(x:30,y:486)
        }.frame(width:1160,height:550,alignment:.topLeading)
        .onReceive(clock) { _ in if playing { if model.finished || (model.isWriting && model.usedMB+model.totalMB>model.capacityMB) { playing=false } else { send(.step) } } }
        .onChange(of:scenePhase) { if $0 != .active { playing=false } }
        .onChange(of:model.stage) { _ in playing=false }
        .onDisappear { playing=false }
    }
}

struct MemoryOrderStrip:View {
    let items:[String];let index:Int
    var body:some View {
        HStack(spacing:12) {
            Text("要求").font(.system(size:15,weight:.bold)).foregroundStyle(.white.opacity(0.65))
            ForEach(items.indices,id:\.self) { i in
                VStack(spacing:4) { Text(items[i]).font(.system(size:25,weight:.bold));Image(systemName:i<index ? "checkmark.circle.fill" : i==index ? "arrowtriangle.up.fill" : "circle").font(.system(size:13)).foregroundStyle(i<=index ? ExperienceStyle.cyan : ExperienceStyle.muted) }
                    .frame(width:63,height:64).foregroundStyle(ExperienceStyle.ink).background(i==index ? ExperienceStyle.cyan.opacity(0.75) : ExperienceStyle.paper,in:WorkshopChamfer(corner:6))
            }
            Spacer(minLength:0)
        }.padding(6)
    }
}
struct MemoryObservationLine:View {
    let title:String;let lines:[String]
    var body:some View { HStack(alignment:.top,spacing:12) { Text(title).font(.system(size:14,weight:.bold)).foregroundStyle(ExperienceStyle.cyan);Text(lines.isEmpty ? "同じ条件から比べた結果が、ここに残ります。" : lines.joined(separator:"　|　")).font(.system(size:14,weight:.medium)).foregroundStyle(.white.opacity(0.85));Spacer(minLength:0) } }
}
