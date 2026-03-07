import XCTest
import SwiftUI
@testable import SnakeGame

final class AppStoragePersistenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    private final class TestSettings {
        @AppStorage("bestScore.offline", store: UserDefaults(suiteName: "placeholder")) var bestScore: Int = 0

        init(store: UserDefaults) {
            _bestScore = AppStorage(wrappedValue: 0, GameMode.offline.bestScoreKey, store: store)
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

        XCTAssertEqual(defaults.integer(forKey: GameMode.offline.bestScoreKey), 42)
        XCTAssertNotEqual(UserDefaults.standard.integer(forKey: GameMode.offline.bestScoreKey), 42)
    }

    func test_givenModeSpecificScores_whenRecordingScore_thenStoresBestAndLeaderboardForThatModeOnly() {
        GameLogic.recordScore(40, for: .offline, defaults: defaults)
        GameLogic.recordScore(85, for: .challenge, defaults: defaults)
        GameLogic.recordScore(70, for: .offline, defaults: defaults)

        XCTAssertEqual(GameLogic.bestScore(for: .offline, defaults: defaults), 70)
        XCTAssertEqual(GameLogic.bestScore(for: .challenge, defaults: defaults), 85)
        XCTAssertEqual(GameLogic.leaderboardScores(for: .offline, defaults: defaults), [70, 40])
        XCTAssertEqual(GameLogic.leaderboardScores(for: .challenge, defaults: defaults), [85])
    }

    func test_givenLegacyGlobalScoreStorage_whenMigrating_thenMovesValuesIntoOfflineOnly() {
        defaults.set(55, forKey: GameLogic.legacyBestScoreKey)
        defaults.set([70, 40, 30], forKey: GameLogic.legacyScoreHistoryKey)

        GameLogic.migrateLegacyScoreStorageIfNeeded(defaults: defaults)

        XCTAssertEqual(defaults.integer(forKey: GameMode.offline.bestScoreKey), 55)
        XCTAssertEqual(defaults.array(forKey: GameMode.offline.leaderboardKey) as? [Int], [70, 40, 30])
        XCTAssertNil(defaults.object(forKey: GameMode.challenge.bestScoreKey))
        XCTAssertNil(defaults.array(forKey: GameMode.challenge.leaderboardKey))
    }

    func test_givenOfflineModeAlreadyStored_whenMigrating_thenDoesNotOverwriteExistingModeSpecificValues() {
        defaults.set(99, forKey: GameMode.offline.bestScoreKey)
        defaults.set([99, 88], forKey: GameMode.offline.leaderboardKey)
        defaults.set(12, forKey: GameLogic.legacyBestScoreKey)
        defaults.set([12], forKey: GameLogic.legacyScoreHistoryKey)

        GameLogic.migrateLegacyScoreStorageIfNeeded(defaults: defaults)

        XCTAssertEqual(defaults.integer(forKey: GameMode.offline.bestScoreKey), 99)
        XCTAssertEqual(defaults.array(forKey: GameMode.offline.leaderboardKey) as? [Int], [99, 88])
    }
}
