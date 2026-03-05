// GameLogic.swift
// Pure helper functions with no SpriteKit or UIKit dependencies.
// Extracted from GameScene so they can be unit tested.

import CoreGraphics

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
}
