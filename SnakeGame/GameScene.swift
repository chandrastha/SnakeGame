import SpriteKit
import AVFoundation
import UIKit

// MARK: - FoodType
enum FoodType {
    case regular
    case speedBoost   // ⚡️ speed up for 5s
    case shield       // 🛡 absorbs one death
    case multiplier   // ⭐ 2× score for 10s
    case trail        // 🌱 left by snake movement
    case death        // 💀 scattered from a dead snake body — 5 pts each
    case magnet       // 🧲 pulls nearby food toward snake for 6s
    case ghost        // 👻 pass through snake bodies for 4s
    case shrink       // ✂️ instantly removes 30% of body (escape tool)
}

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
    var name: String
    var isActive: Bool        // true = has SpriteKit nodes

    // SpriteKit nodes – nil when virtual
    var head: SKShapeNode?
    var body: [SKShapeNode]
    var posHistory: [CGPoint]
    var nameLabel: SKLabelNode?

    // Virtual movement: change direction every ~3 s
    var dirChangeTimer: CGFloat

    // Offline mode tier system
    var tier: BotTier          // assigned by spawnBots(); default .easy
    var isDead: Bool           // true during respawn delay countdown
    var respawnTimer: CGFloat  // seconds remaining before bot reappears
    var aggressionActive: Bool // true when hard/medium bot is currently intercepting player

    init(id: Int, position: CGPoint, colorIndex: Int, name: String) {
        self.id           = id
        self.position     = position
        self.angle        = CGFloat.random(in: 0...(2 * .pi))
        self.targetAngle  = self.angle
        self.score        = Int.random(in: 0...30)
        self.bodyLength   = 10 + Int.random(in: 0...20)
        self.colorIndex   = colorIndex
        self.name         = name
        self.isActive     = false
        self.body         = []
        self.posHistory   = []
        self.dirChangeTimer = CGFloat.random(in: 1...3)
        self.tier             = .easy
        self.isDead           = false
        self.respawnTimer     = 0
        self.aggressionActive = false
    }
}

// MARK: - Remote Player (Online Mode)
struct RemotePlayer {
    var head: SKShapeNode
    var body: [SKShapeNode]
    var posHistory: [CGPoint]
    var score: Int
    var bodyLength: Int
    var nameLabel: SKLabelNode
    var colorIndex: Int
    var playerName: String
}

// MARK: - GameScene
class GameScene: SKScene {

    // MARK: - Callbacks & Config
    var onGameOver: ((Int) -> Void)?
    var playerHeadImage: UIImage?
    var gameMode: GameMode = .offline
    var selectedSnakeColorIndex: Int = 0
    var selectedSnakePatternIndex: Int = 0
    var playerName: String = "Player"

    // MARK: - Audio
    var backgroundMusicPlayer: AVAudioPlayer?
    let eatFoodAction = SKAction.playSoundFileNamed("eat_food.wav", waitForCompletion: false)
    let deathAction   = SKAction.playSoundFileNamed("death.wav",    waitForCompletion: false)

    // MARK: - Timing
    var lastUpdateTime: TimeInterval = 0

    // MARK: - World & Camera
    let worldSize: CGFloat = 4000.0
    let visibleRadius: CGFloat = 700.0
    var cameraNode = SKCameraNode()

    // MARK: - Constants
    let baseMoveSpeed:           CGFloat = 100.0
    let maxMoveSpeed:            CGFloat = 200.0
    let turnSpeed:               CGFloat = 280.0
    let wallAvoidanceDistance:   CGFloat = 80.0
    let playerAvoidanceDistance: CGFloat = 100.0
    let headRadius:              CGFloat = 13.0
    let bodySegmentRadius:       CGFloat = 10.0
    let collisionRadius:         CGFloat = 12.0
    let foodRadius:              CGFloat = 20.0
    let safeSpawnDistance:       CGFloat = 80.0
    let foodPadding:             CGFloat = 80.0
    let initialBodyCount:        Int     = 10
    let spacingBetweenSegments:  Int     = 8
    let segmentPixelSpacing:     CGFloat = 14.0
    let foodCount:               Int     = 200
    let maxDeltaTime:            Double  = 1.0 / 30.0

    // MARK: - Speed & Boost
    var currentMoveSpeed: CGFloat = 100.0
    var isBoostHeld:      Bool    = false
    let boostMultiplier:  CGFloat = 1.65

    // MARK: - Player Snake
    var snakeHead: SKNode!
    var bodySegments:    [SKShapeNode] = []
    var positionHistory: [CGPoint]     = []
    var currentAngle: CGFloat = 0
    var targetAngle:  CGFloat = 0
    var isTouching:   Bool    = false

    // MARK: - Joystick
    let joystickBaseRadius:  CGFloat = 65
    let joystickThumbRadius: CGFloat = 28
    var joystickCenter:      CGPoint = .zero
    var joystickThumbOffset: CGPoint = .zero
    var joystickBaseNode:    SKShapeNode?
    var joystickInnerRing:   SKShapeNode?
    var joystickThumbNode:   SKShapeNode?
    var joystickTouch: UITouch?

    // MARK: - Boost Button
    let boostButtonRadius: CGFloat = 36
    var boostButtonCenter: CGPoint = .zero
    var boostButtonNode:   SKNode?
    var boostTouch:        UITouch?
    // Boost energy meter
    var boostEnergy:        CGFloat = 100.0
    let boostEnergyMax:     CGFloat = 100.0
    let boostDrainRate:     CGFloat = 25.0   // units/sec while boosting (~4s full drain)
    let boostRegenRate:     CGFloat = 10.0   // units/sec while idle (~10s full regen)
    let boostMinEnergy:     CGFloat = 15.0   // minimum to activate boost
    var boostEnergyArcNode: SKShapeNode?

    // MARK: - Food
    let fruitEmojis: [String] = ["🍎","🍊","🍋","🍇","🍓","🍉","🍑","🍌","🫐","🍒"]
    var foodItems: [SKLabelNode] = []
    var foodTypes: [FoodType]   = []
    // Trail food
    var trailFoodTimer: CGFloat = 0
    let trailFoodInterval: CGFloat = 1.2
    let trailFoodEmojis: [String] = ["🌱", "💧", "⭐", "🫧"]
    let deathFoodEmojis: [String] = ["💀", "🔮", "💠"]

    // MARK: - Arena
    var arenaMinX: CGFloat = 0, arenaMaxX: CGFloat = 4000
    var arenaMinY: CGFloat = 0, arenaMaxY: CGFloat = 4000
    var isGameOver: Bool = false

    // MARK: - Score & HUD
    var scorePanel:       SKShapeNode!
    var scoreLabel:       SKLabelNode!
    var scorePanelHeight: CGFloat = 40
    var miniLeaderboard:  SKNode?
    var leaderboardUpdateTimer: CGFloat = 0

    // MARK: - Game State
    var gameOverOverlay:    SKNode? = nil
    var gameSetupComplete:  Bool    = false
    var gameStarted:        Bool    = false
    var isPausedGame:       Bool    = false
    var lastPlayerPosition: CGPoint = .zero

    // MARK: - Power-ups
    var shieldActive:        Bool    = false
    var speedBoostActive:    Bool    = false
    var speedBoostTimeLeft:  CGFloat = 0
    var multiplierActive:    Bool    = false
    var multiplierTimeLeft:  CGFloat = 0
    var invincibleTimeLeft:  CGFloat = 0
    var magnetActive:        Bool    = false
    var magnetTimeLeft:      CGFloat = 0
    let magnetRadius:        CGFloat = 220.0
    var ghostActive:         Bool    = false
    var ghostTimeLeft:       CGFloat = 0
    var score:          Int = 0
    var scoreMultiplier: Int = 1

    // MARK: - Other UI
    var pauseButton:  SKNode?
    var pauseOverlay: SKNode?
    var powerUpPanel: SKShapeNode?
    var powerUpLabel: SKLabelNode?

    // MARK: - Minimap
    var minimapNode:              SKNode?
    var minimapPlayerDot:         SKShapeNode?
    var minimapBotDots:           [SKShapeNode] = []
    var minimapRemotePlayerDots:  [Int: SKShapeNode] = [:]

    // MARK: - Shield Wiggle
    var tailWigglePhase: CGFloat = 0

    // MARK: - Bots (Offline mode)
    var bots: [BotState] = []
    let totalBots = 30
    let botActivationRadius:   CGFloat = 800.0
    let botDeactivationRadius: CGFloat = 1000.0
    // Per-tier base speeds (replaces single botMoveSpeed)
    let botSpeedEasy:   CGFloat = 95.0
    let botSpeedMedium: CGFloat = 120.0
    let botSpeedHard:   CGFloat = 150.0
    let botSpeedScoreCap: Int = 100
    var frameCounter = 0
    var botBodyUpdateFrame: Int = 0

    // MARK: - Remote Players (Online mode)
    var remotePlayers: [Int: RemotePlayer] = [:]

    // Bot name pool (100 names for 99 bots)
    static let botNamePool: [String] = [
        "Noodle","Sizzle","Chomp","Drake","Volt","Blaze","Frost","Viper","Ivy","Coral",
        "Arrow","Star","Byte","Melon","Pixel","Nova","Onyx","Rex","Sage","Titan",
        "Uma","Vex","Wren","Xen","Yeti","Zap","Ace","Bolt","Claw","Dusk",
        "Echo","Fang","Gale","Haze","Iris","Jade","Kite","Luna","Mist","Nero",
        "Opal","Pine","Quill","Raze","Sand","Twig","Ursa","Vale","Wisp","Axel",
        "Brix","Cruz","Dash","Edge","Flux","Grip","Hook","Ion","Jolt","Knox",
        "Lynx","Maze","Nix","Orb","Pyre","Rift","Scorch","Thane","Umbra","Vibe",
        "Warp","Xray","Yarn","Zero","Alpha","Bravo","Cobra","Delta","Eagle","Foxtrot",
        "Ghost","Hawk","Igloo","Juliet","Karma","Lima","Mike","Night","Oscar","Papa",
        "Quartz","Romeo","Sierra","Tango","Union","Victor","Whisky","Xander","Yankee","Zulu"
    ]

    // MARK: - Scene Setup
    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = true
        setupNewGame()
        startBackgroundMusic()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard size.width > 0, size.height > 0, oldSize != size else { return }
        if !gameSetupComplete {
            finishSetup()
        } else {
            repositionUI()
            if isGameOver {
                gameOverOverlay?.removeFromParent()
                gameOverOverlay = nil
                showGameOverScreen()
            }
        }
    }

    func setupNewGame() {
        isGameOver          = false
        isTouching          = false
        currentAngle        = 0
        targetAngle         = 0
        score               = 0
        lastUpdateTime      = 0
        gameSetupComplete   = false
        gameStarted         = false
        isPausedGame        = false
        scoreMultiplier     = 1
        shieldActive        = false
        speedBoostActive    = false
        speedBoostTimeLeft  = 0
        multiplierActive    = false
        multiplierTimeLeft  = 0
        invincibleTimeLeft  = 0
        magnetActive        = false
        magnetTimeLeft      = 0
        ghostActive         = false
        ghostTimeLeft       = 0
        currentMoveSpeed    = baseMoveSpeed
        isBoostHeld         = false
        boostEnergy         = boostEnergyMax
        joystickTouch       = nil
        boostTouch          = nil
        joystickThumbOffset = .zero
        frameCounter        = 0
        leaderboardUpdateTimer = 0
        trailFoodTimer      = 0
        tailWigglePhase     = 0

        removeAllChildren()
        bodySegments.removeAll()
        positionHistory.removeAll()
        bots.removeAll()
        remotePlayers.removeAll()
        foodItems.removeAll()
        foodTypes.removeAll()
        minimapRemotePlayerDots.removeAll()
        gameOverOverlay   = nil
        pauseOverlay      = nil
        powerUpPanel      = nil
        powerUpLabel      = nil
        joystickBaseNode  = nil
        joystickInnerRing = nil
        joystickThumbNode = nil
        boostButtonNode   = nil
        miniLeaderboard   = nil

        backgroundColor = SKColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1.0)
        arenaMinX = 0; arenaMaxX = worldSize
        arenaMinY = 0; arenaMaxY = worldSize

        if size.width > 0, size.height > 0 { finishSetup() }
    }

    func finishSetup() {
        guard size.width > 0, size.height > 0 else { return }

        // Camera
        cameraNode = SKCameraNode()
        cameraNode.position = CGPoint(x: worldSize / 2, y: worldSize / 2)
        addChild(cameraNode)
        camera = cameraNode

        // Initial HUD world positions based on camera at world center
        let cx = worldSize / 2, cy = worldSize / 2
        joystickCenter    = CGPoint(x: cx - size.width/2 + 90,  y: cy - size.height/2 + 100)
        boostButtonCenter = CGPoint(x: cx + size.width/2 - 88,  y: cy - size.height/2 + 100)

        createArenaBorder()
        createSnakeHead()
        createInitialBody()
        createScorePanel()
        createMiniLeaderboard()
        createMinimap()
        if gameMode == .offline { createPauseButton() }
        createJoystick()
        createBoostButton()
        spawnInitialFood()
        updateScoreDisplay()

        if gameMode == .offline {
            spawnBots()
        } else if gameMode == .online {
            PhotonManager.shared.delegate = self
            PhotonManager.shared.sendGameReady()
        }

        gameSetupComplete = true
        startCountdown()
    }

    // MARK: - Arena Border
    func createArenaBorder() {
        // Arena background fill
        let arenaBg = SKShapeNode(rect: CGRect(x: 0, y: 0, width: worldSize, height: worldSize))
        arenaBg.fillColor   = SKColor(red: 0.05, green: 0.07, blue: 0.12, alpha: 1.0)
        arenaBg.strokeColor = .clear
        arenaBg.zPosition   = -11
        addChild(arenaBg)

        // Grid texture lines
        createArenaGrid()

        // Danger zone (inner boundary warning)
        let danger = SKShapeNode(rect: CGRect(
            x: wallAvoidanceDistance, y: wallAvoidanceDistance,
            width: worldSize - wallAvoidanceDistance * 2,
            height: worldSize - wallAvoidanceDistance * 2
        ))
        danger.strokeColor = SKColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.18)
        danger.lineWidth   = 2
        danger.fillColor   = .clear
        danger.zPosition   = -9
        addChild(danger)

        // Glowing border — multiple layers for a neon glow effect
        let borderRect = CGRect(x: 0, y: 0, width: worldSize, height: worldSize)

        // Outer soft glow
        let outerGlow = SKShapeNode(rect: borderRect)
        outerGlow.strokeColor = SKColor(red: 0.0, green: 0.85, blue: 1.0, alpha: 0.25)
        outerGlow.lineWidth   = 16
        outerGlow.glowWidth   = 20
        outerGlow.fillColor   = .clear
        outerGlow.zPosition   = -8
        addChild(outerGlow)

        // Mid glow
        let midGlow = SKShapeNode(rect: borderRect)
        midGlow.strokeColor = SKColor(red: 0.0, green: 0.90, blue: 1.0, alpha: 0.55)
        midGlow.lineWidth   = 6
        midGlow.glowWidth   = 10
        midGlow.fillColor   = .clear
        midGlow.zPosition   = -7
        addChild(midGlow)

        // Inner bright line
        let innerLine = SKShapeNode(rect: borderRect)
        innerLine.strokeColor = SKColor(red: 0.4, green: 0.95, blue: 1.0, alpha: 0.90)
        innerLine.lineWidth   = 3
        innerLine.glowWidth   = 4
        innerLine.fillColor   = .clear
        innerLine.zPosition   = -6
        addChild(innerLine)
    }

    func createArenaGrid() {
        let step: CGFloat = 120.0
        let path = CGMutablePath()

        // Vertical lines
        var x: CGFloat = step
        while x < worldSize {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: worldSize))
            x += step
        }

        // Horizontal lines
        var y: CGFloat = step
        while y < worldSize {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: worldSize, y: y))
            y += step
        }

        let grid = SKShapeNode(path: path)
        grid.strokeColor = SKColor(red: 0.3, green: 0.5, blue: 0.8, alpha: 0.08)
        grid.lineWidth   = 1
        grid.fillColor   = .clear
        grid.zPosition   = -10
        addChild(grid)

        // Dot at each grid intersection
        let dotPath = CGMutablePath()
        let dotR: CGFloat = 2.5
        var dx: CGFloat = step
        while dx <= worldSize {
            var dy: CGFloat = step
            while dy <= worldSize {
                dotPath.addEllipse(in: CGRect(x: dx - dotR, y: dy - dotR,
                                              width: dotR * 2, height: dotR * 2))
                dy += step
            }
            dx += step
        }
        let dots = SKShapeNode(path: dotPath)
        dots.fillColor   = SKColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 0.12)
        dots.strokeColor = .clear
        dots.zPosition   = -10
        addChild(dots)
    }

    // MARK: - Countdown
    func startCountdown() {
        gameStarted = false

        let countLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        countLabel.fontSize                = 110
        countLabel.fontColor               = .white
        countLabel.horizontalAlignmentMode = .center
        countLabel.verticalAlignmentMode   = .center
        countLabel.position                = CGPoint(x: worldSize / 2, y: worldSize / 2)
        countLabel.zPosition               = 900
        countLabel.alpha                   = 0
        addChild(countLabel)

        func pop(_ text: String, color: SKColor = .white, then next: @escaping () -> Void) {
            countLabel.text      = text
            countLabel.fontColor = color
            countLabel.alpha     = 1
            countLabel.setScale(1.6)
            countLabel.run(SKAction.scale(to: 1.0, duration: 0.25))
            run(SKAction.wait(forDuration: 0.8)) {
                countLabel.run(SKAction.fadeOut(withDuration: 0.15)) { next() }
            }
        }

        pop("3") { pop("2") { pop("1") {
            pop("GO!", color: SKColor(red: 0.3, green: 0.9, blue: 0.3, alpha: 1.0)) {
                countLabel.removeFromParent()
                self.gameStarted = true
            }
        }}}
    }

    // MARK: - Camera Follow
    func updateCamera() {
        let halfW = size.width  / 2
        let halfH = size.height / 2
        let clampedX = max(halfW, min(worldSize - halfW, snakeHead.position.x))
        let clampedY = max(halfH, min(worldSize - halfH, snakeHead.position.y))
        cameraNode.position = CGPoint(x: clampedX, y: clampedY)
    }

    // MARK: - HUD Positions (world-space, updated every frame)
    func updateHUDPositions() {
        let cx = cameraNode.position.x
        let cy = cameraNode.position.y

        joystickCenter    = CGPoint(x: cx - size.width/2 + 90,  y: cy - size.height/2 + 100)
        boostButtonCenter = CGPoint(x: cx + size.width/2 - 88,  y: cy - size.height/2 + 100)

        joystickBaseNode?.position  = joystickCenter
        joystickInnerRing?.position = joystickCenter
        if joystickTouch == nil {
            joystickThumbNode?.position = joystickCenter
        } else {
            joystickThumbNode?.position = CGPoint(
                x: joystickCenter.x + joystickThumbOffset.x,
                y: joystickCenter.y + joystickThumbOffset.y
            )
        }
        boostButtonNode?.position = boostButtonCenter

        let panelH = scorePanelHeight
        scorePanel?.position  = CGPoint(x: cx - size.width/2 + 20, y: cy + size.height/2 - 60 - panelH)
        pauseButton?.position = CGPoint(x: cx + size.width/2 - 42, y: cy + size.height/2 - 42)
        powerUpPanel?.position = CGPoint(x: cx, y: cy - size.height/2 + 170)
        // Minimap sits in top-right; leaderboard is pushed down below it
        minimapNode?.position     = CGPoint(x: cx + size.width/2 - 65, y: cy + size.height/2 - 55)
        miniLeaderboard?.position = CGPoint(x: cx + size.width/2 - 10, y: cy + size.height/2 - 195)
    }

    // MARK: - Pause
    func createPauseButton() {
        let btn = SKNode()
        btn.zPosition = 600
        btn.name      = "pauseButton"

        let bg = SKShapeNode(rectOf: CGSize(width: 44, height: 44), cornerRadius: 10)
        bg.fillColor   = SKColor(white: 0, alpha: 0.6)
        bg.strokeColor = .clear
        bg.name        = "pauseButton"
        btn.addChild(bg)

        let icon = SKLabelNode(text: "⏸")
        icon.fontSize                = 22
        icon.horizontalAlignmentMode = .center
        icon.verticalAlignmentMode   = .center
        icon.name                    = "pauseButton"
        btn.addChild(icon)

        let cx = worldSize / 2, cy = worldSize / 2
        btn.position = CGPoint(x: cx + size.width/2 - 42, y: cy + size.height/2 - 42)
        addChild(btn)
        pauseButton = btn
    }

    func togglePause() {
        if isPausedGame {
            isPausedGame   = false
            lastUpdateTime = 0
            pauseOverlay?.removeFromParent()
            pauseOverlay = nil
        } else {
            isPausedGame = true
            showPauseOverlay()
        }
    }

    func showPauseOverlay() {
        let cx = cameraNode.position.x, cy = cameraNode.position.y

        let overlay = SKNode()
        overlay.zPosition = 800
        overlay.name      = "pauseOverlay"

        let bg = SKShapeNode(rectOf: CGSize(width: size.width * 2, height: size.height * 2))
        bg.fillColor   = SKColor(white: 0, alpha: 0.65)
        bg.strokeColor = .clear
        bg.position    = CGPoint(x: cx, y: cy)
        overlay.addChild(bg)

        let title = SKLabelNode(fontNamed: "Arial-BoldMT")
        title.text                    = "PAUSED"
        title.fontSize                = 52
        title.fontColor               = .white
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode   = .center
        title.position                = CGPoint(x: cx, y: cy + 60)
        overlay.addChild(title)

        let resumeBg = SKShapeNode(rectOf: CGSize(width: 200, height: 55), cornerRadius: 14)
        resumeBg.fillColor   = SKColor(red: 0.2, green: 0.75, blue: 0.3, alpha: 1.0)
        resumeBg.strokeColor = .clear
        resumeBg.position    = CGPoint(x: cx, y: cy - 10)
        resumeBg.name        = "resumeButton"
        overlay.addChild(resumeBg)

        let resumeLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        resumeLabel.text                    = "▶  Resume"
        resumeLabel.fontSize                = 22
        resumeLabel.fontColor               = .white
        resumeLabel.horizontalAlignmentMode = .center
        resumeLabel.verticalAlignmentMode   = .center
        resumeLabel.position                = CGPoint(x: cx, y: cy - 10)
        resumeLabel.name                    = "resumeButton"
        overlay.addChild(resumeLabel)

        let quitBg = SKShapeNode(rectOf: CGSize(width: 200, height: 55), cornerRadius: 14)
        quitBg.fillColor   = SKColor(red: 0.75, green: 0.2, blue: 0.2, alpha: 1.0)
        quitBg.strokeColor = .clear
        quitBg.position    = CGPoint(x: cx, y: cy - 85)
        quitBg.name        = "quitButton"
        overlay.addChild(quitBg)

        let quitLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        quitLabel.text                    = "✕  Quit to Menu"
        quitLabel.fontSize                = 20
        quitLabel.fontColor               = .white
        quitLabel.horizontalAlignmentMode = .center
        quitLabel.verticalAlignmentMode   = .center
        quitLabel.position                = CGPoint(x: cx, y: cy - 85)
        quitLabel.name                    = "quitButton"
        overlay.addChild(quitLabel)

        addChild(overlay)
        pauseOverlay = overlay
    }

    // MARK: - Joystick
    func createJoystick() {
        let base = SKShapeNode(circleOfRadius: joystickBaseRadius)
        base.fillColor   = SKColor(white: 1, alpha: 0.06)
        base.strokeColor = SKColor(white: 1, alpha: 0.22)
        base.lineWidth   = 2
        base.position    = joystickCenter
        base.zPosition   = 500
        addChild(base)
        joystickBaseNode = base

        let ring = SKShapeNode(circleOfRadius: joystickBaseRadius * 0.60)
        ring.fillColor   = .clear
        ring.strokeColor = SKColor(white: 1, alpha: 0.10)
        ring.lineWidth   = 1.5
        ring.position    = joystickCenter
        ring.zPosition   = 500
        addChild(ring)
        joystickInnerRing = ring

        let thumb = SKShapeNode(circleOfRadius: joystickThumbRadius)
        thumb.fillColor   = SKColor(white: 1, alpha: 0.30)
        thumb.strokeColor = SKColor(white: 1, alpha: 0.60)
        thumb.lineWidth   = 2
        thumb.glowWidth   = 6
        thumb.position    = joystickCenter
        thumb.zPosition   = 501
        addChild(thumb)
        joystickThumbNode = thumb
    }

    func updateJoystick(at location: CGPoint) {
        let dx    = location.x - joystickCenter.x
        let dy    = location.y - joystickCenter.y
        let dist  = hypot(dx, dy)
        let clamp = min(dist, joystickBaseRadius)
        let angle = atan2(dy, dx)

        joystickThumbOffset = CGPoint(x: cos(angle) * clamp, y: sin(angle) * clamp)
        joystickThumbNode?.position = CGPoint(
            x: joystickCenter.x + joystickThumbOffset.x,
            y: joystickCenter.y + joystickThumbOffset.y
        )

        if dist > 8 {
            targetAngle = angle
            isTouching  = true
        }
    }

    func resetJoystick() {
        joystickThumbOffset = .zero
        joystickThumbNode?.run(SKAction.move(to: joystickCenter, duration: 0.12))
        isTouching    = false
        joystickTouch = nil
    }

    // MARK: - Boost Button
    func createBoostButton() {
        let btn = SKNode()
        btn.position  = boostButtonCenter
        btn.zPosition = 500

        let circle = SKShapeNode(circleOfRadius: boostButtonRadius)
        circle.fillColor   = SKColor(white: 1.0, alpha: 0.10)
        circle.strokeColor = SKColor(white: 1.0, alpha: 0.40)
        circle.lineWidth   = 1.5
        circle.glowWidth   = 3
        circle.name        = "boostCircle"
        btn.addChild(circle)

        let label = SKLabelNode(text: "⚡")
        label.fontSize                = 20
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode   = .center
        btn.addChild(label)

        // Energy arc background ring (child of btn, so it tracks with the button)
        let bgRing = SKShapeNode(circleOfRadius: boostButtonRadius + 5)
        bgRing.fillColor   = .clear
        bgRing.strokeColor = SKColor(white: 1.0, alpha: 0.15)
        bgRing.lineWidth   = 3
        bgRing.zPosition   = 1
        btn.addChild(bgRing)

        // Foreground arc — updated every frame by updateBoostEnergyArc()
        let arc = SKShapeNode()
        arc.fillColor   = .clear
        arc.strokeColor = SKColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 0.9)
        arc.lineWidth   = 3
        arc.lineCap     = .round
        arc.zPosition   = 2
        btn.addChild(arc)
        boostEnergyArcNode = arc

        addChild(btn)
        boostButtonNode = btn
    }

    func updateBoostEnergyArc() {
        guard let arc = boostEnergyArcNode else { return }
        let fraction = boostEnergy / boostEnergyMax
        let endAngle = -.pi / 2.0 + fraction * 2.0 * .pi
        let path = CGMutablePath()
        // Arc uses local coordinates (parent = btn, origin = button center)
        path.addArc(center: .zero, radius: boostButtonRadius + 5,
                    startAngle: -.pi / 2.0, endAngle: endAngle, clockwise: false)
        arc.path        = path
        arc.strokeColor = fraction > 0.3
            ? SKColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 0.9)
            : SKColor(red: 1.0, green: 0.25, blue: 0.1,  alpha: 0.9)
    }

    func setBoostButtonActive(_ active: Bool) {
        guard let btn = boostButtonNode else { return }
        if let circle = btn.childNode(withName: "boostCircle") as? SKShapeNode {
            circle.fillColor   = active
                ? SKColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 0.35)
                : SKColor(white: 1.0, alpha: 0.10)
            circle.strokeColor = active
                ? SKColor(red: 1.0, green: 0.90, blue: 0.0, alpha: 0.85)
                : SKColor(white: 1.0, alpha: 0.40)
            circle.glowWidth = active ? 10 : 3
        }
        btn.run(SKAction.scale(to: active ? 1.15 : 1.0, duration: 0.09))
    }

    // MARK: - Power-up Panel
    func refreshPowerUpPanel() {
        // Power-up status text removed from HUD to keep the play area clean
        powerUpPanel?.isHidden = true
    }

    // MARK: - Background Music
    func startBackgroundMusic() {
        guard let url = Bundle.main.url(forResource: "background_music", withExtension: "mp3") else { return }
        do {
            backgroundMusicPlayer = try AVAudioPlayer(contentsOf: url)
            backgroundMusicPlayer?.numberOfLoops = -1
            backgroundMusicPlayer?.volume        = 0.15
            backgroundMusicPlayer?.play()
        } catch {}
    }

    func stopBackgroundMusic() {
        backgroundMusicPlayer?.stop()
        backgroundMusicPlayer = nil
    }

    // MARK: - Reposition UI (rotation/resize)
    func repositionUI() {
        updateCamera()
        updateHUDPositions()

        if isPausedGame {
            pauseOverlay?.removeFromParent()
            pauseOverlay = nil
            showPauseOverlay()
        }
    }

    // MARK: - Wall Collision
    func checkWallCollision() -> Bool {
        GameLogic.isOutsideArena(
            point: snakeHead.position, radius: headRadius,
            arenaMinX: arenaMinX, arenaMaxX: arenaMaxX,
            arenaMinY: arenaMinY, arenaMaxY: arenaMaxY
        )
    }

    // MARK: - Player Death
    func playerGameOver() {
        guard !isGameOver else { return }
        guard invincibleTimeLeft <= 0 else { return }

        if shieldActive {
            shieldActive = false
            hideShieldGlow()
            invincibleTimeLeft = 1.5
            spawnShieldAbsorbEffect()
            refreshPowerUpPanel()
            return
        }

        isGameOver         = true
        spawnDeathFood(at: bodySegments.map(\.position))   // body scatters as death food
        lastPlayerPosition = snakeHead.position
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        spawnDeathParticles(at: snakeHead.position)

        if gameMode == .online {
            PhotonManager.shared.sendPlayerDied()
        }

        run(deathAction) { [weak self] in
            self?.stopBackgroundMusic()
            self?.showGameOverScreen()
        }
    }

    // MARK: - Shield Visuals
    func showShieldGlow() {
        // Pulsing blue ring
        let glow = SKShapeNode(circleOfRadius: headRadius + 10)
        glow.fillColor   = SKColor(red: 0.3, green: 0.5, blue: 1.0, alpha: 0.22)
        glow.strokeColor = SKColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 0.90)
        glow.lineWidth   = 2.5
        glow.glowWidth   = 14
        glow.position    = .zero
        glow.zPosition   = -1
        glow.name        = "shieldGlow"
        let pulse = SKAction.repeatForever(SKAction.sequence([
            SKAction.group([SKAction.scale(to: 1.18, duration: 0.55),
                            SKAction.fadeAlpha(to: 0.40, duration: 0.55)]),
            SKAction.group([SKAction.scale(to: 0.92, duration: 0.55),
                            SKAction.fadeAlpha(to: 0.18, duration: 0.55)])
        ]))
        glow.run(pulse)
        snakeHead.addChild(glow)

        // Four orbiting particles that spin around the head
        let orbit = SKNode()
        orbit.name      = "shieldOrbit"
        orbit.zPosition = 2
        for i in 0..<4 {
            let orb = SKShapeNode(circleOfRadius: 3.5)
            orb.fillColor   = SKColor(red: 0.55, green: 0.75, blue: 1.0, alpha: 1.0)
            orb.strokeColor = .clear
            orb.glowWidth   = 5
            let a = CGFloat(i) * (.pi / 2)
            orb.position = CGPoint(x: cos(a) * (headRadius + 18), y: sin(a) * (headRadius + 18))
            orbit.addChild(orb)
        }
        orbit.run(SKAction.repeatForever(SKAction.rotate(byAngle: .pi * 2, duration: 1.6)))
        snakeHead.addChild(orbit)
    }

    func hideShieldGlow() {
        snakeHead.childNode(withName: "shieldGlow")?.removeFromParent()
        snakeHead.childNode(withName: "shieldOrbit")?.removeFromParent()
        tailWigglePhase = 0
        updateSegmentScales()   // restore segment sizes changed by wiggle taper
    }

    func spawnShieldAbsorbEffect() {
        let flash = SKShapeNode(circleOfRadius: headRadius * 2.5)
        flash.fillColor   = SKColor(red: 0.3, green: 0.5, blue: 1.0, alpha: 0.7)
        flash.strokeColor = .clear
        flash.position    = snakeHead.position
        flash.zPosition   = 700
        addChild(flash)
        flash.run(SKAction.sequence([
            SKAction.group([SKAction.scale(to: 2.2, duration: 0.35),
                            SKAction.fadeOut(withDuration: 0.35)]),
            SKAction.removeFromParent()
        ]))
    }

    // MARK: - Game Over Screen
    func showGameOverScreen(title: String = "GAME OVER") {
        gameOverOverlay?.removeFromParent()
        gameOverOverlay = nil

        let cx = cameraNode.position.x, cy = cameraNode.position.y

        let overlay = SKNode()
        overlay.zPosition = 1000
        overlay.name      = "gameOverOverlay"

        let bg = SKShapeNode(rectOf: CGSize(width: size.width * 2, height: size.height * 2))
        bg.fillColor   = SKColor(white: 0.0, alpha: 0.82)
        bg.strokeColor = .clear
        bg.position    = CGPoint(x: cx, y: cy)
        overlay.addChild(bg)

        let titleLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        titleLabel.text                    = title
        titleLabel.fontSize                = 48
        titleLabel.fontColor               = .white
        titleLabel.horizontalAlignmentMode = .center
        titleLabel.verticalAlignmentMode   = .center
        titleLabel.position                = CGPoint(x: cx, y: cy + 100)
        overlay.addChild(titleLabel)

        let finalScore = SKLabelNode(fontNamed: "Arial-BoldMT")
        finalScore.text                    = "\(playerName.isEmpty ? "You" : playerName): \(score)"
        finalScore.fontSize                = 30
        finalScore.fontColor               = SKColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0)
        finalScore.horizontalAlignmentMode = .center
        finalScore.verticalAlignmentMode   = .center
        finalScore.position                = CGPoint(x: cx, y: cy + 30)
        overlay.addChild(finalScore)

        // Play Again / Rejoin button (primary action)
        let restartLabel = gameMode == .online ? "Rejoin" : "Play Again"
        let restartBtnY  = cy - 50
        let restartBg = SKShapeNode(rectOf: CGSize(width: 220, height: 58), cornerRadius: 14)
        restartBg.fillColor   = SKColor(red: 0.2, green: 0.75, blue: 0.3, alpha: 1.0)
        restartBg.strokeColor = .clear
        restartBg.position    = CGPoint(x: cx, y: restartBtnY)
        restartBg.name        = "restartButton"
        overlay.addChild(restartBg)

        let restartLbl = SKLabelNode(fontNamed: "Arial-BoldMT")
        restartLbl.text                    = restartLabel
        restartLbl.fontSize                = 22
        restartLbl.fontColor               = .white
        restartLbl.horizontalAlignmentMode = .center
        restartLbl.verticalAlignmentMode   = .center
        restartLbl.position                = CGPoint(x: cx, y: restartBtnY)
        restartLbl.name                    = "restartButton"
        overlay.addChild(restartLbl)

        // Main Menu button (secondary action)
        let menuBtnY  = cy - 125
        let btnBg = SKShapeNode(rectOf: CGSize(width: 220, height: 58), cornerRadius: 14)
        btnBg.fillColor   = SKColor(white: 0.18, alpha: 0.90)
        btnBg.strokeColor = SKColor(white: 1.0, alpha: 0.15)
        btnBg.lineWidth   = 1
        btnBg.position    = CGPoint(x: cx, y: menuBtnY)
        btnBg.name        = "playAgainButton"
        overlay.addChild(btnBg)

        let btnLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        btnLabel.text                    = "Main Menu"
        btnLabel.fontSize                = 20
        btnLabel.fontColor               = SKColor(white: 0.85, alpha: 1.0)
        btnLabel.horizontalAlignmentMode = .center
        btnLabel.verticalAlignmentMode   = .center
        btnLabel.position                = CGPoint(x: cx, y: menuBtnY)
        btnLabel.name                    = "playAgainButton"
        overlay.addChild(btnLabel)

        overlay.alpha = 0
        addChild(overlay)
        gameOverOverlay = overlay
        overlay.run(SKAction.fadeIn(withDuration: 0.4))
    }

    func restartGame() {
        stopBackgroundMusic()
        setupNewGame()
        startBackgroundMusic()
    }

    // MARK: - Score Panel
    func createScorePanel() {
        scoreLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        scoreLabel.text                    = "Score: 0"
        scoreLabel.fontSize                = 20
        scoreLabel.fontColor               = .white
        scoreLabel.horizontalAlignmentMode = .center
        scoreLabel.verticalAlignmentMode   = .center

        let hPad: CGFloat = 16, vPad: CGFloat = 10
        let panelW = scoreLabel.frame.width + hPad * 2
        let panelH = scoreLabel.frame.height + vPad * 2
        scorePanelHeight = panelH

        scorePanel = SKShapeNode(rect: CGRect(x: 0, y: 0, width: panelW, height: panelH), cornerRadius: 12)
        scorePanel.fillColor   = SKColor(white: 0.0, alpha: 0.70)
        scorePanel.strokeColor = .clear
        scorePanel.zPosition   = 500

        let cx = worldSize / 2, cy = worldSize / 2
        scorePanel.position = CGPoint(x: cx - size.width/2 + 20, y: cy + size.height/2 - 60 - panelH)

        scoreLabel.position = CGPoint(x: panelW / 2, y: panelH / 2)
        scorePanel.addChild(scoreLabel)
        addChild(scorePanel)
    }

    func updateScoreDisplay() {
        guard scoreLabel != nil, scorePanel != nil else { return }
        scoreLabel.text = "Score: \(score)"
        let hPad: CGFloat = 16, vPad: CGFloat = 10
        let panelW = max(scoreLabel.frame.width + hPad * 2, 110)
        let panelH = scoreLabel.frame.height + vPad * 2
        scorePanelHeight = panelH
        scorePanel.path = CGPath(
            roundedRect: CGRect(x: 0, y: 0, width: panelW, height: panelH),
            cornerWidth: 12, cornerHeight: 12, transform: nil
        )
        scoreLabel.position = CGPoint(x: panelW / 2, y: panelH / 2)
    }

    // MARK: - Mini Leaderboard
    func createMiniLeaderboard() {
        let node = SKNode()
        node.zPosition = 500
        let cx = worldSize / 2, cy = worldSize / 2
        node.position = CGPoint(x: cx + size.width/2 - 10, y: cy + size.height/2 - 90)
        addChild(node)
        miniLeaderboard = node
    }

    func updateMiniLeaderboard() {
        guard let lb = miniLeaderboard else { return }
        lb.removeAllChildren()

        let myName = playerName.isEmpty ? "You" : playerName
        // isMe flag prevents incorrect highlight when player sets a custom name
        var entries: [(name: String, score: Int, isMe: Bool)] = [(myName, score, true)]
        for i in 0..<bots.count where bots[i].isActive && !bots[i].isDead {
            entries.append((bots[i].name, bots[i].score, false))
        }
        for (_, rp) in remotePlayers {
            entries.append((rp.playerName, rp.score, false))
        }
        entries.sort { $0.score > $1.score }
        let top5 = Array(entries.prefix(5))          // hard cap at 5

        for (i, entry) in top5.enumerated() {
            let label = SKLabelNode(fontNamed: "Arial-BoldMT")
            label.text      = "\(i+1). \(entry.name)  \(entry.score)"
            label.fontSize  = 13
            label.fontColor = entry.isMe
                ? SKColor(red: 1, green: 0.85, blue: 0, alpha: 1)   // gold for player
                : SKColor(white: 1, alpha: 0.70)
            label.horizontalAlignmentMode = .right
            label.verticalAlignmentMode   = .center
            label.position = CGPoint(x: 0, y: -CGFloat(i) * 20)
            lb.addChild(label)
        }
    }

    // MARK: - Minimap
    func createMinimap() {
        minimapBotDots.removeAll()
        let mapSize: CGFloat = 110
        let container = SKNode()
        container.zPosition = 490
        container.name      = "minimapContainer"

        let bg = SKShapeNode(rectOf: CGSize(width: mapSize, height: mapSize), cornerRadius: 4)
        bg.fillColor   = SKColor(white: 0.0, alpha: 0.55)
        bg.strokeColor = SKColor(white: 1.0, alpha: 0.25)
        bg.lineWidth   = 1.0
        container.addChild(bg)

        let innerBorder = SKShapeNode(rectOf: CGSize(width: mapSize - 6, height: mapSize - 6), cornerRadius: 2)
        innerBorder.fillColor   = .clear
        innerBorder.strokeColor = SKColor(white: 1.0, alpha: 0.12)
        innerBorder.lineWidth   = 0.5
        container.addChild(innerBorder)

        let playerDot = SKShapeNode(circleOfRadius: 3.5)
        playerDot.fillColor   = SKColor(red: 1.0, green: 0.9, blue: 0.1, alpha: 1.0)
        playerDot.strokeColor = .clear
        playerDot.zPosition   = 2
        container.addChild(playerDot)
        minimapPlayerDot = playerDot

        for _ in 0..<totalBots {
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
        let mapSize: CGFloat = 110
        let world = CGFloat(worldSize)

        let px = (snakeHead.position.x / world - 0.5) * mapSize
        let py = (snakeHead.position.y / world - 0.5) * mapSize
        playerDot.position = CGPoint(x: px, y: py)

        // Offline: update bot dots
        for (i, dot) in minimapBotDots.enumerated() {
            guard i < bots.count else { break }
            if bots[i].isActive && !bots[i].isDead {
                let bx = (bots[i].position.x / world - 0.5) * mapSize
                let by = (bots[i].position.y / world - 0.5) * mapSize
                dot.position = CGPoint(x: bx, y: by)
                dot.isHidden = false
            } else {
                dot.isHidden = true
            }
        }

        // Online: update remote player dots
        for (actorID, dot) in minimapRemotePlayerDots {
            if let rp = remotePlayers[actorID] {
                let rx = (rp.head.position.x / world - 0.5) * mapSize
                let ry = (rp.head.position.y / world - 0.5) * mapSize
                dot.position = CGPoint(x: rx, y: ry)
                dot.isHidden = false
            } else {
                dot.isHidden = true
            }
        }
    }

    // MARK: - Food System
    func spawnInitialFood() {
        for _ in 0..<foodCount { spawnFood() }
    }

    func spawnFood() {
        // Distribution: regular 40%, multiplier 15%, speedBoost 10%, shield 10%,
        //               magnet 10%, ghost 10%, shrink 5%
        let roll = Int.random(in: 0...19)
        var type: FoodType
        switch roll {
        case 0...7:   type = .regular
        case 8...9:   type = .speedBoost
        case 10...11: type = .shield
        case 12...14: type = .multiplier
        case 15...16: type = .magnet
        case 17...18: type = .ghost
        default:      type = .shrink
        }

        // Cap shields: never more than 2 shield items on the map at once
        let maxShieldsOnMap = 2
        if type == .shield && foodTypes.filter({ $0 == .shield }).count >= maxShieldsOnMap {
            type = .regular
        }

        let food = SKLabelNode()
        switch type {
        case .regular:    food.text = fruitEmojis.randomElement()
        case .speedBoost: food.text = "⚡️"
        case .shield:     food.text = "🛡"
        case .multiplier: food.text = "⭐"
        case .magnet:     food.text = "🧲"
        case .ghost:      food.text = "👻"
        case .shrink:     food.text = "✂️"
        case .trail:      food.text = trailFoodEmojis.randomElement()
        case .death:      food.text = deathFoodEmojis.randomElement()   // not spawned by spawnFood() directly
        }
        food.fontSize                = 28
        food.verticalAlignmentMode   = .center
        food.horizontalAlignmentMode = .center

        var pos = randomPositionInArena()
        var attempts = 0
        while isPositionOnPlayerSnake(pos) && attempts < 20 {
            pos = randomPositionInArena()
            attempts += 1
        }
        food.position = pos
        addChild(food)
        foodItems.append(food)
        foodTypes.append(type)
    }

    func randomPositionInArena() -> CGPoint {
        let minX = arenaMinX + foodPadding, maxX = arenaMaxX - foodPadding
        let minY = arenaMinY + foodPadding, maxY = arenaMaxY - foodPadding
        guard minX < maxX, minY < maxY else { return CGPoint(x: worldSize/2, y: worldSize/2) }
        return CGPoint(x: CGFloat.random(in: minX...maxX), y: CGFloat.random(in: minY...maxY))
    }

    func spawnTrailFood(at position: CGPoint) {
        let food = SKLabelNode(text: trailFoodEmojis.randomElement())
        food.fontSize                = 16   // smaller than regular food
        food.verticalAlignmentMode   = .center
        food.horizontalAlignmentMode = .center
        food.position = position
        food.alpha    = 0
        addChild(food)
        foodItems.append(food)
        foodTypes.append(.trail)
        // Fade in, persist 12s, then fade out and remove node
        food.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: 0.25),
            SKAction.wait(forDuration: 12.0),
            SKAction.fadeOut(withDuration: 1.0),
            SKAction.removeFromParent()
        ]))
    }

    /// Scatter high-value food from a dead snake's body positions.
    /// Spawns at every 3rd segment (max 12 items) to avoid map flooding.
    func spawnDeathFood(at positions: [CGPoint]) {
        guard !positions.isEmpty else { return }
        let step = max(1, positions.count / 12)
        for i in Swift.stride(from: 0, to: positions.count, by: step) {
            let food = SKLabelNode(text: deathFoodEmojis.randomElement()!)
            food.fontSize                = 26
            food.verticalAlignmentMode   = .center
            food.horizontalAlignmentMode = .center
            food.position = positions[i]
            food.alpha    = 0
            addChild(food)
            foodItems.append(food)
            foodTypes.append(.death)
            food.run(SKAction.sequence([
                SKAction.group([SKAction.fadeIn(withDuration: 0.3),
                                SKAction.scale(to: 1.3, duration: 0.15)]),
                SKAction.scale(to: 1.0, duration: 0.15),
                SKAction.wait(forDuration: 15.0),
                SKAction.fadeOut(withDuration: 1.5),
                SKAction.removeFromParent()
            ]))
        }
    }

    func isPositionOnPlayerSnake(_ p: CGPoint) -> Bool {
        if hypot(p.x - snakeHead.position.x, p.y - snakeHead.position.y) < safeSpawnDistance { return true }
        for seg in bodySegments where hypot(p.x - seg.position.x, p.y - seg.position.y) < safeSpawnDistance { return true }
        return false
    }

    func checkFoodCollisions() {
        for (i, food) in foodItems.enumerated().reversed() {
            if hypot(snakeHead.position.x - food.position.x,
                     snakeHead.position.y - food.position.y) < (headRadius + foodRadius) {
                eatFood(at: i)
                return
            }
        }
    }

    func eatFood(at index: Int) {
        let foodPos = foodItems[index].position
        let type    = foodTypes[index]
        foodItems[index].removeFromParent()
        foodItems.remove(at: index)
        foodTypes.remove(at: index)

        if gameMode == .online {
            let newPos = randomPositionInArena()
            PhotonManager.shared.sendFoodEaten(foodIndex: index,
                                               newFoodX: Float(newPos.x),
                                               newFoodY: Float(newPos.y),
                                               newFoodType: 0)
        }

        spawnFood()
        addBodySegment()

        // Apply power-up effects
        switch type {
        case .regular, .trail, .death: break
        case .speedBoost:
            speedBoostActive   = true
            speedBoostTimeLeft = 5.0
        case .shield:
            shieldActive = true
            showShieldGlow()
        case .multiplier:
            multiplierActive   = true
            multiplierTimeLeft = 10.0
            scoreMultiplier    = 2
        case .magnet:
            magnetActive   = true
            magnetTimeLeft = 6.0
            showMagnetActivation()
        case .ghost:
            ghostActive    = true
            ghostTimeLeft  = 4.0
            showGhostEffect()
        case .shrink:
            applyShrink()
        }

        // Per-type point values
        let pts: Int
        switch type {
        case .regular, .speedBoost, .multiplier: pts = 2
        case .shield:                            pts = 1
        case .trail:                             pts = 1
        case .death:                             pts = 5
        case .magnet:                            pts = 2
        case .ghost:                             pts = 2
        case .shrink:                            pts = 1
        }
        score += pts * scoreMultiplier
        updateScoreDisplay()
        updateSpeedForScore()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        run(eatFoodAction)
        spawnFloatingText("+\(pts * scoreMultiplier)", at: foodPos)
        spawnEatParticles(at: foodPos)
        refreshPowerUpPanel()
    }

    func updateSpeedForScore() {
        currentMoveSpeed = GameLogic.calculateSpeed(
            score: score,
            baseMoveSpeed: baseMoveSpeed,
            maxMoveSpeed: maxMoveSpeed,
            speedBoostActive: speedBoostActive
        )
    }

    // MARK: - Floating Score Text
    func spawnFloatingText(_ text: String, at position: CGPoint) {
        let label = SKLabelNode(fontNamed: "Arial-BoldMT")
        label.text                    = text
        label.fontSize                = 24
        label.fontColor               = SKColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0)
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode   = .center
        label.position                = position
        label.zPosition               = 700
        addChild(label)

        label.run(SKAction.sequence([
            SKAction.group([
                SKAction.moveBy(x: 0, y: 65, duration: 0.8),
                SKAction.sequence([SKAction.wait(forDuration: 0.3),
                                   SKAction.fadeOut(withDuration: 0.5)])
            ]),
            SKAction.removeFromParent()
        ]))
    }

    // MARK: - Particle Effects
    func spawnEatParticles(at position: CGPoint) {
        let colors: [SKColor] = [
            SKColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0),
            SKColor(red: 0.4, green: 0.9, blue: 0.4, alpha: 1.0),
            SKColor(red: 1.0, green: 0.5, blue: 0.2, alpha: 1.0)
        ]
        for _ in 0..<8 {
            let p = SKShapeNode(circleOfRadius: 4)
            p.fillColor = colors.randomElement()!; p.strokeColor = .clear
            p.position = position; p.zPosition = 600
            addChild(p)
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let dist  = CGFloat.random(in: 30...70)
            p.run(SKAction.sequence([
                SKAction.group([SKAction.moveBy(x: cos(angle) * dist, y: sin(angle) * dist, duration: 0.5),
                                SKAction.fadeOut(withDuration: 0.5),
                                SKAction.scale(to: 0.1, duration: 0.5)]),
                SKAction.removeFromParent()
            ]))
        }
    }

    func spawnDeathParticles(at position: CGPoint) {
        let colors: [SKColor] = [
            SKColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1.0),
            SKColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1.0),
            SKColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0)
        ]
        for _ in 0..<20 {
            let p = SKShapeNode(circleOfRadius: CGFloat.random(in: 4...8))
            p.fillColor = colors.randomElement()!; p.strokeColor = .clear
            p.position = position; p.zPosition = 600
            addChild(p)
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let dist  = CGFloat.random(in: 50...120)
            p.run(SKAction.sequence([
                SKAction.group([SKAction.moveBy(x: cos(angle) * dist, y: sin(angle) * dist, duration: 0.8),
                                SKAction.fadeOut(withDuration: 0.8),
                                SKAction.scale(to: 0.1, duration: 0.8)]),
                SKAction.removeFromParent()
            ]))
        }
    }

    // MARK: - Snake Head
    func createSnakeHead() {
        let theme    = snakeColorThemes[selectedSnakeColorIndex]
        let spawnPos = CGPoint(x: worldSize / 2, y: worldSize / 2)

        if let image = playerHeadImage {
            let texture = SKTexture(image: cropToCircle(image: image, size: CGSize(width: 40, height: 40)))
            let sprite  = SKSpriteNode(texture: texture)
            sprite.size     = CGSize(width: headRadius * 2, height: headRadius * 2)
            sprite.position = spawnPos
            addChild(sprite)
            snakeHead = sprite
        } else {
            let shape = SKShapeNode(circleOfRadius: headRadius)
            shape.fillColor   = theme.headSKColor
            shape.strokeColor = theme.headStrokeSKColor
            shape.lineWidth   = 2
            shape.glowWidth   = 6
            shape.position    = spawnPos
            addChild(shape)
            snakeHead = shape
            addEyes(to: snakeHead)
        }
        lastPlayerPosition = spawnPos
    }

    // MARK: - Eyes
    func addEyes(to head: SKNode) {
        for xOffset: CGFloat in [-4.5, 4.5] {
            let eye = SKShapeNode(circleOfRadius: 3)
            eye.fillColor   = .white
            eye.strokeColor = .clear
            eye.position    = CGPoint(x: xOffset, y: 5.5)
            eye.zPosition   = 1

            let pupil = SKShapeNode(circleOfRadius: 1.5)
            pupil.fillColor   = SKColor(white: 0.08, alpha: 1.0)
            pupil.strokeColor = .clear
            pupil.position    = CGPoint(x: 0.3, y: 0.3)
            eye.addChild(pupil)
            head.addChild(eye)
        }
    }

    func rotateUIImage(_ image: UIImage, by degrees: CGFloat) -> UIImage {
        let radians = degrees * .pi / 180.0
        let size    = image.size
        UIGraphicsBeginImageContextWithOptions(size, false, image.scale)
        guard let ctx = UIGraphicsGetCurrentContext() else { return image }
        ctx.translateBy(x: size.width / 2, y: size.height / 2)
        ctx.rotate(by: radians)
        ctx.translateBy(x: -size.width / 2, y: -size.height / 2)
        image.draw(at: .zero)
        let result = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return result
    }

    func cropToCircle(image: UIImage, size: CGSize) -> UIImage {
        let rotated = rotateUIImage(image, by: 180)   // rotate 180° so face looks forward
        let rect = CGRect(origin: .zero, size: size)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        UIBezierPath(ovalIn: rect).addClip()
        rotated.draw(in: rect)
        let result = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return result
    }

    // MARK: - Player Body
    func createInitialBody() {
        let spawnPos = CGPoint(x: worldSize / 2, y: worldSize / 2)
        // Pre-populate history with pixel-spaced positions (0.5 px per step)
        let historyNeeded = (initialBodyCount + 5) * Int(segmentPixelSpacing) + 200
        for k in 0..<historyNeeded {
            positionHistory.append(CGPoint(x: spawnPos.x - CGFloat(k) * 0.5, y: spawnPos.y))
        }
        for i in 1...initialBodyCount {
            let seg = makePlayerBodySegment(segIndex: i - 1)
            seg.position = CGPoint(x: spawnPos.x - CGFloat(i) * segmentPixelSpacing, y: spawnPos.y)
            addChild(seg)
            bodySegments.append(seg)
        }
        updateSegmentScales()
    }

    func addBodySegment() {
        let seg = makePlayerBodySegment(segIndex: bodySegments.count)
        seg.position = bodySegments.last?.position ?? snakeHead.position
        addChild(seg)
        bodySegments.append(seg)
        updateSegmentScales()
    }

    func updateSegmentScales() {
        let count = bodySegments.count
        guard count > 0 else { return }
        for (i, seg) in bodySegments.enumerated() {
            let t = count > 1 ? CGFloat(i) / CGFloat(count - 1) : 0
            seg.setScale(1.0 - t * 0.22)
            // Ghost active: keep semi-transparent; otherwise normal taper
            seg.alpha     = ghostActive ? 0.35 : (1.0 - t * 0.10)
            seg.glowWidth = i < count / 2 ? 3 : 0
        }
    }

    func makePlayerBodySegment(segIndex: Int = 0) -> SKShapeNode {
        let theme   = snakeColorThemes[selectedSnakeColorIndex]
        let pattern = SnakePattern(rawValue: selectedSnakePatternIndex) ?? .solid
        return makeBodySegment(color: theme.bodySKColor, stroke: theme.bodyStrokeSKColor,
                               pattern: pattern, segIndex: segIndex)
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

    func makeBodySegment(color: SKColor, stroke: SKColor,
                         pattern: SnakePattern = .solid,
                         segIndex: Int = 0) -> SKShapeNode {
        // Base shape
        let seg: SKShapeNode
        if pattern == .crystal {
            seg = SKShapeNode(path: makeDiamondPath(radius: bodySegmentRadius))
        } else {
            seg = SKShapeNode(circleOfRadius: bodySegmentRadius)
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
        default:
            seg.fillColor   = color
            seg.strokeColor = stroke
        }

        seg.lineWidth = 2
        seg.glowWidth = pattern == .neon ? 14 : 3

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
            dot.position    = CGPoint(x: 0, y: bodySegmentRadius * 0.52)
            dot.zPosition   = 1
            seg.addChild(dot)

        case .scales:
            // Higher-opacity crescent with a visible stroke border
            let arc = SKShapeNode(circleOfRadius: bodySegmentRadius * 0.58)
            arc.fillColor   = SKColor(white: 1.0, alpha: 0.45)
            arc.strokeColor = stroke.withAlphaComponent(0.50)
            arc.lineWidth   = 1.0
            arc.position    = CGPoint(x: bodySegmentRadius * 0.28,
                                      y: bodySegmentRadius * 0.28)
            arc.zPosition   = 1
            seg.addChild(arc)

        case .crystal:
            // Inner diamond highlight — diamond-inside-diamond effect
            let inner = SKShapeNode(path: makeDiamondPath(radius: bodySegmentRadius * 0.45))
            inner.fillColor   = SKColor(white: 1.0, alpha: 0.35)
            inner.strokeColor = .clear
            inner.zPosition   = 1
            seg.addChild(inner)

        case .neon:
            // Second inner ring in body colour for depth
            let ring = SKShapeNode(circleOfRadius: bodySegmentRadius * 0.65)
            ring.fillColor   = .clear
            ring.strokeColor = color.withAlphaComponent(0.55)
            ring.lineWidth   = 2.0
            ring.zPosition   = 1
            seg.addChild(ring)

        case .camo:
            // Real camo: dark-green + dark-brown blotches
            let blotch1 = SKShapeNode(circleOfRadius: bodySegmentRadius * 0.48)
            blotch1.fillColor   = SKColor(red: 0.15, green: 0.45, blue: 0.10, alpha: 0.70)
            blotch1.strokeColor = .clear
            blotch1.position    = CGPoint(x: -bodySegmentRadius * 0.28, y:  bodySegmentRadius * 0.22)
            blotch1.zPosition   = 1
            seg.addChild(blotch1)
            let blotch2 = SKShapeNode(circleOfRadius: bodySegmentRadius * 0.30)
            blotch2.fillColor   = SKColor(red: 0.40, green: 0.25, blue: 0.02, alpha: 0.65)
            blotch2.strokeColor = .clear
            blotch2.position    = CGPoint(x:  bodySegmentRadius * 0.30, y: -bodySegmentRadius * 0.20)
            blotch2.zPosition   = 1
            seg.addChild(blotch2)

        case .galaxy:
            // Stars with varied sizes + purple nebula ring
            let starData: [(CGFloat, CGFloat, CGFloat)] = [(-4, -3, 3.0), (4, -4, 2.0), (-2, 4, 1.5)]
            for (ox, oy, r) in starData {
                let star = SKShapeNode(circleOfRadius: r)
                star.fillColor   = SKColor(white: 1.0, alpha: 0.90)
                star.strokeColor = .clear
                star.position    = CGPoint(x: ox, y: oy)
                star.zPosition   = 1
                seg.addChild(star)
            }
            let nebula = SKShapeNode(circleOfRadius: bodySegmentRadius * 0.78)
            nebula.fillColor   = .clear
            nebula.strokeColor = SKColor(red: 0.60, green: 0.20, blue: 0.90, alpha: 0.55)
            nebula.lineWidth   = 1.5
            nebula.zPosition   = 1
            seg.addChild(nebula)

        default: break
        }

        return seg
    }

    // MARK: - Bot System (Offline Mode)
    func spawnBots() {
        let namePool = GameScene.botNamePool
        for i in 0..<totalBots {
            var colorIndex = (selectedSnakeColorIndex + 1 + (i % (snakeColorThemes.count - 1))) % snakeColorThemes.count
            if colorIndex == selectedSnakeColorIndex {
                colorIndex = (colorIndex + 1) % snakeColorThemes.count
            }
            let name = namePool[i % namePool.count]

            // First 15 spawn near player for immediate action
            let position: CGPoint
            if i < 15 {
                let angle = CGFloat.random(in: 0...(2 * .pi))
                let dist  = CGFloat.random(in: 300...680)
                position = CGPoint(
                    x: max(200, min(worldSize - 200, worldSize/2 + cos(angle) * dist)),
                    y: max(200, min(worldSize - 200, worldSize/2 + sin(angle) * dist))
                )
            } else {
                position = CGPoint(
                    x: CGFloat.random(in: 200...(worldSize - 200)),
                    y: CGFloat.random(in: 200...(worldSize - 200))
                )
            }
            bots.append(BotState(id: i, position: position, colorIndex: colorIndex, name: name))
            // Assign tier: 0–9 easy, 10–21 medium, 22–29 hard
            switch i {
            case 0..<10:  bots[i].tier = .easy
            case 10..<22: bots[i].tier = .medium
            default:      bots[i].tier = .hard
            }
        }
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
        bots[index].head = head

        let nameLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        nameLabel.text      = bot.name
        nameLabel.fontSize  = 12
        nameLabel.fontColor = SKColor(white: 1, alpha: 0.80)
        nameLabel.horizontalAlignmentMode = .center
        nameLabel.verticalAlignmentMode   = .bottom
        nameLabel.position  = CGPoint(x: 0, y: headRadius + 4)
        nameLabel.zPosition = 1
        head.addChild(nameLabel)
        bots[index].nameLabel = nameLabel

        bots[index].posHistory.removeAll()
        let segCount = max(1, bot.bodyLength)
        // Pre-populate history with pixel-spaced positions (0.5 px per step)
        let historyNeeded = (segCount + 5) * Int(segmentPixelSpacing) + 200
        for k in 0..<historyNeeded {
            bots[index].posHistory.append(CGPoint(
                x: bot.position.x - cos(bot.angle) * CGFloat(k) * 0.5,
                y: bot.position.y - sin(bot.angle) * CGFloat(k) * 0.5
            ))
        }
        for i in 1...segCount {
            let seg = makeBodySegment(color: theme.bodySKColor, stroke: theme.bodyStrokeSKColor)
            seg.position = CGPoint(
                x: bot.position.x - cos(bot.angle) * CGFloat(i) * segmentPixelSpacing,
                y: bot.position.y - sin(bot.angle) * CGFloat(i) * segmentPixelSpacing
            )
            addChild(seg)
            bots[index].body.append(seg)
        }
        updateBotBodyScales(index)
        bots[index].isActive = true
    }

    func deactivateBot(_ index: Int) {
        guard bots[index].isActive else { return }
        bots[index].head?.removeFromParent()
        bots[index].head = nil
        bots[index].nameLabel = nil
        for seg in bots[index].body { seg.removeFromParent() }
        bots[index].body.removeAll()
        bots[index].posHistory.removeAll()
        bots[index].isActive = false
    }

    func updateBotBodyScales(_ index: Int) {
        let count = bots[index].body.count
        guard count > 0 else { return }
        for (i, seg) in bots[index].body.enumerated() {
            let t = count > 1 ? CGFloat(i) / CGFloat(count - 1) : 0
            seg.setScale(1.0 - t * 0.22)
            seg.alpha     = 1.0 - t * 0.10
            seg.glowWidth = i < count / 2 ? 3 : 0
        }
    }

    func addBotBodySegment(_ index: Int) {
        guard bots[index].isActive, let head = bots[index].head else {
            bots[index].bodyLength += 1; return
        }
        let theme = snakeColorThemes[bots[index].colorIndex % snakeColorThemes.count]
        let seg   = makeBodySegment(color: theme.bodySKColor, stroke: theme.bodyStrokeSKColor)
        seg.position = bots[index].body.last?.position ?? head.position
        addChild(seg)
        bots[index].body.append(seg)
        bots[index].bodyLength += 1
        updateBotBodyScales(index)
    }

    func respawnBot(_ index: Int) {
        guard !bots[index].isDead else { return }
        if bots[index].isActive {
            spawnDeathFood(at: bots[index].body.map(\.position))  // body becomes death food
            deactivateBot(index)
        }
        // Mark dead with a tier-based respawn delay
        bots[index].isDead           = true
        bots[index].aggressionActive = false
        switch bots[index].tier {
        case .easy:   bots[index].respawnTimer = 4.0
        case .medium: bots[index].respawnTimer = 3.0
        case .hard:   bots[index].respawnTimer = 2.0
        }
    }

    private func finishRespawn(_ index: Int) {
        bots[index].isDead         = false
        bots[index].respawnTimer   = 0
        bots[index].score          = 0
        bots[index].bodyLength     = 10
        bots[index].position       = CGPoint(
            x: CGFloat.random(in: 300...(worldSize - 300)),
            y: CGFloat.random(in: 300...(worldSize - 300))
        )
        bots[index].angle          = CGFloat.random(in: 0...(2 * .pi))
        bots[index].targetAngle    = bots[index].angle
        bots[index].dirChangeTimer = CGFloat.random(in: 1...3)
    }

    /// Returns current move speed for a bot, scaled by player score.
    func botSpeed(for tier: BotTier) -> CGFloat {
        let base: CGFloat
        switch tier {
        case .easy:   base = botSpeedEasy
        case .medium: base = botSpeedMedium
        case .hard:   base = botSpeedHard
        }
        // At score 0: 1.0x; at score 100+: 1.5x
        let fraction = CGFloat(min(score, botSpeedScoreCap)) / CGFloat(botSpeedScoreCap * 2)
        return base * (1.0 + fraction)
    }

    /// Returns the nearest `.death` food within `radius` units of `position`, or nil.
    func findNearestDeathFood(to position: CGPoint, within radius: CGFloat) -> SKLabelNode? {
        var best: SKLabelNode? = nil
        var bestDist = radius
        for (i, food) in foodItems.enumerated() {
            guard foodTypes[i] == .death else { continue }
            let d = hypot(food.position.x - position.x, food.position.y - position.y)
            if d < bestDist { bestDist = d; best = food }
        }
        return best
    }

    func updateBotTargetAngle(_ index: Int) {
        guard let head = bots[index].head else { return }
        let hx = head.position.x, hy = head.position.y

        // 1. Wall avoidance — same for all tiers
        let nearWall = hx - headRadius < wallAvoidanceDistance ||
                       arenaMaxX - (hx + headRadius) < wallAvoidanceDistance ||
                       hy - headRadius < wallAvoidanceDistance ||
                       arenaMaxY - (hy + headRadius) < wallAvoidanceDistance
        if nearWall {
            bots[index].targetAngle = atan2(worldSize/2 - hy, worldSize/2 - hx)
            return
        }

        let tier = bots[index].tier
        let distToPlayer = hypot(snakeHead.position.x - hx, snakeHead.position.y - hy)

        // 2. Death food attraction (medium: 600u, hard: 800u)
        if tier == .medium || tier == .hard {
            let deathRadius: CGFloat = tier == .hard ? 800 : 600
            if let df = findNearestDeathFood(to: head.position, within: deathRadius) {
                bots[index].targetAngle = atan2(df.position.y - hy, df.position.x - hx)
                bots[index].aggressionActive = false
                return
            }
        }

        // 3. Tier-specific player interaction
        switch tier {
        case .hard:
            // Become aggressive when bot is large enough relative to player
            let aggrThreshold = max(0.50, 0.70 - CGFloat(score) / 500.0)
            let botIsLargeEnough = CGFloat(bots[index].bodyLength) >= CGFloat(bodySegments.count) * aggrThreshold
            if botIsLargeEnough && distToPlayer < 600 {
                // Predict player position ahead along their current direction
                let lookahead: CGFloat = 150.0
                let predictedX = snakeHead.position.x + cos(currentAngle) * lookahead
                let predictedY = snakeHead.position.y + sin(currentAngle) * lookahead
                bots[index].targetAngle = atan2(predictedY - hy, predictedX - hx)
                bots[index].aggressionActive = true
                return
            }
            bots[index].aggressionActive = false

        case .medium:
            // Flee only if player is bigger
            if distToPlayer < playerAvoidanceDistance && bodySegments.count > bots[index].bodyLength {
                bots[index].targetAngle = atan2(snakeHead.position.y - hy, snakeHead.position.x - hx) + .pi
                bots[index].aggressionActive = false
                return
            }
            bots[index].aggressionActive = false

        case .easy:
            // Original: flee if player is within avoidance distance
            if distToPlayer < playerAvoidanceDistance {
                bots[index].targetAngle = atan2(snakeHead.position.y - hy, snakeHead.position.x - hx) + .pi
                return
            }
        }

        // 4. Default: aim at nearest food
        guard let fruit = findNearestFood(to: head.position) else { return }
        bots[index].targetAngle = atan2(fruit.position.y - hy, fruit.position.x - hx)
    }

    func updateBots(dt: CGFloat, updateAI: Bool) {
        let playerPos = snakeHead.position

        for i in 0..<bots.count {
            // Respawn delay countdown — skip dead bots entirely
            if bots[i].isDead {
                bots[i].respawnTimer -= dt
                if bots[i].respawnTimer <= 0 { finishRespawn(i) }
                continue
            }

            let dist = hypot(bots[i].position.x - playerPos.x, bots[i].position.y - playerPos.y)

            if !bots[i].isActive && dist < botActivationRadius {
                activateBot(i)
            } else if bots[i].isActive && dist > botDeactivationRadius {
                deactivateBot(i)
            }

            if bots[i].isActive {
                if updateAI { updateBotTargetAngle(i) }
                smoothlyRotate(current: &bots[i].angle, target: bots[i].targetAngle, dt: dt)

                let moveDist = botSpeed(for: bots[i].tier) * dt
                let newX = bots[i].position.x + cos(bots[i].angle) * moveDist
                let newY = bots[i].position.y + sin(bots[i].angle) * moveDist
                bots[i].position = CGPoint(x: newX, y: newY)

                guard let head = bots[i].head else { continue }
                bots[i].posHistory.append(head.position)
                let maxH = Int(CGFloat(bots[i].body.count + 5) * segmentPixelSpacing) + 200
                if bots[i].posHistory.count > maxH {
                    bots[i].posHistory.removeFirst(bots[i].posHistory.count - maxH)
                }

                head.position  = bots[i].position
                head.zRotation = (bots[i].angle * 180 / .pi - 90) * .pi / 180

                if botBodyUpdateFrame == 0 {
                    let botSegPos = arcPositions(history: bots[i].posHistory, leadPos: bots[i].position,
                                                 count: bots[i].body.count, spacing: segmentPixelSpacing)
                    for (j, seg) in bots[i].body.enumerated() { seg.position = botSegPos[j] }

                    // Bot eats nearby food (including trail food)
                    for (f, food) in foodItems.enumerated().reversed() {
                        if hypot(bots[i].position.x - food.position.x,
                                 bots[i].position.y - food.position.y) < (headRadius + foodRadius) {
                            bots[i].score      += 1
                            bots[i].bodyLength += 1
                            food.removeFromParent()
                            foodItems.remove(at: f)
                            foodTypes.remove(at: f)
                            spawnFood()
                            break
                        }
                    }
                }

                if GameLogic.isOutsideArena(point: bots[i].position, radius: headRadius,
                                             arenaMinX: arenaMinX, arenaMaxX: arenaMaxX,
                                             arenaMinY: arenaMinY, arenaMaxY: arenaMaxY) {
                    respawnBot(i); continue
                }
                checkBotFoodCollision(i)

            } else {
                // Virtual bot: simple random walk, bounce at walls
                bots[i].dirChangeTimer -= dt
                if bots[i].dirChangeTimer <= 0 {
                    bots[i].targetAngle    = CGFloat.random(in: 0...(2 * .pi))
                    bots[i].dirChangeTimer = CGFloat.random(in: 2...4)
                }
                smoothlyRotate(current: &bots[i].angle, target: bots[i].targetAngle, dt: dt)

                var newX = bots[i].position.x + cos(bots[i].angle) * botSpeed(for: bots[i].tier) * dt
                var newY = bots[i].position.y + sin(bots[i].angle) * botSpeed(for: bots[i].tier) * dt

                if newX < wallAvoidanceDistance || newX > worldSize - wallAvoidanceDistance {
                    bots[i].angle = .pi - bots[i].angle
                    newX = max(wallAvoidanceDistance, min(worldSize - wallAvoidanceDistance, newX))
                }
                if newY < wallAvoidanceDistance || newY > worldSize - wallAvoidanceDistance {
                    bots[i].angle = -bots[i].angle
                    newY = max(wallAvoidanceDistance, min(worldSize - wallAvoidanceDistance, newY))
                }
                bots[i].position = CGPoint(x: newX, y: newY)
            }
        }
    }

    func checkBotFoodCollision(_ botIndex: Int) {
        guard let head = bots[botIndex].head else { return }
        for (i, food) in foodItems.enumerated().reversed() {
            if hypot(head.position.x - food.position.x,
                     head.position.y - food.position.y) < (headRadius + foodRadius) {
                food.removeFromParent()
                foodItems.remove(at: i)
                foodTypes.remove(at: i)
                spawnFood()
                addBotBodySegment(botIndex)
                bots[botIndex].score += 1
                return
            }
        }
    }

    func checkPlayerCollidesWithBotBodies() -> Bool {
        if ghostActive { return false }   // 👻 ghost: pass through bodies
        for bot in bots where bot.isActive && !bot.isDead {
            if GameLogic.headCollidesWithBody(
                head: snakeHead.position,
                segments: bot.body.map(\.position),
                combinedRadius: collisionRadius + bodySegmentRadius,
                skip: 0
            ) { return true }
        }
        return false
    }

    /// Offline: player head collides with a bot head → both die (head-to-head).
    func checkPlayerHeadVsBotHeads() -> Bool {
        guard gameMode == .offline, !ghostActive else { return false }
        for i in 0..<bots.count {
            guard bots[i].isActive, !bots[i].isDead, let botHead = bots[i].head else { continue }
            let dist = hypot(snakeHead.position.x - botHead.position.x,
                             snakeHead.position.y - botHead.position.y)
            if dist < (headRadius + headRadius) {
                respawnBot(i)   // bot dies simultaneously
                return true     // player also dies (caller triggers playerGameOver)
            }
        }
        return false
    }

    /// Offline: any active bot's head hitting the player's body kills that bot.
    func checkBotHeadsHitPlayerBody() {
        guard gameMode == .offline else { return }
        let playerBodyPositions = bodySegments.map(\.position)
        guard !playerBodyPositions.isEmpty else { return }
        for i in 0..<bots.count {
            guard bots[i].isActive, !bots[i].isDead, let botHead = bots[i].head else { continue }
            if GameLogic.headCollidesWithBody(
                head: botHead.position,
                segments: playerBodyPositions,
                combinedRadius: collisionRadius + bodySegmentRadius,
                skip: 0
            ) {
                respawnBot(i)
            }
        }
    }

    // MARK: - Remote Players (Online Mode)
    func addRemotePlayer(actorID: Int, colorIndex: Int, headPos: CGPoint, playerName: String = "Player") {
        let theme = snakeColorThemes[colorIndex % snakeColorThemes.count]

        let head = SKShapeNode(circleOfRadius: headRadius)
        head.fillColor   = theme.headSKColor
        head.strokeColor = theme.headStrokeSKColor
        head.lineWidth   = 2
        head.glowWidth   = 5
        head.position    = headPos
        addChild(head)
        addEyes(to: head)

        let nameLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        nameLabel.text      = playerName
        nameLabel.fontSize  = 12
        nameLabel.fontColor = SKColor(white: 1, alpha: 0.8)
        nameLabel.horizontalAlignmentMode = .center
        nameLabel.verticalAlignmentMode   = .bottom
        nameLabel.position  = CGPoint(x: 0, y: headRadius + 4)
        head.addChild(nameLabel)

        // Minimap dot for this remote player
        if let mapContainer = minimapNode {
            let dot = SKShapeNode(circleOfRadius: 2.5)
            dot.fillColor   = SKColor(red: 0.3, green: 0.9, blue: 1.0, alpha: 0.9)
            dot.strokeColor = .clear
            dot.zPosition   = 1
            mapContainer.addChild(dot)
            minimapRemotePlayerDots[actorID] = dot
        }

        remotePlayers[actorID] = RemotePlayer(
            head: head, body: [], posHistory: [], score: 0,
            bodyLength: 10, nameLabel: nameLabel, colorIndex: colorIndex,
            playerName: playerName
        )
    }

    func removeRemotePlayer(actorID: Int) {
        guard let rp = remotePlayers[actorID] else { return }
        rp.head.removeFromParent()
        for seg in rp.body { seg.removeFromParent() }
        remotePlayers.removeValue(forKey: actorID)
        minimapRemotePlayerDots[actorID]?.removeFromParent()
        minimapRemotePlayerDots.removeValue(forKey: actorID)
    }

    func updateRemotePlayerPosition(actorID: Int, headX: Float, headY: Float,
                                    angle: Float, score: Int32, bodyLength: Int32) {
        guard var rp = remotePlayers[actorID] else { return }
        let newPos    = CGPoint(x: CGFloat(headX), y: CGFloat(headY))
        let segCount  = max(1, Int(bodyLength))
        let theme     = snakeColorThemes[rp.colorIndex % snakeColorThemes.count]

        rp.head.run(SKAction.move(to: newPos, duration: 0.05))
        rp.head.zRotation = (CGFloat(angle) * 180 / .pi - 90) * .pi / 180

        // Maintain position history (same cap logic as local player)
        rp.posHistory.append(newPos)
        let maxH = Int(CGFloat(segCount + 5) * segmentPixelSpacing) + 200
        if rp.posHistory.count > maxH { rp.posHistory.removeFirst(rp.posHistory.count - maxH) }

        rp.score      = Int(score)
        rp.bodyLength = segCount

        // ── Sync body segment node count ──────────────────────────────────
        while rp.body.count < segCount {
            let seg = makeBodySegment(color: theme.bodySKColor, stroke: theme.bodyStrokeSKColor)
            seg.zPosition = 5
            addChild(seg)
            rp.body.append(seg)
        }
        while rp.body.count > segCount {
            rp.body.last?.removeFromParent()
            rp.body.removeLast()
        }

        // ── Position body segments along recorded path ────────────────────
        let segPositions = arcPositions(history: rp.posHistory, leadPos: newPos,
                                        count: rp.body.count, spacing: segmentPixelSpacing)
        let dist      = hypot(snakeHead.position.x - newPos.x, snakeHead.position.y - newPos.y)
        let isVisible = dist <= visibleRadius
        rp.head.isHidden = !isVisible

        for (i, seg) in rp.body.enumerated() {
            seg.position = segPositions[i]
            seg.isHidden = !isVisible
            // Taper scale + alpha toward tail (same look as local player)
            let t: CGFloat = segCount > 1 ? CGFloat(i) / CGFloat(segCount - 1) : 0
            seg.setScale(1.0 - t * 0.22)
            seg.alpha     = 1.0 - t * 0.10
            seg.glowWidth = i < segCount / 2 ? 3 : 0
        }

        remotePlayers[actorID] = rp
    }

    func checkPlayerCollidesWithRemotePlayers() -> Bool {
        if ghostActive { return false }   // 👻 ghost: pass through bodies
        for (_, rp) in remotePlayers where !rp.head.isHidden {
            if GameLogic.headCollidesWithBody(
                head: snakeHead.position,
                segments: rp.body.map(\.position),
                combinedRadius: collisionRadius + bodySegmentRadius,
                skip: 0
            ) { return true }
        }
        return false
    }

    // MARK: - New Power-Up Effects

    /// 🧲 Magnet — pull nearby food items toward the snake head.
    func applyMagnetEffect() {
        let pullStrength: CGFloat = 5.5
        for food in foodItems {
            let dx   = snakeHead.position.x - food.position.x
            let dy   = snakeHead.position.y - food.position.y
            let dist = hypot(dx, dy)
            guard dist > 1, dist < magnetRadius else { continue }
            food.position.x += (dx / dist) * pullStrength
            food.position.y += (dy / dist) * pullStrength
        }
    }

    /// ✂️ Shrink — instantly remove ~30% of body segments; gives a brief invincibility window.
    func applyShrink() {
        let keepCount   = max(3, Int(CGFloat(bodySegments.count) * 0.70))
        let removeCount = bodySegments.count - keepCount
        guard removeCount > 0 else { return }
        for _ in 0..<removeCount {
            bodySegments.last?.removeFromParent()
            if !bodySegments.isEmpty { bodySegments.removeLast() }
        }
        invincibleTimeLeft = 0.8   // brief safety window after shrink
        updateSegmentScales()
        spawnFloatingText("✂️ Shrink!", at: CGPoint(x: snakeHead.position.x, y: snakeHead.position.y + 60))
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// 👻 Ghost — make the snake semi-transparent; body collision is skipped while active.
    func showGhostEffect() {
        snakeHead.alpha = 0.45
        for seg in bodySegments { seg.alpha = 0.35 }
        spawnFloatingText("👻 Ghost!", at: CGPoint(x: snakeHead.position.x, y: snakeHead.position.y + 60))
    }

    func hideGhostEffect() {
        snakeHead.alpha = 1.0
        updateSegmentScales()   // restores correct alpha per segment
    }

    /// 🧲 Magnet activation — floating text feedback.
    func showMagnetActivation() {
        spawnFloatingText("🧲 Magnet!", at: CGPoint(x: snakeHead.position.x, y: snakeHead.position.y + 60))
    }

    // MARK: - Arc-Length Body Positioning
    /// Returns `count` positions spaced `spacing` pixels apart along the path
    /// stored in `history` (oldest-first), starting from `leadPos` (the head).
    func arcPositions(history: [CGPoint], leadPos: CGPoint,
                      count: Int, spacing: CGFloat) -> [CGPoint] {
        var result = [CGPoint]()
        result.reserveCapacity(count)
        var accumulated: CGFloat = 0
        var prev       = leadPos
        var targetDist = spacing

        for k in stride(from: history.count - 1, through: 0, by: -1) {
            guard result.count < count else { break }
            let p    = history[k]
            let d    = hypot(p.x - prev.x, p.y - prev.y)
            let next = accumulated + d

            while result.count < count && targetDist <= next {
                let t = d > 0 ? (targetDist - accumulated) / d : 0
                result.append(CGPoint(x: prev.x + (p.x - prev.x) * t,
                                      y: prev.y + (p.y - prev.y) * t))
                targetDist += spacing
            }
            accumulated = next
            prev = p
        }
        // Fill any remaining segments with the oldest known position
        let fallback = history.first ?? leadPos
        while result.count < count { result.append(fallback) }
        return result
    }

    // MARK: - AI / Smooth Rotation
    func findNearestFood(to position: CGPoint) -> SKLabelNode? {
        foodItems.min(by: {
            hypot($0.position.x - position.x, $0.position.y - position.y) <
            hypot($1.position.x - position.x, $1.position.y - position.y)
        })
    }

    func smoothlyRotate(current: inout CGFloat, target: CGFloat, dt: CGFloat) {
        var diff = target - current
        while diff >  .pi { diff -= 2 * .pi }
        while diff < -.pi { diff += 2 * .pi }
        let maxTurn = turnSpeed * .pi / 180.0 * dt
        if      diff >  maxTurn { current += maxTurn }
        else if diff < -maxTurn { current -= maxTurn }
        else                    { current  = target  }
    }

    // MARK: - Collision Detection
    func checkSelfCollision() -> Bool {
        GameLogic.headCollidesWithBody(
            head: snakeHead.position,
            segments: bodySegments.map(\.position),
            combinedRadius: collisionRadius + bodySegmentRadius,
            skip: spacingBetweenSegments * 2
        )
    }

    func checkBotVsBotCollisions() {
        for i in 0..<bots.count {
            guard bots[i].isActive, !bots[i].isDead, let headI = bots[i].head else { continue }
            for j in 0..<bots.count {
                guard j != i, bots[j].isActive, !bots[j].isDead else { continue }

                // Bot i head → bot j body
                let bodyPositions = bots[j].body.map(\.position)
                if !bodyPositions.isEmpty,
                   GameLogic.headCollidesWithBody(
                    head: headI.position,
                    segments: bodyPositions,
                    combinedRadius: collisionRadius + bodySegmentRadius,
                    skip: 0
                   ) {
                    respawnBot(i)
                    break
                }

                // Bot i head → bot j head (head-to-head: both die)
                guard let headJ = bots[j].head else { continue }
                let d = hypot(headI.position.x - headJ.position.x,
                              headI.position.y - headJ.position.y)
                if d < (headRadius + headRadius) {
                    respawnBot(i)
                    respawnBot(j)
                    break
                }
            }
        }
    }

    // MARK: - Touch Handling
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let loc = touch.location(in: self)

            if isPausedGame {
                if nodes(at: loc).contains(where: { $0.name == "resumeButton" }) {
                    togglePause()
                } else if nodes(at: loc).contains(where: { $0.name == "quitButton" }) {
                    stopBackgroundMusic()
                    if gameMode == .online { PhotonManager.shared.leaveRoom() }
                    pauseOverlay?.removeFromParent()
                    pauseOverlay = nil
                    onGameOver?(score)
                }
                continue
            }

            if isGameOver {
                let tappedNames = nodes(at: loc).compactMap { $0.name }
                if tappedNames.contains("restartButton") {
                    restartGame()
                } else if tappedNames.contains("playAgainButton") {
                    stopBackgroundMusic()
                    if gameMode == .online { PhotonManager.shared.leaveRoom() }
                    onGameOver?(score)
                }
                continue
            }

            if gameStarted && nodes(at: loc).contains(where: { $0.name == "pauseButton" }) {
                togglePause(); continue
            }

            guard gameStarted, !isPausedGame else { continue }

            let boostDist = hypot(loc.x - boostButtonCenter.x, loc.y - boostButtonCenter.y)
            if boostTouch == nil && boostDist < boostButtonRadius * 1.4 && boostEnergy >= boostMinEnergy {
                boostTouch  = touch
                isBoostHeld = true
                setBoostButtonActive(true)
                continue
            }

            let joystickDist = hypot(loc.x - joystickCenter.x, loc.y - joystickCenter.y)
            if joystickTouch == nil && joystickDist < joystickBaseRadius * 1.6 {
                joystickTouch = touch
                updateJoystick(at: loc)
                continue
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard gameStarted, !isPausedGame, !isGameOver else { return }
        for touch in touches {
            if touch === joystickTouch { updateJoystick(at: touch.location(in: self)) }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if touch === joystickTouch { resetJoystick() }
            if touch === boostTouch {
                boostTouch  = nil
                isBoostHeld = false
                setBoostButtonActive(false)
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if touch === joystickTouch { resetJoystick() }
            if touch === boostTouch {
                boostTouch  = nil
                isBoostHeld = false
                setBoostButtonActive(false)
            }
        }
    }

    // MARK: - Power-up Updates
    func updatePowerUps(dt: CGFloat) {
        var changed = false

        if invincibleTimeLeft > 0 { invincibleTimeLeft = max(0, invincibleTimeLeft - dt) }

        if speedBoostActive {
            speedBoostTimeLeft -= dt
            if speedBoostTimeLeft <= 0 {
                speedBoostActive = false; speedBoostTimeLeft = 0
                updateSpeedForScore()
            }
            changed = true
        }

        if multiplierActive {
            multiplierTimeLeft -= dt
            if multiplierTimeLeft <= 0 {
                multiplierActive = false; multiplierTimeLeft = 0; scoreMultiplier = 1
            }
            changed = true
        }

        if magnetActive {
            magnetTimeLeft -= dt
            if magnetTimeLeft <= 0 { magnetActive = false; magnetTimeLeft = 0 }
            changed = true
        }

        if ghostActive {
            ghostTimeLeft -= dt
            if ghostTimeLeft <= 0 {
                ghostActive = false; ghostTimeLeft = 0
                hideGhostEffect()
            }
            changed = true
        }

        if changed { refreshPowerUpPanel() }
    }

    // MARK: - Game Loop
    override func update(_ currentTime: TimeInterval) {
        guard !isGameOver, gameSetupComplete, gameStarted, !isPausedGame else { return }

        let dt: CGFloat = lastUpdateTime == 0
            ? CGFloat(1.0 / 60.0)
            : CGFloat(min(currentTime - lastUpdateTime, maxDeltaTime))
        lastUpdateTime = currentTime

        updatePowerUps(dt: dt)
        frameCounter += 1
        botBodyUpdateFrame = (botBodyUpdateFrame + 1) % 2

        // --- Boost Energy ---
        if isBoostHeld {
            boostEnergy = max(0, boostEnergy - boostDrainRate * dt)
            if boostEnergy <= 0 {
                isBoostHeld = false
                boostTouch  = nil
                setBoostButtonActive(false)
            }
        } else {
            boostEnergy = min(boostEnergyMax, boostEnergy + boostRegenRate * dt)
        }
        updateBoostEnergyArc()

        // --- Player Movement ---
        let playerDist = currentMoveSpeed * (isBoostHeld ? boostMultiplier : 1.0) * dt

        positionHistory.append(snakeHead.position)
        let maxH = Int(CGFloat(bodySegments.count + 5) * segmentPixelSpacing) + 200
        if positionHistory.count > maxH { positionHistory.removeFirst(positionHistory.count - maxH) }

        if isTouching { smoothlyRotate(current: &currentAngle, target: targetAngle, dt: dt) }

        snakeHead.position.x += cos(currentAngle) * playerDist
        snakeHead.position.y += sin(currentAngle) * playerDist
        snakeHead.zRotation   = (currentAngle * 180.0 / .pi - 90.0) * .pi / 180.0
        lastPlayerPosition    = snakeHead.position

        let segPos = arcPositions(history: positionHistory, leadPos: snakeHead.position,
                                  count: bodySegments.count, spacing: segmentPixelSpacing)

        // Shield wiggle: last 30% of body oscillates perpendicular to movement
        let totalSegs   = bodySegments.count
        let dangerCount = shieldActive ? max(1, Int(CGFloat(totalSegs) * 0.30)) : 0
        let dangerStart = totalSegs - dangerCount
        if shieldActive { tailWigglePhase += dt * 8.0 }
        for (i, seg) in bodySegments.enumerated() {
            var pos = segPos[i]
            let isWiggling = shieldActive && i >= dangerStart
            if isWiggling {
                // progress: 0.0 at the join, 1.0 at the tail tip
                let progress: CGFloat = dangerCount > 1
                    ? CGFloat(i - dangerStart) / CGFloat(dangerCount - 1)
                    : 1.0
                // Amplitude grows from ~0 at the join to 9 at the tip
                let amplitude: CGFloat = 9.0 * progress
                let phase = tailWigglePhase + CGFloat(i - dangerStart) * 0.8
                pos.x += -sin(currentAngle) * sin(phase) * amplitude
                pos.y +=  cos(currentAngle) * sin(phase) * amplitude
                // Size: progressively smaller toward the tip
                let t: CGFloat = totalSegs > 1 ? CGFloat(i) / CGFloat(totalSegs - 1) : 0
                let baseTaper: CGFloat = 1.0 - t * 0.22
                seg.setScale(baseTaper * (1.0 - progress * 0.45))
                // No strokeColor / glowWidth override — keep the body's own colour
            }
            seg.position = pos
        }

        // Shield tail kills bots on contact
        if shieldActive && dangerCount > 0 && frameCounter % 2 == 0 {
            let dangerPositions = (dangerStart..<totalSegs).map { bodySegments[$0].position }
            for bi in 0..<bots.count {
                guard bots[bi].isActive, !bots[bi].isDead, let botHead = bots[bi].head else { continue }
                if GameLogic.headCollidesWithBody(
                    head: botHead.position,
                    segments: dangerPositions,
                    combinedRadius: collisionRadius + bodySegmentRadius,
                    skip: 0
                ) {
                    respawnBot(bi)
                }
            }
        }

        // --- Collisions ---
        if checkWallCollision() { playerGameOver(); return }
        // Self-collision intentionally disabled: snake passes through its own body

        if gameMode == .offline && checkPlayerCollidesWithBotBodies()    { playerGameOver(); return }
        if gameMode == .offline && checkPlayerHeadVsBotHeads()           { playerGameOver(); return }
        if gameMode == .online  && checkPlayerCollidesWithRemotePlayers() { playerGameOver(); return }

        checkFoodCollisions()

        // --- Trail food spawning ---
        if gameStarted, let tailSeg = bodySegments.last {
            trailFoodTimer += dt
            if trailFoodTimer >= trailFoodInterval {
                spawnTrailFood(at: tailSeg.position)
                trailFoodTimer = 0
            }
        }

        // --- Purge orphaned trail food entries (node removed by SKAction, array still has entry) ---
        if frameCounter % 300 == 0 {
            var toRemove: [Int] = []
            for (i, item) in foodItems.enumerated() where item.parent == nil {
                toRemove.append(i)
            }
            for i in toRemove.reversed() {
                foodItems.remove(at: i)
                foodTypes.remove(at: i)
            }
        }

        // --- Camera & HUD ---
        updateCamera()
        updateHUDPositions()

        // --- Magnet power-up: pull food every other frame ---
        if magnetActive && frameCounter % 2 == 0 { applyMagnetEffect() }

        // --- Mode-specific ---
        if gameMode == .offline {
            let updateAI = frameCounter % 2 == 0  // bot AI at ~30 Hz
            updateBots(dt: dt, updateAI: updateAI)
            if frameCounter % 3 == 0 { checkBotVsBotCollisions() }        // bot-vs-bot at ~20 Hz
            if frameCounter % 3 == 0 { checkBotHeadsHitPlayerBody() }    // bot head → player body
        } else if gameMode == .online {
            if frameCounter % 4 == 0 {
                PhotonManager.shared.sendPlayerState(
                    headX: Float(snakeHead.position.x),
                    headY: Float(snakeHead.position.y),
                    angle: Float(currentAngle),
                    score: score,
                    bodyLength: bodySegments.count
                )
            }
        }

        // --- Minimap (every frame) ---
        updateMinimap()

        // --- Mini Leaderboard (update ~1 Hz) ---
        leaderboardUpdateTimer += dt
        if leaderboardUpdateTimer >= 1.0 {
            leaderboardUpdateTimer = 0
            updateMiniLeaderboard()
        }
    }
}

// MARK: - SKColor Helpers
extension SKColor {
    func darkened(by factor: CGFloat) -> SKColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return SKColor(red: max(0, r * (1 - factor)),
                       green: max(0, g * (1 - factor)),
                       blue:  max(0, b * (1 - factor)),
                       alpha: a)
    }
    func withAlphaComponent(_ alpha: CGFloat) -> SKColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return SKColor(red: r, green: g, blue: b, alpha: alpha)
    }
}

// MARK: - PhotonManager Delegate (Online Mode)
extension GameScene: PhotonManagerDelegate {
    func didJoinRoom() {}

    func didReceivePlayerState(_ state: RemotePlayerState, playerID: Int) {
        if remotePlayers[playerID] == nil {
            addRemotePlayer(actorID: playerID,
                            colorIndex: (selectedSnakeColorIndex + playerID) % snakeColorThemes.count,
                            headPos: CGPoint(x: CGFloat(state.headX), y: CGFloat(state.headY)),
                            playerName: state.playerName)
        } else {
            // Update the name label in case the player updated their name mid-game
            remotePlayers[playerID]?.nameLabel.text = state.playerName
            remotePlayers[playerID]?.playerName     = state.playerName
        }
        updateRemotePlayerPosition(actorID: playerID, headX: state.headX, headY: state.headY,
                                   angle: state.angle, score: Int32(state.score), bodyLength: Int32(state.bodyLength))
    }

    func didReceiveFoodEaten(foodIndex: Int, newFoodX: Float, newFoodY: Float, newFoodType: Int) {
        guard foodIndex < foodItems.count else { return }
        foodItems[foodIndex].removeFromParent()
        foodItems.remove(at: foodIndex)
        foodTypes.remove(at: foodIndex)
        let food = SKLabelNode(text: fruitEmojis.randomElement())
        food.fontSize = 28
        food.verticalAlignmentMode   = .center
        food.horizontalAlignmentMode = .center
        food.position = CGPoint(x: CGFloat(newFoodX), y: CGFloat(newFoodY))
        addChild(food)
        foodItems.append(food)
        foodTypes.append(.regular)
    }

    func didPlayerLeave(playerID: Int) {
        removeRemotePlayer(actorID: playerID)
        // Game is continuous — alive player keeps playing; just show a brief notification
        if !isGameOver {
            spawnFloatingText("Opponent left 👋", at: CGPoint(x: snakeHead.position.x, y: snakeHead.position.y + 80))
        }
    }

    func didReceiveOpponentDied(playerID: Int) {
        removeRemotePlayer(actorID: playerID)
    }
}
