import AppKit
import OSLog

private let log = Logger(subsystem: "com.mtkg.clipkun", category: "kuntraykun")

/// 自分のステータスメニューの構造を kuntraykun 用の共有場所に書き出す（連携プロトコル v4）。
///
/// kuntraykun は他プロセスの `NSMenu` を直接読めないため、メニュー構造を JSON で
/// `~/Library/Application Support/Kuntraykun/Menus/<基底bundleID>.json` へ原子的に書き出し、
/// `menuSnapshot` 分散通知で知らせる。kuntraykun はこれをサブメニューとして再構築し、
/// 項目クリックを `invokeMenuItem` で依頼してくる。
/// 仕様: kuntraykun リポジトリ `docs/kun-integration-protocol.md`（v4）。
@MainActor
enum KuntraykunMenuExport {
    /// kuntraykun 側の `sharedMenuDirRelativePath` と一致させる。
    private static let sharedDirRelativePath = "Kuntraykun/Menus"
    private static let menuSnapshotName = Notification.Name("com.mtkg.kun.menuSnapshot")

    /// 直近に書き出したスナップショットの世代。invokeMenuItem の世代確認に使う。
    private(set) static var currentGeneration = ""

    /// `.local` を除いた基底 bundle ID。
    private static var baseBundleID: String {
        let raw = Bundle.main.bundleIdentifier ?? ""
        return raw.hasSuffix(".local") ? String(raw.dropLast(".local".count)) : raw
    }

    private static var fileURL: URL? {
        guard let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            !baseBundleID.isEmpty else { return nil }
        return base
            .appendingPathComponent(sharedDirRelativePath, isDirectory: true)
            .appendingPathComponent("\(baseBundleID).json")
    }

    /// 現在のメニュー構造を書き出し、`menuSnapshot` を通知する。
    /// 起動時・メニュー内容が変わる箇所・requestMenu 受信時に呼ぶ。
    static func export(_ menu: NSMenu) {
        guard let fileURL else { return }
        menu.update() // enabled 状態を確定させてから読む。
        let generation = UUID().uuidString
        let snapshot = Snapshot(generation: generation, items: nodes(of: menu, path: []))
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(snapshot)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            // 原子的書き込み → 通知の順序（読み手が中途半端な内容を見ないため）。
            try data.write(to: fileURL, options: .atomic)
        } catch {
            log.error("menu snapshot export failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        currentGeneration = generation
        DistributedNotificationCenter.default().postNotificationName(
            menuSnapshotName, object: nil,
            userInfo: ["bundleID": baseBundleID, "generation": generation, "protocol": "1"],
            deliverImmediately: true
        )
    }

    /// インデックスパス ID（例 `"3"` / `"3.1"`）の項目を実行する。見つからなければ false。
    static func performItem(id: String, in menu: NSMenu) -> Bool {
        guard let path = parseIndexPath(id), !path.isEmpty else { return false }
        var current = menu
        for index in path.dropLast() {
            guard index < current.numberOfItems,
                  let submenu = current.item(at: index)?.submenu else { return false }
            current = submenu
        }
        let last = path[path.count - 1]
        guard last < current.numberOfItems else { return false }
        current.performActionForItem(at: last)
        return true
    }

    // MARK: - private

    /// メニューを歩いて JSON ノード列にする。ID は実際の NSMenu 内インデックスのパス
    /// （非表示項目はスキップするが、ID の採番は実インデックスのまま。invoke 時にそのまま辿れる）。
    private static func nodes(of menu: NSMenu, path: [Int]) -> [Node] {
        var result: [Node] = []
        for (index, item) in menu.items.enumerated() {
            if item.isHidden { continue }
            let itemPath = path + [index]
            let id = itemPath.map(String.init).joined(separator: ".")
            if item.isSeparatorItem {
                result.append(Node(id: id, title: "", enabled: false, state: "off",
                                   separator: true, children: []))
                continue
            }
            let children = item.submenu.map { nodes(of: $0, path: itemPath) } ?? []
            result.append(Node(
                id: id,
                title: item.title,
                enabled: item.isEnabled,
                state: state(of: item),
                separator: false,
                children: children
            ))
        }
        return result
    }

    private static func state(of item: NSMenuItem) -> String {
        switch item.state {
        case .on: return "on"
        case .mixed: return "mixed"
        default: return "off"
        }
    }

    private static func parseIndexPath(_ id: String) -> [Int]? {
        guard !id.isEmpty else { return nil }
        var path: [Int] = []
        for part in id.split(separator: ".", omittingEmptySubsequences: false) {
            guard let index = Int(part), index >= 0 else { return nil }
            path.append(index)
        }
        return path
    }

    private struct Snapshot: Encodable {
        var formatVersion = 1
        let generation: String
        let items: [Node]
    }

    private struct Node: Encodable {
        let id: String
        let title: String
        let enabled: Bool
        let state: String
        let separator: Bool
        let children: [Node]
    }
}
