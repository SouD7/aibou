import SwiftUI
import SpriteKit

struct IntegratedWindow: View {
    @ObservedObject var app: IntegratedStore
    @ObservedObject var avatar: AvatarStore
    @ObservedObject var monitor: MonitorStore
    @ObservedObject var consultation: ConsultationModel
    @State private var addQuestionRequest = 0

    init(app: IntegratedStore) {
        self.app = app
        avatar = app.avatar
        monitor = app.monitor
        consultation = app.consultation
    }

    var body: some View {
        GeometryReader { geometry in
            room(size: geometry.size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(item: $app.presentation) { panel in
                VStack(spacing: 0) {
                    HStack {
                        Text(panel.title).font(.headline)
                        Spacer()
                        Button("閉じる") { app.presentation = nil }.keyboardShortcut(.cancelAction)
                    }.padding(16).monitorCircuitExclusion()
                    Divider()
                    MonitorWindow(store: monitor, consultation: app.consultation,
                                  presentation: panel.monitorPresentation)
                }
                .frame(width: min(max(geometry.size.width - 80, 900), 1380),
                       height: min(max(geometry.size.height - 70, 600), 920))
                .monitorSurface()
                .environment(\.monitorAppearance, panel.id == "monitor" ? .system : .room)
                .preferredColorScheme(panel.id == "monitor" ? .light : .dark)
            }
            .sheet(isPresented: $app.showingConnection) {
                RoomConnectionView(model: app.consultation) {
                    app.showingConnection = false
                    app.beginConsultation()
                }
            }
        }
        .background(Color(red: 0.085, green: 0.11, blue: 0.14))
    }

    private func room(size: CGSize) -> some View {
        // Keep one SKView mounted while the demo controls appear/disappear.
        // Reparenting a shared SKScene between separate representables loses its hit-test view.
        AvatarWindow(store: avatar, exitDemo: app.exitDemo, showsControls: app.session.isDemo)
        .overlay(alignment: .topLeading) {
            if !app.session.isDemo {
                ScrollView(.vertical) { menu }
                    .frame(width: 114, height: min(app.menuExpanded ? 678 : 114, size.height - 145))
                    .padding(22)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !app.session.isDemo, let component = avatar.selectedComponent {
                componentSummary(component).padding(22)
                    .frame(maxHeight: max(220, size.height - 130), alignment: .top)
            }
        }
        .overlay(alignment: .bottom) {
            // Release local editor/confirmation state while a panel can edit the shared model.
            // Dismissal rebuilds the room surface from the latest question and conversation.
            RoomConsultationSurface(model: consultation, store: monitor, addQuestionRequest: addQuestionRequest,
                                    isVisible: app.session.isConsulting && app.presentation == nil)
                .frame(maxWidth: min(980, size.width - 380))
                .frame(maxHeight: min(440, size.height * 0.5))
                .padding(.bottom, 24)
        }
        .overlay(alignment: .bottomLeading) {
            if !app.session.isDemo {
            Button {
                if app.session.isConsulting { app.endConsultation() }
                else { app.beginConsultation() }
            } label: {
                Label(app.session.isConsulting ? "終了" : "相談",
                      systemImage: app.session.isConsulting ? "xmark" : "bubble.left.and.bubble.right")
                    .font(.system(size: 22.5, weight: .semibold))
                    .padding(.horizontal, 31.5).padding(.vertical, 22.5)
            }
            .buttonStyle(.plain).foregroundStyle(.white)
            .background(Color(red: 0.08, green: 0.22, blue: 0.27).opacity(0.96), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.3)))
            .shadow(radius: 8, y: 3).padding(24)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if app.session.isConsulting {
                Button { addQuestionRequest += 1 } label: {
                    Label("追加", systemImage: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 21).padding(.vertical, 15)
                }
                .buttonStyle(.plain).foregroundStyle(.white)
                .background(Color(red: 0.08, green: 0.22, blue: 0.27).opacity(0.96), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.3)))
                .disabled(!RoomConsultationFlow.canAddQuestion(messages: consultation.messages, busy: consultation.busy,
                                                               question: consultation.question)
                          || !consultation.signedIn)
                .shadow(radius: 8, y: 3).padding(24)
            }
        }
    }

    private var menu: some View {
        VStack(spacing: 10) {
            roundButton("メニュー", symbol: app.menuExpanded ? "xmark" : "line.3.horizontal", size: 114) {
                withAnimation(.easeInOut(duration: 0.18)) { app.menuExpanded.toggle() }
            }
            if app.menuExpanded {
                roundButton("メンテナンス", symbol: "wrench.and.screwdriver", size: 84) { app.open(.maintenance) }
                roundButton("アプリ", symbol: "square.grid.2x2", size: 84) { app.open(.applications) }
                roundButton("モニター", symbol: "waveform.path.ecg", size: 84) { app.open(.monitor) }
                roundButton("学習", symbol: "book", size: 84) { }
                roundButton("デモ", symbol: "slider.horizontal.3", size: 84) { app.enterDemo() }
                roundButton("タイトルへ", symbol: "arrow.uturn.backward", size: 84) { app.returnToTitle() }
            }
        }
    }

    private func roundButton(_ title: String, symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: size == 114 ? 7.5 : 6) {
                Image(systemName: symbol).font(.system(size: size == 114 ? 30 : 22, weight: .medium))
                Text(title).font(.system(size: size == 114 ? 16.5 : (title.count > 5 ? 12 : 14), weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }.frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain).foregroundStyle(.white)
        .background(Color(red: 0.075, green: 0.13, blue: 0.17).opacity(0.94), in: Circle())
        .overlay(Circle().stroke(.white.opacity(0.3)))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        .accessibilityLabel(title)
    }

    private func componentSummary(_ component: RoomComponent) -> some View {
        let summary = HardwareRoomPolicy.summary(for: component.id, panels: monitor.panels)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label(component.title, systemImage: component.symbol).font(.title3.bold())
                    Spacer()
                    Button { avatar.selectComponent(nil) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("コンポーネントを閉じる")
                }
                Text(component.summary).font(.callout).foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                Divider().overlay(.white.opacity(0.2))
                VStack(alignment: .leading, spacing: 7) {
                    Text("全体の負荷").font(.caption).foregroundStyle(.white.opacity(0.6))
                    Text(summary.title).font(.callout)
                    Text(summary.value).font(.system(size: 22, weight: .semibold, design: .rounded))
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    if !monitor.isRunning {
                        Text("監視停止中 · 最後の観測値").font(.caption).foregroundStyle(.yellow)
                    }
                }
                if let tab = HardwareRoomPolicy.tab(for: component.id) {
                    Button { app.open(.hardware(tab)) } label: {
                        HStack { Text("詳細を見る"); Spacer(); Image(systemName: "arrow.up.right") }
                            .padding(12)
                    }
                    .buttonStyle(.plain)
                    .background(MonitorAppearance.roomAccent, in: RoundedRectangle(cornerRadius: 10))
                }
            }.padding(22)
        }
        .frame(width: 320).fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(.white)
        .background(MonitorAppearance.roomBackground.opacity(0.97), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(MonitorAppearance.roomBorder))
        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
    }
}

/// Native menu actions keep the room accessible without adding controls over the artwork.
struct RoomComponentMenuItems: View {
    @ObservedObject var app: IntegratedStore
    @ObservedObject var avatar: AvatarStore

    var body: some View {
        if let scene = avatar.scene {
            ForEach(Array(scene.componentCatalog.selectionComponents.enumerated()), id: \.element.id) { index, component in
                Button {
                    app.menuExpanded = false
                    avatar.selectComponent(component.id)
                } label: {
                    Label("\(component.title)（\(component.category)）", systemImage: component.symbol)
                }
                .keyboardShortcut(index < 10
                                  ? KeyboardShortcut(KeyEquivalent(Character(String((index + 1) % 10))),
                                                     modifiers: [.command, .option]) : nil)
            }
            Divider()
            Button("選択した家具の詳細を見る") {
                if let id = avatar.selectedComponent?.id, let tab = HardwareRoomPolicy.tab(for: id) {
                    app.open(.hardware(tab))
                }
            }
            .keyboardShortcut("d", modifiers: [.command, .option])
            .disabled(avatar.selectedComponent.flatMap { HardwareRoomPolicy.tab(for: $0.id) } == nil)
            Button("選択を解除") { avatar.selectComponent(nil) }
                .disabled(avatar.selectedComponent == nil)
        }
    }
}

struct RoomConnectionView: View {
    @ObservedObject var model: ConsultationModel
    let ready: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("アバターに相談する").font(.title2.bold())
                Spacer()
                Button("閉じる") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("ChatGPTに接続して、AIBOUにこのMacのことを相談できます。")
            Text(model.accountLabel).font(.headline)
            Text(model.status).foregroundStyle(.secondary)
            if !model.error.isEmpty { Text(model.error).foregroundStyle(.red).textSelection(.enabled) }
            if !model.connected {
                TextField("Codex CLIのパス", text: $model.executablePath).textFieldStyle(.roundedBorder)
                HStack {
                    Button("実行ファイルを選択") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = false
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url { model.executablePath = url.path }
                    }.disabled(model.connecting)
                    Spacer()
                    Button(model.connecting ? "接続中…" : "ChatGPTへの接続を開始") {
                        Task { await model.connect() }
                    }.buttonStyle(.borderedProminent).disabled(model.connecting || model.executablePath.isEmpty)
                }
            } else if !model.signedIn {
                if let url = model.loginURL {
                    Button("ブラウザでログイン") { NSWorkspace.shared.open(url) }.buttonStyle(.borderedProminent)
                    Button("ログインを取消") { Task { await model.cancelLogin() } }
                } else {
                    Button("ChatGPTでログイン") { Task { await model.login() } }
                        .buttonStyle(.borderedProminent).disabled(model.connecting)
                }
            } else {
                Button("相談をはじめる", action: ready).buttonStyle(.borderedProminent)
            }
            Text("質問と確認した添付情報をOpenAIへ送信し、ChatGPTアカウントのCodex利用枠を使用します。回答の長さはメニューの「モニター」→「相談」で設定できます。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(28).frame(width: 550).preferredColorScheme(.light)
    }
}
