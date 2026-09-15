import Foundation

// Compiled with the real Core sources and UI/LessonStore.swift. The check uses
// only a disposable directory, never app preferences or the user's save files.
@main
struct CheckLessonStore {
    private static var checks = 0

    @MainActor
    private static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw CheckFailure(message: message) }
        checks += 1
        print("PASS \(message)")
    }

    private struct CheckFailure: Error { let message: String }

    @MainActor
    private static func complete(_ store: LessonStore, id: String) throws {
        guard let lesson = LessonCatalog.lesson(id) else { throw CheckFailure(message: "Missing fixture lesson") }
        store.advance()
        try check(store.session?.step == .experiment, "\(id): experiment reached")
        store.explore()
        store.advance()
        store.answer(lesson.challenge.correctIndex)
        store.advance()
        try check(store.session?.isComplete == true, "\(id): completed through experiment and correct answer")
    }

    @MainActor
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("aibou-lesson-store-check-\(UUID().uuidString)")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        for (name, fixture) in [
            ("corrupt", "{broken JSON, preserve this text"),
            ("future", #"{"version":2,"completedIDs":["memory-dock"],"lastLessonID":"memory-dock","futureField":{"keep":"exactly"}}"#)
        ] {
            let folder = root.appendingPathComponent(name)
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("lessons-v1.json")
            let original = Data(fixture.utf8)
            try original.write(to: url)

            let store = LessonStore(saveURL: url)
            try check(!store.saveError.isEmpty, "\(name): read failure is visible")
            try check(store.progress.completedIDs.isEmpty && store.session == nil, "\(name): unreadable record does not invent completion")
            try check(Data(contentsOf: url) == original, "\(name): construction does not alter source bytes")
            try check(manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).count == 1, "\(name): no backup or overwrite occurs during read")

            store.open("memory-dock")
            let backups = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("lessons-unreadable-") && $0.pathExtension == "json" }
            try check(backups.count == 1, "\(name): opening creates exactly one recovery copy")
            let backup = backups[0]
            let backupID = backup.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "lessons-unreadable-", with: "")
            try check(UUID(uuidString: backupID) != nil, "\(name): recovery copy has a unique UUID name")
            try check(Data(contentsOf: backup) == original, "\(name): recovery copy preserves all original bytes")
            try check(store.saveError.isEmpty, "\(name): successful replacement clears the error")
            try check(LessonProgress.load(from: url).lastLessonID == "memory-dock", "\(name): replacement is a readable current-version record")
            try check(LessonProgress.load(from: url).completedIDs.isEmpty, "\(name): merely opening does not save a completion")

            try complete(store, id: "memory-dock")
            store.retrySave()
            let filesAfterSave = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            try check(filesAfterSave.filter { $0.lastPathComponent.hasPrefix("lessons-unreadable-") }.count == 1, "\(name): subsequent saves do not duplicate the backup")
            try check(Data(contentsOf: backup) == original, "\(name): later completion leaves the backup intact")
            let reopened = LessonStore(saveURL: url)
            try check(reopened.saveError.isEmpty && reopened.progress.completedIDs == ["memory-dock"], "\(name): completion survives store reconstruction")
            try check(reopened.session == nil, "\(name): reloading does not auto-start or manufacture a session")
        }

        // A file in place of the parent directory is reliably unwritable as a
        // directory even on systems where broad privileges ignore mode bits.
        let blockedParent = root.appendingPathComponent("blocked-parent")
        let obstruction = Data("unrelated data must survive a failed save".utf8)
        try obstruction.write(to: blockedParent)
        let blockedURL = blockedParent.appendingPathComponent("lessons-v1.json")
        let blockedStore = LessonStore(saveURL: blockedURL)
        blockedStore.open("battery-voyage")
        try check(!blockedStore.saveError.isEmpty, "write failure: opening exposes save error")
        try check(blockedStore.session?.lessonID == "battery-voyage", "write failure: a session remains usable")
        try complete(blockedStore, id: "battery-voyage")
        try check(blockedStore.progress.completedIDs == ["battery-voyage"], "write failure: earned completion is retained in memory")
        try check(!blockedStore.saveError.isEmpty, "write failure: completion does not hide a persistent save error")
        try check(Data(contentsOf: blockedParent) == obstruction, "write failure: unrelated parent-path bytes are unchanged")

        // Simulate an external repair, then use the same retry path as the UI.
        try manager.removeItem(at: blockedParent)
        blockedStore.retrySave()
        try check(blockedStore.saveError.isEmpty, "recovery: retry clears the error after destination repair")
        let recovered = LessonStore(saveURL: blockedURL)
        try check(recovered.progress.completedIDs == ["battery-voyage"], "recovery: in-memory completion is persisted on retry")
        try check(recovered.progress.lastLessonID == "battery-voyage", "recovery: last lesson also survives reload")
        try check(recovered.session == nil, "recovery: a persisted completion does not auto-start a lesson")

        print("LessonStore checks passed: \(checks); all fixtures were isolated under \(root.lastPathComponent) and removed.")
    }
}
