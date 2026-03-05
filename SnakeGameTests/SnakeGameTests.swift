//
//  SnakeGameTests.swift
//  SnakeGameTests
//
//  Created by Chandra Shrestha on 2026-02-24.
//

import Testing
import CoreGraphics
@testable import SnakeGame

// MARK: - Enum Tests

@Test func gameModeHasBothCases() {
    let modes: [GameMode] = [.online, .offline]
    #expect(modes.count == 2)
}

// MARK: - Speed Progression Tests

@Test func speedAtScoreZeroIsBase() {
    #expect(GameLogic.calculateSpeed(score: 0) == 150)
}

@Test func speedIncreasesWithScore() {
    let s20 = GameLogic.calculateSpeed(score: 20)
    #expect(s20 == 150 + 20 * 2.5) // 200
}

@Test func speedIsCappedAtMax() {
    // score 60 → 150 + 60×2.5 = 300 (exactly at cap)
    #expect(GameLogic.calculateSpeed(score: 60) == 300)
    // score 100 → would be 400, capped at 300
    #expect(GameLogic.calculateSpeed(score: 100) == 300)
}

// MARK: - Leaderboard Tests

@Test func leaderboardInsertsAndSortsDescending() {
    let result = GameLogic.processLeaderboardEntry(score: 50, existing: [30, 10, 70])
    #expect(result == [70, 50, 30, 10])
}

@Test func leaderboardKeepsTop10Only() {
    let existing = Array(1...10).map { $0 * 10 } // [10, 20, ..., 100]
    let result = GameLogic.processLeaderboardEntry(score: 999, existing: existing)
    #expect(result.count == 10)
    #expect(result.first == 999)
    #expect(result.last == 20) // lowest entry (10) is dropped
}

@Test func leaderboardWorksWhenEmpty() {
    let result = GameLogic.processLeaderboardEntry(score: 42, existing: [])
    #expect(result == [42])
}

@Test func leaderboardIsAlwaysSortedDescending() {
    let result = GameLogic.processLeaderboardEntry(score: 5, existing: [3, 8, 1, 9, 2])
    #expect(result == result.sorted(by: >))
}

// MARK: - Wall Collision Tests

@Test func wallCollisionDetectedOnLeftEdge() {
    // Point at x=5, radius=20 → 5-20 = -15 <= arenaMinX(0) → collision
    let hit = GameLogic.isOutsideArena(
        point: CGPoint(x: 5, y: 200),
        radius: 20,
        arenaMinX: 0, arenaMaxX: 400,
        arenaMinY: 0, arenaMaxY: 800
    )
    #expect(hit == true)
}

@Test func wallCollisionNotFiredWhenInsideArena() {
    let hit = GameLogic.isOutsideArena(
        point: CGPoint(x: 200, y: 400),
        radius: 20,
        arenaMinX: 0, arenaMaxX: 400,
        arenaMinY: 0, arenaMaxY: 800
    )
    #expect(hit == false)
}

@Test func wallCollisionDetectedOnRightEdge() {
    // Point at x=395, radius=20 → 395+20=415 >= arenaMaxX(400) → collision
    let hit = GameLogic.isOutsideArena(
        point: CGPoint(x: 395, y: 400),
        radius: 20,
        arenaMinX: 0, arenaMaxX: 400,
        arenaMinY: 0, arenaMaxY: 800
    )
    #expect(hit == true)
}

@Test func wallCollisionReturnsFalseForUninitializedArena() {
    // Guard: arenaMaxX == 0 means scene size not yet set
    let hit = GameLogic.isOutsideArena(
        point: CGPoint(x: 0, y: 0),
        radius: 20,
        arenaMinX: 0, arenaMaxX: 0,
        arenaMinY: 0, arenaMaxY: 0
    )
    #expect(hit == false)
}

// MARK: - Self Collision Tests

@Test func selfCollisionNotTriggeredForNearBodySegments() {
    // Segments within the skip window should never cause a collision
    let head = CGPoint(x: 0, y: 0)
    let segments = (0..<20).map { CGPoint(x: CGFloat($0) * 5, y: 0) }
    let collides = GameLogic.headCollidesWithBody(
        head: head,
        segments: segments,
        combinedRadius: 34,
        skip: 16 // spacingBetweenSegments(8) × 2
    )
    #expect(collides == false)
}

@Test func selfCollisionDetectedForDistantBodySegment() {
    // Segment at index 20 is very close to head → should collide
    let head = CGPoint(x: 0, y: 0)
    var segments = Array(repeating: CGPoint(x: 9999, y: 9999), count: 21)
    segments[20] = CGPoint(x: 2, y: 0)
    let collides = GameLogic.headCollidesWithBody(
        head: head,
        segments: segments,
        combinedRadius: 34,
        skip: 16
    )
    #expect(collides == true)
}

// MARK: - Circle Overlap Tests

@Test func circlesOverlapWhenClose() {
    let a = CGPoint(x: 0, y: 0)
    let b = CGPoint(x: 10, y: 0)
    #expect(GameLogic.circlesOverlap(a, b, combinedRadius: 15) == true)
}

@Test func circlesDoNotOverlapWhenFar() {
    let a = CGPoint(x: 0, y: 0)
    let b = CGPoint(x: 100, y: 0)
    #expect(GameLogic.circlesOverlap(a, b, combinedRadius: 15) == false)
}

// MARK: - Bot AI Tests

@Test func botFoodContestAvoidsLosingRaceAgainstLargerRival() {
    let shouldContest = GameLogic.shouldContestFood(
        BotFoodContestSnapshot(
            selfDistance: 200,
            selfSpeed: 120,
            rivalDistance: 150,
            rivalSpeed: 140,
            value: 16,
            rivalLengthAdvantage: 10,
            riskTolerance: 0.4
        )
    )
    #expect(shouldContest == false)
}

@Test func botFoodContestAllowsHighValueRaceWhenAdvantaged() {
    let shouldContest = GameLogic.shouldContestFood(
        BotFoodContestSnapshot(
            selfDistance: 160,
            selfSpeed: 170,
            rivalDistance: 180,
            rivalSpeed: 130,
            value: 28,
            rivalLengthAdvantage: -4,
            riskTolerance: 0.7
        )
    )
    #expect(shouldContest == true)
}

@Test func botIntentPrefersEscapeWhenDangerIsHigh() {
    let profile = GameLogic.botPersonalityProfile(for: .coward)
    let intent = GameLogic.chooseBotIntent(
        BotModeSnapshot(
            immediateDanger: 0.9,
            escapeRouteQuality: 0.3,
            foodOpportunity: 0.8,
            scavengingOpportunity: 0.7,
            huntOpportunity: 0.1,
            cutOpportunity: 0.0,
            nearbyCrowding: 0.8,
            personality: profile
        )
    )
    #expect(intent == .escape)
}

@Test func botIntentPrefersCutOffWhenOpportunityDominates() {
    let profile = GameLogic.botPersonalityProfile(for: .interceptor)
    let intent = GameLogic.chooseBotIntent(
        BotModeSnapshot(
            immediateDanger: 0.2,
            escapeRouteQuality: 0.8,
            foodOpportunity: 0.25,
            scavengingOpportunity: 0.18,
            huntOpportunity: 0.5,
            cutOpportunity: 0.9,
            nearbyCrowding: 0.2,
            personality: profile
        )
    )
    #expect(intent == .cutOff)
}

@Test func deathFoodIsValuedAboveRegularFood() {
    let regular = GameLogic.botFoodValue(type: .regular, clusterBonus: 0, greed: 0.5, scavengerBias: 0.2)
    let death = GameLogic.botFoodValue(type: .death, clusterBonus: 0, greed: 0.5, scavengerBias: 0.8)
    #expect(death > regular)
}

@Test func hunterAndCowardProfilesStayDistinct() {
    let hunter = GameLogic.botPersonalityProfile(for: .hunter)
    let coward = GameLogic.botPersonalityProfile(for: .coward)
    #expect(hunter.aggression > coward.aggression)
    #expect(coward.caution > hunter.caution)
    #expect(hunter.boostBias >= coward.boostBias)
}
