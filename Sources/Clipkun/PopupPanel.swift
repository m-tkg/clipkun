import AppKit

/// 履歴ポップアップ用の `NSPanel`。
///
/// `.nonactivatingPanel` でアプリ全体を `.accessory` のまま前面化せずに表示しつつ、
/// `canBecomeKey` を true にしてカーソルキー/ESC/クリックを受け取れるようにする。
/// これにより前面アプリのフォーカス文脈（書き戻し先のテキスト欄など）を壊さない。
final class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
