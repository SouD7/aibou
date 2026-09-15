import Foundation
import SwiftUI
#if canImport(CircuitCore)
import CircuitCore
#endif

@MainActor
final class LessonStore: ObservableObject {
    @Published private(set) var progress = LessonProgress()
    @Published private(set) var session: LessonSession?
    @Published var area: ExhibitionAreaID = .a
    @Published private(set) var saveError = ""
    private let saveURL: URL
    private var damagedSave = false

    init(saveURL: URL? = nil) {
        let args = ProcessInfo.processInfo.arguments
        let override = args.firstIndex(of: "--lesson-save").flatMap { index -> URL? in
            index + 1 < args.count ? URL(fileURLWithPath: args[index + 1]) : nil
        }
        self.saveURL = saveURL ?? override ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/aibou-game-lab/lessons-v1.json")
        guard FileManager.default.fileExists(atPath: self.saveURL.path) else { return }
        do { progress = try LessonProgress.load(from: self.saveURL) }
        catch {
            damagedSave = true
            saveError = "授業の記録を読み込めませんでした。元の記録を別名で残してから保存します。"
        }
    }

    var lesson: LessonDefinition? { session.flatMap { LessonCatalog.lesson($0.lessonID) } }

    func open(_ id: String) {
        guard let game = ExhibitionCatalog.game(id), LessonCatalog.lesson(id) != nil else { return }
        area = game.areaID
        session = LessonSession(lessonID: id)
        progress.visit(id)
        persist()
    }
    func showLibrary() { session = nil }
    func explore() { session?.explore() }
    func answer(_ index: Int) { session?.answer(index) }
    func back() { session?.back() }
    func advance() {
        session?.advance()
        if let session, session.isComplete {
            progress.record(session)
            persist()
        }
    }
    func retrySave() { persist() }
    private func persist() {
        do {
            if damagedSave {
                let backup = saveURL.deletingLastPathComponent().appendingPathComponent("lessons-unreadable-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: saveURL, to: backup)
                damagedSave = false
            }
            try progress.save(to: saveURL)
            saveError = ""
        } catch { saveError = "授業の記録を保存できませんでした。この画面では続けられます。" }
    }
}
