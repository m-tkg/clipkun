import XCTest
@testable import ClipkunCore

final class RetentionPolicyTests: XCTestCase {
    private func item(_ id: String, ageSeconds: TimeInterval, now: Date) -> ClipItem {
        ClipItem(
            kind: .text,
            createdAt: now.addingTimeInterval(-ageSeconds),
            contentHash: id,
            preview: id
        )
    }

    func testKeepsItemsWithinPeriod() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let period = RetentionPeriod(unit: .hours, amount: 1) // 3600 秒
        let fresh = item("fresh", ageSeconds: 1800, now: now)
        let result = RetentionPolicy.prune([fresh], now: now, period: period)
        XCTAssertEqual(result.kept.map(\.contentHash), ["fresh"])
        XCTAssertTrue(result.expired.isEmpty)
    }

    func testExpiresItemsOlderThanPeriod() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let period = RetentionPeriod(unit: .hours, amount: 1)
        let old = item("old", ageSeconds: 3601, now: now)
        let result = RetentionPolicy.prune([old], now: now, period: period)
        XCTAssertTrue(result.kept.isEmpty)
        XCTAssertEqual(result.expired.map(\.contentHash), ["old"])
    }

    func testExactBoundaryIsKept() {
        // 経過がちょうど保持期間と等しい項目は保持する（境界を含む）。
        let now = Date(timeIntervalSince1970: 1_000_000)
        let period = RetentionPeriod(unit: .hours, amount: 1)
        let boundary = item("boundary", ageSeconds: 3600, now: now)
        let result = RetentionPolicy.prune([boundary], now: now, period: period)
        XCTAssertEqual(result.kept.map(\.contentHash), ["boundary"])
        XCTAssertTrue(result.expired.isEmpty)
    }

    func testMixedKeepsOrderOfKept() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let period = RetentionPeriod(unit: .days, amount: 1)
        let items = [
            item("a", ageSeconds: 100, now: now),
            item("b", ageSeconds: 90_000, now: now), // > 1 day → expired
            item("c", ageSeconds: 200, now: now),
        ]
        let result = RetentionPolicy.prune(items, now: now, period: period)
        XCTAssertEqual(result.kept.map(\.contentHash), ["a", "c"])
        XCTAssertEqual(result.expired.map(\.contentHash), ["b"])
    }
}
