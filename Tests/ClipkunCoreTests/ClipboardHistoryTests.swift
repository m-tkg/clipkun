import XCTest
@testable import ClipkunCore

final class ClipboardHistoryTests: XCTestCase {
    private func item(hash: String, at seconds: TimeInterval) -> ClipItem {
        ClipItem(
            kind: .text,
            createdAt: Date(timeIntervalSince1970: seconds),
            contentHash: hash,
            preview: hash
        )
    }

    func testInsertPrependsNewest() {
        var history = ClipboardHistory()
        let outcome1 = history.insert(item(hash: "a", at: 1))
        let outcome2 = history.insert(item(hash: "b", at: 2))
        XCTAssertEqual(outcome1, .inserted)
        XCTAssertEqual(outcome2, .inserted)
        XCTAssertEqual(history.items.map(\.contentHash), ["b", "a"])
    }

    func testInsertDuplicateMovesToFrontAndUpdatesTime() {
        var history = ClipboardHistory()
        history.insert(item(hash: "a", at: 1))
        history.insert(item(hash: "b", at: 2))
        let firstAID = history.items.first(where: { $0.contentHash == "a" })!.id

        let outcome = history.insert(item(hash: "a", at: 10))
        XCTAssertEqual(outcome, .movedToFront(firstAID))
        // 重複は新規追加されず、既存項目が先頭へ。createdAt は新しい時刻に更新。
        XCTAssertEqual(history.items.map(\.contentHash), ["a", "b"])
        XCTAssertEqual(history.items.first?.createdAt, Date(timeIntervalSince1970: 10))
        XCTAssertEqual(history.items.first?.id, firstAID)
    }

    func testMoveToFront() {
        var history = ClipboardHistory()
        history.insert(item(hash: "a", at: 1))
        history.insert(item(hash: "b", at: 2))
        history.insert(item(hash: "c", at: 3))
        let aID = history.items.first(where: { $0.contentHash == "a" })!.id

        XCTAssertTrue(history.moveToFront(id: aID))
        XCTAssertEqual(history.items.map(\.contentHash), ["a", "c", "b"])
        XCTAssertFalse(history.moveToFront(id: UUID()))
    }

    func testRemove() {
        var history = ClipboardHistory()
        history.insert(item(hash: "a", at: 1))
        history.insert(item(hash: "b", at: 2))
        let bID = history.items.first(where: { $0.contentHash == "b" })!.id

        let removed = history.remove(id: bID)
        XCTAssertEqual(removed?.contentHash, "b")
        XCTAssertEqual(history.items.map(\.contentHash), ["a"])
        XCTAssertNil(history.remove(id: UUID()))
    }

    func testClear() {
        var history = ClipboardHistory()
        history.insert(item(hash: "a", at: 1))
        history.insert(item(hash: "b", at: 2))
        let removed = history.clear()
        XCTAssertEqual(Set(removed.map(\.contentHash)), ["a", "b"])
        XCTAssertTrue(history.items.isEmpty)
    }

    func testCapEvictsOldest() {
        var history = ClipboardHistory()
        for i in 1...5 { history.insert(item(hash: "\(i)", at: TimeInterval(i))) }
        // items = [5,4,3,2,1]
        let evicted = history.cap(max: 3)
        XCTAssertEqual(history.items.map(\.contentHash), ["5", "4", "3"])
        XCTAssertEqual(evicted.map(\.contentHash), ["2", "1"])
    }

    func testCapNoOpWhenWithinLimit() {
        var history = ClipboardHistory()
        history.insert(item(hash: "a", at: 1))
        XCTAssertTrue(history.cap(max: 3).isEmpty)
        XCTAssertEqual(history.items.count, 1)
        // max が 0 以下なら何もしない。
        XCTAssertTrue(history.cap(max: 0).isEmpty)
        XCTAssertEqual(history.items.count, 1)
    }
}
