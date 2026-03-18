// PlayerEconomy.swift
// Singleton managing soft-currency (Coins), pattern unlock state, and per-run earnings.

import Foundation
import Combine

final class PlayerEconomy: ObservableObject {
    static let shared = PlayerEconomy()

    // MARK: - Persistent state
    @Published private(set) var coins: Int = 0
    private(set) var unlockedPatterns: Set<Int> = []

    // MARK: - Per-run session state (not persisted)
    var sessionCoins: Int = 0

    // MARK: - Pattern pricing tiers
    // rawValue 0–4  → free (Tier 0 / Common)
    // rawValue 5–14 → 300 coins (Tier 1 / Rare)
    // rawValue 15+  → 800 coins (Tier 2 / Epic)
    static func patternCost(rawValue: Int) -> Int? {
        switch rawValue {
        case 0...4:  return nil   // free
        case 5...14: return 300
        default:     return 800
        }
    }

    // MARK: - Init
    private init() {
        coins = UserDefaults.standard.integer(forKey: "economy_coins")
        let stored = UserDefaults.standard.array(forKey: "economy_unlockedPatterns") as? [Int] ?? []
        unlockedPatterns = Set(stored)
        // Free tier always available
        unlockedPatterns.formUnion(0...4)
    }

    // MARK: - Queries
    func isPatternUnlocked(_ rawValue: Int) -> Bool {
        rawValue <= 4 || unlockedPatterns.contains(rawValue)
    }

    // MARK: - Mutations
    func addCoins(_ amount: Int) {
        coins += amount
        UserDefaults.standard.set(coins, forKey: "economy_coins")
    }

    /// Returns false and does nothing if insufficient funds.
    @discardableResult
    func spendCoins(_ amount: Int) -> Bool {
        guard coins >= amount else { return false }
        coins -= amount
        UserDefaults.standard.set(coins, forKey: "economy_coins")
        return true
    }

    /// Unlocks a pattern by spending coins. Returns false if already unlocked or insufficient funds.
    @discardableResult
    func unlockPattern(_ rawValue: Int) -> Bool {
        guard !isPatternUnlocked(rawValue),
              let cost = PlayerEconomy.patternCost(rawValue: rawValue),
              spendCoins(cost) else { return false }
        unlockedPatterns.insert(rawValue)
        UserDefaults.standard.set(Array(unlockedPatterns), forKey: "economy_unlockedPatterns")
        objectWillChange.send()
        return true
    }

    // MARK: - Session helpers (called by GameScene)
    func resetSession() {
        sessionCoins = 0
    }

    func doubleSession() {
        sessionCoins *= 2
    }

    /// Commit session coins to persistent balance and reset session counter.
    func commitSession() {
        guard sessionCoins > 0 else { return }
        addCoins(sessionCoins)
        sessionCoins = 0
    }
}
