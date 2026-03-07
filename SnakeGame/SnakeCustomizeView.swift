// SnakeCustomizeView.swift

import SwiftUI

struct SnakeCustomizeView: View {
    @AppStorage("selectedSnakeColorIndex")   var selectedIndex:        Int = 0
    @AppStorage("selectedSnakePatternIndex") var selectedPatternIndex: Int = 0
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var coins = CoinManager.shared

    @State private var pendingColorIndex:   Int  = 0
    @State private var pendingPatternIndex: Int  = 0
    @State private var showColorUnlock:     Bool = false
    @State private var showPatternUnlock:   Bool = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)

    private var selected: SnakeColorTheme { snakeColorThemes[selectedIndex] }
    private var selectedPattern: SnakePattern { SnakePattern(rawValue: selectedPatternIndex) ?? .solid }

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

                    // Header — dismiss + title + coin balance
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
                        Text("SNAKE SKINS")
                            .font(.system(size: 22, weight: .black))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(red: 0.3, green: 0.9, blue: 0.3),
                                             Color(red: 1.0, green: 0.85, blue: 0.0)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                        Spacer()
                        // Coin balance
                        HStack(spacing: 3) {
                            Text("🪙").font(.system(size: 12))
                            Text("\(coins.balance)")
                                .font(.system(size: 13, weight: .black))
                                .foregroundStyle(Color.yellow)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.yellow.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .padding(.bottom, 16)

                    // Live snake preview
                    snakePreview
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)

                    // ─── Color section ───
                    Text("CHOOSE YOUR SKIN")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .kerning(2.5)
                        .padding(.bottom, 14)

                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(snakeColorThemes) { theme in
                            SkinCell(
                                theme: theme,
                                isSelected: selectedIndex == theme.id,
                                isLocked: !coins.isUnlocked(colorIndex: theme.id),
                                lockCost: CoinManager.colorCost
                            ) {
                                if coins.isUnlocked(colorIndex: theme.id) {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.68)) {
                                        selectedIndex = theme.id
                                    }
                                } else {
                                    pendingColorIndex = theme.id
                                    showColorUnlock   = true
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)

                    // ─── Divider ───
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(height: 1)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)

                    // ─── Pattern section ───
                    Text("CHOOSE PATTERN")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .kerning(2.5)
                        .padding(.bottom, 14)

                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(SnakePattern.allCases, id: \.rawValue) { pattern in
                            PatternCell(
                                pattern: pattern,
                                theme: selected,
                                isSelected: selectedPatternIndex == pattern.rawValue,
                                isLocked: !coins.isUnlocked(patternIndex: pattern.rawValue),
                                lockCost: CoinManager.patternCost
                            ) {
                                if coins.isUnlocked(patternIndex: pattern.rawValue) {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.68)) {
                                        selectedPatternIndex = pattern.rawValue
                                    }
                                } else {
                                    pendingPatternIndex = pattern.rawValue
                                    showPatternUnlock   = true
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 36)
                }
            }
        }
        // Color unlock dialog
        .confirmationDialog(
            "Unlock \(snakeColorThemes[pendingColorIndex].emoji) \(snakeColorThemes[pendingColorIndex].name) for \(CoinManager.colorCost) coins?",
            isPresented: $showColorUnlock,
            titleVisibility: .visible
        ) {
            Button("Unlock (\(CoinManager.colorCost) coins)") {
                if coins.unlock(colorIndex: pendingColorIndex) {
                    withAnimation { selectedIndex = pendingColorIndex }
                }
            }
            .disabled(coins.balance < CoinManager.colorCost)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Balance: \(coins.balance) coins")
        }
        // Pattern unlock dialog
        .confirmationDialog(
            "Unlock \(SnakePattern(rawValue: pendingPatternIndex)?.emoji ?? "") \(SnakePattern(rawValue: pendingPatternIndex)?.name ?? "") pattern for \(CoinManager.patternCost) coins?",
            isPresented: $showPatternUnlock,
            titleVisibility: .visible
        ) {
            Button("Unlock (\(CoinManager.patternCost) coins)") {
                if coins.unlock(patternIndex: pendingPatternIndex) {
                    withAnimation { selectedPatternIndex = pendingPatternIndex }
                }
            }
            .disabled(coins.balance < CoinManager.patternCost)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Balance: \(coins.balance) coins")
        }
    }

    // Animated snake preview strip
    private var snakePreview: some View {
        HStack(spacing: 0) {
            // Head
            ZStack {
                Circle()
                    .fill(selected.swiftUIColor)
                    .frame(width: 38, height: 38)
                    .shadow(color: selected.swiftUIColor.opacity(0.6), radius: 8)

                HStack(spacing: 10) {
                    Circle().fill(Color.white).frame(width: 7, height: 7)
                    Circle().fill(Color.white).frame(width: 7, height: 7)
                }
                .offset(y: -3)
            }

            // Body segments (tapering, with selected pattern)
            ForEach(0..<9, id: \.self) { i in
                let t        = CGFloat(i) / 8.0
                let diameter = 32.0 * (1.0 - t * 0.56)
                let opacity  = 1.0 - t * 0.18
                ZStack {
                    Circle()
                        .fill(selected.bodySwiftUIColor.opacity(opacity))
                        .frame(width: diameter, height: diameter)
                        .patternOverlay(
                            pattern: selectedPattern,
                            color: selected.bodySwiftUIColor.opacity(opacity),
                            size: diameter,
                            segIndex: i
                        )
                }
                .frame(width: diameter, height: diameter)
                .padding(.leading, 1)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(selected.swiftUIColor.opacity(0.3), lineWidth: 1.5)
        )
    }
}

// MARK: - Skin Cell
private struct SkinCell: View {
    let theme: SnakeColorTheme
    let isSelected: Bool
    let isLocked: Bool
    let lockCost: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(theme.swiftUIColor.opacity(isLocked ? 0.45 : 1.0))
                        .frame(width: 58, height: 58)
                        .shadow(color: theme.swiftUIColor.opacity(isSelected ? 0.75 : 0.0), radius: 10)

                    if isLocked {
                        Circle()
                            .fill(Color.black.opacity(0.45))
                            .frame(width: 58, height: 58)
                        VStack(spacing: 2) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.yellow)
                            Text("\(lockCost)🪙")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(Color.yellow)
                        }
                    } else if isSelected {
                        Circle()
                            .strokeBorder(Color.white, lineWidth: 2.5)
                            .frame(width: 58, height: 58)
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .black))
                            .foregroundStyle(Color.white)
                    }
                }
                .scaleEffect(isSelected ? 1.1 : 1.0)

                Text(theme.name)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(isLocked ? 0.35 : (isSelected ? 1.0 : 0.5)))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.68), value: isSelected)
    }
}

// MARK: - Pattern Cell
private struct PatternCell: View {
    let pattern: SnakePattern
    let theme: SnakeColorTheme
    let isSelected: Bool
    let isLocked: Bool
    let lockCost: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(theme.swiftUIColor.opacity(isLocked ? 0.40 : 1.0))
                        .frame(width: 52, height: 52)
                        .shadow(color: theme.swiftUIColor.opacity(isSelected ? 0.70 : 0), radius: 8)
                        .patternOverlay(
                            pattern: pattern,
                            color: theme.swiftUIColor,
                            size: 52,
                            segIndex: 0
                        )

                    if isLocked {
                        Circle()
                            .fill(Color.black.opacity(0.45))
                            .frame(width: 52, height: 52)
                        VStack(spacing: 2) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.yellow)
                            Text("\(lockCost)🪙")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(Color.yellow)
                        }
                    } else if isSelected {
                        Circle()
                            .strokeBorder(Color.white, lineWidth: 2.5)
                            .frame(width: 52, height: 52)
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(Color.white)
                    }
                }
                .scaleEffect(isSelected ? 1.1 : 1.0)

                Text(pattern.name)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(isLocked ? 0.35 : (isSelected ? 1.0 : 0.5)))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.68), value: isSelected)
    }
}

// MARK: - Pattern Overlay ViewBuilder
extension View {
    @ViewBuilder
    func patternOverlay(pattern: SnakePattern, color: Color, size: CGFloat, segIndex: Int = 0) -> some View {
        switch pattern {
        case .solid:
            self

        case .striped:
            // Two-tone: alternate segments show a bright white vertical band (represents stroke-colour fill)
            if segIndex % 2 == 1 {
                self.overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.60))
                        .frame(width: size * 0.45, height: size)
                        .clipShape(Circle())
                )
            } else {
                self.overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: size * 0.45, height: size)
                        .clipShape(Circle())
                )
            }

        case .dotted:
            // Larger dot in a contrasting white — clearly visible accent
            self.overlay(
                Circle()
                    .fill(Color.white.opacity(0.95))
                    .frame(width: max(6, size * 0.20), height: max(6, size * 0.20))
                    .offset(y: -size * 0.24)
            )

        case .scales:
            // Higher-opacity crescent + visible stroke ring
            self.overlay(
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.45))
                        .frame(width: size * 0.55, height: size * 0.55)
                        .offset(x: size * 0.14, y: -size * 0.14)
                    Circle()
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1.0)
                        .frame(width: size * 0.55, height: size * 0.55)
                        .offset(x: size * 0.14, y: -size * 0.14)
                }
                .clipShape(Circle())
            )

        case .crystal:
            // Outer diamond + inner diamond highlight (diamond-in-diamond)
            self.overlay(
                ZStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: size * 0.55, height: size * 0.55)
                        .rotationEffect(.degrees(45))
                    Rectangle()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: size * 0.28, height: size * 0.28)
                        .rotationEffect(.degrees(45))
                }
            )

        case .neon:
            // Strong glow + outer ring + inner ring
            self
                .shadow(color: color, radius: 12)
                .overlay(
                    ZStack {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.80), lineWidth: 2.5)
                            .frame(width: size * 0.80, height: size * 0.80)
                        Circle()
                            .strokeBorder(color.opacity(0.55), lineWidth: 1.5)
                            .frame(width: size * 0.56, height: size * 0.56)
                    }
                )

        case .camo:
            // Real camo: dark-green + dark-brown blotches
            self.overlay(
                ZStack {
                    Circle()
                        .fill(Color(red: 0.15, green: 0.45, blue: 0.10).opacity(0.70))
                        .frame(width: size * 0.42, height: size * 0.42)
                        .offset(x: -size * 0.16, y: size * 0.14)
                    Circle()
                        .fill(Color(red: 0.40, green: 0.25, blue: 0.02).opacity(0.65))
                        .frame(width: size * 0.28, height: size * 0.28)
                        .offset(x: size * 0.18, y: -size * 0.16)
                }
            )

        case .galaxy:
            // Dark base + varied stars + purple nebula ring
            self.overlay(
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.50))
                        .frame(width: size, height: size)
                    // Nebula ring
                    Circle()
                        .strokeBorder(Color(red: 0.60, green: 0.20, blue: 0.90).opacity(0.60), lineWidth: 1.5)
                        .frame(width: size * 0.74, height: size * 0.74)
                    // Star dots — varied sizes
                    Circle().fill(Color.white).frame(width: max(4, size * 0.09)).offset(x: -size * 0.22, y: -size * 0.20)
                    Circle().fill(Color.white).frame(width: max(3, size * 0.07)).offset(x:  size * 0.20, y: -size * 0.22)
                    Circle().fill(Color.white).frame(width: max(2, size * 0.05)).offset(x: -size * 0.10, y:  size * 0.22)
                }
            )
        }
    }
}

#Preview {
    SnakeCustomizeView()
}
