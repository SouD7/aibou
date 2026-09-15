import XCTest

/// Uses public accessibility controls only; no model commands or debug-state mutation.
@MainActor
final class GameLabUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "local.aibou.gamelab")
        if app.state != .notRunning {
            app.terminate()
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 5), "Previous app process did not terminate")
        }
        app.launchArguments = ["--sandbox", "--mute"]
        app.launch()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5), "The app did not become foreground after launch")
        app.revealGameWindowOnceIfNeeded()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15), "Game Lab window did not open")
        control("stage.0").click()
        control("game.reset").click()
    }

    override func tearDownWithError() throws {
        if let app {
            if app.windows.firstMatch.exists {
                let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
                screenshot.name = name
                screenshot.lifetime = .keepAlways
                add(screenshot)
            }
            app.terminate()
        }
        app = nil
    }

    func testIncorrectGateDoesNotPassThenANDPasses() {
        assemble(gate: "gate.or")
        control("game.check").click()
        XCTAssertTrue(element("game.failure").waitForExistence(timeout: 8), "Expected a visible counterexample after testing the wrong gate")
        XCTAssertFalse(element("game.success").exists, "OR must not solve the AND challenge")

        control("game.reset").click()
        assemble(gate: "gate.and")
        control("game.check").click()
        XCTAssertTrue(element("game.success").waitForExistence(timeout: 8))
    }

    func testDisconnectedCircuitDoesNotPass() {
        control("gate.and").click()
        let check = app.buttons["game.check"]
        let step = app.buttons["game.step"]
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        XCTAssertTrue(step.exists)
        XCTAssertFalse(check.isEnabled, "Full verification must wait for a complete circuit")
        XCTAssertFalse(step.isEnabled, "Single-step verification must wait for a complete circuit")
        XCTAssertFalse(element("game.success").exists, "A gate without connections must not solve the challenge")
    }

    func testResetAllowsFreshSolution() {
        assemble(gate: "gate.xor")
        control("input.a").click()
        control("game.step").click()
        control("game.reset").click()
        assemble(gate: "gate.and")
        control("game.check").click()
        XCTAssertTrue(element("game.success").waitForExistence(timeout: 8))
    }

    func testNativeDragPlacesGateInSlot() {
        let gate = control("gate.or")
        let slot = control("gate.slot")
        gate.click(forDuration: 0.8, thenDragTo: slot)
        let placed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "OR", "OR"), object: slot)
        XCTAssertEqual(XCTWaiter.wait(for: [placed], timeout: 5), .completed, "Dragging OR into the slot must place the gate")
    }

    func testResetKeepsORMission() {
        control("stage.1").click()
        assemble(gate: "gate.xor")
        control("input.a").click()
        control("game.reset").click()
        XCTAssertFalse(element("game.check").isEnabled, "Reset must clear the circuit")
        assemble(gate: "gate.or")
        control("game.check").click()
        XCTAssertTrue(element("game.success").waitForExistence(timeout: 8), "Reset must keep the OR mission rather than return to AND")
    }

    func testIncorrectOptionalPredictionDoesNotBlockNextMission() {
        assemble(gate: "gate.and")
        control("game.check").click()
        XCTAssertTrue(element("game.success").waitForExistence(timeout: 8))
        control("prediction.open").click()
        control("prediction.one").click()
        let feedback = element("prediction.feedback")
        XCTAssertTrue(feedback.waitForExistence(timeout: 5))
        let wrongAnswerFeedback = app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "今回は消灯（0）", "今回は消灯（0）")).firstMatch
        XCTAssertTrue(wrongAnswerFeedback.exists, "The initial AND transfer question should explain this wrong answer")
        attachWindowScreenshot("prediction-wrong-answer")
        let close = app.buttons["予想を閉じる"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.click()
        control("game.next").click()
        assemble(gate: "gate.or")
        control("game.check").click()
        XCTAssertTrue(element("game.success").waitForExistence(timeout: 8), "An incorrect optional prediction must still allow the OR mission")
    }

    func testExportResetReplayRestoresCircuitAndLamp() {
        assemble(gate: "gate.and")
        control("game.check").click()
        XCTAssertTrue(element("game.success").waitForExistence(timeout: 8))
        for id in ["input.a", "input.b"] {
            let input = control(id)
            if input.label.contains("0 OFF") { input.click() }
        }
        let litLamp = accessibleText(element("game.lamp"))
        XCTAssertTrue(litLamp.contains("1 点灯"), "Expected a lit lamp. \(element("game.lamp").debugDescription)")

        control("game.developer").click()
        attachWindowScreenshot("developer-auto-scroll")
        let exhibit = app.scrollViews.firstMatch
        XCTAssertTrue(exhibit.exists)
        exhibit.scroll(byDeltaX: 0, deltaY: -350)
        control("game.export").click()
        XCTAssertTrue(element("game.replay").isEnabled)
        XCTAssertTrue(element("game.hint").isHittable, "Header must stay visible while inspecting the developer panel")
        XCTAssertTrue(element("game.developer").isHittable, "Footer must stay visible while inspecting the developer panel")
        attachWindowScreenshot("export-file-created")
        control("game.reset").click()
        XCTAssertFalse(element("game.success").exists)
        XCTAssertTrue(accessibleText(element("game.lamp")).contains("未接続"))
        control("game.replay").click()
        XCTAssertTrue(element("game.success").waitForExistence(timeout: 8), "Replaying the saved file must restore successful verification")
        XCTAssertEqual(accessibleText(element("game.lamp")), litLamp, "Replay must restore the observed lamp state")
    }

    private func assemble(gate: String) {
        control(gate).click()
        control("link.a").click()
        control("link.b").click()
        control("link.output").click()
    }

    private func control(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        if app.state != .runningForeground { app.activate() }
        let element = element(identifier)
        XCTAssertTrue(element.exists || element.waitForExistence(timeout: 5), "Missing accessibility identifier: \(identifier)", file: file, line: line)
        // XCUIElement.click() scrolls an offscreen control into view. Checking
        // isHittable before the click would prevent that native scroll behavior.
        return element
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func accessibleText(_ element: XCUIElement) -> String {
        [element.label, element.value as? String ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func attachWindowScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Exercises the introductory exhibit through player-facing controls and an isolated save.
/// The save path changes per test; no test reads or mutates the player's real progress.
@MainActor
final class WorkshopUITests: XCTestCase {
    private var app: XCUIApplication!
    private var saveURL: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        saveURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("aibou-workshop-\(UUID().uuidString).json")
        app = XCUIApplication(bundleIdentifier: "local.aibou.gamelab")
        if app.state != .notRunning {
            app.terminate()
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 5), "Previous app process did not terminate")
        }
        app.launchArguments = ["--workshop", "--workshop-save", saveURL.path, "--mute"]
        app.launch()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5), "The app did not become foreground after launch")
        app.revealGameWindowOnceIfNeeded()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
    }

    override func tearDownWithError() throws {
        if let app {
            if app.windows.firstMatch.exists { attachWindowScreenshot(name) }
            app.terminate()
        }
        if let saveURL, FileManager.default.fileExists(atPath: saveURL.path) {
            try FileManager.default.removeItem(at: saveURL)
        }
        app = nil
        saveURL = nil
    }

    func testWorkbenchStaysFixedWhenShowingInstructionsAndResults() {
        begin()
        XCTAssertEqual(app.scrollViews.count, 0, "The playable workbench must have no scroll container")
        assemble("and")
        let slotFrame = element("w.slot").frame
        let paletteFrame = element("w.gate.and").frame
        XCTAssertTrue(app.windows.firstMatch.frame.contains(paletteFrame))
        XCTAssertTrue(element("w.undo").isHittable)
        control("w.instructions").click()
        XCTAssertTrue(element("w.panel.close").waitForExistence(timeout: 5))
        control("w.panel.close").click()
        XCTAssertEqual(element("w.slot").frame, slotFrame)
        XCTAssertEqual(element("w.gate.and").frame, paletteFrame)
        verifySuccess()
        XCTAssertTrue(element("w.panel.close").exists)
        control("w.panel.close").click()
        XCTAssertEqual(app.scrollViews.count, 0)
        XCTAssertEqual(element("w.slot").frame, slotFrame)
        XCTAssertEqual(element("w.gate.and").frame, paletteFrame)
        control("w.results").click()
        control("w.finish").click()
        waitForText("w.phase", contains: "finished")
        XCTAssertFalse(element("w.panel.close").exists)
        XCTAssertEqual(element("w.slot").frame, slotFrame)
        attachWindowScreenshot("workshop-fixed-board-after-completion")
    }

    func testIntroductionRequiresStartAndUnknownOutputCannotBeTested() {
        waitForText("w.phase", contains: "welcome")
        XCTAssertTrue(element("workshop.begin").exists)
        XCTAssertFalse(element("workshop.resume").exists)
        attachWindowScreenshot("workshop-welcome-avatar")
        begin()
        control("w.gate.and").click()
        waitForText("w.slot", contains: "パーツ01")
        XCTAssertFalse(accessibleText(element("w.gate.and")).contains("AND"), "The first encounter should invite exploration before revealing the definition")
        XCTAssertFalse(control("w.test").isEnabled)
        waitForText("w.lamp", contains: "未接続")
    }

    func testWrongORProducesCounterexampleAndCannotFinish() {
        begin()
        assemble("or")
        control("w.test").click()
        XCTAssertTrue(element("w.failure").waitForExistence(timeout: 12))
        waitForText("w.phase", contains: "observing")
        XCTAssertFalse(element("w.success").exists)
        if element("w.finish").exists { XCTAssertFalse(element("w.finish").isEnabled) }
        control("w.counterexample").click()
        waitForText("w.input.a", contains: "0 OFF")
        waitForText("w.input.b", contains: "1 ON")
        waitForText("w.lamp", contains: "1")
        attachWindowScreenshot("workshop-wrong-gate-counterexample")
    }

    func testUndoRestoresPreviousGateAndItsOutput() {
        begin()
        assemble("and")
        control("w.input.a").click()
        waitForText("w.lamp", contains: "0")
        control("w.observe").click()
        control("w.gate.or").click()
        waitForText("w.lamp", contains: "1")
        waitForText("w.slot", contains: "パーツ02")
        control("w.undo").click()
        waitForText("w.slot", contains: "パーツ01")
        waitForText("w.lamp", contains: "0")
        attachWindowScreenshot("workshop-undo-restores-behavior")
    }

    func testCompanionSwitchChangesOnlyWhenRequested() {
        begin()
        assemble("and")
        control("w.input.a").click()
        waitForText("w.lamp", contains: "0")
        control("w.askB").click()
        waitForText("w.lamp", contains: "1")
        control("w.askB").click()
        waitForText("w.lamp", contains: "0")
        control("w.input.b").click()
        waitForText("w.lamp", contains: "1")
        attachWindowScreenshot("workshop-companion-collaboration")
    }

    func testStoppingVerificationAllowsEditingWithoutStaleSuccess() {
        begin()
        assemble("and")
        control("w.test").click()
        control("w.stopTest").click()
        control("w.gate.or").click()
        XCTAssertFalse(element("w.success").exists)
        control("w.test").click()
        XCTAssertTrue(element("w.failure").waitForExistence(timeout: 12))
        waitForText("w.phase", contains: "observing")
        XCTAssertFalse(element("w.success").exists, "A cancelled previous AND test must not report success over the new OR circuit")
    }

    func testRelaunchResumesSavedCircuitAndInputState() {
        begin()
        assemble("or")
        control("w.input.a").click()
        control("w.observe").click()
        waitForText("w.lamp", contains: "1")
        waitForText("w.saveStatus", contains: "保存済み")
        let slot = accessibleText(element("w.slot"))
        let lamp = accessibleText(element("w.lamp"))
        app.terminate()
        app.launch()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5), "The app did not become foreground after launch")
        app.revealGameWindowOnceIfNeeded()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(element("workshop.resume").waitForExistence(timeout: 8))
        attachWindowScreenshot("workshop-resume-offer")
        control("workshop.resume").click()
        waitForText("w.phase", contains: "observing")
        XCTAssertEqual(accessibleText(element("w.slot")), slot)
        XCTAssertEqual(accessibleText(element("w.lamp")), lamp)
        XCTAssertTrue(control("w.test").isEnabled)
        attachWindowScreenshot("workshop-resumed-board")
    }

    func testWrongOptionalPredictionStillAllowsCompletedWork() {
        begin()
        assemble("and")
        verifySuccess()
        control("w.prediction").click()
        control("w.predict.1").click() // Seed 17 asks AND(1, 0), whose result is 0.
        XCTAssertTrue(element("w.prediction.feedback").waitForExistence(timeout: 5))
        let explanation = app.staticTexts.matching(NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "今回は", "今回は")).firstMatch
        XCTAssertTrue(explanation.exists, "A wrong prediction should be explained before the player continues")
        attachWindowScreenshot("workshop-wrong-prediction-explanation")
        control("w.prediction.observe").click()
        waitForText("w.input.a", contains: "1 ON")
        waitForText("w.input.b", contains: "0 OFF")
        waitForText("w.lamp", contains: "0")
        control("w.results").click()
        control("w.finish").click()
        waitForText("w.phase", contains: "finished")
        waitForText("w.saveStatus", contains: "保存済み")
        XCTAssertTrue(control("w.artifact").isEnabled)
        attachWindowScreenshot("workshop-completed-with-optional-error")
    }

    func testRestartKeepsCompletedWorkAvailable() {
        begin()
        assemble("and")
        verifySuccess()
        control("w.finish").click()
        waitForText("w.phase", contains: "finished")
        control("w.restart").click()
        let confirm = app.sheets.buttons.matching(identifier: "最初から作る").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Restart must present the concrete confirmation")
        confirm.click()
        waitForText("w.phase", contains: "building")
        waitForText("w.lamp", contains: "未接続")
        control("w.artifact").click()
        XCTAssertTrue(element("w.artifact.close").waitForExistence(timeout: 5))
        attachWindowScreenshot("workshop-workbook-survives-restart")
        control("w.artifact.close").click()
        waitForText("w.phase", contains: "building")
    }

    func testNativeWireDragConnectsTheTwoATerminals() {
        begin()
        control("w.gate.and").click()
        let start = control("w.port.a.start")
        let end = control("w.port.a.end")
        start.click(forDuration: 0.5, thenDragTo: end)
        control("w.link.b").click()
        control("w.link.output").click()
        waitForText("w.lamp", contains: "0")
        XCTAssertTrue(control("w.test").isEnabled, "Dragging A's terminal must supply the third complete connection")
        attachWindowScreenshot("workshop-native-wire-drag")
    }

    private func begin() {
        control("workshop.begin").click()
        waitForText("w.phase", contains: "building")
    }

    private func assemble(_ gate: String) {
        control("w.gate.\(gate)").click()
        for link in ["a", "b", "output"] { control("w.link.\(link)").click() }
        waitForText("w.phase", contains: "observing")
    }

    private func verifySuccess() {
        control("w.test").click()
        XCTAssertTrue(element("w.success").waitForExistence(timeout: 12))
        waitForText("w.phase", contains: "verified")
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func control(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        if app.state != .runningForeground { app.activate() }
        let target = element(identifier)
        XCTAssertTrue(target.exists || target.waitForExistence(timeout: 5), "Missing accessibility identifier: \(identifier)", file: file, line: line)
        // A presented sheet can exist before its opening animation becomes hittable.
        // Wait for that transition before considering a scroll, and never scroll the
        // obscured exhibition underneath a modal sheet.
        if !target.isHittable {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: target)
            _ = XCTWaiter.wait(for: [ready], timeout: 2)
        }
        if !target.isHittable,
           let scroll = app.scrollViews.allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) {
            for _ in 0..<8 where !target.isHittable { scroll.scroll(byDeltaX: 0, deltaY: -220) }
            for _ in 0..<8 where !target.isHittable { scroll.scroll(byDeltaX: 0, deltaY: 220) }
        }
        if !target.isHittable {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: target)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed,
                           "Control exists but cannot be operated: \(identifier)", file: file, line: line)
        }
        return target
    }

    private func accessibleText(_ target: XCUIElement) -> String {
        [target.label, target.value as? String ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func waitForText(_ identifier: String, contains text: String, timeout: TimeInterval = 8,
                             file: StaticString = #filePath, line: UInt = #line) {
        let target = element(identifier)
        XCTAssertTrue(target.exists || target.waitForExistence(timeout: timeout), "Missing \(identifier)", file: file, line: line)
        let phaseNames = ["welcome": "はじめる前", "building": "作る", "observing": "観察する", "verified": "できあがり", "finished": "作品完成"]
        let expectedText = identifier == "w.phase" ? phaseNames[text, default: text] : text
        let predicate = NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", expectedText, expectedText)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: target)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed,
                       "Expected \(identifier) to contain \(text), got \(accessibleText(target))", file: file, line: line)
    }

    private func attachWindowScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}


/// Museum navigation uses the same public controls as a player. Both save files
/// are isolated per test; existing completed work is never used as a fixture.
@MainActor
final class ExhibitionUITests: XCTestCase {
    private var app: XCUIApplication!
    private var saveDirectory: URL!
    private let rooms: [(String, [String])] = [
        ("a", ["bit-art", "circuit-atelier", "memory-switch", "tiny-switch-workshop"]),
        ("b", ["instruction-atelier", "work-dispatch", "parallel-factory", "pixel-factory"]),
        ("c", ["memory-dock", "cache-delivery", "memory-rescue", "storage-warehouse"]),
        ("d", ["display-studio", "packet-express", "board-town", "connection-lab"]),
        ("e", ["pc-day", "battery-voyage", "cooling-workshop", "bottleneck-detective"])
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
        saveDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aibou-exhibition-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
        app = XCUIApplication(bundleIdentifier: "local.aibou.gamelab")
        if app.state != .notRunning {
            app.terminate()
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        }
        app.launchArguments = ["--exhibition-save", saveDirectory.appendingPathComponent("exhibition.json").path,
                               "--workshop-save", saveDirectory.appendingPathComponent("workshop.json").path,
                               "--lesson-save", saveDirectory.appendingPathComponent("lessons.json").path,
                               "--experience-save-dir", saveDirectory.appendingPathComponent("experiences", isDirectory: true).path,
                               "--mute"]
        launchAndReveal()
    }

    override func tearDownWithError() throws {
        if let app {
            if app.windows.firstMatch.exists { attachWindowScreenshot(name) }
            app.terminate()
        }
        if let saveDirectory, FileManager.default.fileExists(atPath: saveDirectory.path) {
            try FileManager.default.removeItem(at: saveDirectory)
        }
        app = nil
        saveDirectory = nil
    }

    func testFiveRoomsHaveFourEntrancesAndMapHasAllTwenty() {
        for (room, games) in rooms {
            control("ex.area.\(room)").click()
            for game in games {
                XCTAssertTrue(control("ex.game.\(game)").isHittable,
                              "Each exhibit must have an operable entrance in room \(room)")
            }
            XCTAssertEqual(gameButtons.count, 4, "A room must expose precisely its four exhibits")
            XCTAssertEqual(app.scrollViews.count, 0, "Exhibits should stay fixed under wheel input")
            attachWindowScreenshot("exhibition-room-\(room)")
            control("ex.back").click()
        }
        control("ex.map").click()
        XCTAssertTrue(control("ex.map.close").isHittable)
        let identifiers = gameButtons.allElementsBoundByIndex.map(\.identifier)
        XCTAssertEqual(Set(identifiers), Set(rooms.flatMap(\.1).map { "ex.game.\($0)" }),
                       "The map must contain all twenty distinct named entrances")
        XCTAssertEqual(identifiers.count, 20)
        attachWindowScreenshot("exhibition-map-twenty-entrances")
    }

    func testAllTwentyGamesStartAndReturnToTheirRoomWithoutLabControls() {
        var startedGames = Set<String>()
        for (room, games) in rooms {
            control("ex.area.\(room)").click()
            for game in games {
                control("ex.game.\(game)").click()
                control("ex.entry.start").click()
                let exit = control("experience.exit")
                XCTAssertTrue(exit.isHittable, "The current experience must start for \(game)")
                XCTAssertFalse(element("ex.entry.start").exists, "Starting \(game) must leave its entry screen")
                XCTAssertFalse(element("ex.lab").exists, "\(game) must have no lab destination")
                XCTAssertFalse(element("lesson.lab").exists, "\(game) must have no lesson-to-lab control")
                XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "ラボで見る")).firstMatch.exists,
                               "\(game) must have no external lab action")
                exit.click()
                XCTAssertTrue(control("ex.game.\(game)").isHittable,
                              "Leaving \(game) must return to its exhibition room")
                XCTAssertEqual(Set(gameButtons.allElementsBoundByIndex.map(\.identifier)),
                               Set(games.map { "ex.game.\($0)" }),
                               "Leaving \(game) must restore exactly room \(room)'s four entrances")
                XCTAssertFalse(element("experience.exit").exists)
                startedGames.insert(game)
            }
            control("ex.back").click()
        }
        XCTAssertEqual(startedGames.count, 20)
    }

    func testAllLessonsCanBeChosenInAnyOrderBeforeCompleting() {
        control("ex.lessons").click()
        var visited = Set<String>()
        for (area, lessons) in rooms.reversed() {
            for id in lessons.reversed() {
                control("lesson.area.\(area)").click()
                control("lesson.open.\(id)").click()
                control("lesson.next").click()
                XCTAssertFalse(control("lesson.next").isEnabled)
                XCTAssertTrue(control("lesson.all").isEnabled)
                if visited.count.isMultiple(of: 2) {
                    control("lesson.all").click()
                } else {
                    control("ex.lessons").click()
                }
                XCTAssertTrue(control("lesson.area.a").isHittable)
                visited.insert(id)
            }
        }
        XCTAssertEqual(visited.count, 20)
        control("lesson.area.c").click()
        control("lesson.open.memory-dock").click()
        attachWindowScreenshot("lesson-free-navigation-memory")
        control("lesson.all").click()
        attachWindowScreenshot("lesson-free-navigation-library")
        control("lesson.close").click()
        XCTAssertTrue(control("ex.area.a").isHittable)
    }

    func testGirlOpensLessonsAndAllTwentyExperimentsComplete() throws {
        let girl = control("ex.lobby.lessons")
        XCTAssertTrue(girl.waitForExistence(timeout: 5))
        girl.click()
        XCTAssertTrue(control("lesson.area.a").exists)
        attachWindowScreenshot("lessons-01-welcome")
        let activities = ["bit.0", "logic.a", "latch.input", "transistor.control",
                          "instructions.swap", "schedule.order", "parallel.cores.increase", "pixels.lanes",
                          "memory.save", "cache.read", "compression.swap", "storage.speed",
                          "frames.hz", "network.bandwidth", "bus.paths", "ports.capability",
                          "flow.next", "battery.energy", "cooling.load.increase", "bottleneck.read"]
        // macOS may expose the activity container's identifier on its children.
        // Keep the same actions, resolving them by their public labels in that case.
        let activityLabels = ["重み128のビットを切り替える", "A  0", "入力  0", "制御信号  OFF",
                              "命令の順番を入れ替える", "短い時間で交代する", "使うコアを増やす", "4レーンにする",
                              "保存する", "同じデータを読む", "SSDへ退避", "速度を50 MB/sに",
                              "120 Hzに", "帯域 10 MB/s", "独立した2本の道にする", "接続：充電のみ",
                              "次の役割へ", "残りを30 Whにする", "作業を増やす", "読込の能力を変更"]
        var index = 0
        for (room, ids) in rooms {
            control("lesson.area.\(room)").click()
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "lesson.open.")).count, 4)
            for id in ids {
                control("lesson.open.\(id)").click()
                attachWindowScreenshot("lessons-intro-\(id)")
                control("lesson.next").click()
                XCTAssertFalse(control("lesson.next").isEnabled, "Opening a diagram alone does not count as exploring")
                let activityByID = element("lesson.activity.\(activities[index])")
                let activity = activityByID.exists ? activityByID : app.buttons.matching(
                    NSPredicate(format: "label == %@", activityLabels[index])).firstMatch
                XCTAssertTrue(activity.waitForExistence(timeout: 3), "Missing lesson action: \(activityLabels[index])")
                activity.click()
                XCTAssertTrue(control("lesson.next").isEnabled)
                XCTAssertEqual(app.scrollViews.count, 0, "Lesson \(id) must fit the game viewport")
                attachWindowScreenshot("lessons-experiment-\(id)")
                control("lesson.next").click()
                XCTAssertFalse(control("lesson.next").isEnabled)
                // Independent expected answers to each fixed-scenario question.
                let correct = [2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 0][index]
                control("lesson.answer.\(correct)").click()
                XCTAssertTrue(control("lesson.next").isEnabled)
                attachWindowScreenshot("lessons-question-\(id)")
                control("lesson.next").click()
                XCTAssertTrue(control("lesson.complete").exists)
                attachWindowScreenshot("lessons-discovery-\(id)")
                control("lesson.done").click()
                XCTAssertTrue(accessibleText(control("lesson.open.\(id)")).contains("発見済み"))
                index += 1
            }
        }
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: saveDirectory.appendingPathComponent("lessons.json"))) as? [String: Any]
        XCTAssertEqual(Set(saved?["completedIDs"] as? [String] ?? []), Set(rooms.flatMap(\.1)))
        attachWindowScreenshot("lessons-all-twenty-discovered")
        control("lesson.close").click()
        XCTAssertTrue(control("ex.area.a").isHittable)
    }

    func testLessonWrongAnswerRetryPersistenceAndExhibitReturn() throws {
        control("ex.lessons").click()
        control("lesson.area.c").click()
        control("lesson.open.memory-dock").click()
        control("lesson.next").click()
        control("lesson.activity.memory.save").click()
        control("lesson.activity.memory.release").click()
        attachWindowScreenshot("lessons-memory-saved-and-released")
        control("lesson.next").click()
        control("lesson.answer.0").click()
        XCTAssertFalse(control("lesson.next").isEnabled)
        XCTAssertTrue(control("lesson.feedback").exists)
        attachWindowScreenshot("lessons-memory-retry")
        control("lesson.answer.1").click()
        control("lesson.next").click()
        XCTAssertTrue(control("lesson.complete").exists)
        control("lesson.close").click()
        control("ex.lessons").click()
        XCTAssertTrue(control("lesson.area.c").exists, "The main lesson entrance always allows choosing a theme")
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        launchAndReveal()
        control("ex.lessons").click()
        control("lesson.area.c").click()
        XCTAssertTrue(accessibleText(control("lesson.open.memory-dock")).contains("発見済み"))
        control("lesson.previous").click()
        control("lesson.next").click()
        XCTAssertFalse(control("lesson.next").isEnabled, "Revisiting starts a fresh, explorable experiment")
        control("lesson.activity.memory.save").click()
        control("lesson.next").click()
        control("lesson.answer.1").click()
        control("lesson.next").click()
        control("lesson.exhibit").click()
        XCTAssertTrue(accessibleText(control("ex.entry.title")).contains("メモリ"))
        XCTAssertFalse(element("ex.entry.start").exists, "A lesson must not present an unfinished game as playable")
        control("ex.back").click()
        XCTAssertTrue(control("ex.game.memory-dock").exists)
    }

    func testLessonsPreserveWorkingCircuitAndRoom() {
        control("ex.area.a").click()
        let original = control("ex.game.circuit-atelier").frame
        control("ex.lessons").click()
        control("lesson.close").click()
        waitForFrame("ex.game.circuit-atelier", toEqual: original)
        enterCircuit()
        control("w.gate.or").click()
        control("w.link.a").click()
        let gate = accessibleText(control("w.gate.or"))
        let link = accessibleText(control("w.link.a"))
        control("ex.lessons").click()
        control("lesson.open.circuit-atelier").click()
        control("lesson.close").click()
        XCTAssertEqual(accessibleText(control("w.gate.or")), gate)
        XCTAssertEqual(accessibleText(control("w.link.a")), link)
        XCTAssertTrue(control("w.input.a").isHittable)
    }

    func testLobbyAnimationPauseAndNavigation() {
        let motion = control("ex.lobby.motion")
        let initiallyPaused = accessibleText(motion).contains("停止中")
        if !initiallyPaused { motion.click() }
        XCTAssertTrue(accessibleText(control("ex.lobby.motion")).contains("停止中"))
        Thread.sleep(forTimeInterval: 0.4)
        let stillA = app.windows.firstMatch.screenshot().pngRepresentation
        Thread.sleep(forTimeInterval: 0.4)
        let stillB = app.windows.firstMatch.screenshot().pngRepresentation
        XCTAssertEqual(stillA, stillB, "Pausing should render a stable resting portrait")
        control("ex.lobby.motion").click()
        XCTAssertTrue(accessibleText(control("ex.lobby.motion")).contains("再生中"))
        Thread.sleep(forTimeInterval: 0.4)
        let movingA = app.windows.firstMatch.screenshot().pngRepresentation
        let blinkDeadline = Date().addingTimeInterval(7.2)
        var blinkObserved = false
        while Date() < blinkDeadline {
            if app.windows.firstMatch.screenshot().pngRepresentation != movingA { blinkObserved = true; break }
            Thread.sleep(forTimeInterval: 0.03)
        }
        XCTAssertTrue(blinkObserved, "The visible lobby should blink while the body remains still")
        attachWindowScreenshot("lobby-motion-running")
        for (area, _) in rooms { XCTAssertTrue(control("ex.area.\(area)").isHittable) }
        control("ex.map").click()
        XCTAssertEqual(gameButtons.count, 20)
        control("ex.map.close").click()
        XCTAssertTrue(accessibleText(control("ex.lobby.motion")).contains("再生中"))
        control("ex.area.a").click()
        XCTAssertFalse(element("ex.lobby.motion").exists)
        control("ex.back").click()
        XCTAssertTrue(control("ex.lobby.motion").isHittable)
        XCTAssertEqual(app.scrollViews.count, 0)
        if initiallyPaused { control("ex.lobby.motion").click() }
    }

    func testLobbyNarrationEndsWhenOpeningMap() {
        control("ex.guide.speak").click()
        let narration = control("ex.guide.speak")
        let speaking = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "音声を止める"), object: narration)
        XCTAssertEqual(XCTWaiter.wait(for: [speaking], timeout: 3), .completed,
                       "The installed Japanese voice should start real narration")
        attachWindowScreenshot("lobby-motion-narration")
        control("ex.map").click()
        XCTAssertTrue(control("ex.map.close").isHittable)
        control("ex.map.close").click()
        XCTAssertTrue(accessibleText(control("ex.guide.speak")).contains("案内を聞く"),
                      "Narration must stop when leaving the visible lobby")
    }

    func testCompactWindowKeepsAllDoorsAndMapEntrancesOperable() {
        let window = app.windows.firstMatch
        let originalFrame = window.frame
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1))
            .withOffset(CGVector(dx: -1, dy: -1))
        let compactCorner = window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 1099, dy: 769))
        corner.click(forDuration: 0.3, thenDragTo: compactCorner)
        let compactSize = XCTNSPredicateExpectation(predicate: NSPredicate { object, _ in
            guard let actual = object as? XCUIElement else { return false }
            return actual.frame.width <= 1150 && actual.frame.height <= 810
        }, object: window)
        let resized = XCTWaiter.wait(for: [compactSize], timeout: 4)
        let compactFrame = window.frame
        let dimensions = XCTAttachment(string: "Before native resize: \(originalFrame)\nAfter native resize: \(compactFrame)")
        dimensions.name = "exhibition-compact-window-dimensions"
        dimensions.lifetime = .keepAlways
        add(dimensions)
        XCTAssertEqual(resized, .completed, "Native window drag must reach a compact viewport; actual frame: \(compactFrame)")
        XCTAssertGreaterThanOrEqual(compactFrame.width, 1090)
        XCTAssertGreaterThanOrEqual(compactFrame.height, 740)
        for (area, _) in rooms {
            let door = control("ex.area.\(area)")
            XCTAssertTrue(door.isHittable)
            XCTAssertTrue(compactFrame.contains(door.frame), "Door \(area) must fit inside the compact window")
        }
        XCTAssertEqual(app.scrollViews.count, 0)
        attachWindowScreenshot("exhibition-compact-lobby")
        control("ex.map").click()
        XCTAssertEqual(gameButtons.count, 20)
        for game in rooms.flatMap(\.1) {
            let entrance = control("ex.game.\(game)")
            XCTAssertTrue(entrance.isHittable)
            XCTAssertTrue(window.frame.contains(entrance.frame), "Map entrance \(game) must fit inside the compact window")
        }
        XCTAssertTrue(control("ex.map.close").isHittable)
        XCTAssertEqual(app.scrollViews.count, 0)
        attachWindowScreenshot("exhibition-compact-map")
    }

    func testMapClosesToOriginalRoomAndPreparingExhibitCannotStart() {
        control("ex.area.c").click()
        let sourceFrame = control("ex.game.memory-dock").frame
        control("ex.map").click()
        control("ex.map.close").click()
        waitForFrame("ex.game.memory-dock", toEqual: sourceFrame)
        control("ex.map").click()
        XCTAssertTrue(control("ex.map.close").exists)
        app.typeKey(.escape, modifierFlags: [])
        waitForFrame("ex.game.memory-dock", toEqual: sourceFrame)
        control("ex.game.memory-dock").click()
        XCTAssertTrue(control("ex.entry.preparing").exists)
        let start = element("ex.entry.start")
        XCTAssertFalse(start.exists && start.isEnabled, "Unimplemented games must not promise playable content")
        attachWindowScreenshot("exhibition-memory-dock-preparing")
        control("ex.back").click()
        XCTAssertTrue(control("ex.game.memory-dock").isHittable)
    }

    func testMapSelectionOpensCorrectEntryAndReturnsToItsArea() {
        control("ex.area.b").click()
        control("ex.map").click()
        control("ex.game.connection-lab").click()
        XCTAssertFalse(element("ex.map.close").exists, "Choosing an exhibit should close the map")
        XCTAssertTrue(control("ex.entry.preparing").exists)
        XCTAssertTrue(accessibleText(control("ex.entry.title")).contains("接続端子と通信・給電"))
        control("ex.back").click()
        for game in rooms.first(where: { $0.0 == "d" })!.1 {
            XCTAssertTrue(control("ex.game.\(game)").isHittable)
        }
    }

    func testEmptyWorkbookClosesToSameRoom() {
        control("ex.area.e").click()
        let sourceFrame = control("ex.game.cooling-workshop").frame
        control("ex.workbook").click()
        XCTAssertTrue(control("ex.workbook.close").isHittable)
        XCTAssertTrue(control("ex.workbook.empty").exists,
                      "A new player should see an empty collection, not demo completion")
        attachWindowScreenshot("exhibition-empty-workbook")
        control("ex.workbook.close").click()
        waitForFrame("ex.game.cooling-workshop", toEqual: sourceFrame)
    }

    func testCircuitWorkSurvivesReturnToExhibitionAndAppRelaunch() {
        control("ex.area.a").click()
        enterCircuit()
        control("w.gate.and").click()
        for link in ["a", "b", "output"] { control("w.link.\(link)").click() }
        // Build an observable nondefault input so a fresh session cannot pass.
        for input in ["a", "b"] {
            let target = control("w.input.\(input)")
            if accessibleText(target).contains("0 OFF") { target.click() }
        }
        XCTAssertTrue(accessibleText(control("w.lamp")).contains("1"))
        let inputA = accessibleText(control("w.input.a"))
        let inputB = accessibleText(control("w.input.b"))
        let lamp = accessibleText(control("w.lamp"))
        let slot = accessibleText(control("w.slot"))
        XCTAssertEqual(app.scrollViews.count, 0)
        attachWindowScreenshot("exhibition-play-before-return")
        control("ex.back").click()
        XCTAssertTrue(control("ex.game.circuit-atelier").isHittable)
        enterCircuit()
        XCTAssertEqual(accessibleText(control("w.input.a")), inputA)
        XCTAssertEqual(accessibleText(control("w.input.b")), inputB)
        XCTAssertEqual(accessibleText(control("w.lamp")), lamp)
        XCTAssertEqual(accessibleText(control("w.slot")), slot)
        control("ex.back").click()
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        launchAndReveal()
        XCTAssertTrue(control("ex.game.circuit-atelier").isHittable,
                      "Relaunch should return to the last room without forcing gameplay")
        enterCircuit()
        XCTAssertEqual(accessibleText(control("w.input.a")), inputA)
        XCTAssertEqual(accessibleText(control("w.input.b")), inputB)
        XCTAssertEqual(accessibleText(control("w.lamp")), lamp)
        XCTAssertEqual(accessibleText(control("w.slot")), slot)
        XCTAssertTrue(control("w.test").isEnabled, "All three preserved connections must still form a testable circuit")
        attachWindowScreenshot("exhibition-play-resumed-after-relaunch")
    }

    func testFreeExperimentKeepsModeMissionAndCircuitWhenReturningFromRoom() {
        control("ex.area.a").click()
        enterCircuit()
        control("w.sandbox").click()
        control("stage.1").click()
        control("gate.or").click()
        for link in ["a", "b", "output"] { control("link.\(link)").click() }
        control("game.check").click()
        XCTAssertTrue(element("game.success").waitForExistence(timeout: 8))
        let slot = accessibleText(control("gate.slot"))
        let lamp = accessibleText(control("game.lamp"))
        control("ex.back").click()
        control("ex.game.circuit-atelier").click()
        control("ex.entry.start").click()
        XCTAssertTrue(control("workshop.return").exists,
                      "Returning from the room must preserve the player's free-experiment mode")
        XCTAssertTrue(element("game.success").exists)
        XCTAssertEqual(accessibleText(control("gate.slot")), slot)
        XCTAssertEqual(accessibleText(control("game.lamp")), lamp)
        attachWindowScreenshot("exhibition-free-experiment-resumed")
        control("workshop.return").click()
        XCTAssertTrue(control("w.input.a").exists, "The guided workshop remains reachable from free experiment")
    }

    func testRestartFromEntryLeavesFreeExperimentAndStartsFreshGuidedWorkshop() {
        control("ex.area.a").click()
        enterCircuit()
        control("w.gate.and").click()
        control("w.link.a").click()
        control("w.sandbox").click()
        control("stage.1").click()
        control("gate.or").click()
        control("ex.back").click()
        control("ex.game.circuit-atelier").click()
        control("ex.entry.restart").click()
        let confirmation = app.sheets.buttons["最初から作る"].firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.click()
        XCTAssertTrue(control("w.input.a").exists,
                      "Starting again from the entry must open the guided workshop, even after using free experiment")
        XCTAssertFalse(element("workshop.return").exists)
        XCTAssertFalse(control("w.test").isEnabled, "Restart must clear the guided working circuit")
        XCTAssertTrue(accessibleText(control("w.lamp")).contains("未接続"))
        attachWindowScreenshot("exhibition-restart-from-sandbox-opens-guided-workshop")
    }

    private func enterCircuit() {
        control("ex.game.circuit-atelier").click()
        control("ex.entry.start").click()
        // The integrated shell can reuse the existing welcome screen. Operate
        // only its visible, player-facing begin/resume control if one is shown.
        if element("workshop.begin").exists { control("workshop.begin").click() }
        else if element("workshop.resume").exists { control("workshop.resume").click() }
        XCTAssertTrue(control("w.input.a").exists)
    }

    private var gameButtons: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ex.game."))
    }

    private func waitForFrame(_ identifier: String, toEqual expected: CGRect,
                              file: StaticString = #filePath, line: UInt = #line) {
        let target = control(identifier, file: file, line: line)
        // Native scene transitions can finish after the accessibility control
        // becomes hittable. Compare settled geometry, not an in-flight frame.
        let predicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement else { return false }
            let frame = element.frame
            return abs(frame.minX - expected.minX) < 0.5 && abs(frame.minY - expected.minY) < 0.5
                && abs(frame.width - expected.width) < 0.5 && abs(frame.height - expected.height) < 0.5
        }
        let restored = XCTNSPredicateExpectation(predicate: predicate, object: target)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 4), .completed,
                       "Closing the overlay must restore entrance geometry: expected \(expected), got \(target.frame)",
                       file: file, line: line)
    }

    private func launchAndReveal() {
        app.launch()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        app.revealGameWindowOnceIfNeeded()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15), "Exhibition window did not open")
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func control(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        if app.state != .runningForeground { app.activate() }
        let target = element(identifier)
        XCTAssertTrue(target.exists || target.waitForExistence(timeout: 5),
                      "Missing exhibition control: \(identifier)", file: file, line: line)
        if !target.isHittable && target.elementType == .button {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: target)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed,
                           "Exhibition control cannot be operated: \(identifier)", file: file, line: line)
        }
        return target
    }

    private func accessibleText(_ element: XCUIElement) -> String {
        [element.label, element.value as? String ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func attachWindowScreenshot(_ name: String) {
        // SwiftUI opacity transitions may continue after AX reports a hittable
        // control. Release captures should show the settled scene, not a fade.
        Thread.sleep(forTimeInterval: 0.35)
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
private extension XCUIApplication {
    /// macOS can keep a real window in another Space while exposing only the app's menu bar.
    /// Select that observed window once through the public Window menu; do not relaunch/retry.
    func revealGameWindowOnceIfNeeded() {
        if windows.firstMatch.exists || windows.firstMatch.waitForExistence(timeout: 2) { return }
        let windowMenu = menuBars.menuBarItems.matching(identifier: "Window").firstMatch
        guard windowMenu.exists else { return }
        windowMenu.click()
        for title in ["AIBOU · 展示館", "AIBOU · 論理回路"] {
            let gameWindow = menuItems.matching(identifier: title).firstMatch
            if gameWindow.exists { gameWindow.click(); return }
        }
    }
}
