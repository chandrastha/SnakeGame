// LeaderboardView.swift

import SwiftUI

struct LeaderboardView: View {
    let scores: [Int]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(red: 0.1, green: 0.1, blue: 0.15)
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
                                        .foregroundStyle(Color.white.opacity(0.5))
                                        .frame(width: 36, alignment: .leading)

                                    Spacer()

                                    Text("\(score) pts")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(index == 0
                                            ? Color(red: 1.0, green: 0.85, blue: 0.0)
                                            : Color.white)
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(index == 0 ? 0.12 : 0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
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
}
