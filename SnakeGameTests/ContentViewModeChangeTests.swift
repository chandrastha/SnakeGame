import XCTest
@testable import SnakeGame

final class ContentViewModeChangeTests: XCTestCase {

    func test_givenOnlineModeDisabled_whenSwitchingToChallenge_thenShouldNotDisconnectPhoton() {
        XCTAssertFalse(ContentView.shouldDisconnectPhotonOnModeChange(mode: .challenge, isOnlineModeEnabled: false))
    }

    func test_givenOnlineModeEnabled_whenSwitchingToChallenge_thenShouldDisconnectPhoton() {
        XCTAssertTrue(ContentView.shouldDisconnectPhotonOnModeChange(mode: .challenge, isOnlineModeEnabled: true))
    }

    func test_givenOnlineModeEnabled_whenSwitchingToOnline_thenShouldNotDisconnectPhoton() {
        XCTAssertFalse(ContentView.shouldDisconnectPhotonOnModeChange(mode: .online, isOnlineModeEnabled: true))
    }
}
