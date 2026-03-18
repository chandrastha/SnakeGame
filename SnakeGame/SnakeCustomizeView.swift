// SnakeCustomizeView.swift

import SwiftUI

struct SnakeCustomizeView: View {
    @AppStorage("selectedSnakeColorIndex")   private var selectedIndex: Int = 0
    @AppStorage("selectedSnakePatternIndex") private var selectedPatternIndex: Int = 0
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var economy = PlayerEconomy.shared
    @State private var purchaseTarget: SnakePattern? = nil

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)

    private var safeSelectedIndex: Int { normalizedSnakeColorIndex(selectedIndex) }
    private var selected: SnakeColorTheme { snakeColorThemes[safeSelectedIndex] }
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
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        Spacer()
                        Color.clear.frame(width: 34, height: 34)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .padding(.bottom, 16)

                    snakePreview
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)

                    Text("CHOOSE YOUR SKIN")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .kerning(2.5)
                        .padding(.bottom, 14)

                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(snakeColorThemes) { theme in
                            SkinCell(
                                theme: theme,
                                isSelected: selectedIndex == theme.id
                            ) {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.68)) {
                                    selectedIndex = normalizedSnakeColorIndex(theme.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)

                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(height: 1)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)

                    Text("CHOOSE PATTERN")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .kerning(2.5)
                        .padding(.bottom, 14)

                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(SnakePattern.allCases, id: \.rawValue) { pattern in
                            let unlocked = economy.isPatternUnlocked(pattern.rawValue)
                            PatternCell(
                                pattern: pattern,
                                theme: selected,
                                isSelected: selectedPatternIndex == pattern.rawValue,
                                isLocked: !unlocked,
                                cost: PlayerEconomy.patternCost(rawValue: pattern.rawValue)
                            ) {
                                if unlocked {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.68)) {
                                        selectedPatternIndex = pattern.rawValue
                                    }
                                } else {
                                    purchaseTarget = pattern
                                }
                            }
                        }
                    }
                    .confirmationDialog(
                        purchaseTarget.map { p in
                            let cost = PlayerEconomy.patternCost(rawValue: p.rawValue) ?? 0
                            let canAfford = economy.coins >= cost
                            return canAfford
                                ? "Unlock \(p.name) for \(cost) 🪙?"
                                : "\(p.name) costs \(cost) 🪙 — you have \(economy.coins)"
                        } ?? "",
                        isPresented: Binding(
                            get: { purchaseTarget != nil },
                            set: { if !$0 { purchaseTarget = nil } }
                        ),
                        titleVisibility: .visible
                    ) {
                        if let p = purchaseTarget {
                            let cost = PlayerEconomy.patternCost(rawValue: p.rawValue) ?? 0
                            if economy.coins >= cost {
                                Button("Unlock for \(cost) 🪙") {
                                    economy.unlockPattern(p.rawValue)
                                    purchaseTarget = nil
                                }
                            }
                            Button("Cancel", role: .cancel) { purchaseTarget = nil }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 36)
                }
            }
        }
    }

    private var snakePreview: some View {
        HStack(spacing: 0) {
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

            ForEach(0..<9, id: \.self) { i in
                let t = CGFloat(i) / 8.0
                let diameter = 32.0 * (1.0 - t * 0.56)
                let opacity = 1.0 - t * 0.18
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

private struct SkinCell: View {
    let theme: SnakeColorTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(theme.swiftUIColor)
                        .frame(width: 58, height: 58)
                        .shadow(color: theme.swiftUIColor.opacity(isSelected ? 0.75 : 0.0), radius: 10)

                    if isSelected {
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
                    .foregroundStyle(Color.white.opacity(isSelected ? 1.0 : 0.5))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.68), value: isSelected)
    }
}

private struct PatternCell: View {
    let pattern: SnakePattern
    let theme: SnakeColorTheme
    let isSelected: Bool
    let isLocked: Bool
    let cost: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(isLocked ? Color.white.opacity(0.06) : theme.swiftUIColor)
                        .frame(width: 52, height: 52)
                        .shadow(color: theme.swiftUIColor.opacity(isSelected ? 0.70 : 0), radius: 8)
                        .patternOverlay(
                            pattern: pattern,
                            color: isLocked ? Color.white.opacity(0.18) : theme.swiftUIColor,
                            size: 52,
                            segIndex: 0
                        )

                    if isLocked {
                        Circle()
                            .fill(Color.black.opacity(0.45))
                            .frame(width: 52, height: 52)
                        Image(systemName: "lock.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.85))
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

                if isLocked, let cost {
                    Text("\(cost) 🪙")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.82, blue: 0.20).opacity(0.90))
                } else {
                    Text(pattern.name)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.white.opacity(isSelected ? 1.0 : 0.5))
                }
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.68), value: isSelected)
    }
}

extension View {
    @ViewBuilder
    func patternOverlay(pattern: SnakePattern, color: Color, size: CGFloat, segIndex: Int = 0) -> some View {
        switch pattern {
        case .solid:
            self

        case .striped:
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
            self.overlay(
                Circle()
                    .fill(Color.white.opacity(0.95))
                    .frame(width: max(6, size * 0.20), height: max(6, size * 0.20))
                    .offset(y: -size * 0.24)
            )

        case .scales:
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
            self.overlay(
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.50))
                        .frame(width: size, height: size)
                    Circle()
                        .strokeBorder(Color(red: 0.60, green: 0.20, blue: 0.90).opacity(0.60), lineWidth: 1.5)
                        .frame(width: size * 0.74, height: size * 0.74)
                    Circle().fill(Color.white).frame(width: max(4, size * 0.09)).offset(x: -size * 0.22, y: -size * 0.20)
                    Circle().fill(Color.white).frame(width: max(3, size * 0.07)).offset(x:  size * 0.20, y: -size * 0.22)
                    Circle().fill(Color.white).frame(width: max(2, size * 0.05)).offset(x: -size * 0.10, y:  size * 0.22)
                }
            )

        case .zigzag:
            self.overlay(
                ZStack {
                    Capsule()
                        .fill(Color.white.opacity(0.62))
                        .frame(width: size * 0.18, height: size * 1.05)
                        .rotationEffect(.degrees(34))
                        .offset(x: -size * 0.18)
                    Capsule()
                        .fill(Color.white.opacity(0.30))
                        .frame(width: size * 0.16, height: size * 0.92)
                        .rotationEffect(.degrees(-28))
                        .offset(x: size * 0.14)
                }
                .clipShape(Circle())
            )

        case .ripple:
            self.overlay(
                ZStack {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.68), lineWidth: max(1.5, size * 0.06))
                        .frame(width: size * 0.82, height: size * 0.82)
                    Circle()
                        .strokeBorder(color.opacity(0.45), lineWidth: max(1.0, size * 0.04))
                        .frame(width: size * 0.48, height: size * 0.48)
                }
            )

        case .split:
            self.overlay(
                Rectangle()
                    .fill(Color.white.opacity(0.36))
                    .frame(width: size * 0.80, height: size * 1.18)
                    .rotationEffect(.degrees(36))
                    .offset(x: size * 0.18)
                    .clipShape(Circle())
            )

        case .ember:
            self.overlay(
                ZStack {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.78, blue: 0.22).opacity(0.80))
                        .frame(width: size * 0.28, height: size * 0.28)
                        .offset(x: -size * 0.16, y: -size * 0.10)
                    Circle()
                        .fill(Color(red: 1.0, green: 0.42, blue: 0.14).opacity(0.72))
                        .frame(width: size * 0.18, height: size * 0.18)
                        .offset(x: size * 0.20, y: size * 0.14)
                }
            )
            .shadow(color: Color(red: 1.0, green: 0.55, blue: 0.14).opacity(0.35), radius: 8)

        case .frost:
            self.overlay(
                ZStack {
                    Capsule()
                        .fill(Color.white.opacity(0.72))
                        .frame(width: size * 0.12, height: size * 0.72)
                    Capsule()
                        .fill(Color.white.opacity(0.50))
                        .frame(width: size * 0.72, height: size * 0.12)
                    Capsule()
                        .fill(Color(red: 0.70, green: 0.92, blue: 1.0).opacity(0.55))
                        .frame(width: size * 0.56, height: size * 0.10)
                        .rotationEffect(.degrees(45))
                }
                .clipShape(Circle())
            )

        case .ringed:
            self.overlay(
                ZStack {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.78), lineWidth: max(1.5, size * 0.07))
                        .frame(width: size * 0.70, height: size * 0.70)
                    Circle()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: size * 0.22, height: size * 0.22)
                }
            )

        case .toxic:
            self.overlay(
                ZStack {
                    Circle()
                        .fill(Color(red: 0.86, green: 1.0, blue: 0.24).opacity(0.78))
                        .frame(width: size * 0.34, height: size * 0.34)
                        .offset(x: -size * 0.18, y: size * 0.12)
                    Circle()
                        .fill(Color.black.opacity(0.26))
                        .frame(width: size * 0.18, height: size * 0.18)
                        .offset(x: size * 0.18, y: -size * 0.18)
                }
            )

        case .checker:
            self.overlay(
                ZStack {
                    ForEach(0..<2, id: \.self) { row in
                        ForEach(0..<2, id: \.self) { column in
                            Rectangle()
                                .fill((row + column).isMultiple(of: 2) ? Color.white.opacity(0.55) : Color.clear)
                                .frame(width: size * 0.30, height: size * 0.30)
                                .offset(
                                    x: CGFloat(column == 0 ? -1 : 1) * size * 0.16,
                                    y: CGFloat(row == 0 ? -1 : 1) * size * 0.16
                                )
                        }
                    }
                }
                .clipShape(Circle())
            )

        case .sphere:
            self.overlay(
                ZStack {
                    Ellipse()
                        .fill(Color.white.opacity(0.70))
                        .frame(width: size * 0.38, height: size * 0.28)
                        .offset(x: -size * 0.15, y: -size * 0.15)
                    Ellipse()
                        .fill(Color.black.opacity(0.22))
                        .frame(width: size * 0.45, height: size * 0.32)
                        .offset(x: size * 0.10, y: size * 0.11)
                }
                .clipShape(Circle())
            )

        case .diamondGrid:
            self.overlay(
                ZStack {
                    Rectangle()
                        .fill(Color.white.opacity(segIndex % 2 == 0 ? 0.40 : 0.10))
                        .frame(width: size * 0.80, height: size * 0.80)
                        .rotationEffect(.degrees(45))
                        .overlay(
                            Rectangle()
                                .stroke(Color.white.opacity(0.70), lineWidth: 1.2)
                                .frame(width: size * 0.80, height: size * 0.80)
                                .rotationEffect(.degrees(45))
                        )
                    Rectangle()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: size * 0.26, height: size * 0.26)
                        .rotationEffect(.degrees(45))
                        .offset(y: -size * 0.09)
                }
                .clipShape(Circle())
            )

        case .cylinder:
            self.overlay(
                ZStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.30))
                        .frame(width: size, height: size * 0.28)
                    Ellipse()
                        .fill(Color.white.opacity(0.42))
                        .frame(width: size * 0.80, height: size * 0.22)
                        .offset(y: -size * 0.28)
                }
                .clipShape(Circle())
            )

        case .armor:
            self.overlay(
                ZStack {
                    Rectangle()
                        .fill(Color(red: 1.0, green: 0.78, blue: 0.08).opacity(0.90))
                        .frame(width: size, height: size * 0.26)
                    Ellipse()
                        .fill(Color.white.opacity(0.38))
                        .frame(width: size * 0.70, height: size * 0.14)
                        .offset(y: -size * 0.04)
                }
                .clipShape(Circle())
            )

        case .leaf:
            self.overlay(
                ZStack {
                    Capsule()
                        .fill(Color.white.opacity(0.30))
                        .frame(width: size * 0.10, height: size * 0.72)
                    Ellipse()
                        .fill(Color.white.opacity(0.38))
                        .frame(width: size * 0.30, height: size * 0.18)
                        .offset(x: -size * 0.08, y: -size * 0.20)
                }
                .clipShape(Circle())
            )

        case .rainbow:
            self.overlay(
                ZStack {
                    Ellipse()
                        .fill(Color.white.opacity(0.70))
                        .frame(width: size * 0.38, height: size * 0.28)
                        .offset(x: -size * 0.15, y: -size * 0.15)
                    Ellipse()
                        .fill(Color.black.opacity(0.22))
                        .frame(width: size * 0.45, height: size * 0.32)
                        .offset(x: size * 0.10, y: size * 0.11)
                }
                .clipShape(Circle())
            )
        case .square:
            self
                .clipShape(RoundedRectangle(cornerRadius: size * 0.18))
                .overlay(
                    Ellipse()
                        .fill(Color.white.opacity(0.50))
                        .frame(width: size * 0.32, height: size * 0.20)
                        .offset(x: -size * 0.12, y: -size * 0.14)
                )
        case .stadium:
            self
                .clipShape(Capsule())
                .overlay(
                    Ellipse()
                        .fill(Color.white.opacity(0.50))
                        .frame(width: size * 0.28, height: size * 0.16)
                        .offset(x: -size * 0.15, y: -size * 0.10)
                )
        case .hexagon:
            self
                .clipShape(HexagonShape())
                .overlay(
                    Ellipse()
                        .fill(Color.white.opacity(0.50))
                        .frame(width: size * 0.30, height: size * 0.18)
                        .offset(x: -size * 0.12, y: -size * 0.14)
                )
        }
    }
}

private struct HexagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        for i in 0..<6 {
            let angle = CGFloat(i) * .pi / 3 - .pi / 6
            let pt = CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }
}

#Preview {
    SnakeCustomizeView()
}
