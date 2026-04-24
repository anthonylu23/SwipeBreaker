import Foundation

struct GameConfig {
    static let columns = 7
    static let rows = 9
    static let dangerRow = 9
    static let leftWall = 0.055
    static let rightWall = 0.945
    static let topWall = 0.82
    static let boardTop = 0.80
    static let boardBottom = 0.22
    static let launcher = Vec2(x: 0.5, y: 0.17)
    static let ballRadius = 0.012
    static let minLaunchSpeed = 0.72
    static let maxLaunchSpeed = 1.485
    static let launchStagger = 0.045

    static var cellWidth: Double {
        (rightWall - leftWall) / Double(columns)
    }

    static var cellHeight: Double {
        (boardTop - boardBottom) / Double(rows)
    }
}

struct BrickRect: Equatable {
    var minX: Double
    var maxX: Double
    var minY: Double
    var maxY: Double
}

struct TurnEvents {
    var brickHits: [Vec2] = []
    var brickBreaks: [Vec2] = []
    var pickups: [Vec2] = []
    var wallBounces: Int = 0
    var ballsLanded: Int = 0
    var didFinishTurn: Bool = false

    var isEmpty: Bool {
        brickHits.isEmpty && brickBreaks.isEmpty && pickups.isEmpty && wallBounces == 0 && ballsLanded == 0
    }
}

struct GameEngine {
    static func newGame(seed: UInt64 = UInt64(Date().timeIntervalSince1970)) -> GameState {
        var state = GameState(
            score: 0,
            turn: 1,
            ballCount: 1,
            launcher: GameConfig.launcher,
            bricks: [],
            pickups: [],
            balls: [],
            pendingExtraBalls: 0,
            nextBallID: 1,
            rngSeed: seed == 0 ? 1 : seed,
            isGameOver: false
        )
        spawnNewRow(in: &state)
        return state
    }

    static func brickRect(column: Int, row: Int) -> BrickRect {
        let width = GameConfig.cellWidth
        let height = GameConfig.cellHeight
        let minX = GameConfig.leftWall + Double(column) * width
        let maxY = GameConfig.boardTop - Double(row) * height
        return BrickRect(
            minX: minX,
            maxX: minX + width,
            minY: maxY - height,
            maxY: maxY
        )
    }

    static func normalizedLaunchVector(fromPull pull: Vec2) -> Vec2 {
        var direction = pull.normalized()
        if direction == .zero {
            return Vec2(x: 0, y: 1)
        }
        if direction.y < 0.24 {
            direction.y = 0.24
            direction = direction.normalized()
        }
        return direction
    }

    static func validAimVector(fromPull pull: Vec2, launcher: Vec2 = GameConfig.launcher) -> Vec2? {
        let direction = pull.normalized()
        guard direction != .zero, direction.y > 0 else { return nil }

        if launcher.y < GameConfig.boardBottom {
            let distanceToBounceArea = GameConfig.boardBottom - launcher.y
            let xAtBounceArea = launcher.x + direction.x * (distanceToBounceArea / direction.y)
            let minX = GameConfig.leftWall + GameConfig.ballRadius
            let maxX = GameConfig.rightWall - GameConfig.ballRadius
            guard xAtBounceArea >= minX, xAtBounceArea <= maxX else { return nil }
        }

        return direction
    }

    static func launchStrength(forPullDistance distance: Double) -> Double {
        min(1, max(0, distance / 0.22))
    }

    static func beginLaunch(state: inout GameState, pull: Vec2, pullDistance: Double) {
        beginLaunch(state: &state, direction: normalizedLaunchVector(fromPull: pull), pullDistance: pullDistance)
    }

    static func beginLaunch(state: inout GameState, direction: Vec2, pullDistance: Double) {
        guard !state.isGameOver, state.balls.isEmpty else { return }

        let direction = direction.normalized()
        guard direction != .zero else { return }

        let strength = launchStrength(forPullDistance: pullDistance)
        let speed = GameConfig.minLaunchSpeed + (GameConfig.maxLaunchSpeed - GameConfig.minLaunchSpeed) * strength
        let velocity = direction * speed

        state.balls = (0..<state.ballCount).map { index in
            defer { state.nextBallID += 1 }
            return BallState(
                id: state.nextBallID,
                position: state.launcher,
                previousPosition: state.launcher,
                velocity: velocity,
                launchDelay: Double(index) * GameConfig.launchStagger,
                isActive: false,
                isFinished: false
            )
        }
    }

    @discardableResult
    static func stepActiveTurn(state: inout GameState, dt: Double) -> Bool {
        var events = TurnEvents()
        return stepActiveTurn(state: &state, dt: dt, events: &events)
    }

    @discardableResult
    static func stepActiveTurn(state: inout GameState, dt: Double, events: inout TurnEvents) -> Bool {
        guard !state.isGameOver, !state.balls.isEmpty else { return false }

        for index in state.balls.indices {
            guard !state.balls[index].isFinished else { continue }

            if state.balls[index].launchDelay > 0 {
                state.balls[index].launchDelay = max(0, state.balls[index].launchDelay - dt)
                continue
            }

            state.balls[index].isActive = true
            moveBall(index: index, state: &state, dt: dt, events: &events)
        }

        if state.balls.allSatisfy(\.isFinished) {
            resolveTurn(state: &state)
            events.didFinishTurn = true
            return true
        }

        return false
    }

    static func resolveTurn(state: inout GameState) {
        state.balls.removeAll(keepingCapacity: true)
        state.ballCount += state.pendingExtraBalls
        state.pendingExtraBalls = 0
        state.turn += 1

        state.bricks = state.bricks.map {
            Brick(column: $0.column, row: $0.row + 1, hitPoints: $0.hitPoints, maxHitPoints: $0.maxHitPoints)
        }
        state.pickups = state.pickups.map {
            ExtraBallPickup(column: $0.column, row: $0.row + 1)
        }.filter { $0.row < GameConfig.dangerRow }

        if state.bricks.contains(where: { $0.row >= GameConfig.dangerRow }) {
            state.isGameOver = true
            return
        }

        spawnNewRow(in: &state)
    }

    static func insertingHighScore(_ entry: HighScoreEntry, into scores: [HighScoreEntry]) -> [HighScoreEntry] {
        Array((scores + [entry])
            .sorted {
                if $0.score == $1.score {
                    return $0.turn > $1.turn
                }
                return $0.score > $1.score
            }
            .prefix(10))
    }

    private static func moveBall(index: Int, state: inout GameState, dt: Double, events: inout TurnEvents) {
        state.balls[index].previousPosition = state.balls[index].position
        var position = state.balls[index].position + state.balls[index].velocity * dt
        var velocity = state.balls[index].velocity

        if position.x - GameConfig.ballRadius <= GameConfig.leftWall {
            position.x = GameConfig.leftWall + GameConfig.ballRadius
            velocity.x = abs(velocity.x)
            events.wallBounces += 1
        } else if position.x + GameConfig.ballRadius >= GameConfig.rightWall {
            position.x = GameConfig.rightWall - GameConfig.ballRadius
            velocity.x = -abs(velocity.x)
            events.wallBounces += 1
        }

        if position.y + GameConfig.ballRadius >= GameConfig.topWall {
            position.y = GameConfig.topWall - GameConfig.ballRadius
            velocity.y = -abs(velocity.y)
            events.wallBounces += 1
        }

        if position.y <= state.launcher.y && velocity.y < 0 {
            let previousPosition = state.balls[index].previousPosition
            let travelY = position.y - previousPosition.y
            let crossingProgress = travelY == 0 ? 1 : (state.launcher.y - previousPosition.y) / travelY
            let landingX = previousPosition.x + (position.x - previousPosition.x) * min(1, max(0, crossingProgress))
            let clampedLandingX = min(
                GameConfig.rightWall - GameConfig.ballRadius,
                max(GameConfig.leftWall + GameConfig.ballRadius, landingX)
            )

            if !state.balls.contains(where: \.isFinished) {
                state.launcher = Vec2(x: clampedLandingX, y: GameConfig.launcher.y)
            }

            state.balls[index].position = state.launcher
            state.balls[index].previousPosition = state.launcher
            state.balls[index].velocity = .zero
            state.balls[index].isActive = false
            state.balls[index].isFinished = true
            events.ballsLanded += 1
            return
        }

        handlePickupCollision(position: position, state: &state, events: &events)
        handleBrickCollision(position: &position, previousPosition: state.balls[index].previousPosition, velocity: &velocity, state: &state, events: &events)

        state.balls[index].position = position
        state.balls[index].velocity = velocity
    }

    private static func handlePickupCollision(position: Vec2, state: inout GameState, events: inout TurnEvents) {
        guard let pickupIndex = state.pickups.firstIndex(where: { pickup in
            let rect = brickRect(column: pickup.column, row: pickup.row)
            let center = Vec2(x: (rect.minX + rect.maxX) * 0.5, y: (rect.minY + rect.maxY) * 0.5)
            return (position - center).length <= GameConfig.cellHeight * 0.30
        }) else {
            return
        }

        let pickup = state.pickups[pickupIndex]
        let rect = brickRect(column: pickup.column, row: pickup.row)
        events.pickups.append(Vec2(x: (rect.minX + rect.maxX) * 0.5, y: (rect.minY + rect.maxY) * 0.5))
        state.pickups.remove(at: pickupIndex)
        state.pendingExtraBalls += 1
    }

    private static func handleBrickCollision(position: inout Vec2, previousPosition: Vec2, velocity: inout Vec2, state: inout GameState, events: inout TurnEvents) {
        let candidateColumn = Int((position.x - GameConfig.leftWall) / GameConfig.cellWidth)
        let candidateRow = Int((GameConfig.boardTop - position.y) / GameConfig.cellHeight)
        let minRow = max(0, candidateRow - 1)
        let maxRow = min(GameConfig.rows - 1, candidateRow + 1)
        let minColumn = max(0, candidateColumn - 1)
        let maxColumn = min(GameConfig.columns - 1, candidateColumn + 1)

        guard minRow <= maxRow, minColumn <= maxColumn else {
            return
        }

        for row in minRow...maxRow {
            for column in minColumn...maxColumn {
                guard let brickIndex = state.bricks.firstIndex(where: { $0.column == column && $0.row == row }) else {
                    continue
                }

                let rect = brickRect(column: column, row: row)
                guard circleIntersects(rect: rect, center: position, radius: GameConfig.ballRadius) else {
                    continue
                }

                let fromSide = previousPosition.x <= rect.minX || previousPosition.x >= rect.maxX
                if fromSide {
                    velocity.x *= -1
                    position.x += velocity.x > 0 ? GameConfig.ballRadius : -GameConfig.ballRadius
                } else {
                    velocity.y *= -1
                    position.y += velocity.y > 0 ? GameConfig.ballRadius : -GameConfig.ballRadius
                }

                state.bricks[brickIndex].hitPoints -= 1
                state.score += 1
                let center = Vec2(x: (rect.minX + rect.maxX) * 0.5, y: (rect.minY + rect.maxY) * 0.5)
                if state.bricks[brickIndex].hitPoints <= 0 {
                    state.bricks.remove(at: brickIndex)
                    events.brickBreaks.append(center)
                } else {
                    events.brickHits.append(center)
                }
                return
            }
        }
    }

    private static func circleIntersects(rect: BrickRect, center: Vec2, radius: Double) -> Bool {
        let nearestX = min(max(center.x, rect.minX), rect.maxX)
        let nearestY = min(max(center.y, rect.minY), rect.maxY)
        let dx = center.x - nearestX
        let dy = center.y - nearestY
        return dx * dx + dy * dy <= radius * radius
    }

    private static func spawnNewRow(in state: inout GameState) {
        var nextRandom = SeededRandom(seed: state.rngSeed)
        let occupiedCount = 2 + Int(nextRandom.next() % 3)
        var columns = Array(0..<GameConfig.columns)
        columns.shuffle(using: &nextRandom)

        let hpFloor = max(1, state.turn)
        for column in columns.prefix(occupiedCount) {
            let hp = hpFloor + Int(nextRandom.next() % UInt64(max(2, min(5, state.turn + 1))))
            state.bricks.append(Brick(column: column, row: 0, hitPoints: hp, maxHitPoints: hp))
        }

        if let pickupColumn = columns.dropFirst(occupiedCount).first {
            state.pickups.append(ExtraBallPickup(column: pickupColumn, row: 0))
        }

        state.rngSeed = nextRandom.seed
    }
}

struct SeededRandom: RandomNumberGenerator {
    var seed: UInt64

    mutating func next() -> UInt64 {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1
        return seed
    }
}
