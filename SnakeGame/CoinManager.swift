import Foundation
import Combine

class CoinManager: ObservableObject {
    static let shared = CoinManager()
    private init() {}

    // Coin balance — backed by UserDefaults
    @Published var balance: Int = UserDefaults.standard.integer(forKey: "coinBalance") {
        didSet { UserDefaults.standard.set(balance, forKey: "coinBalance") }
    }

    // Unlocked sets stored as comma-separated index strings e.g. "0,1,2"
    private(set) var unlockedColors: Set<Int> = {
        let raw = UserDefaults.standard.string(forKey: "unlockedColorIndices") ?? "0,1,2"
        return Set(raw.split(separator: ",").compactMap { Int($0) })
    }()

    private(set) var unlockedPatterns: Set<Int> = {
        let raw = UserDefaults.standard.string(forKey: "unlockedPatternIndices") ?? "0,1"
        return Set(raw.split(separator: ",").compactMap { Int($0) })
    }()

    // Purchase costs
    static let colorCost = 100
    static let patternCost = 75
    static let reviveCost = 50

    // Items always free without purchase
    static let freeColorIndices: Set<Int>   = [0, 1, 2]   // Forest, Ocean, Fire
    static let freePatternIndices: Set<Int> = [0, 1]       // Solid, Striped

    // MARK: - Queries

    func isUnlocked(colorIndex: Int) -> Bool {
        Self.freeColorIndices.contains(colorIndex) || unlockedColors.contains(colorIndex)
    }

    func isUnlocked(patternIndex: Int) -> Bool {
        Self.freePatternIndices.contains(patternIndex) || unlockedPatterns.contains(patternIndex)
    }

    // MARK: - Transactions

    func earn(_ coins: Int) {
        balance += coins
    }

    /// Deducts coins if balance is sufficient. Returns false if not enough coins.
    @discardableResult
    func spend(_ coins: Int) -> Bool {
        guard balance >= coins else { return false }
        balance -= coins
        return true
    }

    /// Unlocks a color skin by index. Returns false if already owned or insufficient coins.
    @discardableResult
    func unlock(colorIndex: Int) -> Bool {
        guard !isUnlocked(colorIndex: colorIndex), spend(Self.colorCost) else { return false }
        unlockedColors.insert(colorIndex)
        saveUnlockedColors()
        objectWillChange.send()
        return true
    }

    /// Unlocks a pattern by index. Returns false if already owned or insufficient coins.
    @discardableResult
    func unlock(patternIndex: Int) -> Bool {
        guard !isUnlocked(patternIndex: patternIndex), spend(Self.patternCost) else { return false }
        unlockedPatterns.insert(patternIndex)
        saveUnlockedPatterns()
        objectWillChange.send()
        return true
    }

    // MARK: - Persistence

    private func saveUnlockedColors() {
        let str = unlockedColors.map(String.init).joined(separator: ",")
        UserDefaults.standard.set(str, forKey: "unlockedColorIndices")
    }

    private func saveUnlockedPatterns() {
        let str = unlockedPatterns.map(String.init).joined(separator: ",")
        UserDefaults.standard.set(str, forKey: "unlockedPatternIndices")
    }
}
