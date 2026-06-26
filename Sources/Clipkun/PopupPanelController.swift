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
        viewModel.backgroundOpacity = store.settings.popupBackgroundOpacity

        let panel = ensurePanel()
        // 再表示時に確実に最新の一覧を描画するため、ホスティングビューを作り直す。
        // （orderOut で隠した NSHostingView は再表示時に viewModel の変更を取りこぼし、
        //   前回のスナップショットを表示することがあるため。）
        rebuildContent(in: panel)

        let size = panelSize(for: viewModel.items.count)
        panel.setContentSize(size)
        positionPanel(panel, size: size)

        installMonitors()
        panel.makeKeyAndOrderFront(nil)
    }

    /// パネルのホスティングビューを作り直して、現在の `viewModel` を確実に描画させる。
    private func rebuildContent(in panel: PopupPanel) {
        let hosting = NSHostingView(rootView: PopupView(viewModel: viewModel))
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
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

    /// 設定に応じて配置する。カーソル位置（既定）はカーソルを含む画面の可視領域内へ収め、
    /// 画面中央指定時はカーソルを含む画面の中央へ置く。
    private func positionPanel(_ panel: NSPanel, size: NSSize) {
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(cursor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(origin: .zero, size: size)
        let origin: CGPoint
        switch store.settings.popupPosition {
        case .cursor:
            origin = PopupGeometry.origin(cursor: cursor, panelSize: size, visibleFrame: visible)
        case .screenCenter:
            origin = PopupGeometry.centered(panelSize: size, visibleFrame: visible)
        }
        panel.setFrameOrigin(origin)
    }

    // MARK: - 操作

    private func confirm(_ item: ClipItem) {
        // 先にパネルを閉じて前面アプリへフォーカスを戻してから選択処理を行う
        // （テキストの自動ペースト時、⌘V が前面アプリへ届くようにするため）。
        hide()
        onSelect?(item)
    }

    private func delete(_ item: ClipItem) {
        store.remove(id: item.id)
        viewModel.items = store.history.items
        if viewModel.items.isEmpty {
            hide()
            return
        }
        viewModel.selectedIndex = min(viewModel.selectedIndex, viewModel.items.count - 1)
        guard let panel else { return }
        // 一覧を確実に再描画するためホスティングビューを作り直し、上端を固定したままサイズ調整する。
        let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        rebuildContent(in: panel)
        panel.setContentSize(panelSize(for: viewModel.items.count))
        panel.setFrameTopLeftPoint(topLeft)
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
            // 端で止める（反対側へループしない）。
            if count > 0 { viewModel.selectViaKeyboard(min(viewModel.selectedIndex + 1, count - 1)) }
            return nil
        case kVK_UpArrow:
            if count > 0 { viewModel.selectViaKeyboard(max(viewModel.selectedIndex - 1, 0)) }
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
