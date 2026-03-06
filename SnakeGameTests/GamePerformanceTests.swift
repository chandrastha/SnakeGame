import XCTest
import CoreGraphics
import SpriteKit
@testable import SnakeGame

final class GamePerformanceTests: XCTestCase {

    // MARK: - Performance Tests

    func test_givenHighFrequencyMath_whenRunningGameLoopHelpers_thenMeetsPerformanceBudget() {
        measure {
            var accumulator: CGFloat = 0
            for _ in 0..<20_000 {
                accumulator += GameLogic.calculateSpeed(score: 120)
                _ = GameLogic.projectedPoint(from: .zero, angle: accumulator.truncatingRemainder(dividingBy: .pi), distance: 14)
            }
            XCTAssertGreaterThan(accumulator, 0)
        }
    }

    func test_givenRepeatedAIEvaluations_whenChoosingIntent_thenRunsEfficiently() {
        let profile = GameLogic.botPersonalityProfile(for: .opportunist)
        let snapshot = BotModeSnapshot(
            immediateDanger: 0.35,
            escapeRouteQuality: 0.7,
            foodOpportunity: 0.5,
            scavengingOpportunity: 0.2,
            huntOpportunity: 0.45,
            cutOpportunity: 0.31,
            nearbyCrowding: 0.2,
            personality: profile
        )

        measure {
            for _ in 0..<50_000 {
                _ = GameLogic.chooseBotIntent(snapshot)
            }
        }
    }

    func test_givenLongSnakeScene_whenRunningUpdateLoop_thenBodyPathStaysPerformant() {
        let scene = GameScene(size: CGSize(width: 390, height: 844))
        scene.scaleMode = .resizeFill
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        scene.didMove(to: view)
        scene.score = 1_500
        scene.updateSpeedForScore()
        scene.gameSetupComplete = true
        scene.gameStarted = true

        measure {
            for tick in 1...120 {
                scene.update(TimeInterval(tick) / 120.0)
            }
        }

        XCTAssertEqual(scene.bodyPositionCache.count, scene.bodySegments.count)
    }
}
