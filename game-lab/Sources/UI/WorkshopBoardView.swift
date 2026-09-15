import SwiftUI
import UniformTypeIdentifiers
#if canImport(CircuitCore)
import CircuitCore
#endif

private struct WorkshopPort: Equatable {
    let link: CircuitLink
    let source: Bool
    var name: String { "\(link == .inputA ? "a" : link == .inputB ? "b" : "output").\(source ? "start" : "end")" }
}

struct WorkshopBoardView: View {
    @ObservedObject var store: WorkshopStore
    var reducedMotion: Bool
    var boardHeight: CGFloat = 320
    @State private var selectedPort: WorkshopPort?
    @State private var dragPoint: CGPoint?
    @State private var dropTarget = false
    @State private var connectionMessage = ""

    private var circuit: CircuitSnapshot { store.circuit }
    private var compactBoard: Bool { boardHeight <= 250 }
    private var gateName: String { circuit.selectedGate.map(partName) ?? "パーツを置こう" }
    private var ports: [WorkshopPort] { CircuitLink.allCases.flatMap { [WorkshopPort(link: $0, source: true), WorkshopPort(link: $0, source: false)] } }

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 0) {
            HStack {
                Label("ふたりの作業台", systemImage: "square.grid.2x2")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(WorkshopBenchColor.paper)
                Spacer()
                Text(store.isTesting ? "実験中  \(store.testRow) / 4" : "\(circuit.links.count) / 3 本 接続")
                    .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(WorkshopBenchColor.cyan)
            }.padding(.horizontal, 22).padding(.top, 18)
            GeometryReader { geometry in
                let size = geometry.size
                ZStack {
                    Canvas { context, canvas in
                        for x in stride(from: 28.0, to: canvas.width, by: 56) {
                            var line = Path()
                            line.move(to: CGPoint(x: x, y: 0))
                            line.addLine(to: CGPoint(x: x, y: canvas.height))
                            context.stroke(line, with: .color(.black.opacity(0.19)), lineWidth: 1)
                            for y in stride(from: 28.0, to: canvas.height, by: 56) {
                                context.fill(Path(ellipseIn: CGRect(x: x - 1.8, y: y - 1.8, width: 3.6, height: 3.6)),
                                             with: .color(Color.white.opacity(0.16)))
                            }
                        }
                        for y in stride(from: 0.0, to: canvas.height, by: 56) {
                            var line = Path()
                            line.move(to: CGPoint(x: 0, y: y))
                            line.addLine(to: CGPoint(x: canvas.width, y: y))
                            context.stroke(line, with: .color(.black.opacity(0.16)), lineWidth: 1)
                        }
                    }.accessibilityHidden(true).allowsHitTesting(false)
                    ForEach(CircuitLink.allCases, id: \.rawValue) { link in
                        wire(link, in: size)
                    }
                    if let origin = selectedPort, let end = dragPoint {
                        connectionPath(from: point(origin, in: size), to: end)
                            .stroke(WorkshopBenchColor.cyan, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [3, 7]))
                            .shadow(color: WorkshopBenchColor.cyan.opacity(0.35), radius: 5)
                            .allowsHitTesting(false)
                    }
                    input(.a, width: min(134, max(92, size.width * 0.155)))
                        .position(x: size.width * 0.105, y: size.height * 0.29)
                    input(.b, width: min(134, max(92, size.width * 0.155)))
                        .position(x: size.width * 0.105, y: size.height * 0.71)
                    gate.frame(width: size.width * 0.255, height: min(172, size.height * 0.47))
                        .position(x: size.width * 0.52, y: size.height * 0.5)
                    lamp.frame(width: min(128, size.width * 0.165), height: min(184, size.height * 0.58))
                        .position(x: size.width * 0.91, y: size.height * 0.5)
                    ForEach(Array(ports.enumerated()), id: \.offset) { _, item in
                        port(item, in: size).position(point(item, in: size))
                    }
                    linkButton(.inputA).position(x: size.width * 0.295, y: size.height * 0.19)
                    linkButton(.inputB).position(x: size.width * 0.295, y: size.height * 0.81)
                    linkButton(.output).position(x: size.width * 0.73, y: size.height * 0.70)
                }.coordinateSpace(name: "workshop.board")
            }.frame(height: boardHeight)
            Text(connectionMessage.isEmpty ? (selectedPort == nil ? "端子をつなぐ  /  スイッチを切り替える  /  光り方を比べる" : "もう片方の丸い端子を選ぼう。Escで取り消し。") : connectionMessage)
                .font(.system(size: 10)).foregroundStyle(WorkshopBenchColor.silver).padding(.horizontal, 18).padding(.bottom, 18)
                .frame(maxWidth: .infinity).accessibilityIdentifier("w.connectionHelp")
            }.padding(10)
                .background { WorkshopBenchMat() }

            Group {
                if compactBoard {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Label("部品", systemImage: "square.stack.3d.up")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(WorkshopBenchColor.paper)
                            Text("クリック\nドラッグ")
                                .font(.system(size: 8)).foregroundStyle(WorkshopBenchColor.silver)
                                .fixedSize(horizontal: true, vertical: true)
                        }.frame(width: 64, alignment: .leading)
                        paletteCards
                    }.padding(12)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("試せるパーツ", systemImage: "square.stack.3d.up")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(WorkshopBenchColor.paper)
                            Spacer()
                            Text("ドラッグ / クリックで配置").font(.system(size: 10)).foregroundStyle(WorkshopBenchColor.silver)
                        }
                        paletteCards
                    }.padding(16)
                }
            }
                .background(LinearGradient(colors: [WorkshopBenchColor.graphite, WorkshopBenchColor.edge], startPoint: .top, endPoint: .bottom), in: WorkshopCutPlate(corner: 12))
                .overlay(WorkshopCutPlate(corner: 12).stroke(WorkshopBenchColor.silver.opacity(0.6), lineWidth: 2))
                .shadow(color: .black.opacity(0.20), radius: 3, y: 4)
        }
            .onExitCommand { selectedPort = nil; dragPoint = nil; connectionMessage = "" }
            .onChange(of: circuit.selectedGate) { _ in selectedPort = nil; dragPoint = nil }
    }

    private var paletteCards: some View {
        HStack(spacing: compactBoard ? 10 : 14) {
            ForEach(GateKind.allCases, id: \.rawValue) { kind in
                Button { choose(kind) } label: {
                    HStack(spacing: compactBoard ? 9 : 12) {
                        ZStack {
                            HStack(spacing: compactBoard ? 5 : 7) {
                                ForEach(0..<4, id: \.self) { _ in
                                    Rectangle().fill(WorkshopBenchColor.brass)
                                        .frame(width: compactBoard ? 4 : 5, height: compactBoard ? 8 : 10)
                                        .overlay(Rectangle().stroke(WorkshopBenchColor.edge, lineWidth: 0.8))
                                }
                            }.offset(y: compactBoard ? 24 : 32)
                            Text(store.discovered ? kind.symbol : partNumber(kind))
                                .font(.system(size: compactBoard ? (store.discovered ? 23 : 18) : (store.discovered ? 26 : 21),
                                              weight: .medium, design: .rounded))
                                .foregroundStyle(WorkshopBenchColor.ink)
                                .frame(width: compactBoard ? 46 : 60, height: compactBoard ? 44 : 59)
                                .background { WorkshopChipHousing(corner: 6, depth: compactBoard ? 4 : 5, screws: true) }
                        }.frame(width: compactBoard ? 49 : 62, height: compactBoard ? 54 : 72)
                        VStack(alignment: .leading, spacing: compactBoard ? 3 : 4) {
                            Text(partName(kind)).font(.system(size: compactBoard ? 11 : 12, weight: .semibold))
                                .lineLimit(1)
                            Text(circuit.selectedGate == kind ? "使用中" : "置いて試す")
                                .font(.system(size: 9))
                                .foregroundStyle(circuit.selectedGate == kind ? WorkshopBenchColor.cyan : WorkshopBenchColor.silver)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }.padding(.horizontal, compactBoard ? 8 : 10).padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(WorkshopBenchColor.paper)
                        .background(WorkshopBenchColor.edge.opacity(0.7), in: WorkshopCutPlate(corner: 8))
                        .overlay(WorkshopCutPlate(corner: 8).stroke(circuit.selectedGate == kind ? WorkshopBenchColor.cyan : Color.white.opacity(0.13), lineWidth: 1.5))
                        .shadow(color: circuit.selectedGate == kind ? WorkshopBenchColor.cyan.opacity(0.10) : .clear, radius: 5)
                }.buttonStyle(.plain).accessibilityIdentifier("w.gate.\(kind.rawValue)")
                    .accessibilityLabel("\(partName(kind))を置く")
                    .onDrag { NSItemProvider(object: "aibou-workshop:\(kind.rawValue)" as NSString) }
            }
        }
    }

    private func partNumber(_ kind: GateKind) -> String { kind == .and ? "01" : kind == .or ? "02" : "03" }
    private func partName(_ kind: GateKind) -> String { store.discovered ? kind.title : "パーツ\(partNumber(kind))" }
    private func choose(_ kind: GateKind) { selectedPort = nil; dragPoint = nil; connectionMessage = ""; store.act(.circuit(.selectGate(kind))) }

    private func point(_ port: WorkshopPort, in size: CGSize) -> CGPoint {
        let fractions: (CGFloat, CGFloat)
        switch (port.link, port.source) {
        case (.inputA, true): fractions = (0.19, 0.29)
        case (.inputA, false): fractions = (0.39, 0.405)
        case (.inputB, true): fractions = (0.19, 0.71)
        case (.inputB, false): fractions = (0.39, 0.595)
        case (.output, true): fractions = (0.65, 0.5)
        case (.output, false): fractions = (0.81, 0.5)
        }
        return CGPoint(x: size.width * fractions.0, y: size.height * fractions.1)
    }

    private func connectionPath(from a: CGPoint, to b: CGPoint) -> Path {
        Path { path in
            path.move(to: a)
            guard abs(b.y - a.y) > 1 else { path.addLine(to: b); return }
            let middle = (a.x + b.x) / 2
            let radius = min(12, abs(b.y - a.y) / 2, abs(b.x - a.x) / 4)
            let directionY: CGFloat = b.y > a.y ? 1 : -1
            let directionX: CGFloat = b.x > a.x ? 1 : -1
            path.addLine(to: CGPoint(x: middle - radius * directionX, y: a.y))
            path.addQuadCurve(to: CGPoint(x: middle, y: a.y + radius * directionY), control: CGPoint(x: middle, y: a.y))
            path.addLine(to: CGPoint(x: middle, y: b.y - radius * directionY))
            path.addQuadCurve(to: CGPoint(x: middle + radius * directionX, y: b.y), control: CGPoint(x: middle, y: b.y))
            path.addLine(to: b)
        }
    }

    private func wire(_ link: CircuitLink, in size: CGSize) -> some View {
        let connected = circuit.links.contains(link)
        let value: LogicSignal = link == .inputA ? LogicSignal(circuit.inputs.a) : link == .inputB ? LogicSignal(circuit.inputs.b) : circuit.output
        let start = point(WorkshopPort(link: link, source: true), in: size)
        let end = point(WorkshopPort(link: link, source: false), in: size)
        let path = connectionPath(from: start, to: end)
        return ZStack {
            if connected {
                path.stroke(.black.opacity(0.45), style: StrokeStyle(lineWidth: 10, lineCap: .round)).offset(y: 3)
                path.stroke(WorkshopBenchColor.edge, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                if value == .high {
                    path.stroke(WorkshopBenchColor.cyan.opacity(0.23), style: StrokeStyle(lineWidth: 15, lineCap: .round)).blur(radius: 4)
                }
                path.stroke(value == .high ? WorkshopBenchColor.cyan : WorkshopBenchColor.silver.opacity(0.75),
                            style: StrokeStyle(lineWidth: 5.5, lineCap: .round))
                path.stroke(Color.white.opacity(value == .high ? 0.42 : 0.19), style: StrokeStyle(lineWidth: 1.3, lineCap: .round)).offset(y: -1)
            } else {
                path.stroke(WorkshopBenchColor.silver.opacity(0.32), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 7]))
            }
        }
            .accessibilityHidden(true).allowsHitTesting(false)
    }

    private func port(_ port: WorkshopPort, in size: CGSize) -> some View {
        let connected = circuit.links.contains(port.link)
        let selected = selectedPort == port
        let target = selectedPort.map { $0.link == port.link && $0.source != port.source } ?? false
        let signal = port.link == .inputA ? LogicSignal(circuit.inputs.a) : port.link == .inputB ? LogicSignal(circuit.inputs.b) : circuit.output
        let lit = connected && signal == .high
        return Button { tap(port) } label: {
            ZStack {
                Circle().fill(.black.opacity(0.4)).frame(width: 31, height: 31).offset(y: 3)
                Circle().fill(LinearGradient(colors: [WorkshopBenchColor.paper, WorkshopBenchColor.steel], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(WorkshopBenchColor.edge, lineWidth: 1.5))
                Circle().fill(WorkshopBenchColor.edge).frame(width: 20, height: 20)
                Circle().fill(lit ? WorkshopBenchColor.cyan : connected ? WorkshopBenchColor.steel : WorkshopBenchColor.graphite)
                    .frame(width: 15, height: 15)
                    .overlay(Circle().stroke(.white.opacity(lit ? 0.75 : 0.15), lineWidth: 1))
                    .shadow(color: lit ? WorkshopBenchColor.cyan.opacity(0.55) : .clear, radius: 4)
                if selected || target {
                    Circle().stroke(WorkshopBenchColor.cyan, lineWidth: 2).frame(width: 33, height: 33)
                }
            }.frame(width: 32, height: 32).contentShape(Circle())
        }.buttonStyle(.plain).disabled(circuit.selectedGate == nil)
            .accessibilityLabel("\(port.link == .inputA ? "A" : port.link == .inputB ? "B" : "出力")の\(port.source ? "送り出す" : "受け取る")端子")
            .accessibilityIdentifier("w.port.\(port.name)")
            .simultaneousGesture(DragGesture(minimumDistance: 6, coordinateSpace: .named("workshop.board"))
                .onChanged { value in
                    guard circuit.selectedGate != nil else { return }
                    selectedPort = port; dragPoint = value.location; connectionMessage = ""
                }
                .onEnded { value in
                    guard circuit.selectedGate != nil else { return }
                    if let targetPort = ports.first(where: {
                        $0 != port && hypot(point($0, in: size).x - value.location.x, point($0, in: size).y - value.location.y) < 32
                    }) { connect(port, targetPort) }
                    else { connectionMessage = "もう片方の丸い端子へつないでね。" }
                    selectedPort = nil; dragPoint = nil
                })
    }

    private func tap(_ port: WorkshopPort) {
        connectionMessage = ""
        if let selected = selectedPort {
            if selected != port { connect(selected, port) }
            selectedPort = nil
        } else { selectedPort = port }
    }
    private func connect(_ first: WorkshopPort, _ second: WorkshopPort) {
        guard first.link == second.link && first.source != second.source else {
            connectionMessage = "送り出す端子と、同じ道の受け取る端子をつなごう。"; return
        }
        connectionMessage = ""
        store.act(.circuit(.toggleLink(first.link)))
    }

    private func input(_ input: CircuitInput, width: CGFloat) -> some View {
        let on = input == .a ? circuit.inputs.a : circuit.inputs.b
        return Button { store.act(.circuit(.toggleInput(input))) } label: {
            VStack(spacing: compactBoard ? 5 : 10) {
                HStack(spacing: compactBoard ? 8 : 10) {
                    VStack(spacing: 1) {
                        Text(input == .a ? "A" : "B").font(.system(size: compactBoard ? 23 : 26, weight: .semibold, design: .rounded))
                        Text(input == .a ? "あなた" : "相棒").font(.system(size: 8, weight: .medium))
                    }
                    ZStack {
                        Circle().fill(WorkshopBenchColor.edge).frame(width: 36, height: 36).offset(y: 5)
                        Circle().fill(LinearGradient(colors: [WorkshopBenchColor.steel, WorkshopBenchColor.edge], startPoint: .leading, endPoint: .trailing))
                            .frame(width: 35, height: 35).offset(y: 3)
                        Circle().fill(on
                            ? LinearGradient(colors: [WorkshopBenchColor.cyan.opacity(0.95), Color(red: 0.10, green: 0.67, blue: 0.74)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color(red: 0.81, green: 0.83, blue: 0.84), WorkshopBenchColor.steel], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 32, height: 32)
                            .overlay(Circle().stroke(.white.opacity(on ? 0.9 : 0.5), lineWidth: 1.5).padding(3))
                            .overlay(Circle().stroke(WorkshopBenchColor.edge, lineWidth: 1.3))
                            .shadow(color: on ? WorkshopBenchColor.cyan.opacity(0.42) : .clear, radius: 5)
                    }.frame(width: 37, height: 42)
                }
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(on ? WorkshopBenchColor.cyan : WorkshopBenchColor.steel)
                        .frame(width: 6, height: compactBoard ? 12 : 14).overlay(RoundedRectangle(cornerRadius: 2).stroke(WorkshopBenchColor.edge, lineWidth: 1))
                    Text(on ? "1  準備できた" : "0  準備前").font(.system(size: compactBoard ? 8 : 9, weight: .semibold))
                }
            }.foregroundStyle(WorkshopBenchColor.ink).frame(width: width, height: compactBoard ? 80 : 108)
                .background { WorkshopChipHousing(corner: 8, depth: compactBoard ? 4 : 7, screws: true) }
        }.buttonStyle(.plain).accessibilityIdentifier("w.input.\(input.rawValue)")
            .accessibilityLabel("入力\(input.rawValue.uppercased()) \(on ? "1 ON" : "0 OFF")")
            .animation(reducedMotion ? nil : .easeOut(duration: 0.16), value: on)
    }

    private var gate: some View {
        ZStack {
            if circuit.selectedGate != nil {
                WorkshopChipHousing(corner: 9, depth: 8, screws: true)
            } else {
                WorkshopCutPlate(corner: 9).fill(WorkshopBenchColor.edge.opacity(0.65))
                    .overlay(WorkshopCutPlate(corner: 9).stroke(dropTarget ? WorkshopBenchColor.cyan : WorkshopBenchColor.silver.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [4, 5])))
            }
            VStack(spacing: 10) {
                if let selectedGate = circuit.selectedGate {
                    Text("LOGIC MODULE").font(.system(size: 7, weight: .semibold, design: .monospaced)).tracking(1.1)
                        .foregroundStyle(WorkshopBenchColor.steel)
                    Text(gateName).font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text(store.discovered ? selectedGate.symbol : "2 → 1")
                        .font(.system(size: 31, weight: .medium, design: .rounded))
                    Text("入力 × 2     出力 × 1").font(.system(size: 8)).foregroundStyle(WorkshopBenchColor.steel)
                } else {
                    Image(systemName: "square.dashed").font(.system(size: 29, weight: .light))
                    Text(gateName).font(.system(size: 12, weight: .semibold))
                    Text("下から選ぶ / ドラッグ").font(.system(size: 8))
                }
            }.foregroundStyle(circuit.selectedGate == nil ? WorkshopBenchColor.silver : WorkshopBenchColor.ink)
                .padding(12)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(WorkshopCutPlate(corner: 9).stroke(dropTarget ? WorkshopBenchColor.cyan : .clear, lineWidth: 3))
            .accessibilityElement(children: .ignore).accessibilityLabel("回路パーツの置き場所。\(gateName)").accessibilityIdentifier("w.slot")
            .onDrop(of: [UTType.plainText], isTargeted: $dropTarget) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                    guard let text = value as? String, text.hasPrefix("aibou-workshop:"),
                          let kind = GateKind(rawValue: String(text.dropFirst("aibou-workshop:".count))) else { return }
                    Task { @MainActor in choose(kind) }
                }
                return true
            }
    }

    private var lamp: some View {
        let high = circuit.output == .high
        let text = circuit.output == .unknown ? "? 未接続" : high ? "1 点灯" : "0 消灯"
        return ZStack {
            WorkshopChipHousing(corner: 8, depth: 8, screws: true)
            VStack(spacing: 12) {
                Text("OUTPUT").font(.system(size: 7, weight: .semibold, design: .monospaced)).tracking(1.3)
                    .foregroundStyle(WorkshopBenchColor.steel)
                ZStack {
                    WorkshopCutPlate(corner: 5).fill(WorkshopBenchColor.edge)
                        .overlay(WorkshopCutPlate(corner: 5).stroke(WorkshopBenchColor.steel, lineWidth: 2))
                    VStack(spacing: 6) {
                        Image(systemName: high ? "lightbulb.fill" : "lightbulb").font(.system(size: 29, weight: .light))
                        Text(circuit.output.label).font(.system(size: 19, weight: .medium, design: .monospaced))
                    }.foregroundStyle(high ? WorkshopBenchColor.cyan : WorkshopBenchColor.silver.opacity(circuit.output == .unknown ? 0.5 : 0.8))
                        .shadow(color: high ? WorkshopBenchColor.cyan.opacity(0.65) : .clear, radius: 7)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(text).font(.system(size: 9, weight: .semibold)).foregroundStyle(WorkshopBenchColor.ink)
            }
            .padding(.horizontal, 12).padding(.vertical, 17)
        }.accessibilityElement(children: .ignore).accessibilityLabel("ランプ。\(text)").accessibilityIdentifier("w.lamp")
            .animation(reducedMotion ? nil : .easeOut(duration: 0.18), value: high)
    }

    private func linkButton(_ link: CircuitLink) -> some View {
        let connected = circuit.links.contains(link)
        let id = link == .inputA ? "a" : link == .inputB ? "b" : "output"
        return Button { selectedPort = nil; connectionMessage = ""; store.act(.circuit(.toggleLink(link))) } label: {
            HStack(spacing: 4) {
                Image(systemName: connected ? "link" : "plus").font(.system(size: 8, weight: .semibold))
                Text(connected ? "接続済" : "つなぐ").font(.system(size: 9, weight: .medium))
            }.padding(.horizontal, 8).padding(.vertical, 6)
                .foregroundStyle(connected ? WorkshopBenchColor.cyan : WorkshopBenchColor.paper)
                .background(WorkshopBenchColor.edge, in: WorkshopCutPlate(corner: 4))
                .overlay(WorkshopCutPlate(corner: 4).stroke(connected ? WorkshopBenchColor.cyan.opacity(0.45) : WorkshopBenchColor.silver.opacity(0.4), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 1, y: 2)
        }.buttonStyle(.plain).disabled(circuit.selectedGate == nil).accessibilityIdentifier("w.link.\(id)")
            .accessibilityLabel("\(id == "output" ? "出力" : id.uppercased())の配線 \(connected ? "接続済み。切り離す" : "つなぐ")")
    }
}

private enum WorkshopBenchColor {
    static let ink = Color(red: 0.10, green: 0.13, blue: 0.17)
    static let edge = Color(red: 0.13, green: 0.16, blue: 0.20)
    static let graphite = Color(red: 0.25, green: 0.28, blue: 0.32)
    static let steel = Color(red: 0.41, green: 0.44, blue: 0.48)
    static let silver = Color(red: 0.65, green: 0.68, blue: 0.71)
    static let paper = Color(red: 0.92, green: 0.91, blue: 0.88)
    static let cyan = Color(red: 0.24, green: 0.92, blue: 0.98)
    static let brass = Color(red: 0.77, green: 0.66, blue: 0.42)
}

private struct WorkshopCutPlate: Shape {
    var corner: CGFloat
    func path(in rect: CGRect) -> Path {
        let cut = min(corner, rect.width / 2, rect.height / 2)
        return Path { path in
            path.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + cut))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cut))
            path.addLine(to: CGPoint(x: rect.maxX - cut, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + cut, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cut))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
            path.closeSubpath()
        }
    }
}

private struct WorkshopBenchMat: View {
    var body: some View {
        ZStack {
            WorkshopCutPlate(corner: 19).fill(WorkshopBenchColor.edge).offset(y: 6)
            WorkshopCutPlate(corner: 19)
                .fill(LinearGradient(colors: [Color.white.opacity(0.96), WorkshopBenchColor.paper, WorkshopBenchColor.steel], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(WorkshopCutPlate(corner: 19).stroke(WorkshopBenchColor.edge.opacity(0.7), lineWidth: 1.5))
            WorkshopCutPlate(corner: 14)
                .fill(LinearGradient(colors: [WorkshopBenchColor.edge, WorkshopBenchColor.graphite, WorkshopBenchColor.edge], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(WorkshopCutPlate(corner: 14).stroke(WorkshopBenchColor.ink, lineWidth: 3))
                .overlay(WorkshopCutPlate(corner: 12).stroke(Color.white.opacity(0.09), lineWidth: 1).padding(5))
                .padding(9)
        }.shadow(color: .black.opacity(0.20), radius: 8, y: 6)
    }
}

private struct WorkshopChipHousing: View {
    var corner: CGFloat = 8
    var depth: CGFloat = 6
    var screws = true

    var body: some View {
        ZStack {
            WorkshopCutPlate(corner: corner + 1).fill(WorkshopBenchColor.ink.opacity(0.65)).offset(x: 3, y: depth + 4)
            WorkshopCutPlate(corner: corner)
                .fill(LinearGradient(colors: [WorkshopBenchColor.steel, WorkshopBenchColor.edge], startPoint: .leading, endPoint: .trailing))
                .overlay(WorkshopCutPlate(corner: corner).stroke(WorkshopBenchColor.ink, lineWidth: 1.5)).offset(y: depth)
            WorkshopCutPlate(corner: corner)
                .fill(LinearGradient(colors: [Color(red: 0.97, green: 0.96, blue: 0.93), WorkshopBenchColor.paper, Color(red: 0.79, green: 0.79, blue: 0.78)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(WorkshopCutPlate(corner: corner).stroke(WorkshopBenchColor.ink, lineWidth: 1.6))
                .overlay(WorkshopCutPlate(corner: max(2, corner - 2)).stroke(.white.opacity(0.7), lineWidth: 1).padding(3))
            if screws {
                GeometryReader { geometry in
                    let inset: CGFloat = geometry.size.width < 80 ? 8 : 10
                    ForEach(0..<4, id: \.self) { index in
                        WorkshopBenchScrew()
                            .position(x: index.isMultiple(of: 2) ? inset : geometry.size.width - inset,
                                      y: index < 2 ? inset : geometry.size.height - inset)
                    }
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct WorkshopBenchScrew: View {
    var body: some View {
        ZStack {
            Circle().fill(WorkshopBenchColor.steel).frame(width: 5, height: 5)
                .overlay(Circle().stroke(WorkshopBenchColor.ink.opacity(0.6), lineWidth: 0.6))
            Rectangle().fill(WorkshopBenchColor.ink.opacity(0.6)).frame(width: 3, height: 0.7).rotationEffect(.degrees(-35))
        }.frame(width: 7, height: 7).accessibilityHidden(true)
    }
}
