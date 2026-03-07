//
//  StartScreenView.swift
//  SnakeGame
//

import SwiftUI

struct StartScreenView: View {
    @Binding var isPlaying:        Bool
    @Binding var selectedGameMode: GameMode
    @Binding var playerImage:      UIImage?
    var onPlayTapped: () -> Void

    @AppStorage("bestScore")               private var bestScore: Int = 0
    @AppStorage("selectedSnakeColorIndex") private var selectedColorIndex: Int = 0
    @AppStorage("playerName")             private var playerName: String = "Player"

    @ObservedObject private var coins = CoinManager.shared

    @State private var showImagePicker:   Bool = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var showSourcePicker:  Bool = false
    @State private var showLeaderboard:   Bool = false
    @State private var showCustomize:     Bool = false
    @State private var showShop:          Bool = false
    @State private var pulsePlay:         Bool = false

    // Detect compact vertical class = iPhone landscape
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var leaderboardScores: [Int] {
        (UserDefaults.standard.array(forKey: "scoreHistory") as? [Int]) ?? []
    }
    private var normalizedSelectedColorIndex: Int { normalizedSnakeColorIndex(selectedColorIndex) }
    private var currentTheme: SnakeColorTheme { snakeColorThemes[normalizedSelectedColorIndex] }
    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        ZStack {
            // Layered gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.07, blue: 0.14),
                    Color(red: 0.10, green: 0.08, blue: 0.18),
                    Color(red: 0.05, green: 0.07, blue: 0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Subtle radial glow at top center
            RadialGradient(
                colors: [
                    Color(red: 0.2, green: 0.7, blue: 0.3).opacity(0.12),
                    Color.clear
                ],
                center: .top,
                startRadius: 0,
                endRadius: 300
            )
            .ignoresSafeArea()

            if isLandscape {
                landscapeLayout
            } else {
                portraitLayout
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulsePlay = true
            }
        }
        // Image picker
        .confirmationDialog("Choose Photo", isPresented: $showSourcePicker, titleVisibility: .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Selfie") { imagePickerSource = .camera; showImagePicker = true }
            }
            Button("Choose from Library") { imagePickerSource = .photoLibrary; showImagePicker = true }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView(sourceType: imagePickerSource) { image in
                playerImage = AvatarStore.save(image) ?? image
            }
        }
        .sheet(isPresented: $showLeaderboard) { LeaderboardView(scores: leaderboardScores) }
        .sheet(isPresented: $showCustomize)   { SnakeCustomizeView() }
        .sheet(isPresented: $showShop)        { ShopView() }
    }

    // ─────────────────────────────────────────────
    // MARK: Portrait Layout
    // ─────────────────────────────────────────────
    private var portraitLayout: some View {
        VStack(spacing: 0) {
            Spacer()

            avatarView(size: 90)
                .padding(.bottom, 10)

            playerNameField(width: 150)
                .padding(.bottom, 8)

            Text("🐍").font(.system(size: 60)).padding(.bottom, 2)

            Text("VIPERUN")
                .font(.system(size: 38, weight: .black))
                .foregroundStyle(titleGradient)
                .shadow(color: Color(red: 0.3, green: 0.9, blue: 0.3).opacity(0.55), radius: 14, x: 0, y: 0)
                .padding(.bottom, 20)

            scoreRow.padding(.bottom, 22)

            modeSelector.padding(.bottom, 30)

            playButton

            Spacer()

            instructionLabel.padding(.bottom, 24)
        }
        .padding(.horizontal, 30)
    }

    // ─────────────────────────────────────────────
    // MARK: Landscape Layout
    // ─────────────────────────────────────────────
    private var landscapeLayout: some View {
        HStack(alignment: .center, spacing: 0) {

            // ── Left column: branding + score ──
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                avatarView(size: 66)
                    .padding(.bottom, 6)

                playerNameField(width: 120)
                    .padding(.bottom, 6)

                Text("🐍").font(.system(size: 36)).padding(.bottom, 2)

                Text("VIPERUN")
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(titleGradient)
                    .shadow(color: Color(red: 0.3, green: 0.9, blue: 0.3).opacity(0.5), radius: 10, x: 0, y: 0)
                    .padding(.bottom, 12)

                scoreRow

                Spacer(minLength: 0)

                instructionLabel.padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.leading, 20)
            .padding(.vertical, 12)

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
                .padding(.vertical, 20)

            // ── Right column: modes + play ──
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                modeSelector.padding(.bottom, 14)

                playButtonCompact

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .padding(.horizontal, 8)
    }

    // ─────────────────────────────────────────────
    // MARK: Shared Sub-views
    // ─────────────────────────────────────────────

    private func avatarView(size: CGFloat) -> some View {
        ZStack {
            if let img = playerImage {
                Image(uiImage: img)
                    .resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(currentTheme.swiftUIColor, lineWidth: 3))
                    .shadow(color: currentTheme.swiftUIColor.opacity(0.5), radius: 8)
            } else {
                Circle()
                    .fill(currentTheme.swiftUIColor.opacity(0.15))
                    .frame(width: size, height: size)
                    .overlay(Circle().strokeBorder(currentTheme.swiftUIColor.opacity(0.5), lineWidth: 2))
                    .overlay(
                        VStack(spacing: 3) {
                            Text("🐍").font(.system(size: size * 0.35))
                            Text("Add Photo")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.4))
                        }
                    )
            }
            // Camera badge
            Circle()
                .fill(Color(red: 0.2, green: 0.75, blue: 0.3))
                .frame(width: 26, height: 26)
                .overlay(Image(systemName: "camera.fill").font(.system(size: 12)).foregroundStyle(.white))
                .offset(x: size * 0.33, y: size * 0.33)
        }
        .onTapGesture { showSourcePicker = true }
    }

    @ViewBuilder
    private func playerNameField(width: CGFloat) -> some View {
        if #available(iOS 17.0, *) {
            TextField("Enter name…", text: $playerName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.09))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(currentTheme.swiftUIColor.opacity(0.40), lineWidth: 1))
                .frame(width: width)
                .onChange(of: playerName) { _, new in
                    if new.count > 16 { playerName = String(new.prefix(16)) }
                }
        } else {
            // Fallback on earlier versions
        }
    }

    private var titleGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.3, green: 0.9, blue: 0.3), Color(red: 1.0, green: 0.85, blue: 0.0)],
            startPoint: .leading, endPoint: .trailing
        )
    }

    private var scoreRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text("🏆").font(.system(size: 17))
                    Text("Best: \(bestScore)")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 1.0, green: 0.85, blue: 0.0).opacity(0.25), lineWidth: 1))

                // Coin balance badge
                HStack(spacing: 4) {
                    Text("🪙").font(.system(size: 14))
                    Text("\(coins.balance)")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(Color.yellow)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Color.yellow.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.yellow.opacity(0.30), lineWidth: 1))
            }

            HStack(spacing: 8) {
                Button(action: { showLeaderboard = true }) {
                    HStack(spacing: 3) {
                        Image(systemName: "list.number").font(.system(size: 12, weight: .bold))
                        Text("Board").font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.0))
                    .padding(.horizontal, 11).padding(.vertical, 9)
                    .background(Color(red: 1.0, green: 0.85, blue: 0.0).opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityIdentifier("leaderboardButton")

                Button(action: { showCustomize = true }) {
                    HStack(spacing: 3) {
                        Image(systemName: "paintpalette.fill").font(.system(size: 12, weight: .bold))
                        Text("Skins").font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(Color(red: 0.75, green: 0.52, blue: 1.0))
                    .padding(.horizontal, 11).padding(.vertical, 9)
                    .background(Color(red: 0.75, green: 0.52, blue: 1.0).opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button(action: { showShop = true }) {
                    HStack(spacing: 3) {
                        Image(systemName: "bag.fill").font(.system(size: 12, weight: .bold))
                        Text("Shop").font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(Color.yellow)
                    .padding(.horizontal, 11).padding(.vertical, 9)
                    .background(Color.yellow.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private var modeSelector: some View {
        VStack(spacing: 8) {
            Text("GAME MODE")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.55))
                .kerning(2)

            HStack(spacing: 8) {
                ModeButton(icon: "🐍", title: "Offline", isSelected: selectedGameMode == .offline) { selectedGameMode = .offline }
                    .accessibilityIdentifier("modeOffline")
                ModeButton(icon: "⚔️", title: "Challenge", isSelected: selectedGameMode == .challenge) { selectedGameMode = .challenge }
                    .accessibilityIdentifier("modeChallenge")
            }
        }
    }

    private var playButton: some View {
        Button(action: { onPlayTapped() }) {
            Text("PLAY")
                .font(.system(size: 28, weight: .black))
                .foregroundStyle(Color.white)
                .frame(width: 220, height: 65)
                .background(LinearGradient(
                    colors: [Color(red: 0.25, green: 0.88, blue: 0.38), Color(red: 0.12, green: 0.65, blue: 0.22)],
                    startPoint: .top, endPoint: .bottom
                ))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.25), lineWidth: 1))
                .shadow(color: Color(red: 0.2, green: 0.85, blue: 0.3).opacity(0.65), radius: 18, x: 0, y: 4)
        }
        .scaleEffect(pulsePlay ? 1.035 : 1.0)
        .accessibilityIdentifier("playButton")
    }

    /// Compact version of the play button used in landscape
    private var playButtonCompact: some View {
        Button(action: { onPlayTapped() }) {
            Text("▶  PLAY")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(LinearGradient(
                    colors: [Color(red: 0.25, green: 0.88, blue: 0.38), Color(red: 0.12, green: 0.65, blue: 0.22)],
                    startPoint: .top, endPoint: .bottom
                ))
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.white.opacity(0.25), lineWidth: 1))
                .shadow(color: Color(red: 0.2, green: 0.85, blue: 0.3).opacity(0.6), radius: 14, x: 0, y: 3)
        }
        .scaleEffect(pulsePlay ? 1.035 : 1.0)
        .accessibilityIdentifier("playButton")
    }

    private var instructionLabel: some View {
        Text(instructionText)
            .font(.system(size: 11))
            .foregroundStyle(Color.white.opacity(0.32))
            .multilineTextAlignment(.center)
    }

    private var instructionText: String {
        switch selectedGameMode {
        case .online:  return "Offline-first build · Online mode is temporarily unavailable"
        case .offline: return "99 bots · Practice mode"
        case .challenge: return "Nemesis snake · 1000 pts · survive the hunt"
        }
    }
}

// MARK: - Mode Button
struct ModeButton: View {
    let icon: String; let title: String; let isSelected: Bool; let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(icon).font(.system(size: 16))
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                Group {
                    if isSelected {
                        LinearGradient(
                            colors: [Color(red: 0.22, green: 0.60, blue: 0.95), Color(red: 0.14, green: 0.42, blue: 0.80)],
                            startPoint: .top, endPoint: .bottom
                        )
                    } else {
                        LinearGradient(colors: [Color.white.opacity(0.07), Color.white.opacity(0.07)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color(red: 0.4, green: 0.72, blue: 1.0) : Color.white.opacity(0.15), lineWidth: 1.5))
            .shadow(color: isSelected ? Color(red: 0.2, green: 0.55, blue: 0.95).opacity(0.4) : .clear, radius: 6, x: 0, y: 2)
        }
        .scaleEffect(isSelected ? 1.04 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Image Picker
struct ImagePickerView: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (UIImage) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onImagePicked: onImagePicked) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        let resolvedSourceType = UIImagePickerController.isSourceTypeAvailable(sourceType) ? sourceType : .photoLibrary
        picker.sourceType    = resolvedSourceType
        picker.allowsEditing = true
        picker.delegate      = context.coordinator
        return picker
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImagePicked: (UIImage) -> Void
        init(onImagePicked: @escaping (UIImage) -> Void) { self.onImagePicked = onImagePicked }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
            if let image { onImagePicked(image) }
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
