import XCTest
@testable import ClipkunCore

final class HotKeyConfigTests: XCTestCase {
    func testDisplayStringOrdersModifiersAppleStyle() {
        let hk = HotKeyConfig(
            keyCode: 9,
            carbonModifiers: HotKeyConfig.controlKey | HotKeyConfig.optionKey
                | HotKeyConfig.shiftKey | HotKeyConfig.cmdKey,
            keyLabel: "V"
        )
        XCTAssertEqual(hk.displayString, "⌃⌥⇧⌘V")
    }

    func testOptionOnly() {
        let hk = HotKeyConfig(keyCode: 9, carbonModifiers: HotKeyConfig.optionKey, keyLabel: "V")
        XCTAssertEqual(hk.displayString, "⌥V")
    }

    func testCodableRoundTrip() throws {
        let hk = HotKeyConfig.defaultPopup
        let data = try JSONEncoder().encode(hk)
        XCTAssertEqual(try JSONDecoder().decode(HotKeyConfig.self, from: data), hk)
    }

    func testDecodeFillsMissingKeys() throws {
        let json = #"{"keyLabel":"X"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(HotKeyConfig.self, from: json)
        XCTAssertEqual(decoded.keyLabel, "X")
        XCTAssertEqual(decoded.keyCode, HotKeyConfig().keyCode)
        XCTAssertEqual(decoded.carbonModifiers, HotKeyConfig().carbonModifiers)
    }
}
