import XCTest
import SpriteKit
@testable import SnakeGame

final class SnakeColorsTests: XCTestCase {

    // MARK: - Unit Tests: Models + Computed Properties

    func test_givenTheme_whenAccessingSwiftUIColor_thenColorExists() {
        let theme = snakeColorThemes[0]
        XCTAssertNotNil(theme.swiftUIColor)
        XCTAssertNotNil(theme.bodySwiftUIColor)
    }

    func test_givenThemeWithLowChannelValues_whenRequestingStrokeColor_thenChannelsAreClamped() {
        let theme = SnakeColorTheme(id: 99, name: "T", emoji: "T", headR: 0.05, headG: 0.04, headB: 0.03, bodyR: 0.02, bodyG: 0.01, bodyB: 0)
        let head = theme.headStrokeSKColor
        let body = theme.bodyStrokeSKColor

        XCTAssertGreaterThanOrEqual(head.cgColor.components?.first ?? -1, 0)
        XCTAssertGreaterThanOrEqual(body.cgColor.components?.first ?? -1, 0)
    }

    func test_givenAllPatterns_whenAccessingNameAndEmoji_thenValuesAreNonEmpty() {
        for pattern in SnakePattern.allCases {
            XCTAssertFalse(pattern.name.isEmpty)
            XCTAssertFalse(pattern.emoji.isEmpty)
        }
    }

    func test_givenExpandedSkinCatalog_whenInspectingCounts_thenIncludesSixteenThemesAndPatterns() {
        XCTAssertEqual(snakeColorThemes.count, 16)
        XCTAssertEqual(SnakePattern.allCases.count, 16)
    }

    func test_givenNegativeColorIndex_whenNormalizing_thenReturnsZero() {
        XCTAssertEqual(normalizedSnakeColorIndex(-5), 0)
    }

    func test_givenTooLargeColorIndex_whenNormalizing_thenReturnsLastThemeIndex() {
        XCTAssertEqual(normalizedSnakeColorIndex(999), snakeColorThemes.count - 1)
    }

}
