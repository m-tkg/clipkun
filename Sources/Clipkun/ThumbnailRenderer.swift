import AppKit

/// 画像のサムネイルを生成するヘルパー。
enum ThumbnailRenderer {
    /// `image` を短辺が `side` になるよう（アスペクト比維持で）縮小し、PNG データを返す。
    /// 元画像が小さい場合は拡大せず、そのままのサイズで PNG 化する。
    static func thumbnailPNG(from image: NSImage, side: CGFloat) -> Data? {
        let source = image.representations.first.map {
            CGSize(width: $0.pixelsWide, height: $0.pixelsHigh)
        } ?? image.size
        guard source.width > 0, source.height > 0 else { return nil }

        let shorter = min(source.width, source.height)
        let scale = shorter > side ? side / shorter : 1
        let target = CGSize(width: source.width * scale, height: source.height * scale)

        let thumb = NSImage(size: target)
        thumb.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: target),
            from: NSRect(origin: .zero, size: source),
            operation: .copy,
            fraction: 1.0
        )
        thumb.unlockFocus()

        guard let tiff = thumb.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
