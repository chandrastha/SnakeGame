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

    var body: some View {
        GeometryReader { proxy in
            let metrics = OnboardingLayoutMetrics(size: proxy.size, safeAreaInsets: proxy.safeAreaInsets)

            ZStack {
                background

                VStack(spacing: 0) {
                    TabView(selection: $currentStep) {
                        WelcomePage(currentStep: $currentStep, metrics: metrics, isActive: currentStep == 0)
                            .tag(0)
                        ControlsPage(currentStep: $currentStep, metrics: metrics, isActive: currentStep == 1)
                            .tag(1)
                        ProfilePage(
                            localName: $localName,
                            userHasEditedName: $userHasEditedName,
                            playerImage: $playerImage,
                            showSourcePicker: $showSourcePicker,
                            onComplete: finishOnboarding,
                            metrics: metrics,
                            isActive: currentStep == 2
                        )
                        .tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.easeInOut(duration: 0.3), value: currentStep)
                    .frame(maxHeight: .infinity)

                    OnboardingDots(count: 3, current: currentStep, metrics: metrics)
                        .padding(.bottom, metrics.dotsBottomPadding)
                }
                .frame(maxWidth: metrics.contentMaxWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, metrics.horizontalPadding)
                .padding(.top, metrics.topPadding)
            }
            .ignoresSafeArea()
            .dynamicTypeSize(.xSmall ... .xLarge)
        }
        .onAppear {
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
    let metrics: OnboardingLayoutMetrics
    let isActive: Bool
    @AppStorage("selectedSnakeColorIndex") private var selectedColorIndex: Int = 0

    private var selectedTheme: SnakeColorTheme {
        snakeColorThemes[normalizedSnakeColorIndex(selectedColorIndex)]
    }

    var body: some View {
        Group {
            if metrics.isLandscape {
                HStack(spacing: metrics.sectionSpacing) {
                    VStack(spacing: metrics.compactGap) {
                        heroMark
                        titleBlock
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                    VStack(spacing: metrics.compactGap) {
                        socialProofCard
                        Spacer(minLength: 0)
                        ctaCluster
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            } else {
                VStack(spacing: metrics.sectionSpacing) {
                    heroMark
                    titleBlock
                    socialProofCard
                        .padding(.top, 150)
                    Spacer(minLength: 0)
                    ctaCluster
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var heroMark: some View {
        ZStack {
            Circle()
                .strokeBorder(Color(red: 0.22, green: 0.92, blue: 0.60).opacity(0.30), lineWidth: 1.5)
                .frame(width: metrics.heroCircleSize, height: metrics.heroCircleSize)

            Circle()
                .fill(Color(red: 0.08, green: 0.17, blue: 0.33).opacity(0.85))
                .frame(width: metrics.heroCoreSize, height: metrics.heroCoreSize)
                .overlay(
                    MiniSnakeHeadGlyph(theme: selectedTheme, size: metrics.heroEmojiSize * 0.95)
                )
                .shadow(color: Color(red: 0.25, green: 0.95, blue: 0.62).opacity(0.35), radius: 24, y: 8)
        }
        .frame(height: metrics.heroBlockHeight)
    }

    private var titleBlock: some View {
        VStack(spacing: metrics.textGap) {
            Text("VIPERUN")
                .font(.system(size: metrics.brandTitleSize, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 0.33, green: 1.0, blue: 0.56), Color(red: 0.18, green: 0.86, blue: 0.70)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: Color(red: 0.25, green: 0.95, blue: 0.62).opacity(0.28), radius: 12)
                .minimumScaleFactor(0.8)
                .lineLimit(1)

            Text("Survive • Hunt • Grow ")
                .font(.system(size: metrics.subtitleSize, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.66))
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private var socialProofCard: some View {
        VStack(spacing: metrics.textGap) {
            HStack(spacing: -8) {
                ForEach(0..<3, id: \.self) { idx in
                    Circle()
                        .fill(Color(red: 0.95 - Double(idx) * 0.08, green: 0.93 - Double(idx) * 0.07, blue: 0.90 - Double(idx) * 0.06))
                        .frame(width: metrics.avatarBadgeSize, height: metrics.avatarBadgeSize)
                        .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1.2))
                }

                Circle()
                    .fill(Color(red: 0.03, green: 0.16, blue: 0.31))
                    .frame(width: metrics.avatarBadgeSize, height: metrics.avatarBadgeSize)
                    .overlay(
                        Text("+2K")
                            .font(.system(size: metrics.tinyLabelSize, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.33, green: 1.0, blue: 0.56))
                    )
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
            }

            Text("Join over 2000+ hunters today")
                .font(.system(size: metrics.cardBodySize, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.78))
                .minimumScaleFactor(0.85)
                .lineLimit(1)
        }
        .padding(.horizontal, metrics.cardPadding)
        .padding(.vertical, metrics.cardPadding * 0.9)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: metrics.cardCorner)
                .fill(Color(red: 0.02, green: 0.08, blue: 0.18).opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.cardCorner)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var ctaCluster: some View {
        VStack(spacing: metrics.textGap) {
            OnboardingPrimaryButton(label: "Get Started", isActive: isActive, showsChevron: true) {
                currentStep = 1
            }

            Button("Skip to Profile") {
                currentStep = 2
            }
            .font(.system(size: metrics.secondaryActionSize, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.52))
            .accessibilityHint("Skip onboarding and jump to profile setup")
        }
        .padding(.bottom, metrics.ctaBottomLift)
    }
}

// MARK: - Controls Page

private enum ControlsTutorialStage: Int, CaseIterable {
    case move
    case eatGrow
    case boost
    case dodge
    case enjoy

    var title: String {
        switch self {
        case .move: return "Move Your Snake"
        case .eatGrow: return "Eat and Grow"
        case .boost: return "Use Boost"
        case .dodge: return "Dodge Rivals"
        case .enjoy: return "Enjoy the Arena"
        }
    }

    var instruction: String {
        switch self {
        case .move:
            return "Drag the joystick and keep moving to learn steering."
        case .eatGrow:
            return "Collect consumables to increase score and body length."
        case .boost:
            return "Hold boost while moving to sprint and drain energy."
        case .dodge:
            return "Get close to the rival snake, then pull away safely."
        case .enjoy:
            return "Keep moving smoothly for a moment. Then continue."
        }
    }

}

private struct ControlsPage: View {
    @Binding var currentStep: Int
    let metrics: OnboardingLayoutMetrics
    let isActive: Bool
    @State private var joystickInput: CGSize = .zero
    @State private var boostHeld: Bool = false
    @State private var tutorialStage: ControlsTutorialStage = .move
    @State private var tutorialProgress: CGFloat = 0
    @State private var tutorialCompleted: Bool = false
    @State private var tutorialLength: Int = 1

    var body: some View {
        Group {
            if metrics.isLandscape {
                HStack(spacing: metrics.sectionSpacing) {
                    VStack(spacing: metrics.compactGap) {
                        titleBlock
                        previewPanel
                            .frame(maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                    VStack(spacing: metrics.compactGap) {
                        trainingControls
                        Spacer(minLength: 0)
                        ctaCluster
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            } else {
                VStack(spacing: metrics.sectionSpacing) {
                    titleBlock
                    previewPanel
                        .frame(maxHeight: .infinity)
                        .layoutPriority(2)
                    trainingControls
                    Spacer(minLength: 0)
                    ctaCluster
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var titleBlock: some View {
        VStack(spacing: metrics.textGap) {
            Text("CONTROLS TRAINING")
                .font(.system(size: metrics.pageTitleSize, weight: .black, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(tutorialStage.title)
                .font(.system(size: metrics.subtitleSize, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 1.0, green: 0.92, blue: 0.40).opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(tutorialCompleted ? "Training complete. Continue to the next onboarding page." : tutorialStage.instruction)
                .font(.system(size: metrics.tinyLabelSize + 1, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.72))
                .lineLimit(2)
                .multilineTextAlignment(.center)

        }
        .frame(maxWidth: .infinity)
    }

    private var previewPanel: some View {
        VStack(spacing: max(6, metrics.textGap * 0.9)) {
            trainingIndicator

            ControlsTrainingMiniGame(
                joystickInput: $joystickInput,
                boostHeld: $boostHeld,
                tutorialStage: $tutorialStage,
                tutorialProgress: $tutorialProgress,
                tutorialCompleted: $tutorialCompleted,
                tutorialLength: $tutorialLength,
                metrics: metrics
            )
                .frame(minHeight: metrics.previewHeight)
        }
    }

    private var trainingIndicator: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text("Step \(tutorialStage.rawValue + 1) \(tutorialStage.title). Len \(tutorialLength)")
                    .font(.system(size: metrics.tinyLabelSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.66))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                Text("\(Int((tutorialCompleted ? 1 : tutorialProgress) * 100))%")
                    .font(.system(size: metrics.tinyLabelSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.28, green: 0.95, blue: 0.64))
            }

            Capsule()
                .fill(Color.white.opacity(0.15))
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color(red: 0.28, green: 0.95, blue: 0.64))
                        .frame(maxWidth: .infinity)
                        .scaleEffect(x: tutorialCompleted ? 1 : max(0.02, tutorialProgress), y: 1, anchor: .leading)
                }
        }
        .padding(.horizontal, 8)
    }

    private var trainingControls: some View {
        HStack(spacing: metrics.sectionSpacing) {
            VStack(spacing: metrics.textGap) {
                TrainingJoystick(input: $joystickInput, metrics: metrics)
                Text("STEER")
                    .font(.system(size: metrics.sectionLabelSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.24, green: 0.95, blue: 0.60))
                    .kerning(2)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: metrics.textGap) {
                TrainingBoostButton(
                    isHeld: $boostHeld,
                    metrics: metrics,
                    isEnabled: tutorialStage.rawValue >= ControlsTutorialStage.boost.rawValue
                )
                Text("BOOST")
                    .font(.system(size: metrics.sectionLabelSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 1.0, green: 0.90, blue: 0.25).opacity(tutorialStage.rawValue >= ControlsTutorialStage.boost.rawValue ? 1 : 0.45))
                    .kerning(2)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private var ctaCluster: some View {
        VStack(spacing: metrics.textGap) {
            OnboardingPrimaryButton(
                label: tutorialCompleted ? "Next" : "Complete Training to Continue",
                isActive: isActive,
                showsChevron: tutorialCompleted,
                isEnabled: tutorialCompleted
            ) {
                currentStep = 2
            }

            Button("Skip to Profile") {
                currentStep = 2
            }
            .font(.system(size: metrics.secondaryActionSize, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.5))
            .accessibilityHint("Skip this step and jump to profile setup")
        }
        .padding(.bottom, metrics.ctaBottomLift)
    }
}

// MARK: - Profile Page

private struct ProfilePage: View {
    @Binding var localName: String
    @Binding var userHasEditedName: Bool
    @Binding var playerImage: UIImage?
    @Binding var showSourcePicker: Bool
    var onComplete: () -> Void
    let metrics: OnboardingLayoutMetrics
    let isActive: Bool

    @AppStorage("selectedSnakeColorIndex") private var selectedColorIndex: Int = 0

    private var themeColor: Color {
        let idx = normalizedSnakeColorIndex(selectedColorIndex)
        return snakeColorThemes[idx].swiftUIColor
    }

    var body: some View {
        Group {
            if metrics.isLandscape {
                HStack(spacing: metrics.sectionSpacing) {
                    VStack(spacing: metrics.compactGap) {
                        titleBlock
                        avatarView(size: metrics.profileAvatarSize)
                        Text("Tap to add a photo for snakehead")
                            .font(.system(size: metrics.tinyLabelSize, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.52))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                    VStack(spacing: metrics.compactGap) {
                        nameField
                        rankCard
                        Spacer(minLength: 0)
                        ctaCluster
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            } else {
                VStack(spacing: metrics.sectionSpacing) {
                    titleBlock
                    avatarView(size: metrics.profileAvatarSize)

                    Text("Tap to add a photo for snakehead")
                        .font(.system(size: metrics.tinyLabelSize, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.52))

                    nameField
                    .padding(.top, 30)
                    rankCard
                    .padding(.top, 30)
                    Spacer(minLength: 0)
                    ctaCluster
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var titleBlock: some View {
        VStack(spacing: metrics.textGap) {
            Text("Your Profile")
                .font(.system(size: metrics.pageTitleSize, weight: .black, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.95))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text("Customize your identity for the arena")
                .font(.system(size: metrics.subtitleSize, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.62))
                .minimumScaleFactor(0.85)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
    }

    private func avatarView(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(themeColor.opacity(0.22), lineWidth: 1)
                .frame(width: size + 26, height: size + 26)

            if let img = playerImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(themeColor, lineWidth: 3))
                    .shadow(color: themeColor.opacity(0.45), radius: 10)
            } else {
                Circle()
                    .fill(Color(red: 0.07, green: 0.14, blue: 0.30).opacity(0.82))
                    .frame(width: size, height: size)
                    .overlay(Circle().strokeBorder(themeColor.opacity(0.55), lineWidth: 2))
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.30))
                            .foregroundStyle(Color.white.opacity(0.62))
                    )
            }

            Circle()
                .fill(Color(red: 0.22, green: 0.94, blue: 0.58))
                .frame(width: metrics.avatarPlusBadgeSize, height: metrics.avatarPlusBadgeSize)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: metrics.avatarPlusIconSize, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.7))
                )
                .offset(x: size * 0.34, y: size * 0.34)
                .shadow(color: Color(red: 0.22, green: 0.94, blue: 0.58).opacity(0.55), radius: 8)
        }
        .onTapGesture { showSourcePicker = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Profile photo")
        .accessibilityHint("Double tap to choose or capture a photo")
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: metrics.textGap) {
            Text("Snake Callsign")
                .font(.system(size: metrics.sectionLabelSize, weight: .bold, design: .rounded))
                .foregroundStyle(Color(red: 0.25, green: 0.95, blue: 0.60))
                .kerning(2)
                .textCase(.uppercase)

            TextField("Enter display name...", text: $localName)
                .font(.system(size: metrics.inputTextSize, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white)
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .padding(.horizontal, metrics.cardPadding)
                .frame(height: metrics.inputHeight)
                .background(
                    RoundedRectangle(cornerRadius: metrics.cardCorner)
                        .fill(Color(red: 0.03, green: 0.09, blue: 0.20).opacity(0.8))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.cardCorner)
                        .stroke(themeColor.opacity(0.4), lineWidth: 1)
                )
                .onChange(of: localName) { newValue in
                    userHasEditedName = true
                    if newValue.count > 16 {
                        localName = String(newValue.prefix(16))
                    }
                }
                .accessibilityLabel("Display name")
                .accessibilityHint("Maximum 16 characters")
        }
        .frame(maxWidth: .infinity)
    }

    private var rankCard: some View {
        HStack(spacing: metrics.cardPadding) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CURRENT RANK")
                    .font(.system(size: metrics.tinyLabelSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .kerning(1)

                Text("Novice Runner")
                    .font(.system(size: metrics.rankTitleSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("0 Wins • 0 XP")
                    .font(.system(size: metrics.rankMetaSize, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.58))
            }

            Spacer(minLength: 0)

            RoundedRectangle(cornerRadius: metrics.cardCorner - 4)
                .fill(Color(red: 0.06, green: 0.16, blue: 0.31).opacity(0.9))
                .frame(width: metrics.rankIconBoxSize, height: metrics.rankIconBoxSize)
                .overlay(
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: metrics.rankIconSize, weight: .bold))
                        .foregroundStyle(Color(red: 0.24, green: 0.95, blue: 0.60))
                )
        }
        .padding(metrics.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: metrics.cardCorner)
                .fill(Color(red: 0.03, green: 0.09, blue: 0.22).opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.cardCorner)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var letsPlayButton: some View {
        OnboardingPrimaryButton(label: "LET'S PLAY!", isActive: isActive, showsChevron: false, action: onComplete)
            .accessibilityHint("Finish onboarding and enter the game")
    }

    private var ctaCluster: some View {
        VStack(spacing: metrics.textGap) {
            letsPlayButton
            Text("Skip to Profile")
                .font(.system(size: metrics.secondaryActionSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.clear)
                .accessibilityHidden(true)
        }
        .padding(.bottom, metrics.ctaBottomLift)
    }
}

// MARK: - Dot Indicator

private struct OnboardingDots: View {
    let count: Int
    let current: Int
    let metrics: OnboardingLayoutMetrics

    var body: some View {
        HStack(spacing: metrics.dotsSpacing) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Color(red: 0.25, green: 0.95, blue: 0.60) : Color.white.opacity(0.25))
                    .frame(width: index == current ? metrics.activeDotWidth : metrics.inactiveDotWidth,
                           height: metrics.dotHeight)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: current)
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Shared Helpers

private struct OnboardingPrimaryButton: View {
    let label: String
    let isActive: Bool
    var showsChevron: Bool = true
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var hasEntered: Bool = false
    @State private var pulsing: Bool = false
    @State private var chevronShifted: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(label)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .tracking(0.5)

                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 18, weight: .bold))
                        .offset(x: chevronShifted ? 4 : 0)
                        .opacity(isEnabled ? 0.92 : 0.42)
                }
            }
            .foregroundStyle(isEnabled ? Color(red: 0.01, green: 0.20, blue: 0.12) : Color.white.opacity(0.68))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: isEnabled
                                ? [Color(red: 0.24, green: 0.95, blue: 0.60), Color(red: 0.16, green: 0.86, blue: 0.54)]
                                : [Color.white.opacity(0.20), Color.white.opacity(0.12)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.8)
            )
            .scaleEffect((hasEntered ? 1.0 : 0.96) * (pulsing && isActive && isEnabled ? 1.02 : 1.0))
            .opacity(hasEntered ? 1 : 0)
            .offset(y: hasEntered ? 0 : 18)
            .shadow(color: (isEnabled ? Color(red: 0.24, green: 0.95, blue: 0.60) : Color.white).opacity(isActive ? (pulsing ? 0.46 : 0.34) : 0.2),
                    radius: isActive ? (pulsing && isEnabled ? 16 : 10) : 6,
                    x: 0,
                    y: isActive ? 8 : 4)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .accessibilityHint("Advances onboarding")
        .onAppear {
            if isActive && isEnabled {
                activateAnimations()
            } else {
                hasEntered = true
            }
        }
        .onChange(of: isActive) { active in
            if active && isEnabled {
                activateAnimations()
            } else {
                withAnimation(.easeOut(duration: 0.12)) {
                    pulsing = false
                    chevronShifted = false
                }
                hasEntered = true
            }
        }
        .onChange(of: isEnabled) { enabled in
            if enabled && isActive {
                activateAnimations()
            } else if !enabled {
                withAnimation(.easeOut(duration: 0.12)) {
                    pulsing = false
                    chevronShifted = false
                }
                hasEntered = true
            }
        }
    }

    private func activateAnimations() {
        hasEntered = false
        pulsing = false
        chevronShifted = false

        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            hasEntered = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            guard isActive && isEnabled else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulsing = true
            }
            if showsChevron {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    chevronShifted = true
                }
            }
        }
    }
}

private enum GameFoodPalette {
    static let regularEmojis: [String] = ["🍎","🍊","🍋","🍇","🍓","🍉","🍑","🍌","🫐","🍒"]
}

private struct MiniSnakeHeadGlyph: View {
    let theme: SnakeColorTheme
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(theme.swiftUIColor)
                .overlay(
                    Circle()
                        .stroke(theme.swiftUIColor.opacity(0.7), lineWidth: 0.6)
                        .blendMode(.multiply)
                )
                .overlay(
                    Circle()
                        .stroke(theme.bodySwiftUIColor.opacity(0.85), lineWidth: max(1.0, size * 0.08))
                )
                .shadow(color: theme.swiftUIColor.opacity(0.45), radius: size * 0.2)

            HStack(spacing: size * 0.18) {
                eye
                eye
            }
            .offset(y: -size * 0.06)
        }
        .frame(width: size, height: size)
    }

    private var eye: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.94))
                .frame(width: size * 0.22, height: size * 0.22)
            Circle()
                .fill(Color.black.opacity(0.84))
                .frame(width: size * 0.10, height: size * 0.10)
                .offset(y: size * 0.01)
        }
    }
}

private struct RivalSnakeHeadGlyph: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.88, green: 0.22, blue: 0.25))
                .overlay(
                    Circle()
                        .stroke(Color(red: 1.0, green: 0.52, blue: 0.56).opacity(0.9), lineWidth: max(1.0, size * 0.08))
                )
                .shadow(color: Color(red: 1.0, green: 0.42, blue: 0.40).opacity(0.48), radius: size * 0.20)

            HStack(spacing: size * 0.18) {
                Circle()
                    .fill(Color.white.opacity(0.94))
                    .frame(width: size * 0.20, height: size * 0.20)
                    .overlay(
                        Circle()
                            .fill(Color.black.opacity(0.84))
                            .frame(width: size * 0.10, height: size * 0.10)
                    )
                Circle()
                    .fill(Color.white.opacity(0.94))
                    .frame(width: size * 0.20, height: size * 0.20)
                    .overlay(
                        Circle()
                            .fill(Color.black.opacity(0.84))
                            .frame(width: size * 0.10, height: size * 0.10)
                    )
            }
            .offset(y: -size * 0.06)
        }
        .frame(width: size, height: size)
    }
}

private struct TrainingJoystick: View {
    @Binding var input: CGSize
    let metrics: OnboardingLayoutMetrics
    @State private var thumbOffset: CGSize = .zero
    @State private var hasInteracted: Bool = false
    @State private var isGuidancePulsing: Bool = false

    private var scale: CGFloat {
        let base: CGFloat
        if metrics.isLandscape {
            base = 0.56
        } else {
            switch metrics.bucket {
            case .compact: base = 0.66
            case .regular: base = 0.76
            case .tall: base = 0.88
            }
        }
        return base * metrics.controlsPadScale
    }

    private var baseRadius: CGFloat { 65.0 * scale }
    private var thumbRadius: CGFloat { 28.0 * scale }

    var body: some View {
        ZStack {
            if !hasInteracted {
                Circle()
                    .stroke(Color(red: 0.32, green: 0.98, blue: 0.62).opacity(0.72), lineWidth: 2.2)
                    .frame(width: baseRadius * 2.30, height: baseRadius * 2.30)
                    .scaleEffect(isGuidancePulsing ? 1.08 : 0.94)
                    .opacity(isGuidancePulsing ? 0.85 : 0.28)

                Circle()
                    .stroke(Color(red: 0.32, green: 0.98, blue: 0.62).opacity(0.42), lineWidth: 1.4)
                    .frame(width: baseRadius * 2.58, height: baseRadius * 2.58)
                    .scaleEffect(isGuidancePulsing ? 1.12 : 0.98)
                    .opacity(isGuidancePulsing ? 0.45 : 0.14)
            }

            Circle()
                .fill(Color(red: 0.15, green: 0.30, blue: 0.20).opacity(0.18))
                .frame(width: baseRadius * 2, height: baseRadius * 2)
            Circle()
                .stroke(Color(red: 0.30, green: 0.85, blue: 0.45).opacity(0.35), lineWidth: 2)
                .frame(width: baseRadius * 2, height: baseRadius * 2)
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 1.5)
                .frame(width: baseRadius * 1.20, height: baseRadius * 1.20)
            Circle()
                .fill(Color(red: 0.25, green: 0.80, blue: 0.40).opacity(0.38))
                .overlay(Circle().stroke(Color(red: 0.40, green: 0.95, blue: 0.55).opacity(0.75), lineWidth: 2))
                .shadow(color: Color(red: 0.25, green: 0.80, blue: 0.40).opacity(0.5), radius: 6)
                .frame(width: thumbRadius * 2, height: thumbRadius * 2)
                .offset(thumbOffset)

            if !hasInteracted {
                VStack(spacing: 4) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 12 * scale, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.95))
                    Text("Touch & drag")
                        .font(.system(size: 10 * scale, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.84))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.36))
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.20), lineWidth: 0.8)
                        )
                )
                .offset(y: baseRadius + 22)
                .allowsHitTesting(false)
            }
        }
        .frame(width: baseRadius * 2, height: baseRadius * 2)
        .contentShape(Circle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !hasInteracted {
                        hasInteracted = true
                    }
                    let localX = value.location.x - baseRadius
                    let localY = value.location.y - baseRadius
                    let dist = hypot(localX, localY)
                    let maxDist = baseRadius - thumbRadius * 0.6

                    let clampedX: CGFloat
                    let clampedY: CGFloat
                    if dist > maxDist, dist > 0 {
                        clampedX = (localX / dist) * maxDist
                        clampedY = (localY / dist) * maxDist
                    } else {
                        clampedX = localX
                        clampedY = localY
                    }

                    thumbOffset = CGSize(width: clampedX, height: clampedY)
                    input = CGSize(width: clampedX / maxDist, height: clampedY / maxDist)
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.12)) {
                        thumbOffset = .zero
                        input = .zero
                    }
                }
        )
        .onAppear {
            guard !hasInteracted else { return }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isGuidancePulsing = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Joystick")
        .accessibilityHint("Drag in any direction to steer the training snake")
    }
}

private struct TrainingBoostButton: View {
    @Binding var isHeld: Bool
    let metrics: OnboardingLayoutMetrics
    var isEnabled: Bool = true
    @State private var hasInteracted: Bool = false
    @State private var isGuidancePulsing: Bool = false

    private var scale: CGFloat {
        let base: CGFloat
        if metrics.isLandscape {
            base = 0.56
        } else {
            switch metrics.bucket {
            case .compact: base = 0.66
            case .regular: base = 0.76
            case .tall: base = 0.88
            }
        }
        return base * metrics.controlsPadScale
    }

    private var radius: CGFloat { 54.0 * scale }

    var body: some View {
        ZStack {
            if !hasInteracted && isEnabled {
                Circle()
                    .stroke(Color(red: 1.0, green: 0.92, blue: 0.20).opacity(0.86), lineWidth: 2.2)
                    .frame(width: radius * 2.32, height: radius * 2.32)
                    .scaleEffect(isGuidancePulsing ? 1.09 : 0.95)
                    .opacity(isGuidancePulsing ? 0.82 : 0.26)

                Circle()
                    .stroke(Color(red: 1.0, green: 0.92, blue: 0.20).opacity(0.48), lineWidth: 1.4)
                    .frame(width: radius * 2.60, height: radius * 2.60)
                    .scaleEffect(isGuidancePulsing ? 1.13 : 0.99)
                    .opacity(isGuidancePulsing ? 0.46 : 0.15)
            }

            Circle()
                .fill(isHeld && isEnabled ? Color(red: 1.0, green: 0.85, blue: 0.0).opacity(0.35) : Color.white.opacity(isEnabled ? 0.10 : 0.06))
                .frame(width: radius * 2, height: radius * 2)
            Circle()
                .stroke(
                    isHeld && isEnabled
                    ? Color(red: 1.0, green: 0.90, blue: 0.0).opacity(0.85)
                    : Color.white.opacity(isEnabled ? 0.40 : 0.20),
                    lineWidth: 1.5
                )
                .frame(width: radius * 2, height: radius * 2)
            Text("⚡")
                .font(.system(size: 20 * scale))
                .opacity(isEnabled ? 1 : 0.45)

            if !hasInteracted && isEnabled {
                Text("HOLD")
                    .font(.system(size: 10 * scale, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.32))
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                            )
                    )
                    .offset(y: radius + 22)
                    .allowsHitTesting(false)
            }
        }
        .shadow(color: Color(red: 1.0, green: 0.90, blue: 0.2).opacity(isHeld && isEnabled ? 0.45 : 0), radius: 12)
        .scaleEffect(isHeld && isEnabled ? 1.12 : 1.0)
        .opacity(isEnabled ? 1 : 0.66)
        .animation(.easeOut(duration: 0.09), value: isHeld)
        .contentShape(Circle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard isEnabled else { return }
                    if !hasInteracted {
                        hasInteracted = true
                    }
                    if !isHeld { isHeld = true }
                }
                .onEnded { _ in
                    isHeld = false
                }
        )
        .onAppear {
            guard isEnabled, !hasInteracted else { return }
            withAnimation(.easeInOut(duration: 0.92).repeatForever(autoreverses: true)) {
                isGuidancePulsing = true
            }
        }
        .onChange(of: isEnabled) { enabled in
            if !enabled {
                isHeld = false
                withAnimation(.easeOut(duration: 0.12)) {
                    isGuidancePulsing = false
                }
            } else if !hasInteracted {
                withAnimation(.easeInOut(duration: 0.92).repeatForever(autoreverses: true)) {
                    isGuidancePulsing = true
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Boost")
        .accessibilityHint("Hold to speed up in the controls training arena")
    }
}

private struct ControlsTrainingMiniGame: View {
    @Binding var joystickInput: CGSize
    @Binding var boostHeld: Bool
    @Binding var tutorialStage: ControlsTutorialStage
    @Binding var tutorialProgress: CGFloat
    @Binding var tutorialCompleted: Bool
    @Binding var tutorialLength: Int
    let metrics: OnboardingLayoutMetrics
    @AppStorage("selectedSnakeColorIndex") private var selectedColorIndex: Int = 0

    @State private var boardSize: CGSize = .zero
    @State private var lastTick: Date?
    @State private var snakeHead: CGPoint = CGPoint(x: 0.22, y: 0.56)
    @State private var snakeDirection: CGVector = CGVector(dx: 1, dy: 0)
    @State private var trail: [CGPoint] = []
    @State private var regularFood: CGPoint = CGPoint(x: 0.72, y: 0.56)
    @State private var specialFood: CGPoint = CGPoint(x: 0.60, y: 0.26)
    @State private var trailFood: CGPoint = CGPoint(x: 0.35, y: 0.30)
    @State private var deathFood: CGPoint = CGPoint(x: 0.80, y: 0.74)
    @State private var rivalHead: CGPoint = CGPoint(x: 0.74, y: 0.30)
    @State private var rivalTrail: [CGPoint] = []
    @State private var rivalPhase: CGFloat = 0.65
    @State private var boostEnergy: CGFloat = 1
    @State private var score: Int = 0
    @State private var movementDuration: CGFloat = 0
    @State private var boostDuration: CGFloat = 0
    @State private var dodgeExposure: Bool = false
    @State private var dodgeSafeDuration: CGFloat = 0
    @State private var enjoyDuration: CGFloat = 0
    @State private var stageFoodEaten: Int = 0

    private let tick = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()
    private let hazardZone = CGRect(x: 0.46, y: 0.34, width: 0.18, height: 0.18)

    private var theme: SnakeColorTheme {
        snakeColorThemes[normalizedSnakeColorIndex(selectedColorIndex)]
    }

    private var consumablesUnlocked: Bool {
        tutorialStage.rawValue >= ControlsTutorialStage.eatGrow.rawValue
    }

    private var boostUnlocked: Bool {
        tutorialStage.rawValue >= ControlsTutorialStage.boost.rawValue
    }

    private var dodgeUnlocked: Bool {
        tutorialStage.rawValue >= ControlsTutorialStage.dodge.rawValue
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: metrics.cardCorner + 2)
                .fill(Color(red: 0.01, green: 0.03, blue: 0.08).opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.cardCorner + 2)
                        .stroke(Color(red: 0.35, green: 0.84, blue: 1.0).opacity(0.30), lineWidth: 1.5)
                )

            GeometryReader { geo in
                ZStack {
                    arenaBackdrop
                    arenaGlowOrbs(in: geo.size)
                    GridOverlay()
                    arenaDangerBoundary(in: geo.size)

                    if dodgeUnlocked {
                        hazardView(in: geo.size)
                    }
                    if consumablesUnlocked {
                        foodView(symbol: GameFoodPalette.regularEmojis[score % GameFoodPalette.regularEmojis.count], at: regularFood, in: geo.size)
                        foodView(symbol: "⭐", at: specialFood, in: geo.size)
                        trailPelletView(at: trailFood, in: geo.size)
                        deathFoodView(at: deathFood, in: geo.size)
                    }

                    if dodgeUnlocked {
                        ForEach(Array(rivalTrail.prefix(14).enumerated()), id: \.offset) { idx, segment in
                            Circle()
                                .fill(Color(red: 1.0, green: 0.38, blue: 0.36).opacity(0.86 - Double(idx) * 0.05))
                                .frame(width: max(4, metrics.foodIconSize + 2 - CGFloat(idx) * 0.45),
                                       height: max(4, metrics.foodIconSize + 2 - CGFloat(idx) * 0.45))
                                .position(point(from: segment, in: geo.size))
                        }

                        RivalSnakeHeadGlyph(size: metrics.foodIconSize + 10)
                            .position(point(from: rivalHead, in: geo.size))
                    }

                    ForEach(Array(trail.prefix(16).enumerated()), id: \.offset) { idx, segment in
                        Circle()
                            .fill(theme.bodySwiftUIColor.opacity(0.90 - Double(idx) * 0.04))
                            .frame(width: max(4, metrics.foodIconSize + 2 - CGFloat(idx) * 0.5),
                                   height: max(4, metrics.foodIconSize + 2 - CGFloat(idx) * 0.5))
                            .position(point(from: segment, in: geo.size))
                    }

                    MiniSnakeHeadGlyph(theme: theme, size: metrics.foodIconSize + 10)
                        .position(point(from: snakeHead, in: geo.size))
                        .overlay(
                            Circle()
                                .stroke(Color(red: 1.0, green: 0.90, blue: 0.2).opacity(boostHeld && boostEnergy > 0 ? 0.5 : 0), lineWidth: 1)
                                .frame(width: metrics.foodIconSize + 20, height: metrics.foodIconSize + 20)
                        )

                    arenaBorder(in: geo.size)
                }
                .clipShape(RoundedRectangle(cornerRadius: metrics.cardCorner))
                .padding(8)
                .onAppear {
                    boardSize = geo.size
                    lastTick = nil
                    tutorialLength = trail.count + 1
                }
                .onChange(of: geo.size) { newValue in
                    boardSize = newValue
                }
            }
            .padding(4)
        }
        .onReceive(tick) { now in
            step(at: now)
        }
        .onDisappear {
            lastTick = nil
            boostHeld = false
            joystickInput = .zero
            rivalTrail.removeAll(keepingCapacity: false)
            tutorialLength = 1
        }
    }

    private func step(at now: Date) {
        guard boardSize.width > 0, boardSize.height > 0 else { return }
        defer { lastTick = now }

        guard let previous = lastTick else { return }
        let dt = CGFloat(min(0.05, max(0.01, now.timeIntervalSince(previous))))

        let inputVector = CGVector(dx: joystickInput.width, dy: joystickInput.height)
        let inputMagnitude = hypot(inputVector.dx, inputVector.dy)
        if inputMagnitude > 0.07 {
            snakeDirection = CGVector(dx: inputVector.dx / inputMagnitude, dy: inputVector.dy / inputMagnitude)
        }

        let canBoost = boostUnlocked && boostHeld && boostEnergy > 0.01
        let speed: CGFloat = canBoost ? 0.56 : 0.36
        var newHead = CGPoint(
            x: snakeHead.x + snakeDirection.dx * speed * dt,
            y: snakeHead.y + snakeDirection.dy * speed * dt
        )

        let edgeMin: CGFloat = 0.06
        let edgeMax: CGFloat = 0.94
        var hitArenaBoundary = false
        newHead.x = min(max(newHead.x, edgeMin), edgeMax)
        newHead.y = min(max(newHead.y, edgeMin), edgeMax)
        if newHead.x == edgeMin || newHead.x == edgeMax {
            snakeDirection.dx *= -1
            hitArenaBoundary = true
        }
        if newHead.y == edgeMin || newHead.y == edgeMax {
            snakeDirection.dy *= -1
            hitArenaBoundary = true
        }

        trail.insert(snakeHead, at: 0)
        let maxTrail = min(18, max(8, 8 + score / 2))
        if trail.count > maxTrail {
            trail.removeLast(trail.count - maxTrail)
        }

        if dodgeUnlocked {
            rivalTrail.insert(rivalHead, at: 0)
            if rivalTrail.count > 12 {
                rivalTrail.removeLast(rivalTrail.count - 12)
            }

            rivalPhase += dt * (canBoost ? 1.45 : 1.20)
            rivalHead = CGPoint(
                x: min(max(0.50 + 0.30 * cos(rivalPhase), edgeMin + 0.01), edgeMax - 0.01),
                y: min(max(0.50 + 0.24 * sin(rivalPhase * 0.86 + 0.6), edgeMin + 0.01), edgeMax - 0.01)
            )
        }

        if consumablesUnlocked {
            if distance(newHead, regularFood) < 0.06 {
                score += 1
                stageFoodEaten += 1
                regularFood = randomArenaPoint(excluding: [newHead, specialFood, trailFood, deathFood, rivalHead])
                boostEnergy = min(1, boostEnergy + 0.10)
            }

            if distance(newHead, specialFood) < 0.065 {
                score += 3
                stageFoodEaten += 1
                specialFood = randomArenaPoint(excluding: [newHead, regularFood, trailFood, deathFood, rivalHead])
                boostEnergy = min(1, boostEnergy + 0.20)
            }

            if distance(newHead, trailFood) < 0.055 {
                score += 1
                stageFoodEaten += 1
                trailFood = randomArenaPoint(excluding: [newHead, regularFood, specialFood, deathFood, rivalHead])
            }

            if distance(newHead, deathFood) < 0.060 {
                score += 2
                stageFoodEaten += 1
                deathFood = randomArenaPoint(excluding: [newHead, regularFood, specialFood, trailFood, rivalHead])
            }
        }

        let rivalDistance = distance(newHead, rivalHead)
        let collidedWithRival = dodgeUnlocked && rivalDistance < 0.06

        if dodgeUnlocked && hazardZone.contains(newHead) {
            score = max(0, score - 2)
            trail = Array(trail.prefix(max(4, trail.count / 2)))
            newHead = CGPoint(x: 0.18, y: 0.60)
            snakeDirection = CGVector(dx: 1, dy: 0)
            dodgeExposure = false
            dodgeSafeDuration = 0
        }

        if collidedWithRival {
            score = max(0, score - 3)
            trail = Array(trail.prefix(max(4, trail.count / 2)))
            newHead = CGPoint(x: 0.20, y: 0.62)
            snakeDirection = CGVector(dx: 1, dy: 0)
            dodgeExposure = false
            dodgeSafeDuration = 0
        }

        if hitArenaBoundary {
            score = max(0, score - 1)
            trail = Array(trail.prefix(max(5, trail.count - 3)))
        }

        if canBoost {
            boostEnergy = max(0, boostEnergy - dt * 0.45)
        } else {
            boostEnergy = min(1, boostEnergy + dt * 0.24)
        }

        updateTutorialProgress(
            dt: dt,
            inputMagnitude: inputMagnitude,
            canBoost: canBoost,
            rivalDistance: rivalDistance
        )

        tutorialLength = trail.count + 1
        snakeHead = newHead
    }

    private func point(from normalized: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: normalized.x * size.width, y: normalized.y * size.height)
    }

    private func randomArenaPoint(excluding points: [CGPoint]) -> CGPoint {
        for _ in 0..<20 {
            let candidate = CGPoint(x: CGFloat.random(in: 0.10...0.90), y: CGFloat.random(in: 0.14...0.86))
            let tooCloseToPoints = points.contains { distance($0, candidate) < 0.15 }
            if !tooCloseToPoints && !hazardZone.contains(candidate) {
                return candidate
            }
        }
        return CGPoint(x: CGFloat.random(in: 0.2...0.8), y: CGFloat.random(in: 0.2...0.8))
    }

    private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    private func updateTutorialProgress(
        dt: CGFloat,
        inputMagnitude: CGFloat,
        canBoost: Bool,
        rivalDistance: CGFloat
    ) {
        if tutorialCompleted {
            tutorialProgress = 1
            return
        }

        switch tutorialStage {
        case .move:
            if inputMagnitude > 0.18 {
                movementDuration += dt
            } else {
                movementDuration = max(0, movementDuration - dt * 0.4)
            }
            tutorialProgress = min(1, movementDuration / 1.4)
            if tutorialProgress >= 1 {
                advanceTutorial(to: .eatGrow)
            }

        case .eatGrow:
            tutorialProgress = min(1, CGFloat(stageFoodEaten) / 3.0)
            if stageFoodEaten >= 3 {
                advanceTutorial(to: .boost)
            }

        case .boost:
            if canBoost {
                boostDuration += dt
            } else {
                boostDuration = max(0, boostDuration - dt * 0.3)
            }
            tutorialProgress = min(1, boostDuration / 1.1)
            if tutorialProgress >= 1 {
                advanceTutorial(to: .dodge)
            }

        case .dodge:
            if rivalDistance < 0.18 {
                dodgeExposure = true
                dodgeSafeDuration = 0
            } else if dodgeExposure {
                dodgeSafeDuration += dt
            }
            tutorialProgress = dodgeExposure ? min(1, dodgeSafeDuration / 1.2) : 0
            if tutorialProgress >= 1 {
                advanceTutorial(to: .enjoy)
            }

        case .enjoy:
            let engaged = inputMagnitude > 0.12 || canBoost
            if engaged {
                enjoyDuration += dt
            } else {
                enjoyDuration = max(0, enjoyDuration - dt * 0.35)
            }
            tutorialProgress = min(1, enjoyDuration / 2.0)
            if tutorialProgress >= 1 {
                tutorialProgress = 1
                tutorialCompleted = true
            }
        }
    }

    private func advanceTutorial(to stage: ControlsTutorialStage) {
        tutorialStage = stage
        tutorialProgress = 0
        movementDuration = 0
        boostDuration = 0
        dodgeExposure = false
        dodgeSafeDuration = 0
        enjoyDuration = 0
        stageFoodEaten = 0
        if stage.rawValue < ControlsTutorialStage.boost.rawValue {
            boostHeld = false
        }
    }

    private var arenaBackdrop: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.14, blue: 0.20),
                    Color(red: 0.03, green: 0.12, blue: 0.15),
                    Color(red: 0.02, green: 0.08, blue: 0.13)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [Color.clear, Color(red: 0.34, green: 0.86, blue: 1.0).opacity(0.08), Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    @ViewBuilder
    private func arenaGlowOrbs(in size: CGSize) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.35, green: 0.80, blue: 0.96).opacity(0.16), Color.clear],
                        center: .center,
                        startRadius: 6,
                        endRadius: size.width * 0.29
                    )
                )
                .frame(width: size.width * 0.58, height: size.width * 0.58)
                .position(x: size.width * 0.20, y: size.height * 0.22)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.35, green: 0.80, blue: 0.96).opacity(0.16), Color.clear],
                        center: .center,
                        startRadius: 6,
                        endRadius: size.width * 0.25
                    )
                )
                .frame(width: size.width * 0.50, height: size.width * 0.50)
                .position(x: size.width * 0.76, y: size.height * 0.36)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 0.35, green: 0.80, blue: 0.96).opacity(0.16), Color.clear],
                        center: .center,
                        startRadius: 6,
                        endRadius: size.width * 0.27
                    )
                )
                .frame(width: size.width * 0.54, height: size.width * 0.54)
                .position(x: size.width * 0.52, y: size.height * 0.78)
        }
    }

    private func arenaRect(in size: CGSize) -> CGRect {
        CGRect(
            x: size.width * 0.06,
            y: size.height * 0.06,
            width: size.width * 0.88,
            height: size.height * 0.88
        )
    }

    @ViewBuilder
    private func arenaDangerBoundary(in size: CGSize) -> some View {
        let rect = arenaRect(in: size).insetBy(dx: size.width * 0.035, dy: size.height * 0.035)
        RoundedRectangle(cornerRadius: 8)
            .stroke(Color(red: 1.0, green: 0.46, blue: 0.42).opacity(0.22), lineWidth: 1.2)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    @ViewBuilder
    private func arenaBorder(in size: CGSize) -> some View {
        let rect = arenaRect(in: size)
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(red: 0.14, green: 0.88, blue: 1.0).opacity(0.30), lineWidth: 9)
                .blur(radius: 2.5)

            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(red: 0.20, green: 0.92, blue: 1.0).opacity(0.62), lineWidth: 2.2)

            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(red: 0.55, green: 0.97, blue: 1.0).opacity(0.86), lineWidth: 1.0)
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func foodView(symbol: String, at normalized: CGPoint, in size: CGSize) -> some View {
        Text(symbol)
            .font(.system(size: metrics.foodIconSize + 6))
            .position(point(from: normalized, in: size))
    }

    @ViewBuilder
    private func trailPelletView(at normalized: CGPoint, in size: CGSize) -> some View {
        Circle()
            .fill(theme.bodySwiftUIColor)
            .frame(width: metrics.foodIconSize + 4, height: metrics.foodIconSize + 4)
            .overlay(Circle().stroke(theme.swiftUIColor.opacity(0.82), lineWidth: 1))
            .position(point(from: normalized, in: size))
    }

    @ViewBuilder
    private func deathFoodView(at normalized: CGPoint, in size: CGSize) -> some View {
        MiniSnakeHeadGlyph(theme: theme, size: metrics.foodIconSize + 6)
            .position(point(from: normalized, in: size))
            .overlay(
                Circle()
                    .stroke(Color(red: 1.0, green: 0.48, blue: 0.50).opacity(0.68), lineWidth: 1.0)
                    .frame(width: metrics.foodIconSize + 14, height: metrics.foodIconSize + 14)
                    .position(point(from: normalized, in: size))
            )
    }

    @ViewBuilder
    private func hazardView(in size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(red: 0.22, green: 0.06, blue: 0.08).opacity(0.58))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(red: 1.0, green: 0.55, blue: 0.58).opacity(0.72), lineWidth: 1.2)
            )
            .frame(width: hazardZone.width * size.width, height: hazardZone.height * size.height)
            .position(point(from: CGPoint(x: hazardZone.midX, y: hazardZone.midY), in: size))
            .overlay(
                ZStack {
                    Image("spawn_hole")
                        .resizable()
                        .scaledToFit()
                        .opacity(0.90)
                        .frame(width: hazardZone.width * size.width * 0.72,
                               height: hazardZone.height * size.height * 0.72)

                    Text("DANGER")
                        .font(.system(size: metrics.tinyLabelSize, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.80))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.black.opacity(0.35))
                                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.8))
                        )
                        .offset(y: hazardZone.height * size.height * 0.30)
                }
                    .position(point(from: CGPoint(x: hazardZone.midX, y: hazardZone.midY), in: size))
            )
    }
}

private struct GridOverlay: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let shortestSide = min(width, height)
            let spacing = max(18, min(34, shortestSide / 10.5))
            let majorSpacing = spacing * 3

            Path { path in
                var x: CGFloat = 0
                while x <= width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))
                    x += spacing
                }
                var y: CGFloat = 0
                while y <= height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                    y += spacing
                }
            }
            .stroke(Color.white.opacity(0.05), lineWidth: 0.6)

            Path { path in
                var x: CGFloat = majorSpacing
                while x < width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))
                    x += majorSpacing
                }
                var y: CGFloat = majorSpacing
                while y < height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                    y += majorSpacing
                }
            }
            .stroke(Color(red: 0.34, green: 0.82, blue: 1.0).opacity(0.18), lineWidth: 1)

            Path { path in
                let dotRadius: CGFloat = 1.2
                var x: CGFloat = spacing
                while x < width {
                    var y: CGFloat = spacing
                    while y < height {
                        path.addEllipse(in: CGRect(x: x - dotRadius, y: y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
                        y += spacing
                    }
                    x += spacing
                }
            }
            .fill(Color.white.opacity(0.09))
        }
        .allowsHitTesting(false)
    }
}

private struct FoodInfoCard: View {
    let type: FoodType
    let title: String
    let subtitle: String
    let accent: Color
    let metrics: OnboardingLayoutMetrics
    let theme: SnakeColorTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.22))
                    .frame(width: metrics.foodIconCircle, height: metrics.foodIconCircle)
                foodIcon
            }

            Text(title)
                .font(.system(size: metrics.foodTitleSize, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(1)

            Text(subtitle)
                .font(.system(size: metrics.foodSubtitleSize, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.56))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, metrics.cardPadding)
        .padding(.vertical, metrics.cardPadding * 0.75)
        .frame(maxWidth: .infinity, minHeight: metrics.foodCardMinHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: metrics.cardCorner)
                .fill(Color(red: 0.04, green: 0.10, blue: 0.22).opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.cardCorner)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var foodIcon: some View {
        switch type {
        case .regular:
            Text(GameFoodPalette.regularEmojis.first ?? "🍎")
                .font(.system(size: metrics.foodIconSize + 4))
        case .multiplier:
            Text("⭐")
                .font(.system(size: metrics.foodIconSize + 3))
        case .death:
            MiniSnakeHeadGlyph(theme: theme, size: metrics.foodIconSize + 6)
        case .trail:
            Circle()
                .fill(theme.bodySwiftUIColor)
                .frame(width: metrics.foodIconSize + 4, height: metrics.foodIconSize + 4)
                .overlay(
                    Circle()
                        .stroke(theme.swiftUIColor.opacity(0.8), lineWidth: 1)
                )
                .shadow(color: theme.bodySwiftUIColor.opacity(0.5), radius: 3)
        case .shield:
            Text("🛡")
                .font(.system(size: metrics.foodIconSize + 3))
        case .magnet:
            Text("🧲")
                .font(.system(size: metrics.foodIconSize + 3))
        case .ghost:
            Text("👻")
                .font(.system(size: metrics.foodIconSize + 3))
        case .shrink:
            Text("✂️")
                .font(.system(size: metrics.foodIconSize + 3))
        }
    }
}

private struct HazardInfoRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let accent: Color
    let metrics: OnboardingLayoutMetrics

    var body: some View {
        HStack(spacing: metrics.cardPadding) {
            RoundedRectangle(cornerRadius: metrics.cardCorner - 4)
                .fill(accent.opacity(0.16))
                .frame(width: metrics.hazardIconBox, height: metrics.hazardIconBox)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: metrics.hazardIconSize, weight: .semibold))
                        .foregroundStyle(accent)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: metrics.hazardTitleSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(subtitle)
                    .font(.system(size: metrics.hazardSubtitleSize, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: metrics.hazardChevronSize, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.28))
        }
        .padding(.horizontal, metrics.cardPadding)
        .padding(.vertical, metrics.cardPadding * 0.7)
        .background(
            RoundedRectangle(cornerRadius: metrics.cardCorner)
                .fill(Color(red: 0.04, green: 0.10, blue: 0.22).opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: metrics.cardCorner)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

// MARK: - Adaptive Metrics

private struct OnboardingLayoutMetrics {
    enum HeightBucket {
        case compact
        case regular
        case tall
    }

    enum WidthBucket {
        case narrowPhone
        case phone
        case tablet
        case largeTablet
    }

    let size: CGSize
    let safeTop: CGFloat
    let safeBottom: CGFloat
    let isLandscape: Bool
    let bucket: HeightBucket
    let widthBucket: WidthBucket
    let contentMaxWidth: CGFloat
    let controlsPadScale: CGFloat

    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    let dotsBottomPadding: CGFloat
    let ctaBottomLift: CGFloat

    let sectionSpacing: CGFloat
    let compactGap: CGFloat
    let textGap: CGFloat

    let cardCorner: CGFloat
    let cardPadding: CGFloat

    let heroCircleSize: CGFloat
    let heroCoreSize: CGFloat
    let heroEmojiSize: CGFloat
    let heroBlockHeight: CGFloat

    let brandTitleSize: CGFloat
    let pageTitleSize: CGFloat
    let subtitleSize: CGFloat

    let avatarBadgeSize: CGFloat
    let tinyLabelSize: CGFloat
    let cardBodySize: CGFloat
    let secondaryActionSize: CGFloat

    let previewHeight: CGFloat
    let snakeSegmentSize: CGFloat
    let previewDotSize: CGFloat
    let previewSnakeOffsetX: CGFloat
    let previewSnakeOffsetY: CGFloat
    let previewBlueDotOffsetX: CGFloat
    let previewBlueDotOffsetY: CGFloat
    let previewYellowDotOffsetX: CGFloat
    let previewYellowDotOffsetY: CGFloat

    let controlOrbOuter: CGFloat
    let controlOrbInner: CGFloat
    let controlIconSize: CGFloat

    let sectionLabelSize: CGFloat

    let foodCardMinHeight: CGFloat
    let foodIconCircle: CGFloat
    let foodIconSize: CGFloat
    let foodTitleSize: CGFloat
    let foodSubtitleSize: CGFloat

    let hazardIconBox: CGFloat
    let hazardIconSize: CGFloat
    let hazardTitleSize: CGFloat
    let hazardSubtitleSize: CGFloat
    let hazardChevronSize: CGFloat

    let profileAvatarSize: CGFloat
    let avatarPlusBadgeSize: CGFloat
    let avatarPlusIconSize: CGFloat
    let inputHeight: CGFloat
    let inputTextSize: CGFloat

    let rankTitleSize: CGFloat
    let rankMetaSize: CGFloat
    let rankIconBoxSize: CGFloat
    let rankIconSize: CGFloat

    let dotsSpacing: CGFloat
    let activeDotWidth: CGFloat
    let inactiveDotWidth: CGFloat
    let dotHeight: CGFloat

    init(size: CGSize, safeAreaInsets: EdgeInsets) {
        self.size = size
        safeTop = safeAreaInsets.top
        safeBottom = safeAreaInsets.bottom
        isLandscape = size.width > size.height

        let availableWidth = size.width - safeAreaInsets.leading - safeAreaInsets.trailing
        if availableWidth < 390 {
            widthBucket = .narrowPhone
        } else if availableWidth < 700 {
            widthBucket = .phone
        } else if availableWidth < 1024 {
            widthBucket = .tablet
        } else {
            widthBucket = .largeTablet
        }

        if availableWidth >= 1100 {
            contentMaxWidth = isLandscape ? 1080 : 900
        } else if availableWidth >= 900 {
            contentMaxWidth = isLandscape ? 980 : 860
        } else if availableWidth >= 700 {
            contentMaxWidth = isLandscape ? 860 : 740
        } else {
            contentMaxWidth = .infinity
        }

        switch widthBucket {
        case .narrowPhone:
            controlsPadScale = 0.94
        case .phone:
            controlsPadScale = 1.0
        case .tablet:
            controlsPadScale = isLandscape ? 1.20 : 1.10
        case .largeTablet:
            controlsPadScale = isLandscape ? 1.30 : 1.16
        }

        let typographyScale: CGFloat
        switch widthBucket {
        case .narrowPhone: typographyScale = 0.95
        case .phone: typographyScale = 1.0
        case .tablet: typographyScale = 1.07
        case .largeTablet: typographyScale = 1.12
        }

        let verticalScale: CGFloat
        switch widthBucket {
        case .narrowPhone: verticalScale = 0.96
        case .phone: verticalScale = 1.0
        case .tablet: verticalScale = 1.06
        case .largeTablet: verticalScale = 1.10
        }

        let horizontalPaddingBoost: CGFloat
        switch widthBucket {
        case .narrowPhone: horizontalPaddingBoost = -2
        case .phone: horizontalPaddingBoost = 0
        case .tablet: horizontalPaddingBoost = 6
        case .largeTablet: horizontalPaddingBoost = 10
        }

        let availableHeight = size.height - safeAreaInsets.top - safeAreaInsets.bottom
        if availableHeight < 700 {
            bucket = .compact
        } else if availableHeight <= 850 {
            bucket = .regular
        } else {
            bucket = .tall
        }

        switch bucket {
        case .compact:
            horizontalPadding = (isLandscape ? 18 : 20) + horizontalPaddingBoost
            topPadding = safeTop + (isLandscape ? 8 : 10)
            dotsBottomPadding = max(6, safeBottom + 4)
            ctaBottomLift = isLandscape ? 8 : 12
            sectionSpacing = (isLandscape ? 10 : 12) * verticalScale
            compactGap = 8
            textGap = 8
            cardCorner = 16
            cardPadding = 12

            heroCircleSize = (isLandscape ? 132 : 156) * verticalScale
            heroCoreSize = (isLandscape ? 106 : 124) * verticalScale
            heroEmojiSize = (isLandscape ? 44 : 52) * typographyScale
            heroBlockHeight = (isLandscape ? 128 : 166) * verticalScale

            brandTitleSize = (isLandscape ? 36 : 42) * typographyScale
            pageTitleSize = (isLandscape ? 26 : 30) * typographyScale
            subtitleSize = (isLandscape ? 13 : 14) * typographyScale

            avatarBadgeSize = 28
            tinyLabelSize = 11 * typographyScale
            cardBodySize = 15 * typographyScale
            secondaryActionSize = 14 * typographyScale

            previewHeight = (isLandscape ? 130 : 190) * verticalScale
            snakeSegmentSize = isLandscape ? 14 : 16
            previewDotSize = isLandscape ? 10 : 12
            previewSnakeOffsetX = isLandscape ? 58 : 74
            previewSnakeOffsetY = isLandscape ? 44 : 56
            previewBlueDotOffsetX = isLandscape ? 138 : 168
            previewBlueDotOffsetY = isLandscape ? 34 : 38
            previewYellowDotOffsetX = isLandscape ? 58 : 74
            previewYellowDotOffsetY = isLandscape ? 82 : 104

            controlOrbOuter = isLandscape ? 92 : 106
            controlOrbInner = isLandscape ? 58 : 68
            controlIconSize = isLandscape ? 20 : 24

            sectionLabelSize = 13 * typographyScale

            foodCardMinHeight = isLandscape ? 84 : 102
            foodIconCircle = isLandscape ? 30 : 34
            foodIconSize = isLandscape ? 14 : 16
            foodTitleSize = 15 * typographyScale
            foodSubtitleSize = 11 * typographyScale

            hazardIconBox = isLandscape ? 38 : 44
            hazardIconSize = isLandscape ? 16 : 18
            hazardTitleSize = 15 * typographyScale
            hazardSubtitleSize = 11 * typographyScale
            hazardChevronSize = 14

            profileAvatarSize = (isLandscape ? 92 : 132) * verticalScale
            avatarPlusBadgeSize = isLandscape ? 30 : 38
            avatarPlusIconSize = isLandscape ? 14 : 17
            inputHeight = (isLandscape ? 50 : 56) * verticalScale
            inputTextSize = 15 * typographyScale

            rankTitleSize = 19 * typographyScale
            rankMetaSize = 13 * typographyScale
            rankIconBoxSize = isLandscape ? 54 : 64
            rankIconSize = isLandscape ? 24 : 28

            dotsSpacing = 7
            activeDotWidth = 22
            inactiveDotWidth = 8
            dotHeight = 8

        case .regular:
            horizontalPadding = (isLandscape ? 20 : 24) + horizontalPaddingBoost
            topPadding = safeTop + (isLandscape ? 10 : 14)
            dotsBottomPadding = max(8, safeBottom + 8)
            ctaBottomLift = isLandscape ? 10 : 14
            sectionSpacing = (isLandscape ? 12 : 14) * verticalScale
            compactGap = 10
            textGap = 10
            cardCorner = 18
            cardPadding = 14

            heroCircleSize = (isLandscape ? 150 : 178) * verticalScale
            heroCoreSize = (isLandscape ? 122 : 142) * verticalScale
            heroEmojiSize = (isLandscape ? 48 : 58) * typographyScale
            heroBlockHeight = (isLandscape ? 146 : 188) * verticalScale

            brandTitleSize = (isLandscape ? 40 : 46) * typographyScale
            pageTitleSize = (isLandscape ? 30 : 34) * typographyScale
            subtitleSize = (isLandscape ? 14 : 15) * typographyScale

            avatarBadgeSize = 32
            tinyLabelSize = 12 * typographyScale
            cardBodySize = 16 * typographyScale
            secondaryActionSize = 15 * typographyScale

            previewHeight = (isLandscape ? 150 : 220) * verticalScale
            snakeSegmentSize = isLandscape ? 16 : 18
            previewDotSize = isLandscape ? 12 : 14
            previewSnakeOffsetX = isLandscape ? 64 : 78
            previewSnakeOffsetY = isLandscape ? 50 : 60
            previewBlueDotOffsetX = isLandscape ? 148 : 180
            previewBlueDotOffsetY = isLandscape ? 40 : 46
            previewYellowDotOffsetX = isLandscape ? 64 : 84
            previewYellowDotOffsetY = isLandscape ? 94 : 118

            controlOrbOuter = isLandscape ? 100 : 116
            controlOrbInner = isLandscape ? 62 : 72
            controlIconSize = isLandscape ? 22 : 26

            sectionLabelSize = 14 * typographyScale

            foodCardMinHeight = isLandscape ? 92 : 112
            foodIconCircle = isLandscape ? 32 : 36
            foodIconSize = isLandscape ? 15 : 17
            foodTitleSize = 16 * typographyScale
            foodSubtitleSize = 12 * typographyScale

            hazardIconBox = isLandscape ? 42 : 48
            hazardIconSize = isLandscape ? 17 : 19
            hazardTitleSize = 16 * typographyScale
            hazardSubtitleSize = 12 * typographyScale
            hazardChevronSize = 15

            profileAvatarSize = (isLandscape ? 102 : 152) * verticalScale
            avatarPlusBadgeSize = isLandscape ? 32 : 40
            avatarPlusIconSize = isLandscape ? 15 : 18
            inputHeight = (isLandscape ? 52 : 58) * verticalScale
            inputTextSize = 16 * typographyScale

            rankTitleSize = 20 * typographyScale
            rankMetaSize = 13 * typographyScale
            rankIconBoxSize = isLandscape ? 58 : 70
            rankIconSize = isLandscape ? 25 : 29

            dotsSpacing = 8
            activeDotWidth = 24
            inactiveDotWidth = 9
            dotHeight = 8

        case .tall:
            horizontalPadding = (isLandscape ? 24 : 28) + horizontalPaddingBoost
            topPadding = safeTop + (isLandscape ? 12 : 18)
            dotsBottomPadding = max(10, safeBottom + 10)
            ctaBottomLift = isLandscape ? 12 : 16
            sectionSpacing = (isLandscape ? 14 : 16) * verticalScale
            compactGap = 12
            textGap = 10
            cardCorner = 20
            cardPadding = 16

            heroCircleSize = (isLandscape ? 168 : 206) * verticalScale
            heroCoreSize = (isLandscape ? 136 : 164) * verticalScale
            heroEmojiSize = (isLandscape ? 52 : 66) * typographyScale
            heroBlockHeight = (isLandscape ? 162 : 220) * verticalScale

            brandTitleSize = (isLandscape ? 44 : 52) * typographyScale
            pageTitleSize = (isLandscape ? 32 : 36) * typographyScale
            subtitleSize = (isLandscape ? 15 : 16) * typographyScale

            avatarBadgeSize = 36
            tinyLabelSize = 12 * typographyScale
            cardBodySize = 17 * typographyScale
            secondaryActionSize = 16 * typographyScale

            previewHeight = (isLandscape ? 170 : 250) * verticalScale
            snakeSegmentSize = isLandscape ? 18 : 20
            previewDotSize = isLandscape ? 13 : 15
            previewSnakeOffsetX = isLandscape ? 70 : 88
            previewSnakeOffsetY = isLandscape ? 56 : 68
            previewBlueDotOffsetX = isLandscape ? 164 : 198
            previewBlueDotOffsetY = isLandscape ? 44 : 52
            previewYellowDotOffsetX = isLandscape ? 74 : 94
            previewYellowDotOffsetY = isLandscape ? 108 : 132

            controlOrbOuter = isLandscape ? 110 : 128
            controlOrbInner = isLandscape ? 68 : 80
            controlIconSize = isLandscape ? 24 : 30

            sectionLabelSize = 15 * typographyScale

            foodCardMinHeight = isLandscape ? 96 : 120
            foodIconCircle = isLandscape ? 34 : 38
            foodIconSize = isLandscape ? 16 : 18
            foodTitleSize = 17 * typographyScale
            foodSubtitleSize = 13 * typographyScale

            hazardIconBox = isLandscape ? 44 : 50
            hazardIconSize = isLandscape ? 18 : 20
            hazardTitleSize = 17 * typographyScale
            hazardSubtitleSize = 13 * typographyScale
            hazardChevronSize = 16

            profileAvatarSize = (isLandscape ? 112 : 170) * verticalScale
            avatarPlusBadgeSize = isLandscape ? 34 : 44
            avatarPlusIconSize = isLandscape ? 16 : 20
            inputHeight = (isLandscape ? 54 : 60) * verticalScale
            inputTextSize = 17 * typographyScale

            rankTitleSize = 22 * typographyScale
            rankMetaSize = 14 * typographyScale
            rankIconBoxSize = isLandscape ? 62 : 74
            rankIconSize = isLandscape ? 26 : 30

            dotsSpacing = 8
            activeDotWidth = 26
            inactiveDotWidth = 10
            dotHeight = 8
        }
    }
}
