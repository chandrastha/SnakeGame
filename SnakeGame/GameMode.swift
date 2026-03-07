// GameMode.swift

enum GameMode: String, CaseIterable {
    case online = "online"
    case offline = "offline"
    case challenge = "challenge"
    case mazeHunt = "mazeHunt"
    case snakeRace = "snakeRace"

    var bestScoreKey: String {
        "bestScore.\(rawValue)"
    }

    var leaderboardKey: String {
        "scoreHistory.\(rawValue)"
    }

    var leaderboardTitle: String {
        switch self {
        case .online:
            return "ONLINE LEADERBOARD"
        case .offline:
            return "CASUAL LEADERBOARD"
        case .challenge:
            return "EXPERT LEADERBOARD"
        case .mazeHunt:
            return "MAZE HUNT LEADERBOARD"
        case .snakeRace:
            return "SNAKE RACE LEADERBOARD"
        }
    }
}
