import AppKit
import Carbon.HIToolbox
import ApplicationServices

/// 前面アプリへ ⌘V を合成送出して自動ペーストするヘルパー。
///
/// 合成キーの送出にはアクセシビリティ許可（システム設定 > プライバシーとセキュリティ >
/// アクセシビリティ）が必要。許可が無いと送出イベントは無視される。
@MainActor
enum AutoPaster {
    /// アクセシビリティ許可があるか。`prompt` が true で未許可なら、システムの許可ダイアログを出す。
    @discardableResult
    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// 前面アプリへ ⌘V を送る。
    /// 合成キーは HID 相当（`.cghidEventTap`）へ post する（IME 等にも確実に届く）。
    static func paste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let v = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false) else {
            return
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
