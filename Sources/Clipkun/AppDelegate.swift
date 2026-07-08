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
    private var updateCheckTimer: Timer?
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

        // 画像行の OCR ボタン → 画像内テキストを認識してクリップボードへコピー。
        popup.onRecognizeText = { [weak self] item in
            self?.recognizeAndCopy(item)
        }

        applySettings(settings)

        statusBar = StatusBarController(
            openSettings: { [weak self] in self?.openSettings() },
            clearHistory: { [weak self] in self?.clearHistory() },
            checkForUpdate: { [weak self] in self?.startUpdateCheck(interactive: true) },
            quit: { NSApp.terminate(nil) }
        )

        // kuntraykun 連携: 管理対象なら自分のアイコンを隠し、showMenu でメニューを出す。
        // v4: メニュー構造を共有してサブメニュー表示・項目実行にも応じる。
        let bridge = KuntraykunBridge(
            setHidden: { [weak self] hidden in self?.statusBar?.setManagedHidden(hidden) },
            popUpMenu: { [weak self] point in self?.statusBar?.popUpMenu(at: point) },
            exportMenu: { [weak self] in self?.statusBar?.exportMenuSnapshot() },
            performMenuItem: { [weak self] id in self?.statusBar?.performMenuItem(id: id) ?? false }
        )
        bridge.start()
        kuntraykunBridge = bridge
        // 起動時に現在のメニュー構造を書き出しておく（kuntraykun 起動済みでもすぐサブメニューが出せる）。
        statusBar?.exportMenuSnapshot()

        startPruneTimer()
        startUpdateCheck(interactive: false)
        startUpdateTimer()

        // OCR モデルの初回ロードは数十秒かかることがあるため、起動時に温めておく。
        // 1秒以上かかる場合だけ HUD で準備中を知らせる（速い環境での一瞬の表示を避ける）。
        let hud = HUDPanelController()
        Task { @MainActor in
            let showHUD = Task { @MainActor in
                guard (try? await Task.sleep(nanoseconds: 1_000_000_000)) != nil else { return }
                hud.show(text: L.string("hud.ocr_warmup"))
            }
            await ImageTextRecognizer.warmUp()
            showHUD.cancel()
            hud.hide()
        }
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

    /// 画像履歴の中のテキストを OCR してクリップボードへコピーする。
    /// 自分の書き込みだが `ignoreCurrentChange()` は呼ばず、監視ポーリングに拾わせて
    /// OCR 結果をテキスト履歴としても残す。
    private func recognizeAndCopy(_ item: ClipItem) {
        guard let data = historyStore.imageData(for: item) else { return }
        Task { @MainActor in
            do {
                let text = try await ImageTextRecognizer.recognize(in: data)
                guard !text.isEmpty else {
                    showInfo(L.string("ocr.no_text"))
                    return
                }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                // テキスト履歴の選択時と同様に、前面アプリへ自動ペーストする。
                // パネルは OCR 開始前に閉じているが、フォーカス復帰の猶予は同じだけ取る。
                if AutoPaster.isTrusted(prompt: true) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        AutoPaster.paste()
                    }
                }
            } catch {
                log.error("text recognition failed: \(error.localizedDescription, privacy: .public)")
                showError(L.format("ocr.failed", error.localizedDescription))
            }
        }
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

    /// 定期サイレントチェック＋スリープ復帰チェックを開始する。
    /// 間隔は未認証 GitHub API のレート制限（60回/時）に十分余裕を持って1時間。
    /// `Timer` はスリープ中に発火しないため、`didWakeNotification` で復帰時にも即チェックする。
    private func startUpdateTimer() {
        let timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.startUpdateCheck(interactive: false)
            }
        }
        timer.tolerance = 360 // 省電力のためコアレッシングを許可（間隔の約10%）。
        updateCheckTimer = timer

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func systemDidWake() {
        startUpdateCheck(interactive: false)
    }

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
                // kuntraykun にもアップデート有無を伝える（集約バッジ/赤丸用）。
                kuntraykunBridge?.reportUpdate(isNewer)
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
