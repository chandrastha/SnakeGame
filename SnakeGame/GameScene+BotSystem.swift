import SpriteKit

// MARK: - Bot Tier (Offline Mode)
enum BotTier { case easy, medium, hard }

// MARK: - Bot State
struct BotState {
    let id: Int
    var position: CGPoint     // head position (always tracked, even when virtual)
    var angle: CGFloat
    var targetAngle: CGFloat
    var score: Int
    var bodyLength: Int
    var colorIndex: Int
    var patternIndex: Int
    var name: String
    var isActive: Bool        // true = has SpriteKit nodes

    // SpriteKit nodes – nil when virtual
    var head: SKShapeNode?
    var body: [SKShapeNode]
    var posHistory: PointRingBuffer
    var bodyPositionCache: [CGPoint]
    var nameLabel: SKLabelNode?

    // Virtual movement: change direction every ~3 s
    var dirChangeTimer: CGFloat

    // Offline mode tier system
    var tier: BotTier          // assigned by spawnBots(); default .easy
    var isDead: Bool           // true during respawn delay countdown
    var respawnTimer: CGFloat  // seconds remaining before bot reappears
    var personality: BotPersonalityKind
    var intent: BotIntent
    var decisionTimer: CGFloat
    var boostTimer: CGFloat
    var boostCooldown: CGFloat
    var isBoosting: Bool
    var focusPoint: CGPoint?
    var focusTimer: CGFloat
    var roamAnchor: CGPoint

    // Trail food
    var trailFoodTimer: CGFloat
    var zoneIndex: Int     // home zone in 3×3 arena grid (0–8), used for area coverage
    var shieldCharges: Int
    var multiplierTimeLeft: CGFloat
    var magnetTimeLeft: CGFloat
    var ghostTimeLeft: CGFloat
    var isNemesis: Bool
    var isCircled: Bool = false
    var circledTimer: CGFloat = 0
    var spawnTimer: CGFloat = 0   // counts down after activation; collision disabled while > 0

    init(id: Int, position: CGPoint, colorIndex: Int, name: String) {
        self.id           = id
        self.position     = position
        self.angle        = CGFloat.random(in: 0...(2 * .pi))
        self.targetAngle  = self.angle
        self.score        = 0
        self.bodyLength   = 10
        self.colorIndex   = colorIndex
        self.patternIndex = 0
        self.name         = name
        self.isActive     = false
        self.body         = []
        self.posHistory   = PointRingBuffer()
        self.bodyPositionCache = []
        self.dirChangeTimer = CGFloat.random(in: 1...3)
        self.tier          = .easy
        self.isDead        = false
        self.respawnTimer  = 0
        self.personality   = .opportunist
        self.intent        = .roam
        self.decisionTimer = 0
        self.boostTimer    = 0
        self.boostCooldown = 0
        self.isBoosting    = false
        self.focusPoint    = nil
        self.focusTimer    = 0
        self.roamAnchor    = position
        self.trailFoodTimer = 0
        self.zoneIndex     = id % 9  // assign home zone in 3×3 grid
        self.shieldCharges = 0
        self.multiplierTimeLeft = 0
        self.magnetTimeLeft = 0
        self.ghostTimeLeft = 0
        self.isNemesis = false
        self.spawnTimer = 0
    }
}

private struct BotThreatSnapshot {
    let id: Int
    let position: CGPoint
    let angle: CGFloat
    let speed: CGFloat
    let length: Int
    let isPlayer: Bool
}

private struct BotFoodTarget {
    let index: Int
    let position: CGPoint
    let type: FoodType
    let utility: CGFloat
}

private struct BotDecision {
    let angle: CGFloat
    let intent: BotIntent
    let shouldBoost: Bool
    let score: CGFloat
    let focusPoint: CGPoint?
}


extension GameScene {

    // MARK: - Bot System (Offline Mode)
    func spawnBots() {
        let namePool = GameScene.botNamePool
        let botCount = localBotTargetCount
        let nemesisIndex = gameMode == .challenge ? botCount - 1 : -1
        let themeCount = snakeColorThemes.count
        let hasMultipleThemes = themeCount > 1

        for i in 0..<botCount {
            let playerColorIndex = normalizedSnakeColorIndex(selectedSnakeColorIndex)
            var colorIndex = playerColorIndex
            if hasMultipleThemes {
                colorIndex = (playerColorIndex + 1 + (i % (themeCount - 1))) % themeCount
                if colorIndex == playerColorIndex {
                    colorIndex = (colorIndex + 1) % themeCount
                }
            }
            let isNemesis = i == nemesisIndex
            let name = isNemesis ? "NEMESIS" : namePool[i % namePool.count]

            // Zone-distributed spawn: divide arena into 3×3 grid so bots cover the whole map.
            // Nemesis always starts near the player (center of the arena).
            let position: CGPoint
            if isNemesis {
                let angle = CGFloat.random(in: 0...(2 * .pi))
                let dist  = CGFloat.random(in: 260...480)
                position = CGPoint(
                    x: max(300, min(worldSize - 300, worldSize / 2 + cos(angle) * dist)),
                    y: max(300, min(worldSize - 300, worldSize / 2 + sin(angle) * dist))
                )
            } else {
                let zoneIdx = i % 9
                let zoneCol = zoneIdx % 3
                let zoneRow = zoneIdx / 3
                let zoneW   = worldSize / 3
                let zoneH   = worldSize / 3
                let pad: CGFloat = 300
                let zMinX = CGFloat(zoneCol) * zoneW + pad
                let zMaxX = CGFloat(zoneCol + 1) * zoneW - pad
                let zMinY = CGFloat(zoneRow) * zoneH + pad
                let zMaxY = CGFloat(zoneRow + 1) * zoneH - pad
                position = CGPoint(
                    x: CGFloat.random(in: zMinX...zMaxX),
                    y: CGFloat.random(in: zMinY...zMaxY)
                )
            }
            bots.append(BotState(id: i, position: position, colorIndex: colorIndex, name: name))

            if isNemesis {
                bots[i].isNemesis = true
                bots[i].tier = .hard
                bots[i].personality = .nemesis
            } else {
                // Casual:  0–17 easy (~30%), 18–41 medium (~40%), 42–59 hard (~30%)
                // Expert:  0–5  easy (~10%),  6–23 medium (~30%), 24–59 hard (~60%)
                if gameMode == .challenge {
                    switch min(i, totalBots - 1) {
                    case 0..<6:  bots[i].tier = .easy
                    case 6..<24: bots[i].tier = .medium
                    default:     bots[i].tier = .hard
                    }
                } else {
                    switch min(i, totalBots - 1) {
                    case 0..<18:  bots[i].tier = .easy
                    case 18..<42: bots[i].tier = .medium
                    default:      bots[i].tier = .hard
                    }
                }
                let personalities = botPersonalities(for: bots[i].tier)
                bots[i].personality = personalities[i % personalities.count]
            }
            configureBotIdentity(index: i, preservePersonality: true)

            if bots[i].isNemesis && gameMode == .challenge {
                bots[i].isDead = true
                bots[i].respawnTimer = expertNemesisInitialDelay
            } else {
                activateBot(i)
            }
        }
        seedStartingBotScores()
    }

    /// Assigns pre-seeded scores to a subset of bots so the arena feels lived-in at game start:
    ///  - ≥2 bots with score > 1000  (large snakes)
    ///  - ≥3 bots with score > 700   (medium-large)
    ///  - ≥5 bots with score > 400   (medium)
    /// Hard-tier bots are preferred for higher scores.
    private func seedStartingBotScores() {
        // Build pool: hard first, then medium, then easy — nemesis excluded
        var pool: [Int] = []
        pool += bots.indices.filter { !bots[$0].isNemesis && !bots[$0].isDead && bots[$0].tier == .hard }.shuffled()
        pool += bots.indices.filter { !bots[$0].isDead && bots[$0].tier == .medium }.shuffled()
        pool += bots.indices.filter { !bots[$0].isDead && bots[$0].tier == .easy }.shuffled()

        var cursor = 0

        func applyScore(_ s: Int) {
            guard cursor < pool.count else { return }
            let idx = pool[cursor]; cursor += 1
            bots[idx].score = s
            bots[idx].bodyLength = targetBotBodyCount(for: idx)
            syncBotLength(idx)
        }

        // ≥2 bots > 1000
        applyScore(Int.random(in: 1100...1300))
        applyScore(Int.random(in: 1050...1250))
        // ≥3 bots > 700
        applyScore(Int.random(in: 780...980))
        applyScore(Int.random(in: 750...950))
        applyScore(Int.random(in: 720...900))
        // ≥5 bots > 400
        applyScore(Int.random(in: 480...660))
        applyScore(Int.random(in: 450...630))
        applyScore(Int.random(in: 430...610))
        applyScore(Int.random(in: 410...580))
        applyScore(Int.random(in: 400...560))
    }

    func updateBotVisibilityLOD() {
        guard !isSpecialOfflineMode else { return }

        let playerPos = snakeHead.position
        let activateSq = botActivationDistance * botActivationDistance
        let deactivateSq = botDeactivationDistance * botDeactivationDistance

        for i in bots.indices {
            guard !bots[i].isDead else { continue }
            let dx = bots[i].position.x - playerPos.x
            let dy = bots[i].position.y - playerPos.y
            let distSq = dx * dx + dy * dy

            if bots[i].isActive {
                if distSq > deactivateSq { deactivateBot(i) }
            } else {
                if distSq < activateSq { activateBot(i) }
            }
        }
    }

    func detectCircledBots() {
        let rayCount: Int     = 12
        let checkDist: CGFloat = 200
        let perpThresh: CGFloat = collisionRadius * 1.4

        for i in bots.indices {
            guard bots[i].isActive && !bots[i].isDead else {
                bots[i].isCircled = false
                continue
            }
            let pos = bots[i].position
            var blockedCount = 0

            for rayIdx in 0..<rayCount {
                let angle = CGFloat(rayIdx) * (2 * .pi / CGFloat(rayCount))
                let dx = cos(angle), dy = sin(angle)
                var blocked = false

                // --- Player body ---
                for pt in bodyPositionCache {
                    let px = pt.x - pos.x, py = pt.y - pos.y
                    let proj = px * dx + py * dy
                    guard proj > 0 && proj < checkDist else { continue }
                    if abs(px * dy - py * dx) < perpThresh { blocked = true; break }
                }

                // --- Other bot bodies (broad-phase distance filter first) ---
                if !blocked {
                    for j in bots.indices where j != i && bots[j].isActive {
                        // Skip bots whose HEAD is farther than checkDist — their body can't block
                        let hdx = bots[j].position.x - pos.x
                        let hdy = bots[j].position.y - pos.y
                        guard abs(hdx) < checkDist + 30 && abs(hdy) < checkDist + 30 else { continue }
                        for pt in bots[j].bodyPositionCache {
                            let px = pt.x - pos.x, py = pt.y - pos.y
                            let proj = px * dx + py * dy
                            guard proj > 0 && proj < checkDist else { continue }
                            if abs(px * dy - py * dx) < perpThresh { blocked = true; break }
                        }
                        if blocked { break }
                    }
                }

                if blocked { blockedCount += 1 }
            }

            if blockedCount >= 7 {
                bots[i].isCircled = true
                bots[i].circledTimer = 2.0
            } else if bots[i].circledTimer <= 0 {
                bots[i].isCircled = false
            }
        }
    }

    private func botPersonalities(for tier: BotTier) -> [BotPersonalityKind] {
        switch tier {
        case .easy:
            return [.scavenger, .coward, .opportunist, .trickster]
        case .medium:
            return [.opportunist, .sprinter, .vulture, .trickster, .hunter]
        case .hard:
            return [.hunter, .interceptor, .sprinter, .vulture, .opportunist]
        }
    }

    private func randomBotLength(for index: Int) -> Int {
        let profile = GameLogic.botPersonalityProfile(for: bots[index].personality)
        let baseRange: ClosedRange<Int>
        switch bots[index].tier {
        case .easy:   baseRange = 9...18
        case .medium: baseRange = 14...26
        case .hard:   baseRange = 18...34
        }

        var length = Int.random(in: baseRange)
        if profile.aggression > 0.75 { length += Int.random(in: 2...5) }
        if profile.scavengerBias > 0.85 { length += Int.random(in: 1...4) }
        if profile.caution > 0.85 { length -= Int.random(in: 0...2) }
        return max(8, length)
    }

    private func botPatternIndex(for index: Int) -> Int {
        let patterns = SnakePattern.allCases.filter { $0 != .solid }
        guard !patterns.isEmpty else { return SnakePattern.solid.rawValue }
        if bots[index].isNemesis {
            return SnakePattern.ember.rawValue
        }
        return patterns[index % patterns.count].rawValue
    }

    private func configureBotIdentity(index: Int, preservePersonality: Bool) {
        if !preservePersonality && !bots[index].isNemesis {
            let personalities = botPersonalities(for: bots[index].tier)
            bots[index].personality = personalities.randomElement() ?? .opportunist
        }

        let targetLength = bots[index].isNemesis ? 130 : randomBotLength(for: index)
        bots[index].score = bots[index].isNemesis
            ? challengeNemesisScore
            : max(0, (targetLength - initialBotBodyCount) * 10)
        bots[index].bodyLength = targetBotBodyCount(for: index)
        bots[index].intent = bots[index].isNemesis ? .hunt : .roam
        bots[index].decisionTimer = 0
        bots[index].boostTimer = 0
        let initialCooldownMax: CGFloat = gameMode == .challenge ? 0.50 : 0.80
        bots[index].boostCooldown = bots[index].isNemesis ? 0.08 : CGFloat.random(in: 0.15...initialCooldownMax)
        bots[index].isBoosting = false
        bots[index].focusPoint = nil
        bots[index].focusTimer = 0
        bots[index].shieldCharges = bots[index].isNemesis ? 2 : 0
        bots[index].multiplierTimeLeft = 0
        bots[index].magnetTimeLeft = 0
        bots[index].ghostTimeLeft = 0
        bots[index].patternIndex = botPatternIndex(for: index)
        bots[index].roamAnchor = randomPositionInZone(for: index)
        bots[index].dirChangeTimer = bots[index].isNemesis ? 1.2 : CGFloat.random(in: 1.8...4.6)
        bots[index].trailFoodTimer = CGFloat.random(in: 0...(botTrailInterval * 0.8))
    }

    func activateBot(_ index: Int) {
        guard !bots[index].isActive else { return }
        let bot   = bots[index]
        let theme = snakeColorThemes[bot.colorIndex % snakeColorThemes.count]

        let head = SKShapeNode(circleOfRadius: headRadius)
        head.fillColor   = theme.headSKColor
        head.strokeColor = theme.headStrokeSKColor
        head.lineWidth   = 2
        head.glowWidth   = 5
        head.position    = bot.position
        head.zRotation   = (bot.angle * 180 / .pi - 90) * .pi / 180
        addChild(head)
        addEyes(to: head)
        if bots[index].isNemesis {
            head.setScale(1.35)
            head.glowWidth = 18
            head.lineWidth = 3.5
            let ring = SKShapeNode(circleOfRadius: headRadius + 7)
            ring.fillColor   = .clear
            ring.strokeColor = SKColor(white: 1.0, alpha: 0.75)
            ring.lineWidth   = 2.5
            ring.glowWidth   = 10
            ring.name        = "nemesisShieldRing"
            ring.isHidden    = bots[index].shieldCharges <= 0
            head.addChild(ring)
        }
        bots[index].head = head

        let nameLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        nameLabel.text      = bot.name
        nameLabel.fontSize  = 12
        nameLabel.fontColor = SKColor(white: 1, alpha: 0.80)
        if bots[index].isNemesis {
            nameLabel.fontSize  = 16
            nameLabel.fontColor = SKColor(red: 1.0, green: 0.3, blue: 0.3, alpha: 1.0)
        }
        nameLabel.horizontalAlignmentMode = .center
        nameLabel.verticalAlignmentMode   = .bottom
        nameLabel.position  = CGPoint(x: 0, y: headRadius + 4)
        nameLabel.zPosition = 1
        head.addChild(nameLabel)
        bots[index].nameLabel = nameLabel

        let segCount = max(1, bot.bodyLength)
        bots[index].posHistory.setCapacity(historyCapacity(forSegmentCount: segCount))
        bots[index].posHistory.removeAll()
        let historyNeeded = historyCapacity(forSegmentCount: segCount)
        for k in 0..<historyNeeded {
            bots[index].posHistory.append(CGPoint(
                x: bot.position.x - cos(bot.angle) * CGFloat(k) * 0.5,
                y: bot.position.y - sin(bot.angle) * CGFloat(k) * 0.5
            ))
        }
        for i in 1...segCount {
            let seg = makeBodySegment(
                color: theme.bodySKColor,
                stroke: theme.bodyStrokeSKColor,
                pattern: SnakePattern(rawValue: bot.patternIndex) ?? .solid,
                segIndex: i - 1,
                radius: botEffectiveBodyRadius(bot.score)
            )
            seg.position = CGPoint(
                x: bot.position.x - cos(bot.angle) * CGFloat(i) * segmentPixelSpacing,
                y: bot.position.y - sin(bot.angle) * CGFloat(i) * segmentPixelSpacing
            )
            addChild(seg)
            bots[index].body.append(seg)
        }
        cacheBodyPositions(from: bots[index].body, into: &bots[index].bodyPositionCache)
        updateBotBodyScales(index)
        bots[index].isActive = true
        bots[index].isCircled = false
        bots[index].circledTimer = 0
        bots[index].spawnTimer = 0.5   // collision disabled during entrance animation
        miniLeaderboardNeedsRefresh = true
        animateSnakeEntrance(head: head, body: bots[index].body, angle: bot.angle, accent: theme.bodySKColor)
    }

    func deactivateBot(_ index: Int) {
        guard bots[index].isActive else { return }
        bots[index].isActive = false   // stop AI immediately
        bots[index].spawnTimer = 0
        let bodyToFade = bots[index].body
        bots[index].head?.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 0.35),
            SKAction.run { [weak self] in self?.finishDeactivateBotNodes(index) }
        ]))
        for seg in bodyToFade {
            seg.run(SKAction.fadeOut(withDuration: 0.35))
        }
        miniLeaderboardNeedsRefresh = true
    }

    private func finishDeactivateBotNodes(_ index: Int) {
        bots[index].head?.removeFromParent()
        bots[index].head = nil
        bots[index].nameLabel?.removeFromParent()
        bots[index].nameLabel = nil
        for seg in bots[index].body { seg.removeFromParent() }
        bots[index].body.removeAll()
        bots[index].bodyPositionCache.removeAll()
        bots[index].posHistory.removeAll()
    }

    func botEffectiveBodyRadius(_ botScore: Int) -> CGFloat {
        botScore < 1000 ? bodySegmentRadius : min(bodySegmentRadius * 1.5, bodySegmentRadius * (1.0 + CGFloat(botScore - 1000) / 4000.0))
    }

    func updateBotBodyScales(_ index: Int) {
        let count = bots[index].body.count
        guard count > 0 else { return }
        let pattern = SnakePattern(rawValue: bots[index].patternIndex) ?? .solid
        for (i, seg) in bots[index].body.enumerated() {
            let t = count > 1 ? CGFloat(i) / CGFloat(count - 1) : 0
            seg.setScale(1.0 - t * 0.22)
            seg.alpha     = 1.0 - t * 0.10
            seg.glowWidth = 0  // perf: bot body glow is expensive; heads retain glow
        }
    }

    func addBotBodySegment(_ index: Int) {
        guard bots[index].isActive, let head = bots[index].head else {
            bots[index].bodyLength += 1; return
        }
        let theme = snakeColorThemes[bots[index].colorIndex % snakeColorThemes.count]
        let seg   = makeBodySegment(
            color: theme.bodySKColor,
            stroke: theme.bodyStrokeSKColor,
            pattern: SnakePattern(rawValue: bots[index].patternIndex) ?? .solid,
            segIndex: bots[index].body.count
        )
        seg.position = bots[index].body.last?.position ?? head.position
        addChild(seg)
        bots[index].body.append(seg)
        bots[index].bodyLength += 1
        ensurePointCacheLength(bots[index].body.count, cache: &bots[index].bodyPositionCache)
        bots[index].posHistory.setCapacity(historyCapacity(forSegmentCount: bots[index].body.count))
        updateBotBodyScales(index)
        miniLeaderboardNeedsRefresh = true
    }

    /// Grow or shrink bot body to match targetBotBodyCount(for:).
    /// Must be called after every change to bots[index].score.
    func syncBotLength(_ index: Int) {
        let target = targetBotBodyCount(for: index)
        bots[index].bodyLength = target
        guard bots[index].isActive, let head = bots[index].head else { return }

        let theme = snakeColorThemes[bots[index].colorIndex % snakeColorThemes.count]
        while bots[index].body.count < target {
            let seg = makeBodySegment(
                color: theme.bodySKColor,
                stroke: theme.bodyStrokeSKColor,
                pattern: SnakePattern(rawValue: bots[index].patternIndex) ?? .solid,
                segIndex: bots[index].body.count,
                radius: botEffectiveBodyRadius(bots[index].score)
            )
            seg.position = bots[index].body.last?.position ?? head.position
            addChild(seg)
            bots[index].body.append(seg)
        }
        while bots[index].body.count > target && bots[index].body.count > 1 {
            bots[index].body.last?.removeFromParent()
            bots[index].body.removeLast()
        }
        ensurePointCacheLength(bots[index].body.count, cache: &bots[index].bodyPositionCache)
        bots[index].posHistory.setCapacity(historyCapacity(forSegmentCount: bots[index].body.count))
        updateBotBodyScales(index)
        miniLeaderboardNeedsRefresh = true
    }

    func respawnBot(_ index: Int) {
        guard !bots[index].isDead else { return }
        if bots[index].isActive {
            spawnDeathFood(at: bots[index].bodyPositionCache,
                           colorIndex: bots[index].colorIndex,
                           patternIndex: bots[index].patternIndex)
            deactivateBot(index)
        }
        // Mark dead with a tier-based respawn delay
        bots[index].isDead = true
        bots[index].isBoosting = false
        bots[index].boostTimer = 0
        bots[index].boostCooldown = 0
        bots[index].focusPoint = nil
        bots[index].focusTimer = 0
        bots[index].intent = .roam
        bots[index].isCircled = false
        bots[index].circledTimer = 0
        if bots[index].isNemesis && gameMode == .challenge {
            bots[index].respawnTimer = expertNemesisRespawnDelay
        } else {
            switch bots[index].tier {
            case .easy:   bots[index].respawnTimer = 4.0
            case .medium: bots[index].respawnTimer = 3.0
            case .hard:   bots[index].respawnTimer = 2.0
            }
        }
        miniLeaderboardNeedsRefresh = true
    }

    private func finishRespawn(_ index: Int) {
        bots[index].isDead = false
        bots[index].respawnTimer = 0
        // Respawn inside the bot's home zone so coverage stays distributed.
        bots[index].position = randomPositionInZone(for: index)
        let playerPosSafe = snakeHead.position
        for _ in 0..<5 {
            let dxSafe = bots[index].position.x - playerPosSafe.x
            let dySafe = bots[index].position.y - playerPosSafe.y
            if dxSafe * dxSafe + dySafe * dySafe > 1600 * 1600 { break }
            bots[index].position = randomPositionInZone(for: index)
        }
        bots[index].angle = CGFloat.random(in: 0...(2 * .pi))
        bots[index].targetAngle = bots[index].angle
        configureBotIdentity(index: index, preservePersonality: true)
        activateBot(index)
        if bots[index].isNemesis && gameMode == .challenge {
            spawnNemesisBanner()
        }
        miniLeaderboardNeedsRefresh = true
    }

    func botSpeed(for index: Int, includeBoost: Bool = true) -> CGFloat {
        let base: CGFloat
        switch bots[index].tier {
        case .easy:   base = botSpeedEasy
        case .medium: base = botSpeedMedium
        case .hard:   base = botSpeedHard
        }
        let profile = GameLogic.botPersonalityProfile(for: bots[index].personality)
        let scoreFraction = CGFloat(min(bots[index].score, botSpeedScoreCap)) / CGFloat(botSpeedScoreCap * 2)
        var speed = base * (1.0 + scoreFraction) * profile.cruiseSpeedMultiplier
        if bots[index].isNemesis { speed *= 1.28 }
        // Expert mode: all bots are faster, making gameplay harder.
        if gameMode == .challenge { speed *= expertBotSpeedMultiplier }
        if includeBoost && bots[index].isBoosting {
            speed *= botBoostMultiplier
        }
        return speed
    }

    func botTurnSpeed(for index: Int) -> CGFloat {
        let profile = GameLogic.botPersonalityProfile(for: bots[index].personality)
        let boostAdjustment: CGFloat = bots[index].isBoosting ? 0.96 : 1.0
        let nemesisBonus: CGFloat = bots[index].isNemesis ? 1.20 : 1.0
        // Per-tier base turn speed: hard bots turn nearly as well as the player (340°/s)
        let tierBase: CGFloat
        switch bots[index].tier {
        case .hard:   tierBase = 320.0
        case .medium: tierBase = 295.0
        case .easy:   tierBase = 270.0
        }
        return tierBase * profile.turnRateMultiplier * boostAdjustment * nemesisBonus
    }

    private func arenaClearance(at point: CGPoint) -> CGFloat {
        min(
            point.x - arenaMinX - headRadius,
            arenaMaxX - point.x - headRadius,
            point.y - arenaMinY - headRadius,
            arenaMaxY - point.y - headRadius
        )
    }

    private func bodyClearance(at point: CGPoint, botIndex i: Int) -> (clearance: CGFloat, hardCollision: Bool) {
        let hardLimit = collisionRadius + bodySegmentRadius + 3
        let softLimit = collisionRadius + bodySegmentRadius + 24
        var minClearance = CGFloat.greatestFiniteMagnitude

        // Use plain CGPoint cache instead of SKNode .position (avoids ObjC runtime overhead).
        // Bounding-box fast rejection skips ~90% of hypot() calls.
        for pos in bodyPositionCache {
            let dx = point.x - pos.x
            let dy = point.y - pos.y
            if abs(dx) > hardLimit || abs(dy) > hardLimit { continue }
            let dist = hypot(dx, dy) - hardLimit
            minClearance = min(minClearance, dist)
            if dist < 0 { return (dist, true) }
        }

        for j in bots.indices where j != i && bots[j].isActive && !bots[j].isDead {
            for pos in bots[j].bodyPositionCache {
                let dx = point.x - pos.x
                let dy = point.y - pos.y
                if abs(dx) > hardLimit || abs(dy) > hardLimit { continue }
                let dist = hypot(dx, dy) - hardLimit
                minClearance = min(minClearance, dist)
                if dist < 0 { return (dist, true) }
            }
        }

        return (minClearance.isFinite ? minClearance + (softLimit - hardLimit) : softLimit, false)
    }

    private func nearbyThreats(for i: Int, radius: CGFloat = 820) -> [BotThreatSnapshot] {
        var threats: [BotThreatSnapshot] = []
        let pos = bots[i].position

        let playerDistance = hypot(snakeHead.position.x - pos.x, snakeHead.position.y - pos.y)
        if playerDistance < radius {
            threats.append(BotThreatSnapshot(
                id: -1,
                position: snakeHead.position,
                angle: currentAngle,
                speed: currentPlayerForwardSpeed(),
                length: bodySegments.count,
                isPlayer: true
            ))
        }

        for j in bots.indices where j != i && bots[j].isActive && !bots[j].isDead {
            let distance = hypot(bots[j].position.x - pos.x, bots[j].position.y - pos.y)
            guard distance < radius else { continue }
            threats.append(BotThreatSnapshot(
                id: j,
                position: bots[j].position,
                angle: bots[j].angle,
                speed: botSpeed(for: j),
                length: bots[j].bodyLength,
                isPlayer: false
            ))
        }

        return threats
    }

    /// Rebuilds per-food cluster bonuses when the food set changes (lazy, O(n) with spatial grid).
    private func rebuildClusterBonusesIfNeeded() {
        guard clusterBonusDirty else { return }

        let clusterRadius: CGFloat = 110
        // Spatial grid: cell size equals the cluster radius so adjacent cells cover the full range.
        var grid: [GridCell: [Int]] = [:]
        grid.reserveCapacity(foodItems.count)
        for (i, food) in foodItems.enumerated() where food.parent != nil {
            let cell = GridCell(
                x: Int(food.position.x / clusterRadius),
                y: Int(food.position.y / clusterRadius)
            )
            grid[cell, default: []].append(i)
        }

        cachedClusterBonuses = Array(repeating: 0, count: foodItems.count)
        for i in foodItems.indices where foodItems[i].parent != nil {
            var bonus: CGFloat = 0
            let px = foodItems[i].position.x
            let py = foodItems[i].position.y
            let cx = Int(px / clusterRadius)
            let cy = Int(py / clusterRadius)
            // Only inspect 3×3 neighbourhood of cells; at cell size == clusterRadius, items
            // in cells ≥ 2 away are guaranteed to exceed the radius so no check is needed.
            for dcx in -1...1 {
                for dcy in -1...1 {
                    guard let neighbors = grid[GridCell(x: cx + dcx, y: cy + dcy)] else { continue }
                    for j in neighbors {
                        guard j != i else { continue }
                        let dx = foodItems[j].position.x - px
                        let dy = foodItems[j].position.y - py
                        guard dx * dx + dy * dy < clusterRadius * clusterRadius else { continue }
                        switch foodTypes[j] {
                        case .death: bonus += 0.55
                        case .trail: bonus += 0.18
                        default:     bonus += 0.10
                        }
                    }
                }
            }
            cachedClusterBonuses[i] = min(2.4, bonus)
        }
        clusterBonusDirty = false
    }

    private func interestingFoodTargets(for i: Int, limit: Int = 8) -> [BotFoodTarget] {
        let profile = GameLogic.botPersonalityProfile(for: bots[i].personality)
        let position = bots[i].position

        rebuildClusterBonusesIfNeeded()
        rebuildFoodGridIfNeeded()

        // Maintain a bounded buffer of the top `limit` candidates as we scan, replacing the
        // worst entry when a better one is found. This avoids allocating and sorting the full
        // candidate array (O(n log n) → O(n · limit) ≈ O(n) for small limit=8).
        var targets: [BotFoodTarget] = []
        targets.reserveCapacity(limit + 1)

        // Use the spatial grid to restrict the scan to cells within foodSearchRadius.
        // cellRadius = ceil(foodSearchRadius / cellSize): e.g. 800/200 = 4 → 9×9 = 81 cells.
        let cellRadius = Int(ceil(profile.foodSearchRadius / foodGridCellSize))
        let hc = foodCell(for: position)
        let searchRadiusSq = profile.foodSearchRadius * profile.foodSearchRadius

        for dcx in -cellRadius...cellRadius {
            for dcy in -cellRadius...cellRadius {
                guard let indices = foodSpatialGrid[GridCell(x: hc.x + dcx, y: hc.y + dcy)] else { continue }
                for index in indices {
                    guard index < foodItems.count else { continue }
                    let food = foodItems[index]
                    guard food.parent != nil else { continue }
                    let fdx = food.position.x - position.x
                    let fdy = food.position.y - position.y
                    let distSq = fdx * fdx + fdy * fdy
                    guard distSq < searchRadiusSq else { continue }
                    let distance = distSq.squareRoot()

                    let bonus = index < cachedClusterBonuses.count ? cachedClusterBonuses[index] : 0
                    let utility = GameLogic.botFoodValue(
                        type: foodTypes[index],
                        clusterBonus: bonus,
                        greed: profile.greed,
                        scavengerBias: profile.scavengerBias
                    ) * max(0.18, 1.0 - distance / profile.foodSearchRadius)

                    guard utility > 0.5 else { continue }

                    let candidate = BotFoodTarget(index: index, position: food.position, type: foodTypes[index], utility: utility)
                    if targets.count < limit {
                        targets.append(candidate)
                    } else if let worstIdx = targets.indices.min(by: { targets[$0].utility < targets[$1].utility }),
                              targets[worstIdx].utility < utility {
                        targets[worstIdx] = candidate
                    }
                }
            }
        }

        targets.sort { $0.utility > $1.utility }

        // --- Super Mouse injection ---
        // If the mouse is active, inject it as a high-value synthetic food target so bots
        // steer toward it. The sentinel index (foodItems.count) is safely skipped by the
        // `guard index < foodItems.count` in checkBotFoodCollision — the actual eat is
        // handled by checkBotCatchesMouse() instead.
        if superMouseState == .active || superMouseState == .trapped {
            let mdx = superMousePosition.x - position.x
            let mdy = superMousePosition.y - position.y
            let mouseDist = hypot(mdx, mdy)
            if mouseDist < profile.foodSearchRadius {
                // Personality-driven utility — independent of tier.
                // Regular food tops out ~8, death food ~12; mouse beats all for hunters.
                let mouseUtility: CGFloat
                switch bots[i].personality {
                case .nemesis:      mouseUtility = 34.0  // drops everything, hunts relentlessly
                case .hunter:       mouseUtility = 30.0  // primary target the moment it's visible
                case .interceptor:  mouseUtility = 27.0  // cuts off escape routes, locks on hard
                case .sprinter:     mouseUtility = 23.0  // uses speed, boosts straight at it
                case .opportunist:  mouseUtility = 16.0  // worth a detour if clearly reachable
                case .trickster:    mouseUtility = 13.0  // erratic but genuinely interested
                case .vulture:      mouseUtility = 11.0  // spots it from afar, approaches cautiously
                case .scavenger:    mouseUtility =  6.0  // prefers safe trail food; mild interest
                case .coward:       mouseUtility =  2.5  // risky prey isn't worth it
                }
                let mouseTarget = BotFoodTarget(
                    index: foodItems.count,          // sentinel — out-of-bounds, safely skipped
                    position: superMousePosition,
                    type: .regular,
                    utility: mouseUtility
                )
                // Replace the weakest target if mouse utility wins, or just append if room
                if targets.count < limit {
                    targets.append(mouseTarget)
                } else if let worstIdx = targets.indices.min(by: { targets[$0].utility < targets[$1].utility }),
                          targets[worstIdx].utility < mouseUtility {
                    targets[worstIdx] = mouseTarget
                }
                targets.sort { $0.utility > $1.utility }
            }
        }

        return targets
    }

    private func interceptPoint(botIndex i: Int, threat: BotThreatSnapshot, cutMode: Bool) -> CGPoint {
        let selfSpeed = max(botSpeed(for: i), 1)
        let distance = hypot(threat.position.x - bots[i].position.x, threat.position.y - bots[i].position.y)
        let lookahead = min(1.25, max(0.45, distance / selfSpeed))
        let future = GameLogic.projectedPoint(from: threat.position, angle: threat.angle, distance: threat.speed * lookahead)
        let lead = CGFloat(cutMode ? 110 : 65)
        return GameLogic.projectedPoint(from: future, angle: threat.angle, distance: lead)
    }

    private func interceptOpportunity(botIndex i: Int, threat: BotThreatSnapshot, cutMode: Bool) -> CGFloat {
        let lengthAdvantage = bots[i].bodyLength - threat.length
        guard lengthAdvantage > (cutMode ? 2 : 0) else { return 0 }

        let point = interceptPoint(botIndex: i, threat: threat, cutMode: cutMode)
        let angleToPoint = atan2(point.y - bots[i].position.y, point.x - bots[i].position.x)
        let distance = hypot(point.x - bots[i].position.x, point.y - bots[i].position.y)
        let align = max(0, cos(GameLogic.shortestAngleDiff(from: bots[i].angle, to: angleToPoint)))
        let distFactor = max(0, 1.0 - distance / 760)
        let crossFactor = cutMode
            ? max(0.25, abs(sin(GameLogic.shortestAngleDiff(from: threat.angle, to: angleToPoint))))
            : 1.0

        return align * distFactor * CGFloat(lengthAdvantage) * crossFactor / 12.0
    }

    private func strategicSnapshot(botIndex i: Int,
                                   profile: BotPersonalityProfile,
                                   threats: [BotThreatSnapshot],
                                   foods: [BotFoodTarget]) -> BotModeSnapshot {
        let minWallClearance = arenaClearance(at: bots[i].position)
        var immediateDanger = max(0, 1.0 - minWallClearance / max(profile.desiredClearance * 1.15, 1))
        var crowding: CGFloat = 0
        var huntOpportunity: CGFloat = 0
        var cutOpportunity: CGFloat = 0

        for threat in threats {
            let distance = hypot(threat.position.x - bots[i].position.x, threat.position.y - bots[i].position.y)
            let sizeFactor = CGFloat(threat.length - bots[i].bodyLength)
            let pressure = max(0, 1.0 - distance / (280 + max(0, sizeFactor) * 8))
            if sizeFactor >= -1 {
                immediateDanger = max(immediateDanger, pressure * (sizeFactor > 0 ? 1.0 : 0.58))
            }
            crowding += max(0, 1.0 - distance / 520)
            huntOpportunity = max(huntOpportunity, interceptOpportunity(botIndex: i, threat: threat, cutMode: false))
            cutOpportunity = max(cutOpportunity, interceptOpportunity(botIndex: i, threat: threat, cutMode: true))
        }

        let bestFood = foods.filter { $0.type != .death && $0.type != .trail }.map(\.utility).max() ?? 0
        let bestScavenge = foods.filter { $0.type == .death || $0.type == .trail }.map(\.utility).max() ?? 0

        return BotModeSnapshot(
            immediateDanger: min(1.0, immediateDanger),
            escapeRouteQuality: GameLogic.clearanceScore(minClearance: minWallClearance, desired: profile.desiredClearance),
            foodOpportunity: min(1.0, bestFood / 20),
            scavengingOpportunity: min(1.0, bestScavenge / 28),
            huntOpportunity: min(1.0, huntOpportunity),
            cutOpportunity: min(1.0, cutOpportunity * (1 + profile.cutBias * 0.2)),
            nearbyCrowding: min(1.0, crowding / 3.0),
            personality: profile
        )
    }

    private func foodContestPenalty(botIndex i: Int,
                                    target: BotFoodTarget,
                                    threats: [BotThreatSnapshot],
                                    selfSpeed: CGFloat) -> CGFloat {
        let profile = GameLogic.botPersonalityProfile(for: bots[i].personality)
        let riskTolerance = GameLogic.clamp01(0.55 + profile.aggression * 0.25 - profile.caution * 0.20)
        var penalty: CGFloat = 0

        for threat in threats {
            let rivalDistance = hypot(threat.position.x - target.position.x, threat.position.y - target.position.y)
            guard rivalDistance < 340 else { continue }
            let contest = BotFoodContestSnapshot(
                selfDistance: hypot(bots[i].position.x - target.position.x, bots[i].position.y - target.position.y),
                selfSpeed: selfSpeed,
                rivalDistance: rivalDistance,
                rivalSpeed: threat.speed,
                value: target.utility,
                rivalLengthAdvantage: CGFloat(threat.length - bots[i].bodyLength),
                riskTolerance: riskTolerance
            )

            if !GameLogic.shouldContestFood(contest) {
                penalty = max(penalty, target.utility * (threat.length >= bots[i].bodyLength ? 1.30 : 0.80))
            } else if threat.length > bots[i].bodyLength {
                penalty = max(penalty, target.utility * 0.24)
            }
        }

        return penalty
    }

    private func shouldBoostForFood(botIndex i: Int,
                                    target: BotFoodTarget,
                                    threats: [BotThreatSnapshot],
                                    selfSpeed: CGFloat,
                                    minClearance: CGFloat) -> Bool {
        guard bots[i].boostCooldown <= 0, target.utility > 14 else { return false }
        guard minClearance > GameLogic.botPersonalityProfile(for: bots[i].personality).desiredClearance * 0.70 else { return false }

        let boostedSpeed = selfSpeed * botBoostMultiplier
        let profile = GameLogic.botPersonalityProfile(for: bots[i].personality)
        let riskTolerance = GameLogic.clamp01(0.58 + profile.boostBias * 0.24 - profile.caution * 0.16)

        for threat in threats {
            let rivalDistance = hypot(threat.position.x - target.position.x, threat.position.y - target.position.y)
            guard rivalDistance < 360 else { continue }

            let normalContest = GameLogic.shouldContestFood(BotFoodContestSnapshot(
                selfDistance: hypot(bots[i].position.x - target.position.x, bots[i].position.y - target.position.y),
                selfSpeed: selfSpeed,
                rivalDistance: rivalDistance,
                rivalSpeed: threat.speed,
                value: target.utility,
                rivalLengthAdvantage: CGFloat(threat.length - bots[i].bodyLength),
                riskTolerance: riskTolerance
            ))

            let boostedContest = GameLogic.shouldContestFood(BotFoodContestSnapshot(
                selfDistance: hypot(bots[i].position.x - target.position.x, bots[i].position.y - target.position.y),
                selfSpeed: boostedSpeed,
                rivalDistance: rivalDistance,
                rivalSpeed: threat.speed,
                value: target.utility,
                rivalLengthAdvantage: CGFloat(threat.length - bots[i].bodyLength),
                riskTolerance: riskTolerance
            ))

            if !normalContest && boostedContest {
                return true
            }
        }

        return target.type == .death &&
            hypot(target.position.x - bots[i].position.x, target.position.y - bots[i].position.y) < 240 &&
            profile.boostBias > 0.60
    }

    private func candidateAngles(botIndex i: Int,
                                 intent: BotIntent,
                                 threats: [BotThreatSnapshot],
                                 foods: [BotFoodTarget]) -> [CGFloat] {
        var angles: [CGFloat] = []
        let base = bots[i].angle
        let sweepRange = intent == .escape ? -18...18 : -14...14
        let increment: CGFloat = intent == .escape ? (CGFloat.pi / 20) : (CGFloat.pi / 18)
        for step in sweepRange {
            angles.append(base + CGFloat(step) * increment)
        }

        let position = bots[i].position
        if let focus = bots[i].focusPoint {
            angles.append(atan2(focus.y - position.y, focus.x - position.x))
        }

        angles.append(atan2(bots[i].roamAnchor.y - position.y, bots[i].roamAnchor.x - position.x))
        angles.append(base + .pi)

        for food in foods.prefix(intent == .escape ? 3 : 6) {
            let angle = atan2(food.position.y - position.y, food.position.x - position.x)
            angles.append(angle)
            angles.append(angle + .pi / 18)
            angles.append(angle - .pi / 18)
        }

        for threat in threats.prefix(5) {
            let away = atan2(position.y - threat.position.y, position.x - threat.position.x)
            angles.append(away)
            angles.append(away + .pi / 10)
            angles.append(away - .pi / 10)

            if bots[i].bodyLength > threat.length + 1 {
                let intercept = interceptPoint(botIndex: i, threat: threat, cutMode: intent == .cutOff)
                let interceptAngle = atan2(intercept.y - position.y, intercept.x - position.x)
                angles.append(interceptAngle)
                angles.append(interceptAngle + .pi / 16)
                angles.append(interceptAngle - .pi / 16)
            }
        }

        var unique: [CGFloat] = []
        var seen: Set<Int> = []
        for angle in angles {
            let normalized = atan2(sin(angle), cos(angle))
            let bucket = Int(((normalized + .pi) * 180 / .pi).rounded())
            if seen.insert(bucket).inserted {
                unique.append(normalized)
            }
        }
        return unique
    }

    private func headingScore(botIndex i: Int,
                              angle: CGFloat,
                              intent: BotIntent,
                              profile: BotPersonalityProfile,
                              threats: [BotThreatSnapshot],
                              foods: [BotFoodTarget]) -> BotDecision {
        let selfSpeed = botSpeed(for: i, includeBoost: false)
        let tierHorizon: CGFloat
        switch bots[i].tier {
        case .easy:   tierHorizon = 0.85
        case .medium: tierHorizon = 1.00
        case .hard:   tierHorizon = 1.10
        }

        let horizon = tierHorizon * profile.horizonMultiplier
        let steps = 5
        let start = bots[i].position
        let pathEnd = GameLogic.projectedPoint(from: start, angle: angle, distance: selfSpeed * horizon)
        var minClearance = CGFloat.greatestFiniteMagnitude
        var risk: CGFloat = 0
        var escapeGain: CGFloat = 0

        for step in 1...steps {
            let t = horizon * CGFloat(step) / CGFloat(steps)
            let point = GameLogic.projectedPoint(from: start, angle: angle, distance: selfSpeed * t)
            let wallClearance = arenaClearance(at: point)
            minClearance = min(minClearance, wallClearance)
            if wallClearance < max(20, profile.desiredClearance * 0.42) {
                return BotDecision(angle: angle, intent: intent, shouldBoost: false, score: -.greatestFiniteMagnitude, focusPoint: nil)
            }

            let body = bodyClearance(at: point, botIndex: i)
            minClearance = min(minClearance, body.clearance)
            if body.hardCollision {
                return BotDecision(angle: angle, intent: intent, shouldBoost: false, score: -.greatestFiniteMagnitude, focusPoint: nil)
            }

            for threat in threats {
                let predicted = GameLogic.projectedPoint(from: threat.position, angle: threat.angle, distance: threat.speed * t)
                let headGap = hypot(point.x - predicted.x, point.y - predicted.y)
                let headSafeDistance = headRadius * 2 + 20
                if headGap < headSafeDistance {
                    return BotDecision(angle: angle, intent: intent, shouldBoost: false, score: -.greatestFiniteMagnitude, focusPoint: nil)
                }

                let sizeDifference = threat.length - bots[i].bodyLength
                let proximity = max(0, 1.0 - headGap / (240 + max(CGFloat(sizeDifference), 0) * 8))
                let threatWeight: CGFloat = threat.isPlayer ? 1.15 : 1.0
                if sizeDifference >= 0 {
                    risk += proximity * (1.1 + CGFloat(max(0, sizeDifference)) * 0.05) * threatWeight
                } else {
                    risk += proximity * 0.18 * threatWeight
                }

                if sizeDifference > 0 {
                    let startGap = hypot(start.x - threat.position.x, start.y - threat.position.y)
                    escapeGain += max(0, (headGap - startGap) / 120)
                }
            }
        }

        let clearanceScore = GameLogic.clearanceScore(minClearance: minClearance, desired: profile.desiredClearance)
        var score = clearanceScore * (44 + profile.caution * 12)
        score += escapeGain * (intent == .escape ? 14 : 5)

        let turnDiff = abs(GameLogic.shortestAngleDiff(from: bots[i].angle, to: angle))
        score -= turnDiff * (10.4 - profile.turnRateMultiplier * 2.8)

        if let focus = bots[i].focusPoint {
            let focusAngle = atan2(focus.y - start.y, focus.x - start.x)
            score += max(0, cos(GameLogic.shortestAngleDiff(from: angle, to: focusAngle))) * 10 * profile.targetStickiness
        }

        let roamAngle = atan2(bots[i].roamAnchor.y - start.y, bots[i].roamAnchor.x - start.x)
        score += max(0, cos(GameLogic.shortestAngleDiff(from: angle, to: roamAngle))) * (intent == .roam ? 10 : 3)

        var bestFoodContribution: CGFloat = -.greatestFiniteMagnitude
        var selectedFood: BotFoodTarget?

        for food in foods {
            let pathDistance = GameLogic.distanceFromPoint(food.position, toSegment: start, pathEnd)
            guard pathDistance < max(56, profile.desiredClearance * 0.85) else { continue }

            let foodDistance = hypot(food.position.x - start.x, food.position.y - start.y)
            let targetAngle = atan2(food.position.y - start.y, food.position.x - start.x)
            let alignment = max(0, cos(GameLogic.shortestAngleDiff(from: angle, to: targetAngle)))
            var contribution = food.utility * alignment * max(0.14, 1.0 - foodDistance / (profile.foodSearchRadius * 1.05))
            contribution -= foodContestPenalty(botIndex: i, target: food, threats: threats, selfSpeed: selfSpeed)

            switch intent {
            case .scavenge:
                contribution *= (food.type == .death || food.type == .trail) ? 1.28 : 0.76
            case .escape:
                contribution *= 0.55
            case .hunt, .cutOff:
                contribution *= (food.type == .death ? 1.12 : 0.74)
            case .roam:
                contribution *= 0.88
            case .forage:
                break
            }

            if contribution > bestFoodContribution {
                bestFoodContribution = contribution
                selectedFood = food
            }
        }

        if selectedFood != nil {
            score += bestFoodContribution
        }

        var bestInterceptBonus: CGFloat = 0
        var interceptFocus: CGPoint? = nil
        if intent == .hunt || intent == .cutOff {
            for threat in threats {
                let lengthAdvantage = bots[i].bodyLength - threat.length
                guard lengthAdvantage > (intent == .cutOff ? 2 : 0) else { continue }

                let intercept = interceptPoint(botIndex: i, threat: threat, cutMode: intent == .cutOff)
                let interceptAngle = atan2(intercept.y - start.y, intercept.x - start.x)
                let interceptDistance = hypot(intercept.x - start.x, intercept.y - start.y)
                let alignment = max(0, cos(GameLogic.shortestAngleDiff(from: angle, to: interceptAngle)))
                let distanceFactor = max(0, 1.0 - interceptDistance / 760)
                let crossFactor = intent == .cutOff
                    ? max(0.25, abs(sin(GameLogic.shortestAngleDiff(from: threat.angle, to: interceptAngle))))
                    : 1.0
                let bonusBase = intent == .cutOff ? (24 + profile.cutBias * 12) : (18 + profile.aggression * 10)
                let bonus = alignment * distanceFactor * crossFactor * CGFloat(lengthAdvantage) * bonusBase / 10.0
                if bonus > bestInterceptBonus {
                    bestInterceptBonus = bonus
                    interceptFocus = intercept
                }
            }
        }
        score += bestInterceptBonus

        let unpredictable = sin(CGFloat(frameCounter) * 0.045 + CGFloat(bots[i].id) * 1.3) * profile.unpredictability * 2.5
        score += unpredictable
        score -= risk * (26 + profile.caution * 18)

        if intent != .escape && clearanceScore < 0.46 {
            score -= 30
        }

        var shouldBoost = false
        if bots[i].boostCooldown <= 0 && minClearance > profile.desiredClearance * 0.70 {
            if intent == .escape && risk > 0.95 {
                shouldBoost = true
            } else if let selectedFood, shouldBoostForFood(botIndex: i, target: selectedFood, threats: threats, selfSpeed: selfSpeed, minClearance: minClearance) {
                shouldBoost = true
            } else if (intent == .hunt || intent == .cutOff) && bestInterceptBonus > 18 && risk < 0.70 && profile.boostBias > 0.52 {
                shouldBoost = true
            }
        }

        let focusPoint = bestInterceptBonus > max(0, bestFoodContribution * 0.92)
            ? interceptFocus
            : selectedFood?.position

        return BotDecision(angle: angle, intent: intent, shouldBoost: shouldBoost, score: score, focusPoint: focusPoint)
    }

    private func chooseBestHeading(for i: Int) -> BotDecision {
        let profile = GameLogic.botPersonalityProfile(for: bots[i].personality)
        let threats = nearbyThreats(for: i, radius: max(620, profile.foodSearchRadius))
        let foods = interestingFoodTargets(for: i)
        let snapshot = strategicSnapshot(botIndex: i, profile: profile, threats: threats, foods: foods)
        var intent = GameLogic.chooseBotIntent(snapshot)
        if bots[i].isNemesis {
            intent = snapshot.immediateDanger > 0.76 ? .escape : (snapshot.cutOpportunity > 0.42 ? .cutOff : .hunt)
            // Lock onto the longest snake anywhere on the map (player or bot)
            if intent != .escape {
                let allTargets = nearbyThreats(for: i, radius: 3600)
                if let biggest = allTargets.max(by: { $0.length < $1.length }) {
                    bots[i].focusPoint = biggest.position
                    bots[i].focusTimer = 1.2
                }
            }
        }

        // --- Super Mouse chase lock ---
        // When the mouse is active and within this bot's search radius, hunting personalities
        // explicitly set focusPoint to the current mouse position every replan. This keeps the
        // stickiness-weighted heading bonus continuously pointing at the (moving) mouse rather
        // than drifting between replans. Non-hunting bots rely solely on food utility scoring.
        if snapshot.immediateDanger <= 0.72,
           superMouseState == .active || superMouseState == .trapped,
           foods.contains(where: { $0.index == foodItems.count }) {

            let distToMouse = hypot(bots[i].position.x - superMousePosition.x,
                                    bots[i].position.y - superMousePosition.y)
            if distToMouse < profile.foodSearchRadius {
                switch bots[i].personality {
                case .nemesis:
                    // Nemesis overrides its snake-hunt target with the mouse when it's closer
                    bots[i].focusPoint = superMousePosition
                    bots[i].focusTimer = profile.replanInterval + 0.20
                    if intent != .escape { intent = .cutOff }   // uses intercept geometry on mouse
                case .hunter:
                    bots[i].focusPoint = superMousePosition
                    bots[i].focusTimer = profile.replanInterval + 0.18
                    if intent != .escape { intent = .forage }
                case .interceptor:
                    bots[i].focusPoint = superMousePosition
                    bots[i].focusTimer = profile.replanInterval + 0.22  // stubborn lock
                    if intent != .escape { intent = .cutOff }   // naturally tries to cut off path
                case .sprinter:
                    bots[i].focusPoint = superMousePosition
                    bots[i].focusTimer = profile.replanInterval + 0.12
                    if intent != .escape { intent = .forage }
                case .opportunist, .trickster:
                    // Soft lock — only if mouse is within 500pt (they don't cross the map for it)
                    if distToMouse < 500 {
                        bots[i].focusPoint = superMousePosition
                        bots[i].focusTimer = profile.replanInterval + 0.08
                    }
                default:
                    break   // scavenger & coward: food utility bias only, no explicit focus lock
                }
            }
        }

        let candidates = candidateAngles(botIndex: i, intent: intent, threats: threats, foods: foods)

        var best = BotDecision(
            angle: bots[i].angle,
            intent: intent,
            shouldBoost: false,
            score: -.greatestFiniteMagnitude,
            focusPoint: bots[i].focusPoint
        )

        for candidate in candidates {
            let decision = headingScore(
                botIndex: i,
                angle: candidate,
                intent: intent,
                profile: profile,
                threats: threats,
                foods: foods
            )
            if decision.score > best.score {
                best = decision
            }
        }

        if best.score == -.greatestFiniteMagnitude {
            let escapeAngle = atan2(
                bots[i].position.y - snakeHead.position.y,
                bots[i].position.x - snakeHead.position.x
            )
            return BotDecision(angle: escapeAngle, intent: .escape, shouldBoost: bots[i].boostCooldown <= 0, score: 0, focusPoint: nil)
        }

        return best
    }

    private func chooseAmbientDecision(for i: Int) -> BotDecision {
        let profile = GameLogic.botPersonalityProfile(for: bots[i].personality)
        if bots[i].dirChangeTimer <= 0 || hypot(bots[i].position.x - bots[i].roamAnchor.x, bots[i].position.y - bots[i].roamAnchor.y) < 130 {
            bots[i].roamAnchor = randomPositionInZone(for: i)
            bots[i].dirChangeTimer = CGFloat.random(in: 1.8...4.6)
        }

        let nearFood = interestingFoodTargets(for: i, limit: 3)
        var best = BotDecision(angle: bots[i].angle, intent: .roam, shouldBoost: false, score: -.greatestFiniteMagnitude, focusPoint: nil)
        var angles = [
            atan2(bots[i].roamAnchor.y - bots[i].position.y, bots[i].roamAnchor.x - bots[i].position.x),
            bots[i].angle,
            bots[i].angle + .pi / 14,
            bots[i].angle - .pi / 14
        ]
        for food in nearFood {
            angles.append(atan2(food.position.y - bots[i].position.y, food.position.x - bots[i].position.x))
        }

        for angle in angles {
            let pathEnd = GameLogic.projectedPoint(from: bots[i].position, angle: angle, distance: botSpeed(for: i, includeBoost: false) * 0.85)
            let clearance = arenaClearance(at: pathEnd)
            guard clearance > 18 else { continue }

            var score = GameLogic.clearanceScore(minClearance: clearance, desired: profile.desiredClearance) * 20
            score += max(0, cos(GameLogic.shortestAngleDiff(
                from: angle,
                to: atan2(bots[i].roamAnchor.y - bots[i].position.y, bots[i].roamAnchor.x - bots[i].position.x)
            ))) * 12

            if let food = nearFood.max(by: { $0.utility < $1.utility }) {
                let foodAngle = atan2(food.position.y - bots[i].position.y, food.position.x - bots[i].position.x)
                score += max(0, cos(GameLogic.shortestAngleDiff(from: angle, to: foodAngle))) * food.utility * 0.45
            }

            score += sin(CGFloat(frameCounter) * 0.03 + CGFloat(bots[i].id)) * profile.unpredictability * 2
            if score > best.score {
                best = BotDecision(angle: angle, intent: .roam, shouldBoost: false, score: score, focusPoint: nil)
            }
        }

        return best
    }

    private func updateBotBoostState(index i: Int, dt: CGFloat) {
        bots[i].dirChangeTimer -= dt
        bots[i].decisionTimer = max(0, bots[i].decisionTimer - dt)
        bots[i].boostCooldown = max(0, bots[i].boostCooldown - dt)

        if bots[i].focusTimer > 0 {
            bots[i].focusTimer -= dt
            if bots[i].focusTimer <= 0 { bots[i].focusPoint = nil }
        }

        bots[i].multiplierTimeLeft = max(0, bots[i].multiplierTimeLeft - dt)
        bots[i].magnetTimeLeft = max(0, bots[i].magnetTimeLeft - dt)
        bots[i].ghostTimeLeft = max(0, bots[i].ghostTimeLeft - dt)

        if bots[i].boostTimer > 0 {
            bots[i].boostTimer -= dt
            if bots[i].boostTimer <= 0 {
                bots[i].boostTimer = 0
                bots[i].isBoosting = false
                let cooldownRange = gameMode == .challenge ? expertBotBoostCooldownRange : botBoostCooldownRange
                bots[i].boostCooldown = bots[i].isNemesis
                    ? CGFloat.random(in: 0.40...1.00)
                    : CGFloat.random(in: cooldownRange)
            }
        }
    }

    private func applyBotDecision(_ decision: BotDecision, index i: Int) {
        let profile = GameLogic.botPersonalityProfile(for: bots[i].personality)
        bots[i].targetAngle = decision.angle
        bots[i].intent = decision.intent

        if let focus = decision.focusPoint {
            bots[i].focusPoint = focus
            bots[i].focusTimer = 0.55 + profile.targetStickiness * 0.45
        } else if decision.intent == .roam {
            bots[i].focusPoint = nil
            bots[i].focusTimer = 0
        }

        if decision.shouldBoost && !bots[i].isBoosting && bots[i].boostCooldown <= 0 {
            bots[i].isBoosting = true
            bots[i].boostTimer = bots[i].isNemesis ? CGFloat.random(in: 0.45...1.20) : CGFloat.random(in: botBoostDurationRange)
        }

        let jitter = CGFloat.random(in: -profile.unpredictability...profile.unpredictability) * 0.05
        bots[i].decisionTimer = max(0.12, profile.replanInterval + jitter)
    }

    private func updateBotVisuals(_ index: Int) {
        guard let head = bots[index].head else { return }

        bots[index].posHistory.append(head.position)

        head.position = bots[index].position
        head.zRotation = (bots[index].angle * 180 / .pi - 90) * .pi / 180
        // Guard SpriteKit property writes: setting unchanged values still triggers internal state dirty.
        // Nemesis uses its own glow/scale values to preserve the larger imposing look.
        if bots[index].isNemesis {
            let targetGlow: CGFloat = bots[index].isBoosting ? 26 : 18
            if head.glowWidth != targetGlow { head.glowWidth = targetGlow }
            let targetScale: CGFloat = bots[index].isBoosting ? 1.35 * 1.04 : 1.35
            if head.xScale != targetScale { head.setScale(targetScale) }
            // Shield ring: show/hide only when charge state changes
            if let ring = head.childNode(withName: "nemesisShieldRing") as? SKShapeNode {
                let shouldShow = bots[index].shieldCharges > 0
                if ring.isHidden == shouldShow {
                    ring.isHidden = !shouldShow
                    if shouldShow {
                        ring.run(SKAction.sequence([
                            SKAction.scale(to: 1.3, duration: 0.12),
                            SKAction.scale(to: 1.0, duration: 0.12)
                        ]))
                    }
                }
            }
        } else {
            let targetGlow: CGFloat = bots[index].isBoosting ? 10 : 5
            if head.glowWidth != targetGlow { head.glowWidth = targetGlow }
            let targetScale: CGFloat = bots[index].isBoosting ? 1.04 : 1.0
            if head.xScale != targetScale { head.setScale(targetScale) }
        }

        fillArcPositions(
            history: bots[index].posHistory,
            leadPos: bots[index].position,
            count: bots[index].body.count,
            spacing: segmentPixelSpacing,
            into: &bots[index].bodyPositionCache
        )
        let pattern = SnakePattern(rawValue: bots[index].patternIndex) ?? .solid
        let bodyCount = bots[index].body.count
        let botNeedsRotation = pattern == .cylinder || pattern == .armor || pattern == .leaf
        for (segmentIndex, segment) in bots[index].body.enumerated() {
            segment.position = bots[index].bodyPositionCache[segmentIndex]
            if botNeedsRotation && segmentIndex > 0
               && segmentIndex < bots[index].bodyPositionCache.count {
                let prev = bots[index].bodyPositionCache[segmentIndex - 1]
                let curr = bots[index].bodyPositionCache[segmentIndex]
                let dx = prev.x - curr.x
                let dy = prev.y - curr.y
                if dx * dx + dy * dy > 0.01 {
                    segment.zRotation = atan2(dy, dx) - (.pi / 2)
                }
            }
            // perf: skip glow on bot body segments entirely — heads retain glow, bodies don't need it.
            // Avoids per-frame GPU re-renders for every segment of every active bot.
        }
    }

    func updateBots(dt: CGFloat, updateAI: Bool) {
        let playerPos = snakeHead.position

        for i in 0..<bots.count {
            if bots[i].isDead {
                bots[i].respawnTimer -= dt
                if bots[i].respawnTimer <= 0 { finishRespawn(i) }
                continue
            }

            if bots[i].spawnTimer > 0 { bots[i].spawnTimer -= dt }
            updateBotBoostState(index: i, dt: dt)
            applyBotMagnetEffect(botIndex: i, dt: dt)

            // Tick circled timer
            if bots[i].circledTimer > 0 {
                bots[i].circledTimer -= dt
                if bots[i].circledTimer <= 0 { bots[i].isCircled = false }
            }

            let distanceToPlayer = hypot(bots[i].position.x - playerPos.x, bots[i].position.y - playerPos.y)

            if updateAI && bots[i].decisionTimer <= 0 {
                let decision = distanceToPlayer < botDetailedAIRadius
                    ? chooseBestHeading(for: i)
                    : chooseAmbientDecision(for: i)
                applyBotDecision(decision, index: i)
            }

            // Circled escape behavior: override target angle to find most clearance
            // Tests 16 directions against player body AND nearby bot bodies.
            if bots[i].isCircled {
                var bestAngle = bots[i].angle
                var bestClearance: CGFloat = 0
                let testCount = 16
                let probeDistance: CGFloat = 110
                // Pre-collect nearby bot indices (broad-phase) to avoid inner triple-loop
                let nearbyBotIndices = bots.indices.filter { j in
                    j != i && bots[j].isActive &&
                    abs(bots[j].position.x - bots[i].position.x) < 300 &&
                    abs(bots[j].position.y - bots[i].position.y) < 300
                }
                for testIdx in 0..<testCount {
                    let testAngle = CGFloat(testIdx) * (2 * .pi / CGFloat(testCount))
                    let tx = bots[i].position.x + cos(testAngle) * probeDistance
                    let ty = bots[i].position.y + sin(testAngle) * probeDistance
                    var minDist: CGFloat = 999
                    // Player body
                    for pt in bodyPositionCache {
                        let d = hypot(pt.x - tx, pt.y - ty)
                        if d < minDist { minDist = d }
                    }
                    // Other bot bodies
                    for j in nearbyBotIndices {
                        for pt in bots[j].bodyPositionCache {
                            let d = hypot(pt.x - tx, pt.y - ty)
                            if d < minDist { minDist = d }
                        }
                    }
                    if minDist > bestClearance {
                        bestClearance = minDist
                        bestAngle = testAngle
                    }
                }
                bots[i].targetAngle = bestAngle
                bots[i].isBoosting = true
            }

            smoothlyRotate(
                current: &bots[i].angle,
                target: bots[i].targetAngle,
                dt: dt,
                maxTurnSpeed: botTurnSpeed(for: i)
            )

            let moveDistance = botSpeed(for: i) * dt
            bots[i].position = GameLogic.projectedPoint(from: bots[i].position, angle: bots[i].angle, distance: moveDistance)

            if GameLogic.isOutsideArena(point: bots[i].position, radius: headRadius,
                                        arenaMinX: arenaMinX, arenaMaxX: arenaMaxX,
                                        arenaMinY: arenaMinY, arenaMaxY: arenaMaxY) {
                if bots[i].shieldCharges > 0 {
                    bots[i].shieldCharges -= 1
                    bots[i].position = CGPoint(
                        x: min(max(bots[i].position.x, arenaMinX + headRadius + 4), arenaMaxX - headRadius - 4),
                        y: min(max(bots[i].position.y, arenaMinY + headRadius + 4), arenaMaxY - headRadius - 4)
                    )
                } else {
                    respawnBot(i)
                    continue
                }
            }

            if bots[i].isActive {
                updateBotVisuals(i)

                bots[i].trailFoodTimer += dt
                let trailInterval = botTrailInterval * 0.65
                if bots[i].isBoosting, bots[i].trailFoodTimer >= trailInterval {
                    if let tailSeg = bots[i].body.last {
                        spawnTrailFood(at: tailSeg.position,
                                       colorIndex: bots[i].colorIndex,
                                       patternIndex: bots[i].patternIndex)
                    }
                    bots[i].trailFoodTimer = 0
                } else if !bots[i].isBoosting {
                    bots[i].trailFoodTimer = 0
                }
            }

            checkBotFoodCollision(i)
        }
    }

    private func applyBotPowerUp(type: FoodType, botIndex: Int) {
        switch type {
        case .shield:
            bots[botIndex].shieldCharges = min(2, bots[botIndex].shieldCharges + 1)
        case .multiplier:
            bots[botIndex].multiplierTimeLeft = 15.0
        case .magnet:
            bots[botIndex].magnetTimeLeft = 6.0
        case .ghost:
            bots[botIndex].ghostTimeLeft = 4.0
        case .regular, .trail, .death:
            break
        case .shrink:
            applyBotShrink(botIndex)
        }
    }

    /// Mirrors the player's applyShrink(). Reduces bot score by 30%; syncBotLength() contracts the body.
    private func applyBotShrink(_ index: Int) {
        guard bots[index].score > 0 else { return }
        bots[index].score = max(0, bots[index].score - bots[index].score * 30 / 100)
    }

    private func applyBotMagnetEffect(botIndex: Int, dt: CGFloat) {
        guard bots[botIndex].magnetTimeLeft > 0 else { return }

        rebuildFoodGridIfNeeded()
        let strength: CGFloat = 560 * dt
        let headPos = bots[botIndex].position
        let magnetRadiusSq = magnetRadius * magnetRadius
        let span = Int(ceil(magnetRadius / foodGridCellSize)) + 1
        let centerCell = foodCell(for: headPos)

        for dcx in -span...span {
            for dcy in -span...span {
                guard let indices = foodSpatialGrid[GridCell(x: centerCell.x + dcx, y: centerCell.y + dcy)] else { continue }
                for i in indices {
                    guard i < foodItems.count, i < foodTypes.count else { continue }
                    if foodTypes[i] == .trail || foodTypes[i] == .death { continue }
                    let food = foodItems[i]
                    guard food.parent != nil else { continue }
                    let dx = headPos.x - food.position.x
                    let dy = headPos.y - food.position.y
                    let distSq = dx * dx + dy * dy
                    guard distSq > 1, distSq < magnetRadiusSq else { continue }
                    let dist = sqrt(distSq)
                    let pull = strength * (1 - dist / magnetRadius)
                    food.position.x += (dx / dist) * pull
                    food.position.y += (dy / dist) * pull
                }
            }
        }
        foodGridDirty = true   // food positions changed; grid indices are stale
    }

    private func botNutrition(for type: FoodType, botIndex: Int) -> Int {
        let mult = bots[botIndex].multiplierTimeLeft > 0 ? 2 : 1
        switch type {
        case .regular:                              return 2 * mult
        case .trail:                                return 1 * mult
        case .death:                                return 5 * mult
        case .shield, .multiplier, .magnet, .ghost: return 2 * mult
        case .shrink:                               return 0
        }
    }

    func checkBotFoodCollision(_ botIndex: Int) {
        rebuildFoodGridIfNeeded()
        let headPosition = bots[botIndex].position
        let thresholdSq: CGFloat = (headRadius + foodRadius) * (headRadius + foodRadius)
        let hc = foodCell(for: headPosition)
        for dcx in -1...1 {
            for dcy in -1...1 {
                guard let indices = foodSpatialGrid[GridCell(x: hc.x + dcx, y: hc.y + dcy)] else { continue }
                for i in indices {
                    guard i < foodItems.count else { continue }
                    let food = foodItems[i]
                    let dx = headPosition.x - food.position.x
                    let dy = headPosition.y - food.position.y
                    if dx * dx + dy * dy < thresholdSq {
                        if foodTypes[i] == .trail { activeTrailFoodCount = max(0, activeTrailFoodCount - 1) }
                        let nutritionScore = botNutrition(for: foodTypes[i], botIndex: botIndex)
                        food.removeFromParent()
                        let type = removeFoodItem(at: i)
                        clusterBonusDirty = true
                        spawnFood()
                        bots[botIndex].score += nutritionScore
                        applyBotPowerUp(type: type, botIndex: botIndex)  // .shrink handled via applyBotShrink()
                        syncBotLength(botIndex)
                        miniLeaderboardNeedsRefresh = true
                        return
                    }
                }
            }
        }
    }

    func checkPlayerCollidesWithBotBodies() -> Bool {
        if ghostActive { return false }   // 👻 ghost: pass through bodies
        let interactionRadiusSq = interactionRadiusForPlayerBody() * interactionRadiusForPlayerBody()
        for bot in bots where bot.isActive && !bot.isDead && bot.spawnTimer <= 0 {
            if bot.ghostTimeLeft > 0 { continue }
            let dx = snakeHead.position.x - bot.position.x
            let dy = snakeHead.position.y - bot.position.y
            guard dx * dx + dy * dy <= interactionRadiusSq else { continue }
            if headCollidesWithPoints(
                snakeHead.position,
                points: bot.bodyPositionCache,
                combinedRadius: collisionRadius + bodySegmentRadius,
                skip: 1
            ) { return true }
        }
        return false
    }

    /// Offline: player head collides with a bot head → both die (head-to-head).
    func checkPlayerHeadVsBotHeads() -> Bool {
        guard !ghostActive else { return false }
        for i in 0..<bots.count {
            guard bots[i].isActive, !bots[i].isDead, bots[i].spawnTimer <= 0, let botHead = bots[i].head else { continue }
            let dist = hypot(snakeHead.position.x - botHead.position.x,
                             snakeHead.position.y - botHead.position.y)
            if dist < (headRadius + headRadius) {
                if bots[i].shieldCharges > 0 {
                    bots[i].shieldCharges -= 1
                } else {
                    respawnBot(i)   // bot dies simultaneously
                }
                return true     // player also dies (caller triggers playerGameOver)
            }
        }
        return false
    }

    /// Offline: any active bot's head hitting the player's body kills that bot.
    func checkBotHeadsHitPlayerBody() {
        
        let interactionRadius = interactionRadiusForPlayerBody()
        let interactionRadiusSq = interactionRadius * interactionRadius
        guard !bodyPositionCache.isEmpty else { return }
        for i in 0..<bots.count {
            guard bots[i].isActive, !bots[i].isDead, bots[i].spawnTimer <= 0, let botHead = bots[i].head else { continue }
            if bots[i].ghostTimeLeft > 0 { continue }
            let dx = snakeHead.position.x - botHead.position.x
            let dy = snakeHead.position.y - botHead.position.y
            guard dx * dx + dy * dy <= interactionRadiusSq else { continue }
            if bodyOccupancyContains(botHead.position) && headCollidesWithPoints(
                botHead.position,
                points: bodyPositionCache,
                combinedRadius: collisionRadius + bodySegmentRadius,
                skip: 1
            ) {
                if bots[i].shieldCharges > 0 {
                    bots[i].shieldCharges -= 1
                } else {
                    respawnBot(i)
                }
            }
        }
    }
    // MARK: - New Power-Up Effects

    /// 🧲 Magnet — pull nearby food items toward the snake head.
    /// Uses the food spatial grid to query only cells within magnetRadius, avoiding an O(n) full scan.
    func applyMagnetEffect() {
        rebuildFoodGridIfNeeded()
        let pullStrength: CGFloat   = 5.5
        let magnetRadiusSq: CGFloat = magnetRadius * magnetRadius
        let headPos = snakeHead.position
        let span = Int(ceil(magnetRadius / foodGridCellSize)) + 1
        let centerCell = foodCell(for: headPos)
        for dcx in -span...span {
            for dcy in -span...span {
                guard let indices = foodSpatialGrid[GridCell(x: centerCell.x + dcx, y: centerCell.y + dcy)] else { continue }
                for i in indices {
                    guard i < foodItems.count else { continue }
                    let food = foodItems[i]
                    guard food.parent != nil else { continue }
                    let dx = headPos.x - food.position.x
                    let dy = headPos.y - food.position.y
                    let distSq = dx * dx + dy * dy
                    guard distSq > 1, distSq < magnetRadiusSq else { continue }
                    let dist = hypot(dx, dy)
                    food.position = CGPoint(x: food.position.x + (dx / dist) * pullStrength,
                                            y: food.position.y + (dy / dist) * pullStrength)
                }
            }
        }
        foodGridDirty = true   // food positions changed; grid indices are stale
    }

    /// ✂️ Shrink — consolation bonus first, then reduce score by ~10% so syncSnakeLength() contracts body.
    func applyShrink() {
        guard score > 0 else { return }
        let bonus      = 3
        score         += bonus * scoreMultiplier       // consolation before reduction
        let reduction  = max(1, score * 10 / 100)
        score          = max(0, score - reduction)
        updateScoreDisplay()
        updateSpeedForScore()   // calls syncSnakeLength() → body contracts
        invincibleTimeLeft = 1.5   // extended escape window (was 0.8s)
        spawnFloatingText("✂️ -\(reduction) pts", at: CGPoint(x: snakeHead.position.x, y: snakeHead.position.y + 60))
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// 👻 Ghost — make the snake semi-transparent; body collision is skipped while active.
    func showGhostEffect() {
        snakeHead.alpha = 0.55
        for seg in bodySegments { seg.alpha = 0.55 }
        let flicker = SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.55, duration: 0.3),
            SKAction.fadeAlpha(to: 0.28, duration: 0.3)
        ]))
        snakeHead.run(flicker, withKey: "ghostFlicker")
        spawnFloatingText("👻 Ghost!", at: CGPoint(x: snakeHead.position.x, y: snakeHead.position.y + 60))
    }

    func hideGhostEffect() {
        snakeHead.removeAction(forKey: "ghostFlicker")
        snakeHead.alpha = 1.0
        for seg in bodySegments { seg.alpha = 1.0 }
        updateSegmentScales()   // restores correct scale per segment
    }

    /// 🧲 Magnet activation — floating text feedback.
    func showMagnetActivation() {
        spawnFloatingText("🧲 Magnet!", at: CGPoint(x: snakeHead.position.x, y: snakeHead.position.y + 60))
    }

    // MARK: - Arc-Length Body Positioning
    /// Returns `count` positions spaced `spacing` pixels apart along the path
    /// stored in `history` (oldest-first), starting from `leadPos` (the head).
    func fillArcPositions(history: PointRingBuffer, leadPos: CGPoint,
                          count: Int, spacing: CGFloat, into result: inout [CGPoint]) {
        ensurePointCacheLength(count, cache: &result)
        guard count > 0 else { return }

        var accumulated: CGFloat = 0
        var prev       = leadPos
        var targetDist = spacing

        var filled = 0
        history.forEachNewestToOldest { p in
            guard filled < count else { return false }
            let d    = hypot(p.x - prev.x, p.y - prev.y)
            let next = accumulated + d

            while filled < count && targetDist <= next {
                let t = d > 0 ? (targetDist - accumulated) / d : 0
                result[filled] = CGPoint(x: prev.x + (p.x - prev.x) * t,
                                         y: prev.y + (p.y - prev.y) * t)
                filled += 1
                targetDist += spacing
            }
            accumulated = next
            prev = p
            return true
        }

        let fallback = history.oldestPoint ?? leadPos
        while filled < count {
            result[filled] = fallback
            filled += 1
        }
    }

    // MARK: - AI / Smooth Rotation
    func findNearestFood(to position: CGPoint) -> SKNode? {
        foodItems.min(by: {
            hypot($0.position.x - position.x, $0.position.y - position.y) <
            hypot($1.position.x - position.x, $1.position.y - position.y)
        })
    }

    func smoothlyRotate(current: inout CGFloat, target: CGFloat, dt: CGFloat) {
        smoothlyRotate(current: &current, target: target, dt: dt, maxTurnSpeed: turnSpeed)
    }

    func smoothlyRotate(current: inout CGFloat, target: CGFloat, dt: CGFloat, maxTurnSpeed: CGFloat) {
        var diff = target - current
        while diff >  .pi { diff -= 2 * .pi }
        while diff < -.pi { diff += 2 * .pi }
        let maxTurn = maxTurnSpeed * .pi / 180.0 * dt
        if      diff >  maxTurn { current += maxTurn }
        else if diff < -maxTurn { current -= maxTurn }
        else                    { current  = target  }
    }

}
