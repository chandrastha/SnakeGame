//
//  OnlineMatchView.swift
//  SnakeGame
//
//  Matchmaking / lobby sheet shown when the player taps PLAY in Online mode.
//

import SwiftUI

struct OnlineMatchView: View {

    // MARK: - Callbacks
    let onMatchReady: () -> Void
    let onCancel:     () -> Void

    // MARK: - Observed network state
    @StateObject private var photon = PhotonManager.shared

    // MARK: - Local UI state
    @State private var didStartConnect = false

    // MARK: - Computed helpers
    private var titleGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.3, green: 0.9, blue: 0.3),
                     Color(red: 1.0, green: 0.85, blue: 0.0)],
            startPoint: .leading, endPoint: .trailing
        )
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.12).ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Title ──
                Text("🌐  ONLINE")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(titleGradient)
                    .padding(.top, 36)
                    .padding(.bottom, 32)

                // ── State-driven content ──
                Group {
                    switch photon.connectionState {
                    case .disconnected:
                        connectingView(message: "Preparing…")

                    case .connecting:
                        connectingView(message: "Connecting to server…")

                    case .inLobby:
                        connectingView(message: "Finding a room…")

                    case .inRoom:
                        inRoomView

                    case .failed:
                        failedView
                    }
                }

                Spacer()

                // ── Cancel button ──
                Button(action: {
                    photon.disconnect()
                    onCancel()
                }) {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            guard !didStartConnect else { return }
            didStartConnect = true
            // connect() now internally calls joinOrCreateRoom() once auth succeeds
            photon.connect()
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Sub-views

    /// Spinner + message shown while connecting or finding a room.
    private func connectingView(message: String) -> some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.3, green: 0.9, blue: 0.4)))
                .scaleEffect(1.6)

            Text(message)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    /// Player count card + "Play Now" button shown once inside a room.
    private var inRoomView: some View {
        VStack(spacing: 28) {

            // Player count pill
            VStack(spacing: 6) {
                Text("\(photon.roomPlayerCount)")
                    .font(.system(size: 52, weight: .black))
                    .foregroundStyle(Color(red: 0.3, green: 0.9, blue: 0.4))

                Text("/ 100 players joined")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 32)

            // Subtitle
            if photon.roomPlayerCount < 100 {
                Text("Waiting for more players…")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.4))
            } else {
                Text("Room is full — starting!")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.3, green: 0.9, blue: 0.4))
            }

            // Play Now button (always visible once in room)
            Button(action: {
                photon.sendGameReady()
                onMatchReady()
            }) {
                Text("▶  PLAY NOW")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(Color.white)
                    .frame(width: 220, height: 58)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.2, green: 0.8, blue: 0.3),
                                     Color(red: 0.1, green: 0.6, blue: 0.2)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: Color(red: 0.2, green: 0.8, blue: 0.3).opacity(0.5),
                            radius: 12, x: 0, y: 4)
            }

            Text("You can also start before the room fills up")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.25))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    /// Error card shown on connection failure.
    private var failedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 38))
                .foregroundStyle(Color(red: 1.0, green: 0.35, blue: 0.3))

            Text("Connection failed")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color.white)

            // Show the actual Firebase error so it's diagnosable without Xcode
            if !photon.lastError.isEmpty {
                Text(photon.lastError)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color(red: 1.0, green: 0.6, blue: 0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 20)
            } else {
                Text("Check your internet connection and try again.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button(action: {
                // connect() will re-auth and auto-search for a room
                photon.connect()
            }) {
                Text("Retry")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.2, green: 0.55, blue: 0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
