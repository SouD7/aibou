import SwiftUI
import UniformTypeIdentifiers
#if canImport(CircuitCore)
import CircuitCore
#endif

struct CircuitExperienceView: View {
    var onExit: () -> Void
    @StateObject private var store = ExperienceStore(CircuitExperienceModel(stage: 1))
    var body: some View {
        ExperienceScreen(store: store, onExit: onExit) { model, send in
            CircuitExperienceApparatus(model: model, send: send)
        }
    }
}

struct CircuitExperienceApparatus: View {
    let model: CircuitExperienceModel
    let send: (CircuitExperienceModel.Action) -> Void
    @State private var selectedPort: CircuitExperienceModel.Port?
    @State private var dragPoint: CGPoint?
    @State private var running = false
    @State private var remaining = 0
    @Environment(\.scenePhase) private var scenePhase
    private var circuit: CircuitSnapshot { model.circuit }
    private let timer = Timer.publish(every: 0.7, on: .main, in: .common).autoconnect()
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 16) {
                bench.frame(width: 844, height: 366)
                truthTable.frame(width: 264, height: 366)
            }
            tray.frame(height: 58)
            controls.frame(height: 54)
        }.padding(18)
            .onReceive(timer) { _ in
                guard running, model.canObserve, remaining > 0 else { return }
                send(.step); remaining -= 1
                if remaining == 0 { running = false }
            }
            .onChange(of: model.revision) { _ in cancelTest() }
            .onChange(of: model.stage) { _ in cancelTest(); selectedPort = nil }
            .onChange(of: scenePhase) { if $0 != .active { cancelTest() } }
            .onDisappear { cancelTest() }
    }
    private var bench: some View {
        ZStack {
            Canvas { context, _ in
                for link in CircuitLink.allCases {
                    let ports = pair(link), path = wire(from: point(ports.0), to: point(ports.1))
                    if circuit.links.contains(link) {
                        context.stroke(path, with: .color(.black.opacity(0.4)), style: StrokeStyle(lineWidth: 17, lineCap: .round, lineJoin: .round))
                        context.stroke(path, with: .color(signal(link) == .high ? ExperienceStyle.cyan : Color.gray), style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                        context.stroke(path, with: .color(.white.opacity(0.38)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    } else {
                        context.stroke(path, with: .color(.white.opacity(0.22)), style: StrokeStyle(lineWidth: 3, dash: [7, 8]))
                    }
                }
                if let origin = selectedPort, let end = dragPoint {
                    context.stroke(wire(from: point(origin), to: end), with: .color(ExperienceStyle.cyan), style: StrokeStyle(lineWidth: 4, dash: [5, 5]))
                }
            }.allowsHitTesting(false)
            HStack {
                Label("ふたりの作業台", systemImage: "square.grid.2x2").font(.system(size: 17, weight: .semibold))
                Spacer()
                Text(selectedPort.map { "\($0.title) → 次の端子" } ?? "端子をクリック・ドラッグしてつなぐ").font(.system(size: 14))
            }.foregroundStyle(.white.opacity(0.8)).padding(.horizontal, 12).frame(width: 844).position(x: 422, y: 15)
            input(.a, name: model.stage == 5 ? "A 準備完了" : "A あなた").position(x: 111, y: 112)
            input(.b, name: model.stage == 5 ? "B 開始許可" : "B 相棒").position(x: 111, y: 280)
            ExperienceDevice(title: circuit.selectedGate.map(partName) ?? "部品スロット", subtitle: "入力 × 2　出力 × 1", active: circuit.selectedGate != nil) {
                Text(circuit.selectedGate?.symbol ?? "+").font(.system(size: 67, weight: .bold, design: .rounded))
            }.frame(width: 222, height: 212).position(x: 433, y: 193)
                .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                    LogicDrop.text(providers) { value in if let gate = GateKind(rawValue: value) { edit(.selectGate(gate)) } }
                }
            ExperienceDevice(title: "OUTPUT", active: circuit.output == .high) {
                VStack(spacing: 8) {
                    Image(systemName: circuit.output == .unknown ? "questionmark" : "lightbulb.fill")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(circuit.output == .high ? ExperienceStyle.cyan : Color.gray)
                        .shadow(color: circuit.output == .high ? .cyan.opacity(0.7) : .clear, radius: 12)
                    Text(circuit.output.label).font(.system(size: 32, weight: .bold, design: .monospaced)).foregroundStyle(.white)
                    Text(circuit.output == .unknown ? "未接続" : circuit.output == .high ? "点灯" : "消灯").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                }.frame(maxWidth: .infinity).padding(.vertical, 9).background(ExperienceStyle.dark, in: RoundedRectangle(cornerRadius: 8))
            }.frame(width: 168, height: 254).position(x: 731, y: 193)
            ForEach(CircuitExperienceModel.Port.allCases, id: \.rawValue) { port in portView(port).position(point(port)) }
        }.coordinateSpace(name: "circuit-checkpoint-bench")
    }
    private func input(_ input: CircuitInput, name: String) -> some View {
        let on = input == .a ? circuit.inputs.a : circuit.inputs.b
        return ExperienceDevice(title: name) {
            Button { edit(.toggleInput(input)) } label: {
                HStack(spacing: 13) {
                    Circle().fill(LinearGradient(colors: on ? [.white, ExperienceStyle.cyan] : [.gray, ExperienceStyle.dark], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 3)).frame(width: 49, height: 49)
                        .shadow(color: on ? .cyan.opacity(0.45) : .black.opacity(0.3), radius: on ? 8 : 0, y: 3)
                    Text(on ? "1" : "0").font(.system(size: 31, weight: .bold, design: .monospaced))
                }
            }.buttonStyle(.plain).disabled(!model.started).accessibilityLabel("\(name) を\(on ? "0" : "1")にする")
        }.frame(width: 180, height: 140)
    }
    private var truthTable: some View {
        ExperienceDevice(title: "4つの条件", subtitle: "目標と、今の回路を比較") {
            VStack(spacing: 4) {
                HStack { Text("A B").frame(width: 50); Text("目標").frame(width: 55); Text("観察").frame(width: 55) }
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(ExperienceStyle.muted)
                ForEach(Array(InputPair.truthTable.enumerated()), id: \.offset) { _, inputs in
                    let row = model.observations.first { $0.inputs == inputs }
                    Button { edit(.replayRow(inputs)) } label: {
                        HStack {
                            Text("\(inputs.a ? 1 : 0) \(inputs.b ? 1 : 0)").frame(width: 50)
                            Text(GateKind.and.evaluate(inputs) ? "1" : "0").frame(width: 55)
                            Text(row?.actual.label ?? "・").frame(width: 55)
                        }.font(.system(size: 23, weight: .semibold, design: .monospaced))
                            .padding(.vertical, 7).frame(maxWidth: .infinity)
                            .background(circuit.inputs == inputs ? ExperienceStyle.cyan.opacity(0.26) : row.map { $0.passed ? Color.clear : ExperienceStyle.coral.opacity(0.22) } ?? .clear, in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).disabled(row == nil)
                        .accessibilityLabel("A\(inputs.a ? 1 : 0) B\(inputs.b ? 1 : 0)、目標\(GateKind.and.evaluate(inputs) ? 1 : 0)、観察\(row?.actual.label ?? "未記録")を再現")
                }
                Text("\(model.observations.count) / 4 通りを観察").font(.system(size: 17, weight: .bold)).padding(.top, 4)
            }
        }
    }
    private var tray: some View {
        HStack(spacing: 12) {
            Label("部品", systemImage: "cpu").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white).frame(width: 74)
            ForEach(GateKind.allCases, id: \.rawValue) { gate in
                Button { edit(.selectGate(gate)) } label: {
                    HStack(spacing: 10) { Text(gate.symbol).font(.system(size: 26, weight: .bold)); Text(partName(gate)).font(.system(size: 15, weight: .semibold)) }
                        .frame(width: 122, height: 32)
                }.buttonStyle(LogicCompactButtonStyle(primary: circuit.selectedGate == gate)).disabled(!model.started)
                    .onDrag { NSItemProvider(object: gate.rawValue as NSString) }
                    .accessibilityLabel("\(partName(gate))を配置")
            }
            Spacer(minLength: 10)
            ForEach(CircuitLink.allCases, id: \.rawValue) { link in
                Button { edit(.toggleLink(link)) } label: {
                    Label(linkName(link), systemImage: circuit.links.contains(link) ? "link" : "link.badge.plus").frame(width: 107, height: 32)
                }.buttonStyle(LogicCompactButtonStyle(primary: circuit.links.contains(link))).disabled(!model.started)
                    .accessibilityLabel("\(linkName(link))を\(circuit.links.contains(link) ? "外す" : "つなぐ")")
            }
        }
    }
    @ViewBuilder private var controls: some View {
        if !model.started {
            HStack { Text("未接続の「？」は、消灯の0とは違うよ。").font(.system(size: 20, weight: .medium)).foregroundStyle(.white); Spacer(); Button("一緒に作る") { edit(.begin) }.buttonStyle(ExperienceButtonStyle(primary: true)) }
        } else if model.stage == 5 && circuit.verification == .passed {
            HStack(spacing: 12) {
                let prediction = circuit.prediction.inputs
                Text("予想  A=\(prediction.a ? 1 : 0) / B=\(prediction.b ? 1 : 0)").font(.system(size: 21, weight: .bold)).foregroundStyle(.white)
                Button("0 消える") { edit(.predict(false)) }.buttonStyle(ExperienceButtonStyle())
                Button("1 光る") { edit(.predict(true)) }.buttonStyle(ExperienceButtonStyle())
                Button("予想を見送る") { edit(.skipPrediction) }.buttonStyle(ExperienceButtonStyle())
                Spacer(minLength: 0)
                Button("相棒にお願い") { edit(.askCompanion) }.buttonStyle(ExperienceButtonStyle())
            }
        } else {
            HStack(spacing: 14) {
                Button { if running { running = false } else { if remaining == 0 { remaining = 4 }; running = true } } label: {
                    Label(running ? "一時停止 \(4 - remaining) / 4" : remaining > 0 ? "テスト再開" : "4通りテスト", systemImage: running ? "pause.fill" : "play.fill")
                }.buttonStyle(ExperienceButtonStyle(primary: true)).disabled(!model.canObserve).keyboardShortcut(.space, modifiers: [])
                Button("1条件進む") { cancelTest(); send(.step) }.buttonStyle(ExperienceButtonStyle()).disabled(!model.canObserve)
                Button("今を記録") { edit(.observe) }.buttonStyle(ExperienceButtonStyle()).disabled(!model.canObserve)
                Spacer(minLength: 0)
                Text("\(circuit.links.count) / 3 本 接続").font(.system(size: 17, weight: .semibold)).foregroundStyle(ExperienceStyle.cyan)
                Button("相棒にお願い") { edit(.askCompanion) }.buttonStyle(ExperienceButtonStyle())
            }
        }
    }
    private func portView(_ port: CircuitExperienceModel.Port) -> some View {
        Button {
            cancelTest()
            if let origin = selectedPort { send(.connect(origin, port)); selectedPort = nil }
            else { selectedPort = port }
        } label: {
            Circle().fill(ExperienceStyle.dark)
                .overlay(Circle().strokeBorder(selectedPort == port ? .white : .gray, lineWidth: 3))
                .overlay(Circle().fill(signal(port.link) == .high && (port.source || circuit.links.contains(port.link)) ? ExperienceStyle.cyan : Color.gray).padding(8))
                .frame(width: 40, height: 40)
        }.buttonStyle(.plain).disabled(!model.started).accessibilityLabel(port.title)
            .simultaneousGesture(DragGesture(minimumDistance: 8, coordinateSpace: .named("circuit-checkpoint-bench"))
                .onChanged { value in guard model.started else { return }; cancelTest(); selectedPort = port; dragPoint = value.location }
                .onEnded { value in
                    defer { selectedPort = nil; dragPoint = nil }
                    guard model.started else { return }
                    if let target = CircuitExperienceModel.Port.allCases.first(where: { hypot(point($0).x - value.location.x, point($0).y - value.location.y) < 30 }) { send(.connect(port, target)) }
                })
    }
    private func cancelTest() { running = false; remaining = 0 }
    private func edit(_ action: CircuitExperienceModel.Action) { cancelTest(); send(action) }
    private func partName(_ gate: GateKind) -> String { model.named ? gate.title : "パーツ0\((GateKind.allCases.firstIndex(of: gate) ?? 0) + 1)" }
    private func linkName(_ link: CircuitLink) -> String { link == .inputA ? "Aの線" : link == .inputB ? "Bの線" : "出力の線" }
    private func signal(_ link: CircuitLink) -> LogicSignal { link == .inputA ? LogicSignal(circuit.inputs.a) : link == .inputB ? LogicSignal(circuit.inputs.b) : circuit.output }
    private func pair(_ link: CircuitLink) -> (CircuitExperienceModel.Port, CircuitExperienceModel.Port) { link == .inputA ? (.aOut, .gateA) : link == .inputB ? (.bOut, .gateB) : (.gateOut, .lampIn) }
    private func point(_ port: CircuitExperienceModel.Port) -> CGPoint {
        switch port { case .aOut: return CGPoint(x: 210, y: 112); case .bOut: return CGPoint(x: 210, y: 280); case .gateA: return CGPoint(x: 322, y: 167); case .gateB: return CGPoint(x: 322, y: 229); case .gateOut: return CGPoint(x: 544, y: 193); case .lampIn: return CGPoint(x: 647, y: 193) }
    }
    private func wire(from start: CGPoint, to end: CGPoint) -> Path {
        Path { p in p.move(to: start); let mid = (start.x + end.x) / 2; p.addCurve(to: end, control1: CGPoint(x: mid, y: start.y), control2: CGPoint(x: mid, y: end.y)) }
    }
}
