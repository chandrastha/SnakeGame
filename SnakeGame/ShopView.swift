// ShopView.swift

import SwiftUI

struct ShopView: View {
    @ObservedObject private var coins = CoinManager.shared
    @Environment(\.dismiss) var dismiss

    @AppStorage("selectedSnakeColorIndex")   private var selectedColorIndex:   Int = 0
    @AppStorage("selectedSnakePatternIndex") private var selectedPatternIndex: Int = 0

    @State private var pendingColorIndex:   Int = 0
    @State private var pendingPatternIndex: Int = 0
    @State private var showColorUnlock:   Bool = false
    @State private var showPatternUnlock: Bool = false
    @State private var justUnlocked: Int? = nil  // flashes purchased item

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        ZStack {
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

            ScrollView {
                VStack(spacing: 0) {

                    // Header
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.7))
                                .frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.1))
                                .clipShape(Circle())
                        }
                        Spacer()
                        Text("COIN SHOP")
                            .font(.system(size: 22, weight: .black))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(red: 1.0, green: 0.85, blue: 0.0),
                                             Color(red: 1.0, green: 0.60, blue: 0.0)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                        Spacer()
                        Color.clear.frame(width: 34, height: 34)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .padding(.bottom, 12)

                    // Coin balance
                    coinBalanceBadge
                        .padding(.bottom, 24)

                    // Colors section
                    sectionHeader("SNAKE COLORS", cost: CoinManager.colorCost)

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(snakeColorThemes) { theme in
                            shopColorCell(theme: theme)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)

                    // Divider
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(height: 1)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)

                    // Patterns section
                    sectionHeader("PATTERNS", cost: CoinManager.patternCost)

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(SnakePattern.allCases, id: \.rawValue) { pattern in
                            shopPatternCell(pattern: pattern)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
        }
        // Color unlock sheet
        .confirmationDialog(
            "Unlock \(snakeColorThemes[pendingColorIndex].emoji) \(snakeColorThemes[pendingColorIndex].name) for \(CoinManager.colorCost) coins?",
            isPresented: $showColorUnlock,
            titleVisibility: .visible
        ) {
            Button("Unlock (\(CoinManager.colorCost) coins)") {
                if coins.unlock(colorIndex: pendingColorIndex) {
                    selectedColorIndex = pendingColorIndex
                    justUnlocked = pendingColorIndex
                }
            }
            .disabled(coins.balance < CoinManager.colorCost)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Balance: \(coins.balance) coins")
        }
        // Pattern unlock sheet
        .confirmationDialog(
            "Unlock \(SnakePattern(rawValue: pendingPatternIndex)?.emoji ?? "") \(SnakePattern(rawValue: pendingPatternIndex)?.name ?? "") for \(CoinManager.patternCost) coins?",
            isPresented: $showPatternUnlock,
            titleVisibility: .visible
        ) {
            Button("Unlock (\(CoinManager.patternCost) coins)") {
                if coins.unlock(patternIndex: pendingPatternIndex) {
                    selectedPatternIndex = pendingPatternIndex
                    justUnlocked = 1000 + pendingPatternIndex
                }
            }
            .disabled(coins.balance < CoinManager.patternCost)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Balance: \(coins.balance) coins")
        }
    }

    // MARK: - Sub-views

    private var coinBalanceBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.fill")
                .foregroundStyle(Color.yellow)
                .font(.system(size: 18))
            Text("\(coins.balance)")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(Color.yellow)
            Text("coins")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.yellow.opacity(0.7))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(Color.yellow.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Color.yellow.opacity(0.30), lineWidth: 1.5))
    }

    private func sectionHeader(_ title: String, cost: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.45))
                .kerning(2.5)
            Spacer()
            Text("\(cost) coins each")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.yellow.opacity(0.55))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private func shopColorCell(theme: SnakeColorTheme) -> some View {
        let unlocked = coins.isUnlocked(colorIndex: theme.id)
        Button(action: {
            if unlocked {
                selectedColorIndex = theme.id
            } else {
                pendingColorIndex = theme.id
                showColorUnlock = true
            }
        }) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(theme.swiftUIColor)
                        .frame(width: 52, height: 52)
                        .shadow(color: theme.swiftUIColor.opacity(unlocked ? 0.5 : 0.15), radius: 8)

                    if !unlocked {
                        // Dimming overlay
                        Circle()
                            .fill(Color.black.opacity(0.52))
                            .frame(width: 52, height: 52)
                        VStack(spacing: 2) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.yellow)
                            Text("\(CoinManager.colorCost)")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(Color.yellow)
                        }
                    } else if selectedColorIndex == theme.id {
                        Circle()
                            .strokeBorder(Color.white, lineWidth: 2.5)
                            .frame(width: 52, height: 52)
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(Color.white)
                    }
                }
                .scaleEffect(selectedColorIndex == theme.id ? 1.08 : 1.0)

                Text(theme.emoji + " " + theme.name)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white.opacity(unlocked ? (selectedColorIndex == theme.id ? 1.0 : 0.55) : 0.35))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.68), value: selectedColorIndex)
    }

    @ViewBuilder
    private func shopPatternCell(pattern: SnakePattern) -> some View {
        let unlocked = coins.isUnlocked(patternIndex: pattern.rawValue)
        let currentTheme = snakeColorThemes[min(selectedColorIndex, snakeColorThemes.count - 1)]
        Button(action: {
            if unlocked {
                selectedPatternIndex = pattern.rawValue
            } else {
                pendingPatternIndex = pattern.rawValue
                showPatternUnlock = true
            }
        }) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(currentTheme.swiftUIColor.opacity(unlocked ? 1.0 : 0.4))
                        .frame(width: 52, height: 52)
                        .shadow(color: currentTheme.swiftUIColor.opacity(unlocked ? 0.5 : 0), radius: 8)
                        .patternOverlay(
                            pattern: pattern,
                            color: currentTheme.swiftUIColor,
                            size: 52,
                            segIndex: 0
                        )

                    if !unlocked {
                        Circle()
                            .fill(Color.black.opacity(0.52))
                            .frame(width: 52, height: 52)
                        VStack(spacing: 2) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.yellow)
                            Text("\(CoinManager.patternCost)")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(Color.yellow)
                        }
                    } else if selectedPatternIndex == pattern.rawValue {
                        Circle()
                            .strokeBorder(Color.white, lineWidth: 2.5)
                            .frame(width: 52, height: 52)
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(Color.white)
                    }
                }
                .scaleEffect(selectedPatternIndex == pattern.rawValue ? 1.08 : 1.0)

                Text(pattern.emoji + " " + pattern.name)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white.opacity(unlocked ? (selectedPatternIndex == pattern.rawValue ? 1.0 : 0.55) : 0.35))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.68), value: selectedPatternIndex)
    }
}

#Preview {
    ShopView()
}
