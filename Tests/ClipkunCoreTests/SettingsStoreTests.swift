import XCTest
@testable import ClipkunCore

final class SettingsStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("clipkun-test-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    func testLoadReturnsDefaultWhenMissing() {
        let store = SettingsStore(url: tempURL())
        XCTAssertEqual(store.load(), .default)
    }

    func testSaveThenLoadRoundTrip() throws {
        let url = tempURL()
        let store = SettingsStore(url: url)
        let settings = Settings(retention: RetentionPeriod(unit: .days, amount: 7), maxItemCount: 42)
        try store.save(settings)
        XCTAssertEqual(store.load(), settings)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    func testLoadReturnsDefaultWhenCorrupted() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "not json".data(using: .utf8)!.write(to: url)
        let store = SettingsStore(url: url)
        XCTAssertEqual(store.load(), .default)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
