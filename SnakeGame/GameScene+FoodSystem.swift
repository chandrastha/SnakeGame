import SpriteKit

// MARK: - FoodType
enum FoodType: Int {
    case regular = 0
    case shield = 1      // 🛡 absorbs one death
    case multiplier = 2  // ⭐ 2× score for 10s
    case trail = 3       // 🌱 left by snake movement
    case death = 4       // 💀 scattered from a dead snake body — 5 pts each
    case magnet = 5      // 🧲 pulls nearby food toward snake for 6s
    case ghost = 6       // 👻 pass through snake bodies for 4s
    case shrink = 7      // ✂️ instantly removes 10% of body (escape tool)
}

extension GameScene {

    // MARK: - Food System
    func spawnInitialFood() {
        for _ in 0..<foodCount { spawnFood() }
    }
    func randomSpawnFoodType() -> FoodType {
        let roll = Int.random(in: 0...99)
        let candidate: FoodType
        switch roll {
        case 0...94: candidate = .regular       // 95%
        case 95:     candidate = .shield        // 1%
        case 96:     candidate = .multiplier    // 1%
        case 97:     candidate = .magnet        // 1%
        case 98:     candidate = .ghost         // 1%
        default:     candidate = .shrink        // 1%
        }

        switch candidate {
        case .shield:
            if foodTypes.filter({ $0 == .shield }).count >= 2 { return .regular }
        case .multiplier:
            if foodTypes.filter({ $0 == .multiplier }).count >= 3 { return .regular }
        case .magnet:
            if foodTypes.filter({ $0 == .magnet }).count >= 3 { return .regular }
        case .ghost:
            if foodTypes.filter({ $0 == .ghost }).count >= 3 { return .regular }
        case .shrink:
            if foodTypes.filter({ $0 == .shrink }).count >= 3 { return .regular }
        default: break
        }
        return candidate
    }

    func makeRegularFoodNode() -> SKLabelNode {
        let food = SKLabelNode(text: fruitEmojis.randomElement())
        food.fontSize                = 17
        food.verticalAlignmentMode   = .center
        food.horizontalAlignmentMode = .center
        return food
    }

    func makeFoodNode(for type: FoodType) -> SKNode {
        switch type {
        case .regular:
            return makeRegularFoodNode()
        case .shield:
            return makeIconFoodNode("🛡")
        case .multiplier:
            return makeIconFoodNode("⭐")
        case .magnet:
            return makeIconFoodNode("🧲")
        case .ghost:
            return makeIconFoodNode("👻")
        case .shrink:
            return makeIconFoodNode("✂️")
        case .trail, .death:
            return makeIconFoodNode("●")
        }
    }

    func makeIconFoodNode(_ text: String) -> SKLabelNode {
        let food = SKLabelNode(text: text)
        food.fontSize                = 22
        food.verticalAlignmentMode   = .center
        food.horizontalAlignmentMode = .center
        return food
    }

    func spawnFood() {
        let type = randomSpawnFoodType()
        let food = makeFoodNode(for: type)

        // 60 % of spawns are biased toward high-traffic zones; 40 % are uniform random.
        var pos = CGFloat.random(in: 0...1) < 0.60 ? heatmapWeightedPosition() : randomPositionInArena()
        var attempts = 0
        while isPositionOnPlayerSnake(pos) && attempts < 20 {
            pos = randomPositionInArena()
            attempts += 1
        }
        food.position = pos
        addChild(food)
        foodItems.append(food)
        foodTypes.append(type)
        foodGridInsert(at: foodItems.count - 1)
        clusterBonusDirty = true
    }

    func randomPositionInArena() -> CGPoint {
        let minX = arenaMinX + foodPadding, maxX = arenaMaxX - foodPadding
        let minY = arenaMinY + foodPadding, maxY = arenaMaxY - foodPadding
        guard minX < maxX, minY < maxY else { return CGPoint(x: worldSize/2, y: worldSize/2) }
        return CGPoint(x: CGFloat.random(in: minX...maxX), y: CGFloat.random(in: minY...maxY))
    }

    // MARK: - Heatmap Helpers

    /// Sample snake positions into the movement heatmap and apply periodic decay.
    func updateMovementHeatmap(dt: CGFloat) {
        heatmapSampleTimer += dt
        heatmapDecayTimer  += dt

        if heatmapSampleTimer >= heatmapSampleInterval {
            heatmapSampleTimer = 0
            // Record player head
            if !isGameOver { recordHeatmapPosition(snakeHead.position) }
            // Record active bot heads (sampled to avoid cost)
            for bot in bots where bot.isActive && !bot.isDead {
                recordHeatmapPosition(bot.position)
            }
        }

        if heatmapDecayTimer >= heatmapDecayInterval {
            heatmapDecayTimer = 0
            for row in 0..<heatmapRows {
                for col in 0..<heatmapCols {
                    movementHeatmap[row][col] *= heatmapDecayFactor
                }
            }
        }
    }

    private func recordHeatmapPosition(_ pos: CGPoint) {
        let arenaW = arenaMaxX - arenaMinX
        let arenaH = arenaMaxY - arenaMinY
        guard arenaW > 0, arenaH > 0 else { return }
        let col = Int(((pos.x - arenaMinX) / arenaW) * CGFloat(heatmapCols))
        let row = Int(((pos.y - arenaMinY) / arenaH) * CGFloat(heatmapRows))
        let c = max(0, min(heatmapCols - 1, col))
        let r = max(0, min(heatmapRows - 1, row))
        movementHeatmap[r][c] += 1.0
    }

    /// Pick a food spawn position weighted toward high-activity heatmap cells.
    /// Falls back to a uniform random position if the heatmap is empty.
    func heatmapWeightedPosition() -> CGPoint {
        // Build cumulative weight array
        var total: Float = 0
        var weights: [Float] = []
        weights.reserveCapacity(heatmapRows * heatmapCols)
        for row in 0..<heatmapRows {
            for col in 0..<heatmapCols {
                total += movementHeatmap[row][col]
                weights.append(total)
            }
        }
        guard total > 0 else { return randomPositionInArena() }

        let pick = Float.random(in: 0..<total)
        var chosenIdx = weights.firstIndex(where: { $0 > pick }) ?? (heatmapRows * heatmapCols - 1)
        chosenIdx = max(0, min(heatmapRows * heatmapCols - 1, chosenIdx))

        let col = chosenIdx % heatmapCols
        let row = chosenIdx / heatmapCols
        let cellW = (arenaMaxX - arenaMinX) / CGFloat(heatmapCols)
        let cellH = (arenaMaxY - arenaMinY) / CGFloat(heatmapRows)
        let cellMinX = arenaMinX + CGFloat(col) * cellW + foodPadding
        let cellMaxX = arenaMinX + CGFloat(col + 1) * cellW - foodPadding
        let cellMinY = arenaMinY + CGFloat(row) * cellH + foodPadding
        let cellMaxY = arenaMinY + CGFloat(row + 1) * cellH - foodPadding

        guard cellMinX < cellMaxX, cellMinY < cellMaxY else { return randomPositionInArena() }
        return CGPoint(x: CGFloat.random(in: cellMinX...cellMaxX),
                       y: CGFloat.random(in: cellMinY...cellMaxY))
    }

    /// Returns a random position inside a bot's home zone (3×3 arena grid).
    /// 80% of the time the point is inside the bot's assigned zone;
    /// 20% of the time it is a fully random arena position to allow cross-zone roaming.
    func randomPositionInZone(for botIndex: Int) -> CGPoint {
        guard botIndex < bots.count else { return randomPositionInArena() }
        if CGFloat.random(in: 0...1) < 0.20 { return randomPositionInArena() }
        let zoneIdx = bots[botIndex].zoneIndex
        let zoneCol = zoneIdx % 3
        let zoneRow = zoneIdx / 3
        let zoneW   = worldSize / 3
        let zoneH   = worldSize / 3
        let pad: CGFloat = 300
        let zMinX = max(arenaMinX + pad, CGFloat(zoneCol) * zoneW + pad)
        let zMaxX = min(arenaMaxX - pad, CGFloat(zoneCol + 1) * zoneW - pad)
        let zMinY = max(arenaMinY + pad, CGFloat(zoneRow) * zoneH + pad)
        let zMaxY = min(arenaMaxY - pad, CGFloat(zoneRow + 1) * zoneH - pad)
        guard zMinX < zMaxX, zMinY < zMaxY else { return randomPositionInArena() }
        return CGPoint(x: CGFloat.random(in: zMinX...zMaxX), y: CGFloat.random(in: zMinY...zMaxY))
    }

    // MARK: - Skin-Matched Food Node Builders

    /// Returns (or creates) a cached SKTexture for trail food at the given color index.
    /// Rendered once as a plain circle — pattern detail is indistinguishable at 5 pt effective radius.
    private func trailFoodTexture(colorIndex: Int) -> SKTexture {
        if let cached = trailFoodTextureCache[colorIndex] { return cached }
        let idx   = colorIndex % snakeColorThemes.count
        let theme = snakeColorThemes[idx]
        let r     = bodySegmentRadius          // 10 pt
        let shape = SKShapeNode(circleOfRadius: r)
        shape.fillColor   = theme.bodySKColor
        shape.strokeColor = theme.bodyStrokeSKColor
        shape.lineWidth   = 1.5
        shape.glowWidth   = 2.0
        let diameter = r * 2
        let crop     = CGRect(x: -diameter, y: -diameter, width: diameter * 2, height: diameter * 2)
        let texture  = (view as? SKView)?.texture(from: shape, crop: crop) ?? SKTexture()
        trailFoodTextureCache[colorIndex] = texture
        return texture
    }

    /// Pre-warm the trail food texture cache for all color themes.
    /// Called once at game start so no allocations happen during gameplay.
    func prewarmTrailFoodTextures() {
        for i in 0..<snakeColorThemes.count { _ = trailFoodTexture(colorIndex: i) }
    }

    /// Tiny sprite matching the player/bot skin color. Uses a pre-rendered texture instead
    /// of a nested SKShapeNode hierarchy — eliminates 1–5 CGPath allocs per spawn.
    /// Effective radius ≈ 5 pt (scale 0.5 × bodySegmentRadius 10 pt).
    func makeTrailFoodNode(colorIndex: Int, patternIndex: Int) -> SKNode {
        let sprite = SKSpriteNode(texture: trailFoodTexture(colorIndex: colorIndex))
        sprite.setScale(0.5)
        return sprite
    }

    /// Body-segment circle matching a dead snake's skin, same visual size as regular food.
    /// Scale 0.8 → effective radius 8px.
    func makeDeathFoodNode(colorIndex: Int, patternIndex: Int) -> SKShapeNode {
        let idx     = colorIndex % snakeColorThemes.count
        let theme   = snakeColorThemes[idx]
        let pattern = SnakePattern(rawValue: patternIndex) ?? .solid
        let node    = makeBodySegment(color: theme.bodySKColor,
                                      stroke: theme.bodyStrokeSKColor,
                                      pattern: pattern, segIndex: 0)
        node.setScale(0.8)
        return node
    }

    /// Mini snake head (with eyes) matching a dead snake's head color.
    /// Scale 0.65 on headRadius(13) → effective radius ~8.5px, slightly bigger than body circles.
    func makeDeathHeadNode(colorIndex: Int) -> SKNode {
        let idx   = colorIndex % snakeColorThemes.count
        let theme = snakeColorThemes[idx]
        let head  = SKShapeNode(circleOfRadius: headRadius)
        head.fillColor   = theme.headSKColor
        head.strokeColor = theme.headStrokeSKColor
        head.lineWidth   = 2
        head.glowWidth   = 4
        head.setScale(0.65)
        addEyes(to: head)
        return head
    }

    func spawnTrailFood(at position: CGPoint, colorIndex: Int, patternIndex: Int) {
        // Hard cap: O(1) counter check instead of O(n) filter
        guard activeTrailFoodCount < maxTrailFoodItems else { return }

        let food = makeTrailFoodNode(colorIndex: colorIndex, patternIndex: patternIndex)
        food.position = position
        food.alpha    = 0
        addChild(food)
        foodItems.append(food)
        foodTypes.append(.trail)
        foodGridInsert(at: foodItems.count - 1)
        activeTrailFoodCount += 1
        // Do NOT set clusterBonusDirty here: trail food spawns ~53×/sec and the cluster bonus
        // cache doesn't need trail-food precision for bot food-targeting decisions.

        food.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.25),
            SKAction.wait(forDuration: 12.0),
            SKAction.fadeOut(withDuration: 1.0),
            SKAction.run { [weak self, weak food] in
                guard let self, let food else { return }
                if let idx = self.foodItems.firstIndex(where: { $0 === food }) {
                    // Natural expiry path: item still in arrays, hasn't been eaten early
                    self.removeFoodItem(at: idx)
                    self.activeTrailFoodCount = max(0, self.activeTrailFoodCount - 1)
                }
                // If not found: food was eaten early; counter already decremented at eat site
            },
            SKAction.removeFromParent()
        ]))
    }

    /// Scatter skin-matched food from a dead snake's body positions.
    /// Count = 1/3 of body length. First item is the snake's head (with eyes);
    /// remaining items are scaled body-segment circles with the same color + pattern.
    func spawnDeathFood(at positions: [CGPoint], colorIndex: Int, patternIndex: Int) {
        guard !positions.isEmpty else { return }
        let totalItems = max(1, positions.count / 3)
        let step       = max(1, positions.count / totalItems)

        let deathPopAnimation = SKAction.sequence([
            SKAction.group([SKAction.fadeIn(withDuration: 0.3),
                            SKAction.scale(to: 1.3, duration: 0.15)]),
            SKAction.scale(to: 1.0, duration: 0.15),
            SKAction.wait(forDuration: 15.0),
            SKAction.fadeOut(withDuration: 1.5),
            SKAction.removeFromParent()
        ])

        var isFirst = true
        for i in Swift.stride(from: 0, to: positions.count, by: step) {
            let food: SKNode = isFirst
                ? makeDeathHeadNode(colorIndex: colorIndex)
                : makeDeathFoodNode(colorIndex: colorIndex, patternIndex: patternIndex)
            isFirst      = false
            food.position = positions[i]
            food.alpha    = 0
            addChild(food)
            foodItems.append(food)
            foodTypes.append(.death)
            foodGridInsert(at: foodItems.count - 1)
            food.run(deathPopAnimation)
        }
    }

    func isPositionOnPlayerSnake(_ p: CGPoint) -> Bool {
        if hypot(p.x - snakeHead.position.x, p.y - snakeHead.position.y) < safeSpawnDistance { return true }
        for pos in bodyPositionCache where hypot(p.x - pos.x, p.y - pos.y) < safeSpawnDistance { return true }
        return false
    }
    /// O(1) food removal: swap-with-last keeps all three parallel arrays in sync.
    /// Returns the removed food type. All removal sites must use this instead of
    /// direct foodItems.remove(at:) / foodTypes.remove(at:) calls.
    @discardableResult
    func removeFoodItem(at index: Int) -> FoodType {
        let removedType = foodTypes[index]
        let last = foodItems.count - 1
        let removedPos = foodItems[index].position   // capture before potential swap
        if index != last {
            foodItems.swapAt(index, last)
            foodTypes.swapAt(index, last)
            if cachedClusterBonuses.count > last {
                cachedClusterBonuses.swapAt(index, last)
            }
            foodGridFixSwap(removedAt: index, removedPos: removedPos, movedFrom: last)
        } else {
            // Removing the last element — just remove from grid directly
            foodGridRemoveLast(at: removedPos)
        }
        foodItems.removeLast()
        foodTypes.removeLast()
        if cachedClusterBonuses.count > foodItems.count {
            cachedClusterBonuses.removeLast()
        }
        return removedType
    }

    func checkFoodCollisions() {
        rebuildFoodGridIfNeeded()
        let thresholdSq: CGFloat = (headRadius + foodRadius) * (headRadius + foodRadius)
        let headPos = snakeHead.position
        let hc = foodCell(for: headPos)
        // span=1 → 3×3 = 9 cells checked; at cell size 200 this comfortably covers the 25px threshold.
        for dcx in -1...1 {
            for dcy in -1...1 {
                guard let indices = foodSpatialGrid[GridCell(x: hc.x + dcx, y: hc.y + dcy)] else { continue }
                for i in indices {
                    guard i < foodItems.count, foodItems[i].parent != nil else { continue }
                    let dx = headPos.x - foodItems[i].position.x
                    let dy = headPos.y - foodItems[i].position.y
                    if dx * dx + dy * dy < thresholdSq {
                        eatFood(at: i)
                        return
                    }
                }
            }
        }
    }

    func eatFood(at index: Int) {
        let foodPos = foodItems[index].position
        let type    = foodTypes[index]

        if type == .trail { activeTrailFoodCount = max(0, activeTrailFoodCount - 1) }
        foodItems[index].removeFromParent()
        removeFoodItem(at: index)
        clusterBonusDirty = true
        spawnFood()
        // Body length is now derived from score via syncSnakeLength() — no direct addBodySegment() call here.

        // Apply power-up effects
        switch type {
        case .regular, .trail, .death: break
        case .shield:
            shieldActive = true
            showShieldGlow()
            spawnFloatingText("🛡 Shield!", at: CGPoint(x: foodPos.x, y: foodPos.y + 60))
        case .multiplier:
            multiplierActive   = true
            multiplierTimeLeft = 15.0
            scoreMultiplier    = 2
            showMultiplierEffect()
            spawnFloatingText("⭐ ×2 Score (15s)!", at: CGPoint(x: foodPos.x, y: foodPos.y + 60))
        case .magnet:
            magnetActive   = true
            magnetTimeLeft = 12.0
            showMagnetEffect()
            showMagnetActivation()
        case .ghost:
            ghostActive    = true
            ghostTimeLeft  = 12.0
            showGhostEffect()
        case .shrink:
            if score < 120 {
                spawnFloatingText("Too small to shrink!", at: CGPoint(x: foodPos.x, y: foodPos.y + 60))
            } else {
                applyShrink()
            }
        }

        // Per-type point values; power-ups award 2 pts (parity with botNutrition)
        let pts: Int
        switch type {
        case .regular:                           pts = 2
        case .trail:                             pts = 1
        case .death:                             pts = 5
        case .shield, .multiplier,
             .magnet, .ghost:                    pts = 2
        case .shrink:                            pts = 0  // shrink scores via applyShrink()
        }
        incrementCombo()
        let base  = pts * scoreMultiplier
        let bonus = GameLogic.comboBonus(forComboCount: comboCount)
        let total = base + bonus
        score += total
        if total > 0 {
            let text  = bonus > 0 ? "+\(total) combo!" : "+\(total)"
            let color: SKColor = bonus > 0
                ? SKColor(red: 0.2, green: 1.0, blue: 0.4, alpha: 1.0)
                : SKColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0)
            spawnFloatingText(text, at: foodPos, color: color)
        }
        updateScoreDisplay()
        updateSpeedForScore()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // Throttle eat sounds: max one per 80ms to prevent stutter during fast eating
        if lastUpdateTime - lastEatSoundTime > 0.08 {
            lastEatSoundTime = lastUpdateTime
            switch type {
            case .shield, .multiplier, .magnet, .ghost, .shrink:
                run(eatSpecialFoodAction)
            default:
                run(eatFoodAction)
            }
        }
        spawnEatParticles(at: foodPos)
        refreshPowerUpPanel()
    }

    func updateSpeedForScore() {
        currentMoveSpeed = GameLogic.calculateSpeed(
            score: score,
            baseMoveSpeed: baseMoveSpeed,
            maxMoveSpeed: maxMoveSpeed
        )
        syncSnakeLength()
    }


    // MARK: - Food Spatial Grid Helpers

    /// Convert a world position to a grid cell using foodGridCellSize (200 pt).
    /// This is distinct from gridCell(for:) which uses the 30 pt occupancy grid.
    func foodCell(for pos: CGPoint) -> GridCell {
        GridCell(x: Int(pos.x / foodGridCellSize), y: Int(pos.y / foodGridCellSize))
    }

    /// Rebuild the food spatial grid from scratch. Called lazily when foodGridDirty is true
    /// (i.e. after the magnet power-up has moved food nodes between cells).
    func rebuildFoodGridIfNeeded() {
        guard foodGridDirty else { return }
        foodSpatialGrid.removeAll(keepingCapacity: true)
        for i in foodItems.indices where foodItems[i].parent != nil {
            foodSpatialGrid[foodCell(for: foodItems[i].position), default: []].append(i)
        }
        foodGridDirty = false
    }

    /// Insert a newly-appended food item into the grid.
    /// Must be called immediately after foodItems.append() at every spawn site.
    private func foodGridInsert(at index: Int) {
        guard !foodGridDirty else { return }   // grid will be rebuilt anyway; skip incremental insert
        foodSpatialGrid[foodCell(for: foodItems[index].position), default: []].append(index)
    }

    /// Remove the last element from the grid (used when index == last in removeFoodItem).
    private func foodGridRemoveLast(at pos: CGPoint) {
        guard !foodGridDirty else { return }
        let last = foodItems.count - 1   // still valid before removeLast()
        let cell = foodCell(for: pos)
        foodSpatialGrid[cell]?.removeAll(where: { $0 == last })
        if foodSpatialGrid[cell]?.isEmpty == true { foodSpatialGrid.removeValue(forKey: cell) }
    }

    /// After a swap-with-last removal: remove the old index from its cell and rename the
    /// moved item (was at `movedFrom`, now at `index`) in its cell.
    private func foodGridFixSwap(removedAt index: Int, removedPos: CGPoint, movedFrom last: Int) {
        guard !foodGridDirty else { return }
        // Remove the item being deleted
        let rc = foodCell(for: removedPos)
        foodSpatialGrid[rc]?.removeAll(where: { $0 == index })
        if foodSpatialGrid[rc]?.isEmpty == true { foodSpatialGrid.removeValue(forKey: rc) }
        // Rename the moved item's index in its cell (foodItems[index] is now the former last)
        let mc = foodCell(for: foodItems[index].position)   // after swap, foodItems[index] is former last
        if let pos = foodSpatialGrid[mc]?.firstIndex(of: last) {
            foodSpatialGrid[mc]![pos] = index
        }
    }

    func bodyOccupancyContains(_ point: CGPoint) -> Bool {
        let center = gridCell(for: point)
        for dx in -1...1 {
            for dy in -1...1 {
                if playerBodyOccupancy.contains(GridCell(x: center.x + dx, y: center.y + dy)) {
                    return true
                }
            }
        }
        return false
    }

    func updatePlayerBodyVisuals() {
        let count = bodySegments.count
        guard count > 0 else {
            playerBodyPathNode.alpha = ghostActive ? 0.18 : 0.30
            return
        }

        let needsRotation = selectedSnakePattern == .cylinder
                         || selectedSnakePattern == .armor
                         || selectedSnakePattern == .leaf
        for (index, segment) in bodySegments.enumerated() {
            if index < bodyPositionCache.count {
                segment.position = bodyPositionCache[index]
            }
            // Orient pill/leaf segments to face the direction of travel
            if needsRotation && index > 0 && index < bodyPositionCache.count {
                let prev = bodyPositionCache[index - 1]
                let curr = bodyPositionCache[index]
                let dx = prev.x - curr.x
                let dy = prev.y - curr.y
                if dx * dx + dy * dy > 0.01 {
                    segment.zRotation = atan2(dy, dx) - (.pi / 2)
                }
            }
            let progress = count > 1 ? CGFloat(index) / CGFloat(count - 1) : 0
            let scale = 1.0 - progress * 0.22
            segment.setScale(scale)
            segment.alpha = ghostActive ? max(0.22, 0.44 - progress * 0.10) : (1.0 - progress * 0.10)

            // Glow gradient: bright leading quarter fades to nothing at the tail.
            // Neon pattern keeps its full glow everywhere; boost adds extra.
            let isNeon = selectedSnakePattern == .neon
            let boostBonus: CGFloat = isBoostHeld ? 4 : 0
            let baseGlow: CGFloat
            if isNeon {
                baseGlow = 10 + boostBonus
            } else if index < max(1, count / 8) {
                baseGlow = 6 + boostBonus       // first ~12%: bright rim
            } else if index < max(1, count / 4) {
                baseGlow = 3 + boostBonus * 0.5  // next ~12%: moderate rim
            } else {
                baseGlow = 0
            }
            let desiredGlow: CGFloat = ghostActive ? baseGlow * 0.4 : baseGlow
            // Guard: glowWidth triggers SpriteKit re-render every time it's set, even if unchanged.
            if segment.glowWidth != desiredGlow { segment.glowWidth = desiredGlow }
            segment.zPosition = snakeHead.zPosition - 0.04 - CGFloat(index) * 0.0005
        }

        playerBodyPathNode.alpha = ghostActive ? 0.18 : 0.30
    }

    func acquireBodySegmentNode(segIndex: Int) -> SKShapeNode {
        makePlayerBodySegment(segIndex: segIndex)
    }

    func releaseBodySegmentNode(_ node: SKShapeNode) {
        node.removeFromParent()
    }

    func updateSegmentScales() {
        updatePlayerBodyVisuals()
    }

    func makePlayerBodySegment(segIndex: Int = 0) -> SKShapeNode {
        let theme = snakeColorThemes[normalizedSnakeColorIndex(selectedSnakeColorIndex)]
        if selectedSnakePattern == .rainbow {
            let hue = CGFloat(segIndex % 12) / 12.0
            let rainbowColor  = SKColor(hue: hue, saturation: 0.85, brightness: 0.95, alpha: 1.0)
            let rainbowStroke = rainbowColor.darkened(by: 0.20)
            return makeBodySegment(
                color: rainbowColor,
                stroke: rainbowStroke,
                pattern: .rainbow,
                segIndex: segIndex,
                radius: effectiveBodyRadius
            )
        }
        return makeBodySegment(
            color: theme.bodySKColor,
            stroke: theme.bodyStrokeSKColor,
            pattern: selectedSnakePattern,
            segIndex: segIndex,
            radius: effectiveBodyRadius
        )
    }


    /// Builds an organic, irregular oval CGPath for the spawn hole interior.
    /// Fixed perturbations give a consistent shape every spawn.
    /// `scale` lets the glow rim be slightly larger than the filled interior.
    private func makeIrregularHolePath(scale: CGFloat = 1.0) -> CGPath {
        let rx: CGFloat = 41 * scale   // base half-width
        let ry: CGFloat = 19 * scale   // base half-height (keeps 2:1 aspect)
        // Fixed per-vertex radial perturbations — same every call for a consistent shape
        let perturb: [CGFloat] = [1.00, 0.82, 1.14, 0.90, 1.18, 0.85, 1.08, 0.78,
                                   1.20, 0.88, 1.05, 0.80, 1.15, 0.92, 1.10, 0.86]
        let n = perturb.count
        var pts = [CGPoint]()
        for i in 0..<n {
            let a = CGFloat(i) / CGFloat(n) * .pi * 2
            let r = perturb[i]
            pts.append(CGPoint(x: cos(a) * rx * r, y: sin(a) * ry * r))
        }
        let path = CGMutablePath()
        path.move(to: pts[0])
        for i in 0..<n {
            let prev = pts[(i + n - 1) % n]
            let curr = pts[i]
            let next = pts[(i + 1) % n]
            let next2 = pts[(i + 2) % n]
            // Catmull-Rom → cubic bezier control points
            let cp1 = CGPoint(x: curr.x + (next.x - prev.x) * 0.22,
                              y: curr.y + (next.y - prev.y) * 0.22)
            let cp2 = CGPoint(x: next.x - (next2.x - curr.x) * 0.22,
                              y: next.y - (next2.y - curr.y) * 0.22)
            path.addCurve(to: next, control1: cp1, control2: cp2)
        }
        path.closeSubpath()
        return path
    }

    func createSpawnHole(at position: CGPoint, angle: CGFloat, accent: SKColor) -> SKNode {
        let hole = SKNode()
        hole.position = position
        // z=1: above snake body (z≈0) so dark interior covers unrevealed segments.
        // groundSprite at local z=-2 → abs z=-1, below snake so grass shows under everything.
        hole.zPosition = 1
        hole.zRotation = angle

        // Natural ground/grass texture rendered from image asset (grass + dirt rim)
        let groundSprite = SKSpriteNode(imageNamed: "spawn_hole")
        groundSprite.size = CGSize(width: 124, height: 62)
        groundSprite.zPosition = -2   // abs z=-1: beneath snake body (z≈0)
        hole.addChild(groundSprite)

        // Deep dark interior with irregular edge — covers underground snake segments (abs z=1)
        let interior = SKShapeNode(path: makeIrregularHolePath())
        interior.fillColor = SKColor(red: 0.01, green: 0.02, blue: 0.01, alpha: 0.88)
        interior.strokeColor = .clear
        interior.zPosition = 0   // abs z=1: above snake body
        hole.addChild(interior)

        // Glow rim traces the same irregular edge as the interior
        let rimInner = SKShapeNode(path: makeIrregularHolePath(scale: 1.08))
        rimInner.fillColor = .clear
        rimInner.strokeColor = accent.withAlphaComponent(0.55)
        rimInner.lineWidth = 2.5
        rimInner.glowWidth = 8
        hole.addChild(rimInner)

        // Pulsing rim animation
        rimInner.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.30, duration: 0.35),
            SKAction.fadeAlpha(to: 0.80, duration: 0.35)
        ])))

        // Ripple rings expanding outward
        for idx in 0..<3 {
            let ripple = SKShapeNode(circleOfRadius: 28)
            ripple.fillColor = .clear
            ripple.strokeColor = accent.withAlphaComponent(0.40)
            ripple.lineWidth = 1.5
            ripple.setScale(0.3)
            ripple.alpha = 0
            hole.addChild(ripple)
            ripple.run(SKAction.sequence([
                SKAction.wait(forDuration: Double(idx) * 0.15),
                SKAction.group([
                    SKAction.sequence([
                        SKAction.fadeIn(withDuration: 0.05),
                        SKAction.fadeOut(withDuration: 0.40)
                    ]),
                    SKAction.scale(to: 3.5, duration: 0.45)
                ]),
                SKAction.removeFromParent()
            ]))
        }

        return hole
    }

    func animateSnakeEntrance(head: SKNode, body: [SKShapeNode], angle: CGFloat, accent: SKColor) {
        let holePos = head.position
        let hole = createSpawnHole(at: holePos, angle: angle, accent: accent)
        hole.setScale(0.1)
        addChild(hole)

        // Hole opens
        hole.run(SKAction.sequence([
            SKAction.scale(to: 1.0, duration: 0.20)
        ]))

        // Head emerges first after hole opens.
        // Raise head to z=2 so it appears above the dark interior (hole abs z=1).
        let origHeadAlpha = head.alpha
        let origHeadScaleX = head.xScale
        let origHeadScaleY = head.yScale
        head.zPosition = 2   // above interior (abs z=1); reset to 0 when hole closes
        head.alpha = 0
        head.setScale(0.15)
        head.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.20),
            SKAction.group([
                SKAction.fadeAlpha(to: origHeadAlpha, duration: 0.25),
                SKAction.scaleX(to: origHeadScaleX, duration: 0.28),
                SKAction.scaleY(to: origHeadScaleY, duration: 0.28)
            ])
        ]))

        // Body segments emerge sequentially along the snake path from the hole.
        // Pre-position each segment along the intended trail (no "fly to" movement),
        // then just fade and scale in place to eliminate the flying-body visual.
        // Each segment starts below the interior (z≈-0.04) and jumps to z=2 on emerge.
        for (index, seg) in body.enumerated() {
            let targetAlpha = seg.alpha
            let targetScaleX = seg.xScale
            let targetScaleY = seg.yScale
            // Place segment along the snake's direction from the hole
            seg.position = CGPoint(
                x: holePos.x - cos(angle) * CGFloat(index + 1) * segmentPixelSpacing,
                y: holePos.y - sin(angle) * CGFloat(index + 1) * segmentPixelSpacing
            )
            seg.alpha = 0
            seg.setScale(0.15)
            let delay = 0.38 + Double(index) * 0.055
            seg.run(SKAction.sequence([
                SKAction.wait(forDuration: delay),
                SKAction.run { seg.zPosition = 2 },   // pop above interior as it emerges
                SKAction.group([
                    SKAction.fadeAlpha(to: targetAlpha, duration: 0.22),
                    SKAction.scaleX(to: targetScaleX, duration: 0.25),
                    SKAction.scaleY(to: targetScaleY, duration: 0.25)
                ])
            ]))
        }

        // Hole closes after all segments emerge; reset head z back to normal.
        let closingDelay = 0.38 + Double(body.count) * 0.055 + 0.35
        hole.run(SKAction.sequence([
            SKAction.wait(forDuration: closingDelay),
            SKAction.group([
                SKAction.fadeOut(withDuration: 0.25),
                SKAction.scale(to: 0.2, duration: 0.25)
            ]),
            SKAction.run { [weak head] in head?.zPosition = 0 },
            SKAction.removeFromParent()
        ]))
    }

    func makeDiamondPath(radius: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to:    CGPoint(x: 0,        y: radius))
        p.addLine(to: CGPoint(x: radius * 0.8, y: 0))
        p.addLine(to: CGPoint(x: 0,        y: -radius))
        p.addLine(to: CGPoint(x: -radius * 0.8, y: 0))
        p.closeSubpath()
        return p
    }

    func makeLeafPath(radius: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: radius))
        p.addCurve(
            to:       CGPoint(x:  0, y: -radius),
            control1: CGPoint(x:  radius * 1.0, y:  radius * 0.4),
            control2: CGPoint(x:  radius * 1.0, y: -radius * 0.4)
        )
        p.addCurve(
            to:       CGPoint(x:  0, y: radius),
            control1: CGPoint(x: -radius * 1.0, y: -radius * 0.4),
            control2: CGPoint(x: -radius * 1.0, y:  radius * 0.4)
        )
        p.closeSubpath()
        return p
    }

    func makeRoundedRectPath(size: CGSize, cornerRadius: CGFloat) -> CGPath {
        UIBezierPath(
            roundedRect: CGRect(
                x: -size.width / 2,
                y: -size.height / 2,
                width: size.width,
                height: size.height
            ),
            cornerRadius: cornerRadius
        ).cgPath
    }

    func makeSquarePath(radius: CGFloat) -> CGPath {
        let side = radius * 1.72
        return CGPath(roundedRect: CGRect(x: -side/2, y: -side/2, width: side, height: side),
                      cornerWidth: radius * 0.22, cornerHeight: radius * 0.22, transform: nil)
    }

    func makeStadiumPath(radius: CGFloat) -> CGPath {
        // Horizontal capsule - circle chopped on left and right
        let w = radius * 2.1
        let h = radius * 1.5
        return CGPath(roundedRect: CGRect(x: -w/2, y: -h/2, width: w, height: h),
                      cornerWidth: h/2, cornerHeight: h/2, transform: nil)
    }

    func makeHexagonPath(radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<6 {
            let angle = CGFloat(i) * .pi / 3.0 - .pi / 6.0
            let pt = CGPoint(x: radius * cos(angle), y: radius * sin(angle))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }

    func makeBodySegment(color: SKColor, stroke: SKColor,
                         pattern: SnakePattern = .solid,
                         segIndex: Int = 0,
                         radius: CGFloat? = nil) -> SKShapeNode {
        let r = radius ?? bodySegmentRadius
        // Base shape
        let seg: SKShapeNode
        if pattern == .crystal {
            seg = SKShapeNode(path: makeDiamondPath(radius: r))
        } else if pattern == .cylinder {
            let pillSize = CGSize(width: r * 2.0, height: r * 2.6)
            seg = SKShapeNode(path: makeRoundedRectPath(size: pillSize, cornerRadius: r * 0.9))
        } else if pattern == .armor {
            let pillSize = CGSize(width: r * 2.0, height: r * 2.8)
            seg = SKShapeNode(path: makeRoundedRectPath(size: pillSize, cornerRadius: r))
        } else if pattern == .leaf {
            seg = SKShapeNode(path: makeLeafPath(radius: r))
        } else if pattern == .square {
            seg = SKShapeNode(path: makeSquarePath(radius: r))
        } else if pattern == .stadium {
            seg = SKShapeNode(path: makeStadiumPath(radius: r))
        } else if pattern == .hexagon {
            seg = SKShapeNode(path: makeHexagonPath(radius: r))
        } else {
            seg = SKShapeNode(circleOfRadius: r)
        }

        // Base colour per pattern
        switch pattern {
        case .striped:
            // Strong two-colour contrast: alternate between fill and stroke colours
            if segIndex % 2 == 1 {
                seg.fillColor   = stroke     // stroke colour as fill on alternating segments
                seg.strokeColor = color      // and body colour as border
            } else {
                seg.fillColor   = color
                seg.strokeColor = stroke
            }
        case .galaxy:
            seg.fillColor   = color.darkened(by: 0.55)
            seg.strokeColor = stroke.darkened(by: 0.30)
        case .split:
            seg.fillColor   = color.darkened(by: 0.12)
            seg.strokeColor = stroke
        case .ember:
            seg.fillColor   = color.darkened(by: 0.10)
            seg.strokeColor = stroke.withAlphaComponent(0.92)
        case .toxic:
            seg.fillColor   = color.darkened(by: 0.08)
            seg.strokeColor = stroke
        case .diamondGrid:
            seg.fillColor   = segIndex % 2 == 0 ? color.darkened(by: 0.10) : color.darkened(by: 0.25)
            seg.strokeColor = stroke
        case .armor:
            seg.fillColor   = color.darkened(by: 0.20)
            seg.strokeColor = SKColor(red: 1.0, green: 0.78, blue: 0.08, alpha: 0.90)
        case .sphere, .cylinder, .leaf, .rainbow:
            seg.fillColor   = color
            seg.strokeColor = stroke
        case .square, .stadium, .hexagon:
            seg.fillColor   = color
            seg.strokeColor = stroke
        default:
            seg.fillColor   = color
            seg.strokeColor = stroke
        }

        seg.lineWidth = 2
        seg.glowWidth = pattern == .neon ? 14 : (pattern == .ember ? 8 : 3)

        if pattern == .neon {
            seg.strokeColor = SKColor(white: 1.0, alpha: 0.80)
            seg.lineWidth   = 2.5
        }

        // Overlay child nodes for textured patterns
        switch pattern {
        case .dotted:
            // Larger dot in accent (stroke) colour — clearly visible
            let dot = SKShapeNode(circleOfRadius: 4.5)
            dot.fillColor   = stroke
            dot.strokeColor = .clear
            dot.position    = CGPoint(x: 0, y: r * 0.52)
            dot.zPosition   = 1
            seg.addChild(dot)

        case .scales:
            // Higher-opacity crescent with a visible stroke border
            let arc = SKShapeNode(circleOfRadius: r * 0.58)
            arc.fillColor   = SKColor(white: 1.0, alpha: 0.45)
            arc.strokeColor = stroke.withAlphaComponent(0.50)
            arc.lineWidth   = 1.0
            arc.position    = CGPoint(x: r * 0.28,
                                      y: r * 0.28)
            arc.zPosition   = 1
            seg.addChild(arc)

        case .crystal:
            // Inner diamond highlight — diamond-inside-diamond effect
            let inner = SKShapeNode(path: makeDiamondPath(radius: r * 0.45))
            inner.fillColor   = SKColor(white: 1.0, alpha: 0.35)
            inner.strokeColor = .clear
            inner.zPosition   = 1
            seg.addChild(inner)

        case .neon:
            // Second inner ring in body colour for depth
            let ring = SKShapeNode(circleOfRadius: r * 0.65)
            ring.fillColor   = .clear
            ring.strokeColor = color.withAlphaComponent(0.55)
            ring.lineWidth   = 2.0
            ring.zPosition   = 1
            seg.addChild(ring)

        case .camo:
            // Real camo: dark-green + dark-brown blotches
            let blotch1 = SKShapeNode(circleOfRadius: r * 0.48)
            blotch1.fillColor   = SKColor(red: 0.15, green: 0.45, blue: 0.10, alpha: 0.70)
            blotch1.strokeColor = .clear
            blotch1.position    = CGPoint(x: -r * 0.28, y:  r * 0.22)
            blotch1.zPosition   = 1
            seg.addChild(blotch1)
            let blotch2 = SKShapeNode(circleOfRadius: r * 0.30)
            blotch2.fillColor   = SKColor(red: 0.40, green: 0.25, blue: 0.02, alpha: 0.65)
            blotch2.strokeColor = .clear
            blotch2.position    = CGPoint(x:  r * 0.30, y: -r * 0.20)
            blotch2.zPosition   = 1
            seg.addChild(blotch2)

        case .galaxy:
            // Stars with varied sizes + purple nebula ring
            let starData: [(CGFloat, CGFloat, CGFloat)] = [(-4, -3, 3.0), (4, -4, 2.0), (-2, 4, 1.5)]
            for (ox, oy, starR) in starData {
                let star = SKShapeNode(circleOfRadius: starR)
                star.fillColor   = SKColor(white: 1.0, alpha: 0.90)
                star.strokeColor = .clear
                star.position    = CGPoint(x: ox, y: oy)
                star.zPosition   = 1
                seg.addChild(star)
            }
            let nebula = SKShapeNode(circleOfRadius: r * 0.78)
            nebula.fillColor   = .clear
            nebula.strokeColor = SKColor(red: 0.60, green: 0.20, blue: 0.90, alpha: 0.55)
            nebula.lineWidth   = 1.5
            nebula.zPosition   = 1
            seg.addChild(nebula)

        case .zigzag:
            let slash1 = SKShapeNode(path: makeRoundedRectPath(
                size: CGSize(width: r * 0.52, height: r * 2.05),
                cornerRadius: r * 0.22
            ))
            slash1.fillColor = SKColor(white: 1.0, alpha: 0.58)
            slash1.strokeColor = .clear
            slash1.zRotation = .pi / 5
            slash1.position = CGPoint(x: -r * 0.24, y: 0)
            slash1.zPosition = 1
            seg.addChild(slash1)

            let slash2 = SKShapeNode(path: makeRoundedRectPath(
                size: CGSize(width: r * 0.46, height: r * 1.85),
                cornerRadius: r * 0.20
            ))
            slash2.fillColor = stroke.withAlphaComponent(0.36)
            slash2.strokeColor = .clear
            slash2.zRotation = -.pi / 6
            slash2.position = CGPoint(x: r * 0.22, y: 0)
            slash2.zPosition = 1
            seg.addChild(slash2)

        case .ripple:
            let outerRing = SKShapeNode(circleOfRadius: r * 0.70)
            outerRing.fillColor = .clear
            outerRing.strokeColor = SKColor(white: 1.0, alpha: 0.72)
            outerRing.lineWidth = 1.6
            outerRing.zPosition = 1
            seg.addChild(outerRing)

            let innerRing = SKShapeNode(circleOfRadius: r * 0.36)
            innerRing.fillColor = .clear
            innerRing.strokeColor = color.withAlphaComponent(0.55)
            innerRing.lineWidth = 1.1
            innerRing.zPosition = 1
            seg.addChild(innerRing)

        case .split:
            let slice = SKShapeNode(path: makeRoundedRectPath(
                size: CGSize(width: r * 1.25, height: r * 2.30),
                cornerRadius: r * 0.24
            ))
            slice.fillColor = SKColor(white: 1.0, alpha: 0.28)
            slice.strokeColor = .clear
            slice.zRotation = .pi / 5
            slice.position = CGPoint(x: r * 0.24, y: 0)
            slice.zPosition = 1
            seg.addChild(slice)

        case .ember:
            let ember1 = SKShapeNode(circleOfRadius: r * 0.22)
            ember1.fillColor = SKColor(red: 1.0, green: 0.76, blue: 0.20, alpha: 0.86)
            ember1.strokeColor = .clear
            ember1.position = CGPoint(x: -r * 0.20, y: -r * 0.12)
            ember1.zPosition = 1
            seg.addChild(ember1)

            let ember2 = SKShapeNode(circleOfRadius: r * 0.14)
            ember2.fillColor = SKColor(red: 1.0, green: 0.44, blue: 0.14, alpha: 0.82)
            ember2.strokeColor = .clear
            ember2.position = CGPoint(x: r * 0.22, y: r * 0.20)
            ember2.zPosition = 1
            seg.addChild(ember2)

        case .frost:
            let vertical = SKShapeNode(path: makeRoundedRectPath(
                size: CGSize(width: r * 0.24, height: r * 1.40),
                cornerRadius: r * 0.12
            ))
            vertical.fillColor = SKColor(white: 1.0, alpha: 0.70)
            vertical.strokeColor = .clear
            vertical.zPosition = 1
            seg.addChild(vertical)

            let horizontal = SKShapeNode(path: makeRoundedRectPath(
                size: CGSize(width: r * 1.38, height: r * 0.24),
                cornerRadius: r * 0.12
            ))
            horizontal.fillColor = SKColor(red: 0.72, green: 0.92, blue: 1.0, alpha: 0.48)
            horizontal.strokeColor = .clear
            horizontal.zRotation = .pi / 4
            horizontal.zPosition = 1
            seg.addChild(horizontal)

        case .ringed:
            let ring = SKShapeNode(circleOfRadius: r * 0.58)
            ring.fillColor = .clear
            ring.strokeColor = SKColor(white: 1.0, alpha: 0.76)
            ring.lineWidth = 1.8
            ring.zPosition = 1
            seg.addChild(ring)

            let center = SKShapeNode(circleOfRadius: r * 0.18)
            center.fillColor = SKColor(white: 1.0, alpha: 0.24)
            center.strokeColor = .clear
            center.zPosition = 1
            seg.addChild(center)

        case .toxic:
            let acidBlob = SKShapeNode(circleOfRadius: r * 0.34)
            acidBlob.fillColor = SKColor(red: 0.86, green: 1.0, blue: 0.22, alpha: 0.80)
            acidBlob.strokeColor = .clear
            acidBlob.position = CGPoint(x: -r * 0.18, y: r * 0.16)
            acidBlob.zPosition = 1
            seg.addChild(acidBlob)

            let darkSpot = SKShapeNode(circleOfRadius: r * 0.16)
            darkSpot.fillColor = SKColor(white: 0.08, alpha: 0.22)
            darkSpot.strokeColor = .clear
            darkSpot.position = CGPoint(x: r * 0.20, y: -r * 0.22)
            darkSpot.zPosition = 1
            seg.addChild(darkSpot)

        case .checker:
            let tileSize = r * 0.54
            let offsets: [(CGFloat, CGFloat, Bool)] = [
                (-tileSize * 0.5, -tileSize * 0.5, true),
                ( tileSize * 0.5, -tileSize * 0.5, false),
                (-tileSize * 0.5,  tileSize * 0.5, false),
                ( tileSize * 0.5,  tileSize * 0.5, true)
            ]
            for (x, y, isFilled) in offsets {
                let tile = SKShapeNode(path: makeRoundedRectPath(
                    size: CGSize(width: tileSize, height: tileSize),
                    cornerRadius: r * 0.08
                ))
                tile.fillColor = isFilled ? SKColor(white: 1.0, alpha: 0.45) : .clear
                tile.strokeColor = .clear
                tile.position = CGPoint(x: x, y: y)
                tile.zPosition = 1
                seg.addChild(tile)
            }

        case .sphere:
            // Specular highlight — bright ellipse offset upper-left (simulates light source)
            let highlight = SKShapeNode(ellipseOf: CGSize(
                width:  r * 0.75,
                height: r * 0.55
            ))
            highlight.fillColor   = SKColor(white: 1.0, alpha: 0.70)
            highlight.strokeColor = .clear
            highlight.position    = CGPoint(x: -r * 0.30, y: r * 0.30)
            highlight.zPosition   = 2
            seg.addChild(highlight)
            // Shadow — dark ellipse lower-right for depth
            let shadow = SKShapeNode(ellipseOf: CGSize(
                width:  r * 0.90,
                height: r * 0.65
            ))
            shadow.fillColor   = SKColor(white: 0.0, alpha: 0.22)
            shadow.strokeColor = .clear
            shadow.position    = CGPoint(x: r * 0.20, y: -r * 0.22)
            shadow.zPosition   = 2
            seg.addChild(shadow)

        case .rainbow:
            // Same 3D sphere highlight — rainbow color is set per-segment in makePlayerBodySegment
            let rHighlight = SKShapeNode(ellipseOf: CGSize(
                width:  r * 0.75,
                height: r * 0.55
            ))
            rHighlight.fillColor   = SKColor(white: 1.0, alpha: 0.70)
            rHighlight.strokeColor = .clear
            rHighlight.position    = CGPoint(x: -r * 0.30, y: r * 0.30)
            rHighlight.zPosition   = 2
            seg.addChild(rHighlight)
            let rShadow = SKShapeNode(ellipseOf: CGSize(
                width:  r * 0.90,
                height: r * 0.65
            ))
            rShadow.fillColor   = SKColor(white: 0.0, alpha: 0.22)
            rShadow.strokeColor = .clear
            rShadow.position    = CGPoint(x: r * 0.20, y: -r * 0.22)
            rShadow.zPosition   = 2
            seg.addChild(rShadow)

        case .diamondGrid:
            // Full-size diamond overlay alternating light/dark for woven lattice look
            let d1 = SKShapeNode(path: makeDiamondPath(radius: r * 0.90))
            d1.fillColor   = segIndex % 2 == 0
                ? SKColor(white: 1.0, alpha: 0.40)
                : SKColor(white: 0.0, alpha: 0.20)
            d1.strokeColor = stroke.withAlphaComponent(0.80)
            d1.lineWidth   = 1.2
            d1.zPosition   = 1
            seg.addChild(d1)
            // Inner highlight diamond for chrome sheen
            let d2 = SKShapeNode(path: makeDiamondPath(radius: r * 0.38))
            d2.fillColor   = SKColor(white: 1.0, alpha: 0.55)
            d2.strokeColor = .clear
            d2.position    = CGPoint(x: 0, y: r * 0.18)
            d2.zPosition   = 2
            seg.addChild(d2)

        case .cylinder:
            // Mid-band stripe
            let band = SKShapeNode(rect: CGRect(
                x: -r,
                y: -r * 0.35,
                width: r * 2.0,
                height: r * 0.70
            ))
            band.fillColor   = SKColor(white: 1.0, alpha: 0.30)
            band.strokeColor = .clear
            band.zPosition   = 1
            seg.addChild(band)
            // Top shine
            let shine = SKShapeNode(ellipseOf: CGSize(
                width:  r * 1.60,
                height: r * 0.50
            ))
            shine.fillColor   = SKColor(white: 1.0, alpha: 0.42)
            shine.strokeColor = .clear
            shine.position    = CGPoint(x: 0, y: r * 0.72)
            shine.zPosition   = 2
            seg.addChild(shine)

        case .armor:
            // Gold band ring across the center
            let ring = SKShapeNode(rect: CGRect(
                x: -r,
                y: -r * 0.22,
                width: r * 2.0,
                height: r * 0.44
            ))
            ring.fillColor   = SKColor(red: 1.0, green: 0.78, blue: 0.08, alpha: 0.90)
            ring.strokeColor = .clear
            ring.zPosition   = 1
            seg.addChild(ring)
            // Highlight on top of gold ring
            let ringShine = SKShapeNode(ellipseOf: CGSize(
                width:  r * 1.40,
                height: r * 0.26
            ))
            ringShine.fillColor   = SKColor(white: 1.0, alpha: 0.38)
            ringShine.strokeColor = .clear
            ringShine.position    = CGPoint(x: 0, y: r * 0.08)
            ringShine.zPosition   = 2
            seg.addChild(ringShine)

        case .leaf:
            // Center vein line
            let veinPath = CGMutablePath()
            veinPath.move(to:    CGPoint(x: 0, y:  r * 0.72))
            veinPath.addLine(to: CGPoint(x: 0, y: -r * 0.72))
            let vein = SKShapeNode(path: veinPath)
            vein.strokeColor = SKColor(white: 1.0, alpha: 0.32)
            vein.lineWidth   = 1.0
            vein.zPosition   = 1
            seg.addChild(vein)
            // Small highlight at top of leaf
            let leafShine = SKShapeNode(ellipseOf: CGSize(
                width:  r * 0.55,
                height: r * 0.32
            ))
            leafShine.fillColor   = SKColor(white: 1.0, alpha: 0.38)
            leafShine.strokeColor = .clear
            leafShine.position    = CGPoint(x: -r * 0.12, y: r * 0.38)
            leafShine.zPosition   = 2
            seg.addChild(leafShine)

        default: break
        }

        // Specular highlight — small bright circle at top-left simulates a convex lit surface.
        // Skipped for crystal (diamond) since the geometry already has a bright edge.
        if pattern != .crystal {
            let spec = SKShapeNode(circleOfRadius: bodySegmentRadius * 0.30)
            spec.fillColor   = SKColor(white: 1.0, alpha: 0.48)
            spec.strokeColor = .clear
            spec.position    = CGPoint(x: -bodySegmentRadius * 0.36, y: bodySegmentRadius * 0.40)
            spec.zPosition   = 2
            seg.addChild(spec)
        }

        return seg
    }

}
