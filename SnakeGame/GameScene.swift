import SpriteKit
import AVFoundation
import UIKit

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
    var shieldCharges: Int
    var multiplierTimeLeft: CGFloat
    var magnetTimeLeft: CGFloat
    var ghostTimeLeft: CGFloat
    var isNemesis: Bool

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
        self.shieldCharges = 0
        self.multiplierTimeLeft = 0
        self.magnetTimeLeft = 0
        self.ghostTimeLeft = 0
        self.isNemesis = false
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

// MARK: - Remote Player (Online Mode)
struct RemotePlayer {
    var head: SKShapeNode
    var body: [SKShapeNode]
    var posHistory: PointRingBuffer
    var bodyPositionCache: [CGPoint]
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
    private var hasShutdown = false

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
    let cameraZoomStepScore: CGFloat = 300.0
    let cameraZoomPerStep:   CGFloat = 0.10
    let maxCameraScale:      CGFloat = 1.50

    // MARK: - Constants
    let baseMoveSpeed:           CGFloat = 100.0
    let maxMoveSpeed:            CGFloat = 130.0
    let turnSpeed:               CGFloat = 280.0
    let playerTurnSpeedBase:     CGFloat = 340.0
    let playerTurnSpeedBoost:    CGFloat = 170.0
    let wallAvoidanceDistance:   CGFloat = 80.0
    let playerAvoidanceDistance: CGFloat = 100.0
    let headRadius:              CGFloat = 13.0
    let bodySegmentRadius:       CGFloat = 10.0
    let collisionRadius:         CGFloat = 12.0
    let foodRadius:              CGFloat = 12.0
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
    var positionHistory = PointRingBuffer()
    var bodyPositionCache: [CGPoint] = []
    var currentAngle: CGFloat = 0
    var targetAngle:  CGFloat = 0
    var isTouching:   Bool    = false

    // MARK: - Joystick
    let joystickBaseRadius:  CGFloat = 65
    let joystickThumbRadius: CGFloat = 28
    let joystickDeadZone:    CGFloat = 10
    var joystickCenter:      CGPoint = .zero
    var joystickThumbOffset: CGPoint = .zero
    var joystickEngagement:  CGFloat = 0
    var joystickBaseNode:    SKShapeNode?
    var joystickInnerRing:   SKShapeNode?
    var joystickThumbNode:   SKShapeNode?
    var joystickTouch: UITouch?

    // MARK: - Boost Button
    let boostButtonRadius: CGFloat = 36
    var boostButtonCenter: CGPoint = .zero
    var boostButtonNode:   SKNode?
    var boostTouch:        UITouch?
    // Boost score drain — replaces energy bar; costs 1 score point per 200ms
    var boostScoreDrainTimer: CGFloat = 0

    // MARK: - Food
    let fruitEmojis: [String] = ["🍎","🍊","🍋","🍇","🍓","🍉","🍑","🍌","🫐","🍒"]
    var foodItems: [SKNode] = []
    var foodTypes: [FoodType]   = []
    // Cluster-bonus cache: avoids O(n²) recomputation every bot-AI tick.
    // Rebuilt lazily whenever food is added or removed (clusterBonusDirty = true).
    var cachedClusterBonuses: [CGFloat] = []
    var clusterBonusDirty: Bool = true
    // Trail food
    var trailFoodTimer: CGFloat = 0
    var activeTrailFoodCount: Int = 0         // O(1) counter; avoids O(n) filter on trail cap check
    let playerTrailInterval: CGFloat = 0.35   // player spawns trail food every 0.35s
    let botTrailInterval:    CGFloat = 0.60   // bots spawn trail food every 0.60s
    let maxTrailFoodItems:   Int     = 150    // hard cap on active .trail nodes
    // Trail food: makeTrailFoodNode — scaled body segment matching player skin + pattern
    // Death food: makeDeathHeadNode (head) + makeDeathFoodNode (body segments) matching dead snake skin

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
    var minimapUpdateTimer: CGFloat = 0
    var leaderArrowUpdateTimer: CGFloat = 0
    var miniLeaderboardNeedsRefresh = true

    // MARK: - Game State
    var gameOverOverlay:    SKNode? = nil
    var gameSetupComplete:  Bool    = false
    var gameStarted:        Bool    = false
    var onlineRoundPrimed:  Bool    = false
    var isPausedGame:       Bool    = false
    var lastPlayerPosition: CGPoint = .zero

    // MARK: - Power-ups
    var shieldActive:        Bool    = false
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
    /// Target body segment count derived directly from score.
    /// initialBodyCount + 1 segment per 10 score points.
    var targetBodyCount: Int { max(initialBodyCount, initialBodyCount + score / 10) }

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
    var leaderArrowNode:          SKNode?
    var leaderArrowLabel:         SKLabelNode?

    // MARK: - Shield Wiggle
    var tailWigglePhase: CGFloat = 0

    // MARK: - Bots (Offline mode)
    var bots: [BotState] = []
    let totalBots = 30
    let challengeNemesisScore = 1000
    let expertNemesisInitialDelay: CGFloat = 60.0
    let expertNemesisRespawnDelay: CGFloat = 120.0
    var localBotTargetCount: Int { gameMode == .challenge ? totalBots + 1 : totalBots }
    // Per-tier base speeds (replaces single botMoveSpeed)
    let botSpeedEasy:   CGFloat = 95.0
    let botSpeedMedium: CGFloat = 120.0
    let botSpeedHard:   CGFloat = 150.0
    let botSpeedScoreCap: Int = 100
    let botBoostMultiplier: CGFloat = 1.52
    let botBoostDurationRange: ClosedRange<CGFloat> = 0.30...0.90
    let botBoostCooldownRange: ClosedRange<CGFloat> = 1.10...2.40
    let botDetailedAIRadius: CGFloat = 1200.0
    let botCollisionBroadPhaseRadius: CGFloat = 260.0
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

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        shutdown()
    }

    deinit {
        shutdown()
    }

    func shutdown() {
        guard !hasShutdown else { return }
        hasShutdown = true

        removeAllActions()
        joystickTouch = nil
        boostTouch = nil
        isBoostHeld = false
        stopBackgroundMusic()

        if PhotonManager.shared.delegate === self {
            PhotonManager.shared.delegate = nil
        }
        if gameMode == .online {
            PhotonManager.shared.leaveRoom()
        }
    }

    private var isLandscapeLayout: Bool { size.width > size.height }

    private func cameraScale() -> CGFloat {
        max(cameraNode.xScale, 1.0)
    }

    private func cameraHalfExtents(using scale: CGFloat? = nil) -> (halfW: CGFloat, halfH: CGFloat) {
        let zoom = scale ?? cameraScale()
        return (size.width * zoom / 2, size.height * zoom / 2)
    }

    private func hudControlScale() -> CGFloat {
        cameraScale()
    }

    private func joystickMargins() -> CGPoint {
        isLandscapeLayout ? CGPoint(x: 74, y: 132) : CGPoint(x: 90, y: 100)
    }

    private func boostMargins() -> CGPoint {
        isLandscapeLayout ? CGPoint(x: 94, y: 118) : CGPoint(x: 88, y: 100)
    }

    private func minimapMargins() -> CGPoint {
        isLandscapeLayout ? CGPoint(x: 106, y: 78) : CGPoint(x: 88, y: 68)
    }

    private func leaderArrowMarginTop() -> CGFloat {
        isLandscapeLayout ? 68 : 74
    }

    private func desiredCameraScale() -> CGFloat {
        let zoomSteps = floor(CGFloat(score) / cameraZoomStepScore)
        return min(1.0 + zoomSteps * cameraZoomPerStep, maxCameraScale)
    }

    func setupNewGame() {
        if !AppFeatureFlags.isOnlineModeEnabled, gameMode == .online {
            gameMode = .offline
        }
        selectedSnakeColorIndex = normalizedSnakeColorIndex(selectedSnakeColorIndex)
        hasShutdown         = false
        isGameOver          = false
        isTouching          = false
        currentAngle        = 0
        targetAngle         = 0
        score               = 0
        lastUpdateTime      = 0
        gameSetupComplete   = false
        gameStarted         = false
        onlineRoundPrimed   = false
        isPausedGame        = false
        scoreMultiplier     = 1
        shieldActive        = false
        multiplierActive    = false
        multiplierTimeLeft  = 0
        invincibleTimeLeft  = 0
        magnetActive        = false
        magnetTimeLeft      = 0
        ghostActive         = false
        ghostTimeLeft       = 0
        currentMoveSpeed    = baseMoveSpeed
        isBoostHeld         = false
        boostScoreDrainTimer = 0
        joystickTouch       = nil
        boostTouch          = nil
        joystickThumbOffset = .zero
        joystickEngagement  = 0
        frameCounter        = 0
        leaderboardUpdateTimer = 0
        minimapUpdateTimer     = 0
        leaderArrowUpdateTimer = 0
        miniLeaderboardNeedsRefresh = true
        trailFoodTimer       = 0
        activeTrailFoodCount = 0
        tailWigglePhase      = 0

        removeAllChildren()
        bodySegments.removeAll()
        bodyPositionCache.removeAll()
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
        leaderArrowNode   = nil
        leaderArrowLabel  = nil

        backgroundColor = gameMode == .challenge
            ? SKColor(red: 0.11, green: 0.03, blue: 0.03, alpha: 1.0)
            : SKColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 1.0)
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
        let extents = cameraHalfExtents(using: 1.0)
        let joystickInset = joystickMargins()
        let boostInset = boostMargins()
        joystickCenter    = CGPoint(x: cx - extents.halfW + joystickInset.x, y: cy - extents.halfH + joystickInset.y)
        boostButtonCenter = CGPoint(x: cx + extents.halfW - boostInset.x,   y: cy - extents.halfH + boostInset.y)

        createArenaBorder()
        createSnakeHead()
        createInitialBody()
        createScorePanel()
        createMiniLeaderboard()
        createMinimap()
        createLeaderArrow()
        if gameMode != .online { createPauseButton() }
        createJoystick()
        createBoostButton()
        if gameMode == .online {
            prepareOnlineFoodSlots()
        } else {
            spawnInitialFood()
        }
        updateScoreDisplay()

        if gameMode == .online {
            PhotonManager.shared.delegate = self
        } else {
            spawnBots()
        }

        gameSetupComplete = true
        if gameMode == .online {
            primeOnlineRoundIfReady()
        } else {
            startGameImmediately()
        }

        let playerTheme = snakeColorThemes[selectedSnakeColorIndex % snakeColorThemes.count]
        animateSnakeEntrance(head: snakeHead, body: bodySegments, angle: currentAngle, accent: playerTheme.bodySKColor)
    }

    // MARK: - Arena Border
    func createArenaBorder() {
        // Arena background fill
        let arenaBg = SKShapeNode(rect: CGRect(x: 0, y: 0, width: worldSize, height: worldSize))
        let isChallengeMode = gameMode == .challenge
        arenaBg.fillColor   = isChallengeMode
            ? SKColor(red: 0.22, green: 0.06, blue: 0.07, alpha: 1.0)
            : SKColor(red: 0.21, green: 0.29, blue: 0.36, alpha: 1.0)
        arenaBg.strokeColor = .clear
        arenaBg.zPosition   = -11
        addChild(arenaBg)

        let laneWidth: CGFloat = 260
        for bandIndex in -2...18 {
            let x = CGFloat(bandIndex) * laneWidth - 180
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x + laneWidth * 0.90, y: 0))
            path.addLine(to: CGPoint(x: x + laneWidth * 1.65, y: worldSize))
            path.addLine(to: CGPoint(x: x + laneWidth * 0.75, y: worldSize))
            path.closeSubpath()

            let band = SKShapeNode(path: path)
            band.fillColor = bandIndex.isMultiple(of: 2)
                ? (isChallengeMode ? SKColor(red: 0.52, green: 0.14, blue: 0.12, alpha: 0.24) : SKColor(red: 0.28, green: 0.37, blue: 0.43, alpha: 0.18))
                : (isChallengeMode ? SKColor(red: 0.16, green: 0.04, blue: 0.04, alpha: 0.22) : SKColor(red: 0.12, green: 0.19, blue: 0.25, alpha: 0.16))
            band.strokeColor = .clear
            band.zPosition = -10.8
            addChild(band)
        }

        let glowCenters: [CGPoint] = [
            CGPoint(x: worldSize * 0.22, y: worldSize * 0.24),
            CGPoint(x: worldSize * 0.78, y: worldSize * 0.30),
            CGPoint(x: worldSize * 0.36, y: worldSize * 0.74),
            CGPoint(x: worldSize * 0.74, y: worldSize * 0.82)
        ]
        for (index, center) in glowCenters.enumerated() {
            let glow = SKShapeNode(circleOfRadius: index.isMultiple(of: 2) ? 300 : 240)
            glow.position = center
            glow.fillColor = index.isMultiple(of: 2)
                ? (isChallengeMode ? SKColor(red: 0.95, green: 0.32, blue: 0.22, alpha: 0.12) : SKColor(red: 0.60, green: 0.78, blue: 0.82, alpha: 0.07))
                : (isChallengeMode ? SKColor(red: 0.38, green: 0.09, blue: 0.10, alpha: 0.16) : SKColor(red: 0.15, green: 0.23, blue: 0.31, alpha: 0.10))
            glow.strokeColor = .clear
            glow.zPosition = -10.7
            addChild(glow)
        }

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

        let isChallengeMode = gameMode == .challenge

        let grid = SKShapeNode(path: path)
        grid.strokeColor = isChallengeMode
            ? SKColor(red: 0.96, green: 0.50, blue: 0.42, alpha: 0.11)
            : SKColor(red: 0.80, green: 0.92, blue: 1.0, alpha: 0.10)
        grid.lineWidth   = 1
        grid.fillColor   = .clear
        grid.zPosition   = -10
        addChild(grid)

        let accentPath = CGMutablePath()
        let accentStep: CGFloat = step * 3
        var ax: CGFloat = accentStep
        while ax < worldSize {
            accentPath.move(to: CGPoint(x: ax, y: 0))
            accentPath.addLine(to: CGPoint(x: ax, y: worldSize))
            ax += accentStep
        }

        var ay: CGFloat = accentStep
        while ay < worldSize {
            accentPath.move(to: CGPoint(x: 0, y: ay))
            accentPath.addLine(to: CGPoint(x: worldSize, y: ay))
            ay += accentStep
        }

        let accentGrid = SKShapeNode(path: accentPath)
        accentGrid.strokeColor = isChallengeMode
            ? SKColor(red: 0.35, green: 0.08, blue: 0.07, alpha: 0.30)
            : SKColor(red: 0.10, green: 0.18, blue: 0.24, alpha: 0.22)
        accentGrid.lineWidth = 2
        accentGrid.fillColor = .clear
        accentGrid.zPosition = -9.95
        addChild(accentGrid)

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
        dots.fillColor   = SKColor(red: 0.94, green: 0.98, blue: 1.0, alpha: 0.14)
        dots.strokeColor = .clear
        dots.zPosition   = -10
        addChild(dots)
    }

    // MARK: - Countdown
    func primeOnlineRoundIfReady() {
        guard gameMode == .online, gameSetupComplete, !onlineRoundPrimed else { return }
        guard PhotonManager.shared.connectionState == .inRoom else { return }
        onlineRoundPrimed = true
        PhotonManager.shared.sendGameReady()
        startCountdown()
    }

    func startGameImmediately() {
        gameStarted   = true
        ghostActive   = true
        ghostTimeLeft = 4.0
        showGhostEffect()
    }

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
                self.startGameImmediately()
            }
        }}}
    }

    // MARK: - Camera Follow
    func updateCamera() {
        let desiredScale = desiredCameraScale()
        let newScale = cameraNode.xScale + (desiredScale - cameraNode.xScale) * 0.08
        cameraNode.setScale(newScale)

        let extents = cameraHalfExtents(using: newScale)
        let halfW = extents.halfW
        let halfH = extents.halfH
        let clampedX = max(halfW, min(worldSize - halfW, snakeHead.position.x))
        let clampedY = max(halfH, min(worldSize - halfH, snakeHead.position.y))
        cameraNode.position = CGPoint(x: clampedX, y: clampedY)
    }

    // MARK: - HUD Positions (world-space, updated every frame)
    func updateHUDPositions() {
        let cx = cameraNode.position.x
        let cy = cameraNode.position.y
        let extents = cameraHalfExtents()
        let controlScale = hudControlScale()
        let joystickInset = joystickMargins()
        let boostInset = boostMargins()
        let minimapInset = minimapMargins()

        joystickCenter    = CGPoint(x: cx - extents.halfW + joystickInset.x, y: cy - extents.halfH + joystickInset.y)
        boostButtonCenter = CGPoint(x: cx + extents.halfW - boostInset.x,    y: cy - extents.halfH + boostInset.y)

        joystickBaseNode?.position  = joystickCenter
        joystickBaseNode?.setScale(controlScale)
        joystickInnerRing?.position = joystickCenter
        joystickInnerRing?.setScale(controlScale)
        joystickThumbNode?.setScale(controlScale)
        if joystickTouch == nil {
            joystickThumbNode?.position = joystickCenter
        } else {
            joystickThumbNode?.position = CGPoint(
                x: joystickCenter.x + joystickThumbOffset.x * controlScale,
                y: joystickCenter.y + joystickThumbOffset.y * controlScale
            )
        }
        boostButtonNode?.position = boostButtonCenter
        boostButtonNode?.setScale(controlScale * (isBoostHeld ? 1.15 : 1.0))

        let panelH = scorePanelHeight
        scorePanel?.position  = CGPoint(x: cx - extents.halfW + 20, y: cy + extents.halfH - 60 - panelH)
        pauseButton?.position = CGPoint(x: cx + extents.halfW - 42, y: cy + extents.halfH - 42)
        powerUpPanel?.position = CGPoint(x: cx, y: cy - extents.halfH + 170)
        minimapNode?.position = CGPoint(x: cx + extents.halfW - minimapInset.x, y: cy + extents.halfH - minimapInset.y)
        miniLeaderboard?.position = CGPoint(x: cx + extents.halfW - minimapInset.x + 56, y: cy + extents.halfH - minimapInset.y - 140)
        leaderArrowNode?.position = CGPoint(x: cx, y: cy + extents.halfH - leaderArrowMarginTop())
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
        base.fillColor   = SKColor(red: 0.15, green: 0.30, blue: 0.20, alpha: 0.18)
        base.strokeColor = SKColor(red: 0.3, green: 0.85, blue: 0.45, alpha: 0.35)
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
        thumb.fillColor   = SKColor(red: 0.25, green: 0.80, blue: 0.40, alpha: 0.38)
        thumb.strokeColor = SKColor(red: 0.4, green: 0.95, blue: 0.55, alpha: 0.75)
        thumb.lineWidth   = 2
        thumb.glowWidth   = 6
        thumb.position    = joystickCenter
        thumb.zPosition   = 501
        addChild(thumb)
        joystickThumbNode = thumb
    }

    func updateJoystick(at location: CGPoint) {
        let controlScale = hudControlScale()
        let dx    = (location.x - joystickCenter.x) / controlScale
        let dy    = (location.y - joystickCenter.y) / controlScale
        let dist  = hypot(dx, dy)
        let angle = atan2(dy, dx)
        let normalized = max(0, min(1, (dist - joystickDeadZone) / (joystickBaseRadius - joystickDeadZone)))
        let engagement = normalized > 0 ? pow(normalized, 0.82) : 0
        let thumbDistance = normalized > 0
            ? joystickDeadZone + engagement * (joystickBaseRadius - joystickDeadZone)
            : 0

        joystickEngagement = engagement
        joystickThumbOffset = CGPoint(x: cos(angle) * thumbDistance, y: sin(angle) * thumbDistance)
        joystickThumbNode?.position = CGPoint(
            x: joystickCenter.x + joystickThumbOffset.x * controlScale,
            y: joystickCenter.y + joystickThumbOffset.y * controlScale
        )

        if normalized > 0 {
            targetAngle = angle
            isTouching  = true
        } else {
            isTouching = false
        }
    }

    func resetJoystick() {
        joystickThumbOffset = .zero
        joystickEngagement  = 0
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

        addChild(btn)
        boostButtonNode = btn
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
        btn.run(SKAction.scale(to: hudControlScale() * (active ? 1.15 : 1.0), duration: 0.09))
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
        spawnDeathFood(at: bodySegments.map(\.position),
                       colorIndex: selectedSnakeColorIndex,
                       patternIndex: selectedSnakePatternIndex)   // body scatters as death food
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
        bg.fillColor   = SKColor(red: 0.03, green: 0.05, blue: 0.12, alpha: 0.88)
        bg.strokeColor = .clear
        bg.position    = CGPoint(x: cx, y: cy)
        overlay.addChild(bg)

        // Card background for game-over content
        let card = SKShapeNode(rectOf: CGSize(width: 280, height: 260), cornerRadius: 22)
        card.fillColor   = SKColor(red: 0.08, green: 0.10, blue: 0.18, alpha: 0.95)
        card.strokeColor = SKColor(red: 0.3, green: 0.85, blue: 0.4, alpha: 0.30)
        card.lineWidth   = 1.5
        card.position    = CGPoint(x: cx, y: cy - 10)
        overlay.addChild(card)

        let titleLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        titleLabel.text                    = title
        titleLabel.fontSize                = 42
        titleLabel.fontColor               = .white
        titleLabel.horizontalAlignmentMode = .center
        titleLabel.verticalAlignmentMode   = .center
        titleLabel.position                = CGPoint(x: cx, y: cy + 100)
        overlay.addChild(titleLabel)

        let finalScore = SKLabelNode(fontNamed: "Arial-BoldMT")
        finalScore.text                    = "\(playerName.isEmpty ? "You" : playerName): \(score)"
        finalScore.fontSize                = 28
        finalScore.fontColor               = SKColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0)
        finalScore.horizontalAlignmentMode = .center
        finalScore.verticalAlignmentMode   = .center
        finalScore.position                = CGPoint(x: cx, y: cy + 35)
        overlay.addChild(finalScore)

        // Play Again / Rejoin button (primary action)
        let restartLabel = gameMode == .online ? "Rejoin" : "Play Again"
        let restartBtnY  = cy - 45
        let restartBg = SKShapeNode(rectOf: CGSize(width: 220, height: 54), cornerRadius: 14)
        restartBg.fillColor   = SKColor(red: 0.20, green: 0.78, blue: 0.32, alpha: 1.0)
        restartBg.strokeColor = SKColor(white: 1.0, alpha: 0.20)
        restartBg.lineWidth   = 1
        restartBg.glowWidth   = 6
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
        let menuBtnY  = cy - 115
        let btnBg = SKShapeNode(rectOf: CGSize(width: 220, height: 54), cornerRadius: 14)
        btnBg.fillColor   = SKColor(red: 0.12, green: 0.14, blue: 0.22, alpha: 0.95)
        btnBg.strokeColor = SKColor(white: 1.0, alpha: 0.20)
        btnBg.lineWidth   = 1
        btnBg.position    = CGPoint(x: cx, y: menuBtnY)
        btnBg.name        = "playAgainButton"
        overlay.addChild(btnBg)

        let btnLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        btnLabel.text                    = "Main Menu"
        btnLabel.fontSize                = 20
        btnLabel.fontColor               = SKColor(white: 0.90, alpha: 1.0)
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
        if gameMode == .online {
            PhotonManager.shared.prepareLocalPlayerForNewRound()
        }
        setupNewGame()
        startBackgroundMusic()
    }

    // MARK: - Score Panel
    func createScorePanel() {
        scoreLabel = SKLabelNode(fontNamed: "Arial-BoldMT")
        scoreLabel.text                    = "0"
        scoreLabel.fontSize                = 20
        scoreLabel.fontColor               = .white
        scoreLabel.horizontalAlignmentMode = .center
        scoreLabel.verticalAlignmentMode   = .center

        let hPad: CGFloat = 16, vPad: CGFloat = 10
        let panelW = max(scoreLabel.frame.width + hPad * 2, 72)
        let panelH = scoreLabel.frame.height + vPad * 2
        scorePanelHeight = panelH

        scorePanel = SKShapeNode(rect: CGRect(x: 0, y: 0, width: panelW, height: panelH), cornerRadius: 12)
        scorePanel.fillColor   = SKColor(red: 0.05, green: 0.08, blue: 0.15, alpha: 0.85)
        scorePanel.strokeColor = SKColor(red: 0.3, green: 0.85, blue: 0.4, alpha: 0.45)
        scorePanel.lineWidth   = 1.0
        scorePanel.zPosition   = 500

        let cx = worldSize / 2, cy = worldSize / 2
        scorePanel.position = CGPoint(x: cx - size.width/2 + 20, y: cy + size.height/2 - 60 - panelH)

        scoreLabel.position = CGPoint(x: panelW / 2, y: panelH / 2)
        scorePanel.addChild(scoreLabel)
        addChild(scorePanel)
    }

    func updateScoreDisplay() {
        guard scoreLabel != nil, scorePanel != nil else { return }
        scoreLabel.text = "\(score)"
        let hPad: CGFloat = 16, vPad: CGFloat = 10
        let panelW = max(scoreLabel.frame.width + hPad * 2, 72)
        let panelH = scoreLabel.frame.height + vPad * 2
        scorePanelHeight = panelH
        scorePanel.path = CGPath(
            roundedRect: CGRect(x: 0, y: 0, width: panelW, height: panelH),
            cornerWidth: 12, cornerHeight: 12, transform: nil
        )
        scoreLabel.position = CGPoint(x: panelW / 2, y: panelH / 2)
        miniLeaderboardNeedsRefresh = true
    }

    private func historyCapacity(forSegmentCount count: Int) -> Int {
        max(64, Int(CGFloat(max(count, 1) + 5) * segmentPixelSpacing) + 200)
    }

    private func ensurePointCacheLength(_ count: Int, cache: inout [CGPoint]) {
        if cache.count == count { return }
        if cache.count < count {
            cache.append(contentsOf: repeatElement(.zero, count: count - cache.count))
        } else {
            cache.removeLast(cache.count - count)
        }
    }

    private func cacheBodyPositions(from nodes: [SKShapeNode], into cache: inout [CGPoint]) {
        ensurePointCacheLength(nodes.count, cache: &cache)
        guard !nodes.isEmpty else { return }
        for index in nodes.indices {
            cache[index] = nodes[index].position
        }
    }

    private func interactionRadiusForPlayerBody() -> CGFloat {
        CGFloat(max(1, bodySegments.count)) * segmentPixelSpacing + 140
    }

    private func botPairWithinBroadPhase(_ lhs: BotState, _ rhs: BotState) -> Bool {
        let dx = lhs.position.x - rhs.position.x
        let dy = lhs.position.y - rhs.position.y
        let radius = botCollisionBroadPhaseRadius + CGFloat(max(lhs.bodyLength, rhs.bodyLength)) * 0.6
        return dx * dx + dy * dy <= radius * radius
    }

    private func headCollidesWithPoints(_ head: CGPoint, points: [CGPoint], combinedRadius: CGFloat, skip: Int = 0) -> Bool {
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

    private func headCollidesWithPoints(_ head: CGPoint, points: [CGPoint], startIndex: Int, combinedRadius: CGFloat) -> Bool {
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
        let cx = worldSize / 2, cy = worldSize / 2
        node.position = CGPoint(x: cx + size.width/2 - 10, y: cy + size.height/2 - 90)
        addChild(node)
        miniLeaderboard = node
    }

    func updateMiniLeaderboard() {
        guard let lb = miniLeaderboard else { return }
        lb.removeAllChildren()
        miniLeaderboardNeedsRefresh = false

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

        let myName = playerName.isEmpty ? "You" : playerName
        var best: (name: String, score: Int, position: CGPoint, isPlayer: Bool) = (
            name: myName,
            score: score,
            position: snakeHead.position,
            isPlayer: true
        )

        for bot in bots where !bot.isDead {
            if bot.score > best.score {
                best = (name: bot.name, score: bot.score, position: bot.position, isPlayer: false)
            }
        }

        for (_, remote) in remotePlayers {
            if remote.score > best.score {
                best = (
                    name: remote.playerName.isEmpty ? "Player" : remote.playerName,
                    score: remote.score,
                    position: remote.head.position,
                    isPlayer: false
                )
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

    // MARK: - Food System
    func spawnInitialFood() {
        for _ in 0..<foodCount { spawnFood() }
    }

    func prepareOnlineFoodSlots() {
        guard gameMode == .online else { return }
        if foodItems.count == foodCount, foodTypes.count == foodCount { return }

        foodItems = (0..<foodCount).map { _ in SKNode() }
        foodTypes = Array(repeating: .regular, count: foodCount)
    }

    func randomSpawnFoodType() -> FoodType {
        let roll = Int.random(in: 0...99)
        let candidate: FoodType
        switch roll {
        case 0...89:  candidate = .regular
        case 90...91: candidate = .shield
        case 92...93: candidate = .multiplier
        case 94...95: candidate = .magnet
        case 96...97: candidate = .ghost
        default:      candidate = .shrink
        }

        if candidate == .shield && foodTypes.filter({ $0 == .shield }).count >= 2 {
            return .regular
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
        food.fontSize                = 17
        food.verticalAlignmentMode   = .center
        food.horizontalAlignmentMode = .center
        return food
    }

    func spawnFood() {
        let type = randomSpawnFoodType()
        let food = makeFoodNode(for: type)

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
        clusterBonusDirty = true
    }

    func randomPositionInArena() -> CGPoint {
        let minX = arenaMinX + foodPadding, maxX = arenaMaxX - foodPadding
        let minY = arenaMinY + foodPadding, maxY = arenaMaxY - foodPadding
        guard minX < maxX, minY < maxY else { return CGPoint(x: worldSize/2, y: worldSize/2) }
        return CGPoint(x: CGFloat.random(in: minX...maxX), y: CGFloat.random(in: minY...maxY))
    }

    // MARK: - Skin-Matched Food Node Builders

    /// Tiny body-segment circle matching the player/bot skin color and pattern.
    /// Scale 0.5 → effective radius 5px (smaller than regular food).
    func makeTrailFoodNode(colorIndex: Int, patternIndex: Int) -> SKShapeNode {
        let idx     = colorIndex % snakeColorThemes.count
        let theme   = snakeColorThemes[idx]
        let pattern = SnakePattern(rawValue: patternIndex) ?? .solid
        let node    = makeBodySegment(color: theme.bodySKColor,
                                      stroke: theme.bodyStrokeSKColor,
                                      pattern: pattern, segIndex: 0)
        node.setScale(0.5)
        return node
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
                    self.foodItems.remove(at: idx)
                    self.foodTypes.remove(at: idx)
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
            food.run(deathPopAnimation)
        }
    }

    func isPositionOnPlayerSnake(_ p: CGPoint) -> Bool {
        if hypot(p.x - snakeHead.position.x, p.y - snakeHead.position.y) < safeSpawnDistance { return true }
        for seg in bodySegments where hypot(p.x - seg.position.x, p.y - seg.position.y) < safeSpawnDistance { return true }
        return false
    }

    func applyOnlineFoodUpdate(foodIndex: Int, newFoodX: Float, newFoodY: Float, newFoodType: Int) {
        prepareOnlineFoodSlots()
        guard foodIndex >= 0, foodIndex < foodItems.count else { return }

        let oldType = foodTypes[foodIndex]
        if oldType == .trail {
            activeTrailFoodCount = max(0, activeTrailFoodCount - 1)
        }

        foodItems[foodIndex].removeFromParent()

        let type = FoodType(rawValue: newFoodType) ?? .regular
        let node = makeFoodNode(for: type)
        node.position = CGPoint(x: CGFloat(newFoodX), y: CGFloat(newFoodY))
        addChild(node)
        foodItems[foodIndex] = node
        foodTypes[foodIndex] = type
    }

    func checkFoodCollisions() {
        let thresholdSq: CGFloat = (headRadius + foodRadius) * (headRadius + foodRadius)
        for (i, food) in foodItems.enumerated().reversed() {
            guard food.parent != nil else { continue }
            let dx = snakeHead.position.x - food.position.x
            let dy = snakeHead.position.y - food.position.y
            if dx * dx + dy * dy < thresholdSq {
                eatFood(at: i)
                return
            }
        }
    }

    func eatFood(at index: Int) {
        let foodPos = foodItems[index].position
        let type    = foodTypes[index]

        if gameMode == .online {
            let newPos = randomPositionInArena()
            let newType = randomSpawnFoodType()
            applyOnlineFoodUpdate(
                foodIndex: index,
                newFoodX: Float(newPos.x),
                newFoodY: Float(newPos.y),
                newFoodType: newType.rawValue
            )
            PhotonManager.shared.sendFoodEaten(foodIndex: index,
                                               newFoodX: Float(newPos.x),
                                               newFoodY: Float(newPos.y),
                                               newFoodType: newType.rawValue)
        } else {
            if type == .trail { activeTrailFoodCount = max(0, activeTrailFoodCount - 1) }
            foodItems[index].removeFromParent()
            foodItems.remove(at: index)
            foodTypes.remove(at: index)
            clusterBonusDirty = true
            spawnFood()
        }
        // Body length is now derived from score via syncSnakeLength() — no direct addBodySegment() call here.

        // Apply power-up effects
        switch type {
        case .regular, .trail, .death: break
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

        // Per-type point values — power-ups are pure utility (0 pts)
        let pts: Int
        switch type {
        case .regular:                           pts = 2
        case .trail:                             pts = 1
        case .death:                             pts = 5
        case .shield, .multiplier,
             .magnet, .ghost, .shrink:           pts = 0
        }
        score += pts * scoreMultiplier
        updateScoreDisplay()
        updateSpeedForScore()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        run(eatFoodAction)
        if pts > 0 { spawnFloatingText("+\(pts * scoreMultiplier)", at: foodPos) }
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
        let theme    = snakeColorThemes[normalizedSnakeColorIndex(selectedSnakeColorIndex)]
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
        let historyNeeded = historyCapacity(forSegmentCount: initialBodyCount)
        positionHistory.setCapacity(historyNeeded)
        positionHistory.removeAll()
        for k in 0..<historyNeeded {
            positionHistory.append(CGPoint(x: spawnPos.x - CGFloat(k) * 0.5, y: spawnPos.y))
        }
        for i in 1...initialBodyCount {
            let seg = makePlayerBodySegment(segIndex: i - 1)
            seg.position = CGPoint(x: spawnPos.x - CGFloat(i) * segmentPixelSpacing, y: spawnPos.y)
            addChild(seg)
            bodySegments.append(seg)
        }
        cacheBodyPositions(from: bodySegments, into: &bodyPositionCache)
        updateSegmentScales()
    }

    func addBodySegment() {
        let seg = makePlayerBodySegment(segIndex: bodySegments.count)
        seg.position = bodySegments.last?.position ?? snakeHead.position
        addChild(seg)
        bodySegments.append(seg)
        ensurePointCacheLength(bodySegments.count, cache: &bodyPositionCache)
        positionHistory.setCapacity(historyCapacity(forSegmentCount: bodySegments.count))
        updateSegmentScales()
    }

    /// Grow or shrink the player body to match targetBodyCount.
    /// Called on every score change so boost drain also shrinks the snake.
    func syncSnakeLength() {
        let target = targetBodyCount
        while bodySegments.count < target {
            let seg = makePlayerBodySegment(segIndex: bodySegments.count)
            seg.position = bodySegments.last?.position ?? snakeHead.position
            addChild(seg)
            bodySegments.append(seg)
        }
        while bodySegments.count > target && bodySegments.count > 1 {
            bodySegments.removeLast().removeFromParent()
        }
        ensurePointCacheLength(bodySegments.count, cache: &bodyPositionCache)
        positionHistory.setCapacity(historyCapacity(forSegmentCount: bodySegments.count))
        updateSegmentScales()
    }

    func createSpawnHole(at position: CGPoint, angle: CGFloat, accent: SKColor) -> SKNode {
        let hole = SKNode()
        hole.position = position
        hole.zPosition = -0.5
        hole.zRotation = angle

        let shadow = SKShapeNode(ellipseOf: CGSize(width: 60, height: 28))
        shadow.fillColor = SKColor(red: 0.03, green: 0.05, blue: 0.07, alpha: 0.72)
        shadow.strokeColor = SKColor(red: 0.12, green: 0.18, blue: 0.20, alpha: 0.40)
        shadow.lineWidth = 1.0
        shadow.yScale = 0.74
        hole.addChild(shadow)

        let rim = SKShapeNode(ellipseOf: CGSize(width: 72, height: 34))
        rim.fillColor = .clear
        rim.strokeColor = accent.withAlphaComponent(0.26)
        rim.lineWidth = 1.6
        rim.glowWidth = 4
        rim.yScale = 0.72
        hole.addChild(rim)

        for index in 0..<6 {
            let puff = SKShapeNode(circleOfRadius: CGFloat.random(in: 3.5...6.0))
            puff.fillColor = SKColor(red: 0.75, green: 0.83, blue: 0.78, alpha: 0.18)
            puff.strokeColor = .clear
            let spread = CGFloat(index - 2) * 5.0
            puff.position = CGPoint(x: spread, y: CGFloat.random(in: -5...4))
            puff.zPosition = -0.1
            hole.addChild(puff)

            let rise = SKAction.group([
                SKAction.moveBy(x: CGFloat.random(in: -10...10), y: CGFloat.random(in: 10...20), duration: 0.36),
                SKAction.fadeOut(withDuration: 0.36),
                SKAction.scale(to: 0.4, duration: 0.36)
            ])
            puff.run(SKAction.sequence([
                SKAction.wait(forDuration: Double(index) * 0.015),
                rise,
                SKAction.removeFromParent()
            ]))
        }

        return hole
    }

    func animateSnakeEntrance(head: SKNode, body: [SKShapeNode], angle: CGFloat, accent: SKColor) {
        let hole = createSpawnHole(at: head.position, angle: angle, accent: accent)
        addChild(hole)
        hole.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.55),
            SKAction.group([
                SKAction.fadeOut(withDuration: 0.24),
                SKAction.scale(to: 0.88, duration: 0.24)
            ]),
            SKAction.removeFromParent()
        ]))

        let nodes = [head] + body.map { $0 as SKNode }
        for (index, node) in nodes.enumerated() {
            let targetAlpha = node.alpha
            let targetX = node.xScale
            let targetY = node.yScale
            node.alpha = 0
            node.setScale(max(0.18, min(targetX, targetY) * 0.22))
            node.run(SKAction.sequence([
                SKAction.wait(forDuration: Double(min(index, 7)) * 0.028),
                SKAction.group([
                    SKAction.fadeAlpha(to: targetAlpha, duration: 0.28),
                    SKAction.scaleX(to: targetX, duration: 0.32),
                    SKAction.scaleY(to: targetY, duration: 0.32)
                ])
            ]))
        }
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
        let theme   = snakeColorThemes[normalizedSnakeColorIndex(selectedSnakeColorIndex)]
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
        let botCount = localBotTargetCount
        let nemesisIndex = gameMode == .challenge ? botCount - 1 : -1

        for i in 0..<botCount {
            let playerColorIndex = normalizedSnakeColorIndex(selectedSnakeColorIndex)
            var colorIndex = (playerColorIndex + 1 + (i % (snakeColorThemes.count - 1))) % snakeColorThemes.count
            if colorIndex == playerColorIndex {
                colorIndex = (colorIndex + 1) % snakeColorThemes.count
            }
            let isNemesis = i == nemesisIndex
            let name = isNemesis ? "NEMESIS" : namePool[i % namePool.count]

            // First 15 spawn near player for immediate action
            let position: CGPoint
            if i < 15 {
                let angle = CGFloat.random(in: 0...(2 * .pi))
                let dist  = isNemesis ? CGFloat.random(in: 260...480) : CGFloat.random(in: 300...680)
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

            if isNemesis {
                bots[i].isNemesis = true
                bots[i].tier = .hard
                bots[i].personality = .nemesis
            } else {
                // Assign tier: 0–9 easy, 10–21 medium, 22–29 hard
                switch min(i, totalBots - 1) {
                case 0..<10:  bots[i].tier = .easy
                case 10..<22: bots[i].tier = .medium
                default:      bots[i].tier = .hard
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

    private func configureBotIdentity(index: Int, preservePersonality: Bool) {
        if !preservePersonality && !bots[index].isNemesis {
            let personalities = botPersonalities(for: bots[index].tier)
            bots[index].personality = personalities.randomElement() ?? .opportunist
        }

        let profile = GameLogic.botPersonalityProfile(for: bots[index].personality)
        let length = bots[index].isNemesis ? 130 : randomBotLength(for: index)
        let bonusScore = Int(CGFloat(length) * (0.35 + profile.aggression * 0.25 + profile.scavengerBias * 0.15))

        bots[index].score = bots[index].isNemesis ? challengeNemesisScore : max(4, bonusScore + Int.random(in: 0...10))
        bots[index].bodyLength = length
        bots[index].intent = bots[index].isNemesis ? .hunt : .roam
        bots[index].decisionTimer = 0
        bots[index].boostTimer = 0
        bots[index].boostCooldown = bots[index].isNemesis ? 0.08 : CGFloat.random(in: 0.15...0.80)
        bots[index].isBoosting = false
        bots[index].focusPoint = nil
        bots[index].focusTimer = 0
        bots[index].shieldCharges = 0
        bots[index].multiplierTimeLeft = 0
        bots[index].magnetTimeLeft = 0
        bots[index].ghostTimeLeft = 0
        bots[index].roamAnchor = randomPositionInArena()
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
            let seg = makeBodySegment(color: theme.bodySKColor, stroke: theme.bodyStrokeSKColor)
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
        miniLeaderboardNeedsRefresh = true
        animateSnakeEntrance(head: head, body: bots[index].body, angle: bot.angle, accent: theme.bodySKColor)
    }

    func deactivateBot(_ index: Int) {
        guard bots[index].isActive else { return }
        bots[index].head?.removeFromParent()
        bots[index].head = nil
        bots[index].nameLabel = nil
        for seg in bots[index].body { seg.removeFromParent() }
        bots[index].body.removeAll()
        bots[index].bodyPositionCache.removeAll()
        bots[index].posHistory.removeAll()
        bots[index].isActive = false
        miniLeaderboardNeedsRefresh = true
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
                           patternIndex: 0)  // body becomes death food; bots use solid pattern
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
        bots[index].position = CGPoint(
            x: CGFloat.random(in: 300...(worldSize - 300)),
            y: CGFloat.random(in: 300...(worldSize - 300))
        )
        bots[index].angle = CGFloat.random(in: 0...(2 * .pi))
        bots[index].targetAngle = bots[index].angle
        configureBotIdentity(index: index, preservePersonality: true)
        activateBot(index)
        if bots[index].isNemesis && gameMode == .challenge {
            spawnFloatingText("⚠️ Nemesis has entered!", at: CGPoint(x: snakeHead.position.x, y: snakeHead.position.y + 90))
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
        if bots[index].isNemesis { speed *= 1.18 }
        if includeBoost && bots[index].isBoosting {
            speed *= botBoostMultiplier
        }
        return speed
    }

    func botTurnSpeed(for index: Int) -> CGFloat {
        let profile = GameLogic.botPersonalityProfile(for: bots[index].personality)
        let boostAdjustment: CGFloat = bots[index].isBoosting ? 0.96 : 1.0
        let nemesisBonus: CGFloat = bots[index].isNemesis ? 1.20 : 1.0
        return turnSpeed * profile.turnRateMultiplier * boostAdjustment * nemesisBonus
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
                speed: currentMoveSpeed * (isBoostHeld ? boostMultiplier : 1.0),
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

    /// Rebuilds per-food cluster bonuses when the food set changes (lazy, O(n²) once per change).
    private func rebuildClusterBonusesIfNeeded() {
        guard clusterBonusDirty else { return }
        cachedClusterBonuses = Array(repeating: 0, count: foodItems.count)
        for i in foodItems.indices where foodItems[i].parent != nil {
            var bonus: CGFloat = 0
            let px = foodItems[i].position.x
            let py = foodItems[i].position.y
            for j in foodItems.indices where j != i && foodItems[j].parent != nil {
                let dx = foodItems[j].position.x - px
                let dy = foodItems[j].position.y - py
                if abs(dx) > 110 || abs(dy) > 110 { continue }
                guard hypot(dx, dy) < 110 else { continue }
                switch foodTypes[j] {
                case .death: bonus += 0.55
                case .trail: bonus += 0.18
                default:     bonus += 0.10
                }
            }
            cachedClusterBonuses[i] = min(2.4, bonus)
        }
        clusterBonusDirty = false
    }

    private func interestingFoodTargets(for i: Int, limit: Int = 8) -> [BotFoodTarget] {
        let profile = GameLogic.botPersonalityProfile(for: bots[i].personality)
        let position = bots[i].position
        var targets: [BotFoodTarget] = []

        rebuildClusterBonusesIfNeeded()

        for (index, food) in foodItems.enumerated() where food.parent != nil {
            let distance = hypot(food.position.x - position.x, food.position.y - position.y)
            guard distance < profile.foodSearchRadius else { continue }

            let bonus = index < cachedClusterBonuses.count ? cachedClusterBonuses[index] : 0
            let utility = GameLogic.botFoodValue(
                type: foodTypes[index],
                clusterBonus: bonus,
                greed: profile.greed,
                scavengerBias: profile.scavengerBias
            ) * max(0.18, 1.0 - distance / profile.foodSearchRadius)

            guard utility > 0.5 else { continue }
            targets.append(BotFoodTarget(index: index, position: food.position, type: foodTypes[index], utility: utility))
        }

        targets.sort { $0.utility > $1.utility }
        return Array(targets.prefix(limit))
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
            bots[i].roamAnchor = randomPositionInArena()
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
                bots[i].boostCooldown = bots[i].isNemesis
                    ? CGFloat.random(in: 0.40...1.00)
                    : CGFloat.random(in: botBoostCooldownRange)
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
        let targetGlow: CGFloat = bots[index].isBoosting ? 10 : 5
        if head.glowWidth != targetGlow { head.glowWidth = targetGlow }
        let targetScale: CGFloat = bots[index].isBoosting ? 1.04 : 1.0
        if head.xScale != targetScale { head.setScale(targetScale) }

        if botBodyUpdateFrame == 0 {
            fillArcPositions(
                history: bots[index].posHistory,
                leadPos: bots[index].position,
                count: bots[index].body.count,
                spacing: segmentPixelSpacing,
                into: &bots[index].bodyPositionCache
            )
            let camPos    = cameraNode.position
            let viewHalfW = (size.width  * 0.5) / cameraNode.xScale + bodySegmentRadius * 2
            let viewHalfH = (size.height * 0.5) / cameraNode.yScale + bodySegmentRadius * 2
            let boosting   = bots[index].isBoosting
            let bodyCount  = bots[index].body.count
            let halfCount  = max(1, bodyCount / 2)
            let sixthCount = max(2, bodyCount / 6)
            for (segmentIndex, segment) in bots[index].body.enumerated() {
                let pos = bots[index].bodyPositionCache[segmentIndex]
                // Only write SKNode position when visible in viewport.
                if abs(pos.x - camPos.x) < viewHalfW && abs(pos.y - camPos.y) < viewHalfH {
                    segment.position = pos
                }
                let baseGlow: CGFloat = segmentIndex < halfCount ? 3 : 0
                let newGlow: CGFloat  = (boosting && segmentIndex < sixthCount) ? 6 : baseGlow
                if segment.glowWidth != newGlow { segment.glowWidth = newGlow }
            }
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

            updateBotBoostState(index: i, dt: dt)
            applyBotMagnetEffect(botIndex: i, dt: dt)
            let distanceToPlayer = hypot(bots[i].position.x - playerPos.x, bots[i].position.y - playerPos.y)

            if updateAI && bots[i].decisionTimer <= 0 {
                let decision = distanceToPlayer < botDetailedAIRadius
                    ? chooseBestHeading(for: i)
                    : chooseAmbientDecision(for: i)
                applyBotDecision(decision, index: i)
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
                let trailInterval = bots[i].isBoosting ? botTrailInterval * 0.65 : botTrailInterval
                if bots[i].trailFoodTimer >= trailInterval {
                    if let tailSeg = bots[i].body.last {
                        spawnTrailFood(at: tailSeg.position,
                                       colorIndex: bots[i].colorIndex,
                                       patternIndex: 0)
                    }
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
            bots[botIndex].multiplierTimeLeft = 10.0
        case .magnet:
            bots[botIndex].magnetTimeLeft = 6.0
        case .ghost:
            bots[botIndex].ghostTimeLeft = 4.0
        case .regular, .trail, .death, .shrink:
            break
        }
    }

    private func applyBotMagnetEffect(botIndex: Int, dt: CGFloat) {
        guard bots[botIndex].magnetTimeLeft > 0 else { return }

        let strength: CGFloat = 560 * dt
        let headPos = bots[botIndex].position
        let magnetRadiusSq = magnetRadius * magnetRadius

        for (i, food) in foodItems.enumerated() {
            guard food.parent != nil else { continue }
            if foodTypes[i] == .trail || foodTypes[i] == .death { continue }

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

    private func botNutrition(for type: FoodType, botIndex: Int) -> (segments: Int, score: Int) {
        let scoreMultiplier = bots[botIndex].multiplierTimeLeft > 0 ? 2 : 1
        switch type {
        case .regular:                   return (1, 2 * scoreMultiplier)
        case .trail:                     return (1, 1 * scoreMultiplier)
        case .death:                     return (2, 5 * scoreMultiplier)
        case .shield, .multiplier,
             .magnet, .ghost:            return (1, 2 * scoreMultiplier)
        case .shrink:                    return (0, 0)
        }
    }

    func checkBotFoodCollision(_ botIndex: Int) {
        let headPosition = bots[botIndex].position
        let thresholdSq: CGFloat = (headRadius + foodRadius) * (headRadius + foodRadius)
        for (i, food) in foodItems.enumerated().reversed() {
            let dx = headPosition.x - food.position.x
            let dy = headPosition.y - food.position.y
            if dx * dx + dy * dy < thresholdSq {
                if foodTypes[i] == .trail { activeTrailFoodCount = max(0, activeTrailFoodCount - 1) }
                let nutrition = botNutrition(for: foodTypes[i], botIndex: botIndex)
                food.removeFromParent()
                foodItems.remove(at: i)
                let type = foodTypes.remove(at: i)
                clusterBonusDirty = true
                spawnFood()
                for _ in 0..<nutrition.segments { addBotBodySegment(botIndex) }
                bots[botIndex].score += nutrition.score
                applyBotPowerUp(type: type, botIndex: botIndex)
                miniLeaderboardNeedsRefresh = true

                if type == .shrink, bots[botIndex].bodyLength > 12 {
                    bots[botIndex].bodyLength = max(10, bots[botIndex].bodyLength - 2)
                    while bots[botIndex].body.count > bots[botIndex].bodyLength {
                        bots[botIndex].body.last?.removeFromParent()
                        bots[botIndex].body.removeLast()
                    }
                    ensurePointCacheLength(bots[botIndex].body.count, cache: &bots[botIndex].bodyPositionCache)
                    bots[botIndex].posHistory.setCapacity(historyCapacity(forSegmentCount: bots[botIndex].body.count))
                }
                return
            }
        }
    }

    func checkPlayerCollidesWithBotBodies() -> Bool {
        if ghostActive { return false }   // 👻 ghost: pass through bodies
        let interactionRadiusSq = interactionRadiusForPlayerBody() * interactionRadiusForPlayerBody()
        for bot in bots where bot.isActive && !bot.isDead {
            if bot.ghostTimeLeft > 0 { continue }
            let dx = snakeHead.position.x - bot.position.x
            let dy = snakeHead.position.y - bot.position.y
            guard dx * dx + dy * dy <= interactionRadiusSq else { continue }
            if headCollidesWithPoints(
                snakeHead.position,
                points: bot.bodyPositionCache,
                combinedRadius: collisionRadius + bodySegmentRadius
            ) { return true }
        }
        return false
    }

    /// Offline: player head collides with a bot head → both die (head-to-head).
    func checkPlayerHeadVsBotHeads() -> Bool {
        guard gameMode != .online, !ghostActive else { return false }
        for i in 0..<bots.count {
            guard bots[i].isActive, !bots[i].isDead, let botHead = bots[i].head else { continue }
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
        guard gameMode != .online else { return }
        let interactionRadius = interactionRadiusForPlayerBody()
        let interactionRadiusSq = interactionRadius * interactionRadius
        guard !bodyPositionCache.isEmpty else { return }
        for i in 0..<bots.count {
            guard bots[i].isActive, !bots[i].isDead, let botHead = bots[i].head else { continue }
            if bots[i].ghostTimeLeft > 0 { continue }
            let dx = snakeHead.position.x - botHead.position.x
            let dy = snakeHead.position.y - botHead.position.y
            guard dx * dx + dy * dy <= interactionRadiusSq else { continue }
            if headCollidesWithPoints(
                botHead.position,
                points: bodyPositionCache,
                combinedRadius: collisionRadius + bodySegmentRadius
            ) {
                if bots[i].shieldCharges > 0 {
                    bots[i].shieldCharges -= 1
                } else {
                    respawnBot(i)
                }
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
            head: head, body: [], posHistory: PointRingBuffer(), bodyPositionCache: [], score: 0,
            bodyLength: 10, nameLabel: nameLabel, colorIndex: colorIndex,
            playerName: playerName
        )
        miniLeaderboardNeedsRefresh = true
        animateSnakeEntrance(head: head, body: [], angle: 0, accent: theme.bodySKColor)
    }

    func removeRemotePlayer(actorID: Int) {
        guard let rp = remotePlayers[actorID] else { return }
        rp.head.removeFromParent()
        for seg in rp.body { seg.removeFromParent() }
        remotePlayers.removeValue(forKey: actorID)
        minimapRemotePlayerDots[actorID]?.removeFromParent()
        minimapRemotePlayerDots.removeValue(forKey: actorID)
        miniLeaderboardNeedsRefresh = true
    }

    func updateRemotePlayerPosition(actorID: Int, headX: Float, headY: Float,
                                    angle: Float, score: Int32, bodyLength: Int32) {
        guard var rp = remotePlayers[actorID] else { return }
        let newPos    = CGPoint(x: CGFloat(headX), y: CGFloat(headY))
        let segCount  = max(1, Int(bodyLength))
        let theme     = snakeColorThemes[rp.colorIndex % snakeColorThemes.count]

        rp.head.run(SKAction.move(to: newPos, duration: 0.05))
        rp.head.zRotation = (CGFloat(angle) * 180 / .pi - 90) * .pi / 180

        rp.posHistory.setCapacity(historyCapacity(forSegmentCount: segCount))
        rp.posHistory.append(newPos)

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
        ensurePointCacheLength(rp.body.count, cache: &rp.bodyPositionCache)

        fillArcPositions(history: rp.posHistory, leadPos: newPos,
                         count: rp.body.count, spacing: segmentPixelSpacing,
                         into: &rp.bodyPositionCache)
        let dist      = hypot(snakeHead.position.x - newPos.x, snakeHead.position.y - newPos.y)
        let isVisible = dist <= visibleRadius
        rp.head.isHidden = !isVisible

        for (i, seg) in rp.body.enumerated() {
            seg.position = rp.bodyPositionCache[i]
            seg.isHidden = !isVisible
            // Taper scale + alpha toward tail (same look as local player)
            let t: CGFloat = segCount > 1 ? CGFloat(i) / CGFloat(segCount - 1) : 0
            seg.setScale(1.0 - t * 0.22)
            seg.alpha     = 1.0 - t * 0.10
            seg.glowWidth = i < segCount / 2 ? 3 : 0
        }

        remotePlayers[actorID] = rp
        miniLeaderboardNeedsRefresh = true
    }

    func checkPlayerCollidesWithRemotePlayers() -> Bool {
        if ghostActive { return false }   // 👻 ghost: pass through bodies
        for (_, rp) in remotePlayers where !rp.head.isHidden {
            if headCollidesWithPoints(
                snakeHead.position,
                points: rp.bodyPositionCache,
                combinedRadius: collisionRadius + bodySegmentRadius
            ) { return true }
        }
        return false
    }

    // MARK: - New Power-Up Effects

    /// 🧲 Magnet — pull nearby food items toward the snake head.
    func applyMagnetEffect() {
        let pullStrength: CGFloat   = 5.5
        let magnetRadiusSq: CGFloat = magnetRadius * magnetRadius
        for food in foodItems {
            guard food.parent != nil else { continue }
            let dx     = snakeHead.position.x - food.position.x
            let dy     = snakeHead.position.y - food.position.y
            let distSq = dx * dx + dy * dy
            guard distSq > 1, distSq < magnetRadiusSq else { continue }
            let dist = hypot(dx, dy)   // sqrt only for in-range items
            food.position = CGPoint(x: food.position.x + (dx / dist) * pullStrength,
                                    y: food.position.y + (dy / dist) * pullStrength)
        }
    }

    /// ✂️ Shrink — reduce score by ~10% so that syncSnakeLength() contracts the body accordingly.
    func applyShrink() {
        guard score > 0 else { return }
        let reduction  = max(1, score * 10 / 100)
        score          = max(0, score - reduction)
        updateScoreDisplay()
        updateSpeedForScore()   // calls syncSnakeLength() → body contracts
        invincibleTimeLeft = 0.8   // brief safety window after shrink
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

    // MARK: - Collision Detection
    func checkSelfCollision() -> Bool {
        headCollidesWithPoints(
            snakeHead.position,
            points: bodyPositionCache,
            combinedRadius: collisionRadius + bodySegmentRadius,
            skip: spacingBetweenSegments * 2
        )
    }


    @discardableResult
    private func consumeBotShieldIfAvailable(_ index: Int) -> Bool {
        guard bots[index].shieldCharges > 0 else { return false }
        bots[index].shieldCharges -= 1
        return true
    }

    func checkBotVsBotCollisions() {
        guard bots.count > 1 else { return }

        for i in 0..<(bots.count - 1) {
            guard bots[i].isActive, !bots[i].isDead, let headI = bots[i].head else { continue }

            for j in (i + 1)..<bots.count {
                guard bots[j].isActive, !bots[j].isDead, let headJ = bots[j].head else { continue }
                guard botPairWithinBroadPhase(bots[i], bots[j]) else { continue }

                // Head-to-body collisions (both directions)
                if bots[i].ghostTimeLeft <= 0 {
                    if !bots[j].bodyPositionCache.isEmpty,
                       headCollidesWithPoints(
                        headI.position,
                        points: bots[j].bodyPositionCache,
                        combinedRadius: collisionRadius + bodySegmentRadius
                       ) {
                        if !consumeBotShieldIfAvailable(i) { respawnBot(i) }
                        continue
                    }
                }

                if bots[j].ghostTimeLeft <= 0 {
                    if !bots[i].bodyPositionCache.isEmpty,
                       headCollidesWithPoints(
                        headJ.position,
                        points: bots[i].bodyPositionCache,
                        combinedRadius: collisionRadius + bodySegmentRadius
                       ) {
                        if !consumeBotShieldIfAvailable(j) { respawnBot(j) }
                        continue
                    }
                }

                // Head-to-head collision (evaluated once per pair)
                if bots[i].ghostTimeLeft <= 0, bots[j].ghostTimeLeft <= 0 {
                    let d = hypot(headI.position.x - headJ.position.x,
                                  headI.position.y - headJ.position.y)
                    if d < (headRadius + headRadius) {
                        if !consumeBotShieldIfAvailable(i) { respawnBot(i) }
                        if !consumeBotShieldIfAvailable(j) { respawnBot(j) }
                    }
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
                    shutdown()
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
                    shutdown()
                    onGameOver?(score)
                }
                continue
            }

            if gameStarted && nodes(at: loc).contains(where: { $0.name == "pauseButton" }) {
                togglePause(); continue
            }

            guard gameStarted, !isPausedGame else { continue }

            let controlScale = hudControlScale()
            let boostDist = hypot(loc.x - boostButtonCenter.x, loc.y - boostButtonCenter.y)
            if boostTouch == nil && boostDist < boostButtonRadius * 1.4 * controlScale && score > 0 {
                boostTouch  = touch
                isBoostHeld = true
                setBoostButtonActive(true)
                continue
            }

            let joystickDist = hypot(loc.x - joystickCenter.x, loc.y - joystickCenter.y)
            if joystickTouch == nil && joystickDist < joystickBaseRadius * 1.6 * controlScale {
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

        // --- Boost Score Drain (1 pt per 200ms) ---
        if isBoostHeld {
            if score <= 0 {
                // No score left — disengage boost
                isBoostHeld = false
                boostTouch  = nil
                setBoostButtonActive(false)
            } else {
                boostScoreDrainTimer += dt
                if boostScoreDrainTimer >= 0.2 {
                    boostScoreDrainTimer = 0
                    score = max(0, score - 1)
                    updateScoreDisplay()
                    updateSpeedForScore()
                }
            }
        } else {
            boostScoreDrainTimer = 0
        }

        // --- Player Movement ---
        let playerDist = currentMoveSpeed * (isBoostHeld ? boostMultiplier : 1.0) * dt

        positionHistory.append(snakeHead.position)
        positionHistory.setCapacity(historyCapacity(forSegmentCount: bodySegments.count))

        if isTouching {
            let dynamicTurnSpeed = playerTurnSpeedBase
                + joystickEngagement * playerTurnSpeedBoost
                + (isBoostHeld ? 25 : 0)
            smoothlyRotate(
                current: &currentAngle,
                target: targetAngle,
                dt: dt,
                maxTurnSpeed: dynamicTurnSpeed
            )
        }

        snakeHead.position.x += cos(currentAngle) * playerDist
        snakeHead.position.y += sin(currentAngle) * playerDist
        snakeHead.zRotation   = (currentAngle * 180.0 / .pi - 90.0) * .pi / 180.0
        lastPlayerPosition    = snakeHead.position

        fillArcPositions(history: positionHistory, leadPos: snakeHead.position,
                         count: bodySegments.count, spacing: segmentPixelSpacing,
                         into: &bodyPositionCache)

        // Shield wiggle: last 30% of body oscillates perpendicular to movement
        let totalSegs   = bodySegments.count
        let dangerCount = shieldActive ? max(1, Int(CGFloat(totalSegs) * 0.30)) : 0
        let dangerStart = totalSegs - dangerCount
        if shieldActive { tailWigglePhase += dt * 8.0 }

        // Viewport bounds for culling off-screen segment writes (cache computed once per frame).
        // bodyPositionCache is always updated fully — only the SKNode write is skipped off-screen.
        let camPos   = cameraNode.position
        let viewHalfW = (size.width  * 0.5) / cameraNode.xScale + bodySegmentRadius * 2
        let viewHalfH = (size.height * 0.5) / cameraNode.yScale + bodySegmentRadius * 2

        for (i, seg) in bodySegments.enumerated() {
            var pos = bodyPositionCache[i]
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
            bodyPositionCache[i] = pos
            // Only push position to the SKNode when it is within the visible viewport.
            // The cache above is always authoritative for AI collision checks.
            if abs(pos.x - camPos.x) < viewHalfW && abs(pos.y - camPos.y) < viewHalfH {
                seg.position = pos
            }
        }

        // Shield tail kills bots on contact
        if shieldActive && dangerCount > 0 && frameCounter % 2 == 0 {
            for bi in 0..<bots.count {
                guard bots[bi].isActive, !bots[bi].isDead, let botHead = bots[bi].head else { continue }
                if headCollidesWithPoints(
                    botHead.position,
                    points: bodyPositionCache,
                    startIndex: dangerStart,
                    combinedRadius: collisionRadius + bodySegmentRadius
                ) {
                    respawnBot(bi)
                }
            }
        }

        // --- Collisions ---
        if checkWallCollision() { playerGameOver(); return }
        // Self-collision intentionally disabled: snake passes through its own body

        if gameMode != .online && checkPlayerCollidesWithBotBodies()    { playerGameOver(); return }
        if gameMode != .online && checkPlayerHeadVsBotHeads()           { playerGameOver(); return }
        if gameMode == .online  && checkPlayerCollidesWithRemotePlayers() { playerGameOver(); return }

        checkFoodCollisions()

        // --- Trail food spawning (player) ---
        if gameMode != .online, gameStarted, let tailSeg = bodySegments.last {
            trailFoodTimer += dt
            if trailFoodTimer >= playerTrailInterval {
                spawnTrailFood(at: tailSeg.position,
                               colorIndex: selectedSnakeColorIndex,
                               patternIndex: selectedSnakePatternIndex)
                trailFoodTimer = 0
            }
        }

        // --- Safety net: purge orphaned food entries (death food still relies on this) ---
        if gameMode != .online && frameCounter % 300 == 0 {
            var toRemove: [Int] = []
            for (i, item) in foodItems.enumerated() where item.parent == nil {
                toRemove.append(i)
            }
            for i in toRemove.reversed() {
                foodItems.remove(at: i)
                foodTypes.remove(at: i)
            }
            // Reconcile counter against live trail entries to correct any drift
            activeTrailFoodCount = foodTypes.filter { $0 == .trail }.count
        }

        // --- Camera & HUD ---
        updateCamera()
        updateHUDPositions()

        // --- Magnet power-up: pull food every other frame ---
        if magnetActive && frameCounter % 2 == 0 { applyMagnetEffect() }

        // --- Mode-specific ---
        if gameMode != .online {
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
        minimapUpdateTimer += dt
        if minimapUpdateTimer >= (1.0 / 15.0) {
            minimapUpdateTimer = 0
            updateMinimap()
        }

        leaderArrowUpdateTimer += dt
        if leaderArrowUpdateTimer >= 0.1 {
            leaderArrowUpdateTimer = 0
            updateLeaderArrow()
        }

        // --- Mini Leaderboard (refresh on change, with 1 Hz fallback) ---
        leaderboardUpdateTimer += dt
        if miniLeaderboardNeedsRefresh || leaderboardUpdateTimer >= 1.0 {
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
    func didJoinRoom() {
        primeOnlineRoundIfReady()
    }

    func didReceivePlayerState(_ state: RemotePlayerState, playerID: Int) {
        if remotePlayers[playerID] == nil {
            addRemotePlayer(actorID: playerID,
                            colorIndex: (normalizedSnakeColorIndex(selectedSnakeColorIndex) + playerID) % snakeColorThemes.count,
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
        applyOnlineFoodUpdate(
            foodIndex: foodIndex,
            newFoodX: newFoodX,
            newFoodY: newFoodY,
            newFoodType: newFoodType
        )
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
