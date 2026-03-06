import XCTest
@testable import SnakeGame

final class GameModeTests: XCTestCase {

    // MARK: - Unit Tests: Enum Cases

    func test_givenGameModeCases_whenEnumeratingKnownModes_thenOnlineAndOfflineExist() {
        let modes: [GameMode] = [.online, .offline]
        XCTAssertEqual(modes.count, 2)
        XCTAssertEqual(modes[0], .online)
        XCTAssertEqual(modes[1], .offline)
    }
}
