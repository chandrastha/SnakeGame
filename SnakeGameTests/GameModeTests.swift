import XCTest
@testable import SnakeGame

final class GameModeTests: XCTestCase {

    // MARK: - Unit Tests: Enum Cases

    func test_givenGameModeCases_whenEnumeratingKnownModes_thenAllModesExist() {
        let modes: [GameMode] = [.online, .offline, .challenge, .mazeHunt, .snakeRace]
        XCTAssertEqual(modes.count, 5)
        XCTAssertEqual(modes[0], .online)
        XCTAssertEqual(modes[1], .offline)
        XCTAssertEqual(modes[2], .challenge)
        XCTAssertEqual(modes[3], .mazeHunt)
        XCTAssertEqual(modes[4], .snakeRace)
    }
}
