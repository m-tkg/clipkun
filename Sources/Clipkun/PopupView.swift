import SwiftUI
import AppKit
import ClipkunCore

/// ポップアップの表示状態。選択位置はキー操作（PopupPanelController）からも更新される。
@MainActor
final class PopupViewModel: ObservableObject {
    @Published var items: [ClipItem] = []
    @Published var selectedIndex: Int = 0
    /// 検索フォームの入力文字列。変化に応じて `filteredItems` が絞り込まれる。
    @Published var searchText: String = ""
    /// 背景の不透明度（0=透明〜1=不透明）。
    @Published var backgroundOpacity: Double = 0.9

    /// `searchText` で絞り込んだ表示用の一覧。選択/確定/削除/ナビはこれを基準にする。
    var filteredItems: [ClipItem] { filterClips(items, query: searchText) }

    /// サムネ画像の取得（HistoryStore に委譲）。
    var thumbnailProvider: (ClipItem) -> NSImage? = { _ in nil }
    /// 行の選択確定（クリック / Enter）。
    var onConfirm: (ClipItem) -> Void = { _ in }
    /// 行の個別削除（ゴミ箱）。
    var onDelete: (ClipItem) -> Void = { _ in }
    /// 画像行の OCR（画像内テキストをコピー）。
    var onOCR: (ClipItem) -> Void = { _ in }
    /// 全履歴削除（一覧の右クリックメニュー）。
    var onClearAll: () -> Void = {}
}

/// 履歴一覧。各行はサムネ/アイコン＋プレビュー＋右端ゴミ箱。
/// 選択行をハイライトし、クリックで確定、ゴミ箱で個別削除する。
struct PopupView: View {
    @ObservedObject var viewModel: PopupViewModel

    var body: some View {
        VStack(spacing: 0) {
            // 検索フィールド（AppKit の NSTextField）はこの透明スペースの上に
            // コントローラが別レイヤーで重ねる。SwiftUI ツリー内に AppKit を埋め込むと
            // この `.nonactivatingPanel` ではリアクティブ再描画が止まるため分離している。
            Color.clear.frame(height: PopupMetrics.searchFieldHeight)
            Divider()
            content
        }
        .frame(width: PopupMetrics.width)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
                .opacity(viewModel.backgroundOpacity)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var content: some View {
        let items = viewModel.filteredItems
        Group {
            if items.isEmpty {
                emptyState
            } else {
                list(items)
            }
        }
        // 一覧を右クリック → 全履歴削除（検索フォームはネイティブの編集メニューを保つため対象外）。
        .contextMenu {
            Button(L.string("popup.clear_all"), role: .destructive) { viewModel.onClearAll() }
        }
    }

    private var emptyState: some View {
        // 履歴ゼロなら「履歴がありません」、検索ヒットゼロなら「該当なし」。
        Text(viewModel.items.isEmpty ? L.string("popup.empty") : L.string("popup.no_results"))
            .font(.callout)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: PopupMetrics.listHeight(for: 0))
    }

    private func list(_ items: [ClipItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        PopupRow(
                            number: recencyNumber(of: item),
                            item: item,
                            isSelected: index == viewModel.selectedIndex,
                            thumbnail: viewModel.thumbnailProvider(item),
                            onConfirm: { viewModel.onConfirm(item) },
                            onDelete: { viewModel.onDelete(item) },
                            onOCR: { viewModel.onOCR(item) }
                        )
                        .id(index)
                    }
                }
                .padding(6)
            }
            // この View は選択/検索のたびに作り直されるため、表示直後に選択行が見えるようスクロールする。
            .onAppear { proxy.scrollTo(viewModel.selectedIndex, anchor: .center) }
        }
        .frame(height: PopupMetrics.listHeight(for: items.count))
    }

    /// 行番号は「最新＝1」の意味を保つため、全履歴での位置で表示する（フィルタ中も新しさが分かる）。
    private func recencyNumber(of item: ClipItem) -> Int {
        (viewModel.items.firstIndex(of: item) ?? 0) + 1
    }
}

/// 一覧の1行。
private struct PopupRow: View {
    let number: Int
    let item: ClipItem
    let isSelected: Bool
    let thumbnail: NSImage?
    let onConfirm: () -> Void
    let onDelete: () -> Void
    let onOCR: () -> Void

    @State private var isHoveringTrash = false
    @State private var isHoveringOCR = false

    var body: some View {
        HStack(spacing: 8) {
            // 履歴の番号（最新が 1）。
            Text("\(number)")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundColor(.secondary)
                .frame(width: 22, alignment: .trailing)
            icon
                .frame(width: 32, height: 32)
            // 画像行のみ: 画像内テキストを OCR してコピーするボタン（解像度表示の左）。
            if item.kind == .image {
                Button(action: onOCR) {
                    Image(systemName: "text.viewfinder")
                        .foregroundColor(isHoveringOCR ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .onHover { isHoveringOCR = $0 }
                .help(L.string("popup.ocr"))
            }
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
    /// 最上部の検索フォームの高さ。
    static let searchFieldHeight: CGFloat = 36

    /// 一覧部分の高さ（0件でも空状態の最小高さを確保する）。
    static func listHeight(for count: Int) -> CGFloat {
        let rows = min(max(count, 1), maxVisibleRows)
        return CGFloat(rows) * rowHeight + verticalPadding
    }

    /// パネル全体の高さ（検索フォーム＋区切り線＋一覧）。
    static func totalHeight(for count: Int) -> CGFloat {
        searchFieldHeight + 1 + listHeight(for: count)
    }
}
