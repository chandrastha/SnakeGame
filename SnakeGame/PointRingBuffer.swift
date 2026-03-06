import CoreGraphics

struct PointRingBuffer {
    private var storage: [CGPoint]
    private var startIndex: Int = 0

    private(set) var count: Int = 0

    init(capacity: Int = 0) {
        storage = capacity > 0 ? Array(repeating: .zero, count: capacity) : []
    }

    var capacity: Int { storage.count }
    var isEmpty: Bool { count == 0 }

    var oldestPoint: CGPoint? {
        guard count > 0 else { return nil }
        return storage[startIndex]
    }

    var newestPoint: CGPoint? {
        guard count > 0, capacity > 0 else { return nil }
        return storage[physicalIndex(forLogicalIndex: count - 1)]
    }

    mutating func setCapacity(_ newCapacity: Int) {
        guard newCapacity != capacity else { return }
        guard newCapacity > 0 else {
            storage.removeAll()
            startIndex = 0
            count = 0
            return
        }

        let retainedCount = min(count, newCapacity)
        var newStorage = Array(repeating: CGPoint.zero, count: newCapacity)

        if retainedCount > 0 {
            let firstLogicalIndex = count - retainedCount
            for offset in 0..<retainedCount {
                newStorage[offset] = point(atLogicalIndex: firstLogicalIndex + offset)
            }
        }

        storage = newStorage
        startIndex = 0
        count = retainedCount
    }

    mutating func removeAll(keepingCapacity: Bool = true) {
        if keepingCapacity {
            startIndex = 0
            count = 0
        } else {
            storage.removeAll()
            startIndex = 0
            count = 0
        }
    }

    mutating func append(_ point: CGPoint) {
        guard capacity > 0 else { return }

        if count < capacity {
            storage[physicalIndex(forLogicalIndex: count)] = point
            count += 1
            return
        }

        storage[startIndex] = point
        startIndex = (startIndex + 1) % capacity
    }

    func pointsOldestToNewest() -> [CGPoint] {
        guard count > 0 else { return [] }
        var points: [CGPoint] = []
        points.reserveCapacity(count)
        forEachOldestToNewest { point in
            points.append(point)
            return true
        }
        return points
    }

    func forEachOldestToNewest(_ body: (CGPoint) -> Bool) {
        guard count > 0 else { return }
        for logicalIndex in 0..<count {
            if !body(point(atLogicalIndex: logicalIndex)) {
                break
            }
        }
    }

    func forEachNewestToOldest(_ body: (CGPoint) -> Bool) {
        guard count > 0 else { return }
        for logicalIndex in stride(from: count - 1, through: 0, by: -1) {
            if !body(point(atLogicalIndex: logicalIndex)) {
                break
            }
        }
    }

    private func point(atLogicalIndex logicalIndex: Int) -> CGPoint {
        storage[physicalIndex(forLogicalIndex: logicalIndex)]
    }

    private func physicalIndex(forLogicalIndex logicalIndex: Int) -> Int {
        guard capacity > 0 else { return 0 }
        return (startIndex + logicalIndex) % capacity
    }
}
