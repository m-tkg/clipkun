import CoreGraphics

/// ポップアップパネルの配置を計算する純粋関数。
///
/// AppKit に依存しないよう `CGPoint`/`CGSize`/`CGRect` のみで扱う。
/// 座標系は Cocoa グローバル座標（原点は左下、y は上向き）を想定する。
public enum PopupGeometry {
    /// カーソル位置を起点にパネルを置くための原点（左下）を返す。
    ///
    /// 既定ではカーソルの少し下にパネルの左上が来るよう配置し、画面（`visibleFrame`）から
    /// はみ出す場合は内側へクランプする。複数ディスプレイでは、カーソルを含む画面の
    /// `visibleFrame` を呼び出し側が渡す前提。
    /// - Parameters:
    ///   - cursor: カーソル位置（Cocoa グローバル座標）。
    ///   - panelSize: パネルの大きさ。
    ///   - visibleFrame: 配置先画面の可視領域（メニューバー/Dock を除く）。
    ///   - gap: カーソルとパネル上端の隙間（既定 4pt）。
    public static func origin(
        cursor: CGPoint,
        panelSize: CGSize,
        visibleFrame: CGRect,
        gap: CGFloat = 4
    ) -> CGPoint {
        // 既定の配置: カーソルの少し下にパネルの左上角を合わせる。
        var x = cursor.x
        var y = cursor.y - gap - panelSize.height

        // 右端はみ出し: 右辺を可視領域内へ収める。
        if x + panelSize.width > visibleFrame.maxX {
            x = visibleFrame.maxX - panelSize.width
        }
        // 左端はみ出し。
        if x < visibleFrame.minX {
            x = visibleFrame.minX
        }
        // 下端はみ出し: 下に置けない場合はカーソルの上側へ反転する。
        if y < visibleFrame.minY {
            let above = cursor.y + gap
            if above + panelSize.height <= visibleFrame.maxY {
                y = above
            } else {
                // 上にも収まらなければ可視領域内へクランプ。
                y = visibleFrame.minY
            }
        }
        // 上端はみ出し。
        if y + panelSize.height > visibleFrame.maxY {
            y = visibleFrame.maxY - panelSize.height
        }
        return CGPoint(x: x, y: y)
    }

    /// 画面（`visibleFrame`）の中央にパネルを置くための原点（左下）を返す。
    public static func centered(panelSize: CGSize, visibleFrame: CGRect) -> CGPoint {
        CGPoint(
            x: visibleFrame.midX - panelSize.width / 2,
            y: visibleFrame.midY - panelSize.height / 2
        )
    }
}
