import SwiftUI
#if canImport(CircuitCore)
import CircuitCore
#endif

/// A completed work is independent of the editable workshop. Inputs are local
/// to this sheet; the saved circuit and its recorded observations stay intact.
struct WorkshopArtifactView: View {
    let artifact: WorkshopArtifact
    let onClose: () -> Void
    @State private var inputs: InputPair

    init(artifact: WorkshopArtifact, onClose: @escaping () -> Void) {
        self.artifact = artifact
        self.onClose = onClose
        _inputs = State(initialValue: artifact.circuit.inputs)
    }

    private var gate: GateKind? { artifact.circuit.selectedGate }
    private var output: LogicSignal {
        guard artifact.circuit.isConnected, let gate else { return .unknown }
        return LogicSignal(gate.evaluate(inputs))
    }
    private var observedCount: Int {
        InputPair.truthTable.filter { pair in artifact.observations.contains { $0.inputs == pair } }.count
    }
    private var verified: Bool {
        artifact.circuit.verification == .passed && artifact.circuit.checks.count == 4
            && artifact.circuit.checks.allSatisfy(\.passed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("日記", systemImage: "book.closed").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("閉じる", action: onClose)
                    .buttonStyle(WorkshopButtonStyle())
                    .accessibilityIdentifier("w.artifact.close")
                    .keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("01  ふたりの準備完了ランプ")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                        Text("完成したときの回路を、ここで動かしてみよう。")
                            .font(.system(size: 13)).foregroundStyle(WorkshopStyle.muted)
                    }
                    liveCircuit
                    HStack(spacing: 8) {
                        Image(systemName: verified ? "checkmark.seal.fill" : "circle.dashed")
                            .foregroundStyle(WorkshopStyle.teal)
                        Text(verified ? "保存した回路は、4通りとも目標どおり。" : "保存した回路の記録")
                            .font(.system(size: 12, weight: .medium))
                    }
                    observationNotebook
                    Text(gate?.explanation ?? "この作品には部品がありません。")
                        .font(.system(size: 13)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    Text("日記では、完成した回路を繰り返し試せます。")
                        .font(.system(size: 11)).foregroundStyle(WorkshopStyle.muted)
                }.padding(.bottom, 2)
            }
        }
        .padding(28).frame(width: 560, height: 680)
        .foregroundStyle(WorkshopStyle.ink).background(WorkshopStyle.paper)
    }

    private var liveCircuit: some View {
        VStack(spacing: 13) {
            HStack {
                Text("スイッチを切り替えてみよう").font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(artifact.circuit.links.count) / 3 本 接続")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(WorkshopStyle.muted)
            }
            GeometryReader { geometry in
                let size = geometry.size
                ZStack {
                    artifactWire(.inputA, from: CGPoint(x: size.width * 0.23, y: 37),
                                 to: CGPoint(x: size.width * 0.42, y: 61),
                                 signal: LogicSignal(inputs.a))
                    artifactWire(.inputB, from: CGPoint(x: size.width * 0.23, y: 121),
                                 to: CGPoint(x: size.width * 0.42, y: 97),
                                 signal: LogicSignal(inputs.b))
                    artifactWire(.output, from: CGPoint(x: size.width * 0.64, y: 79),
                                 to: CGPoint(x: size.width * 0.80, y: 79), signal: output)
                    inputButton(.a).position(x: size.width * 0.115, y: 37)
                    inputButton(.b).position(x: size.width * 0.115, y: 121)
                    VStack(spacing: 8) {
                        Image(systemName: "cpu").font(.system(size: 22, weight: .light)).foregroundStyle(WorkshopStyle.teal)
                        Text(gate?.title ?? "未配置").font(.system(size: 16, weight: .semibold, design: .rounded))
                    }.frame(width: size.width * 0.22, height: 99)
                        .background(WorkshopStyle.paper, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(WorkshopStyle.line, lineWidth: 1))
                        .position(x: size.width * 0.53, y: 79)
                    lamp.position(x: size.width * 0.90, y: 79)
                }
            }.frame(height: 163)
        }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(WorkshopStyle.line, lineWidth: 1))
    }

    private func artifactWire(_ link: CircuitLink, from start: CGPoint, to end: CGPoint,
                              signal: LogicSignal) -> some View {
        let connected = artifact.circuit.links.contains(link)
        return Path { path in
            path.move(to: start)
            let middle = (start.x + end.x) / 2
            path.addCurve(to: end, control1: CGPoint(x: middle, y: start.y),
                          control2: CGPoint(x: middle, y: end.y))
        }.stroke(connected ? (signal == .high ? WorkshopStyle.teal : WorkshopStyle.muted) : WorkshopStyle.line,
                 style: StrokeStyle(lineWidth: connected ? 3 : 1.5, lineCap: .round, dash: connected ? [] : [3, 5]))
            .accessibilityHidden(true).allowsHitTesting(false)
    }

    private func inputButton(_ input: CircuitInput) -> some View {
        let on = input == .a ? inputs.a : inputs.b
        return Button {
            if input == .a { inputs.a.toggle() } else { inputs.b.toggle() }
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 5) {
                    Text(input == .a ? "A" : "B").font(.system(size: 11, weight: .semibold))
                    Text(on ? "1" : "0").font(.system(size: 12, weight: .bold, design: .monospaced))
                }
                ZStack(alignment: on ? .trailing : .leading) {
                    Capsule().fill(on ? WorkshopStyle.teal : WorkshopStyle.line).frame(width: 52, height: 28)
                    Circle().fill(.white).frame(width: 20, height: 20).padding(4)
                }
                Text(on ? "準備できた" : "準備前")
                    .font(.system(size: 9)).foregroundStyle(WorkshopStyle.muted)
            }.frame(width: 84)
        }.buttonStyle(.plain)
            .accessibilityLabel("作品の入力\(input.rawValue.uppercased())。\(on ? "1 準備できた" : "0 準備前")")
            .accessibilityIdentifier("w.artifact.input.\(input.rawValue)")
    }

    private var lamp: some View {
        let high = output == .high
        let label = output == .unknown ? "? 未接続" : high ? "1 点灯" : "0 消灯"
        return VStack(spacing: 9) {
            Image(systemName: high ? "lightbulb.fill" : "lightbulb")
                .font(.system(size: 31, weight: .light))
                .foregroundStyle(high ? WorkshopStyle.amber : WorkshopStyle.muted)
                .frame(width: 56, height: 56)
                .background(high ? Color.yellow.opacity(0.13) : WorkshopStyle.paper, in: Circle())
            Text(label).font(.system(size: 11, weight: .medium))
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel("作品のランプ。\(label)")
            .accessibilityIdentifier("w.artifact.lamp")
    }

    private var observationNotebook: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("保存した観察ノート", systemImage: "book.pages").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(observedCount) / 4 通り").font(.system(size: 10)).foregroundStyle(WorkshopStyle.muted)
            }
            VStack(spacing: 0) {
                HStack {
                    Text("A").frame(width: 28)
                    Text("B").frame(width: 28)
                    Spacer()
                    Text("目標").frame(width: 56)
                    Text("保存時の結果").frame(width: 85)
                }.font(.system(size: 10)).foregroundStyle(WorkshopStyle.muted)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                ForEach(Array(InputPair.truthTable.enumerated()), id: \.offset) { _, pair in
                    let row = artifact.observations.first { $0.inputs == pair }
                    HStack {
                        Text(pair.a ? "1" : "0").frame(width: 28)
                        Text(pair.b ? "1" : "0").frame(width: 28)
                        Spacer()
                        Text(row.map { $0.expected ? "1" : "0" } ?? "—").frame(width: 56)
                        Text(row?.actual.label ?? "未観察").frame(width: 85)
                    }.font(.system(size: 12, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(inputs == pair ? WorkshopStyle.mint : Color.white)
                        .overlay(alignment: .top) { Rectangle().fill(WorkshopStyle.line.opacity(0.6)).frame(height: 0.5) }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("保存時の観察。A\(pair.a ? 1 : 0)、B\(pair.b ? 1 : 0)、目標\(row.map { $0.expected ? "1" : "0" } ?? "未記録")、結果\(row?.actual.label ?? "未観察")")
                }
            }.background(.white, in: RoundedRectangle(cornerRadius: 13))
                .clipShape(RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(WorkshopStyle.line, lineWidth: 1))
        }
    }
}
