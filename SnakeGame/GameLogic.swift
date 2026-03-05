// GameLogic.swift
// Pure helper functions with no SpriteKit or UIKit dependencies.
// Extracted from GameScene so they can be unit tested.

import CoreGraphics

enum BotIntent: String, CaseIterable {
    case forage
    case scavenge
    case hunt
    case cutOff
    case escape
    case roam
}

enum BotPersonalityKind: String, CaseIterable {
    case scavenger
    case hunter
    case coward
    case opportunist
    case sprinter
    case vulture
    case interceptor
    case trickster
}

struct BotPersonalityProfile {
    let aggression: CGFloat
    let caution: CGFloat
    let greed: CGFloat
    let scavengerBias: CGFloat
    let cutBias: CGFloat
    let boostBias: CGFloat
    let unpredictability: CGFloat
    let turnRateMultiplier: CGFloat
    let horizonMultiplier: CGFloat
    let cruiseSpeedMultiplier: CGFloat
    let replanInterval: CGFloat
    let desiredClearance: CGFloat
    let foodSearchRadius: CGFloat
    let targetStickiness: CGFloat
}

struct BotModeSnapshot {
    let immediateDanger: CGFloat
    let escapeRouteQuality: CGFloat
    let foodOpportunity: CGFloat
    let scavengingOpportunity: CGFloat
    let huntOpportunity: CGFloat
    let cutOpportunity: CGFloat
    let nearbyCrowding: CGFloat
    let personality: BotPersonalityProfile
}

struct BotFoodContestSnapshot {
    let selfDistance: CGFloat
    let selfSpeed: CGFloat
    let rivalDistance: CGFloat
    let rivalSpeed: CGFloat
    let value: CGFloat
    let rivalLengthAdvantage: CGFloat
    let riskTolerance: CGFloat
}

enum GameLogic {

    // MARK: - Wall Collision

    /// Returns true if a circle of `radius` centred at `point` overlaps the arena boundary.
    static func isOutsideArena(
        point: CGPoint,
        radius: CGFloat,
        arenaMinX: CGFloat, arenaMaxX: CGFloat,
        arenaMinY: CGFloat, arenaMaxY: CGFloat
    ) -> Bool {
        guard arenaMaxX > 0, arenaMaxY > 0 else { return false }
        return point.x - radius <= arenaMinX || point.x + radius >= arenaMaxX ||
               point.y - radius <= arenaMinY || point.y + radius >= arenaMaxY
    }

    // MARK: - Circle Collision

    /// Returns true if two circles (defined by their centres and combined radius) overlap.
    static func circlesOverlap(
        _ a: CGPoint,
        _ b: CGPoint,
        combinedRadius: CGFloat
    ) -> Bool {
        hypot(a.x - b.x, a.y - b.y) < combinedRadius
    }

    static func clamp01(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    static func projectedPoint(from start: CGPoint, angle: CGFloat, distance: CGFloat) -> CGPoint {
        CGPoint(x: start.x + cos(angle) * distance,
                y: start.y + sin(angle) * distance)
    }

    static func shortestAngleDiff(from current: CGFloat, to target: CGFloat) -> CGFloat {
        var diff = target - current
        while diff > .pi { diff -= 2 * .pi }
        while diff < -.pi { diff += 2 * .pi }
        return diff
    }

    static func clearanceScore(minClearance: CGFloat, desired: CGFloat) -> CGFloat {
        guard desired > 0 else { return 1 }
        return clamp01(minClearance / desired)
    }

    static func distanceFromPoint(_ point: CGPoint, toSegment start: CGPoint, _ end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSq = dx * dx + dy * dy
        guard lengthSq > 0 else { return hypot(point.x - start.x, point.y - start.y) }

        let t = clamp01(((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSq)
        let projection = CGPoint(x: start.x + dx * t, y: start.y + dy * t)
        return hypot(point.x - projection.x, point.y - projection.y)
    }

    // MARK: - Speed Calculation

    /// Returns the move speed for the given score.
    /// Mirrors the formula in GameScene.updateSpeedForScore().
    static func calculateSpeed(
        score: Int,
        baseMoveSpeed: CGFloat = 150,
        maxMoveSpeed:  CGFloat = 300
    ) -> CGFloat {
        let speed = min(baseMoveSpeed + CGFloat(score) * 2.5, maxMoveSpeed)
        return speed
    }

    // MARK: - Leaderboard

    /// Inserts `score` into `existing`, sorts descending, and returns the top `maxEntries`.
    static func processLeaderboardEntry(
        score: Int,
        existing: [Int],
        maxEntries: Int = 10
    ) -> [Int] {
        let updated = (existing + [score]).sorted(by: >)
        return Array(updated.prefix(maxEntries))
    }

    // MARK: - Self Collision

    /// Returns true if `head` is within `combinedRadius` of any element in `segments`,
    /// skipping the first `skip` elements (nearest segments cannot collide).
    static func headCollidesWithBody(
        head: CGPoint,
        segments: [CGPoint],
        combinedRadius: CGFloat,
        skip: Int
    ) -> Bool {
        for (i, seg) in segments.enumerated() {
            guard i >= skip else { continue }
            if hypot(head.x - seg.x, head.y - seg.y) < combinedRadius { return true }
        }
        return false
    }

    // MARK: - Bot AI

    static func botPersonalityProfile(for kind: BotPersonalityKind) -> BotPersonalityProfile {
        switch kind {
        case .scavenger:
            return BotPersonalityProfile(
                aggression: 0.35, caution: 0.65, greed: 0.78, scavengerBias: 1.00,
                cutBias: 0.25, boostBias: 0.40, unpredictability: 0.18,
                turnRateMultiplier: 1.02, horizonMultiplier: 1.08,
                cruiseSpeedMultiplier: 0.98, replanInterval: 0.22,
                desiredClearance: 92, foodSearchRadius: 720, targetStickiness: 0.62
            )
        case .hunter:
            return BotPersonalityProfile(
                aggression: 0.95, caution: 0.30, greed: 0.45, scavengerBias: 0.30,
                cutBias: 0.68, boostBias: 0.78, unpredictability: 0.12,
                turnRateMultiplier: 1.08, horizonMultiplier: 1.02,
                cruiseSpeedMultiplier: 1.05, replanInterval: 0.18,
                desiredClearance: 72, foodSearchRadius: 620, targetStickiness: 0.78
            )
        case .coward:
            return BotPersonalityProfile(
                aggression: 0.18, caution: 0.98, greed: 0.35, scavengerBias: 0.25,
                cutBias: 0.10, boostBias: 0.72, unpredictability: 0.15,
                turnRateMultiplier: 1.15, horizonMultiplier: 1.22,
                cruiseSpeedMultiplier: 1.00, replanInterval: 0.16,
                desiredClearance: 116, foodSearchRadius: 640, targetStickiness: 0.55
            )
        case .opportunist:
            return BotPersonalityProfile(
                aggression: 0.58, caution: 0.55, greed: 0.65, scavengerBias: 0.58,
                cutBias: 0.52, boostBias: 0.58, unpredictability: 0.20,
                turnRateMultiplier: 1.06, horizonMultiplier: 1.00,
                cruiseSpeedMultiplier: 1.01, replanInterval: 0.20,
                desiredClearance: 84, foodSearchRadius: 690, targetStickiness: 0.66
            )
        case .sprinter:
            return BotPersonalityProfile(
                aggression: 0.70, caution: 0.42, greed: 0.58, scavengerBias: 0.38,
                cutBias: 0.48, boostBias: 0.98, unpredictability: 0.16,
                turnRateMultiplier: 1.18, horizonMultiplier: 0.94,
                cruiseSpeedMultiplier: 1.10, replanInterval: 0.16,
                desiredClearance: 78, foodSearchRadius: 650, targetStickiness: 0.60
            )
        case .vulture:
            return BotPersonalityProfile(
                aggression: 0.48, caution: 0.62, greed: 0.72, scavengerBias: 0.96,
                cutBias: 0.38, boostBias: 0.64, unpredictability: 0.18,
                turnRateMultiplier: 1.00, horizonMultiplier: 1.10,
                cruiseSpeedMultiplier: 1.00, replanInterval: 0.22,
                desiredClearance: 90, foodSearchRadius: 760, targetStickiness: 0.72
            )
        case .interceptor:
            return BotPersonalityProfile(
                aggression: 0.82, caution: 0.46, greed: 0.42, scavengerBias: 0.20,
                cutBias: 0.92, boostBias: 0.70, unpredictability: 0.10,
                turnRateMultiplier: 1.12, horizonMultiplier: 1.15,
                cruiseSpeedMultiplier: 1.03, replanInterval: 0.18,
                desiredClearance: 76, foodSearchRadius: 610, targetStickiness: 0.80
            )
        case .trickster:
            return BotPersonalityProfile(
                aggression: 0.60, caution: 0.44, greed: 0.55, scavengerBias: 0.42,
                cutBias: 0.58, boostBias: 0.62, unpredictability: 0.34,
                turnRateMultiplier: 1.16, horizonMultiplier: 0.98,
                cruiseSpeedMultiplier: 1.02, replanInterval: 0.19,
                desiredClearance: 80, foodSearchRadius: 660, targetStickiness: 0.50
            )
        }
    }

    static func botFoodValue(
        type: FoodType,
        clusterBonus: CGFloat,
        greed: CGFloat,
        scavengerBias: CGFloat
    ) -> CGFloat {
        let base: CGFloat
        switch type {
        case .regular:    base = 12
        case .trail:      base = 6
        case .death:      base = 24
        case .shield:     base = 11
        case .multiplier: base = 13
        case .magnet:     base = 9
        case .ghost:      base = 10
        case .shrink:     base = 3
        }

        var value = base * (1 + clusterBonus * 0.28)
        value *= 1 + greed * 0.22
        if type == .death || type == .trail {
            value *= 1 + scavengerBias * 0.45
        }
        return value
    }

    static func shouldContestFood(_ snapshot: BotFoodContestSnapshot) -> Bool {
        let selfETA = snapshot.selfDistance / max(snapshot.selfSpeed, 1)
        let rivalETA = snapshot.rivalDistance / max(snapshot.rivalSpeed, 1)
        let valueFactor = clamp01(snapshot.value / 28)
        let riskPenalty = max(0, snapshot.rivalLengthAdvantage) * 0.03
        let margin = 1.0 + snapshot.riskTolerance * 0.20 + valueFactor * 0.12 - riskPenalty

        if snapshot.rivalLengthAdvantage > 8 && rivalETA < selfETA {
            return false
        }
        return selfETA <= rivalETA * max(0.72, margin)
    }

    static func chooseBotIntent(_ snapshot: BotModeSnapshot) -> BotIntent {
        let danger = clamp01(snapshot.immediateDanger)
        let food = clamp01(snapshot.foodOpportunity)
        let scavenging = clamp01(snapshot.scavengingOpportunity)
        let hunt = clamp01(snapshot.huntOpportunity)
        let cut = clamp01(snapshot.cutOpportunity)
        let escapeRoute = clamp01(snapshot.escapeRouteQuality)
        let crowding = clamp01(snapshot.nearbyCrowding)
        let profile = snapshot.personality

        if danger > 0.72 || (danger > 0.45 && escapeRoute < 0.40) {
            return .escape
        }

        if cut > max(hunt, food) * (0.88 - profile.cutBias * 0.14) &&
            cut > 0.42 &&
            crowding < 0.78 {
            return .cutOff
        }

        if scavenging > max(food, hunt) * (0.90 - profile.scavengerBias * 0.12) &&
            scavenging > 0.34 {
            return .scavenge
        }

        if hunt > max(food, scavenging) * (0.94 - profile.aggression * 0.16) &&
            hunt > 0.36 {
            return .hunt
        }

        if food > 0.16 {
            return .forage
        }

        return danger > 0.28 ? .escape : .roam
    }
}
