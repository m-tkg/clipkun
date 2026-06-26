import AppKit
import Carbon.HIToolbox
import ClipkunCore

/// `NSEvent`（設定 UI でのキー記録）を `HotKeyConfig`（Carbon 登録値）へ変換するヘルパー。
enum HotKeyTranslation {
    /// NSEvent の修飾フラグを Carbon の修飾フラグへ変換する。
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= HotKeyConfig.cmdKey }
        if flags.contains(.option) { m |= HotKeyConfig.optionKey }
        if flags.contains(.control) { m |= HotKeyConfig.controlKey }
        if flags.contains(.shift) { m |= HotKeyConfig.shiftKey }
        return m
    }

    /// keyDown イベントから `HotKeyConfig` を作る。修飾キーが1つも無い場合は nil（誤爆防止）。
    static func config(from event: NSEvent) -> HotKeyConfig? {
        let modifiers = carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else { return nil }
        return HotKeyConfig(
            keyCode: UInt32(event.keyCode),
            carbonModifiers: modifiers,
            keyLabel: keyLabel(for: event)
        )
    }

    /// 表示用のキーラベル。特殊キーは名前で、印字可能キーは大文字で表す。
    static func keyLabel(for event: NSEvent) -> String {
        if let special = specialKeyNames[Int(event.keyCode)] {
            return special
        }
        if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
            let trimmed = chars.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed.uppercased()
            }
        }
        return "Key\(event.keyCode)"
    }

    private static let specialKeyNames: [Int: String] = [
        kVK_Space: "Space",
        kVK_Return: "↩",
        kVK_Tab: "⇥",
        kVK_Escape: "⎋",
        kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←",
        kVK_RightArrow: "→",
        kVK_UpArrow: "↑",
        kVK_DownArrow: "↓",
        kVK_Home: "Home",
        kVK_End: "End",
        kVK_PageUp: "Page Up",
        kVK_PageDown: "Page Down",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}
