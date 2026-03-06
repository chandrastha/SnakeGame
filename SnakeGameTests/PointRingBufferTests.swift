import XCTest
import CoreGraphics
@testable import SnakeGame

final class PointRingBufferTests: XCTestCase {

    func test_givenCapacity_whenAppendingPastLimit_thenOverwritesOldestPoint() {
        var buffer = PointRingBuffer(capacity: 3)

        buffer.append(CGPoint(x: 1, y: 1))
        buffer.append(CGPoint(x: 2, y: 2))
        buffer.append(CGPoint(x: 3, y: 3))
        buffer.append(CGPoint(x: 4, y: 4))

        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer.pointsOldestToNewest(), [
            CGPoint(x: 2, y: 2),
            CGPoint(x: 3, y: 3),
            CGPoint(x: 4, y: 4)
        ])
    }

    func test_givenBuffer_whenIteratingNewestToOldest_thenTraversalOrderIsStable() {
        var buffer = PointRingBuffer(capacity: 4)
        for value in 1...4 {
            buffer.append(CGPoint(x: CGFloat(value), y: 0))
        }

        var values: [CGFloat] = []
        buffer.forEachNewestToOldest { point in
            values.append(point.x)
            return true
        }

        XCTAssertEqual(values, [4, 3, 2, 1])
    }

    func test_givenSmallerCapacity_whenResizing_thenRetainsNewestPoints() {
        var buffer = PointRingBuffer(capacity: 5)
        for value in 1...5 {
            buffer.append(CGPoint(x: CGFloat(value), y: CGFloat(value)))
        }

        buffer.setCapacity(3)

        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer.pointsOldestToNewest(), [
            CGPoint(x: 3, y: 3),
            CGPoint(x: 4, y: 4),
            CGPoint(x: 5, y: 5)
        ])
    }
}
