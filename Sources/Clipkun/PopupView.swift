import SwiftUI
import AppKit
import ClipkunCore

/// ポップアップの表示状態。選択位置はキー操作（PopupPanelController）からも更新される。
@MainActor
final class PopupViewModel: ObservableObject {
    @Published var items: [ClipItem] = []
    @Published var selectedIndex: Int = 0
    /// キーボード操作時のみ増えるカウンタ。これが変化したときだけ選択行へスクロールする
    /// （マウスホバーでの選択変更ではスクロールさせない）。
    @Published var keyboardScrollTick: Int = 0

    /// キーボード（↑↓）で選択を移動する。ホバーと違い、選択行までスクロールする。
    func selectViaKeyboard(_ index: Int) {
        selectedIndex = index
        keyboardScrollTick &+= 1
    }

    /// サムネ画像の取得（HistoryStore に委譲）。
    var thumbnailProvider: (ClipItem) -> NSImage? = { _ in nil }
    /// 行の選択確定（クリック / Enter）。
    var onConfirm: (ClipItem) -> Void = { _ in }
    /// 行の個別削除（ゴミ箱）。
    var onDelete: (ClipItem) -> Void = { _ in }
}

/// 履歴一覧。各行はサムネ/アイコン＋プレビュー＋右端ゴミ箱。
/// 選択行をハイライトし、クリックで確定、ゴミ箱で個別削除する。
struct PopupView: View {
    @ObservedObject var viewModel: PopupViewModel

    var body: some View {
        Group {
            if viewModel.items.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .frame(width: PopupMetrics.width)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private var emptyState: some View {
        Text(L.string("popup.empty"))
            .font(.callout)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                        PopupRow(
                            item: item,
                            isSelected: index == viewModel.selectedIndex,
                            thumbnail: viewModel.thumbnailProvider(item),
                            onConfirm: { viewModel.onConfirm(item) },
                            onDelete: { viewModel.onDelete(item) }
                        )
                        .id(index)
                        .onHover { hovering in
                            if hovering { viewModel.selectedIndex = index }
                        }
                    }
                }
                .padding(6)
            }
            // キーボード操作時のみスクロールする（マウスホバーでは勝手にスクロールしない）。
            .onChange(of: viewModel.keyboardScrollTick) { _ in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(viewModel.selectedIndex, anchor: .center)
                }
            }
        }
        .frame(height: PopupMetrics.height(for: viewModel.items.count))
    }
}

/// 一覧の1行。
private struct PopupRow: View {
    let item: ClipItem
    let isSelected: Bool
    let thumbnail: NSImage?
    let onConfirm: () -> Void
    let onDelete: () -> Void

    @State private var isHoveringTrash = false

    var body: some View {
        HStack(spacing: 8) {
            icon
                .frame(width: 32, height: 32)
            Text(item.preview)
                .lineLimit(2)
                .truncationMode(.tail)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(isHoveringTrash ? .red : .secondary)
            }
            .buttonStyle(.plain)
            .onHover { isHoveringTrash = $0 }
            .help(L.string("popup.delete"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.25) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onConfirm)
    }

    @ViewBuilder
    private var icon: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .cornerRadius(3)
        } else {
            Image(systemName: symbolName)
                .font(.system(size: 18))
                .foregroundColor(.secondary)
        }
    }

    private var symbolName: String {
        switch item.kind {
        case .text: return "doc.plaintext"
        case .fileURLs: return "doc.on.doc"
        case .image: return "photo"
        }
    }
}

/// ポップアップの寸法。PopupPanelController がパネルサイズ計算にも使う。
enum PopupMetrics {
    static let width: CGFloat = 360
    static let rowHeight: CGFloat = 46
    static let maxVisibleRows = 8
    static let verticalPadding: CGFloat = 12

    static func height(for count: Int) -> CGFloat {
        let rows = min(max(count, 1), maxVisibleRows)
        return CGFloat(rows) * rowHeight + verticalPadding
    }
}
