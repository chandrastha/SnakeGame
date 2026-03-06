import XCTest
@testable import SnakeGame

final class PhotonManagerTests: XCTestCase {

    // MARK: - Unit Tests: Seed Generation

    func test_givenCustomSeedConfig_whenGeneratingInitialFood_thenCountAndBoundsAreValid() {
        let seed = PhotonManager.initialRoomFoodSeed(count: 50, worldSize: 1000, padding: 60)

        XCTAssertEqual(seed.count, 50)

        var shieldCount = 0
        for i in 0..<50 {
            guard let slot = seed["\(i)"] else {
                XCTFail("Missing food slot \(i)")
                return
            }

            let x = (slot["x"] as? Float) ?? -1
            let y = (slot["y"] as? Float) ?? -1
            let type = (slot["type"] as? Int) ?? -1

            XCTAssertGreaterThanOrEqual(x, 60)
            XCTAssertLessThanOrEqual(x, 940)
            XCTAssertGreaterThanOrEqual(y, 60)
            XCTAssertLessThanOrEqual(y, 940)
            XCTAssertTrue((0...7).contains(type))

            if type == FoodType.shield.rawValue {
                shieldCount += 1
            }
        }

        XCTAssertLessThanOrEqual(shieldCount, 2)
    }
}
