import XCTest
@testable import ClipkunCore

final class RetentionPeriodTests: XCTestCase {
    func testDefaultIsOneDay() {
        let p = RetentionPeriod.default
        XCTAssertEqual(p.unit, .days)
        XCTAssertEqual(p.amount, 1)
        XCTAssertEqual(p.timeInterval, 86_400)
    }

    func testHoursClampLowerBound() {
        // 0 時間は不正 → 1 にクランプ。
        let p = RetentionPeriod(unit: .hours, amount: 0)
        XCTAssertEqual(p.amount, 1)
    }

    func testHoursClampUpperBound() {
        // 24 時間以上は 23 にクランプ（24 時間以上は「日」で表す）。
        let p = RetentionPeriod(unit: .hours, amount: 24)
        XCTAssertEqual(p.amount, 23)
    }

    func testDaysClampLowerBound() {
        let p = RetentionPeriod(unit: .days, amount: 0)
        XCTAssertEqual(p.amount, 1)
    }

    func testDaysClampUpperBound() {
        let p = RetentionPeriod(unit: .days, amount: 31)
        XCTAssertEqual(p.amount, 30)
    }

    func testTimeIntervalHours() {
        XCTAssertEqual(RetentionPeriod(unit: .hours, amount: 3).timeInterval, 3 * 3600)
    }

    func testTimeIntervalDays() {
        XCTAssertEqual(RetentionPeriod(unit: .days, amount: 2).timeInterval, 2 * 86_400)
    }

    func testCodableRoundTripAndClampOnDecode() throws {
        // 範囲外の値が書かれた JSON を読んでもクランプされる。
        let json = #"{"unit":"hours","amount":100}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RetentionPeriod.self, from: json)
        XCTAssertEqual(decoded.unit, .hours)
        XCTAssertEqual(decoded.amount, 23)
    }

    func testValidRange() {
        XCTAssertEqual(RetentionPeriod.validRange(for: .hours), 1...23)
        XCTAssertEqual(RetentionPeriod.validRange(for: .days), 1...30)
    }
}
