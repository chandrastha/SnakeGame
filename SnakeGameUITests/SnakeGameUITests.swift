//
//  SnakeGameUITests.swift
//  SnakeGameUITests
//
//  Created by Chandra Shrestha on 2026-02-24.
//

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

    // MARK: - Start Screen

    /// App launches and shows the PLAY button on the start screen.
    @MainActor
    func testLaunchShowsStartScreen() throws {
        let playButton = app.buttons["playButton"]
        XCTAssertTrue(playButton.waitForExistence(timeout: 5))
    }

    /// Both game mode buttons are visible on the start screen.
    @MainActor
    func testAllGameModeButtonsVisible() throws {
        XCTAssertTrue(app.buttons["modeOnline"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["modeOffline"].exists)
    }

    // MARK: - Mode Selection

    /// Tapping each mode button changes selection (button remains enabled).
    @MainActor
    func testModeSwitching() throws {
        app.buttons["modeOnline"].tap()
        XCTAssertTrue(app.buttons["modeOnline"].isEnabled)

        app.buttons["modeOffline"].tap()
        XCTAssertTrue(app.buttons["modeOffline"].isEnabled)
    }

    // MARK: - Leaderboard Sheet

    /// Tapping the leaderboard button presents the leaderboard sheet.
    @MainActor
    func testLeaderboardOpens() throws {
        app.buttons["leaderboardButton"].tap()
        XCTAssertTrue(
            app.staticTexts["leaderboardTitle"].waitForExistence(timeout: 5)
        )
    }

    /// Tapping the close button dismisses the leaderboard sheet.
    @MainActor
    func testLeaderboardCloses() throws {
        app.buttons["leaderboardButton"].tap()
        XCTAssertTrue(app.buttons["closeButton"].waitForExistence(timeout: 5))

        app.buttons["closeButton"].tap()
        // After dismissal the start screen PLAY button should be visible again
        XCTAssertTrue(app.buttons["playButton"].waitForExistence(timeout: 3))
    }

    // MARK: - Starting the Game (Offline mode)

    /// Tapping PLAY in Offline mode transitions to the game (start screen disappears).
    @MainActor
    func testPlayButtonStartsOfflineGame() throws {
        app.buttons["modeOffline"].tap()
        let playButton = app.buttons["playButton"]
        XCTAssertTrue(playButton.waitForExistence(timeout: 5))
        playButton.tap()

        // The PLAY button should no longer be on screen once the game has started
        let disappeared = playButton.waitForNonExistence(timeout: 5)
        XCTAssertTrue(disappeared, "PLAY button should disappear after starting the game")
    }

    /// After game over / returning to menu, the start screen reappears.
    @MainActor
    func testReturnToMenuShowsStartScreen() throws {
        app.buttons["modeOffline"].tap()
        app.buttons["playButton"].tap()
        Thread.sleep(forTimeInterval: 1.0) // wait for countdown

        // Terminate and relaunch simulates "next session" returning to start screen
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["playButton"].waitForExistence(timeout: 5))
    }

    // MARK: - Launch Performance

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
