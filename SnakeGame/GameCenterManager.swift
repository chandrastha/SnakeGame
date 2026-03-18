import GameKit
import UIKit

class GameCenterManager: NSObject, GKGameCenterControllerDelegate {
    static let shared = GameCenterManager()

    let highScoreLeaderboardID = "co.chandrashrestha.viperun.highscore"
    private(set) var isAuthenticated = false

    // P2 fix: guard against duplicate submissions on resize/rotation
    private var hasSubmittedScoreThisRound = false

    // P1 fix: store auth VC and retry once scene activates
    private var pendingAuthViewController: UIViewController?

    func authenticate() {
        let player = GKLocalPlayer.local
        player.authenticateHandler = { [weak self] viewController, _ in
            guard let self else { return }
            if let vc = viewController {
                if let root = Self.rootViewController() {
                    root.present(vc, animated: true)
                } else {
                    self.pendingAuthViewController = vc
                    NotificationCenter.default.addObserver(
                        self,
                        selector: #selector(self.sceneDidActivate),
                        name: UIScene.didActivateNotification,
                        object: nil
                    )
                }
            }
            self.isAuthenticated = player.isAuthenticated
        }
    }

    @objc private func sceneDidActivate() {
        NotificationCenter.default.removeObserver(self, name: UIScene.didActivateNotification, object: nil)
        if let vc = pendingAuthViewController, let root = Self.rootViewController() {
            root.present(vc, animated: true)
            pendingAuthViewController = nil
        }
    }

    func submitScore(_ score: Int) {
        guard GKLocalPlayer.local.isAuthenticated, !hasSubmittedScoreThisRound else { return }
        hasSubmittedScoreThisRound = true
        GKLeaderboard.submitScore(
            score, context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: [highScoreLeaderboardID]
        ) { error in
            if let error { print("GC score error: \(error)") }
        }
    }

    func resetSession() {
        hasSubmittedScoreThisRound = false
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
