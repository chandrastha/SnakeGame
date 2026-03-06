import XCTest
import UIKit
@testable import SnakeGame

final class AvatarStoreTests: XCTestCase {

    // MARK: - Unit Tests: Avatar Transform

    func test_givenRectangularImage_whenPreparingAvatar_thenReturnsSquareWithRequestedSize() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 300))
        let image = renderer.image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(origin: .zero, size: CGSize(width: 600, height: 300)))
        }

        let prepared = AvatarStore.preparedAvatar(from: image, pixelSize: 128)

        XCTAssertEqual(prepared?.size.width, 128)
        XCTAssertEqual(prepared?.size.height, 128)
    }

    func test_givenInvalidPixelSize_whenPreparingAvatar_thenReturnsNil() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { _ in }
        XCTAssertNil(AvatarStore.preparedAvatar(from: image, pixelSize: 0))
    }
}
