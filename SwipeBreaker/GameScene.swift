import SpriteKit
import UIKit

private enum Palette {
    static let bgTop = SKColor(red: 0.06, green: 0.07, blue: 0.13, alpha: 1)
    static let bgBottom = SKColor(red: 0.012, green: 0.012, blue: 0.022, alpha: 1)
    static let accent = SKColor(red: 0.55, green: 0.85, blue: 1.0, alpha: 1)
    static let danger = SKColor(red: 0.95, green: 0.32, blue: 0.32, alpha: 1)
    static let launcher = SKColor(red: 0.72, green: 0.92, blue: 1.0, alpha: 1)
    static let pickup = SKColor(red: 1.0, green: 0.88, blue: 0.45, alpha: 1)
    static let hudPrimary = SKColor(white: 1.0, alpha: 0.95)
    static let hudSecondary = SKColor(white: 1.0, alpha: 0.55)
}

@MainActor
final class GameScene: SKScene {
    private static let launchFeedbackBucketCount = 5
    private static let aimDotSpacing: CGFloat = 15
    private static let trailSpawnInterval: TimeInterval = 1.0 / 60.0

    private let store: SaveStore
    private var state: GameState
    private var lastCompletedState: GameState
    private var highScores: [HighScoreEntry]
    private var didRecordGameOverScore = false

    private let backgroundLayer = SKNode()
    private let backgroundSprite = SKSpriteNode()
    private let starfieldNode = SKNode()
    private let worldNode = SKNode()
    private let trailLayer = SKNode()
    private let effectsLayer = SKNode()
    private let hudNode = SKNode()
    private let scoreLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let bestLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private let statusLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let hintLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private let launcherNode = SKShapeNode(circleOfRadius: 9)
    private let launcherGlow = SKShapeNode(circleOfRadius: 22)
    private let aimLine = SKShapeNode()
    private let ceilingLine = SKShapeNode()
    private let dangerLine = SKShapeNode()
    private let leftBoundaryLine = SKShapeNode()
    private let rightBoundaryLine = SKShapeNode()
    private let failOverlay = SKShapeNode()

    private var brickNodes: [String: SKShapeNode] = [:]
    private var unusedBrickNodes: [SKShapeNode] = []
    private var ballNodes: [Int: SKShapeNode] = [:]
    private var unusedBallNodes: [SKShapeNode] = []
    private var pickupNodes: [String: SKShapeNode] = [:]
    private var unusedPickupNodes: [SKShapeNode] = []
    private var aimDotNodes: [SKShapeNode] = []
    private var brickHitPointsByID: [String: Int] = [:]
    private var trailPool: [SKShapeNode] = []
    private var ballTrailLastSpawn: [Int: TimeInterval] = [:]

    private var dragStart: CGPoint?
    private var currentDrag: CGPoint?
    private var aimStartPoint = CGPoint.zero
    private var aimEndPoint = CGPoint.zero
    private var aimDotPhase: CGFloat = 0
    private let launchFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let comboFeedbackGenerator = UINotificationFeedbackGenerator()
    private var lastLaunchFeedbackBucket = 0
    private var fixedStepAccumulator: Double = 0
    private var lastUpdateTime: TimeInterval = 0

    private var hitStopUntil: TimeInterval = 0
    private var shakeOffset: CGPoint = .zero
    private var shakeIntensity: CGFloat = 0
    private var shakeDecay: CGFloat = 0
    private var comboCount: Int = 0
    private var hasUsedFirstHint = false
    private var didHaveBallsInFlight = false
    private var lastGradientSize: CGSize = .zero

    init(store: SaveStore) {
        self.store = store
        let loadedState = (try? store.loadSession()) ?? GameEngine.newGame()
        state = loadedState
        lastCompletedState = loadedState
        highScores = (try? store.loadHighScores()) ?? []
        super.init(size: CGSize(width: 390, height: 844))
        backgroundColor = SKColor.black
    }

    required init?(coder aDecoder: NSCoder) {
        store = SaveStore()
        let loadedState = (try? store.loadSession()) ?? GameEngine.newGame()
        state = loadedState
        lastCompletedState = loadedState
        highScores = (try? store.loadHighScores()) ?? []
        super.init(coder: aDecoder)
    }

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = false
        view.preferredFramesPerSecond = 120
        setupScene()
        renderAll()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutStaticNodes()
        renderAll()
    }

    override func update(_ currentTime: TimeInterval) {
        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
            return
        }

        let frameTime = min(0.05, currentTime - lastUpdateTime)
        lastUpdateTime = currentTime

        applyShake(dt: frameTime)

        if currentTime < hitStopUntil {
            renderDynamicNodes()
            return
        }

        fixedStepAccumulator += frameTime

        let fixedStep = 1.0 / 120.0
        var didFinishTurn = false
        var events = TurnEvents()
        while fixedStepAccumulator >= fixedStep {
            didFinishTurn = GameEngine.stepActiveTurn(state: &state, dt: fixedStep, events: &events) || didFinishTurn
            fixedStepAccumulator -= fixedStep
        }

        respond(to: events, currentTime: currentTime)

        if didFinishTurn {
            completeTurn()
        }

        spawnBallTrails(currentTime: currentTime)
        renderDynamicNodes()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)

        if state.isGameOver {
            startNewGame()
            return
        }

        guard state.balls.isEmpty, point.distance(to: scenePoint(for: state.launcher)) < 140 else {
            return
        }

        dragStart = scenePoint(for: state.launcher)
        currentDrag = point
        resetLaunchFeedback()
        launchFeedbackGenerator.prepare()
        comboFeedbackGenerator.prepare()
        animateLauncherPulse(active: true)
        hideHintLabel()
        updateAimPreview()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard dragStart != nil, let touch = touches.first else { return }
        currentDrag = touch.location(in: self)
        updateAimPreview()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishDrag()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        animateLauncherPulse(active: false)
        clearAimPreview()
    }

    func persistCompletedTurn() {
        try? store.saveSession(lastCompletedState)
    }

    private func setupScene() {
        removeAllChildren()

        addChild(backgroundLayer)
        backgroundLayer.zPosition = -100
        backgroundLayer.addChild(backgroundSprite)
        backgroundLayer.addChild(starfieldNode)

        addChild(worldNode)
        worldNode.addChild(trailLayer)
        trailLayer.zPosition = -1
        worldNode.addChild(effectsLayer)
        effectsLayer.zPosition = 50

        addChild(hudNode)
        hudNode.zPosition = 200

        [scoreLabel, bestLabel, statusLabel, hintLabel].forEach {
            $0.horizontalAlignmentMode = .center
            $0.verticalAlignmentMode = .center
            hudNode.addChild($0)
        }
        scoreLabel.fontColor = Palette.hudPrimary
        bestLabel.fontColor = Palette.hudSecondary
        statusLabel.fontColor = Palette.hudPrimary
        hintLabel.fontColor = Palette.hudSecondary
        hintLabel.alpha = 0

        launcherGlow.fillColor = Palette.launcher.withAlphaComponent(0.18)
        launcherGlow.strokeColor = .clear
        launcherGlow.alpha = 0
        launcherGlow.zPosition = 1
        worldNode.addChild(launcherGlow)

        launcherNode.fillColor = Palette.launcher
        launcherNode.strokeColor = SKColor.white.withAlphaComponent(0.85)
        launcherNode.lineWidth = 1
        launcherNode.zPosition = 2
        worldNode.addChild(launcherNode)

        aimLine.isHidden = true
        aimLine.zPosition = 3
        worldNode.addChild(aimLine)

        ceilingLine.strokeColor = SKColor(white: 1, alpha: 0.32)
        ceilingLine.lineWidth = 1.5
        ceilingLine.lineCap = .round
        worldNode.addChild(ceilingLine)

        dangerLine.strokeColor = SKColor(white: 1, alpha: 0.22)
        dangerLine.lineWidth = 1.0
        dangerLine.lineCap = .round
        worldNode.addChild(dangerLine)

        [leftBoundaryLine, rightBoundaryLine].forEach {
            $0.strokeColor = SKColor(white: 1, alpha: 0.16)
            $0.lineWidth = 1.0
            $0.lineCap = .round
            worldNode.addChild($0)
        }

        failOverlay.fillColor = SKColor(red: 0.78, green: 0.10, blue: 0.08, alpha: 1.0)
        failOverlay.strokeColor = .clear
        failOverlay.zPosition = 150
        failOverlay.alpha = 0
        failOverlay.isHidden = true
        addChild(failOverlay)

        layoutStaticNodes()
    }

    private func layoutStaticNodes() {
        rebuildBackgroundIfNeeded()

        scoreLabel.fontSize = 38
        bestLabel.fontSize = 11
        statusLabel.fontSize = 14
        hintLabel.fontSize = 13

        scoreLabel.position = CGPoint(x: size.width * 0.5, y: size.height - 56)
        bestLabel.position = CGPoint(x: size.width * 0.5, y: size.height - 86)
        statusLabel.position = CGPoint(x: size.width * 0.5, y: size.height * 0.055)
        hintLabel.position = CGPoint(x: size.width * 0.5, y: size.height * GameConfig.launcher.y + 36)

        launcherNode.position = scenePoint(for: state.launcher)
        launcherGlow.position = launcherNode.position

        let ceilingY = size.height * GameConfig.topWall
        let ceilingPath = CGMutablePath()
        ceilingPath.move(to: CGPoint(x: size.width * GameConfig.leftWall, y: ceilingY))
        ceilingPath.addLine(to: CGPoint(x: size.width * GameConfig.rightWall, y: ceilingY))
        ceilingLine.path = ceilingPath

        let dangerY = size.height * GameConfig.boardBottom
        let path = CGMutablePath()
        path.move(to: CGPoint(x: size.width * GameConfig.leftWall, y: dangerY))
        path.addLine(to: CGPoint(x: size.width * GameConfig.rightWall, y: dangerY))
        dangerLine.path = path

        let leftBoundaryPath = CGMutablePath()
        leftBoundaryPath.move(to: CGPoint(x: size.width * GameConfig.leftWall, y: dangerY))
        leftBoundaryPath.addLine(to: CGPoint(x: size.width * GameConfig.leftWall, y: ceilingY))
        leftBoundaryLine.path = leftBoundaryPath

        let rightBoundaryPath = CGMutablePath()
        rightBoundaryPath.move(to: CGPoint(x: size.width * GameConfig.rightWall, y: dangerY))
        rightBoundaryPath.addLine(to: CGPoint(x: size.width * GameConfig.rightWall, y: ceilingY))
        rightBoundaryLine.path = rightBoundaryPath

        failOverlay.path = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
        failOverlay.position = .zero
    }

    private func rebuildBackgroundIfNeeded() {
        guard size.width > 0, size.height > 0, size != lastGradientSize else { return }
        lastGradientSize = size
        backgroundSprite.size = size
        backgroundSprite.position = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        backgroundSprite.texture = makeGradientTexture(size: CGSize(width: 8, height: max(2, size.height)))
        rebuildStarfield()
    }

    private func makeGradientTexture(size: CGSize) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let cg = context.cgContext
            let colors = [Palette.bgTop.cgColor, Palette.bgBottom.cgColor] as CFArray
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: size.height),
                    end: CGPoint(x: 0, y: 0),
                    options: []
                )
            }
        }
        return SKTexture(image: image)
    }

    private func rebuildStarfield() {
        starfieldNode.removeAllChildren()
        var rng = SeededRandom(seed: 0x5712_9A3F)
        let starCount = 38
        for _ in 0..<starCount {
            let x = CGFloat(Double(rng.next() % 10_000) / 10_000) * size.width
            let y = CGFloat(Double(rng.next() % 10_000) / 10_000) * size.height
            let radius = 0.5 + CGFloat(Double(rng.next() % 100) / 100) * 1.0
            let alpha = 0.10 + CGFloat(Double(rng.next() % 100) / 100) * 0.18
            let star = SKShapeNode(circleOfRadius: radius)
            star.fillColor = SKColor(white: 1, alpha: alpha)
            star.strokeColor = .clear
            star.position = CGPoint(x: x, y: y)
            starfieldNode.addChild(star)
        }
    }

    private func renderAll() {
        renderHUD()
        renderBricks()
        renderPickups()
        renderDynamicNodes()
        updateHintVisibility()
    }

    private func renderHUD() {
        scoreLabel.text = "\(state.score)"
        let bestScore = highScores.first?.score ?? 0
        bestLabel.text = "BEST  \(bestScore)    TURN  \(state.turn)    BALLS  \(state.ballCount)"
        if state.isGameOver {
            statusLabel.text = "TAP TO RESTART"
        } else {
            statusLabel.text = "READY"
            if state.balls.isEmpty {
                statusLabel.alpha = 0.65
            } else {
                statusLabel.alpha = 0
            }
        }
    }

    private func updateHintVisibility() {
        let shouldShow = !state.isGameOver
            && state.turn == 1
            && state.score == 0
            && state.balls.isEmpty
            && !hasUsedFirstHint
        if shouldShow {
            hintLabel.text = "swipe down to aim ↓"
            if hintLabel.action(forKey: "hint") == nil {
                hintLabel.removeAllActions()
                hintLabel.alpha = 0
                let pulse = SKAction.sequence([
                    .fadeAlpha(to: 0.55, duration: 0.6),
                    .fadeAlpha(to: 0.22, duration: 0.6)
                ])
                hintLabel.run(.repeatForever(pulse), withKey: "hint")
            }
        } else {
            hideHintLabel()
        }
    }

    private func hideHintLabel() {
        if hintLabel.action(forKey: "hint") != nil || hintLabel.alpha > 0 {
            hintLabel.removeAction(forKey: "hint")
            hintLabel.run(.fadeOut(withDuration: 0.18))
        }
    }

    private func renderBricks(animateChanges: Bool = false) {
        var visibleIDs = Set<String>()

        for brick in state.bricks {
            let id = brick.id
            visibleIDs.insert(id)
            let previousHitPoints = brickHitPointsByID[id]
            let node = brickNodes[id] ?? dequeueBrickNode()
            brickNodes[id] = node
            if node.parent == nil {
                worldNode.addChild(node)
            }

            let rect = sceneRect(for: brick)
            node.position = CGPoint(x: rect.midX, y: rect.midY)
            let bodyPath = CGPath(
                roundedRect: CGRect(x: -rect.width * 0.5, y: -rect.height * 0.5, width: rect.width, height: rect.height),
                cornerWidth: 5,
                cornerHeight: 5,
                transform: nil
            )
            node.path = bodyPath
            node.fillColor = brickColor(for: brick)
            node.strokeColor = brickStrokeColor(for: brick)

            if let shadow = node.childNode(withName: "shadow") as? SKShapeNode {
                shadow.path = bodyPath
            }
            if let highlight = node.childNode(withName: "highlight") as? SKShapeNode {
                let inset: CGFloat = 1.6
                highlight.path = CGPath(
                    roundedRect: CGRect(
                        x: -rect.width * 0.5 + inset,
                        y: -rect.height * 0.5 + inset,
                        width: rect.width - inset * 2,
                        height: rect.height - inset * 2
                    ),
                    cornerWidth: 4,
                    cornerHeight: 4,
                    transform: nil
                )
            }
            let label = node.childNode(withName: "hp") as? SKLabelNode
            label?.text = "\(brick.hitPoints)"
            label?.fontSize = max(11, min(20, rect.height * 0.42))

            if animateChanges, let previousHitPoints, previousHitPoints > brick.hitPoints {
                animateBrickDamage(node: node, rect: rect)
            }
        }

        let staleBrickIDs = brickNodes.keys.filter { !visibleIDs.contains($0) }
        for id in staleBrickIDs {
            if let node = brickNodes[id] {
                if animateChanges {
                    animateBrickBreak(id: id, node: node)
                } else {
                    recycleBrickNode(id: id, node: node)
                }
            }
        }

        brickHitPointsByID = Dictionary(uniqueKeysWithValues: state.bricks.map { ($0.id, $0.hitPoints) })

        updateDangerLine()
    }

    private func updateDangerLine() {
        let lowestRow = state.bricks.map(\.row).max() ?? 0
        if lowestRow >= 7 {
            dangerLine.strokeColor = Palette.danger.withAlphaComponent(0.55)
            if dangerLine.action(forKey: "pulse") == nil {
                let pulse = SKAction.sequence([
                    .fadeAlpha(to: 1.0, duration: 0.5),
                    .fadeAlpha(to: 0.45, duration: 0.5)
                ])
                dangerLine.run(.repeatForever(pulse), withKey: "pulse")
            }
        } else {
            dangerLine.removeAction(forKey: "pulse")
            dangerLine.alpha = 1
            dangerLine.strokeColor = SKColor(white: 1, alpha: 0.22)
        }
    }

    private func renderPickups(animateCollections: Bool = false) {
        var visibleIDs = Set<String>()

        for pickup in state.pickups {
            let id = pickup.id
            visibleIDs.insert(id)
            let isNew = pickupNodes[id] == nil
            let node = pickupNodes[id] ?? dequeuePickupNode()
            pickupNodes[id] = node
            if node.parent == nil {
                worldNode.addChild(node)
            }

            let rect = sceneRect(column: pickup.column, row: pickup.row)
            let radius = min(rect.width, rect.height) * 0.21
            node.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
            node.position = CGPoint(x: rect.midX, y: rect.midY)
            if let core = node.childNode(withName: "core") as? SKShapeNode {
                let coreRadius = radius * 0.45
                core.path = CGPath(ellipseIn: CGRect(x: -coreRadius, y: -coreRadius, width: coreRadius * 2, height: coreRadius * 2), transform: nil)
            }

            if isNew {
                node.removeAction(forKey: "pulse")
                let breathe = SKAction.sequence([
                    .scale(to: 1.18, duration: 0.6),
                    .scale(to: 0.92, duration: 0.6)
                ])
                breathe.timingMode = .easeInEaseOut
                node.run(.repeatForever(breathe), withKey: "pulse")
            }
        }

        let stalePickupIDs = pickupNodes.keys.filter { !visibleIDs.contains($0) }
        for id in stalePickupIDs {
            if let node = pickupNodes[id] {
                if animateCollections {
                    animatePickupCollection(id: id, node: node)
                } else {
                    recyclePickupNode(id: id, node: node)
                }
            }
        }
    }

    private func renderDynamicNodes() {
        renderBricks(animateChanges: !state.balls.isEmpty)
        renderPickups(animateCollections: !state.balls.isEmpty)
        renderHUD()
        launcherNode.position = scenePoint(for: state.launcher)
        launcherGlow.position = launcherNode.position

        var visibleIDs = Set<Int>()
        for ball in state.balls where ball.isActive && !ball.isFinished {
            visibleIDs.insert(ball.id)
            let node = ballNodes[ball.id] ?? dequeueBallNode()
            ballNodes[ball.id] = node
            if node.parent == nil {
                worldNode.addChild(node)
            }
            node.position = scenePoint(for: ball.position)
            node.alpha = 1
        }

        let staleBallIDs = ballNodes.keys.filter { !visibleIDs.contains($0) }
        for id in staleBallIDs {
            if let node = ballNodes[id] {
                recycleBallNode(id: id, node: node)
            }
        }
    }

    private func finishDrag() {
        defer {
            resetLaunchFeedback()
            animateLauncherPulse(active: false)
            clearAimPreview()
        }
        guard let start = dragStart, let current = currentDrag, state.balls.isEmpty, !state.isGameOver else {
            return
        }

        let pullPoint = Vec2(x: Double(start.x - current.x) / Double(size.width), y: Double(start.y - current.y) / Double(size.height))
        let distance = start.distance(to: current) / min(size.width, size.height)
        guard distance > 0.035 else { return }

        hasUsedFirstHint = true
        AudioManager.shared.play(.launch)
        emitLauncherRing()
        GameEngine.beginLaunch(state: &state, pull: pullPoint, pullDistance: distance)
        comboCount = 0
        didHaveBallsInFlight = true
        renderDynamicNodes()
    }

    private func completeTurn() {
        if state.isGameOver, !didRecordGameOverScore {
            highScores = (try? store.recordHighScore(score: state.score, turn: state.turn)) ?? highScores
            try? store.clearSession()
            didRecordGameOverScore = true
            playFailAnimation()
        } else if !state.isGameOver {
            lastCompletedState = state
            try? store.saveSession(state)
            emitLauncherRing()
            AudioManager.shared.play(.bounce)
        }

        comboCount = 0
        didHaveBallsInFlight = false
        renderBricks()
        renderPickups()
        renderHUD()
        updateHintVisibility()
    }

    private func startNewGame() {
        failOverlay.removeAllActions()
        failOverlay.alpha = 0
        failOverlay.isHidden = true
        statusLabel.removeAllActions()
        statusLabel.alpha = 0
        state = GameEngine.newGame()
        lastCompletedState = state
        didRecordGameOverScore = false
        hasUsedFirstHint = false
        comboCount = 0
        didHaveBallsInFlight = false
        brickHitPointsByID.removeAll(keepingCapacity: true)
        try? store.saveSession(state)
        clearAimPreview()
        renderAll()
    }

    private func updateAimPreview() {
        guard let start = dragStart, let current = currentDrag else { return }
        let pullPoint = Vec2(x: Double(start.x - current.x) / Double(size.width), y: Double(start.y - current.y) / Double(size.height))
        let direction = GameEngine.normalizedLaunchVector(fromPull: pullPoint)
        let strength = GameEngine.launchStrength(forPullDistance: start.distance(to: current) / min(size.width, size.height))
        let previewLength = (70 + 110 * strength)

        let end = CGPoint(
            x: start.x + direction.x * previewLength,
            y: start.y + direction.y * previewLength
        )

        aimStartPoint = start
        aimEndPoint = end
        aimLine.alpha = 0.45 + 0.45 * strength
        aimLine.isHidden = false
        layoutAimDots(strength: CGFloat(strength))
        startAimLineAnimationIfNeeded()
        triggerStrengthFeedbackIfNeeded(strength: strength)
    }

    private func clearAimPreview() {
        resetLaunchFeedback()
        dragStart = nil
        currentDrag = nil
        aimLine.isHidden = true
        aimLine.removeAction(forKey: "dash")
        aimDotPhase = 0
    }

    private func startAimLineAnimationIfNeeded() {
        guard aimLine.action(forKey: "dash") == nil else { return }

        let duration: CGFloat = 0.45
        let animateDash = SKAction.customAction(withDuration: TimeInterval(duration)) { [weak self] _, elapsed in
            guard let self else { return }
            self.aimDotPhase = (elapsed / duration) * Self.aimDotSpacing
            self.layoutAimDots(strength: nil)
        }
        aimLine.run(.repeatForever(animateDash), withKey: "dash")
    }

    private func layoutAimDots(strength: CGFloat?) {
        let dx = aimEndPoint.x - aimStartPoint.x
        let dy = aimEndPoint.y - aimStartPoint.y
        let length = max(1, sqrt(dx * dx + dy * dy))
        let dotCount = Int(ceil(length / Self.aimDotSpacing)) + 2
        ensureAimDotCount(dotCount)

        for (index, node) in aimDotNodes.enumerated() {
            let distance = CGFloat(index) * Self.aimDotSpacing + aimDotPhase
            guard index < dotCount, distance <= length else {
                node.isHidden = true
                continue
            }

            let progress = distance / length
            node.position = CGPoint(
                x: aimStartPoint.x + dx * progress,
                y: aimStartPoint.y + dy * progress
            )
            // Color shifts cool→warm with progress (and intensifies with strength)
            let warm = max(0, min(1, progress))
            let baseHue: CGFloat = 0.58 - 0.50 * warm
            let saturation: CGFloat = 0.55 + 0.30 * warm
            let brightness: CGFloat = 0.95
            node.fillColor = SKColor(hue: baseHue, saturation: saturation, brightness: brightness, alpha: 1)
            node.strokeColor = node.fillColor
            if let strength {
                node.setScale(1.0 + 0.6 * strength * (1 - progress))
            }
            node.isHidden = false
        }
    }

    private func ensureAimDotCount(_ count: Int) {
        guard aimDotNodes.count < count else { return }

        for _ in aimDotNodes.count..<count {
            let dot = SKShapeNode(circleOfRadius: 2.4)
            dot.fillColor = .white
            dot.strokeColor = .white
            dot.lineWidth = 0
            aimLine.addChild(dot)
            aimDotNodes.append(dot)
        }
    }

    private func triggerStrengthFeedbackIfNeeded(strength: Double) {
        let bucketCount = Self.launchFeedbackBucketCount
        let bucket = min(bucketCount, max(0, Int(ceil(strength * Double(bucketCount)))))
        guard bucket > lastLaunchFeedbackBucket else { return }

        lastLaunchFeedbackBucket = bucket
        let intensity = 0.25 + (0.75 * Double(bucket) / Double(bucketCount))
        launchFeedbackGenerator.impactOccurred(intensity: CGFloat(intensity))
        launchFeedbackGenerator.prepare()
    }

    private func resetLaunchFeedback() {
        lastLaunchFeedbackBucket = 0
    }

    // MARK: - Effects

    private func respond(to events: TurnEvents, currentTime: TimeInterval) {
        if events.wallBounces > 0 {
            AudioManager.shared.play(.bounce)
        }

        for hit in events.brickHits {
            spawnImpactSpark(at: scenePoint(for: hit), color: SKColor(white: 1, alpha: 0.8), radius: 4)
            requestShake(intensity: 1.6, duration: 0.10)
            AudioManager.shared.play(.brickHit)
        }

        var combosThisFrame = 0
        for breakPoint in events.brickBreaks {
            comboCount += 1
            combosThisFrame += 1
            spawnImpactSpark(at: scenePoint(for: breakPoint), color: Palette.accent, radius: 8)
            spawnComboLabelIfNeeded(at: scenePoint(for: breakPoint))
            requestShake(intensity: 3.2, duration: 0.16)
            AudioManager.shared.play(.brickBreak)
        }

        if combosThisFrame > 0 && hitStopUntil < currentTime {
            hitStopUntil = currentTime + 0.05
        }

        for pickup in events.pickups {
            spawnImpactSpark(at: scenePoint(for: pickup), color: Palette.pickup, radius: 10)
            AudioManager.shared.play(.pickup)
        }
    }

    private func requestShake(intensity: CGFloat, duration: TimeInterval) {
        shakeIntensity = min(6.5, shakeIntensity + intensity)
        shakeDecay = max(shakeDecay, CGFloat(1.0 / duration))
    }

    private func applyShake(dt: TimeInterval) {
        guard shakeIntensity > 0.05 else {
            if shakeOffset != .zero {
                shakeOffset = .zero
                worldNode.position = .zero
            }
            shakeIntensity = 0
            return
        }
        let dx = CGFloat.random(in: -1...1) * shakeIntensity
        let dy = CGFloat.random(in: -1...1) * shakeIntensity
        shakeOffset = CGPoint(x: dx, y: dy)
        worldNode.position = shakeOffset
        let decayPerSecond = max(8, shakeDecay * 8)
        shakeIntensity = max(0, shakeIntensity - decayPerSecond * CGFloat(dt))
    }

    private func spawnComboLabelIfNeeded(at point: CGPoint) {
        guard comboCount >= 2 else { return }
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = "x\(comboCount)"
        label.fontSize = 18 + CGFloat(min(comboCount, 8)) * 1.4
        label.fontColor = comboCount >= 5 ? Palette.pickup : Palette.accent
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = point
        label.zPosition = 80
        label.alpha = 0
        effectsLayer.addChild(label)

        let move = SKAction.moveBy(x: 0, y: 38, duration: 0.55)
        move.timingMode = .easeOut
        let appear = SKAction.fadeAlpha(to: 1, duration: 0.08)
        let fade = SKAction.fadeAlpha(to: 0, duration: 0.45)
        let scaleUp = SKAction.scale(to: 1.25, duration: 0.55)
        scaleUp.timingMode = .easeOut

        label.run(.sequence([
            appear,
            .group([move, fade, scaleUp]),
            .removeFromParent()
        ]))

        if comboCount == 3 || comboCount == 5 || comboCount == 8 {
            comboFeedbackGenerator.notificationOccurred(.success)
            comboFeedbackGenerator.prepare()
        }
    }

    private func spawnImpactSpark(at point: CGPoint, color: SKColor, radius: CGFloat) {
        let ring = SKShapeNode(circleOfRadius: radius)
        ring.position = point
        ring.fillColor = .clear
        ring.strokeColor = color
        ring.lineWidth = 1.5
        ring.zPosition = 60
        effectsLayer.addChild(ring)

        let action = SKAction.group([
            .scale(to: 2.6, duration: 0.30),
            .fadeOut(withDuration: 0.30)
        ])
        action.timingMode = .easeOut
        ring.run(.sequence([action, .removeFromParent()]))
    }

    private func emitLauncherRing() {
        let ring = SKShapeNode(circleOfRadius: 12)
        ring.position = scenePoint(for: state.launcher)
        ring.fillColor = .clear
        ring.strokeColor = Palette.launcher.withAlphaComponent(0.85)
        ring.lineWidth = 1.5
        ring.zPosition = 4
        worldNode.addChild(ring)
        let pulse = SKAction.group([
            .scale(to: 3.4, duration: 0.55),
            .fadeOut(withDuration: 0.55)
        ])
        pulse.timingMode = .easeOut
        ring.run(.sequence([pulse, .removeFromParent()]))
    }

    private func animateLauncherPulse(active: Bool) {
        launcherGlow.removeAllActions()
        launcherNode.removeAction(forKey: "pulse")
        if active {
            launcherGlow.alpha = 0
            launcherGlow.setScale(0.6)
            launcherGlow.run(.fadeAlpha(to: 0.55, duration: 0.15))
            let breathe = SKAction.sequence([
                .scale(to: 1.4, duration: 0.7),
                .scale(to: 0.9, duration: 0.7)
            ])
            breathe.timingMode = .easeInEaseOut
            launcherGlow.run(.repeatForever(breathe))

            let bodyPulse = SKAction.sequence([
                .scale(to: 1.18, duration: 0.5),
                .scale(to: 1.0, duration: 0.5)
            ])
            bodyPulse.timingMode = .easeInEaseOut
            launcherNode.run(.repeatForever(bodyPulse), withKey: "pulse")
        } else {
            launcherGlow.run(.fadeAlpha(to: 0, duration: 0.18))
            launcherNode.run(.scale(to: 1.0, duration: 0.18))
        }
    }

    private func spawnBallTrails(currentTime: TimeInterval) {
        for ball in state.balls where ball.isActive && !ball.isFinished {
            let last = ballTrailLastSpawn[ball.id] ?? 0
            guard currentTime - last >= Self.trailSpawnInterval else { continue }
            ballTrailLastSpawn[ball.id] = currentTime
            spawnTrailDot(at: scenePoint(for: ball.position))
        }
        // Cleanup stale trail spawn entries
        let activeIDs = Set(state.balls.filter { $0.isActive && !$0.isFinished }.map(\.id))
        ballTrailLastSpawn = ballTrailLastSpawn.filter { activeIDs.contains($0.key) }
    }

    private func spawnTrailDot(at point: CGPoint) {
        let dot = trailPool.popLast() ?? makeTrailDot()
        dot.position = point
        dot.alpha = 0.55
        dot.setScale(1.0)
        if dot.parent == nil { trailLayer.addChild(dot) }

        let fade = SKAction.group([
            .fadeOut(withDuration: 0.32),
            .scale(to: 0.35, duration: 0.32)
        ])
        fade.timingMode = .easeOut
        dot.run(.sequence([fade, .run { [weak self, weak dot] in
            guard let self, let dot else { return }
            dot.removeFromParent()
            self.trailPool.append(dot)
        }]))
    }

    private func makeTrailDot() -> SKShapeNode {
        let radius = max(3, min(size.width, size.height) * 0.010)
        let dot = SKShapeNode(circleOfRadius: radius)
        dot.fillColor = Palette.accent.withAlphaComponent(0.7)
        dot.strokeColor = .clear
        return dot
    }

    private func playFailAnimation() {
        AudioManager.shared.play(.gameOver)
        failOverlay.removeAllActions()
        failOverlay.alpha = 0
        failOverlay.isHidden = false

        for node in brickNodes.values {
            node.removeAction(forKey: "fail")
            let jitter = SKAction.sequence([
                .moveBy(x: -4, y: 0, duration: 0.035),
                .moveBy(x: 8, y: 0, duration: 0.07),
                .moveBy(x: -4, y: 0, duration: 0.035)
            ])
            let dim = SKAction.fadeAlpha(to: 0.45, duration: 0.6)
            node.run(.group([.repeat(jitter, count: 3), dim]), withKey: "fail")
        }

        let pulse = SKAction.sequence([
            .fadeAlpha(to: 0.42, duration: 0.10),
            .fadeAlpha(to: 0.10, duration: 0.18),
            .fadeAlpha(to: 0.28, duration: 0.10),
            .fadeAlpha(to: 0.0, duration: 0.45),
            .hide()
        ])
        failOverlay.run(pulse)

        statusLabel.alpha = 0
        statusLabel.text = "TAP TO RESTART"
        statusLabel.run(.sequence([
            .wait(forDuration: 0.55),
            .fadeAlpha(to: 0.95, duration: 0.35)
        ]))
        requestShake(intensity: 5, duration: 0.4)
    }

    private func dequeueBrickNode() -> SKShapeNode {
        if let node = unusedBrickNodes.popLast() {
            node.alpha = 1
            node.xScale = 1
            node.yScale = 1
            return node
        }

        let node = SKShapeNode()
        node.lineWidth = 1

        let shadow = SKShapeNode()
        shadow.name = "shadow"
        shadow.fillColor = SKColor(white: 0, alpha: 0.45)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 1.5, y: -2.5)
        shadow.zPosition = -1
        node.addChild(shadow)

        let highlight = SKShapeNode()
        highlight.name = "highlight"
        highlight.fillColor = .clear
        highlight.strokeColor = SKColor(white: 1, alpha: 0.18)
        highlight.lineWidth = 1
        highlight.zPosition = 0.5
        node.addChild(highlight)

        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.name = "hp"
        label.fontColor = .white
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.zPosition = 1
        node.addChild(label)
        return node
    }

    private func recycleBrickNode(id: String, node: SKShapeNode) {
        brickNodes[id] = nil
        brickHitPointsByID[id] = nil
        node.removeAllActions()
        node.alpha = 1
        node.xScale = 1
        node.yScale = 1
        node.removeFromParent()
        unusedBrickNodes.append(node)
    }

    private func animateBrickBreak(id: String, node: SKShapeNode) {
        brickNodes[id] = nil
        brickHitPointsByID[id] = nil
        node.removeAllActions()

        let pop = SKAction.group([
            .scale(to: 1.32, duration: 0.14),
            .fadeOut(withDuration: 0.18)
        ])
        pop.timingMode = .easeOut

        node.run(pop) { [weak self, weak node] in
            guard let self, let node else { return }
            node.removeFromParent()
            node.alpha = 1
            node.xScale = 1
            node.yScale = 1
            self.unusedBrickNodes.append(node)
        }
    }

    private func animateBrickDamage(node: SKShapeNode, rect: CGRect) {
        node.removeAction(forKey: "damage")
        node.xScale = 1
        node.yScale = 1

        let punch = SKAction.sequence([
            .scale(to: 1.10, duration: 0.045),
            .scale(to: 0.96, duration: 0.055),
            .scale(to: 1.0, duration: 0.08)
        ])
        punch.timingMode = .easeOut
        node.run(punch, withKey: "damage")
    }

    private func brickColor(for brick: Brick) -> SKColor {
        let healthScale = max(4, state.turn + 5)
        let normalizedHealth = min(1, Double(brick.hitPoints) / Double(healthScale))
        let hue = CGFloat(0.58 - 0.58 * normalizedHealth)
        let saturation = CGFloat(0.62 + 0.30 * normalizedHealth)
        let brightness = CGFloat(0.55 + 0.30 * min(1, normalizedHealth + 0.18))
        return SKColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
    }

    private func brickStrokeColor(for brick: Brick) -> SKColor {
        let healthScale = max(4, state.turn + 5)
        let normalizedHealth = min(1, Double(brick.hitPoints) / Double(healthScale))
        return SKColor(white: 0.85 + 0.15 * CGFloat(1 - normalizedHealth), alpha: 0.32)
    }

    private func dequeueBallNode() -> SKShapeNode {
        if let node = unusedBallNodes.popLast() {
            node.alpha = 1
            return node
        }

        let radius = max(4, min(size.width, size.height) * 0.014)
        let node = SKShapeNode(circleOfRadius: radius)
        node.fillColor = .white
        node.strokeColor = Palette.accent
        node.lineWidth = 1
        node.zPosition = 5

        let glow = SKShapeNode(circleOfRadius: radius * 2.4)
        glow.fillColor = Palette.accent.withAlphaComponent(0.18)
        glow.strokeColor = .clear
        glow.zPosition = -1
        node.addChild(glow)
        return node
    }

    private func recycleBallNode(id: Int, node: SKShapeNode) {
        ballNodes[id] = nil
        ballTrailLastSpawn[id] = nil
        node.removeAllActions()
        node.removeFromParent()
        unusedBallNodes.append(node)
    }

    private func dequeuePickupNode() -> SKShapeNode {
        if let node = unusedPickupNodes.popLast() {
            node.alpha = 1
            node.xScale = 1
            node.yScale = 1
            return node
        }

        let node = SKShapeNode()
        node.fillColor = .clear
        node.strokeColor = Palette.pickup
        node.lineWidth = 2
        node.zPosition = 4

        let core = SKShapeNode()
        core.name = "core"
        core.fillColor = Palette.pickup.withAlphaComponent(0.85)
        core.strokeColor = .clear
        node.addChild(core)
        return node
    }

    private func recyclePickupNode(id: String, node: SKShapeNode) {
        pickupNodes[id] = nil
        node.removeAllActions()
        node.alpha = 1
        node.xScale = 1
        node.yScale = 1
        node.removeFromParent()
        unusedPickupNodes.append(node)
    }

    private func animatePickupCollection(id: String, node: SKShapeNode) {
        pickupNodes[id] = nil
        node.removeAllActions()

        let burst = SKShapeNode(circleOfRadius: 8)
        burst.position = node.position
        burst.fillColor = Palette.pickup.withAlphaComponent(0.30)
        burst.strokeColor = Palette.pickup
        burst.lineWidth = 2
        burst.zPosition = node.zPosition + 1
        worldNode.addChild(burst)

        let burstAction = SKAction.group([
            .scale(to: 3.4, duration: 0.28),
            .fadeOut(withDuration: 0.28)
        ])
        burstAction.timingMode = .easeOut
        burst.run(.sequence([burstAction, .removeFromParent()]))

        let collect = SKAction.group([
            .scale(to: 1.95, duration: 0.16),
            .fadeOut(withDuration: 0.18)
        ])
        collect.timingMode = .easeOut

        node.run(collect) { [weak self, weak node] in
            guard let self, let node else { return }
            node.removeFromParent()
            node.alpha = 1
            node.xScale = 1
            node.yScale = 1
            self.unusedPickupNodes.append(node)
        }
    }

    private func scenePoint(for point: Vec2) -> CGPoint {
        CGPoint(x: point.x * Double(size.width), y: point.y * Double(size.height))
    }

    private func sceneRect(for brick: Brick) -> CGRect {
        sceneRect(column: brick.column, row: brick.row)
    }

    private func sceneRect(column: Int, row: Int) -> CGRect {
        let rect = GameEngine.brickRect(column: column, row: row)
        let minX = rect.minX * Double(size.width)
        let maxX = rect.maxX * Double(size.width)
        let minY = rect.minY * Double(size.height)
        let maxY = rect.maxY * Double(size.height)
        let insetX = max(2, (maxX - minX) * 0.045)
        let insetY = max(2, (maxY - minY) * 0.12)
        return CGRect(x: minX + insetX, y: minY + insetY, width: maxX - minX - insetX * 2, height: maxY - minY - insetY * 2)
    }
}

private extension CGPoint {
    func distance(to point: CGPoint) -> Double {
        let dx = x - point.x
        let dy = y - point.y
        return sqrt(Double(dx * dx + dy * dy))
    }
}
