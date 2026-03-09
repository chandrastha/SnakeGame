// GameLogic.swift
// Pure helper functions with no SpriteKit or UIKit dependencies.
// Extracted from GameScene so they can be unit tested.

import CoreGraphics
import Foundation

// MARK: - Bot Enums

/// The high-level tactical goal a bot is currently pursuing.
/// `chooseBotIntent` selects among these each replan cycle.
enum BotIntent: String, CaseIterable {
    /// Move toward the highest-value nearby food item.
    case forage
    /// Wait near a dying snake to collect its body-trail pellets.
    case scavenge
    /// Chase a shorter or slower snake to force a head-on kill.
    case hunt
    /// Race ahead of another snake and turn across its path to cut it off.
    case cutOff
    /// Flee immediate danger — wall, larger head, or enclosed space.
    case escape
    /// No high-value opportunity; cruise freely while scanning the arena.
    case roam
}

/// Archetype labels used to look up a `BotPersonalityProfile` preset.
/// Each kind represents a distinct playstyle tuned by its profile values.
enum BotPersonalityKind: String, CaseIterable {
    case scavenger    // High greed, follows trail food and corpse pellets.
    case hunter       // Aggressive head-chaser with strong cut bias.
    case coward       // Avoidance-first; flees early and keeps wide clearance.
    case opportunist  // Balanced all-rounder; adapts to whatever the arena offers.
    case sprinter     // Speed-focused; boosts frequently and replans fast.
    case vulture      // Patient scavenger with the widest food-search radius.
    case interceptor  // Specialises in cutting off rivals rather than eating food.
    case trickster    // High unpredictability; erratic movement confuses opponents.
    case nemesis      // Elite killer tuned specifically for player elimination.
}

// MARK: - Bot Data Structures

/// Immutable tuning profile that defines how a bot thinks and moves.
/// All bias/multiplier values are dimensionless scalars unless noted.
struct BotPersonalityProfile {
    /// 0–1. Willingness to engage or chase other snakes.
    let aggression: CGFloat
    /// 0–1. Weight given to hazard avoidance when scoring headings.
    let caution: CGFloat
    /// 0–1. Amplifies the perceived value of food targets.
    let greed: CGFloat
    /// 0–1. Extra preference for trail/death food over live food.
    let scavengerBias: CGFloat
    /// 0–1. Likelihood of choosing a cut-off manoeuvre over direct pursuit.
    let cutBias: CGFloat
    /// 0–1. Probability of activating boost in favourable situations.
    let boostBias: CGFloat
    /// 0–1. Jitter added to heading choices to make movement less predictable.
    let unpredictability: CGFloat
    /// Multiplier on the base angular turn rate (1.0 = normal).
    let turnRateMultiplier: CGFloat
    /// Multiplier on the forward lookahead distance used for obstacle sensing.
    let horizonMultiplier: CGFloat
    /// Multiplier on the base cruise speed (1.0 = normal).
    let cruiseSpeedMultiplier: CGFloat
    /// Seconds between full intent re-evaluations.
    let replanInterval: CGFloat
    /// Minimum clear space (world units) the bot tries to maintain around its head.
    let desiredClearance: CGFloat
    /// World-unit radius in which the bot scans for food targets.
    let foodSearchRadius: CGFloat
    /// 0–1. How long the bot stays locked onto a chosen target before re-evaluating.
    let targetStickiness: CGFloat
}

/// Snapshot of the arena state used by `chooseBotIntent`.
/// All opportunity/danger fields are normalised to 0–1.
struct BotModeSnapshot {
    /// How immediately threatened the bot is (wall proximity, enemy heads, enclosed space).
    let immediateDanger: CGFloat
    /// How good the available escape headings are (1 = wide open, 0 = trapped).
    let escapeRouteQuality: CGFloat
    /// Proximity and value of the nearest reachable food item.
    let foodOpportunity: CGFloat
    /// Proximity of trail/death pellets from recently killed snakes.
    let scavengingOpportunity: CGFloat
    /// Feasibility of a successful head-on kill against a nearby shorter snake.
    let huntOpportunity: CGFloat
    /// Feasibility of cutting off a rival's path.
    let cutOpportunity: CGFloat
    /// Density of other snakes in the immediate area (used to suppress cut-off in crowds).
    let nearbyCrowding: CGFloat
    /// The bot's active personality, used to weight each opportunity.
    let personality: BotPersonalityProfile
}

/// Inputs for the food-contest arbitration function `shouldContestFood`.
struct BotFoodContestSnapshot {
    /// Distance from this bot's head to the food (world units).
    let selfDistance: CGFloat
    /// Current move speed of this bot (world units/s).
    let selfSpeed: CGFloat
    /// Distance from the rival's head to the same food (world units).
    let rivalDistance: CGFloat
    /// Current move speed of the rival (world units/s).
    let rivalSpeed: CGFloat
    /// `botFoodValue` score for this food item.
    let value: CGFloat
    /// Rival body length minus this bot's body length (positive = rival is larger).
    let rivalLengthAdvantage: CGFloat
    /// 0–1 from personality; higher = willing to contest riskier races.
    let riskTolerance: CGFloat
}

struct LeaderboardScoreEntry: Equatable {
    let name: String
    let score: Int
    let isCurrentPlayer: Bool
}

struct LeaderboardDisplayEntry: Equatable {
    let rank: Int
    let name: String
    let score: Int
    let isCurrentPlayer: Bool
}

// MARK: - GameLogic

enum GameLogic {

    // MARK: - Maze Hunt Progression

    enum MazeMilestoneFocus: String {
        case baseline
        case ai
        case maze
        case systems
    }

    struct MazeHuntRoundPlan {
        let band: Int
        let roundInBand: Int
        let timerSeconds: Int
        let mouseSpeedMultiplier: CGFloat
        let milestoneFocus: MazeMilestoneFocus
        let hasHeadStart: Bool
    }

    static func mazeMilestoneFocus(forBand band: Int) -> MazeMilestoneFocus {
        guard band >= 3 else { return .baseline }
        switch band % 9 {
        case 3: return .ai
        case 6: return .maze
        case 0: return .systems
        default: return .baseline
        }
    }


    enum MazeSpecialRoundType: String, CaseIterable {
        case none
        case twoMouse
        case pickupRich
        case highScoreBonus
        case largeMazePressure
    }

    struct MazeSpecialRoundPlan {
        let shouldSchedule: Bool
        let scheduledRoundIndex: Int?
    }

    static func mazeRequiredCaptures(band: Int, specialRound: MazeSpecialRoundType) -> Int {
        if specialRound == .twoMouse {
            return band >= 7 ? 2 : 1
        }
        return 1
    }

    static func mazeSpecialRoundPlan(
        band: Int,
        bandsWithoutSpecial: Int,
        randomRoll: CGFloat,
        randomRoundIndex: Int
    ) -> MazeSpecialRoundPlan {
        guard band >= 4 else { return MazeSpecialRoundPlan(shouldSchedule: false, scheduledRoundIndex: nil) }
        let guaranteed = bandsWithoutSpecial >= 2
        let shouldSchedule = guaranteed || randomRoll < 0.55
        if shouldSchedule {
            let index = min(max(randomRoundIndex, 1), 3)
            return MazeSpecialRoundPlan(shouldSchedule: true, scheduledRoundIndex: index)
        }
        return MazeSpecialRoundPlan(shouldSchedule: false, scheduledRoundIndex: nil)
    }
    static func mazeHuntRoundPlan(band: Int, roundInBand: Int) -> MazeHuntRoundPlan {
        let clampedBand = max(1, band)
        let clampedRound = min(max(roundInBand, 1), 3)
        let focus = mazeMilestoneFocus(forBand: clampedBand)

        // Keep rounds short and urgent. Only add time on major complexity jumps.
        let timer = clampedBand >= 6 ? 35 : 30
        let speedBoost = min(CGFloat(clampedBand - 1) * 0.08, 0.75)

        return MazeHuntRoundPlan(
            band: clampedBand,
            roundInBand: clampedRound,
            timerSeconds: timer,
            mouseSpeedMultiplier: 1 + speedBoost,
            milestoneFocus: focus,
            hasHeadStart: clampedBand <= 2
        )
    }

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

    // MARK: - Math Utilities

    /// Clamps `value` to the closed interval [0, 1].
    static func clamp01(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    /// Returns the point `distance` world units from `start` along `angle` (radians).
    static func projectedPoint(from start: CGPoint, angle: CGFloat, distance: CGFloat) -> CGPoint {
        CGPoint(x: start.x + cos(angle) * distance,
                y: start.y + sin(angle) * distance)
    }

    /// Returns the signed difference between two angles, normalised to (−π, π].
    /// Positive means turning counter-clockwise to reach `target` from `current`.
    static func shortestAngleDiff(from current: CGFloat, to target: CGFloat) -> CGFloat {
        var diff = target - current
        while diff > .pi  { diff -= 2 * .pi }
        while diff < -.pi { diff += 2 * .pi }
        return diff
    }

    /// Returns a 0–1 score representing how much clear space the bot has.
    /// A result of 1 means `minClearance` meets or exceeds `desired`; lower values
    /// indicate the bot is closer to obstacles than it would like.
    static func clearanceScore(minClearance: CGFloat, desired: CGFloat) -> CGFloat {
        guard desired > 0 else { return 1 }
        return clamp01(minClearance / desired)
    }

    /// Returns the shortest distance from `point` to the line segment [`start`, `end`].
    /// Degenerates to point–point distance when the segment has zero length.
    static func distanceFromPoint(_ point: CGPoint, toSegment start: CGPoint, _ end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSq = dx * dx + dy * dy
        guard lengthSq > 0 else { return hypot(point.x - start.x, point.y - start.y) }

        // Project `point` onto the infinite line, then clamp to the segment.
        let t = clamp01(((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSq)
        let projection = CGPoint(x: start.x + dx * t, y: start.y + dy * t)
        return hypot(point.x - projection.x, point.y - projection.y)
    }

    // MARK: - Speed Calculation

    /// Returns the move speed for the given score.
    /// Mirrors the formula in GameScene.updateSpeedForScore().
    static func calculateSpeed(
        score: Int,
        baseMoveSpeed: CGFloat = 100,
        maxMoveSpeed:  CGFloat = 130
    ) -> CGFloat {
        let speed = min(baseMoveSpeed + CGFloat(score) * 2.5, maxMoveSpeed)
        return speed
    }

    // MARK: - Combo Scoring

    /// Bonus points awarded for eating foods in rapid succession.
    /// Combo begins at the 2nd consecutive eat within the time window.
    static func comboBonus(forComboCount count: Int) -> Int {
        guard count >= 2 else { return 0 }
        return min(count - 1, 8)   // +1 per consecutive eat, cap at +8
    }

    /// Returns true when the combo count hits a notable streak milestone.
    static func isStreakThreshold(_ count: Int) -> Bool {
        return count == 3 || count == 5 || count == 8 || count % 10 == 0
    }

    static func boostedPlayerSpeed(
        baseSpeed: CGFloat,
        fastestBoostingBotSpeed: CGFloat?,
        minimumBoostMultiplier: CGFloat = 1.65,
        dominanceMultiplier: CGFloat = 1.5
    ) -> CGFloat {
        let minimumBoostedSpeed = baseSpeed * minimumBoostMultiplier
        guard let fastestBoostingBotSpeed else { return minimumBoostedSpeed }
        return max(minimumBoostedSpeed, fastestBoostingBotSpeed * dominanceMultiplier)
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

    static func leaderboardDisplayEntries(
        from entries: [LeaderboardScoreEntry],
        topCount: Int = 4,
        expandedTopCount: Int = 5
    ) -> [LeaderboardDisplayEntry] {
        guard !entries.isEmpty else { return [] }

        let ranked = entries.enumerated().sorted { lhs, rhs in
            if lhs.element.score != rhs.element.score {
                return lhs.element.score > rhs.element.score
            }
            if lhs.element.isCurrentPlayer != rhs.element.isCurrentPlayer {
                return lhs.element.isCurrentPlayer && !rhs.element.isCurrentPlayer
            }
            if lhs.element.name != rhs.element.name {
                return lhs.element.name.localizedCaseInsensitiveCompare(rhs.element.name) == .orderedAscending
            }
            return lhs.offset < rhs.offset
        }
        .enumerated()
        .map { offset, entry in
            LeaderboardDisplayEntry(
                rank: offset + 1,
                name: entry.element.name,
                score: entry.element.score,
                isCurrentPlayer: entry.element.isCurrentPlayer
            )
        }

        guard let currentPlayerIndex = ranked.firstIndex(where: { $0.isCurrentPlayer }) else {
            return Array(ranked.prefix(topCount))
        }

        let baseCount = currentPlayerIndex < topCount ? expandedTopCount : topCount
        var display = Array(ranked.prefix(baseCount))

        if currentPlayerIndex >= display.count {
            display.append(ranked[currentPlayerIndex])
        }

        return display
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

    /// Returns the hard-coded `BotPersonalityProfile` for the given archetype.
    ///
    /// All numeric values were hand-tuned during playtesting. The key design
    /// invariants are:
    /// - `aggression + caution` need not sum to 1; they are independent axes.
    /// - `desiredClearance` is in world units (roughly sprite-radius multiples).
    /// - `foodSearchRadius` should stay above the camera's visible radius so bots
    ///   can plan toward off-screen food.
    /// - `replanInterval` trades responsiveness for CPU cost; keep it above ~0.14 s.
    static func botPersonalityProfile(for kind: BotPersonalityKind) -> BotPersonalityProfile {
        switch kind {
        case .scavenger:
            // Cautious forager — prioritises safe trails over risky head confrontations.
            return BotPersonalityProfile(
                aggression: 0.35, caution: 0.65, greed: 0.78, scavengerBias: 1.00,
                cutBias: 0.25, boostBias: 0.40, unpredictability: 0.18,
                turnRateMultiplier: 1.02, horizonMultiplier: 1.08,
                cruiseSpeedMultiplier: 0.98, replanInterval: 0.22,
                desiredClearance: 92, foodSearchRadius: 720, targetStickiness: 0.62
            )
        case .hunter:
            // Aggressive head-chaser — highest aggression, strong cut & boost bias.
            return BotPersonalityProfile(
                aggression: 0.95, caution: 0.30, greed: 0.45, scavengerBias: 0.30,
                cutBias: 0.68, boostBias: 0.78, unpredictability: 0.12,
                turnRateMultiplier: 1.08, horizonMultiplier: 1.02,
                cruiseSpeedMultiplier: 1.05, replanInterval: 0.18,
                desiredClearance: 72, foodSearchRadius: 620, targetStickiness: 0.78
            )
        case .coward:
            // Survival-first — highest caution and clearance, escapes at the first sign of danger.
            return BotPersonalityProfile(
                aggression: 0.18, caution: 0.98, greed: 0.35, scavengerBias: 0.25,
                cutBias: 0.10, boostBias: 0.72, unpredictability: 0.15,
                turnRateMultiplier: 1.15, horizonMultiplier: 1.22,
                cruiseSpeedMultiplier: 1.00, replanInterval: 0.16,
                desiredClearance: 116, foodSearchRadius: 640, targetStickiness: 0.55
            )
        case .opportunist:
            // Jack-of-all-trades — every stat near the middle so it adapts to any situation.
            return BotPersonalityProfile(
                aggression: 0.58, caution: 0.55, greed: 0.65, scavengerBias: 0.58,
                cutBias: 0.52, boostBias: 0.58, unpredictability: 0.20,
                turnRateMultiplier: 1.06, horizonMultiplier: 1.00,
                cruiseSpeedMultiplier: 1.01, replanInterval: 0.20,
                desiredClearance: 84, foodSearchRadius: 690, targetStickiness: 0.66
            )
        case .sprinter:
            // Speed demon — highest boost bias and cruise multiplier, fastest replan cadence.
            return BotPersonalityProfile(
                aggression: 0.70, caution: 0.42, greed: 0.58, scavengerBias: 0.38,
                cutBias: 0.48, boostBias: 0.98, unpredictability: 0.16,
                turnRateMultiplier: 1.18, horizonMultiplier: 0.94,
                cruiseSpeedMultiplier: 1.10, replanInterval: 0.16,
                desiredClearance: 78, foodSearchRadius: 650, targetStickiness: 0.60
            )
        case .vulture:
            // Patient opportunist — widest search radius, nearly max scavenger bias.
            return BotPersonalityProfile(
                aggression: 0.48, caution: 0.62, greed: 0.72, scavengerBias: 0.96,
                cutBias: 0.38, boostBias: 0.64, unpredictability: 0.18,
                turnRateMultiplier: 1.00, horizonMultiplier: 1.10,
                cruiseSpeedMultiplier: 1.00, replanInterval: 0.22,
                desiredClearance: 90, foodSearchRadius: 760, targetStickiness: 0.72
            )
        case .interceptor:
            // Path-cutter — highest cut bias, locks onto targets stubbornly (high stickiness).
            return BotPersonalityProfile(
                aggression: 0.82, caution: 0.46, greed: 0.42, scavengerBias: 0.20,
                cutBias: 0.92, boostBias: 0.70, unpredictability: 0.10,
                turnRateMultiplier: 1.12, horizonMultiplier: 1.15,
                cruiseSpeedMultiplier: 1.03, replanInterval: 0.18,
                desiredClearance: 76, foodSearchRadius: 610, targetStickiness: 0.80
            )
        case .trickster:
            // Erratic mover — highest unpredictability, low target stickiness.
            return BotPersonalityProfile(
                aggression: 0.60, caution: 0.44, greed: 0.55, scavengerBias: 0.42,
                cutBias: 0.58, boostBias: 0.62, unpredictability: 0.34,
                turnRateMultiplier: 1.16, horizonMultiplier: 0.98,
                cruiseSpeedMultiplier: 1.02, replanInterval: 0.19,
                desiredClearance: 80, foodSearchRadius: 660, targetStickiness: 0.50
            )
        case .nemesis:
            // Hyper-aggressive apex predator for challenge mode.
            return BotPersonalityProfile(
                aggression: 1.00, caution: 0.34, greed: 0.40, scavengerBias: 0.10,
                cutBias: 0.96, boostBias: 1.00, unpredictability: 0.08,
                turnRateMultiplier: 1.30, horizonMultiplier: 1.20,
                cruiseSpeedMultiplier: 1.22, replanInterval: 0.12,
                desiredClearance: 70, foodSearchRadius: 920, targetStickiness: 0.96
            )
        }
    }

    /// Returns a desirability score for a food item from this bot's perspective.
    ///
    /// - Parameters:
    ///   - type: The food's type, which sets the base value.
    ///   - clusterBonus: 0–1 density bonus when multiple food items are nearby.
    ///     Each 1.0 unit adds ~28 % to the base value.
    ///   - greed: From `BotPersonalityProfile.greed`; amplifies all food values.
    ///   - scavengerBias: From `BotPersonalityProfile.scavengerBias`; extra weight
    ///     for `.death` and `.trail` food (corpse scavenging reward).
    ///
    /// Base values: regular=12, trail=6, death=24, shield=11,
    ///              multiplier=13, magnet=9, ghost=10, shrink=3.
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
        case .death:      base = 24  // High base — killing food is risky but rewarding.
        case .shield:     base = 11
        case .multiplier: base = 13
        case .magnet:     base = 9
        case .ghost:      base = 10
        case .shrink:     base = 3   // Low base — shrink food offers little upside.
        }

        // Cluster bonus rewards bots for targeting food-dense areas.
        var value = base * (1 + clusterBonus * 0.28)
        // Greed uniformly scales up all food desirability.
        value *= 1 + greed * 0.22
        // Scavenger types get a further bonus for trail/death food specifically.
        if type == .death || type == .trail {
            value *= 1 + scavengerBias * 0.45
        }
        return value
    }

    /// Decides whether this bot should race a rival for the same food item.
    ///
    /// The core logic compares estimated time-to-arrival (ETA = distance / speed).
    /// A bot will contest the food if its ETA is within a personality-adjusted
    /// multiple of the rival's ETA — but two hard exits override that:
    ///
    /// 1. **Length veto**: if the rival is >8 segments longer AND will arrive first,
    ///    contesting is suicidal (head-on kill risk), so we always back off.
    /// 2. **Margin floor**: `max(0.72, margin)` ensures the bot never contests food
    ///    unless its own ETA is meaningfully competitive even at zero risk tolerance.
    ///
    /// - Parameter snapshot: Arena inputs captured at decision time.
    /// - Returns: `true` if the bot should pursue the food despite the rival.
    static func shouldContestFood(_ snapshot: BotFoodContestSnapshot) -> Bool {
        let selfETA   = snapshot.selfDistance   / max(snapshot.selfSpeed,   1)
        let rivalETA  = snapshot.rivalDistance  / max(snapshot.rivalSpeed,  1)

        // Normalise food value to [0,1] using 28 as the practical maximum base value.
        let valueFactor = clamp01(snapshot.value / 28)

        // Larger rivals raise the risk of a losing head-on; reduce contest willingness.
        // Only positive length advantages penalise us; being larger gives no bonus here.
        let riskPenalty = max(0, snapshot.rivalLengthAdvantage) * 0.03

        // Effective ETA ratio threshold the bot is willing to accept.
        // Base of 1.0 means "only contest if we arrive at the same time or earlier".
        // Risk tolerance and high-value food loosen the threshold; a large rival tightens it.
        let margin = 1.0 + snapshot.riskTolerance * 0.20 + valueFactor * 0.12 - riskPenalty

        // Hard veto: a much larger rival with a head-start will likely kill us head-on.
        if snapshot.rivalLengthAdvantage > 8 && rivalETA < selfETA {
            return false
        }

        // Contest if our ETA is competitive within the personality-adjusted margin.
        return selfETA <= rivalETA * max(0.72, margin)
    }

    /// Selects the highest-priority `BotIntent` given the current arena snapshot.
    ///
    /// Priority ladder (highest to lowest):
    /// 1. **Escape** — triggered immediately if danger is severe, or if moderate danger
    ///    pairs with poor escape options.
    /// 2. **Cut-off** — preferred when the opportunity is dominant, crowding is low,
    ///    and the bot's `cutBias` makes the threshold attainable.
    /// 3. **Scavenge** — preferred over food/hunt when trail pellets are abundant and
    ///    the bot's `scavengerBias` lowers the relative threshold.
    /// 4. **Hunt** — chosen when a kill opportunity clearly beats food/scavenging and
    ///    `aggression` lowers the required advantage margin.
    /// 5. **Forage** — default when any food is visible (opportunity > 0.16).
    /// 6. **Roam** (fallback) — or a mild escape if residual danger is present.
    ///
    /// All thresholds are tuned so that a perfectly balanced opportunist profile
    /// produces roughly equal intent distribution in a mid-density arena.
    static func chooseBotIntent(_ snapshot: BotModeSnapshot) -> BotIntent {
        let danger      = clamp01(snapshot.immediateDanger)
        let food        = clamp01(snapshot.foodOpportunity)
        let scavenging  = clamp01(snapshot.scavengingOpportunity)
        let hunt        = clamp01(snapshot.huntOpportunity)
        let cut         = clamp01(snapshot.cutOpportunity)
        let escapeRoute = clamp01(snapshot.escapeRouteQuality)
        let crowding    = clamp01(snapshot.nearbyCrowding)
        let profile     = snapshot.personality

        // 1. Escape: immediate high danger, or moderate danger with limited exits.
        if danger > 0.72 || (danger > 0.45 && escapeRoute < 0.40) {
            return .escape
        }

        // 2. Cut-off: personality-adjusted threshold keeps low-cutBias bots (e.g. coward)
        //    from attempting cut-offs; crowding guard prevents collisions in packed spaces.
        if cut > max(hunt, food) * (0.88 - profile.cutBias * 0.14) &&
            cut > 0.42 &&
            crowding < 0.78 {
            return .cutOff
        }

        // 3. Scavenge: high-scavengerBias bots lower the threshold needed to prefer
        //    trail food over live food or hunting.
        if scavenging > max(food, hunt) * (0.90 - profile.scavengerBias * 0.12) &&
            scavenging > 0.34 {
            return .scavenge
        }

        // 4. Hunt: aggressive bots lower the threshold needed to prefer hunting
        //    over foraging or scavenging.
        if hunt > max(food, scavenging) * (0.94 - profile.aggression * 0.16) &&
            hunt > 0.36 {
            return .hunt
        }

        // 5. Forage: any detectable food beats roaming (low threshold keeps bots active).
        if food > 0.16 {
            return .forage
        }

        // 6. Fallback: mild residual danger nudges toward escape; otherwise roam freely.
        return danger > 0.28 ? .escape : .roam
    }
}
