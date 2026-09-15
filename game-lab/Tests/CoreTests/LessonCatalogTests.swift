import Foundation
import XCTest
@testable import CircuitCore

final class LessonCatalogTests: XCTestCase {
    func testEveryExhibitionHasExactlyOneLessonWithoutChangingPlayableGames() {
        XCTAssertEqual(LessonCatalog.lessons.map(\.id), ExhibitionCatalog.games.map(\.id))
        XCTAssertEqual(Set(LessonCatalog.lessons.map(\.id)).count, 20)
        XCTAssertEqual(Set(LessonCatalog.lessons.map(\.activity)), Set(LessonActivityKind.allCases))
        XCTAssertEqual(ExhibitionCatalog.games.filter(\.isPlayable).count, 20)
        for area in ExhibitionAreaID.allCases {
            XCTAssertEqual(LessonCatalog.lessons(in: area).map(\.id), ExhibitionCatalog.games(in: area).map(\.id))
            XCTAssertEqual(LessonCatalog.lessons(in: area).count, 4)
        }
        XCTAssertNil(LessonCatalog.lesson("unknown-lesson"))
    }

    func testEveryLessonHasACompleteBoundedTeachingSequenceAndValidQuestion() {
        for lesson in LessonCatalog.lessons {
            let text = [lesson.title, lesson.question, lesson.goal, lesson.intro, lesson.explanation,
                        lesson.analogyLimit, lesson.activityPrompt, lesson.takeaway, lesson.labConnection]
            XCTAssertTrue(text.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, lesson.id)
            XCTAssertLessThanOrEqual(lesson.title.count, 24, lesson.id)
            XCTAssertLessThanOrEqual(lesson.explanation.count, 150, lesson.id)
            XCTAssertGreaterThanOrEqual(lesson.explanation.count, 60, lesson.id)
            XCTAssertLessThanOrEqual(lesson.intro.count, 140, lesson.id)
            XCTAssertEqual(lesson.challenge.options.count, 3, lesson.id)
            XCTAssertEqual(Set(lesson.challenge.options).count, 3, lesson.id)
            XCTAssertTrue(lesson.challenge.options.indices.contains(lesson.challenge.correctIndex), lesson.id)
            XCTAssertFalse(lesson.challenge.prompt.isEmpty, lesson.id)
            XCTAssertFalse(lesson.challenge.correctFeedback.isEmpty, lesson.id)
            XCTAssertFalse(lesson.challenge.incorrectFeedback.isEmpty, lesson.id)
            XCTAssertFalse(lesson.challenge.prompt.contains("今の結果"), "Quiz must not silently depend on mutable activity state: \(lesson.id)")
        }
    }

    func testSourcesUseReviewedPrimaryPublishersAndSecureURLs() throws {
        let publishers = Set(["ocw.mit.edu", "pages.cs.wisc.edu", "support.apple.com", "www.apple.com",
                              "developer.apple.com", "www.intel.com", "docs.nvidia.com", "www.cloudflare.com", "www.usb.org"])
        for lesson in LessonCatalog.lessons {
            XCTAssertFalse(lesson.sources.isEmpty, lesson.id)
            for source in lesson.sources {
                XCTAssertFalse(source.title.isEmpty, lesson.id)
                let url = try XCTUnwrap(URL(string: source.url), source.url)
                XCTAssertEqual(url.scheme, "https", source.url)
                XCTAssertTrue(publishers.contains(try XCTUnwrap(url.host)), source.url)
            }
        }
    }

    func testCatalogRoundTripsWithoutLosingFeedbackOrSourceAttribution() throws {
        let data = try JSONEncoder().encode(LessonCatalog.lessons)
        let restored = try JSONDecoder().decode([LessonDefinition].self, from: data)
        XCTAssertEqual(restored, LessonCatalog.lessons)
    }

    func testTeachingExamplesHaveStableArithmeticAnswers() throws {
        func answer(_ id: String) throws -> String {
            let challenge = try XCTUnwrap(LessonCatalog.lesson(id)).challenge
            return challenge.options[challenge.correctIndex]
        }
        XCTAssertEqual(try answer("bit-art"), "8通り")
        XCTAssertEqual(try answer("circuit-atelier"), "0")
        XCTAssertEqual(try answer("instruction-atelier"), "10")
        XCTAssertEqual(try answer("parallel-factory"), "2秒")
        XCTAssertEqual(try answer("board-town"), "10個")
        XCTAssertEqual(try answer("display-studio"), "30枚")
        XCTAssertEqual(try answer("packet-express"), "約100msのまま")
        XCTAssertEqual(try answer("battery-voyage"), "4時間")
        XCTAssertEqual(try answer("bottleneck-detective"), "読む工程")
    }
}
