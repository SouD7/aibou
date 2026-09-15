import Foundation

/// Compile with Core/*.swift and UI/ExhibitionStore.swift; no app or desktop access required.
@main
@MainActor
struct ExhibitionStoreChecks {
    private struct CheckFailure: Error { let description: String }
    private static var count = 0

    private static func check(_ condition: @autoclosure () -> Bool, _ description: String) throws {
        guard condition() else { throw CheckFailure(description: description) }
        count += 1
    }

    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aibou-exhibition-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("visits.json")
        let store = ExhibitionStore(saveURL: url)
        try check(store.route == .lobby, "A first visit starts in the lobby")
        store.visitArea(.d)
        try check(store.route == .area(.d), "Area navigation has a real destination")
        store.openGame("connection-lab")
        try check(store.route == .entry("connection-lab"), "A playable exhibit has an entry")
        try check(store.visitedGameIDs == ["connection-lab"], "Opening an exhibit records only a visit")
        try check(store.startGame("connection-lab"), "The connection experience can start")
        try check(store.route == .playing("connection-lab"), "A successful start shows the selected game")
        store.goBack()
        try check(store.route == .area(.d), "Entry back returns to its own area")
        store.openGame("unknown-game")
        try check(store.route == .area(.d), "Unknown links do not corrupt navigation")
        store.goBack()
        try check(store.route == .lobby, "Area back returns to the lobby")
        try check(store.startGame(ExhibitionCatalog.circuitGameID), "The implemented circuit can start")
        try check(store.route == .playing(ExhibitionCatalog.circuitGameID), "A successful start presents the game")
        let resumed = ExhibitionStore(saveURL: url)
        try check(resumed.route == .area(.a), "Relaunch restores the room without auto-starting the game")
        try check(resumed.visitedGameIDs == ["connection-lab", ExhibitionCatalog.circuitGameID], "Visits survive relaunch")
        store.goBack()
        try check(store.route == .area(.a), "Game back returns directly to its own area")
        store.goToLobby()
        try check(ExhibitionStore(saveURL: url).route == .lobby, "An explicit lobby return is persisted")

        let invalidURL = directory.appendingPathComponent("future.json")
        let invalidData = Data(#"{"schemaVersion":9,"visitedGameIDs":[]}"#.utf8)
        try invalidData.write(to: invalidURL)
        let invalidStore = ExhibitionStore(saveURL: invalidURL)
        try check(!invalidStore.saveError.isEmpty, "Unreadable progress is disclosed")
        let originalBeforeAction = try Data(contentsOf: invalidURL)
        try check(originalBeforeAction == invalidData, "Loading an unreadable file never overwrites it")
        invalidStore.visitArea(.c)
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("exhibition-unreadable-") }
        try check(backups.count == 1, "The original is backed up before replacement")
        let backupData = try Data(contentsOf: backups[0])
        try check(backupData == invalidData, "The backup preserves the original bytes")
        try check(invalidStore.saveError.isEmpty, "Successful recovery clears the error")
        try check(ExhibitionStore(saveURL: invalidURL).route == .area(.c), "Recovered progress can be reloaded")

        let blockedURL = directory.appendingPathComponent("directory-instead-of-file")
        try FileManager.default.createDirectory(at: blockedURL, withIntermediateDirectories: true)
        let blockedStore = ExhibitionStore(saveURL: blockedURL)
        blockedStore.visitArea(.e)
        try check(!blockedStore.saveError.isEmpty, "Write failure remains visible")
        try check(blockedStore.route == .area(.e), "Write failure does not prevent current-session navigation")
        print("ExhibitionStore: \(count) checks passed")
    }
}
