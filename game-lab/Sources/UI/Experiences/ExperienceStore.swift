import Foundation
import SwiftUI
#if canImport(CircuitCore)
import CircuitCore
#endif

@MainActor
final class ExperienceStore<M: ExperienceModel>: ObservableObject {
    @Published private(set) var record: ExperienceRecord<M>
    @Published private(set) var saveError = ""
    @Published private(set) var message = ""
    @Published var hintLevel = 0 {
        didSet {
            if hintLevel > (record.hintLevels?[String(model.stage)] ?? 0) {
                if record.hintLevels == nil { record.hintLevels = [:] }
                record.hintLevels?[String(model.stage)] = hintLevel
                persist()
            }
        }
    }
    private let saveURL: URL?
    private var unreadable = false
    var model: M { record.model }
    var canUndo: Bool { !record.undo.isEmpty }
    var artifacts: [ExperienceArtifact<M>] { record.artifacts }
    var comparisons: [M] { record.comparisons }
    var completedStages: Set<Int> { record.completedStages }
    var blockedSave: Bool { unreadable }
    var reflections: [ExperienceReflection<M>] { record.reflections ?? [] }
    var pendingReflection: ExperienceReflection<M>? { reflections.last.flatMap { $0.after == nil ? $0 : nil } }

    init(_ model: M, saveURL: URL? = nil, inMemory: Bool = false) {
        record = ExperienceRecord(model: model)
        let args = ProcessInfo.processInfo.arguments
        let directory = args.firstIndex(of: "--experience-save-dir").flatMap { i in i + 1 < args.count ? URL(fileURLWithPath: args[i+1]) : nil }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/aibou-game-lab/experiences")
        self.saveURL = inMemory ? nil : (saveURL ?? directory.appendingPathComponent(M.gameID + "-v1.json"))
        if let url = self.saveURL, FileManager.default.fileExists(atPath: url.path) {
            do {
                let loaded = try JSONDecoder().decode(ExperienceRecord<M>.self, from: Data(contentsOf: url))
                guard loaded.isValid else { throw CocoaError(.coderReadCorrupt) }
                record = loaded; message = "前の作業を再開しました"
            } catch {
                unreadable = true
                saveError = "前の記録を読み込めません。元の記録は保持しています。"
            }
        }
    }
    func send(_ action: M.Action) {
        let old = model
        var next = old; next.send(action)
        guard next != old, next.isValid else { return }
        record.undo.append(old); record.undo = Array(record.undo.suffix(100))
        record.model = next
        record.actions.append(String(describing: action)); record.actions = Array(record.actions.suffix(1000))
        message = ""; persist()
    }
    func undo() {
        guard let old = record.undo.popLast() else { return }
        record.model = old; message = "一手戻しました"; persist()
    }
    func restart() { selectStage(model.stage) }
    func selectStage(_ stage: Int) {
        guard (1...5).contains(stage) else { return }
        record.model = M(stage: stage); record.undo = []; record.actions = []
        hintLevel = 0; message = "新しい試行を始めました"; persist()
    }
    func rememberComparison() {
        guard record.comparisons.last != model else { message = "この状態は観察ノートにあります"; return }
        record.comparisons.append(model); record.comparisons = Array(record.comparisons.suffix(10))
        persist(); if saveError.isEmpty { message = "条件と観察をノートに残しました" }
    }
    @discardableResult func saveArtifact() -> Bool {
        guard model.isComplete else { return false }
        if !record.artifacts.contains(where: { $0.model == model }) {
            record.artifacts.append(ExperienceArtifact(model: model))
            record.artifacts = Array(record.artifacts.suffix(50))
        }
        record.completedStages.insert(model.stage)
        record.undo = []
        persist()
        if saveError.isEmpty { message = "日記に保存しました"; return true }
        return false
    }
    func next() { if saveArtifact(), model.stage < 5 { selectStage(model.stage + 1) } }
    func retrySave() { persist() }
    func predict(_ text: String, reason: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var items = reflections
        items.append(ExperienceReflection(before: model, prediction: String(text.prefix(2000)), reason: String(reason.prefix(2000))))
        record.reflections = Array(items.suffix(50)); persist()
        if saveError.isEmpty { message = "予想を残しました。条件を変えて確かめよう" }
    }
    func recordDiscovery(_ text: String) {
        guard var items = record.reflections, let index = items.indices.last, items[index].after == nil else { return }
        items[index].after = model; items[index].discovery = String(text.prefix(2000))
        record.reflections = items; persist()
        if saveError.isEmpty { message = "予想と結果を別々に残しました" }
    }
    func preserveUnreadableAndStart() {
        guard unreadable, let url = saveURL else { return }
        do {
            let backup = url.deletingLastPathComponent().appendingPathComponent(M.gameID + "-unreadable-" + UUID().uuidString + ".json")
            try FileManager.default.copyItem(at: url, to: backup)
            unreadable = false; persist()
        } catch { saveError = "元の記録を別名で保持できませんでした。保存は停止しています。" }
    }
    private func persist() {
        guard !unreadable, let url = saveURL else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(record).write(to: url, options: .atomic)
            saveError = ""
        } catch { saveError = "保存できませんでした。作業は画面に残っています。" }
    }
}
