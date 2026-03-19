//
//  OnboardingView.swift
//  SnakeGame
//

import SwiftUI
import Combine

// MARK: - OnboardingView

struct OnboardingView: View {
    @Binding var playerImage: UIImage?
    var onComplete: () -> Void

    @AppStorage("playerName") private var persistedName: String = "Player"
    @ObservedObject private var gcManager = GameCenterManager.shared

    @State private var currentStep: Int = 0
    @State private var localName: String = ""
    @State private var userHasEditedName: Bool = false

    // Photo picker state
    @State private var showSourcePicker: Bool = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary
    @State private var showImagePicker: Bool = false
    @State private var showSelfieCaptureView: Bool = false

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        ZStack {
            // Background — matches StartScreenView exactly
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.12, blue: 0.22),
                    Color(red: 0.15, green: 0.22, blue: 0.38)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

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

            VStack(spacing: 0) {
                TabView(selection: $currentStep) {
                    WelcomePage(currentStep: $currentStep)
                        .tag(0)
                    ControlsPage(currentStep: $currentStep)
                        .tag(1)
                    SurvivePage(currentStep: $currentStep)
                        .tag(2)
                    ProfilePage(
                        localName: $localName,
                        userHasEditedName: $userHasEditedName,
                        playerImage: $playerImage,
                        showSourcePicker: $showSourcePicker,
                        onComplete: finishOnboarding
                    )
                    .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentStep)

                OnboardingDots(count: 4, current: currentStep)
                    .padding(.bottom, isLandscape ? 12 : 28)
            }
        }
        .onAppear {
            // Pre-seed name if the user already set one in a prior session
            if persistedName != "Player" {
                localName = persistedName
            }
        }
        .onReceive(gcManager.$gcDisplayName) { alias in
            guard let alias, !alias.isEmpty, !userHasEditedName else { return }
            localName = alias
        }
        .confirmationDialog("Choose Photo", isPresented: $showSourcePicker, titleVisibility: .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Selfie") { showSelfieCaptureView = true }
            }
            Button("Choose from Library") {
                imagePickerSource = .photoLibrary
                showImagePicker = true
            }
            Button("Cancel", role: .cancel) {}
        }
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
    }

    private func finishOnboarding() {
        let trimmed = localName.trimmingCharacters(in: .whitespaces)
        persistedName = trimmed.isEmpty ? "Player" : String(trimmed.prefix(16))
        onComplete()
    }
}

// MARK: - Welcome Page

private struct WelcomePage: View {
    @Binding var currentStep: Int
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        if isLandscape {
            HStack(spacing: 32) {
                brandingBlock
                    .frame(maxWidth: .infinity)
                actionsBlock
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 32)
        } else {
            VStack(spacing: 0) {
                Spacer()
                brandingBlock
                Spacer()
                actionsBlock
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 36)
        }
    }

    private var brandingBlock: some View {
        VStack(spacing: 16) {
            Text("🐍")
                .font(.system(size: isLandscape ? 56 : 80))
                .shadow(color: Color(red: 0.25, green: 0.88, blue: 0.38).opacity(0.5), radius: 16)

            Text("VIPERUN")
                .font(.system(size: isLandscape ? 32 : 44, weight: .black))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.3, green: 1.0, blue: 0.45), Color(red: 0.2, green: 0.8, blue: 0.6)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )

            Text("Grow. Hunt. Survive.")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.65))
                .multilineTextAlignment(.center)
        }
    }

    private var actionsBlock: some View {
        VStack(spacing: 12) {
            OnboardingPrimaryButton(label: "Get Started") {
                currentStep = 1
            }
            Button("Skip to Profile") {
                currentStep = 3
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.4))
        }
    }
}

// MARK: - Controls Page

private struct ControlsPage: View {
    @Binding var currentStep: Int
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        if isLandscape {
            HStack(spacing: 32) {
                controlsIllustration
                    .frame(maxWidth: .infinity)
                VStack(spacing: 20) {
                    titleBlock
                    controlsList
                    Spacer()
                    navigationButtons
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 32)
        } else {
            VStack(spacing: 0) {
                Spacer(minLength: 20)
                titleBlock
                Spacer(minLength: 16)
                controlsIllustration
                    .frame(height: 180)
                Spacer(minLength: 16)
                controlsList
                Spacer()
                navigationButtons
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 36)
        }
    }

    private var titleBlock: some View {
        VStack(spacing: 6) {
            Text("Controls")
                .font(.system(size: 26, weight: .black))
                .foregroundStyle(Color.white)
            Text("Simple to learn, hard to master")
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.5))
        }
    }

    private var controlsIllustration: some View {
        ZStack {
            // Joystick base
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 120, height: 120)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1.5))
                .overlay(
                    // Thumb nub
                    Circle()
                        .fill(Color(red: 0.25, green: 0.88, blue: 0.38).opacity(0.8))
                        .frame(width: 44, height: 44)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                        .offset(x: 18, y: -14)
                )
                .offset(x: -60)

            // Boost button
            Capsule()
                .fill(Color(red: 1.0, green: 0.55, blue: 0.1).opacity(0.85))
                .frame(width: 80, height: 40)
                .overlay(
                    Text("BOOST")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.white)
                )
                .shadow(color: Color(red: 1.0, green: 0.55, blue: 0.1).opacity(0.5), radius: 8)
                .offset(x: 60)

            // Joystick label
            Text("Drag to steer")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.5))
                .offset(x: -60, y: 72)

            // Boost label
            Text("Hold to sprint")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.5))
                .offset(x: 60, y: 32)
        }
    }

    private var controlsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ControlRow(icon: "hand.draw.fill",
                       color: Color(red: 0.25, green: 0.88, blue: 0.38),
                       text: "Drag anywhere on screen to steer")
            ControlRow(icon: "bolt.fill",
                       color: Color(red: 1.0, green: 0.55, blue: 0.1),
                       text: "Hold BOOST to sprint — costs tail length")
            ControlRow(icon: "arrow.trianglehead.2.counterclockwise.rotate.90",
                       color: Color(red: 0.4, green: 0.72, blue: 1.0),
                       text: "Release boost to recover your size")
        }
    }

    private var navigationButtons: some View {
        VStack(spacing: 12) {
            OnboardingPrimaryButton(label: "Next") {
                currentStep = 2
            }
            Button("Skip to Profile") {
                currentStep = 3
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.4))
        }
    }
}

// MARK: - Survive Page

private struct SurvivePage: View {
    @Binding var currentStep: Int
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        if isLandscape {
            HStack(spacing: 32) {
                VStack(spacing: 20) {
                    titleBlock
                    foodList
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 20) {
                    hazardList
                    Spacer()
                    navigationButtons
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 32)
        } else {
            VStack(spacing: 0) {
                Spacer(minLength: 20)
                titleBlock
                Spacer(minLength: 20)
                foodList
                Spacer(minLength: 16)
                hazardList
                Spacer()
                navigationButtons
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 36)
        }
    }

    private var titleBlock: some View {
        VStack(spacing: 6) {
            Text("Stay Alive")
                .font(.system(size: 26, weight: .black))
                .foregroundStyle(Color.white)
            Text("Know your food from your foes")
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.5))
        }
    }

    private var foodList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Food")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.35))
                .textCase(.uppercase)
                .kerning(1)

            FoodRow(color: Color(red: 0.25, green: 0.88, blue: 0.38),
                    label: "Normal food",
                    detail: "Grow longer and score points")
            FoodRow(color: Color(red: 0.95, green: 0.25, blue: 0.25),
                    label: "Death food",
                    detail: "Shrinks whoever eats it — avoid it")
            FoodRow(color: Color(red: 1.0, green: 0.85, blue: 0.25),
                    label: "Trail food",
                    detail: "Dropped by all snakes as they move")
        }
    }

    private var hazardList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hazards")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.35))
                .textCase(.uppercase)
                .kerning(1)

            HazardRow(icon: "square.fill", color: Color(red: 0.6, green: 0.3, blue: 0.8),
                      text: "Hit a wall and it's game over")
            HazardRow(icon: "exclamationmark.triangle.fill", color: Color(red: 1.0, green: 0.55, blue: 0.1),
                      text: "Crash into any snake's body to die")
            HazardRow(icon: "bolt.shield.fill", color: Color(red: 0.4, green: 0.72, blue: 1.0),
                      text: "Boost wisely — you shrink as you sprint")
        }
    }

    private var navigationButtons: some View {
        VStack(spacing: 12) {
            OnboardingPrimaryButton(label: "Set Up Profile") {
                currentStep = 3
            }
            Button("Skip") {
                currentStep = 3
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.4))
        }
    }
}

// MARK: - Profile Page

private struct ProfilePage: View {
    @Binding var localName: String
    @Binding var userHasEditedName: Bool
    @Binding var playerImage: UIImage?
    @Binding var showSourcePicker: Bool
    var onComplete: () -> Void

    @AppStorage("selectedSnakeColorIndex") private var selectedColorIndex: Int = 0
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var isLandscape: Bool { verticalSizeClass == .compact }

    private var themeColor: Color {
        let idx = normalizedSnakeColorIndex(selectedColorIndex)
        return snakeColorThemes[idx].swiftUIColor
    }

    var body: some View {
        if isLandscape {
            HStack(spacing: 40) {
                VStack(spacing: 16) {
                    avatarView(size: 90)
                    Text("Tap to add a photo")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.35))
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 20) {
                    titleBlock
                    nameField
                    Spacer()
                    letsPlayButton
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 32)
        } else {
            VStack(spacing: 0) {
                Spacer(minLength: 20)
                titleBlock
                Spacer(minLength: 24)
                avatarView(size: 110)
                Text("Tap to add a photo")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .padding(.top, 8)
                Spacer(minLength: 24)
                nameField
                Spacer()
                letsPlayButton
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 36)
        }
    }

    private var titleBlock: some View {
        VStack(spacing: 6) {
            Text("Your Profile")
                .font(.system(size: 26, weight: .black))
                .foregroundStyle(Color.white)
            Text("Optional — change anytime from the main menu")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.45))
                .multilineTextAlignment(.center)
        }
    }

    private func avatarView(size: CGFloat) -> some View {
        ZStack {
            if let img = playerImage {
                Image(uiImage: img)
                    .resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(themeColor, lineWidth: 3))
                    .shadow(color: themeColor.opacity(0.5), radius: 8)
            } else {
                Circle()
                    .fill(themeColor.opacity(0.15))
                    .frame(width: size, height: size)
                    .overlay(Circle().strokeBorder(themeColor.opacity(0.5), lineWidth: 2))
                    .overlay(
                        VStack(spacing: 3) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: size * 0.28))
                                .foregroundStyle(Color.white.opacity(0.4))
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
                .overlay(
                    Image(systemName: "camera.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                )
                .offset(x: size * 0.33, y: size * 0.33)
        }
        .onTapGesture { showSourcePicker = true }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Display Name")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.4))
                .textCase(.uppercase)
                .kerning(0.8)

            TextField("Enter your name…", text: $localName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.09))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(themeColor.opacity(0.4), lineWidth: 1)
                )
                .onChange(of: localName) { newValue in
                    userHasEditedName = true
                    if newValue.count > 16 { localName = String(newValue.prefix(16)) }
                }
        }
    }

    private var letsPlayButton: some View {
        Button(action: onComplete) {
            Text("Let's Play!")
                .font(.system(size: 19, weight: .black))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.2, green: 0.8, blue: 0.35), Color(red: 0.1, green: 0.65, blue: 0.45)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: Color(red: 0.2, green: 0.8, blue: 0.35).opacity(0.4), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Dot Indicator

private struct OnboardingDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current
                          ? Color(red: 0.25, green: 0.88, blue: 0.38)
                          : Color.white.opacity(0.2))
                    .frame(width: i == current ? 20 : 8, height: 8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: current)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Shared Helpers

private struct OnboardingPrimaryButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.2, green: 0.8, blue: 0.35), Color(red: 0.1, green: 0.65, blue: 0.45)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: Color(red: 0.2, green: 0.8, blue: 0.35).opacity(0.35), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }
}

private struct ControlRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
                .frame(width: 28)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.8))
        }
    }
}

private struct FoodRow: View {
    let color: Color
    let label: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(color)
                .frame(width: 14, height: 14)
                .shadow(color: color.opacity(0.6), radius: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
        }
    }
}

private struct HazardRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(color)
                .frame(width: 28)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.75))
        }
    }
}
