import SpriteKit

// MARK: - SuperMouse State
enum SuperMouseState {
    case dormant        // Waiting for 2-minute timer
    case spawningHole   // Hole grows from point → full size (1.5s)
    case emerging       // Mouse slides out head-first (2.0s)
    case active         // Running freely, full AI
    case trapped        // All escape arcs < 45°, glows red
    case caught         // Player ate it — celebration then cleanup
    case retreating     // Timer ran out, mouse slides back into hole (1.5s)
    case despawning     // Hole shrinks and disappears (1.0s) → dormant
}

// MARK: - SuperMouseNode
final class SuperMouseNode: SKNode {

    // Body parts
    private let bodyNode   = SKShapeNode()
    private let headNode   = SKShapeNode()
    private let earLeft    = SKShapeNode()
    private let earRight   = SKShapeNode()
    private let earInnerL  = SKShapeNode()
    private let earInnerR  = SKShapeNode()
    private let eyeLeft    = SKShapeNode()
    private let eyeRight   = SKShapeNode()
    private let specLeft   = SKShapeNode()
    private let specRight  = SKShapeNode()
    private let noseNode   = SKShapeNode()
    private let tailNode   = SKShapeNode()
    private var whiskers:  [SKShapeNode] = []
    private var feet:      [SKShapeNode] = []

    // Animation state
    private var animPhase: CGFloat = 0
    private var whiskerPhase: CGFloat = 0
    private var currentGlowColor: SKColor = .green

    // Mouse body color
    private static let bodyColor   = SKColor(red: 0.72, green: 0.68, blue: 0.72, alpha: 1.0)
    private static let headColor   = SKColor(red: 0.76, green: 0.72, blue: 0.76, alpha: 1.0)
    private static let earColor    = SKColor(red: 0.62, green: 0.58, blue: 0.62, alpha: 1.0)
    private static let earPink     = SKColor(red: 0.96, green: 0.72, blue: 0.78, alpha: 1.0)
    private static let noseColor   = SKColor(red: 0.95, green: 0.60, blue: 0.65, alpha: 1.0)
    private static let tailColor   = SKColor(red: 0.80, green: 0.68, blue: 0.62, alpha: 1.0)
    private static let eyeColor    = SKColor(red: 0.08, green: 0.06, blue: 0.10, alpha: 1.0)

    override init() {
        super.init()
        buildMouse()
        startWhiskerTwitch()
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    // MARK: - Build

    private func buildMouse() {
        // Body — rounded rect approximated by ellipse
        let bodyPath = CGMutablePath()
        bodyPath.addEllipse(in: CGRect(x: -14, y: -9, width: 28, height: 18))
        bodyNode.path = bodyPath
        bodyNode.fillColor = SuperMouseNode.bodyColor
        bodyNode.strokeColor = .clear
        bodyNode.zPosition = 0
        addChild(bodyNode)

        // Head — slightly larger circle, at front (+16 x-offset in local space; head leads)
        let headPath = CGMutablePath()
        headPath.addEllipse(in: CGRect(x: -10, y: -9, width: 20, height: 18))
        headNode.path = headPath
        headNode.fillColor = SuperMouseNode.headColor
        headNode.strokeColor = .clear
        headNode.position = CGPoint(x: 14, y: 0)
        headNode.zPosition = 1
        addChild(headNode)

        // Ears
        buildEar(earLeft,  inner: earInnerL, atX: 10,  atY:  11)
        buildEar(earRight, inner: earInnerR, atX: 10,  atY: -11)

        // Eyes (on head, offset from headNode world position)
        buildEye(eyeLeft,  spec: specLeft,  at: CGPoint(x: 22, y: 5))
        buildEye(eyeRight, spec: specRight, at: CGPoint(x: 22, y: -5))

        // Nose
        let nosePath = CGMutablePath()
        nosePath.addEllipse(in: CGRect(x: -3, y: -2, width: 6, height: 4))
        noseNode.path = nosePath
        noseNode.fillColor = SuperMouseNode.noseColor
        noseNode.strokeColor = .clear
        noseNode.position = CGPoint(x: 25, y: 0)
        noseNode.zPosition = 3
        addChild(noseNode)

        // Whiskers — 3 per side
        for i in 0..<3 {
            let angle = CGFloat(i - 1) * 0.28   // spread: -0.28, 0, +0.28 rad
            whiskers.append(makeWhisker(angle:  angle, sideY:  1))
            whiskers.append(makeWhisker(angle: -angle, sideY: -1))
        }

        // Feet — 4 small ovals
        let feetPositions: [(CGFloat, CGFloat)] = [
            ( 8,  12), (-6,  12),   // front-left, back-left
            ( 8, -12), (-6, -12)    // front-right, back-right
        ]
        for (fx, fy) in feetPositions {
            let foot = SKShapeNode()
            let fp = CGMutablePath()
            fp.addEllipse(in: CGRect(x: -4, y: -3, width: 8, height: 6))
            foot.path = fp
            foot.fillColor = SuperMouseNode.earColor
            foot.strokeColor = .clear
            foot.position = CGPoint(x: fx, y: fy)
            foot.zPosition = -0.5
            addChild(foot)
            feet.append(foot)
        }

        // Tail — starts behind body; redrawn each update
        tailNode.strokeColor = SuperMouseNode.tailColor
        tailNode.lineWidth = 2.8
        tailNode.lineCap = .round
        tailNode.zPosition = -1
        addChild(tailNode)
        updateTailShape(phase: 0)

        // Glow
        bodyNode.glowWidth = 6
        bodyNode.glowWidth = 6
        setGlowColor(.green)
    }

    private func buildEar(_ ear: SKShapeNode, inner: SKShapeNode, atX: CGFloat, atY: CGFloat) {
        let ep = CGMutablePath()
        ep.addEllipse(in: CGRect(x: -7, y: -7, width: 14, height: 14))
        ear.path = ep
        ear.fillColor = SuperMouseNode.earColor
        ear.strokeColor = .clear
        ear.position = CGPoint(x: atX, y: atY)
        ear.zPosition = 0.5
        addChild(ear)

        let ip = CGMutablePath()
        ip.addEllipse(in: CGRect(x: -4, y: -4, width: 8, height: 8))
        inner.path = ip
        inner.fillColor = SuperMouseNode.earPink
        inner.strokeColor = .clear
        inner.position = CGPoint(x: atX, y: atY)
        inner.zPosition = 0.6
        addChild(inner)
    }

    private func buildEye(_ eye: SKShapeNode, spec: SKShapeNode, at pos: CGPoint) {
        let ep = CGMutablePath()
        ep.addEllipse(in: CGRect(x: -3.5, y: -3.5, width: 7, height: 7))
        eye.path = ep
        eye.fillColor = SuperMouseNode.eyeColor
        eye.strokeColor = .clear
        eye.position = pos
        eye.zPosition = 2
        addChild(eye)

        let sp = CGMutablePath()
        sp.addEllipse(in: CGRect(x: -1.2, y: -1.2, width: 2.4, height: 2.4))
        spec.path = sp
        spec.fillColor = .white
        spec.strokeColor = .clear
        spec.position = CGPoint(x: pos.x + 1.2, y: pos.y + 1.2)
        spec.zPosition = 2.5
        addChild(spec)
    }

    private func makeWhisker(angle: CGFloat, sideY: CGFloat) -> SKShapeNode {
        let len: CGFloat = 16
        let wp = CGMutablePath()
        wp.move(to: CGPoint(x: 20, y: sideY * 3))
        wp.addLine(to: CGPoint(x: 20 + cos(angle) * len, y: sideY * 3 + sin(angle) * len * sideY))
        let w = SKShapeNode(path: wp)
        w.strokeColor = SKColor(white: 0.92, alpha: 0.9)
        w.lineWidth = 1.0
        w.lineCap = .round
        w.zPosition = 2
        addChild(w)
        return w
    }

    // MARK: - Whisker Twitch (runs forever)

    private func startWhiskerTwitch() {
        for (i, w) in whiskers.enumerated() {
            let delay = SKAction.wait(forDuration: Double(i) * 0.09)
            let twitchAngle: CGFloat = (i % 2 == 0) ? 0.18 : -0.18
            let twitch = SKAction.sequence([
                SKAction.rotate(byAngle: twitchAngle,  duration: 0.10),
                SKAction.rotate(byAngle: -twitchAngle, duration: 0.10)
            ])
            w.run(SKAction.sequence([delay, SKAction.repeatForever(twitch)]))
        }
    }

    // MARK: - Tail Shape

    func updateTailShape(phase: CGFloat) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -14, y: 0))
        let wave1 = sin(phase) * 10
        let wave2 = sin(phase + 1.2) * 8
        path.addCurve(
            to: CGPoint(x: -44, y: wave1),
            control1: CGPoint(x: -24, y: wave2),
            control2: CGPoint(x: -34, y: wave1 * 0.6)
        )
        tailNode.path = path
    }

    // MARK: - Feet Stride

    private func updateFeetStride(phase: CGFloat) {
        // front-left and back-right in phase; front-right and back-left opposite
        let a0 =  sin(phase) * 0.35
        let a1 = -sin(phase) * 0.35
        if feet.count == 4 {
            feet[0].yScale = 1.0 + a0   // front-left
            feet[1].yScale = 1.0 + a1   // back-left
            feet[2].yScale = 1.0 + a1   // front-right
            feet[3].yScale = 1.0 + a0   // back-right
        }
    }

    // MARK: - Glow

    func setGlowColor(_ color: SKColor) {
        guard color != currentGlowColor else { return }
        currentGlowColor = color
        bodyNode.removeAction(forKey: "glow")
        headNode.removeAction(forKey: "glow")
        if color == .red {
            // Rapid pulse when trapped
            let pulse = SKAction.sequence([
                SKAction.customAction(withDuration: 0) { [weak self] _, _ in
                    self?.bodyNode.glowWidth = 12
                    self?.headNode.glowWidth = 10
                },
                SKAction.wait(forDuration: 0.25),
                SKAction.customAction(withDuration: 0) { [weak self] _, _ in
                    self?.bodyNode.glowWidth = 4
                    self?.headNode.glowWidth = 3
                },
                SKAction.wait(forDuration: 0.25)
            ])
            bodyNode.run(SKAction.repeatForever(pulse), withKey: "glow")
        }
        // Tint body via simple linear mix
        let (tr, tg, tb): (CGFloat, CGFloat, CGFloat)
        switch color {
        case .green:  (tr, tg, tb) = (0.6, 1.0, 0.6)
        case .yellow: (tr, tg, tb) = (1.0, 0.9, 0.5)
        case .red:    (tr, tg, tb) = (1.0, 0.5, 0.5)
        default:      (tr, tg, tb) = (1.0, 1.0, 1.0)
        }
        func mix(_ base: SKColor, tr: CGFloat, tg: CGFloat, tb: CGFloat, frac: CGFloat) -> SKColor {
            var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
            base.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
            return SKColor(red: br + (tr - br) * frac, green: bg + (tg - bg) * frac,
                           blue: bb + (tb - bb) * frac, alpha: ba)
        }
        bodyNode.fillColor = mix(SuperMouseNode.bodyColor, tr: tr, tg: tg, tb: tb, frac: 0.35)
        headNode.fillColor = mix(SuperMouseNode.headColor, tr: tr, tg: tg, tb: tb, frac: 0.35)
    }

    // MARK: - Per-frame Update

    /// Call every frame from GameScene to drive animations.
    func update(dt: CGFloat, speed: CGFloat, state: SuperMouseState) {
        animPhase  += dt * (speed / 100.0) * 6.0  // stride rate scales with speed
        whiskerPhase += dt

        updateTailShape(phase: animPhase)
        updateFeetStride(phase: animPhase)

        switch state {
        case .active:
            setGlowColor(.green)
        case .trapped:
            setGlowColor(.red)
        case .emerging:
            setGlowColor(SKColor(white: 0.7, alpha: 1))
        default:
            break
        }
    }
}
