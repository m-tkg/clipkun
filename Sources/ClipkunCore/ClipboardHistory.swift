import Foundation

/// クリップボード履歴のコレクション（純粋値型）。`items[0]` が最新。
///
/// AppKit/ファイル I/O から独立した並べ替え・重複排除・件数上限のみを担う。
/// 実体ファイルの保存/削除は App 側（HistoryStore）が、ここが返す差分情報を見て行う。
public struct ClipboardHistory: Equatable {
    /// 先頭が最新の履歴配列。
    public private(set) var items: [ClipItem]

    public init(items: [ClipItem] = []) {
        self.items = items
    }

    /// `insert` の結果。App 側が実体ファイルの新規保存/再利用を判断するために使う。
    public enum InsertOutcome: Equatable {
        /// 新規に先頭へ追加した。
        case inserted
        /// 同一内容が既にあったため、その項目を先頭へ移動した（id を返す）。
        case movedToFront(UUID)
    }

    /// 新しい項目を先頭へ追加する。
    /// 同じ `contentHash` の項目が既にあれば、新規追加せず既存項目を先頭へ移動し
    /// `createdAt` を新項目の時刻へ更新する（= 最近使った順を維持し、実体の重複保存を避ける）。
    @discardableResult
    public mutating func insert(_ item: ClipItem) -> InsertOutcome {
        if let index = items.firstIndex(where: { $0.contentHash == item.contentHash }) {
            var existing = items.remove(at: index)
            existing.createdAt = item.createdAt
            items.insert(existing, at: 0)
            return .movedToFront(existing.id)
        }
        items.insert(item, at: 0)
        return .inserted
    }

    /// 指定 id の項目を先頭へ移動する。存在すれば true。
    @discardableResult
    public mutating func moveToFront(id: UUID, now: Date? = nil) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        var item = items.remove(at: index)
        if let now { item.createdAt = now }
        items.insert(item, at: 0)
        return true
    }

    /// 指定 id の項目を削除する。削除した項目（実体ファイルの後始末用）を返す。
    @discardableResult
    public mutating func remove(id: UUID) -> ClipItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: index)
    }

    /// すべて削除し、削除した項目（実体ファイルの後始末用）を返す。
    @discardableResult
    public mutating func clear() -> [ClipItem] {
        let removed = items
        items = []
        return removed
    }

    /// 件数を `max` 以下に保つよう、超過分（最古から）を取り除く。
    /// 取り除いた項目（実体ファイルの後始末用）を返す。`max` が 0 以下なら何もしない。
    @discardableResult
    public mutating func cap(max: Int) -> [ClipItem] {
        guard max > 0, items.count > max else { return [] }
        let evicted = Array(items[max...])
        items = Array(items[..<max])
        return evicted
    }
}
