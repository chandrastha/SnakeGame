// SnakeColors.swift

import SpriteKit
import SwiftUI

// MARK: - Color Theme
struct SnakeColorTheme: Identifiable {
    let id: Int
    let name: String
    let emoji: String
    let headR, headG, headB: CGFloat
    let bodyR, bodyG, bodyB: CGFloat

    // SpriteKit colors
    var headSKColor: SKColor {
        SKColor(red: headR, green: headG, blue: headB, alpha: 1.0)
    }
    var headStrokeSKColor: SKColor {
        SKColor(red: max(0, headR - 0.12), green: max(0, headG - 0.12), blue: max(0, headB - 0.12), alpha: 1.0)
    }
    var bodySKColor: SKColor {
        SKColor(red: bodyR, green: bodyG, blue: bodyB, alpha: 1.0)
    }
    var bodyStrokeSKColor: SKColor {
        SKColor(red: max(0, bodyR - 0.12), green: max(0, bodyG - 0.12), blue: max(0, bodyB - 0.12), alpha: 1.0)
    }

    // SwiftUI colors
    var swiftUIColor: Color {
        Color(red: Double(headR), green: Double(headG), blue: Double(headB))
    }
    var bodySwiftUIColor: Color {
        Color(red: Double(bodyR), green: Double(bodyG), blue: Double(bodyB))
    }
}

// MARK: - Available Themes
let snakeColorThemes: [SnakeColorTheme] = [
    SnakeColorTheme(id: 0, name: "Forest",  emoji: "🌿",
                    headR: 0.40, headG: 0.80, headB: 0.40,
                    bodyR: 0.32, bodyG: 0.68, bodyB: 0.32),

    SnakeColorTheme(id: 1, name: "Ocean",   emoji: "🌊",
                    headR: 0.20, headG: 0.62, headB: 0.92,
                    bodyR: 0.14, bodyG: 0.50, bodyB: 0.80),

    SnakeColorTheme(id: 2, name: "Fire",    emoji: "🔥",
                    headR: 0.95, headG: 0.35, headB: 0.08,
                    bodyR: 0.85, bodyG: 0.24, bodyB: 0.04),

    SnakeColorTheme(id: 3, name: "Royal",   emoji: "💜",
                    headR: 0.70, headG: 0.28, headB: 0.92,
                    bodyR: 0.58, bodyG: 0.18, bodyB: 0.80),

    SnakeColorTheme(id: 4, name: "Gold",    emoji: "✨",
                    headR: 0.95, headG: 0.78, headB: 0.08,
                    bodyR: 0.85, bodyG: 0.66, bodyB: 0.04),

    SnakeColorTheme(id: 5, name: "Neon",    emoji: "💗",
                    headR: 1.00, headG: 0.38, headB: 0.72,
                    bodyR: 0.88, bodyG: 0.26, bodyB: 0.60),

    SnakeColorTheme(id: 6, name: "Ice",     emoji: "❄️",
                    headR: 0.66, headG: 0.88, headB: 1.00,
                    bodyR: 0.55, bodyG: 0.76, bodyB: 0.94),

    SnakeColorTheme(id: 7, name: "Shadow",  emoji: "🖤",
                    headR: 0.42, headG: 0.42, headB: 0.50,
                    bodyR: 0.30, bodyG: 0.30, bodyB: 0.38),

    SnakeColorTheme(id: 8, name: "Sunset",  emoji: "🌇",
                    headR: 0.98, headG: 0.56, headB: 0.28,
                    bodyR: 0.89, bodyG: 0.36, bodyB: 0.22),

    SnakeColorTheme(id: 9, name: "Mint",    emoji: "🍃",
                    headR: 0.48, headG: 0.96, headB: 0.78,
                    bodyR: 0.30, bodyG: 0.82, bodyB: 0.64),

    SnakeColorTheme(id: 10, name: "Crimson", emoji: "🩸",
                    headR: 0.88, headG: 0.18, headB: 0.24,
                    bodyR: 0.70, bodyG: 0.10, bodyB: 0.16),

    SnakeColorTheme(id: 11, name: "Copper",  emoji: "🪙",
                    headR: 0.80, headG: 0.48, headB: 0.22,
                    bodyR: 0.63, bodyG: 0.34, bodyB: 0.14),

    SnakeColorTheme(id: 12, name: "Storm",   emoji: "⛈",
                    headR: 0.54, headG: 0.66, headB: 0.84,
                    bodyR: 0.37, bodyG: 0.49, bodyB: 0.69),

    SnakeColorTheme(id: 13, name: "Orchid",  emoji: "🌸",
                    headR: 0.90, headG: 0.44, headB: 0.86,
                    bodyR: 0.73, bodyG: 0.30, bodyB: 0.70),

    SnakeColorTheme(id: 14, name: "Toxic",   emoji: "☣️",
                    headR: 0.72, headG: 0.92, headB: 0.12,
                    bodyR: 0.48, bodyG: 0.74, bodyB: 0.06),

    SnakeColorTheme(id: 15, name: "Pearl",   emoji: "🫧",
                    headR: 0.94, headG: 0.96, headB: 1.00,
                    bodyR: 0.76, bodyG: 0.82, bodyB: 0.92),
]

func normalizedSnakeColorIndex(_ index: Int) -> Int {
    guard !snakeColorThemes.isEmpty else { return 0 }
    return min(max(index, 0), snakeColorThemes.count - 1)
}

// MARK: - Snake Patterns
enum SnakePattern: Int, CaseIterable {
    case solid   = 0   // Default flat fill
    case striped = 1   // Every 2nd segment lightened
    case dotted  = 2   // White accent dot on each segment
    case scales  = 3   // Crescent highlight overlay
    case crystal = 4   // Diamond shape
    case neon    = 5   // Extra bright glow ring
    case camo    = 6   // Dark blotch overlay
    case galaxy  = 7   // Dark base + star sparkle dots
    case zigzag  = 8   // Angled streaks
    case ripple  = 9   // Concentric wave rings
    case split   = 10  // Diagonal two-tone cut
    case ember   = 11  // Warm sparks and glow
    case frost   = 12  // Ice-line cross highlights
    case ringed  = 13  // Bold center ring
    case toxic   = 14  // Acid blobs
    case checker     = 15  // Checker tiles
    case sphere      = 16  // 3D ball with specular highlight and shadow
    case diamondGrid = 17  // Woven diamond lattice (silver scale)
    case cylinder    = 18  // Striped pill segments oriented to travel direction
    case armor       = 19  // Dark capsule with gold band rings
    case leaf        = 20  // Organic leaf-shaped segments with vein
    case rainbow     = 21  // Each segment cycles through rainbow hues

    var name: String {
        switch self {
        case .solid:       return "Solid"
        case .striped:     return "Striped"
        case .dotted:      return "Dotted"
        case .scales:      return "Scales"
        case .crystal:     return "Crystal"
        case .neon:        return "Neon"
        case .camo:        return "Camo"
        case .galaxy:      return "Galaxy"
        case .zigzag:      return "Zigzag"
        case .ripple:      return "Ripple"
        case .split:       return "Split"
        case .ember:       return "Ember"
        case .frost:       return "Frost"
        case .ringed:      return "Ringed"
        case .toxic:       return "Toxic"
        case .checker:     return "Checker"
        case .sphere:      return "Sphere"
        case .diamondGrid: return "Diamond"
        case .cylinder:    return "Cylinder"
        case .armor:       return "Armor"
        case .leaf:        return "Leaf"
        case .rainbow:     return "Rainbow"
        }
    }

    var emoji: String {
        switch self {
        case .solid:       return "⬤"
        case .striped:     return "▤"
        case .dotted:      return "⁙"
        case .scales:      return "🐟"
        case .crystal:     return "💎"
        case .neon:        return "✨"
        case .camo:        return "🌿"
        case .galaxy:      return "🌌"
        case .zigzag:      return "⚡️"
        case .ripple:      return "🌀"
        case .split:       return "◐"
        case .ember:       return "🔥"
        case .frost:       return "❄️"
        case .ringed:      return "◎"
        case .toxic:       return "☣️"
        case .checker:     return "▦"
        case .sphere:      return "🔵"
        case .diamondGrid: return "🔷"
        case .cylinder:    return "🥫"
        case .armor:       return "🛡️"
        case .leaf:        return "🍃"
        case .rainbow:     return "🌈"
        }
    }
}
