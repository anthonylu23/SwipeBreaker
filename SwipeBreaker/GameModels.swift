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

struct ExtraBallPickup: Codable, Equatable, Identifiable {
    var column: Int
    var row: Int

    var id: String {
        "extra-\(column)-\(row)"
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
    var nextBallID: Int
    var rngSeed: UInt64
    var isGameOver: Bool
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
