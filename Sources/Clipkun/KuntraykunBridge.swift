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
    private static let managedDefaultsKey = "KuntraykunManaged"

    /// 自分のアイコンを隠す/戻すクロージャ（StatusBarController へ委譲）。
    private let setHidden: (Bool) -> Void
    /// 自分のメニューを指定座標に出すクロージャ（StatusBarController へ委譲）。
    private let popUpMenu: (NSPoint) -> Void

    /// `.local` を除いた自分の基底 bundle ID。
    private let myBundleID: String
    /// kuntraykun の管理対象に選ばれているか（UserDefaults に永続化）。
    private var isManaged: Bool
    /// `NSWorkspace.runningApplications` の KVO 監視トークン。
    private var runningAppsObservation: NSKeyValueObservation?

    init(setHidden: @escaping (Bool) -> Void, popUpMenu: @escaping (NSPoint) -> Void) {
        self.setHidden = setHidden
        self.popUpMenu = popUpMenu
        let raw = Bundle.main.bundleIdentifier ?? ""
        self.myBundleID = raw.hasSuffix(".local") ? String(raw.dropLast(".local".count)) : raw
        self.isManaged = UserDefaults.standard.bool(forKey: Self.managedDefaultsKey)
    }

    /// 観測を開始し、初期のアイコン表示を決め、起動を通知する。
    func start() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(onSync(_:)), name: Self.syncName, object: nil)
        dnc.addObserver(self, selector: #selector(onShowMenu(_:)), name: Self.showMenuName, object: nil)

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
    }

    /// メニュー表示依頼。自分宛なら指定スクリーン座標に自分のメニューを出す。
    @objc private func onShowMenu(_ note: Notification) {
        guard note.userInfo?["target"] as? String == myBundleID,
              let xs = note.userInfo?["x"] as? String, let x = Double(xs),
              let ys = note.userInfo?["y"] as? String, let y = Double(ys) else { return }
        popUpMenu(NSPoint(x: x, y: y))
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
        setHidden(isManaged && hubRunning)
    }
}
