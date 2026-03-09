import XCTest
import SpriteKit
@testable import SnakeGame

final class GameSceneIntegrationTests: XCTestCase {

    private func makeRunningScene() -> GameScene {
        let scene = GameScene(size: CGSize(width: 390, height: 844))
        scene.scaleMode = .resizeFill
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        scene.didMove(to: view)
        scene.gameSetupComplete = true
        scene.gameStarted = true
        return scene
    }

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
        let scene = makeRunningScene()

        scene.update(1.0)

        XCTAssertEqual(scene.lastUpdateTime, 1.0)
    }

    func test_givenBoostHeldAndZeroScore_whenUpdateCalled_thenBoostDisengages() {
        let scene = makeRunningScene()
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
        let scene = makeRunningScene()
        scene.score = 1_500
        scene.updateSpeedForScore()

        for tick in 1...60 {
            scene.update(TimeInterval(tick) / 60.0)
        }

        XCTAssertEqual(scene.bodySegments.count, scene.targetBodyCount)
        XCTAssertEqual(scene.bodyPositionCache.count, scene.bodySegments.count)
        XCTAssertLessThanOrEqual(scene.positionHistory.count, scene.positionHistory.capacity)
        XCTAssertGreaterThan(scene.positionHistory.capacity, 0)
    }

    func test_givenFreshScene_whenDidMove_thenCreatesScorePanelAndLeaderboard() {
        let scene = makeRunningScene()

        XCTAssertNotNil(scene.scorePanel)
        XCTAssertNotNil(scene.scoreLabel)
        XCTAssertEqual(scene.scoreLabel.text, "SCORE 0")
        XCTAssertNotNil(scene.miniLeaderboard)
    }

    func test_givenBoostState_whenUpdatingTrailFood_thenOnlyBoostingPlayerLeavesTrail() {
        let scene = makeRunningScene()
        scene.score = 20
        scene.updateSpeedForScore()
        for index in scene.bots.indices {
            scene.bots[index].isBoosting = false
            scene.bots[index].boostCooldown = 999
            scene.bots[index].trailFoodTimer = 0
        }

        for tick in 1...6 {
            scene.update(1.0 + Double(tick) * 0.12)
        }
        XCTAssertEqual(scene.foodTypes.filter { $0 == .trail }.count, 0)

        scene.isBoostHeld = true
        for tick in 7...12 {
            scene.update(1.0 + Double(tick) * 0.12)
        }

        XCTAssertGreaterThan(scene.foodTypes.filter { $0 == .trail }.count, 0)
    }

    func test_givenHeadToHeadCollision_whenUpdatingScene_thenBothPlayerAndBotDie() throws {
        let scene = makeRunningScene()
        scene.ghostActive = false
        scene.ghostTimeLeft = 0

        guard let botIndex = scene.bots.indices.first(where: { scene.bots[$0].isActive && !scene.bots[$0].isDead }) else {
            return XCTFail("Expected an active bot")
        }

        scene.bots[botIndex].position = scene.snakeHead.position
        scene.bots[botIndex].head?.position = scene.snakeHead.position
        scene.bots[botIndex].bodyPositionCache = [scene.snakeHead.position]

        scene.update(1.0)

        XCTAssertTrue(scene.isGameOver)
        XCTAssertTrue(scene.bots[botIndex].isDead)
    }
}
