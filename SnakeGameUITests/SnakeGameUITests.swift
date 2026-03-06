import XCTest

final class SnakeGameUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    // MARK: - UI Tests: Major User Flows + Navigation

    @MainActor
    func test_givenFreshLaunch_whenViewingStartScreen_thenCoreControlsAreReachable() {
        XCTAssertTrue(app.buttons["playButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["modeOnline"].exists)
        XCTAssertTrue(app.buttons["modeOffline"].exists)
        XCTAssertTrue(app.buttons["leaderboardButton"].exists)
    }

    @MainActor
    func test_givenStartScreen_whenOpeningAndClosingLeaderboard_thenReturnsToStartScreen() {
        app.buttons["leaderboardButton"].tap()
        XCTAssertTrue(app.staticTexts["leaderboardTitle"].waitForExistence(timeout: 5))

        app.buttons["closeButton"].tap()
        XCTAssertTrue(app.buttons["playButton"].waitForExistence(timeout: 5))
    }

    @MainActor
    func test_givenOfflineMode_whenTappingPlay_thenTransitionsToGame() {
        app.buttons["modeOffline"].tap()
        let playButton = app.buttons["playButton"]
        playButton.tap()

        XCTAssertFalse(playButton.waitForExistence(timeout: 1), "PLAY button should disappear after game starts")
    }

    // MARK: - UI Tests: Interactive Controls + Accessibility IDs

    @MainActor
    func test_givenModeButtons_whenTogglingModes_thenControlsRemainInteractable() {
        let online = app.buttons["modeOnline"]
        let offline = app.buttons["modeOffline"]

        online.tap()
        XCTAssertTrue(online.isHittable)

        offline.tap()
        XCTAssertTrue(offline.isHittable)
    }

    @MainActor
    func test_givenLeaderboardWithoutScores_whenPresented_thenShowsEmptyStateMessage() {
        app.buttons["leaderboardButton"].tap()

        let emptyStateText = app.staticTexts["No scores yet.\nPlay a game to get started!"]
        XCTAssertTrue(emptyStateText.waitForExistence(timeout: 5))
    }

    // MARK: - UI Tests: Orientation

    @MainActor
    func test_givenPortraitAndLandscape_whenRotatingDevice_thenPlayButtonRemainsAccessible() {
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["playButton"].waitForExistence(timeout: 2))

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["playButton"].waitForExistence(timeout: 2))

        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: - Performance

    @MainActor
    func test_givenColdStart_whenLaunchingApp_thenLaunchPerformanceIsMeasured() {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
