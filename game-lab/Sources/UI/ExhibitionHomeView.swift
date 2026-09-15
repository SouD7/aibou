import SwiftUI
#if canImport(CircuitCore)
import CircuitCore
#endif

/// Exhibition navigation owns no duplicate game state. Leaving a workbench
/// retains the same CircuitLabStore and the saved work.
struct ExhibitionHomeView: View {
    @ObservedObject var gameStore: CircuitLabStore
    @ObservedObject var exhibition: ExhibitionStore
    @ObservedObject private var workshop: WorkshopStore
    @StateObject private var narrator = GuideVoice()
    @StateObject private var lessons = LessonStore()
    @State private var overlay: Overlay?
    @State private var hoveredGame: String?
    @State private var hoveredArea: ExhibitionAreaID?
    @State private var hoveredGuide = false
    @State private var showingArtifact = false
    @State private var restartConfirmation = false
    @State private var legacyCircuit = false
    @AppStorage("aibou.lobbyMotionPaused") private var lobbyMotionPaused = false
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @Environment(\.scenePhase) private var scenePhase
    private enum Overlay { case map, workbook, lessons }

    init(gameStore: CircuitLabStore, exhibition: ExhibitionStore) {
        self.gameStore = gameStore; self.exhibition = exhibition
        self.workshop = gameStore.workshop
    }

    private var playing: Bool { if case .playing = exhibition.route { return true }; return false }
    private var reduced: Bool { workshop.reducedMotion || systemReducedMotion }
    private var currentGame: ExhibitionGame? {
        switch exhibition.route {
        case .entry(let id), .playing(let id): return ExhibitionCatalog.game(id)
        default: return nil
        }
    }
    private var roomTitle: String {
        switch exhibition.route {
        case .lobby: return "総合ロビー"
        case .area(let id): return "\(id.letter)  \(ExhibitionCatalog.area(id).title)"
        case .entry(let id), .playing(let id): return ExhibitionCatalog.game(id)?.title ?? "展示館"
        }
    }
    private var guideLine: String {
        if hoveredGuide { return "気になるしくみを、一緒に見つけよう。私をクリックすると、20の小さな授業を選べるよ。" }
        if let id = hoveredGame, let game = ExhibitionCatalog.game(id) { return game.guideInvitation }
        if let id = hoveredArea { return ExhibitionCatalog.area(id).guideInvitation }
        switch exhibition.route {
        case .lobby: return "ようこそ。気になる扉を開けて、PCの中のしくみを一緒に見にいこう。"
        case .area(let id): return ExhibitionCatalog.area(id).guideInvitation
        case .entry(let id), .playing(let id): return ExhibitionCatalog.game(id)?.guideInvitation ?? "一緒に見てみよう。"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            navigation
            ZStack {
                Group {
                    if playing {
                        if let game = currentGame, !legacyCircuit || game.id != ExhibitionCatalog.circuitGameID {
                            ExperienceRouterView(gameID: game.id, onExit: { navigate { exhibition.goBack() } })
                        } else {
                            CircuitLabView(store: gameStore, embeddedInExhibition: true)
                        }
                    } else {
                        ExhibitionStage {
                            scene.id(String(describing: exhibition.route)).transition(.opacity)
                        }
                    }
                }.disabled(overlay != nil).accessibilityHidden(overlay != nil)
                if let overlay {
                    ExhibitionStage {
                        switch overlay {
                        case .map:
                            ExhibitionMapView(exhibition: exhibition, workshop: workshop,
                                openGame: { id in dismissOverlay(); navigate { exhibition.openGame(id) } },
                                openArea: { id in dismissOverlay(); navigate { exhibition.visitArea(id) } },
                                close: dismissOverlay)
                        case .workbook:
                            ExperienceWorkbookView(exhibition: exhibition, workshop: workshop,
                                close: dismissOverlay,
                                openGame: { id in dismissOverlay(); navigate { exhibition.openGame(id) } },
                                openLegacyArtifact: { showingArtifact = true })
                        case .lessons:
                            LessonExperienceView(store: lessons, close: dismissOverlay,
                                openExhibit: { id in dismissOverlay(); navigate { exhibition.openGame(id) } })
                        }
                    }.transition(.opacity).zIndex(2)
                }
            }
            if !playing {
                companionCaption.opacity(overlay == nil ? 1 : 0)
                    .disabled(overlay != nil).accessibilityHidden(overlay != nil)
            }
            if !exhibition.saveError.isEmpty {
                saveNotice.disabled(overlay != nil).accessibilityHidden(overlay != nil)
            }
        }
        .frame(minWidth: 1100, minHeight: playing ? 735 : 730)
        .foregroundStyle(ExhibitionStyle.ink).background(ExhibitionStyle.paper)
        .preferredColorScheme(.light)
        .onDisappear { narrator.stop(); workshop.disappear() }
        .onChange(of: scenePhase) { if $0 != .active { narrator.stop(); workshop.cancelTest(announce: false) } }
        .sheet(isPresented: $showingArtifact) {
            if let artifact = workshop.state.completedArtifact {
                WorkshopArtifactView(artifact: artifact) { showingArtifact = false }
            }
        }
        .confirmationDialog("作業中の回路を最初から作り直しますか？", isPresented: $restartConfirmation, titleVisibility: .visible) {
            Button("最初から作る") { gameStore.showsSandbox = false; workshop.restart(); startCircuit() }
            Button("キャンセル", role: .cancel) {}
        } message: { Text("完成した作品は日記に残ります。") }
    }

    private var navigation: some View {
        HStack(spacing: 22) {
            Button { dismissOverlay(); navigate { exhibition.goToLobby() } } label: {
                Text("aibou").font(.system(size: 24, weight: .bold, design: .rounded)).tracking(-1)
            }.buttonStyle(.plain).accessibilityLabel("展示館のロビーへ").accessibilityIdentifier("ex.lobby")
            Rectangle().fill(ExhibitionStyle.ink.opacity(0.15)).frame(width: 1, height: 25)
            DestinationNavigation(current: .exhibition,
                onExhibition: { dismissOverlay(); navigate { exhibition.goToLobby() } },
                exhibitionIdentifier: "ex.exhibition")
            if exhibition.route != .lobby {
                Button { dismissOverlay(); navigate { exhibition.goBack() } } label: {
                    Label(playing || currentGame != nil ? "展示室へ" : "ロビー", systemImage: "chevron.left")
                }.buttonStyle(.plain).font(.system(size: 14, weight: .semibold)).accessibilityIdentifier("ex.back")
            }
            Spacer(minLength: 8)
            Text(overlay == nil ? roomTitle : "展示館")
                .font(.system(size: 18, weight: .bold, design: .rounded)).lineLimit(1)
                .accessibilityIdentifier("ex.room.title")
            Spacer(minLength: 8)
            if exhibition.route == .lobby {
                Button { lobbyMotionPaused.toggle() } label: {
                    Image(systemName: lobbyMotionPaused ? "play.circle" : "pause.circle")
                        .font(.system(size: 19))
                }.buttonStyle(.plain)
                    .accessibilityLabel(lobbyMotionPaused ? "女の子の動きを再開" : "女の子の動きを止める")
                    .accessibilityValue(lobbyMotionPaused ? "停止中" : "再生中")
                    .accessibilityIdentifier("ex.lobby.motion")
                    .help(lobbyMotionPaused ? "女の子の動きを再開" : "女の子の動きを止める")
            }
            Button { showOverlay(.workbook) } label: { Label("日記", systemImage: "book.closed") }
                .buttonStyle(.plain).font(.system(size: 14, weight: .semibold)).accessibilityIdentifier("ex.workbook")
            Button { showOverlay(.lessons) } label: { Label("授業", systemImage: "bubble.left.and.text.bubble.right") }
                .buttonStyle(.plain).font(.system(size: 14, weight: .semibold)).accessibilityIdentifier("ex.lessons")
            Button { showOverlay(.map) } label: { Label("館内マップ", systemImage: "map") }
                .buttonStyle(ExhibitionButtonStyle(accent: .white.opacity(0.8), compact: true)).accessibilityIdentifier("ex.map")
        }.padding(.horizontal, 25).frame(height: 64)
            .background(ExhibitionStyle.paper)
            .overlay(alignment: .bottom) { Rectangle().fill(ExhibitionStyle.ink.opacity(0.8)).frame(height: 1.5) }
            .disabled(overlay != nil && overlay != .lessons)
            .accessibilityHidden(overlay != nil && overlay != .lessons)
    }

    @ViewBuilder private var scene: some View {
        switch exhibition.route {
        case .lobby: lobby
        case .area(let id): areaScene(id)
        case .entry(let id):
            if let game = ExhibitionCatalog.game(id) { entryScene(game) }
        case .playing: EmptyView()
        }
    }

    private var lobby: some View {
        ZStack(alignment: .topLeading) {
            LobbyAnimatedScene(reducedMotion: reduced || lobbyMotionPaused,
                               active: overlay == nil && scenePhase == .active)
            ForEach(ExhibitionCatalog.areas) { area in
                if let placement = ExhibitionLayout.doors[area.id] {
                    ExhibitionHotspot(placement: placement, title: "\(area.id.letter)  \(area.title)", subtitle: area.learningTopics,
                        accent: ExhibitionStyle.color(area.id), id: "ex.area.\(area.id.rawValue)", door: true, reduceMotion: reduced,
                        onHover: { inside in hoveredArea = inside ? area.id : nil }) {
                            navigate { exhibition.visitArea(area.id) }
                        }
                }
            }
            LobbyGuideHotspot(action: { showOverlay(.lessons) }, onHover: { hoveredGuide = $0 })
            Button { showOverlay(.workbook) } label: {
                VStack(spacing: 5) {
                    Label("日記", systemImage: "book.closed")
                        .font(.system(size: 23, weight: .semibold, design: .rounded))
                    Text(workshop.state.completedArtifact == nil ? "発見を、ここに残そう" : "準備完了ランプが完成！")
                        .font(.system(size: 17)).foregroundStyle(ExhibitionStyle.muted)
                }.padding(.horizontal, 24).padding(.vertical, 15)
                    .background(ExhibitionStyle.paper, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(ExhibitionStyle.ink, lineWidth: 1.5))
            }.buttonStyle(.plain).accessibilityIdentifier("ex.lobby.workbook").position(x: 245, y: 739)
            HStack(spacing: 23) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(workshop.state.hasStarted ? "ふたりの続き、ここから。" : "最初の体験におすすめ")
                        .font(.system(size: 17)).foregroundStyle(ExhibitionStyle.muted)
                    Text("論理回路").font(.system(size: 25, weight: .bold, design: .rounded))
                }
                Button {
                    if workshop.state.hasStarted { startCircuit() }
                    else { navigate { exhibition.openGame(ExhibitionCatalog.circuitGameID) } }
                } label: {
                    Label(workshop.state.hasStarted ? "つづきから" : "のぞいてみる", systemImage: "arrow.right")
                }.buttonStyle(ExhibitionButtonStyle(accent: ExhibitionStyle.color(.a)))
                    .accessibilityIdentifier("ex.lobby.circuit")
            }.padding(21).background(ExhibitionStyle.paper, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(ExhibitionStyle.ink, lineWidth: 2))
                .position(x: 1190, y: 811)
        }
    }

    private func areaScene(_ id: ExhibitionAreaID) -> some View {
        ZStack(alignment: .topLeading) {
            ExhibitionRoomArt(name: "area-\(id.rawValue)")
            deviceLabels(id).allowsHitTesting(false).accessibilityHidden(true)
            ForEach(Array(ExhibitionCatalog.games(in: id).enumerated()), id: \.element.id) { index, game in
                ExhibitionHotspot(placement: ExhibitionLayout.exhibits(id)[index], title: game.title,
                    subtitle: statusTitle(game), accent: ExhibitionStyle.color(id), id: "ex.game.\(game.id)", reduceMotion: reduced,
                    onHover: { inside in hoveredGame = inside ? game.id : nil }) {
                        navigate { exhibition.openGame(game.id) }
                    }
            }
        }
    }

    private func entryScene(_ game: ExhibitionGame) -> some View {
        let circuit = game.id == ExhibitionCatalog.circuitGameID
        return ZStack(alignment: .topLeading) {
            ExhibitionRoomArt(name: circuit && ExhibitionArtwork.images["circuit-entry"] != nil ? "circuit-entry" : "area-\(game.areaID.rawValue)")
            if !circuit { deviceLabels(game.areaID).allowsHitTesting(false).accessibilityHidden(true) }
            LinearGradient(colors: [.clear, ExhibitionStyle.ink.opacity(0.20)], startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false).accessibilityHidden(true)
            HStack(spacing: 12) {
                Text(game.areaID.letter).font(.system(size: 22, weight: .bold))
                    .frame(width: 43, height: 43).background(ExhibitionStyle.color(game.areaID), in: RoundedRectangle(cornerRadius: 9))
                Text(ExhibitionCatalog.area(game.areaID).title).font(.system(size: 23, weight: .semibold))
            }.padding(12).background(ExhibitionStyle.paper.opacity(0.95), in: RoundedRectangle(cornerRadius: 12))
                .position(x: 220, y: 66)
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 30) {
                    Image(systemName: game.icon).font(.system(size: 35, weight: .medium))
                        .frame(width: 74, height: 74).background(ExhibitionStyle.color(game.areaID).opacity(0.24), in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(game.title).font(.system(size: 33, weight: .bold, design: .rounded))
                            .accessibilityIdentifier("ex.entry.title")
                        Text(game.learningDescription).font(.system(size: 22)).lineSpacing(7).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 13) {
                        if game.isPlayable {
                            Button { legacyCircuit = false; navigate { _ = exhibition.startGame(game.id) } } label: {
                                Label(exhibition.progress(for: game.id)?.canResume == true ? "つづきから" : "一緒にはじめる", systemImage: "play.fill")
                            }.buttonStyle(ExhibitionButtonStyle(accent: ExhibitionStyle.color(game.areaID)))
                                .accessibilityIdentifier("ex.entry.start")
                            if circuit && workshop.state.hasStarted {
                                Button("以前の回路を開く") { startCircuit() }
                                    .buttonStyle(.plain).font(.system(size: 18, weight: .medium)).accessibilityIdentifier("ex.entry.restart")
                            }
                        } else {
                            Text("ただいま準備中").font(.system(size: 21, weight: .semibold))
                                .padding(.horizontal, 24).padding(.vertical, 17)
                                .background(ExhibitionStyle.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
                                .accessibilityIdentifier("ex.entry.preparing")
                            Text("体験の公開まで、ほかの展示も見てみよう。")
                                .font(.system(size: 16)).foregroundStyle(ExhibitionStyle.muted).frame(width: 240).fixedSize(horizontal: false, vertical: true)
                        }
                    }.frame(width: 255)
                }
                HStack(spacing: 12) {
                    Image(systemName: "sparkle").foregroundStyle(ExhibitionStyle.color(game.areaID))
                    Text(game.isPlayable ? (circuit ? "つなぐ  →  試す  →  光り方をくらべる" : "触って試す  →  変化を観察する  →  発見を残す") : "公開後は、このしくみを手を動かして体験できます。")
                        .font(.system(size: 21, weight: .medium)).lineLimit(2)
                    Spacer()
                    if !game.isPlayable {
                        Button { navigate { exhibition.openGame(ExhibitionCatalog.circuitGameID) } } label: {
                            Label("あそべる論理回路へ", systemImage: "arrow.right")
                        }.buttonStyle(.plain).font(.system(size: 18, weight: .semibold)).accessibilityIdentifier("ex.entry.circuit")
                    }
                }.padding(.top, 12).overlay(alignment: .top) { Rectangle().fill(ExhibitionStyle.ink.opacity(0.13)).frame(height: 1) }
            }.padding(30).frame(width: 1480)
                .background(RoundedRectangle(cornerRadius: 16).fill(ExhibitionStyle.paper.opacity(0.98))
                    .shadow(color: .black.opacity(0.14), radius: 10, y: 6))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(ExhibitionStyle.ink, lineWidth: 2))
                .position(x: 800, y: 743)
        }
    }

    private var companionCaption: some View {
        HStack(spacing: 17) {
            HStack(spacing: 7) {
                Circle().fill(ExhibitionStyle.color(exhibition.currentAreaID ?? .a)).frame(width: 8, height: 8)
                Text("aibou").font(.system(size: 15, weight: .bold, design: .rounded))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(guideLine).font(.system(size: 15, weight: .medium)).lineLimit(2)
                    .accessibilityIdentifier("ex.guide.caption")
                if let reason = narrator.unavailableReason {
                    Text(reason).font(.system(size: 11)).foregroundStyle(ExhibitionStyle.muted)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button {
                if narrator.isSpeaking { narrator.stop() }
                else { narrator.speak(guideLine) }
            } label: { Image(systemName: narrator.isSpeaking ? "stop.fill" : "speaker.wave.2") }
                .buttonStyle(.plain).frame(width: 44, height: 44)
                .accessibilityLabel(narrator.isSpeaking ? "案内の音声を止める" : "案内を聞く").accessibilityIdentifier("ex.guide.speak")
        }.padding(.horizontal, 29).frame(height: 68)
            .background(ExhibitionStyle.paper).overlay(alignment: .top) { Rectangle().fill(ExhibitionStyle.ink.opacity(0.15)).frame(height: 1) }
    }

    private var saveNotice: some View {
        HStack {
            Text(exhibition.saveError).font(.system(size: 12))
            Spacer()
            Button("保存を再試行") { exhibition.retrySave() }.accessibilityIdentifier("ex.save.retry")
        }.padding(10).background(Color.orange.opacity(0.13))
    }

    private func statusTitle(_ game: ExhibitionGame) -> String {
        let status = exhibition.status(for: game, workshop: workshop.state)
        return status == .visited ? "あそべる" : status.title
    }
    @ViewBuilder private func deviceLabels(_ area: ExhibitionAreaID) -> some View {
        if area == .b {
            Text("3").font(.system(size: 34, weight: .bold, design: .rounded))
                .rotationEffect(.degrees(24)).position(x: 0.333 * 1600, y: 0.426 * 900)
            ForEach(Array(["2", "3", "5"].enumerated()), id: \.offset) { index, number in
                Text(number).font(.system(size: 34, weight: .bold, design: .rounded))
                    .rotationEffect(.degrees(4)).position(x: (0.479 + Double(index) * 0.046) * 1600, y: 0.426 * 900)
            }
        } else if area == .d {
            Group {
                Text("CPU").position(x: 0.177 * 1600, y: 0.710 * 900)
                Text("SSD").position(x: 0.515 * 1600, y: 0.675 * 900)
                Text("GPU").position(x: 0.526 * 1600, y: 0.799 * 900)
            }.font(.system(size: 23, weight: .bold, design: .rounded))
        }
    }
    private func navigate(_ action: () -> Void) {
        narrator.stop(); workshop.cancelTest(announce: false)
        hoveredGame = nil; hoveredArea = nil; hoveredGuide = false
        withAnimation(reduced ? nil : .easeInOut(duration: 0.2), action)
    }
    private func startCircuit() {
        legacyCircuit = true
        narrator.stop()
        if workshop.resumePending { workshop.resume() }
        else if workshop.state.phase == .welcome { workshop.act(.begin) }
        navigate { _ = exhibition.startGame(ExhibitionCatalog.circuitGameID) }
    }
    private func showOverlay(_ value: Overlay) {
        exhibition.refreshExperienceProgress()
        if value == .lessons { lessons.showLibrary() }
        narrator.stop(); workshop.cancelTest(announce: false); workshop.stopSpeech()
        hoveredGame = nil; hoveredArea = nil; hoveredGuide = false
        withAnimation(reduced ? nil : .easeOut(duration: 0.16)) { overlay = value }
    }
    private func dismissOverlay() {
        withAnimation(reduced ? nil : .easeOut(duration: 0.16)) { overlay = nil }
    }
}

struct ExhibitionAppView: View {
    @StateObject private var game = CircuitLabStore()
    @StateObject private var exhibition = ExhibitionStore()
    var body: some View {
        ExhibitionHomeView(gameStore: game, exhibition: exhibition)
            .onAppear {
                let args = ProcessInfo.processInfo.arguments
                if let i = args.firstIndex(of: "--experience"), i + 1 < args.count {
                    _ = exhibition.startGame(args[i + 1])
                }
            }
    }
}
