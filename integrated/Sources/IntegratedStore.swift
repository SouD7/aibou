import SwiftUI
import Combine

@MainActor
final class IntegratedStore: ObservableObject {
    let avatar: AvatarStore
    let monitor: MonitorStore
    let consultation: ConsultationModel
    @Published private(set) var session = RoomSession()
    @Published var menuExpanded = false
    @Published var presentation: RoomPanel?
    @Published var showingConnection = false
    private var subscriptions: Set<AnyCancellable> = []
    private var liveState = RoomVisualState()

    init() {
        avatar = AvatarStore()
        // Separate archives allow the original monitor and integrated app to run independently.
        let archive = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AIBOU", isDirectory: true)
        monitor = MonitorStore(directory: archive)
        consultation = ConsultationModel()
        resetPose()
        avatar.scene?.onWarningSelection = { [weak self] id in self?.acknowledgeWarning(id) }
        monitor.$panels.sink { [weak self] panels in self?.applyReadings(panels) }.store(in: &subscriptions)
        avatar.$roomVisualState.sink { [weak self] state in
            guard let self else { return }
            self.avatar.replaceComponentWarnings(self.session.visibleWarnings(HardwareRoomPolicy.warnings(for: state)))
        }.store(in: &subscriptions)
        Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] now in
            guard let self, !self.session.isConsulting, !self.session.isDemo,
                  now >= self.session.nextPoseAt, self.session.shouldChoosePose(now: now) else { return }
            self.avatar.selectedPose = HardwareRoomPolicy.avatarCandidates(for: self.avatar.roomVisualState).randomElement() ?? .standingBackHands
        }.store(in: &subscriptions)
        consultation.$signedIn.combineLatest(consultation.$connected).receive(on: RunLoop.main).sink { [weak self] signedIn, connected in
            guard let self, self.session.isConsulting, !(signedIn && connected) else { return }
            self.endConsultation()
            self.showingConnection = true
        }.store(in: &subscriptions)
    }

    private func applyReadings(_ panels: [MonitorTab: PanelReading]) {
        liveState = HardwareRoomPolicy.visualState(panels: panels, previous: liveState)
        guard !session.isDemo else { return }
        avatar.scene?.setRoomVisualState(liveState)
    }

    func acknowledgeWarning(_ id: String) {
        session.acknowledge(id)
        avatar.replaceComponentWarnings(session.visibleWarnings(avatar.componentWarnings))
    }

    func enterDemo() {
        if session.isConsulting { endConsultation() }
        avatar.selectComponent(nil)
        session.enterDemo()
        menuExpanded = false
        avatar.scene?.scaleMode = .aspectFit
    }

    func exitDemo() {
        session.leaveDemo()
        avatar.scene?.scaleMode = .aspectFit
        avatar.paused = false
        avatar.focused = false
        avatar.strength = 1
        avatar.reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        avatar.selectComponent(nil)
        avatar.scene?.setRoomVisualState(liveState)
        avatar.replaceComponentWarnings(session.visibleWarnings(HardwareRoomPolicy.warnings(for: liveState)))
        resetPose()
    }

    func beginConsultation() {
        menuExpanded = false
        guard consultation.connected && consultation.signedIn else {
            showingConnection = true
            return
        }
        avatar.selectComponent(nil)
        session.beginConsultation()
        avatar.voice.stop()
        avatar.focused = false
        avatar.paused = false
        avatar.selectedPose = .standingFrontHands
    }

    func endConsultation() {
        session.endConsultation()
        if consultation.busy { Task { await consultation.interrupt() } }
        resetPose()
    }

    func open(_ panel: RoomPanel) {
        menuExpanded = false
        avatar.selectComponent(nil)
        presentation = panel
    }

    private func resetPose() {
        avatar.voice.stop()
        avatar.selectedPose = .standingBackHands
        avatar.scene?.selectPose(.standingBackHands, animated: false)
    }
}

enum RoomPanel: Identifiable {
    case monitor, maintenance, applications, hardware(MonitorTab)
    var id: String {
        switch self {
        case .monitor: return "monitor"
        case .maintenance: return "maintenance"
        case .applications: return "applications"
        case .hardware(let tab): return tab.rawValue
        }
    }
    var title: String {
        switch self {
        case .monitor: return "モニター"
        case .maintenance: return "メンテナンス"
        case .applications: return "アプリ"
        case .hardware(let tab): return tab.title
        }
    }
    var monitorPresentation: MonitorPresentation {
        switch self {
        case .monitor: return .full
        case .maintenance: return .diagnostics
        case .applications: return .applications
        case .hardware(let tab): return .hardware(tab)
        }
    }
}
