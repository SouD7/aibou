import SwiftUI
#if canImport(CircuitCore)
import CircuitCore
#endif

enum WorkshopStyle {
    static let ink = Color(red: 0.13, green: 0.20, blue: 0.23)
    static let muted = Color(red: 0.38, green: 0.46, blue: 0.49)
    static let teal = Color(red: 0.00, green: 0.43, blue: 0.49)
    static let mint = Color(red: 0.87, green: 0.96, blue: 0.94)
    static let paper = Color(red: 0.96, green: 0.97, blue: 0.965)
    static let line = Color(red: 0.83, green: 0.88, blue: 0.87)
    static let purple = Color(red: 0.44, green: 0.38, blue: 0.62)
    static let amber = Color(red: 0.65, green: 0.39, blue: 0.05)
}

struct WorkshopButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 11)
            .foregroundStyle(WorkshopStyle.ink)
            .background(WorkshopChamfer(corner: 8).fill(LinearGradient(colors: primary ? [Color(red: 0.62, green: 0.96, blue: 0.98), Color(red: 0.19, green: 0.78, blue: 0.87)] : [Color.white, Color(red: 0.84, green: 0.86, blue: 0.87)], startPoint: .top, endPoint: .bottom)))
            .overlay(WorkshopChamfer(corner: 8).strokeBorder(Color(red: 0.22, green: 0.27, blue: 0.32), lineWidth: 1.2))
            .overlay(WorkshopChamfer(corner: 6, insetAmount: 3).strokeBorder(.white.opacity(0.6), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 0, y: configuration.isPressed ? 0 : 2)
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct WorkshopView: View {
    @ObservedObject var store: WorkshopStore
    @ObservedObject private var voice: GuideVoice
    var openSandbox: () -> Void
    private var minimumHeight: CGFloat
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmRestart = false
    private enum Panel { case instructions, result, save }
    @State private var activePanel: Panel?
    @State private var expandedGuide = false

    init(store: WorkshopStore, minimumHeight: CGFloat = 750, openSandbox: @escaping () -> Void) {
        self.store = store; self.voice = store.voice; self.openSandbox = openSandbox
        self.minimumHeight = minimumHeight
    }

    private var atEntrance: Bool { store.state.phase == .welcome || store.resumePending }
    private var reduced: Bool { store.reducedMotion || systemReducedMotion }
    private var phaseTitle: String {
        switch store.state.phase {
        case .welcome: return "はじめる前"
        case .building: return "作る"
        case .observing: return "観察する"
        case .verified: return store.isTesting ? "確かめる" : "できあがり"
        case .finished: return "作品完成"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { viewport in
                if atEntrance {
                    ScrollView {
                        entrance.frame(maxWidth: 1420)
                            .frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: .top)
                    }
                } else {
                    fixedWorkspace.frame(maxWidth: 1600).frame(maxWidth: .infinity)
                }
            }
            footer
        }
        .background(WorkshopBackdrop()).foregroundStyle(WorkshopStyle.ink)
        .frame(minWidth: 1100, minHeight: minimumHeight)
        .disabled(activePanel != nil)
        .overlay { if let panel = activePanel { panelOverlay(panel) } }
        .onChange(of: store.isTesting) { testing in
            if !testing && store.testRow == 4 && store.circuit.verification != .untested { activePanel = .result }
        }
        .onChange(of: store.state.phase) { phase in
            if phase == .verified && !store.isTesting { activePanel = .result }
        }
        .onAppear { store.appear() }
        .onDisappear { store.disappear() }
        .onChange(of: scenePhase) { phase in if phase != .active { store.cancelTest(announce: false) } }
        .sheet(isPresented: $store.showPrediction) { prediction }
        .sheet(isPresented: $store.showSettings) { settings }
        .sheet(isPresented: $store.showArtifact) {
            if let work = store.state.completedArtifact {
                WorkshopArtifactView(artifact: work) { store.showArtifact = false }
            }
        }
        .confirmationDialog("作業中の回路を最初からやり直しますか？", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("最初から作る") { store.restart() }
            Button("続ける", role: .cancel) {}
        } message: { Text("完成した作品は日記に残ります。") }
    }

    private var header: some View {
        HStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "cpu").font(.system(size: 25, weight: .medium))
                Text("論理回路").font(.system(size: 23, weight: .bold, design: .rounded))
                Text("01").font(.system(size: 16, weight: .semibold, design: .monospaced)).padding(.leading, 9)
            }.padding(.horizontal, 22).padding(.vertical, 14).modifier(WorkshopPlate())
            Spacer()
            if store.state.completedArtifact != nil {
                Button { store.cancelTest(); store.showArtifact = true } label: { Label("日記  1", systemImage: "book.closed") }
                    .buttonStyle(WorkshopButtonStyle()).accessibilityIdentifier("w.artifact")
            }
            Button { store.setVoice(!store.voiceEnabled) } label: {
                Label(store.voiceEnabled ? "音声オン" : "音声オフ", systemImage: store.voiceEnabled ? "speaker.wave.2" : "speaker.slash")
            }.buttonStyle(WorkshopButtonStyle()).accessibilityIdentifier("w.voice")
            Button { store.cancelTest(); store.showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                .buttonStyle(WorkshopButtonStyle()).accessibilityLabel("音と動きの設定").accessibilityIdentifier("w.settings")
            Button("自由実験") { store.disappear(); openSandbox() }.buttonStyle(WorkshopButtonStyle())
                .accessibilityIdentifier("w.sandbox")
        }.padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 2)
    }

    private var entrance: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                Text("EXHIBIT 01  /  SIGNAL WORKSHOP")
                    .font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(WorkshopStyle.teal)
                Text(store.resumePending ? "おかえり。\n続きから、つくろう。" : "ふたりの合図で、\n灯りをつくろう。")
                    .font(.system(size: 36, weight: .semibold, design: .rounded)).lineSpacing(8)
                Text(store.resumePending ? "回路と観察ノートを、このMacに残してあるよ。" : "ふたりの準備がそろったときだけ光るランプ。\nスイッチと小さな部品で、一緒に作ってみよう。")
                    .font(.system(size: 16)).lineSpacing(8).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 26) {
                    entranceFeature("hand.draw", "つないで")
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(WorkshopStyle.muted)
                    entranceFeature("eye", "観察して")
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(WorkshopStyle.muted)
                    entranceFeature("lightbulb", "見つける")
                }.padding(.vertical, 5)
                HStack(spacing: 12) {
                    Button { if store.resumePending { store.resume() } else { store.act(.begin) } } label: {
                        Label(store.resumePending ? "続きから" : "一緒につくる", systemImage: "arrow.right")
                    }.buttonStyle(WorkshopButtonStyle(primary: true))
                        .accessibilityIdentifier(store.resumePending ? "workshop.resume" : "workshop.begin")
                    if store.resumePending {
                        Button("最初から") { confirmRestart = true }.buttonStyle(WorkshopButtonStyle()).accessibilityIdentifier("workshop.fresh")
                    }
                }
                Text("知識は、ここから。好きなだけ試して大丈夫。")
                    .font(.system(size: 12)).foregroundStyle(WorkshopStyle.muted)
                if !store.saveError.isEmpty { saveWarning }
            }.padding(32).frame(maxWidth: 660, alignment: .leading).modifier(WorkshopPlate())
                .overlay(alignment: .topLeading) { guideName.offset(x: 24, y: -16) }
                .padding(.bottom, 25).zIndex(1)
            IllustratedGuideView(speaking: voice.isSpeaking, reducedMotion: reduced, compact: false)
                .frame(minWidth: 320, maxWidth: 480).frame(height: 550).padding(.leading, -36)
        }.padding(.horizontal, 44).padding(.top, 45).padding(.bottom, 12)
    }

    private var guideName: some View {
        Text("aibou").font(.system(size: 17, weight: .medium, design: .rounded)).tracking(1)
            .foregroundStyle(.white).padding(.horizontal, 23).padding(.vertical, 6)
            .background(WorkshopChamfer(corner: 7).fill(Color(red: 0.17, green: 0.21, blue: 0.26)))
            .overlay(alignment: .leading) { Rectangle().fill(Color.cyan).frame(width: 3, height: 18).padding(.leading, 8) }
    }

    private func entranceFeature(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(WorkshopStyle.teal)
            Text(text).font(.system(size: 12, weight: .medium))
        }
    }

    // Scale the complete workbench only when the window is short. Neither wheel
    // input nor changing instructions/results can move the parts under the cursor.
    private var fixedWorkspace: some View {
        GeometryReader { viewport in
            let scale = min(1, max(1, viewport.size.height) / 720)
            let canvasHeight = viewport.size.height / scale
            workspace(height: canvasHeight)
                .frame(width: viewport.size.width / scale, height: canvasHeight)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: viewport.size.width, height: viewport.size.height, alignment: .topLeading)
        }
    }

    private func workspace(height: CGFloat) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Text("ふたりとも準備できたら、光らせよう。")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 8)
                Button { activePanel = .instructions } label: { Label("操作", systemImage: "cursorarrow.click") }
                    .buttonStyle(WorkshopButtonStyle()).accessibilityIdentifier("w.instructions")
                Button { activePanel = .result } label: { Label("結果", systemImage: "checklist") }
                    .buttonStyle(WorkshopButtonStyle()).accessibilityIdentifier("w.results")
                    .disabled(store.circuit.verification == .untested || store.isTesting)
                testControl
            }.padding(.horizontal, 16).padding(.vertical, 9).modifier(WorkshopPlate())
            HStack(alignment: .top, spacing: 16) {
                WorkshopBoardView(store: store, reducedMotion: reduced, boardHeight: min(340, max(230, height - 500)))
                    .frame(minWidth: 600, maxWidth: .infinity)
                VStack(spacing: 14) {
                    notebook.padding(17).modifier(WorkshopPlate())
                    HStack(spacing: 8) {
                        Button { store.act(.undo) } label: { Label("一手戻す", systemImage: "arrow.uturn.backward") }
                            .buttonStyle(WorkshopButtonStyle()).disabled(!store.state.canUndo).accessibilityIdentifier("w.undo")
                            .keyboardShortcut("z", modifiers: .command)
                        Button { confirmRestart = true } label: { Image(systemName: "arrow.counterclockwise") }
                            .buttonStyle(WorkshopButtonStyle()).accessibilityLabel("最初からやり直す").accessibilityIdentifier("w.restart")
                    }
                }.frame(width: 232)
            }
            Spacer(minLength: 0)
            companion
        }.padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 14)
            .overlay(alignment: .bottomTrailing) {
                if expandedGuide {
                    ZStack(alignment: .topTrailing) {
                        IllustratedGuideView(speaking: voice.isSpeaking, reducedMotion: reduced, compact: false)
                            .frame(width: 380, height: 430)
                        Button { expandedGuide = false } label: { Image(systemName: "xmark") }
                            .buttonStyle(WorkshopButtonStyle()).accessibilityLabel("案内を小さくする")
                    }.padding(.trailing, 26).padding(.bottom, 137)
                }
            }
    }

    private func panelOverlay(_ panel: Panel) -> some View {
        ZStack {
            Color.black.opacity(0.24).onTapGesture { activePanel = nil }
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(panel == .instructions ? "操作のヒント" : panel == .save ? "保存について" : "実験の結果")
                        .font(.system(size: 18, weight: .semibold))
                    Spacer()
                    Button("閉じる") { activePanel = nil }
                        .buttonStyle(WorkshopButtonStyle()).accessibilityIdentifier("w.panel.close")
                }
                switch panel {
                case .instructions:
                    Text("① 部品をクリックかドラッグで置く。\n② 丸い端子どうしをドラッグ、または順にクリックしてつなぐ。\n③ スイッチを変え、結果をノートに残す。\n\n「つなぐ」ボタンでも配線できます。")
                        .font(.system(size: 15)).lineSpacing(7).fixedSize(horizontal: false, vertical: true)
                case .save: saveWarning
                case .result:
                    if store.state.phase == .finished { finished }
                    else if store.circuit.verification == .passed { completion }
                    else { failureResult }
                }
            }.padding(24).frame(width: 670).modifier(WorkshopPlate())
                .foregroundStyle(WorkshopStyle.ink)
        }.onExitCommand { activePanel = nil }
    }

    @ViewBuilder private var failureResult: some View {
        if let failure = store.circuit.checks.first(where: { !$0.passed }) {
            VStack(alignment: .leading, spacing: 16) {
                Label("違いを見つけた", systemImage: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold)).accessibilityIdentifier("w.failure")
                Text("A=\(failure.inputs.a ? 1 : 0)、B=\(failure.inputs.b ? 1 : 0)のとき、目標は\(failure.expected ? 1 : 0)。今の回路は\(failure.actual.label)。")
                    .font(.system(size: 15)).lineSpacing(5)
                Button("この条件で試す") {
                    store.act(.selectCounterexample(failure.inputs)); activePanel = nil
                }.buttonStyle(WorkshopButtonStyle(primary: true)).accessibilityIdentifier("w.counterexample")
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder private var testControl: some View {
        if store.isTesting {
            Button { store.cancelTest() } label: { Label("止める  \(store.testRow)/4", systemImage: "stop.fill") }
                .buttonStyle(WorkshopButtonStyle(primary: true)).accessibilityIdentifier("w.stopTest")
        } else {
            Button { store.runTest() } label: { Label("4通りテスト", systemImage: "play.fill") }
                .buttonStyle(WorkshopButtonStyle(primary: true)).disabled(!store.circuit.isConnected)
                .accessibilityIdentifier("w.test").keyboardShortcut(.return, modifiers: .command)
        }
    }

    private var companion: some View {
        HStack(alignment: .center, spacing: 20) {
            Button { expandedGuide.toggle() } label: {
                IllustratedGuideView(speaking: voice.isSpeaking, reducedMotion: reduced, compact: true)
                    .frame(width: 104, height: 110)
                    .background(LinearGradient(colors: [Color(red: 0.35, green: 0.42, blue: 0.46), Color(red: 0.14, green: 0.20, blue: 0.25)], startPoint: .top, endPoint: .bottom))
                    .clipShape(WorkshopChamfer(corner: 10))
                    .overlay(WorkshopChamfer(corner: 10).stroke(Color.cyan.opacity(0.6), lineWidth: 2))
            }.buttonStyle(.plain).accessibilityLabel(expandedGuide ? "相棒を小さく表示" : "相棒を大きく表示")
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    guideName
                    Text(store.isTesting ? "一緒に実験中" : "あなたの相棒").font(.system(size: 10)).foregroundStyle(WorkshopStyle.muted)
                    Spacer()
                    Button { voice.isSpeaking ? store.stopSpeech() : store.replayDialogue() } label: {
                        Image(systemName: voice.isSpeaking ? "stop.circle" : "speaker.wave.2")
                    }.buttonStyle(.plain).disabled(!store.voiceEnabled)
                        .accessibilityLabel(voice.isSpeaking ? "読み上げを止める" : "もう一度聞く").accessibilityIdentifier("w.replayVoice")
                }
                Text(store.dialogue).font(.system(size: 15, weight: .medium)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("w.dialogue")
                if let reason = voice.unavailableReason { Text(reason).font(.caption2).foregroundStyle(WorkshopStyle.muted) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 10) {
                Button { store.act(.askCompanion) } label: {
                    Label(store.circuit.inputs.b ? "Bを切ってもらう" : "Bを入れてもらう", systemImage: "hand.raised").frame(width: 142)
                }.buttonStyle(WorkshopButtonStyle(primary: true)).accessibilityIdentifier("w.askB")
                Button { store.act(.hint) } label: {
                    Label("一緒に考える", systemImage: "lightbulb").frame(width: 142)
                }.buttonStyle(WorkshopButtonStyle()).accessibilityIdentifier("w.hint")
            }
        }.padding(.leading, 10).padding(.trailing, 20).padding(.vertical, 10).modifier(WorkshopPlate())
    }

    private var notebook: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "book.pages").foregroundStyle(WorkshopStyle.teal)
                Text("観察ノート").font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            Text("ふたりとも準備できたときだけ、光るのが目標。")
                .font(.system(size: 11)).lineSpacing(4).foregroundStyle(WorkshopStyle.muted).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                HStack { Text("A"); Text("B"); Spacer(); Text("目標"); Text("観察") }.font(.system(size: 10, weight: .medium))
                    .foregroundStyle(WorkshopStyle.muted).padding(12)
                ForEach(Array(InputPair.truthTable.enumerated()), id: \.offset) { _, pair in
                    let row = store.state.observations.first { $0.inputs == pair }
                    let current = store.circuit.inputs == pair
                    HStack(spacing: 12) {
                        Text(pair.a ? "1" : "0"); Text(pair.b ? "1" : "0")
                        Spacer()
                        Text(pair.a && pair.b ? "1" : "0").foregroundStyle(WorkshopStyle.muted)
                        HStack(spacing: 3) {
                            Text(row?.actual.label ?? "·")
                            if let row { Image(systemName: row.passed ? "checkmark" : "arrow.triangle.2.circlepath").font(.system(size: 8)) }
                        }.frame(width: 31, alignment: .trailing).foregroundStyle(row?.passed == false ? WorkshopStyle.amber : WorkshopStyle.teal)
                    }.font(.system(size: 13, weight: .medium, design: .monospaced)).padding(.horizontal, 12).padding(.vertical, 10)
                        .background(current ? WorkshopStyle.mint : Color.white)
                        .overlay(alignment: .top) { Rectangle().fill(WorkshopStyle.line.opacity(0.6)).frame(height: 0.5) }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("A\(pair.a ? 1 : 0)、B\(pair.b ? 1 : 0)、目標\(pair.a && pair.b ? 1 : 0)、観察\(row?.actual.label ?? "まだ")")
                        .accessibilityIdentifier("w.row.\(pair.a ? 1 : 0)\(pair.b ? 1 : 0)")
                }
            }.background(.white, in: RoundedRectangle(cornerRadius: 16)).clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(WorkshopStyle.line, lineWidth: 1))
            Button { store.act(.observe) } label: {
                Label("今の結果を残す", systemImage: "pencil.line").frame(maxWidth: .infinity)
            }.buttonStyle(WorkshopButtonStyle()).disabled(!store.state.canObserve || store.isTesting).accessibilityIdentifier("w.observe")
            Text("\(store.state.observations.count) / 4 通りを観察")
                .font(.system(size: 10)).foregroundStyle(WorkshopStyle.muted).accessibilityElement(children: .ignore).accessibilityLabel("\(store.state.observations.count) / 4 通りを観察").accessibilityIdentifier("w.observationCount")
        }
    }

    private var completion: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("4通りとも、目標どおり。", systemImage: "checkmark.seal.fill")
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(WorkshopStyle.teal).accessibilityIdentifier("w.success")
            Text("ふたつの条件が両方そろうと、合図を出す。これが AND の働きです。")
                .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button { store.act(.finish); activePanel = nil } label: { Label("日記に残す", systemImage: "bookmark") }
                    .buttonStyle(WorkshopButtonStyle(primary: true)).accessibilityIdentifier("w.finish")
                Button("別の場面で予想する") { activePanel = nil; store.showPrediction = true }
                    .buttonStyle(WorkshopButtonStyle()).accessibilityIdentifier("w.prediction")
                Spacer()
                Text("予想はあとでも大丈夫。").font(.system(size: 10)).foregroundStyle(WorkshopStyle.muted)
            }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(WorkshopStyle.mint, in: RoundedRectangle(cornerRadius: 20))
    }

    private var finished: some View {
        HStack(spacing: 18) {
            Image(systemName: "lightbulb.2.fill").font(.system(size: 30, weight: .light)).foregroundStyle(WorkshopStyle.teal)
            VStack(alignment: .leading, spacing: 6) {
                Text("作品01  ふたりの準備完了ランプ").font(.system(size: 16, weight: .semibold))
                Text("つないで、比べて、仕組みを見つけたね。")
                    .font(.system(size: 12)).foregroundStyle(WorkshopStyle.muted)
            }
            Spacer()
            Button("作品を見る") { activePanel = nil; store.showArtifact = true }.buttonStyle(WorkshopButtonStyle(primary: true)).accessibilityIdentifier("w.viewWork")
        }.padding(20).background(WorkshopStyle.mint, in: RoundedRectangle(cornerRadius: 20))
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("0 = 準備前   1 = 準備できた   ? = 未接続")
            Spacer()
            if !store.saveError.isEmpty {
                Button("保存を確認") { activePanel = .save }.accessibilityIdentifier("w.saveDetails")
            }
            Text(phaseTitle).accessibilityElement(children: .ignore).accessibilityLabel("進行状況、\(phaseTitle)").accessibilityValue(store.state.phase.rawValue).accessibilityIdentifier("w.phase")
            Label(store.saveMessage.isEmpty ? "作業はこのMacに保存されます" : store.saveMessage, systemImage: store.saveError.isEmpty ? "checkmark.icloud" : "exclamationmark.icloud")
                .accessibilityElement(children: .ignore).accessibilityLabel(store.saveMessage.isEmpty ? "作業はこのMacに保存されます" : store.saveMessage).accessibilityIdentifier("w.saveStatus")
        }.font(.system(size: 10)).foregroundStyle(WorkshopStyle.muted)
            .padding(.horizontal, 28).padding(.vertical, 12).background(.white.opacity(0.8))
    }

    private var saveWarning: some View {
        HStack(spacing: 12) {
            Text(store.saveError).font(.caption).fixedSize(horizontal: false, vertical: true)
            Button("保存を再試行") { store.retrySave() }.buttonStyle(WorkshopButtonStyle()).accessibilityIdentifier("w.retrySave")
        }.padding(12).foregroundStyle(WorkshopStyle.amber).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var prediction: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Text("場面を変えて、考えよう。").font(.title3.bold()); Spacer(); Button("閉じる") { store.showPrediction = false }.accessibilityIdentifier("w.prediction.close") }
            Text("Aは「準備完了」、Bは「開始の許可」。\(store.circuit.prediction.inputs.a ? "準備はできた" : "準備はまだ")、\(store.circuit.prediction.inputs.b ? "許可は出ている" : "許可はまだ")。このとき、ランプはどうなる？")
                .font(.system(size: 17)).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
            Text("同じAND回路を、別の合図に置き換えてみよう。")
                .font(.system(size: 12)).foregroundStyle(WorkshopStyle.muted)
            HStack {
                Button("つかない（0）") { store.act(.circuit(.predict(false))) }.buttonStyle(WorkshopButtonStyle()).accessibilityIdentifier("w.predict.0")
                Button("つく（1）") { store.act(.circuit(.predict(true))) }.buttonStyle(WorkshopButtonStyle()).accessibilityIdentifier("w.predict.1")
            }
            if let answer = store.circuit.prediction.isCorrect {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(answer ? "予想どおり" : "今回は")、\(store.circuit.prediction.inputs.a && store.circuit.prediction.inputs.b ? "点灯" : "消灯")するよ。")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(WorkshopStyle.teal).accessibilityIdentifier("w.prediction.feedback")
                    Text("この条件はA=\(store.circuit.prediction.inputs.a ? 1 : 0)、B=\(store.circuit.prediction.inputs.b ? 1 : 0)。ANDは両方が1のときだけ光る。片方だけでは光らないんだ。")
                        .font(.system(size: 14)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                    Button("回路で確かめる") {
                        store.act(.circuit(.setInputs(store.circuit.prediction.inputs))); store.showPrediction = false
                    }.buttonStyle(WorkshopButtonStyle()).accessibilityIdentifier("w.prediction.observe")
                }.padding(18).background(WorkshopStyle.mint, in: RoundedRectangle(cornerRadius: 15))
            }
            Text("予想を外しても、作品はそのまま残せます。")
                .font(.caption).foregroundStyle(WorkshopStyle.muted)
        }.padding(30).frame(width: 530).foregroundStyle(WorkshopStyle.ink)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Text("音と動き").font(.title3.bold()); Spacer(); Button("閉じる") { store.showSettings = false }.accessibilityIdentifier("w.settings.close") }
            Toggle("相棒の声", isOn: Binding(get: { store.voiceEnabled }, set: store.setVoice))
            Toggle("操作音", isOn: Binding(get: { store.soundEnabled }, set: store.setSound))
            Toggle("動きを抑える", isOn: Binding(get: { store.reducedMotion }, set: store.setReducedMotion))
            Text("台詞はいつも文字でも表示します。音声を聞き終える前でも操作できます。")
                .font(.caption).lineSpacing(4).foregroundStyle(WorkshopStyle.muted)
            Divider()
            Text("この展示は0と1を扱う論理回路のモデルです。電圧・電流・信号の伝わる時間は省略しています。")
                .font(.caption).lineSpacing(4).foregroundStyle(WorkshopStyle.muted)
        }.padding(30).frame(width: 420)
    }

}
