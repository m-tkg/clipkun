import SwiftUI
import AppKit
import Carbon.HIToolbox
import ClipkunCore

/// ホットキーを記録するボタン。押下後に次のキー入力（修飾キー必須）を取り込む。
struct HotKeyRecorderView: View {
    @SwiftUI.Binding var config: HotKeyConfig
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggle) {
            Text(isRecording ? L.string("hotkey.recording") : config.displayString)
                .frame(minWidth: 120)
        }
        .onDisappear(perform: stop)
    }

    private func toggle() {
        if isRecording { stop() } else { start() }
    }

    private func start() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Esc（修飾なし）で記録をキャンセル。
            if event.keyCode == UInt16(kVK_Escape),
               event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                stop()
                return nil
            }
            // 修飾キーが付いていれば確定。無ければ記録継続（誤爆防止）。
            if let newConfig = HotKeyTranslation.config(from: event) {
                config = newConfig
                stop()
            }
            return nil // 記録中はイベントを消費する。
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }
}
