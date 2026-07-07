import AppKit

/// 進行中の処理を知らせる小さな HUD（スピナー＋テキスト）。
/// フォーカスを奪わず、クリックも透過する。画面下部中央に表示する。
@MainActor
final class HUDPanelController {
    private var panel: NSPanel?
    private var spinner: NSProgressIndicator?

    func show(text: String) {
        hide()

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor

        let stack = NSStackView(views: [spinner, label])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 16)

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 10
        effect.layer?.masksToBounds = true
        effect.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
        ])

        let size = stack.fittingSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = effect

        if let visible = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.minY + 100))
        }
        panel.orderFrontRegardless()
        self.panel = panel
        self.spinner = spinner
    }

    func hide() {
        // スピナーのアニメーションが生きているとパネルが再表示されることがあるため、先に止める。
        spinner?.stopAnimation(nil)
        spinner = nil
        panel?.close()
        panel = nil
    }
}
