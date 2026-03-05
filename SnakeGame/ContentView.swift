//
//  ContentView.swift
//  SnakeGame
//

import SwiftUI
import SpriteKit

struct ContentView: View {
    @State private var isPlaying: Bool = false
    @State private var selectedGameMode: GameMode = .offline
    @State private var isAwaitingOnlineJoin: Bool = false
    @ObservedObject private var photon = PhotonManager.shared

    @State private var playerImage: UIImage? = {
        if let data = UserDefaults.standard.data(forKey: "playerHeadImage"),
           let img  = UIImage(data: data) { return img }
        return nil
    }()

    @AppStorage("bestScore")                private var bestScore: Int = 0
    @AppStorage("selectedSnakeColorIndex")  private var selectedSnakeColorIndex: Int = 0
    @AppStorage("selectedSnakePatternIndex") private var selectedSnakePatternIndex: Int = 0
    @AppStorage("playerName")              private var playerName: String = "Player"

    var body: some View {
        ZStack {
            if isPlaying {
                GameView(
                    gameMode:     selectedGameMode,
                    colorIndex:   selectedSnakeColorIndex,
                    patternIndex: selectedSnakePatternIndex,
                    playerName:   playerName,
                    playerImage:  playerImage,
                    onGameOver: { finalScore in
                        if finalScore > bestScore { bestScore = finalScore }
                        saveToLeaderboard(finalScore)
                        isAwaitingOnlineJoin = false
                        withAnimation(.easeInOut(duration: 0.4)) { isPlaying = false }
                    }
                )
                .ignoresSafeArea()
                .transition(.opacity)
            } else {
                StartScreenView(
                    isPlaying:        $isPlaying,
                    selectedGameMode: $selectedGameMode,
                    playerImage:      $playerImage,
                    onPlayTapped: {
                        if selectedGameMode == .online {
                            isAwaitingOnlineJoin = true
                            PhotonManager.shared.setPlayerName(playerName)
                            if photon.connectionState == .inRoom {
                                isAwaitingOnlineJoin = false
                                withAnimation(.easeInOut(duration: 0.4)) { isPlaying = true }
                            } else {
                                PhotonManager.shared.connect()
                            }
                        } else {
                            isAwaitingOnlineJoin = false
                            isPlaying = true
                        }
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: isPlaying)
        .onChange(of: photon.connectionState) { state in
            guard isAwaitingOnlineJoin else { return }
            switch state {
            case .inRoom:
                isAwaitingOnlineJoin = false
                withAnimation(.easeInOut(duration: 0.4)) { isPlaying = true }
            case .failed, .disconnected:
                isAwaitingOnlineJoin = false
            case .connecting, .inLobby:
                break
            }
        }
    }

    private func saveToLeaderboard(_ score: Int) {
        let history = (UserDefaults.standard.array(forKey: "scoreHistory") as? [Int]) ?? []
        let updated = GameLogic.processLeaderboardEntry(score: score, existing: history)
        UserDefaults.standard.set(updated, forKey: "scoreHistory")
    }
}

// MARK: - Game View Wrapper
struct GameView: UIViewRepresentable {
    let gameMode:    GameMode
    let colorIndex:  Int
    let patternIndex: Int
    let playerName:  String
    let playerImage: UIImage?
    let onGameOver:  (Int) -> Void

    func makeUIView(context: Context) -> SKView {
        let skView = SKView()
        skView.ignoresSiblingOrder = true
        skView.autoresizingMask    = [.flexibleWidth, .flexibleHeight]

        let scene = GameScene()
        scene.size                     = CGSize(width: 390, height: 844)
        scene.scaleMode                = .resizeFill
        scene.gameMode                 = gameMode
        scene.selectedSnakeColorIndex  = colorIndex
        scene.selectedSnakePatternIndex = patternIndex
        scene.playerName               = playerName
        scene.playerHeadImage          = playerImage
        scene.onGameOver               = onGameOver

        skView.presentScene(scene)
        return skView
    }

    func updateUIView(_ uiView: SKView, context: Context) {
        if let scene = uiView.scene {
            let newSize = uiView.bounds.size
            if newSize != .zero && scene.size != newSize { scene.size = newSize }
        }
    }
}

#Preview {
    ContentView()
}
