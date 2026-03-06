import XCTest
import CoreGraphics
@testable import SnakeGame

final class GameLogicTests: XCTestCase {

    // MARK: - Unit Tests: Math + Collision

    func test_givenPointInsideArena_whenCheckingBoundary_thenReturnsFalse() {
        let result = GameLogic.isOutsideArena(
            point: CGPoint(x: 200, y: 200),
            radius: 10,
            arenaMinX: 0, arenaMaxX: 400,
            arenaMinY: 0, arenaMaxY: 400
        )
        XCTAssertFalse(result)
    }

    func test_givenUninitializedArena_whenCheckingBoundary_thenReturnsFalse() {
        let result = GameLogic.isOutsideArena(
            point: .zero,
            radius: 10,
            arenaMinX: 0, arenaMaxX: 0,
            arenaMinY: 0, arenaMaxY: 0
        )
        XCTAssertFalse(result)
    }

    func test_givenOverlappingCircles_whenCheckingOverlap_thenReturnsTrue() {
        XCTAssertTrue(GameLogic.circlesOverlap(.zero, CGPoint(x: 4, y: 0), combinedRadius: 5))
    }

    func test_givenValueOutsideRange_whenClamp01_thenClampsToBounds() {
        XCTAssertEqual(GameLogic.clamp01(-0.2), 0)
        XCTAssertEqual(GameLogic.clamp01(1.2), 1)
    }

    func test_givenAngleAndDistance_whenProjectingPoint_thenComputesExpectedPoint() {
        let p = GameLogic.projectedPoint(from: .zero, angle: .pi / 2, distance: 10)
        XCTAssertEqual(p.x, 0, accuracy: 0.001)
        XCTAssertEqual(p.y, 10, accuracy: 0.001)
    }

    func test_givenWrappedAngles_whenShortestAngleDiff_thenReturnsNormalizedDelta() {
        let delta = GameLogic.shortestAngleDiff(from: .pi - 0.1, to: -.pi + 0.1)
        XCTAssertEqual(delta, 0.2, accuracy: 0.001)
    }

    func test_givenZeroDesiredClearance_whenClearanceScore_thenReturnsOne() {
        XCTAssertEqual(GameLogic.clearanceScore(minClearance: 5, desired: 0), 1)
    }

    func test_givenPointNearSegment_whenDistanceFromPoint_thenReturnsPerpendicularDistance() {
        let d = GameLogic.distanceFromPoint(CGPoint(x: 5, y: 3), toSegment: CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0))
        XCTAssertEqual(d, 3, accuracy: 0.001)
    }

    // MARK: - Unit Tests: Business Logic

    func test_givenHighScore_whenCalculateSpeed_thenCapsAtMaximum() {
        XCTAssertEqual(GameLogic.calculateSpeed(score: 200), 300)
    }

    func test_givenExistingScores_whenProcessingLeaderboard_thenReturnsSortedTopTen() {
        let existing = Array(stride(from: 10, through: 120, by: 10))
        let output = GameLogic.processLeaderboardEntry(score: 999, existing: existing)
        XCTAssertEqual(output.count, 10)
        XCTAssertEqual(output.first, 999)
        XCTAssertEqual(output, output.sorted(by: >))
    }

    func test_givenBodySegmentsBeyondSkip_whenHeadTouchesTail_thenDetectsCollision() {
        var segments = Array(repeating: CGPoint(x: 999, y: 999), count: 20)
        segments[19] = CGPoint(x: 1, y: 1)
        XCTAssertTrue(GameLogic.headCollidesWithBody(head: .zero, segments: segments, combinedRadius: 3, skip: 10))
    }

    // MARK: - Unit Tests: Bot Logic

    func test_givenEachPersonalityKind_whenLoadingProfile_thenReturnsDistinctProfile() {
        for kind in BotPersonalityKind.allCases {
            let profile = GameLogic.botPersonalityProfile(for: kind)
            XCTAssertGreaterThan(profile.replanInterval, 0)
            XCTAssertGreaterThan(profile.foodSearchRadius, 0)
        }
    }

    func test_givenDeathFoodAndScavengerBias_whenScoringFood_thenOutscoresRegularFood() {
        let death = GameLogic.botFoodValue(type: .death, clusterBonus: 0.4, greed: 0.7, scavengerBias: 1.0)
        let regular = GameLogic.botFoodValue(type: .regular, clusterBonus: 0.4, greed: 0.7, scavengerBias: 1.0)
        XCTAssertGreaterThan(death, regular)
    }

    func test_givenLargeRivalAdvantage_whenContestingFood_thenReturnsFalse() {
        let snapshot = BotFoodContestSnapshot(
            selfDistance: 300,
            selfSpeed: 100,
            rivalDistance: 150,
            rivalSpeed: 150,
            value: 28,
            rivalLengthAdvantage: 12,
            riskTolerance: 1.0
        )
        XCTAssertFalse(GameLogic.shouldContestFood(snapshot))
    }

    func test_givenHighDanger_whenChoosingIntent_thenReturnsEscape() {
        let snapshot = BotModeSnapshot(
            immediateDanger: 0.9,
            escapeRouteQuality: 0.2,
            foodOpportunity: 1,
            scavengingOpportunity: 1,
            huntOpportunity: 1,
            cutOpportunity: 1,
            nearbyCrowding: 0.1,
            personality: GameLogic.botPersonalityProfile(for: .opportunist)
        )
        XCTAssertEqual(GameLogic.chooseBotIntent(snapshot), .escape)
    }

    func test_givenLowDangerAndFoodOpportunity_whenChoosingIntent_thenReturnsForage() {
        let snapshot = BotModeSnapshot(
            immediateDanger: 0.1,
            escapeRouteQuality: 0.9,
            foodOpportunity: 0.4,
            scavengingOpportunity: 0.1,
            huntOpportunity: 0.1,
            cutOpportunity: 0.1,
            nearbyCrowding: 0.3,
            personality: GameLogic.botPersonalityProfile(for: .coward)
        )
        XCTAssertEqual(GameLogic.chooseBotIntent(snapshot), .forage)
    }
}
