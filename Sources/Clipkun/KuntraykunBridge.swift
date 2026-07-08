import AppKit
import OSLog

private let log = Logger(subsystem: "com.mtkg.clipkun", category: "kuntraykun")

/// kuntraykun（`com.mtkg.kuntraykun`）に「まとめられる」ための連携ブリッジ。
///
/// 仕様: kuntraykun リポジトリの `docs/kun-integration-protocol.md`（連携プロトコル v1）。
/// kuntraykun とは別アプリのため `KuntraykunCore` は import せず、通知名・キーをここに自前定義する
/// （プロトコルを変えるときは双方を一致させること）。
///
/// 役割:
/// - `sync` を観測し、自分が管理対象なら（かつ kuntraykun 起動中なら）自分のアイコンを隠す。
/// - `showMenu` を観測し、自分宛なら指定座標に自分のメニューを popUp する。
/// - 起動時に `appLaunched` を送り、kuntraykun から最新の `sync` を受け取る。
@MainActor
final class KuntraykunBridge {
    // MARK: プロトコル定数（kuntraykun 側と一致させる）
    /// kuntraykun 本体（本番／ローカル検証ビルドの両方を起動中判定の対象にする）。
    private static let kuntraykunBundleIDs = ["com.mtkg.kuntraykun", "com.mtkg.kuntraykun.local"]
    private static let syncName = Notification.Name("com.mtkg.kuntraykun.sync")
    private static let showMenuName = Notification.Name("com.mtkg.kuntraykun.showMenu")
    private static let appLaunchedName = Notification.Name("com.mtkg.kun.appLaunched")
    private static let updateStateName = Notification.Name("com.mtkg.kun.updateState")
    private static let requestMenuName = Notification.Name("com.mtkg.kuntraykun.requestMenu")
    private static let invokeMenuItemName = Notification.Name("com.mtkg.kuntraykun.invokeMenuItem")
    private static let managedDefaultsKey = "KuntraykunManaged"

    /// 自分のアイコンを隠す/戻すクロージャ（StatusBarController へ委譲）。
    private let setHidden: (Bool) -> Void
    /// 自分のメニューを指定座標に出すクロージャ（StatusBarController へ委譲）。
    private let popUpMenu: (NSPoint) -> Void
    /// メニュースナップショットを書き出すクロージャ（連携 v4、StatusBarController へ委譲）。
    private let exportMenu: () -> Void
    /// サブメニュー項目の実行クロージャ（連携 v4、項目 ID → 実行成否）。
    private let performMenuItem: (String) -> Bool

    /// `.local` を除いた自分の基底 bundle ID。
    private let myBundleID: String
    /// kuntraykun の管理対象に選ばれているか（UserDefaults に永続化）。
    private var isManaged: Bool
    /// 遅延表示（復活）の世代。再評価のたびに進めて保留中の復活をキャンセルする。
    private var showGeneration = 0
    /// 直近に kuntraykun へ報告したアップデート有無。sync 受信時に再送して整合させる。
    private var lastReportedUpdate = false
    /// `NSWorkspace.runningApplications` の KVO 監視トークン。
    private var runningAppsObservation: NSKeyValueObservation?

    init(setHidden: @escaping (Bool) -> Void,
         popUpMenu: @escaping (NSPoint) -> Void,
         exportMenu: @escaping () -> Void,
         performMenuItem: @escaping (String) -> Bool) {
        self.setHidden = setHidden
        self.popUpMenu = popUpMenu
        self.exportMenu = exportMenu
        self.performMenuItem = performMenuItem
        let raw = Bundle.main.bundleIdentifier ?? ""
        self.myBundleID = raw.hasSuffix(".local") ? String(raw.dropLast(".local".count)) : raw
        self.isManaged = UserDefaults.standard.bool(forKey: Self.managedDefaultsKey)
    }

    /// 観測を開始し、初期のアイコン表示を決め、起動を通知する。
    func start() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(onSync(_:)), name: Self.syncName, object: nil)
        dnc.addObserver(self, selector: #selector(onShowMenu(_:)), name: Self.showMenuName, object: nil)
        dnc.addObserver(self, selector: #selector(onRequestMenu(_:)), name: Self.requestMenuName, object: nil)
        dnc.addObserver(self, selector: #selector(onInvokeMenuItem(_:)), name: Self.invokeMenuItemName, object: nil)

        // kuntraykun の起動/終了でアイコン表示を再計算する。
        // LSUIElement（メニューバー常駐）アプリの起動/終了は NSWorkspace の didLaunch/didTerminate 通知が
        // 配信されないため、runningApplications を KVO 監視する（kuntraykun のクラッシュ時もアイコンが復活する）。
        // .initial で初回の表示判定も行う。
        runningAppsObservation = NSWorkspace.shared.observe(\.runningApplications, options: [.initial]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refreshVisibility() }
        }

        // 起動を通知（kuntraykun が最新 sync を返してくれる）。
        dnc.postNotificationName(
            Self.appLaunchedName, object: nil,
            userInfo: ["bundleID": myBundleID, "protocol": "1"],
            deliverImmediately: true
        )
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        runningAppsObservation?.invalidate()
    }

    // MARK: - 通知ハンドラ

    /// 対象集合の通知。自分が含まれるかで管理対象フラグを更新・永続化し、アイコン表示を再計算する。
    @objc private func onSync(_ note: Notification) {
        let managed = (note.userInfo?["managed"] as? String ?? "")
            .split(separator: ",").map(String.init)
        let nowManaged = managed.contains(myBundleID)
        if nowManaged != isManaged {
            isManaged = nowManaged
            UserDefaults.standard.set(nowManaged, forKey: Self.managedDefaultsKey)
            log.info("managed=\(nowManaged, privacy: .public)")
        }
        refreshVisibility()
        // 起動直後の kuntraykun にも現在のアップデート状態を伝える。
        reportUpdate(lastReportedUpdate)
    }

    /// 「アップデートあり/なし」を kuntraykun に報告する（更新検知時・解消時に呼ぶ）。
    func reportUpdate(_ hasUpdate: Bool) {
        lastReportedUpdate = hasUpdate
        DistributedNotificationCenter.default().postNotificationName(
            Self.updateStateName, object: nil,
            userInfo: ["bundleID": myBundleID, "hasUpdate": hasUpdate ? "1" : "0", "protocol": "1"],
            deliverImmediately: true
        )
    }

    /// メニュー表示依頼。自分宛なら指定スクリーン座標に自分のメニューを出す。
    @objc private func onShowMenu(_ note: Notification) {
        guard note.userInfo?["target"] as? String == myBundleID,
              let xs = note.userInfo?["x"] as? String, let x = Double(xs),
              let ys = note.userInfo?["y"] as? String, let y = Double(ys) else { return }
        popUpMenu(NSPoint(x: x, y: y))
    }

    /// メニュースナップショットの書き出し依頼（連携 v4）。targets に自分が含まれるときだけ応じる。
    @objc private func onRequestMenu(_ note: Notification) {
        let targets = (note.userInfo?["targets"] as? String ?? "")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard targets.contains(myBundleID) else { return }
        exportMenu()
    }

    /// サブメニュー項目の実行依頼（連携 v4）。世代が現行スナップショットと一致するときだけ実行する。
    /// 不一致（依頼が古い）なら実行せず、最新のスナップショットを書き出し直して知らせる。
    @objc private func onInvokeMenuItem(_ note: Notification) {
        guard note.userInfo?["target"] as? String == myBundleID,
              let itemID = note.userInfo?["itemID"] as? String else { return }
        let generation = note.userInfo?["generation"] as? String ?? ""
        guard generation == KuntraykunMenuExport.currentGeneration else {
            log.info("invoke ignored (stale generation); re-exporting menu")
            exportMenu()
            return
        }
        if !performMenuItem(itemID) {
            log.error("invoke failed: item \(itemID, privacy: .public) not found")
        }
        // 実行でメニュー内容（チェック状態や文言）が変わりうるので書き出し直す。
        // アクションの副作用（ウィンドウ表示等）が済んでから読むため、次のループに逃がす。
        DispatchQueue.main.async { [exportMenu] in exportMenu() }
    }

    /// アイコン表示規則: 隠す = (管理対象) かつ (kuntraykun 起動中)。
    /// kuntraykun が未起動なら隠さない（操作不能を防ぐフォールバック）。
    @objc private func refreshVisibility() {
        // NSRunningApplication.runningApplications(withBundleIdentifier:) は実行中でも空を返すことがあり
        // （誤判定でアイコンが再表示される）、KVO 対象の NSWorkspace.shared.runningApplications と
        // 同じソースで判定して整合させる。
        let hubRunning = NSWorkspace.shared.runningApplications.contains { app in
            guard let id = app.bundleIdentifier else { return false }
            return Self.kuntraykunBundleIDs.contains(id)
        }
        // 再評価のたびに世代を進め、保留中の遅延表示を無効化する。
        showGeneration &+= 1
        if !isManaged || hubRunning {
            // 管理対象でない→表示、管理対象かつ kuntraykun 起動中→隠す（いずれも即時）。
            setHidden(isManaged && hubRunning)
        } else {
            // 管理対象だが kuntraykun を検知できない。KVO の瞬間的なゆらぎで誤って復活し
            // アイコンが一瞬出てしまうのを防ぐため、少し待ってから復活する（待機中に再検知したらキャンセル）。
            let gen = showGeneration
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.showGeneration == gen else { return }
                    self.setHidden(false)
                }
            }
        }
    }
}
