import AppKit
import Carbon.HIToolbox
import OSLog
import ClipkunCore

private let log = Logger(subsystem: "com.mtkg.clipkun", category: "hotkey")

/// Carbon `RegisterEventHotKey` を使ったグローバルホットキー管理。
///
/// CGEventTap と違い**アクセシビリティ権限が不要**で、押下イベントだけを受け取れる。
/// 機能ごとに安定した ID で登録し、押下時は `EventHotKeyID` を見て該当アクションへ振り分ける。
@MainActor
final class HotKeyManager {
    private struct Entry {
        var ref: EventHotKeyRef?
        var action: () -> Void
    }

    private var entries: [UInt32: Entry] = [:]
    private var handlerRef: EventHandlerRef?
    private let signature: OSType = 0x434C_5021 // 'CLP!'

    /// 指定 ID のホットキーを（あれば置き換えて）登録する。
    func register(id: UInt32, config: HotKeyConfig, action: @escaping () -> Void) {
        unregister(id: id)
        installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(
            config.keyCode,
            config.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            entries[id] = Entry(ref: ref, action: action)
            log.info("hotkey \(id) registered: \(config.displayString, privacy: .public)")
        } else {
            log.error("RegisterEventHotKey failed for id \(id): \(status)")
        }
    }

    /// 指定 ID の登録を解除する（イベントハンドラは常駐させたままにする）。
    func unregister(id: UInt32) {
        if let entry = entries[id], let ref = entry.ref {
            UnregisterEventHotKey(ref)
        }
        entries[id] = nil
    }

    fileprivate func handle(id: UInt32) {
        entries[id]?.action()
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData, let event else { return noErr }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                let id = hotKeyID.id
                MainActor.assumeIsolated { manager.handle(id: id) }
                return noErr
            },
            1,
            &spec,
            selfPtr,
            &handlerRef
        )
    }
}
