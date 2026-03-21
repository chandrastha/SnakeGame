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
        XCTAssertEqual(GameLogic.calculateSpeed(score: 200), 130)
    }

    func test_givenBoostingBotSpeed_whenCalculatingPlayerBoost_thenMaintainsOnePointFiveTimesLead() {
        let boostedSpeed = GameLogic.boostedPlayerSpeed(
            baseSpeed: 120,
            fastestBoostingBotSpeed: 180
        )
        XCTAssertEqual(boostedSpeed, 270, accuracy: 0.001)
    }

    func test_givenExistingScores_whenProcessingLeaderboard_thenReturnsSortedTopTen() {
        let existing = Array(stride(from: 10, through: 120, by: 10))
        let output = GameLogic.processLeaderboardEntry(score: 999, existing: existing)
        XCTAssertEqual(output.count, 10)
        XCTAssertEqual(output.first, 999)
        XCTAssertEqual(output, output.sorted(by: >))
    }

    func test_givenPlayerOutsideTopFour_whenBuildingLeaderboard_thenIncludesTopFourPlusCurrentPlayer() {
        let entries = [
            LeaderboardScoreEntry(name: "A", score: 90, isCurrentPlayer: false),
            LeaderboardScoreEntry(name: "B", score: 80, isCurrentPlayer: false),
            LeaderboardScoreEntry(name: "C", score: 70, isCurrentPlayer: false),
            LeaderboardScoreEntry(name: "D", score: 60, isCurrentPlayer: false),
            LeaderboardScoreEntry(name: "Me", score: 15, isCurrentPlayer: true)
        ]

        let visible = GameLogic.leaderboardDisplayEntries(from: entries)

        XCTAssertEqual(visible.count, 5)
        XCTAssertEqual(visible.prefix(4).map(\.name), ["A", "B", "C", "D"])
        XCTAssertEqual(visible.last?.name, "Me")
        XCTAssertEqual(visible.last?.rank, 5)
    }

    func test_givenPlayerInsideTopFour_whenBuildingLeaderboard_thenExpandsToTopFive() {
        let entries = [
            LeaderboardScoreEntry(name: "A", score: 90, isCurrentPlayer: false),
            LeaderboardScoreEntry(name: "Me", score: 85, isCurrentPlayer: true),
            LeaderboardScoreEntry(name: "C", score: 70, isCurrentPlayer: false),
            LeaderboardScoreEntry(name: "D", score: 60, isCurrentPlayer: false),
            LeaderboardScoreEntry(name: "E", score: 50, isCurrentPlayer: false),
            LeaderboardScoreEntry(name: "F", score: 40, isCurrentPlayer: false)
        ]

        let visible = GameLogic.leaderboardDisplayEntries(from: entries)

        XCTAssertEqual(visible.count, 5)
        XCTAssertEqual(visible.map(\.rank), [1, 2, 3, 4, 5])
        XCTAssertEqual(visible[1].name, "Me")
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
            XCTAssertGreaterThan(profile.emergencyTurnMultiplier, 0)
            XCTAssertGreaterThan(profile.escapeSpeedReductionCap, 0)
            XCTAssertGreaterThanOrEqual(profile.corridorPreference, 0)
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

    func test_givenLowClearanceNonEscapePath_whenPreferringEscape_thenReturnsTrue() {
        XCTAssertTrue(
            GameLogic.shouldPreferEscape(
                nonEscapeClearanceScore: 0.42,
                bestNonEscapeScore: 30,
                bestEscapeScore: 28,
                immediateDanger: 0.60
            )
        )
    }

    func test_givenWideCorridorAndEnoughMediumHeadings_whenCheckingViableEscapeCorridor_thenReturnsTrue() {
        XCTAssertTrue(GameLogic.hasViableEscapeCorridor(widestSafeSpanDegrees: 45, mediumRangeHeadingCount: 3))
        XCTAssertFalse(GameLogic.hasViableEscapeCorridor(widestSafeSpanDegrees: 15, mediumRangeHeadingCount: 2))
    }

    func test_givenEscapeIntentAndHighTurnDemand_whenCalculatingSteeringMultiplier_thenReducesSpeedMoreThanRoam() {
        let roamMultiplier = GameLogic.botSteeringSpeedMultiplier(
            turnDemand: 1.0,
            immediateDanger: 0.8,
            intent: .roam,
            isCircled: false,
            baseReductionCap: 0.18,
            challengeReductionCap: 0.12,
            isChallengeOrNemesis: false
        )
        let escapeMultiplier = GameLogic.botSteeringSpeedMultiplier(
            turnDemand: 1.0,
            immediateDanger: 0.8,
            intent: .escape,
            isCircled: true,
            baseReductionCap: 0.18,
            challengeReductionCap: 0.12,
            isChallengeOrNemesis: false
        )

        XCTAssertLessThan(escapeMultiplier, roamMultiplier)
    }
}
