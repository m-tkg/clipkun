import XCTest
@testable import ClipkunCore

final class ClipFilterTests: XCTestCase {
    private func item(_ preview: String) -> ClipItem {
        ClipItem(
            kind: .text,
            createdAt: Date(timeIntervalSince1970: 0),
            contentHash: preview,
            preview: preview
        )
    }

    func testEmptyQueryReturnsAll() {
        let items = [item("apple"), item("banana")]
        XCTAssertEqual(filterClips(items, query: "").map(\.preview), ["apple", "banana"])
        // 空白だけのクエリも空とみなす。
        XCTAssertEqual(filterClips(items, query: "   ").map(\.preview), ["apple", "banana"])
    }

    func testPartialMatch() {
        let items = [item("apple pie"), item("banana"), item("pineapple")]
        XCTAssertEqual(filterClips(items, query: "apple").map(\.preview), ["apple pie", "pineapple"])
    }

    func testCaseInsensitive() {
        let items = [item("Hello World"), item("goodbye")]
        XCTAssertEqual(filterClips(items, query: "hello").map(\.preview), ["Hello World"])
        XCTAssertEqual(filterClips(items, query: "WORLD").map(\.preview), ["Hello World"])
    }

    func testTrimsSurroundingWhitespace() {
        let items = [item("apple"), item("banana")]
        XCTAssertEqual(filterClips(items, query: "  apple  ").map(\.preview), ["apple"])
    }

    func testNoMatchReturnsEmpty() {
        let items = [item("apple"), item("banana")]
        XCTAssertTrue(filterClips(items, query: "cherry").isEmpty)
    }
}
