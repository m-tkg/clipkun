import AppKit

/// メニューバー常駐アイコンとメニューを管理する。
/// 設定項目自体は設定ダイアログに集約し、メニューは入口だけを提供する。
@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    /// ステータスメニュー本体。kuntraykun 連携時はこのメニューを指定座標へ popUp する。
    private let menu = NSMenu()

    private let openSettings: () -> Void
    private let clearHistory: () -> Void
    private let checkForUpdate: () -> Void
    private let quitApp: () -> Void
    private var updateItem: NSMenuItem!
    /// 新版ありを示す赤バッジ（アイコン右下にオーバーレイ）。
    private var badgeView: NSView?

    private static var checkUpdateTitle: String { L.string("menu.check_update") }

    /// ローカル検証ビルド（バンドルID が `.local` で終わる）かどうか。
    private var isLocalBuild: Bool {
        (Bundle.main.bundleIdentifier ?? "").hasSuffix(".local")
    }

    init(
        openSettings: @escaping () -> Void,
        clearHistory: @escaping () -> Void,
        checkForUpdate: @escaping () -> Void,
        quit: @escaping () -> Void
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.openSettings = openSettings
        self.clearHistory = clearHistory
        self.checkForUpdate = checkForUpdate
        self.quitApp = quit
        super.init()

        if let button = statusItem.button {
            if let template = Self.menuBarImage() {
                button.image = template
            } else if let symbol = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipkun") {
                symbol.isTemplate = true
                button.image = symbol
            } else {
                button.title = "📋"
            }
            if isLocalBuild {
                button.title = " " + L.string("menu_bar.local")
                button.imagePosition = .imageLeading
            }
            installBadge(on: button)
        }
        // kuntraykun 一覧用に、現在のメニューバーアイコンを共有場所へ書き出す（連携 v2）。
        KuntraykunIconExport.export(statusItem.button?.image)

        // 先頭にバージョン情報（操作不可）。ローカルビルドは併記する。
        var versionTitle = L.format("menu.version", UpdateService.currentVersion)
        if isLocalBuild { versionTitle += " (" + L.string("menu_bar.local") + ")" }
        let versionItem = NSMenuItem(title: versionTitle, action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(.separator())
        menu.addItem(menuItem(title: L.string("menu.settings"), action: #selector(handleOpenSettings), key: ","))
        menu.addItem(menuItem(title: L.string("menu.clear_history"), action: #selector(handleClearHistory), key: ""))
        updateItem = menuItem(title: Self.checkUpdateTitle, action: #selector(handleCheckForUpdate), key: "")
        menu.addItem(updateItem)
        menu.addItem(.separator())
        menu.addItem(menuItem(title: L.string("menu.quit"), action: #selector(handleQuit), key: "q"))
        statusItem.menu = menu
    }

    func setUpdateAvailable(tag: String) {
        updateItem.title = L.format("menu.install_update", tag)
        badgeView?.isHidden = false
        // メニュー文言が変わったので kuntraykun 用スナップショットを書き出し直す（連携 v4）。
        exportMenuSnapshot()
    }

    func clearUpdateAvailable() {
        updateItem.title = Self.checkUpdateTitle
        badgeView?.isHidden = true
        exportMenuSnapshot()
    }

    /// 赤バッジをアイコン右下へオーバーレイする。位置はアイコン画像の幅基準で固定し、
    /// 「ローカル」テキスト併記時（imagePosition = .imageLeading）でも常にアイコングリフの右下に乗せる。
    private func installBadge(on button: NSStatusBarButton) {
        let size: CGFloat = 8
        let iconWidth = button.image?.size.width ?? 18
        let badge = UpdateBadgeView(diameter: size)
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.isHidden = true
        button.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: size),
            badge.heightAnchor.constraint(equalToConstant: size),
            badge.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: iconWidth - size),
            badge.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
        badgeView = badge
    }

    // MARK: - kuntraykun 連携

    /// kuntraykun に集約されている間、自分のメニューバーアイコンを隠す/戻す。
    /// `NSStatusItem` 自体は破棄せず保持し、`popUpMenu(at:)` で使い回す。
    func setManagedHidden(_ hidden: Bool) {
        statusItem.isVisible = !hidden
    }

    /// 自分のステータスメニューを指定スクリーン座標（左下原点）に表示する。
    /// kuntraykun からの showMenu 依頼で、kuntraykun アイコン直下に出すために使う。
    func popUpMenu(at point: NSPoint) {
        menu.popUp(positioning: nil, at: point, in: nil)
    }

    /// メニュー構造を kuntraykun 用の共有場所へ書き出す（連携 v4）。
    /// 起動時・requestMenu 受信時・メニュー内容が変わる箇所から呼ぶ。
    func exportMenuSnapshot() {
        KuntraykunMenuExport.export(menu)
    }

    /// kuntraykun のサブメニューでクリックされた項目（インデックスパス ID）を実行する（連携 v4）。
    func performMenuItem(id: String) -> Bool {
        KuntraykunMenuExport.performItem(id: id, in: menu)
    }

    private func menuItem(title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func handleOpenSettings() { openSettings() }
    @objc private func handleClearHistory() { clearHistory() }
    @objc private func handleCheckForUpdate() { checkForUpdate() }
    @objc private func handleQuit() { quitApp() }

    /// メニューバー用のテンプレート（モノクロ）画像を返す。見つからなければ nil。
    private static func menuBarImage() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        let height: CGFloat = 18
        let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1
        image.size = NSSize(width: height * aspect, height: height)
        image.isTemplate = true
        return image
    }
}
