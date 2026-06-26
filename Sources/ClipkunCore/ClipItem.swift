import Foundation

/// 履歴1件の種別。
public enum ClipItemKind: String, Codable, Equatable {
    /// プレーンテキスト。
    case text
    /// ファイル/フォルダの URL 群（Finder などからのコピー）。
    case fileURLs
    /// 画像。
    case image
}

/// 履歴1件のメタデータ。
///
/// データの実体（画像 PNG・長文テキスト・ファイルパス群）は App 側が
/// `blobs/` 配下にファイルとして保存し、ここでは相対ファイル名で参照する。
/// 純粋ロジック（重複排除・並べ替え・期限判定）はこのメタデータだけで完結させ、
/// `ClipkunCore` を AppKit/ファイル I/O から独立させる。
public struct ClipItem: Codable, Equatable, Identifiable {
    public let id: UUID
    public var kind: ClipItemKind
    /// 作成時刻。同一内容を再コピーして先頭へ移動したときは「最近使った時刻」に更新する。
    public var createdAt: Date
    /// 重複排除キー。内容（テキスト/画像データ/パス群）のハッシュ。
    public var contentHash: String
    /// 一覧表示用のプレビュー文字列（テキスト先頭やファイル名）。
    public var preview: String
    /// `blobs/` 配下の実体ファイル名（短いテキストは内包し nil）。
    public var blobFileName: String?
    /// `thumbnails/` 配下のサムネ画像ファイル名（画像のみ）。
    public var thumbnailFileName: String?
    /// 実体のおおよそのバイト数（ディスク使用量の目安）。
    public var byteSize: Int

    public init(
        id: UUID = UUID(),
        kind: ClipItemKind,
        createdAt: Date,
        contentHash: String,
        preview: String,
        blobFileName: String? = nil,
        thumbnailFileName: String? = nil,
        byteSize: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.contentHash = contentHash
        self.preview = preview
        self.blobFileName = blobFileName
        self.thumbnailFileName = thumbnailFileName
        self.byteSize = byteSize
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.kind = try c.decode(ClipItemKind.self, forKey: .kind)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.contentHash = try c.decode(String.self, forKey: .contentHash)
        self.preview = try c.decodeIfPresent(String.self, forKey: .preview) ?? ""
        self.blobFileName = try c.decodeIfPresent(String.self, forKey: .blobFileName)
        self.thumbnailFileName = try c.decodeIfPresent(String.self, forKey: .thumbnailFileName)
        self.byteSize = try c.decodeIfPresent(Int.self, forKey: .byteSize) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, createdAt, contentHash, preview, blobFileName, thumbnailFileName, byteSize
    }
}
