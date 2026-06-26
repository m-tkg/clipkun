import AppKit
import CryptoKit
import UniformTypeIdentifiers
import ClipkunCore

/// `NSPasteboard` から取り込んだ1件分の生データ。
///
/// 重複排除キー（`contentHash`）・一覧用プレビュー・ディスクへ保存する blob/サムネを
/// まとめて持ち、`HistoryStore` がこれを使って `ClipItem`（Core のメタデータ）と
/// 実体ファイルを生成する。AppKit に触れるのはここまでで、Core 側へは渡さない。
struct CapturedContent {
    /// 短いテキストは blob に逃がさず preview に内包する（このバイト長まで）。
    static let inlineTextLimit = 256
    /// サムネイルの短辺サイズ（ポイント）。
    static let thumbnailSide: CGFloat = 56

    let kind: ClipItemKind
    let contentHash: String
    let preview: String
    /// `blobs/` に保存する実体（短いテキストは nil）。
    let blobData: Data?
    /// blob ファイルの拡張子（"txt" / "png" / "json"）。
    let blobExtension: String?
    /// 画像のサムネ PNG（画像以外は nil）。
    let thumbnailPNG: Data?
    let byteSize: Int

    // MARK: - Pasteboard からの生成

    /// 現在のクリップボード内容を取り込む。対応する内容が無ければ nil。
    /// 種別の優先順位は ①ファイルURL ②画像 ③テキスト（ファイルコピーは文字列表現も併存するため URL を先に見る）。
    static func from(pasteboard: NSPasteboard) -> CapturedContent? {
        if let urls = fileURLs(from: pasteboard) {
            return fromFileURLs(urls)
        }
        if let image = imageData(from: pasteboard), let content = fromImage(image) {
            return content
        }
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return fromText(text)
        }
        return nil
    }

    private static func fileURLs(from pasteboard: NSPasteboard) -> [URL]? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL],
              !urls.isEmpty else {
            return nil
        }
        return urls
    }

    private static func imageData(from pasteboard: NSPasteboard) -> NSImage? {
        // public.image に準拠するフレーバー（png/tiff/jpeg/gif/bmp/heic 等）があるときだけ
        // 画像とみなす。特定型に限定すると、別形式しか載せないアプリの画像を取りこぼすため
        // UTType.image で広く判定する（テキストのみのときは false なので誤検出しない）。
        guard pasteboard.canReadItem(withDataConformingToTypes: [UTType.image.identifier]) else {
            return nil
        }
        return NSImage(pasteboard: pasteboard)
    }

    // MARK: - 種別ごとの構築

    private static func fromText(_ text: String) -> CapturedContent {
        let data = Data(text.utf8)
        let hash = sha256Hex(data)
        if text.utf8.count <= inlineTextLimit {
            return CapturedContent(
                kind: .text, contentHash: hash, preview: text,
                blobData: nil, blobExtension: nil, thumbnailPNG: nil, byteSize: data.count
            )
        }
        let preview = String(text.prefix(inlineTextLimit))
        return CapturedContent(
            kind: .text, contentHash: hash, preview: preview,
            blobData: data, blobExtension: "txt", thumbnailPNG: nil, byteSize: data.count
        )
    }

    private static func fromFileURLs(_ urls: [URL]) -> CapturedContent {
        let paths = urls.map(\.path)
        let joined = paths.joined(separator: "\n")
        let hash = sha256Hex(Data(joined.utf8))
        let names = urls.map { $0.lastPathComponent }
        let preview = names.count == 1 ? names[0] : names.joined(separator: ", ")
        let json = (try? JSONEncoder().encode(paths)) ?? Data()
        return CapturedContent(
            kind: .fileURLs, contentHash: hash, preview: preview,
            blobData: json, blobExtension: "json", thumbnailPNG: nil, byteSize: json.count
        )
    }

    private static func fromImage(_ image: NSImage) -> CapturedContent? {
        // PNG 化できない画像（PDF ベース等）は保存も書き戻しもできないため取り込まない
        // （壊れた履歴項目を作らない）。
        guard let png = pngData(from: image), !png.isEmpty else { return nil }
        let hash = sha256Hex(png)
        let pixelSize = pixelSize(of: image)
        let preview = "\(Int(pixelSize.width))×\(Int(pixelSize.height))"
        let thumb = ThumbnailRenderer.thumbnailPNG(from: image, side: thumbnailSide)
        return CapturedContent(
            kind: .image, contentHash: hash, preview: preview,
            blobData: png, blobExtension: "png", thumbnailPNG: thumb, byteSize: png.count
        )
    }

    // MARK: - ヘルパー

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func pixelSize(of image: NSImage) -> CGSize {
        if let rep = image.representations.first {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return image.size
    }
}
