import Foundation
import SwiftUI

// MARK: - HUD Element enum

enum HUDElement: String, CaseIterable, Codable {
    case joystick
    case boostButton
    case score
    case combo
    case miniLeaderboard
    case leaderArrow
    case minimap
    case pauseButton

    var displayName: String {
        switch self {
        case .joystick:        return "Joystick"
        case .boostButton:     return "Boost"
        case .score:           return "Score"
        case .combo:           return "Combo"
        case .miniLeaderboard: return "Leaderboard"
        case .leaderArrow:     return "Leader Arrow"
        case .minimap:         return "Minimap"
        case .pauseButton:     return "Pause"
        }
    }

    var shortLabel: String {
        switch self {
        case .joystick:        return "JOY"
        case .boostButton:     return "BOOST"
        case .score:           return "SCORE"
        case .combo:           return "COMBO"
        case .miniLeaderboard: return "LB"
        case .leaderArrow:     return "ARROW"
        case .minimap:         return "MAP"
        case .pauseButton:     return "⏸"
        }
    }

    /// Only joystick and boostButton support size customization.
    var supportsScale: Bool {
        self == .joystick || self == .boostButton
    }

    var tileColor: Color {
        switch self {
        case .joystick, .boostButton: return Color(red: 0.3, green: 0.8, blue: 0.3)
        case .score, .combo:          return Color(red: 0.9, green: 0.75, blue: 0.2)
        case .miniLeaderboard:        return Color(red: 0.4, green: 0.6, blue: 1.0)
        case .leaderArrow:            return Color(red: 1.0, green: 0.4, blue: 0.4)
        case .minimap:                return Color(red: 0.7, green: 0.4, blue: 1.0)
        case .pauseButton:            return Color(white: 0.6)
        }
    }

    var isCircular: Bool {
        self == .joystick || self == .boostButton || self == .minimap || self == .pauseButton
    }
}

// MARK: - HUD Element Config

struct HUDElementConfig: Codable, Equatable {
    /// Normalized screen position: 0 = left/bottom, 1 = right/top.
    var normalizedX: CGFloat
    var normalizedY: CGFloat
    /// Uniform scale multiplier. Range 0.5–2.0 (default 1.0).
    /// Only honored for joystick and boostButton.
    var scale: CGFloat

    init(normalizedX: CGFloat, normalizedY: CGFloat, scale: CGFloat = 1.0) {
        self.normalizedX = max(0, min(1, normalizedX))
        self.normalizedY = max(0, min(1, normalizedY))
        self.scale = max(0.5, min(2.0, scale))
    }
}

// MARK: - PlayAreaLayout

/// Stores portrait and landscape element positions separately so the user can
/// configure each orientation independently.
struct PlayAreaLayout: Identifiable, Equatable {
    var id:                UUID
    var name:              String
    var createdAt:         Date
    /// Portrait-mode positions. Keyed by HUDElement.rawValue.
    var portraitElements:  [String: HUDElementConfig]
    /// Landscape-mode positions. Falls back to portraitElements if empty.
    var landscapeElements: [String: HUDElementConfig]

    // Convenience lookup: returns the right config for the given orientation.
    func config(for element: HUDElement, isLandscape: Bool) -> HUDElementConfig? {
        if isLandscape, let cfg = landscapeElements[element.rawValue] { return cfg }
        return portraitElements[element.rawValue]
    }

    mutating func setConfig(_ cfg: HUDElementConfig, for element: HUDElement, isLandscape: Bool) {
        if isLandscape {
            landscapeElements[element.rawValue] = cfg
        } else {
            portraitElements[element.rawValue] = cfg
        }
    }

    // Built-in default — empty element dicts means GameScene uses its own margin helpers.
    static let defaultID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let `default` = PlayAreaLayout(
        id:               defaultID,
        name:             "Default",
        createdAt:        .distantPast,
        portraitElements: [:],
        landscapeElements: [:]
    )

    var isDefault: Bool { id == Self.defaultID }
}

// MARK: - Codable (manual, for backward compat with old "elements" key)

extension PlayAreaLayout: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt
        case portraitElements
        case landscapeElements
        case elements        // legacy key from v1
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(UUID.self,   forKey: .id)
        name      = try c.decode(String.self, forKey: .name)
        createdAt = try c.decode(Date.self,   forKey: .createdAt)
        // Prefer new key; fall back to old "elements" key for saved data from v1
        portraitElements = try c.decodeIfPresent([String: HUDElementConfig].self, forKey: .portraitElements)
            ?? c.decodeIfPresent([String: HUDElementConfig].self, forKey: .elements)
            ?? [:]
        landscapeElements = try c.decodeIfPresent([String: HUDElementConfig].self, forKey: .landscapeElements) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,               forKey: .id)
        try c.encode(name,             forKey: .name)
        try c.encode(createdAt,        forKey: .createdAt)
        try c.encode(portraitElements,  forKey: .portraitElements)
        try c.encode(landscapeElements, forKey: .landscapeElements)
    }
}

// MARK: - PlayAreaLayoutStore

final class PlayAreaLayoutStore: ObservableObject {
    static let shared = PlayAreaLayoutStore()

    private let layoutsKey  = "playAreaLayouts_v2"   // bumped to avoid stale v1 data conflicts
    private let activeIDKey = "playAreaActiveLayoutID_v1"

    @Published private(set) var layouts:      [PlayAreaLayout] = [.default]
    @Published private(set) var activeLayout: PlayAreaLayout   = .default

    private init() { load() }

    // MARK: CRUD

    func save(_ layout: PlayAreaLayout) {
        guard !layout.isDefault else { return }
        if let idx = layouts.firstIndex(where: { $0.id == layout.id }) {
            layouts[idx] = layout
        } else {
            layouts.append(layout)
        }
        persist()
    }

    func delete(_ layout: PlayAreaLayout) {
        guard !layout.isDefault else { return }
        layouts.removeAll { $0.id == layout.id }
        if activeLayout.id == layout.id { setActive(.default) }
        persist()
    }

    func setActive(_ layout: PlayAreaLayout) {
        activeLayout = layout
        UserDefaults.standard.set(layout.id.uuidString, forKey: activeIDKey)
    }

    // MARK: Persistence

    private func persist() {
        let userLayouts = layouts.filter { !$0.isDefault }
        if let data = try? JSONEncoder().encode(userLayouts) {
            UserDefaults.standard.set(data, forKey: layoutsKey)
        }
    }

    private func load() {
        var loaded: [PlayAreaLayout] = [.default]
        if let data = UserDefaults.standard.data(forKey: layoutsKey),
           let decoded = try? JSONDecoder().decode([PlayAreaLayout].self, from: data) {
            loaded += decoded
        }
        layouts = loaded

        let savedIDStr = UserDefaults.standard.string(forKey: activeIDKey) ?? ""
        let savedID    = UUID(uuidString: savedIDStr)
        activeLayout   = layouts.first { $0.id == savedID } ?? .default
    }

    // MARK: Default positions (mirrors GameScene margin helpers)
    //
    // All normalizedX/Y use the convention: 0=left/bottom, 1=right/top.
    // These match the game's default margin positions (no safe area) on a
    // 390×844 portrait / 844×390 landscape reference device.

    static func defaultConfig(for element: HUDElement, isLandscape: Bool) -> HUDElementConfig {
        switch element {
        case .joystick:
            // max(w*0.22, 90) from left; max(h*0.18, 130) from bottom
            return isLandscape
                ? HUDElementConfig(normalizedX: 0.11, normalizedY: 0.33)
                : HUDElementConfig(normalizedX: 0.23, normalizedY: 0.18)

        case .boostButton:
            // Mirrored to joystick from right edge
            return isLandscape
                ? HUDElementConfig(normalizedX: 0.89, normalizedY: 0.33)
                : HUDElementConfig(normalizedX: 0.77, normalizedY: 0.18)

        case .score:
            // Below leader arrow: arrow (74pt) + 44pt clearance = 118pt from top → y = 1 - 118/844
            return isLandscape
                ? HUDElementConfig(normalizedX: 0.50, normalizedY: 0.71)
                : HUDElementConfig(normalizedX: 0.50, normalizedY: 0.86)

        case .combo:
            // Below score: ~187pt from top center → y = 1 - 187/844
            return isLandscape
                ? HUDElementConfig(normalizedX: 0.50, normalizedY: 0.55)
                : HUDElementConfig(normalizedX: 0.50, normalizedY: 0.78)

        case .miniLeaderboard:
            // Center = 112pt from left, 113pt from top → x=112/390, y=1-113/844
            return isLandscape
                ? HUDElementConfig(normalizedX: 0.13, normalizedY: 0.69)
                : HUDElementConfig(normalizedX: 0.29, normalizedY: 0.87)

        case .leaderArrow:
            // 74pt from top → y = 1 - 74/844
            return isLandscape
                ? HUDElementConfig(normalizedX: 0.50, normalizedY: 0.83)
                : HUDElementConfig(normalizedX: 0.50, normalizedY: 0.91)

        case .minimap:
            // 88pt from right = 302/390 from left; 68pt from top → y=1-68/844
            return isLandscape
                ? HUDElementConfig(normalizedX: 0.87, normalizedY: 0.80)
                : HUDElementConfig(normalizedX: 0.77, normalizedY: 0.92)

        case .pauseButton:
            // 42pt from right, 42pt from top
            return isLandscape
                ? HUDElementConfig(normalizedX: 0.95, normalizedY: 0.89)
                : HUDElementConfig(normalizedX: 0.89, normalizedY: 0.95)
        }
    }
}
