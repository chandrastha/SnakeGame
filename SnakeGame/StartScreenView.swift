//
//  StartScreenView.swift
//  SnakeGame
//

import SwiftUI
import GameController

struct StartScreenView: View {
    @Binding var isPlaying:        Bool
    @Binding var selectedGameMode: GameMode
    @Binding var playerImage:      UIImage?
    var onPlayTapped: () -> Void

    @AppStorage("selectedSnakeColorIndex") private var selectedColorIndex: Int = 0
    @AppStorage("playerName")             private var playerName: String = "Player"
    @ObservedObject private var economy = PlayerEconomy.shared


    @State private var showImagePicker:      Bool = false
    @State private var imagePickerSource:    UIImagePickerController.SourceType = .photoLibrary
    @State private var showSourcePicker:     Bool = false
    @State private var showSelfieCaptureView: Bool = false
    @State private var showCustomize:          Bool = false
    @State private var showPlayAreaCustomize:  Bool = false
    @State private var showSettingsMenu:       Bool = false
    @State private var controllerConnected: Bool = false

    // Detect compact vertical class = iPhone landscape
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var normalizedSelectedColorIndex: Int { normalizedSnakeColorIndex(selectedColorIndex) }
    private var currentTheme: SnakeColorTheme { snakeColorThemes[normalizedSelectedColorIndex] }
    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, isLandscape ? 18 : 20)
                    .padding(.top, isLandscape ? 8 : 12)
                    .padding(.bottom, isLandscape ? 8 : 10)

                if isLandscape {
                    landscapeLayout
                } else {
                    portraitLayout
                }
            }

            if showSettingsMenu {
                settingsModalOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(10)
            }

            if showSourcePicker {
                photoSourceModalOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.20), value: showSettingsMenu)
        .animation(.easeInOut(duration: 0.20), value: showSourcePicker)
        .onAppear {
            if let controller = GCController.controllers().first {
                controllerConnected = true
                registerControllerHandlers(controller)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidConnect)) { note in
            guard let controller = note.object as? GCController else { return }
            controllerConnected = true
            registerControllerHandlers(controller)
        }
        .onReceive(NotificationCenter.default.publisher(for: .GCControllerDidDisconnect)) { _ in
            controllerConnected = false
        }
        // Image picker
        .fullScreenCover(isPresented: $showSelfieCaptureView) {
            SelfieCaptureView(
                onCapture: { image in
                    showSelfieCaptureView = false
                    playerImage = AvatarStore.save(image) ?? image
                },
                onCancel: { showSelfieCaptureView = false }
            )
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView(sourceType: imagePickerSource) { image in
                playerImage = AvatarStore.save(image) ?? image
            }
        }
        .sheet(isPresented: $showCustomize)          { SnakeCustomizeView() }
        .sheet(isPresented: $showPlayAreaCustomize) { PlayAreaCustomizeView() }
    }

    // ─────────────────────────────────────────────
    // MARK: Portrait Layout
    // ─────────────────────────────────────────────
    private var portraitLayout: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 6)

            avatarView(size: 90)
                .padding(.bottom, 10)

            playerNameField(width: 150)
                .padding(.bottom, 14)

            profileRow.padding(.bottom, 14)

            modeSelector
                .padding(.bottom, 26)

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

            // ── Left column: profile/actions ──
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                avatarView(size: 66)
                    .padding(.bottom, 6)

                playerNameField(width: 120)
                    .padding(.bottom, 10)

                profileRow

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

            // ── Right column: modes ──
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                modeSelector

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .padding(.horizontal, 8)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            coinBalancePill
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: { showSettingsMenu = true }) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.03, green: 0.10, blue: 0.22).opacity(0.78))
                        .frame(width: isLandscape ? 42 : 46, height: isLandscape ? 42 : 46)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.16), lineWidth: 1)
                        )
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: isLandscape ? 17 : 18, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.88))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .accessibilityHint("Opens settings actions")
        }
    }

    private var settingsModalOverlay: some View {
        GeometryReader { proxy in
            let cardWidth = min(isLandscape ? 350 : 320, proxy.size.width - 42)

            ZStack {
                Color.black.opacity(0.56)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showSettingsMenu = false
                    }

                ZStack {
                    Circle()
                        .fill(currentTheme.swiftUIColor.opacity(0.14))
                        .frame(width: cardWidth * 0.90, height: cardWidth * 0.90)
                        .blur(radius: 22)
                        .offset(x: -cardWidth * 0.26, y: -44)

                    Circle()
                        .fill(Color(red: 0.30, green: 0.86, blue: 1.0).opacity(0.12))
                        .frame(width: cardWidth * 0.78, height: cardWidth * 0.78)
                        .blur(radius: 20)
                        .offset(x: cardWidth * 0.20, y: 70)

                    VStack(spacing: 16) {
                        Text("SETTINGS")
                            .font(.system(size: isLandscape ? 30 : 32, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.96))
                            .tracking(1.2)

                        settingsModalButton(
                            title: "Skins",
                            systemImage: "paintpalette.fill",
                            tint: Color(red: 0.35, green: 1.0, blue: 0.63)
                        ) {
                            showSettingsMenu = false
                            showCustomize = true
                        }

                        settingsModalButton(
                            title: "Layout",
                            systemImage: "squares.leading.rectangle",
                            tint: Color(red: 0.35, green: 0.83, blue: 1.0)
                        ) {
                            showSettingsMenu = false
                            showPlayAreaCustomize = true
                        }

                        settingsModalButton(
                            title: "Ranks",
                            systemImage: "trophy.fill",
                            tint: Color(red: 1.0, green: 0.84, blue: 0.30)
                        ) {
                            showSettingsMenu = false
                            GameCenterManager.shared.showLeaderboard()
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 26)
                }
                .frame(width: cardWidth)
                .background(
                    RoundedRectangle(cornerRadius: 34)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.11, green: 0.17, blue: 0.31).opacity(0.96),
                                    Color(red: 0.09, green: 0.15, blue: 0.28).opacity(0.96)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 34)
                        .stroke(Color(red: 0.45, green: 0.92, blue: 1.0).opacity(0.44), lineWidth: 1.6)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 34)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        .padding(8)
                )
                .shadow(color: Color(red: 0.32, green: 0.88, blue: 1.0).opacity(0.35), radius: 26, y: 12)
                .padding(.horizontal, 20)
            }
        }
    }

    private var photoSourceModalOverlay: some View {
        GeometryReader { proxy in
            let cardWidth = min(isLandscape ? 360 : 328, proxy.size.width - 42)

            ZStack {
                Color.black.opacity(0.58)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showSourcePicker = false
                    }

                ZStack {
                    Circle()
                        .fill(currentTheme.swiftUIColor.opacity(0.14))
                        .frame(width: cardWidth * 0.88, height: cardWidth * 0.88)
                        .blur(radius: 22)
                        .offset(x: -cardWidth * 0.24, y: -48)

                    Circle()
                        .fill(Color(red: 0.30, green: 0.86, blue: 1.0).opacity(0.10))
                        .frame(width: cardWidth * 0.70, height: cardWidth * 0.70)
                        .blur(radius: 18)
                        .offset(x: cardWidth * 0.22, y: 68)

                    VStack(spacing: 14) {
                        Text("CHOOSE PHOTO")
                            .font(.system(size: isLandscape ? 27 : 29, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.96))
                            .tracking(1)
                            .minimumScaleFactor(0.80)
                            .lineLimit(1)

                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            photoSourceModalButton(
                                title: "Take Selfie",
                                systemImage: "camera.fill",
                                tint: Color(red: 0.35, green: 1.0, blue: 0.63)
                            ) {
                                showSourcePicker = false
                                showSelfieCaptureView = true
                            }
                        }

                        photoSourceModalButton(
                            title: "Choose from Library",
                            systemImage: "photo.on.rectangle.angled",
                            tint: Color(red: 0.35, green: 0.83, blue: 1.0)
                        ) {
                            showSourcePicker = false
                            imagePickerSource = .photoLibrary
                            showImagePicker = true
                        }

                        Button(action: { showSourcePicker = false }) {
                            Text("Cancel")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.62))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 24)
                    .padding(.bottom, 18)
                }
                .frame(width: cardWidth)
                .background(
                    RoundedRectangle(cornerRadius: 34)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.11, green: 0.17, blue: 0.31).opacity(0.97),
                                    Color(red: 0.09, green: 0.15, blue: 0.28).opacity(0.97)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 34)
                        .stroke(currentTheme.swiftUIColor.opacity(0.42), lineWidth: 1.6)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 34)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        .padding(8)
                )
                .shadow(color: currentTheme.swiftUIColor.opacity(0.35), radius: 26, y: 12)
                .padding(.horizontal, 20)
            }
        }
    }

    private func settingsModalButton(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .frame(maxWidth: .infinity)
            .frame(height: isLandscape ? 62 : 66)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.white.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(tint.opacity(0.45), lineWidth: 1.2)
            )
            .shadow(color: tint.opacity(0.20), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func photoSourceModalButton(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: isLandscape ? 21 : 23, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .minimumScaleFactor(0.80)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: isLandscape ? 60 : 64)
            .background(
                RoundedRectangle(cornerRadius: 21)
                    .fill(Color.white.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 21)
                    .stroke(tint.opacity(0.45), lineWidth: 1.2)
            )
            .shadow(color: tint.opacity(0.18), radius: 9, y: 4)
        }
        .buttonStyle(.plain)
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

    private var coinBalancePill: some View {
        HStack(spacing: 6) {
            Text("🪙")
                .font(.system(size: isLandscape ? 14 : 16))
            Text("\(economy.coins)")
                .font(.system(size: isLandscape ? 14 : 15, weight: .black))
                .foregroundStyle(Color(red: 1.0, green: 0.90, blue: 0.30))
            Text("coins")
                .font(.system(size: isLandscape ? 12 : 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .padding(.horizontal, isLandscape ? 14 : 18)
        .padding(.vertical, isLandscape ? 7 : 8)
        .background(Color(red: 0.04, green: 0.10, blue: 0.22).opacity(0.72))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
    }

    private var profileRow: some View {
        HStack(spacing: 8) {
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

            Button(action: { showPlayAreaCustomize = true }) {
                HStack(spacing: 3) {
                    Image(systemName: "squares.leading.rectangle").font(.system(size: 12, weight: .bold))
                    Text("Layout").font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(Color(red: 0.3, green: 0.75, blue: 1.0))
                .padding(.horizontal, 11).padding(.vertical, 9)
                .background(Color(red: 0.3, green: 0.75, blue: 1.0).opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button(action: { GameCenterManager.shared.showLeaderboard() }) {
                HStack(spacing: 3) {
                    Image(systemName: "trophy.fill").font(.system(size: 12, weight: .bold))
                    Text("Ranks").font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(Color(red: 1.0, green: 0.8, blue: 0.2))
                .padding(.horizontal, 11).padding(.vertical, 9)
                .background(Color(red: 1.0, green: 0.8, blue: 0.2).opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var modeSelector: some View {
        VStack(spacing: 8) {
            Text("GAME MODE")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.55))
                .kerning(2)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ModeButton(icon: "🐍", title: "Casual", isSelected: selectedGameMode == .offline) { startGame(in: .offline) }
                        .accessibilityIdentifier("modeCasual")
                    ModeButton(icon: "⚔️", title: "Expert", isSelected: selectedGameMode == .challenge) { startGame(in: .challenge) }
                        .accessibilityIdentifier("modeExpert")
                }
            }
        }
    }

    private var instructionLabel: some View {
        Text(instructionText)
            .font(.system(size: 11))
            .foregroundStyle(Color.white.opacity(0.32))
            .multilineTextAlignment(.center)
    }

    private var instructionText: String {
        switch selectedGameMode {
        case .offline: return "99 bots · Casual mode"
        case .challenge: return "Expert mode · delayed nemesis · survive the hunt"
        }
    }

    private func registerControllerHandlers(_ controller: GCController) {
        controller.extendedGamepad?.buttonA.pressedChangedHandler = { _, _, pressed in
            guard pressed else { return }
            DispatchQueue.main.async { startGame(in: selectedGameMode) }
        }
        controller.extendedGamepad?.dpad.left.pressedChangedHandler = { _, _, pressed in
            guard pressed else { return }
            DispatchQueue.main.async { selectedGameMode = .offline }
        }
        controller.extendedGamepad?.dpad.right.pressedChangedHandler = { _, _, pressed in
            guard pressed else { return }
            DispatchQueue.main.async { selectedGameMode = .challenge }
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.08, blue: 0.20),
                    Color(red: 0.01, green: 0.05, blue: 0.16),
                    Color(red: 0.01, green: 0.02, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(red: 0.22, green: 0.86, blue: 0.56).opacity(0.24),
                    Color.clear
                ],
                center: .top,
                startRadius: 20,
                endRadius: 360
            )

            LinearGradient(
                colors: [Color.clear, Color(red: 0.0, green: 0.25, blue: 0.30).opacity(0.10), Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .ignoresSafeArea()
    }

    private func startGame(in mode: GameMode) {
        selectedGameMode = mode
        onPlayTapped()
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
