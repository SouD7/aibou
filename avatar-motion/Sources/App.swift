import SwiftUI
import SpriteKit
import Combine
import UniformTypeIdentifiers

@MainActor
final class AvatarAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let request = CaptureRequest.parse(CommandLine.arguments) else { return }
        DispatchQueue.main.async {
            do {
                try SceneCapture.run(request)
                print("Captured SpriteKit frames in \(request.directory.path)")
                NSApplication.shared.terminate(nil)
            } catch {
                fputs("Capture failed: \(error.localizedDescription)\n", stderr)
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

@MainActor
final class AvatarStore: ObservableObject {
    @Published private(set) var componentWarnings: [String: ComponentWarning] = [:]
    @Published private(set) var selectedComponent: RoomComponent?
    @Published private(set) var roomVisualState = RoomVisualState()
    @Published private(set) var selectedStandingVariant: AvatarPoseID = .standing
    @Published var selectedPose: AvatarPoseID = .standing {
        didSet {
            scene?.selectPose(selectedPose)
            if selectedPose.isStanding { selectedStandingVariant = selectedPose }
            else { voice.stop() }
        }
    }
    @Published var paused = false { didSet { updatePause(); if paused { voice.stop() } } }
    @Published var reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        didSet { scene?.reducedMotion = reducedMotion }
    }
    @Published var strength = 1.0 { didSet { scene?.motionStrength = strength } }
    @Published var focused = false { didSet { scene?.focused = focused } }
    @Published var errorMessage: String?
    @Published private(set) var sampleURL: URL?
    @Published private(set) var effectivelyPaused = false
    let voice = VoicePlayer()
    let scene: AvatarScene?
    private var windowVisible = true
    private var subscriptions: Set<AnyCancellable> = []

    init() {
        do {
            let loaded = try SceneLoader.load()
            scene = loaded.0
            sampleURL = ["aiff", "wav", "m4a"].compactMap {
                let url = loaded.1.appendingPathComponent("sample.\($0)")
                guard FileManager.default.fileExists(atPath: url.path),
                      let envelope = try? AudioEnvelope.load(url: url), !envelope.values.isEmpty else { return nil }
                return url
            }.first
        } catch {
            scene = nil; errorMessage = "表示を準備できません: \(error.localizedDescription)"
        }
        voice.$amplitude.sink { [weak self] value in self?.scene?.speechAmplitude = value }.store(in: &subscriptions)
        voice.$isPlaying.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        voice.$errorMessage.compactMap { $0 }.sink { [weak self] in self?.errorMessage = $0 }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSWindow.didMiniaturizeNotification).sink { [weak self] _ in
            self?.windowVisible = false; self?.voice.stop(); self?.updatePause()
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSWindow.didDeminiaturizeNotification).sink { [weak self] _ in
            self?.windowVisible = true; self?.updatePause()
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification).sink { [weak self] note in
            guard let window = note.object as? NSWindow, !window.isMiniaturized else { return }
            self?.windowVisible = window.occlusionState.contains(.visible)
            if self?.windowVisible == false { self?.voice.stop() }
            self?.updatePause()
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didHideNotification).sink { [weak self] _ in
            self?.windowVisible = false; self?.voice.stop(); self?.updatePause()
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didUnhideNotification).sink { [weak self] _ in
            self?.windowVisible = true; self?.updatePause()
        }.store(in: &subscriptions)
        scene?.reducedMotion = reducedMotion
        scene?.onComponentSelection = { [weak self] component in
            self?.selectedComponent = component
        }
        scene?.onWarningsChange = { [weak self] warnings in self?.componentWarnings = warnings }
        if let scene { roomVisualState = scene.visualState }
        scene?.onVisualStateChange = { [weak self] state in self?.roomVisualState = state }
    }

    func togglePause() { paused.toggle() }
    func selectComponent(_ id: String?) { scene?.selectRoomComponent(id) }
    func setComponentWarning(_ warning: ComponentWarning?, for id: String) {
        scene?.setComponentWarning(warning, for: id)
    }
    func componentWarning(for id: String) -> ComponentWarning? {
        guard id == "fans" else { return componentWarnings[id] }
        let messages = ["fan-1", "fan-2"].compactMap { componentWarnings[$0]?.message }
            .filter { !$0.isEmpty }
        let distinct = messages.reduce(into: [String]()) { result, message in
            if !result.contains(message) { result.append(message) }
        }
        guard !distinct.isEmpty else {
            return componentWarnings["fan-1"] != nil || componentWarnings["fan-2"] != nil
                ? ComponentWarning(message: "ファンに警告があります。") : nil
        }
        return ComponentWarning(message: distinct.joined(separator: "\n"))
    }
    func hasComponentWarning(_ id: String) -> Bool { componentWarning(for: id) != nil }
    func replaceComponentWarnings(_ warnings: [String: ComponentWarning]) {
        var expanded = warnings
        if let fans = expanded.removeValue(forKey: "fans") {
            expanded["fan-1"] = fans; expanded["fan-2"] = fans
        }
        scene?.replaceComponentWarnings(expanded)
    }
    func toggleWarningDemo(for id: String) {
        setComponentWarning(hasComponentWarning(id) ? nil :
            ComponentWarning(message: "表示テスト用の警告です。実際の異常ではありません。"), for: id)
    }
    func setComponentVisualState(_ optionID: String, for id: String) {
        guard scene?.setComponentVisualState(optionID, for: id) == true else {
            errorMessage = "この表示状態は選択できません。"; return
        }
    }
    func selectPrimaryMode(_ pose: AvatarPoseID) {
        selectedPose = pose == .standing ? selectedStandingVariant : pose
    }
    func selectStandingVariant(_ pose: AvatarPoseID) {
        guard pose.isStanding else { return }
        selectedPose = pose
    }
    func playSample() {
        if let sampleURL { selectedPose = selectedStandingVariant; paused = false; voice.play(url: sampleURL) }
    }
    func playImported(_ url: URL) {
        selectedPose = selectedStandingVariant; paused = false; voice.play(url: url)
    }

    private func updatePause() {
        effectivelyPaused = paused || !windowVisible
        scene?.setAnimationPaused(effectivelyPaused)
    }
}

struct AvatarWindow: View {
    @StateObject var store: AvatarStore
    @State private var importingAudio = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.45)
            stage
            Divider().opacity(0.45)
            controls
        }
        .background(Color(nsColor: NSColor(red: 0.09, green: 0.082, blue: 0.10, alpha: 1)))
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .fileImporter(isPresented: $importingAudio,
                      allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { store.playImported(url) }
            case .failure(let error): store.errorMessage = "音声を開けません: \(error.localizedDescription)"
            }
        }
        .alert("AIBOU", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("閉じる") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color(red: 0.28, green: 0.75, blue: 0.78).opacity(0.18))
                Image(systemName: "sparkles").foregroundStyle(Color(red: 0.48, green: 0.91, blue: 0.91))
            }.frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("AIBOU motion room").font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(statusText).font(.caption).foregroundStyle(.white.opacity(0.58))
            }
            Spacer()
            if let scene = store.scene {
                Menu {
                    ForEach(scene.componentCatalog.selectionComponents) { component in
                        Button { store.selectComponent(component.id) } label: {
                            Label("\(store.hasComponentWarning(component.id) ? "⚠︎ " : "")\(component.title)（\(component.category)）", systemImage: component.symbol)
                        }
                    }
                } label: {
                    Label("コンポーネント", systemImage: "square.grid.2x2")
                }
                .fixedSize().disabled(store.focused)
                .help("部屋のコンポーネントを一覧から選択します")
                Menu {
                    Text("警告マークの表示テスト")
                    ForEach(scene.componentCatalog.selectionComponents) { component in
                        Toggle(component.title, isOn: Binding(
                            get: { store.hasComponentWarning(component.id) },
                            set: { _ in store.toggleWarningDemo(for: component.id) }))
                    }
                    Divider()
                    Button("すべてに表示（デモ）") {
                        store.replaceComponentWarnings(Dictionary(uniqueKeysWithValues:
                            scene.componentCatalog.selectionComponents.map {
                                ($0.id, ComponentWarning(message: "表示テスト用の警告です。実際の異常ではありません。"))
                            }))
                    }
                    Button("すべて解除") { store.replaceComponentWarnings([:]) }
                        .disabled(store.componentWarnings.isEmpty)
                } label: {
                    let warningCount = scene.componentCatalog.selectionComponents.filter { store.hasComponentWarning($0.id) }.count
                    Label(warningCount == 0 ? "警告デモ" : "警告デモ \(warningCount)",
                          systemImage: "exclamationmark.bubble")
                }.fixedSize().help("検知は行わず、警告表示だけを切り替えます")
            }
            HStack(spacing: 5) {
                Circle().fill(store.effectivelyPaused ? Color.orange : Color.green).frame(width: 7, height: 7)
                Text(store.effectivelyPaused ? "一時停止" : "ゆっくり動作中").font(.caption).foregroundStyle(.white.opacity(0.72))
            }
        }.padding(.horizontal, 16).frame(height: 54)
    }

    @ViewBuilder private var stage: some View {
        if let scene = store.scene {
            InteractiveRoomView(scene: scene)
                .aspectRatio(CGFloat(scene.size.width / scene.size.height), contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.075, green: 0.068, blue: 0.085))
                .overlay(alignment: .topTrailing) {
                    if let component = store.selectedComponent {
                        RoomComponentDetail(component: component,
                                            warning: store.componentWarning(for: component.id),
                                            visualState: store.roomVisualState,
                                            setVisualState: { store.setComponentVisualState($0, for: component.id) }) {
                            store.selectComponent(nil)
                        }
                            .padding(16)
                    }
                }
                .onExitCommand { store.selectComponent(nil) }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "photo.badge.exclamationmark").font(.largeTitle)
                Text("シーンを表示できません").font(.headline)
                Text("Assets/rig.json と画像を確認してください。").font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var controls: some View {
        VStack(spacing: 13) {
            HStack(spacing: 8) {
                ForEach(AvatarPoseID.primaryModes) { pose in
                    Button { store.selectPrimaryMode(pose) } label: {
                        Label(pose.japaneseTitle, systemImage: pose.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .frame(minWidth: 72)
                    }
                    .buttonStyle(PoseButtonStyle(selected: pose == .standing ? store.selectedPose.isStanding : store.selectedPose == pose))
                }
                Divider().frame(height: 24).overlay(.white.opacity(0.18)).padding(.horizontal, 3)
                Button(action: store.togglePause) {
                    Label(store.paused ? "再開" : "止める", systemImage: store.paused ? "play.fill" : "pause.fill")
                        .frame(minWidth: 61)
                }.buttonStyle(.bordered)
                Spacer()
                Button(action: store.playSample) { Label("サンプル音声", systemImage: "waveform") }
                    .buttonStyle(.bordered).disabled(store.sampleURL == nil)
                    .help(store.sampleURL == nil ? "Assets/sample.aiff がありません" : "実際の音量から口の動きを作ります")
                Button { importingAudio = true } label: { Label("音声を選ぶ…", systemImage: "music.note") }
                    .buttonStyle(.borderedProminent).tint(Color(red: 0.18, green: 0.61, blue: 0.65))
            }
            if store.selectedPose.isStanding {
                HStack(spacing: 12) {
                    Text("立ち姿").font(.caption).foregroundStyle(.white.opacity(0.62))
                    Picker("立ち姿", selection: Binding(get: { store.selectedStandingVariant },
                                                        set: { store.selectStandingVariant($0) })) {
                        ForEach(AvatarPoseID.standingVariants) { pose in
                            Text(pose.standingVariantTitle).tag(pose)
                        }
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 285)
                    Spacer()
                    Text("声の再生中も立ち姿を切り替えられます")
                        .font(.caption2).foregroundStyle(.white.opacity(0.42))
                }
            }
            HStack(spacing: 14) {
                Label("アバターの動き", systemImage: "dial.low").font(.caption).foregroundStyle(.white.opacity(0.62))
                Slider(value: $store.strength, in: 0...1.5).frame(maxWidth: 260)
                Text(String(format: "%.0f%%", store.strength * 100)).font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.68)).frame(width: 42, alignment: .trailing)
                Spacer()
                Toggle("動きを抑える", isOn: $store.reducedMotion).toggleStyle(.switch).controlSize(.small)
                Toggle("キャラクターのみ", isOn: $store.focused).toggleStyle(.switch).controlSize(.small)
            }
        }.padding(.horizontal, 16).padding(.vertical, 14)
            .background(.ultraThinMaterial.opacity(0.35)).frame(minHeight: 104)
    }

    private var statusText: String {
        if store.voice.isPlaying { return "声に合わせて話しています" }
        switch store.selectedPose {
        case .standing: return "部屋でひと休み"
        case .standingBackHands: return "手を後ろで組んでひと休み"
        case .standingFrontHands: return "手を前で組んでひと休み"
        case .sleeping: return "静かに眠っています"
        case .reading: return "本を読んでいます"
        }
    }
}

struct PoseButtonStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 11).padding(.vertical, 7)
            .background(selected ? Color(red: 0.16, green: 0.62, blue: 0.66).opacity(0.78) : Color.white.opacity(configuration.isPressed ? 0.13 : 0.07),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(selected ? 0.18 : 0.08)))
    }
}

@main
struct AvatarMotionApp: App {
    @NSApplicationDelegateAdaptor(AvatarAppDelegate.self) private var delegate
    @StateObject private var store = AvatarStore()

    var body: some Scene {
        WindowGroup("AIBOU Motion") {
            AvatarWindow(store: store).frame(minWidth: 920, minHeight: 650)
        }
        .defaultSize(width: 1100, height: 735)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
