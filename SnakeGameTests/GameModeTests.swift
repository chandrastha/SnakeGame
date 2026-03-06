import XCTest
@testable import SnakeGame

final class GameModeTests: XCTestCase {

    // MARK: - Unit Tests: Enum Cases

    func test_givenGameModeCases_whenEnumeratingKnownModes_thenOnlineOfflineAndChallengeExist() {
        let modes: [GameMode] = [.online, .offline, .challenge]
        XCTAssertEqual(modes.count, 3)
        XCTAssertEqual(modes[0], .online)
        XCTAssertEqual(modes[1], .offline)
        XCTAssertEqual(modes[2], .challenge)
    }
}
