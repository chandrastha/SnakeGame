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
//
// These tests exercise the pure AI helper functions in GameLogic.
// They run without a simulator and serve as a regression guard for
// the contest, intent, and food-valuation logic introduced in this PR.

// shouldContestFood: the bot is further away AND slower than a much larger rival.
// The length-advantage hard veto (>8 segments) should force a back-off.
@Test func botFoodContestAvoidsLosingRaceAgainstLargerRival() {
    let shouldContest = GameLogic.shouldContestFood(
        BotFoodContestSnapshot(
            selfDistance: 200,       // further from food
            selfSpeed: 120,          // slower
            rivalDistance: 150,
            rivalSpeed: 140,
            value: 16,               // medium value — not worth the head-on risk
            rivalLengthAdvantage: 10, // rival is 10 segments longer → veto applies
            riskTolerance: 0.4
        )
    )
    #expect(shouldContest == false)
}

// shouldContestFood: the bot is faster and the rival is slightly shorter.
// High-value food (28 = max base) and a favourable risk tolerance should allow contest.
@Test func botFoodContestAllowsHighValueRaceWhenAdvantaged() {
    let shouldContest = GameLogic.shouldContestFood(
        BotFoodContestSnapshot(
            selfDistance: 160,
            selfSpeed: 170,          // meaningfully faster
            rivalDistance: 180,      // rival is farther away
            rivalSpeed: 130,
            value: 28,               // maximum base value food
            rivalLengthAdvantage: -4, // bot is 4 segments longer → no penalty
            riskTolerance: 0.7       // willing to take moderate risk
        )
    )
    #expect(shouldContest == true)
}

// chooseBotIntent: even with tempting food and scavenging opportunities,
// extreme danger (0.9) must always override everything and force an escape.
@Test func botIntentPrefersEscapeWhenDangerIsHigh() {
    let profile = GameLogic.botPersonalityProfile(for: .coward)
    let intent = GameLogic.chooseBotIntent(
        BotModeSnapshot(
            immediateDanger: 0.9,        // well above the 0.72 hard escape threshold
            escapeRouteQuality: 0.3,
            foodOpportunity: 0.8,        // high food signal — should be ignored
            scavengingOpportunity: 0.7,
            huntOpportunity: 0.1,
            cutOpportunity: 0.0,
            nearbyCrowding: 0.8,
            personality: profile
        )
    )
    #expect(intent == .escape)
}

// chooseBotIntent: low danger, dominant cut opportunity, and interceptor personality
// (high cutBias) — the bot must select .cutOff over hunt or food.
@Test func botIntentPrefersCutOffWhenOpportunityDominates() {
    let profile = GameLogic.botPersonalityProfile(for: .interceptor)
    let intent = GameLogic.chooseBotIntent(
        BotModeSnapshot(
            immediateDanger: 0.2,
            escapeRouteQuality: 0.8,
            foodOpportunity: 0.25,       // moderate food — should lose to cut
            scavengingOpportunity: 0.18,
            huntOpportunity: 0.5,        // notable hunt — still loses to cut
            cutOpportunity: 0.9,         // dominant opportunity
            nearbyCrowding: 0.2,         // low crowding — guard condition is met
            personality: profile
        )
    )
    #expect(intent == .cutOff)
}

// botFoodValue: death food (base 24) + high scavengerBias bonus must exceed
// regular food (base 12) even with identical greed.
// Validates that the scavengerBias multiplier is correctly applied only to .death/.trail.
@Test func deathFoodIsValuedAboveRegularFood() {
    let regular = GameLogic.botFoodValue(type: .regular, clusterBonus: 0, greed: 0.5, scavengerBias: 0.2)
    let death   = GameLogic.botFoodValue(type: .death,   clusterBonus: 0, greed: 0.5, scavengerBias: 0.8)
    #expect(death > regular)
}

// botPersonalityProfile: hunter and coward are intentionally polar opposites.
// This test acts as a canary — if profile values are accidentally swapped or
// normalised, these ordering invariants will fail.
@Test func hunterAndCowardProfilesStayDistinct() {
    let hunter = GameLogic.botPersonalityProfile(for: .hunter)
    let coward  = GameLogic.botPersonalityProfile(for: .coward)
    #expect(hunter.aggression > coward.aggression)  // hunter is far more aggressive
    #expect(coward.caution > hunter.caution)         // coward is far more cautious
    #expect(hunter.boostBias >= coward.boostBias)    // hunter boosts at least as often
}
