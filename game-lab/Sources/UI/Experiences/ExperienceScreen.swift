import SwiftUI
#if canImport(CircuitCore)
import CircuitCore
#endif

struct ExperienceScreen<M: ExperienceModel, Content: View>: View {
    @ObservedObject var store: ExperienceStore<M>
    var onExit: () -> Void
    @ViewBuilder var content: (M, @escaping (M.Action) -> Void) -> Content
    @StateObject private var voice = GuideVoice()
    @State private var panel: Panel?
    @State private var preview: M?
    @State private var previewOriginal: M?
    @State private var boardEpoch = 0
    @State private var confirmRestart = false
    @State private var predictionText = ""
    @State private var reasonText = ""
    @State private var discoveryText = ""
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduced
    enum Panel: String, Identifiable { case hints, comparison, works, stages, reflection; var id: String { rawValue } }
    private var game: ExhibitionGame? { ExhibitionCatalog.game(M.gameID) }
    private var line: String {
        if store.hintLevel > 0, store.model.hints.indices.contains(store.hintLevel-1) { return store.model.hints[store.hintLevel-1] }
        return store.model.guide
    }
    var body: some View {
        ExhibitionStage {
            ZStack(alignment: .topLeading) {
                WorkshopBackdrop().frame(width: 1600, height: 900)
                Color.white.opacity(0.06).frame(width: 1600, height: 900).allowsHitTesting(false)
                header.frame(width: 1544, height: 62).offset(x: 28, y: 16)
                goal.frame(width: 1544, height: 56).offset(x: 28, y: 94)
                content(store.model, { store.hintLevel = 0; store.send($0) })
                    .frame(width: 1160, height: 550).background(ExperienceMat())
                    .id("\(store.model.stage)-\(boardEpoch)-\(panel != nil)-\(scenePhase == .active)")
                    .disabled(panel != nil || scenePhase != .active)
                    .offset(x: 28, y: 169)
                notebook.frame(width: 356, height: 292).offset(x: 1216, y: 169)
                guide.frame(width: 365, height: 426).offset(x: 1210, y: 462)
                caption.frame(width: 1160, height: 82).offset(x: 28, y: 739)
                controls.frame(width: 1160, height: 54).offset(x: 28, y: 839)
            }.foregroundStyle(ExperienceStyle.ink).frame(width: 1600, height: 900)
        }
        .onDisappear { voice.stop() }
        .onChange(of: scenePhase) { if $0 != .active { voice.stop() } }
        .onChange(of: store.model.stage) { _ in voice.stop() }
        .sheet(item: $panel) { value in panelView(value) }
        .confirmationDialog("この課題を最初の状態から試しますか？", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("最初から試す") { boardEpoch += 1; store.restart() }
            Button("続ける", role: .cancel) {}
        } message: { Text("作品と比較ノートは残ります。") }
    }
    private var header: some View {
        HStack(spacing: 20) {
            Button { voice.stop(); onExit() } label: { Label("展示室へ", systemImage: "chevron.left") }
                .buttonStyle(ExperienceButtonStyle()).accessibilityIdentifier("experience.exit")
            Image(systemName: game?.icon ?? "cpu").font(.system(size: 28))
            Text(game?.title ?? M.gameID).font(.system(size: 29, weight: .bold, design: .rounded))
            Rectangle().fill(ExperienceStyle.ink.opacity(0.2)).frame(width: 1, height: 28)
            Button { open(.stages) } label: { Text("\(store.model.stage) / 5　\(store.model.stageTitle)").font(.system(size: 21, weight: .semibold)) }.buttonStyle(.plain)
            Spacer(minLength: 8)
            Button { open(.hints) } label: { Label("ヒント", systemImage: "lightbulb") }.buttonStyle(ExperienceButtonStyle())
            Button { open(.works) } label: { Label("作品 \(store.artifacts.count)", systemImage: "book.closed") }.buttonStyle(ExperienceButtonStyle())
        }.padding(.horizontal, 18).modifier(WorkshopPlate())
    }
    private var goal: some View {
        HStack(spacing: 15) {
            Image(systemName: store.model.isComplete ? "checkmark.seal.fill" : "flag").foregroundStyle(store.model.isComplete ? Color.teal : ExperienceStyle.ink)
            Text(store.model.goal).font(.system(size: 21, weight: .semibold, design: .rounded)).lineLimit(2)
            Spacer()
            if store.completedStages.contains(store.model.stage) { Label("作品あり", systemImage: "checkmark.circle.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(.teal) }
        }.padding(.horizontal, 21).frame(maxWidth: .infinity, maxHeight: .infinity).modifier(WorkshopPlate())
    }
    private var notebook: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack { Image(systemName: "note.text").foregroundStyle(.teal); Text("観察ノート").font(.system(size: 22, weight: .bold)) }
            ForEach(Array(store.model.metrics.prefix(5).enumerated()), id: \.offset) { _, metric in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(metric.label).font(.system(size: 15, weight: .medium)).foregroundStyle(ExperienceStyle.muted)
                        Spacer(minLength: 8)
                        Text(metric.value).font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
                    }
                    if !metric.detail.isEmpty { Text(metric.detail).font(.system(size: 12)).foregroundStyle(ExperienceStyle.muted).lineLimit(1) }
                }
            }
            Spacer(minLength: 0)
        }.padding(22).modifier(WorkshopPlate())
    }
    private var guide: some View {
        let progressed = store.model != M(stage: store.model.stage)
        let pose = store.model.isComplete ? "celebrating" : (store.hintLevel > 0 || progressed || !store.record.actions.isEmpty ? "explaining" : "welcome")
        return Group {
            if let art = LessonArtwork.images[pose] {
                Image(nsImage: art).resizable().scaledToFit()
                    .shadow(color: .black.opacity(0.16), radius: 7, x: 4, y: 5)
                    .animation(reduced ? nil : .easeInOut(duration: 0.18), value: pose)
            } else {
                IllustratedGuideView(speaking: voice.isSpeaking, reducedMotion: reduced, compact: false)
            }
        }.allowsHitTesting(false).accessibilityLabel(store.model.isComplete ? "発見を喜ぶ相棒の女の子" : "一緒に観察する相棒の女の子")
    }
    private var caption: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Text("aibou").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.teal)
                Text(line).font(.system(size: 22, weight: .medium, design: .rounded)).lineLimit(2).minimumScaleFactor(0.85)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { if voice.isSpeaking { voice.stop() } else { voice.speak(line) } } label: { Image(systemName: voice.isSpeaking ? "stop.fill" : "speaker.wave.2") }
                .buttonStyle(ExperienceButtonStyle()).accessibilityLabel("相棒の案内を聞く")
        }.padding(.horizontal, 22).padding(.vertical, 10).modifier(WorkshopPlate())
    }
    private var controls: some View {
        HStack(spacing: 13) {
            Button { boardEpoch += 1; store.undo() } label: { Label("一手戻す", systemImage: "arrow.uturn.backward") }
                .disabled(!store.canUndo).keyboardShortcut("z", modifiers: .command)
            Button { boardEpoch += 1; confirmRestart = true } label: { Image(systemName: "arrow.counterclockwise") }.accessibilityLabel("課題を最初から")
            Button { store.rememberComparison(); open(.comparison) } label: { Label("比較ノート", systemImage: "rectangle.on.rectangle") }
            Button { open(.reflection) } label: { Label("予想と発見", systemImage: "pencil.line") }
            Spacer(minLength: 3)
            if !store.saveError.isEmpty {
                Button(store.blockedSave ? "記録を保持して開始" : "保存を再試行") {
                    if store.blockedSave { store.preserveUnreadableAndStart() } else { store.retrySave() }
                }.help(store.saveError)
            } else if store.model.isComplete {
                Button { _ = store.saveArtifact() } label: { Label("作品を残す", systemImage: "checkmark.seal") }.buttonStyle(ExperienceButtonStyle(primary: true))
                if store.model.stage < 5 { Button("次の課題へ") { boardEpoch += 1; store.next() }.buttonStyle(ExperienceButtonStyle(primary: true)) }
            } else {
                Text(store.message).font(.system(size: 14)).foregroundStyle(ExperienceStyle.ink).lineLimit(1)
            }
        }.buttonStyle(ExperienceButtonStyle())
    }
    private func open(_ value: Panel) { voice.stop(); preview = nil; previewOriginal = nil; panel = value }
    @ViewBuilder private func panelView(_ value: Panel) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(value == .hints ? "一緒に考えよう" : value == .comparison ? "条件と結果を比べる" : value == .works ? "日記" : value == .reflection ? "予想と発見" : "好きな課題を選ぶ")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Spacer()
                Button("閉じる") { panel = nil; preview = nil }.buttonStyle(ExperienceButtonStyle())
            }
            if let shown = preview {
                Text("記録のコピーを操作しています。元の作品と作業中の盤面は変わりません。")
                    .font(.system(size: 16)).foregroundStyle(ExperienceStyle.muted)
                content(shown, { action in var copy = preview ?? shown; copy.send(action); if copy.isValid { preview = copy } })
                    .frame(width: 1160, height: 550).background(ExperienceMat())
                HStack {
                    Button("記録の状態へ戻す") { preview = previewOriginal }
                    Button("同じ課題の最初から動かす") { preview = M(stage: shown.stage) }
                    Button("一覧へ") { preview = nil }
                }.buttonStyle(ExperienceButtonStyle())
            } else {
                switch value {
                case .reflection:
                    reflectionPanel
                case .hints:
                    Text(store.model.goal).font(.system(size: 22, weight: .medium))
                    ForEach(Array(store.model.hints.enumerated()), id: \.offset) { index, hint in
                        if index < store.hintLevel { Text("\(index+1).  \(hint)").font(.system(size: 21)).padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 12)) }
                    }
                    Button(store.hintLevel == 0 ? "注目するところを聞く" : "もう少し聞く") { store.hintLevel = min(store.model.hints.count, store.hintLevel + 1) }
                        .disabled(store.hintLevel >= store.model.hints.count).buttonStyle(ExperienceButtonStyle(primary: true))
                    Text("ヒントを使っても作品は同じように残せます。").foregroundStyle(ExperienceStyle.muted)
                case .stages:
                    ForEach(1...5, id: \.self) { n in
                        let sample = M(stage: n)
                        Button { store.selectStage(n); panel = nil } label: {
                            HStack { Text("\(n)").font(.title); VStack(alignment: .leading) { Text(sample.stageTitle).font(.title3.bold()); Text(sample.goal).font(.body) }; Spacer(); if store.completedStages.contains(n) { Image(systemName: "checkmark.seal.fill").foregroundStyle(.teal) } }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(ExperienceButtonStyle(primary: n == store.model.stage))
                    }
                case .works:
                    if store.artifacts.isEmpty { Text("課題を達成したら、「作品を残す」でここに飾ろう。").font(.title3).padding(30) }
                    ScrollView { VStack(spacing: 12) {
                        ForEach(store.artifacts.reversed()) { artifact in
                            recordRow(artifact.model, title: "\(artifact.model.stage) · \(artifact.model.stageTitle)")
                        }
                    } }
                case .comparison:
                    Text("操作や設定を含む状態を残しています。同じ初期条件で一つずつ変えて比べよう。").font(.system(size: 18))
                    ScrollView { VStack(spacing: 12) {
                        ForEach(Array(store.comparisons.enumerated()), id: \.offset) { index, model in recordRow(model, title: "観察 \(index+1) · \(model.stageTitle)") }
                    } }
                }
            }
            Spacer(minLength: 0)
        }.padding(28).frame(width: preview == nil ? 1040 : 1216, height: preview == nil ? 680 : 800)
            .background(ExperienceStyle.paper).foregroundStyle(ExperienceStyle.ink)
    }
    private func recordRow(_ model: M, title: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(title).font(.system(size: 21, weight: .bold)); Spacer(); Button("開いて動かす") { previewOriginal = model; preview = model }.buttonStyle(ExperienceButtonStyle()) }
            HStack(spacing: 28) { ForEach(Array(model.metrics.enumerated()), id: \.offset) { _, metric in VStack(alignment: .leading) { Text(metric.label).font(.caption); Text(metric.value).bold() } } }
        }.padding(20).background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
    }
    private var reflectionPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(ExperienceReflectionPrompt.text(M.gameID)).font(.system(size: 22, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                Text("予想は任意。正誤でクリアや作品は変わりません。試した条件と結果を、一緒に記録します。")
                    .font(.system(size: 16)).foregroundStyle(ExperienceStyle.muted)
                if let pending = store.pendingReflection {
                    Text("先に考えたこと：\(pending.prediction)").font(.system(size: 20, weight: .semibold))
                    if !pending.reason.isEmpty { Text("理由：\(pending.reason)") }
                    Text("盤面へ戻って試したら、ここで発見を残そう。結果は今の盤面と一緒に保存されるよ。")
                    TextField("結果からわかったこと（任意）", text: $discoveryText, axis: .vertical).lineLimit(3...5).textFieldStyle(.roundedBorder)
                    HStack {
                        Button("盤面へ戻って試す") { panel = nil }.buttonStyle(ExperienceButtonStyle(primary: true))
                        Button("今の結果を残す") { store.recordDiscovery(discoveryText); discoveryText = "" }.buttonStyle(ExperienceButtonStyle())
                    }
                } else {
                    TextField("どの条件を変えると、どうなると思う？", text: $predictionText, axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder)
                    TextField("そう考えた理由（任意）", text: $reasonText, axis: .vertical).lineLimit(2...3).textFieldStyle(.roundedBorder)
                    Button("予想を残して試す") { store.predict(predictionText, reason: reasonText); predictionText = ""; reasonText = ""; panel = nil }
                        .disabled(predictionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).buttonStyle(ExperienceButtonStyle(primary: true))
                }
                ForEach(store.reflections.filter { $0.after != nil }.reversed()) { note in
                    VStack(alignment: .leading, spacing: 10) {
                        Text("予想：\(note.prediction)").bold()
                        if !note.reason.isEmpty { Text("理由：\(note.reason)") }
                        Text("発見：\(note.discovery.isEmpty ? "結果を保存しました" : note.discovery)")
                        HStack {
                            Button("試す前を開く") { previewOriginal = note.before; preview = note.before }
                            Button("試した後を開く") { previewOriginal = note.after; preview = note.after }
                        }.buttonStyle(ExperienceButtonStyle())
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 12))
                }
            }.font(.system(size: 18)).padding(4)
        }
    }
}
