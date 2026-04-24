import Foundation

final class SaveStore {
    private let directory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var sessionURL: URL {
        directory.appendingPathComponent("session.json")
    }

    private var scoresURL: URL {
        directory.appendingPathComponent("high_scores.json")
    }

    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directory = directory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SwipeBreaker", isDirectory: true)

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadSession() throws -> GameState? {
        guard fileManager.fileExists(atPath: sessionURL.path) else { return nil }
        let data = try Data(contentsOf: sessionURL)
        return try decoder.decode(GameState.self, from: data)
    }

    func saveSession(_ state: GameState) throws {
        try ensureDirectory()
        let data = try encoder.encode(state)
        try data.write(to: sessionURL, options: [.atomic])
    }

    func clearSession() throws {
        guard fileManager.fileExists(atPath: sessionURL.path) else { return }
        try fileManager.removeItem(at: sessionURL)
    }

    func loadHighScores() throws -> [HighScoreEntry] {
        guard fileManager.fileExists(atPath: scoresURL.path) else { return [] }
        let data = try Data(contentsOf: scoresURL)
        return try decoder.decode(PersistedScores.self, from: data).highScores
    }

    func recordHighScore(score: Int, turn: Int, date: Date = Date()) throws -> [HighScoreEntry] {
        let updated = GameEngine.insertingHighScore(
            HighScoreEntry(score: score, turn: turn, date: date),
            into: try loadHighScores()
        )
        try saveHighScores(updated)
        return updated
    }

    func saveHighScores(_ scores: [HighScoreEntry]) throws {
        try ensureDirectory()
        let data = try encoder.encode(PersistedScores(highScores: scores))
        try data.write(to: scoresURL, options: [.atomic])
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
