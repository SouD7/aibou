import SwiftUI
import UniformTypeIdentifiers
#if canImport(CircuitCore)
import CircuitCore
#endif

private enum LabStyle {
    static let ink = Color(red: 0.10, green: 0.16, blue: 0.21)
    static let muted = Color(red: 0.40, green: 0.46, blue: 0.50)
    static let teal = Color(red: 0.00, green: 0.49, blue: 0.55)
    static let mint = Color(red: 0.88, green: 0.97, blue: 0.96)
    static let line = Color(red: 0.84, green: 0.89, blue: 0.90)
    static let background = Color(red: 0.95, green: 0.96, blue: 0.97)
    static let purple = Color(red: 0.43, green: 0.39, blue: 0.65)
}

struct CircuitSandboxView: View {
    @StateObject private var store: CircuitLabStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dropTarget = false
    @State private var showPrediction = false

    init() {
        _store = StateObject(wrappedValue: CircuitLabStore())
    }

    init(store: CircuitLabStore) {
        _store = StateObject(wrappedValue: store)
    }

    private var missionIndex: Int { GateKind.allCases.firstIndex(of: store.state.mission) ?? 0 }
    private var passed: Bool { store.state.verification == .passed }
    private var failed: Bool { store.state.verification == .failed }
    private var lampOn: Bool { store.state.output == .high }

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { viewport in
                ScrollViewReader { scroller in
                    ScrollView(.vertical) {
                        exhibitContent
                            .frame(minHeight: viewport.size.height, alignment: .top)
                    }
                    .onChange(of: store.showHint) { visible in
                        if visible { scroller.scrollTo("hint-panel", anchor: .bottom) }
                    }
                    .onChange(of: store.showDeveloper) { visible in
                        if visible { scroller.scrollTo("developer-panel", anchor: .bottom) }
                    }
                }
            }
            footer
        }
        .background(LabStyle.background)
        .foregroundStyle(LabStyle.ink)
        .preferredColorScheme(.light)
        .frame(minWidth: 1060, minHeight: 750)
        .sheet(isPresented: $showPrediction) { predictionPanel }
    }

    private var exhibitContent: some View {
        HStack(alignment: .top, spacing: 22) {
            sidebar.frame(width: 176)
            VStack(alignment: .leading, spacing: 18) {
                missionHeading
                HStack(alignment: .top, spacing: 18) {
                    VStack(spacing: 0) {
                        board.frame(minHeight: 310, idealHeight: 335, maxHeight: 390)
                        Divider().overlay(LabStyle.line)
                        palette
                    }
                    .background(.white, in: RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(LabStyle.line, lineWidth: 1))
                    inspector.frame(width: 245)
                }
                actionBar
                if store.showHint { hintPanel.id("hint-panel") }
                if store.showDeveloper { developerPanel.id("developer-panel") }
                if !store.notice.isEmpty {
                    Text(store.notice).font(.caption).foregroundStyle(LabStyle.muted)
                        .accessibilityIdentifier("game.notice")
                }
                Spacer(minLength: 0)
            }
        }.padding(.horizontal, 26).padding(.top, 24).padding(.bottom, 14)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: "sparkle").foregroundStyle(LabStyle.teal)
                Text("aibou").font(.system(size: 27, weight: .semibold, design: .rounded))
            }
            Rectangle().fill(LabStyle.line).frame(width: 1, height: 24).padding(.horizontal, 6)
            Text("あそんで、わかる。").font(.system(size: 13, weight: .medium)).foregroundStyle(LabStyle.muted)
            Spacer()
            Label("ハードウェアの小さな実験室", systemImage: "square.stack.3d.up")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(LabStyle.muted)
            Button { store.showHint.toggle() } label: {
                Label("ヒント", systemImage: "lightbulb")
            }.buttonStyle(LabButtonStyle()).accessibilityIdentifier("game.hint")
        }.padding(.horizontal, 28).padding(.vertical, 18)
        .background(.white)
        .overlay(alignment: .bottom) { Rectangle().fill(LabStyle.line).frame(height: 1) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 7) {
                Text("EXHIBIT 01").font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2.4).foregroundStyle(LabStyle.teal)
                Text("回路の\nアトリエ").font(.system(size: 29, weight: .bold, design: .rounded)).lineSpacing(5)
                Text("ふたつの合図で、\n光をつくろう。").font(.system(size: 13)).lineSpacing(5).foregroundStyle(LabStyle.muted)
            }
            VStack(spacing: 8) {
                ForEach(Array(GateKind.allCases.enumerated()), id: \.element) { index, gate in
                    Button { store.chooseMission(gate) } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().fill(store.state.mission == gate ? LabStyle.teal : Color.white).frame(width: 29, height: 29)
                                if store.state.completedMissions.contains(gate) {
                                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                                } else {
                                    Text(String(format: "%02d", index + 1)).font(.system(size: 11, weight: .bold, design: .monospaced))
                                }
                            }.foregroundStyle(store.state.mission == gate ? .white : LabStyle.muted)
                            Text(shortTitle(gate)).font(.system(size: 12, weight: .semibold))
                            Spacer(minLength: 0)
                        }.padding(10)
                        .background(store.state.mission == gate ? LabStyle.mint : Color.clear, in: RoundedRectangle(cornerRadius: 13))
                    }.buttonStyle(.plain).accessibilityIdentifier("stage.\(index)")
                    .accessibilityLabel("実験\(index + 1) \(shortTitle(gate))")
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 27)).foregroundStyle(LabStyle.purple)
                Text("小さな回路が、\n計算のはじまり。").font(.system(size: 13, weight: .semibold)).lineSpacing(4)
                Text("CPUの中でも、0と1を扱う回路が組み合わさって働いているよ。")
                    .font(.system(size: 11)).lineSpacing(5).foregroundStyle(LabStyle.muted)
            }.padding(15).background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var missionHeading: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("実験 \(String(format: "%02d", missionIndex + 1)) / 03")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(LabStyle.teal)
                Spacer()
                Text("選ぶ → つなぐ → 試す").font(.system(size: 11, weight: .medium)).foregroundStyle(LabStyle.muted)
            }
            Text(goal(store.state.mission)).font(.system(size: 22, weight: .bold))
            Text("パーツを置いて3本の線をつなごう。A・Bはいつでも切り替えられるよ。")
                .font(.system(size: 12)).foregroundStyle(LabStyle.muted)
        }
    }

    private var board: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                Canvas { context, size in
                    for x in stride(from: 20.0, to: size.width, by: 22) {
                        for y in stride(from: 20.0, to: size.height, by: 22) {
                            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)), with: .color(LabStyle.line.opacity(0.55)))
                        }
                    }
                }.accessibilityHidden(true)
                VStack {
                    HStack {
                        Label("回路ボード", systemImage: "cpu").font(.system(size: 11, weight: .semibold))
                        Spacer()
                        HStack(spacing: 5) {
                            Circle().fill(store.fullyConnected ? LabStyle.teal : LabStyle.muted.opacity(0.5)).frame(width: 5, height: 5)
                            Text(store.fullyConnected ? "接続できた" : "\(store.state.links.count) / 3 本 接続")
                        }.font(.system(size: 10, weight: .medium)).foregroundStyle(LabStyle.muted)
                    }
                    Spacer()
                    Text(store.fullyConnected ? "スイッチを切り替えて、ランプの変化を観察しよう。" : "下のパーツを選び、「つなぐ」で信号の通り道を作ろう。")
                        .font(.system(size: 11)).foregroundStyle(LabStyle.muted)
                }.padding(20)

                circuitWire(from: CGPoint(x: w * 0.20, y: h * 0.33), to: CGPoint(x: w * 0.43, y: h * 0.40), link: .inputA, high: store.state.inputs.a)
                circuitWire(from: CGPoint(x: w * 0.20, y: h * 0.67), to: CGPoint(x: w * 0.43, y: h * 0.60), link: .inputB, high: store.state.inputs.b)
                circuitWire(from: CGPoint(x: w * 0.66, y: h * 0.50), to: CGPoint(x: w * 0.84, y: h * 0.50), link: .output, high: lampOn)
                inputSwitch(.a).position(x: w * 0.12, y: h * 0.33)
                inputSwitch(.b).position(x: w * 0.12, y: h * 0.67)
                gateSlot.frame(width: w * 0.235, height: 142).position(x: w * 0.545, y: h * 0.50)
                lamp.position(x: w * 0.89, y: h * 0.50)
                wireButton(.inputA, label: "A", id: "a").position(x: w * 0.305, y: h * 0.29)
                wireButton(.inputB, label: "B", id: "b").position(x: w * 0.305, y: h * 0.71)
                wireButton(.output, label: "出力", id: "output").position(x: w * 0.755, y: h * 0.64)
            }
        }
    }

    private func circuitWire(from start: CGPoint, to end: CGPoint, link: CircuitLink, high: Bool) -> some View {
        let connected = store.state.links.contains(link)
        return Path { path in
            path.move(to: start)
            let middle = (start.x + end.x) / 2
            path.addCurve(to: end, control1: CGPoint(x: middle, y: start.y), control2: CGPoint(x: middle, y: end.y))
        }
        .stroke(connected ? (high ? LabStyle.teal : LabStyle.muted) : LabStyle.line,
                style: StrokeStyle(lineWidth: connected ? 3 : 2, lineCap: .round, dash: connected ? [] : [4, 6]))
        .accessibilityHidden(true)
    }

    private func inputSwitch(_ input: CircuitInput) -> some View {
        let on = input == .a ? store.state.inputs.a : store.state.inputs.b
        let name = input == .a ? "A" : "B"
        return Button { store.act(.toggleInput(input)) } label: {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text(name).font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(on ? "1" : "0").font(.system(size: 12, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(on ? LabStyle.mint : LabStyle.background, in: RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(on ? LabStyle.teal : LabStyle.muted)
                }
                ZStack(alignment: on ? .trailing : .leading) {
                    Capsule().fill(on ? LabStyle.teal : LabStyle.line).frame(width: 62, height: 32)
                    Circle().fill(.white).frame(width: 24, height: 24).shadow(color: .black.opacity(0.08), radius: 2, y: 1).padding(4)
                }
                Text(on ? "ON" : "OFF").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(LabStyle.muted)
            }
        }.buttonStyle(.plain)
        .accessibilityIdentifier("input.\(name.lowercased())")
        .accessibilityLabel("入力\(name) \(on ? "1 ON" : "0 OFF")")
        .help("クリックで入力\(name)を切り替える")
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: on)
    }

    private var gateSlot: some View {
        VStack(spacing: 9) {
            if let gate = store.state.selectedGate {
                Text(gate.rawValue.uppercased()).font(.system(size: 25, weight: .bold, design: .rounded))
                Text(gateNotation(gate)).font(.system(size: 16, weight: .medium, design: .monospaced)).foregroundStyle(LabStyle.teal)
                Text("入力 → ルール → 出力").font(.system(size: 9)).foregroundStyle(LabStyle.muted)
            } else {
                Image(systemName: "square.dashed.inset.filled").font(.system(size: 25)).foregroundStyle(LabStyle.teal)
                Text("パーツを置こう").font(.system(size: 12, weight: .semibold))
                Text("下から選ぶ / ドラッグ").font(.system(size: 9)).foregroundStyle(LabStyle.muted)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(dropTarget ? LabStyle.mint : Color.white, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(store.state.selectedGate == nil ? LabStyle.line : LabStyle.teal, style: StrokeStyle(lineWidth: 2, dash: store.state.selectedGate == nil ? [5, 4] : [])))
        .shadow(color: LabStyle.ink.opacity(0.04), radius: 10, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("回路パーツの置き場所。\(store.state.selectedGate?.title ?? "空")")
        .accessibilityIdentifier("gate.slot")
        .onDrop(of: [UTType.plainText], isTargeted: $dropTarget) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                guard let raw = value as? String, let gate = GateKind(rawValue: raw) else { return }
                Task { @MainActor in store.act(.selectGate(gate)) }
            }
            return true
        }
    }

    private var lamp: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(lampOn ? Color(red: 0.98, green: 0.88, blue: 0.47).opacity(0.22) : LabStyle.background).frame(width: 73, height: 73)
                Image(systemName: lampOn ? "lightbulb.fill" : "lightbulb")
                    .font(.system(size: 37, weight: .light)).foregroundStyle(lampOn ? Color(red: 0.78, green: 0.52, blue: 0.07) : LabStyle.muted)
            }
            Text(store.state.output == .unknown ? "? 未接続" : (lampOn ? "1 点灯" : "0 消灯"))
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(lampOn ? LabStyle.teal : LabStyle.muted)
        }.accessibilityElement(children: .ignore)
        .accessibilityLabel("出力ランプ。\(store.state.output == .unknown ? "未接続" : (lampOn ? "1 点灯" : "0 消灯"))")
        .accessibilityIdentifier("game.lamp")
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: lampOn)
    }

    private func wireButton(_ link: CircuitLink, label: String, id: String) -> some View {
        let connected = store.state.links.contains(link)
        return Button { store.act(.toggleLink(link)) } label: {
            HStack(spacing: 3) {
                Image(systemName: connected ? "link" : "plus").font(.system(size: 8, weight: .bold))
                Text(connected ? "接続済" : "つなぐ").font(.system(size: 9, weight: .semibold))
            }.padding(.horizontal, 7).padding(.vertical, 5)
                .background(.white, in: Capsule()).overlay(Capsule().stroke(connected ? LabStyle.teal.opacity(0.5) : LabStyle.line))
                .foregroundStyle(connected ? LabStyle.teal : LabStyle.muted)
        }.buttonStyle(.plain).disabled(store.state.selectedGate == nil)
        .accessibilityIdentifier("link.\(id)")
        .accessibilityLabel("\(label)の配線 \(connected ? "接続済み。切り離す" : "つなぐ")")
        .help(connected ? "\(label)の線を切り離す" : "\(label)の線をつなぐ")
    }

    private var palette: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("使えるパーツ").font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("クリックでも置けるよ").font(.system(size: 10)).foregroundStyle(LabStyle.muted)
            }
            HStack(spacing: 10) {
                ForEach(GateKind.allCases, id: \.self) { gate in
                    let selected = store.state.selectedGate == gate
                    Button { store.act(.selectGate(gate)) } label: {
                        HStack(spacing: 10) {
                            Text(gateNotation(gate)).font(.system(size: 19, weight: .medium, design: .monospaced))
                                .frame(width: 31, height: 38).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(gate.rawValue.uppercased()).font(.system(size: 13, weight: .bold, design: .rounded))
                                Text(gateSubtitle(gate)).font(.system(size: 9)).foregroundStyle(LabStyle.muted)
                            }
                            Spacer(minLength: 0)
                        }.padding(10).frame(maxWidth: .infinity)
                        .background(selected ? LabStyle.mint : LabStyle.background, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? LabStyle.teal : Color.clear, lineWidth: 1.5))
                    }.buttonStyle(.plain).accessibilityIdentifier("gate.\(gate.rawValue)")
                    .accessibilityLabel("\(gate.rawValue.uppercased()) パーツを置く")
                    .onDrag { NSItemProvider(object: gate.rawValue as NSString) }
                }
            }
        }.padding(18)
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "list.bullet.rectangle").foregroundStyle(LabStyle.teal)
                Text("この回路の約束").font(.system(size: 13, weight: .bold))
            }
            VStack(spacing: 0) {
                HStack {
                    Text("A").frame(width: 25)
                    Text("B").frame(width: 25)
                    Spacer()
                    Text("目標").frame(width: 34)
                    Text("結果").frame(width: 34)
                }.font(.system(size: 10, weight: .semibold)).foregroundStyle(LabStyle.muted).padding(.horizontal, 10).padding(.vertical, 10)
                ForEach(0..<4) { index in
                    let a = index >= 2
                    let b = index % 2 == 1
                    let check = store.state.checks.first { $0.inputs.a == a && $0.inputs.b == b }
                    HStack {
                        Text(a ? "1" : "0").frame(width: 25)
                        Text(b ? "1" : "0").frame(width: 25)
                        Spacer()
                        Text(expected(a, b, gate: store.state.mission) ? "1" : "0").frame(width: 34)
                        HStack(spacing: 2) {
                            Text(check.map { signal($0.actual) } ?? "—")
                            if let check { Image(systemName: check.passed ? "checkmark" : "xmark").font(.system(size: 8, weight: .bold)) }
                        }.frame(width: 34).foregroundStyle(check == nil ? LabStyle.muted : (check!.passed ? LabStyle.teal : Color(red: 0.73, green: 0.30, blue: 0.18)))
                    }.font(.system(size: 13, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 10).padding(.vertical, 12)
                        .background(store.state.inputs.a == a && store.state.inputs.b == b ? LabStyle.mint : Color.clear)
                        .overlay(alignment: .top) { Rectangle().fill(LabStyle.line.opacity(0.5)).frame(height: 1) }
                }
            }.background(.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(LabStyle.line))
                .accessibilityElement(children: .contain).accessibilityIdentifier("game.truthTable")
            feedback
        }
    }

    @ViewBuilder private var feedback: some View {
        if passed {
            VStack(alignment: .leading, spacing: 11) {
                Label("回路ができた！", systemImage: "checkmark.seal.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(LabStyle.teal)
                    .accessibilityIdentifier("game.success")
                Text("4通りすべてで、目標どおりに動いたよ。")
                    .font(.system(size: 11)).lineSpacing(4)
                Divider()
                Button { showPrediction = true } label: {
                    Label("別の場面で予想する", systemImage: "thought.bubble")
                }.buttonStyle(LabButtonStyle()).accessibilityIdentifier("prediction.open")
                Button { store.next() } label: {
                    HStack { Text(missionIndex == 2 ? "もう一度、自由に試す" : "次の実験へ"); Spacer(); Image(systemName: "arrow.right") }
                }.buttonStyle(LabButtonStyle(prominent: true)).accessibilityIdentifier("game.next")
                Text("予想はあとでも大丈夫。").font(.system(size: 9)).foregroundStyle(LabStyle.muted)
            }.padding(15).background(LabStyle.mint, in: RoundedRectangle(cornerRadius: 16))
        } else if failed {
            VStack(alignment: .leading, spacing: 9) {
                Label("もう少し！", systemImage: "arrow.trianglehead.clockwise").font(.system(size: 15, weight: .bold)).accessibilityIdentifier("game.failure")
                if let wrong = store.state.checks.first(where: { !$0.passed }) {
                    Text("A=\(wrong.inputs.a ? 1 : 0)、B=\(wrong.inputs.b ? 1 : 0) のとき")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    Text("目標は \(wrong.expected ? 1 : 0)、この回路は \(signal(wrong.actual))。パーツを変えて、違いを試してみよう。")
                        .font(.system(size: 11)).lineSpacing(4)
                    Button("この入力で観察する") { store.act(.setInputs(wrong.inputs)) }
                        .buttonStyle(LabButtonStyle()).accessibilityIdentifier("game.counterexample")
                }
            }.padding(15).background(Color(red: 1, green: 0.95, blue: 0.88), in: RoundedRectangle(cornerRadius: 16))
        } else {
            VStack(alignment: .leading, spacing: 9) {
                Label(store.state.checks.isEmpty ? "まずは、触ってみよう" : "一条件ずつ観察中", systemImage: "hand.tap")
                    .font(.system(size: 12, weight: .semibold))
                Text(store.state.checks.isEmpty ? "入力の0と1を変えると、どうなる？ 間違えても、何度でも試せるよ。" : "表の結果が埋まっていくよ。「4条件を確かめる」でまとめて試せるよ。")
                    .font(.system(size: 11)).lineSpacing(4).foregroundStyle(LabStyle.muted)
            }.padding(15).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func predictionButton(_ value: Bool) -> some View {
        Button(value ? "つく（1）" : "つかない（0）") { store.act(.predict(value)) }
            .buttonStyle(LabButtonStyle(prominent: store.state.prediction.answer == value))
            .accessibilityIdentifier(value ? "prediction.one" : "prediction.zero")
    }

    private var predictionPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("場面を変えて考えよう", systemImage: "thought.bubble").font(.title3.bold())
                Spacer()
                Button { showPrediction = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("予想を閉じる")
            }
            Text(transferPrompt).font(.system(size: 16)).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
            Text("同じ回路でも、入力の名前を変えると身近な仕組みになる。").font(.system(size: 12)).foregroundStyle(LabStyle.muted)
            HStack(spacing: 12) { predictionButton(false); predictionButton(true) }
            if let answer = store.state.prediction.answer {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.state.prediction.isCorrect == true ? "そのとおり！" : "今回は\(answer ? "消灯（0）" : "点灯（1）")になるよ。")
                        .font(.headline).foregroundStyle(LabStyle.teal)
                    Text(transferReason).font(.system(size: 13)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(LabStyle.mint, in: RoundedRectangle(cornerRadius: 13))
                    .accessibilityIdentifier("prediction.feedback")
            }
            Spacer(minLength: 0)
            HStack {
                Button("回路で確かめる") {
                    store.act(.setInputs(store.state.prediction.inputs))
                    showPrediction = false
                }.buttonStyle(LabButtonStyle()).accessibilityIdentifier("prediction.observe")
                Spacer()
                Button("閉じる") { showPrediction = false }.buttonStyle(LabButtonStyle(prominent: true))
            }
        }.padding(28).frame(width: 560, height: 490).foregroundStyle(LabStyle.ink).background(.white)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button { store.act(.selectMission(store.state.mission)) } label: {
                Label("やり直す", systemImage: "arrow.counterclockwise")
            }.buttonStyle(LabButtonStyle()).accessibilityIdentifier("game.reset")
            Spacer()
            Button { store.act(.step) } label: {
                Label("1条件ずつ", systemImage: "forward.end")
            }.buttonStyle(LabButtonStyle()).disabled(!store.fullyConnected).accessibilityIdentifier("game.step")
            Button { store.act(.verify) } label: {
                Label("4条件を確かめる", systemImage: "play.fill")
            }.buttonStyle(LabButtonStyle(prominent: true)).disabled(!store.fullyConnected)
                .accessibilityIdentifier("game.check").keyboardShortcut(.return, modifiers: [.command])
        }
    }

    private var hintPanel: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb").foregroundStyle(LabStyle.purple)
            VStack(alignment: .leading, spacing: 5) {
                Text("違いが出る入力を探そう").font(.system(size: 12, weight: .bold))
                Text("ANDは両方が1のとき、ORは少なくとも片方が1のとき、XORは片方だけが1のときに1を出すよ。片方だけONと、両方ONを比べてみよう。")
                    .font(.system(size: 11)).lineSpacing(4)
            }
            Spacer()
            Button { store.showHint = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("ヒントを閉じる")
        }.padding(14).background(Color.white, in: RoundedRectangle(cornerRadius: 14))
    }

    private var developerPanel: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("開発用の記録").font(.system(size: 11, weight: .bold))
                Text(String(format: "seed %llu · モデル処理 %.1f μs", store.state.seed, store.actionMicroseconds))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(LabStyle.muted)
                Spacer()
            }
            HStack {
                Button("状態・操作を書き出す") { store.exportEvidence() }.accessibilityIdentifier("game.export")
                Button("記録を再生") { store.replayExport() }.disabled(!store.canReplay).accessibilityIdentifier("game.replay")
                if store.exportedDirectory != nil { Button("保存先を開く") { store.revealExport() } }
            }.buttonStyle(LabButtonStyle())
            Text("操作再生は内部モデルの再現確認です。画面操作の検証とは別に記録します。")
                .font(.system(size: 9)).foregroundStyle(LabStyle.muted)
        }.padding(12).background(.white, in: RoundedRectangle(cornerRadius: 12))
    }

    private var footer: some View {
        HStack {
            Text("0 = OFF / 1 = ON").font(.system(size: 10, weight: .medium, design: .monospaced))
            Circle().fill(LabStyle.line).frame(width: 3, height: 3)
            Text("電圧や伝わる時間を省いた、論理回路のモデルです。").font(.system(size: 10))
            Spacer()
            Button { store.showDeveloper.toggle() } label: {
                Label("開発用の記録", systemImage: "curlybraces")
            }.buttonStyle(.plain).font(.system(size: 10)).accessibilityIdentifier("game.developer")
        }.foregroundStyle(LabStyle.muted).padding(.horizontal, 28).padding(.vertical, 12)
    }

    private func expected(_ a: Bool, _ b: Bool, gate: GateKind) -> Bool {
        switch gate { case .and: return a && b; case .or: return a || b; case .xor: return a != b }
    }
    private func signal(_ value: LogicSignal) -> String {
        switch value { case .low: return "0"; case .high: return "1"; case .unknown: return "?" }
    }
    private func shortTitle(_ gate: GateKind) -> String {
        switch gate { case .and: return "ふたりの合図"; case .or: return "どちらかの合図"; case .xor: return "ひとつだけの合図" }
    }
    private func goal(_ gate: GateKind) -> String {
        switch gate {
        case .and: return "AとBが両方ONのときだけ、光らせよう。"
        case .or: return "少なくとも片方がONなら、光らせよう。"
        case .xor: return "AとBの片方だけがONなら、光らせよう。"
        }
    }
    private func gateNotation(_ gate: GateKind) -> String {
        switch gate { case .and: return "＆"; case .or: return "≥1"; case .xor: return "=1" }
    }
    private func gateSubtitle(_ gate: GateKind) -> String {
        switch gate { case .and: return "両方が1"; case .or: return "片方でも両方でも1"; case .xor: return "片方だけ1" }
    }
    private var transferPrompt: String {
        let p = store.state.prediction.inputs
        return "A・Bを2つのセンサーに置き換えたよ。Aが\(p.a ? "反応" : "無反応")、Bが\(p.b ? "反応" : "無反応")なら、このランプは？"
    }
    private var transferReason: String {
        let p = store.state.prediction.inputs
        return "反応を1、無反応を0とすると、A=\(p.a ? 1 : 0)、B=\(p.b ? 1 : 0)。\(store.state.mission.explanation)"
    }
}

private struct LabButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .foregroundStyle(prominent ? Color.white : LabStyle.ink)
            .background(prominent ? LabStyle.teal : Color.white, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(prominent ? Color.clear : LabStyle.line))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.38)
    }
}
