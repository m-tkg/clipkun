import AppKit

/// 新版が利用可能なときにメニューバーアイコンの右下へ重ねる赤バッジ（小さな赤丸）。
///
/// ベースアイコンは `isTemplate = true`（明暗で自動着色）を保つため、色付きのバッジは
/// 画像へ焼き込まず、この独立した view（`CALayer`）をオーバーレイして表示/非表示を切り替える。
/// メニューバー背景に溶けないよう細い白の縁取りを付ける。
final class UpdateBadgeView: NSView {
    init(diameter: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        wantsLayer = true
        let layer = layer ?? CALayer()
        layer.backgroundColor = NSColor.systemRed.cgColor
        layer.cornerRadius = diameter / 2
        layer.borderWidth = 1
        layer.borderColor = NSColor.white.cgColor
        self.layer = layer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
