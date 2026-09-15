import SwiftUI

struct CoolingExperienceView: View {
    @StateObject private var store = ExperienceStore(CoolingModel(stage: 1))
    var onExit: () -> Void
    var body: some View { ExperienceScreen(store: store, onExit: onExit) { model, send in CoolingApparatus(model: model, send: send) } }
}
struct CoolingApparatus: View {
    @Environment(\.accessibilityReduceMotion) private var reduced
    let model: CoolingModel
    let send: (CoolingModel.Action) -> Void
    private var sample: CoolingSample? { model.inspected.flatMap { model.samples.indices.contains($0) ? model.samples[$0] : nil } }
    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                ExperienceDevice(title: "計算チップ", subtitle: model.restricted ? "保護動作 · 1個ずつ" : (model.fast ? "速く · 2個ずつ" : "ゆっくり · 1個ずつ"), active: model.tick > 0) {
                    ThermalProcessor(active: model.tick > 0, restricted: model.restricted)
                        .frame(width: 150, height: 132)
                    Text("発熱 \(model.heatPerStep)").font(.system(size: 23, weight: .bold))
                }.frame(width: 206, height: 306)
                ThermalFlow(color: ExperienceStyle.coral, active: model.tick > 0, label: "熱")
                    .frame(width: 44, height: 180)
                ExperienceDevice(title: "冷却ユニット", subtitle: "フィン → 空気へ", active: model.tick > 0) {
                    ThermalFanAssembly(cooler: model.cooler, tick: model.tick, reduced: reduced)
                        .frame(width: 285, height: 146)
                    Text("放熱 \(model.cooling)").font(.system(size: 24, weight: .bold)).foregroundStyle(.teal)
                }.frame(width: 338, height: 306)
                    .onDrop(of: ["public.text"], isTargeted: nil) { providers in
                        guard let provider = providers.first else { return false }
                        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                            guard let raw = object as? String, let value = Int(raw) else { return }
                            DispatchQueue.main.async { send(.cooler(value)) }
                        }
                        return true
                    }
                ThermalFlow(color: ExperienceStyle.cyan, active: model.tick > 0, label: "空気へ")
                    .frame(width: 55, height: 180)
                ExperienceDevice(title: "熱 \(model.heat)", subtitle: "教材の熱ポイント") {
                    HStack(spacing: 7) {
                        ZStack(alignment: .bottom) {
                            Capsule().fill(ExperienceStyle.dark).frame(width: 42, height: 157)
                            Capsule().fill(LinearGradient(colors: [ExperienceStyle.coral, .orange], startPoint: .top, endPoint: .bottom)).frame(width: 30, height: max(3,CGFloat(min(24,model.heat))/24*145)).padding(.bottom, 6)
                            Rectangle().fill(.white).frame(width: 47, height: 2).offset(y: -102)
                        }.animation(reduced ? nil : .easeOut(duration: 0.25), value: model.heat)
                        VStack(alignment: .leading) { Text("24"); Spacer(); Text("16").foregroundStyle(ExperienceStyle.coral); Spacer(); Text("0") }
                            .font(.system(size: 12, weight: .bold, design: .monospaced)).frame(height: 150)
                    }
                }.frame(width: 151, height: 306)
                VStack(alignment: .leading, spacing: 12) {
                    Text("完成した作品").font(.system(size: 16, weight: .bold))
                    HStack(alignment: .lastTextBaseline, spacing: 5) { Text("\(model.work)").font(.system(size: 44, weight: .bold, design: .rounded)); Text("個").font(.headline) }
                    HStack(spacing: 4) { ForEach(0..<min(4, model.work), id: \.self) { _ in
                        Image(systemName: "cube.fill").font(.system(size: 24)).foregroundStyle(ExperienceStyle.cyan)
                    } }.frame(height: 28)
                    Label("音 \(model.noise)", systemImage: "speaker.wave.2").font(.system(size: 20, weight: .semibold))
                    if let sample { Text("観察 \(sample.tick)刻み目\n熱 \(sample.heat) · 完成 \(sample.work)").font(.system(size: 14)) }
                }.foregroundStyle(.white).frame(width: 146, alignment: .leading)
            }
            HStack(spacing: 10) {
                Text("条件").foregroundStyle(.white).font(.headline)
                if model.stage == 1 {
                    Button("ゆっくり") { send(.fast(false)) }.buttonStyle(ExperienceButtonStyle(primary: !model.fast))
                    Button("速く") { send(.fast(true)) }.buttonStyle(ExperienceButtonStyle(primary: model.fast))
                } else if model.stage == 4 {
                    Button("通常の周囲") { send(.warm(false)) }.buttonStyle(ExperienceButtonStyle(primary: !model.warm))
                    Button("暖かい周囲") { send(.warm(true)) }.buttonStyle(ExperienceButtonStyle(primary: model.warm))
                } else {
                    ForEach(model.stage == 2 ? [3,5] : [1,3,5], id: \.self) { c in
                        Button { send(.cooler(c)) } label: { Label(c == 1 ? "フィン 1" : c == 3 ? "静音 3" : "強力 5", systemImage: c == 1 ? "line.3.horizontal" : "fanblades") }
                            .buttonStyle(ExperienceButtonStyle(primary: model.cooler == c))
                            .onDrag { NSItemProvider(object: String(c) as NSString) }
                    }
                }
                if model.stage == 5 {
                    Button("4刻み / 8個") { send(.length(4)) }.buttonStyle(ExperienceButtonStyle(primary: model.length == 4))
                    Button("12刻み / 24個") { send(.length(12)) }.buttonStyle(ExperienceButtonStyle(primary: model.length == 12))
                }
                Spacer()
            }
            HStack(spacing: 8) {
                Text("熱の記録").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                ForEach(Array(model.samples.enumerated()), id: \.offset) { index, s in
                    Button { send(.inspect(index)) } label: {
                        VStack(spacing: 4) { Rectangle().fill(s.restricted ? ExperienceStyle.amber : ExperienceStyle.coral).frame(width: 18, height: max(2,CGFloat(s.heat)*1.5)); Text("\(s.tick)").font(.system(size: 11)) }
                            .frame(width: 22, height: 48, alignment: .bottom)
                    }.buttonStyle(.plain).foregroundStyle(.white).help("\(s.tick)刻み：熱\(s.heat)、完成\(s.work)")
                }
                Spacer()
                ExperiencePlaybackControls(canStep: model.canStep) { send(.step) }
                    .id("\(model.cooler)-\(model.fast)-\(model.warm)-\(model.length)")
            }.frame(height: 55)
            HStack { Text("比較：" + model.runs.suffix(3).map { "\($0.fast ? "速く" : "ゆっくり")・放熱\($0.cooler) \($0.warm ? "暖" : "通常") → \($0.sample.work)個 / 熱\($0.sample.heat) / 音\($0.sample.noise)" }.joined(separator: "　｜　")).font(.system(size: 13)).foregroundStyle(.white.opacity(0.8)); Spacer() }
        }.padding(20).frame(width: 1160, height: 550)
    }
}

struct BottleneckExperienceView: View {
    @StateObject private var store = ExperienceStore(BottleneckModel(stage: 1))
    var onExit: () -> Void
    var body: some View { ExperienceScreen(store: store, onExit: onExit) { model, send in BottleneckApparatus(model: model, send: send) } }
}
struct BottleneckApparatus: View {
    @State private var runEpoch = 0
    let model: BottleneckModel
    let send: (BottleneckModel.Action) -> Void
    var body: some View {
        VStack(spacing: 17) {
            HStack(spacing: 10) {
                machine("読み込む", symbol: "tray.and.arrow.down", rate: model.config.read, count: model.unread, color: ExperienceStyle.purple, note: "読み込み前")
                ExperienceSignal(active: model.q1 > 0).frame(width: 32)
                queue(model.q1, title: "計算待ち", color: ExperienceStyle.purple).foregroundStyle(.white).frame(width: 118)
                machine("計算する", symbol: "cpu", rate: model.config.cpu, count: nil, color: ExperienceStyle.cyan, note: model.q1 == 0 ? "入力待ち" : "入力 \(model.q1)")
                ExperienceSignal(active: model.q2 > 0).frame(width: 32)
                queue(model.q2, title: "書出し待ち", color: ExperienceStyle.coral).foregroundStyle(.white).frame(width: 118)
                machine("書き出す", symbol: "tray.and.arrow.up", rate: model.config.write, count: model.done, color: ExperienceStyle.coral, note: "完成 \(model.done) / 6")
            }.frame(height: 265)
            ExperienceDevice(title: "RAM　\(model.q1 + model.q2) / \(model.config.ram) 使用中") {
                HStack(spacing: 12) {
                    ForEach(0..<model.config.ram, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 5).fill(i < model.q1 + model.q2 ? ExperienceStyle.cyan : ExperienceStyle.dark)
                            .frame(width: 55, height: 35).overlay(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.7), lineWidth: 2))
                    }
                }
            }.frame(height: 107)
            HStack(spacing: 10) {
                Text("改善部品").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                if model.stage >= 2 {
                    ForEach(choices, id: \.self) { key in
                        Button { send(.upgrade(key)) } label: { Label(label(key), systemImage: key == "cpu" ? "cpu" : key == "ram" ? "memorychip" : "arrow.up.right") }
                            .buttonStyle(ExperienceButtonStyle(primary: changed(key)))
                    }
                }
                Spacer()
                ExperiencePlaybackControls(canStep: model.canStep) { send(.step) }.id("\(model.config)-\(runEpoch)")
                Button { runEpoch += 1; send(.retry) } label: { Image(systemName: "backward.end") }.buttonStyle(ExperienceButtonStyle()).help("同じ条件で最初から流す")
            }
            HStack(spacing: 6) {
                Text("履歴").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                ForEach(Array(model.samples.enumerated()), id: \.offset) { i, s in
                    Button("\(s.tick)") { send(.inspect(i)) }.buttonStyle(.plain).font(.system(size: 16, weight: .bold)).foregroundStyle(model.inspected == i ? ExperienceStyle.ink : .white)
                        .frame(width: 28, height: 28).background(model.inspected == i ? ExperienceStyle.cyan : .white.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                }
                if let i = model.inspected, model.samples.indices.contains(i) {
                    let s = model.samples[i]
                    Text("\(s.tick)刻み：計算待ち\(s.q1) / 書出し待ち\(s.q2) / 完成\(s.done)").font(.system(size: 14)).foregroundStyle(ExperienceStyle.cyan)
                }
                Spacer()
                Text(model.runs.suffix(3).map { "r\($0.config.read)/c\($0.config.cpu)/w\($0.config.write) → \($0.ticks)刻み" }.joined(separator: "  |  ")).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
            }.frame(height: 35)
        }.padding(20).frame(width: 1160, height: 550)
    }
    private var choices: [String] { switch model.stage { case 2: return ["read","cpu","write"]; case 3: return ["cpu","ram"]; case 4: return ["read","cpu"]; case 5: return ["cpu","write"]; default: return [] } }
    private func label(_ key: String) -> String { switch key { case "read": return "読込"; case "cpu": return "CPU"; case "ram": return "RAM"; default: return "書出" } }
    private func changed(_ key: String) -> Bool {
        let base = BottleneckModel.baseline(model.stage)
        switch key { case "read": return model.config.read != base.read; case "cpu": return model.config.cpu != base.cpu; case "ram": return model.config.ram != base.ram; default: return model.config.write != base.write }
    }
    private func machine(_ title: String, symbol: String, rate: Int, count: Int?, color: Color, note: String) -> some View {
        ExperienceDevice(title: title, subtitle: "能力 \(rate) 個 / 刻み", active: title == "計算する" && changed("cpu")) {
            VStack(spacing: 12) {
                ZStack {
                    WorkshopChamfer(corner: 10).fill(ExperienceStyle.dark)
                    HStack(spacing: 5) {
                        ForEach(0..<4, id: \.self) { _ in Capsule().fill(.gray.opacity(0.65)).frame(width: 4, height: 48) }
                        Spacer(minLength: 3)
                        Image(systemName: symbol).font(.system(size: 40, weight: .medium))
                            .frame(width: 75, height: 61)
                            .background(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .topLeading, endPoint: .bottomTrailing), in: WorkshopChamfer(corner: 8))
                            .overlay(WorkshopChamfer(corner: 8).strokeBorder(.white.opacity(0.75), lineWidth: 2))
                            .shadow(color: color.opacity(model.tick > 0 ? 0.4 : 0), radius: 8)
                        Spacer(minLength: 3)
                        VStack(spacing: 5) { ForEach(0..<3, id: \.self) { i in Circle().fill(model.tick > 0 && i == model.tick % 3 ? color : .gray.opacity(0.4)).frame(width: 6, height: 6) } }
                    }.padding(10)
                }.frame(height: 81)
                if let count {
                    HStack(spacing: 4) {
                        ForEach(0..<6, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 3).fill(i < count ? color : ExperienceStyle.dark.opacity(0.25))
                                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(ExperienceStyle.dark.opacity(0.6), lineWidth: 1))
                                .frame(width: 23, height: 25)
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        ForEach(0..<rate, id: \.self) { _ in
                            Image(systemName: "bolt.fill").font(.system(size: 17)).foregroundStyle(model.q1 > 0 ? ExperienceStyle.ink : .gray)
                                .frame(maxWidth: .infinity).frame(height: 25).background(color.opacity(model.q1 > 0 ? 0.75 : 0.2), in: RoundedRectangle(cornerRadius: 3))
                        }
                    }
                }
                Text(note).font(.system(size: 15, weight: .bold, design: .rounded))
            }
        }.frame(width: 228, height: 268)
    }
    private func queue(_ count: Int, title: String, color: Color) -> some View {
        VStack(spacing: 12) {
            Text(title).font(.system(size: 15, weight: .bold))
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(ExperienceStyle.dark)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.gray, lineWidth: 3))
                HStack(spacing: 4) { ForEach(0..<6, id: \.self) { i in
                    Circle().fill(Color.gray.opacity(0.8)).frame(width: 10, height: 10).overlay(Circle().stroke(.black.opacity(0.4), lineWidth: 2))
                } }.offset(y: 19)
                HStack(spacing: 3) { ForEach(0..<count, id: \.self) { i in
                    WorkshopChamfer(corner: 3).fill(LinearGradient(colors: [color, color.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                        .overlay(WorkshopChamfer(corner: 3).strokeBorder(.white.opacity(0.8), lineWidth: 1))
                        .overlay(Text("\(i+1)").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(ExperienceStyle.ink))
                        .frame(width: count > 4 ? 13 : 19, height: 39)
                } }.offset(y: -6)
                if count == 0 { Text("空").font(.system(size: 14)).foregroundStyle(.white.opacity(0.4)).offset(y: -6) }
            }.frame(height: 75)
            Text("\(count) 個").font(.system(size: 18, weight: .bold, design: .rounded))
        }.frame(maxWidth: .infinity)
    }
}

private struct ThermalProcessor: View {
    let active: Bool
    let restricted: Bool
    var body: some View {
        ZStack {
            WorkshopChamfer(corner: 11).fill(LinearGradient(colors: [Color(red: 0.37, green: 0.4, blue: 0.43), ExperienceStyle.dark], startPoint: .topLeading, endPoint: .bottomTrailing))
            HStack(spacing: 8) { ForEach(0..<8, id: \.self) { _ in Rectangle().fill(ExperienceStyle.amber).frame(width: 5, height: 122) } }
            VStack(spacing: 8) { ForEach(0..<7, id: \.self) { _ in Rectangle().fill(ExperienceStyle.amber).frame(width: 136, height: 5) } }
            WorkshopChamfer(corner: 8).fill(LinearGradient(colors: [ExperienceStyle.paper, active ? ExperienceStyle.coral : .gray], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 102, height: 101)
                .overlay(WorkshopChamfer(corner: 8).strokeBorder(ExperienceStyle.ink, lineWidth: 3))
                .shadow(color: active ? .orange.opacity(0.75) : .clear, radius: 13)
            VStack(spacing: 5) {
                Image(systemName: restricted ? "shield.lefthalf.filled" : "cpu").font(.system(size: 38, weight: .medium))
                Text(restricted ? "保護中" : "CPU").font(.system(size: 16, weight: .bold, design: .monospaced))
            }.foregroundStyle(ExperienceStyle.ink)
        }
    }
}
private struct ThermalFanAssembly: View {
    let cooler: Int
    let tick: Int
    let reduced: Bool
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9).fill(LinearGradient(colors: [.gray, ExperienceStyle.dark], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(ExperienceStyle.ink, lineWidth: 3))
            HStack(spacing: 0) {
                HStack(spacing: 3) { ForEach(0..<12, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 2).fill(LinearGradient(colors: [Color(red: 0.42, green: 0.22, blue: 0.15), ExperienceStyle.amber, Color(red: 0.64, green: 0.32, blue: 0.13)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: 6, height: 118)
                } }.padding(.horizontal, 8)
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(ExperienceStyle.dark).overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.gray, lineWidth: 3))
                    Circle().fill(.black.opacity(0.35)).padding(9)
                    Circle().stroke(.gray.opacity(0.5), lineWidth: 2).padding(8)
                    Image(systemName: "fanblades.fill").font(.system(size: 111)).foregroundStyle(LinearGradient(colors: [Color(red: 0.7, green: 0.78, blue: 0.79), Color(red: 0.36, green: 0.44, blue: 0.49)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .rotationEffect(.degrees(reduced ? 0 : Double(tick)*(cooler == 5 ? 120 : 65))).animation(reduced ? nil : .easeOut(duration: 0.35), value: tick)
                    Circle().fill(ExperienceStyle.dark).frame(width: 35, height: 35).overlay(Circle().stroke(ExperienceStyle.cyan, lineWidth: 3))
                    ForEach(0..<4, id: \.self) { i in Circle().fill(.gray).frame(width: 7, height: 7).offset(x: i % 2 == 0 ? -58 : 58, y: i < 2 ? -57 : 57) }
                }.frame(width: 133, height: 133).opacity(cooler == 1 ? 0.2 : 1)
            }
            VStack { Spacer(); RoundedRectangle(cornerRadius: 3).fill(.gray).frame(width: 266, height: 6).overlay(Rectangle().fill(.white.opacity(0.4)).frame(height: 1), alignment: .top) }
        }
    }
}
private struct ThermalFlow: View {
    let color: Color
    let active: Bool
    let label: String
    var body: some View {
        VStack(spacing: 11) {
            Text(label).font(.system(size: 12, weight: .bold)).foregroundStyle(color)
            ForEach(0..<3, id: \.self) { row in
                GeometryReader { g in
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: 12))
                        p.addCurve(to: CGPoint(x: g.size.width-8, y: 12), control1: CGPoint(x: g.size.width*0.3, y: CGFloat(row % 2 == 0 ? 0 : 24)), control2: CGPoint(x: g.size.width*0.65, y: CGFloat(row % 2 == 0 ? 24 : 0)))
                    }.stroke(color.opacity(active ? 0.85 : 0.24), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .black)).foregroundStyle(color.opacity(active ? 1 : 0.3)).position(x: g.size.width-5, y: 12)
                }.frame(height: 25)
            }
        }.shadow(color: active ? color.opacity(0.5) : .clear, radius: 5).allowsHitTesting(false)
    }
}
