import SpriteKit
import AVFoundation
import UIKit
import GameController


// MARK: - GameScene
class GameScene: SKScene {

    struct GridCell: Hashable {
        let x: Int
        let y: Int
    }

    // MARK: - Callbacks & Config
    var onGameOver: ((Int) -> Void)?
    var playerHeadImage: UIImage?
    var gameMode: GameMode = .offline
    var selectedSnakeColorIndex: Int = 0
    var selectedSnakePatternIndex: Int = 0
    var playerName: String = "Player"
    var activeLayout: PlayAreaLayout = .default
    private var hasShutdown = false

    // MARK: - Audio
    var backgroundMusicPlayer: AVAudioPlayer?
    let eatFoodAction = SKAction.playSoundFileNamed("eat_food.wav", waitForCompletion: false)
    let deathAction   = SKAction.playSoundFileNamed("death.wav",    waitForCompletion: false)
    var lastEatSoundTime: TimeInterval = 0   // throttles eat sounds to prevent stutter

    // MARK: - Timing
    var lastUpdateTime: TimeInterval = 0

    // MARK: - World & Camera
    let worldSize: CGFloat = 6000.0
    let visibleRadius: CGFloat = 700.0
    var cameraNode = SKCameraNode()
    let cameraZoomStepScore: CGFloat = 500.0
    let cameraZoomPerStep:   CGFloat = 0.08
    let maxCameraScale:      CGFloat = 1.20

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
    var effectiveHeadRadius: CGFloat {
        score < 1000 ? headRadius : min(headRadius * 1.5, headRadius * (1.0 + CGFloat(score - 1000) / 4000.0))
    }
    var effectiveBodyRadius: CGFloat {
        score < 1000 ? bodySegmentRadius : min(bodySegmentRadius * 1.5, bodySegmentRadius * (1.0 + CGFloat(score - 1000) / 4000.0))
    }
    let collisionRadius:         CGFloat = 12.0
    let foodRadius:              CGFloat = 12.0
    let safeSpawnDistance:       CGFloat = 80.0
    let foodPadding:             CGFloat = 80.0
    let initialBodyCount:        Int     = 10
    let initialBotBodyCount:     Int     = 10
    let spacingBetweenSegments:  Int     = 8
    let segmentPixelSpacing:     CGFloat = 14.0
    let foodCount:               Int     = 340
    let maxDeltaTime:            Double  = 0.1
    let minimumGameplayFPS:      Double  = 30.0
    var botUpdateAccumulator:    CGFloat = 0
    var botCollisionAccumulator: CGFloat = 0
    var botHeadCheckAccumulator: CGFloat = 0

    // MARK: - Speed & Boost
    var currentMoveSpeed: CGFloat = 100.0
    var isBoostHeld:      Bool    = false
    let boostMultiplier:  CGFloat = 1.65
    var boostZoomExtra:   CGFloat = 0    // temporary extra zoom-out while boosting

    // MARK: - Player Snake
    var snakeHead: SKNode!
    var bodySegments:    [SKShapeNode] = []
    var playerBodyPathNode = SKShapeNode()
    var positionHistory = PointRingBuffer()
    var bodyPositionCache: [CGPoint] = []
    var playerBodyOccupancy: Set<GridCell> = []
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

    // MARK: - Game Controller
    var connectedController: GCController?

    // MARK: - Boost Button
    let boostButtonRadius: CGFloat = 54   // 150% of original 36pt
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
    // Spatial grid for food collision queries: cuts checkFoodCollisions / checkBotFoodCollision
    // from O(n=340) down to O(~3) per query.  Cell size 200 pt → 30×30 = 900 cells on the 6000 pt world.
    // Indices stored are into the foodItems/foodTypes arrays; kept in sync by removeFoodItem(at:).
    var foodSpatialGrid: [GridCell: [Int]] = [:]
    let foodGridCellSize: CGFloat = 200.0
    var foodGridDirty: Bool = true   // set true when magnet moves food; triggers lazy full rebuild
    // Trail food
    var trailFoodTimer: CGFloat = 0
    var activeTrailFoodCount: Int = 0         // O(1) counter; avoids O(n) filter on trail cap check
    let playerTrailInterval: CGFloat = 0.35   // player spawns trail food every 0.35s
    let botTrailInterval:    CGFloat = 0.60   // bots spawn trail food every 0.60s
    let maxTrailFoodItems:   Int     = 220    // hard cap on active .trail nodes
    // Trail food: makeTrailFoodNode — simple texture-backed sprite (pre-rendered per color theme).
    // Using SKSpriteNode with a cached SKTexture avoids allocating 1–5 nested SKShapeNodes
    // per spawn (53/sec while boosting). Cache is pre-warmed at game start.
    var trailFoodTextureCache: [Int: SKTexture] = [:]
    // Regular and icon food: pre-rendered SKTexture per emoji/icon string.
    // Eliminates live SKLabelNode text rendering cost for ~340 on-screen food nodes.
    var foodTextureCache: [String: SKTexture] = [:]
    // Death food: makeDeathHeadNode (head) + makeDeathFoodNode (body segments) matching dead snake skin

    // MARK: - Movement Heatmap (food density weighting)
    // 20×20 grid over the playable arena. Each cell accumulates activity as snake heads pass through.
    // Food spawns are biased 60% toward high-activity cells, 40% uniform random.
    let heatmapCols: Int = 20
    let heatmapRows: Int = 20
    var movementHeatmap: [[Float]] = Array(repeating: Array(repeating: 0.1, count: 20), count: 20)   // [row][col]
    var heatmapSampleTimer: CGFloat = 0
    let heatmapSampleInterval: CGFloat = 0.5   // record positions every 0.5 s
    var heatmapDecayTimer: CGFloat = 0
    let heatmapDecayInterval: CGFloat = 15.0   // decay all cells every 15 s
    let heatmapDecayFactor: Float = 0.85       // keep 85% of activity per decay step

    // MARK: - Arena
    var arenaMinX: CGFloat = 0, arenaMaxX: CGFloat = 6000
    var arenaMinY: CGFloat = 0, arenaMaxY: CGFloat = 6000
    var isGameOver: Bool = false

    // MARK: - Score & HUD
    var scorePanel:                SKShapeNode?
    var scoreLabel:                SKLabelNode!
    var scorePanelHeight:          CGFloat = 40
    var hudScoreFontSize:          CGFloat = 44   // set in createScorePanel, used for combo offset
    var miniLeaderboard:           SKNode?
    var miniLeaderboardPanelHeight: CGFloat = 134  // updated in updateMiniLeaderboard
    var leaderboardUpdateTimer: CGFloat = 0
    var minimapUpdateTimer: CGFloat = 0
    var leaderArrowUpdateTimer: CGFloat = 0
    var miniLeaderboardNeedsRefresh = true

    // MARK: - Combo / Streak Scoring
    var comboCount:      Int     = 0
    var comboTimer:      CGFloat = 0
    let comboWindowSecs: CGFloat = 2.5
    let comboMaxDisplay: Int     = 5
    var comboLabel:      SKLabelNode?
    var comboPanelNode:  SKShapeNode?
    var comboFadeTimer:  CGFloat = 0
    let comboFadeSecs:   CGFloat = 2.0

    // MARK: - Game State
    var gameOverOverlay:    SKNode?   = nil
    var gameOverFocusedIndex: Int      = 0
    var gameOverButtonOrder:  [String] = []
    var gameSetupComplete:  Bool    = false
    var gameStarted:        Bool    = false
    var isPausedGame:       Bool    = false
    var lastPlayerPosition: CGPoint = .zero

    // MARK: - Maze Hunt Mode State
    enum MazeSpecialRoundType: CaseIterable {
        case none
        case twoMouse
        case pickupRich
        case highScoreBonus
        case largeMazePressure
    }

    enum MazePickupKind: CaseIterable {
        case boost
        case time
        case reveal
        case slow
    }

    var mazeWalls: [SKShapeNode] = []
    var mazeExits: [SKShapeNode] = []
    var mazeSafeSpaces: [SKShapeNode] = []
    var mazeMouseNode: SKLabelNode?
    var mazeMice: [SKLabelNode] = []
    var mazePickups: [SKLabelNode] = []
    var mazePickupKinds: [MazePickupKind] = []
    var mazeRevealTimer: CGFloat = 0
    var mazeSlowFieldTimer: CGFloat = 0
    var mazePickupSpawnTimer: CGFloat = 0
    var mazeNearMissTimer: CGFloat = 0
    var mazeBoostEnergy: CGFloat = 100
    let mazeBoostEnergyMax: CGFloat = 100
    var mazeModeLabel: SKLabelNode?
    var mazeObjectiveLabel: SKLabelNode?
    var mazePickupStatusLabel: SKLabelNode?
    var mazeEscapeTimer: CGFloat = 45
    var mazeEscapeTarget: CGPoint = .zero
    var mazeBand: Int = 1
    var mazeRoundInBand: Int = 1
    var mazeMouseSpeedMultiplier: CGFloat = 1
    var mazeCurrentSpecialRound: MazeSpecialRoundType = .none
    var mazeSpecialRoundIndex: Int? = nil
    var mazeBandsWithoutSpecial: Int = 0
    var mazeTutorialActive: Bool = false
    var mazeTutorialStep: Int = 0
    var mazeTutorialProgress: CGFloat = 0
    static var hasSeenMazeTutorial = false

    // MARK: - Snake Race Mode
    var raceObstacles: [SKShapeNode] = []
    var raceCheckpoints: [SKShapeNode] = []
    var raceModeLabel: SKLabelNode?
    var raceCurrentCheckpoint: Int = 0
    var raceTimeRemaining: CGFloat = 75
    var raceIsFinished: Bool = false

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
    /// Target body segment count for a bot, derived from score. Mirrors targetBodyCount.
    func targetBotBodyCount(for botIndex: Int) -> Int {
        max(initialBotBodyCount, initialBotBodyCount + bots[botIndex].score / 10)
    }
    var isSnakeRaceMode: Bool { false }
    var isSpecialOfflineMode: Bool { false }

    var hasUsedRevive: Bool = false

    // MARK: - Super Mouse
    var superMouseState: SuperMouseState = .dormant
    var superMouseTimer: CGFloat = 0
    var superMouseNode: SuperMouseNode?
    var superMouseHoleNode: SKNode?
    var superMouseHolePosition: CGPoint = .zero
    var superMousePosition: CGPoint = .zero
    var superMouseAngle: CGFloat = 0
    var superMouseReplanTimer: CGFloat = 0
    var superMouseEmergeProgress: CGFloat = 0
    var superMouseCurrentSpeed: CGFloat = 135
    let superMouseSpawnInterval: CGFloat = 15  // every 2 minutes
    let superMouseActiveLimit:   CGFloat = 30    // escapes if not caught within 30s
    let superMouseBaseSpeed:     CGFloat = 158   // just below player boost speed (100×1.65=165); scared surge hits ~193
    // HUD notification nodes
    var superMouseArrowNode: SKNode?
    var superMouseArrowLabel: SKLabelNode?
    var superMouseMinimapDot: SKShapeNode?
    var superMouseCountdownLabel: SKLabelNode?

    // MARK: - Other UI
    var pauseButton:  SKNode?
    var pauseOverlay: SKNode?
    var powerUpPanel: SKShapeNode?
    var powerUpLabel: SKLabelNode?

    // MARK: - Minimap
    var minimapNode:              SKNode?
    var minimapPlayerDot:         SKShapeNode?
    var minimapBotDots:           [SKShapeNode] = []
    var leaderArrowNode:          SKNode?
    var leaderArrowLabel:         SKLabelNode?

    // MARK: - Shield Wiggle
    var tailWigglePhase: CGFloat = 0

    // MARK: - Bots (Offline mode)
    var bots: [BotState] = []
    let totalBots = 60
    let challengeNemesisScore = 1200  // 10 + 1200/10 = 130 segments — preserves nemesis visual size
    let expertNemesisInitialDelay: CGFloat = 120.0  // Nemesis appears 2 minutes into Expert mode
    let expertNemesisRespawnDelay: CGFloat = 120.0  // Nemesis re-enters 2 minutes after death
    var localBotTargetCount: Int { totalBots }  // Nemesis is bot #60 (index 59) in Expert — included in the 60
    // Per-tier base speeds (replaces single botMoveSpeed)
    let botSpeedEasy:   CGFloat = 95.0
    let botSpeedMedium: CGFloat = 120.0
    let botSpeedHard:   CGFloat = 150.0
    let botSpeedScoreCap: Int = 100
    /// Extra speed multiplier applied to ALL bots in Expert (.challenge) mode.
    let expertBotSpeedMultiplier: CGFloat = 1.18
    let botBoostMultiplier: CGFloat = 1.52
    let botBoostDurationRange: ClosedRange<CGFloat> = 0.30...0.90
    let botBoostCooldownRange: ClosedRange<CGFloat> = 1.10...2.40
    /// Tighter boost cooldown used by ALL bots in Expert mode.
    let expertBotBoostCooldownRange: ClosedRange<CGFloat> = 0.65...1.50
    let botDetailedAIRadius: CGFloat = 1200.0
    let botCollisionBroadPhaseRadius: CGFloat = 260.0
    let botActivationDistance: CGFloat = 1200.0
    let botDeactivationDistance: CGFloat = 1500.0
    var botVisibilityUpdateTimer: CGFloat = 0
    var circledDetectionTimer: CGFloat = 0
    var frameCounter = 0

    // MARK: - Adaptive Quality
    // Monitors smoothed FPS and reduces rendering cost when the device is struggling.
    // Triggers after 2s below 50 FPS; recovers after 2s above 55 FPS.
    var smoothedFPS: CGFloat = 60
    var lowFPSTimer: CGFloat = 0
    var highFPSTimer: CGFloat = 0
    var adaptiveQualityActive: Bool = false
    let adaptiveQualityBotLimit: Int = 40   // max active bots when quality is reduced
    let adaptiveLowFPSThreshold: CGFloat  = 50
    let adaptiveHighFPSThreshold: CGFloat = 55

    // MARK: - Remote Players (Online mode)

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
        setupControllerSupport()
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
        NotificationCenter.default.removeObserver(self, name: .GCControllerDidConnect, object: nil)
        NotificationCenter.default.removeObserver(self, name: .GCControllerDidDisconnect, object: nil)
        connectedController = nil
    }

    // MARK: - Game Controller Support
    func setupControllerSupport() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerConnected(_:)),
            name: .GCControllerDidConnect,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDisconnected(_:)),
            name: .GCControllerDidDisconnect,
            object: nil
        )
        if let controller = GCController.controllers().first {
            connectController(controller)
        }
    }

    @objc func controllerConnected(_ notification: Notification) {
        guard let controller = notification.object as? GCController else { return }
        connectController(controller)
    }

    @objc func controllerDisconnected(_ notification: Notification) {
        connectedController = nil
        updateVirtualControlsVisibility()
    }

    func connectController(_ controller: GCController) {
        connectedController = controller
        guard let gp = controller.extendedGamepad else {
            updateVirtualControlsVisibility()
            return
        }
        // Menu → pause/unpause
        gp.buttonMenu.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { self?.togglePause() }
        }
        // A (Cross) → confirm the focused game-over button
        gp.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed, let self, self.isGameOver else { return }
            self.confirmGameOverSelection()
        }
        // B (Circle) → quick-exit to Main Menu from game-over
        gp.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed, let self, self.isGameOver else { return }
            self.shutdown()
            self.onGameOver?(self.score)
        }
        // D-pad up/down → navigate game-over button list
        gp.dpad.up.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.navigateGameOver(by: -1)
        }
        gp.dpad.down.pressedChangedHandler = { [weak self] _, _, pressed in
            guard pressed else { return }
            self?.navigateGameOver(by: 1)
        }
        updateVirtualControlsVisibility()
    }

    func updateVirtualControlsVisibility() {
        let hasController = connectedController != nil
        joystickBaseNode?.isHidden  = hasController
        joystickInnerRing?.isHidden = hasController
        joystickThumbNode?.isHidden = hasController
        boostButtonNode?.isHidden   = hasController
    }

    func readControllerInput() {
        guard let gamepad = connectedController?.extendedGamepad else { return }

        // Left thumbstick → steer
        let lx = CGFloat(gamepad.leftThumbstick.xAxis.value)
        let ly = CGFloat(gamepad.leftThumbstick.yAxis.value)
        let magnitude = hypot(lx, ly)

        if magnitude > 0.15 {
            targetAngle = atan2(ly, lx)
            isTouching = true
            joystickEngagement = min(1.0, magnitude)
        } else if gamepad.dpad.right.isPressed {
            targetAngle = 0;          isTouching = true; joystickEngagement = 1
        } else if gamepad.dpad.up.isPressed {
            targetAngle = .pi / 2;    isTouching = true; joystickEngagement = 1
        } else if gamepad.dpad.left.isPressed {
            targetAngle = .pi;        isTouching = true; joystickEngagement = 1
        } else if gamepad.dpad.down.isPressed {
            targetAngle = -.pi / 2;   isTouching = true; joystickEngagement = 1
        } else {
            isTouching = false
            joystickEngagement = 0
        }

        // Right trigger / shoulder → Boost
        let boost = gamepad.rightTrigger.value > 0.3
            || gamepad.rightShoulder.isPressed
            || gamepad.leftTrigger.value > 0.3
        if boost != isBoostHeld {
            isBoostHeld = boost
            setBoostButtonActive(boost)
        }
    }

    private var isLandscapeLayout: Bool { size.width > size.height }
    var isIPadLayout: Bool { min(size.width, size.height) >= 768 }

    private func cameraScale() -> CGFloat {
        max(cameraNode.xScale, 1.0)
    }

    func cameraHalfExtents(using scale: CGFloat? = nil) -> (halfW: CGFloat, halfH: CGFloat) {
        let zoom = scale ?? cameraScale()
        return (size.width * zoom / 2, size.height * zoom / 2)
    }

    func hudControlScale() -> CGFloat {
        cameraScale()
    }

    /// Returns safe-area insets from the current window scene (falls back to zero if unavailable).
    var safeInsets: UIEdgeInsets {
        view?.window?.safeAreaInsets ?? .zero
    }

    func joystickMargins() -> CGPoint {
        // Returns: CGPoint(x: distFromLeft, y: distFromBottom)
        if let cfg = activeConfig(for: .joystick) {
            return CGPoint(x: cfg.normalizedX * size.width,
                           y: cfg.normalizedY * size.height)
        }
        let si = safeInsets
        let baseX = max(size.width  * 0.22, 90.0)
        let baseY = max(size.height * 0.18, 130.0)
        return CGPoint(x: baseX + si.left, y: baseY + si.bottom)
    }

    func boostMargins() -> CGPoint {
        // Returns: CGPoint(x: distFromRight, y: distFromBottom)
        if let cfg = activeConfig(for: .boostButton) {
            return CGPoint(x: (1.0 - cfg.normalizedX) * size.width,
                           y: cfg.normalizedY * size.height)
        }
        let si = safeInsets
        let baseX = max(size.width  * 0.22, 90.0)
        let baseY = max(size.height * 0.18, 130.0)
        return CGPoint(x: baseX + si.right, y: baseY + si.bottom)
    }

    func minimapMargins() -> CGPoint {
        // Returns: CGPoint(x: distFromRight, y: distFromTop)
        if let cfg = activeConfig(for: .minimap) {
            return CGPoint(x: (1.0 - cfg.normalizedX) * size.width,
                           y: (1.0 - cfg.normalizedY) * size.height)
        }
        let si = safeInsets
        let baseX: CGFloat = isLandscapeLayout ? 106 : 88
        let baseY: CGFloat = isLandscapeLayout ? 78 : 68
        return CGPoint(x: baseX + si.right, y: baseY + si.top)
    }

    func leaderArrowMarginTop() -> CGFloat {
        // Returns: distance from TOP of screen
        if let cfg = activeConfig(for: .leaderArrow) {
            return (1.0 - cfg.normalizedY) * size.height
        }
        let si = safeInsets
        return (isLandscapeLayout ? 68 : 74) + si.top
    }

    // MARK: - Layout helpers

    /// Returns the active config for an element, respecting the current orientation.
    /// Landscape falls back to portrait if no landscape-specific config is saved.
    private func activeConfig(for element: HUDElement) -> HUDElementConfig? {
        activeLayout.config(for: element, isLandscape: isLandscapeLayout)
    }

    /// Converts a normalized position into camera world-space coordinates.
    /// normalizedX: 0=left, 1=right;  normalizedY: 0=bottom, 1=top (game convention).
    private func normalizedToWorld(_ normalizedX: CGFloat, _ normalizedY: CGFloat,
                                   cx: CGFloat, cy: CGFloat,
                                   halfW: CGFloat, halfH: CGFloat) -> CGPoint {
        CGPoint(x: cx - halfW + normalizedX * halfW * 2,
                y: cy - halfH + normalizedY * halfH * 2)
    }

    /// Returns the world-space position for an element if the active layout overrides it.
    func customWorldPoint(for element: HUDElement,
                                  cx: CGFloat, cy: CGFloat,
                                  halfW: CGFloat, halfH: CGFloat) -> CGPoint? {
        guard let cfg = activeConfig(for: element) else { return nil }
        return normalizedToWorld(cfg.normalizedX, cfg.normalizedY,
                                 cx: cx, cy: cy, halfW: halfW, halfH: halfH)
    }

    /// Returns the effective scale for an element: base camera scale × custom scale
    /// (custom scale only applied for joystick and boostButton).
    func elementScale(for element: HUDElement) -> CGFloat {
        let base = hudControlScale()
        guard element.supportsScale, let cfg = activeConfig(for: element) else { return base }
        return base * cfg.scale
    }

    var selectedSnakePattern: SnakePattern {
        SnakePattern(rawValue: selectedSnakePatternIndex) ?? .solid
    }

    func playerDisplayName() -> String {
        playerName.isEmpty ? "You" : playerName
    }

    /// Theoretical max boost speed of all non-nemesis bots (regardless of whether they are
    /// currently boosting). Used to anchor the player's boost so it always feels dominant.
    private func fastestRegularBotBoostSpeed() -> CGFloat? {
        bots.indices.compactMap { index in
            guard !bots[index].isDead, !bots[index].isNemesis else { return nil }
            // Cruise speed * boost multiplier, irrespective of current isBoosting state.
            return botSpeed(for: index, includeBoost: false) * botBoostMultiplier
        }
        .max()
    }

    func currentPlayerForwardSpeed() -> CGFloat {
        guard isBoostHeld else { return currentMoveSpeed }
        // Casual (.offline): player boost is 30% above the highest regular-bot boost speed.
        // Expert (.challenge): player boost is only 10% above, keeping the game harder.
        let dominanceMultiplier: CGFloat = gameMode == .challenge ? 1.10 : 1.30
        return GameLogic.boostedPlayerSpeed(
            baseSpeed: currentMoveSpeed,
            fastestBoostingBotSpeed: fastestRegularBotBoostSpeed(),
            minimumBoostMultiplier: boostMultiplier,
            dominanceMultiplier: dominanceMultiplier
        )
    }

    private func desiredCameraScale() -> CGFloat {
        let zoomSteps = floor(CGFloat(score) / cameraZoomStepScore)
        return min(1.0 + zoomSteps * cameraZoomPerStep, maxCameraScale)
    }

    func setupNewGame() {
        selectedSnakeColorIndex = normalizedSnakeColorIndex(selectedSnakeColorIndex)
        hasShutdown         = false
        isGameOver          = false
        isTouching          = false
        currentAngle        = 0
        targetAngle         = 0
        score               = 0
        lastUpdateTime      = 0
        lastEatSoundTime    = 0
        gameSetupComplete   = false
        gameStarted         = false
        isPausedGame        = false
        scoreMultiplier     = 1
        hasUsedRevive       = false
        shieldActive        = false
        multiplierActive    = false
        multiplierTimeLeft  = 0
        hideMultiplierEffect()
        invincibleTimeLeft  = 0
        magnetActive        = false
        magnetTimeLeft      = 0
        hideMagnetEffect()
        ghostActive         = false
        ghostTimeLeft       = 0
        currentMoveSpeed    = baseMoveSpeed
        isBoostHeld         = false
        boostZoomExtra      = 0
        boostScoreDrainTimer = 0
        joystickTouch       = nil
        boostTouch          = nil
        joystickThumbOffset = .zero
        joystickEngagement  = 0
        frameCounter        = 0
        botUpdateAccumulator = 0
        botCollisionAccumulator = 0
        botHeadCheckAccumulator = 0
        botVisibilityUpdateTimer = 0
        leaderboardUpdateTimer = 0
        minimapUpdateTimer     = 0
        leaderArrowUpdateTimer = 0
        miniLeaderboardNeedsRefresh = true
        trailFoodTimer       = 0
        activeTrailFoodCount = 0
        tailWigglePhase      = 0
        // Initialise heatmap with a small uniform baseline so early food isn't purely central.
        movementHeatmap = Array(repeating: Array(repeating: 0.1, count: heatmapCols), count: heatmapRows)
        heatmapSampleTimer = 0
        heatmapDecayTimer  = 0
        mazeEscapeTimer      = 45
        mazeEscapeTarget     = .zero
        mazeBand             = 1
        mazeRoundInBand      = 1
        mazeMouseSpeedMultiplier = 1
        mazeRevealTimer      = 0
        mazeSlowFieldTimer   = 0
        mazePickupSpawnTimer = 0
        mazeNearMissTimer    = 0
        mazeBoostEnergy      = mazeBoostEnergyMax
        mazeCurrentSpecialRound = .none
        mazeSpecialRoundIndex = nil
        mazeBandsWithoutSpecial = 0
        mazeTutorialActive   = false
        mazeTutorialStep     = 0
        mazeTutorialProgress = 0
        raceCurrentCheckpoint = 0
        raceTimeRemaining    = 75
        raceIsFinished       = false

        removeAllChildren()
        bodySegments.removeAll()
        bodyPositionCache.removeAll()
        positionHistory.removeAll()
        playerBodyOccupancy.removeAll()
        playerBodyPathNode.removeFromParent()
        bots.removeAll()
        foodItems.removeAll()
        foodTypes.removeAll()
        foodSpatialGrid.removeAll()
        foodGridDirty = false
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
        hideSuperMouseHUD()
        superMouseCountdownLabel?.removeFromParent()
        superMouseCountdownLabel = nil
        superMouseState = .dormant
        superMouseTimer = 0
        superMouseNode?.removeFromParent()
        superMouseNode = nil
        superMouseHoleNode?.removeFromParent()
        superMouseHoleNode = nil
        mazeWalls.removeAll()
        mazeExits.removeAll()
        mazeSafeSpaces.removeAll()
        mazeMice.removeAll()
        mazePickups.removeAll()
        mazePickupKinds.removeAll()
        mazeMouseNode = nil
        mazeModeLabel = nil
        mazeObjectiveLabel = nil
        mazePickupStatusLabel = nil
        raceObstacles.removeAll()
        raceCheckpoints.removeAll()
        raceModeLabel = nil

        if gameMode == .challenge {
            backgroundColor = SKColor(red: 0.15, green: 0.05, blue: 0.05, alpha: 1.0)
        } else if isSnakeRaceMode {
            backgroundColor = SKColor(red: 0.06, green: 0.18, blue: 0.20, alpha: 1.0)
        } else {
            backgroundColor = SKColor(red: 0.09, green: 0.13, blue: 0.11, alpha: 1.0)
        }
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
        createComboHUD()
        createMiniLeaderboard()
        createMinimap()
        createLeaderArrow()
        createSuperMouseCountdownLabel()
        if isSnakeRaceMode {
            createSnakeRaceModeContent()
        }
        createJoystick()
        createBoostButton()
        if !isSpecialOfflineMode {
            spawnInitialFood()
        } else {
            boostButtonNode?.alpha = 0.5
        }
        updateScoreDisplay()

        if !isSpecialOfflineMode {
            spawnBots()
        }
        updateMiniLeaderboard()

        gameSetupComplete = true
        prewarmTrailFoodTextures()   // build SKTexture cache before first trail spawn
        prewarmFoodTextures()        // pre-render all emoji/icon food textures
        startGameImmediately()

        let playerTheme = snakeColorThemes[selectedSnakeColorIndex % snakeColorThemes.count]
        animateSnakeEntrance(head: snakeHead, body: bodySegments, angle: currentAngle, accent: playerTheme.bodySKColor)
    }

    // MARK: - Arena Border
    func createArenaBorder() {
        // Arena background fill
        let arenaBg = SKShapeNode(rect: CGRect(x: 0, y: 0, width: worldSize, height: worldSize))
        let isChallengeMode = gameMode == .challenge
        if isSnakeRaceMode {
            arenaBg.fillColor = SKColor(red: 0.10, green: 0.32, blue: 0.34, alpha: 1.0)
        } else if isChallengeMode {
            arenaBg.fillColor = SKColor(red: 0.28, green: 0.10, blue: 0.10, alpha: 1.0)
        } else {
            arenaBg.fillColor = SKColor(red: 0.10, green: 0.22, blue: 0.14, alpha: 1.0)
        }
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
            if isSnakeRaceMode {
                band.fillColor = bandIndex.isMultiple(of: 2)
                    ? SKColor(red: 0.16, green: 0.62, blue: 0.62, alpha: 0.16)
                    : SKColor(red: 0.07, green: 0.34, blue: 0.38, alpha: 0.14)
            } else {
                band.fillColor = bandIndex.isMultiple(of: 2)
                    ? (isChallengeMode ? SKColor(red: 0.65, green: 0.16, blue: 0.12, alpha: 0.30) : SKColor(red: 0.30, green: 0.45, blue: 0.58, alpha: 0.22))
                    : (isChallengeMode ? SKColor(red: 0.18, green: 0.05, blue: 0.04, alpha: 0.26) : SKColor(red: 0.14, green: 0.24, blue: 0.34, alpha: 0.18))
            }
        }

        // Ambient glow orbs — larger, brighter, with an outer soft ring for depth
        let glowData: [(CGPoint, CGFloat)] = [
            (CGPoint(x: worldSize * 0.22, y: worldSize * 0.24), 340),
            (CGPoint(x: worldSize * 0.78, y: worldSize * 0.30), 270),
            (CGPoint(x: worldSize * 0.36, y: worldSize * 0.74), 300),
            (CGPoint(x: worldSize * 0.74, y: worldSize * 0.82), 260),
            // Extra orbs for visual richness
            (CGPoint(x: worldSize * 0.50, y: worldSize * 0.50), 420),
            (CGPoint(x: worldSize * 0.12, y: worldSize * 0.65), 200),
            (CGPoint(x: worldSize * 0.88, y: worldSize * 0.55), 210),
        ]
        for (index, (center, radius)) in glowData.enumerated() {
            let isLarge = index.isMultiple(of: 2)
            // Outer soft halo
            let halo = SKShapeNode(circleOfRadius: radius * 1.6)
            halo.position = center
            halo.fillColor = isLarge
                ? (isChallengeMode ? SKColor(red: 0.80, green: 0.18, blue: 0.10, alpha: 0.06) : SKColor(red: 0.30, green: 0.60, blue: 0.80, alpha: 0.04))
                : (isChallengeMode ? SKColor(red: 0.55, green: 0.08, blue: 0.08, alpha: 0.07) : SKColor(red: 0.20, green: 0.45, blue: 0.65, alpha: 0.05))
            halo.strokeColor = .clear
            halo.zPosition = -10.9
            addChild(halo)

            // Inner vivid glow
            let glow = SKShapeNode(circleOfRadius: radius)
            glow.position = center
            glow.fillColor = isLarge
                ? (isChallengeMode ? SKColor(red: 0.98, green: 0.35, blue: 0.18, alpha: 0.20) : SKColor(red: 0.45, green: 0.72, blue: 0.90, alpha: 0.13))
                : (isChallengeMode ? SKColor(red: 0.65, green: 0.12, blue: 0.12, alpha: 0.22) : SKColor(red: 0.28, green: 0.55, blue: 0.75, alpha: 0.14))
            glow.strokeColor = isLarge
                ? (isChallengeMode ? SKColor(red: 1.0, green: 0.45, blue: 0.20, alpha: 0.10) : SKColor(red: 0.55, green: 0.85, blue: 1.0, alpha: 0.08))
                : .clear
            glow.lineWidth   = 1.5
            glow.glowWidth   = isLarge ? 24 : 14
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
            ? SKColor(red: 1.0, green: 0.42, blue: 0.30, alpha: 0.18)
            : SKColor(red: 0.72, green: 0.90, blue: 1.0, alpha: 0.16)
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
            ? SKColor(red: 0.90, green: 0.28, blue: 0.18, alpha: 0.38)
            : SKColor(red: 0.40, green: 0.72, blue: 1.0, alpha: 0.28)
        accentGrid.lineWidth = 2
        accentGrid.glowWidth = isChallengeMode ? 3 : 2
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
        dots.fillColor   = isChallengeMode
            ? SKColor(red: 1.0, green: 0.58, blue: 0.40, alpha: 0.30)
            : SKColor(red: 0.80, green: 0.95, blue: 1.0, alpha: 0.26)
        dots.strokeColor = .clear
        dots.zPosition   = -10
        addChild(dots)
    }

    // MARK: - Snake Race
    func createSnakeRaceModeContent() {
        raceTimeRemaining = 80
        createRaceObstaclesAndCheckpoints()

        let label = SKLabelNode(fontNamed: "Arial-BoldMT")
        label.fontSize = 18
        label.fontColor = SKColor(red: 0.60, green: 0.95, blue: 0.95, alpha: 1)
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: worldSize / 2, y: worldSize / 2 + 540)
        label.zPosition = 610
        addChild(label)
        raceModeLabel = label
        updateRaceHUD()
    }

    func createRaceObstaclesAndCheckpoints() {
        let center = CGPoint(x: worldSize / 2, y: worldSize / 2)
        let obstacleRects: [CGRect] = [
            CGRect(x: center.x - 320, y: center.y + 320, width: 640, height: 34),
            CGRect(x: center.x - 500, y: center.y + 100, width: 420, height: 34),
            CGRect(x: center.x + 80, y: center.y + 100, width: 420, height: 34),
            CGRect(x: center.x - 380, y: center.y - 120, width: 760, height: 34),
            CGRect(x: center.x - 500, y: center.y - 340, width: 400, height: 34),
            CGRect(x: center.x + 120, y: center.y - 340, width: 400, height: 34)
        ]

        raceObstacles = obstacleRects.map { rect in
            let obstacle = SKShapeNode(rect: rect, cornerRadius: 10)
            obstacle.fillColor = SKColor(red: 0.06, green: 0.75, blue: 0.75, alpha: 0.75)
            obstacle.strokeColor = SKColor(red: 0.6, green: 1.0, blue: 1.0, alpha: 0.9)
            obstacle.glowWidth = 7
            obstacle.zPosition = 120
            addChild(obstacle)
            return obstacle
        }

        let checkpoints: [CGPoint] = [
            CGPoint(x: center.x, y: center.y + 470),
            CGPoint(x: center.x - 470, y: center.y + 10),
            CGPoint(x: center.x + 470, y: center.y - 210),
            CGPoint(x: center.x, y: center.y - 470)
        ]

        raceCheckpoints = checkpoints.enumerated().map { index, point in
            let ring = SKShapeNode(circleOfRadius: 54)
            ring.position = point
            ring.fillColor = .clear
            ring.strokeColor = index == 0 ? SKColor(red: 1.0, green: 0.92, blue: 0.32, alpha: 1) : SKColor(red: 0.55, green: 0.65, blue: 0.65, alpha: 0.6)
            ring.lineWidth = 6
            ring.glowWidth = index == 0 ? 12 : 0
            ring.zPosition = 115
            addChild(ring)
            return ring
        }
    }

    func updateRaceHUD() {
        raceModeLabel?.text = "Snake Race · CP \(min(raceCurrentCheckpoint + 1, raceCheckpoints.count))/\(max(1, raceCheckpoints.count)) · Time: \(Int(max(0, raceTimeRemaining)))"
    }
    // MARK: - Countdown
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
        let boostZoomTarget: CGFloat = isBoostHeld ? 0.12 : 0
        boostZoomExtra += (boostZoomTarget - boostZoomExtra) * 0.08
        let desiredScale = desiredCameraScale() + boostZoomExtra
        let newScale = cameraNode.xScale + (desiredScale - cameraNode.xScale) * 0.08
        cameraNode.setScale(newScale)

        let extents = cameraHalfExtents(using: newScale)
        let halfW = extents.halfW
        let halfH = extents.halfH
        let clampedX = max(halfW, min(worldSize - halfW, snakeHead.position.x))
        let clampedY = max(halfH, min(worldSize - halfH, snakeHead.position.y))
        cameraNode.position = CGPoint(x: clampedX, y: clampedY)
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
            let blendedAngle = isSnakeRaceMode
                ? shortestAngleLerp(from: currentAngle, to: angle, blend: 0.55 + 0.35 * normalized)
                : angle
            targetAngle = blendedAngle
            isTouching  = true
            joystickThumbNode?.alpha = 0.92
        } else {
            isTouching = false
            joystickThumbNode?.alpha = 0.72
        }
    }

    func resetJoystick() {
        joystickThumbOffset = .zero
        joystickEngagement  = 0
        joystickThumbNode?.run(SKAction.move(to: joystickCenter, duration: 0.12))
        isTouching    = false
        joystickTouch = nil
    }

    func shortestAngleLerp(from: CGFloat, to: CGFloat, blend: CGFloat) -> CGFloat {
        let delta = atan2(sin(to - from), cos(to - from))
        return from + delta * max(0, min(1, blend))
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

    func collidesWithShapeWalls(_ walls: [SKShapeNode], padding: CGFloat = 8) -> Bool {
        walls.contains { wall in
            wall.frame.insetBy(dx: -padding, dy: -padding).contains(snakeHead.position)
        }
    }

    func runModeImpactVFX(color: SKColor) {
        let ring = SKShapeNode(circleOfRadius: 14)
        ring.position = snakeHead.position
        ring.strokeColor = color
        ring.lineWidth = 4
        ring.glowWidth = 10
        ring.zPosition = 700
        addChild(ring)
        ring.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 5.0, duration: 0.28),
                SKAction.fadeOut(withDuration: 0.28)
            ]),
            SKAction.removeFromParent()
        ]))
    }

    func updateSnakeRaceMode(dt: CGFloat) {
        guard isSnakeRaceMode, !raceIsFinished else { return }
        raceTimeRemaining -= dt
        updateRaceHUD()

        if collidesWithShapeWalls(raceObstacles, padding: 16) {
            score = max(0, score - 3)
            updateScoreDisplay()
            runModeImpactVFX(color: .cyan)
            snakeHead.position.x -= cos(currentAngle) * 26
            snakeHead.position.y -= sin(currentAngle) * 26
        }

        if raceCurrentCheckpoint < raceCheckpoints.count {
            let checkpoint = raceCheckpoints[raceCurrentCheckpoint]
            let distance = hypot(snakeHead.position.x - checkpoint.position.x, snakeHead.position.y - checkpoint.position.y)
            if distance < 70 {
                checkpoint.strokeColor = SKColor(red: 0.22, green: 0.95, blue: 0.45, alpha: 1)
                checkpoint.glowWidth = 16
                score += 20
                updateScoreDisplay()
                raceCurrentCheckpoint += 1
                if raceCurrentCheckpoint < raceCheckpoints.count {
                    raceCheckpoints[raceCurrentCheckpoint].strokeColor = SKColor(red: 1.0, green: 0.92, blue: 0.32, alpha: 1)
                    raceCheckpoints[raceCurrentCheckpoint].glowWidth = 12
                } else {
                    raceIsFinished = true
                    let timeBonusCap: Int = 40
                    let timeBonus = min(timeBonusCap, Int(max(0, raceTimeRemaining) * 0.5))
                    score += timeBonus
                    spawnFloatingText("⏱ Time Bonus +\(timeBonus)!", at: snakeHead.position)
                    updateScoreDisplay()
                    runModeImpactVFX(color: .green)
                    completeSpecialMode(success: true)
                }
                updateRaceHUD()
            }
        }

        if raceTimeRemaining <= 0 {
            completeSpecialMode(success: false)
        }
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
        comboCount = 0; comboTimer = 0; updateComboDisplay()
        spawnDeathFood(at: bodyPositionCache,
                       colorIndex: selectedSnakeColorIndex,
                       patternIndex: selectedSnakePatternIndex)   // body scatters as death food
        lastPlayerPosition = snakeHead.position
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        spawnDeathParticles(at: snakeHead.position)

        run(deathAction) { [weak self] in
            self?.stopBackgroundMusic()
            self?.showGameOverScreen()
        }
    }

    func completeSpecialMode(success: Bool) {
        guard !isGameOver else { return }
        isGameOver = true
        isBoostHeld = false
        boostTouch = nil
        setBoostButtonActive(false)
        if success {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        run(SKAction.wait(forDuration: 0.25)) { [weak self] in
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

    func showMultiplierEffect() {
        guard snakeHead != nil, snakeHead.childNode(withName: "multiplierGlow") == nil else { return }
        let glow = SKShapeNode(circleOfRadius: headRadius + 8)
        glow.fillColor   = SKColor(red: 1.0, green: 0.85, blue: 0.1, alpha: 0.18)
        glow.strokeColor = SKColor(red: 1.0, green: 0.9, blue: 0.2, alpha: 0.90)
        glow.lineWidth   = 2.5
        glow.glowWidth   = 16
        glow.position    = .zero
        glow.zPosition   = -1
        glow.name        = "multiplierGlow"
        glow.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.group([SKAction.scale(to: 1.2, duration: 0.5),
                            SKAction.fadeAlpha(to: 0.38, duration: 0.5)]),
            SKAction.group([SKAction.scale(to: 0.9, duration: 0.5),
                            SKAction.fadeAlpha(to: 0.16, duration: 0.5)])
        ])))
        snakeHead.addChild(glow)
    }

    func hideMultiplierEffect() {
        snakeHead?.childNode(withName: "multiplierGlow")?.removeFromParent()
    }

    func showMagnetEffect() {
        guard snakeHead != nil, snakeHead.childNode(withName: "magnetGlow") == nil else { return }
        let glow = SKShapeNode(circleOfRadius: headRadius + 10)
        glow.fillColor   = SKColor(red: 0.6, green: 0.1, blue: 0.9, alpha: 0.15)
        glow.strokeColor = SKColor(red: 0.75, green: 0.2, blue: 1.0, alpha: 0.85)
        glow.lineWidth   = 2.0
        glow.glowWidth   = 12
        glow.position    = .zero
        glow.zPosition   = -1
        glow.name        = "magnetGlow"
        glow.run(SKAction.repeatForever(SKAction.rotate(byAngle: .pi * 2, duration: 1.5)))
        snakeHead.addChild(glow)
    }

    func hideMagnetEffect() {
        snakeHead?.childNode(withName: "magnetGlow")?.removeFromParent()
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

    // MARK: - Floating Score Text
    func spawnFloatingText(_ text: String, at position: CGPoint, color: SKColor = SKColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0)) {
        let label = SKLabelNode(fontNamed: "Arial-BoldMT")
        label.text                    = text
        label.fontSize                = 24
        label.fontColor               = color
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

    // MARK: - Nemesis Banner
    func spawnNemesisBanner() {
        guard let cam = camera else {
            spawnFloatingText("⚠️ NEMESIS HAS ARRIVED", at: CGPoint(x: snakeHead.position.x, y: snakeHead.position.y + 120),
                              color: SKColor(red: 1.0, green: 0.18, blue: 0.18, alpha: 1.0))
            return
        }
        let bg = SKShapeNode(rectOf: CGSize(width: size.width, height: 64), cornerRadius: 8)
        bg.fillColor   = SKColor(red: 0.12, green: 0, blue: 0, alpha: 0.88)
        bg.strokeColor = SKColor(red: 0.88, green: 0.18, blue: 0.18, alpha: 1.0)
        bg.lineWidth   = 2
        bg.glowWidth   = 8
        bg.zPosition   = 900
        let lbl = SKLabelNode(fontNamed: "Arial-BoldMT")
        lbl.text                    = "  NEMESIS HAS ARRIVED  "
        lbl.fontSize                = 28
        lbl.fontColor               = SKColor(red: 1.0, green: 0.25, blue: 0.25, alpha: 1.0)
        lbl.horizontalAlignmentMode = .center
        lbl.verticalAlignmentMode   = .center
        bg.addChild(lbl)
        bg.position = CGPoint(x: 0, y: size.height / 2 + 64)
        cam.addChild(bg)
        bg.run(SKAction.sequence([
            SKAction.moveTo(y: size.height * 0.28, duration: 0.35),
            SKAction.wait(forDuration: 1.8),
            SKAction.moveTo(y: -(size.height / 2 + 64), duration: 0.40),
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

        // All head variants share a container so we can attach shadow + highlight to both.
        let container = SKNode()
        container.position = spawnPos

        // Drop shadow — offset ellipse drawn behind everything else.
        let shadow = SKShapeNode(ellipseOf: CGSize(width: headRadius * 2.4, height: headRadius * 1.4))
        shadow.fillColor   = SKColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.45)
        shadow.strokeColor = .clear
        shadow.position    = CGPoint(x: 2, y: -4)
        shadow.zPosition   = -1
        container.addChild(shadow)

        if let image = playerHeadImage {
            let ring = SKShapeNode(circleOfRadius: headRadius + 2)
            ring.fillColor   = theme.headSKColor
            ring.strokeColor = theme.headStrokeSKColor
            ring.lineWidth   = 2
            ring.glowWidth   = 10
            container.addChild(ring)

            let texture = SKTexture(image: cropToCircle(image: image, size: CGSize(width: 40, height: 40)))
            let sprite  = SKSpriteNode(texture: texture)
            sprite.size      = CGSize(width: headRadius * 2, height: headRadius * 2)
            sprite.zPosition = 1
            container.addChild(sprite)
        } else {
            // Outer glow ring
            let glowRing = SKShapeNode(circleOfRadius: headRadius + 3)
            glowRing.fillColor   = .clear
            glowRing.strokeColor = theme.headSKColor.withAlphaComponent(0.55)
            glowRing.lineWidth   = 3
            glowRing.glowWidth   = 10
            glowRing.zPosition   = -0.5
            container.addChild(glowRing)

            // Main head circle
            let shape = SKShapeNode(circleOfRadius: headRadius)
            shape.fillColor   = theme.headSKColor
            shape.strokeColor = theme.headStrokeSKColor
            shape.lineWidth   = 2.0
            shape.glowWidth   = 6
            container.addChild(shape)

            // Inner sheen — slightly lighter circle to simulate curved surface
            let sheen = SKShapeNode(circleOfRadius: headRadius * 0.72)
            sheen.fillColor   = theme.headSKColor.withAlphaComponent(0.18)
            sheen.strokeColor = .clear
            sheen.position    = CGPoint(x: -1, y: 1)
            sheen.zPosition   = 0.5
            container.addChild(sheen)

            addEyes(to: container)

            // Specular highlight — small white circle offset toward top-left
            let highlight = SKShapeNode(circleOfRadius: headRadius * 0.28)
            highlight.fillColor   = SKColor(white: 1.0, alpha: 0.55)
            highlight.strokeColor = .clear
            highlight.position    = CGPoint(x: -headRadius * 0.38, y: headRadius * 0.42)
            highlight.zPosition   = 2
            container.addChild(highlight)
        }

        addChild(container)
        snakeHead = container
        lastPlayerPosition = spawnPos
    }

    // MARK: - Eyes
    func addEyes(to head: SKNode) {
        let theme = snakeColorThemes[normalizedSnakeColorIndex(selectedSnakeColorIndex)]
        for xOffset: CGFloat in [-4.5, 4.5] {
            // White sclera
            let eye = SKShapeNode(circleOfRadius: 3.5)
            eye.fillColor   = SKColor(white: 0.96, alpha: 1.0)
            eye.strokeColor = SKColor(white: 0.55, alpha: 0.4)
            eye.lineWidth   = 0.5
            eye.position    = CGPoint(x: xOffset, y: 5.5)
            eye.zPosition   = 1

            // Coloured iris ring
            let iris = SKShapeNode(circleOfRadius: 2.3)
            iris.fillColor   = theme.headSKColor.withAlphaComponent(0.85)
            iris.strokeColor = .clear
            iris.position    = CGPoint(x: 0.25, y: 0.25)
            eye.addChild(iris)

            // Dark pupil
            let pupil = SKShapeNode(circleOfRadius: 1.4)
            pupil.fillColor   = SKColor(white: 0.05, alpha: 1.0)
            pupil.strokeColor = .clear
            pupil.position    = CGPoint(x: 0.25, y: 0.25)
            eye.addChild(pupil)

            // Tiny specular dot on pupil
            let dot = SKShapeNode(circleOfRadius: 0.55)
            dot.fillColor   = SKColor(white: 1.0, alpha: 0.9)
            dot.strokeColor = .clear
            dot.position    = CGPoint(x: -0.4, y: 0.55)
            eye.addChild(dot)

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

        bodySegments.removeAll(keepingCapacity: true)
        for index in 0..<initialBodyCount {
            let segment = acquireBodySegmentNode(segIndex: index)
            segment.position = CGPoint(x: spawnPos.x - CGFloat(index + 1) * segmentPixelSpacing, y: spawnPos.y)
            addChild(segment)
            bodySegments.append(segment)
        }

        ensurePointCacheLength(bodySegments.count, cache: &bodyPositionCache)
        for i in 0..<bodySegments.count {
            bodyPositionCache[i] = CGPoint(x: spawnPos.x - CGFloat(i + 1) * segmentPixelSpacing, y: spawnPos.y)
        }

        configurePlayerBodyPathNodeIfNeeded()
        updatePlayerBodyPathAndCollisionSet()
    }

    func addBodySegment() {
        let segment = acquireBodySegmentNode(segIndex: bodySegments.count)
        segment.position = bodySegments.last?.position ?? snakeHead.position
        addChild(segment)
        bodySegments.append(segment)
        ensurePointCacheLength(bodySegments.count, cache: &bodyPositionCache)
        let fallback = bodyPositionCache.dropLast().last ?? snakeHead.position
        bodyPositionCache[bodySegments.count - 1] = fallback
        positionHistory.setCapacity(historyCapacity(forSegmentCount: bodySegments.count))
        updatePlayerBodyVisuals()
    }

    /// Grow or shrink the player body to match targetBodyCount.
    /// Called on every score change so boost drain also shrinks the snake.
    func syncSnakeLength() {
        let target = targetBodyCount
        while bodySegments.count < target {
            let segment = acquireBodySegmentNode(segIndex: bodySegments.count)
            segment.position = bodySegments.last?.position ?? snakeHead.position
            addChild(segment)
            bodySegments.append(segment)
        }
        while bodySegments.count > target && bodySegments.count > 1 {
            releaseBodySegmentNode(bodySegments.removeLast())
        }
        ensurePointCacheLength(bodySegments.count, cache: &bodyPositionCache)
        positionHistory.setCapacity(historyCapacity(forSegmentCount: bodySegments.count))
        updatePlayerBodyVisuals()
    }

    private func configurePlayerBodyPathNodeIfNeeded() {
        if playerBodyPathNode.parent == nil {
            let theme = snakeColorThemes[normalizedSnakeColorIndex(selectedSnakeColorIndex)]
            playerBodyPathNode.strokeColor = theme.bodySKColor.withAlphaComponent(0.26)
            playerBodyPathNode.lineWidth = bodySegmentRadius * 2
            playerBodyPathNode.lineCap = .round
            playerBodyPathNode.lineJoin = .round
            playerBodyPathNode.fillColor = .clear
            playerBodyPathNode.glowWidth = selectedSnakePattern == .neon ? 10 : 2
            playerBodyPathNode.zPosition = snakeHead.zPosition - 0.2
            addChild(playerBodyPathNode)
        }
    }

    func updatePlayerBodyPathAndCollisionSet() {
        let path = CGMutablePath()
        if let first = bodyPositionCache.first {
            path.move(to: first)
            // Rendering every point in a very long body can tank SKShapeNode performance.
            // Keep collision data at full resolution, but downsample only the drawn path.
            let maxRenderedPoints = 260
            let renderStep = max(1, bodyPositionCache.count / maxRenderedPoints)
            var index = renderStep
            while index < bodyPositionCache.count {
                path.addLine(to: bodyPositionCache[index])
                index += renderStep
            }
            if let last = bodyPositionCache.last,
               bodyPositionCache.count > 1,
               bodyPositionCache[(bodyPositionCache.count - 1) / renderStep * renderStep] != last {
                path.addLine(to: last)
            }
        }
        playerBodyPathNode.path = path
        updatePlayerBodyVisuals()

        // Only rebuild every 2nd frame: checkBotHeadsHitPlayerBody() also runs on even frames,
        // so the set is always fresh when it is actually consumed.
        if frameCounter % 2 == 0 {
            playerBodyOccupancy.removeAll(keepingCapacity: true)
            for point in bodyPositionCache {
                let cell = gridCell(for: point)
                playerBodyOccupancy.insert(cell)
            }
        }
    }

    // Larger cell size reduces Set inserts: with 30 px cells and 14 px segment spacing,
    // consecutive segments share cells, so unique cell count drops ~3–4×.
    // The ±1-cell neighbourhood check still covers ±30 px, which comfortably exceeds
    // the 22 px combined collision radius (collisionRadius + bodySegmentRadius).
    private let occupancyCellSize: CGFloat = 30.0

    func gridCell(for point: CGPoint) -> GridCell {
        GridCell(x: Int(point.x / occupancyCellSize), y: Int(point.y / occupancyCellSize))
    }

    // MARK: - Super Mouse

    // MARK: Super Mouse HUD

    /// Shows a bold banner + creates screen-edge arrow + minimap dot when mouse spawns.
    func showSuperMouseAlert() {
        let cam = cameraNode
        let zoom = cameraScale()
        let halfW = size.width  * zoom / 2
        let halfH = size.height * zoom / 2

        // --- Banner ---
        let banner = SKNode()
        banner.zPosition = 510
        banner.name = "superMouseBanner"

        let bg = SKShapeNode(rectOf: CGSize(width: 320 * zoom, height: 46 * zoom),
                             cornerRadius: 12 * zoom)
        bg.fillColor = SKColor(red: 0.10, green: 0.07, blue: 0.02, alpha: 0.88)
        bg.strokeColor = SKColor(red: 1.0, green: 0.82, blue: 0.18, alpha: 0.9)
        bg.lineWidth = 1.5 * zoom
        bg.glowWidth = 6 * zoom
        banner.addChild(bg)

        let lbl = SKLabelNode(fontNamed: "Arial-BoldMT")
        lbl.text = "🐭  SUPER MOUSE IS OUT!  +100pts"
        lbl.fontSize = 14 * zoom
        lbl.fontColor = SKColor(red: 1.0, green: 0.92, blue: 0.55, alpha: 1.0)
        lbl.verticalAlignmentMode = .center
        lbl.horizontalAlignmentMode = .center
        banner.addChild(lbl)

        // Position near top of screen in camera space
        banner.position = CGPoint(x: cam.position.x, y: cam.position.y + halfH - 90 * zoom)
        addChild(banner)

        // Animate: drop in, hold, fade out
        let dropIn  = SKAction.moveBy(x: 0, y: -14 * zoom, duration: 0.25)
        dropIn.timingMode = .easeOut
        let hold    = SKAction.wait(forDuration: 3.0)
        let fadeOut = SKAction.fadeOut(withDuration: 0.5)
        let remove  = SKAction.removeFromParent()
        banner.run(SKAction.sequence([dropIn, hold, fadeOut, remove]))

        // Pulse border to grab attention
        let pulseBorder = SKAction.sequence([
            SKAction.customAction(withDuration: 0) { node, _ in
                (node as? SKShapeNode)?.glowWidth = 14 * zoom
            },
            SKAction.wait(forDuration: 0.3),
            SKAction.customAction(withDuration: 0) { node, _ in
                (node as? SKShapeNode)?.glowWidth = 4 * zoom
            },
            SKAction.wait(forDuration: 0.3)
        ])
        bg.run(SKAction.repeat(pulseBorder, count: 4))

        // --- Screen-edge arrow ---
        createSuperMouseArrow()

        // --- Minimap dot ---
        createSuperMouseMinimapDot()

        // Countdown label is created at setup; just ensure it exists
        createSuperMouseCountdownLabel()
    }

    private func createSuperMouseArrow() {
        let node = SKNode()
        node.zPosition = 506
        node.isHidden = true
        node.name = "superMouseArrow"

        let ring = SKShapeNode(circleOfRadius: 16)
        ring.fillColor = SKColor(red: 0.10, green: 0.06, blue: 0.02, alpha: 0.55)
        ring.strokeColor = SKColor(red: 1.0, green: 0.82, blue: 0.18, alpha: 0.7)
        ring.lineWidth = 1.5
        node.addChild(ring)

        let arrowPath = CGMutablePath()
        arrowPath.move(to: CGPoint(x: 0, y: 13))
        arrowPath.addLine(to: CGPoint(x: 9, y: -8))
        arrowPath.addLine(to: CGPoint(x: 0, y: -3))
        arrowPath.addLine(to: CGPoint(x: -9, y: -8))
        arrowPath.closeSubpath()
        let arrow = SKShapeNode(path: arrowPath)
        arrow.fillColor = SKColor(red: 1.0, green: 0.82, blue: 0.18, alpha: 0.95)
        arrow.strokeColor = SKColor(red: 1.0, green: 0.94, blue: 0.62, alpha: 0.9)
        arrow.lineWidth = 1.0
        arrow.glowWidth = 5
        node.addChild(arrow)

        let emoji = SKLabelNode(text: "🐭")
        emoji.fontSize = 13
        emoji.verticalAlignmentMode = .center
        emoji.horizontalAlignmentMode = .center
        emoji.position = CGPoint(x: 0, y: -1)
        node.addChild(emoji)

        addChild(node)
        superMouseArrowNode = node
    }

    private func createSuperMouseMinimapDot() {
        guard let minimap = minimapNode else { return }
        let dot = SKShapeNode(circleOfRadius: 4)
        dot.fillColor = SKColor(red: 1.0, green: 0.85, blue: 0.15, alpha: 1.0)
        dot.strokeColor = SKColor(red: 1.0, green: 1.0, blue: 0.6, alpha: 0.9)
        dot.lineWidth = 1.0
        dot.glowWidth = 5
        dot.zPosition = 10
        dot.name = "superMouseMinimapDot"
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.5, duration: 0.4),
            SKAction.scale(to: 0.8, duration: 0.4)
        ])
        dot.run(SKAction.repeatForever(pulse))
        minimap.addChild(dot)
        superMouseMinimapDot = dot
    }

    func createSuperMouseCountdownLabel() {
        guard superMouseCountdownLabel == nil else { return }
        let zoom = cameraScale()
        let hw = size.width  * zoom / 2
        let hh = size.height * zoom / 2
        let lbl = SKLabelNode(fontNamed: "Arial-BoldMT")
        lbl.fontSize = 12 * zoom
        lbl.fontColor = SKColor(red: 1.0, green: 0.82, blue: 0.2, alpha: 0.9)
        lbl.horizontalAlignmentMode = .right
        lbl.verticalAlignmentMode = .top
        lbl.position = CGPoint(x: cameraNode.position.x + hw - 18 * zoom,
                               y: cameraNode.position.y + hh - 50 * zoom)
        lbl.zPosition = 508
        lbl.isHidden = true
        lbl.name = "superMouseCountdown"
        addChild(lbl)
        superMouseCountdownLabel = lbl
    }

    func hideSuperMouseHUD() {
        superMouseArrowNode?.removeFromParent()
        superMouseArrowNode = nil
        superMouseMinimapDot?.removeFromParent()
        superMouseMinimapDot = nil
        // Keep countdown label alive — it shows the "in Xs" dormant hint
    }

    func updateSuperMouseHUD() {
        let isVisible = superMouseState == .active || superMouseState == .trapped

        // --- Minimap dot position ---
        if let dot = superMouseMinimapDot, isVisible {
            let mapSize: CGFloat = 118
            let world = CGFloat(worldSize)
            dot.position = CGPoint(
                x: (superMousePosition.x / world - 0.5) * mapSize,
                y: (superMousePosition.y / world - 0.5) * mapSize
            )
            dot.isHidden = false
        } else {
            superMouseMinimapDot?.isHidden = true
        }

        // --- Screen-edge arrow ---
        guard let arrowNode = superMouseArrowNode else { return }
        guard isVisible else { arrowNode.isHidden = true; return }

        let zoom  = cameraScale()
        let halfW = size.width  * zoom / 2
        let halfH = size.height * zoom / 2
        let dx = superMousePosition.x - cameraNode.position.x
        let dy = superMousePosition.y - cameraNode.position.y
        let inView = abs(dx) <= halfW - 60 && abs(dy) <= halfH - 90

        if inView {
            arrowNode.isHidden = true
        } else {
            arrowNode.isHidden = false
            let angle = atan2(dy, dx)
            arrowNode.zRotation = angle - .pi / 2
            // Clamp to screen edge
            let edgeX = cameraNode.position.x + max(-halfW + 36, min(halfW - 36, cos(angle) * halfW * 0.88))
            let edgeY = cameraNode.position.y + max(-halfH + 36, min(halfH - 36, sin(angle) * halfH * 0.88))
            arrowNode.position = CGPoint(x: edgeX, y: edgeY)
        }

        // --- Countdown / "Coming soon" hint ---
        if let cntLabel = superMouseCountdownLabel {
            let zoom2 = cameraScale()
            let hw = size.width * zoom2 / 2
            let hh = size.height * zoom2 / 2
            cntLabel.position = CGPoint(x: cameraNode.position.x + hw - 18 * zoom2,
                                        y: cameraNode.position.y + hh - 50 * zoom2)

            if isVisible {
                // Active: show escape countdown
                let timeLeft = max(0, superMouseActiveLimit - superMouseTimer)
                let secs = Int(ceil(timeLeft))
                cntLabel.text = "🐭 \(secs)s"
                cntLabel.fontColor = secs <= 5
                    ? SKColor(red: 1.0, green: 0.35, blue: 0.3, alpha: 1.0)
                    : SKColor(red: 1.0, green: 0.82, blue: 0.2, alpha: 0.9)
                cntLabel.isHidden = false
            } else if superMouseState == .dormant {
                // Dormant: show "coming soon" hint in last 20s
                let remaining = superMouseSpawnInterval - superMouseTimer
                if remaining <= 20 {
                    let secs = Int(ceil(remaining))
                    cntLabel.text = "🐭 in \(secs)s"
                    cntLabel.fontColor = SKColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 0.55)
                    cntLabel.isHidden = false
                } else {
                    cntLabel.isHidden = true
                }
            } else {
                cntLabel.isHidden = true
            }
        }
    }

    func spawnMouseHole() {
        // Pick a position at least 600pt from walls and 500pt from player
        var pos = CGPoint.zero
        let margin: CGFloat = 600
        for _ in 0..<30 {
            let candidate = CGPoint(
                x: CGFloat.random(in: arenaMinX + margin ... arenaMaxX - margin),
                y: CGFloat.random(in: arenaMinY + margin ... arenaMaxY - margin)
            )
            let dPlayer = hypot(snakeHead.position.x - candidate.x,
                                snakeHead.position.y - candidate.y)
            if dPlayer > 500 { pos = candidate; break }
        }
        if pos == .zero {
            pos = CGPoint(x: (arenaMinX + arenaMaxX) / 2 + CGFloat.random(in: -600...600),
                          y: (arenaMinY + arenaMaxY) / 2 + CGFloat.random(in: -600...600))
        }
        superMouseHolePosition = pos

        let hole = SKNode()
        // Outer dark shadow oval
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 90, height: 56))
        shadow.fillColor = SKColor(white: 0, alpha: 0.35)
        shadow.strokeColor = .clear
        shadow.zPosition = -0.5
        hole.addChild(shadow)
        // Concentric depth rings
        for (r, a) in [(36, 0.9), (26, 0.95), (16, 1.0)] as [(Int, Double)] {
            let ring = SKShapeNode(circleOfRadius: CGFloat(r))
            ring.fillColor = SKColor(white: 0, alpha: CGFloat(a))
            ring.strokeColor = SKColor(white: 0.08, alpha: 0.6)
            ring.lineWidth = 1.5
            ring.zPosition = CGFloat(r) / 10.0
            hole.addChild(ring)
        }
        // Pulsing inner dot (life indicator)
        let dot = SKShapeNode(circleOfRadius: 6)
        dot.fillColor = SKColor(red: 0.5, green: 0.3, blue: 0.1, alpha: 0.8)
        dot.strokeColor = .clear
        dot.zPosition = 5
        dot.name = "holeDot"
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.3, duration: 0.5),
            SKAction.scale(to: 0.8, duration: 0.5)
        ])
        dot.run(SKAction.repeatForever(pulse))
        hole.addChild(dot)

        hole.position = pos
        hole.setScale(0.01)
        hole.zPosition = 2
        addChild(hole)
        superMouseHoleNode = hole

        // Grow animation
        hole.run(SKAction.scale(to: 1.0, duration: 0.8))
    }

    func despawnMouseHole() {
        guard let hole = superMouseHoleNode else { return }
        hole.run(SKAction.sequence([
            SKAction.scale(to: 0.01, duration: 0.7),
            SKAction.removeFromParent()
        ]))
        superMouseHoleNode = nil
    }

    func beginMouseEmerge() {
        // Create mouse node at the hole, scale from 0
        let mouse = SuperMouseNode()
        mouse.position = superMouseHolePosition
        mouse.setScale(0.01)
        mouse.zPosition = 10
        addChild(mouse)
        superMouseNode = mouse
        superMousePosition = superMouseHolePosition
        superMouseAngle = CGFloat.random(in: 0 ..< .pi * 2)
        superMouseEmergeProgress = 0

        mouse.run(SKAction.scale(to: 1.0, duration: 0.6))
        showSuperMouseAlert()
    }

    func beginMouseRetreat() {
        // Visual: mouse node fades as it moves back to hole
        superMouseNode?.run(SKAction.sequence([
            SKAction.fadeOut(withDuration: 1.4),
            SKAction.removeFromParent()
        ]))
        hideSuperMouseHUD()
        showSuperMouseEscapedBanner()
    }

    private func showSuperMouseEscapedBanner() {
        let zoom = cameraScale()
        let halfH = size.height * zoom / 2

        let banner = SKNode()
        banner.zPosition = 510

        let bg = SKShapeNode(rectOf: CGSize(width: 280 * zoom, height: 40 * zoom),
                             cornerRadius: 10 * zoom)
        bg.fillColor = SKColor(red: 0.18, green: 0.04, blue: 0.04, alpha: 0.85)
        bg.strokeColor = SKColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 0.8)
        bg.lineWidth = 1.2 * zoom
        banner.addChild(bg)

        let lbl = SKLabelNode(fontNamed: "Arial-BoldMT")
        lbl.text = "🐭 The mouse got away!"
        lbl.fontSize = 13 * zoom
        lbl.fontColor = SKColor(red: 1.0, green: 0.65, blue: 0.55, alpha: 1.0)
        lbl.verticalAlignmentMode = .center
        lbl.horizontalAlignmentMode = .center
        banner.addChild(lbl)

        banner.position = CGPoint(x: cameraNode.position.x,
                                  y: cameraNode.position.y + halfH - 90 * zoom)
        addChild(banner)

        banner.run(SKAction.sequence([
            SKAction.wait(forDuration: 2.2),
            SKAction.fadeOut(withDuration: 0.4),
            SKAction.removeFromParent()
        ]))
    }

    // MARK: Super Mouse AI

    /// Returns the best escape heading and whether the mouse is trapped.
    func chooseSuperMouseHeading() -> (angle: CGFloat, isTrapped: Bool) {
        // --- Step 1: Snapshot nearby body segments (within 260pt) ---
        // Building once here avoids checking all segments inside the per-angle loop.
        var nearbyBodyPts: [CGPoint] = []
        nearbyBodyPts.reserveCapacity(80)
        let scanRadius: CGFloat  = 260
        let scanRadSq:  CGFloat  = scanRadius * scanRadius
        let blockR:     CGFloat  = 22   // treat a probe as "blocked" if within this of a body pt
        let blockRSq:   CGFloat  = blockR * blockR

        // Player body segments
        for pt in bodyPositionCache {
            let dx = pt.x - superMousePosition.x
            let dy = pt.y - superMousePosition.y
            if abs(dx) < scanRadius && abs(dy) < scanRadius && dx*dx + dy*dy < scanRadSq {
                nearbyBodyPts.append(pt)
            }
        }
        // Active bot body segments
        for i in 0..<bots.count where bots[i].isActive {
            for pt in bots[i].bodyPositionCache {
                let dx = pt.x - superMousePosition.x
                let dy = pt.y - superMousePosition.y
                if abs(dx) < scanRadius && abs(dy) < scanRadius && dx*dx + dy*dy < scanRadSq {
                    nearbyBodyPts.append(pt)
                }
            }
        }

        // Helper: is a world point blocked by any nearby body segment?
        func bodyBlocked(_ p: CGPoint) -> Bool {
            for pt in nearbyBodyPts {
                let dx = pt.x - p.x; let dy = pt.y - p.y
                if abs(dx) < blockR && abs(dy) < blockR && dx*dx + dy*dy < blockRSq { return true }
            }
            return false
        }

        // --- Step 2: Score 24 candidate angles ---
        let candidateStep: CGFloat = .pi / 12   // every 15°
        var bestAngle  = superMouseAngle
        var bestScore: CGFloat = -.infinity
        var blockedCount = 0
        let wallMargin: CGFloat = 100

        var candidate: CGFloat = 0
        while candidate < .pi * 2 {
            defer { candidate += candidateStep }

            let projected = GameLogic.projectedPoint(from: superMousePosition,
                                                     angle: candidate, distance: 100)

            // Hard reject: wall
            if projected.x < arenaMinX + wallMargin || projected.x > arenaMaxX - wallMargin
            || projected.y < arenaMinY + wallMargin || projected.y > arenaMaxY - wallMargin {
                blockedCount += 1; continue
            }

            // Hard reject: immediate body collision
            if bodyBlocked(projected) { blockedCount += 1; continue }

            var score: CGFloat = 0

            // Reward distance from player head
            score += hypot(snakeHead.position.x - projected.x,
                           snakeHead.position.y - projected.y) * 0.8

            // Reward distance from bot heads (within 500pt)
            for i in 0..<bots.count where bots[i].isActive {
                let bdx = bots[i].position.x - projected.x
                let bdy = bots[i].position.y - projected.y
                if abs(bdx) < 500 && abs(bdy) < 500 {
                    score += hypot(bdx, bdy) * 0.3
                }
            }

            // Turn efficiency — prefer not reversing direction
            var turnDiff = abs(candidate - superMouseAngle)
            while turnDiff > .pi { turnDiff = abs(turnDiff - 2 * .pi) }
            score -= turnDiff * 8

            // Multi-step look-ahead: 5 probes × 50pt — checks BOTH walls AND body
            var probe = projected
            var pathClear = true
            for step in 1...5 {
                probe = GameLogic.projectedPoint(from: probe, angle: candidate, distance: 50)
                let weight = CGFloat(6 - step)  // closer obstacle → heavier penalty

                let hitWall = probe.x < arenaMinX + wallMargin || probe.x > arenaMaxX - wallMargin
                           || probe.y < arenaMinY + wallMargin || probe.y > arenaMaxY - wallMargin
                if hitWall {
                    score -= 50 * weight
                    pathClear = false; break
                }
                if bodyBlocked(probe) {
                    score -= 65 * weight   // body walls penalised more than arena walls
                    pathClear = false; break
                }
                // Reward open distance from player along this path
                score += hypot(snakeHead.position.x - probe.x,
                               snakeHead.position.y - probe.y) * 0.10
            }
            if pathClear { score += 35 }  // bonus for a fully clear corridor

            if score > bestScore { bestScore = score; bestAngle = candidate }
        }

        // Trapped = 18+ of 24 directions blocked by walls OR body segments
        let isTrapped = blockedCount >= 18
        return (bestAngle, isTrapped)
    }

    // MARK: Super Mouse State Machine

    func updateSuperMouse(dt: CGFloat) {
        guard gameStarted, !isGameOver, !isPausedGame else { return }

        switch superMouseState {

        case .dormant:
            superMouseTimer += dt
            if superMouseTimer >= superMouseSpawnInterval {
                superMouseTimer = 0
                spawnMouseHole()
                superMouseState = .spawningHole
            }

        case .spawningHole:
            superMouseTimer += dt
            if superMouseTimer >= 1.5 {
                superMouseTimer = 0
                beginMouseEmerge()
                superMouseState = .emerging
            }

        case .emerging:
            superMouseTimer += dt
            superMouseEmergeProgress = min(superMouseTimer / 2.0, 1.0)
            // Move mouse slowly outward from hole as it emerges
            let emergeOffset: CGFloat = 40 * superMouseEmergeProgress
            superMousePosition = CGPoint(
                x: superMouseHolePosition.x + cos(superMouseAngle) * emergeOffset,
                y: superMouseHolePosition.y + sin(superMouseAngle) * emergeOffset
            )
            superMouseNode?.position = superMousePosition
            superMouseNode?.zRotation = superMouseAngle - .pi / 2
            superMouseNode?.update(dt: dt, speed: 0, state: .emerging)
            if superMouseEmergeProgress >= 1.0 {
                superMouseTimer = 0
                superMouseCurrentSpeed = superMouseBaseSpeed
                superMouseState = .active
            }

        case .active:
            superMouseTimer += dt
            if superMouseTimer >= superMouseActiveLimit {
                superMouseTimer = 0
                superMouseState = .retreating
                beginMouseRetreat()
                return
            }
            moveSuperMouse(dt: dt, state: .active)

        case .trapped:
            moveSuperMouse(dt: dt, state: .trapped)
            // Check if it escaped (replan will update state)

        case .caught:
            break   // handled by rewardSuperMouseCatch()

        case .retreating:
            superMouseTimer += dt
            // Lerp back to hole
            if let _ = superMouseHoleNode {
                let t = min(superMouseTimer * 1.2, 1.0)
                superMousePosition = CGPoint(
                    x: superMousePosition.x + (superMouseHolePosition.x - superMousePosition.x) * t * dt * 3,
                    y: superMousePosition.y + (superMouseHolePosition.y - superMousePosition.y) * t * dt * 3
                )
                superMouseNode?.position = superMousePosition
            }
            if superMouseTimer >= 1.6 {
                superMouseTimer = 0
                superMouseNode?.removeFromParent()
                superMouseNode = nil
                superMouseState = .despawning
                despawnMouseHole()
            }

        case .despawning:
            superMouseTimer += dt
            if superMouseTimer >= 1.0 {
                superMouseTimer = 0
                superMouseState = .dormant
            }
        }
    }

    private func moveSuperMouse(dt: CGFloat, state: SuperMouseState) {
        // AI replan every 0.08s
        superMouseReplanTimer += dt
        if superMouseReplanTimer >= 0.08 {
            superMouseReplanTimer = 0
            let result = chooseSuperMouseHeading()
            superMouseAngle = result.angle
            if state == .active && result.isTrapped {
                superMouseState = .trapped
            } else if state == .trapped && !result.isTrapped {
                superMouseState = .active
            }
        }

        // Speed boost when any snake head is very close
        var nearestThreatDist = hypot(snakeHead.position.x - superMousePosition.x,
                                      snakeHead.position.y - superMousePosition.y)
        for i in 0..<bots.count where bots[i].isActive {
            let d = hypot(bots[i].position.x - superMousePosition.x,
                          bots[i].position.y - superMousePosition.y)
            if d < nearestThreatDist { nearestThreatDist = d }
        }
        let speedMul: CGFloat = (nearestThreatDist < 200) ? 1.22 : (state == .trapped ? 0.60 : 1.0)
        superMouseCurrentSpeed = superMouseBaseSpeed * speedMul

        let dist = superMouseCurrentSpeed * dt
        superMousePosition = GameLogic.projectedPoint(from: superMousePosition,
                                                      angle: superMouseAngle,
                                                      distance: dist)
        // Clamp to arena
        superMousePosition.x = max(arenaMinX + 60, min(arenaMaxX - 60, superMousePosition.x))
        superMousePosition.y = max(arenaMinY + 60, min(arenaMaxY - 60, superMousePosition.y))

        superMouseNode?.position = superMousePosition
        superMouseNode?.zRotation = superMouseAngle - .pi / 2
        superMouseNode?.update(dt: dt, speed: superMouseCurrentSpeed, state: state)

        checkPlayerCatchesMouse()
        checkBotCatchesMouse()
    }

    private func checkBotCatchesMouse() {
        guard superMouseNode != nil else { return }
        let threshold: CGFloat = 13 + 18   // headRadius + mouseRadius
        for i in 0..<bots.count where bots[i].isActive {
            let dx = bots[i].position.x - superMousePosition.x
            let dy = bots[i].position.y - superMousePosition.y
            if abs(dx) < threshold && abs(dy) < threshold && hypot(dx, dy) < threshold {
                // Bot eats the mouse — smaller reward (20 pts nutrition), mouse escapes
                bots[i].score += 20
                spawnFloatingText("🐭 +20", at: superMousePosition,
                                  color: SKColor(red: 0.9, green: 0.7, blue: 0.2, alpha: 1.0))
                spawnEatParticles(at: superMousePosition)
                superMouseState = .retreating
                beginMouseRetreat()
                return
            }
        }
    }

    func checkPlayerCatchesMouse() {
        guard superMouseNode != nil else { return }
        let dist = hypot(snakeHead.position.x - superMousePosition.x,
                         snakeHead.position.y - superMousePosition.y)
        if dist < 13 + 18 {   // headRadius(13) + mouseBodyRadius(18)
            rewardSuperMouseCatch()
        }
    }

    func rewardSuperMouseCatch() {
        guard superMouseState == .active || superMouseState == .trapped else { return }
        superMouseState = .caught
        hideSuperMouseHUD()

        // Celebration animation
        superMouseNode?.run(SKAction.sequence([
            SKAction.scale(to: 1.7, duration: 0.15),
            SKAction.fadeOut(withDuration: 0.45),
            SKAction.removeFromParent()
        ]))
        superMouseNode = nil

        // Score
        score += 100
        spawnFloatingText("🐭 SUPER MOUSE +100!", at: superMousePosition,
                          color: SKColor(red: 1.0, green: 0.85, blue: 0.0, alpha: 1.0))
        spawnEatParticles(at: superMousePosition)
        updateScoreDisplay()
        updateSpeedForScore()

        // Super power: multiplier ×2 (10s) + ghost (6s)
        multiplierActive   = true
        multiplierTimeLeft = max(multiplierTimeLeft, 10.0)
        scoreMultiplier    = 2
        ghostActive        = true
        ghostTimeLeft      = max(ghostTimeLeft, 6.0)
        showMultiplierEffect()
        showGhostEffect()
        spawnFloatingText("⚡ SUPER POWER!", at: CGPoint(x: superMousePosition.x, y: superMousePosition.y + 70),
                          color: SKColor(red: 0.4, green: 1.0, blue: 1.0, alpha: 1.0))
        refreshPowerUpPanel()
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        // Despawn hole then reset to dormant
        let holeRef = superMouseHoleNode
        superMouseHoleNode = nil
        holeRef?.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.8),
            SKAction.scale(to: 0.01, duration: 0.5),
            SKAction.removeFromParent()
        ]))
        superMouseTimer = 0
        superMouseState = .dormant
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
        // Nemesis gets a brief ghost window after each shield hit so it can escape
        if bots[index].isNemesis {
            bots[index].ghostTimeLeft = max(bots[index].ghostTimeLeft, 2.0)
        }
        return true
    }

    func checkBotVsBotCollisions() {
        guard bots.count > 1 else { return }

        for i in 0..<(bots.count - 1) {
            guard bots[i].isActive, !bots[i].isDead, let headI = bots[i].head else { continue }
            var botIRespawned = false

            for j in (i + 1)..<bots.count {
                guard bots[j].isActive, !bots[j].isDead, let headJ = bots[j].head else { continue }
                guard botPairWithinBroadPhase(bots[i], bots[j]) else { continue }

                // Head-to-head collision (evaluated once per pair)
                if bots[i].ghostTimeLeft <= 0, bots[j].ghostTimeLeft <= 0 {
                    let d = hypot(headI.position.x - headJ.position.x,
                                  headI.position.y - headJ.position.y)
                    if d < (headRadius + headRadius) {
                        if !consumeBotShieldIfAvailable(i) {
                            respawnBot(i)
                            botIRespawned = true
                        }
                        if !consumeBotShieldIfAvailable(j) { respawnBot(j) }
                        break
                    }
                }

                // Head-to-body collisions (both directions)
                if bots[i].ghostTimeLeft <= 0,
                   !bots[j].bodyPositionCache.isEmpty,
                   headCollidesWithPoints(
                    headI.position,
                    points: bots[j].bodyPositionCache,
                    combinedRadius: collisionRadius + bodySegmentRadius,
                    skip: 1
                   ) {
                    if !consumeBotShieldIfAvailable(i) {
                        respawnBot(i)
                        botIRespawned = true
                    }
                    break
                }

                if bots[j].ghostTimeLeft <= 0,
                   !bots[i].bodyPositionCache.isEmpty,
                   headCollidesWithPoints(
                    headJ.position,
                    points: bots[i].bodyPositionCache,
                    combinedRadius: collisionRadius + bodySegmentRadius,
                    skip: 1
                   ) {
                    if !consumeBotShieldIfAvailable(j) { respawnBot(j) }
                }
            }

            if botIRespawned {
                continue
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
                if tappedNames.contains("reviveButton") {
                    revivePlayer()
                } else if tappedNames.contains("restartButton") {
                    restartGame()
                } else if tappedNames.contains("playAgainButton") {
                    shutdown()
                    onGameOver?(score)
                }
                continue
            }

            guard gameStarted, !isPausedGame else { continue }

            let controlScale = hudControlScale()
            let boostDist = hypot(loc.x - boostButtonCenter.x, loc.y - boostButtonCenter.y)
            let canBoost = score > 0
            if boostTouch == nil && boostDist < boostButtonRadius * 1.4 * controlScale && canBoost {
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
        let priorMultiplierSeconds = Int(ceil(max(0, multiplierTimeLeft)))
        let priorMagnetSeconds = Int(ceil(max(0, magnetTimeLeft)))
        let priorGhostSeconds = Int(ceil(max(0, ghostTimeLeft)))

        var shouldRefreshPowerUpPanel = false

        if invincibleTimeLeft > 0 {
            invincibleTimeLeft = max(0, invincibleTimeLeft - dt)
        }

        if multiplierActive {
            multiplierTimeLeft = max(0, multiplierTimeLeft - dt)
            if multiplierTimeLeft == 0 {
                multiplierActive = false
                scoreMultiplier = 1
                hideMultiplierEffect()
                shouldRefreshPowerUpPanel = true
            }
        }

        if magnetActive {
            magnetTimeLeft = max(0, magnetTimeLeft - dt)
            if magnetTimeLeft == 0 {
                magnetActive = false
                hideMagnetEffect()
                shouldRefreshPowerUpPanel = true
            }
        }

        if ghostActive {
            ghostTimeLeft = max(0, ghostTimeLeft - dt)
            if ghostTimeLeft == 0 {
                ghostActive = false
                hideGhostEffect()
                shouldRefreshPowerUpPanel = true
            }
        }

        let multiplierSecondsChanged = multiplierActive && Int(ceil(multiplierTimeLeft)) != priorMultiplierSeconds
        let magnetSecondsChanged = magnetActive && Int(ceil(magnetTimeLeft)) != priorMagnetSeconds
        let ghostSecondsChanged = ghostActive && Int(ceil(ghostTimeLeft)) != priorGhostSeconds

        if shouldRefreshPowerUpPanel || multiplierSecondsChanged || magnetSecondsChanged || ghostSecondsChanged {
            refreshPowerUpPanel()
        }
    }

    // MARK: - Game Loop
    override func update(_ currentTime: TimeInterval) {
        guard !isGameOver, gameSetupComplete, gameStarted, !isPausedGame else { return }
        readControllerInput()

        let frameDelta: CGFloat = lastUpdateTime == 0
            ? CGFloat(1.0 / 60.0)
            : CGFloat(max(0, currentTime - lastUpdateTime))
        let dt: CGFloat = min(frameDelta, CGFloat(maxDeltaTime))
        lastUpdateTime = currentTime

        // Adaptive quality: track smoothed FPS and engage/disengage reduced rendering
        let instantFPS: CGFloat = frameDelta > 0 ? min(1.0 / frameDelta, 120) : 60
        smoothedFPS = smoothedFPS * 0.9 + instantFPS * 0.1
        if !adaptiveQualityActive {
            if smoothedFPS < adaptiveLowFPSThreshold {
                lowFPSTimer += dt
                if lowFPSTimer >= 2.0 { adaptiveQualityActive = true; lowFPSTimer = 0 }
            } else {
                lowFPSTimer = 0
            }
        } else {
            if smoothedFPS >= adaptiveHighFPSThreshold {
                highFPSTimer += dt
                if highFPSTimer >= 2.0 { adaptiveQualityActive = false; highFPSTimer = 0 }
            } else {
                highFPSTimer = 0
            }
        }

        updatePowerUps(dt: dt)
        tickCombo(dt: dt)
        frameCounter += 1

        // --- Boost Drain ---
        if isBoostHeld {
            if score <= 0 {
                // No score left — disengage boost
                isBoostHeld = false
                boostTouch  = nil
                setBoostButtonActive(false)
            } else {
                boostScoreDrainTimer += dt
                while boostScoreDrainTimer >= 0.2 {
                    boostScoreDrainTimer -= 0.2
                    score = max(0, score - 1)
                    updateScoreDisplay()
                    updateSpeedForScore()
                    if score == 0 {
                        isBoostHeld = false
                        boostTouch = nil
                        setBoostButtonActive(false)
                        break
                    }
                }
            }
        } else {
            boostScoreDrainTimer = 0
        }

        // --- Player Movement ---
        let baseDist = currentPlayerForwardSpeed() * dt
        let raceControlSpeedFactor: CGFloat = isSnakeRaceMode ? (0.72 + joystickEngagement * 0.72) : 1.0
        let playerDist = baseDist * raceControlSpeedFactor

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

        for i in bodyPositionCache.indices {
            var pos = bodyPositionCache[i]
            let isWiggling = shieldActive && i >= dangerStart
            if isWiggling {
                let progress: CGFloat = dangerCount > 1
                    ? CGFloat(i - dangerStart) / CGFloat(dangerCount - 1)
                    : 1.0
                let amplitude: CGFloat = 9.0 * progress
                let phase = tailWigglePhase + CGFloat(i - dangerStart) * 0.8
                pos.x += -sin(currentAngle) * sin(phase) * amplitude
                pos.y +=  cos(currentAngle) * sin(phase) * amplitude
            }
            bodyPositionCache[i] = pos
        }
        updatePlayerBodyPathAndCollisionSet()

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

        if !isSpecialOfflineMode && checkPlayerHeadVsBotHeads() { playerGameOver(); return }
        if !isSpecialOfflineMode && checkPlayerCollidesWithBotBodies() { playerGameOver(); return }
        

        if !isSpecialOfflineMode { checkFoodCollisions() }

        // --- Super Mouse ---
        if !isSpecialOfflineMode { updateSuperMouse(dt: dt) }

        // --- Trail food spawning (player) ---
        if !isSpecialOfflineMode, gameStarted, let tailPos = bodyPositionCache.last {
            trailFoodTimer += dt
            if isBoostHeld, trailFoodTimer >= playerTrailInterval {
                spawnTrailFood(at: tailPos,
                               colorIndex: selectedSnakeColorIndex,
                               patternIndex: selectedSnakePatternIndex)
                trailFoodTimer = 0
            } else if !isBoostHeld {
                trailFoodTimer = 0
            }
        }

        // --- Safety net: purge orphaned food entries (death food still relies on this) ---
        if !isSpecialOfflineMode && frameCounter % 300 == 0 {
            // Collect indices descending so swap-with-last in removeFoodItem doesn't corrupt
            // earlier indices (removing highest-index first means swaps only affect already-seen slots).
            var toRemove: [Int] = []
            for (i, item) in foodItems.enumerated() where item.parent == nil {
                toRemove.append(i)
            }
            for i in toRemove.sorted(by: >) {
                removeFoodItem(at: i)
            }
            // Reconcile counter against live trail entries to correct any drift
            activeTrailFoodCount = foodTypes.filter { $0 == .trail }.count
            foodGridDirty = true   // grid may be stale after batch removals
        }

        // --- Camera & HUD ---
        updateCamera()
        updateHUDPositions()

        if !isSpecialOfflineMode {
            botVisibilityUpdateTimer += dt
            if botVisibilityUpdateTimer >= 0.20 {
                botVisibilityUpdateTimer = 0
                updateBotVisibilityLOD()
            }
            circledDetectionTimer += dt
            if circledDetectionTimer >= 0.5 {
                circledDetectionTimer = 0
                detectCircledBots()
            }
        }

        // --- Magnet power-up: pull food every other frame ---
        if magnetActive && frameCounter % 2 == 0 { applyMagnetEffect() }

        // --- Mode-specific ---
        if isSnakeRaceMode {
            updateSnakeRaceMode(dt: dt)
        } else {
            let simulationStep = CGFloat(1.0 / minimumGameplayFPS)
            // Use the already-clamped `dt` (capped at maxDeltaTime) instead of raw frameDelta.
            // This prevents debt runaway: on a slow frame the accumulator can queue at most
            // ceil(maxDeltaTime / simulationStep) = 3 ticks instead of potentially 6+.
            botUpdateAccumulator += dt
            botCollisionAccumulator += dt
            botHeadCheckAccumulator += dt

            // Hard cap: never run more than 3 simulation steps per render frame.
            // Extra debt is discarded, which causes bots to slow down gracefully rather than
            // stacking up expensive catch-up work that makes the next frame even slower.
            let maxStepsPerFrame: CGFloat = 3 * simulationStep
            if botUpdateAccumulator    > maxStepsPerFrame { botUpdateAccumulator    = maxStepsPerFrame }
            if botCollisionAccumulator > maxStepsPerFrame { botCollisionAccumulator = maxStepsPerFrame }
            if botHeadCheckAccumulator > maxStepsPerFrame { botHeadCheckAccumulator = maxStepsPerFrame }

            while botUpdateAccumulator >= simulationStep {
                updateBots(dt: simulationStep, updateAI: true)
                botUpdateAccumulator -= simulationStep
            }

            while botCollisionAccumulator >= simulationStep {
                checkBotVsBotCollisions()
                botCollisionAccumulator -= simulationStep
            }

            while botHeadCheckAccumulator >= simulationStep {
                checkBotHeadsHitPlayerBody()
                botHeadCheckAccumulator -= simulationStep
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
            updateSuperMouseHUD()
        }

        // --- Mini Leaderboard (refresh on change, with 1 Hz fallback) ---
        leaderboardUpdateTimer += dt
        if miniLeaderboardNeedsRefresh || leaderboardUpdateTimer >= 1.0 {
            leaderboardUpdateTimer = 0
            updateMiniLeaderboard()
        }

        // --- Movement Heatmap update ---
        updateMovementHeatmap(dt: dt)
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
