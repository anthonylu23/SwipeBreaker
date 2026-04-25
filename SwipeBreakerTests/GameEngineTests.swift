import XCTest
@testable import SwipeBreaker

final class GameEngineTests: XCTestCase {
    func testGameStateAndHighScoresRoundTripThroughSaveStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SaveStore(directory: directory)
        let state = GameEngine.newGame(seed: 42)

        try store.saveSession(state)
        let loaded = try store.loadSession()
        XCTAssertEqual(loaded, state)

        _ = try store.recordHighScore(score: 30, turn: 6, date: Date(timeIntervalSince1970: 10))
        _ = try store.recordHighScore(score: 50, turn: 4, date: Date(timeIntervalSince1970: 20))
        XCTAssertEqual(try store.loadHighScores().map(\.score), [50, 30])
    }

    func testNewGameStartsLauncherAtConfiguredCenter() {
        let state = GameEngine.newGame(seed: 42)

        XCTAssertEqual(state.launcher, GameConfig.launcher)
        XCTAssertEqual(state.launcher.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(state.launcher.y, 0.17, accuracy: 0.001)
    }

    func testHighScoresSortAndTrimToTopTen() {
        let base = (0..<12).map {
            HighScoreEntry(id: UUID(), score: $0, turn: $0, date: Date(timeIntervalSince1970: Double($0)))
        }

        let result = GameEngine.insertingHighScore(HighScoreEntry(score: 99, turn: 1), into: base)
        XCTAssertEqual(result.count, 10)
        XCTAssertEqual(result.first?.score, 99)
        XCTAssertEqual(result.last?.score, 3)
    }

    func testResolveTurnAdvancesBricksAndDetectsGameOver() {
        var state = GameEngine.newGame(seed: 7)
        state.bricks = [
            Brick(column: 3, row: GameConfig.dangerRow - 1, hitPoints: 1, maxHitPoints: 1)
        ]
        state.pickups = []

        GameEngine.resolveTurn(state: &state)

        XCTAssertTrue(state.isGameOver)
        XCTAssertEqual(state.turn, 2)
    }

    func testResolveTurnAddsPendingExtraBallsAndSpawnsRow() {
        var state = GameEngine.newGame(seed: 10)
        state.bricks = []
        state.pendingExtraBalls = 2

        GameEngine.resolveTurn(state: &state)

        XCTAssertFalse(state.isGameOver)
        XCTAssertEqual(state.ballCount, 3)
        XCTAssertFalse(state.bricks.isEmpty)
    }

    func testTopRowSpawnsNearCeiling() {
        let rect = GameEngine.brickRect(column: 0, row: 0)

        XCTAssertLessThan(GameConfig.topWall - rect.maxY, 0.08)
    }

    func testSwipeVectorAndStrengthClamp() {
        let shallow = GameEngine.normalizedLaunchVector(fromPull: Vec2(x: 1, y: 0))
        XCTAssertGreaterThanOrEqual(shallow.y, 0.23)

        XCTAssertEqual(GameEngine.launchStrength(forPullDistance: -1), 0)
        XCTAssertEqual(GameEngine.launchStrength(forPullDistance: 1), 1)
        XCTAssertEqual(GameEngine.launchStrength(forPullDistance: 0.11), 0.5, accuracy: 0.001)
    }

    func testValidAimVectorRejectsPullsOutsideBounceArea() {
        XCTAssertNil(GameEngine.validAimVector(fromPull: Vec2(x: 0, y: -1)))
        XCTAssertNil(GameEngine.validAimVector(fromPull: Vec2(x: 1, y: 0.1)))
        XCTAssertNil(GameEngine.validAimVector(fromPull: Vec2(x: 1, y: 0.05)))

        let valid = GameEngine.validAimVector(fromPull: Vec2(x: 0.05, y: 0.5))
        XCTAssertNotNil(valid)
        XCTAssertGreaterThan(valid?.y ?? 0, 0)
    }

    func testValidAimVectorAcceptsBottomPlayableCorners() {
        let launcher = GameConfig.launcher
        let minX = GameConfig.leftWall + GameConfig.ballRadius
        let maxX = GameConfig.rightWall - GameConfig.ballRadius
        let bottomY = GameConfig.boardBottom

        let leftCornerPull = Vec2(x: minX - launcher.x, y: bottomY - launcher.y)
        let rightCornerPull = Vec2(x: maxX - launcher.x, y: bottomY - launcher.y)

        XCTAssertNotNil(GameEngine.validAimVector(fromPull: leftCornerPull))
        XCTAssertNotNil(GameEngine.validAimVector(fromPull: rightCornerPull))
    }

    func testFullStrengthLaunchUsesIncreasedMaximumSpeed() {
        var state = GameEngine.newGame(seed: 1)
        state.bricks = []
        state.pickups = []

        GameEngine.beginLaunch(state: &state, pull: Vec2(x: 0, y: 1), pullDistance: 1)

        XCTAssertEqual(state.balls.first?.velocity.length ?? 0, 1.485, accuracy: 0.001)
    }

    func testDirectionBasedLaunchPreservesExactDirectionRatio() {
        var state = GameEngine.newGame(seed: 1)
        state.bricks = []
        state.pickups = []

        GameEngine.beginLaunch(state: &state, direction: Vec2(x: 0.3, y: 0.4), pullDistance: 1)

        let velocity = state.balls.first?.velocity ?? .zero
        XCTAssertEqual(velocity.x / velocity.y, 0.75, accuracy: 0.001)
        XCTAssertEqual(velocity.length, 1.485, accuracy: 0.001)
    }

    func testPullBasedLaunchStillClampsShallowPulls() {
        var state = GameEngine.newGame(seed: 1)
        state.bricks = []
        state.pickups = []

        GameEngine.beginLaunch(state: &state, pull: Vec2(x: 1, y: 0), pullDistance: 1)

        let velocity = state.balls.first?.velocity ?? .zero
        XCTAssertGreaterThanOrEqual(velocity.normalized().y, 0.23)
    }

    func testSeededRowsAlwaysSpawnExtraBallPickups() {
        let states = (1...100).map { GameEngine.newGame(seed: UInt64($0)) }

        XCTAssertTrue(states.allSatisfy { !$0.pickups.isEmpty })
    }

    func testSeededRowsSpawnFewerBricks() {
        let states = (1...100).map { GameEngine.newGame(seed: UInt64($0)) }
        let brickCounts = states.map(\.bricks.count)

        XCTAssertEqual(brickCounts.min(), 2)
        XCTAssertEqual(brickCounts.max(), 4)
    }

    func testExtraBallPickupsSpawnOnlyInUnoccupiedColumns() {
        for seed in 1...100 {
            let state = GameEngine.newGame(seed: UInt64(seed))

            for pickup in state.pickups {
                XCTAssertFalse(state.bricks.contains { $0.column == pickup.column && $0.row == pickup.row })
            }
        }
    }

    func testRegularPickupStillAddsOnePendingExtraBallByDefault() {
        var state = pickupCollisionState(kind: .regular, rngSeed: 1)

        var events = TurnEvents()
        _ = GameEngine.stepActiveTurn(state: &state, dt: 1.0 / 120.0, events: &events)

        XCTAssertEqual(state.pendingExtraBalls, 1)
        XCTAssertNil(state.queuedMysteryEffect)
        XCTAssertEqual(events.pickups.first?.kind, .regular)
    }

    func testMysteryRowsSpawnDeterministicallyWithoutOverlaps() {
        let firstPass = (1...100).map { GameEngine.newGame(seed: UInt64($0)).pickups }
        let secondPass = (1...100).map { GameEngine.newGame(seed: UInt64($0)).pickups }

        XCTAssertEqual(firstPass, secondPass)
        XCTAssertTrue(firstPass.contains { pickups in pickups.contains { $0.kind == .mystery } })

        for seed in 1...100 {
            let state = GameEngine.newGame(seed: UInt64(seed))
            let occupiedColumns = Set(state.bricks.map(\.column))
            let pickupCoordinates = Set(state.pickups.map(\.coordinate))

            XCTAssertEqual(pickupCoordinates.count, state.pickups.count)
            XCTAssertTrue(state.pickups.allSatisfy { !occupiedColumns.contains($0.column) })
            XCTAssertEqual(state.pickups.filter { $0.kind == .regular }.count, 1)
            XCTAssertLessThanOrEqual(state.pickups.filter { $0.kind == .mystery }.count, 1)
        }
    }

    func testMysteryEffectResolutionIsDeterministicFromSeed() {
        var first = pickupCollisionState(kind: .mystery, rngSeed: 35)
        var second = pickupCollisionState(kind: .mystery, rngSeed: 35)

        var firstEvents = TurnEvents()
        var secondEvents = TurnEvents()
        _ = GameEngine.stepActiveTurn(state: &first, dt: 1.0 / 120.0, events: &firstEvents)
        _ = GameEngine.stepActiveTurn(state: &second, dt: 1.0 / 120.0, events: &secondEvents)

        XCTAssertEqual(first.queuedMysteryEffect, .halfBallsNextLaunch)
        XCTAssertEqual(first.queuedMysteryEffect, second.queuedMysteryEffect)
        XCTAssertEqual(firstEvents.pickups.first?.mysteryEffect, secondEvents.pickups.first?.mysteryEffect)
    }

    func testTemporaryLaunchCountEffectsDoNotMutatePermanentBallCount() {
        XCTAssertEqual(GameEngine.effectiveLaunchBallCount(baseCount: 5, effect: .doubleBallsNextLaunch), 10)
        XCTAssertEqual(GameEngine.effectiveLaunchBallCount(baseCount: 5, effect: .halfBallsNextLaunch), 2)
        XCTAssertEqual(GameEngine.effectiveLaunchBallCount(baseCount: 5, effect: .deleteBallsNextLaunch), 2)

        var state = GameEngine.newGame(seed: 1)
        state.bricks = []
        state.pickups = []
        state.ballCount = 5
        state.queuedMysteryEffect = .doubleBallsNextLaunch

        GameEngine.beginLaunch(state: &state, direction: Vec2(x: 0, y: 1), pullDistance: 1)

        XCTAssertEqual(state.balls.count, 10)
        XCTAssertEqual(state.ballCount, 5)
        XCTAssertNil(state.queuedMysteryEffect)
        XCTAssertEqual(state.activeMysteryEffect, .doubleBallsNextLaunch)

        state.balls = []
        GameEngine.resolveTurn(state: &state)

        XCTAssertEqual(state.ballCount, 5)
        XCTAssertNil(state.activeMysteryEffect)
    }

    func testDoubleRegularPickupValueMakesRegularPickupsWorthTwoForOneTurn() {
        var state = pickupCollisionState(kind: .regular, rngSeed: 1)
        state.activeMysteryEffect = .doubleRegularPickupValue

        var events = TurnEvents()
        _ = GameEngine.stepActiveTurn(state: &state, dt: 1.0 / 120.0, events: &events)

        XCTAssertEqual(state.pendingExtraBalls, 2)

        state.balls = []
        GameEngine.resolveTurn(state: &state)

        XCTAssertNil(state.activeMysteryEffect)
    }

    func testMysteryPenaltiesKeepAtLeastOneEffectiveLaunchBall() {
        XCTAssertEqual(GameEngine.effectiveLaunchBallCount(baseCount: 1, effect: .halfBallsNextLaunch), 1)
        XCTAssertEqual(GameEngine.effectiveLaunchBallCount(baseCount: 1, effect: .deleteBallsNextLaunch), 1)
        XCTAssertEqual(GameEngine.effectiveLaunchBallCount(baseCount: 2, effect: .deleteBallsNextLaunch), 1)
    }

    func testOldSaveShapeDecodesRegularPickupsAndNoMysteryEffect() throws {
        let json = """
        {
          "score": 0,
          "turn": 1,
          "ballCount": 1,
          "launcher": { "x": 0.5, "y": 0.17 },
          "bricks": [],
          "pickups": [{ "column": 3, "row": 0 }],
          "balls": [],
          "pendingExtraBalls": 0,
          "nextBallID": 1,
          "rngSeed": 42,
          "isGameOver": false
        }
        """.data(using: .utf8)!

        let state = try JSONDecoder().decode(GameState.self, from: json)

        XCTAssertEqual(state.pickups.first?.kind, .regular)
        XCTAssertNil(state.queuedMysteryEffect)
        XCTAssertNil(state.activeMysteryEffect)
    }

    func testBallBouncesOffWall() {
        var state = GameEngine.newGame(seed: 1)
        state.bricks = []
        state.pickups = []
        state.balls = [
            BallState(
                id: 1,
                position: Vec2(x: GameConfig.leftWall + 0.003, y: 0.5),
                previousPosition: Vec2(x: GameConfig.leftWall + 0.004, y: 0.5),
                velocity: Vec2(x: -0.4, y: 0.2),
                launchDelay: 0,
                isActive: true,
                isFinished: false
            )
        ]

        _ = GameEngine.stepActiveTurn(state: &state, dt: 1.0 / 120.0)

        XCTAssertGreaterThan(state.balls[0].velocity.x, 0)
    }

    func testStepReportsBrickHitAndBreakEvents() {
        var state = GameState(
            score: 0,
            turn: 1,
            ballCount: 1,
            launcher: GameConfig.launcher,
            bricks: [Brick(column: 3, row: 3, hitPoints: 2, maxHitPoints: 2)],
            pickups: [],
            balls: [],
            pendingExtraBalls: 0,
            nextBallID: 2,
            rngSeed: 1,
            isGameOver: false
        )
        let rect = GameEngine.brickRect(column: 3, row: 3)
        state.balls = [
            BallState(
                id: 1,
                position: Vec2(x: (rect.minX + rect.maxX) * 0.5, y: rect.minY - GameConfig.ballRadius * 0.5),
                previousPosition: Vec2(x: (rect.minX + rect.maxX) * 0.5, y: rect.minY - GameConfig.ballRadius * 2),
                velocity: Vec2(x: 0, y: 0.6),
                launchDelay: 0,
                isActive: true,
                isFinished: false
            )
        ]

        var events = TurnEvents()
        _ = GameEngine.stepActiveTurn(state: &state, dt: 1.0 / 120.0, events: &events)

        XCTAssertEqual(events.brickHits.count, 1)
        XCTAssertTrue(events.brickBreaks.isEmpty)

        // Damage the brick to 1 HP, hit again — this time it should break.
        state.bricks[0].hitPoints = 1
        state.balls[0].position = Vec2(x: (rect.minX + rect.maxX) * 0.5, y: rect.minY - GameConfig.ballRadius * 0.5)
        state.balls[0].previousPosition = Vec2(x: (rect.minX + rect.maxX) * 0.5, y: rect.minY - GameConfig.ballRadius * 2)
        state.balls[0].velocity = Vec2(x: 0, y: 0.6)

        var events2 = TurnEvents()
        _ = GameEngine.stepActiveTurn(state: &state, dt: 1.0 / 120.0, events: &events2)

        XCTAssertEqual(events2.brickBreaks.count, 1)
        XCTAssertTrue(state.bricks.isEmpty)
    }

    func testStepReportsWallBouncesAndBallLandings() {
        var state = GameEngine.newGame(seed: 1)
        state.bricks = []
        state.pickups = []
        state.balls = [
            BallState(
                id: 1,
                position: Vec2(x: GameConfig.leftWall + 0.003, y: 0.5),
                previousPosition: Vec2(x: GameConfig.leftWall + 0.004, y: 0.5),
                velocity: Vec2(x: -0.4, y: 0.2),
                launchDelay: 0,
                isActive: true,
                isFinished: false
            )
        ]

        var events = TurnEvents()
        _ = GameEngine.stepActiveTurn(state: &state, dt: 1.0 / 120.0, events: &events)

        XCTAssertGreaterThanOrEqual(events.wallBounces, 1)
    }

    func testBallDamagesBrickAndIncreasesScore() {
        var state = GameState(
            score: 0,
            turn: 1,
            ballCount: 1,
            launcher: GameConfig.launcher,
            bricks: [Brick(column: 3, row: 3, hitPoints: 1, maxHitPoints: 1)],
            pickups: [],
            balls: [],
            pendingExtraBalls: 0,
            nextBallID: 2,
            rngSeed: 1,
            isGameOver: false
        )
        let rect = GameEngine.brickRect(column: 3, row: 3)
        state.balls = [
            BallState(
                id: 1,
                position: Vec2(x: (rect.minX + rect.maxX) * 0.5, y: rect.minY - GameConfig.ballRadius * 0.5),
                previousPosition: Vec2(x: (rect.minX + rect.maxX) * 0.5, y: rect.minY - GameConfig.ballRadius * 2),
                velocity: Vec2(x: 0, y: 0.6),
                launchDelay: 0,
                isActive: true,
                isFinished: false
            )
        ]

        _ = GameEngine.stepActiveTurn(state: &state, dt: 1.0 / 120.0)

        XCTAssertEqual(state.score, 1)
        XCTAssertTrue(state.bricks.isEmpty)
        XCTAssertLessThan(state.balls[0].velocity.y, 0)
    }

    func testBallBelowBoardMovingUpDoesNotCrashCollisionScan() {
        var state = stateWithBall(
            position: Vec2(x: 0.5, y: -0.4),
            previousPosition: Vec2(x: 0.5, y: -0.405),
            velocity: Vec2(x: 0, y: 0.6)
        )

        _ = GameEngine.stepActiveTurn(state: &state, dt: 1.0 / 120.0)

        XCTAssertFalse(state.isGameOver)
        XCTAssertEqual(state.score, 0)
    }

    func testBallOutsideSideWallsDoesNotCrashCollisionScan() {
        for xPosition in [-0.4, 1.4] {
            var state = stateWithBall(
                position: Vec2(x: xPosition, y: 0.5),
                previousPosition: Vec2(x: xPosition, y: 0.5),
                velocity: Vec2(x: 0, y: 0.4)
            )

            _ = GameEngine.stepActiveTurn(state: &state, dt: 1.0 / 120.0)

            XCTAssertFalse(state.isGameOver)
            XCTAssertEqual(state.score, 0)
        }
    }

    func testFirstReturningBallSetsNextLauncherPosition() {
        var state = stateWithBall(
            position: Vec2(x: 0.40, y: GameConfig.launcher.y + 0.01),
            previousPosition: Vec2(x: 0.40, y: GameConfig.launcher.y + 0.01),
            velocity: Vec2(x: 0.60, y: -0.60)
        )

        _ = GameEngine.stepActiveTurn(state: &state, dt: 1.0 / 30.0)

        XCTAssertEqual(state.launcher.x, 0.41, accuracy: 0.001)
        XCTAssertEqual(state.launcher.y, GameConfig.launcher.y, accuracy: 0.001)
    }

    func testLaterReturningBallsDoNotOverrideFirstLandingPosition() {
        var state = GameState(
            score: 0,
            turn: 1,
            ballCount: 2,
            launcher: Vec2(x: 0.37, y: GameConfig.launcher.y),
            bricks: [],
            pickups: [],
            balls: [
                BallState(
                    id: 1,
                    position: Vec2(x: 0.37, y: GameConfig.launcher.y),
                    previousPosition: Vec2(x: 0.37, y: GameConfig.launcher.y),
                    velocity: .zero,
                    launchDelay: 0,
                    isActive: false,
                    isFinished: true
                ),
                BallState(
                    id: 2,
                    position: Vec2(x: 0.72, y: GameConfig.launcher.y + 0.01),
                    previousPosition: Vec2(x: 0.72, y: GameConfig.launcher.y + 0.01),
                    velocity: Vec2(x: -0.60, y: -0.60),
                    launchDelay: 0,
                    isActive: true,
                    isFinished: false
                )
            ],
            pendingExtraBalls: 0,
            nextBallID: 3,
            rngSeed: 1,
            isGameOver: false
        )

        _ = GameEngine.stepActiveTurn(state: &state, dt: 1.0 / 30.0)

        XCTAssertEqual(state.launcher.x, 0.37, accuracy: 0.001)
    }

    func testLandingPositionIsClampedInsideSideWalls() {
        var state = stateWithBall(
            position: Vec2(x: 0.05, y: GameConfig.launcher.y + 0.01),
            previousPosition: Vec2(x: 0.05, y: GameConfig.launcher.y + 0.01),
            velocity: Vec2(x: -1.20, y: -0.60)
        )

        _ = GameEngine.stepActiveTurn(state: &state, dt: 1.0 / 30.0)

        XCTAssertEqual(state.launcher.x, GameConfig.leftWall + GameConfig.ballRadius, accuracy: 0.001)
    }

    private func stateWithBall(position: Vec2, previousPosition: Vec2, velocity: Vec2) -> GameState {
        GameState(
            score: 0,
            turn: 1,
            ballCount: 1,
            launcher: GameConfig.launcher,
            bricks: [Brick(column: 3, row: 3, hitPoints: 2, maxHitPoints: 2)],
            pickups: [],
            balls: [
                BallState(
                    id: 1,
                    position: position,
                    previousPosition: previousPosition,
                    velocity: velocity,
                    launchDelay: 0,
                    isActive: true,
                    isFinished: false
                )
            ],
            pendingExtraBalls: 0,
            nextBallID: 2,
            rngSeed: 1,
            isGameOver: false
        )
    }

    private func pickupCollisionState(kind: PickupKind, rngSeed: UInt64) -> GameState {
        let rect = GameEngine.brickRect(column: 3, row: 3)
        let center = Vec2(x: (rect.minX + rect.maxX) * 0.5, y: (rect.minY + rect.maxY) * 0.5)
        return GameState(
            score: 0,
            turn: 1,
            ballCount: 1,
            launcher: GameConfig.launcher,
            bricks: [],
            pickups: [ExtraBallPickup(column: 3, row: 3, kind: kind)],
            balls: [
                BallState(
                    id: 1,
                    position: center,
                    previousPosition: center,
                    velocity: .zero,
                    launchDelay: 0,
                    isActive: true,
                    isFinished: false
                )
            ],
            pendingExtraBalls: 0,
            nextBallID: 2,
            rngSeed: rngSeed,
            isGameOver: false
        )
    }
}
