//
//  ContentView.swift
//  SnakeGame
//

import SwiftUI
import SpriteKit

struct ContentView: View {
    @State private var isPlaying: Bool = false
    @State private var selectedGameMode: GameMode = .offline

    @State private var playerImage: UIImage? = AvatarStore.load()

    @AppStorage("selectedSnakeColorIndex")  private var selectedSnakeColorIndex: Int = 0
    @AppStorage("selectedSnakePatternIndex") private var selectedSnakePatternIndex: Int = 0
    @AppStorage("playerName")              private var playerName: String = "Player"

    private var safeSnakeColorIndex: Int {
        normalizedSnakeColorIndex(selectedSnakeColorIndex)
    }

    var body: some View {
        ZStack {
            if isPlaying {
                GameView(
                    gameMode:     selectedGameMode,
                    colorIndex:   safeSnakeColorIndex,
                    patternIndex: selectedSnakePatternIndex,
                    playerName:   playerName,
                    playerImage:  playerImage,
                    onGameOver: { finalScore in
                        if AppFeatureFlags.isOnlineModeEnabled, selectedGameMode == .online {
                            PhotonManager.shared.disconnect()
                        }
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
                        if AppFeatureFlags.isOnlineModeEnabled, selectedGameMode == .online {
                            PhotonManager.shared.setPlayerName(playerName)
                        } else {
                            isPlaying = true
                        }
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: isPlaying)
        .onChange(of: selectedGameMode) { mode in
            if Self.shouldDisconnectPhotonOnModeChange(mode: mode, isOnlineModeEnabled: AppFeatureFlags.isOnlineModeEnabled) {
                PhotonManager.shared.disconnect()
            }
        }
        .onAppear {
            if !AppFeatureFlags.isOnlineModeEnabled, selectedGameMode == .online {
                selectedGameMode = .offline
            }
        }
    }


    static func shouldDisconnectPhotonOnModeChange(mode: GameMode, isOnlineModeEnabled: Bool) -> Bool {
        isOnlineModeEnabled && mode != .online
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
        skView.preferredFramesPerSecond = 60

        let scene = GameScene()
        scene.size                     = CGSize(width: 390, height: 844)
        scene.scaleMode                = .resizeFill
        scene.gameMode                 = AppFeatureFlags.isOnlineModeEnabled || gameMode != .online ? gameMode : .offline
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

    static func dismantleUIView(_ uiView: SKView, coordinator: ()) {
        (uiView.scene as? GameScene)?.shutdown()
        uiView.presentScene(nil)
    }
}

#Preview {
    ContentView()
}
