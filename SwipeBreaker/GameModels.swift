import Foundation

struct Vec2: Codable, Equatable, Hashable {
    var x: Double
    var y: Double

    static let zero = Vec2(x: 0, y: 0)

    var length: Double {
        sqrt(x * x + y * y)
    }

    func normalized() -> Vec2 {
        let length = self.length
        guard length > 0.000_001 else { return .zero }
        return Vec2(x: x / length, y: y / length)
    }

    static func + (lhs: Vec2, rhs: Vec2) -> Vec2 {
        Vec2(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    static func - (lhs: Vec2, rhs: Vec2) -> Vec2 {
        Vec2(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    static func * (lhs: Vec2, rhs: Double) -> Vec2 {
        Vec2(x: lhs.x * rhs, y: lhs.y * rhs)
    }
}

struct GridCoordinate: Codable, Equatable, Hashable {
    var column: Int
    var row: Int
}

struct Brick: Codable, Equatable, Identifiable {
    var column: Int
    var row: Int
    var hitPoints: Int
    var maxHitPoints: Int

    var id: String {
        "\(column)-\(row)"
    }

    var coordinate: GridCoordinate {
        GridCoordinate(column: column, row: row)
    }
}

enum PickupKind: String, Codable, Equatable {
    case regular
    case mystery
}

struct ExtraBallPickup: Codable, Equatable, Identifiable {
    var column: Int
    var row: Int
    var kind: PickupKind = .regular

    var id: String {
        "\(kind.rawValue)-\(column)-\(row)"
    }

    var coordinate: GridCoordinate {
        GridCoordinate(column: column, row: row)
    }

    init(column: Int, row: Int, kind: PickupKind = .regular) {
        self.column = column
        self.row = row
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case column
        case row
        case kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        column = try container.decode(Int.self, forKey: .column)
        row = try container.decode(Int.self, forKey: .row)
        kind = try container.decodeIfPresent(PickupKind.self, forKey: .kind) ?? .regular
    }
}

enum MysteryPowerEffect: String, Codable, Equatable {
    case doubleBallsNextLaunch
    case doubleRegularPickupValue
    case halfBallsNextLaunch
    case deleteBallsNextLaunch

    var shortLabel: String {
        switch self {
        case .doubleBallsNextLaunch: return "2X"
        case .doubleRegularPickupValue: return "+2"
        case .halfBallsNextLaunch: return "1/2"
        case .deleteBallsNextLaunch: return "-BALL"
        }
    }
}

struct BallState: Codable, Equatable, Identifiable {
    var id: Int
    var position: Vec2
    var previousPosition: Vec2
    var velocity: Vec2
    var launchDelay: Double
    var isActive: Bool
    var isFinished: Bool
}

struct GameState: Codable, Equatable {
    var score: Int
    var turn: Int
    var ballCount: Int
    var launcher: Vec2
    var bricks: [Brick]
    var pickups: [ExtraBallPickup]
    var balls: [BallState]
    var pendingExtraBalls: Int
    var queuedMysteryEffect: MysteryPowerEffect? = nil
    var activeMysteryEffect: MysteryPowerEffect? = nil
    var nextBallID: Int
    var rngSeed: UInt64
    var isGameOver: Bool

    init(
        score: Int,
        turn: Int,
        ballCount: Int,
        launcher: Vec2,
        bricks: [Brick],
        pickups: [ExtraBallPickup],
        balls: [BallState],
        pendingExtraBalls: Int,
        queuedMysteryEffect: MysteryPowerEffect? = nil,
        activeMysteryEffect: MysteryPowerEffect? = nil,
        nextBallID: Int,
        rngSeed: UInt64,
        isGameOver: Bool
    ) {
        self.score = score
        self.turn = turn
        self.ballCount = ballCount
        self.launcher = launcher
        self.bricks = bricks
        self.pickups = pickups
        self.balls = balls
        self.pendingExtraBalls = pendingExtraBalls
        self.queuedMysteryEffect = queuedMysteryEffect
        self.activeMysteryEffect = activeMysteryEffect
        self.nextBallID = nextBallID
        self.rngSeed = rngSeed
        self.isGameOver = isGameOver
    }
}

struct HighScoreEntry: Codable, Equatable, Identifiable {
    var id: UUID
    var score: Int
    var turn: Int
    var date: Date

    init(id: UUID = UUID(), score: Int, turn: Int, date: Date = Date()) {
        self.id = id
        self.score = score
        self.turn = turn
        self.date = date
    }
}

struct PersistedScores: Codable, Equatable {
    var highScores: [HighScoreEntry]
}
