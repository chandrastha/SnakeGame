import XCTest
@testable import SnakeGame

final class GameModeTests: XCTestCase {

    // MARK: - Unit Tests: Enum Cases

    func test_givenGameModeCases_whenEnumeratingKnownModes_thenAllModesExist() {
        let modes = GameMode.allCases
        XCTAssertEqual(modes.count, 5)
        XCTAssertEqual(modes[0], .online)
        XCTAssertEqual(modes[1], .offline)
        XCTAssertEqual(modes[2], .challenge)
        XCTAssertEqual(modes[3], .mazeHunt)
        XCTAssertEqual(modes[4], .snakeRace)
    }

    func test_givenGameMode_whenReadingStorageKeys_thenUsesStableModeSpecificKeys() {
        XCTAssertEqual(GameMode.online.rawValue, "online")
        XCTAssertEqual(GameMode.mazeHunt.rawValue, "mazeHunt")
        XCTAssertEqual(GameMode.offline.bestScoreKey, "bestScore.offline")
        XCTAssertEqual(GameMode.challenge.leaderboardKey, "scoreHistory.challenge")
        XCTAssertEqual(GameMode.snakeRace.leaderboardTitle, "SNAKE RACE LEADERBOARD")
    }
}
