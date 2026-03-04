// LeaderboardView.swift

import SwiftUI

struct LeaderboardView: View {
    let scores: [Int]
    @Environment(\.dismiss) private var dismiss

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
                        .accessibilityIdentifier("closeButton")
                        Spacer()
                        Text("🏆 LEADERBOARD")
                            .accessibilityIdentifier("leaderboardTitle")
                            .font(.system(size: 24, weight: .black))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color(red: 0.3, green: 0.9, blue: 0.3),
                                             Color(red: 1.0, green: 0.85, blue: 0.0)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                        Spacer()
                        // Balance spacer
                        Color.clear.frame(width: 34, height: 34)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
                    .padding(.bottom, 24)

                    if scores.isEmpty {
                        Text("No scores yet.\nPlay a game to get started!")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .padding(.top, 60)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(Array(scores.prefix(10).enumerated()), id: \.offset) { index, score in
                                HStack {
                                    Text(medal(for: index))
                                        .font(.system(size: 22))
                                        .frame(width: 36)

                                    Text("#\(index + 1)")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(rankColor(for: index).opacity(0.75))
                                        .frame(width: 36, alignment: .leading)

                                    Spacer()

                                    Text("\(score) pts")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(rankColor(for: index))
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(rankBackground(for: index))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(index < 3 ? rankColor(for: index).opacity(0.30) : Color.clear, lineWidth: 1)
                                )
                                .padding(.horizontal, 24)
                            }
                        }
                        .padding(.bottom, 32)
                    }
                }
            }
        }
    }

    private func medal(for index: Int) -> String {
        switch index {
        case 0: return "🥇"
        case 1: return "🥈"
        case 2: return "🥉"
        default: return "🎯"
        }
    }

    private func rankColor(for index: Int) -> Color {
        switch index {
        case 0: return Color(red: 1.0, green: 0.84, blue: 0.0)   // gold
        case 1: return Color(red: 0.75, green: 0.80, blue: 0.90) // silver
        case 2: return Color(red: 0.85, green: 0.55, blue: 0.30) // bronze
        default: return Color.white
        }
    }

    private func rankBackground(for index: Int) -> Color {
        switch index {
        case 0: return Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.12)
        case 1: return Color(red: 0.75, green: 0.80, blue: 0.90).opacity(0.09)
        case 2: return Color(red: 0.85, green: 0.55, blue: 0.30).opacity(0.09)
        default: return Color.white.opacity(0.06)
        }
    }
}
