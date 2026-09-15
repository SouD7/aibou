import XCTest
@testable import CircuitCore

final class LobbyMotionTests: XCTestCase {
    func testBlinkBrieflyClosesAndReturnsToOpenEyes() {
        XCTAssertEqual(LobbyMotion.blink(at: 2.7), 1, accuracy: 0.0001)
        XCTAssertEqual(LobbyMotion.blink(at: 0), 0)
        XCTAssertEqual(LobbyMotion.blink(at: 3), 0)
        var closedSamples = 0
        for t in stride(from: 0.0, to: 6.8, by: 0.01) {
            let blink = LobbyMotion.blink(at: t)
            XCTAssertTrue((0...1).contains(blink))
            if blink > 0.25 { closedSamples += 1 }
        }
        XCTAssertGreaterThan(closedSamples, 10)
        XCTAssertLessThan(closedSamples, 40)
    }

    func testBlinkRepeatsWithoutHoldingEyesClosed() {
        XCTAssertEqual(LobbyMotion.blink(at: 6.05), 1, accuracy: 0.0001)
        XCTAssertEqual(LobbyMotion.blink(at: 9.5), 1, accuracy: 0.0001)
        XCTAssertEqual(LobbyMotion.blink(at: 6.8), 0)
    }
}
