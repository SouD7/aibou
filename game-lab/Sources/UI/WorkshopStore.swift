import AppKit
import SwiftUI
import AVFoundation
#if canImport(CircuitCore)
import CircuitCore
#endif

@MainActor
final class WorkshopStore: ObservableObject {
    @Published private(set) var state: WorkshopSnapshot
    @Published private(set) var dialogue: String
    @Published private(set) var isTesting = false
    @Published private(set) var testRow = 0
    @Published private(set) var saveMessage = ""
    @Published private(set) var saveError = ""
    @Published var resumePending = false
    @Published var voiceEnabled: Bool
    @Published var soundEnabled: Bool
    @Published var reducedMotion: Bool
    @Published var showPrediction = false
    @Published var showSettings = false
    @Published var showArtifact = false
    let voice = GuideVoice()
    private var session: WorkshopSession
    private var testTask: Task<Void, Never>?
    private let saveURL: URL
    private var damagedSave = false
    private var visible = false
    private var soundPlayer: AVAudioPlayer?
    private let defaults = UserDefaults.standard

    init(saveURL: URL? = nil) {
        let args = ProcessInfo.processInfo.arguments
        let override: URL? = args.firstIndex(of: "--workshop-save").flatMap { index in
            index + 1 < args.count ? URL(fileURLWithPath: args[index + 1]) : nil
        }
        self.saveURL = saveURL ?? override ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/aibou-game-lab/workshop-v1.json")
        voiceEnabled = !args.contains("--mute") && (UserDefaults.standard.object(forKey: "workshop.voice") as? Bool ?? true)
        soundEnabled = !args.contains("--mute") && (UserDefaults.standard.object(forKey: "workshop.sound") as? Bool ?? true)
        reducedMotion = UserDefaults.standard.bool(forKey: "workshop.reduceMotion")
        let fresh = WorkshopSession(seed: 17)
        session = fresh; state = fresh.state; dialogue = fresh.state.feedbackText
        if FileManager.default.fileExists(atPath: self.saveURL.path) {
            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: self.saveURL.path)
                guard (attrs[.size] as? NSNumber)?.intValue ?? 0 <= WorkshopSession.maximumReplayBytes else {
                    throw WorkshopError.documentTooLarge(WorkshopSession.maximumReplayBytes + 1)
                }
                session = try WorkshopSession.replay(data: Data(contentsOf: self.saveURL))
                state = session.state
                resumePending = state.hasStarted
                dialogue = state.feedbackText
                saveMessage = "前回の作業を読み込みました"
            } catch {
                damagedSave = true
                saveError = "前回の記録を読み込めませんでした。新しく始めるときに元の記録を別名で残します。"
            }
        }
    }

    var circuit: CircuitSnapshot { state.circuit }
    var discovered: Bool { circuit.verification == .passed || state.completedArtifact != nil }
    var mood: GuideMood {
        if isTesting { return .observing }
        if state.phase == .welcome || resumePending { return .greeting }
        if state.phase == .verified || state.phase == .finished { return .celebrate }
        if state.feedback == .hint || state.feedback == .connectionChanged { return .pointing }
        if circuit.verification == .failed { return .thinking }
        return .observing
    }

    func appear() { visible = true }
    func disappear() { visible = false; cancelTest(announce: false); voice.stop(); soundPlayer?.stop() }
    func resume() {
        resumePending = false
        say(state.phase == .finished ? "おかえり。ふたりで作ったランプ、日記に残っているよ。" : "おかえり。作りかけの回路は、このまま残してあるよ。続きから試そう。")
    }
    func restart() { resumePending = false; act(.reset) }

    func act(_ action: WorkshopAction) {
        cancelTest(announce: false)
        if case .circuit(.selectGate(let kind)) = action, circuit.selectedGate == kind { return }
        let before = state
        guard apply(action) else { return }
        switch action {
        case .circuit(.toggleInput), .circuit(.setInputs):
            playSound("switch") // Watching is quiet; input changes do not trigger a lecture.
            say(state.feedbackText, speak: false)
        case .circuit(.toggleLink):
            playSound("connect")
            if !before.circuit.isConnected && circuit.isConnected { say(state.feedbackText) }
            else if !circuit.isConnected { say("あと\(3 - circuit.links.count)本。丸い端子をつないで、合図の通り道を作ろう。", speak: false) }
        case .circuit(.selectGate):
            playSound("switch")
            say(before.circuit.selectedGate == nil ? "置けたね。A・B・ランプへ、3本の線をつないでみよう。" : "違う部品にしたね。同じ入力で比べると、働きの違いが見つかるよ。", speak: before.circuit.selectedGate == nil)
        case .hint:
            if circuit.selectedGate == nil { say("下のパーツをひとつ選んで、作業台に置いてみて。クリックでもドラッグでも大丈夫。") }
            else if !circuit.isConnected { say("丸い端子から、同じ道のもう片方の端子へつないでみよう。「つなぐ」ボタンでもできるよ。") }
            else if state.hintLevel >= 3 { say("パーツ01を試してみよう。片方だけと、両方そろったときを比べてみてね。") }
            else { say(state.feedbackText) }
        case .undo: say("ひとつ前に戻したよ。もう一度、違うやり方を試してみよう。", speak: false)
        case .finish:
            playSound("success")
            say(saveError.isEmpty ? "ふたりの準備完了ランプ、完成！日記に残したよ。またいつでも動かしてみよう。" : "ふたりの準備完了ランプ、完成！保存はまだできていないので、この画面で確認してね。")
        default: say(state.feedbackText)
        }
    }

    private func apply(_ action: WorkshopAction) -> Bool {
        do {
            try session.apply(action)
            state = session.state
            persist()
            return true
        } catch {
            say(error.localizedDescription, speak: false)
            return false
        }
    }

    func runTest() {
        guard circuit.isConnected, !isTesting else { return }
        isTesting = true; testRow = 0
        let originalInputs = circuit.inputs
        say("4通り、今の回路の光り方を順番に確かめるね。")
        testTask = Task { [weak self] in
            guard let self else { return }
            for index in 0..<4 {
                guard !Task.isCancelled else { return }
                guard self.apply(.circuit(.step)) else { self.cancelTest(announce: false); return }
                self.testRow = index + 1
                do { try await Task.sleep(nanoseconds: 850_000_000) } catch { return }
            }
            guard !Task.isCancelled else { return }
            let feedback = self.state.feedbackText
            _ = self.apply(.circuit(.setInputs(originalInputs)))
            self.isTesting = false; self.testTask = nil
            self.say(feedback)
            if self.circuit.verification == .passed { self.playSound("success") }
        }
    }

    func cancelTest(announce: Bool = true) {
        let wasTesting = isTesting
        testTask?.cancel(); testTask = nil; isTesting = false; testRow = 0
        if announce && wasTesting { say("確かめるのを止めたよ。ここまでの結果は、ノートに残してあるよ。", speak: false) }
    }

    func setVoice(_ value: Bool) {
        voiceEnabled = value; defaults.set(value, forKey: "workshop.voice")
        if !value { voice.stop() }
    }
    func setSound(_ value: Bool) { soundEnabled = value; defaults.set(value, forKey: "workshop.sound"); if !value { soundPlayer?.stop() } }
    func setReducedMotion(_ value: Bool) { reducedMotion = value; defaults.set(value, forKey: "workshop.reduceMotion") }
    func replayDialogue() { if voiceEnabled { voice.speak(dialogue) } }
    func stopSpeech() { voice.stop() }
    private func say(_ text: String, speak: Bool = true) {
        let changed = dialogue != text
        dialogue = text
        if changed { voice.stop() }
        if speak && voiceEnabled && visible { voice.speak(text) }
    }

    func retrySave() { persist() }
    private func persist() {
        do {
            let folder = saveURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if damagedSave {
                let backup = folder.appendingPathComponent("workshop-unreadable-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: saveURL, to: backup)
                damagedSave = false
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(session.replayDocument())
            guard data.count <= WorkshopSession.maximumReplayBytes else { throw WorkshopError.documentTooLarge(data.count) }
            try data.write(to: saveURL, options: .atomic)
            saveError = ""; saveMessage = "このMacに保存済み"
        } catch { saveError = "作業を保存できませんでした。\(error.localizedDescription)"; saveMessage = "未保存" }
    }

    private func playSound(_ name: String) {
        guard soundEnabled, visible, let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "WorkshopSounds") else { return }
        do { soundPlayer = try AVAudioPlayer(contentsOf: url); soundPlayer?.volume = 0.35; soundPlayer?.play() } catch { /* Sound is optional; all results are also visible. */ }
    }
}
