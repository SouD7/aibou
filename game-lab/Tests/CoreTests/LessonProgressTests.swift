import Foundation
import XCTest
@testable import CircuitCore

final class LessonProgressTests: XCTestCase {
    private let lessonID = "memory-dock"

    private func temporarySave() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("aibou-lesson-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("lessons/progress.json")
    }

    private func writeFixture(_ json: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)
    }

    private func completedSession(_ id: String) throws -> LessonSession {
        var session = LessonSession(lessonID: id)
        session.advance()
        session.explore()
        session.advance()
        session.answer(try XCTUnwrap(LessonCatalog.lesson(id)).challenge.correctIndex)
        session.advance()
        XCTAssertTrue(session.isComplete)
        return session
    }

    func testReadingCannotSkipTheExperimentOrCreateCompletion() throws {
        var session = LessonSession(lessonID: lessonID)
        var progress = LessonProgress()
        progress.visit(lessonID)

        // Early interaction notifications must not pre-authorize later steps.
        session.explore()
        session.answer(try XCTUnwrap(LessonCatalog.lesson(lessonID)).challenge.correctIndex)
        XCTAssertFalse(session.explored)
        XCTAssertNil(session.selectedOption)

        session.advance()
        XCTAssertEqual(session.step, .experiment)
        XCTAssertFalse(session.canAdvance)
        for _ in 0..<5 { session.advance() }
        progress.record(session)
        XCTAssertEqual(session.step, .experiment)
        XCTAssertFalse(session.isComplete)
        XCTAssertTrue(progress.completedIDs.isEmpty)
        XCTAssertEqual(progress.lastLessonID, lessonID)
    }

    func testEveryLessonRequiresAnExperimentAndCorrectAnswerBeforeReflection() throws {
        for lesson in LessonCatalog.lessons {
            var session = LessonSession(lessonID: lesson.id)
            var progress = LessonProgress()
            session.advance()
            session.explore()
            session.advance()
            XCTAssertEqual(session.step, .question, lesson.id)
            XCTAssertFalse(session.canAdvance, lesson.id)

            let wrong = try XCTUnwrap(lesson.challenge.options.indices.first { $0 != lesson.challenge.correctIndex })
            session.answer(wrong)
            session.advance()
            progress.record(session)
            XCTAssertEqual(session.step, .question, lesson.id)
            XCTAssertEqual(session.selectedOption, wrong, lesson.id)
            XCTAssertFalse(session.answeredCorrectly, lesson.id)
            XCTAssertTrue(progress.completedIDs.isEmpty, lesson.id)

            session.answer(lesson.challenge.correctIndex)
            XCTAssertTrue(session.canAdvance, lesson.id)
            progress.record(session)
            XCTAssertTrue(progress.completedIDs.isEmpty, "The learner has not reached the summary: \(lesson.id)")
            session.advance()
            XCTAssertEqual(session.step, .reflection, lesson.id)
            XCTAssertTrue(session.isComplete, lesson.id)
            XCTAssertFalse(session.canAdvance, lesson.id)
            progress.record(session)
            progress.record(session)
            XCTAssertEqual(progress.completedIDs, [lesson.id], lesson.id)
        }
    }

    func testInvalidAnswersAndOutOfStepActionsDoNotChangeLearningEvidence() throws {
        let lesson = try XCTUnwrap(LessonCatalog.lesson(lessonID))
        var session = LessonSession(lessonID: lessonID)
        session.advance()
        session.explore()
        session.advance()
        let unanswered = session
        session.answer(-1)
        session.answer(lesson.challenge.options.endIndex)
        session.answer(Int.max)
        XCTAssertEqual(session, unanswered)

        session.answer(lesson.challenge.correctIndex)
        session.advance()
        let complete = session
        session.answer((lesson.challenge.correctIndex + 1) % lesson.challenge.options.count)
        session.explore()
        session.advance()
        XCTAssertEqual(session, complete, "Answer controls are inactive on the summary page.")
    }

    func testGoingBackPreservesExplorationButARevisedWrongAnswerBlocksAdvancing() throws {
        let lesson = try XCTUnwrap(LessonCatalog.lesson(lessonID))
        var session = try completedSession(lessonID)
        session.back()
        XCTAssertEqual(session.step, .question)
        XCTAssertFalse(session.isComplete)
        XCTAssertEqual(session.selectedOption, lesson.challenge.correctIndex)

        session.back()
        XCTAssertEqual(session.step, .experiment)
        XCTAssertTrue(session.explored)
        session.back()
        session.back()
        XCTAssertEqual(session.step, .introduction, "Back at the first page must stay in bounds.")
        session.advance()
        session.advance()
        XCTAssertEqual(session.step, .question)
        session.answer((lesson.challenge.correctIndex + 1) % lesson.challenge.options.count)
        XCTAssertFalse(session.canAdvance)
        session.advance()
        XCTAssertEqual(session.step, .question)
        XCTAssertFalse(session.isComplete)

        session.answer(lesson.challenge.correctIndex)
        session.advance()
        XCTAssertTrue(session.isComplete, "The learner can correct the answer without restarting the lesson.")
    }

    func testRetryStartsFreshWithoutDeletingAnAlreadyEarnedCompletion() throws {
        var progress = LessonProgress()
        progress.record(try completedSession(lessonID))

        // The UI retries by creating a new session for the selected lesson.
        var retry = LessonSession(lessonID: lessonID)
        XCTAssertEqual(retry.step, .introduction)
        XCTAssertFalse(retry.explored)
        XCTAssertNil(retry.selectedOption)
        XCTAssertFalse(retry.answeredCorrectly)
        XCTAssertFalse(retry.isComplete)
        retry.advance()
        retry.advance()
        XCTAssertEqual(retry.step, .experiment)
        progress.record(retry)
        XCTAssertEqual(progress.completedIDs, [lessonID])
    }

    func testUnknownLessonCannotBeVisitedAnsweredOrRecorded() {
        var progress = LessonProgress()
        progress.visit(lessonID)
        let original = progress
        progress.visit("removed-lesson")
        var unknown = LessonSession(lessonID: "removed-lesson")
        unknown.advance()
        unknown.explore()
        unknown.advance()
        unknown.answer(0)
        unknown.advance()
        progress.record(unknown)
        XCTAssertEqual(unknown.step, .question)
        XCTAssertNil(unknown.selectedOption)
        XCTAssertFalse(unknown.isComplete)
        XCTAssertEqual(progress, original)
    }

    func testSavingAndReplacingProgressRetainsOnlyEarnedCompletionAndLastVisit() throws {
        let url = try temporarySave()
        var progress = LessonProgress()
        progress.visit(lessonID)
        progress.record(try completedSession(lessonID))
        try progress.save(to: url)
        XCTAssertEqual(try LessonProgress.load(from: url), progress)

        progress.visit("battery-voyage")
        progress.record(LessonSession(lessonID: "battery-voyage"))
        try progress.save(to: url)
        let restored = try LessonProgress.load(from: url)
        XCTAssertEqual(restored.completedIDs, [lessonID])
        XCTAssertEqual(restored.lastLessonID, "battery-voyage")
        XCTAssertEqual(restored.version, 1)

        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertNil(saved["session"], "A reload must not manufacture a partially answered lesson session.")
        XCTAssertNil(saved["step"])
        XCTAssertNil(saved["answeredCorrectly"])
    }

    func testOldIdentifiersAreFilteredWithoutLosingKnownCompletedLessons() throws {
        let url = try temporarySave()
        try writeFixture(#"{"version":1,"completedIDs":["memory-dock","removed-lesson","memory-dock","bit-art"],"lastLessonID":"removed-lesson"}"#, to: url)
        let originalData = try Data(contentsOf: url)
        let restored = try LessonProgress.load(from: url)
        XCTAssertEqual(restored.completedIDs, ["memory-dock", "bit-art"])
        XCTAssertNil(restored.lastLessonID)
        XCTAssertEqual(try Data(contentsOf: url), originalData, "Loading must not rewrite the source record.")

        try restored.save(to: url)
        XCTAssertEqual(try LessonProgress.load(from: url), restored)
    }

    func testCorruptRecordsThrowAndRemainAvailableForRecovery() throws {
        let url = try temporarySave()
        let fixtures = [
            "{not valid JSON",
            #"{"version":1,"completedIDs":"memory-dock"}"#,
            #"{"version":1,"completedIDs":[1],"lastLessonID":"memory-dock"}"#,
            #"{"completedIDs":[],"lastLessonID":"memory-dock"}"#
        ]
        for fixture in fixtures {
            try writeFixture(fixture, to: url)
            let originalData = try Data(contentsOf: url)
            XCTAssertThrowsError(try LessonProgress.load(from: url), fixture)
            XCTAssertEqual(try Data(contentsOf: url), originalData)
        }
    }

    func testFutureVersionIsRejectedWithoutOverwritingOrDowngradingTheRecord() throws {
        let url = try temporarySave()
        try writeFixture(#"{"version":2,"completedIDs":["memory-dock"],"lastLessonID":"memory-dock","futureField":{"keep":true}}"#, to: url)
        let originalData = try Data(contentsOf: url)
        XCTAssertThrowsError(try LessonProgress.load(from: url)) { error in
            XCTAssertEqual((error as? CocoaError)?.code, .coderReadCorrupt)
        }
        XCTAssertEqual(try Data(contentsOf: url), originalData)
    }

    func testMissingFileAndUnwritableParentReportFailureInsteadOfInventingProgress() throws {
        let url = try temporarySave()
        XCTAssertThrowsError(try LessonProgress.load(from: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        // A regular file occupying the parent path is deterministic even when tests run with broad permissions.
        let obstruction = url.deletingLastPathComponent()
        let sentinel = Data("keep this unrelated file".utf8)
        try sentinel.write(to: obstruction)
        var progress = LessonProgress()
        progress.record(try completedSession(lessonID))
        XCTAssertThrowsError(try progress.save(to: url))
        XCTAssertEqual(try Data(contentsOf: obstruction), sentinel)
    }
}
