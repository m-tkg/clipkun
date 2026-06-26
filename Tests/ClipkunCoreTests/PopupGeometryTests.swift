import XCTest
import CoreGraphics
@testable import ClipkunCore

final class PopupGeometryTests: XCTestCase {
    // 原点(0,0)・1440x900 の単一画面（メニューバー等は無視）。
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let panel = CGSize(width: 300, height: 400)

    func testPlacesBelowCursorByDefault() {
        let origin = PopupGeometry.origin(
            cursor: CGPoint(x: 500, y: 600),
            panelSize: panel,
            visibleFrame: screen,
            gap: 4
        )
        XCTAssertEqual(origin.x, 500)
        XCTAssertEqual(origin.y, 600 - 4 - 400) // 196
    }

    func testClampsRightEdge() {
        let origin = PopupGeometry.origin(
            cursor: CGPoint(x: 1400, y: 600),
            panelSize: panel,
            visibleFrame: screen
        )
        // 右辺が画面内に収まる: maxX(1440) - width(300) = 1140
        XCTAssertEqual(origin.x, 1140)
    }

    func testClampsLeftEdge() {
        let shifted = CGRect(x: 100, y: 0, width: 1440, height: 900)
        let origin = PopupGeometry.origin(
            cursor: CGPoint(x: 90, y: 600),
            panelSize: panel,
            visibleFrame: shifted
        )
        XCTAssertEqual(origin.x, 100)
    }

    func testFlipsAboveWhenNoRoomBelow() {
        // カーソルが下端付近 → 下に置けないので上側へ反転。
        let origin = PopupGeometry.origin(
            cursor: CGPoint(x: 500, y: 50),
            panelSize: panel,
            visibleFrame: screen,
            gap: 4
        )
        XCTAssertEqual(origin.y, 50 + 4) // カーソル上側
    }

    func testCentered() {
        let origin = PopupGeometry.centered(panelSize: panel, visibleFrame: screen)
        // (1440/2 - 300/2, 900/2 - 400/2) = (570, 250)
        XCTAssertEqual(origin.x, 570)
        XCTAssertEqual(origin.y, 250)
    }

    func testCenteredOnOffsetScreen() {
        let offset = CGRect(x: 100, y: 50, width: 1000, height: 800)
        let origin = PopupGeometry.centered(panelSize: panel, visibleFrame: offset)
        XCTAssertEqual(origin.x, 100 + 500 - 150) // 450
        XCTAssertEqual(origin.y, 50 + 400 - 200)  // 250
    }

    func testClampsTopEdgeWhenTooTall() {
        // 画面より高いパネルはどこにも収まらない → 上端にクランプ。
        let tall = CGSize(width: 300, height: 2000)
        let origin = PopupGeometry.origin(
            cursor: CGPoint(x: 500, y: 50),
            panelSize: tall,
            visibleFrame: screen
        )
        XCTAssertEqual(origin.y, screen.maxY - tall.height)
    }
}
