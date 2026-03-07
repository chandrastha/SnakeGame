import XCTest
import SpriteKit
@testable import SnakeGame

final class GameSceneIntegrationTests: XCTestCase {
    private var originalCoinBalance: Int = 0

    override func setUp() {
        super.setUp()
        originalCoinBalance = CoinManager.shared.balance
        CoinManager.shared.balance = 0
    }

    override func tearDown() {
        CoinManager.shared.balance = originalCoinBalance
        super.tearDown()
    }

    private func makeScene(mode: GameMode = .offline) -> GameScene {
        let scene = GameScene(size: CGSize(width: 390, height: 844))
        scene.scaleMode = .resizeFill
        scene.gameMode = mode
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        scene.didMove(to: view)
        return scene
    }

    // MARK: - Integration Tests: SpriteKit + SwiftUI Bridge Points

    func test_givenFreshScene_whenDidMove_thenInitialStateIsPrepared() {
        let scene = makeScene()

        XCTAssertFalse(scene.isGameOver)
        XCTAssertEqual(scene.score, 0)
        XCTAssertGreaterThan(scene.foodItems.count, 0)
    }

    func test_givenStartedScene_whenUpdateCalled_thenLastUpdateTimeChanges() {
        let scene = makeScene()

        scene.gameSetupComplete = true
        scene.gameStarted = true

        scene.update(1.0)

        XCTAssertEqual(scene.lastUpdateTime, 1.0)
    }

    func test_givenBoostHeldAndZeroScore_whenUpdateCalled_thenBoostDisengages() {
        let scene = makeScene()

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
        let scene = makeScene(mode: .challenge)

        XCTAssertEqual(scene.bots.count, scene.totalBots + 1)
        let nemesisBots = scene.bots.filter { $0.isNemesis }
        XCTAssertEqual(nemesisBots.count, 1)
        XCTAssertEqual(nemesisBots.first?.score, scene.challengeNemesisScore)
        XCTAssertEqual(nemesisBots.first?.personality, .nemesis)
    }

    func test_givenVeryHighScore_whenUpdatingScene_thenHistoryBuffersStayBounded() {
        let scene = makeScene()
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

    func test_givenSessionCoins_whenCompletingSpecialMode_thenBanksThemThroughFinalizePath() {
        CoinManager.shared.balance = 5
        let scene = makeScene(mode: .mazeHunt)
        scene.sessionCoinsEarned = 7

        scene.completeSpecialMode(success: true)

        XCTAssertTrue(scene.isGameOver)
        XCTAssertEqual(scene.lastRunCoinsAwarded, 7)
        XCTAssertEqual(scene.sessionCoinsEarned, 0)
        XCTAssertEqual(CoinManager.shared.balance, 12)
    }

    func test_givenBankedRunCoins_whenShowingGameOver_thenOverlayDisplaysRunBankAndReviveState() {
        CoinManager.shared.balance = 40
        let scene = makeScene()
        scene.sessionCoinsEarned = 15
        scene.finalizeRunEconomy()

        scene.showGameOverScreen()

        let texts = scene.gameOverOverlay?.children.compactMap { ($0 as? SKLabelNode)?.text } ?? []
        XCTAssertTrue(texts.contains("Run coins  +15"))
        XCTAssertTrue(texts.contains("Bank total  55"))
        XCTAssertTrue(texts.contains("Revive 50 🪙  •  After revive 5"))
    }

    func test_givenSuccessfulSpecialModeCompletion_whenShowingOverlay_thenUsesVictoryStateWithoutRevive() {
        CoinManager.shared.balance = 100
        let scene = makeScene(mode: .snakeRace)

        scene.completeSpecialMode(success: true)
        scene.showGameOverScreen()

        let texts = scene.gameOverOverlay?.children.compactMap { ($0 as? SKLabelNode)?.text } ?? []
        XCTAssertTrue(texts.contains("VICTORY"))
        XCTAssertTrue(texts.contains("Run completed successfully"))
        XCTAssertFalse((scene.gameOverOverlay?.children.compactMap(\.name) ?? []).contains("reviveButton"))
    }

    func test_givenBotEatsUtilityPickup_whenCheckingCollision_thenBotScoreDoesNotIncrease() {
        let scene = makeScene()
        guard !scene.bots.isEmpty else {
            XCTFail("Expected bots to be created for offline scene")
            return
        }

        let botIndex = 0
        let startingScore = scene.bots[botIndex].score
        let startingLength = scene.bots[botIndex].bodyLength
        let food = SKNode()
        food.position = scene.bots[botIndex].position
        scene.addChild(food)
        scene.foodItems.append(food)
        scene.foodTypes.append(.magnet)

        scene.checkBotFoodCollision(botIndex)

        XCTAssertEqual(scene.bots[botIndex].score, startingScore)
        XCTAssertEqual(scene.bots[botIndex].bodyLength, startingLength)
    }

    func test_givenShrinkReward_whenApplied_thenScoreAndBodyLengthContractTogether() {
        let scene = makeScene()
        scene.score = 100
        scene.updateSpeedForScore()

        scene.applyRunReward(GameLogic.reward(for: .shrink(currentScore: scene.score)))

        XCTAssertEqual(scene.score, 90)
        XCTAssertEqual(scene.bodySegments.count, scene.targetBodyCount)
    }
}
