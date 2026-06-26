import AppKit

/// `NSPasteboard.general` を一定間隔でポーリングし、変更を検知して取り込む。
///
/// NSPasteboard には変更通知 API が無いため、`changeCount` の差分監視で実現する。
/// `changeCount` の比較だけなら負荷は無視でき、変化したときだけ本体を読む。
/// 自分（`ClipboardWriter`）が書き戻したことによる変更は `ignoreCurrentChange()` で無視する。
@MainActor
final class ClipboardMonitor {
    /// ポーリング間隔（秒）。体感の追従性とアイドル負荷の妥協点。
    static let interval: TimeInterval = 0.5

    /// 新しい内容を取り込んだときに呼ばれる。
    var onCapture: ((CapturedContent) -> Void)?

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?

    init() {
        // 起動直後の現在内容は「変更」とみなさない（既存内容を取り込み直さない）。
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        // メニュー操作中なども止まらないよう common モードで回す。
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 現在の `changeCount` を「観測済み」にして、直近の変更を取り込み対象から外す。
    /// 履歴からの書き戻し直後に呼び、自分の書き込みを二重取り込みしないようにする。
    func ignoreCurrentChange() {
        lastChangeCount = pasteboard.changeCount
    }

    private func poll() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current
        if let content = CapturedContent.from(pasteboard: pasteboard) {
            onCapture?(content)
        }
    }
}
