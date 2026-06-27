import Foundation

/// `preview` を対象に、`query`（前後空白トリム・大文字小文字無視）でフィルタする純粋関数。
/// `query` が空（空白のみ含む）なら元の配列をそのまま返す。
public func filterClips(_ items: [ClipItem], query: String) -> [ClipItem] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return items }
    return items.filter { $0.preview.range(of: q, options: .caseInsensitive) != nil }
}
