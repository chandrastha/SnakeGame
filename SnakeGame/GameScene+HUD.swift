import SpriteKit

extension GameScene {

    // MARK: - HUD Positions (world-space, updated every frame)
    func updateHUDPositions() {
        let cx = cameraNode.position.x
        let cy = cameraNode.position.y
        let extents = cameraHalfExtents()
        let controlScale = hudControlScale()
        let joystickInset = joystickMargins()
        let boostInset = boostMargins()
        let minimapInset = minimapMargins()

        // Multiply every inset by controlScale so screen-space positions stay fixed under zoom.
        joystickCenter    = CGPoint(
            x: cx - extents.halfW + joystickInset.x * controlScale,
            y: cy - extents.halfH + joystickInset.y * controlScale
        )
        boostButtonCenter = CGPoint(
            x: cx + extents.halfW - boostInset.x * controlScale,
            y: cy - extents.halfH + boostInset.y * controlScale
        )

        joystickBaseNode?.position  = joystickCenter
        joystickBaseNode?.setScale(elementScale(for: .joystick))
        joystickInnerRing?.position = joystickCenter
        joystickInnerRing?.setScale(elementScale(for: .joystick))
        joystickThumbNode?.setScale(elementScale(for: .joystick))
        if joystickTouch == nil {
            joystickThumbNode?.position = joystickCenter
        } else {
            joystickThumbNode?.position = CGPoint(
                x: joystickCenter.x + joystickThumbOffset.x * controlScale,
                y: joystickCenter.y + joystickThumbOffset.y * controlScale
            )
        }
        boostButtonNode?.position = boostButtonCenter
        boostButtonNode?.setScale(elementScale(for: .boostButton) * (isBoostHeld ? 1.15 : 1.0))

        let si        = safeInsets
        let topInset  = si.top
        let leftInset = si.left

        let halfW = extents.halfW
        let halfH = extents.halfH

        // ── Score: top-center, below leader arrow ───────────────────────────
        // Leader arrow center is at leaderArrowMarginTop() from top.
        // Arrow label is 22pt below center (~12pt tall), so clear it by 44pt total.
        let arrowClearance: CGFloat = leaderArrowMarginTop() + 44
        let scoreTopY = cy + halfH - arrowClearance * controlScale
        if let pt = customWorldPoint(for: .score, cx: cx, cy: cy, halfW: halfW, halfH: halfH) {
            scoreLabel?.position = pt
        } else {
            scoreLabel?.position = CGPoint(x: cx, y: scoreTopY)
        }

        // ── Combo: centered, just below score ────────────────────────────────
        // comboPanelNode rect origin is (0,0) → position = bottom-left corner.
        // Panel is 190×34 world units (no scale applied), so center x = cx - 95.
        // y: score bottom = scoreTopY - hudScoreFontSize (world units); add 8pt gap.
        if let pt = customWorldPoint(for: .combo, cx: cx, cy: cy, halfW: halfW, halfH: halfH) {
            comboPanelNode?.position = CGPoint(x: pt.x - 95, y: pt.y - 34)
        } else {
            comboPanelNode?.position = CGPoint(
                x: cx - 95,
                y: scoreTopY - hudScoreFontSize - 8 - 34
            )
        }

        powerUpPanel?.position = CGPoint(
            x: cx,
            y: cy - halfH + (170 + si.bottom) * controlScale
        )
        minimapNode?.position = CGPoint(
            x: cx + halfW - minimapInset.x * controlScale,
            y: cy + halfH - minimapInset.y * controlScale
        )
        // Leaderboard: top-LEFT, top edge at minimapInset.y from screen top.
        // miniLeaderboard.position is the CENTER of the panel (rectOf: is centered).
        // panelHeight is in world-space units (no camera scaling), so offset is plain /2.
        if let pt = customWorldPoint(for: .miniLeaderboard, cx: cx, cy: cy, halfW: halfW, halfH: halfH) {
            // pt is the center of the leaderboard panel — no further offset needed
            miniLeaderboard?.position = pt
        } else {
            let lbLeftEdge = cx - halfW + (20 + leftInset) * controlScale
            miniLeaderboard?.position = CGPoint(
                x: lbLeftEdge + 92 * controlScale,
                y: cy + halfH - minimapInset.y * controlScale - miniLeaderboardPanelHeight / 2
            )
        }
        if let pt = customWorldPoint(for: .leaderArrow, cx: cx, cy: cy, halfW: halfW, halfH: halfH) {
            leaderArrowNode?.position = pt
        } else {
            leaderArrowNode?.position = CGPoint(
                x: cx,
                y: cy + halfH - leaderArrowMarginTop() * controlScale
            )
        }
    }


    // MARK: - Game Over Screen
    func showGameOverScreen(title: String = "GAME OVER") {
        GameCenterManager.shared.submitScore(score)

        gameOverOverlay?.removeFromParent()
        gameOverOverlay = nil

        let cx = cameraNode.position.x, cy = cameraNode.position.y
        let canRevive = !hasUsedRevive
        let isExpert  = gameMode == .challenge

        let overlay = SKNode()
        overlay.zPosition = 1000
        overlay.name      = "gameOverOverlay"

        // Dimmed full-screen background
        let bg = SKShapeNode(rectOf: CGSize(width: size.width * 2, height: size.height * 2))
        bg.fillColor   = SKColor(red: 0.06, green: 0.08, blue: 0.18, alpha: 0.88)
        bg.strokeColor = .clear
        bg.position    = CGPoint(x: cx, y: cy)
        overlay.addChild(bg)

        // Card layout constants — all positions relative to card centre (cx, cy)
        let cardW: CGFloat = min(300, size.width * 0.82)
        let cardH: CGFloat = canRevive ? 370 : 320
        let cardCY = cy   // card vertically centred on screen

        // Card glow ring (outside the card for depth)
        let glowRing = SKShapeNode(rectOf: CGSize(width: cardW + 12, height: cardH + 12), cornerRadius: 26)
        glowRing.fillColor   = .clear
        glowRing.strokeColor = isExpert
            ? SKColor(red: 1.0, green: 0.45, blue: 0.20, alpha: 0.35)
            : SKColor(red: 0.35, green: 0.78, blue: 0.92, alpha: 0.35)
        glowRing.lineWidth   = 2
        glowRing.glowWidth   = 14
        glowRing.position    = CGPoint(x: cx, y: cardCY)
        overlay.addChild(glowRing)

        // Main card
        let card = SKShapeNode(rectOf: CGSize(width: cardW, height: cardH), cornerRadius: 22)
        card.fillColor   = SKColor(red: 0.12, green: 0.16, blue: 0.28, alpha: 0.97)
        card.strokeColor = isExpert
            ? SKColor(red: 1.0, green: 0.60, blue: 0.20, alpha: 0.30)
            : SKColor(red: 0.40, green: 0.82, blue: 0.75, alpha: 0.30)
        card.lineWidth   = 1.5
        card.position    = CGPoint(x: cx, y: cardCY)
        overlay.addChild(card)

        // Title
        let titleLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        titleLabel.text                    = title
        titleLabel.fontSize                = 34
        titleLabel.fontColor               = .white
        titleLabel.horizontalAlignmentMode = .center
        titleLabel.verticalAlignmentMode   = .center
        titleLabel.position                = CGPoint(x: cx, y: cardCY + cardH / 2 - 46)
        overlay.addChild(titleLabel)

        // Score display
        let scoreLine = SKLabelNode(fontNamed: "Arial-BoldMT")
        scoreLine.text                    = "Score  \(score)"
        scoreLine.fontSize                = 28
        scoreLine.fontColor               = isExpert
            ? SKColor(red: 1.0, green: 0.72, blue: 0.35, alpha: 1.0)
            : SKColor(red: 0.45, green: 0.95, blue: 0.85, alpha: 1.0)
        scoreLine.horizontalAlignmentMode = .center
        scoreLine.verticalAlignmentMode   = .center
        scoreLine.position                = CGPoint(x: cx, y: cardCY + cardH / 2 - 96)
        overlay.addChild(scoreLine)

        // Divider line
        let divPath = CGMutablePath()
        divPath.move(to: CGPoint(x: cx - cardW * 0.36, y: cardCY + cardH / 2 - 120))
        divPath.addLine(to: CGPoint(x: cx + cardW * 0.36, y: cardCY + cardH / 2 - 120))
        let div = SKShapeNode(path: divPath)
        div.strokeColor = SKColor(white: 1.0, alpha: 0.12)
        div.lineWidth   = 1
        overlay.addChild(div)

        // Button Y positions (inside card, below score/divider)
        let buttonSpacing: CGFloat = 62
        let firstBtnY = canRevive
            ? cardCY - cardH / 2 + 194   // leave room for 3 buttons
            : cardCY - cardH / 2 + 152   // 2 buttons

        // Helper to build a pill button
        func makeButton(label: String, fillColor: SKColor, strokeColor: SKColor,
                        glowW: CGFloat, yPos: CGFloat, name: String) {
            let btnBg = SKShapeNode(rectOf: CGSize(width: cardW - 56, height: 50), cornerRadius: 14)
            btnBg.fillColor   = fillColor
            btnBg.strokeColor = strokeColor
            btnBg.lineWidth   = 1.5
            btnBg.glowWidth   = glowW
            btnBg.position    = CGPoint(x: cx, y: yPos)
            btnBg.name        = name
            overlay.addChild(btnBg)

            // Specular highlight strip on button
            let btnSheen = SKShapeNode(rectOf: CGSize(width: cardW - 80, height: 10), cornerRadius: 5)
            btnSheen.fillColor   = SKColor(white: 1.0, alpha: 0.14)
            btnSheen.strokeColor = .clear
            btnSheen.position    = CGPoint(x: cx, y: yPos + 14)
            btnSheen.zPosition   = 0.5
            overlay.addChild(btnSheen)

            let lbl = SKLabelNode(fontNamed: "Arial-BoldMT")
            lbl.text                    = label
            lbl.fontSize                = 19
            lbl.fontColor               = .white
            lbl.horizontalAlignmentMode = .center
            lbl.verticalAlignmentMode   = .center
            lbl.position                = CGPoint(x: cx, y: yPos)
            lbl.name                    = name
            overlay.addChild(lbl)
        }

        var nextBtnY = firstBtnY
        if canRevive {
            makeButton(
                label:       "⚡ Revive",
                fillColor:   SKColor(red: 0.90, green: 0.58, blue: 0.0, alpha: 1.0),
                strokeColor: SKColor(red: 1.0, green: 0.85, blue: 0.25, alpha: 0.70),
                glowW:       10,
                yPos:        nextBtnY,
                name:        "reviveButton"
            )
            nextBtnY -= buttonSpacing
        }

        makeButton(
            label:       "Play Again",
            fillColor:   SKColor(red: 0.18, green: 0.70, blue: 0.60, alpha: 1.0),
            strokeColor: SKColor(white: 1.0, alpha: 0.22),
            glowW:       6,
            yPos:        nextBtnY,
            name:        "restartButton"
        )
        nextBtnY -= buttonSpacing

        makeButton(
            label:       "Main Menu",
            fillColor:   SKColor(red: 0.18, green: 0.22, blue: 0.36, alpha: 0.95),
            strokeColor: SKColor(white: 1.0, alpha: 0.18),
            glowW:       0,
            yPos:        nextBtnY,
            name:        "playAgainButton"
        )

        // Controller navigation
        gameOverButtonOrder = canRevive
            ? ["reviveButton", "restartButton", "playAgainButton"]
            : ["restartButton", "playAgainButton"]
        gameOverFocusedIndex = 0

        if connectedController != nil {
            let hint = SKLabelNode(fontNamed: "Arial")
            hint.text = "↕  Navigate   ·   A Confirm   ·   B Menu"
            hint.fontSize = 11
            hint.fontColor = SKColor(white: 1, alpha: 0.32)
            hint.horizontalAlignmentMode = .center
            hint.verticalAlignmentMode   = .center
            hint.position = CGPoint(x: cx, y: cardCY - cardH / 2 + 20)
            overlay.addChild(hint)
        }

        overlay.alpha = 0
        addChild(overlay)
        gameOverOverlay = overlay
        overlay.run(SKAction.fadeIn(withDuration: 0.35))
        if connectedController != nil { applyGameOverFocusHighlight() }
    }

    func restartGame() {
        stopBackgroundMusic()
        setupNewGame()
        startBackgroundMusic()
    }

    // MARK: - Game Over Controller Navigation
    func applyGameOverFocusHighlight() {
        for (i, name) in gameOverButtonOrder.enumerated() {
            guard let node = gameOverOverlay?.children.first(where: {
                $0.name == name && $0 is SKShapeNode
            }) as? SKShapeNode else { continue }
            if i == gameOverFocusedIndex {
                node.strokeColor = SKColor(white: 1.0, alpha: 0.90)
                node.glowWidth   = 18
                node.setScale(1.06)
            } else {
                node.strokeColor = SKColor(white: 1.0, alpha: 0.18)
                node.glowWidth   = 2
                node.setScale(1.0)
            }
        }
    }

    func navigateGameOver(by delta: Int) {
        guard isGameOver, !gameOverButtonOrder.isEmpty else { return }
        gameOverFocusedIndex = (gameOverFocusedIndex + delta + gameOverButtonOrder.count) % gameOverButtonOrder.count
        applyGameOverFocusHighlight()
    }

    func confirmGameOverSelection() {
        guard isGameOver, !gameOverButtonOrder.isEmpty else { return }
        switch gameOverButtonOrder[gameOverFocusedIndex] {
        case "reviveButton":    revivePlayer()
        case "restartButton":   restartGame()
        case "playAgainButton": shutdown(); onGameOver?(score)
        default: break
        }
    }

    // MARK: - Revive
    func revivePlayer() {
        guard !hasUsedRevive else { return }
        hasUsedRevive = true

        // Remove game over overlay
        gameOverOverlay?.removeFromParent()
        gameOverOverlay = nil

        // Reset body nodes and rebuild position history at arena center
        for seg in bodySegments { releaseBodySegmentNode(seg) }
        bodySegments.removeAll()
        bodyPositionCache.removeAll()

        let spawnPos = CGPoint(x: worldSize / 2, y: worldSize / 2)
        let reviveBodyCount = max(initialBodyCount, initialBodyCount + score / 20)
        let historyNeeded = historyCapacity(forSegmentCount: reviveBodyCount)
        positionHistory.setCapacity(historyNeeded)
        positionHistory.removeAll()
        for k in 0..<historyNeeded {
            positionHistory.append(CGPoint(x: spawnPos.x - CGFloat(k) * 0.5, y: spawnPos.y))
        }
        for index in 0..<reviveBodyCount {
            let segment = acquireBodySegmentNode(segIndex: index)
            segment.position = CGPoint(x: spawnPos.x - CGFloat(index + 1) * segmentPixelSpacing, y: spawnPos.y)
            addChild(segment)
            bodySegments.append(segment)
        }
        ensurePointCacheLength(bodySegments.count, cache: &bodyPositionCache)
        for i in 0..<bodySegments.count {
            bodyPositionCache[i] = CGPoint(x: spawnPos.x - CGFloat(i + 1) * segmentPixelSpacing, y: spawnPos.y)
        }
        updatePlayerBodyPathAndCollisionSet()

        // Reposition head
        snakeHead.removeFromParent()
        snakeHead.position = spawnPos
        addChild(snakeHead)
        currentAngle = 0
        targetAngle  = 0
        lastPlayerPosition = spawnPos

        // Restore game state
        isGameOver    = false
        shieldActive  = false
        multiplierActive   = false
        multiplierTimeLeft = 0
        magnetActive  = false
        magnetTimeLeft = 0
        ghostActive   = false
        ghostTimeLeft  = 0
        scoreMultiplier = 1
        boostZoomExtra  = 0
        refreshPowerUpPanel()

        // 3 seconds invincibility with flashing
        invincibleTimeLeft = 3.0
        snakeHead.run(SKAction.repeat(
            SKAction.sequence([
                SKAction.fadeAlpha(to: 0.25, duration: 0.18),
                SKAction.fadeAlpha(to: 1.0,  duration: 0.18)
            ]),
            count: 8
        ))

        startBackgroundMusic()
    }


    // MARK: - Score Panel
    func createScorePanel() {
        // Large score at top-center; position updated every frame in updateHUDPositions()
        let scoreFontSize: CGFloat = isIPadLayout ? 50 : 42
        hudScoreFontSize = scoreFontSize

        let shadow = SKLabelNode(fontNamed: "Arial-BoldMT")
        shadow.text                    = "0"
        shadow.fontSize                = scoreFontSize
        shadow.fontColor               = SKColor(red: 0, green: 0, blue: 0, alpha: 0.55)
        shadow.horizontalAlignmentMode = .center
        shadow.verticalAlignmentMode   = .top
        shadow.position                = CGPoint(x: 2, y: -2)
        shadow.zPosition               = -1
        shadow.name                    = "scoreShadow"

        scoreLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        scoreLabel.text                    = "0"
        scoreLabel.fontSize                = scoreFontSize
        scoreLabel.fontColor               = .white
        scoreLabel.horizontalAlignmentMode = .center
        scoreLabel.verticalAlignmentMode   = .top
        scoreLabel.zPosition               = 501
        scoreLabel.addChild(shadow)

        // Initial position — overwritten by updateHUDPositions() each frame
        let cx = worldSize / 2, cy = worldSize / 2
        scoreLabel.position = CGPoint(x: cx, y: cy + size.height / 2 - 20)
        addChild(scoreLabel)
    }


    func updateScoreDisplay() {
        guard scoreLabel != nil else { return }
        scoreLabel.text = "\(score)"
        (scoreLabel.childNode(withName: "scoreShadow") as? SKLabelNode)?.text = "\(score)"
        miniLeaderboardNeedsRefresh = true
    }

    // MARK: - Combo System

    func incrementCombo() {
        comboCount    += 1
        comboTimer     = 0
        comboFadeTimer = comboFadeSecs
        updateComboDisplay()
    }

    func tickCombo(dt: CGFloat) {
        guard comboCount > 0 else { return }
        comboTimer += dt
        if comboTimer >= comboWindowSecs {
            comboCount = 0
            comboTimer = 0
            updateComboDisplay()
            return
        }
        comboFadeTimer = max(0, comboFadeTimer - dt)
        if comboFadeTimer <= 0 {
            comboLabel?.alpha      = 0
            comboPanelNode?.alpha  = 0
        }
    }

    func updateComboDisplay() {
        guard comboCount >= 2 else {
            comboLabel?.alpha     = 0
            comboPanelNode?.alpha = 0
            return
        }
        let stars = String(repeating: "★", count: min(comboCount, comboMaxDisplay))
        comboLabel?.text  = "COMBO \(comboCount)× \(stars)"
        comboLabel?.alpha     = 1
        comboPanelNode?.alpha = 1
    }

    func createComboHUD() {
        let panel = SKShapeNode(rect: CGRect(x: 0, y: 0, width: 190, height: 34), cornerRadius: 10)
        panel.fillColor   = SKColor(red: 1.0, green: 0.75, blue: 0.0, alpha: 0.85)
        panel.strokeColor = .clear
        panel.zPosition   = 501
        panel.alpha       = 0
        addChild(panel)
        comboPanelNode = panel

        let label = SKLabelNode(fontNamed: "Arial-BoldMT")
        label.fontSize                = 14
        label.fontColor               = SKColor(red: 0.1, green: 0.05, blue: 0.0, alpha: 1.0)
        label.verticalAlignmentMode   = .center
        label.horizontalAlignmentMode = .center
        label.position                = CGPoint(x: 95, y: 17)
        label.zPosition               = 502
        panel.addChild(label)
        comboLabel = label
    }

    func historyCapacity(forSegmentCount count: Int) -> Int {
        max(64, Int(CGFloat(max(count, 1) + 5) * segmentPixelSpacing) + 200)
    }

    func ensurePointCacheLength(_ count: Int, cache: inout [CGPoint]) {
        if cache.count == count { return }
        if cache.count < count {
            cache.append(contentsOf: repeatElement(.zero, count: count - cache.count))
        } else {
            cache.removeLast(cache.count - count)
        }
    }

    func cacheBodyPositions(from nodes: [SKShapeNode], into cache: inout [CGPoint]) {
        ensurePointCacheLength(nodes.count, cache: &cache)
        guard !nodes.isEmpty else { return }
        for index in nodes.indices {
            cache[index] = nodes[index].position
        }
    }

    func interactionRadiusForPlayerBody() -> CGFloat {
        CGFloat(max(1, bodySegments.count)) * segmentPixelSpacing + 140
    }

    func botPairWithinBroadPhase(_ lhs: BotState, _ rhs: BotState) -> Bool {
        let dx = lhs.position.x - rhs.position.x
        let dy = lhs.position.y - rhs.position.y
        let radius = botCollisionBroadPhaseRadius + CGFloat(max(lhs.bodyLength, rhs.bodyLength)) * 0.6
        return dx * dx + dy * dy <= radius * radius
    }

    func headCollidesWithPoints(_ head: CGPoint, points: [CGPoint], combinedRadius: CGFloat, skip: Int = 0) -> Bool {
        guard points.count > skip else { return false }
        let thresholdSq = combinedRadius * combinedRadius
        for index in skip..<points.count {
            let dx = head.x - points[index].x
            if abs(dx) >= combinedRadius { continue }
            let dy = head.y - points[index].y
            if abs(dy) >= combinedRadius { continue }
            if dx * dx + dy * dy < thresholdSq { return true }
        }
        return false
    }

    func headCollidesWithPoints(_ head: CGPoint, points: [CGPoint], startIndex: Int, combinedRadius: CGFloat) -> Bool {
        guard points.count > startIndex else { return false }
        let thresholdSq = combinedRadius * combinedRadius
        for index in startIndex..<points.count {
            let dx = head.x - points[index].x
            if abs(dx) >= combinedRadius { continue }
            let dy = head.y - points[index].y
            if abs(dy) >= combinedRadius { continue }
            if dx * dx + dy * dy < thresholdSq { return true }
        }
        return false
    }

    private func headCollidesWithNodes(_ head: CGPoint, nodes: [SKShapeNode], combinedRadius: CGFloat, skip: Int = 0) -> Bool {
        guard nodes.count > skip else { return false }
        let thresholdSq = combinedRadius * combinedRadius
        for index in skip..<nodes.count {
            let point = nodes[index].position
            let dx = head.x - point.x
            let dy = head.y - point.y
            if dx * dx + dy * dy < thresholdSq {
                return true
            }
        }
        return false
    }

    // MARK: - Mini Leaderboard
    func createMiniLeaderboard() {
        let node = SKNode()
        node.zPosition = 500
        // Initial position is corrected by updateHUDPositions() immediately after; just place it off-screen.
        node.position = CGPoint(x: worldSize / 2, y: worldSize / 2)
        addChild(node)
        miniLeaderboard = node
    }

    func updateMiniLeaderboard() {
        guard let lb = miniLeaderboard else { return }
        lb.removeAllChildren()
        miniLeaderboardNeedsRefresh = false

        var entries: [LeaderboardScoreEntry] = [LeaderboardScoreEntry(
            name: playerDisplayName(),
            score: score,
            isCurrentPlayer: true
        )]
        for i in 0..<bots.count where bots[i].isActive && !bots[i].isDead {
            entries.append(LeaderboardScoreEntry(name: bots[i].name, score: bots[i].score, isCurrentPlayer: false))
        }
        let visibleEntries = GameLogic.leaderboardDisplayEntries(from: entries)
        let panelHeight = CGFloat(max(visibleEntries.count, 1)) * 20 + 34
        miniLeaderboardPanelHeight = panelHeight

        let bg = SKShapeNode(rectOf: CGSize(width: 184, height: panelHeight), cornerRadius: 14)
        bg.fillColor = SKColor(red: 0.05, green: 0.08, blue: 0.15, alpha: 0.50)
        bg.strokeColor = SKColor(red: 0.80, green: 0.92, blue: 1.0, alpha: 0.18)
        bg.lineWidth = 1
        lb.addChild(bg)

        let title = SKLabelNode(fontNamed: "Arial-BoldMT")
        title.text = "LEADERS"
        title.fontSize = 11
        title.fontColor = SKColor(white: 1.0, alpha: 0.52)
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode = .center
        title.position = CGPoint(x: 0, y: panelHeight / 2 - 16)
        lb.addChild(title)

        for (i, entry) in visibleEntries.enumerated() {
            let label = SKLabelNode(fontNamed: "Arial-BoldMT")
            label.text      = "\(entry.rank). \(entry.name)  \(entry.score)"
            label.fontSize  = 13
            label.fontColor = entry.isCurrentPlayer
                ? SKColor(red: 1, green: 0.85, blue: 0, alpha: 1)   // gold for player
                : SKColor(white: 1, alpha: 0.70)
            label.horizontalAlignmentMode = .left
            label.verticalAlignmentMode   = .center
            label.position = CGPoint(x: -84, y: panelHeight / 2 - 36 - CGFloat(i) * 20)
            // -84 = -(184/2) + 8 → 8pt left padding inside the 184pt-wide panel
            lb.addChild(label)
        }
    }

    // MARK: - Minimap
    func createMinimap() {
        minimapBotDots.removeAll()
        let mapSize: CGFloat = 118
        let container = SKNode()
        container.zPosition = 490
        container.name      = "minimapContainer"

        let bg = SKShapeNode(rectOf: CGSize(width: mapSize, height: mapSize), cornerRadius: 16)
        bg.fillColor   = SKColor(red: 0.07, green: 0.10, blue: 0.15, alpha: 0.30)
        bg.strokeColor = SKColor(red: 0.80, green: 0.92, blue: 1.0, alpha: 0.22)
        bg.lineWidth   = 1.2
        container.addChild(bg)

        let innerBorder = SKShapeNode(rectOf: CGSize(width: mapSize - 8, height: mapSize - 8), cornerRadius: 13)
        innerBorder.fillColor   = .clear
        innerBorder.strokeColor = SKColor(red: 0.25, green: 0.45, blue: 0.52, alpha: 0.26)
        innerBorder.lineWidth   = 0.8
        container.addChild(innerBorder)

        let crosshairPath = CGMutablePath()
        crosshairPath.move(to: CGPoint(x: -mapSize / 2 + 10, y: 0))
        crosshairPath.addLine(to: CGPoint(x: mapSize / 2 - 10, y: 0))
        crosshairPath.move(to: CGPoint(x: 0, y: -mapSize / 2 + 10))
        crosshairPath.addLine(to: CGPoint(x: 0, y: mapSize / 2 - 10))
        let crosshair = SKShapeNode(path: crosshairPath)
        crosshair.strokeColor = SKColor(red: 0.83, green: 0.92, blue: 0.96, alpha: 0.10)
        crosshair.lineWidth = 0.8
        container.addChild(crosshair)

        let playerDot = SKShapeNode(circleOfRadius: 3.5)
        playerDot.fillColor   = SKColor(red: 1.0, green: 0.9, blue: 0.1, alpha: 1.0)
        playerDot.strokeColor = .clear
        playerDot.zPosition   = 2
        container.addChild(playerDot)
        minimapPlayerDot = playerDot

        for _ in 0..<localBotTargetCount {
            let dot = SKShapeNode(circleOfRadius: 2.0)
            dot.fillColor   = SKColor(white: 0.8, alpha: 0.65)
            dot.strokeColor = .clear
            dot.zPosition   = 1
            dot.isHidden    = true
            container.addChild(dot)
            minimapBotDots.append(dot)
        }

        // Initial position (will be updated by updateHUDPositions each frame)
        let cx = worldSize / 2, cy = worldSize / 2
        container.position = CGPoint(x: cx + size.width/2 - 65, y: cy + size.height/2 - 55)
        addChild(container)
        minimapNode = container
    }

    func updateMinimap() {
        guard let _ = minimapNode, let playerDot = minimapPlayerDot else { return }
        let mapSize: CGFloat = 118
        let world = CGFloat(worldSize)

        let px = (snakeHead.position.x / world - 0.5) * mapSize
        let py = (snakeHead.position.y / world - 0.5) * mapSize
        playerDot.position = CGPoint(x: px, y: py)

        for (i, dot) in minimapBotDots.enumerated() {
            guard i < bots.count else { break }
            if !bots[i].isDead {
                let bx = (bots[i].position.x / world - 0.5) * mapSize
                let by = (bots[i].position.y / world - 0.5) * mapSize
                dot.position = CGPoint(x: bx, y: by)
                let theme = snakeColorThemes[bots[i].colorIndex % snakeColorThemes.count]
                dot.fillColor = theme.bodySKColor.withAlphaComponent(bots[i].isActive ? 0.82 : 0.48)
                dot.isHidden = false
            } else {
                dot.isHidden = true
            }
        }

    }

    func createLeaderArrow() {
        let node = SKNode()
        node.zPosition = 505
        node.isHidden = true

        let ring = SKShapeNode(circleOfRadius: 14)
        ring.fillColor = SKColor(red: 0.05, green: 0.08, blue: 0.15, alpha: 0.42)
        ring.strokeColor = SKColor(red: 0.80, green: 0.92, blue: 1.0, alpha: 0.24)
        ring.lineWidth = 1.2
        node.addChild(ring)

        let arrowPath = CGMutablePath()
        arrowPath.move(to: CGPoint(x: 0, y: 12))
        arrowPath.addLine(to: CGPoint(x: 8, y: -8))
        arrowPath.addLine(to: CGPoint(x: 0, y: -3))
        arrowPath.addLine(to: CGPoint(x: -8, y: -8))
        arrowPath.closeSubpath()

        let arrow = SKShapeNode(path: arrowPath)
        arrow.fillColor = SKColor(red: 1.0, green: 0.82, blue: 0.18, alpha: 0.96)
        arrow.strokeColor = SKColor(red: 1.0, green: 0.94, blue: 0.62, alpha: 0.98)
        arrow.lineWidth = 1.0
        arrow.glowWidth = 4
        node.addChild(arrow)

        let label = SKLabelNode(fontNamed: "Arial-BoldMT")
        label.fontSize = 10
        label.fontColor = SKColor(white: 1.0, alpha: 0.82)
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: -22)
        label.text = ""
        node.addChild(label)

        addChild(node)
        leaderArrowNode = node
        leaderArrowLabel = label
    }

    private func highestScoringSnakeTarget() -> (name: String, score: Int, position: CGPoint, isPlayer: Bool)? {
        guard snakeHead != nil else { return nil }

        var best: (name: String, score: Int, position: CGPoint, isPlayer: Bool) = (
            name: playerDisplayName(),
            score: score,
            position: snakeHead.position,
            isPlayer: true
        )

        for bot in bots where !bot.isDead {
            if bot.score > best.score {
                best = (name: bot.name, score: bot.score, position: bot.position, isPlayer: false)
            }
        }


        return best
    }

    func updateLeaderArrow() {
        guard let arrowNode = leaderArrowNode, let label = leaderArrowLabel else { return }
        guard let target = highestScoringSnakeTarget(), !target.isPlayer else {
            arrowNode.isHidden = true
            return
        }

        let dx = target.position.x - cameraNode.position.x
        let dy = target.position.y - cameraNode.position.y
        let extents = cameraHalfExtents()
        let inView = abs(dx) <= extents.halfW - 50 && abs(dy) <= extents.halfH - 90
        if inView {
            arrowNode.isHidden = true
            return
        }

        arrowNode.isHidden = false
        arrowNode.zRotation = atan2(dy, dx) - .pi / 2
        label.zRotation = -arrowNode.zRotation
        let displayName = target.name.count > 10 ? String(target.name.prefix(10)) : target.name
        label.text = "\(displayName) \(target.score)"
    }

}
