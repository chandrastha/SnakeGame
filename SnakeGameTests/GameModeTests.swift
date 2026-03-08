import XCTest
@testable import SnakeGame

final class GameModeTests: XCTestCase {
    func test_givenGameModeCases_whenEnumeratingKnownModes_thenAllModesExist() {
        let modes: [GameMode] = [.offline, .challenge]
        XCTAssertEqual(modes.count, 2)
        XCTAssertEqual(modes[0], .offline)
        XCTAssertEqual(modes[1], .challenge)
    }
}
