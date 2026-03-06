import XCTest
import CoreGraphics
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
}
