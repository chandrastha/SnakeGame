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
]

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

    var name: String {
        switch self {
        case .solid:   return "Solid"
        case .striped: return "Striped"
        case .dotted:  return "Dotted"
        case .scales:  return "Scales"
        case .crystal: return "Crystal"
        case .neon:    return "Neon"
        case .camo:    return "Camo"
        case .galaxy:  return "Galaxy"
        }
    }

    var emoji: String {
        switch self {
        case .solid:   return "⬤"
        case .striped: return "▤"
        case .dotted:  return "⁙"
        case .scales:  return "🐟"
        case .crystal: return "💎"
        case .neon:    return "✨"
        case .camo:    return "🌿"
        case .galaxy:  return "🌌"
        }
    }
}
