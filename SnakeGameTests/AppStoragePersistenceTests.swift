import XCTest
import SwiftUI
@testable import SnakeGame

final class AppStoragePersistenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    private final class TestSettings {
        @AppStorage("bestScore", store: UserDefaults(suiteName: "placeholder")) var bestScore: Int = 0

        init(store: UserDefaults) {
            _bestScore = AppStorage(wrappedValue: 0, "bestScore", store: store)
        }
    }

    override func setUp() {
        super.setUp()
        suiteName = "AppStoragePersistenceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Unit Tests: @AppStorage / UserDefaults

    func test_givenInMemoryStore_whenSettingAppStorageValue_thenPersistsToThatStoreOnly() {
        let settings = TestSettings(store: defaults)

        settings.bestScore = 42

        XCTAssertEqual(defaults.integer(forKey: "bestScore"), 42)
        XCTAssertNotEqual(UserDefaults.standard.integer(forKey: "bestScore"), 42)
    }

    func test_givenExistingUserDefaultsHistory_whenProcessingLeaderboard_thenStoresTopEntries() {
        defaults.set([10, 70, 30], forKey: "scoreHistory")
        let existing = defaults.array(forKey: "scoreHistory") as? [Int] ?? []

        let updated = GameLogic.processLeaderboardEntry(score: 40, existing: existing)
        defaults.set(updated, forKey: "scoreHistory")

        XCTAssertEqual(defaults.array(forKey: "scoreHistory") as? [Int], [70, 40, 30, 10])
    }
}
