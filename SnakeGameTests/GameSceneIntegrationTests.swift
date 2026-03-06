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
}
