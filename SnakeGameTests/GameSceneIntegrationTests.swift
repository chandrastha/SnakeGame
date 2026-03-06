import XCTest
import SpriteKit
@testable import SnakeGame

final class GameSceneIntegrationTests: XCTestCase {

    // MARK: - Integration Tests: SpriteKit + SwiftUI Bridge Points

    func test_givenFreshScene_whenDidMove_thenInitialStateIsPrepared() {
        let scene = GameScene(size: CGSize(width: 390, height: 844))
        scene.scaleMode = .resizeFill
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))

        scene.didMove(to: view)

        XCTAssertFalse(scene.isGameOver)
        XCTAssertEqual(scene.score, 0)
        XCTAssertGreaterThan(scene.foodItems.count, 0)
    }

    func test_givenStartedScene_whenUpdateCalled_thenLastUpdateTimeChanges() {
        let scene = GameScene(size: CGSize(width: 390, height: 844))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        scene.didMove(to: view)

        scene.gameSetupComplete = true
        scene.gameStarted = true

        scene.update(1.0)

        XCTAssertEqual(scene.lastUpdateTime, 1.0)
    }

    func test_givenBoostHeldAndZeroScore_whenUpdateCalled_thenBoostDisengages() {
        let scene = GameScene(size: CGSize(width: 390, height: 844))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        scene.didMove(to: view)

        scene.gameSetupComplete = true
        scene.gameStarted = true
        scene.score = 0
        scene.isBoostHeld = true

        scene.update(1.0)

        XCTAssertFalse(scene.isBoostHeld)
    }

    func test_givenSceneShutdown_whenShutdownCalledTwice_thenRemainsIdempotent() {
        let scene = GameScene(size: CGSize(width: 390, height: 844))

        scene.shutdown()
        scene.shutdown()

        XCTAssertTrue(true) // verifies no crash and idempotent guard path
    }

    func test_givenChallengeModeScene_whenDidMove_thenSpawnsNemesisWithThousandScore() {
        let scene = GameScene(size: CGSize(width: 390, height: 844))
        scene.scaleMode = .resizeFill
        scene.gameMode = .challenge
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))

        scene.didMove(to: view)

        XCTAssertEqual(scene.bots.count, scene.totalBots + 1)
        let nemesisBots = scene.bots.filter { $0.isNemesis }
        XCTAssertEqual(nemesisBots.count, 1)
        XCTAssertEqual(nemesisBots.first?.score, scene.challengeNemesisScore)
        XCTAssertEqual(nemesisBots.first?.personality, .nemesis)
    }

    func test_givenVeryHighScore_whenUpdatingScene_thenHistoryBuffersStayBounded() {
        let scene = GameScene(size: CGSize(width: 390, height: 844))
        scene.scaleMode = .resizeFill
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))

        scene.didMove(to: view)
        scene.score = 1_500
        scene.updateSpeedForScore()
        scene.gameSetupComplete = true
        scene.gameStarted = true

        for tick in 1...60 {
            scene.update(TimeInterval(tick) / 60.0)
        }

        XCTAssertEqual(scene.bodySegments.count, scene.targetBodyCount)
        XCTAssertEqual(scene.bodyPositionCache.count, scene.bodySegments.count)
        XCTAssertLessThanOrEqual(scene.positionHistory.count, scene.positionHistory.capacity)
        XCTAssertGreaterThan(scene.positionHistory.capacity, 0)
    }
}
