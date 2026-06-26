import AppKit
import OSLog
import ClipkunCore

private let log = Logger(subsystem: "com.mtkg.clipkun", category: "app")

/// アプリ本体。設定の読込・反映、クリップボード監視・履歴保存・ポップアップ・
/// ステータスバー UI・設定ウィンドウ・アップデートの配線を担う。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SettingsStore(url: SettingsStore.defaultURL())

    private var settings = Settings.default
    private lazy var historyStore = HistoryStore(settings: settings)
    private let monitor = ClipboardMonitor()
    private let hotKey = HotKeyManager()
    private lazy var writer = ClipboardWriter(store: historyStore)
    private lazy var popup = PopupPanelController(store: historyStore)

    private var statusBar: StatusBarController?
    private var settingsWindowController: SettingsWindowController?
    private var pruneTimer: Timer?
    private var kuntraykunBridge: KuntraykunBridge?

    // 機能ごとの安定したホットキー ID。
    private enum HotKeyID {
        static let popup: UInt32 = 1
    }
    private var appliedPopupHotKey: HotKeyConfig?

    // アップデート関連。
    private let updateService = UpdateService()
    private lazy var selfUpdater = SelfUpdater(service: updateService)
    private var availableRelease: ReleaseInfo?

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = store.load()
        historyStore.settings = settings

        // クリップボード監視 → 履歴保存。
        monitor.onCapture = { [weak self] content in
            self?.historyStore.capture(content)
        }
        monitor.start()

        // ポップアップで選んだら最新クリップボードへ書き戻す。
        popup.onSelect = { [weak self] item in
            guard let self else { return }
            writer.write(item)
            // 自分の書き戻しを二重取り込みしないよう、直近の変更を観測済みにする。
            monitor.ignoreCurrentChange()
            historyStore.markUsed(id: item.id)
            // テキストに限り、クリップボードへ入れると同時に前面アプリへ自動ペーストする。
            if item.kind == .text, AutoPaster.isTrusted(prompt: true) {
                // パネルが閉じ前面アプリへフォーカスが戻るのを待ってから ⌘V を送る。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    AutoPaster.paste()
                }
            }
        }

        applySettings(settings)

        statusBar = StatusBarController(
            openSettings: { [weak self] in self?.openSettings() },
            clearHistory: { [weak self] in self?.clearHistory() },
            checkForUpdate: { [weak self] in self?.startUpdateCheck(interactive: true) },
            quit: { NSApp.terminate(nil) }
        )

        // kuntraykun 連携: 管理対象なら自分のアイコンを隠し、showMenu でメニューを出す。
        let bridge = KuntraykunBridge(
            setHidden: { [weak self] hidden in self?.statusBar?.setManagedHidden(hidden) },
            popUpMenu: { [weak self] point in self?.statusBar?.popUpMenu(at: point) }
        )
        bridge.start()
        kuntraykunBridge = bridge

        startPruneTimer()
        startUpdateCheck(interactive: false)
    }

    /// 設定を各所へ反映する。ホットキーは構成が変わったときだけ登録し直す。
    private func applySettings(_ settings: Settings) {
        historyStore.settings = settings

        if appliedPopupHotKey != settings.popupHotKey {
            hotKey.register(id: HotKeyID.popup, config: settings.popupHotKey) { [weak self] in
                guard let self else { return }
                // ポーリング間隔を待たずに直近のコピー（直前の Ctrl+Cmd+Shift+4 等）を取り込んでから表示する。
                self.monitor.captureNow()
                self.popup.toggle()
            }
            appliedPopupHotKey = settings.popupHotKey
        }
    }

    private func clearHistory() {
        historyStore.clear()
    }

    /// 期限切れ履歴を定期的に破棄する（ポップアップを開かなくても掃除する）。
    private func startPruneTimer() {
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.historyStore.pruneExpired(now: Date())
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pruneTimer = timer
    }

    private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                initialSettings: settings,
                onChange: { [weak self] newSettings in
                    guard let self else { return }
                    self.settings = newSettings
                    self.applySettings(newSettings)
                    try? self.store.save(newSettings)
                }
            )
        }
        settingsWindowController?.show()
    }

    // MARK: - アップデート

    private func startUpdateCheck(interactive: Bool) {
        Task { @MainActor in
            do {
                let release = try await updateService.fetchLatestRelease()
                let isNewer = VersionComparator.isNewer(
                    tag: release.tagName, than: UpdateService.currentVersion)
                if isNewer {
                    availableRelease = release
                    statusBar?.setUpdateAvailable(tag: release.tagName)
                } else {
                    availableRelease = nil
                    statusBar?.clearUpdateAvailable()
                }
                if interactive {
                    if isNewer {
                        promptInstall(release)
                    } else {
                        showInfo(L.format("update.latest", UpdateService.currentVersion))
                    }
                }
            } catch {
                log.error("update check failed: \(error.localizedDescription, privacy: .public)")
                if interactive {
                    showError(L.format("update.check_failed", error.localizedDescription))
                }
            }
        }
    }

    private func promptInstall(_ release: ReleaseInfo) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L.format("update.available.title", release.tagName)
        alert.informativeText = L.format("update.available.body", UpdateService.currentVersion)
        alert.addButton(withTitle: L.string("update.button.update"))
        alert.addButton(withTitle: L.string("update.button.open_release"))
        alert.addButton(withTitle: L.string("button.cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            performUpdate(release)
        case .alertSecondButtonReturn:
            if let url = URL(string: release.htmlUrl) { NSWorkspace.shared.open(url) }
        default:
            break
        }
    }

    private func performUpdate(_ release: ReleaseInfo) {
        Task { @MainActor in
            do {
                try await selfUpdater.performUpdate(to: release)
            } catch {
                log.error("self-update failed: \(error.localizedDescription, privacy: .public)")
                showError(L.format("update.failed", error.localizedDescription))
            }
        }
    }

    private func showInfo(_ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Clipkun"
        alert.informativeText = text
        alert.runModal()
    }

    private func showError(_ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L.string("alert.error.title")
        alert.informativeText = text
        alert.runModal()
    }
}
