import AppKit
import SwiftUI
import Carbon.HIToolbox
import ClipkunCore

/// 履歴ポップアップパネルの表示・操作を司る。
///
/// ホットキーでカーソル位置に `.nonactivatingPanel` を出し、カーソルキー/Enter/ESC と
/// 外側クリックを監視する。選択確定で `onSelect` を呼び、パネルを閉じる。
@MainActor
final class PopupPanelController {
    /// 行を選択確定したときに呼ばれる（書き戻しは AppDelegate が行う）。
    var onSelect: ((ClipItem) -> Void)?

    private let store: HistoryStore
    private let viewModel = PopupViewModel()
    private var panel: PopupPanel?

    private var keyMonitor: Any?
    private var globalClickMonitor: Any?

    init(store: HistoryStore) {
        self.store = store
        viewModel.thumbnailProvider = { [weak store] item in store?.thumbnail(for: item) }
        viewModel.onConfirm = { [weak self] item in self?.confirm(item) }
        viewModel.onDelete = { [weak self] item in self?.delete(item) }
    }

    /// 表示/非表示をトグルする（ホットキー押下時）。
    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    // MARK: - 表示

    private func show() {
        store.pruneExpired(now: Date())
        viewModel.items = store.history.items
        viewModel.selectedIndex = 0

        let panel = ensurePanel()
        let size = panelSize(for: viewModel.items.count)
        panel.setContentSize(size)
        positionPanel(panel, size: size)

        installMonitors()
        panel.makeKeyAndOrderFront(nil)
    }

    private func hide() {
        removeMonitors()
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> PopupPanel {
        if let panel { return panel }
        let panel = PopupPanel(
            contentRect: NSRect(origin: .zero, size: panelSize(for: 0)),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let hosting = NSHostingView(rootView: PopupView(viewModel: viewModel))
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        self.panel = panel
        return panel
    }

    private func panelSize(for count: Int) -> NSSize {
        let height = count == 0 ? 64 : PopupMetrics.height(for: count)
        return NSSize(width: PopupMetrics.width, height: height)
    }

    /// カーソルを含む画面の可視領域内に収まるよう原点を決めて配置する。
    private func positionPanel(_ panel: NSPanel, size: NSSize) {
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(origin: .zero, size: size)
        let origin = PopupGeometry.origin(
            cursor: cursor,
            panelSize: size,
            visibleFrame: visible
        )
        panel.setFrameOrigin(origin)
    }

    // MARK: - 操作

    private func confirm(_ item: ClipItem) {
        onSelect?(item)
        hide()
    }

    private func delete(_ item: ClipItem) {
        store.remove(id: item.id)
        viewModel.items = store.history.items
        if viewModel.items.isEmpty {
            hide()
            return
        }
        viewModel.selectedIndex = min(viewModel.selectedIndex, viewModel.items.count - 1)
        let size = panelSize(for: viewModel.items.count)
        if let panel {
            let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
            panel.setContentSize(size)
            panel.setFrameTopLeftPoint(topLeft)
        }
    }

    // MARK: - 入力監視

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKey(event) ?? event
        }
        // 他アプリ上のクリックでキャンセル（パネル内クリックは SwiftUI が処理）。
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.hide()
        }
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        keyMonitor = nil
        globalClickMonitor = nil
    }

    /// 取り込んだら nil（消費）、対象外なら event（素通し）を返す。
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        let count = viewModel.items.count
        switch Int(event.keyCode) {
        case kVK_Escape:
            hide()
            return nil
        case kVK_DownArrow:
            if count > 0 { viewModel.selectedIndex = (viewModel.selectedIndex + 1) % count }
            return nil
        case kVK_UpArrow:
            if count > 0 { viewModel.selectedIndex = (viewModel.selectedIndex - 1 + count) % count }
            return nil
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if count > 0, viewModel.items.indices.contains(viewModel.selectedIndex) {
                confirm(viewModel.items[viewModel.selectedIndex])
            }
            return nil
        default:
            return event
        }
    }
}
