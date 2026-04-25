import SpriteKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
private enum Palette {
    static var usesLight: Bool = false

    private static var mode: Theme.Mode { usesLight ? .light : .dark }
    private static var theme: Theme.Palette { Theme.palette(for: mode) }

    static var background: SKColor { theme.background.sk }
    static var accent: SKColor     { theme.accent.sk }
    static var launcher: SKColor   { theme.launcher.sk }
    static var pickup: SKColor     { theme.pickup.sk }
    static var danger: SKColor     { theme.destructive.sk }
    static var textPrimary: SKColor   { theme.textPrimary.sk }
    static var textSecondary: SKColor { theme.textSecondary.sk }
    static var border: SKColor     { theme.border.sk }
}

@MainActor
private final class LaunchFeedback {
#if canImport(UIKit)
    private let generator = UIImpactFeedbackGenerator(style: .medium)
#endif

    func prepare() {
#if canImport(UIKit)
        generator.prepare()
#endif
    }

    func impactOccurred(intensity: CGFloat) {
#if canImport(UIKit)
        generator.impactOccurred(intensity: intensity)
#endif
    }
}

@MainActor
private final class ComboFeedback {
#if canImport(UIKit)
    private let generator = UINotificationFeedbackGenerator()
#endif

    func prepare() {
#if canImport(UIKit)
        generator.prepare()
#endif
    }

    func success() {
#if canImport(UIKit)
        generator.notificationOccurred(.success)
#endif
    }
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
    private let worldNode = SKNode()
    private let trailLayer = SKNode()
    private let effectsLayer = SKNode()
    private let hudNode = SKNode()
    private let scoreLabel = SKLabelNode(fontNamed: Theme.FontName.bold)
    private let bestLabel = SKLabelNode(fontNamed: Theme.FontName.medium)
    private let statusLabel = SKLabelNode(fontNamed: Theme.FontName.semibold)
    private let hintLabel = SKLabelNode(fontNamed: Theme.FontName.regular)
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

    private var dragOrigin: CGPoint?
    private var currentDrag: CGPoint?
    private var aimStartPoint = CGPoint.zero
    private var aimEndPoint = CGPoint.zero
    private var aimDotPhase: CGFloat = 0
    private let launchFeedbackGenerator = LaunchFeedback()
    private let comboFeedbackGenerator = ComboFeedback()
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
    private var lastBackgroundSize: CGSize = .zero
    private var topSafeArea: CGFloat = 0
    private var bottomSafeArea: CGFloat = 0
    private var usesLightAppearance = false {
        didSet { Palette.usesLight = usesLightAppearance }
    }

    var onGameOverChange: ((Bool) -> Void)?
    private var lastReportedGameOver = false

    private var themePalette: Theme.Palette {
        Theme.palette(for: usesLightAppearance ? Theme.Mode.light : Theme.Mode.dark)
    }

    private var sceneBackgroundColor: SKColor { themePalette.background.sk }
    private var hudPrimaryColor: SKColor      { themePalette.textPrimary.sk }
    private var hudSecondaryColor: SKColor    { themePalette.textSecondary.sk }
    private var ceilingBoundaryColor: SKColor { themePalette.border.sk.withAlphaComponent(0.45) }
    private var dangerBoundaryColor: SKColor  { themePalette.border.sk.withAlphaComponent(0.30) }
    private var sideBoundaryColor: SKColor    { themePalette.border.sk.withAlphaComponent(0.22) }
    private var ballFillColor: SKColor        { themePalette.textPrimary.sk }

    init(store: SaveStore) {
        self.store = store
        let loadedState = Self.normalizedLoadedState((try? store.loadSession()) ?? GameEngine.newGame())
        state = loadedState
        lastCompletedState = loadedState
        highScores = (try? store.loadHighScores()) ?? []
        super.init(size: CGSize(width: 390, height: 844))
        backgroundColor = sceneBackgroundColor
    }

    required init?(coder aDecoder: NSCoder) {
        store = SaveStore()
        let loadedState = Self.normalizedLoadedState((try? store.loadSession()) ?? GameEngine.newGame())
        state = loadedState
        lastCompletedState = loadedState
        highScores = (try? store.loadHighScores()) ?? []
        super.init(coder: aDecoder)
        backgroundColor = sceneBackgroundColor
    }

    private static func normalizedLoadedState(_ loadedState: GameState) -> GameState {
        var state = loadedState
        if state.turn == 1, state.score == 0, state.balls.isEmpty {
            state.launcher = GameConfig.launcher
        }
        return state
    }

    override func didMove(to view: SKView) {
#if canImport(UIKit)
        view.isMultipleTouchEnabled = false
#endif
        view.preferredFramesPerSecond = 120
        refreshSafeArea(from: view)
        setupScene()
        renderAll()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        if let view { refreshSafeArea(from: view) }
        layoutStaticNodes()
        renderAll()
    }

    private func refreshSafeArea(from view: SKView) {
        topSafeArea = view.safeAreaInsets.top
        bottomSafeArea = view.safeAreaInsets.bottom
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

#if canImport(UIKit)
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        beginDrag(at: touch.location(in: self))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard dragOrigin != nil, let touch = touches.first else { return }
        updateDrag(to: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        finishDrag()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelDrag()
    }
#endif

#if os(macOS)
    override func mouseDown(with event: NSEvent) {
        beginDrag(at: event.location(in: self))
    }

    override func mouseDragged(with event: NSEvent) {
        updateDrag(to: event.location(in: self))
    }

    override func mouseUp(with event: NSEvent) {
        finishDrag()
    }

    override func mouseExited(with event: NSEvent) {
        cancelDrag()
    }
#endif

    func persistCompletedTurn() {
        try? store.saveSession(lastCompletedState)
    }

    func setLightAppearance(_ isLight: Bool) {
        guard usesLightAppearance != isLight else { return }
        usesLightAppearance = isLight
        applyTheme()
    }

    private func setupScene() {
        removeAllChildren()
        backgroundColor = sceneBackgroundColor

        addChild(backgroundLayer)
        backgroundLayer.zPosition = -100
        backgroundLayer.addChild(backgroundSprite)

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
        scoreLabel.fontColor = hudPrimaryColor
        bestLabel.fontColor = hudSecondaryColor
        statusLabel.fontColor = hudPrimaryColor
        hintLabel.fontColor = hudSecondaryColor
        hintLabel.alpha = 0

        launcherGlow.fillColor = Palette.launcher.withAlphaComponent(0.18)
        launcherGlow.strokeColor = .clear
        launcherGlow.alpha = 0
        launcherGlow.zPosition = 1
        worldNode.addChild(launcherGlow)

        launcherNode.fillColor = Palette.launcher
        launcherNode.strokeColor = Palette.accent.withAlphaComponent(0.7)
        launcherNode.lineWidth = 1
        launcherNode.zPosition = 2
        worldNode.addChild(launcherNode)

        aimLine.isHidden = true
        aimLine.zPosition = 3
        worldNode.addChild(aimLine)

        ceilingLine.lineCap = .round
        worldNode.addChild(ceilingLine)

        dangerLine.lineCap = .round
        worldNode.addChild(dangerLine)

        [leftBoundaryLine, rightBoundaryLine].forEach {
            $0.lineCap = .round
            worldNode.addChild($0)
        }
        applyBounceBoundaryStyle(isAiming: false)

        failOverlay.fillColor = SKColor(red: 0.78, green: 0.10, blue: 0.08, alpha: 1.0)
        failOverlay.strokeColor = .clear
        failOverlay.zPosition = 150
        failOverlay.alpha = 0
        failOverlay.isHidden = true
        addChild(failOverlay)

        applyTheme()

        layoutStaticNodes()
    }

    private func applyTheme() {
        backgroundColor = sceneBackgroundColor
        backgroundSprite.color = sceneBackgroundColor
        scoreLabel.fontColor = hudPrimaryColor
        bestLabel.fontColor = hudSecondaryColor
        statusLabel.fontColor = hudPrimaryColor
        hintLabel.fontColor = hudSecondaryColor
        launcherNode.strokeColor = Palette.accent.withAlphaComponent(0.7)
        launcherNode.fillColor = Palette.launcher
        ballNodes.values.forEach { updateBallNodeTheme($0) }
        unusedBallNodes.forEach { updateBallNodeTheme($0) }
        if brickNodes.isEmpty {
            updateDangerLine()
        } else {
            renderBricks()
        }
    }

    private func layoutStaticNodes() {
        rebuildSolidBackgroundIfNeeded()

        scoreLabel.fontSize = 30
        bestLabel.fontSize = 10
        statusLabel.fontSize = 13
        hintLabel.fontSize = 12

        launcherNode.position = scenePoint(for: state.launcher)
        launcherGlow.position = launcherNode.position

        let ceilingY = size.height * GameConfig.topWall
        let dangerY = size.height * GameConfig.boardBottom
        let launcherY = size.height * GameConfig.launcher.y

        let hudTopAvailable = size.height - max(topSafeArea, 10) - 8
        let scoreY = max(ceilingY + 24, hudTopAvailable - 18)
        let bestY = max(ceilingY + 8, scoreY - 26)
        scoreLabel.position = CGPoint(x: size.width * 0.5, y: scoreY)
        bestLabel.position = CGPoint(x: size.width * 0.5, y: bestY)

        let statusY = max(bottomSafeArea + 16, launcherY * 0.45)
        statusLabel.position = CGPoint(x: size.width * 0.5, y: statusY)
        let hintY = (launcherY + dangerY) * 0.5
        hintLabel.position = CGPoint(x: size.width * 0.5, y: hintY)

        let ceilingPath = CGMutablePath()
        ceilingPath.move(to: CGPoint(x: size.width * GameConfig.leftWall, y: ceilingY))
        ceilingPath.addLine(to: CGPoint(x: size.width * GameConfig.rightWall, y: ceilingY))
        ceilingLine.path = ceilingPath

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

    private func rebuildSolidBackgroundIfNeeded() {
        guard size.width > 0, size.height > 0, size != lastBackgroundSize else { return }
        lastBackgroundSize = size
        backgroundSprite.size = size
        backgroundSprite.position = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        backgroundSprite.texture = nil
        backgroundSprite.color = sceneBackgroundColor
        backgroundSprite.colorBlendFactor = 1
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
        let effectText = state.queuedMysteryEffect.map { "   NEXT \($0.shortLabel)" } ?? ""
        bestLabel.text = "BEST \(bestScore)   TURN \(state.turn)   BALLS \(state.ballCount)\(effectText)"
        if state.isGameOver {
            statusLabel.text = ""
            statusLabel.alpha = 0
        } else {
            statusLabel.text = "SWIPE TO LAUNCH"
            statusLabel.alpha = state.balls.isEmpty ? 0.5 : 0
        }
    }

    private func updateHintVisibility() {
        let shouldShow = !state.isGameOver
            && state.turn == 1
            && state.score == 0
            && state.balls.isEmpty
            && !hasUsedFirstHint
        if shouldShow {
            hintLabel.text = "pull down to aim ↓"
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
            let cornerRadius = max(7, min(rect.width, rect.height) * 0.22)
            let bodyRect = CGRect(x: -rect.width * 0.5, y: -rect.height * 0.5, width: rect.width, height: rect.height)
            let bodyPath = CGPath(
                roundedRect: bodyRect,
                cornerWidth: cornerRadius,
                cornerHeight: cornerRadius,
                transform: nil
            )
            let style = brickGlassStyle(for: brick)
            node.path = bodyPath
            node.fillColor = style.bodyFill
            node.strokeColor = style.outerRim
            node.lineWidth = max(1.5, min(rect.width, rect.height) * 0.045)
            node.glowWidth = usesLightAppearance ? 0.8 : 1.4

            if let shadow = node.childNode(withName: "shadow") as? SKShapeNode {
                shadow.path = bodyPath
                shadow.fillColor = style.shadow
                shadow.position = CGPoint(x: rect.width * 0.035, y: -rect.height * 0.07)
            }
            if let innerRim = node.childNode(withName: "innerRim") as? SKShapeNode {
                let inset = max(2.0, min(rect.width, rect.height) * 0.075)
                innerRim.path = CGPath(
                    roundedRect: bodyRect.insetBy(dx: inset, dy: inset),
                    cornerWidth: max(2, cornerRadius - inset),
                    cornerHeight: max(2, cornerRadius - inset),
                    transform: nil
                )
                innerRim.strokeColor = style.innerRim
                innerRim.lineWidth = max(0.8, min(rect.width, rect.height) * 0.026)
            }
            if let topSheen = node.childNode(withName: "topSheen") as? SKShapeNode {
                topSheen.path = CGPath(
                    roundedRect: CGRect(
                        x: -rect.width * 0.34,
                        y: rect.height * 0.16,
                        width: rect.width * 0.50,
                        height: rect.height * 0.17
                    ),
                    cornerWidth: rect.height * 0.085,
                    cornerHeight: rect.height * 0.085,
                    transform: nil
                )
                topSheen.fillColor = style.topSheen
            }
            if let gloss = node.childNode(withName: "gloss") as? SKShapeNode {
                gloss.path = CGPath(
                    ellipseIn: CGRect(
                        x: rect.width * 0.18,
                        y: rect.height * 0.22,
                        width: rect.width * 0.22,
                        height: rect.height * 0.12
                    ),
                    transform: nil
                )
                gloss.fillColor = style.gloss
            }
            let label = node.childNode(withName: "hp") as? SKLabelNode
            label?.text = "\(brick.hitPoints)"
            label?.fontColor = style.label
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
        guard dragOrigin == nil else {
            applyBounceBoundaryStyle(isAiming: true)
            return
        }

        let lowestRow = state.bricks.map(\.row).max() ?? 0
        applyBounceBoundaryStyle(isAiming: false)
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
        }
    }

    private func applyBounceBoundaryStyle(isAiming: Bool) {
        ceilingLine.strokeColor = isAiming ? Palette.accent.withAlphaComponent(0.72) : ceilingBoundaryColor
        ceilingLine.lineWidth = isAiming ? 2.5 : 1.5

        dangerLine.removeAction(forKey: "pulse")
        dangerLine.alpha = 1
        dangerLine.strokeColor = isAiming ? Palette.accent.withAlphaComponent(0.55) : dangerBoundaryColor
        dangerLine.lineWidth = isAiming ? 2.0 : 1.0

        [leftBoundaryLine, rightBoundaryLine].forEach {
            $0.strokeColor = isAiming ? Palette.accent.withAlphaComponent(0.42) : sideBoundaryColor
            $0.lineWidth = isAiming ? 1.75 : 1.0
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
            updatePickupNode(node, for: pickup.kind)
            if let core = node.childNode(withName: "core") as? SKShapeNode {
                let coreRadius = radius * 0.45
                core.path = CGPath(ellipseIn: CGRect(x: -coreRadius, y: -coreRadius, width: coreRadius * 2, height: coreRadius * 2), transform: nil)
            }
            if let label = node.childNode(withName: "label") as? SKLabelNode {
                label.fontSize = radius * 1.35
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

    private func beginDrag(at point: CGPoint) {
        if state.isGameOver {
            startNewGame()
            return
        }

        guard state.balls.isEmpty else { return }

        dragOrigin = point
        currentDrag = point
        resetLaunchFeedback()
        launchFeedbackGenerator.prepare()
        comboFeedbackGenerator.prepare()
        animateLauncherPulse(active: true)
        applyBounceBoundaryStyle(isAiming: true)
        hideHintLabel()
        updateAimPreview()
    }

    private func updateDrag(to point: CGPoint) {
        guard dragOrigin != nil else { return }
        currentDrag = point
        updateAimPreview()
    }

    private func finishDrag() {
        defer {
            resetLaunchFeedback()
            animateLauncherPulse(active: false)
            clearAimPreview()
        }
        guard state.balls.isEmpty, !state.isGameOver, let aim = currentAimIntent() else { return }

        hasUsedFirstHint = true
        AudioManager.shared.play(.launch)
        emitLauncherRing()
        GameEngine.beginLaunch(state: &state, direction: aim.direction, pullDistance: aim.distance)
        comboCount = 0
        didHaveBallsInFlight = true
        renderDynamicNodes()
    }

    private func cancelDrag() {
        animateLauncherPulse(active: false)
        clearAimPreview()
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
        notifyGameOverChange()
    }

    private func updateAimPreview() {
        guard let aim = currentAimIntent() else {
            hideAimPreview()
            return
        }

        let launcherPoint = scenePoint(for: state.launcher)
        let previewLength = 110 + 190 * aim.strength
        let sceneDirection = sceneUnitVector(for: aim.direction)

        let end = CGPoint(
            x: launcherPoint.x + sceneDirection.dx * previewLength,
            y: launcherPoint.y + sceneDirection.dy * previewLength
        )

        aimStartPoint = launcherPoint
        aimEndPoint = end
        aimLine.alpha = 0.45 + 0.45 * aim.strength
        aimLine.isHidden = false
        layoutAimDots(strength: CGFloat(aim.strength))
        startAimLineAnimationIfNeeded()
        triggerStrengthFeedbackIfNeeded(strength: aim.strength)
    }

    private func currentAimIntent() -> (direction: Vec2, strength: Double, distance: Double)? {
        guard let origin = dragOrigin, let current = currentDrag, size.width > 0, size.height > 0 else { return nil }

        let pull = Vec2(x: Double(origin.x - current.x) / Double(size.width), y: Double(origin.y - current.y) / Double(size.height))
        let distance = origin.distance(to: current) / min(size.width, size.height)
        guard distance > 0.035, let direction = GameEngine.validAimVector(fromPull: pull, launcher: state.launcher) else {
            return nil
        }

        return (direction, GameEngine.launchStrength(forPullDistance: distance), distance)
    }

    private func clearAimPreview() {
        resetLaunchFeedback()
        dragOrigin = nil
        currentDrag = nil
        hideAimPreview()
        updateDangerLine()
    }

    private func hideAimPreview() {
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
            requestShake(intensity: 0.7, duration: 0.07)
            AudioManager.shared.play(.brickHit)
        }

        var combosThisFrame = 0
        for breakPoint in events.brickBreaks {
            comboCount += 1
            combosThisFrame += 1
            spawnImpactSpark(at: scenePoint(for: breakPoint), color: Palette.accent, radius: 8)
            spawnComboLabelIfNeeded(at: scenePoint(for: breakPoint))
            requestShake(intensity: 1.4, duration: 0.10)
            AudioManager.shared.play(.brickBreak)
        }

        if combosThisFrame > 0 && hitStopUntil < currentTime {
            hitStopUntil = currentTime + 0.05
        }

        for pickup in events.pickups {
            let color = pickup.kind == .mystery ? Palette.accent : Palette.pickup
            spawnImpactSpark(at: scenePoint(for: pickup.position), color: color, radius: pickup.kind == .mystery ? 12 : 10)
            if let effect = pickup.mysteryEffect {
                spawnMysteryEffectLabel(effect, at: scenePoint(for: pickup.position))
            }
            AudioManager.shared.play(.pickup)
        }
    }

    private func requestShake(intensity: CGFloat, duration: TimeInterval) {
        shakeIntensity = min(3.0, shakeIntensity + intensity)
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
        let label = SKLabelNode(fontNamed: Theme.FontName.bold)
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
            comboFeedbackGenerator.success()
            comboFeedbackGenerator.prepare()
        }
    }

    private func spawnMysteryEffectLabel(_ effect: MysteryPowerEffect, at point: CGPoint) {
        let label = SKLabelNode(fontNamed: Theme.FontName.bold)
        label.text = effect.shortLabel
        label.fontSize = 15
        label.fontColor = Palette.accent
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.position = point
        label.zPosition = 90
        effectsLayer.addChild(label)

        let move = SKAction.group([
            .moveBy(x: 0, y: 28, duration: 0.45),
            .fadeOut(withDuration: 0.45),
            .scale(to: 1.25, duration: 0.45)
        ])
        move.timingMode = .easeOut
        label.run(.sequence([move, .removeFromParent()]))
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
            let dim = SKAction.fadeAlpha(to: 0.35, duration: 0.6)
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

        notifyGameOverChange()
        requestShake(intensity: 5, duration: 0.4)
    }

    private func notifyGameOverChange() {
        if lastReportedGameOver != state.isGameOver {
            lastReportedGameOver = state.isGameOver
            onGameOverChange?(state.isGameOver)
        }
    }

    var currentScore: Int { state.score }
    var currentTurn: Int { state.turn }
    var currentBestScore: Int { highScores.first?.score ?? state.score }
    var isGameOver: Bool { state.isGameOver }

    func restartGame() {
        startNewGame()
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
        shadow.strokeColor = .clear
        shadow.zPosition = -1
        node.addChild(shadow)

        let innerRim = SKShapeNode()
        innerRim.name = "innerRim"
        innerRim.fillColor = .clear
        innerRim.zPosition = 0.35
        node.addChild(innerRim)

        let topSheen = SKShapeNode()
        topSheen.name = "topSheen"
        topSheen.strokeColor = .clear
        topSheen.zPosition = 0.45
        node.addChild(topSheen)

        let gloss = SKShapeNode()
        gloss.name = "gloss"
        gloss.strokeColor = .clear
        gloss.zPosition = 0.55
        node.addChild(gloss)

        let label = SKLabelNode(fontNamed: Theme.FontName.bold)
        label.name = "hp"
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

    private struct BrickGlassStyle {
        let bodyFill: SKColor
        let outerRim: SKColor
        let innerRim: SKColor
        let shadow: SKColor
        let topSheen: SKColor
        let gloss: SKColor
        let label: SKColor
    }

    private func brickGlassStyle(for brick: Brick) -> BrickGlassStyle {
        let healthTint = mutedBrickTint(for: brick)

        if usesLightAppearance {
            let body = SKColor(hex: 0xF3EEE3, alpha: 0.50)
                .blended(to: healthTint, fraction: 0.46)
                .withAlphaComponent(0.56)
            let outer = SKColor(white: 1, alpha: 0.82)
                .blended(to: healthTint, fraction: 0.42)
                .withAlphaComponent(0.88)
            let inner = SKColor(hex: 0xFFFFFF, alpha: 0.38)
                .blended(to: healthTint, fraction: 0.20)
                .withAlphaComponent(0.42)
            let label = SKColor(hex: 0x2F2823, alpha: 0.92)
                .blended(to: healthTint, fraction: 0.26)
                .withAlphaComponent(0.95)

            return BrickGlassStyle(
                bodyFill: body,
                outerRim: outer,
                innerRim: inner,
                shadow: healthTint.withAlphaComponent(0.20),
                topSheen: SKColor(white: 1, alpha: 0.30),
                gloss: SKColor(white: 1, alpha: 0.48),
                label: label
            )
        }

        let body = SKColor(hex: 0x3D4646, alpha: 0.30)
            .blended(to: healthTint, fraction: 0.52)
            .withAlphaComponent(0.34)
        let outer = SKColor(hex: 0xDCE8E5, alpha: 0.58)
            .blended(to: healthTint, fraction: 0.52)
            .withAlphaComponent(0.68)
        let inner = SKColor(hex: 0xFFFFFF, alpha: 0.20)
            .blended(to: healthTint, fraction: 0.24)
            .withAlphaComponent(0.24)
        let label = Palette.textPrimary
            .blended(to: healthTint, fraction: 0.22)
            .withAlphaComponent(0.96)

        return BrickGlassStyle(
            bodyFill: body,
            outerRim: outer,
            innerRim: inner,
            shadow: SKColor(white: 0, alpha: 0.36),
            topSheen: SKColor(white: 1, alpha: 0.16),
            gloss: SKColor(white: 1, alpha: 0.28),
            label: label
        )
    }

    private func mutedBrickTint(for brick: Brick) -> SKColor {
        let base = brickHealthTint(for: brick)
        let neutral = usesLightAppearance
            ? SKColor(hex: 0xD5C8B8)
            : SKColor(hex: 0x8BA09C)
        return neutral.blended(to: base, fraction: usesLightAppearance ? 0.44 : 0.52)
    }

    private func brickHealthTint(for brick: Brick) -> SKColor {
        let healthScale = max(4, state.turn + 5)
        let t = CGFloat(min(1, Double(brick.hitPoints) / Double(healthScale)))
        let healthy = Palette.accent
        let mid = Palette.pickup
        let wounded = Palette.danger
        if t < 0.5 {
            return healthy.blended(to: mid, fraction: t * 2)
        } else {
            return mid.blended(to: wounded, fraction: (t - 0.5) * 2)
        }
    }

    private func dequeueBallNode() -> SKShapeNode {
        if let node = unusedBallNodes.popLast() {
            node.alpha = 1
            return node
        }

        let radius = max(4, min(size.width, size.height) * 0.014)
        let node = SKShapeNode(circleOfRadius: radius)
        node.lineWidth = 1
        node.zPosition = 5

        let glow = SKShapeNode(circleOfRadius: radius * 2.4)
        glow.strokeColor = .clear
        glow.zPosition = -1
        node.addChild(glow)
        updateBallNodeTheme(node)
        return node
    }

    private func updateBallNodeTheme(_ node: SKShapeNode) {
        node.fillColor = Palette.accent
        node.strokeColor = .clear
        node.lineWidth = 0
        if let glow = node.children.first as? SKShapeNode {
            glow.fillColor = Palette.accent.withAlphaComponent(0.22)
        }
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

        let label = SKLabelNode(fontNamed: Theme.FontName.bold)
        label.name = "label"
        label.text = "?"
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.fontColor = .white
        label.zPosition = 1
        node.addChild(label)
        return node
    }

    private func updatePickupNode(_ node: SKShapeNode, for kind: PickupKind) {
        switch kind {
        case .regular:
            node.strokeColor = Palette.pickup
            (node.childNode(withName: "core") as? SKShapeNode)?.fillColor = Palette.pickup.withAlphaComponent(0.85)
            node.childNode(withName: "label")?.isHidden = true
        case .mystery:
            node.strokeColor = Palette.accent
            (node.childNode(withName: "core") as? SKShapeNode)?.fillColor = Palette.accent.withAlphaComponent(0.88)
            node.childNode(withName: "label")?.isHidden = false
        }
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

    private func sceneUnitVector(for direction: Vec2) -> CGVector {
        let dx = CGFloat(direction.x) * size.width
        let dy = CGFloat(direction.y) * size.height
        let length = max(0.000_001, sqrt(dx * dx + dy * dy))
        return CGVector(dx: dx / length, dy: dy / length)
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
