import SwiftUI
#if canImport(CircuitCore)
import CircuitCore
#endif

/// Small, event-driven models. Every value belongs to the lesson, never to the
/// user's machine. The host resets these states by changing the lesson identity.
struct LessonActivityView: View {
    let kind: LessonActivityKind
    var onExplore: () -> Void

    @State private var bits = [false, false, false, false, false, false, true, true]
    @State private var inputA = false
    @State private var inputB = false
    @State private var mode = 0
    @State private var stored = false
    @State private var count = 1
    @State private var countB = 1
    @State private var countC = 1
    @State private var saved = false
    @State private var occupied = true
    @State private var cacheReady = false
    @State private var requests = 0
    @State private var cacheHit = false

    init(kind: LessonActivityKind, onExplore: @escaping () -> Void) {
        self.kind = kind
        self.onExplore = onExplore
        // The compression lesson starts with the original representation, so
        // the first compression action produces an observable change.
        _inputB = State(initialValue: kind == .compression)
    }

    private let ink = Color(red: 0.12, green: 0.16, blue: 0.20)
    private let paper = Color(red: 0.98, green: 0.96, blue: 0.92)
    private let cyan = Color(red: 0.24, green: 0.82, blue: 0.90)
    private let lavender = Color(red: 0.73, green: 0.63, blue: 0.93)
    private let amber = Color(red: 1.0, green: 0.78, blue: 0.36)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("触ってたしかめる", systemImage: "hand.tap")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
                Text("しくみの模型 · 実測値ではありません")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }
            experiment.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(18)
        .foregroundStyle(.white)
        .background(RoundedRectangle(cornerRadius: 20).fill(ink))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.12), lineWidth: 1))
        .accessibilityIdentifier("lesson.activity")
    }

    @ViewBuilder private var experiment: some View {
        switch kind {
        case .bits: bitsExperiment
        case .logic: logicExperiment
        case .latch: latchExperiment
        case .transistor: transistorExperiment
        case .instructions: instructionsExperiment
        case .schedule: scheduleExperiment
        case .parallel: parallelExperiment
        case .pixels: pixelsExperiment
        case .memory: memoryExperiment
        case .cache: cacheExperiment
        case .compression: compressionExperiment
        case .storage: storageExperiment
        case .frames: framesExperiment
        case .network: networkExperiment
        case .bus: busExperiment
        case .ports: portsExperiment
        case .flow: flowExperiment
        case .battery: batteryExperiment
        case .cooling: coolingExperiment
        case .bottleneck: bottleneckExperiment
        }
    }

    private func act(_ change: () -> Void) {
        change()
        onExplore()
    }

    private func button(_ title: String, id: String, accent: Color? = nil,
                        action: @escaping () -> Void) -> some View {
        Button { act(action) } label: {
            Text(title).font(.system(size: 18, weight: .bold, design: .rounded))
                .frame(minWidth: 50, minHeight: 42)
                .padding(.horizontal, 14)
                .foregroundStyle(ink)
                .background(RoundedRectangle(cornerRadius: 10).fill(accent ?? paper))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("lesson.activity.\(id)")
        .accessibilityLabel(title)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 17, weight: .medium))
            .foregroundStyle(.white.opacity(0.86))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.07)))
    }

    private func metric(_ value: String, _ label: String, color: Color? = nil) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 31, weight: .bold, design: .rounded))
                .foregroundStyle(color ?? cyan).monospacedDigit()
            Text(label).font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.70))
        }.frame(maxWidth: .infinity)
    }

    private func module(_ title: String, icon: String, active: Bool = true,
                        color: Color? = nil, minimumHeight: CGFloat = 95) -> some View {
        VStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 30, weight: .medium)).accessibilityHidden(true)
            Text(title).font(.system(size: 18, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(active ? ink : .white.opacity(0.55))
        .frame(maxWidth: .infinity, minHeight: minimumHeight)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 13).fill(active ? (color ?? cyan) : .white.opacity(0.07)))
    }

    private var arrow: some View {
        Image(systemName: "arrow.right").font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.white.opacity(0.50)).frame(width: 25)
            .accessibilityHidden(true)
    }

    private func cells(_ filled: Int, total: Int, color: Color? = nil, height: CGFloat = 34) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { index in
                RoundedRectangle(cornerRadius: 5)
                    .fill(index < filled ? (color ?? cyan) : .white.opacity(0.09))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.12)))
            }
        }.frame(height: height).accessibilityElement(children: .ignore)
            .accessibilityLabel("\(total)枠のうち\(filled)枠を使用")
    }

    private func selector(_ label: String, value: Int, range: ClosedRange<Int>, id: String,
                          change: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 18, weight: .medium))
            button("−", id: "\(id).decrease") { change(max(range.lowerBound, value - 1)) }
                .disabled(value == range.lowerBound)
                .disabled(value == range.lowerBound)
                .opacity(value == range.lowerBound ? 0.40 : 1)
                .accessibilityLabel("\(label)を減らす")
            Text("\(value)").font(.system(size: 23, weight: .bold, design: .rounded))
                .monospacedDigit().frame(minWidth: 30)
            button("＋", id: "\(id).increase") { change(min(range.upperBound, value + 1)) }
                .disabled(value == range.upperBound)
                .disabled(value == range.upperBound)
                .opacity(value == range.upperBound ? 0.40 : 1)
                .accessibilityLabel("\(label)を増やす")
        }
    }

    private var bitsExperiment: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                ForEach(0..<8, id: \.self) { index in
                    VStack(spacing: 7) {
                        Text("\(1 << (7 - index))").font(.system(size: 16, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.65))
                        button(bits[index] ? "1" : "0", id: "bit.\(index)", accent: bits[index] ? cyan : paper) {
                            bits[index].toggle()
                        }.accessibilityLabel("重み\(1 << (7 - index))のビットを切り替える")
                            .accessibilityValue(bits[index] ? "1" : "0")
                    }
                }
            }
            metric("\(bits.enumerated().reduce(0) { $0 + ($1.element ? 1 << (7 - $1.offset) : 0) })", "1になった重みの合計")
            note("どのスイッチを1にすると、数がいくつ増える？ 8ビットで0〜255を表せるよ。")
        }
    }

    private var logicValue: Bool { mode == 0 ? inputA && inputB : inputA || inputB }
    private var logicExperiment: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                VStack(spacing: 12) {
                    button("A  \(inputA ? 1 : 0)", id: "logic.a", accent: inputA ? cyan : paper) { inputA.toggle() }
                    button("B  \(inputB ? 1 : 0)", id: "logic.b", accent: inputB ? cyan : paper) { inputB.toggle() }
                }
                arrow
                module(mode == 0 ? "AND\n両方が1" : "OR\nどちらかが1", icon: "cpu", color: lavender)
                arrow
                module(logicValue ? "1 · 点灯" : "0 · 消灯", icon: logicValue ? "lightbulb.fill" : "lightbulb", active: logicValue)
            }
            button(mode == 0 ? "ORに替える" : "ANDに替える", id: "logic.gate") { mode = mode == 0 ? 1 : 0 }
            note("AとBを切り替えて、4通りの組み合わせを試そう。部品を替えると、同じ入力でも結果が変わる。")
        }
    }

    private var latchExperiment: some View {
        VStack(spacing: 18) {
            HStack(spacing: 18) {
                button("入力  \(inputA ? 1 : 0)", id: "latch.input", accent: inputA ? cyan : paper) { inputA.toggle() }
                arrow
                module(stored ? "記憶している値  1" : "記憶している値  0", icon: "memorychip", color: lavender)
                arrow
                module(stored ? "点灯" : "消灯", icon: stored ? "lightbulb.fill" : "lightbulb", active: stored)
            }
            HStack(spacing: 18) {
                button("今の入力を取り込んで保持", id: "latch.capture", accent: cyan) { stored = inputA; requests += 1 }
                Text(requests == 0 ? "入力を1にして取り込もう" : inputA != stored ? "入力と記憶が違っている！" : "次は、入力だけを変えてみよう")
                    .font(.system(size: 18, weight: .semibold))
            }
            note("入力を取り込み、保持する回路の模型。保持中は入力を変えても記憶は変わらない。電源がなくなっても残る保存とは別。")
        }
    }

    private var transistorExperiment: some View {
        VStack(spacing: 17) {
            HStack(spacing: 14) {
                module("電源", icon: "battery.100percent", color: amber)
                arrow
                module(inputA ? "通り道が開く" : "通り道が閉じる", icon: "switch.2", active: inputA)
                arrow
                module(inputA ? "電流が流れる" : "流れを止める", icon: inputA ? "lightbulb.fill" : "lightbulb", active: inputA)
            }
            button("制御信号  \(inputA ? "ON" : "OFF")", id: "transistor.control", accent: inputA ? cyan : paper) { inputA.toggle() }
            note("信号で電流の通り道を制御する、スイッチとしてのトランジスタの模型。種類や回路によってONの条件は変わる。")
        }
    }

    private var instructionsExperiment: some View {
        VStack(spacing: 15) {
            HStack(spacing: 12) {
                metric("3", "最初の値")
                arrow
                module(mode == 0 ? "① ＋2" : "① ×2", icon: "1.square", color: lavender)
                arrow
                module(mode == 0 ? "② ×2" : "② ＋2", icon: "2.square", color: lavender)
                arrow
                metric(mode == 0 ? "10" : "8", "結果")
            }
            button("命令の順番を入れ替える", id: "instructions.swap", accent: cyan) { mode = mode == 0 ? 1 : 0 }
            note(mode == 0 ? "(3＋2)×2＝10。命令は、ひとつ前の結果を受け取って進む。順序を替えると？" : "3×2＋2＝8。同じ2つの命令でも、実行する順番が結果を変える。")
        }
    }

    private var scheduleExperiment: some View {
        let timeline = inputA ? ["A", "B", "A", "B", "A", "B", "A", "B"] : ["A", "A", "A", "A", "B", "B", "B", "B"]
        return VStack(spacing: 14) {
            HStack(spacing: 9) {
                Text("1つのCPU\n時間 →").font(.system(size: 18, weight: .bold))
                ForEach(0..<8, id: \.self) { index in
                    VStack(spacing: 5) {
                        Text("\(index + 1)").font(.system(size: 15, design: .monospaced)).foregroundStyle(.white.opacity(0.6))
                        Text(timeline[index]).font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(ink).frame(maxWidth: .infinity, minHeight: 40)
                            .background(RoundedRectangle(cornerRadius: 7).fill(timeline[index] == "A" ? cyan : lavender))
                    }
                }
            }
            HStack(spacing: 22) {
                metric(inputA ? "2番目" : "5番目", "Bが最初に働ける順番", color: lavender)
                metric("8単位", "両方が終わるまで")
                button(inputA ? "Aを終えてからBへ" : "短い時間で交代する", id: "schedule.order", accent: cyan) { inputA.toggle() }
            }
            note("AもBも4単位の仕事。交代すれば両方が少しずつ進むが、総量は減らない。この模型では交代にかかる時間を省略。")
        }
    }

    private var parallelExperiment: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 22) {
                VStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { worker in
                        HStack(spacing: 9) {
                            Image(systemName: "cpu").foregroundStyle(worker < count ? cyan : .white.opacity(0.20))
                            cells(inputA ? (worker == 0 ? 8 : 0) : (worker < count ? (8 + count - 1 - worker) / count : 0), total: 8, color: worker < count ? cyan : paper, height: 22)
                        }
                    }
                }
                metric(inputA ? "8" : "\((8 + count - 1) / count)", "8仕事の終了まで")
            }
            HStack(spacing: 18) {
                selector("使うコア", value: count, range: 1...4, id: "parallel.cores") { count = $0 }
                button(inputA ? "独立した仕事にする" : "前の結果を待つ仕事にする", id: "parallel.dependency", accent: lavender) { inputA.toggle() }
            }
            note(inputA ? "8仕事が一列につながり、前の答えを待つ。コアを増やしても、この依存は消えない。" : "8つの独立した仕事なら、同時に進められる。実機では分配・受け渡しの手間もかかる。")
        }
    }

    private var pixelsExperiment: some View {
        let resolution = inputA ? 8 : 4
        return VStack(spacing: 14) {
            HStack(spacing: 35) {
                VStack(spacing: 2) {
                    ForEach(0..<resolution, id: \.self) { y in
                        HStack(spacing: 2) {
                            ForEach(0..<resolution, id: \.self) { x in
                                let on = (x + y < resolution) && (x > 0 || y > 0)
                                Rectangle().fill(on ? cyan : .white.opacity(0.09))
                            }
                        }
                    }
                }.frame(width: 152, height: 152).accessibilityLabel("\(resolution)かける\(resolution)画素の三角形")
                VStack(spacing: 12) {
                    metric("\(resolution * resolution)画素", "同じ計算を、それぞれの点に")
                    Text("\(count)レーンで処理すると、\(resolution * resolution / count)回で完了")
                        .font(.system(size: 18, weight: .medium))
                    HStack(spacing: 10) {
                        button(inputA ? "4×4にする" : "8×8にする", id: "pixels.resolution", accent: cyan) { inputA.toggle() }
                        button(count == 1 ? "4レーンにする" : "1レーンにする", id: "pixels.lanes", accent: lavender) { count = count == 1 ? 4 : 1 }
                    }
                }
            }
            note("各画素が独立した計算なら、まとめて処理できる。レーン数は模型の数で、実物のGPUコア数ではない。準備時間も省略。")
        }
    }

    private var memoryExperiment: some View {
        VStack(spacing: 16) {
            HStack(spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("RAM · 作業中のデータ", systemImage: "memorychip").font(.system(size: 18, weight: .bold))
                    cells(occupied ? 4 : 0, total: 6)
                    Text(occupied ? "4 / 6 枠を使用" : "0 / 6 枠を使用").font(.system(size: 18, design: .monospaced))
                }
                module(saved ? "SSD\n保存したコピーあり" : "SSD\nまだ保存していない", icon: "externaldrive", active: saved, color: lavender)
            }
            HStack(spacing: 12) {
                button("保存する", id: "memory.save", accent: cyan) { saved = true }.disabled(!occupied || saved)
                button(occupied ? "作業を終えて解放" : "また読み込む", id: "memory.release") {
                    if occupied { occupied = false } else if saved { occupied = true }
                }.disabled(!occupied && !saved)
                button("やり直す", id: "memory.reset") { occupied = true; saved = false }
            }
            note(!saved && !occupied ? "保存しないまま作業を終えたので、この模型ではデータが残っていない。「やり直す」で、今度は保存してから比べよう。" : saved && occupied ? "保存できた。でもRAMは4枠のまま。保存と、使い終わった領域を解放することは別の操作。" : "データがRAMにある間は作業領域を使う。保存したコピーは、RAMの領域を解放してもSSDに残る。")
        }
    }

    private var cacheExperiment: some View {
        VStack(spacing: 15) {
            HStack(spacing: 12) {
                module("CPU\n同じデータを要求", icon: "cpu", color: cyan)
                arrow
                module(cacheReady ? "キャッシュ\nコピーあり" : "キャッシュ\n空", icon: "tray", active: cacheReady, color: lavender)
                arrow
                module("RAM\n元のデータ", icon: "memorychip", active: requests == 0 || !cacheHit, color: amber)
            }
            HStack(spacing: 18) {
                button("同じデータを読む", id: "cache.read", accent: cyan) { cacheHit = cacheReady; cacheReady = true; requests += 1 }
                button("キャッシュを空にする", id: "cache.clear") { cacheReady = false; requests = 0; cacheHit = false }
                Text(requests == 0 ? "まず読んでみよう" : cacheHit ? "HIT · 近くから取得" : "MISS · RAMから取得")
                    .font(.system(size: 18, weight: .bold)).foregroundStyle(cacheHit ? cyan : amber)
            }
            note("1回目はRAMから読み、コピーを近くに置く。2回目は？ キャッシュの容量は限られ、いつも欲しいデータがあるとは限らない。")
        }
    }

    private var compressionExperiment: some View {
        let original = inputA ? "ABABABAB" : "AAAABBBB"
        let encoded = inputA ? "1A1B1A1B\n1A1B1A1B" : "4A4B"
        let ramSize = inputB ? 8 : mode == 1 ? 0 : inputA ? 16 : 4
        return VStack(spacing: 16) {
            HStack(spacing: 14) {
                VStack(spacing: 8) {
                    Text(original).font(.system(size: 25, weight: .bold, design: .monospaced))
                    Text("元の並び · 8記号").font(.system(size: 18))
                }.frame(maxWidth: .infinity)
                arrow
                VStack(spacing: 8) {
                    Text(inputB ? original : mode == 1 ? "SSDへ退避" : encoded)
                        .font(.system(size: 24, weight: .bold, design: .monospaced)).foregroundStyle(lavender)
                    Text(inputB ? "RAMで元の形に" : mode == 1 ? "8記号をSSDへ移す" : "連続を「数＋文字」に").font(.system(size: 18))
                }.frame(maxWidth: .infinity)
                metric("\(ramSize)記号", "RAM上の表現")
            }
            HStack(spacing: 9) {
                button("RAM内で圧縮", id: "compression.compress", accent: cyan) { mode = 0; inputB = false }
                    .disabled(!inputB && mode == 0)
                button("SSDへ退避", id: "compression.swap", accent: lavender) { mode = 1; inputB = false }
                    .disabled(!inputB && mode == 1)
                button("使うために戻す", id: "compression.restore") { inputB = true }
                    .disabled(inputB)
                button("並びを変更", id: "compression.pattern") { inputA.toggle(); inputB = false }
            }
            note(mode == 1 ? "退避はデータをSSD側へ移す。使うときはRAMへ戻す転送が必要。実際には管理用の領域もある。" : "可逆圧縮は元に戻せる表現へ変換する。並びによっては逆に長くなる。この記号数は模型で、実機のバイト数ではない。")
        }
    }

    private var storageExperiment: some View {
        let amount = inputA ? 200 : 100
        let speed = inputB ? 50 : 20
        return VStack(spacing: 17) {
            HStack(spacing: 14) {
                module("\(amount) MB\n読みたいデータ", icon: "doc.on.doc", color: lavender)
                arrow
                module("\(speed) MB/s\n転送速度", icon: "externaldrive", color: amber)
                arrow
                metric("\(amount / speed)秒", "転送だけに必要な時間")
            }
            HStack(spacing: 12) {
                button("データ量を\(inputA ? "100" : "200") MBに", id: "storage.amount") { inputA.toggle() }
                button("速度を\(inputB ? "20" : "50") MB/sに", id: "storage.speed", accent: cyan) { inputB.toggle() }
            }
            note("転送時間＝データ量÷速度。この模型は待ち時間を省略。保存できる「容量」と、単位時間に運べる「速さ」は違う。")
        }
    }

    private var framesExperiment: some View {
        let fps = inputA ? 60 : 30
        let hz = inputB ? 120 : 60
        return VStack(spacing: 15) {
            HStack(spacing: 24) {
                metric("\(fps) fps", "GPUが1秒に作る枚数")
                arrow
                metric("\(hz) Hz", "画面が1秒に更新する回数", color: lavender)
            }
            HStack(spacing: 7) {
                Text("連続する6回の表示").font(.system(size: 16, weight: .medium)).frame(width: 145)
                ForEach(0..<6, id: \.self) { slot in
                    Text("絵\(slot * fps / hz + 1)").font(.system(size: 18, weight: .bold))
                        .foregroundStyle(ink).frame(maxWidth: .infinity, minHeight: 39)
                        .background(RoundedRectangle(cornerRadius: 7).fill(slot == 0 || slot * fps / hz != (slot - 1) * fps / hz ? cyan : lavender))
                }
            }
            HStack(spacing: 12) {
                button("\(inputA ? "30" : "60") fpsに", id: "frames.fps") { inputA.toggle() }
                button("\(inputB ? "60" : "120") Hzに", id: "frames.hz") { inputB.toggle() }
            }
            note("規則正しく更新する模型。Hzだけ上げても、作られていない新しい絵は増えない。fpsとHzは別の指標。")
        }
    }

    private var networkExperiment: some View {
        let bandwidth = inputA ? 20 : 10
        let latency = inputB ? 100 : 20
        let transfer = 1000 / bandwidth
        return VStack(spacing: 15) {
            HStack(spacing: 12) {
                module("1 MB\n送るデータ", icon: "envelope", color: cyan)
                arrow
                VStack(spacing: 8) {
                    Text("転送 \(transfer) ms").font(.system(size: 20, weight: .bold))
                    Text("＋ 片道の遅延 \(latency) ms").font(.system(size: 18)).foregroundStyle(lavender)
                }.frame(maxWidth: .infinity)
                arrow
                metric("\(transfer + latency) ms", "最後のデータが届くまで")
            }
            HStack(spacing: 12) {
                button("帯域 \(bandwidth) MB/s", id: "network.bandwidth", accent: cyan) { inputA.toggle() }
                button("遅延 \(latency) ms", id: "network.latency") { inputB.toggle() }
            }
            note("帯域は運べる量、遅延は届くまでの待ち。片方だけ改善しても、もう片方は残る。混雑や再送は省いた模型。")
        }
    }

    private var busExperiment: some View {
        let paths = inputA ? 2 : 1
        return VStack(spacing: 16) {
            HStack(spacing: 18) {
                VStack(spacing: 10) {
                    module("装置A · 4単位", icon: "externaldrive", color: cyan, minimumHeight: 70)
                    module("装置B · 4単位", icon: "photo", color: lavender, minimumHeight: 70)
                }.frame(width: 180)
                VStack(spacing: 15) {
                    cells(4, total: 4, color: cyan, height: 28)
                    if paths == 2 { cells(4, total: 4, color: lavender, height: 28) }
                    Text(paths == 1 ? "同じ道を順番に使う" : "独立した道を同時に使う")
                        .font(.system(size: 18, weight: .bold))
                }
                arrow
                metric(paths == 1 ? "8" : "4", "完了までの時間単位")
            }.frame(height: 150)
            button(paths == 1 ? "独立した2本の道にする" : "共有する1本の道にする", id: "bus.paths", accent: cyan) { inputA.toggle() }
            note("各道が1時間単位に1単位を運ぶ模型。部品同士を結ぶ経路にも限界があり、接続先を含めた設計で速さが変わる。")
        }
    }

    private var portsExperiment: some View {
        let canConnect = mode == 2 || (mode == 1 && !inputA)
        return VStack(spacing: 15) {
            HStack(spacing: 15) {
                module("USB-C\n同じ差し込み形状", icon: "cable.connector", color: lavender)
                arrow
                module(inputA ? "外部画面" : "外付けSSD", icon: inputA ? "display" : "externaldrive", active: canConnect)
                metric(canConnect ? "使える" : "機能不足", "この接続の組み合わせ", color: canConnect ? cyan : amber)
            }
            HStack(spacing: 10) {
                button(["接続：充電のみ", "接続：充電＋データ", "接続：充電＋データ＋映像"][mode], id: "ports.capability", accent: cyan) { mode = (mode + 1) % 3 }
                button(inputA ? "SSDにつなぐ" : "画面につなぐ", id: "ports.device") { inputA.toggle() }
            }
            note("USB-Cは端子の形。映像や転送速度、給電の対応は別。実際はPC・ケーブル・周辺機器すべての仕様を確かめる。")
        }
    }

    private var flowExperiment: some View {
        let titles = ["SSD\n読み込む", "RAM\n作業に置く", "CPU\n加工する", "画面\n確かめる", "SSD\n保存する"]
        let icons = ["externaldrive", "memorychip", "cpu", "display", "externaldrive.badge.checkmark"]
        let explanations = ["保存してあった写真を、SSDから取り出す。", "加工に使うデータを、RAMの作業領域へ置く。", "命令に沿って写真を加工する。GPUが処理を担う場合もある。", "結果を画面で確かめる。表示しただけでは、保存したことにはならない。", "加工結果をSSDへ保存する。作業用RAMの役割とは別。"]
        return VStack(spacing: 15) {
            Text("写真を編集して、保存するまで").font(.system(size: 20, weight: .bold))
            HStack(spacing: 5) {
                ForEach(0..<5, id: \.self) { index in
                    if index > 0 { Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.4)) }
                    module(titles[index], icon: icons[index], active: mode == index, color: index == 1 ? lavender : cyan)
                }
            }
            button(mode == 4 ? "最初からたどる" : "次の役割へ", id: "flow.next", accent: cyan) { mode = (mode + 1) % 5 }
            note(explanations[mode])
        }
    }

    private var batteryExperiment: some View {
        let watts = count * 10
        let energy = inputA ? 30 : 60
        return VStack(spacing: 17) {
            HStack(spacing: 14) {
                module("\(energy) Wh\n蓄えたエネルギー", icon: inputA ? "battery.50percent" : "battery.100percent", color: amber)
                arrow
                module("\(watts) W\n使うペース", icon: "bolt", color: lavender)
                arrow
                metric(String(format: "%.1f時間", Double(energy) / Double(watts)), "一定の消費なら")
            }
            HStack(spacing: 20) {
                selector("活動の重さ", value: count, range: 1...3, id: "battery.load") { count = $0 }
                button("残りを\(inputA ? 60 : 30) Whにする", id: "battery.energy", accent: amber) { inputA.toggle() }
            }
            note("持ち時間＝Wh÷W。Wは消費する速さ、Whはエネルギーの量。実際の消費は作業・明るさ・温度などで変わる。")
        }
    }

    private var coolingExperiment: some View {
        let heat = count * 20
        let cooling = countB * 20
        return VStack(spacing: 15) {
            HStack(spacing: 18) {
                module("発熱 \(heat) W", icon: "cpu", color: amber)
                arrow
                module("放熱 \(cooling) W", icon: "fanblades", color: cyan)
                metric(heat > cooling ? "上がる" : heat == cooling ? "つり合う" : "下がる", "この瞬間の温度の傾向", color: heat > cooling ? amber : cyan)
            }
            HStack(spacing: 20) {
                selector("作業", value: count, range: 1...3, id: "cooling.load") { count = $0 }
                selector("冷却", value: countB, range: 1...3, id: "cooling.fan") { countB = $0 }
            }
            note("入る熱と逃げる熱の差を考える模型。実機では温度差でも放熱量が変わり、冷やせば無限に温度が下がるわけではない。")
        }
    }

    private var bottleneckExperiment: some View {
        let rate = min(count, countB, countC) * 10
        return VStack(spacing: 14) {
            HStack(spacing: 12) {
                rateColumn("読む", value: count, minimum: rate / 10, color: lavender)
                arrow
                rateColumn("加工", value: countB, minimum: rate / 10, color: cyan)
                arrow
                rateColumn("書く", value: countC, minimum: rate / 10, color: amber)
                metric("\(rate)", "全体の上限 · 単位/秒")
            }
            HStack(spacing: 10) {
                button("読込の能力を変更", id: "bottleneck.read") { count = count % 3 + 1 }
                button("加工の能力を変更", id: "bottleneck.process") { countB = countB % 3 + 1 }
                button("書込の能力を変更", id: "bottleneck.write") { countC = countC % 3 + 1 }
            }
            note("同じ量のデータが順に流れる模型。全体の速さは、一番細い部分が上限になる。他だけ速くしても上限は変わらない。")
        }
    }

    private func rateColumn(_ title: String, value: Int, minimum: Int, color: Color) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 18, weight: .bold))
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 5).fill(index < value ? color : .white.opacity(0.08))
                        .frame(width: 20, height: 30 + CGFloat(index) * 16)
                }
            }.frame(height: 66)
            Text("\(value * 10) /秒").font(.system(size: 18, weight: .bold)).monospacedDigit()
            Text(value == minimum ? "ここが上限" : "余裕あり").font(.system(size: 15, weight: .medium))
                .foregroundStyle(value == minimum ? amber : .white.opacity(0.6))
        }.frame(maxWidth: .infinity)
    }
}
