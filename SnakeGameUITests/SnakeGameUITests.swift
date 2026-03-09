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
        XCTAssertTrue(app.buttons["modeCasual"].exists)
        XCTAssertTrue(app.buttons["modeExpert"].exists)
    }

    @MainActor
    func test_givenCasualMode_whenTappingPlay_thenTransitionsToGame() {
        app.buttons["modeCasual"].tap()
        let playButton = app.buttons["playButton"]
        playButton.tap()

        XCTAssertFalse(playButton.waitForExistence(timeout: 1), "PLAY button should disappear after game starts")
    }

    // MARK: - UI Tests: Interactive Controls + Accessibility IDs

    @MainActor
    func test_givenModeButtons_whenTogglingModes_thenControlsRemainInteractable() {
        let casual = app.buttons["modeCasual"]
        let expert = app.buttons["modeExpert"]

        casual.tap()
        XCTAssertTrue(casual.isHittable)

        expert.tap()
        XCTAssertTrue(expert.isHittable)
    }

    @MainActor
    func test_givenOfflineFirstBuild_whenViewingStartScreen_thenOnlineModeIsHidden() {
        XCTAssertFalse(app.buttons["modeOnline"].exists)
    }

    @MainActor
    func test_givenCasualMode_whenTappingPlay_thenOnlineMatchmakingIsNotPresented() {
        app.buttons["modeCasual"].tap()
        app.buttons["playButton"].tap()

        XCTAssertFalse(app.staticTexts["🌐  ONLINE"].waitForExistence(timeout: 1))
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
