import GameKit
import UIKit

class GameCenterManager: NSObject, GKGameCenterControllerDelegate {
    static let shared = GameCenterManager()

    let highScoreLeaderboardID = "co.chandrashrestha.viperun.highscore"
    private(set) var isAuthenticated = false

    func authenticate() {
        let player = GKLocalPlayer.local
        player.authenticateHandler = { [weak self] viewController, _ in
            if let vc = viewController {
                Self.rootViewController()?.present(vc, animated: true)
            }
            self?.isAuthenticated = player.isAuthenticated
        }
    }

    func submitScore(_ score: Int) {
        guard GKLocalPlayer.local.isAuthenticated else { return }
        GKLeaderboard.submitScore(
            score, context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: [highScoreLeaderboardID]
        ) { error in
            if let error { print("GC score error: \(error)") }
        }
    }

    func showLeaderboard() {
        guard let vc = Self.rootViewController() else { return }
        let gcVC = GKGameCenterViewController(
            leaderboardID: highScoreLeaderboardID,
            playerScope: .global,
            timeScope: .allTime
        )
        gcVC.gameCenterDelegate = self
        vc.present(gcVC, animated: true)
    }

    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
    }

    private static func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}
