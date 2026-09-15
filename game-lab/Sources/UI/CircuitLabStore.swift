import AppKit
import SwiftUI
#if canImport(CircuitCore)
import CircuitCore
#endif

@MainActor
final class CircuitLabStore: ObservableObject {
    let workshop = WorkshopStore()
    private var session: CircuitSession
    @Published private(set) var state: CircuitSnapshot
    @Published var showHint = false
    @Published var showDeveloper = false
    @Published var showsSandbox = ProcessInfo.processInfo.arguments.contains("--sandbox")
    @Published var notice = ""
    @Published var exportedDirectory: URL?
    @Published private(set) var actionMicroseconds: Double = 0

    init() {
        let initial = CircuitSession(seed: 17)
        session = initial
        state = initial.state
    }

    func act(_ action: CircuitAction) {
        do {
            let began = ProcessInfo.processInfo.systemUptime
            try session.apply(action)
            actionMicroseconds = (ProcessInfo.processInfo.systemUptime - began) * 1_000_000
            state = session.state
            notice = ""
        } catch {
            notice = "操作を実行できませんでした。\(error.localizedDescription)"
        }
    }

    var fullyConnected: Bool {
        state.selectedGate != nil && state.links.count == 3
    }

    func chooseMission(_ gate: GateKind) {
        guard gate != state.mission else { return }
        showHint = false
        act(.selectMission(gate))
    }

    func next() {
        showHint = false
        if state.mission == .xor {
            act(.selectMission(.and))
        } else {
            act(.nextMission)
        }
    }

    func exportEvidence() {
        do {
            let root = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/aibou-game-lab/Exports", isDirectory: true)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
            let directory = root.appendingPathComponent(formatter.string(from: Date()), isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let replay = session.replayDocument()
            try encoder.encode(state).write(to: directory.appendingPathComponent("state.json"), options: .atomic)
            try encoder.encode(replay).write(to: directory.appendingPathComponent("replay.json"), options: .atomic)
            exportedDirectory = directory
            notice = "状態と操作記録を書き出しました。"
        } catch {
            notice = "書き出せませんでした。\(error.localizedDescription)"
        }
    }

    func replayExport() {
        guard let directory = exportedDirectory else { return }
        do {
            let data = try Data(contentsOf: directory.appendingPathComponent("replay.json"))
            session = try CircuitSession.replay(data: data)
            state = session.state
            notice = "保存した操作を再生しました。"
        } catch {
            notice = "再生できませんでした。\(error.localizedDescription)"
        }
    }

    var canReplay: Bool { exportedDirectory != nil }
    func revealExport() {
        if let directory = exportedDirectory { NSWorkspace.shared.open(directory) }
    }
}
