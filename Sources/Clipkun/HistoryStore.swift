import AppKit
import OSLog
import ClipkunCore

private let log = Logger(subsystem: "com.mtkg.clipkun", category: "history")

/// クリップボード履歴の保持と永続化を担う。
///
/// 純粋ロジック（`ClipboardHistory`/`RetentionPolicy`）に並べ替え・重複排除・期限判定を任せ、
/// ここでは実体（画像 PNG・長文テキスト・ファイルパス群）の blob/サムネ I/O と
/// `index.json` の読み書き、期限切れ・件数超過の実体ファイル削除を行う。
@MainActor
final class HistoryStore {
    /// 履歴が変化したときに呼ばれる（UI 更新用）。
    var onChange: (() -> Void)?

    private(set) var history: ClipboardHistory

    /// 保持期間・件数上限の参照元（AppDelegate が設定変更時に更新する）。
    var settings: Settings

    private let directory: URL
    private let blobsDir: URL
    private let thumbsDir: URL
    private let indexURL: URL
    private let fm = FileManager.default

    init(settings: Settings, directory: URL = HistoryStore.defaultDirectory()) {
        self.settings = settings
        self.directory = directory
        self.blobsDir = directory.appendingPathComponent("blobs", isDirectory: true)
        self.thumbsDir = directory.appendingPathComponent("thumbnails", isDirectory: true)
        self.indexURL = directory.appendingPathComponent("index.json")
        self.history = ClipboardHistory()

        createDirectories()
        loadIndex()
        pruneExpired(now: Date())
        reconcileOrphans()
    }

    /// 既定の保存先（`~/Library/Application Support/Clipkun/`）。
    nonisolated static func defaultDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Clipkun", isDirectory: true)
    }

    // MARK: - 取り込み

    /// 取り込んだ内容を履歴へ追加する。
    /// 同一内容（同 `contentHash`）が既にあれば実体を再保存せず先頭へ移動する。
    func capture(_ content: CapturedContent) {
        let now = Date()

        // 既存の重複は実体を書かずに先頭へ移動するだけ。
        if let existing = history.items.first(where: { $0.contentHash == content.contentHash }) {
            history.moveToFront(id: existing.id, now: now)
            applyCapAndSave()
            return
        }

        // 新規: blob/サムネを保存してから ClipItem を作る。
        let id = UUID()
        var blobFileName: String?
        var thumbnailFileName: String?

        if let blob = content.blobData, let ext = content.blobExtension {
            let name = "\(id.uuidString).\(ext)"
            do {
                try blob.write(to: blobsDir.appendingPathComponent(name), options: .atomic)
                blobFileName = name
            } catch {
                log.error("blob write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        if let thumb = content.thumbnailPNG {
            let name = "\(id.uuidString).png"
            do {
                try thumb.write(to: thumbsDir.appendingPathComponent(name), options: .atomic)
                thumbnailFileName = name
            } catch {
                log.error("thumbnail write failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        let item = ClipItem(
            id: id,
            kind: content.kind,
            createdAt: now,
            contentHash: content.contentHash,
            preview: content.preview,
            blobFileName: blobFileName,
            thumbnailFileName: thumbnailFileName,
            byteSize: content.byteSize
        )
        history.insert(item)
        applyCapAndSave()
    }

    // MARK: - 削除・移動

    /// 指定 id を削除し、実体ファイルも後始末する。
    func remove(id: UUID) {
        if let removed = history.remove(id: id) {
            deleteFiles(for: removed)
            saveIndex()
            onChange?()
        }
    }

    /// すべて削除し、実体ファイルも後始末する。
    func clear() {
        let removed = history.clear()
        removed.forEach(deleteFiles(for:))
        saveIndex()
        onChange?()
    }

    /// 選択された項目を「最近使った」位置（先頭）へ移動する。
    func markUsed(id: UUID) {
        if history.moveToFront(id: id, now: Date()) {
            saveIndex()
            onChange?()
        }
    }

    /// 期限切れの項目を破棄する。
    func pruneExpired(now: Date) {
        let result = RetentionPolicy.prune(history.items, now: now, period: settings.retention)
        guard !result.expired.isEmpty else { return }
        history = ClipboardHistory(items: result.kept)
        result.expired.forEach(deleteFiles(for:))
        saveIndex()
        onChange?()
    }

    // MARK: - 実体データの解決（書き戻し・表示用）

    /// テキスト項目の本文を返す（短文は preview、長文は blob から）。
    func fullText(for item: ClipItem) -> String? {
        guard item.kind == .text else { return nil }
        if let name = item.blobFileName,
           let data = try? Data(contentsOf: blobsDir.appendingPathComponent(name)) {
            return String(decoding: data, as: UTF8.self)
        }
        return item.preview
    }

    /// 画像項目の PNG データを返す。
    func imageData(for item: ClipItem) -> Data? {
        guard item.kind == .image, let name = item.blobFileName else { return nil }
        return try? Data(contentsOf: blobsDir.appendingPathComponent(name))
    }

    /// ファイル項目の URL 群を返す。
    func fileURLs(for item: ClipItem) -> [URL]? {
        guard item.kind == .fileURLs, let name = item.blobFileName,
              let data = try? Data(contentsOf: blobsDir.appendingPathComponent(name)),
              let paths = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        return paths.map { URL(fileURLWithPath: $0) }
    }

    /// 一覧表示用のサムネ画像を返す。
    func thumbnail(for item: ClipItem) -> NSImage? {
        guard let name = item.thumbnailFileName else { return nil }
        return NSImage(contentsOf: thumbsDir.appendingPathComponent(name))
    }

    // MARK: - 内部処理

    private func applyCapAndSave() {
        let evicted = history.cap(max: settings.maxItemCount)
        evicted.forEach(deleteFiles(for:))
        saveIndex()
        onChange?()
    }

    private func createDirectories() {
        for dir in [directory, blobsDir, thumbsDir] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let items = try? JSONDecoder().decode([ClipItem].self, from: data) else {
            return
        }
        history = ClipboardHistory(items: items)
    }

    private func saveIndex() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(history.items)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            log.error("index save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func deleteFiles(for item: ClipItem) {
        if let name = item.blobFileName {
            try? fm.removeItem(at: blobsDir.appendingPathComponent(name))
        }
        if let name = item.thumbnailFileName {
            try? fm.removeItem(at: thumbsDir.appendingPathComponent(name))
        }
    }

    /// index から参照されない孤児 blob/サムネを削除する（起動時の整合性回復）。
    private func reconcileOrphans() {
        let referencedBlobs = Set(history.items.compactMap(\.blobFileName))
        let referencedThumbs = Set(history.items.compactMap(\.thumbnailFileName))
        removeUnreferenced(in: blobsDir, keeping: referencedBlobs)
        removeUnreferenced(in: thumbsDir, keeping: referencedThumbs)
    }

    private func removeUnreferenced(in dir: URL, keeping: Set<String>) {
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return
        }
        for url in entries where !keeping.contains(url.lastPathComponent) {
            try? fm.removeItem(at: url)
        }
    }
}
