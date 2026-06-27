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
    /// パネルの中身を載せる土台（contentView）。
    private var contentContainer: NSView?
    /// 一覧の SwiftUI ホスト。検索/選択/削除のたびに作り直して確実に再描画する
    /// （この `.nonactivatingPanel` では SwiftUI のリアクティブ更新が画面に反映されないため）。
    private var listHost: NSHostingView<PopupView>?
    /// 検索フィールド（AppKit・常駐）。リストを作り直してもフォーカス/IME を保つため分離する。
    private var searchField: NSTextField?
    private var searchDelegate: SearchFieldDelegate?

    private var keyMonitor: Any?
    private var globalClickMonitor: Any?

    init(store: HistoryStore) {
        self.store = store
        viewModel.thumbnailProvider = { [weak store] item in store?.thumbnail(for: item) }
        viewModel.onConfirm = { [weak self] item in self?.confirm(item) }
        viewModel.onDelete = { [weak self] item in self?.delete(item) }
        viewModel.onClearAll = { [weak self] in self?.clearAll() }
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
        clearSearch()
        viewModel.items = store.history.items
        viewModel.selectedIndex = 0
        viewModel.backgroundOpacity = store.settings.popupBackgroundOpacity

        let panel = ensurePanel()
        let size = panelSize(for: viewModel.filteredItems.count)
        panel.setContentSize(size)
        positionPanel(panel, size: size)
        rebuildList()

        installMonitors()
        panel.makeKeyAndOrderFront(nil)
        focusSearchField()
    }

    /// 検索フィールドをパネルの first responder にする（キーになった後に呼ぶ）。
    /// `.nonactivatingPanel` でも、キーウィンドウであれば NSTextField の編集（IME 含む）が効く。
    /// レイアウト確定後に呼ぶため次の runloop に逃がす。
    private func focusSearchField() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, let field = self.searchField else { return }
            panel.makeFirstResponder(field)
        }
    }

    /// 検索文字をクリアする（viewModel と AppKit フィールド双方）。
    private func clearSearch() {
        viewModel.searchText = ""
        searchField?.stringValue = ""
    }

    /// パネルの中身を組み立てる。土台コンテナに「常駐の検索フィールド（AppKit）」と
    /// 「作り直し対象の一覧ホスト（SwiftUI）」を載せる。検索フィールドを最前面に保ち、
    /// その背面で一覧ホストを差し替えることで、フォーカス/IME を保ったまま一覧だけ再描画する。
    private func installContent(in panel: PopupPanel) {
        let container = NSView(frame: NSRect(origin: .zero, size: panelSize(for: 0)))
        container.autoresizesSubviews = true
        panel.contentView = container
        contentContainer = container

        let field = makeSearchField()
        layoutSearchField(field, in: container)
        // 上端に固定（下マージンを可変に）。リサイズ時も検索フィールドは最上部に留まる。
        field.autoresizingMask = [.width, .minYMargin]
        container.addSubview(field)
        searchField = field

        rebuildList()
    }

    /// 一覧ホストを作り直して、現在の `viewModel`（絞り込み・選択）を確実に描画する。
    /// 検索フィールドより背面へ入れて、フィールドは常駐のまま最前面に保つ。
    private func rebuildList() {
        guard let container = contentContainer else { return }
        listHost?.removeFromSuperview()
        let host = NSHostingView(rootView: PopupView(viewModel: viewModel))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        if let field = searchField {
            container.addSubview(host, positioned: .below, relativeTo: field)
        } else {
            container.addSubview(host)
        }
        listHost = host
    }

    private func makeSearchField() -> NSTextField {
        let field = NSTextField()
        field.placeholderString = L.string("popup.search.placeholder")
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        // 検索文字が変わったら同期的に反映＋リサイズする（描画フラッシュを同サイクルで起こすため）。
        let delegate = SearchFieldDelegate { [weak self] text in
            guard let self else { return }
            self.viewModel.searchText = text
            self.handleSearchChanged()
        }
        searchDelegate = delegate
        field.delegate = delegate
        return field
    }

    /// 検索フィールドを最上部の検索エリア内に縦中央で配置する。
    private func layoutSearchField(_ field: NSTextField, in container: NSView) {
        let fieldHeight: CGFloat = 22
        let topArea = PopupMetrics.searchFieldHeight
        let y = container.bounds.height - topArea + (topArea - fieldHeight) / 2
        field.frame = NSRect(x: 12, y: y, width: container.bounds.width - 24, height: fieldHeight)
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
        installContent(in: panel)
        self.panel = panel
        return panel
    }

    private func panelSize(for count: Int) -> NSSize {
        NSSize(width: PopupMetrics.width, height: PopupMetrics.totalHeight(for: count))
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
        if viewModel.filteredItems.isEmpty {
            hide()
            return
        }
        viewModel.selectedIndex = min(viewModel.selectedIndex, viewModel.filteredItems.count - 1)
        resizeKeepingTop()
        rebuildList()
    }

    /// 全履歴を削除して閉じる（一覧の右クリックメニュー）。
    private func clearAll() {
        store.clear()
        hide()
    }

    /// 検索文字の変化に応じて、選択を先頭へ戻し、パネルをリサイズして一覧を作り直す。
    private func handleSearchChanged() {
        guard let panel, panel.isVisible else { return }
        viewModel.selectedIndex = 0
        resizeKeepingTop()
        rebuildList()
    }

    /// パネルの上端を固定したまま、現在の絞り込み件数に合わせて高さを調整する。
    private func resizeKeepingTop() {
        guard let panel else { return }
        let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        panel.setContentSize(panelSize(for: viewModel.filteredItems.count))
        panel.setFrameTopLeftPoint(topLeft)
    }

    // MARK: - 入力監視

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            // handleKey が nil を返したら「消費」。self が nil のときだけ素通しする
            // （`?? event` だと消費の nil も素通しになり、↑↓ が検索フィールドのカーソルを動かす）。
            guard let self else { return event }
            return self.handleKey(event)
        }
        // 他アプリ上のクリックでキャンセル（パネル内クリックは SwiftUI が処理）。
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            self?.hide()
        }
    }

    /// 検索フィールドで IME 変換中（未確定の marked text がある）かを返す。
    private func isComposingIME() -> Bool {
        guard let editor = searchField?.currentEditor() as? NSTextView else { return false }
        return editor.hasMarkedText()
    }

    private func removeMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        keyMonitor = nil
        globalClickMonitor = nil
    }

    /// 取り込んだら nil（消費）、対象外なら event（素通し）を返す。
    /// ローカルモニタは first responder（検索フォーム）より先にイベントを見るため、ナビゲーション系
    /// （↑↓ / Enter / Esc / ⌘⌫）だけを消費し、文字キー・backspace・del 単独は素通しして
    /// 検索フォームの編集に使わせる。
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        // IME 変換中（marked text あり）は横取りせず入力メソッドに渡す。
        // Enter＝変換確定 / 矢印＝候補移動 / Esc＝変換取消 を一覧操作より優先する。
        if isComposingIME() { return event }

        let items = viewModel.filteredItems
        let count = items.count
        let keyCode = Int(event.keyCode)

        // ⌘⌫ / ⌘del で選択中の履歴を削除（backspace/del 単独は検索編集に使うため衝突を避ける）。
        if event.modifierFlags.contains(.command),
           keyCode == kVK_Delete || keyCode == kVK_ForwardDelete {
            if count > 0, items.indices.contains(viewModel.selectedIndex) {
                delete(items[viewModel.selectedIndex])
            }
            return nil
        }

        switch keyCode {
        case kVK_Escape:
            // 検索文字があれば 1 回目で検索クリア、空なら閉じる。
            if viewModel.searchText.isEmpty {
                hide()
            } else {
                clearSearch()
                handleSearchChanged()
            }
            return nil
        case kVK_DownArrow:
            // 端で止める（反対側へループしない）。
            if count > 0 {
                viewModel.selectedIndex = min(viewModel.selectedIndex + 1, count - 1)
                rebuildList()
            }
            return nil
        case kVK_UpArrow:
            if count > 0 {
                viewModel.selectedIndex = max(viewModel.selectedIndex - 1, 0)
                rebuildList()
            }
            return nil
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if count > 0, items.indices.contains(viewModel.selectedIndex) {
                confirm(items[viewModel.selectedIndex])
            }
            return nil
        default:
            return event
        }
    }
}

/// 検索 NSTextField の編集を受け取り、メインアクターのコールバックへ橋渡しする。
/// （`NSTextFieldDelegate` は `NSObject` を要求するため、@MainActor のコントローラ本体とは分離する。）
private final class SearchFieldDelegate: NSObject, NSTextFieldDelegate {
    private let onChange: @MainActor (String) -> Void
    init(onChange: @escaping @MainActor (String) -> Void) { self.onChange = onChange }
    func controlTextDidChange(_ note: Notification) {
        guard let field = note.object as? NSTextField else { return }
        let value = field.stringValue
        MainActor.assumeIsolated { onChange(value) }
    }
}
