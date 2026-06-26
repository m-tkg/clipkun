import AppKit
import ClipkunCore

/// 選択された履歴項目を `NSPasteboard.general` へ書き戻す（自動ペーストはしない）。
///
/// 書き戻すと最新のクリップボードになり、ユーザは任意のアプリで通常どおり貼り付けできる。
/// 実体データの解決は `HistoryStore` に委ねる。
@MainActor
struct ClipboardWriter {
    let store: HistoryStore
    private var pasteboard: NSPasteboard { .general }

    /// 指定項目をクリップボードへ書き戻す。書き込めたら true。
    @discardableResult
    func write(_ item: ClipItem) -> Bool {
        pasteboard.clearContents()
        switch item.kind {
        case .text:
            guard let text = store.fullText(for: item) else { return false }
            return pasteboard.setString(text, forType: .string)
        case .image:
            guard let data = store.imageData(for: item) else { return false }
            return pasteboard.setData(data, forType: .png)
        case .fileURLs:
            guard let urls = store.fileURLs(for: item), !urls.isEmpty else { return false }
            return pasteboard.writeObjects(urls as [NSURL])
        }
    }
}
