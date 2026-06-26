import XCTest
@testable import ClipkunCore

final class SettingsTests: XCTestCase {
    func testDefaults() {
        let s = Settings.default
        XCTAssertEqual(s.popupHotKey, .defaultPopup)
        XCTAssertEqual(s.retention, .default)
        XCTAssertEqual(s.maxItemCount, 200)
    }

    func testMaxItemCountClamp() {
        XCTAssertEqual(Settings(maxItemCount: 1).maxItemCount, 10)
        XCTAssertEqual(Settings(maxItemCount: 5000).maxItemCount, 1000)
    }

    func testDecodeFillsMissingKeysWithDefaults() throws {
        // 空 JSON でも既定で補完される（前方/後方互換）。
        let json = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Settings.self, from: json)
        XCTAssertEqual(decoded, .default)
    }

    func testDecodePartialKeys() throws {
        let json = #"{"maxItemCount":50}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Settings.self, from: json)
        XCTAssertEqual(decoded.maxItemCount, 50)
        XCTAssertEqual(decoded.retention, .default)
        XCTAssertEqual(decoded.popupHotKey, .defaultPopup)
    }

    func testEncodeDecodeRoundTrip() throws {
        let original = Settings(
            popupHotKey: HotKeyConfig(keyCode: 9, carbonModifiers: HotKeyConfig.optionKey, keyLabel: "V"),
            retention: RetentionPeriod(unit: .hours, amount: 5),
            maxItemCount: 123
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testDefaultPopupHotKeyIsOptionV() {
        let hk = HotKeyConfig.defaultPopup
        XCTAssertEqual(hk.keyCode, 9)
        XCTAssertEqual(hk.carbonModifiers, HotKeyConfig.optionKey)
        XCTAssertEqual(hk.displayString, "⌥V")
    }
}
