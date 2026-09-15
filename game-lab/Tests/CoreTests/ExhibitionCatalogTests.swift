import XCTest
@testable import CircuitCore

final class ExhibitionCatalogTests: XCTestCase {
    private func temporarySave() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aibou-exhibition-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("museum/visits.json")
    }

    func testAllTwentyLearningThemesHaveOneEntranceAcrossFiveAreas() {
        XCTAssertEqual(ExhibitionCatalog.areas.map(\.id), ExhibitionAreaID.allCases)
        XCTAssertEqual(Set(ExhibitionCatalog.areas.map(\.colorName)).count, 5)
        XCTAssertEqual(ExhibitionCatalog.games.count, 20)
        XCTAssertEqual(Set(ExhibitionCatalog.games.map(\.id)).count, 20)
        XCTAssertEqual(Set(ExhibitionCatalog.games.map(\.themeID)), Set((1...20).map { String(format: "H%02d", $0) }))
        for area in ExhibitionAreaID.allCases {
            XCTAssertEqual(ExhibitionCatalog.games(in: area).count, 4)
            XCTAssertEqual(ExhibitionCatalog.area(area).id, area)
        }
        for game in ExhibitionCatalog.games {
            XCTAssertFalse(game.learningDescription.isEmpty)
            XCTAssertFalse(game.guideInvitation.isEmpty)
            XCTAssertFalse(game.icon.isEmpty)
        }
    }

    func testAllImplementedExperiencesCanBePresentedAsPlayable() throws {
        XCTAssertEqual(ExhibitionCatalog.games.filter(\.isPlayable).count, 20)
        let atelier = try XCTUnwrap(ExhibitionCatalog.game(ExhibitionCatalog.circuitGameID))
        XCTAssertEqual(atelier.areaID, .a)
        XCTAssertEqual(atelier.themeID, "H03")
        XCTAssertEqual(atelier.title, "論理回路")
        XCTAssertNil(ExhibitionCatalog.game("made-up-exhibition"))
    }

    func testVisitCannotBecomeLearningCompletion() throws {
        let atelier = try XCTUnwrap(ExhibitionCatalog.game(ExhibitionCatalog.circuitGameID))
        var session = WorkshopSession()
        XCTAssertEqual(ExhibitionGameStatus.resolve(game: atelier, visited: false, workshop: session.state), .unvisited)
        XCTAssertEqual(ExhibitionGameStatus.resolve(game: atelier, visited: true, workshop: session.state), .visited)
        try session.apply(.begin)
        XCTAssertEqual(ExhibitionGameStatus.resolve(game: atelier, visited: false, workshop: session.state), .inProgress)
        try session.apply(.circuit(.selectGate(.and)))
        for link in CircuitLink.allCases { try session.apply(.circuit(.toggleLink(link))) }
        for _ in 0..<4 { try session.apply(.circuit(.step)) }
        XCTAssertEqual(session.state.phase, .verified)
        XCTAssertEqual(ExhibitionGameStatus.resolve(game: atelier, visited: true, workshop: session.state), .inProgress,
                       "A passed test without a saved work must not advertise a work in the collection.")
        try session.apply(.finish)
        XCTAssertEqual(ExhibitionGameStatus.resolve(game: atelier, visited: true, workshop: session.state), .completed)
        try session.apply(.reset)
        XCTAssertEqual(ExhibitionGameStatus.resolve(game: atelier, visited: true, workshop: session.state), .completed,
                       "Starting a new experiment does not remove an existing completed work.")
        for game in ExhibitionCatalog.games where !game.isPlayable {
            XCTAssertEqual(ExhibitionGameStatus.resolve(game: game, visited: true, workshop: session.state), .preparing)
        }
    }

    func testVisitsAreDeduplicatedAndUnknownGamesDoNotMoveTheVisitor() {
        var progress = ExhibitionProgress()
        progress.visit("memory-dock")
        progress.visit("memory-dock")
        XCTAssertEqual(progress.visitedGameIDs, ["memory-dock"])
        XCTAssertEqual(progress.lastAreaID, .c)
        let before = progress
        progress.visit("unknown")
        XCTAssertEqual(progress, before)
        progress.navigate(to: nil)
        XCTAssertNil(progress.lastAreaID)
        XCTAssertEqual(progress.visitedGameIDs, ["memory-dock"])
    }

    func testSavingAndReplacingProgressRestoresLastAreaWithoutAPlayingRoute() throws {
        let url = try temporarySave()
        var progress = ExhibitionProgress()
        progress.visit(ExhibitionCatalog.circuitGameID)
        try progress.save(to: url)
        XCTAssertEqual(try ExhibitionProgress.load(from: url), progress)
        progress.visit("cooling-workshop")
        try progress.save(to: url)
        let restored = try ExhibitionProgress.load(from: url)
        XCTAssertEqual(restored.lastAreaID, .e)
        XCTAssertEqual(restored.visitedGameIDs, [ExhibitionCatalog.circuitGameID, "cooling-workshop"])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertNil(object["completedGameIDs"])
        XCTAssertNil(object["playing"])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
    }

    func testRestoringOldIdentifiersKeepsKnownVisitsAndReturnsUnknownAreaToLobby() throws {
        let data = Data(#"{"schemaVersion":1,"visitedGameIDs":["bit-art","removed-game","bit-art"],"lastAreaID":"removed-area"}"#.utf8)
        let progress = try JSONDecoder().decode(ExhibitionProgress.self, from: data)
        XCTAssertEqual(progress.visitedGameIDs, ["bit-art"])
        XCTAssertNil(progress.lastAreaID)
    }

    func testInvalidOrFutureProgressNeverSilentlyLoadsAsCurrentVersion() throws {
        let future = Data(#"{"schemaVersion":2,"visitedGameIDs":[],"lastAreaID":"a"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ExhibitionProgress.self, from: future)) {
            XCTAssertEqual($0 as? ExhibitionSaveError, .unsupportedVersion(2))
        }
        let bad = Data(#"{"schemaVersion":1,"visitedGameIDs":"circuit-atelier"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ExhibitionProgress.self, from: bad))
    }

    func testOversizedProgressIsRejectedBeforeDecoding() throws {
        let url = try temporarySave()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 32, count: ExhibitionProgress.maximumBytes + 1).write(to: url)
        XCTAssertThrowsError(try ExhibitionProgress.load(from: url)) {
            XCTAssertEqual($0 as? ExhibitionSaveError, .tooLarge)
        }
    }
}
