import SwiftUI
import AppKit

struct MemoryPCDayExperienceView:View {
    @StateObject private var store=ExperienceStore(MemoryPCDayModel(stage:1))
    var onExit:()->Void
    var body:some View { ExperienceScreen(store:store,onExit:onExit) { model,send in MemoryPCDayApparatus(model:model,send:send) } }
}
struct MemoryPCDayApparatus:View {
    let model:MemoryPCDayModel;let send:(MemoryPCDayModel.Action)->Void
    @State private var selectedSlot:Int?=nil
    var body:some View {
        ZStack(alignment:.topLeading) {
            Canvas { context,_ in
                var control=Path();control.move(to:.init(x:160,y:100));control.addLine(to:.init(x:215,y:100));control.move(to:.init(x:400,y:100));control.addLine(to:.init(x:470,y:100))
                context.stroke(control,with:.color(model.remaining>0 ? ExperienceStyle.cyan:.gray),style:.init(lineWidth:5,dash:[7,6]))
                var output=Path();output.move(to:.init(x:730,y:120));output.addLine(to:.init(x:870,y:120))
                context.stroke(output,with:.color(model.display != nil ? ExperienceStyle.cyan:.gray),lineWidth:8)
                var storage=Path();storage.move(to:.init(x:600,y:225));storage.addLine(to:.init(x:600,y:285));storage.addLine(to:.init(x:425,y:285))
                let transferring=model.remaining>0 && model.current.map { [MemoryPCCommand.open,.save,.saveAs].contains($0) } == true
                if transferring { context.stroke(storage,with:.color(ExperienceStyle.cyan),lineWidth:8) }
                else { context.stroke(storage,with:.color(.gray),style:.init(lineWidth:5,dash:[7,5])) }
            }.allowsHitTesting(false)
            ExperienceDevice(title:"入力") { Image(systemName:"hand.tap.fill").font(.system(size:40)).foregroundStyle(ExperienceStyle.cyan) }.frame(width:140,height:145).offset(x:20,y:30)
            ExperienceDevice(title:"CPU",subtitle:"計算・制御",active:model.remaining>0) {
                Image(systemName:"cpu").font(.system(size:45)).foregroundStyle(model.remaining>0 ? ExperienceStyle.cyan:ExperienceStyle.ink)
            }.frame(width:185,height:165).offset(x:215,y:20)
            ExperienceDevice(title:"RAM 作業台",subtitle:model.ram.map { "作業 v\($0)" } ?? "写真なし",active:model.ram != nil) {
                MemoryPhoto(version:model.ram).frame(width:205,height:110)
            }.frame(width:260,height:230).offset(x:470,y:20)
            ExperienceDevice(title:"ディスプレイ",subtitle:model.display.map { "表示 v\($0)" } ?? "表示なし",active:model.display != nil) {
                MemoryPhoto(version:model.display).frame(width:205,height:110)
            }.frame(width:260,height:230).offset(x:870,y:20)
            ExperienceDevice(title:"SSD 保存庫",subtitle:"") {
                HStack(spacing:10) {
                    ForEach(model.storage.keys.sorted(),id:\.self) { id in
                        Button { send(.source(id)) } label: {
                            HStack(spacing:7) { MemoryPhoto(version:model.storage[id]).frame(width:70,height:48);Text("\(id=="original" ? "元写真" : "別名")\nv\(model.storage[id] ?? 0)").font(.system(size:13,weight:.bold)) }
                                .padding(4).overlay(RoundedRectangle(cornerRadius:5).stroke(model.selectedSource==id ? ExperienceStyle.cyan:.clear,lineWidth:2))
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(width:model.stage==5 ? 360:215,height:125).offset(x:model.stage==5 ? 60:210,y:200)
            Text("写真データ").font(.system(size:13,weight:.medium)).foregroundStyle(.white.opacity(0.7)).offset(x:759,y:141)
            if model.stage==3 && !model.rebooted && model.powered {
                VStack(alignment:.leading,spacing:7) {
                    Text("課題の開始時点で済んでいる操作 · 5拍")
                        .font(.system(size:12,weight:.medium)).foregroundStyle(.white.opacity(0.7))
                    HStack(spacing:8) {
                        ForEach([MemoryPCCommand.open,.edit,.display]) { command in
                            HStack(spacing:6) {
                                Image(systemName:command.icon)
                                Text(command.title)
                                Image(systemName:"checkmark.circle.fill").foregroundStyle(ExperienceStyle.cyan)
                            }.font(.system(size:14,weight:.bold)).foregroundStyle(ExperienceStyle.ink)
                                .padding(.horizontal,11).frame(height:30)
                                .background(ExperienceStyle.paper,in:WorkshopChamfer(corner:5))
                        }
                        Image(systemName:"arrow.right").foregroundStyle(ExperienceStyle.cyan)
                        Text(model.current?.title ?? "電源を入れ直そう").font(.system(size:15,weight:.bold)).foregroundStyle(ExperienceStyle.cyan)
                    }
                }.offset(x:470,y:263)
            } else {
                Text(model.powered ? "\(model.current?.title ?? "次の操作を置こう")  ·  \(model.ticks)拍" : "電源 OFF")
                    .font(.system(size:18,weight:.bold)).foregroundStyle(ExperienceStyle.cyan).offset(x:650,y:285)
            }

            HStack(spacing:9) {
                ForEach(0..<6,id:\.self) { i in
                    Button { selectedSlot=i<model.program.count ? i:nil } label: {
                        VStack(spacing:6) {
                            if i<model.program.count {
                                Image(systemName:model.program[i].icon).font(.system(size:24))
                                Text(model.program[i].title).font(.system(size:17,weight:.bold))
                                Image(systemName:i<model.pc ? "checkmark.circle.fill" : i==model.pc ? "arrowtriangle.up.fill":"circle").font(.system(size:12)).foregroundStyle(ExperienceStyle.cyan)
                            } else { Image(systemName:"plus").font(.system(size:23)).foregroundStyle(.gray);Text("操作札").font(.system(size:13)).foregroundStyle(.gray) }
                        }.frame(width:116,height:90).foregroundStyle(ExperienceStyle.ink)
                            .background(i==selectedSlot ? ExperienceStyle.cyan.opacity(0.7):ExperienceStyle.paper,in:WorkshopChamfer(corner:8))
                            .overlay(WorkshopChamfer(corner:8).strokeBorder(i==model.pc ? ExperienceStyle.cyan:ExperienceStyle.ink,lineWidth:i==model.pc ? 3:1))
                    }.buttonStyle(.plain)
                    .onDrag { NSItemProvider(object:"slot:\(i)" as NSString) }
                    .memoryDrop { value in
                        if value.hasPrefix("slot:"),let from=Int(value.dropFirst(5)) { send(.move(from,i-from)) }
                        else if let command=MemoryPCCommand(rawValue:value) { send(.append(command)) }
                    }
                }
            }.offset(x:20,y:342)
            HStack(spacing:10) {
                Button("←") { if let i=selectedSlot,i>0 { send(.move(i,-1));selectedSlot=i-1 } }.buttonStyle(ExperienceButtonStyle())
                Button("→") { if let i=selectedSlot,i<model.program.count-1 { send(.move(i,1));selectedSlot=i+1 } }.buttonStyle(ExperienceButtonStyle())
                Button("外す") { if let i=selectedSlot { send(.remove(i));selectedSlot=nil } }.buttonStyle(ExperienceButtonStyle())
            }.offset(x:800,y:359)
            HStack(spacing:9) {
                ForEach(MemoryPCCommand.allCases.filter { $0 != .saveAs || model.stage==5 }) { command in
                    Button { send(.append(command)) } label: { Label(command.title,systemImage:command.icon) }.buttonStyle(ExperienceButtonStyle()).onDrag { NSItemProvider(object:command.rawValue as NSString) }
                }
            }.offset(x:20,y:454)
            HStack(spacing:10) {
                Button("1拍実行") { send(.step) }.buttonStyle(ExperienceButtonStyle(primary:true)).keyboardShortcut(.space,modifiers:[])
                if model.stage==3 { Button(model.powered ? "電源OFF" : "電源ON") { send(.power) }.buttonStyle(ExperienceButtonStyle()) }
                else { Button("観察を記録") { send(.observe) }.buttonStyle(ExperienceButtonStyle()) }
            }.offset(x:790,y:454)
            Text("細い破線：CPUの指示　　太い実線：写真データの移動")
                .font(.system(size:13,weight:.medium)).foregroundStyle(.white.opacity(0.7)).offset(x:20,y:519)
        }.frame(width:1160,height:550,alignment:.topLeading)
    }
}

struct MemoryPhoto:View {
    let version:Int?
    var body:some View {
        ZStack(alignment:.bottomTrailing) {
            Canvas { context,size in
                context.fill(Path(CGRect(origin:.zero,size:size)),with:.linearGradient(Gradient(colors:[Color(red:0.24,green:0.56,blue:0.87),Color(red:0.75,green:0.91,blue:1)]),startPoint:.zero,endPoint:.init(x:0,y:size.height)))
                var mountain=Path();mountain.move(to:.init(x:0,y:size.height*0.8));mountain.addLine(to:.init(x:size.width*0.28,y:size.height*0.23));mountain.addLine(to:.init(x:size.width*0.52,y:size.height*0.59));mountain.addLine(to:.init(x:size.width*0.7,y:size.height*0.12));mountain.addLine(to:.init(x:size.width,y:size.height*0.75));mountain.addLine(to:.init(x:size.width,y:size.height));mountain.addLine(to:.init(x:0,y:size.height));mountain.closeSubpath()
                context.fill(mountain,with:.color(Color(red:0.2,green:0.37,blue:0.46)))
                var snow=Path();snow.move(to:.init(x:size.width*0.6,y:size.height*0.37));snow.addLine(to:.init(x:size.width*0.7,y:size.height*0.12));snow.addLine(to:.init(x:size.width*0.82,y:size.height*0.38));snow.addLine(to:.init(x:size.width*0.73,y:size.height*0.29));snow.addLine(to:.init(x:size.width*0.68,y:size.height*0.36));snow.closeSubpath();context.fill(snow,with:.color(.white))
                context.fill(Path(CGRect(x:0,y:size.height*0.82,width:size.width,height:size.height*0.18)),with:.color(ExperienceStyle.cyan.opacity(0.7)))
                if version==1 { context.fill(Path(CGRect(origin:.zero,size:size)),with:.color(.black.opacity(0.34))) }
                if version==nil { context.fill(Path(CGRect(origin:.zero,size:size)),with:.color(ExperienceStyle.dark)) }
            }
            Text(version.map { "v\($0)" } ?? "—").font(.system(size:14,weight:.bold)).padding(5).foregroundStyle(.white).background(ExperienceStyle.ink.opacity(0.8)).padding(5)
        }.clipShape(RoundedRectangle(cornerRadius:5)).overlay(RoundedRectangle(cornerRadius:5).stroke(ExperienceStyle.ink,lineWidth:4))
    }
}

struct MemoryBatteryExperienceView:View {
    @StateObject private var store=ExperienceStore(MemoryBatteryModel(stage:1))
    var onExit:()->Void
    var body:some View { ExperienceScreen(store:store,onExit:onExit) { model,send in MemoryBatteryApparatus(model:model,send:send) } }
}
struct MemoryBatteryApparatus:View {
    let model:MemoryBatteryModel;let send:(MemoryBatteryModel.Action)->Void
    @State private var playing=false
    @Environment(\.scenePhase) private var scenePhase
    private let clock=Timer.publish(every:0.7,on:.main,in:.common).autoconnect()
    private var canAdvance:Bool { model.index<6 && model.energy+model.current.supply-model.current.mode.watts>=0 }
    var body:some View {
        ZStack(alignment:.topLeading) {
            ExperienceDevice(title:"給電",subtitle:"機器へ届く電力") {
                Image(systemName:"powerplug.fill").font(.system(size:45)).foregroundStyle(ExperienceStyle.ink)
                Text("\(model.current.supply) W").font(.system(size:36,weight:.bold,design:.rounded))
            }.frame(width:250,height:235).offset(x:35,y:20)
            ExperienceSignal(active:model.current.supply>0).frame(width:480,height:22).offset(x:305,y:80)
            Text("入ってくる速さ").font(.system(size:14,weight:.bold)).foregroundStyle(.white.opacity(0.7)).offset(x:360,y:50)
            ExperienceDevice(title:"PCの消費",subtitle:model.current.mode.title) {
                Image(systemName:"desktopcomputer").font(.system(size:46)).foregroundStyle(ExperienceStyle.ink)
                Text("\(model.current.mode.watts) W").font(.system(size:36,weight:.bold,design:.rounded))
            }.frame(width:290,height:235).offset(x:830,y:20)
            ExperienceDevice(title:"バッテリー",subtitle:"残っている量 · 上限60Wh",active:true) {
                HStack(spacing:18) {
                    ZStack(alignment:.bottom) {
                        RoundedRectangle(cornerRadius:7).fill(ExperienceStyle.dark)
                        RoundedRectangle(cornerRadius:7).fill(ExperienceStyle.cyan.gradient).frame(height:CGFloat(model.energy)/360*125)
                        VStack { ForEach(0..<5,id:\.self) { _ in Rectangle().fill(.white.opacity(0.4)).frame(height:1);Spacer(minLength:0) } }.padding(8)
                    }.frame(width:62,height:125).overlay(RoundedRectangle(cornerRadius:7).stroke(ExperienceStyle.ink,lineWidth:3))
                    VStack(spacing:10) {
                        Text("\(model.energyText) Wh").font(.system(size:31,weight:.bold,design:.rounded))
                        Text("この区間 \(model.lastDelta>0 ? "+" : "")\(MemoryBatteryModel.wh(model.lastDelta)) Wh").font(.system(size:14,weight:.bold)).foregroundStyle(model.lastDelta<0 ? ExperienceStyle.coral:ExperienceStyle.muted)
                    }
                }
            }.frame(width:365,height:240).offset(x:365,y:140)
            HStack(spacing:6) {
                Image(systemName:model.current.supply>=model.current.mode.watts ? "arrow.left" : "arrow.right").font(.system(size:24,weight:.black))
                Text("\(abs(model.current.mode.watts-model.current.supply)) W").font(.system(size:19,weight:.bold))
            }.foregroundStyle(ExperienceStyle.cyan).offset(x:729,y:203)
            Text(model.current.supply>=model.current.mode.watts ? "電池へ蓄える" : "電池から補う").font(.system(size:13,weight:.medium)).foregroundStyle(.white.opacity(0.7)).offset(x:729,y:239)
            VStack(alignment:.leading,spacing:12) {
                Text("\(model.index*10) 分経過").font(.system(size:23,weight:.bold))
                Text("仕事 \(model.workText)").font(.system(size:20,weight:.bold))
                Text(model.spilled>0 ? "満充電で受け取らなかった量\n\(MemoryBatteryModel.wh(model.spilled)) Wh" : "給電中でも、\n減ることがあるかな？").font(.system(size:15,weight:.medium))
            }.foregroundStyle(.white).offset(x:35,y:282)
            if model.stage>1 {
                VStack(alignment:.leading,spacing:8) {
                    Text("\(model.selectedIndex+1)区間目の動かし方").font(.system(size:14,weight:.bold)).foregroundStyle(.white)
                    HStack(spacing:6) { ForEach(MemoryPowerMode.allCases) { mode in Button(mode.title) { playing=false;send(.mode(model.selectedIndex,mode)) }.buttonStyle(ExperienceButtonStyle(primary:model.intervals[model.selectedIndex].mode==mode)).disabled(model.selectedIndex<model.index) } }
                }.offset(x:790,y:298)
            }
            HStack(spacing:8) {
                ForEach(0..<6,id:\.self) { i in
                    Button { playing=false;send(.select(i)) } label: {
                        VStack(spacing:5) {
                            HStack(spacing:4) {
                                Image(systemName:i<model.index ? "checkmark.circle.fill" : "circle").foregroundStyle(i<model.index ? ExperienceStyle.cyan:ExperienceStyle.muted)
                                if i<model.levels.count { Text("\(MemoryBatteryModel.wh(model.levels[i]))Wh").font(.system(size:12,weight:.bold)) }
                            }
                            Text("\(i*10)〜\((i+1)*10)分").font(.system(size:13,weight:.bold))
                            Text(model.intervals[i].mode.title).font(.system(size:17,weight:.bold))
                            Text("給電\(model.intervals[i].supply)W").font(.system(size:11))
                        }.frame(width:108,height:84).foregroundStyle(ExperienceStyle.ink).background(model.selectedIndex==i ? ExperienceStyle.cyan.opacity(0.8):ExperienceStyle.paper,in:WorkshopChamfer(corner:7))
                    }.buttonStyle(.plain)
                }
            }.offset(x:20,y:395)
            HStack(spacing:8) {
                Button("10分進める") { playing=false;send(.step) }.buttonStyle(ExperienceButtonStyle(primary:true)).keyboardShortcut(.space,modifiers:[])
                Button(playing ? "停止" : "再生") { playing.toggle() }.buttonStyle(ExperienceButtonStyle()).disabled(!canAdvance)
                Button("もう一度") { playing=false;send(.restart) }.buttonStyle(ExperienceButtonStyle())
            }.offset(x:758,y:406)
            HStack(spacing:8) {
                if model.stage==2 { Button("全区間 標準") { playing=false;send(.all(.standard)) }.buttonStyle(ExperienceButtonStyle());Button("全区間 高速") { playing=false;send(.all(.fast)) }.buttonStyle(ExperienceButtonStyle()) }
                if model.stage==3 { ForEach([0,18,36],id:\.self) { w in Button("給電\(w)W") { playing=false;send(.supply(w)) }.buttonStyle(ExperienceButtonStyle(primary:model.current.supply==w)) } }
                Text(model.trials.suffix(3).map { "\(MemoryBatteryModel.wh($0.endingSixths))Wh / 仕事\($0.work)" }.joined(separator:"　|　")).font(.system(size:13,weight:.bold)).foregroundStyle(.white.opacity(0.85))
            }.offset(x:20,y:490)
        }.frame(width:1160,height:550,alignment:.topLeading)
        .onReceive(clock) { _ in if playing { if canAdvance { send(.step) } else { playing=false } } }
        .onChange(of:scenePhase) { if $0 != .active { playing=false } }
        .onChange(of:model.stage) { _ in playing=false }
        .onDisappear { playing=false }
    }
}
