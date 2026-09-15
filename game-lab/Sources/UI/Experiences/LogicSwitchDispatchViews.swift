import SwiftUI

struct LogicTinySwitchView: View {
    var onExit: () -> Void
    @StateObject private var store = ExperienceStore(LogicTinySwitchModel(stage: 1))
    var body: some View { ExperienceScreen(store: store,onExit: onExit) { model,send in LogicTinySwitchApparatus(model: model,send: send) } }
}

struct LogicTinySwitchApparatus: View {
    let model: LogicTinySwitchModel
    let send: (LogicTinySwitchModel.Action) -> Void
    var body: some View {
        VStack(spacing: 15) {
            ZStack {
                Canvas { context,size in
                    let bright = Color.cyan, off = Color.gray.opacity(0.6)
                    func wire(_ points: [CGPoint], _ active: Bool, dashed: Bool = false) {
                        var path = Path(); path.addLines(points)
                        context.stroke(path,with: .color(.black.opacity(0.7)),style: StrokeStyle(lineWidth: dashed ? 4 : 13,lineCap: .round,lineJoin: .round))
                        context.stroke(path,with: .color(dashed ? Color.purple : active ? bright : off),style: StrokeStyle(lineWidth: dashed ? 3 : 7,lineCap: .round,lineJoin: .round,dash: dashed ? [6,5] : []))
                    }
                    let p = CGPoint(x: 132,y: 155), l = CGPoint(x: 860,y: 155)
                    let first = position(0), firstY = first.y + 38
                    if model.switchCount == 1 {
                        wire([p,CGPoint(x: 260,y: 155),CGPoint(x: 260,y: firstY),CGPoint(x: first.x-92,y: firstY)],model.powered)
                        wire([CGPoint(x: first.x+92,y: firstY),CGPoint(x: 800,y: firstY),CGPoint(x: 800,y: 155),l],model.output == 1)
                    } else if model.layout == .series {
                        let second = position(1)
                        wire([p,CGPoint(x: 250,y: 155),CGPoint(x: 250,y: firstY),CGPoint(x: first.x-92,y: firstY)],model.powered)
                        wire([CGPoint(x: first.x+92,y: firstY),CGPoint(x: second.x-92,y: firstY)],model.powered && model.isClosed(0))
                        wire([CGPoint(x: second.x+92,y: firstY),CGPoint(x: 825,y: firstY),CGPoint(x: 825,y: 155),l],model.output == 1)
                    } else {
                        for i in 0..<2 {
                            let at = position(i), y = at.y + 38
                            wire([p,CGPoint(x: 225,y: 155),CGPoint(x: 225,y: y),CGPoint(x: at.x-92,y: y)],model.powered)
                            wire([CGPoint(x: at.x+92,y: y),CGPoint(x: 785,y: y),CGPoint(x: 785,y: 155),l],model.powered && model.isClosed(i))
                        }
                    }
                    wire([CGPoint(x: 929,y: 214),CGPoint(x: 929,y: 340),CGPoint(x: 67,y: 340),CGPoint(x: 67,y: 214)],model.output == 1)
                }.allowsHitTesting(false)
                ExperienceDevice(title: "電源",subtitle: model.powered ? "ON" : "OFF",active: model.powered) {
                    Button { send(.power) } label: { Image(systemName: "bolt.fill").font(.system(size: 38)).frame(width: 45,height: 50) }.buttonStyle(LogicCompactButtonStyle(primary: model.powered))
                }.frame(width: 130,height: 140).position(x: 70,y: 155)
                ForEach(0..<model.switchCount,id: \.self) { i in
                    switchModule(i).position(position(i))
                }
                ExperienceDevice(title: "ランプ",subtitle: model.powered ? model.output.map { $0 == 1 ? "点灯" : "消灯" } ?? "未接続" : "電源OFF",active: model.output == 1) {
                    HStack { Image(systemName: model.output == 1 ? "lightbulb.fill" : "lightbulb").font(.system(size: 38)).foregroundStyle(model.output == 1 ? Color.cyan : Color.gray); Text(model.output.map(String.init) ?? "?").font(.system(size: 35,weight: .bold)) }
                }.frame(width: 145,height: 140).position(x: 930,y: 155)
                VStack(alignment: .leading,spacing: 5) {
                    Text(model.switchCount == 1 ? "A  目標  観察" : "A  B  目標  観察").font(.system(size: 14,weight: .bold,design: .monospaced))
                    ForEach(Array(model.observations.enumerated()),id: \.offset) { index,row in
                        Button { send(.replay(index)) } label: { Text(model.switchCount == 1 ? "\(row.a)    \(row.expected)    \(row.actual.map(String.init) ?? "?")" : "\(row.a)  \(row.b)    \(row.expected)    \(row.actual.map(String.init) ?? "?")").font(.system(size: 15,weight: .bold,design: .monospaced)).foregroundStyle(row.matches ? Color.cyan : Color.orange) }.buttonStyle(.plain)
                    }
                }.foregroundStyle(.white).frame(width: 135,height: 95,alignment: .topLeading).position(x: 1020,y: 280)
            }.frame(width: 1100,height: 355)
            HStack(spacing: 12) {
                Text("部品").foregroundStyle(.white).font(.headline)
                ForEach(0..<model.switchCount,id: \.self) { i in
                    Button { send(.place(i)) } label: { ExperienceChip(label: "スイッチ\(i == 0 ? "A" : "B")",symbol: "switch.2",selected: model.placed[i]) }.buttonStyle(.plain)
                        .onDrag { NSItemProvider(object: String(i) as NSString) }.accessibilityIdentifier("tiny.place.\(i)")
                }
                if model.switchCount == 2 {
                    ForEach(LogicTinySwitchModel.Layout.allCases,id: \.self) { layout in Button(layout.title) { send(.changeLayout(layout)) }.buttonStyle(LogicCompactButtonStyle(primary: model.layout == layout)) }
                }
                Spacer()
                Button { send(.record) } label: { Label("記録",systemImage: "pencil.line") }.buttonStyle(LogicCompactButtonStyle())
                Button { send(.test) } label: { Label(model.switchCount == 1 ? "2通りテスト" : "4通りテスト",systemImage: "play.fill") }.buttonStyle(LogicCompactButtonStyle(primary: true)).accessibilityIdentifier("tiny.test")
            }
            Text("紫の線 = 開閉の合図　／　太い道 = ランプへつながる経路　／　0と未接続 ? は別").font(.system(size: 15)).foregroundStyle(.white.opacity(0.65))
        }.padding(20).frame(width: 1160,height: 550)
    }
    private func position(_ i: Int) -> CGPoint {
        if model.switchCount == 1 { return CGPoint(x: 525,y: 155) }
        return model.layout == .series ? CGPoint(x: i == 0 ? 407 : 672,y: 155) : CGPoint(x: 525,y: i == 0 ? 100 : 245)
    }
    @ViewBuilder private func switchModule(_ i: Int) -> some View {
        if model.placed[i] {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button("\(i == 0 ? "A" : "B") = \(model.inputs[i])") { send(.toggle(i)) }.buttonStyle(LogicCompactButtonStyle(primary: model.inputs[i] == 1)).accessibilityIdentifier("tiny.input.\(i)")
                    Button { send(.connect(i)) } label: { Image(systemName: model.connected[i] ? "link" : "link.badge.plus") }.buttonStyle(LogicCompactButtonStyle(primary: model.connected[i])).accessibilityLabel("制御線を\(model.connected[i] ? "外す" : "つなぐ")")
                }.frame(height: 36)
                ZStack {
                    Rectangle().fill(ExperienceStyle.purple.opacity(model.connected[i] ? 1 : 0.2)).frame(width: 4,height: 16)
                    if !model.connected[i] { Image(systemName: "xmark").font(.system(size: 10,weight: .bold)).foregroundStyle(ExperienceStyle.purple) }
                }.frame(height: 16)
                ZStack {
                    WorkshopChamfer(corner: 12).fill(LinearGradient(colors: [.white,ExperienceStyle.paper],startPoint: .topLeading,endPoint: .bottomTrailing))
                    WorkshopChamfer(corner: 12).strokeBorder(model.powered && model.isClosed(i) ? ExperienceStyle.cyan : ExperienceStyle.muted,lineWidth: 3)
                    Text("\(i == 0 ? "A" : "B") · \(model.connected[i] ? model.isClosed(i) ? "通る" : "止まる" : "?")").font(.system(size: 18,weight: .bold)).foregroundStyle(ExperienceStyle.ink).offset(y: -26)
                    HStack(spacing: 8) {
                        Canvas { context,size in
                            let left = CGPoint(x: 7,y: 16), right = CGPoint(x: 62,y: 16)
                            var p = Path(); p.move(to: left); p.addLine(to: model.isClosed(i) ? right : CGPoint(x: 49,y: 6))
                            context.stroke(p,with: .color(model.isClosed(i) ? .cyan : .gray),style: StrokeStyle(lineWidth: 6,lineCap: .round))
                            for point in [left,right] { context.fill(Path(ellipseIn: CGRect(x: point.x-5,y: point.y-5,width: 10,height: 10)),with: .color(.gray)) }
                        }.frame(width: 70,height: 32)
                        Button("\(model.activeOn[i])で通る") { send(.invert(i)) }.font(.system(size: 14,weight: .bold)).buttonStyle(.bordered)
                    }.offset(y: 12)
                }.frame(width: 185,height: 92).compositingGroup().shadow(color: .black.opacity(0.3),radius: 0,y: 5)
            }.frame(width: 205,height: 144)
        } else {
            Button { send(.place(i)) } label: { VStack { Image(systemName: "plus.square.dashed").font(.largeTitle); Text("\(i == 0 ? "A" : "B")を置く").font(.headline) }.foregroundStyle(.white.opacity(0.6)).frame(width: 180,height: 115).background(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.35),style: StrokeStyle(lineWidth: 2,dash: [8]))) }.buttonStyle(.plain)
                .onDrop(of: ["public.text"],isTargeted: nil) { providers in LogicDrop.text(providers) { _ in send(.place(i)) } }
        }
    }
}

struct LogicWorkDispatchView: View {
    var onExit: () -> Void
    @StateObject private var store = ExperienceStore(LogicWorkDispatchModel(stage: 1))
    var body: some View { ExperienceScreen(store: store,onExit: onExit) { model,send in LogicWorkDispatchApparatus(model: model,send: send) } }
}

struct LogicWorkDispatchApparatus: View {
    let model: LogicWorkDispatchModel
    let send: (LogicWorkDispatchModel.Action) -> Void
    @State private var closing: Int?
    private var owners: [Int?] {
        var values: [Int?] = []
        for i in model.jobs.indices where [.ready,.paused,.waiting].contains(model.jobs[i].status) { values += Array(repeating: Optional.some(i),count: model.jobs[i].ram) }
        return values + Array(repeating: nil,count: max(0,model.capacity-values.count))
    }
    private func color(_ i: Int) -> Color { i == 0 ? .cyan : .purple }
    var body: some View {
        VStack(spacing: 17) {
            HStack(spacing: 15) {
                VStack(alignment: .leading,spacing: 6) { Text("作業場所").font(.headline); Text("\(model.used) / \(model.capacity) 枠").font(.system(size: 25,weight: .bold,design: .rounded)); Text("RAM · 置く場所").font(.system(size: 13)) }.foregroundStyle(.white).frame(width: 140)
                ramRack.frame(width: 920,height: 86)
            }.frame(height: 93)
            HStack(spacing: 20) {
                cpuStation.frame(width: 370,height: 218)
                    .onDrop(of: ["public.text"],isTargeted: nil) { providers in LogicDrop.text(providers) { raw in if let i = Int(raw) { send(.select(i)) } } }
                LogicSignalCable(active: selectedReady,color: selectedColor).frame(width: 35,height: 35)
                VStack(alignment: .leading,spacing: 8) {
                    HStack { Label("仕事ラック",systemImage: "tray.2.fill");Spacer();Text("選んで、CPUへ渡す").font(.system(size: 13)) }.font(.system(size: 16,weight: .bold)).foregroundStyle(.white.opacity(0.85))
                    ForEach(model.jobs.indices,id: \.self) { i in jobRow(i) }
                    if model.jobs.count == 1 { Text("載せた仕事は、1コマずつ計算が進むよ。").font(.system(size: 14)).foregroundStyle(.white.opacity(0.55)).padding(.top,8) }
                    Spacer(minLength: 0)
                }.padding(.horizontal,19).padding(.vertical,17).frame(width: 660,height: 230,alignment: .topLeading)
                    .background(LogicMachineHousing())
            }.frame(height: 230)
            HStack(spacing: 10) {
                VStack(alignment: .leading,spacing: 5) { Text("CPUを渡す順").font(.headline); Text("\(model.tick) コマ済").font(.system(size: 20,weight: .bold)) }.foregroundStyle(.white).frame(width: 140)
                ForEach(0..<max(6,min(10,model.tick+1)),id: \.self) { index in
                    VStack(spacing: 5) {
                        Text(String(index+1)).font(.system(size: 12,weight: .bold)).foregroundStyle(.white.opacity(0.6))
                        ZStack {
                            RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.3)).overlay(RoundedRectangle(cornerRadius: 8).stroke(index == model.tick ? Color.cyan : .white.opacity(0.2),lineWidth: 2))
                            if model.timeline.indices.contains(index) {
                                if let i = model.timeline[index] { Image(systemName: model.jobs[i].symbol).font(.title2).foregroundStyle(color(i)) }
                                else { Image(systemName: "clock").foregroundStyle(.gray) }
                            } else if index == model.tick, let selected = model.selected, model.jobs[selected].status == .ready { Image(systemName: model.jobs[selected].symbol).font(.title2).foregroundStyle(color(selected).opacity(0.6)) }
                        }.frame(width: 68,height: 48)
                    }
                }
                Spacer()
            }
            HStack(spacing: 12) {
                ExperiencePlaybackControls(canStep: !model.allDone && model.tick < 60 && (model.jobs.contains { $0.status == .ready || $0.status == .waiting }), step: { send(.step) })
                    .id("dispatch-\(model.stage)-\(model.capacity)-\(model.selected ?? -1)-\(model.jobs.map { $0.status.rawValue }.joined())").accessibilityIdentifier("dispatch.step")
                Button("最初から") { send(.rewind) }.buttonStyle(LogicCompactButtonStyle())
                Button("比較を記録") { send(.recordComparison) }.buttonStyle(LogicCompactButtonStyle()).disabled(!model.allDone)
                Spacer()
                if model.stage == 5 { ForEach([4,6,8],id: \.self) { size in Button("机\(size)枠") { send(.capacity(size)) }.buttonStyle(LogicCompactButtonStyle(primary: model.capacity == size)) } }
            }
        }.padding(20).frame(width: 1160,height: 550)
        .alert("途中の計算を捨てて閉じますか？",isPresented: Binding(get: { closing != nil },set: { if !$0 { closing = nil } })) {
            Button("閉じる",role: .destructive) { if let closing { send(.close(closing)) }; closing = nil }
            Button("続ける",role: .cancel) { closing = nil }
        } message: { Text("作業場所は空きます。もう一度載せると、この仕事は最初からになります。") }
    }
    private var ramRack: some View {
        GeometryReader { proxy in
            let pitch=proxy.size.width/CGFloat(model.capacity)
            ZStack(alignment: .topLeading) {
                ForEach(0..<model.capacity,id: \.self) { slot in
                    VStack(spacing: 4) {
                        Text(String(slot+1)).font(.system(size: 11,weight: .bold,design: .monospaced)).foregroundStyle(.white.opacity(0.65))
                        ZStack {
                            WorkshopChamfer(corner: 8).fill(Color.black.opacity(0.3))
                            WorkshopChamfer(corner: 8).strokeBorder(.white.opacity(0.17),lineWidth: 2)
                            Text("空き").font(.system(size: 12)).foregroundStyle(.white.opacity(0.35))
                        }.frame(height: 64)
                    }.frame(width: pitch-6).offset(x: CGFloat(slot)*pitch)
                        .onDrop(of: ["public.text"],isTargeted: nil) { providers in LogicDrop.text(providers) { raw in if let i=Int(raw) { send(.admit(i)) } } }
                }
                ForEach(model.jobs.indices,id: \.self) { i in
                    let job=model.jobs[i]
                    if let first=owners.firstIndex(where: { $0 == i }) {
                        Button { send(.select(i)) } label: {
                            ZStack {
                                WorkshopChamfer(corner: 8).fill(LinearGradient(colors: [color(i).opacity(0.55),color(i),color(i).opacity(0.7)],startPoint: .top,endPoint: .bottom))
                                WorkshopChamfer(corner: 8).strokeBorder(.black.opacity(0.8),lineWidth: 3)
                                WorkshopChamfer(corner: 6,insetAmount: 5).strokeBorder(.white.opacity(0.6),lineWidth: 1)
                                HStack(spacing: 0) { ForEach(0..<job.ram,id: \.self) { segment in Rectangle().fill(.clear).frame(width: pitch).overlay(alignment: .trailing) { if segment < job.ram-1 { Rectangle().fill(.black.opacity(0.22)).frame(width: 2) } } } }.clipped()
                                HStack(spacing: 9) { Image(systemName: job.symbol).font(.system(size: 28));Text(job.name).font(.system(size: 21,weight: .bold));Text("\(job.ram)枠").font(.system(size: 13,weight: .bold)) }.foregroundStyle(ExperienceStyle.ink)
                            }.frame(width: CGFloat(job.ram)*pitch-6,height: 64)
                                .overlay(WorkshopChamfer(corner: 8).strokeBorder(model.selected == i ? Color.white : .clear,lineWidth: 3))
                        }.buttonStyle(.plain).offset(x: CGFloat(first)*pitch,y: 18)
                            .onDrag { NSItemProvider(object: String(i) as NSString) }
                            .accessibilityLabel("\(job.name)、\(job.ram)枠を使用")
                    }
                }
            }
        }
    }
    private var selectedReady: Bool { !model.allDone && model.selected.map { model.jobs[$0].status == .ready } == true }
    private var selectedColor: Color { model.selected.map(color) ?? .cyan }
    private var cpuCaption: String {
        if model.allDone { return "すべて完了" }
        guard let selected = model.selected else { return "仕事を選ぼう" }
        switch model.jobs[selected].status {
        case .ready: return "次の1コマ：\(model.jobs[selected].name)"
        case .waiting: return "通信の返事を待っている"
        case .paused: return "仕事が停止中"
        case .pending: return "まず作業場所に載せよう"
        case .completed: return "次の仕事を選ぼう"
        }
    }
    private var cpuStation: some View {
        ZStack {
            LogicMachineHousing(accent: selectedColor,active: selectedReady)
            VStack(spacing: 9) {
                Text("CPU · 計算する装置").font(.system(size: 20,weight: .bold)).foregroundStyle(.white)
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.35)).overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.2),lineWidth: 2))
                    HStack(spacing: 15) {
                        Image(systemName: model.allDone ? "checkmark.circle.fill" : selectedReady ? model.jobs[model.selected!].symbol : model.jobs.contains(where: { $0.status == .waiting }) ? "clock" : "cpu")
                            .font(.system(size: 42,weight: .medium)).foregroundStyle(model.allDone ? Color.green : selectedReady ? selectedColor : Color.gray)
                        VStack(alignment: .leading,spacing: 8) {
                            Text(selectedReady ? "次の 1 コマ" : model.allDone ? "計算終了" : "待機中").font(.system(size: 15,weight: .bold)).foregroundStyle(.white.opacity(0.75))
                            HStack(spacing: 5) { ForEach(0..<3,id: \.self) { index in Image(systemName: "chevron.right").foregroundStyle(selectedReady ? selectedColor.opacity(Double(index + 1) / 3) : .gray.opacity(0.35)) } }.font(.system(size: 23,weight: .black))
                        }
                    }.padding(.horizontal,30)
                }.frame(height: 85).padding(.horizontal,33)
                Text(cpuCaption).font(.system(size: 16,weight: .bold)).foregroundStyle(selectedReady ? selectedColor : Color.white.opacity(0.85))
                Text("1 台 · 同時に 1 つの仕事").font(.system(size: 12,weight: .medium)).foregroundStyle(.white.opacity(0.55))
            }.padding(.vertical,19)
            HStack { hazardColumn;Spacer();hazardColumn }.padding(.horizontal,15)
        }
    }
    private var hazardColumn: some View {
        VStack(spacing: 6) {
            Capsule().fill(selectedReady ? Color.orange : .gray).frame(width: 6,height: 40)
            Canvas { context,size in
                context.fill(Path(roundedRect: CGRect(origin: .zero,size: size),cornerRadius: 2),with: .color(Color(red: 0.77,green: 0.77,blue: 0.70)))
                for y in stride(from: 0.0,to: size.height,by: 16) {
                    var p=Path();p.addLines([CGPoint(x: 0,y: y+7),CGPoint(x: size.width,y: y),CGPoint(x: size.width,y: y+7),CGPoint(x: 0,y: y+14)]);p.closeSubpath()
                    context.fill(p,with: .color(Color(red: 0.29,green: 0.30,blue: 0.29)))
                }
            }.frame(width: 14,height: 75).clipShape(RoundedRectangle(cornerRadius: 2))
            Capsule().fill(selectedReady ? Color.orange : .gray).frame(width: 6,height: 25)
        }.allowsHitTesting(false)
    }
    private func jobRow(_ i: Int) -> some View {
        let job=model.jobs[i]
        return HStack(spacing: 12) {
            VStack(spacing: 3) {
                Image(systemName: job.symbol).font(.system(size: 25,weight: .medium))
                Text(job.name).font(.system(size: 12,weight: .bold))
            }.foregroundStyle(ExperienceStyle.ink).frame(width: 58,height: 58)
                .background(WorkshopChamfer(corner: 8).fill(color(i).gradient))
                .overlay(WorkshopChamfer(corner: 8).strokeBorder(.white.opacity(0.55),lineWidth: 2))
                .onDrag { NSItemProvider(object: String(i) as NSString) }
            VStack(alignment: .leading,spacing: 7) {
                HStack(spacing: 7) {
                    Text("\(job.done) / \(job.work)").font(.system(size: 21,weight: .bold,design: .monospaced))
                    ForEach(0..<job.work,id: \.self) { step in Circle().fill(step < job.done ? color(i) : Color.white.opacity(0.07)).frame(width: 10,height: 10).overlay(Circle().stroke(.white.opacity(0.2),lineWidth: 1)) }
                    Spacer(minLength: 0)
                }
                Label(job.status == .waiting ? "I/O待ち · あと\(job.ioRemaining)コマ" : "\(status(job)) · 場所\(job.ram)枠",systemImage: job.status == .waiting ? "clock.fill" : job.status == .completed ? "checkmark.circle" : "square.grid.3x1.below.line.grid.1x2")
                    .font(.system(size: 12,weight: .semibold)).foregroundStyle(job.status == .waiting ? Color.orange : .white.opacity(0.6))
            }.foregroundStyle(.white).frame(width: 194)
            Spacer(minLength: 0)
            HStack(spacing: 7) {
                Button(job.status == .pending ? "載せる" : "CPUへ") { send(job.status == .pending ? .admit(i) : .select(i)) }
                    .buttonStyle(LogicCompactButtonStyle(primary: model.selected == i && job.status == .ready))
                    .disabled(job.status == .completed || job.status == .waiting || job.status == .paused)
                    .accessibilityIdentifier("dispatch.job.\(i)")
                if job.status == .ready || job.status == .paused { Button(job.status == .paused ? "再開" : "停止") { send(.pause(i)) }.buttonStyle(LogicCompactButtonStyle()) }
                if [.ready,.waiting,.paused].contains(job.status) { Button { closing = i } label: { Image(systemName: "xmark").font(.system(size: 13,weight: .bold)) }.buttonStyle(LogicCompactButtonStyle()).accessibilityLabel("仕事を閉じて場所を空ける") }
            }.frame(minWidth: 205,alignment: .trailing)
        }.padding(.horizontal,10).padding(.vertical,7).frame(height: 77)
            .background(WorkshopChamfer(corner: 9).fill(Color.black.opacity(model.selected == i ? 0.28 : 0.12)))
            .overlay(WorkshopChamfer(corner: 9).strokeBorder(model.selected == i ? color(i) : Color.white.opacity(0.13),lineWidth: model.selected == i ? 2 : 1))
    }
    private func status(_ job: LogicWorkDispatchModel.Job) -> String {
        switch job.status { case .pending: return "待機"; case .ready: return "準備OK"; case .paused: return "停止中"; case .waiting: return "通信待ち \(job.ioRemaining)"; case .completed: return "完了" }
    }
}
